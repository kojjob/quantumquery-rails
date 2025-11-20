# frozen_string_literal: true

module CodeValidation
  # Validates SQL queries for syntax and security
  class SqlValidator < BaseValidator
    FORBIDDEN_OPERATIONS = %w[
      DROP
      TRUNCATE
      ALTER
      CREATE
      GRANT
      REVOKE
      EXECUTE
      EXEC
      xp_
      sp_
    ].freeze

    DANGEROUS_OPERATIONS = %w[
      UPDATE
      DELETE
      INSERT
    ].freeze

    DDL_OPERATIONS = [
      /\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|PROCEDURE|FUNCTION)/i,
      /\bTRUNCATE\s+TABLE/i,
      /\bALTER\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)/i,
      /\bCREATE\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|PROCEDURE|FUNCTION)/i
    ].freeze

    PERMISSION_OPERATIONS = [
      /\bGRANT\s+/i,
      /\bREVOKE\s+/i,
      /\bDENY\s+/i
    ].freeze

    STORED_PROCEDURE_EXEC = [
      /\bEXEC(?:UTE)?\s+/i,
      /\bCALL\s+/i,
      /\bxp_\w+/i,
      /\bsp_\w+/i
    ].freeze

    SQL_INJECTION_PATTERNS = [
      /['"]\s*OR\s+['"]?\d+['"]?\s*=\s*['"]?\d+/i,      # OR 1=1
      /['"]\s*OR\s+['"]?1['"]?\s*=\s*['"]?1/i,
      /;\s*DROP\s+TABLE/i,                               # ; DROP TABLE
      /;\s*DELETE\s+FROM/i,                              # ; DELETE FROM
      /;\s*UPDATE\s+/i,                                  # ; UPDATE
      /UNION\s+(?:ALL\s+)?SELECT/i,                      # UNION SELECT
      /--\s*$/m,                                         # SQL comment at end
      /#\s*$/m,                                          # MySQL comment
      /\/\*.*\*\//m,                                     # Multi-line comment
      /\bxp_cmdshell\b/i,                                # xp_cmdshell
      /\bINTO\s+OUTFILE\b/i,                             # INTO OUTFILE
      /\bLOAD_FILE\s*\(/i,                               # LOAD_FILE
      /\bINTO\s+DUMPFILE\b/i                             # INTO DUMPFILE
    ].freeze

    DANGEROUS_FUNCTIONS = [
      /\bxp_cmdshell\b/i,
      /\bxp_regread\b/i,
      /\bxp_regwrite\b/i,
      /\bLOAD_FILE\s*\(/i,
      /\bINTO\s+OUTFILE\b/i,
      /\bINTO\s+DUMPFILE\b/i,
      /\bSYSTEM\s*\(/i,
      /\b\\\!\s*/i                                       # MySQL system command
    ].freeze

    protected

    def validate_syntax
      check_basic_sql_syntax
      check_query_structure
    end

    def check_basic_sql_syntax
      # Normalize whitespace for checking
      normalized = code.gsub(/\s+/, " ").strip
      
      # Check for empty or whitespace-only queries
      if normalized.empty?
        add_error("SQL query is empty")
        return
      end

      # Check for balanced parentheses
      check_balanced_parentheses

      # Check for balanced quotes
      check_balanced_quotes

      # Check for valid SQL keywords at start
      check_valid_start_keyword(normalized)
    end

    def check_balanced_parentheses
      count = 0
      code.each_char do |char|
        count += 1 if char == "("
        count -= 1 if char == ")"
        
        if count < 0
          add_error("Unmatched closing parenthesis")
          return
        end
      end

      if count > 0
        add_error("Unmatched opening parenthesis (#{count} unclosed)")
      end
    end

    def check_balanced_quotes
      # Track quotes outside of comments
      in_single = false
      in_double = false
      prev_char = nil

      code.each_char do |char|
        if char == "'" && prev_char != "\\"
          in_single = !in_single
        elsif char == '"' && prev_char != "\\"
          in_double = !in_double
        end
        prev_char = char
      end

      add_error("Unmatched single quote") if in_single
      add_error("Unmatched double quote") if in_double
    end

    def check_valid_start_keyword(normalized)
      valid_starts = %w[SELECT INSERT UPDATE DELETE WITH SHOW DESCRIBE EXPLAIN]
      
      # Extract first keyword
      first_keyword = normalized.split(/\s+/).first&.upcase
      
      unless valid_starts.include?(first_keyword)
        if FORBIDDEN_OPERATIONS.include?(first_keyword)
          # This will be caught by security validation
          return
        else
          add_warning("Query starts with unexpected keyword: #{first_keyword}")
        end
      end
    end

    def check_query_structure
      # Check for basic SELECT structure
      if code.match?(/\bSELECT\b/i)
        check_select_structure
      end

      # Check for UPDATE/DELETE without WHERE
      if code.match?(/\b(UPDATE|DELETE)\b/i)
        check_modification_structure
      end
    end

    def check_select_structure
      # Warn if SELECT * is used (performance concern)
      if code.match?(/\bSELECT\s+\*/i) && !code.match?(/\bLIMIT\b/i)
        add_warning("SELECT * without LIMIT may return large result sets")
      end

      # Check for FROM clause (unless it's a constant select)
      unless code.match?(/\bFROM\b/i) || code.match?(/\bSELECT\s+['"\d]/i)
        add_warning("SELECT query missing FROM clause")
      end
    end

    def check_modification_structure
      # Check for UPDATE without WHERE
      if code.match?(/\bUPDATE\s+\w+\s+SET\b/i) && !code.match?(/\bWHERE\b/i)
        add_violation(
          :dangerous_operation,
          "UPDATE statement without WHERE clause (affects all rows)",
          severity: :critical
        )
      end

      # Check for DELETE without WHERE
      if code.match?(/\bDELETE\s+FROM\s+\w+(?!\s+WHERE)\b/i)
        add_violation(
          :dangerous_operation,
          "DELETE statement without WHERE clause (affects all rows)",
          severity: :critical
        )
      end
    end

    def validate_security
      check_forbidden_operations
      check_dangerous_operations
      check_sql_injection
      check_dangerous_functions
      check_permission_operations
      check_stored_procedures
      check_stacked_queries
      check_information_disclosure
    end

    def check_forbidden_operations
      # Check DDL operations
      check_for_patterns(DDL_OPERATIONS, :forbidden_function, "DDL operation detected")

      # Check individual forbidden keywords
      FORBIDDEN_OPERATIONS.each do |op|
        if code.match?(/\b#{op}\b/i)
          add_violation(
            :forbidden_function,
            "Forbidden SQL operation '#{op}' detected",
            operation: op
          )
        end
      end
    end

    def check_dangerous_operations
      DANGEROUS_OPERATIONS.each do |op|
        if code.match?(/\b#{op}\b/i)
          # Check if it has WHERE clause
          op_pattern = /\b#{op}\b.*?\bWHERE\b/im
          unless code.match?(op_pattern)
            add_violation(
              :dangerous_operation,
              "#{op} operation without WHERE clause",
              operation: op,
              severity: :critical
            )
          end
        end
      end
    end

    def check_sql_injection
      check_for_patterns(
        SQL_INJECTION_PATTERNS,
        :code_injection,
        "Potential SQL injection pattern detected"
      )

      # Check for concatenation in queries (potential injection)
      if code.match?(/\|\||CONCAT\s*\(/i)
        add_warning("String concatenation detected - ensure proper parameterization")
      end
    end

    def check_dangerous_functions
      check_for_patterns(
        DANGEROUS_FUNCTIONS,
        :system_command,
        "Dangerous SQL function detected"
      )
    end

    def check_permission_operations
      check_for_patterns(
        PERMISSION_OPERATIONS,
        :forbidden_function,
        "Permission modification operation detected"
      )
    end

    def check_stored_procedures
      check_for_patterns(
        STORED_PROCEDURE_EXEC,
        :code_injection,
        "Stored procedure execution detected"
      )
    end

    def check_stacked_queries
      # Check for multiple statements (stacked queries)
      statements = code.split(";").map(&:strip).reject(&:empty?)
      
      if statements.length > 1
        add_violation(
          :code_injection,
          "Multiple SQL statements detected (stacked queries)",
          count: statements.length
        )
      end
    end

    def check_information_disclosure
      # Check for queries that might expose sensitive information
      sensitive_tables = %w[
        users
        passwords
        credentials
        tokens
        sessions
        authentication
        authorization
      ]

      sensitive_tables.each do |table|
        if code.match?(/\bFROM\s+#{table}\b/i) || code.match?(/\bJOIN\s+#{table}\b/i)
          add_warning("Query accesses potentially sensitive table '#{table}'")
        end
      end

      # Check for password/credential columns in SELECT
      if code.match?(/\bSELECT\b.*\b(password|passwd|pwd|secret|token|key|credential)\b/i)
        add_warning("Query selects potentially sensitive columns")
      end
    end
  end
end

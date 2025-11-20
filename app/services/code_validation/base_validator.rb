# frozen_string_literal: true

module CodeValidation
  # Base class for code validators with security checks and syntax validation
  # Subclasses implement language-specific validation rules
  class BaseValidator
    # Validation result structure
    ValidationResult = Struct.new(
      :valid,
      :errors,
      :warnings,
      :violations,
      :metadata,
      keyword_init: true
    ) do
      def valid?
        valid
      end

      def has_errors?
        errors.any?
      end

      def has_warnings?
        warnings.any?
      end

      def has_violations?
        violations.any?
      end

      def safe?
        valid? && !has_violations?
      end
    end

    # Security violation types
    VIOLATION_TYPES = {
      forbidden_import: "Forbidden import detected",
      forbidden_function: "Forbidden function call detected",
      file_access: "File system access detected",
      network_access: "Network access detected",
      system_command: "System command execution detected",
      code_injection: "Potential code injection detected",
      resource_limit: "Resource limit violation",
      dangerous_operation: "Dangerous operation detected"
    }.freeze

    attr_reader :code, :options

    def initialize(code, options = {})
      @code = code
      @options = options
      @errors = []
      @warnings = []
      @violations = []
      @metadata = {}
    end

    # Main validation method - override in subclasses
    def validate
      reset_state
      
      # Basic validations
      validate_not_empty
      validate_syntax if @errors.empty?
      validate_security if @errors.empty?
      validate_resource_limits if @errors.empty?
      
      build_result
    end

    protected

    def reset_state
      @errors = []
      @warnings = []
      @violations = []
      @metadata = {}
    end

    def validate_not_empty
      if code.nil? || code.strip.empty?
        @errors << "Code cannot be empty"
      end
    end

    # Override in subclasses
    def validate_syntax
      raise NotImplementedError, "#{self.class} must implement validate_syntax"
    end

    # Override in subclasses for language-specific security checks
    def validate_security
      raise NotImplementedError, "#{self.class} must implement validate_security"
    end

    def validate_resource_limits
      # Check code length
      max_length = options[:max_code_length] || 10_000
      if code.length > max_length
        add_violation(:resource_limit, "Code exceeds maximum length of #{max_length} characters")
      end

      # Check line count
      line_count = code.lines.count
      max_lines = options[:max_lines] || 500
      if line_count > max_lines
        add_violation(:resource_limit, "Code exceeds maximum of #{max_lines} lines")
      end

      @metadata[:line_count] = line_count
      @metadata[:char_count] = code.length
    end

    def add_error(message)
      @errors << message
    end

    def add_warning(message)
      @warnings << message
    end

    def add_violation(type, message, details = {})
      @violations << {
        type: type,
        message: message,
        description: VIOLATION_TYPES[type],
        details: details,
        severity: violation_severity(type)
      }
    end

    def violation_severity(type)
      case type
      when :system_command, :code_injection, :file_access
        :critical
      when :forbidden_import, :forbidden_function, :network_access
        :high
      when :dangerous_operation
        :medium
      when :resource_limit
        :low
      else
        :info
      end
    end

    def build_result
      ValidationResult.new(
        valid: @errors.empty?,
        errors: @errors,
        warnings: @warnings,
        violations: @violations,
        metadata: @metadata
      )
    end

    # Common security pattern checks
    def check_for_patterns(patterns, violation_type, message)
      patterns.each do |pattern|
        if code.match?(pattern)
          match = code.match(pattern)
          add_violation(
            violation_type,
            message,
            pattern: pattern.source,
            matched: match[0]
          )
        end
      end
    end

    # Check for forbidden keywords/functions
    def check_forbidden_keywords(keywords, violation_type)
      keywords.each do |keyword|
        # Use word boundaries to avoid false positives
        pattern = /\b#{Regexp.escape(keyword)}\b/
        if code.match?(pattern)
          add_violation(
            violation_type,
            "Forbidden keyword '#{keyword}' detected",
            keyword: keyword
          )
        end
      end
    end

    # Extract identifiers from code (override for language-specific parsing)
    def extract_identifiers
      code.scan(/\b[a-zA-Z_][a-zA-Z0-9_]*\b/)
    end

    # Check if code contains SQL injection patterns
    def check_sql_injection_patterns
      sql_injection_patterns = [
        /['"]\s*OR\s+['"]?\d+['"]?\s*=\s*['"]?\d+/i,  # OR 1=1
        /['"]\s*OR\s+['"]?1['"]?\s*=\s*['"]?1/i,
        /;\s*DROP\s+TABLE/i,                           # ; DROP TABLE
        /;\s*DELETE\s+FROM/i,                          # ; DELETE FROM
        /UNION\s+SELECT/i,                             # UNION SELECT
        /--\s*$/m,                                     # SQL comment at end
        /#\s*$/m                                       # MySQL comment
      ]

      check_for_patterns(
        sql_injection_patterns,
        :code_injection,
        "Potential SQL injection pattern detected"
      )
    end

    # Check for shell injection patterns
    def check_shell_injection_patterns
      shell_injection_patterns = [
        /[;&|`$()]/,                    # Shell metacharacters
        />\s*\/dev\/null/,              # Output redirection
        /<<\s*EOF/,                     # Here documents
        /\$\{.*\}/,                     # Variable expansion
        /`.*`/                          # Command substitution
      ]

      check_for_patterns(
        shell_injection_patterns,
        :code_injection,
        "Potential shell injection pattern detected"
      )
    end
  end
end

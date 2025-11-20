# frozen_string_literal: true

module CodeValidation
  # Validates R code for syntax and security
  class RValidator < BaseValidator
    FORBIDDEN_FUNCTIONS = %w[
      system
      system2
      shell
      shell.exec
      Sys.setenv
      Sys.unsetenv
      file.create
      file.remove
      file.copy
      file.rename
      dir.create
      unlink
      download.file
      source
      eval
      parse
      call
      do.call
      get
      assign
      rm
      save
      load
      readRDS
      saveRDS
      sink
      setwd
      getwd
    ].freeze

    FORBIDDEN_PACKAGES = %w[
      system
      httr
      RCurl
      curl
      downloader
    ].freeze

    FILE_OPERATIONS = [
      /\bfile\./,
      /\bdir\./,
      /\bunlink\s*\(/,
      /\bwrite\./,
      /\bsave\s*\(/,
      /\bload\s*\(/,
      /\breadRDS\s*\(/,
      /\bsaveRDS\s*\(/,
      /\bsink\s*\(/,
      /\bsetwd\s*\(/
    ].freeze

    SYSTEM_COMMANDS = [
      /\bsystem\s*\(/,
      /\bsystem2\s*\(/,
      /\bshell\s*\(/,
      /\bshell\.exec\s*\(/,
      /\bSys\.setenv\s*\(/
    ].freeze

    NETWORK_OPERATIONS = [
      /\bdownload\.file\s*\(/,
      /\burl\s*\(/,
      /\bhttr::/,
      /\bRCurl::/,
      /\bcurl::/
    ].freeze

    CODE_EXECUTION = [
      /\beval\s*\(/,
      /\bparse\s*\(/,
      /\bsource\s*\(/,
      /\bdo\.call\s*\(/,
      /\bcall\s*\(/
    ].freeze

    protected

    def validate_syntax
      check_basic_r_syntax
    end

    def check_basic_r_syntax
      # Check for balanced brackets
      brackets = { "(" => ")", "[" => "]", "{" => "}" }
      stack = []
      
      code.each_char.with_index do |char, idx|
        if brackets.key?(char)
          stack.push([char, idx])
        elsif brackets.value?(char)
          if stack.empty?
            add_error("Unmatched closing bracket '#{char}' at position #{idx}")
            return
          end
          open_bracket, _ = stack.pop
          if brackets[open_bracket] != char
            add_error("Mismatched brackets: '#{open_bracket}' closed with '#{char}'")
            return
          end
        end
      end

      unless stack.empty?
        unclosed = stack.map { |b, _| b }.join(", ")
        add_error("Unclosed brackets: #{unclosed}")
      end

      # Check for common R syntax patterns
      check_assignment_operators
      check_function_definitions
      check_common_errors
    end

    def check_assignment_operators
      lines = code.lines
      
      lines.each_with_index do |line, idx|
        line_num = idx + 1
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")
        
        # Check for invalid assignment
        if stripped.match?(/^\s*\d+\w*\s*(<-|=)/)
          add_error("Invalid assignment target at line #{line_num}")
        end
      end
    end

    def check_function_definitions
      # Check for function definitions without proper syntax
      func_pattern = /(\w+)\s*<-\s*function\s*\(/
      
      code.scan(func_pattern).each do |match|
        func_name = match[0]
        
        # Check if function body is properly enclosed
        func_def_pattern = /#{func_name}\s*<-\s*function\s*\([^)]*\)\s*\{/
        unless code.match?(func_def_pattern)
          add_warning("Function '#{func_name}' may be missing opening brace")
        end
      end
    end

    def check_common_errors
      lines = code.lines
      
      lines.each_with_index do |line, idx|
        line_num = idx + 1
        stripped = line.strip
        
        # Check for unmatched quotes
        single_quotes = stripped.count("'") - stripped.scan(/\\'/).length
        double_quotes = stripped.count('"') - stripped.scan(/\\"/).length
        
        if single_quotes.odd?
          add_error("Unmatched single quote at line #{line_num}")
        end
        
        if double_quotes.odd?
          add_error("Unmatched double quote at line #{line_num}")
        end
        
        # Check for <- vs = consistency
        if stripped.match?(/<-/) && stripped.match?(/\s=\s/)
          add_warning("Mixed assignment operators (<- and =) at line #{line_num}")
        end
      end
    end

    def validate_security
      check_forbidden_functions
      check_forbidden_packages
      check_file_operations
      check_system_commands
      check_network_operations
      check_code_execution
      check_dangerous_patterns
    end

    def check_forbidden_functions
      check_forbidden_keywords(FORBIDDEN_FUNCTIONS, :forbidden_function)
    end

    def check_forbidden_packages
      # Check library/require statements
      library_pattern = /(?:library|require)\s*\(\s*["']?(\w+)["']?\s*\)/
      
      code.scan(library_pattern).each do |match|
        package_name = match[0]
        if FORBIDDEN_PACKAGES.include?(package_name)
          add_violation(
            :forbidden_import,
            "Loading forbidden package '#{package_name}'",
            package: package_name
          )
        end
      end

      # Check :: syntax
      FORBIDDEN_PACKAGES.each do |pkg|
        if code.match?(/\b#{pkg}::/)
          add_violation(
            :forbidden_import,
            "Using forbidden package '#{pkg}' with :: syntax",
            package: pkg
          )
        end
      end
    end

    def check_file_operations
      check_for_patterns(FILE_OPERATIONS, :file_access, "File system operation detected")
    end

    def check_system_commands
      check_for_patterns(SYSTEM_COMMANDS, :system_command, "System command execution detected")
    end

    def check_network_operations
      check_for_patterns(NETWORK_OPERATIONS, :network_access, "Network operation detected")
    end

    def check_code_execution
      check_for_patterns(CODE_EXECUTION, :code_injection, "Dynamic code execution detected")
    end

    def check_dangerous_patterns
      # Check for infinite loops
      if code.match?(/while\s*\(\s*TRUE\s*\)/) && !code.match?(/break/)
        add_warning("Potential infinite loop detected (while TRUE without break)")
      end

      if code.match?(/repeat\s*\{/) && !code.match?(/break/)
        add_warning("Potential infinite loop detected (repeat without break)")
      end

      # Check for recursive functions without base case
      func_pattern = /(\w+)\s*<-\s*function\s*\([^)]*\)\s*\{([^}]*)\}/m
      code.scan(func_pattern).each do |match|
        func_name, func_body = match
        if func_body.include?(func_name) && !func_body.match?(/\breturn\b/)
          add_warning("Potential infinite recursion in function '#{func_name}'")
        end
      end

      # Check for large vectors/sequences
      if code.match?(/seq\s*\([^)]*,\s*\d{6,}/)
        add_violation(:resource_limit, "Large sequence detected (potential memory issue)")
      end

      if code.match?(/rep\s*\([^)]*,\s*\d{6,}/)
        add_violation(:resource_limit, "Large repetition detected (potential memory issue)")
      end

      # Check SQL injection in database operations
      check_sql_injection_patterns

      # Check for dangerous data manipulation
      if code.match?(/\brm\s*\(\s*list\s*=\s*ls\s*\(\s*\)\s*\)/)
        add_violation(:dangerous_operation, "Clearing entire workspace detected (rm(list=ls()))")
      end
    end
  end
end

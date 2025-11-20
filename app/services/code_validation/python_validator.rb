# frozen_string_literal: true

module CodeValidation
  # Validates Python code for syntax and security
  # Uses Python's ast module for syntax checking
  class PythonValidator < BaseValidator
    FORBIDDEN_IMPORTS = %w[
      os
      subprocess
      sys
      socket
      http
      urllib
      requests
      shutil
      pathlib
      pickle
      marshal
      shelve
      __import__
      eval
      exec
      compile
      open
    ].freeze

    FORBIDDEN_FUNCTIONS = %w[
      eval
      exec
      compile
      __import__
      open
      file
      input
      raw_input
      execfile
      reload
      __builtins__
    ].freeze

    DANGEROUS_ATTRIBUTES = %w[
      __code__
      __globals__
      __closure__
      __dict__
      __class__
      __bases__
      __subclasses__
      __import__
    ].freeze

    FILE_OPERATIONS = [
      /\bopen\s*\(/,
      /\bfile\s*\(/,
      /\bwith\s+open\s*\(/,
      /Path\s*\(/,
      /\.read\s*\(/,
      /\.write\s*\(/,
      /\.readlines\s*\(/,
      /\.writelines\s*\(/
    ].freeze

    NETWORK_OPERATIONS = [
      /\bsocket\./,
      /\brequests\./,
      /\burllib\./,
      /\bhttp\./,
      /\bftplib\./,
      /\bsmtplib\./,
      /\btelnetlib\./
    ].freeze

    SYSTEM_COMMANDS = [
      /\bos\.system\s*\(/,
      /\bos\.popen\s*\(/,
      /\bos\.exec/,
      /\bsubprocess\./,
      /\bcommands\./,
      /\bshell\s*=\s*True/
    ].freeze

    protected

    def validate_syntax
      # Try to parse with Python's ast module
      # We'll use a simple approach by checking for common syntax errors
      check_basic_python_syntax
    end

    def check_basic_python_syntax
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

      # Check for basic Python syntax patterns
      check_indentation
      check_common_syntax_errors
    end

    def check_indentation
      lines = code.lines
      indent_levels = []
      
      lines.each_with_index do |line, idx|
        next if line.strip.empty? || line.strip.start_with?("#")
        
        # Count leading spaces
        indent = line[/^\s*/].length
        
        # Check for tabs
        if line.start_with?("\t")
          add_error("Tab character found at line #{idx + 1}. Use spaces for indentation.")
          return
        end
        
        indent_levels << indent
      end

      # Check if indentation is consistent (multiples of same base)
      non_zero_indents = indent_levels.select { |i| i > 0 }.uniq.sort
      if non_zero_indents.any?
        base_indent = non_zero_indents.first
        inconsistent = non_zero_indents.any? { |i| i % base_indent != 0 }
        if inconsistent
          add_warning("Inconsistent indentation detected. Use consistent spacing (e.g., 4 spaces).")
        end
      end
    end

    def check_common_syntax_errors
      lines = code.lines
      
      lines.each_with_index do |line, idx|
        line_num = idx + 1
        stripped = line.strip
        
        # Check for missing colons
        if stripped.match?(/^\s*(if|elif|else|for|while|def|class|try|except|finally|with)\b/)
          unless stripped.end_with?(":")
            add_error("Missing colon at end of line #{line_num}")
          end
        end
        
        # Check for invalid assignment
        if stripped.match?(/^\s*\d+\w*\s*=/)
          add_error("Invalid assignment target at line #{line_num}")
        end
      end
    end

    def validate_security
      check_forbidden_imports
      check_forbidden_functions
      check_dangerous_attributes
      check_file_operations
      check_network_operations
      check_system_commands
      check_code_execution
      check_dangerous_patterns
    end

    def check_forbidden_imports
      # Check for forbidden imports
      import_pattern = /^(?:from\s+(\w+)|import\s+(\w+))/
      
      code.lines.each do |line|
        if match = line.match(import_pattern)
          module_name = match[1] || match[2]
          if FORBIDDEN_IMPORTS.include?(module_name)
            add_violation(
              :forbidden_import,
              "Import of forbidden module '#{module_name}'",
              module: module_name,
              line: line.strip
            )
          end
        end
      end

      # Check for dynamic imports
      if code.match?(/__import__\s*\(/)
        add_violation(:forbidden_import, "Dynamic import using __import__")
      end
    end

    def check_forbidden_functions
      check_forbidden_keywords(FORBIDDEN_FUNCTIONS, :forbidden_function)
    end

    def check_dangerous_attributes
      DANGEROUS_ATTRIBUTES.each do |attr|
        if code.include?(attr)
          add_violation(
            :dangerous_operation,
            "Access to dangerous attribute '#{attr}'",
            attribute: attr
          )
        end
      end
    end

    def check_file_operations
      check_for_patterns(FILE_OPERATIONS, :file_access, "File system operation detected")
    end

    def check_network_operations
      check_for_patterns(NETWORK_OPERATIONS, :network_access, "Network operation detected")
    end

    def check_system_commands
      check_for_patterns(SYSTEM_COMMANDS, :system_command, "System command execution detected")
    end

    def check_code_execution
      code_exec_patterns = [
        /\beval\s*\(/,
        /\bexec\s*\(/,
        /\bcompile\s*\(/,
        /\bexecfile\s*\(/
      ]

      check_for_patterns(code_exec_patterns, :code_injection, "Dynamic code execution detected")
    end

    def check_dangerous_patterns
      # Check for infinite loops (basic detection)
      if code.match?(/while\s+True\s*:/) && !code.match?(/break/)
        add_warning("Potential infinite loop detected (while True without break)")
      end

      # Check for recursive patterns without base case
      func_defs = code.scan(/def\s+(\w+)\s*\(/)
      func_defs.each do |func_name|
        func_pattern = /def\s+#{func_name[0]}\s*\([^)]*\):(.*?)(?=\ndef|\z)/m
        if match = code.match(func_pattern)
          func_body = match[1]
          if func_body.include?(func_name[0]) && !func_body.match?(/\breturn\b/)
            add_warning("Potential infinite recursion in function '#{func_name[0]}'")
          end
        end
      end

      # Check for large data structures
      if code.match?(/range\s*\(\s*\d{6,}/)
        add_violation(:resource_limit, "Large range detected (potential memory issue)")
      end

      # Check SQL injection in pandas/SQL operations
      check_sql_injection_patterns
    end
  end
end

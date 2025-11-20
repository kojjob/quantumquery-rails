# frozen_string_literal: true

require "test_helper"

class CodeValidationTest < ActiveSupport::TestCase
  # Python Validator Tests
  test "python validator accepts safe code" do
    safe_code = <<~PYTHON
      import pandas as pd
      import numpy as np
      
      df = pd.read_csv('data.csv')
      result = df.describe()
      print(result)
    PYTHON

    validator = CodeValidation::PythonValidator.new(safe_code)
    result = validator.validate

    assert result.valid?
    assert_empty result.errors
  end

  test "python validator detects forbidden imports" do
    unsafe_code = <<~PYTHON
      import os
      import subprocess
      
      os.system('rm -rf /')
    PYTHON

    validator = CodeValidation::PythonValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    violation_types = result.violations.map { |v| v[:type] }
    assert_includes violation_types, :forbidden_import
  end

  test "python validator detects system commands" do
    unsafe_code = <<~PYTHON
      import subprocess
      subprocess.run(['ls', '-la'])
    PYTHON

    validator = CodeValidation::PythonValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :system_command || v[:type] == :forbidden_import }
  end

  test "python validator detects file operations" do
    unsafe_code = <<~PYTHON
      with open('/etc/passwd', 'r') as f:
          data = f.read()
    PYTHON

    validator = CodeValidation::PythonValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :file_access }
  end

  test "python validator detects eval/exec" do
    unsafe_code = <<~PYTHON
      user_input = input()
      eval(user_input)
    PYTHON

    validator = CodeValidation::PythonValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    violation_types = result.violations.map { |v| v[:type] }
    assert_includes violation_types, :code_injection
  end

  test "python validator detects syntax errors" do
    invalid_code = <<~PYTHON
      if True
          print('missing colon')
    PYTHON

    validator = CodeValidation::PythonValidator.new(invalid_code)
    result = validator.validate

    assert_not result.valid?
    assert result.has_errors?
  end

  test "python validator detects unbalanced brackets" do
    invalid_code = "result = calculate((1 + 2) * 3"

    validator = CodeValidation::PythonValidator.new(invalid_code)
    result = validator.validate

    assert_not result.valid?
    assert result.errors.any? { |e| e.include?("bracket") }
  end

  # R Validator Tests
  test "r validator accepts safe code" do
    safe_code = <<~R
      library(ggplot2)
      library(dplyr)
      
      data <- read.csv('data.csv')
      summary <- data %>% group_by(category) %>% summarize(mean_value = mean(value))
      print(summary)
    R

    validator = CodeValidation::RValidator.new(safe_code)
    result = validator.validate

    assert result.valid?
    assert_empty result.errors
  end

  test "r validator detects forbidden functions" do
    unsafe_code = <<~R
      system('rm -rf ~/')
      file.remove('important.txt')
    R

    validator = CodeValidation::RValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    violation_types = result.violations.map { |v| v[:type] }
    assert_includes violation_types, :system_command
    assert_includes violation_types, :file_access
  end

  test "r validator detects file operations" do
    unsafe_code = <<~R
      file.create('test.txt')
      write.csv(data, 'output.csv')
    R

    validator = CodeValidation::RValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :file_access }
  end

  test "r validator detects dangerous workspace operations" do
    unsafe_code = "rm(list = ls())"

    validator = CodeValidation::RValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :dangerous_operation }
  end

  test "r validator detects syntax errors" do
    invalid_code = <<~R
      if (TRUE {
        print('missing parenthesis')
      }
    R

    validator = CodeValidation::RValidator.new(invalid_code)
    result = validator.validate

    assert_not result.valid?
    assert result.has_errors?
  end

  # SQL Validator Tests
  test "sql validator accepts safe SELECT queries" do
    safe_code = <<~SQL
      SELECT id, name, email
      FROM users
      WHERE created_at > '2024-01-01'
      LIMIT 100
    SQL

    validator = CodeValidation::SqlValidator.new(safe_code)
    result = validator.validate

    assert result.valid?
    assert_empty result.errors
  end

  test "sql validator detects DROP TABLE" do
    unsafe_code = "DROP TABLE users;"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :forbidden_function }
  end

  test "sql validator detects DELETE without WHERE" do
    unsafe_code = "DELETE FROM users"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    critical_violations = result.violations.select { |v| v[:severity] == :critical }
    assert critical_violations.any?
  end

  test "sql validator detects UPDATE without WHERE" do
    unsafe_code = "UPDATE users SET role = 'admin'"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    critical_violations = result.violations.select { |v| v[:severity] == :critical }
    assert critical_violations.any?
  end

  test "sql validator detects SQL injection patterns" do
    unsafe_code = "SELECT * FROM users WHERE id = 1 OR 1=1"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :code_injection }
  end

  test "sql validator detects stacked queries" do
    unsafe_code = "SELECT * FROM users; DROP TABLE users;"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :code_injection }
  end

  test "sql validator detects dangerous functions" do
    unsafe_code = "SELECT * FROM users; EXEC xp_cmdshell 'dir'"

    validator = CodeValidation::SqlValidator.new(unsafe_code)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :system_command }
  end

  test "sql validator detects syntax errors" do
    invalid_code = "SELECT * FROM"

    validator = CodeValidation::SqlValidator.new(invalid_code)
    result = validator.validate

    assert result.has_warnings?
  end

  # Factory Tests
  test "validator factory builds python validator" do
    validator = CodeValidation::ValidatorFactory.build(:python, "print('hello')")
    assert_instance_of CodeValidation::PythonValidator, validator
  end

  test "validator factory builds r validator" do
    validator = CodeValidation::ValidatorFactory.build(:r, "print('hello')")
    assert_instance_of CodeValidation::RValidator, validator
  end

  test "validator factory builds sql validator" do
    validator = CodeValidation::ValidatorFactory.build(:sql, "SELECT 1")
    assert_instance_of CodeValidation::SqlValidator, validator
  end

  test "validator factory raises for unsupported language" do
    assert_raises RuntimeError do
      CodeValidation::ValidatorFactory.build(:javascript, "console.log('test')")
    end
  end

  test "validator factory checks language support" do
    assert CodeValidation::ValidatorFactory.supported?(:python)
    assert CodeValidation::ValidatorFactory.supported?(:r)
    assert CodeValidation::ValidatorFactory.supported?(:sql)
    assert_not CodeValidation::ValidatorFactory.supported?(:javascript)
  end

  # Resource Limit Tests
  test "validators detect code length violations" do
    long_code = "x = 1\n" * 10_000

    validator = CodeValidation::PythonValidator.new(long_code, max_code_length: 5000)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :resource_limit }
  end

  test "validators detect line count violations" do
    many_lines = "# comment\n" * 1000

    validator = CodeValidation::PythonValidator.new(many_lines, max_lines: 500)
    result = validator.validate

    assert result.has_violations?
    assert result.violations.any? { |v| v[:type] == :resource_limit }
  end

  # Integration Tests
  test "validation result provides comprehensive information" do
    code_with_issues = <<~PYTHON
      import os
      import pandas as pd
      
      # This will trigger violations
      os.system('echo test')
      
      # This is safe
      df = pd.DataFrame({'a': [1, 2, 3]})
      print(df.describe())
    PYTHON

    validator = CodeValidation::PythonValidator.new(code_with_issues)
    result = validator.validate

    # Check result structure
    assert_respond_to result, :valid?
    assert_respond_to result, :has_errors?
    assert_respond_to result, :has_warnings?
    assert_respond_to result, :has_violations?
    assert_respond_to result, :safe?

    # Should have violations but may be syntactically valid
    assert result.has_violations?
    assert_not result.safe?

    # Check violation structure
    result.violations.each do |violation|
      assert violation.key?(:type)
      assert violation.key?(:message)
      assert violation.key?(:severity)
    end
  end

  test "safe method returns true only when valid and no violations" do
    safe_code = "import pandas as pd\ndf = pd.DataFrame()"
    unsafe_code = "import os\nos.system('ls')"
    invalid_code = "if True print('test')"

    safe_result = CodeValidation::PythonValidator.new(safe_code).validate
    unsafe_result = CodeValidation::PythonValidator.new(unsafe_code).validate
    invalid_result = CodeValidation::PythonValidator.new(invalid_code).validate

    assert safe_result.safe?
    assert_not unsafe_result.safe?
    assert_not invalid_result.safe?
  end
end

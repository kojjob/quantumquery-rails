# frozen_string_literal: true

module CodeExecution
  # Factory for building appropriate code executors based on language
  class ExecutorFactory
    # Build an executor for the given language
    #
    # @param language [String, Symbol] The programming language
    # @param code [String] The code to execute
    # @param options [Hash] Execution options
    # @return [BaseExecutor] The appropriate executor instance
    # @raise [RuntimeError] If the language is not supported
    def self.build(language, code, options = {})
      language = language.to_s.downcase

      case language
      when "python", "py"
        PythonExecutor.new(code, options)
      when "r"
        RExecutor.new(code, options)
      when "sql"
        SqlExecutor.new(code, options)
      else
        raise "Unsupported language for execution: #{language}"
      end
    end

    # Check if a language is supported
    #
    # @param language [String, Symbol] The programming language
    # @return [Boolean] True if the language is supported
    def self.supported?(language)
      language = language.to_s.downcase
      %w[python py r sql].include?(language)
    end

    # Get list of supported languages
    #
    # @return [Array<String>] List of supported languages
    def self.supported_languages
      %w[python r sql]
    end
  end
end

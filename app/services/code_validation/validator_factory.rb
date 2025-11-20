# frozen_string_literal: true

module CodeValidation
  # Factory for building appropriate code validators based on language
  class ValidatorFactory
    # Build a validator for the given language/analysis type
    #
    # @param language [String, Symbol] The programming language or analysis type
    # @param code [String] The code to validate
    # @param options [Hash] Validation options
    # @return [BaseValidator] The appropriate validator instance
    # @raise [RuntimeError] If the language is not supported
    def self.build(language, code, options = {})
      language = language.to_s.downcase

      case language
      when "python", "py"
        PythonValidator.new(code, options)
      when "r"
        RValidator.new(code, options)
      when "sql"
        SqlValidator.new(code, options)
      else
        raise "Unsupported language for validation: #{language}"
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

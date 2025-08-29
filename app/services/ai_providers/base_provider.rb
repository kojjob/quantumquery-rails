# app/services/ai_providers/base_provider.rb
module AiProviders
  class BaseProvider
    attr_reader :config, :model

    def initialize(model: nil, config: {})
      @model = model || default_model
      @config = config
      @client = initialize_client
    end

    # Abstract methods to be implemented by subclasses
    def generate_completion(prompt, options = {})
      raise NotImplementedError, "#{self.class} must implement #generate_completion"
    end

    def generate_code(prompt, language: "python", **options)
      raise NotImplementedError, "#{self.class} must implement #generate_code"
    end

    def analyze_data_requirements(query, dataset_schema, options = {})
      raise NotImplementedError, "#{self.class} must implement #analyze_data_requirements"
    end

    def interpret_results(results, original_query, options = {})
      raise NotImplementedError, "#{self.class} must implement #interpret_results"
    end

    def available_models
      raise NotImplementedError, "#{self.class} must implement #available_models"
    end

    def supports_streaming?
      false
    end

    def supports_function_calling?
      false
    end

    def supports_vision?
      false
    end

    def max_context_length
      4096 # Default, override in subclasses
    end

    def cost_per_1k_tokens
      { input: 0.001, output: 0.002 } # Default pricing
    end

    protected

    def initialize_client
      raise NotImplementedError, "#{self.class} must implement #initialize_client"
    end

    def default_model
      raise NotImplementedError, "#{self.class} must implement #default_model"
    end

    def handle_api_error(error)
      Rails.logger.error "AI Provider Error (#{self.class}): #{error.message}"

      case error
      when /rate limit/i
        raise ProviderErrors::RateLimitError, error.message
      when /api key/i, /authentication/i
        raise ProviderErrors::AuthenticationError, error.message
      when /timeout/i
        raise ProviderErrors::TimeoutError, error.message
      else
        raise ProviderErrors::APIError, error.message
      end
    end

    def extract_code_from_response(response)
      # Extract code blocks from markdown-formatted responses
      code_blocks = response.scan(/```(?:python|r|sql|julia|javascript)?\n(.*?)\n```/m)
      code_blocks.flatten.first || response
    end

    def calculate_tokens(text)
      # Rough estimation - override with provider-specific tokenization
      text.split(/\s+/).length * 1.3
    end
  end

  # Custom error classes
  module ProviderErrors
    class APIError < StandardError; end
    class RateLimitError < APIError; end
    class AuthenticationError < APIError; end
    class TimeoutError < APIError; end
    class ModelNotAvailableError < APIError; end
  end
end

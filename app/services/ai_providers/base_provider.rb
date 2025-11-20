# app/services/ai_providers/base_provider.rb
module AiProviders
  class BaseProvider
    attr_reader :config, :model

    def initialize(model: nil, config: {})
      @model = model || default_model
      @config = config
      @client = initialize_client
      @rate_limiter = RateLimiter.new(self.class.name, config[:rate_limit] || default_rate_limit)
      @retry_config = {
        max_attempts: config[:max_retries] || 3,
        base_delay: config[:base_delay] || 1.0,
        max_delay: config[:max_delay] || 30.0,
        exponential_base: config[:exponential_base] || 2.0
      }
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

    def default_rate_limit
      { requests_per_minute: 60, tokens_per_minute: 100_000 }
    end

    # Retry wrapper with exponential backoff
    def with_retry(&block)
      attempt = 0
      
      loop do
        attempt += 1
        
        begin
          return yield
        rescue => error
          should_retry, wait_time = should_retry_error?(error, attempt)
          
          if should_retry
            Rails.logger.warn "Retry attempt #{attempt}/#{@retry_config[:max_attempts]} after error: #{error.message}"
            sleep wait_time
            next
          else
            raise error
          end
        end
      end
    end

    def should_retry_error?(error, attempt)
      # Don't retry if max attempts reached
      return [ false, 0 ] if attempt >= @retry_config[:max_attempts]

      # Check if error is retryable
      retryable = case error
      when ProviderErrors::RateLimitError, ProviderErrors::TimeoutError
        true
      when ProviderErrors::APIError
        # Retry on 5xx errors but not 4xx
        error.message =~ /5\d{2}/ || error.message =~ /timeout/i || error.message =~ /temporary/i
      else
        error.message =~ /rate limit|timeout|temporary|503|502|500/i
      end

      return [ false, 0 ] unless retryable

      # Calculate exponential backoff with jitter
      wait_time = calculate_backoff(attempt)
      [ true, wait_time ]
    end

    def calculate_backoff(attempt)
      delay = @retry_config[:base_delay] * (@retry_config[:exponential_base] ** (attempt - 1))
      delay = [ delay, @retry_config[:max_delay] ].min
      
      # Add jitter (random 0-25% variation)
      jitter = delay * (0.75 + rand * 0.25)
      jitter
    end

    # Rate limiting wrapper
    def with_rate_limit(&block)
      @rate_limiter.throttle(&block)
    end

    # Combined retry + rate limit wrapper
    def with_resilience(&block)
      with_retry do
        with_rate_limit(&block)
      end
    end

    def handle_api_error(error)
      Rails.logger.error "AI Provider Error (#{self.class}): #{error.message}"
      Rails.logger.error error.backtrace.first(5).join("\n") if error.backtrace

      # Normalize error types
      error_message = error.respond_to?(:message) ? error.message : error.to_s
      
      case error_message
      when /rate.?limit|429/i
        raise ProviderErrors::RateLimitError, error_message
      when /api.?key|unauthorized|401|403/i
        raise ProviderErrors::AuthenticationError, error_message
      when /timeout|timed.?out/i
        raise ProviderErrors::TimeoutError, error_message
      when /model.*(not|unavailable|exists)/i
        raise ProviderErrors::ModelNotAvailableError, error_message
      when /5\d{2}/
        raise ProviderErrors::APIError, "Server error: #{error_message}"
      else
        raise ProviderErrors::APIError, error_message
      end
    end

    def extract_code_from_response(response)
      # Extract code blocks from markdown-formatted responses
      code_blocks = response.scan(/```(?:python|r|sql|julia|javascript)?\n(.*?)\n```/m)
      code_blocks.flatten.first || response
    end

    def calculate_tokens(text)
      # Rough estimation - override with provider-specific tokenization
      return 0 if text.nil? || text.empty?
      text.split(/\s+/).length * 1.3
    end

    # Streaming helper for subclasses
    def handle_streaming_response(stream_proc)
      accumulated_content = ""
      
      stream_proc.call do |chunk|
        content_delta = extract_content_from_chunk(chunk)
        accumulated_content << content_delta if content_delta
        
        yield content_delta if block_given? && content_delta
      end
      
      accumulated_content
    end

    def extract_content_from_chunk(chunk)
      # Override in subclasses based on provider-specific chunk format
      chunk.to_s
    end

    # Rate limiter implementation
    class RateLimiter
      def initialize(provider_name, limits)
        @provider_name = provider_name
        @requests_per_minute = limits[:requests_per_minute]
        @tokens_per_minute = limits[:tokens_per_minute]
        @request_times = []
        @token_usage = []
        @mutex = Mutex.new
      end

      def throttle
        @mutex.synchronize do
          wait_if_needed
          record_request
        end
        
        result = yield
        
        @mutex.synchronize do
          record_tokens(result) if result.is_a?(Hash) && result[:usage]
        end
        
        result
      end

      private

      def wait_if_needed
        now = Time.current
        one_minute_ago = now - 60.seconds

        # Clean old entries
        @request_times.reject! { |t| t < one_minute_ago }
        @token_usage.reject! { |entry| entry[:time] < one_minute_ago }

        # Check request rate limit
        if @request_times.size >= @requests_per_minute
          oldest_request = @request_times.first
          wait_time = 60 - (now - oldest_request)
          
          if wait_time > 0
            Rails.logger.info "Rate limit: waiting #{wait_time.round(2)}s"
            sleep wait_time
            @request_times.shift
          end
        end

        # Check token rate limit
        total_tokens = @token_usage.sum { |entry| entry[:tokens] }
        if total_tokens >= @tokens_per_minute
          oldest_token = @token_usage.first
          wait_time = 60 - (now - oldest_token[:time])
          
          if wait_time > 0
            Rails.logger.info "Token rate limit: waiting #{wait_time.round(2)}s"
            sleep wait_time
          end
        end
      end

      def record_request
        @request_times << Time.current
      end

      def record_tokens(result)
        total = result.dig(:usage, :total_tokens) || 0
        @token_usage << { time: Time.current, tokens: total }
      end
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

# app/services/ai_providers/anthropic_provider.rb
module AiProviders
  class AnthropicProvider < BaseProvider
    MODELS = {
      "claude-3-opus" => {
        name: "Claude 3 Opus",
        context: 200_000,
        cost: { input: 0.015, output: 0.075 },
        capabilities: [ :advanced_reasoning, :complex_analysis, :code_generation ]
      },
      "claude-3-sonnet" => {
        name: "Claude 3 Sonnet",
        context: 200_000,
        cost: { input: 0.003, output: 0.015 },
        capabilities: [ :balanced_performance, :code_generation ]
      },
      "claude-3-haiku" => {
        name: "Claude 3 Haiku",
        context: 200_000,
        cost: { input: 0.00025, output: 0.00125 },
        capabilities: [ :fast_responses, :simple_tasks ]
      }
    }.freeze

    def generate_completion(prompt, options = {})
      with_resilience do
        messages = build_messages(prompt, options)
        
        # Handle streaming if requested
        if options[:stream] && block_given?
          stream_completion(messages, options) do |chunk|
            yield chunk
          end
        else
          non_streaming_completion(messages, options)
        end
      end
    rescue => e
      handle_api_error(e)
    end

    def generate_completion_stream(prompt, options = {}, &block)
      generate_completion(prompt, options.merge(stream: true), &block)
    end

    def generate_code(prompt, language: "python", **options)
      with_resilience do
        system_prompt = code_generation_system_prompt(language)

        code_prompt = """
        Generate production-ready #{language} code for the following task:

        #{prompt}

        Requirements:
        - Include proper error handling
        - Add helpful comments
        - Follow best practices for #{language}
        - Optimize for performance and readability
        - Include necessary imports

        Return only the code without any explanation.
        """

        response = non_streaming_completion(
          build_messages(code_prompt, options.merge(system_prompt: system_prompt)),
          options.merge(temperature: 0.3)
        )
        
        extract_code_from_response(response[:content])
      end
    rescue => e
      handle_api_error(e)
    end

    def analyze_data_requirements(query, dataset_schema, options = {})
      with_resilience do
        analysis_prompt = """
        Analyze the following natural language query and determine data requirements:

        Query: #{query}

        Available Dataset Schema:
        #{dataset_schema.to_json}

        Please provide:
        1. The type of analysis requested (statistical, predictive, exploratory, etc.)
        2. Required tables/datasets
        3. Specific columns needed
        4. Any filters or conditions to apply
        5. Suggested analysis steps
        6. Estimated complexity (1-10 scale)

        Format as JSON.
        """

        response = non_streaming_completion(
          build_messages(analysis_prompt, options),
          options.merge(temperature: 0.2)
        )
        
        JSON.parse(response[:content])
      end
    rescue JSON::ParserError => e
      { error: "Failed to parse analysis requirements: #{e.message}" }
    rescue => e
      handle_api_error(e)
    end

    def interpret_results(results, original_query, options = {})
      with_resilience do
        interpretation_prompt = """
        Interpret these analysis results for a non-technical audience:

        Original Question: #{original_query}

        Analysis Results:
        #{results.to_json}

        Please provide:
        1. Direct answer to the original question
        2. Key findings and insights
        3. Statistical significance (if applicable)
        4. Business implications
        5. Recommendations for action
        6. Limitations of the analysis

        Use clear, non-technical language while maintaining accuracy.
        """

        response = non_streaming_completion(
          build_messages(interpretation_prompt, options),
          options.merge(temperature: 0.5)
        )
        
        response[:content]
      end
    rescue => e
      handle_api_error(e)
    end

    def available_models
      MODELS.keys
    end

    def supports_streaming?
      true
    end

    def supports_function_calling?
      @model.include?("claude-3") && !@model.include?("haiku")
    end

    def supports_vision?
      @model.include?("claude-3")
    end

    def max_context_length
      MODELS[@model][:context] || 200_000
    end

    def cost_per_1k_tokens
      MODELS[@model][:cost] || super
    end

    protected

    def initialize_client
      Anthropic::Client.new(api_key: Rails.application.credentials.anthropic_api_key)
    end

    def default_model
      "claude-3-sonnet"
    end

    private

    def build_messages(prompt, options = {})
      messages = []
      
      # Handle vision inputs if provided
      if options[:images] && supports_vision?
        content = [ { type: "text", text: prompt } ]
        
        Array(options[:images]).each do |image|
          content << build_image_content(image)
        end
        
        messages << { role: "user", content: content }
      else
        messages << { role: "user", content: prompt }
      end
      
      messages
    end

    def build_image_content(image)
      case image
      when String
        if image.start_with?("http")
          # URL image
          { type: "image", source: { type: "url", url: image } }
        elsif image.start_with?("data:")
          # Data URI
          media_type, base64_data = image.split(",", 2)
          media_type = media_type.match(/image\/(\w+)/)[0]
          { type: "image", source: { type: "base64", media_type: media_type, data: base64_data } }
        else
          # Assume base64
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: image } }
        end
      when Hash
        # Already formatted
        image
      end
    end

    def non_streaming_completion(messages, options)
      response = @client.messages.create(
        model: @model,
        max_tokens: options[:max_tokens] || 4000,
        temperature: options[:temperature] || 0.7,
        system: options[:system_prompt] || default_system_prompt,
        messages: messages
      )

      {
        content: extract_content_from_response(response),
        usage: {
          input_tokens: response.usage.input_tokens,
          output_tokens: response.usage.output_tokens,
          total_tokens: response.usage.input_tokens + response.usage.output_tokens
        },
        model: @model,
        stop_reason: response.stop_reason
      }
    end

    def stream_completion(messages, options)
      accumulated_content = ""
      usage_data = { input_tokens: 0, output_tokens: 0 }
      
      @client.messages.stream(
        model: @model,
        max_tokens: options[:max_tokens] || 4000,
        temperature: options[:temperature] || 0.7,
        system: options[:system_prompt] || default_system_prompt,
        messages: messages
      ) do |event|
        case event
        when Anthropic::StreamEvent::ContentBlockDelta
          delta = event.delta.text
          accumulated_content << delta if delta
          yield delta if block_given? && delta
        when Anthropic::StreamEvent::MessageStart
          usage_data[:input_tokens] = event.message.usage.input_tokens if event.message.usage
        when Anthropic::StreamEvent::MessageDelta
          usage_data[:output_tokens] = event.usage.output_tokens if event.usage
        end
      end
      
      {
        content: accumulated_content,
        usage: {
          input_tokens: usage_data[:input_tokens],
          output_tokens: usage_data[:output_tokens],
          total_tokens: usage_data[:input_tokens] + usage_data[:output_tokens]
        },
        model: @model
      }
    end

    def extract_content_from_response(response)
      # Handle both single text content and multi-content responses
      if response.content.is_a?(Array)
        text_parts = response.content.select { |c| c.type == "text" }
        text_parts.map(&:text).join("\n")
      else
        response.content[0].text
      end
    end

    def default_system_prompt
      """
      You are QuantumQuery, an advanced data science assistant. You help users analyze data
      by generating and executing code, interpreting results, and providing insights.

      Your responses should be:
      - Accurate and based on statistical best practices
      - Clear and understandable to your audience
      - Actionable with specific recommendations
      - Transparent about limitations and assumptions
      """
    end

    def code_generation_system_prompt(language)
      """
      You are an expert #{language} programmer and data scientist. Generate high-quality,
      production-ready code that:

      - Follows #{language} best practices and conventions
      - Includes comprehensive error handling
      - Is well-commented and self-documenting
      - Handles edge cases appropriately
      - Is optimized for performance
      - Uses appropriate libraries for data science tasks

      Available libraries:
      #{available_libraries_for(language)}
      """
    end

    def available_libraries_for(language)
      case language
      when "python"
        "pandas, numpy, scipy, scikit-learn, matplotlib, seaborn, plotly, statsmodels"
      when "r"
        "tidyverse, ggplot2, dplyr, caret, forecast, lme4, data.table"
      when "sql"
        "Standard SQL with window functions, CTEs, and analytical functions"
      else
        "Standard library"
      end
    end
  end
end

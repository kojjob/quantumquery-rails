# app/services/ai_providers/openai_provider.rb
module AiProviders
  class OpenaiProvider < BaseProvider
    MODELS = {
      "gpt-4-turbo" => {
        name: "GPT-4 Turbo",
        context: 128_000,
        cost: { input: 0.01, output: 0.03 },
        capabilities: [ :advanced_reasoning, :function_calling, :vision ]
      },
      "gpt-4" => {
        name: "GPT-4",
        context: 8192,
        cost: { input: 0.03, output: 0.06 },
        capabilities: [ :advanced_reasoning, :function_calling ]
      },
      "gpt-3.5-turbo" => {
        name: "GPT-3.5 Turbo",
        context: 16_385,
        cost: { input: 0.0005, output: 0.0015 },
        capabilities: [ :fast_responses, :basic_reasoning ]
      }
    }.freeze

    def generate_completion(prompt, options = {})
      response = @client.chat(
        parameters: {
          model: @model,
          messages: build_messages(prompt, options[:system_prompt]),
          max_tokens: options[:max_tokens] || 4000,
          temperature: options[:temperature] || 0.7,
          response_format: options[:json_mode] ? { type: "json_object" } : nil
        }.compact
      )

      {
        content: response.dig("choices", 0, "message", "content"),
        usage: {
          input_tokens: response.dig("usage", "prompt_tokens"),
          output_tokens: response.dig("usage", "completion_tokens"),
          total_tokens: response.dig("usage", "total_tokens")
        },
        model: @model
      }
    rescue => e
      handle_api_error(e)
    end

    def generate_code(prompt, language: "python", **options)
      functions = [ {
        name: "generate_code",
        description: "Generate code for data analysis",
        parameters: {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "The generated #{language} code"
            },
            explanation: {
              type: "string",
              description: "Brief explanation of what the code does"
            },
            dependencies: {
              type: "array",
              items: { type: "string" },
              description: "Required libraries or packages"
            }
          },
          required: [ "code" ]
        }
      } ]

      response = @client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: "system", content: code_generation_system_prompt(language) },
            { role: "user", content: prompt }
          ],
          functions: functions,
          function_call: { name: "generate_code" },
          temperature: 0.3
        }
      )

      function_call = response.dig("choices", 0, "message", "function_call")
      if function_call
        result = JSON.parse(function_call["arguments"])
        result["code"]
      else
        extract_code_from_response(response.dig("choices", 0, "message", "content"))
      end
    rescue => e
      handle_api_error(e)
    end

    def analyze_data_requirements(query, dataset_schema, options = {})
      functions = [ {
        name: "analyze_requirements",
        description: "Analyze data requirements for the query",
        parameters: {
          type: "object",
          properties: {
            analysis_type: {
              type: "string",
              enum: [ "statistical", "predictive", "exploratory", "descriptive", "diagnostic" ]
            },
            required_tables: {
              type: "array",
              items: { type: "string" }
            },
            required_columns: {
              type: "array",
              items: { type: "string" }
            },
            filters: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  column: { type: "string" },
                  operator: { type: "string" },
                  value: { type: "string" }
                }
              }
            },
            analysis_steps: {
              type: "array",
              items: { type: "string" }
            },
            complexity_score: {
              type: "number",
              minimum: 1,
              maximum: 10
            }
          },
          required: [ "analysis_type", "required_tables", "analysis_steps", "complexity_score" ]
        }
      } ]

      response = @client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: "system", content: "You are a data analysis expert. Analyze the requirements for the given query." },
            { role: "user", content: "Query: #{query}\n\nDataset Schema: #{dataset_schema.to_json}" }
          ],
          functions: functions,
          function_call: { name: "analyze_requirements" },
          temperature: 0.2
        }
      )

      function_call = response.dig("choices", 0, "message", "function_call")
      JSON.parse(function_call["arguments"]) if function_call
    rescue => e
      handle_api_error(e)
    end

    def interpret_results(results, original_query, options = {})
      interpretation_prompt = build_interpretation_prompt(results, original_query)

      response = generate_completion(
        interpretation_prompt,
        system_prompt: "You are a data analyst explaining results to business stakeholders.",
        temperature: 0.5
      )

      response[:content]
    end

    def available_models
      MODELS.keys
    end

    def supports_streaming?
      true
    end

    def supports_function_calling?
      @model != "gpt-3.5-turbo"
    end

    def supports_vision?
      @model == "gpt-4-turbo"
    end

    def max_context_length
      MODELS[@model][:context] || 4096
    end

    def cost_per_1k_tokens
      MODELS[@model][:cost] || super
    end

    protected

    def initialize_client
      OpenAI::Client.new(access_token: Rails.application.credentials.openai_api_key)
    end

    def default_model
      "gpt-4-turbo"
    end

    private

    def build_messages(prompt, system_prompt = nil)
      messages = []
      messages << { role: "system", content: system_prompt || default_system_prompt }
      messages << { role: "user", content: prompt }
      messages
    end

    def default_system_prompt
      "You are QuantumQuery, an advanced data science assistant powered by GPT-4."
    end

    def code_generation_system_prompt(language)
      """
      You are an expert #{language} programmer specializing in data science.
      Generate clean, efficient, well-documented code.
      Include error handling and follow best practices.
      """
    end

    def build_interpretation_prompt(results, query)
      """
      Interpret these results for the query: #{query}

      Results: #{results.to_json}

      Provide:
      1. Direct answer
      2. Key insights
      3. Recommendations
      4. Limitations

      Use business-friendly language.
      """
    end
  end
end

# test/services/ai_providers_test.rb
require "test_helper"

class AiProvidersTest < ActiveSupport::TestCase
  setup do
    @test_prompt = "What is the capital of France?"
    @code_prompt = "Write a function to calculate the mean of a list"
    @dataset_schema = {
      tables: [ "users", "orders" ],
      columns: {
        users: [ "id", "name", "email", "created_at" ],
        orders: [ "id", "user_id", "total", "status", "created_at" ]
      }
    }
  end

  # Anthropic Provider Tests
  test "anthropic provider initializes correctly" do
    provider = AiProviders::AnthropicProvider.new
    
    assert_equal "claude-3-sonnet", provider.model
    assert provider.supports_streaming?
    assert provider.supports_vision?
    assert_equal 200_000, provider.max_context_length
  end

  test "anthropic provider generates basic completion" do
    skip "Requires ANTHROPIC_API_KEY" unless ENV["ANTHROPIC_API_KEY"].present?
    
    provider = AiProviders::AnthropicProvider.new(model: "claude-3-haiku")
    
    result = provider.generate_completion(@test_prompt, max_tokens: 100)
    
    assert result[:content].present?
    assert result[:usage][:total_tokens] > 0
    assert_equal "claude-3-haiku", result[:model]
    
    puts "\n✓ Anthropic completion: #{result[:content][0..100]}..."
    puts "  Tokens used: #{result[:usage][:total_tokens]}"
  end

  test "anthropic provider streams completion" do
    skip "Requires ANTHROPIC_API_KEY" unless ENV["ANTHROPIC_API_KEY"].present?
    
    provider = AiProviders::AnthropicProvider.new(model: "claude-3-haiku")
    chunks = []
    
    result = provider.generate_completion_stream(@test_prompt, max_tokens: 50) do |chunk|
      chunks << chunk
    end
    
    assert result[:content].present?
    assert chunks.length > 1, "Should receive multiple chunks"
    assert_equal chunks.join, result[:content]
    
    puts "\n✓ Anthropic streaming: Received #{chunks.length} chunks"
  end

  test "anthropic provider generates code" do
    skip "Requires ANTHROPIC_API_KEY" unless ENV["ANTHROPIC_API_KEY"].present?
    
    provider = AiProviders::AnthropicProvider.new(model: "claude-3-sonnet")
    
    code = provider.generate_code(@code_prompt, language: "python")
    
    assert code.present?
    assert code.include?("def"), "Code should contain a function definition"
    
    puts "\n✓ Anthropic code generation:"
    puts code[0..200]
  end

  test "anthropic provider handles rate limiting" do
    skip "Requires ANTHROPIC_API_KEY" unless ENV["ANTHROPIC_API_KEY"].present?
    
    provider = AiProviders::AnthropicProvider.new(
      model: "claude-3-haiku",
      config: { rate_limit: { requests_per_minute: 2, tokens_per_minute: 1000 } }
    )
    
    start_time = Time.current
    
    3.times do |i|
      provider.generate_completion("Count to #{i}", max_tokens: 20)
    end
    
    elapsed = Time.current - start_time
    
    # Should take at least 30 seconds due to rate limiting (3 requests at 2 RPM)
    assert elapsed >= 30, "Rate limiting should enforce delays"
    
    puts "\n✓ Anthropic rate limiting: #{elapsed.round(1)}s for 3 requests"
  end

  test "anthropic provider retries on transient errors" do
    provider = AiProviders::AnthropicProvider.new
    
    # Mock the client to fail twice then succeed
    attempts = 0
    provider.instance_variable_get(:@client).stub :messages, ->(*args) {
      attempts += 1
      raise StandardError, "502 Bad Gateway" if attempts <= 2
      OpenStruct.new(
        content: [ OpenStruct.new(text: "Success", type: "text") ],
        usage: OpenStruct.new(input_tokens: 10, output_tokens: 5),
        stop_reason: "end_turn"
      )
    } do
      result = provider.generate_completion(@test_prompt)
      assert_equal "Success", result[:content]
      assert_equal 3, attempts
    end
    
    puts "\n✓ Anthropic retry logic: Succeeded after #{attempts} attempts"
  end

  # OpenAI Provider Tests
  test "openai provider initializes correctly" do
    provider = AiProviders::OpenaiProvider.new
    
    assert_equal "gpt-4-turbo", provider.model
    assert provider.supports_streaming?
    assert provider.supports_function_calling?
    assert provider.supports_vision?
    assert_equal 128_000, provider.max_context_length
  end

  test "openai provider generates basic completion" do
    skip "Requires OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"].present?
    
    provider = AiProviders::OpenaiProvider.new(model: "gpt-3.5-turbo")
    
    result = provider.generate_completion(@test_prompt, max_tokens: 100)
    
    assert result[:content].present?
    assert result[:usage][:total_tokens] > 0
    
    puts "\n✓ OpenAI completion: #{result[:content][0..100]}..."
    puts "  Tokens used: #{result[:usage][:total_tokens]}"
  end

  test "openai provider streams completion" do
    skip "Requires OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"].present?
    
    provider = AiProviders::OpenaiProvider.new(model: "gpt-3.5-turbo")
    chunks = []
    
    result = provider.generate_completion_stream(@test_prompt, max_tokens: 50) do |chunk|
      chunks << chunk
    end
    
    assert result[:content].present?
    assert chunks.length > 1, "Should receive multiple chunks"
    
    puts "\n✓ OpenAI streaming: Received #{chunks.length} chunks"
  end

  test "openai provider generates code with function calling" do
    skip "Requires OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"].present?
    
    provider = AiProviders::OpenaiProvider.new(model: "gpt-4-turbo")
    
    code = provider.generate_code(@code_prompt, language: "python")
    
    assert code.present?
    assert code.include?("def"), "Code should contain a function definition"
    
    puts "\n✓ OpenAI code generation (with functions):"
    puts code[0..200]
  end

  test "openai provider analyzes data requirements with functions" do
    skip "Requires OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"].present?
    
    provider = AiProviders::OpenaiProvider.new(model: "gpt-4-turbo")
    
    result = provider.analyze_data_requirements(
      "What are the top 10 customers by total order value?",
      @dataset_schema
    )
    
    assert result[:analysis_type].present?
    assert result[:required_tables].is_a?(Array)
    assert result[:complexity_score].between?(1, 10)
    
    puts "\n✓ OpenAI data requirements analysis:"
    puts "  Type: #{result[:analysis_type]}"
    puts "  Tables: #{result[:required_tables]}"
    puts "  Complexity: #{result[:complexity_score]}"
  end

  test "openai provider handles rate limiting" do
    skip "Requires OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"].present?
    
    provider = AiProviders::OpenaiProvider.new(
      model: "gpt-3.5-turbo",
      config: { rate_limit: { requests_per_minute: 2, tokens_per_minute: 1000 } }
    )
    
    start_time = Time.current
    
    3.times do |i|
      provider.generate_completion("Count to #{i}", max_tokens: 20)
    end
    
    elapsed = Time.current - start_time
    
    assert elapsed >= 30, "Rate limiting should enforce delays"
    
    puts "\n✓ OpenAI rate limiting: #{elapsed.round(1)}s for 3 requests"
  end

  # Integration Tests
  test "both providers handle errors consistently" do
    anthropic = AiProviders::AnthropicProvider.new
    openai = AiProviders::OpenaiProvider.new
    
    [ anthropic, openai ].each do |provider|
      assert_raises(AiProviders::ProviderErrors::AuthenticationError) do
        # Mock API key error
        provider.send(:handle_api_error, StandardError.new("401 Unauthorized"))
      end
      
      assert_raises(AiProviders::ProviderErrors::RateLimitError) do
        provider.send(:handle_api_error, StandardError.new("429 Rate limit exceeded"))
      end
      
      assert_raises(AiProviders::ProviderErrors::TimeoutError) do
        provider.send(:handle_api_error, StandardError.new("Request timeout"))
      end
    end
    
    puts "\n✓ Both providers handle errors consistently"
  end

  test "providers report capabilities correctly" do
    providers = {
      "Claude 3 Opus" => AiProviders::AnthropicProvider.new(model: "claude-3-opus"),
      "Claude 3 Haiku" => AiProviders::AnthropicProvider.new(model: "claude-3-haiku"),
      "GPT-4 Turbo" => AiProviders::OpenaiProvider.new(model: "gpt-4-turbo"),
      "GPT-3.5 Turbo" => AiProviders::OpenaiProvider.new(model: "gpt-3.5-turbo")
    }
    
    puts "\n✓ Provider Capabilities:"
    providers.each do |name, provider|
      puts "\n  #{name}:"
      puts "    Streaming: #{provider.supports_streaming?}"
      puts "    Function Calling: #{provider.supports_function_calling?}"
      puts "    Vision: #{provider.supports_vision?}"
      puts "    Context Length: #{provider.max_context_length.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end
  end
end

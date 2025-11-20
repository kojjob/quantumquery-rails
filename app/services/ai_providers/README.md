# AI Providers

This directory contains integrations with various AI providers for QuantumQuery's analysis capabilities.

## Overview

The AI provider system is built on a modular architecture with a base class (`BaseProvider`) that defines the interface and common functionality, and provider-specific implementations for Anthropic, OpenAI, and others.

## Features

All providers support:

- **Streaming Responses**: Real-time token streaming for better UX
- **Automatic Retries**: Exponential backoff for transient errors
- **Rate Limiting**: Configurable RPM and TPM limits
- **Error Handling**: Consistent error types across providers
- **Token Tracking**: Automatic usage tracking and cost calculation

## Available Providers

### Anthropic (Claude)

```ruby
provider = AiProviders::AnthropicProvider.new(
  model: "claude-3-sonnet",  # or "claude-3-opus", "claude-3-haiku"
  config: {
    max_retries: 3,
    base_delay: 1.0,
    rate_limit: {
      requests_per_minute: 60,
      tokens_per_minute: 100_000
    }
  }
)

# Basic completion
result = provider.generate_completion("Explain quantum computing")
puts result[:content]
puts "Tokens: #{result[:usage][:total_tokens]}"

# Streaming
provider.generate_completion_stream("Write a story") do |chunk|
  print chunk
end

# Vision support (Claude 3 models)
result = provider.generate_completion(
  "What's in this image?",
  images: ["https://example.com/image.jpg"]
)

# Code generation
code = provider.generate_code(
  "Create a function to analyze sales data",
  language: "python"
)
```

**Capabilities:**
- ✅ Streaming
- ✅ Vision (Claude 3 models)
- ⚠️ Function Calling (Claude 3 Opus/Sonnet only)
- Context: 200K tokens
- Best for: Complex reasoning, long documents, code generation

### OpenAI (GPT)

```ruby
provider = AiProviders::OpenaiProvider.new(
  model: "gpt-4-turbo",  # or "gpt-4", "gpt-3.5-turbo"
  config: {
    max_retries: 3,
    rate_limit: {
      requests_per_minute: 60,
      tokens_per_minute: 150_000
    }
  }
)

# Basic completion
result = provider.generate_completion("Explain machine learning")
puts result[:content]

# Streaming
provider.generate_completion_stream("Write code") do |chunk|
  print chunk
end

# Function calling (GPT-4 models)
code = provider.generate_code(
  "Write a data analysis function",
  language: "python"
)  # Uses function calling for structured output

# Data requirements analysis
requirements = provider.analyze_data_requirements(
  "What are the top 10 customers?",
  dataset_schema
)

# Vision support (GPT-4 Turbo)
result = provider.generate_completion(
  "Describe this chart",
  images: ["data:image/jpeg;base64,/9j/4AAQ..."]
)
```

**Capabilities:**
- ✅ Streaming
- ✅ Function Calling (GPT-4 models)
- ✅ Vision (GPT-4 Turbo)
- Context: 128K tokens (GPT-4 Turbo)
- Best for: Function calling, JSON outputs, vision tasks

## Usage in QueryAnalysisOrchestrator

The orchestrator automatically selects the best provider based on:
- Model availability
- Task complexity
- Required capabilities
- Cost optimization

```ruby
# In app/services/query_analysis_orchestrator.rb

def create_provider(model)
  case model
  when /claude/
    AiProviders::AnthropicProvider.new(model: model)
  when /gpt/
    AiProviders::OpenaiProvider.new(model: model)
  # ... other providers
  end
end
```

## Core Methods

All providers implement these methods:

### `generate_completion(prompt, options = {})`

Generate a text completion.

**Options:**
- `max_tokens`: Maximum response length (default: 4000)
- `temperature`: Sampling temperature 0-1 (default: 0.7)
- `system_prompt`: System instruction (optional)
- `stream`: Enable streaming (default: false)
- `images`: Array of image URLs/base64 (vision models only)
- `json_mode`: Force JSON response (OpenAI only)

**Returns:**
```ruby
{
  content: "The response text...",
  usage: {
    input_tokens: 123,
    output_tokens: 456,
    total_tokens: 579
  },
  model: "claude-3-sonnet",
  stop_reason: "end_turn"  # or finish_reason
}
```

### `generate_code(prompt, language:, **options)`

Generate code for a specific programming language.

**Parameters:**
- `prompt`: Description of what code should do
- `language`: "python", "r", "sql", "julia", etc.
- `options`: Same as generate_completion

**Returns:** String of generated code

### `analyze_data_requirements(query, dataset_schema, options = {})`

Analyze what data is needed for a query.

**Returns:**
```ruby
{
  analysis_type: "statistical",
  required_tables: ["users", "orders"],
  required_columns: ["user_id", "total", "created_at"],
  filters: [...],
  analysis_steps: [...],
  complexity_score: 7
}
```

### `interpret_results(results, original_query, options = {})`

Interpret analysis results in plain language.

**Returns:** String with user-friendly interpretation

## Resilience Features

### Automatic Retries

All API calls automatically retry on transient errors:

```ruby
# Retries these errors automatically:
- Rate limit errors (429)
- Timeouts
- 5xx server errors
- Network issues

# Does NOT retry:
- Authentication errors (401, 403)
- Invalid request errors (400)
- Model not available (404)
```

Retry behavior:
- Max attempts: 3 (configurable)
- Exponential backoff: 1s, 2s, 4s, ...
- Max delay: 30s
- Jitter: ±25% randomization

### Rate Limiting

Prevents hitting API rate limits:

```ruby
provider = AiProviders::AnthropicProvider.new(
  config: {
    rate_limit: {
      requests_per_minute: 60,    # RPM limit
      tokens_per_minute: 100_000  # TPM limit
    }
  }
)
```

The rate limiter:
- Tracks requests and tokens in a sliding window
- Automatically throttles when approaching limits
- Logs wait times for debugging

### Error Handling

Consistent error types across all providers:

```ruby
begin
  result = provider.generate_completion(prompt)
rescue AiProviders::ProviderErrors::RateLimitError => e
  # Rate limit exceeded, retry later
rescue AiProviders::ProviderErrors::AuthenticationError => e
  # Invalid API key
rescue AiProviders::ProviderErrors::TimeoutError => e
  # Request timed out
rescue AiProviders::ProviderErrors::ModelNotAvailableError => e
  # Model doesn't exist or unavailable
rescue AiProviders::ProviderErrors::APIError => e
  # Other API error
end
```

## Configuration

### API Keys

Set these environment variables or Rails credentials:

```yaml
# config/credentials.yml.enc
anthropic_api_key: sk-ant-...
openai_api_key: sk-...
```

Or use environment variables:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

### Model Selection

Configure in `ModelSelector` service:

```ruby
# app/services/model_selector.rb

def select_model_for_task(task_type)
  case task_type
  when :intent_analysis
    "claude-3-haiku"        # Fast, cheap
  when :code_generation
    "claude-3-sonnet"       # Balanced
  when :machine_learning
    "gpt-4-turbo"          # Function calling
  when :result_interpretation
    "claude-3-opus"         # Best reasoning
  end
end

def select_model_by_complexity(score)
  case score
  when 1..3
    "claude-3-haiku"        # Simple queries
  when 4..7
    "claude-3-sonnet"       # Medium complexity
  when 8..10
    "claude-3-opus"         # Complex analysis
  end
end
```

## Testing

Run the test suite:

```bash
# Without API calls (mocked)
rails test test/services/ai_providers_test.rb

# With real API calls (requires API keys)
ANTHROPIC_API_KEY=sk-ant-... OPENAI_API_KEY=sk-... \
  rails test test/services/ai_providers_test.rb
```

Tests include:
- ✅ Basic completions
- ✅ Streaming responses
- ✅ Code generation
- ✅ Data requirements analysis
- ✅ Rate limiting
- ✅ Retry logic
- ✅ Error handling
- ✅ Vision support
- ✅ Function calling

## Performance Tips

1. **Choose the right model:**
   - Use Haiku/3.5-Turbo for simple tasks
   - Use Sonnet for balanced performance
   - Use Opus/GPT-4 for complex reasoning

2. **Use streaming for long responses:**
   ```ruby
   provider.generate_completion_stream(prompt) do |chunk|
     ActionCable.server.broadcast("analysis_#{id}", chunk)
   end
   ```

3. **Set appropriate max_tokens:**
   ```ruby
   # Short answers
   provider.generate_completion(prompt, max_tokens: 500)
   
   # Code generation
   provider.generate_completion(prompt, max_tokens: 2000)
   
   # Long analysis
   provider.generate_completion(prompt, max_tokens: 4000)
   ```

4. **Use lower temperature for deterministic tasks:**
   ```ruby
   # Code generation (deterministic)
   provider.generate_code(prompt, temperature: 0.2)
   
   # Creative writing
   provider.generate_completion(prompt, temperature: 0.9)
   ```

5. **Enable caching for repeated queries:**
   The `QueryCacheService` wraps provider calls to cache results.

## Cost Optimization

Approximate costs per 1M tokens:

| Model | Input | Output |
|-------|-------|--------|
| Claude 3 Opus | $15 | $75 |
| Claude 3 Sonnet | $3 | $15 |
| Claude 3 Haiku | $0.25 | $1.25 |
| GPT-4 Turbo | $10 | $30 |
| GPT-4 | $30 | $60 |
| GPT-3.5 Turbo | $0.50 | $1.50 |

Track costs:
```ruby
result = provider.generate_completion(prompt)

cost_per_1k = provider.cost_per_1k_tokens
input_cost = (result[:usage][:input_tokens] / 1000.0) * cost_per_1k[:input]
output_cost = (result[:usage][:output_tokens] / 1000.0) * cost_per_1k[:output]
total_cost = input_cost + output_cost

puts "Cost: $#{total_cost.round(4)}"
```

## Future Enhancements

Planned additions:

- [ ] Google Gemini provider
- [ ] Cohere provider
- [ ] Replicate provider (open source models)
- [ ] Prompt caching (Anthropic)
- [ ] Batch API support (OpenAI)
- [ ] Fine-tuned model support
- [ ] Embeddings support
- [ ] Model performance analytics

## Troubleshooting

### "API key not configured"

Set the appropriate environment variable or Rails credential:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Rate limit errors persist

Reduce the rate_limit config or upgrade your API plan:
```ruby
config: { rate_limit: { requests_per_minute: 30 } }
```

### Timeouts on long operations

Increase timeout (if available) or split into smaller requests:
```ruby
# Use streaming for long responses
provider.generate_completion_stream(long_prompt) do |chunk|
  # Process chunk immediately
end
```

### High costs

- Use cheaper models (Haiku/3.5-Turbo) for simple tasks
- Reduce max_tokens
- Enable caching
- Lower temperature for shorter responses

## Support

For issues or questions:
- Check logs: `Rails.logger` includes all provider calls
- Review error types: `AiProviders::ProviderErrors::*`
- Test individual methods: See test file for examples

# app/services/model_selector.rb
class ModelSelector
  TASK_MODEL_MATRIX = {
    intent_analysis: {
      primary: 'claude-3-sonnet',
      fallback: ['gpt-4', 'claude-3-haiku'],
      requirements: [:reasoning, :context_understanding]
    },
    code_generation: {
      primary: 'claude-3-opus',
      fallback: ['gpt-4-turbo', 'claude-3-sonnet'],
      requirements: [:code_generation, :complex_logic]
    },
    sql_generation: {
      primary: 'gpt-4',
      fallback: ['claude-3-sonnet', 'gpt-3.5-turbo'],
      requirements: [:sql_expertise, :schema_understanding]
    },
    data_exploration: {
      primary: 'claude-3-sonnet',
      fallback: ['gpt-4', 'gemini-pro'],
      requirements: [:data_analysis, :pattern_recognition]
    },
    result_interpretation: {
      primary: 'claude-3-opus',
      fallback: ['gpt-4', 'claude-3-sonnet'],
      requirements: [:reasoning, :communication, :nuance]
    },
    visualization: {
      primary: 'gpt-4-turbo',
      fallback: ['claude-3-sonnet', 'gemini-pro'],
      requirements: [:code_generation, :visual_understanding]
    },
    machine_learning: {
      primary: 'claude-3-opus',
      fallback: ['gpt-4', 'gemini-ultra'],
      requirements: [:ml_expertise, :code_generation, :math]
    }
  }.freeze

  def initialize(user, organization = nil)
    @user = user
    @organization = organization || user.organization
    @available_models = determine_available_models
  end

  def select_model_for_task(task_type, options = {})
    task_config = TASK_MODEL_MATRIX[task_type] || default_task_config
    
    # Check user preferences
    if options[:preferred_model] && model_available?(options[:preferred_model])
      return options[:preferred_model]
    end

    # Try primary model
    primary = task_config[:primary]
    return primary if model_available?(primary) && !exceeds_cost_limit?(primary, options)

    # Try fallback models
    task_config[:fallback].each do |model|
      if model_available?(model) && !exceeds_cost_limit?(model, options)
        return model
      end
    end

    # Return cheapest available model as last resort
    cheapest_available_model
  end

  def select_model_by_complexity(complexity_score)
    case complexity_score
    when 0..3
      select_economical_model
    when 4..6
      select_balanced_model
    when 7..10
      select_powerful_model
    else
      select_balanced_model
    end
  end

  def estimate_cost(model, estimated_tokens)
    provider = provider_for_model(model)
    costs = provider.new(model: model).cost_per_1k_tokens
    
    input_cost = (estimated_tokens[:input] / 1000.0) * costs[:input]
    output_cost = (estimated_tokens[:output] / 1000.0) * costs[:output]
    
    {
      input_cost: input_cost,
      output_cost: output_cost,
      total_cost: input_cost + output_cost,
      model: model
    }
  end

  def recommend_models_for_query(query_analysis)
    recommendations = []

    # Recommend based on query type
    primary_task = determine_primary_task(query_analysis)
    primary_model = select_model_for_task(primary_task)
    
    recommendations << {
      model: primary_model,
      reason: "Best for #{primary_task.to_s.humanize.downcase}",
      estimated_cost: estimate_cost(primary_model, query_analysis[:estimated_tokens])
    }

    # Add economical alternative
    economical = select_economical_model
    if economical != primary_model
      recommendations << {
        model: economical,
        reason: "Cost-effective option",
        estimated_cost: estimate_cost(economical, query_analysis[:estimated_tokens])
      }
    end

    # Add premium option if available
    premium = select_powerful_model
    if premium != primary_model && model_available?(premium)
      recommendations << {
        model: premium,
        reason: "Maximum capability",
        estimated_cost: estimate_cost(premium, query_analysis[:estimated_tokens])
      }
    end

    recommendations
  end

  private

  def determine_available_models
    user_models = @user.available_models
    org_models = @organization&.settings&.dig('allowed_models') || []
    
    # Intersection of user tier models and org allowed models
    available = user_models
    available &= org_models if org_models.any?
    available
  end

  def model_available?(model)
    @available_models.include?(model)
  end

  def exceeds_cost_limit?(model, options)
    return false unless options[:max_cost]
    
    estimated_cost = estimate_cost(model, options[:estimated_tokens] || default_token_estimate)
    estimated_cost[:total_cost] > options[:max_cost]
  end

  def select_economical_model
    economical_models = ['gpt-3.5-turbo', 'claude-3-haiku', 'mixtral-8x7b', 'llama3-8b']
    (economical_models & @available_models).first || @available_models.first
  end

  def select_balanced_model
    balanced_models = ['claude-3-sonnet', 'gpt-4', 'gemini-pro', 'llama3-70b']
    (balanced_models & @available_models).first || select_economical_model
  end

  def select_powerful_model
    powerful_models = ['claude-3-opus', 'gpt-4-turbo', 'gemini-ultra', 'command-r-plus']
    (powerful_models & @available_models).first || select_balanced_model
  end

  def cheapest_available_model
    # Return the cheapest model from available models
    model_costs = @available_models.map do |model|
      provider = provider_for_model(model)
      costs = provider.new(model: model).cost_per_1k_tokens
      [model, costs[:input] + costs[:output]]
    end
    
    model_costs.min_by(&:last)&.first || 'gpt-3.5-turbo'
  end

  def provider_for_model(model)
    case model
    when /claude/
      AiProviders::AnthropicProvider
    when /gpt/
      AiProviders::OpenaiProvider
    when /gemini/
      AiProviders::GoogleProvider
    when /llama/, /mixtral/
      AiProviders::ReplicateProvider
    when /command/
      AiProviders::CohereProvider
    else
      AiProviders::OpenaiProvider # Default
    end
  end

  def determine_primary_task(query_analysis)
    # Analyze the query to determine the primary task type
    query_text = query_analysis[:query].downcase
    
    return :machine_learning if query_text.match?(/predict|forecast|classify|cluster/)
    return :visualization if query_text.match?(/chart|graph|plot|visuali/)
    return :sql_generation if query_text.match?(/sql|query|database/)
    return :result_interpretation if query_text.match?(/explain|interpret|mean/)
    
    :data_exploration # Default
  end

  def default_token_estimate
    { input: 1000, output: 2000 }
  end

  def default_task_config
    {
      primary: 'gpt-3.5-turbo',
      fallback: ['claude-3-haiku', 'mixtral-8x7b'],
      requirements: []
    }
  end
end
# app/services/query_analysis_orchestrator.rb
class QueryAnalysisOrchestrator
  attr_reader :analysis_request, :model_selector, :execution_steps

  def initialize(analysis_request)
    @analysis_request = analysis_request
    @model_selector = ModelSelector.new(analysis_request.user, analysis_request.organization)
    @execution_steps = []
    @total_tokens_used = { input: 0, output: 0 }
    @total_cost = 0.0
    @cache_service = QueryCacheService.new(
      analysis_request.organization,
      analysis_request.dataset,
      { 
        user_id: analysis_request.user.id,
        request_id: analysis_request.id,
        ai_model: analysis_request.model_used,
        skip_cache: analysis_request.user_options&.dig('skip_cache')
      }
    )
  end

  def perform
    Rails.logger.info "Starting analysis for request #{@analysis_request.id}"
    
    # Check cache first
    cached_result = @cache_service.execute_with_cache(@analysis_request.natural_language_query) do
      perform_analysis
    end
    
    if cached_result && cached_result != perform_analysis_result
      Rails.logger.info "Using cached result for request #{@analysis_request.id}"
      @analysis_request.update!(
        final_results: cached_result,
        metadata: @analysis_request.metadata.merge('cache_hit' => true)
      )
      @analysis_request.complete!
      notify_completion
      return cached_result
    end
    
    perform_analysis_result
  end
  
  private
  
  def perform_analysis
    @analysis_request.start_analysis!

    begin
      # Stage 1: Understand the query intent
      analyze_intent

      # Stage 2: Analyze data requirements
      analyze_data_requirements

      # Stage 3: Generate analysis plan
      generate_analysis_plan

      # Stage 4: Execute analysis steps
      execute_analysis_steps

      # Stage 5: Interpret and synthesize results
      interpret_results

      # Complete the analysis
      @analysis_request.complete!
      notify_completion
      
      # Return the final results for caching
      @analysis_request.final_results
      
    rescue => e
      handle_error(e)
      nil
    end
  end
  
  def perform_analysis_result
    @perform_analysis_result ||= perform_analysis
  end

  def analyze_intent
    Rails.logger.info "Stage 1: Analyzing query intent"

    # Select best model for intent analysis
    model = @model_selector.select_model_for_task(:intent_analysis)
    provider = create_provider(model)

    prompt = build_intent_analysis_prompt

    result = provider.generate_completion(prompt, temperature: 0.3, json_mode: true)

    intent_data = JSON.parse(result[:content]) rescue {}

    @analysis_request.update!(
      analyzed_intent: intent_data,
      complexity_score: intent_data["complexity_score"] || 5.0,
      metadata: @analysis_request.metadata.merge(
        "selected_models" => { "intent_analysis" => model }
      )
    )

    track_usage(result[:usage])

    # Check if clarification is needed
    if intent_data["needs_clarification"]
      @analysis_request.request_clarification!
      raise "Query requires clarification: #{intent_data['clarification_needed']}"
    end
  end

  def analyze_data_requirements
    Rails.logger.info "Stage 2: Analyzing data requirements"

    @analysis_request.generate_code!

    model = @model_selector.select_model_for_task(:data_exploration)
    provider = create_provider(model)

    dataset_schema = fetch_dataset_schema

    requirements = provider.analyze_data_requirements(
      @analysis_request.natural_language_query,
      dataset_schema
    )

    @analysis_request.update!(
      data_requirements: requirements,
      metadata: @analysis_request.metadata.merge(
        "selected_models" => @analysis_request.metadata["selected_models"].merge(
          "data_requirements" => model
        )
      )
    )
  end

  def generate_analysis_plan
    Rails.logger.info "Stage 3: Generating analysis plan"

    # Use complexity to select appropriate model
    model = @model_selector.select_model_by_complexity(@analysis_request.complexity_score)
    provider = create_provider(model)

    plan_prompt = build_analysis_plan_prompt

    result = provider.generate_completion(plan_prompt, temperature: 0.5)
    plan = parse_analysis_plan(result[:content])

    # Create execution steps based on plan
    plan["steps"].each_with_index do |step_config, index|
      @execution_steps << create_execution_step(step_config, index)
    end

    track_usage(result[:usage])
  end

  def execute_analysis_steps
    Rails.logger.info "Stage 4: Executing #{@execution_steps.count} analysis steps"

    @analysis_request.execute_code!

    @execution_steps.each do |step|
      execute_single_step(step)
    end
  end

  def execute_single_step(step)
    Rails.logger.info "Executing step: #{step.step_type}"

    # Select model based on step type
    task_type = map_step_type_to_task(step.step_type)
    model = @model_selector.select_model_for_task(task_type)
    provider = create_provider(model)

    # Generate code for this step
    code_prompt = build_code_generation_prompt(step)
    generated_code = provider.generate_code(
      code_prompt,
      language: step.language,
      temperature: 0.2
    )

    step.update!(generated_code: generated_code, status: :validating)

    # Validate the code
    validation_result = validate_generated_code(generated_code, step.language)

    if validation_result[:valid]
      step.update!(status: :executing)

      # Queue for execution in sandboxed environment
      CodeExecutionJob.perform_later(step)

      # Wait for execution to complete (with timeout)
      wait_for_step_completion(step)
    else
      step.update!(
        status: :failed,
        error_message: validation_result[:errors].join(", ")
      )
      raise "Code validation failed: #{validation_result[:errors].join(', ')}"
    end
  end

  def interpret_results
    Rails.logger.info "Stage 5: Interpreting results"

    @analysis_request.interpret_results!

    # Use best model for interpretation
    model = @model_selector.select_model_for_task(:result_interpretation)
    provider = create_provider(model)

    # Gather all results from execution steps
    all_results = gather_execution_results

    interpretation = provider.interpret_results(
      all_results,
      @analysis_request.natural_language_query,
      user_level: @analysis_request.user.technical_level
    )

    # Create final result summary
    create_result_summary(interpretation, all_results)

    @analysis_request.update!(
      metadata: @analysis_request.metadata.merge(
        "interpretation" => interpretation,
        "total_tokens_used" => @total_tokens_used,
        "total_cost" => @total_cost,
        "models_used" => @analysis_request.metadata["selected_models"]
      )
    )
  end

  def create_provider(model)
    case model
    when /claude/
      AiProviders::AnthropicProvider.new(model: model)
    when /gpt/
      AiProviders::OpenaiProvider.new(model: model)
    when /gemini/
      AiProviders::GoogleProvider.new(model: model) # To be implemented
    when /llama/, /mixtral/
      AiProviders::ReplicateProvider.new(model: model) # To be implemented
    when /command/
      AiProviders::CohereProvider.new(model: model) # To be implemented
    else
      AiProviders::OpenaiProvider.new(model: model)
    end
  end

  def build_intent_analysis_prompt
    """
    Analyze this data science query and provide a structured analysis:

    Query: #{@analysis_request.natural_language_query}

    Dataset: #{@analysis_request.dataset.name}
    Dataset Description: #{@analysis_request.dataset.description}

    Provide a JSON response with:
    {
      'query_type': 'statistical|predictive|exploratory|descriptive|diagnostic',
      'main_objective': 'string describing the primary goal',
      'required_analysis_types': ['array of analysis types needed'],
      'identified_entities': ['key entities or variables mentioned'],
      'complexity_score': number between 1-10,
      'estimated_steps': number of steps needed,
      'needs_clarification': boolean,
      'clarification_needed': 'what needs clarification if applicable',
      'suggested_approach': 'brief description of recommended approach'
    }
    """
  end

  def build_analysis_plan_prompt
    """
    Create a detailed analysis plan for this query:

    Query: #{@analysis_request.natural_language_query}
    Intent: #{@analysis_request.analyzed_intent.to_json}
    Data Requirements: #{@analysis_request.data_requirements.to_json}
    User Level: #{@analysis_request.user.technical_level}

    Generate a step-by-step plan with specific analysis steps.
    Each step should specify:
    - Step type (exploration, cleaning, analysis, visualization, etc.)
    - Programming language to use
    - Specific techniques or algorithms
    - Expected outputs

    Format as structured text that can be parsed.
    """
  end

  def build_code_generation_prompt(step)
    """
    Generate #{step.language} code for the following analysis step:

    Step Type: #{step.step_type}
    Step Description: #{step.description}

    Data Context:
    #{fetch_data_context_for_step(step)}

    Previous Results:
    #{fetch_previous_results(step)}

    Requirements:
    - Production-ready code with error handling
    - Well-commented for clarity
    - Optimized for performance
    - Save outputs in standard formats

    Generate only the code, no explanations.
    """
  end

  def fetch_dataset_schema
    @analysis_request.dataset.schema_metadata || {}
  end

  def fetch_data_context_for_step(step)
    # Get relevant schema and sample data for the step
    @analysis_request.dataset.schema_metadata.slice("tables", "columns", "row_counts")
  end

  def fetch_previous_results(step)
    # Get results from previous steps if needed
    previous_steps = @execution_steps.select { |s| s.completed? }
    previous_steps.map { |s| { type: s.step_type, summary: s.result_data } }
  end

  def parse_analysis_plan(plan_text)
    # Parse the plan text into structured steps
    # This would be more sophisticated in production
    {
      "steps" => [
        {
          "type" => "data_exploration",
          "language" => "python",
          "description" => "Initial data exploration and summary statistics"
        },
        {
          "type" => "statistical_analysis",
          "language" => "python",
          "description" => "Perform required statistical analysis"
        },
        {
          "type" => "visualization",
          "language" => "python",
          "description" => "Create visualizations of results"
        }
      ]
    }
  end

  def create_execution_step(step_config, index)
    @analysis_request.execution_steps.create!(
      step_type: step_config["type"],
      language: step_config["language"] || "python",
      description: step_config["description"],
      sequence_number: index,
      status: :pending
    )
  end

  def validate_generated_code(code, language)
    validator = CodeValidator.new(code, language)
    validator.validate
  end

  def wait_for_step_completion(step, timeout: 60.seconds)
    start_time = Time.current

    while step.reload.status_executing? && (Time.current - start_time) < timeout
      sleep 2
    end

    if step.status_executing?
      step.update!(status: :timeout, error_message: "Execution timeout")
      raise "Step execution timeout"
    end

    raise "Step failed: #{step.error_message}" if step.status_failed?
  end

  def gather_execution_results
    @execution_steps.map do |step|
      {
        step_type: step.step_type,
        results: step.result_data,
        visualizations: step.visualizations.map(&:url),
        execution_time: step.duration_seconds
      }
    end
  end

  def create_result_summary(interpretation, results)
    # Create a comprehensive summary document
    summary = {
      query: @analysis_request.natural_language_query,
      interpretation: interpretation,
      detailed_results: results,
      execution_time: @execution_steps.sum(&:duration_seconds),
      models_used: @analysis_request.metadata["selected_models"],
      total_cost: @total_cost
    }

    # Store as attachment or in database
    @analysis_request.update!(final_results: summary)
  end

  def map_step_type_to_task(step_type)
    case step_type
    when "machine_learning", "model_evaluation"
      :machine_learning
    when "visualization"
      :visualization
    when "data_exploration", "data_cleaning", "feature_engineering"
      :data_exploration
    when "statistical_analysis"
      :code_generation
    else
      :code_generation
    end
  end

  def track_usage(usage_data)
    @total_tokens_used[:input] += usage_data[:input_tokens] || 0
    @total_tokens_used[:output] += usage_data[:output_tokens] || 0

    # Calculate cost based on model and tokens
    # This would use actual pricing data
    @total_cost += calculate_cost(usage_data)
  end

  def calculate_cost(usage_data)
    # Simplified cost calculation
    input_cost = (usage_data[:input_tokens] || 0) * 0.00001
    output_cost = (usage_data[:output_tokens] || 0) * 0.00003
    input_cost + output_cost
  end

  def handle_error(error)
    Rails.logger.error "Analysis failed: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")

    @analysis_request.fail!(error.message)

    notify_failure(error)
  end

  def notify_completion
    Rails.logger.info "Analysis completed successfully"
    # Notification handled by model callbacks
  end

  def notify_failure(error)
    Rails.logger.error "Notifying user of failure"
    # Notification handled by model callbacks
  end
end

# frozen_string_literal: true

# ResultInterpreter: Comprehensive service for interpreting code execution results
# 
# This service transforms raw execution outputs into actionable insights by:
# - Aggregating results from multiple execution steps
# - Using AI to generate natural language interpretations
# - Recommending appropriate visualizations
# - Providing statistical summaries and business implications
# - Handling errors and partial results gracefully
#
# @example Basic usage
#   interpreter = ResultInterpreter.new(analysis_request)
#   interpretation = interpreter.interpret
#   # => {
#   #   summary: "...",
#   #   key_insights: [...],
#   #   visualizations: [...],
#   #   recommendations: [...],
#   #   statistics: {...},
#   #   warnings: [...]
#   # }
#
# @example With custom AI provider
#   interpreter = ResultInterpreter.new(analysis_request, ai_provider: custom_provider)
#   interpretation = interpreter.interpret(user_level: :expert)

class ResultInterpreter
  # Statistical significance thresholds
  SIGNIFICANCE_LEVELS = {
    highly_significant: 0.01,
    significant: 0.05,
    marginally_significant: 0.10
  }.freeze

  # Chart type recommendations based on data characteristics
  CHART_RECOMMENDATIONS = {
    temporal: %w[line area],
    categorical: %w[bar column pie],
    continuous: %w[scatter histogram density],
    comparison: %w[bar grouped_bar],
    distribution: %w[histogram box violin],
    correlation: %w[scatter heatmap],
    geographic: %w[map choropleth],
    hierarchical: %w[treemap sunburst]
  }.freeze

  attr_reader :analysis_request, :execution_steps, :ai_provider, :errors, :warnings

  # Initialize the interpreter with an analysis request
  #
  # @param analysis_request [AnalysisRequest] The analysis request to interpret
  # @param ai_provider [AiProviders::BaseProvider] Optional AI provider (auto-selected if not provided)
  def initialize(analysis_request, ai_provider: nil)
    @analysis_request = analysis_request
    @execution_steps = analysis_request.execution_steps.order(:id)
    @ai_provider = ai_provider
    @errors = []
    @warnings = []
  end

  # Main interpretation method - coordinates all interpretation steps
  #
  # @param options [Hash] Interpretation options
  # @option options [Symbol] :user_level User technical level (:beginner, :intermediate, :expert)
  # @option options [Boolean] :include_code Include code snippets in interpretation
  # @option options [Boolean] :detailed Extended analysis with more detail
  # @return [Hash] Comprehensive interpretation result
  def interpret(options = {})
    # Aggregate all execution results
    aggregated_results = aggregate_results

    # Early return if no successful results
    if aggregated_results[:successful_steps].empty?
      return handle_all_failed_results(aggregated_results)
    end

    # Generate AI-powered interpretation
    ai_interpretation = generate_ai_interpretation(aggregated_results, options)

    # Recommend visualizations
    visualization_recommendations = recommend_visualizations(aggregated_results)

    # Extract statistical summaries
    statistical_summary = extract_statistical_summary(aggregated_results)

    # Generate business implications
    business_implications = extract_business_implications(ai_interpretation)

    # Compile final interpretation
    {
      summary: ai_interpretation[:summary],
      direct_answer: ai_interpretation[:direct_answer],
      key_insights: ai_interpretation[:key_insights] || [],
      statistical_summary: statistical_summary,
      visualizations: visualization_recommendations,
      business_implications: business_implications,
      recommendations: ai_interpretation[:recommendations] || [],
      limitations: ai_interpretation[:limitations] || [],
      confidence_score: calculate_confidence_score(aggregated_results),
      execution_metadata: build_execution_metadata(aggregated_results),
      errors: @errors,
      warnings: @warnings,
      raw_ai_response: ai_interpretation[:raw_response]
    }
  rescue => e
    Rails.logger.error "Result interpretation failed: #{e.message}\n#{e.backtrace.join("\n")}"
    @errors << "Interpretation error: #{e.message}"
    {
      summary: "Unable to generate full interpretation due to an error.",
      direct_answer: "Error occurred during interpretation",
      key_insights: [],
      statistical_summary: {},
      visualizations: [],
      business_implications: [],
      recommendations: [],
      limitations: ["Interpretation error prevented full analysis"],
      confidence_score: 0.0,
      execution_metadata: {},
      errors: @errors,
      warnings: @warnings,
      raw_ai_response: nil
    }
  end

  private

  # Aggregate results from all execution steps into a structured format
  #
  # @return [Hash] Aggregated results with successful/failed steps categorized
  def aggregate_results
    results = {
      successful_steps: [],
      failed_steps: [],
      total_execution_time: 0,
      data_tables: [],
      charts: [],
      statistics: [],
      model_metrics: []
    }

    @execution_steps.each do |step|
      results[:total_execution_time] += step.duration_seconds || 0

      if step.status_completed?
        results[:successful_steps] << format_step_result(step)
        
        # Extract structured data
        results[:data_tables] << step.result_data["tables"] if step.result_data&.dig("tables")
        results[:charts] << step.result_data["charts"] if step.result_data&.dig("charts")
        results[:statistics] << step.result_data["statistics"] if step.result_data&.dig("statistics")
        results[:model_metrics] << step.result_data["model_metrics"] if step.result_data&.dig("model_metrics")
      else
        results[:failed_steps] << format_failed_step(step)
        @warnings << "Step #{step.id} (#{step.step_type}) failed: #{step.error_message}"
      end
    end

    # Flatten and clean arrays - check for empty to avoid compact! on nil
    results[:data_tables] = results[:data_tables].flatten.compact
    results[:charts] = results[:charts].flatten.compact
    results[:statistics] = results[:statistics].flatten.compact
    results[:model_metrics] = results[:model_metrics].flatten.compact

    results
  end

  # Format a successful execution step for interpretation
  #
  # @param step [ExecutionStep] The execution step to format
  # @return [Hash] Formatted step information
  def format_step_result(step)
    {
      sequence: step.id,
      type: step.step_type,
      language: step.language,
      output: step.result_data&.dig("output"),
      tables: step.result_data&.dig("tables"),
      charts: step.result_data&.dig("charts"),
      statistics: step.result_data&.dig("statistics"),
      model_metrics: step.result_data&.dig("model_metrics"),
      execution_time: step.duration_seconds,
      resource_usage: step.resource_usage
    }
  end

  # Format a failed execution step
  #
  # @param step [ExecutionStep] The failed execution step
  # @return [Hash] Formatted failure information
  def format_failed_step(step)
    {
      sequence: step.id,
      type: step.step_type,
      language: step.language,
      status: step.status,
      error_message: step.error_message,
      attempted_at: step.started_at
    }
  end

  # Generate AI-powered interpretation of the results
  #
  # @param results [Hash] Aggregated results
  # @param options [Hash] Interpretation options
  # @return [Hash] AI-generated interpretation
  def generate_ai_interpretation(results, options = {})
    provider = @ai_provider || select_ai_provider
    user_level = options[:user_level] || @analysis_request.user&.technical_level || :intermediate

    prompt = build_comprehensive_interpretation_prompt(results, options)

    begin
      response = provider.interpret_results(
        results,
        @analysis_request.natural_language_query,
        user_level: user_level
      )

      # Parse structured response (assuming JSON format from AI)
      parsed_response = parse_ai_response(response)
      
      parsed_response.merge(raw_response: response)
    rescue => e
      Rails.logger.error "AI interpretation failed: #{e.message}"
      @errors << "AI interpretation error: #{e.message}"
      {
        summary: generate_fallback_summary(results),
        direct_answer: "Unable to generate AI interpretation",
        key_insights: extract_basic_insights(results),
        recommendations: [],
        limitations: ["AI interpretation unavailable"],
        raw_response: nil
      }
    end
  end

  # Build a comprehensive prompt for AI interpretation
  #
  # @param results [Hash] Aggregated results
  # @param options [Hash] Prompt options
  # @return [String] The constructed prompt
  def build_comprehensive_interpretation_prompt(results, options)
    # Get dataset info - AnalysisRequest belongs_to :dataset
    dataset = @analysis_request.dataset
    dataset_info = if dataset
      summary = dataset.schema_summary
      if summary.is_a?(Hash)
        "- #{dataset.name}: #{summary['total_columns'] || 'N/A'} columns, #{summary['total_rows'] || 'N/A'} rows"
      else
        "- #{dataset.name}: #{summary}"
      end
    else
      "No dataset information available"
    end

    <<~PROMPT
      You are analyzing results from a data analysis pipeline. Provide a comprehensive interpretation.

      ORIGINAL QUESTION:
      #{@analysis_request.natural_language_query}

      DATASET INFORMATION:
      #{dataset_info}

      ANALYSIS CONTEXT:
      - Total execution steps: #{@execution_steps.count}
      - Successful steps: #{results[:successful_steps].count}
      - Failed steps: #{results[:failed_steps].count}
      - Total execution time: #{results[:total_execution_time].round(2)}s

      EXECUTION RESULTS:
      #{format_results_for_prompt(results)}

      Please provide your interpretation in the following JSON structure:
      {
        "direct_answer": "Clear, concise answer to the original question",
        "summary": "2-3 sentence executive summary of findings",
        "key_insights": [
          "Specific insight 1 with supporting data",
          "Specific insight 2 with supporting data",
          "Specific insight 3 with supporting data"
        ],
        "statistical_significance": {
          "findings": "Description of statistical significance",
          "p_values": "Any relevant p-values or confidence intervals",
          "effect_sizes": "Practical significance of findings"
        },
        "business_implications": [
          "Actionable business implication 1",
          "Actionable business implication 2"
        ],
        "recommendations": [
          "Specific recommendation 1 with rationale",
          "Specific recommendation 2 with rationale"
        ],
        "limitations": [
          "Limitation of analysis 1",
          "Limitation of analysis 2"
        ],
        "confidence_level": "high|medium|low - your confidence in these results"
      }

      INTERPRETATION GUIDELINES:
      - Use #{options[:user_level] || 'intermediate'} level technical language
      - Focus on actionable insights, not just describing what was done
      - Highlight statistical significance where applicable
      - Be specific with numbers and percentages
      - Explain causation vs correlation carefully
      - Note any surprising or counterintuitive findings
      - Suggest follow-up analyses if appropriate
    PROMPT
  end

  # Format results for inclusion in AI prompt
  #
  # @param results [Hash] Aggregated results
  # @return [String] Formatted results text
  def format_results_for_prompt(results)
    output = []

    results[:successful_steps].each do |step|
      output << "Step #{step[:sequence]} (#{step[:type]}):"
      output << "  Output: #{step[:output]}" if step[:output].present?
      output << "  Tables: #{step[:tables].to_json}" if step[:tables].present?
      output << "  Statistics: #{step[:statistics].to_json}" if step[:statistics].present?
      output << "  Model Metrics: #{step[:model_metrics].to_json}" if step[:model_metrics].present?
      output << ""
    end

    unless results[:failed_steps].empty?
      output << "FAILED STEPS:"
      results[:failed_steps].each do |step|
        output << "  Step #{step[:sequence]} (#{step[:type]}): #{step[:error_message]}"
      end
    end

    output.join("\n")
  end

  # Parse AI response, handling various formats
  #
  # @param response [String] Raw AI response
  # @return [Hash] Parsed response
  def parse_ai_response(response)
    # Try to parse as JSON first
    if response.is_a?(String)
      # Extract JSON from markdown code blocks or plain text
      json_match = response.match(/```json\s*(\{.*?\})\s*```/m) || 
                   response.match(/(\{.*\})/m)
      
      if json_match
        JSON.parse(json_match[1])
      else
        # Fallback: treat as plain text summary
        {
          summary: response,
          direct_answer: response.split("\n").first,
          key_insights: response.split("\n").select { |line| line.match?(/^[-*]/) },
          recommendations: [],
          limitations: []
        }
      end
    else
      # Already parsed or structured response
      response
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "Failed to parse AI response as JSON: #{e.message}"
    {
      summary: response.to_s,
      direct_answer: "See summary",
      key_insights: [],
      recommendations: [],
      limitations: []
    }
  end

  # Recommend visualizations based on result characteristics
  #
  # @param results [Hash] Aggregated results
  # @return [Array<Hash>] Visualization recommendations
  def recommend_visualizations(results)
    recommendations = []

    # Analyze result types and suggest appropriate charts
    results[:statistics].each do |stat|
      recommendations.concat(suggest_charts_for_statistics(stat))
    end

    results[:data_tables].each do |table|
      recommendations.concat(suggest_charts_for_table(table))
    end

    # Include existing charts from execution
    results[:charts].each do |chart|
      recommendations << {
        type: "existing",
        chart_type: chart["type"],
        title: chart["title"],
        data: chart["data"],
        description: chart["description"]
      }
    end

    recommendations.uniq { |r| [r[:chart_type], r[:title]] }
  end

  # Suggest charts for statistical data
  #
  # @param stat [Hash] Statistical data
  # @return [Array<Hash>] Chart recommendations
  def suggest_charts_for_statistics(stat)
    charts = []

    # Distribution visualization
    if stat.key?("mean") && stat.key?("std")
      charts << {
        chart_type: "histogram",
        title: "Distribution of #{stat['variable'] || 'Values'}",
        description: "Shows the frequency distribution",
        config: { bins: 30, show_normal_curve: true }
      }
    end

    # Correlation heatmap
    if stat.key?("correlation_matrix")
      charts << {
        chart_type: "heatmap",
        title: "Correlation Matrix",
        description: "Shows relationships between variables",
        config: { colorscale: "RdBu", symmetric: true }
      }
    end

    charts
  end

  # Suggest charts for tabular data
  #
  # @param table [Hash] Table data
  # @return [Array<Hash>] Chart recommendations
  def suggest_charts_for_table(table)
    return [] unless table.is_a?(Hash) && table["columns"] && table["data"]

    charts = []
    columns = table["columns"]
    data = table["data"]

    # Time series detection
    time_cols = columns.select { |c| c.match?(/date|time|year|month/i) }
    if time_cols.any?
      numeric_cols = detect_numeric_columns(table)
      numeric_cols.each do |col|
        charts << {
          chart_type: "line",
          title: "#{col} over time",
          description: "Temporal trend analysis",
          config: { x_axis: time_cols.first, y_axis: col }
        }
      end
    end

    # Categorical comparison
    categorical_cols = detect_categorical_columns(table)
    if categorical_cols.any?
      charts << {
        chart_type: "bar",
        title: "Comparison by #{categorical_cols.first}",
        description: "Compare values across categories",
        config: { x_axis: categorical_cols.first }
      }
    end

    charts
  end

  # Extract statistical summary from results
  #
  # @param results [Hash] Aggregated results
  # @return [Hash] Statistical summary
  def extract_statistical_summary(results)
    summary = {
      total_steps: @execution_steps.count,
      successful_steps: results[:successful_steps].count,
      failed_steps: results[:failed_steps].count,
      execution_time: results[:total_execution_time].round(2),
      data_points_analyzed: count_data_points(results),
      statistical_tests_performed: results[:statistics].count,
      visualizations_generated: results[:charts].count
    }

    # Extract key statistical values
    if results[:statistics].any?
      summary[:key_statistics] = extract_key_statistics(results[:statistics])
    end

    summary
  end

  # Extract key statistics from statistical results
  #
  # @param statistics [Array<Hash>] Statistical results
  # @return [Hash] Key statistics
  def extract_key_statistics(statistics)
    key_stats = {}

    statistics.each do |stat|
      # P-values for significance testing
      if stat.key?("p_value")
        key_stats[:significant_results] ||= []
        level = determine_significance_level(stat["p_value"])
        if level
          key_stats[:significant_results] << {
            test: stat["test_name"] || "unknown",
            p_value: stat["p_value"],
            significance: level
          }
        end
      end

      # Effect sizes
      if stat.key?("effect_size") || stat.key?("r_squared")
        key_stats[:effect_sizes] ||= []
        key_stats[:effect_sizes] << {
          metric: stat["effect_size"] || stat["r_squared"],
          interpretation: interpret_effect_size(stat["effect_size"] || stat["r_squared"])
        }
      end
    end

    key_stats
  end

  # Determine statistical significance level
  #
  # @param p_value [Float] P-value from statistical test
  # @return [Symbol, nil] Significance level or nil if not significant
  def determine_significance_level(p_value)
    return nil unless p_value.is_a?(Numeric)

    SIGNIFICANCE_LEVELS.each do |level, threshold|
      return level if p_value < threshold
    end

    nil
  end

  # Interpret effect size magnitude
  #
  # @param effect_size [Float] Effect size value
  # @return [String] Interpretation
  def interpret_effect_size(effect_size)
    return "unknown" unless effect_size.is_a?(Numeric)

    case effect_size.abs
    when 0...0.2
      "negligible"
    when 0.2...0.5
      "small"
    when 0.5...0.8
      "medium"
    else
      "large"
    end
  end

  # Extract business implications from AI interpretation
  #
  # @param ai_interpretation [Hash] AI-generated interpretation
  # @return [Array<String>] Business implications
  def extract_business_implications(ai_interpretation)
    implications = ai_interpretation[:business_implications] || []
    
    # If AI didn't provide implications, generate basic ones
    if implications.empty?
      implications << "Review the key insights for actionable takeaways"
      implications << "Consider the recommendations for next steps"
    end

    implications
  end

  # Calculate confidence score based on result quality
  #
  # @param results [Hash] Aggregated results
  # @return [Float] Confidence score between 0 and 1
  def calculate_confidence_score(results)
    score = 1.0

    # Penalize for failed steps
    failure_rate = results[:failed_steps].count.to_f / @execution_steps.count
    score -= (failure_rate * 0.3)

    # Penalize for missing data
    score -= 0.1 if results[:data_tables].empty?
    score -= 0.1 if results[:statistics].empty?

    # Boost for comprehensive results
    score += 0.1 if results[:model_metrics].any?

    [score, 0.0].max.round(2)
  end

  # Build execution metadata summary
  #
  # @param results [Hash] Aggregated results
  # @return [Hash] Execution metadata
  def build_execution_metadata(results)
    {
      total_steps: @execution_steps.count,
      successful_steps: results[:successful_steps].count,
      failed_steps: results[:failed_steps].count,
      total_execution_time: results[:total_execution_time].round(2),
      average_step_time: (results[:total_execution_time] / @execution_steps.count).round(2),
      languages_used: @execution_steps.map(&:language).uniq,
      step_types: @execution_steps.map(&:step_type).uniq
    }
  end

  # Handle case where all steps failed
  #
  # @param results [Hash] Aggregated results
  # @return [Hash] Failure interpretation
  def handle_all_failed_results(results)
    {
      summary: "All analysis steps failed to execute successfully.",
      direct_answer: "Unable to complete analysis due to execution failures",
      key_insights: [],
      statistical_summary: extract_statistical_summary(results),
      visualizations: [],
      business_implications: ["Review error messages and retry analysis"],
      recommendations: [
        "Check dataset quality and completeness",
        "Verify analysis parameters",
        "Review execution logs for specific errors"
      ],
      limitations: ["Complete analysis failure prevented interpretation"],
      confidence_score: 0.0,
      execution_metadata: build_execution_metadata(results),
      errors: results[:failed_steps].map { |s| s[:error_message] },
      warnings: @warnings
    }
  end

  # Generate fallback summary when AI interpretation fails
  #
  # @param results [Hash] Aggregated results
  # @return [String] Fallback summary
  def generate_fallback_summary(results)
    "Completed #{results[:successful_steps].count} of #{@execution_steps.count} analysis steps " \
    "in #{results[:total_execution_time].round(2)} seconds. " \
    "Generated #{results[:data_tables].count} data tables and #{results[:charts].count} visualizations."
  end

  # Extract basic insights when AI interpretation unavailable
  #
  # @param results [Hash] Aggregated results
  # @return [Array<String>] Basic insights
  def extract_basic_insights(results)
    insights = []

    insights << "Analyzed data across #{@execution_steps.count} computational steps"
    
    if results[:statistics].any?
      insights << "Performed #{results[:statistics].count} statistical analysis steps"
    end

    if results[:data_tables].any?
      insights << "Generated #{results[:data_tables].count} result tables"
    end

    insights
  end

  # Count total data points analyzed
  #
  # @param results [Hash] Aggregated results
  # @return [Integer] Total data points
  def count_data_points(results)
    count = 0

    results[:data_tables].each do |table|
      count += table["data"]&.count || 0 if table.is_a?(Hash)
    end

    count
  end

  # Detect numeric columns in a table
  #
  # @param table [Hash] Table data
  # @return [Array<String>] Numeric column names
  def detect_numeric_columns(table)
    return [] unless table["data"]&.any?

    table["columns"].select do |col|
      sample_values = table["data"].first(10).map { |row| row[col] }.compact
      sample_values.all? { |v| v.is_a?(Numeric) }
    end
  end

  # Detect categorical columns in a table
  #
  # @param table [Hash] Table data
  # @return [Array<String>] Categorical column names
  def detect_categorical_columns(table)
    return [] unless table["data"]&.any?

    table["columns"].select do |col|
      sample_values = table["data"].first(100).map { |row| row[col] }.compact
      unique_count = sample_values.uniq.count
      # Consider categorical if: string type and < 20 unique values
      sample_values.first.is_a?(String) && unique_count < 20
    end
  end

  # Select appropriate AI provider based on task requirements
  #
  # @return [AiProviders::BaseProvider] Selected AI provider
  def select_ai_provider
    model_selector = ModelSelector.new
    model = model_selector.select_model_for_task(:result_interpretation)

    case model
    when /claude/
      AiProviders::AnthropicProvider.new(model: model)
    when /gpt/
      AiProviders::OpenaiProvider.new(model: model)
    else
      AiProviders::OpenaiProvider.new(model: model)
    end
  end
end

# app/services/visualization_service.rb
class VisualizationService
  attr_reader :analysis_request, :execution_step

  def initialize(analysis_request, execution_step = nil)
    @analysis_request = analysis_request
    @execution_step = execution_step
  end

  def generate_chart_data
    return default_chart_data unless @execution_step&.result_data.present?
    
    result_type = detect_result_type(@execution_step.result_data)
    
    case result_type
    when :time_series
      generate_time_series_chart
    when :categorical
      generate_categorical_chart
    when :distribution
      generate_distribution_chart
    when :correlation
      generate_correlation_chart
    when :comparison
      generate_comparison_chart
    else
      default_chart_data
    end
  end

  def generate_summary_charts
    charts = []
    
    # Execution time chart
    if @analysis_request.execution_steps.any?
      charts << {
        id: "execution_time_chart",
        type: "bar",
        data: execution_time_data,
        options: execution_time_options
      }
    end
    
    # Complexity breakdown
    if @analysis_request.analyzed_intent.present?
      charts << {
        id: "complexity_chart",
        type: "doughnut",
        data: complexity_data,
        options: complexity_options
      }
    end
    
    # Token usage
    if @analysis_request.metadata&.dig('total_tokens_used').present?
      charts << {
        id: "token_usage_chart",
        type: "pie",
        data: token_usage_data,
        options: token_usage_options
      }
    end
    
    charts
  end

  private

  def detect_result_type(result_data)
    # Analyze the structure of result data to determine visualization type
    return :time_series if result_data.is_a?(Hash) && result_data.keys.any? { |k| k.to_s.match?(/date|time/i) }
    return :distribution if result_data.is_a?(Array) && result_data.first.is_a?(Numeric)
    return :categorical if result_data.is_a?(Hash) && result_data.values.all? { |v| v.is_a?(Numeric) }
    return :comparison if result_data.is_a?(Array) && result_data.first.is_a?(Hash)
    :default
  end

  def generate_time_series_chart
    {
      type: 'line',
      data: {
        labels: extract_time_labels(@execution_step.result_data),
        datasets: [{
          label: 'Values over Time',
          data: extract_time_values(@execution_step.result_data),
          borderColor: 'rgb(102, 126, 234)',
          backgroundColor: 'rgba(102, 126, 234, 0.1)',
          tension: 0.1
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { position: 'top' },
          title: { display: true, text: 'Time Series Analysis' }
        },
        scales: {
          y: { beginAtZero: true }
        }
      }
    }
  end

  def generate_categorical_chart
    {
      type: 'bar',
      data: {
        labels: @execution_step.result_data.keys.map(&:to_s),
        datasets: [{
          label: 'Values',
          data: @execution_step.result_data.values,
          backgroundColor: [
            'rgba(102, 126, 234, 0.6)',
            'rgba(118, 75, 162, 0.6)',
            'rgba(237, 100, 166, 0.6)',
            'rgba(144, 205, 244, 0.6)',
            'rgba(248, 150, 30, 0.6)'
          ],
          borderColor: [
            'rgb(102, 126, 234)',
            'rgb(118, 75, 162)',
            'rgb(237, 100, 166)',
            'rgb(144, 205, 244)',
            'rgb(248, 150, 30)'
          ],
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false },
          title: { display: true, text: 'Categorical Analysis' }
        },
        scales: {
          y: { beginAtZero: true }
        }
      }
    }
  end

  def generate_distribution_chart
    {
      type: 'histogram',
      data: {
        datasets: [{
          label: 'Distribution',
          data: @execution_step.result_data,
          backgroundColor: 'rgba(102, 126, 234, 0.6)',
          borderColor: 'rgb(102, 126, 234)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false },
          title: { display: true, text: 'Data Distribution' }
        },
        scales: {
          y: { beginAtZero: true }
        }
      }
    }
  end

  def generate_correlation_chart
    {
      type: 'scatter',
      data: {
        datasets: [{
          label: 'Correlation',
          data: format_correlation_data(@execution_step.result_data),
          backgroundColor: 'rgba(102, 126, 234, 0.6)'
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { position: 'top' },
          title: { display: true, text: 'Correlation Analysis' }
        },
        scales: {
          x: { type: 'linear', position: 'bottom' },
          y: { beginAtZero: true }
        }
      }
    }
  end

  def generate_comparison_chart
    {
      type: 'radar',
      data: {
        labels: extract_comparison_labels(@execution_step.result_data),
        datasets: extract_comparison_datasets(@execution_step.result_data)
      },
      options: {
        responsive: true,
        plugins: {
          legend: { position: 'top' },
          title: { display: true, text: 'Comparative Analysis' }
        },
        scales: {
          r: {
            angleLines: { display: false },
            suggestedMin: 0,
            suggestedMax: 100
          }
        }
      }
    }
  end

  def execution_time_data
    steps = @analysis_request.execution_steps.order(:sequence_number)
    {
      labels: steps.map { |s| s.step_type.humanize },
      datasets: [{
        label: 'Execution Time (ms)',
        data: steps.map { |s| s.execution_time_ms || 0 },
        backgroundColor: 'rgba(102, 126, 234, 0.6)',
        borderColor: 'rgb(102, 126, 234)',
        borderWidth: 1
      }]
    }
  end

  def execution_time_options
    {
      responsive: true,
      plugins: {
        legend: { display: false },
        title: { 
          display: true, 
          text: 'Step Execution Times'
        }
      },
      scales: {
        y: { 
          beginAtZero: true,
          title: {
            display: true,
            text: 'Time (milliseconds)'
          }
        }
      }
    }
  end

  def complexity_data
    intent = @analysis_request.analyzed_intent
    {
      labels: ['Simple', 'Moderate', 'Complex'],
      datasets: [{
        data: [
          intent['complexity_score'] < 4 ? intent['complexity_score'] * 25 : 0,
          intent['complexity_score'].between?(4, 7) ? intent['complexity_score'] * 14 : 0,
          intent['complexity_score'] > 7 ? intent['complexity_score'] * 10 : 0
        ],
        backgroundColor: [
          'rgba(34, 197, 94, 0.6)',
          'rgba(251, 146, 60, 0.6)',
          'rgba(239, 68, 68, 0.6)'
        ],
        borderColor: [
          'rgb(34, 197, 94)',
          'rgb(251, 146, 60)',
          'rgb(239, 68, 68)'
        ],
        borderWidth: 1
      }]
    }
  end

  def complexity_options
    {
      responsive: true,
      plugins: {
        legend: { position: 'bottom' },
        title: { 
          display: true, 
          text: 'Analysis Complexity'
        }
      }
    }
  end

  def token_usage_data
    tokens = @analysis_request.metadata['total_tokens_used']
    {
      labels: ['Input Tokens', 'Output Tokens'],
      datasets: [{
        data: [tokens['input'] || 0, tokens['output'] || 0],
        backgroundColor: [
          'rgba(102, 126, 234, 0.6)',
          'rgba(118, 75, 162, 0.6)'
        ],
        borderColor: [
          'rgb(102, 126, 234)',
          'rgb(118, 75, 162)'
        ],
        borderWidth: 1
      }]
    }
  end

  def token_usage_options
    {
      responsive: true,
      plugins: {
        legend: { position: 'bottom' },
        title: { 
          display: true, 
          text: 'Token Usage'
        }
      }
    }
  end

  def default_chart_data
    {
      type: 'bar',
      data: {
        labels: ['No Data'],
        datasets: [{
          label: 'No visualization data available',
          data: [0],
          backgroundColor: 'rgba(156, 163, 175, 0.6)'
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false },
          title: { 
            display: true, 
            text: 'Visualization will appear here when data is available'
          }
        }
      }
    }
  end

  def extract_time_labels(data)
    # Extract time-based keys from the data
    data.select { |k, _| k.to_s.match?(/date|time/i) }.keys.map(&:to_s)
  end

  def extract_time_values(data)
    # Extract corresponding values for time series
    data.select { |k, _| k.to_s.match?(/date|time/i) }.values
  end

  def format_correlation_data(data)
    # Format data for scatter plot
    return [] unless data.is_a?(Array) || data.is_a?(Hash)
    
    if data.is_a?(Array)
      data.map.with_index { |v, i| { x: i, y: v } }
    else
      data.map { |k, v| { x: k.to_s.hash % 100, y: v } }
    end
  end

  def extract_comparison_labels(data)
    return [] unless data.is_a?(Array) && data.first.is_a?(Hash)
    data.first.keys.map(&:to_s)
  end

  def extract_comparison_datasets(data)
    return [] unless data.is_a?(Array)
    
    data.map.with_index do |item, index|
      {
        label: "Dataset #{index + 1}",
        data: item.values,
        borderColor: "rgba(#{102 + index * 20}, #{126 - index * 10}, #{234 - index * 30}, 1)",
        backgroundColor: "rgba(#{102 + index * 20}, #{126 - index * 10}, #{234 - index * 30}, 0.2)"
      }
    end
  end
end
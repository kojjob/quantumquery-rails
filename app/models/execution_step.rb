class ExecutionStep < ApplicationRecord
  # Associations
  belongs_to :analysis_request
  has_one_attached :code_file
  has_one_attached :output_file
  has_many_attached :visualizations # Charts, graphs, etc.
  
  # Validations
  validates :step_type, presence: true
  validates :language, presence: true
  
  # Enums
  enum :step_type, {
    data_exploration: 0,
    data_cleaning: 1,
    statistical_analysis: 2,
    visualization: 3,
    machine_learning: 4,
    feature_engineering: 5,
    model_evaluation: 6,
    custom_computation: 7,
    result_interpretation: 8
  }, prefix: true
  
  enum :language, {
    python: 0,
    r: 1,
    sql: 2,
    julia: 3,
    javascript: 4
  }, prefix: true
  
  enum :status, {
    pending: 0,
    generating: 1,
    validating: 2,
    executing: 3,
    completed: 4,
    failed: 5,
    timeout: 6
  }, prefix: true
  
  # Store execution details in JSONB
  store_accessor :result_data, :output, :tables, :charts, :statistics, :model_metrics
  store_accessor :resource_usage, :cpu_time_ms, :memory_mb, :execution_time_ms, :container_id
  
  # Scopes
  scope :successful, -> { where(status: :completed) }
  scope :failed, -> { where(status: [:failed, :timeout]) }
  scope :by_type, ->(type) { where(step_type: type) }
  
  def duration_seconds
    return nil unless completed_at && started_at
    (completed_at - started_at).to_f
  end
  
  def formatted_code
    return nil unless generated_code.present?
    
    case language
    when 'python'
      "```python\n#{generated_code}\n```"
    when 'r'
      "```r\n#{generated_code}\n```"
    when 'sql'
      "```sql\n#{generated_code}\n```"
    else
      generated_code
    end
  end
  
  def execute!
    update!(started_at: Time.current, status: :executing)
    
    # This will be handled by a Solid Queue job
    CodeExecutionJob.perform_later(self)
  end
  
  def requires_network?
    # Determine if this step needs network access (for API calls, etc.)
    generated_code&.match?(/requests\.|urllib|httpx|curl|fetch/)
  end
  
  def estimated_memory_mb
    # Estimate memory requirements based on dataset size and operation type
    base_memory = 512 # MB
    
    multiplier = case step_type
                 when 'machine_learning' then 4
                 when 'data_exploration', 'feature_engineering' then 2
                 when 'visualization' then 1.5
                 else 1
                 end
    
    base_memory * multiplier
  end
end

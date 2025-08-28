class AnalysisRequest < ApplicationRecord
  include AASM
  
  # Associations
  belongs_to :user
  belongs_to :dataset
  belongs_to :organization
  has_many :execution_steps, dependent: :destroy
  has_many_attached :generated_artifacts # Charts, CSV exports, etc.
  
  # Validations
  validates :natural_language_query, presence: true, length: { minimum: 10, maximum: 5000 }
  
  # State machine for analysis workflow
  aasm column: :status, enum: true do
    state :pending, initial: true
    state :analyzing
    state :generating_code
    state :executing
    state :interpreting_results
    state :completed
    state :failed
    state :requires_clarification
    
    event :start_analysis do
      transitions from: :pending, to: :analyzing
      after do
        broadcast_status_update
        AnalysisJob.perform_later(self)
      end
    end
    
    event :generate_code do
      transitions from: :analyzing, to: :generating_code
      after do
        broadcast_status_update
      end
    end
    
    event :execute_code do
      transitions from: :generating_code, to: :executing
      after do
        broadcast_status_update
      end
    end
    
    event :interpret_results do
      transitions from: :executing, to: :interpreting_results
      after do
        broadcast_status_update
      end
    end
    
    event :complete do
      transitions from: :interpreting_results, to: :completed
      after do
        update(completed_at: Time.current)
        broadcast_status_update
        notify_user_of_completion
      end
    end
    
    event :fail do
      transitions from: [:analyzing, :generating_code, :executing, :interpreting_results], to: :failed
      after do |error_message|
        update(error_message: error_message)
        notify_user_of_failure
      end
    end
    
    event :request_clarification do
      transitions from: [:pending, :analyzing], to: :requires_clarification
    end
    
    event :retry_analysis do
      transitions from: [:failed, :requires_clarification], to: :pending
    end
  end
  
  # Enums
  enum :status, {
    pending: 0,
    analyzing: 1,
    generating_code: 2,
    executing: 3,
    interpreting_results: 4,
    completed: 5,
    failed: 6,
    requires_clarification: 7
  }
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :in_progress, -> { where(status: [:analyzing, :generating_code, :executing, :interpreting_results]) }
  scope :successful, -> { where(status: :completed) }
  
  # Store complex data in JSONB fields
  store_accessor :analyzed_intent, :query_type, :required_analysis_types, :identified_entities
  store_accessor :data_requirements, :tables_needed, :columns_needed, :filters_applied
  store_accessor :metadata, :selected_models, :execution_time, :tokens_used, :cost_estimate
  
  def estimated_completion_time
    # Estimate based on complexity
    base_time = 30 # seconds
    complexity_multiplier = (complexity_score || 1.0)
    (base_time * complexity_multiplier).seconds.from_now
  end
  
  def total_execution_time
    return nil unless completed?
    execution_steps.sum(:execution_time_ms) / 1000.0 # Convert to seconds
  end
  
  def progress_percentage
    case status.to_sym
    when :pending then 0
    when :analyzing then 20
    when :generating_code then 40
    when :executing then 60
    when :interpreting_results then 80
    when :completed then 100
    when :failed, :requires_clarification then 0
    else 0
    end
  end
  
  def current_step_description
    case status.to_sym
    when :pending then "Waiting to start..."
    when :analyzing then "Analyzing your query and understanding intent..."
    when :generating_code then "Generating analysis code..."
    when :executing then "Executing analysis steps..."
    when :interpreting_results then "Interpreting and summarizing results..."
    when :completed then "Analysis complete!"
    when :failed then "Analysis failed"
    when :requires_clarification then "Needs more information"
    else "Processing..."
    end
  end
  
  def processing?
    %w[analyzing generating_code executing interpreting_results].include?(status)
  end
  
  # Broadcast status updates via Turbo Streams
  def broadcast_status_update
    broadcast_update_to(
      self,
      target: "analysis-status",
      partial: "analysis_requests/analysis_status",
      locals: { analysis_request: self }
    )
    
    broadcast_update_to(
      self,
      target: "progress-section",
      partial: "analysis_requests/progress_bar",
      locals: { analysis_request: self }
    )
  end
  
  private
  
  def notify_user_of_completion
    # Use Action Cable to notify user in real-time via Solid Cable
    AnalysisChannel.broadcast_to(
      user,
      { 
        type: 'analysis_completed',
        analysis_id: id,
        message: "Your analysis '#{natural_language_query.truncate(50)}' is complete!"
      }
    )
  end
  
  def notify_user_of_failure
    AnalysisChannel.broadcast_to(
      user,
      { 
        type: 'analysis_failed',
        analysis_id: id,
        message: "Analysis failed: #{error_message}"
      }
    )
  end
end

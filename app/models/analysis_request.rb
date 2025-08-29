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
        AnalysisJob.perform_later(self)
      end
    end

    event :generate_code do
      transitions from: :analyzing, to: :generating_code
    end

    event :execute_code do
      transitions from: :generating_code, to: :executing
    end

    event :interpret_results do
      transitions from: :executing, to: :interpreting_results
    end

    event :complete do
      transitions from: :interpreting_results, to: :completed
      after do
        update_execution_metrics
        notify_user_of_completion
      end
    end

    event :fail do
      transitions from: [ :analyzing, :generating_code, :executing, :interpreting_results ], to: :failed
      after do |error_message|
        update(error_message: error_message)
        notify_user_of_failure
      end
    end

    event :request_clarification do
      transitions from: [ :pending, :analyzing ], to: :requires_clarification
    end

    event :retry_analysis do
      transitions from: [ :failed, :requires_clarification ], to: :pending
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
  scope :in_progress, -> { where(status: [ :analyzing, :generating_code, :executing, :interpreting_results ]) }
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

  private

  def update_execution_metrics
    # Calculate total execution time and store it in both the column and metadata
    total_time = total_execution_time
    if total_time
      update_columns(execution_time: total_time)
      # Also update metadata to maintain backward compatibility
      self.metadata = (metadata || {}).merge("execution_time" => total_time)
      save! if changed?
    end
  end

  def notify_user_of_completion
    # Use Action Cable to notify user in real-time via Solid Cable
    AnalysisChannel.broadcast_to(
      user,
      {
        type: "analysis_completed",
        analysis_id: id,
        message: "Your analysis '#{natural_language_query.truncate(50)}' is complete!"
      }
    )
  end

  def notify_user_of_failure
    AnalysisChannel.broadcast_to(
      user,
      {
        type: "analysis_failed",
        analysis_id: id,
        message: "Analysis failed: #{error_message}"
      }
    )
  end
end

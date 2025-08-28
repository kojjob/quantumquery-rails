class ScheduledReport < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :dataset, optional: true
  
  # Serialization
  serialize :recipients, coder: JSON
  serialize :metadata, coder: JSON
  
  # Validations
  validates :name, presence: true
  validates :query, presence: true
  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  validates :format, inclusion: { in: %w[pdf xlsx csv] }
  validates :schedule_hour, inclusion: { in: 0..23 }
  validates :schedule_day, inclusion: { in: 0..6 }, if: :weekly?
  validates :schedule_day, inclusion: { in: 1..31 }, if: :monthly?
  validates :recipients, presence: true
  
  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :due_for_run, -> { enabled.where('next_run_at <= ?', Time.current) }
  scope :by_frequency, ->(freq) { where(frequency: freq) }
  
  # Callbacks
  before_create :set_initial_next_run_at
  after_update :recalculate_next_run_at, if: :schedule_changed?
  
  def daily?
    frequency == 'daily'
  end
  
  def weekly?
    frequency == 'weekly'
  end
  
  def monthly?
    frequency == 'monthly'
  end
  
  def run!
    return false unless enabled? && due?
    
    # Create analysis request
    analysis_request = user.analysis_requests.create!(
      natural_language_query: query,
      dataset: dataset,
      organization: organization,
      metadata: {
        scheduled_report_id: id,
        scheduled_report_name: name,
        auto_generated: true
      }
    )
    
    # Start the analysis
    analysis_request.start_analysis!
    
    # Update run information
    update!(
      last_run_at: Time.current,
      next_run_at: calculate_next_run_at,
      run_count: run_count + 1
    )
    
    # Schedule email delivery job for when analysis completes
    ScheduledReportDeliveryJob.set(wait: 5.minutes).perform_later(self, analysis_request)
    
    true
  rescue => e
    Rails.logger.error "Failed to run scheduled report #{id}: #{e.message}"
    false
  end
  
  def due?
    next_run_at.present? && next_run_at <= Time.current
  end
  
  def calculate_next_run_at(from_time = Time.current)
    case frequency
    when 'daily'
      calculate_daily_next_run(from_time)
    when 'weekly'
      calculate_weekly_next_run(from_time)
    when 'monthly'
      calculate_monthly_next_run(from_time)
    end
  end
  
  def formatted_schedule
    case frequency
    when 'daily'
      "Daily at #{schedule_hour}:00"
    when 'weekly'
      "Every #{Date::DAYNAMES[schedule_day]} at #{schedule_hour}:00"
    when 'monthly'
      "Monthly on day #{schedule_day} at #{schedule_hour}:00"
    end
  end
  
  def recipient_list
    recipients || []
  end
  
  def add_recipient(email)
    self.recipients ||= []
    self.recipients << email unless self.recipients.include?(email)
    save
  end
  
  def remove_recipient(email)
    return unless recipients
    self.recipients.delete(email)
    save
  end
  
  private
  
  def set_initial_next_run_at
    self.next_run_at ||= calculate_next_run_at
  end
  
  def schedule_changed?
    saved_change_to_frequency? || 
    saved_change_to_schedule_day? || 
    saved_change_to_schedule_hour? ||
    saved_change_to_enabled?
  end
  
  def recalculate_next_run_at
    if enabled?
      update_column(:next_run_at, calculate_next_run_at)
    else
      update_column(:next_run_at, nil)
    end
  end
  
  def calculate_daily_next_run(from_time)
    next_run = from_time.change(hour: schedule_hour, min: 0, sec: 0)
    next_run += 1.day if next_run <= from_time
    next_run
  end
  
  def calculate_weekly_next_run(from_time)
    next_run = from_time.beginning_of_week(:sunday)
    next_run += schedule_day.days
    next_run = next_run.change(hour: schedule_hour, min: 0, sec: 0)
    
    # If the calculated time is in the past, move to next week
    next_run += 1.week if next_run <= from_time
    next_run
  end
  
  def calculate_monthly_next_run(from_time)
    next_run = from_time.change(day: [schedule_day, from_time.end_of_month.day].min, 
                                hour: schedule_hour, min: 0, sec: 0)
    
    # If the calculated time is in the past, move to next month
    if next_run <= from_time
      next_run = next_run.next_month
      # Handle end-of-month edge cases
      next_run = next_run.change(day: [schedule_day, next_run.end_of_month.day].min)
    end
    
    next_run
  end
end
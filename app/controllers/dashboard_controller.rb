class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @recent_analyses = current_user.analysis_requests
                                  .includes(:dataset)
                                  .order(created_at: :desc)
                                  .limit(5)
    
    @scheduled_reports = current_user.scheduled_reports
                                    .enabled
                                    .includes(:dataset)
                                    .order(:next_run_at)
                                    .limit(5)
    
    @datasets = current_user.organization&.datasets&.limit(5) || Dataset.none
    
    # Statistics
    @total_analyses = current_user.analysis_requests.count
    @total_scheduled_reports = current_user.scheduled_reports.count
    @active_scheduled_reports = current_user.scheduled_reports.enabled.count
    @total_datasets = current_user.organization&.datasets&.count || 0
  end
end
class DashboardController < ApplicationController
  before_action :authenticate_user!
  
  def index
    ensure_organization!
    
    @stats = {
      total_analyses: current_user.analysis_requests.count,
      data_sources: current_user.organization.datasets.count,
      active_analyses: current_user.analysis_requests.where(status: ['analyzing', 'generating_code', 'executing']).count,
      avg_execution_time: calculate_average_execution_time
    }
    
    @recent_analyses = current_user.analysis_requests
                                  .includes(:dataset)
                                  .order(created_at: :desc)
                                  .limit(5)
    
    @data_sources = current_user.organization.datasets
                                .order(created_at: :desc)
                                .limit(5)
  end
  
  private
  
  def calculate_average_execution_time
    completed = current_user.analysis_requests.successful
    return '0s' if completed.empty?
    
    total_seconds = completed.sum { |r| 
      (r.completed_at - r.created_at).to_i rescue 0 
    }
    
    avg_seconds = total_seconds / completed.count
    
    if avg_seconds < 60
      "#{avg_seconds}s"
    elsif avg_seconds < 3600
      "#{avg_seconds / 60}m"
    else
      "#{avg_seconds / 3600}h"
    end
  end
end
class AnalysisRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_analysis_request, only: [:show, :edit, :update, :destroy, :status]
  
  def index
    @analysis_requests = current_user.analysis_requests
                                     .includes(:dataset)
                                     .order(created_at: :desc)
                                     .page(params[:page])
  end
  
  def show
    @execution_steps = @analysis_request.execution_steps.order(:order_index)
  end
  
  def new
    @analysis_request = current_user.analysis_requests.build
    @datasets = current_user.organization.datasets.active
  end
  
  def create
    @analysis_request = current_user.analysis_requests.build(analysis_request_params)
    @analysis_request.organization = current_user.organization
    
    if @analysis_request.save
      # Start analysis in background
      AnalysisJob.perform_later(@analysis_request)
      
      redirect_to @analysis_request, notice: 'Analysis started successfully!'
    else
      @datasets = current_user.organization.datasets.active
      render :new, status: :unprocessable_entity
    end
  end
  
  def status
    render json: {
      status: @analysis_request.status,
      progress: @analysis_request.progress_percentage,
      current_step: @analysis_request.current_step_description,
      execution_steps: @analysis_request.execution_steps.map { |step|
        {
          id: step.id,
          type: step.step_type,
          status: step.status,
          output: step.output&.truncate(500)
        }
      }
    }
  end
  
  private
  
  def set_analysis_request
    @analysis_request = current_user.analysis_requests.find(params[:id])
  end
  
  def analysis_request_params
    params.require(:analysis_request).permit(
      :natural_language_query,
      :dataset_id,
      :analysis_type,
      :priority
    )
  end
end
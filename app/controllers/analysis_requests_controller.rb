class AnalysisRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_organization!
  before_action :set_analysis_request, only: [:show, :destroy, :status, :export]
  
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
  
  def destroy
    @analysis_request.destroy
    redirect_to analysis_requests_path, notice: 'Analysis request was successfully deleted.'
  end
  
  def export
    export_service = AnalysisExportService.new(@analysis_request, params[:format])
    
    respond_to do |format|
      format.pdf do
        @export_data = export_service.export
        render pdf: "analysis_request_#{@analysis_request.id}",
               template: 'analysis_requests/export',
               layout: 'pdf',
               page_size: 'A4',
               orientation: 'portrait',
               margin: { top: 20, bottom: 20, left: 15, right: 15 },
               footer: { right: '[page] of [topage]', font_size: 9 }
      end
      
      format.xlsx do
        send_data export_service.export.read,
                  filename: "analysis_request_#{@analysis_request.id}.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  disposition: 'attachment'
      end
      
      format.csv do
        send_data export_service.export,
                  filename: "analysis_request_#{@analysis_request.id}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
    end
  rescue ArgumentError => e
    redirect_to @analysis_request, alert: e.message
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
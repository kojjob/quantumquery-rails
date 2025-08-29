class AnalysisRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_analysis_request, only: [ :show, :destroy, :export ]

  def index
    @analysis_requests = current_user.organization.analysis_requests
      .includes(:user, :dataset)
      .order(created_at: :desc)
      .page(params[:page])
      .per(20)

    # Filter by status if provided
    if params[:status].present?
      @analysis_requests = @analysis_requests.where(status: params[:status])
    end

    # Filter by dataset if provided
    if params[:dataset_id].present?
      @analysis_requests = @analysis_requests.where(dataset_id: params[:dataset_id])
    end
  end

  def show
    @execution_steps = @analysis_request.execution_steps.order(:step_number)
  end

  def destroy
    @analysis_request.destroy
    redirect_to analysis_requests_path, notice: "Analysis request was successfully deleted."
  end

  def export
    respond_to do |format|
      format.json { render json: @analysis_request.result }
      format.csv {
        send_data @analysis_request.to_csv,
                  filename: "analysis_#{@analysis_request.id}_#{Date.current}.csv"
      }
      format.xlsx {
        send_data @analysis_request.to_xlsx,
                  filename: "analysis_#{@analysis_request.id}_#{Date.current}.xlsx"
      }
    end
  end

  private

  def set_analysis_request
    @analysis_request = current_user.organization.analysis_requests.find(params[:id])
  end
end

class DatasetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dataset, only: [ :show, :edit, :update, :destroy, :analyze ]

  def index
    @datasets = current_user.organization.datasets.includes(:analysis_requests)
      .order(created_at: :desc)
  end

  def show
    @analysis_requests = @dataset.analysis_requests
      .includes(:user)
      .order(created_at: :desc)
      .limit(10)
  end

  def new
    @dataset = current_user.organization.datasets.build
  end

  def create
    @dataset = current_user.organization.datasets.build(dataset_params)

    if @dataset.save
      redirect_to @dataset, notice: "Dataset was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @dataset.update(dataset_params)
      redirect_to @dataset, notice: "Dataset was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @dataset.destroy
    redirect_to datasets_path, notice: "Dataset was successfully deleted."
  end

  def analyze
    # Create new analysis request
    analysis_request = @dataset.analysis_requests.create!(
      user: current_user,
      query: params[:query] || "Analyze this dataset",
      status: "pending"
    )

    # Queue analysis job (if you have background jobs set up)
    # AnalysisJob.perform_later(analysis_request.id)

    redirect_to analysis_request, notice: "Analysis request created successfully."
  end

  private

  def set_dataset
    @dataset = current_user.organization.datasets.find(params[:id])
  end

  def dataset_params
    params.require(:dataset).permit(:name, :description, :data_source_type, :connection_params, :schema_info, :sample_data)
  end
end

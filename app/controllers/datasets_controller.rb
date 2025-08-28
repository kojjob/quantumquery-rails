class DatasetsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_organization!
  before_action :set_dataset, only: [:show, :edit, :update, :destroy, :test_connection, :fetch_schema, :sample_data]
  
  def index
    @datasets = current_user.organization.datasets.includes(:created_by)
  end
  
  def show
    @recent_analyses = @dataset.analysis_requests
                               .includes(:user)
                               .order(created_at: :desc)
                               .limit(10)
  end
  
  def new
    @dataset = current_user.organization.datasets.build
  end
  
  def create
    @dataset = current_user.organization.datasets.build(dataset_params)
    @dataset.created_by = current_user
    
    if @dataset.save
      if @dataset.csv_upload?
        handle_csv_upload
      end
      
      redirect_to @dataset, notice: 'Dataset created successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    # View will be rendered
  end
  
  def update
    if @dataset.update(dataset_params)
      redirect_to @dataset, notice: 'Dataset updated successfully!'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @dataset.destroy
    redirect_to datasets_path, notice: 'Dataset was successfully deleted.'
  end
  
  def test_connection
    connector = create_connector(@dataset)
    result = connector.test_connection
    
    if result[:success]
      @dataset.update!(status: 'connected', last_connected_at: Time.current)
      render json: { success: true, message: 'Connection successful!', details: result }
    else
      @dataset.update!(status: 'connection_failed', last_error: result[:error])
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end
  
  def fetch_schema
    connector = create_connector(@dataset)
    schema = connector.fetch_schema
    
    render json: { 
      success: true, 
      schema: schema,
      tables_count: schema[:tables]&.count || 0,
      columns_count: schema[:tables]&.values&.sum { |t| t[:columns]&.count || 0 } || 0
    }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end
  
  def sample_data
    connector = create_connector(@dataset)
    samples = connector.fetch_sample_data(limit: 50)
    
    render json: { success: true, samples: samples }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end
  
  private
  
  def set_dataset
    @dataset = current_user.organization.datasets.find(params[:id])
  end
  
  def dataset_params
    params.require(:dataset).permit(
      :name, :description, :source_type,
      connection_config: {}
    ).tap do |p|
      # Handle file upload for CSV
      if params[:dataset][:csv_file].present?
        p[:source_type] = 'csv_upload'
      end
    end
  end
  
  def handle_csv_upload
    if params[:dataset][:csv_file].present?
      uploaded = params[:dataset][:csv_file]
      
      # Save file to storage
      file_path = Rails.root.join('storage', 'uploads', 'csv', "#{@dataset.id}_#{uploaded.original_filename}")
      FileUtils.mkdir_p(file_path.dirname)
      File.open(file_path, 'wb') do |file|
        file.write(uploaded.read)
      end
      
      @dataset.update!(
        connection_config: { 'file_path' => file_path.to_s },
        metadata: {
          original_filename: uploaded.original_filename,
          file_size: uploaded.size,
          content_type: uploaded.content_type
        }
      )
      
      # Auto-fetch schema for CSV
      connector = create_connector(@dataset)
      connector.fetch_schema
    end
  end
  
  def create_connector(dataset)
    case dataset.source_type
    when 'postgresql'
      DataConnectors::PostgresqlConnector.new(
        dataset: dataset,
        connection_params: dataset.connection_config
      )
    when 'mysql'
      DataConnectors::MysqlConnector.new(
        dataset: dataset,
        connection_params: dataset.connection_config
      )
    when 'csv_upload'
      DataConnectors::CsvConnector.new(
        dataset: dataset,
        connection_params: dataset.connection_config
      )
    else
      raise "Unsupported source type: #{dataset.source_type}"
    end
  end
end
class DataSourceConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_data_source_connection, only: [:show, :edit, :update, :destroy, :test_connection, :sync_schema, :list_tables]

  def index
    @data_source_connections = current_user.organization.data_source_connections
                                          .includes(:user)
                                          .order(created_at: :desc)
  end

  def show
    @tables = @data_source_connection.metadata['tables'] || []
    @last_sync = @data_source_connection.metadata['last_schema_sync_at']
  end

  def new
    @data_source_connection = current_user.organization.data_source_connections.build
    @source_type = params[:source_type] || 'postgresql'
  end

  def create
    @data_source_connection = current_user.organization.data_source_connections.build(data_source_connection_params)
    @data_source_connection.user = current_user
    
    # Format credentials based on source type
    @data_source_connection.credentials = format_credentials(params[:data_source_connection])
    
    if @data_source_connection.save
      redirect_to @data_source_connection, notice: 'Data source connection was successfully created. Testing connection...'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @source_type = @data_source_connection.source_type
  end

  def update
    # Update credentials if provided
    if params[:data_source_connection][:credentials].present?
      @data_source_connection.credentials = format_credentials(params[:data_source_connection])
    end
    
    if @data_source_connection.update(data_source_connection_params.except(:credentials))
      redirect_to @data_source_connection, notice: 'Data source connection was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @data_source_connection.destroy!
    redirect_to data_source_connections_url, notice: 'Data source connection was successfully removed.'
  end

  def test_connection
    @data_source_connection.test_connection
    redirect_to @data_source_connection, notice: 'Testing connection...'
  end

  def sync_schema
    @data_source_connection.sync_schema
    redirect_to @data_source_connection, notice: 'Syncing schema...'
  end

  def list_tables
    if @data_source_connection.connected?
      tables = @data_source_connection.list_tables
      render json: { success: true, tables: tables }
    else
      render json: { success: false, error: 'Connection not active' }, status: :unprocessable_entity
    end
  end

  private

  def set_data_source_connection
    @data_source_connection = current_user.organization.data_source_connections.find(params[:id])
  end

  def data_source_connection_params
    params.require(:data_source_connection).permit(:name, :source_type, :connection_options)
  end

  def format_credentials(params)
    credentials = {}
    
    case params[:source_type]
    when 'snowflake'
      credentials = {
        account: params[:snowflake_account],
        username: params[:snowflake_username],
        password: params[:snowflake_password],
        warehouse: params[:snowflake_warehouse],
        database: params[:snowflake_database],
        schema: params[:snowflake_schema],
        role: params[:snowflake_role],
        region: params[:snowflake_region]
      }.compact
    when 'bigquery'
      credentials = {
        project_id: params[:bigquery_project_id],
        dataset: params[:bigquery_dataset]
      }
      
      if params[:bigquery_service_account_json].present?
        credentials[:service_account_json] = params[:bigquery_service_account_json]
      elsif params[:bigquery_api_key].present?
        credentials[:api_key] = params[:bigquery_api_key]
      end
    when 'postgresql'
      credentials = {
        host: params[:pg_host],
        port: params[:pg_port] || 5432,
        database: params[:pg_database],
        username: params[:pg_username],
        password: params[:pg_password],
        schema: params[:pg_schema] || 'public'
      }.compact
    when 'mysql'
      credentials = {
        host: params[:mysql_host],
        port: params[:mysql_port] || 3306,
        database: params[:mysql_database],
        username: params[:mysql_username],
        password: params[:mysql_password]
      }.compact
    end
    
    credentials.to_json
  end
end
class DataSourceConnection < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  has_many :datasets, dependent: :nullify

  # Encryption for credentials using lockbox
  has_encrypted :credentials

  # Status enum
  enum :status, {
    pending: 0,
    connected: 1,
    error: 2,
    disconnected: 3,
    syncing: 4
  }

  # Source types
  SOURCE_TYPES = {
    'snowflake' => 'Snowflake',
    'bigquery' => 'BigQuery',
    'postgresql' => 'PostgreSQL',
    'mysql' => 'MySQL',
    'csv' => 'CSV Upload',
    'excel' => 'Excel Upload'
  }.freeze

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES.keys }
  validates :credentials, presence: true, if: :requires_credentials?

  # Scopes
  scope :active, -> { where(status: [:connected, :syncing]) }
  scope :by_type, ->(type) { where(source_type: type) }

  # Callbacks
  before_validation :set_default_metadata
  after_create :test_connection
  after_update :test_connection, if: :saved_change_to_credentials_ciphertext?

  def requires_credentials?
    %w[snowflake bigquery postgresql mysql].include?(source_type)
  end

  def cloud_data_warehouse?
    %w[snowflake bigquery].include?(source_type)
  end

  def display_name
    SOURCE_TYPES[source_type] || source_type.humanize
  end

  def test_connection
    TestDataSourceConnectionJob.perform_later(self)
  end

  def sync_schema
    SyncDataSourceSchemaJob.perform_later(self)
  end

  def connect!
    connector = connector_class.new(self)
    
    if connector.test_connection
      update!(status: :connected, last_synced_at: Time.current)
      sync_schema
      true
    else
      update!(status: :error, last_error_at: Time.current)
      false
    end
  rescue => e
    update!(
      status: :error,
      last_error_at: Time.current,
      last_error_message: e.message
    )
    false
  end

  def disconnect!
    update!(status: :disconnected)
  end

  def connector_class
    case source_type
    when 'snowflake'
      DataSources::SnowflakeConnector
    when 'bigquery'
      DataSources::BigQueryConnector
    when 'postgresql'
      DataSources::PostgresqlConnector
    when 'mysql'
      DataSources::MysqlConnector
    when 'csv'
      DataSources::CsvConnector
    when 'excel'
      DataSources::ExcelConnector
    else
      raise "Unknown source type: #{source_type}"
    end
  end

  def execute_query(query)
    raise "Connection not active" unless connected?
    
    connector = connector_class.new(self)
    connector.execute_query(query)
  end

  def list_tables
    return [] unless connected?
    
    connector = connector_class.new(self)
    connector.list_tables
  end

  def get_table_schema(table_name)
    return nil unless connected?
    
    connector = connector_class.new(self)
    connector.get_table_schema(table_name)
  end

  def credentials_hash
    return {} if credentials.blank?
    
    JSON.parse(credentials).symbolize_keys
  rescue JSON::ParserError
    {}
  end

  private

  def set_default_metadata
    self.metadata ||= {}
    self.connection_options ||= {}
  end
end

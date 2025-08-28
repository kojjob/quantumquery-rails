class Dataset < ApplicationRecord
  # Associations
  belongs_to :organization
  belongs_to :data_source_connection, optional: true
  has_many :analysis_requests, dependent: :restrict_with_error
  has_one_attached :data_file # For CSV/Excel uploads
  
  # Validations
  validates :name, presence: true
  validates :data_source_type, presence: true
  
  # Encryption for sensitive connection info
  encrypts :connection_config
  
  # Enums
  enum :status, {
    pending_connection: 0,
    connected: 1,
    syncing: 2,
    ready: 3,
    error: 4,
    disconnected: 5
  }, prefix: true
  
  enum :data_source_type, {
    postgresql: 0,
    mysql: 1,
    mongodb: 2,
    csv_upload: 3,
    excel_upload: 4,
    api_endpoint: 5,
    s3_bucket: 6,
    google_sheets: 7,
    snowflake: 8,
    bigquery: 9
  }, prefix: true
  
  # Store schema information in JSONB
  store_accessor :schema_metadata, :tables, :columns, :row_counts, :relationships, :indexes
  store_accessor :connection_config, :host, :port, :database, :username, :encrypted_password, 
                 :ssl_enabled, :connection_pool_size
  
  # Scopes
  scope :active, -> { where(status: [:connected, :ready]) }
  scope :by_type, ->(type) { where(data_source_type: type) }
  
  def test_connection
    connector.test_connection
  rescue => e
    update(status: :error, last_error: e.message)
    false
  end
  
  def refresh_schema
    return unless status_connected? || status_ready?
    
    DatasetSchemaRefreshJob.perform_later(self)
  end
  
  def sample_data(limit: 100)
    connector.sample_data(limit: limit)
  end
  
  def connector
    @connector ||= DataSources::ConnectorFactory.build(self)
  end
  
  def estimated_size_mb
    return data_file.byte_size / 1.megabyte.to_f if data_file.attached?
    
    # Estimate from row counts
    total_rows = row_counts&.values&.sum || 0
    total_rows * 0.001 # Rough estimate: 1KB per row
  end
end

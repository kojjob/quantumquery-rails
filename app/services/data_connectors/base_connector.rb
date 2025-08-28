# Base class for all data connectors
module DataConnectors
  class BaseConnector
    include ActiveModel::Model
    
    attr_accessor :dataset, :connection_params
    
    validates :dataset, presence: true
    
    def connect
      raise NotImplementedError, "Subclasses must implement connect"
    end
    
    def test_connection
      raise NotImplementedError, "Subclasses must implement test_connection"
    end
    
    def fetch_schema
      raise NotImplementedError, "Subclasses must implement fetch_schema"
    end
    
    def fetch_sample_data(limit: 100)
      raise NotImplementedError, "Subclasses must implement fetch_sample_data"
    end
    
    def execute_query(query)
      raise NotImplementedError, "Subclasses must implement execute_query"
    end
    
    def disconnect
      # Override if needed
    end
    
    protected
    
    def log_activity(action, details = {})
      Rails.logger.info "[#{self.class.name}] #{action}: #{details.to_json}"
      
      dataset.activity_logs.create!(
        action: action,
        details: details,
        performed_at: Time.current
      )
    end
    
    def handle_connection_error(error)
      Rails.logger.error "Connection failed: #{error.message}"
      dataset.update!(
        status: 'connection_failed',
        last_error: error.message,
        last_error_at: Time.current
      )
      raise
    end
  end
end
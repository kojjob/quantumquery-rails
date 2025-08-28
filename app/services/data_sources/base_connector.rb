module DataSources
  class BaseConnector
    attr_reader :connection, :credentials

    def initialize(data_source_connection)
      @connection = data_source_connection
      @credentials = connection.credentials_hash
    end

    # Abstract methods to be implemented by subclasses
    def test_connection
      raise NotImplementedError, "Subclass must implement test_connection method"
    end

    def execute_query(query)
      raise NotImplementedError, "Subclass must implement execute_query method"
    end

    def list_tables
      raise NotImplementedError, "Subclass must implement list_tables method"
    end

    def list_databases
      []
    end

    def list_schemas
      []
    end

    def get_table_schema(table_name)
      raise NotImplementedError, "Subclass must implement get_table_schema method"
    end

    def get_table_preview(table_name, limit = 100)
      query = build_preview_query(table_name, limit)
      execute_query(query)
    end

    def import_table(table_name, dataset)
      # Import table data to a dataset
      raise NotImplementedError, "Subclass must implement import_table method"
    end

    protected

    def build_preview_query(table_name, limit)
      "SELECT * FROM #{sanitize_table_name(table_name)} LIMIT #{limit.to_i}"
    end

    def sanitize_table_name(table_name)
      # Basic sanitization - override in subclasses for specific SQL dialects
      table_name.gsub(/[^a-zA-Z0-9_.]/, '')
    end

    def format_results(result_set, columns = nil)
      return { columns: [], rows: [], row_count: 0 } if result_set.nil? || result_set.empty?

      {
        columns: columns || extract_columns(result_set),
        rows: extract_rows(result_set),
        row_count: result_set.size
      }
    end

    def extract_columns(result_set)
      # Override in subclasses
      []
    end

    def extract_rows(result_set)
      # Override in subclasses
      []
    end

    def handle_connection_error(error)
      Rails.logger.error "Connection error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      connection.update!(
        status: :error,
        last_error_at: Time.current,
        last_error_message: error.message
      )
      
      false
    end
  end
end
# frozen_string_literal: true

module CodeExecution
  # Executes SQL queries against datasets
  # Connects directly to the database with read-only permissions
  class SqlExecutor < BaseExecutor
    # SQL execution doesn't use Docker containers
    # Instead, it connects directly to the dataset's database
    
    def execute
      @start_time = Time.current

      begin
        # Validate dataset
        validate_dataset

        # Execute SQL query
        execute_query
      rescue => e
        handle_error(e)
      end
    end

    protected

    def validate_dataset
      dataset = options[:dataset]
      
      unless dataset
        raise ArgumentError, "Dataset is required for SQL execution"
      end

      unless dataset.connected?
        raise "Dataset is not connected"
      end

      unless %w[postgresql mysql mongodb].include?(dataset.data_source_type)
        raise "SQL execution not supported for #{dataset.data_source_type}"
      end
    end

    def execute_query
      dataset = options[:dataset]
      
      # Establish read-only connection
      connection = establish_readonly_connection(dataset)

      # Execute query with timeout
      results = execute_with_timeout(connection, code, timeout_seconds)

      # Calculate duration
      duration = Time.current - @start_time

      # Format results
      ExecutionResult.new(
        success: true,
        output: format_query_results(results),
        error: "",
        exit_code: 0,
        duration_seconds: duration,
        metadata: {
          row_count: results.count,
          columns: results.first&.keys || [],
          dataset_id: dataset.id,
          data_source_type: dataset.data_source_type
        }
      )
    rescue => e
      duration = Time.current - @start_time
      
      ExecutionResult.new(
        success: false,
        output: "",
        error: e.message,
        exit_code: 1,
        duration_seconds: duration,
        metadata: {
          error_class: e.class.name
        }
      )
    ensure
      connection&.close rescue nil
    end

    def establish_readonly_connection(dataset)
      case dataset.data_source_type
      when "postgresql"
        establish_postgres_connection(dataset)
      when "mysql"
        establish_mysql_connection(dataset)
      else
        raise "Unsupported database type: #{dataset.data_source_type}"
      end
    end

    def establish_postgres_connection(dataset)
      require "pg"
      
      config = dataset.connection_config.symbolize_keys
      
      conn = PG.connect(
        host: config[:host],
        port: config[:port] || 5432,
        dbname: config[:database],
        user: config[:username],
        password: config[:password],
        connect_timeout: 5
      )

      # Set read-only transaction
      conn.exec("BEGIN TRANSACTION READ ONLY")
      
      conn
    end

    def establish_mysql_connection(dataset)
      require "mysql2"
      
      config = dataset.connection_config.symbolize_keys
      
      client = Mysql2::Client.new(
        host: config[:host],
        port: config[:port] || 3306,
        database: config[:database],
        username: config[:username],
        password: config[:password],
        connect_timeout: 5,
        read_timeout: timeout_seconds
      )

      # Set read-only mode
      client.query("SET SESSION TRANSACTION READ ONLY")
      
      client
    end

    def execute_with_timeout(connection, query, timeout)
      # Use Timeout to enforce query timeout
      Timeout.timeout(timeout) do
        case connection
        when PG::Connection
          connection.exec(query).to_a
        when Mysql2::Client
          connection.query(query).to_a
        else
          raise "Unknown connection type: #{connection.class}"
        end
      end
    rescue Timeout::Error
      raise "Query timeout after #{timeout} seconds"
    end

    def format_query_results(results)
      return "No results" if results.empty?

      # Convert to JSON for consistent output format
      {
        rows: results,
        count: results.count
      }.to_json
    end

    def timeout_seconds
      options[:timeout] || DEFAULT_TIMEOUT
    end

    # SQL executor doesn't use Docker, so these are no-ops
    def image_name
      nil
    end

    def prepare_code
      code
    end

    def execution_command
      []
    end
  end
end

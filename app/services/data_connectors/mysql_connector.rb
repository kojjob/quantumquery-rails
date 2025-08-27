# MySQL data connector
require 'mysql2'

module DataConnectors
  class MysqlConnector < BaseConnector
    attr_reader :connection
    
    def connect
      @connection = Mysql2::Client.new(
        host: connection_params['host'],
        port: connection_params['port'] || 3306,
        database: connection_params['database'],
        username: connection_params['username'],
        password: connection_params['password'],
        ssl_mode: connection_params['ssl_mode'] || :preferred,
        encoding: 'utf8mb4',
        connect_timeout: 10,
        read_timeout: 30,
        write_timeout: 30
      )
      
      log_activity('connected', { database: connection_params['database'] })
      @connection
    rescue Mysql2::Error => e
      handle_connection_error(e)
    end
    
    def test_connection
      connect unless @connection
      result = @connection.query("SELECT VERSION() as version, DATABASE() as db, USER() as user")
      row = result.first
      
      {
        success: true,
        version: row['version'],
        database: row['db'],
        user: row['user']
      }
    rescue Mysql2::Error => e
      { success: false, error: e.message }
    end
    
    def fetch_schema
      connect unless @connection
      
      schema = {
        tables: {},
        views: {},
        indexes: {},
        constraints: {}
      }
      
      # Fetch tables
      tables_query = <<-SQL
        SELECT 
          TABLE_SCHEMA,
          TABLE_NAME,
          TABLE_TYPE,
          TABLE_COMMENT,
          TABLE_ROWS,
          DATA_LENGTH
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
        ORDER BY TABLE_NAME
      SQL
      
      tables_result = @connection.query(tables_query)
      
      tables_result.each do |row|
        table_key = row['TABLE_NAME']
        
        # Fetch columns
        columns_query = <<-SQL
          SELECT 
            COLUMN_NAME,
            DATA_TYPE,
            CHARACTER_MAXIMUM_LENGTH,
            IS_NULLABLE,
            COLUMN_DEFAULT,
            COLUMN_COMMENT,
            COLUMN_KEY,
            EXTRA
          FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
          ORDER BY ORDINAL_POSITION
        SQL
        
        columns_stmt = @connection.prepare(columns_query)
        columns = columns_stmt.execute(row['TABLE_NAME'])
        
        schema[:tables][table_key] = {
          name: row['TABLE_NAME'],
          type: row['TABLE_TYPE'],
          comment: row['TABLE_COMMENT'],
          estimated_rows: row['TABLE_ROWS'],
          size_bytes: row['DATA_LENGTH'],
          columns: columns.map { |col|
            {
              name: col['COLUMN_NAME'],
              type: col['DATA_TYPE'],
              nullable: col['IS_NULLABLE'] == 'YES',
              default: col['COLUMN_DEFAULT'],
              comment: col['COLUMN_COMMENT'],
              max_length: col['CHARACTER_MAXIMUM_LENGTH'],
              key: col['COLUMN_KEY'],
              extra: col['EXTRA']
            }
          }
        }
      end
      
      # Fetch indexes
      schema[:tables].each do |table_name, table_info|
        indexes_query = "SHOW INDEXES FROM `#{table_name}`"
        indexes = @connection.query(indexes_query)
        
        indexed_columns = {}
        indexes.each do |idx|
          indexed_columns[idx['Key_name']] ||= {
            unique: idx['Non_unique'] == 0,
            columns: []
          }
          indexed_columns[idx['Key_name']][:columns] << idx['Column_name']
        end
        
        schema[:indexes][table_name] = indexed_columns.map do |name, info|
          {
            name: name,
            unique: info[:unique],
            columns: info[:columns]
          }
        end
      end
      
      # Store schema in dataset
      dataset.update!(
        schema_metadata: schema,
        schema_fetched_at: Time.current,
        status: 'connected'
      )
      
      log_activity('schema_fetched', { 
        tables_count: schema[:tables].count,
        total_columns: schema[:tables].values.sum { |t| t[:columns].count }
      })
      
      schema
    rescue Mysql2::Error => e
      handle_connection_error(e)
    end
    
    def fetch_sample_data(limit: 100)
      connect unless @connection
      
      samples = {}
      
      # Get main tables
      main_tables = dataset.schema_metadata['tables'].select do |_, table|
        table[:estimated_rows].to_i > 0 && table[:type] == 'BASE TABLE'
      end.take(5)
      
      main_tables.each do |table_name, table_info|
        query = "SELECT * FROM `#{table_name}` LIMIT ?"
        stmt = @connection.prepare(query)
        result = stmt.execute(limit)
        
        samples[table_name] = {
          columns: result.fields,
          data: result.to_a,
          row_count: table_info[:estimated_rows]
        }
      end
      
      log_activity('sample_data_fetched', { 
        tables_sampled: samples.keys,
        total_rows: samples.values.sum { |s| s[:data].count }
      })
      
      samples
    rescue Mysql2::Error => e
      handle_connection_error(e)
    end
    
    def execute_query(query, limit: 10000)
      connect unless @connection
      
      # Add safety limit if SELECT without LIMIT
      safe_query = query.strip
      if safe_query.upcase.start_with?('SELECT') && !safe_query.upcase.include?('LIMIT')
        safe_query += " LIMIT #{limit}"
      end
      
      start_time = Time.current
      result = @connection.query(safe_query, as: :array, symbolize_keys: false)
      execution_time = Time.current - start_time
      
      response = {
        columns: result.fields,
        data: result.to_a,
        row_count: result.count,
        execution_time: execution_time,
        query: safe_query
      }
      
      log_activity('query_executed', {
        query: safe_query.truncate(100),
        row_count: response[:row_count],
        execution_time: execution_time
      })
      
      response
    rescue Mysql2::Error => e
      log_activity('query_failed', { 
        query: query.truncate(100),
        error: e.message 
      })
      raise
    end
    
    def disconnect
      @connection&.close
      @connection = nil
      log_activity('disconnected')
    end
  end
end
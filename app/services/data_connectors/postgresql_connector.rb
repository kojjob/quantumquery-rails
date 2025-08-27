# PostgreSQL data connector
require 'pg'

module DataConnectors
  class PostgresqlConnector < BaseConnector
    attr_reader :connection
    
    def connect
      @connection = PG.connect(
        host: connection_params['host'],
        port: connection_params['port'] || 5432,
        dbname: connection_params['database'],
        user: connection_params['username'],
        password: connection_params['password'],
        sslmode: connection_params['ssl_mode'] || 'prefer'
      )
      
      log_activity('connected', { database: connection_params['database'] })
      @connection
    rescue PG::Error => e
      handle_connection_error(e)
    end
    
    def test_connection
      connect unless @connection
      result = @connection.exec("SELECT version(), current_database(), current_user")
      
      {
        success: true,
        version: result[0]['version'],
        database: result[0]['current_database'],
        user: result[0]['current_user']
      }
    rescue PG::Error => e
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
      
      # Fetch tables and columns
      tables_query = <<-SQL
        SELECT 
          t.table_schema,
          t.table_name,
          t.table_type,
          obj_description(c.oid) as table_comment
        FROM information_schema.tables t
        JOIN pg_class c ON c.relname = t.table_name
        WHERE t.table_schema NOT IN ('pg_catalog', 'information_schema')
        ORDER BY t.table_schema, t.table_name
      SQL
      
      tables_result = @connection.exec(tables_query)
      
      tables_result.each do |row|
        table_key = "#{row['table_schema']}.#{row['table_name']}"
        
        # Fetch columns for each table
        columns_query = <<-SQL
          SELECT 
            column_name,
            data_type,
            character_maximum_length,
            is_nullable,
            column_default,
            col_description(pgc.oid, a.attnum) as column_comment
          FROM information_schema.columns c
          JOIN pg_class pgc ON pgc.relname = c.table_name
          JOIN pg_attribute a ON a.attrelid = pgc.oid AND a.attname = c.column_name
          WHERE table_schema = $1 AND table_name = $2
          ORDER BY ordinal_position
        SQL
        
        columns = @connection.exec_params(
          columns_query, 
          [row['table_schema'], row['table_name']]
        )
        
        schema[:tables][table_key] = {
          schema: row['table_schema'],
          name: row['table_name'],
          type: row['table_type'],
          comment: row['table_comment'],
          columns: columns.map { |col| 
            {
              name: col['column_name'],
              type: col['data_type'],
              nullable: col['is_nullable'] == 'YES',
              default: col['column_default'],
              comment: col['column_comment'],
              max_length: col['character_maximum_length']
            }
          },
          row_count: fetch_row_count(row['table_schema'], row['table_name'])
        }
      end
      
      # Fetch indexes
      indexes_query = <<-SQL
        SELECT 
          schemaname,
          tablename,
          indexname,
          indexdef
        FROM pg_indexes
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, tablename, indexname
      SQL
      
      indexes_result = @connection.exec(indexes_query)
      indexes_result.each do |row|
        table_key = "#{row['schemaname']}.#{row['tablename']}"
        schema[:indexes][table_key] ||= []
        schema[:indexes][table_key] << {
          name: row['indexname'],
          definition: row['indexdef']
        }
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
    rescue PG::Error => e
      handle_connection_error(e)
    end
    
    def fetch_sample_data(limit: 100)
      connect unless @connection
      
      samples = {}
      
      # Get main tables (exclude system tables)
      main_tables = dataset.schema_metadata['tables'].select do |_, table|
        table[:row_count] > 0 && table[:type] == 'BASE TABLE'
      end.take(5) # Sample from up to 5 tables
      
      main_tables.each do |table_key, table_info|
        schema, table = table_key.split('.')
        
        query = <<-SQL
          SELECT * FROM #{@connection.quote_ident(schema)}.#{@connection.quote_ident(table)}
          LIMIT $1
        SQL
        
        result = @connection.exec_params(query, [limit])
        
        samples[table_key] = {
          columns: result.fields,
          data: result.values,
          row_count: table_info[:row_count]
        }
      end
      
      log_activity('sample_data_fetched', { 
        tables_sampled: samples.keys,
        total_rows: samples.values.sum { |s| s[:data].count }
      })
      
      samples
    rescue PG::Error => e
      handle_connection_error(e)
    end
    
    def execute_query(query, limit: 10000)
      connect unless @connection
      
      # Add safety limit if not present
      safe_query = query.strip
      unless safe_query.upcase.include?('LIMIT')
        safe_query += " LIMIT #{limit}"
      end
      
      start_time = Time.current
      result = @connection.exec(safe_query)
      execution_time = Time.current - start_time
      
      response = {
        columns: result.fields,
        data: result.values,
        row_count: result.ntuples,
        execution_time: execution_time,
        query: safe_query
      }
      
      log_activity('query_executed', {
        query: safe_query.truncate(100),
        row_count: response[:row_count],
        execution_time: execution_time
      })
      
      response
    rescue PG::Error => e
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
    
    private
    
    def fetch_row_count(schema, table)
      query = "SELECT COUNT(*) FROM #{@connection.quote_ident(schema)}.#{@connection.quote_ident(table)}"
      result = @connection.exec(query)
      result[0]['count'].to_i
    rescue
      0
    end
  end
end
module DataSources
  class SnowflakeConnector < BaseConnector
    require 'net/http'
    require 'uri'
    require 'json'

    def test_connection
      # Test connection using Snowflake SQL API
      execute_query("SELECT 1 as test")
      true
    rescue => e
      handle_connection_error(e)
      false
    end

    def execute_query(query)
      uri = build_api_url("/statements")
      http = build_http_client(uri)
      
      request = Net::HTTP::Post.new(uri)
      request = add_auth_headers(request)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      
      request_body = {
        statement: query,
        timeout: 60,
        database: credentials[:database],
        schema: credentials[:schema],
        warehouse: credentials[:warehouse],
        role: credentials[:role]
      }.compact
      
      request.body = request_body.to_json
      
      response = http.request(request)
      
      if response.code.to_i == 200
        result = JSON.parse(response.body)
        
        # Check statement status
        if result['data']
          format_snowflake_results(result)
        else
          # Poll for results if async
          poll_for_results(result['statementHandle'])
        end
      else
        raise "Snowflake API error: #{response.code} - #{response.body}"
      end
    rescue => e
      handle_connection_error(e)
      raise
    end

    def list_tables
      query = <<~SQL
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = '#{credentials[:schema] || 'PUBLIC'}'
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
      SQL
      
      result = execute_query(query)
      result[:rows].map { |row| row[0] }
    end

    def list_databases
      query = "SHOW DATABASES"
      result = execute_query(query)
      result[:rows].map { |row| row[1] } # Database name is typically in second column
    end

    def list_schemas
      query = "SHOW SCHEMAS IN DATABASE #{credentials[:database]}"
      result = execute_query(query)
      result[:rows].map { |row| row[1] } # Schema name is typically in second column
    end

    def get_table_schema(table_name)
      query = <<~SQL
        SELECT 
          column_name,
          data_type,
          is_nullable,
          column_default,
          character_maximum_length,
          numeric_precision,
          numeric_scale
        FROM information_schema.columns
        WHERE table_schema = '#{credentials[:schema] || 'PUBLIC'}'
          AND table_name = UPPER('#{sanitize_table_name(table_name)}')
        ORDER BY ordinal_position
      SQL
      
      result = execute_query(query)
      
      result[:rows].map do |row|
        {
          name: row[0],
          type: row[1],
          nullable: row[2] == 'YES',
          default: row[3],
          max_length: row[4],
          precision: row[5],
          scale: row[6]
        }
      end
    end

    def import_table(table_name, dataset)
      # Import data in batches
      batch_size = 10000
      offset = 0
      total_rows = 0
      
      loop do
        query = <<~SQL
          SELECT * FROM #{sanitize_table_name(table_name)}
          LIMIT #{batch_size} OFFSET #{offset}
        SQL
        
        result = execute_query(query)
        break if result[:rows].empty?
        
        # Store the batch in the dataset
        store_batch(dataset, result, offset == 0)
        
        total_rows += result[:rows].size
        offset += batch_size
        
        # Update progress
        dataset.update!(
          metadata: dataset.metadata.merge(
            import_progress: (offset.to_f / get_table_count(table_name) * 100).round(2)
          )
        )
      end
      
      dataset.update!(
        row_count: total_rows,
        status: 'ready'
      )
      
      total_rows
    end

    private

    def build_api_url(endpoint)
      account = credentials[:account]
      region = credentials[:region] || 'us-west-2'
      
      # Construct Snowflake API URL
      # Format: https://[account].[region].snowflakecomputing.com/api/v2/statements
      URI("https://#{account}.#{region}.snowflakecomputing.com/api/v2#{endpoint}")
    end

    def build_http_client(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.read_timeout = 120
      http.open_timeout = 10
      http
    end

    def add_auth_headers(request)
      # Use either JWT token or username/password authentication
      if credentials[:token]
        request['Authorization'] = "Bearer #{credentials[:token]}"
      else
        # Basic auth with username and password
        auth = Base64.strict_encode64("#{credentials[:username]}:#{credentials[:password]}")
        request['Authorization'] = "Basic #{auth}"
      end
      
      request['X-Snowflake-Authorization-Token-Type'] = 'KEYPAIR_JWT' if credentials[:private_key]
      
      request
    end

    def poll_for_results(statement_handle)
      max_polls = 60
      poll_interval = 2
      
      max_polls.times do
        sleep poll_interval
        
        uri = build_api_url("/statements/#{statement_handle}")
        http = build_http_client(uri)
        
        request = Net::HTTP::Get.new(uri)
        request = add_auth_headers(request)
        
        response = http.request(request)
        
        if response.code.to_i == 200
          result = JSON.parse(response.body)
          
          case result['status']
          when 'SUCCESS'
            return format_snowflake_results(result)
          when 'FAILED'
            raise "Query failed: #{result['message']}"
          when 'CANCELLED'
            raise "Query was cancelled"
          end
        end
      end
      
      raise "Query timeout - exceeded maximum polling time"
    end

    def format_snowflake_results(result)
      columns = result['resultSetMetaData']&.dig('rowType') || []
      rows = result['data'] || []
      
      {
        columns: columns.map { |col| col['name'] },
        rows: rows,
        row_count: result['resultSetMetaData']&.dig('numRows') || rows.size
      }
    end

    def get_table_count(table_name)
      query = "SELECT COUNT(*) FROM #{sanitize_table_name(table_name)}"
      result = execute_query(query)
      result[:rows].first&.first || 0
    end

    def store_batch(dataset, result, is_first_batch)
      # Store data in dataset's associated storage
      # This would typically write to a file or database table
      
      if is_first_batch
        # Create schema from first batch
        dataset.update!(
          schema: {
            columns: result[:columns].map do |col_name|
              { name: col_name, type: 'string' } # Simplified - would detect actual types
            end
          }
        )
      end
      
      # Append data to dataset storage
      # Implementation depends on storage strategy
    end

    def sanitize_table_name(table_name)
      # Snowflake identifier sanitization
      parts = table_name.split('.')
      parts.map { |part| %Q("#{part.gsub('"', '""')}") }.join('.')
    end
  end
end
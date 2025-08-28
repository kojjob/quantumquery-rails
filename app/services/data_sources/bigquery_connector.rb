module DataSources
  class BigQueryConnector < BaseConnector
    require 'google/cloud/bigquery'

    def test_connection
      client.query("SELECT 1 as test")
      true
    rescue => e
      handle_connection_error(e)
      false
    end

    def execute_query(query)
      results = client.query(query, max: 10000)
      format_bigquery_results(results)
    rescue => e
      handle_connection_error(e)
      raise
    end

    def list_tables
      dataset_id = credentials[:dataset] || client.dataset_id
      dataset = client.dataset(dataset_id)
      
      return [] unless dataset
      
      dataset.tables.map(&:table_id)
    end

    def list_datasets
      client.datasets.map(&:dataset_id)
    end

    def get_table_schema(table_name)
      dataset_id = credentials[:dataset] || client.dataset_id
      dataset = client.dataset(dataset_id)
      table = dataset.table(table_name)
      
      return [] unless table
      
      table.schema.fields.map do |field|
        {
          name: field.name,
          type: field.type,
          mode: field.mode,
          description: field.description,
          nullable: field.mode != 'REQUIRED'
        }
      end
    end

    def import_table(table_name, dataset)
      dataset_id = credentials[:dataset] || client.dataset_id
      bq_dataset = client.dataset(dataset_id)
      table = bq_dataset.table(table_name)
      
      return 0 unless table
      
      # Get total row count
      total_rows = table.rows_count
      
      # Import in batches
      batch_size = 10000
      offset = 0
      imported_rows = 0
      
      while offset < total_rows
        query = <<~SQL
          SELECT * FROM `#{credentials[:project_id]}.#{dataset_id}.#{table_name}`
          LIMIT #{batch_size} OFFSET #{offset}
        SQL
        
        results = client.query(query)
        
        # Store batch
        store_batch(dataset, format_bigquery_results(results), offset == 0)
        
        imported_rows += results.count
        offset += batch_size
        
        # Update progress
        dataset.update!(
          metadata: dataset.metadata.merge(
            import_progress: (imported_rows.to_f / total_rows * 100).round(2)
          )
        )
      end
      
      dataset.update!(
        row_count: imported_rows,
        status: 'ready'
      )
      
      imported_rows
    end

    private

    def client
      @client ||= begin
        if credentials[:service_account_json]
          # Use service account credentials
          Google::Cloud::Bigquery.new(
            project_id: credentials[:project_id],
            credentials: JSON.parse(credentials[:service_account_json])
          )
        elsif credentials[:api_key]
          # Use API key (limited functionality)
          Google::Cloud::Bigquery.new(
            project_id: credentials[:project_id],
            credentials: credentials[:api_key]
          )
        else
          # Use application default credentials
          Google::Cloud::Bigquery.new(
            project_id: credentials[:project_id]
          )
        end
      end
    end

    def format_bigquery_results(results)
      return { columns: [], rows: [], row_count: 0 } unless results && results.any?
      
      columns = results.fields.map(&:name)
      rows = results.map { |row| columns.map { |col| row[col] } }
      
      {
        columns: columns,
        rows: rows,
        row_count: results.count
      }
    end

    def store_batch(dataset, result, is_first_batch)
      if is_first_batch
        # Create schema from first batch
        dataset.update!(
          schema: {
            columns: result[:columns].map do |col_name|
              { name: col_name, type: detect_column_type(result[:rows], col_name) }
            end
          }
        )
      end
      
      # Append data to dataset storage
      # Implementation depends on storage strategy
    end

    def detect_column_type(rows, column_name)
      # Simple type detection - would be more sophisticated in production
      'string'
    end
  end
end
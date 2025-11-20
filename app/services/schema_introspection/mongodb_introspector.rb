# app/services/schema_introspection/mongodb_introspector.rb
module SchemaIntrospection
  class MongodbIntrospector < BaseIntrospector
    def extract_tables
      # In MongoDB, tables are collections
      with_connection do |client|
        database = client.database
        database.collection_names.sort
      end
    end

    def extract_columns
      # MongoDB is schemaless, so we sample documents to infer structure
      collections = extract_tables
      columns_by_collection = {}

      with_connection do |client|
        database = client.database
        
        collections.each do |collection_name|
          columns_by_collection[collection_name] = analyze_collection_structure(database, collection_name)
        end
      end

      columns_by_collection
    end

    def extract_row_counts
      collections = extract_tables
      counts = {}

      with_connection do |client|
        database = client.database
        
        collections.each do |collection_name|
          begin
            collection = database[collection_name]
            counts[collection_name] = collection.count
          rescue => e
            Rails.logger.warn "Failed to count documents in #{collection_name}: #{e.message}"
            counts[collection_name] = nil
          end
        end
      end

      counts
    end

    def extract_sample_data(limit: 5)
      collections = extract_tables.take(3)
      samples = {}

      with_connection do |client|
        database = client.database
        
        collections.each do |collection_name|
          begin
            collection = database[collection_name]
            samples[collection_name] = collection.find.limit(limit).to_a.map do |doc|
              doc.transform_keys(&:to_s)
            end
          rescue => e
            Rails.logger.warn "Failed to sample #{collection_name}: #{e.message}"
            samples[collection_name] = []
          end
        end
      end

      samples
    end

    def extract_metadata
      with_connection do |client|
        {
          database_name: client.database.name,
          server_version: client.database.command(buildInfo: 1).first["version"],
          connection_info: {
            host: dataset.connection_config["host"],
            port: dataset.connection_config["port"],
            database: dataset.connection_config["database"]
          }
        }
      end
    end

    def test_connection
      with_connection do |client|
        client.database.command(ping: 1)
        true
      end
    rescue => e
      Rails.logger.error "MongoDB connection test failed: #{e.message}"
      false
    end

    private

    def analyze_collection_structure(database, collection_name)
      collection = database[collection_name]
      
      # Sample documents to infer schema
      sample_docs = collection.find.limit(100).to_a
      return [] if sample_docs.empty?

      # Collect all unique field paths
      field_paths = {}
      
      sample_docs.each do |doc|
        flatten_document(doc).each do |path, value|
          field_paths[path] ||= []
          field_paths[path] << value
        end
      end

      # Analyze each field
      field_paths.map do |path, values|
        {
          name: path,
          type: infer_column_type(values),
          nullable: values.any?(&:nil?),
          stats: calculate_column_stats(values)
        }
      end.sort_by { |f| f[:name] }
    end

    def flatten_document(doc, prefix = "")
      result = {}
      
      doc.each do |key, value|
        field_path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        
        case value
        when Hash
          result.merge!(flatten_document(value, field_path))
        when Array
          # Just track that it's an array
          result[field_path] = value
        else
          result[field_path] = value
        end
      end
      
      result
    end

    def with_connection
      require "mongo"
      
      client = Mongo::Client.new([ connection_string ], connection_options)
      yield client
    ensure
      client&.close
    end

    def connection_string
      host = dataset.connection_config["host"] || "localhost"
      port = dataset.connection_config["port"] || 27017
      "#{host}:#{port}"
    end

    def connection_options
      {
        database: dataset.connection_config["database"],
        user: dataset.connection_config["username"],
        password: dataset.connection_config["encrypted_password"]
      }.compact
    end
  end
end

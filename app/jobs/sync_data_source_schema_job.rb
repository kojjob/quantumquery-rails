class SyncDataSourceSchemaJob < ApplicationJob
  queue_as :low

  def perform(data_source_connection)
    return unless data_source_connection.connected?

    connector = data_source_connection.connector_class.new(data_source_connection)
    
    # Get list of tables
    tables = connector.list_tables
    
    # Get schemas if supported
    schemas = connector.respond_to?(:list_schemas) ? connector.list_schemas : []
    
    # Get databases if supported
    databases = connector.respond_to?(:list_databases) ? connector.list_databases : []
    
    # Store metadata
    data_source_connection.update!(
      metadata: data_source_connection.metadata.merge(
        tables: tables,
        schemas: schemas,
        databases: databases,
        last_schema_sync_at: Time.current
      )
    )
    
    # Get detailed schema for each table (limit to first 20 tables for performance)
    table_schemas = {}
    tables.first(20).each do |table_name|
      table_schemas[table_name] = connector.get_table_schema(table_name)
    rescue => e
      Rails.logger.error "Failed to get schema for table #{table_name}: #{e.message}"
    end
    
    data_source_connection.update!(
      metadata: data_source_connection.metadata.merge(
        table_schemas: table_schemas
      )
    )
  rescue => e
    Rails.logger.error "Schema sync failed: #{e.message}"
    data_source_connection.update!(
      last_error_at: Time.current,
      last_error_message: "Schema sync failed: #{e.message}"
    )
  end
end
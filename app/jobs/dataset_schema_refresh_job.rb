# app/jobs/dataset_schema_refresh_job.rb
class DatasetSchemaRefreshJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(dataset)
    Rails.logger.info "Refreshing schema for dataset #{dataset.id} (#{dataset.name})"

    # Build appropriate introspector
    introspector = SchemaIntrospection::IntrospectorFactory.build(dataset)

    # Test connection first
    unless introspector.test_connection
      dataset.update!(
        status: :error,
        last_error: "Failed to connect to data source"
      )
      return
    end

    # Introspect schema
    schema = introspector.introspect

    # Update dataset with schema metadata
    dataset.update!(
      schema_metadata: schema,
      status: :ready,
      last_connected_at: Time.current,
      last_error: nil
    )

    # Cache the formatted schema for AI
    cache_schema_for_ai(dataset, schema)

    Rails.logger.info "Successfully refreshed schema for dataset #{dataset.id}"
  rescue => e
    Rails.logger.error "Schema refresh failed for dataset #{dataset.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    dataset.update!(
      status: :error,
      last_error: "Schema introspection failed: #{e.message}"
    )

    raise e
  end

  private

  def cache_schema_for_ai(dataset, schema)
    introspector = SchemaIntrospection::IntrospectorFactory.build(dataset)
    formatted_schema = introspector.send(:format_for_ai, schema)

    Rails.cache.write(
      "dataset_schema_ai:#{dataset.id}",
      formatted_schema,
      expires_in: 1.hour
    )
  end
end

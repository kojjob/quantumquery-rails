class RefreshCacheJob < ApplicationJob
  queue_as :default

  def perform(cache_entry_id)
    cache_entry = QueryCache.find_by(id: cache_entry_id)
    return unless cache_entry

    # Find the dataset and organization
    dataset = cache_entry.dataset
    organization = cache_entry.organization

    # Re-execute the query to refresh the cache
    service = QueryCacheService.new(organization, dataset)

    # Use the AI analysis service to re-execute the query
    analysis_service = AiAnalysisService.new(
      dataset: dataset,
      organization: organization
    )

    begin
      result = analysis_service.analyze(cache_entry.query_text)

      # Update the cache entry with fresh results
      cache_entry.update!(
        results: result,
        expires_at: QueryCache.calculate_expiration(result),
        query_execution_time: cache_entry.metadata["execution_time"]
      )

      Rails.logger.info "Successfully refreshed cache entry #{cache_entry_id}"
    rescue => e
      Rails.logger.error "Failed to refresh cache entry #{cache_entry_id}: #{e.message}"
      # Mark the cache entry as expired if refresh fails
      cache_entry.update!(expires_at: Time.current)
    end
  end
end

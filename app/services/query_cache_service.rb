class QueryCacheService
  attr_reader :organization, :dataset, :options

  def initialize(organization, dataset, options = {})
    @organization = organization
    @dataset = dataset
    @options = options
  end

  # Main method to execute query with caching
  def execute_with_cache(query_text, &block)
    # Check if caching is enabled
    return yield if caching_disabled?
    
    # Try to find cached result
    cached_result = find_cached_result(query_text)
    
    if cached_result
      Rails.logger.info "Cache HIT for query: #{query_text[0..100]}"
      track_cache_hit(query_text)
      return cached_result
    end
    
    Rails.logger.info "Cache MISS for query: #{query_text[0..100]}"
    track_cache_miss(query_text)
    
    # Execute the query
    start_time = Time.current
    result = yield
    execution_time = Time.current - start_time
    
    # Cache the result if it's cacheable
    if cacheable_result?(result)
      cache_result(query_text, result, execution_time)
    end
    
    result
  end
  
  # Invalidate cache for a dataset
  def invalidate_dataset_cache!
    QueryCache
      .where(dataset: dataset, organization: organization)
      .update_all(expires_at: Time.current)
  end
  
  # Clear all expired cache entries
  def clear_expired_cache!
    QueryCache.cleanup_expired!
  end
  
  # Get cache statistics
  def cache_statistics
    total_entries = QueryCache.by_organization(organization).count
    active_entries = QueryCache.by_organization(organization).active.count
    total_size = QueryCache.organization_cache_size(organization)
    
    popular_queries = QueryCache
      .by_organization(organization)
      .active
      .popular
      .limit(10)
      .pluck(:query_text, :access_count)
    
    {
      total_entries: total_entries,
      active_entries: active_entries,
      expired_entries: total_entries - active_entries,
      total_size_mb: (total_size / 1.megabyte.to_f).round(2),
      hit_rate: calculate_hit_rate,
      popular_queries: popular_queries,
      cache_enabled: cache_enabled?
    }
  end
  
  # Warm the cache with common queries
  def warm_cache(queries)
    queries.each do |query_text|
      execute_with_cache(query_text) do
        # Execute actual query here
        # This would typically call the AI analysis service
        { data: { message: "Warming cache for: #{query_text}" } }
      end
    end
  end
  
  private
  
  def find_cached_result(query_text)
    return nil unless cache_enabled?
    
    QueryCache.find_cached_result(
      query_text,
      dataset.id,
      organization.id
    )
  end
  
  def cache_result(query_text, result, execution_time)
    return unless cache_enabled?
    return unless cacheable_result?(result)
    
    # Check cache size limits
    enforce_cache_limits!
    
    metadata = {
      ai_model: options[:ai_model] || 'default',
      execution_time: execution_time,
      user_id: options[:user_id],
      request_id: options[:request_id],
      cached_at: Time.current
    }
    
    QueryCache.cache_result(
      query_text,
      dataset.id,
      organization.id,
      result,
      metadata
    )
  rescue => e
    Rails.logger.error "Failed to cache query result: #{e.message}"
    # Don't fail the request if caching fails
  end
  
  def cacheable_result?(result)
    return false if result.nil?
    return false if result.is_a?(Hash) && result[:error].present?
    return false if result.to_json.bytesize > max_cache_size_bytes
    
    true
  end
  
  def cache_enabled?
    return false if options[:skip_cache] == true
    return false if ENV['DISABLE_QUERY_CACHE'] == 'true'
    
    # Check organization settings
    organization_cache_enabled = organization.settings&.dig('cache', 'enabled')
    organization_cache_enabled != false
  end
  
  def caching_disabled?
    !cache_enabled?
  end
  
  def max_cache_size_bytes
    # 10MB default max size per cache entry
    ENV.fetch('MAX_CACHE_ENTRY_SIZE', 10.megabytes).to_i
  end
  
  def enforce_cache_limits!
    # Enforce organization cache size limit (default 1GB)
    max_org_cache_size = ENV.fetch('MAX_ORG_CACHE_SIZE_MB', 1000).to_i
    current_size_mb = QueryCache.organization_cache_size(organization) / 1.megabyte.to_f
    
    if current_size_mb > max_org_cache_size
      # Remove least recently used entries
      QueryCache.purge_least_recently_used(organization, max_org_cache_size * 0.8)
    end
  end
  
  def track_cache_hit(query_text)
    Rails.cache.increment("cache_hits:#{organization.id}:#{Date.current}")
    Rails.cache.increment("cache_hits:total:#{Date.current}")
  end
  
  def track_cache_miss(query_text)
    Rails.cache.increment("cache_misses:#{organization.id}:#{Date.current}")
    Rails.cache.increment("cache_misses:total:#{Date.current}")
  end
  
  def calculate_hit_rate
    hits = Rails.cache.read("cache_hits:#{organization.id}:#{Date.current}") || 0
    misses = Rails.cache.read("cache_misses:#{organization.id}:#{Date.current}") || 0
    total = hits + misses
    
    return 0 if total.zero?
    
    ((hits.to_f / total) * 100).round(2)
  end
end
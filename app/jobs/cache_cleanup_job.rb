class CacheCleanupJob < ApplicationJob
  queue_as :low_priority

  def perform
    # Clean up expired cache entries
    expired_count = QueryCache.cleanup_expired!
    Rails.logger.info "Cleaned up #{expired_count} expired cache entries"

    # Clean up cache for each organization that exceeds limits
    Organization.find_each do |organization|
      current_size_mb = QueryCache.organization_cache_size(organization) / 1.megabyte.to_f
      max_size_mb = ENV.fetch("MAX_ORG_CACHE_SIZE_MB", 1000).to_i

      if current_size_mb > max_size_mb
        QueryCache.purge_least_recently_used(organization, max_size_mb * 0.8)
        Rails.logger.info "Purged cache for organization #{organization.id} from #{current_size_mb}MB to target"
      end
    end
  end
end

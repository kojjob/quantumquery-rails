class QueryCache < ApplicationRecord
  belongs_to :dataset
  belongs_to :organization

  # Validations
  validates :query_hash, presence: true, uniqueness: true
  validates :query_text, presence: true
  validates :results, presence: true

  # Scopes
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :by_organization, ->(org) { where(organization: org) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(access_count: :desc) }

  # Callbacks
  before_validation :generate_query_hash
  before_save :calculate_cache_size
  after_create :schedule_expiration_cleanup

  # Class methods for cache management
  class << self
    def find_cached_result(query_text, dataset_id, organization_id)
      cache_entry = active
        .find_by(
          query_hash: generate_hash(query_text, dataset_id),
          dataset_id: dataset_id,
          organization_id: organization_id
        )

      if cache_entry
        cache_entry.record_access!
        cache_entry.results
      else
        nil
      end
    end

    def cache_result(query_text, dataset_id, organization_id, results, metadata = {})
      query_hash = generate_hash(query_text, dataset_id)

      cache_entry = find_or_initialize_by(
        query_hash: query_hash,
        dataset_id: dataset_id,
        organization_id: organization_id
      )

      cache_entry.update!(
        query_text: query_text,
        results: results,
        metadata: metadata,
        expires_at: calculate_expiration(results),
        ai_model: metadata[:ai_model],
        query_execution_time: metadata[:execution_time]
      )

      cache_entry
    end

    def generate_hash(query_text, dataset_id)
      Digest::SHA256.hexdigest("#{query_text.downcase.strip}:#{dataset_id}")
    end

    def calculate_expiration(results)
      # Cache duration based on result size and complexity
      base_duration = 24.hours

      if results.is_a?(Hash)
        row_count = results.dig(:data, :rows)&.size || 0

        if row_count > 10000
          base_duration = 6.hours
        elsif row_count > 1000
          base_duration = 12.hours
        end
      end

      Time.current + base_duration
    end

    def cleanup_expired!
      expired.destroy_all
    end

    def organization_cache_size(organization)
      by_organization(organization).sum(:cache_size_bytes)
    end

    def purge_least_recently_used(organization, target_size_mb)
      target_bytes = target_size_mb * 1.megabyte
      current_size = organization_cache_size(organization)

      if current_size > target_bytes
        entries_to_remove = by_organization(organization)
          .order(accessed_at: :asc, access_count: :asc)
          .limit(100)

        entries_to_remove.each do |entry|
          entry.destroy
          current_size -= entry.cache_size_bytes
          break if current_size <= target_bytes
        end
      end
    end
  end

  # Instance methods
  def record_access!
    self.class.transaction do
      increment!(:access_count)
      touch(:accessed_at) if respond_to?(:accessed_at)
    end
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def hit_rate
    return 0 if access_count.zero?

    # Calculate based on metadata if available
    if metadata["total_queries"].present?
      (access_count.to_f / metadata["total_queries"]) * 100
    else
      access_count
    end
  end

  def size_in_mb
    cache_size_bytes / 1.megabyte.to_f
  end

  def refresh!
    # Re-execute the query and update cache
    RefreshCacheJob.perform_later(self)
  end

  def invalidate!
    update!(expires_at: Time.current)
  end

  private

  def generate_query_hash
    return if query_hash.present?

    self.query_hash = self.class.generate_hash(query_text, dataset_id)
  end

  def calculate_cache_size
    self.cache_size_bytes = results.to_json.bytesize
  end

  def schedule_expiration_cleanup
    CacheCleanupJob.set(wait_until: expires_at).perform_later if expires_at.present?
  end
end

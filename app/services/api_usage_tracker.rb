class ApiUsageTracker
  class << self
    def track(api_token:, endpoint:, ip_address:, user_agent:, response_code: nil, response_time: nil)
      ApiUsageLog.create!(
        api_token: api_token,
        endpoint: endpoint,
        ip_address: ip_address,
        user_agent: user_agent,
        response_code: response_code,
        response_time: response_time
      )
    rescue StandardError => e
      Rails.logger.error "Failed to track API usage: #{e.message}"
      # Don't fail the request if tracking fails
    end

    def check_rate_limit(api_token, limit_per_hour: 1000)
      recent_usage = ApiUsageLog.where(api_token: api_token)
                                 .where("created_at >= ?", 1.hour.ago)
                                 .count

      if recent_usage >= limit_per_hour
        return { allowed: false, remaining: 0, reset_at: 1.hour.from_now }
      end

      {
        allowed: true,
        remaining: limit_per_hour - recent_usage,
        reset_at: 1.hour.from_now
      }
    end
  end
end
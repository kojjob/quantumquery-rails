class ApiToken < ApplicationRecord
  belongs_to :user

  # Validations
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true

  # Scopes
  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where.not(expires_at: nil).where("expires_at <= ?", Time.current) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  # Callbacks
  before_validation :generate_token, on: :create
  before_save :serialize_scopes

  # Default scopes
  DEFAULT_SCOPES = %w[
    datasets:read
    datasets:write
    analysis:read
    analysis:write
    cache:read
    cache:manage
  ].freeze

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def has_scope?(scope)
    return false unless active?
    scopes_array.include?(scope.to_s) || scopes_array.include?("*")
  end

  def scopes_array
    return [] if scopes.blank?
    scopes.is_a?(Array) ? scopes : JSON.parse(scopes)
  rescue JSON::ParserError
    scopes.split(",").map(&:strip)
  end

  def usage_this_month
    ApiUsageLog.where(api_token: self)
               .where("created_at >= ?", Time.current.beginning_of_month)
               .count
  end

  def usage_today
    ApiUsageLog.where(api_token: self)
               .where("created_at >= ?", Time.current.beginning_of_day)
               .count
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def serialize_scopes
    self.scopes = scopes_array.to_json if scopes.is_a?(Array)
  end
end

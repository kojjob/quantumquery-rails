class ShareLink < ApplicationRecord
  belongs_to :analysis_request
  belongs_to :created_by, class_name: 'User'
  
  has_secure_password validations: false
  
  # Validations
  validates :token, presence: true, uniqueness: true
  validates :analysis_request, presence: true
  validates :created_by, presence: true
  
  # Callbacks
  before_validation :generate_token, on: :create
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def views_exceeded?
    max_views.present? && view_count >= max_views
  end
  
  def accessible?
    active? && !expired? && !views_exceeded?
  end
  
  def record_access!
    increment!(:access_count)
    increment!(:view_count) if view_count < (max_views || Float::INFINITY)
  end
  
  def deactivate!
    update!(active: false)
  end
  
  def public_url
    Rails.application.routes.url_helpers.shared_analysis_url(token: token)
  end
  
  def requires_password?
    password_digest.present?
  end
  
  def verify_password(password)
    return true unless requires_password?
    authenticate(password)
  end
  
  private
  
  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end

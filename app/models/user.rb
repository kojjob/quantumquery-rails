class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :two_factor_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         otp_secret_encryption_key: ENV.fetch("OTP_SECRET_KEY", Rails.application.credentials.otp_secret_key)
  
  devise :two_factor_backupable, otp_number_of_backup_codes: 10

  # Associations
  belongs_to :organization, optional: true
  has_many :analysis_requests, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  
  # User tiers for model access
  enum :subscription_tier, {
    free: 0,
    professional: 1,
    enterprise: 2,
    custom: 3
  }, prefix: true

  # Technical skill level for appropriate explanations
  enum :technical_level, {
    beginner: 0,
    intermediate: 1,
    advanced: 2,
    expert: 3
  }, default: :beginner

  def available_models
    case subscription_tier
    when 'free'
      ['gpt-3.5-turbo', 'mixtral-8x7b', 'llama3-8b']
    when 'professional'
      ['gpt-3.5-turbo', 'gpt-4', 'claude-3-sonnet', 'mixtral-8x7b', 'llama3-70b']
    when 'enterprise', 'custom'
      ['gpt-3.5-turbo', 'gpt-4', 'gpt-4-turbo', 'claude-3-opus', 'claude-3-sonnet', 
       'gemini-pro', 'gemini-ultra', 'command-r-plus', 'mixtral-8x7b', 'llama3-70b']
    else
      ['gpt-3.5-turbo']
    end
  end

  def monthly_query_limit
    case subscription_tier
    when 'free' then 100
    when 'professional' then 500
    when 'enterprise' then 2000
    when 'custom' then nil # unlimited
    else 100
    end
  end
  
  # Two-Factor Authentication helpers
  def two_factor_enabled?
    otp_required_for_login?
  end
  
  def enable_two_factor!
    self.otp_required_for_login = true
    self.two_factor_enabled_at = Time.current
    self.otp_secret = User.generate_otp_secret unless otp_secret.present?
    generate_otp_backup_codes!
    save!
  end
  
  def disable_two_factor!
    self.otp_required_for_login = false
    self.two_factor_enabled_at = nil
    self.otp_secret = nil
    self.otp_backup_codes = nil
    self.consumed_timestep = nil
    save!
  end
  
  def two_factor_qr_code_uri
    issuer = "QuantumQuery"
    label = "#{issuer}:#{email}"
    otp_provisioning_uri(label, issuer: issuer)
  end
end

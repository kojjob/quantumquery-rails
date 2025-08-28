class Organization < ApplicationRecord
  # Associations
  has_many :users, dependent: :destroy
  has_many :datasets, dependent: :destroy
  has_many :analysis_requests, dependent: :destroy
  has_many :scheduled_reports, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :team_members, through: :team_memberships, source: :user
  
  # Validations
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  
  # Callbacks
  before_validation :generate_slug
  
  # Subscription tiers
  enum :subscription_tier, {
    starter: 0,
    professional: 1,
    enterprise: 2,
    custom: 3
  }, prefix: true
  
  # Settings stored in JSONB
  store_accessor :settings, :allowed_models, :max_users, :max_datasets, 
                 :max_monthly_queries, :custom_model_endpoints, :data_retention_days
  
  def usage_this_month
    analysis_requests.where('created_at >= ?', Time.current.beginning_of_month).count
  end
  
  def at_query_limit?
    return false if subscription_tier_custom?
    usage_this_month >= (max_monthly_queries || default_monthly_limit)
  end
  
  private
  
  def generate_slug
    self.slug = name.parameterize if name.present? && slug.blank?
  end
  
  def default_monthly_limit
    case subscription_tier
    when 'starter' then 1000
    when 'professional' then 5000
    when 'enterprise' then 20000
    else 1000
    end
  end
end

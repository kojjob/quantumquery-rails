class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  # Associations
  belongs_to :organization, optional: true
  has_many :analysis_requests, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :dashboards, dependent: :destroy

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
    when "free"
      [ "gpt-3.5-turbo", "mixtral-8x7b", "llama3-8b" ]
    when "professional"
      [ "gpt-3.5-turbo", "gpt-4", "claude-3-sonnet", "mixtral-8x7b", "llama3-70b" ]
    when "enterprise", "custom"
      [ "gpt-3.5-turbo", "gpt-4", "gpt-4-turbo", "claude-3-opus", "claude-3-sonnet",
       "gemini-pro", "gemini-ultra", "command-r-plus", "mixtral-8x7b", "llama3-70b" ]
    else
      [ "gpt-3.5-turbo" ]
    end
  end

  def monthly_query_limit
    case subscription_tier
    when "free" then 100
    when "professional" then 500
    when "enterprise" then 2000
    when "custom" then nil # unlimited
    else 100
    end
  end
end

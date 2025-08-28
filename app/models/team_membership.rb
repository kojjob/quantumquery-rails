class TeamMembership < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :invited_by, class_name: 'User', optional: true
  
  # Enums
  enum :role, {
    viewer: 0,
    editor: 1,
    admin: 2,
    owner: 3
  }
  
  # Validations
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :organization_id, message: "is already a member of this organization" }
  validates :invitation_token, uniqueness: true, allow_nil: true
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :pending, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }
  
  # Callbacks
  before_create :generate_invitation_token, if: -> { accepted_at.nil? }
  before_create :set_expiration_date, if: -> { accepted_at.nil? }
  
  def pending?
    accepted_at.nil?
  end
  
  def accepted?
    accepted_at.present?
  end
  
  def expired?
    pending? && invitation_expires_at < Time.current
  end
  
  def accept!
    update!(accepted_at: Time.current, invitation_token: nil, invitation_expires_at: nil)
  end
  
  def can_edit?
    editor? || admin? || owner?
  end
  
  def can_manage_team?
    admin? || owner?
  end
  
  def can_delete?
    owner?
  end
  
  private
  
  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end
  
  def set_expiration_date
    self.invitation_expires_at = 7.days.from_now
  end
end

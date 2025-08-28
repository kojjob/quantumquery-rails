class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :user
  
  # Validations
  validates :content, presence: true, length: { minimum: 1, maximum: 5000 }
  validates :user, presence: true
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :oldest, -> { order(created_at: :asc) }
  
  # Callbacks
  before_update :mark_as_edited
  
  def edited?
    edited
  end
  
  def author_name
    user.email.split('@').first
  end
  
  def formatted_time
    if created_at > 1.day.ago
      "#{time_ago_in_words(created_at)} ago"
    else
      created_at.strftime("%B %d, %Y at %l:%M %p")
    end
  end
  
  private
  
  def mark_as_edited
    if content_changed?
      self.edited = true
      self.edited_at = Time.current
    end
  end
  
  def time_ago_in_words(time)
    ActionController::Base.helpers.time_ago_in_words(time)
  end
end

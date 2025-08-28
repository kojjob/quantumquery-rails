class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  protected
  
  def ensure_organization!
    return if current_user.nil? || current_user.organization.present?
    
    # Create a default organization for the user if they don't have one
    org = Organization.create!(
      name: "#{current_user.email.split('@').first}'s Organization",
      settings: { created_from: 'auto_creation' }
    )
    
    current_user.update!(organization: org)
  end
end

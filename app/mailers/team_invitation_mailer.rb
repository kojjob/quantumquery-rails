class TeamInvitationMailer < ApplicationMailer
  def existing_user_invitation(team_membership)
    @membership = team_membership
    @organization = @membership.organization
    @invited_by = @membership.invited_by
    @invitation_url = accept_invitation_url(token: @membership.invitation_token)
    
    mail(
      to: @membership.user.email,
      subject: "You've been invited to join #{@organization.name} on QuantumQuery"
    )
  end
  
  def new_user_invitation(team_membership)
    @membership = team_membership
    @organization = @membership.organization
    @invited_by = @membership.invited_by
    @invitation_url = accept_invitation_url(token: @membership.invitation_token)
    
    mail(
      to: @membership.user.email,
      subject: "You're invited to join #{@organization.name} on QuantumQuery"
    )
  end
end
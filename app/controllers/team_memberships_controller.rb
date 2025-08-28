class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :ensure_admin_access, except: [:index, :accept_invitation]
  before_action :set_membership, only: [:update, :destroy, :resend_invitation]

  def index
    @team_memberships = @organization.team_memberships
                                      .includes(:user, :invited_by)
                                      .active
    
    @current_user_membership = @team_memberships.find_by(user: current_user)
    @pending_invitations = @team_memberships.pending
    @active_members = @team_memberships.accepted
  end

  def create
    @membership = @organization.team_memberships.build(membership_params)
    @membership.invited_by = current_user
    
    # Check if user exists or create invitation
    user = User.find_by(email: params[:email])
    
    if user
      @membership.user = user
      if @membership.save
        TeamInvitationMailer.existing_user_invitation(@membership).deliver_later
        render json: { 
          success: true, 
          message: "Invitation sent to #{params[:email]}"
        }
      else
        render json: { 
          success: false, 
          errors: @membership.errors.full_messages 
        }, status: :unprocessable_entity
      end
    else
      # Create pending invitation for new user
      @membership.user = User.invite!(email: params[:email])
      if @membership.save
        TeamInvitationMailer.new_user_invitation(@membership).deliver_later
        render json: { 
          success: true, 
          message: "Invitation sent to #{params[:email]}. They'll need to create an account."
        }
      else
        render json: { 
          success: false, 
          errors: @membership.errors.full_messages 
        }, status: :unprocessable_entity
      end
    end
  end

  def accept_invitation
    @membership = TeamMembership.find_by!(invitation_token: params[:token])
    
    if @membership.expired?
      flash[:alert] = "This invitation has expired"
      redirect_to root_path
    elsif @membership.user == current_user
      @membership.accept!
      flash[:notice] = "You've joined #{@membership.organization.name}!"
      redirect_to dashboard_path
    else
      flash[:alert] = "This invitation is for a different user"
      redirect_to root_path
    end
  end

  def update
    if @membership.update(membership_params)
      render json: { 
        success: true, 
        message: "Team member role updated"
      }
    else
      render json: { 
        success: false, 
        errors: @membership.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  def destroy
    if @membership.owner?
      render json: { 
        success: false, 
        error: "Cannot remove the organization owner" 
      }, status: :forbidden
    else
      @membership.destroy
      render json: { 
        success: true, 
        message: "Team member removed"
      }
    end
  end

  def resend_invitation
    if @membership.invitation_accepted_at.present?
      render json: { 
        success: false, 
        error: "This member has already accepted the invitation" 
      }, status: :unprocessable_entity
    else
      @membership.regenerate_invitation_token
      
      if @membership.user.created_at.present?
        TeamInvitationMailer.existing_user_invitation(@membership).deliver_later
      else
        TeamInvitationMailer.new_user_invitation(@membership).deliver_later
      end
      
      render json: { 
        success: true, 
        message: "Invitation resent successfully"
      }
    end
  end

  private

  def set_organization
    @organization = current_user.organization || 
                   current_user.organizations_as_member.find(params[:organization_id])
  end

  def ensure_admin_access
    membership = current_user.team_memberships.find_by(organization: @organization)
    unless membership&.can_manage_team?
      render json: { 
        error: "You don't have permission to manage team members" 
      }, status: :forbidden
    end
  end

  def set_membership
    @membership = @organization.team_memberships.find(params[:id])
  end

  def membership_params
    params.require(:team_membership).permit(:role)
  end
end
class ShareLinksController < ApplicationController
  before_action :authenticate_user!, except: [:show, :authenticate]
  before_action :set_analysis_request, only: [:create]
  before_action :set_share_link, only: [:destroy, :update]
  before_action :set_share_link_by_token, only: [:show, :authenticate]

  def create
    @share_link = @analysis_request.share_links.build(share_link_params)
    @share_link.created_by = current_user
    
    if @share_link.save
      render json: { 
        success: true, 
        share_url: shared_analysis_url(token: @share_link.token),
        share_link: @share_link.slice(:id, :token, :expires_at, :max_views, :requires_password?)
      }
    else
      render json: { success: false, errors: @share_link.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    if @share_link.accessible?
      if @share_link.requires_password? && !session["share_link_#{@share_link.token}_authenticated"]
        render :password_required
      else
        @share_link.record_access!
        @analysis_request = @share_link.analysis_request
        @read_only = true
        render 'analysis_requests/show'
      end
    else
      render :link_expired
    end
  end

  def authenticate
    if @share_link.verify_password(params[:password])
      session["share_link_#{@share_link.token}_authenticated"] = true
      redirect_to shared_analysis_path(token: @share_link.token)
    else
      flash.now[:alert] = "Incorrect password"
      render :password_required
    end
  end

  def update
    if @share_link.update(share_link_params)
      render json: { success: true, share_link: @share_link }
    else
      render json: { success: false, errors: @share_link.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @share_link.deactivate!
    render json: { success: true, message: "Share link has been deactivated" }
  end

  private

  def set_analysis_request
    @analysis_request = current_user.analysis_requests.find(params[:analysis_request_id])
  end

  def set_share_link
    @share_link = current_user.share_links.find(params[:id])
  end

  def set_share_link_by_token
    @share_link = ShareLink.find_by!(token: params[:token])
  end

  def share_link_params
    params.require(:share_link).permit(:expires_at, :max_views, :password)
  end
end
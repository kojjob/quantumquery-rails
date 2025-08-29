class ApiTokensController < ApplicationController
  before_action :authenticate_user!
  before_action :set_api_token, only: [ :show, :revoke, :destroy ]

  def index
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
  end

  def new
    @api_token = current_user.api_tokens.build
  end

  def create
    @api_token = current_user.api_tokens.build(api_token_params)
    @api_token.scopes = params[:api_token][:scopes] if params[:api_token][:scopes].present?

    if @api_token.save
      flash[:notice] = "API token created successfully. Please copy your token now as it won't be shown again."
      redirect_to api_token_path(@api_token)
    else
      render :new
    end
  end

  def show
    # Token is only shown once after creation
    @show_token = @api_token.created_at > 1.minute.ago
  end

  def revoke
    @api_token.revoke!
    redirect_to api_tokens_path, notice: "API token has been revoked."
  end

  def destroy
    @api_token.destroy
    redirect_to api_tokens_path, notice: "API token has been deleted."
  end

  private

  def set_api_token
    @api_token = current_user.api_tokens.find(params[:id])
  end

  def api_token_params
    params.require(:api_token).permit(:name, :expires_at, scopes: [])
  end
end

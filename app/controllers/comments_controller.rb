class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_commentable
  before_action :set_comment, only: [:edit, :update, :destroy]

  def index
    @comments = @commentable.comments.includes(:user).recent
    render json: @comments.map { |comment| serialize_comment(comment) }
  end

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      broadcast_comment_created
      render json: { success: true, comment: serialize_comment(@comment) }
    else
      render json: { success: false, errors: @comment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @comment.user == current_user
      if @comment.update(comment_params)
        broadcast_comment_updated
        render json: { success: true, comment: serialize_comment(@comment) }
      else
        render json: { success: false, errors: @comment.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { success: false, error: "You can only edit your own comments" }, status: :forbidden
    end
  end

  def destroy
    if @comment.user == current_user || current_user_can_moderate?
      @comment.destroy
      broadcast_comment_deleted
      render json: { success: true, message: "Comment deleted" }
    else
      render json: { success: false, error: "You can only delete your own comments" }, status: :forbidden
    end
  end

  private

  def set_commentable
    if params[:analysis_request_id]
      @commentable = current_user.organization.analysis_requests.find(params[:analysis_request_id])
    elsif params[:dataset_id]
      @commentable = current_user.organization.datasets.find(params[:dataset_id])
    else
      render json: { error: "Commentable resource not found" }, status: :not_found
    end
  end

  def set_comment
    @comment = @commentable.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:content)
  end

  def serialize_comment(comment)
    {
      id: comment.id,
      content: comment.content,
      author: comment.author_name,
      author_id: comment.user_id,
      created_at: comment.created_at,
      formatted_time: comment.formatted_time,
      edited: comment.edited?,
      edited_at: comment.edited_at,
      can_edit: comment.user == current_user,
      can_delete: comment.user == current_user || current_user_can_moderate?
    }
  end

  def current_user_can_moderate?
    return false unless current_user.organization
    membership = current_user.team_memberships.find_by(organization: @commentable.organization)
    membership&.can_manage_team?
  end

  def broadcast_comment_created
    ActionCable.server.broadcast(
      "comments_#{@commentable.class.name.underscore}_#{@commentable.id}",
      {
        action: 'created',
        comment: serialize_comment(@comment)
      }
    )
  end

  def broadcast_comment_updated
    ActionCable.server.broadcast(
      "comments_#{@commentable.class.name.underscore}_#{@commentable.id}",
      {
        action: 'updated',
        comment: serialize_comment(@comment)
      }
    )
  end

  def broadcast_comment_deleted
    ActionCable.server.broadcast(
      "comments_#{@commentable.class.name.underscore}_#{@commentable.id}",
      {
        action: 'deleted',
        comment_id: @comment.id
      }
    )
  end
end
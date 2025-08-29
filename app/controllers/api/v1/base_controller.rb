module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_api_token!
      before_action :set_default_format
      before_action :track_api_usage

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
      rescue_from ActionController::ParameterMissing, with: :bad_request

      private

      def authenticate_api_token!
        authenticate_or_request_with_http_token do |token, _options|
          @api_token = ApiToken.active.find_by(token: token)
          if @api_token
            @api_token.update!(last_used_at: Time.current)
            @current_user = @api_token.user
            @current_organization = @current_user.organization
            true
          else
            false
          end
        end
      end

      def set_default_format
        request.format = :json unless params[:format]
      end

      def track_api_usage
        return unless @api_token

        ApiUsageTracker.track(
          api_token: @api_token,
          endpoint: "#{controller_name}##{action_name}",
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def not_found(exception)
        render json: {
          error: "Resource not found",
          message: exception.message
        }, status: :not_found
      end

      def unprocessable_entity(exception)
        render json: {
          error: "Validation failed",
          message: exception.message,
          errors: exception.record.errors.full_messages
        }, status: :unprocessable_entity
      end

      def bad_request(exception)
        render json: {
          error: "Bad request",
          message: exception.message
        }, status: :bad_request
      end

      def paginate(collection)
        collection.page(params[:page]).per(params[:per_page] || 25)
      end

      def render_success(data, status: :ok)
        render json: {
          success: true,
          data: data
        }, status: status
      end

      def render_error(message, status: :unprocessable_entity)
        render json: {
          success: false,
          error: message
        }, status: status
      end
    end
  end
end
module Users
  class SessionsController < Devise::SessionsController
    prepend_before_action :check_otp, only: [:create]
    
    private
    
    def check_otp
      if params[:user][:otp_attempt].present?
        authenticate_with_otp
      end
    end
    
    def authenticate_with_otp
      user = find_user
      
      if user && user.otp_required_for_login?
        if user.validate_and_consume_otp!(params[:user][:otp_attempt]) ||
           user.invalidate_otp_backup_code!(params[:user][:otp_attempt])
          # OTP is valid, continue with normal authentication
          return
        else
          # Invalid OTP
          sign_out(user) if signed_in?(user)
          flash[:alert] = "Invalid authentication code."
          redirect_to new_user_session_path and return
        end
      end
    end
    
    def find_user
      User.find_by(email: params[:user][:email])
    end
  end
end
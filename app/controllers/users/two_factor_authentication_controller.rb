module Users
  class TwoFactorAuthenticationController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_otp_secret_exists, only: [:show, :enable]
    
    def show
      @qr_code = generate_qr_code
      @backup_codes = current_user.otp_backup_codes if current_user.two_factor_enabled?
    end
    
    def enable
      if current_user.validate_and_consume_otp!(params[:otp_code])
        current_user.enable_two_factor!
        @backup_codes = current_user.otp_backup_codes
        flash[:notice] = "Two-factor authentication has been enabled successfully."
        render :backup_codes
      else
        flash[:alert] = "Invalid verification code. Please try again."
        redirect_to users_two_factor_authentication_path
      end
    end
    
    def disable
      if params[:confirm] == "DISABLE"
        current_user.disable_two_factor!
        flash[:notice] = "Two-factor authentication has been disabled."
        redirect_to edit_user_registration_path
      else
        flash[:alert] = "Please type DISABLE to confirm."
        redirect_to users_two_factor_authentication_path
      end
    end
    
    def regenerate_backup_codes
      if current_user.two_factor_enabled?
        current_user.generate_otp_backup_codes!
        current_user.save!
        @backup_codes = current_user.otp_backup_codes
        flash[:notice] = "New backup codes have been generated."
        render :backup_codes
      else
        redirect_to users_two_factor_authentication_path
      end
    end
    
    private
    
    def ensure_otp_secret_exists
      unless current_user.otp_secret.present?
        current_user.otp_secret = User.generate_otp_secret
        current_user.save!
      end
    end
    
    def generate_qr_code
      qr_code_uri = current_user.two_factor_qr_code_uri
      qrcode = RQRCode::QRCode.new(qr_code_uri)
      
      # Generate SVG for the QR code
      qrcode.as_svg(
        color: "000",
        shape_rendering: "crispEdges",
        module_size: 4,
        standalone: true,
        use_path: true
      )
    end
  end
end
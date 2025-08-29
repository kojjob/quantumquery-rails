# Configure OTP secret encryption key
# In production, use Rails credentials or environment variables
Rails.application.config.after_initialize do
  otp_key = ENV.fetch("OTP_SECRET_KEY") do
    if Rails.env.production?
      Rails.application.credentials.otp_secret_key
    else
      # Development/test key - DO NOT use in production
      "bf93a5d2b02d86a45866a16f15c1369783b464a5c4f09a5950ceb0a56fb38f0ad0f2cc3962864f2390ae2e3c95d21246ad8e245ec831c206f44e54705a8c73fa"
    end
  end
  
  # Ensure the key is set
  if otp_key.blank?
    raise "OTP_SECRET_KEY is not set. Please set it in credentials or environment variables."
  end
end
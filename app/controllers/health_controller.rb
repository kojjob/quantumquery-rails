class HealthController < ApplicationController
  skip_before_action :authenticate_user!, if: -> { defined?(authenticate_user!) }

  def show
    render json: { status: "ok", timestamp: Time.current }, status: :ok
  end
end

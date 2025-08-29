class ScheduledReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_scheduled_report, only: [ :show, :edit, :update, :destroy, :enable, :disable, :run_now ]
  before_action :set_datasets, only: [ :new, :create, :edit, :update ]

  def index
    @scheduled_reports = current_user.scheduled_reports
                                    .includes(:dataset)
                                    .order(created_at: :desc)

    @scheduled_reports = @scheduled_reports.enabled if params[:status] == "enabled"
    @scheduled_reports = @scheduled_reports.where(frequency: params[:frequency]) if params[:frequency].present?

    @scheduled_reports = @scheduled_reports.page(params[:page])
  end

  def show
    @recent_runs = @scheduled_report.user.analysis_requests
                                        .where("metadata->>'scheduled_report_id' = ?", @scheduled_report.id.to_s)
                                        .order(created_at: :desc)
                                        .limit(10)
  end

  def new
    @scheduled_report = current_user.scheduled_reports.build(
      enabled: true,
      frequency: "weekly",
      schedule_hour: 9,
      schedule_day: 1,
      format: "pdf"
    )
  end

  def create
    @scheduled_report = current_user.scheduled_reports.build(scheduled_report_params)
    @scheduled_report.organization = current_user.organization

    if @scheduled_report.save
      redirect_to @scheduled_report, notice: "Scheduled report was successfully created."
    else
      set_datasets
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @scheduled_report.update(scheduled_report_params)
      redirect_to @scheduled_report, notice: "Scheduled report was successfully updated."
    else
      set_datasets
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @scheduled_report.destroy!
    redirect_to scheduled_reports_url, notice: "Scheduled report was successfully deleted."
  end

  def enable
    @scheduled_report.update!(enabled: true)
    redirect_back(fallback_location: scheduled_reports_path, notice: "Scheduled report has been enabled.")
  end

  def disable
    @scheduled_report.update!(enabled: false)
    redirect_back(fallback_location: scheduled_reports_path, notice: "Scheduled report has been disabled.")
  end

  def run_now
    if @scheduled_report.run!
      flash[:notice] = "Report is being generated and will be sent to the configured recipients."
    else
      flash[:alert] = "Failed to generate report. Please try again."
    end
    redirect_back(fallback_location: @scheduled_report)
  end

  private

  def set_scheduled_report
    @scheduled_report = current_user.scheduled_reports.find(params[:id])
  end

  def set_datasets
    @datasets = current_user.organization&.datasets || Dataset.none
  end

  def scheduled_report_params
    params.require(:scheduled_report).permit(
      :name, :query, :dataset_id, :frequency, :format,
      :schedule_hour, :schedule_day, :enabled,
      recipients: []
    ).tap do |params|
      # Ensure recipients is an array of strings
      if params[:recipients].is_a?(String)
        params[:recipients] = params[:recipients].split(",").map(&:strip)
      end
    end
  end
end

# app/jobs/scheduled_report_runner_job.rb
class ScheduledReportRunnerJob < ApplicationJob
  queue_as :scheduled_reports

  # This job runs periodically to check and execute due scheduled reports
  def perform
    Rails.logger.info "Running scheduled reports check at #{Time.current}"

    reports_run = 0
    ScheduledReport.due_for_run.find_each do |report|
      if report.run!
        reports_run += 1
        Rails.logger.info "Successfully ran scheduled report #{report.id} - #{report.name}"
      else
        Rails.logger.error "Failed to run scheduled report #{report.id} - #{report.name}"
      end
    rescue => e
      Rails.logger.error "Error running scheduled report #{report.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    Rails.logger.info "Completed scheduled reports run. Ran #{reports_run} reports."
  end
end

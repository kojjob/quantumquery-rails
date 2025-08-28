# app/jobs/scheduled_report_delivery_job.rb
class ScheduledReportDeliveryJob < ApplicationJob
  queue_as :mailers
  
  def perform(scheduled_report, analysis_request)
    # Wait for analysis to complete
    unless analysis_request.completed?
      if analysis_request.failed?
        notify_failure(scheduled_report, analysis_request)
        return
      elsif analysis_request.processing?
        # Re-enqueue for later check
        ScheduledReportDeliveryJob.set(wait: 2.minutes).perform_later(scheduled_report, analysis_request)
        return
      end
    end
    
    # Generate the report in the requested format
    export_service = AnalysisExportService.new(analysis_request, scheduled_report.format)
    
    case scheduled_report.format
    when 'pdf'
      report_data = generate_pdf_report(analysis_request, export_service)
    when 'xlsx'
      report_data = export_service.export
    when 'csv'
      report_data = export_service.export
    else
      Rails.logger.error "Unknown report format: #{scheduled_report.format}"
      return
    end
    
    # Send to all recipients
    scheduled_report.recipient_list.each do |recipient|
      ScheduledReportMailer.deliver_report(
        scheduled_report: scheduled_report,
        analysis_request: analysis_request,
        recipient: recipient,
        report_data: report_data,
        format: scheduled_report.format
      ).deliver_later
    end
    
    Rails.logger.info "Delivered scheduled report #{scheduled_report.id} to #{scheduled_report.recipient_list.count} recipients"
  rescue => e
    Rails.logger.error "Failed to deliver scheduled report #{scheduled_report.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    notify_failure(scheduled_report, analysis_request, e.message)
  end
  
  private
  
  def generate_pdf_report(analysis_request, export_service)
    # For PDF, we need to generate it using WickedPDF
    # This would normally be done through the controller, but we can generate it here
    export_data = export_service.export
    
    pdf = WickedPdf.new.pdf_from_string(
      ApplicationController.renderer.render(
        template: 'analysis_requests/export',
        layout: 'pdf',
        assigns: { export_data: export_data }
      ),
      page_size: 'A4',
      orientation: 'portrait',
      margin: { top: 20, bottom: 20, left: 15, right: 15 }
    )
    
    pdf
  end
  
  def notify_failure(scheduled_report, analysis_request, error_message = nil)
    scheduled_report.recipient_list.each do |recipient|
      ScheduledReportMailer.report_failure(
        scheduled_report: scheduled_report,
        analysis_request: analysis_request,
        recipient: recipient,
        error_message: error_message || analysis_request.error_message
      ).deliver_later
    end
  end
end
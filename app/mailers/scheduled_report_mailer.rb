class ScheduledReportMailer < ApplicationMailer
  def deliver_report(scheduled_report:, analysis_request:, recipient:, report_data:, format:)
    @scheduled_report = scheduled_report
    @analysis_request = analysis_request
    @recipient = recipient
    @format = format
    
    filename = "#{@scheduled_report.name.parameterize}-#{Date.current}.#{format}"
    
    case format
    when 'pdf'
      attachments[filename] = {
        mime_type: 'application/pdf',
        content: report_data
      }
    when 'xlsx'
      attachments[filename] = {
        mime_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        content: report_data.read
      }
    when 'csv'
      attachments[filename] = {
        mime_type: 'text/csv',
        content: report_data
      }
    end
    
    mail(
      to: recipient,
      subject: "QuantumQuery Report: #{@scheduled_report.name} - #{Date.current}"
    )
  end
  
  def report_failure(scheduled_report:, analysis_request:, recipient:, error_message:)
    @scheduled_report = scheduled_report
    @analysis_request = analysis_request
    @recipient = recipient
    @error_message = error_message
    
    mail(
      to: recipient,
      subject: "QuantumQuery Report Failed: #{@scheduled_report.name}"
    )
  end
end
# app/services/analysis_export_service.rb
require 'csv'

class AnalysisExportService
  attr_reader :analysis_request, :format

  def initialize(analysis_request, format)
    @analysis_request = analysis_request
    @format = format.to_sym
  end

  def export
    case format
    when :pdf
      export_pdf
    when :xlsx
      export_excel
    when :csv
      export_csv
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  def export_pdf
    # PDF generation is handled by the controller using WickedPDF
    # This method returns the data needed for the PDF view
    {
      analysis: analysis_request,
      execution_steps: analysis_request.execution_steps.order(:sequence_number),
      metadata: prepare_metadata,
      summary: prepare_summary
    }
  end

  def export_excel
    package = Axlsx::Package.new
    workbook = package.workbook

    # Summary sheet
    workbook.add_worksheet(name: "Summary") do |sheet|
      add_summary_sheet(sheet)
    end

    # Execution steps sheet
    workbook.add_worksheet(name: "Execution Steps") do |sheet|
      add_execution_steps_sheet(sheet)
    end

    # Results sheet
    if analysis_request.completed?
      workbook.add_worksheet(name: "Results") do |sheet|
        add_results_sheet(sheet)
      end
    end

    # Metadata sheet
    workbook.add_worksheet(name: "Metadata") do |sheet|
      add_metadata_sheet(sheet)
    end

    package.to_stream
  end

  def export_csv
    CSV.generate do |csv|
      # Header section
      csv << ["Analysis Request Export"]
      csv << ["Generated at", Time.current.strftime("%Y-%m-%d %H:%M:%S")]
      csv << []

      # Query information
      csv << ["Query Information"]
      csv << ["Query", analysis_request.natural_language_query]
      csv << ["Status", analysis_request.status.humanize]
      csv << ["Dataset", analysis_request.dataset&.name]
      csv << ["Created", analysis_request.created_at.strftime("%Y-%m-%d %H:%M:%S")]
      csv << ["Completed", analysis_request.completed_at&.strftime("%Y-%m-%d %H:%M:%S") || "N/A"]
      csv << []

      # Execution steps
      csv << ["Execution Steps"]
      csv << ["Step Type", "Status", "Language", "Duration (ms)", "Description"]
      
      analysis_request.execution_steps.order(:sequence_number).each do |step|
        csv << [
          step.step_type,
          step.status,
          step.language,
          step.execution_time_ms || "N/A",
          step.description || "N/A"
        ]
      end
      csv << []

      # Results summary
      if analysis_request.completed?
        csv << ["Results Summary"]
        if analysis_request.final_results.present?
          flatten_hash(analysis_request.final_results).each do |key, value|
            csv << [key, value]
          end
        end
      end
    end
  end

  def add_summary_sheet(sheet)
    # Styling
    title_style = sheet.workbook.styles.add_style(
      b: true, 
      sz: 14, 
      alignment: { horizontal: :left }
    )
    header_style = sheet.workbook.styles.add_style(
      b: true,
      bg_color: "E0E0E0",
      alignment: { horizontal: :left }
    )
    
    # Title
    sheet.add_row ["Analysis Request Summary"], style: title_style
    sheet.add_row []
    
    # Basic information
    sheet.add_row ["Field", "Value"], style: header_style
    sheet.add_row ["Query", analysis_request.natural_language_query]
    sheet.add_row ["Status", analysis_request.status.humanize]
    sheet.add_row ["Dataset", analysis_request.dataset&.name || "N/A"]
    sheet.add_row ["User", analysis_request.user.email]
    sheet.add_row ["Organization", analysis_request.organization.name]
    sheet.add_row ["Created", analysis_request.created_at.strftime("%Y-%m-%d %H:%M:%S")]
    sheet.add_row ["Completed", analysis_request.completed_at&.strftime("%Y-%m-%d %H:%M:%S") || "N/A"]
    sheet.add_row ["Complexity Score", analysis_request.complexity_score || "N/A"]
    
    # Column widths
    sheet.column_widths 20, 50
  end

  def add_execution_steps_sheet(sheet)
    header_style = sheet.workbook.styles.add_style(
      b: true,
      bg_color: "E0E0E0",
      alignment: { horizontal: :center }
    )
    
    # Headers
    sheet.add_row [
      "Sequence",
      "Step Type",
      "Status",
      "Language",
      "Duration (ms)",
      "Description"
    ], style: header_style
    
    # Data rows
    analysis_request.execution_steps.order(:sequence_number).each do |step|
      sheet.add_row [
        step.sequence_number,
        step.step_type,
        step.status,
        step.language,
        step.execution_time_ms || "N/A",
        step.description || "N/A"
      ]
    end
    
    sheet.column_widths 10, 20, 15, 15, 15, 40
  end

  def add_results_sheet(sheet)
    header_style = sheet.workbook.styles.add_style(
      b: true,
      bg_color: "E0E0E0",
      alignment: { horizontal: :left }
    )
    
    sheet.add_row ["Analysis Results"], style: header_style
    sheet.add_row []
    
    if analysis_request.final_results.present?
      flatten_hash(analysis_request.final_results).each do |key, value|
        sheet.add_row [key, format_value(value)]
      end
    else
      sheet.add_row ["No results available"]
    end
    
    sheet.column_widths 30, 50
  end

  def add_metadata_sheet(sheet)
    header_style = sheet.workbook.styles.add_style(
      b: true,
      bg_color: "E0E0E0",
      alignment: { horizontal: :left }
    )
    
    sheet.add_row ["Analysis Metadata"], style: header_style
    sheet.add_row []
    
    # Intent analysis
    if analysis_request.analyzed_intent.present?
      sheet.add_row ["Intent Analysis"], style: header_style
      flatten_hash(analysis_request.analyzed_intent).each do |key, value|
        sheet.add_row [key, format_value(value)]
      end
      sheet.add_row []
    end
    
    # Data requirements
    if analysis_request.data_requirements.present?
      sheet.add_row ["Data Requirements"], style: header_style
      flatten_hash(analysis_request.data_requirements).each do |key, value|
        sheet.add_row [key, format_value(value)]
      end
      sheet.add_row []
    end
    
    # Additional metadata
    if analysis_request.metadata.present?
      sheet.add_row ["Additional Metadata"], style: header_style
      flatten_hash(analysis_request.metadata).each do |key, value|
        sheet.add_row [key, format_value(value)]
      end
    end
    
    sheet.column_widths 30, 50
  end

  def prepare_metadata
    {
      user: analysis_request.user.email,
      organization: analysis_request.organization.name,
      dataset: analysis_request.dataset&.name,
      created_at: analysis_request.created_at,
      completed_at: analysis_request.completed_at,
      complexity_score: analysis_request.complexity_score,
      total_execution_time: analysis_request.total_execution_time
    }
  end

  def prepare_summary
    {
      total_steps: analysis_request.execution_steps.count,
      completed_steps: analysis_request.execution_steps.where(status: 'completed').count,
      failed_steps: analysis_request.execution_steps.where(status: 'failed').count,
      models_used: analysis_request.metadata&.dig('selected_models'),
      tokens_used: analysis_request.metadata&.dig('total_tokens_used'),
      total_cost: analysis_request.metadata&.dig('total_cost')
    }
  end

  def flatten_hash(hash, parent_key = "", result = {})
    return result unless hash.is_a?(Hash)
    
    hash.each do |key, value|
      new_key = parent_key.empty? ? key.to_s : "#{parent_key}.#{key}"
      
      if value.is_a?(Hash)
        flatten_hash(value, new_key, result)
      elsif value.is_a?(Array)
        result[new_key] = value.join(", ")
      else
        result[new_key] = value
      end
    end
    
    result
  end

  def format_value(value)
    case value
    when Hash
      value.to_json
    when Array
      value.join(", ")
    when Time, DateTime
      value.strftime("%Y-%m-%d %H:%M:%S")
    when nil
      "N/A"
    else
      value.to_s
    end
  end
end
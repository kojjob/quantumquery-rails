# app/services/schema_introspection/excel_introspector.rb
require "roo"

module SchemaIntrospection
  class ExcelIntrospector < BaseIntrospector
    def extract_tables
      sheet_names
    end

    def extract_columns
      columns_by_sheet = {}
      
      sheet_names.each do |sheet_name|
        columns_by_sheet[sheet_name] = analyze_sheet_structure(sheet_name)
      end
      
      columns_by_sheet
    end

    def extract_row_counts
      counts = {}
      
      with_spreadsheet do |xlsx|
        sheet_names.each do |sheet_name|
          sheet = xlsx.sheet(sheet_name)
          counts[sheet_name] = sheet.last_row - 1 # Subtract header row
        end
      end
      
      counts
    rescue => e
      Rails.logger.error "Failed to count Excel rows: #{e.message}"
      {}
    end

    def extract_sample_data(limit: 5)
      samples = {}
      
      with_spreadsheet do |xlsx|
        sheet_names.take(3).each do |sheet_name| # Sample first 3 sheets
          samples[sheet_name] = read_sample_rows(xlsx, sheet_name, limit)
        end
      end
      
      samples
    rescue => e
      Rails.logger.error "Failed to sample Excel data: #{e.message}"
      {}
    end

    def extract_metadata
      return {} unless dataset.data_file.attached?

      with_spreadsheet do |xlsx|
        {
          filename: dataset.data_file.filename.to_s,
          file_size: dataset.data_file.byte_size,
          content_type: dataset.data_file.content_type,
          sheet_count: xlsx.sheets.count,
          sheet_names: xlsx.sheets,
          uploaded_at: dataset.data_file.created_at
        }
      end
    rescue => e
      Rails.logger.error "Failed to extract Excel metadata: #{e.message}"
      {}
    end

    def test_connection
      dataset.data_file.attached? && dataset.data_file.blob.present?
    end

    private

    def sheet_names
      return [] unless dataset.data_file.attached?

      with_spreadsheet do |xlsx|
        xlsx.sheets.map { |name| name.parameterize.underscore }
      end
    rescue => e
      Rails.logger.error "Failed to read Excel sheets: #{e.message}"
      []
    end

    def analyze_sheet_structure(sheet_name)
      with_spreadsheet do |xlsx|
        original_name = xlsx.sheets.find { |s| s.parameterize.underscore == sheet_name }
        sheet = xlsx.sheet(original_name)
        
        return [] if sheet.last_row < 1
        
        # Get headers from first row
        headers = sheet.row(1)
        
        # Sample data from next rows
        sample_rows = (2..[ sheet.last_row, 102 ].min).map do |row_num|
          sheet.row(row_num)
        end
        
        headers.each_with_index.map do |header, col_idx|
          values = sample_rows.map { |row| row[col_idx] }
          
          {
            name: header.to_s.parameterize.underscore,
            display_name: header.to_s,
            type: infer_column_type(values),
            nullable: values.any?(&:nil?),
            stats: calculate_column_stats(values)
          }
        end
      end
    rescue => e
      Rails.logger.error "Failed to analyze Excel sheet #{sheet_name}: #{e.message}"
      []
    end

    def read_sample_rows(xlsx, sheet_name, limit)
      original_name = xlsx.sheets.find { |s| s.parameterize.underscore == sheet_name }
      sheet = xlsx.sheet(original_name)
      
      return [] if sheet.last_row < 2
      
      headers = sheet.row(1).map { |h| h.to_s.parameterize.underscore }
      
      (2..[ sheet.last_row, limit + 1 ].min).map do |row_num|
        row_data = sheet.row(row_num)
        headers.zip(row_data).to_h
      end
    rescue => e
      Rails.logger.error "Failed to read Excel sample for #{sheet_name}: #{e.message}"
      []
    end

    def with_spreadsheet
      return unless dataset.data_file.attached?

      dataset.data_file.open do |file|
        xlsx = Roo::Spreadsheet.open(file.path)
        yield xlsx
      end
    end
  end
end

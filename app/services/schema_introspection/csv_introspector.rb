# app/services/schema_introspection/csv_introspector.rb
require "csv"

module SchemaIntrospection
  class CsvIntrospector < BaseIntrospector
    def extract_tables
      [ file_table_name ]
    end

    def extract_columns
      {
        file_table_name => analyze_csv_structure
      }
    end

    def extract_row_counts
      {
        file_table_name => count_rows
      }
    end

    def extract_sample_data(limit: 5)
      return {} unless dataset.data_file.attached?

      {
        file_table_name => read_sample_rows(limit)
      }
    end

    def extract_metadata
      return {} unless dataset.data_file.attached?

      {
        filename: dataset.data_file.filename.to_s,
        file_size: dataset.data_file.byte_size,
        content_type: dataset.data_file.content_type,
        uploaded_at: dataset.data_file.created_at
      }
    end

    def test_connection
      dataset.data_file.attached? && dataset.data_file.blob.present?
    end

    private

    def file_table_name
      return "data" unless dataset.data_file.attached?
      
      # Use filename without extension as table name
      File.basename(dataset.data_file.filename.to_s, ".*").parameterize.underscore
    end

    def analyze_csv_structure
      return [] unless dataset.data_file.attached?

      # Read first chunk to analyze
      sample_rows = read_sample_rows(100)
      return [] if sample_rows.empty?

      headers = sample_rows.first.keys
      
      headers.map do |header|
        values = sample_rows.map { |row| row[header] }
        
        {
          name: header.to_s.parameterize.underscore,
          display_name: header.to_s,
          type: infer_column_type(values),
          nullable: values.any?(&:nil?),
          stats: calculate_column_stats(values)
        }
      end
    end

    def count_rows
      return 0 unless dataset.data_file.attached?

      count = 0
      dataset.data_file.open do |file|
        CSV.foreach(file, headers: true) do
          count += 1
        end
      end
      count
    rescue => e
      Rails.logger.error "Failed to count CSV rows: #{e.message}"
      0
    end

    def read_sample_rows(limit)
      return [] unless dataset.data_file.attached?

      rows = []
      dataset.data_file.open do |file|
        CSV.foreach(file, headers: true).with_index do |row, index|
          break if index >= limit
          rows << row.to_h
        end
      end
      rows
    rescue => e
      Rails.logger.error "Failed to read CSV sample: #{e.message}"
      []
    end
  end
end

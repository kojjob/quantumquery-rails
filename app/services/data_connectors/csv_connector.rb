# CSV file data connector
require 'csv'

module DataConnectors
  class CsvConnector < BaseConnector
    attr_reader :file_path, :csv_data
    
    def connect
      @file_path = connection_params['file_path'] || dataset.file_attachment&.path
      
      unless @file_path && File.exist?(@file_path)
        raise "CSV file not found at #{@file_path}"
      end
      
      # Detect encoding
      encoding = detect_encoding(@file_path)
      
      # Parse CSV with proper options
      @csv_data = CSV.read(
        @file_path,
        headers: true,
        encoding: "#{encoding}:UTF-8",
        header_converters: :symbol,
        converters: [:numeric, :date_time]
      )
      
      log_activity('connected', { 
        file: File.basename(@file_path),
        rows: @csv_data.count,
        columns: @csv_data.headers.count
      })
      
      @csv_data
    rescue CSV::MalformedCSVError => e
      handle_connection_error(e)
    end
    
    def test_connection
      connect unless @csv_data
      
      {
        success: true,
        file_name: File.basename(@file_path),
        file_size: File.size(@file_path),
        row_count: @csv_data.count,
        column_count: @csv_data.headers.count,
        encoding: detect_encoding(@file_path)
      }
    rescue => e
      { success: false, error: e.message }
    end
    
    def fetch_schema
      connect unless @csv_data
      
      schema = {
        file_info: {
          name: File.basename(@file_path),
          size: File.size(@file_path),
          modified: File.mtime(@file_path),
          encoding: detect_encoding(@file_path)
        },
        columns: analyze_columns,
        statistics: calculate_statistics,
        data_quality: analyze_data_quality
      }
      
      # Store schema in dataset
      dataset.update!(
        schema_metadata: schema,
        schema_fetched_at: Time.current,
        status: 'connected'
      )
      
      log_activity('schema_fetched', { 
        columns: schema[:columns].count,
        data_types: schema[:columns].map { |c| c[:inferred_type] }.uniq
      })
      
      schema
    rescue => e
      handle_connection_error(e)
    end
    
    def fetch_sample_data(limit: 100)
      connect unless @csv_data
      
      sample_rows = @csv_data.take(limit)
      
      {
        columns: @csv_data.headers,
        data: sample_rows.map(&:to_h),
        total_rows: @csv_data.count,
        sample_size: sample_rows.count
      }
    end
    
    def execute_query(query)
      connect unless @csv_data
      
      # For CSV, we support simple filtering and selection
      # This would typically be done in the sandboxed Python/R environment
      # Here we provide basic functionality for testing
      
      if query.downcase.start_with?('select')
        execute_select_query(query)
      else
        raise "Only SELECT queries are supported for CSV files"
      end
    end
    
    def export_to_format(format, output_path = nil)
      connect unless @csv_data
      
      output_path ||= Rails.root.join('tmp', "export_#{Time.current.to_i}.#{format}")
      
      case format.to_s.downcase
      when 'json'
        File.write(output_path, @csv_data.map(&:to_h).to_json)
      when 'parquet'
        export_to_parquet(output_path)
      when 'xlsx'
        export_to_excel(output_path)
      else
        raise "Unsupported export format: #{format}"
      end
      
      log_activity('exported', { 
        format: format,
        file: output_path.to_s
      })
      
      output_path
    end
    
    private
    
    def detect_encoding(file_path)
      # Try to detect file encoding
      detector = CharlockHolmes::EncodingDetector.detect(File.read(file_path, mode: 'rb'))
      detector[:encoding] || 'UTF-8'
    rescue
      'UTF-8'
    end
    
    def analyze_columns
      return [] unless @csv_data.any?
      
      @csv_data.headers.map do |header|
        column_data = @csv_data[header].compact
        
        {
          name: header.to_s,
          inferred_type: infer_data_type(column_data),
          non_null_count: column_data.count,
          null_count: @csv_data.count - column_data.count,
          unique_count: column_data.uniq.count,
          sample_values: column_data.take(5)
        }
      end
    end
    
    def infer_data_type(values)
      return 'empty' if values.empty?
      
      # Check if all values match a pattern
      if values.all? { |v| v.is_a?(Integer) }
        'integer'
      elsif values.all? { |v| v.is_a?(Float) || v.is_a?(Integer) }
        'numeric'
      elsif values.all? { |v| v.is_a?(Date) || v.is_a?(DateTime) || v.is_a?(Time) }
        'datetime'
      elsif values.all? { |v| v.to_s =~ /^\d{4}-\d{2}-\d{2}/ }
        'date'
      elsif values.all? { |v| v.to_s =~ /^(true|false|yes|no|y|n|1|0)$/i }
        'boolean'
      else
        'string'
      end
    end
    
    def calculate_statistics
      stats = {}
      
      @csv_data.headers.each do |header|
        column_data = @csv_data[header].compact
        column_type = infer_data_type(column_data)
        
        if %w[integer numeric].include?(column_type)
          numeric_values = column_data.map(&:to_f)
          stats[header] = {
            min: numeric_values.min,
            max: numeric_values.max,
            mean: numeric_values.sum / numeric_values.count,
            median: calculate_median(numeric_values),
            std_dev: calculate_std_dev(numeric_values)
          }
        elsif column_type == 'string'
          stats[header] = {
            min_length: column_data.map(&:to_s).map(&:length).min,
            max_length: column_data.map(&:to_s).map(&:length).max,
            avg_length: column_data.map(&:to_s).map(&:length).sum.to_f / column_data.count
          }
        end
      end
      
      stats
    end
    
    def calculate_median(values)
      sorted = values.sort
      len = sorted.length
      len.odd? ? sorted[len / 2] : (sorted[len / 2 - 1] + sorted[len / 2]) / 2.0
    end
    
    def calculate_std_dev(values)
      mean = values.sum.to_f / values.count
      variance = values.map { |v| (v - mean) ** 2 }.sum / values.count
      Math.sqrt(variance)
    end
    
    def analyze_data_quality
      {
        total_rows: @csv_data.count,
        complete_rows: @csv_data.count { |row| row.none? { |_, v| v.nil? } },
        duplicate_rows: @csv_data.count - @csv_data.map(&:to_h).uniq.count,
        missing_values_by_column: @csv_data.headers.map { |h| 
          [h, @csv_data.count { |row| row[h].nil? }]
        }.to_h
      }
    end
    
    def execute_select_query(query)
      # Very basic SELECT parsing for demonstration
      # In production, this would be handled by the sandboxed environment
      
      if query.downcase.include?('where')
        # Basic WHERE clause support
        conditions = parse_where_clause(query)
        filtered = @csv_data.select do |row|
          evaluate_conditions(row, conditions)
        end
        
        {
          columns: @csv_data.headers,
          data: filtered.map(&:to_h),
          row_count: filtered.count
        }
      else
        # Return all data
        {
          columns: @csv_data.headers,
          data: @csv_data.map(&:to_h),
          row_count: @csv_data.count
        }
      end
    end
    
    def parse_where_clause(query)
      # Simplified WHERE parsing
      where_match = query.match(/where\s+(.+?)(?:\s+order\s+by|\s+limit|$)/i)
      return {} unless where_match
      
      conditions = {}
      where_match[1].split(/\s+and\s+/i).each do |condition|
        if match = condition.match(/(\w+)\s*=\s*['"]?(.+?)['"]?$/)
          conditions[match[1].to_sym] = match[2]
        end
      end
      
      conditions
    end
    
    def evaluate_conditions(row, conditions)
      conditions.all? do |column, value|
        row[column].to_s == value.to_s
      end
    end
    
    def export_to_parquet(output_path)
      # Would use Arrow/Parquet gem in production
      raise NotImplementedError, "Parquet export requires additional dependencies"
    end
    
    def export_to_excel(output_path)
      # Would use axlsx or similar gem in production
      raise NotImplementedError, "Excel export requires additional dependencies"
    end
  end
end
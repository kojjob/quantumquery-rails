# app/services/schema_introspection/base_introspector.rb
module SchemaIntrospection
  class BaseIntrospector
    attr_reader :dataset

    def initialize(dataset)
      @dataset = dataset
    end

    # Main method to introspect and return complete schema
    def introspect
      {
        tables: extract_tables,
        columns: extract_columns,
        row_counts: extract_row_counts,
        relationships: extract_relationships,
        indexes: extract_indexes,
        sample_data: extract_sample_data,
        metadata: extract_metadata,
        introspected_at: Time.current
      }
    end

    # Abstract methods to be implemented by subclasses
    def extract_tables
      raise NotImplementedError, "#{self.class} must implement #extract_tables"
    end

    def extract_columns
      raise NotImplementedError, "#{self.class} must implement #extract_columns"
    end

    def extract_row_counts
      {}
    end

    def extract_relationships
      {}
    end

    def extract_indexes
      {}
    end

    def extract_sample_data(limit: 5)
      {}
    end

    def extract_metadata
      {}
    end

    # Helper to test connection
    def test_connection
      raise NotImplementedError, "#{self.class} must implement #test_connection"
    end

    protected

    # Infer column type from values
    def infer_column_type(values)
      return "unknown" if values.empty?

      # Sample non-nil values
      sample = values.compact.take(100)
      return "null" if sample.empty?

      # Check for common types
      if sample.all? { |v| v.is_a?(Integer) || v.to_s.match?(/^\-?\d+$/) }
        "integer"
      elsif sample.all? { |v| v.is_a?(Float) || v.to_s.match?(/^\-?\d+\.\d+$/) }
        "float"
      elsif sample.all? { |v| v.to_s.match?(/^\d{4}-\d{2}-\d{2}/) }
        "date"
      elsif sample.all? { |v| [ true, false, "true", "false", "t", "f", 0, 1 ].include?(v) }
        "boolean"
      elsif sample.any? { |v| v.to_s.length > 500 }
        "text"
      else
        "string"
      end
    end

    # Calculate statistics for a column
    def calculate_column_stats(values)
      non_null = values.compact
      
      {
        null_count: values.count - non_null.count,
        null_percentage: ((values.count - non_null.count) / values.count.to_f * 100).round(2),
        unique_count: non_null.uniq.count,
        sample_values: non_null.take(5)
      }
    end

    # Format schema for AI consumption
    def format_for_ai(schema)
      {
        summary: generate_schema_summary(schema),
        tables: format_tables_for_ai(schema[:tables], schema[:columns]),
        relationships: format_relationships_for_ai(schema[:relationships])
      }
    end

    def generate_schema_summary(schema)
      table_count = schema[:tables]&.length || 0
      total_columns = schema[:columns]&.values&.flatten&.length || 0
      total_rows = schema[:row_counts]&.values&.sum || 0

      "Dataset contains #{table_count} tables with #{total_columns} total columns and approximately #{total_rows} rows."
    end

    def format_tables_for_ai(tables, columns)
      return [] unless tables && columns

      tables.map do |table|
        table_columns = columns[table] || []
        
        {
          name: table,
          columns: table_columns.map { |col| "#{col[:name]} (#{col[:type]})" },
          column_count: table_columns.length,
          primary_keys: table_columns.select { |c| c[:primary_key] }.map { |c| c[:name] }
        }
      end
    end

    def format_relationships_for_ai(relationships)
      return [] unless relationships

      relationships.map do |rel|
        "#{rel[:from_table]}.#{rel[:from_column]} → #{rel[:to_table]}.#{rel[:to_column]}"
      end
    end
  end
end

# app/services/schema_introspection/introspector_factory.rb
module SchemaIntrospection
  class IntrospectorFactory
    def self.build(dataset)
      case dataset.data_source_type
      when "postgresql"
        PostgresqlIntrospector.new(dataset)
      when "mysql"
        MysqlIntrospector.new(dataset)
      when "csv_upload"
        CsvIntrospector.new(dataset)
      when "excel_upload"
        ExcelIntrospector.new(dataset)
      when "mongodb"
        MongodbIntrospector.new(dataset)
      else
        raise "Unsupported data source type: #{dataset.data_source_type}"
      end
    end
  end
end

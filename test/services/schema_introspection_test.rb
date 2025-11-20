# test/services/schema_introspection_test.rb
require "test_helper"

class SchemaIntrospectionTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
  end

  # CSV Introspector Tests
  test "csv introspector extracts schema from uploaded file" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Test CSV",
      data_source_type: :csv_upload,
      status: :ready
    )

    # Attach a test CSV file
    csv_content = "name,age,email\nJohn,30,john@example.com\nJane,25,jane@example.com\n"
    dataset.data_file.attach(
      io: StringIO.new(csv_content),
      filename: "test.csv",
      content_type: "text/csv"
    )

    introspector = SchemaIntrospection::CsvIntrospector.new(dataset)
    schema = introspector.introspect

    assert schema[:tables].include?("test")
    assert_equal 3, schema[:columns]["test"].length
    assert_equal 2, schema[:row_counts]["test"]
    
    column_names = schema[:columns]["test"].map { |c| c[:name] }
    assert_includes column_names, "name"
    assert_includes column_names, "age"
    assert_includes column_names, "email"
  end

  test "csv introspector infers column types correctly" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Typed CSV",
      data_source_type: :csv_upload,
      status: :ready
    )

    csv_content = <<~CSV
      name,age,price,active,created_at
      Product A,100,19.99,true,2024-01-15
      Product B,200,29.99,false,2024-02-20
      Product C,150,24.99,true,2024-03-10
    CSV

    dataset.data_file.attach(
      io: StringIO.new(csv_content),
      filename: "products.csv",
      content_type: "text/csv"
    )

    introspector = SchemaIntrospection::CsvIntrospector.new(dataset)
    schema = introspector.introspect

    columns = schema[:columns]["products"]
    
    name_col = columns.find { |c| c[:name] == "name" }
    assert_equal "string", name_col[:type]
    
    age_col = columns.find { |c| c[:name] == "age" }
    assert_equal "integer", age_col[:type]
    
    price_col = columns.find { |c| c[:name] == "price" }
    assert_equal "float", price_col[:type]
    
    active_col = columns.find { |c| c[:name] == "active" }
    assert_equal "boolean", active_col[:type]
    
    date_col = columns.find { |c| c[:name] == "created_at" }
    assert_equal "date", date_col[:type]
  end

  test "csv introspector handles empty files gracefully" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Empty CSV",
      data_source_type: :csv_upload,
      status: :ready
    )

    dataset.data_file.attach(
      io: StringIO.new(""),
      filename: "empty.csv",
      content_type: "text/csv"
    )

    introspector = SchemaIntrospection::CsvIntrospector.new(dataset)
    schema = introspector.introspect

    assert_empty schema[:columns]["empty"]
    assert_equal 0, schema[:row_counts]["empty"]
  end

  # Excel Introspector Tests
  test "excel introspector can be instantiated" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Test Excel",
      data_source_type: :excel_upload,
      status: :ready
    )

    introspector = SchemaIntrospection::ExcelIntrospector.new(dataset)
    assert_not_nil introspector
  end

  # PostgreSQL Introspector Tests (requires test database)
  test "postgresql introspector queries can be constructed" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Test PostgreSQL",
      data_source_type: :postgresql,
      status: :ready,
      connection_config: {
        host: "localhost",
        port: 5432,
        database: "test_db",
        username: "test_user"
      }
    )

    introspector = SchemaIntrospection::PostgresqlIntrospector.new(dataset)
    assert_not_nil introspector
    
    # Test type normalization
    assert_equal "string", introspector.send(:normalize_pg_type, "character varying")
    assert_equal "integer", introspector.send(:normalize_pg_type, "bigint")
    assert_equal "float", introspector.send(:normalize_pg_type, "numeric")
    assert_equal "boolean", introspector.send(:normalize_pg_type, "boolean")
    assert_equal "datetime", introspector.send(:normalize_pg_type, "timestamp")
    assert_equal "json", introspector.send(:normalize_pg_type, "jsonb")
  end

  # MySQL Introspector Tests
  test "mysql introspector type normalization" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Test MySQL",
      data_source_type: :mysql,
      status: :ready,
      connection_config: {
        host: "localhost",
        port: 3306,
        database: "test_db",
        username: "test_user"
      }
    )

    introspector = SchemaIntrospection::MysqlIntrospector.new(dataset)
    
    assert_equal "string", introspector.send(:normalize_mysql_type, "varchar")
    assert_equal "integer", introspector.send(:normalize_mysql_type, "int")
    assert_equal "float", introspector.send(:normalize_mysql_type, "decimal")
    assert_equal "boolean", introspector.send(:normalize_mysql_type, "boolean")
    assert_equal "datetime", introspector.send(:normalize_mysql_type, "datetime")
    assert_equal "json", introspector.send(:normalize_mysql_type, "json")
  end

  # Factory Tests
  test "introspector factory builds correct introspector for each type" do
    csv_dataset = Dataset.new(data_source_type: :csv_upload)
    assert_instance_of SchemaIntrospection::CsvIntrospector,
                       SchemaIntrospection::IntrospectorFactory.build(csv_dataset)

    excel_dataset = Dataset.new(data_source_type: :excel_upload)
    assert_instance_of SchemaIntrospection::ExcelIntrospector,
                       SchemaIntrospection::IntrospectorFactory.build(excel_dataset)

    pg_dataset = Dataset.new(data_source_type: :postgresql)
    assert_instance_of SchemaIntrospection::PostgresqlIntrospector,
                       SchemaIntrospection::IntrospectorFactory.build(pg_dataset)

    mysql_dataset = Dataset.new(data_source_type: :mysql)
    assert_instance_of SchemaIntrospection::MysqlIntrospector,
                       SchemaIntrospection::IntrospectorFactory.build(mysql_dataset)

    mongo_dataset = Dataset.new(data_source_type: :mongodb)
    assert_instance_of SchemaIntrospection::MongodbIntrospector,
                       SchemaIntrospection::IntrospectorFactory.build(mongo_dataset)
  end

  test "introspector factory raises for unsupported types" do
    unsupported = Dataset.new(data_source_type: :api_endpoint)
    
    assert_raises RuntimeError do
      SchemaIntrospection::IntrospectorFactory.build(unsupported)
    end
  end

  # Job Tests
  test "dataset schema refresh job updates dataset" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Job Test CSV",
      data_source_type: :csv_upload,
      status: :connected
    )

    csv_content = "id,name\n1,Test\n2,Demo\n"
    dataset.data_file.attach(
      io: StringIO.new(csv_content),
      filename: "job_test.csv",
      content_type: "text/csv"
    )

    DatasetSchemaRefreshJob.perform_now(dataset)

    dataset.reload
    assert_equal "ready", dataset.status
    assert_not_nil dataset.schema_metadata
    assert_not_nil dataset.last_connected_at
    assert_includes dataset.schema_metadata["tables"], "job_test"
  end

  test "dataset schema refresh job handles errors" do
    dataset = Dataset.create!(
      organization: @organization,
      name: "Failing Dataset",
      data_source_type: :postgresql,
      status: :connected,
      connection_config: {
        host: "invalid_host",
        database: "invalid_db"
      }
    )

    assert_raises StandardError do
      DatasetSchemaRefreshJob.perform_now(dataset)
    end

    dataset.reload
    assert_equal "error", dataset.status
    assert_not_nil dataset.last_error
  end

  # Base Introspector Tests
  test "base introspector infers column types correctly" do
    introspector = SchemaIntrospection::BaseIntrospector.new(nil)

    assert_equal "integer", introspector.send(:infer_column_type, [ 1, 2, 3, 4, 5 ])
    assert_equal "float", introspector.send(:infer_column_type, [ 1.5, 2.3, 3.7 ])
    assert_equal "boolean", introspector.send(:infer_column_type, [ true, false, true ])
    assert_equal "date", introspector.send(:infer_column_type, [ "2024-01-01", "2024-02-15" ])
    assert_equal "string", introspector.send(:infer_column_type, [ "hello", "world" ])
    assert_equal "text", introspector.send(:infer_column_type, [ "a" * 600 ])
  end

  test "base introspector calculates column stats" do
    introspector = SchemaIntrospection::BaseIntrospector.new(nil)
    values = [ 1, 2, 3, nil, 3, 4, 5 ]

    stats = introspector.send(:calculate_column_stats, values)

    assert_equal 1, stats[:null_count]
    assert_equal 14.29, stats[:null_percentage]
    assert_equal 5, stats[:unique_count]
    assert_equal 5, stats[:sample_values].length
  end
end

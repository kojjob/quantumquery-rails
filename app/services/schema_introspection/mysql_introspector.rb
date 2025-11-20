# app/services/schema_introspection/mysql_introspector.rb
module SchemaIntrospection
  class MysqlIntrospector < BaseIntrospector
    def extract_tables
      with_connection do |conn|
        result = conn.query(<<~SQL)
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = DATABASE()
            AND table_type = 'BASE TABLE'
          ORDER BY table_name;
        SQL

        result.map { |row| row["table_name"] }
      end
    end

    def extract_columns
      tables = extract_tables
      columns_by_table = {}

      with_connection do |conn|
        tables.each do |table|
          columns_by_table[table] = extract_table_columns(conn, table)
        end
      end

      columns_by_table
    end

    def extract_row_counts
      tables = extract_tables
      counts = {}

      with_connection do |conn|
        tables.each do |table|
          begin
            result = conn.query("SELECT COUNT(*) as count FROM `#{conn.escape(table)}`")
            counts[table] = result.first["count"]
          rescue => e
            Rails.logger.warn "Failed to count rows in #{table}: #{e.message}"
            counts[table] = nil
          end
        end
      end

      counts
    end

    def extract_relationships
      with_connection do |conn|
        result = conn.query(<<~SQL)
          SELECT
            kcu.table_name as from_table,
            kcu.column_name as from_column,
            kcu.referenced_table_name as to_table,
            kcu.referenced_column_name as to_column,
            kcu.constraint_name
          FROM information_schema.key_column_usage kcu
          WHERE kcu.table_schema = DATABASE()
            AND kcu.referenced_table_name IS NOT NULL
          ORDER BY kcu.table_name, kcu.column_name;
        SQL

        result.map do |row|
          {
            from_table: row["from_table"],
            from_column: row["from_column"],
            to_table: row["to_table"],
            to_column: row["to_column"],
            constraint_name: row["constraint_name"]
          }
        end
      end
    end

    def extract_indexes
      with_connection do |conn|
        result = conn.query(<<~SQL)
          SELECT
            table_name,
            index_name,
            GROUP_CONCAT(column_name ORDER BY seq_in_index) as column_names,
            non_unique = 0 as is_unique
          FROM information_schema.statistics
          WHERE table_schema = DATABASE()
          GROUP BY table_name, index_name, non_unique
          ORDER BY table_name, index_name;
        SQL

        indexes_by_table = {}
        
        result.each do |row|
          table = row["table_name"]
          indexes_by_table[table] ||= []
          
          indexes_by_table[table] << {
            name: row["index_name"],
            columns: row["column_names"].split(","),
            unique: row["is_unique"] == 1,
            primary: row["index_name"] == "PRIMARY"
          }
        end

        indexes_by_table
      end
    end

    def test_connection
      with_connection do |conn|
        conn.query("SELECT 1")
        true
      end
    rescue => e
      Rails.logger.error "MySQL connection test failed: #{e.message}"
      false
    end

    private

    def extract_table_columns(conn, table)
      result = conn.query(<<~SQL)
        SELECT
          column_name,
          data_type,
          is_nullable,
          column_default,
          character_maximum_length,
          numeric_precision,
          numeric_scale,
          column_key = 'PRI' as is_primary_key
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = '#{conn.escape(table)}'
        ORDER BY ordinal_position;
      SQL

      result.map do |row|
        {
          name: row["column_name"],
          type: normalize_mysql_type(row["data_type"]),
          nullable: row["is_nullable"] == "YES",
          default: row["column_default"],
          max_length: row["character_maximum_length"]&.to_i,
          precision: row["numeric_precision"]&.to_i,
          scale: row["numeric_scale"]&.to_i,
          primary_key: row["is_primary_key"] == 1
        }
      end
    end

    def normalize_mysql_type(mysql_type)
      case mysql_type.downcase
      when "varchar", "char", "text", "tinytext", "mediumtext", "longtext"
        "string"
      when "int", "integer", "tinyint", "smallint", "mediumint", "bigint"
        "integer"
      when "decimal", "numeric", "float", "double", "real"
        "float"
      when "boolean", "bool"
        "boolean"
      when "date"
        "date"
      when "datetime", "timestamp"
        "datetime"
      when "time"
        "time"
      when "json"
        "json"
      when "blob", "binary", "varbinary"
        "binary"
      else
        mysql_type
      end
    end

    def with_connection
      require "mysql2"
      
      conn = Mysql2::Client.new(connection_params)
      yield conn
    ensure
      conn&.close
    end

    def connection_params
      {
        host: dataset.connection_config["host"] || "localhost",
        port: dataset.connection_config["port"] || 3306,
        database: dataset.connection_config["database"],
        username: dataset.connection_config["username"],
        password: dataset.connection_config["encrypted_password"]
      }
    end
  end
end

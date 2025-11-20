# app/services/schema_introspection/postgresql_introspector.rb
module SchemaIntrospection
  class PostgresqlIntrospector < BaseIntrospector
    def extract_tables
      with_connection do |conn|
        result = conn.exec(<<~SQL)
          SELECT 
            table_name,
            table_type
          FROM information_schema.tables
          WHERE table_schema = 'public'
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
            result = conn.exec("SELECT COUNT(*) as count FROM #{conn.escape_identifier(table)}")
            counts[table] = result[0]["count"].to_i
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
        result = conn.exec(<<~SQL)
          SELECT
            tc.table_name as from_table,
            kcu.column_name as from_column,
            ccu.table_name as to_table,
            ccu.column_name as to_column,
            tc.constraint_name
          FROM information_schema.table_constraints AS tc
          JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
          JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = 'public'
          ORDER BY tc.table_name, kcu.column_name;
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
        result = conn.exec(<<~SQL)
          SELECT
            t.relname as table_name,
            i.relname as index_name,
            array_agg(a.attname ORDER BY c.ordinality) as column_names,
            ix.indisunique as is_unique,
            ix.indisprimary as is_primary
          FROM pg_class t
          JOIN pg_index ix ON t.oid = ix.indrelid
          JOIN pg_class i ON i.oid = ix.indexrelid
          JOIN unnest(ix.indkey) WITH ORDINALITY c(attnum, ordinality) ON true
          JOIN pg_attribute a ON t.oid = a.attrelid AND a.attnum = c.attnum
          JOIN pg_namespace n ON n.oid = t.relnamespace
          WHERE n.nspname = 'public'
            AND t.relkind = 'r'
          GROUP BY t.relname, i.relname, ix.indisunique, ix.indisprimary
          ORDER BY t.relname, i.relname;
        SQL

        indexes_by_table = {}
        
        result.each do |row|
          table = row["table_name"]
          indexes_by_table[table] ||= []
          
          indexes_by_table[table] << {
            name: row["index_name"],
            columns: row["column_names"].gsub(/[{}]/, "").split(","),
            unique: row["is_unique"] == "t",
            primary: row["is_primary"] == "t"
          }
        end

        indexes_by_table
      end
    end

    def extract_sample_data(limit: 5)
      tables = extract_tables.take(3) # Only sample first 3 tables
      samples = {}

      with_connection do |conn|
        tables.each do |table|
          begin
            result = conn.exec("SELECT * FROM #{conn.escape_identifier(table)} LIMIT #{limit}")
            samples[table] = result.map { |row| row.to_h }
          rescue => e
            Rails.logger.warn "Failed to sample #{table}: #{e.message}"
            samples[table] = []
          end
        end
      end

      samples
    end

    def extract_metadata
      with_connection do |conn|
        {
          database_name: conn.db,
          server_version: conn.server_version,
          encoding: conn.internal_encoding.to_s,
          connection_info: {
            host: dataset.connection_config["host"],
            port: dataset.connection_config["port"],
            database: dataset.connection_config["database"]
          }
        }
      end
    end

    def test_connection
      with_connection do |conn|
        conn.exec("SELECT 1")
        true
      end
    rescue => e
      Rails.logger.error "PostgreSQL connection test failed: #{e.message}"
      false
    end

    private

    def extract_table_columns(conn, table)
      result = conn.exec(<<~SQL)
        SELECT
          c.column_name,
          c.data_type,
          c.is_nullable,
          c.column_default,
          c.character_maximum_length,
          c.numeric_precision,
          c.numeric_scale,
          CASE 
            WHEN pk.column_name IS NOT NULL THEN true
            ELSE false
          END as is_primary_key
        FROM information_schema.columns c
        LEFT JOIN (
          SELECT kcu.column_name, kcu.table_name
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
          WHERE tc.constraint_type = 'PRIMARY KEY'
            AND tc.table_schema = 'public'
        ) pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
        WHERE c.table_schema = 'public'
          AND c.table_name = $1
        ORDER BY c.ordinal_position;
      SQL

      conn.exec_params(result, [ table ]).map do |row|
        {
          name: row["column_name"],
          type: normalize_pg_type(row["data_type"]),
          nullable: row["is_nullable"] == "YES",
          default: row["column_default"],
          max_length: row["character_maximum_length"]&.to_i,
          precision: row["numeric_precision"]&.to_i,
          scale: row["numeric_scale"]&.to_i,
          primary_key: row["is_primary_key"] == "t"
        }
      end
    end

    def normalize_pg_type(pg_type)
      case pg_type
      when "character varying", "varchar", "character", "char", "text"
        "string"
      when "integer", "bigint", "smallint"
        "integer"
      when "numeric", "decimal", "real", "double precision"
        "float"
      when "boolean"
        "boolean"
      when "date"
        "date"
      when "timestamp without time zone", "timestamp with time zone", "timestamp"
        "datetime"
      when "time without time zone", "time with time zone", "time"
        "time"
      when "json", "jsonb"
        "json"
      when "uuid"
        "uuid"
      when "bytea"
        "binary"
      else
        pg_type
      end
    end

    def with_connection
      conn = PG.connect(connection_params)
      yield conn
    ensure
      conn&.close
    end

    def connection_params
      {
        host: dataset.connection_config["host"] || "localhost",
        port: dataset.connection_config["port"] || 5432,
        dbname: dataset.connection_config["database"],
        user: dataset.connection_config["username"],
        password: dataset.connection_config["encrypted_password"]
      }
    end
  end
end

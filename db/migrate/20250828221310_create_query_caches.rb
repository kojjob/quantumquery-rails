class CreateQueryCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :query_caches do |t|
      t.string :query_hash, null: false
      t.text :query_text, null: false
      t.references :dataset, null: false, foreign_key: true, index: true
      t.references :organization, null: false, foreign_key: true, index: true
      t.jsonb :results, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :expires_at
      t.integer :access_count, default: 0, null: false
      t.bigint :cache_size_bytes, default: 0, null: false
      t.string :cache_key
      t.string :ai_model
      t.float :query_execution_time

      t.timestamps
    end
    
    add_index :query_caches, :query_hash, unique: true
    add_index :query_caches, :expires_at
    add_index :query_caches, [:organization_id, :created_at]
    add_index :query_caches, :cache_key
  end
end

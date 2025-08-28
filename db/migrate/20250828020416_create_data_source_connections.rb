class CreateDataSourceConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :data_source_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source_type, null: false
      t.text :credentials_ciphertext
      t.integer :status, default: 0, null: false
      t.datetime :last_synced_at
      t.datetime :last_error_at
      t.text :last_error_message
      t.jsonb :metadata, default: {}, null: false
      t.jsonb :connection_options, default: {}, null: false

      t.timestamps
    end

    add_index :data_source_connections, [:organization_id, :source_type]
    add_index :data_source_connections, :status
    add_index :data_source_connections, [:organization_id, :name], unique: true
  end
end

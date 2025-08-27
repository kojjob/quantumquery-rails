class CreateDatasets < ActiveRecord::Migration[8.0]
  def change
    create_table :datasets do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :data_source_type
      t.jsonb :connection_config
      t.jsonb :schema_metadata
      t.integer :status, default: 0
      t.text :last_error

      t.timestamps
    end
  end
end

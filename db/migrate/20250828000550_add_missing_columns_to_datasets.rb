class AddMissingColumnsToDatasets < ActiveRecord::Migration[8.0]
  def change
    add_column :datasets, :created_by_id, :integer
    add_column :datasets, :metadata, :jsonb, default: {}
    add_column :datasets, :last_connected_at, :datetime
    
    add_index :datasets, :created_by_id
    add_foreign_key :datasets, :users, column: :created_by_id
  end
end

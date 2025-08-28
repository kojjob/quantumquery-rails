class AddAccessedAtToQueryCaches < ActiveRecord::Migration[8.0]
  def change
    add_column :query_caches, :accessed_at, :datetime
    add_index :query_caches, :accessed_at
  end
end

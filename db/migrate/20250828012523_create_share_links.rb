class CreateShareLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :share_links do |t|
      t.references :analysis_request, null: false, foreign_key: true
      t.bigint :created_by_id, null: false
      t.string :token, null: false
      t.datetime :expires_at
      t.integer :access_count, default: 0
      t.integer :view_count, default: 0
      t.integer :max_views
      t.string :password_digest
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    
    add_index :share_links, :token, unique: true
    add_index :share_links, :created_by_id
    add_index :share_links, :active
    add_foreign_key :share_links, :users, column: :created_by_id
  end
end

class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.references :commentable, polymorphic: true, null: false
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.jsonb :metadata, default: {}
      t.boolean :edited, default: false
      t.datetime :edited_at

      t.timestamps
    end
    
    add_index :comments, :created_at
  end
end

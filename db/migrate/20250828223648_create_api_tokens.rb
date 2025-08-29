class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :token
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.text :scopes

      t.timestamps
    end
    add_index :api_tokens, :token
  end
end

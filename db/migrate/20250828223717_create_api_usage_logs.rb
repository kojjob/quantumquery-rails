class CreateApiUsageLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :api_usage_logs do |t|
      t.references :api_token, null: false, foreign_key: true
      t.string :endpoint
      t.string :ip_address
      t.string :user_agent
      t.integer :response_code
      t.float :response_time

      t.timestamps
    end
  end
end

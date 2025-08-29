class CreateScheduledReports < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduled_reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :dataset, foreign_key: true
      t.string :name, null: false
      t.text :query, null: false
      t.string :frequency, null: false, default: 'weekly'
      t.integer :schedule_day # 0-6 for weekly (Sunday-Saturday), 1-31 for monthly
      t.integer :schedule_hour, default: 9 # 0-23
      t.text :recipients # JSON array of email addresses
      t.string :format, default: 'pdf' # pdf, xlsx, csv
      t.boolean :enabled, default: true
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.integer :run_count, default: 0
      t.text :metadata # JSON for additional settings

      t.timestamps
    end

    add_index :scheduled_reports, :next_run_at
    add_index :scheduled_reports, :enabled
    add_index :scheduled_reports, [ :user_id, :enabled ]
  end
end

class CreateDashboardWidgets < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboard_widgets do |t|
      t.references :dashboard, null: false, foreign_key: true
      t.string :widget_type
      t.string :title
      t.jsonb :config
      t.integer :position
      t.integer :row
      t.integer :col
      t.integer :width
      t.integer :height

      t.timestamps
    end
  end
end

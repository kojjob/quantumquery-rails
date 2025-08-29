class CreateDashboards < ActiveRecord::Migration[8.0]
  def change
    create_table :dashboards do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.string :layout
      t.jsonb :config
      t.integer :position
      t.boolean :is_default

      t.timestamps
    end
    add_index :dashboards, :is_default
  end
end

class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name
      t.string :slug
      t.jsonb :settings
      t.integer :subscription_tier

      t.timestamps
    end
  end
end

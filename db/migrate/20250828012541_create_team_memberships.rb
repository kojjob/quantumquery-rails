class CreateTeamMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :team_memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.bigint :invited_by_id
      t.datetime :accepted_at
      t.string :invitation_token
      t.datetime :invitation_expires_at
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :team_memberships, :invitation_token, unique: true
    add_index :team_memberships, [:organization_id, :user_id], unique: true
    add_index :team_memberships, :active
    add_foreign_key :team_memberships, :users, column: :invited_by_id
  end
end

class AddTwoFactorToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :encrypted_otp_secret, :string
    add_column :users, :encrypted_otp_secret_iv, :string
    add_column :users, :encrypted_otp_secret_salt, :string
    add_column :users, :consumed_timestep, :integer
    add_column :users, :otp_required_for_login, :boolean, default: false, null: false
    add_column :users, :otp_backup_codes, :text, array: true
    add_column :users, :two_factor_enabled_at, :datetime
    
    add_index :users, :encrypted_otp_secret, unique: true
  end
end

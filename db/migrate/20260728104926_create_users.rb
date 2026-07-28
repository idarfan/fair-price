# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email, null: false
      t.string   :google_uid, null: false
      t.string   :totp_secret
      t.boolean  :totp_enabled, default: false, null: false
      t.text     :backup_codes
      t.integer  :status, default: 0, null: false
      t.boolean  :admin, default: false, null: false
      t.integer  :session_version, default: 0, null: false
      t.datetime :approved_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :google_uid, unique: true
  end
end

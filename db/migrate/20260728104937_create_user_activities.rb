# frozen_string_literal: true

class CreateUserActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_activities do |t|
      t.references :user, null: false, foreign_key: true
      t.integer  :kind, null: false
      t.string   :path
      t.string   :action_name
      t.string   :activity_token
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer  :duration_ms
      t.jsonb    :metadata, default: {}

      t.timestamps
    end

    add_index :user_activities, [ :user_id, :kind, :started_at ]
  end
end

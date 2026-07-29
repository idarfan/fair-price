# frozen_string_literal: true

class AddReferrerPathToUserActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :user_activities, :referrer_path, :string
  end
end

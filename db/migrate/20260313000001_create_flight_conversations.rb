class CreateFlightConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :flight_conversations do |t|
      t.string :token, null: false
      t.timestamps
    end

    add_index :flight_conversations, :token, unique: true
  end
end

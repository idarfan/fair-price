class DropFlightTables < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :flight_messages, :flight_conversations
    drop_table :flight_messages
    drop_table :flight_conversations
  end

  def down
    create_table :flight_conversations do |t|
      t.string :token, null: false
      t.timestamps
    end
    add_index :flight_conversations, :token, unique: true

    create_table :flight_messages do |t|
      t.references :flight_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :flight_messages, [ :flight_conversation_id, :created_at ]
  end
end

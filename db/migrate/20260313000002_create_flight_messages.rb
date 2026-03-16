class CreateFlightMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :flight_messages do |t|
      t.references :flight_conversation, null: false, foreign_key: true
      t.string :role, null: false   # "user" | "assistant"
      t.text   :content, null: false
      t.timestamps
    end

    add_index :flight_messages, [ :flight_conversation_id, :created_at ]
  end
end

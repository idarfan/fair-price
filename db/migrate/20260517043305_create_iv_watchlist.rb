class CreateIvWatchlist < ActiveRecord::Migration[8.1]
  def change
    create_table :iv_watchlists do |t|
      t.string  :symbol,    null: false
      t.string  :group_tag, default: 'general'
      t.boolean :active,    default: true, null: false
      t.timestamps
    end

    add_index :iv_watchlists, :symbol, unique: true
    add_index :iv_watchlists, :group_tag
  end
end

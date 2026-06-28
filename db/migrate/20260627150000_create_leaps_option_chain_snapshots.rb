class CreateLeapsOptionChainSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :leaps_option_chain_snapshots do |t|
      t.string  :symbol,           null: false
      t.date    :expiration_date,  null: false
      t.integer :dte
      t.decimal :strike,           precision: 10, scale: 4, null: false
      t.string  :option_type,      null: false  # "Call" / "Put"
      t.decimal :bid,              precision: 10, scale: 4
      t.decimal :ask,              precision: 10, scale: 4
      t.decimal :last_price,       precision: 10, scale: 4
      t.decimal :underlying_price, precision: 10, scale: 4
      t.integer :volume
      t.integer :open_interest
      t.decimal :delta,            precision: 8, scale: 6
      t.decimal :iv,               precision: 8, scale: 6
      t.decimal :itm_probability,  precision: 8, scale: 6
      t.decimal :vol_oi_ratio,     precision: 8, scale: 4
      t.datetime :scraped_at,      null: false
      t.timestamps
    end

    # Unique per contract — upsert replaces on each new scrape
    add_index :leaps_option_chain_snapshots,
              %i[symbol expiration_date strike option_type],
              unique: true,
              name: "idx_leaps_chain_unique"

    # Cache check: "has this symbol been scraped recently?"
    add_index :leaps_option_chain_snapshots,
              %i[symbol scraped_at],
              name: "idx_leaps_chain_symbol_scraped"
  end
end

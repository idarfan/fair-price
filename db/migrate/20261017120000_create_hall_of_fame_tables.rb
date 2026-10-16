# frozen_string_literal: true

# 投資名人堂（hall-of-fame-spec.md P1）。六張 hof_ 表，與其他功能不共用資料。
#
# 金額一律存區間上下限兩欄（§1-4），無上限區間 max 為 NULL；不存單一估算值。
# hof_sync_runs.http_validators 存每個索引 URL 的 ETag／Last-Modified（§1-10 條件式請求），
# 格式：{ "<url>" => { "etag" => "...", "last_modified" => "..." } }。
class CreateHallOfFameTables < ActiveRecord::Migration[8.1]
  def change
    create_table :hof_officials do |t|
      t.string  :slug,         null: false
      t.string  :display_name, null: false
      t.string  :category,     null: false # congress / executive
      t.string  :source,       null: false # house / oge
      t.string  :last_name,    null: false
      t.string  :first_name,   null: false
      t.string  :district
      t.string  :title
      t.boolean :active,       null: false, default: true
      t.timestamps
    end
    add_index :hof_officials, :slug, unique: true

    create_table :hof_filings do |t|
      t.references :official, null: false, foreign_key: { to_table: :hof_officials }
      t.string   :source,       null: false
      t.string   :doc_id,       null: false
      t.string   :filing_type,  null: false # ptr / annual / amendment / oge_278e / oge_278t
      t.integer  :year
      t.date     :filing_date
      t.string   :pdf_url
      t.string   :pdf_path
      t.string   :sha256
      t.string   :parse_status, null: false, default: "pending" # pending / parsed / needs_review / failed
      t.text     :parse_error
      t.datetime :parsed_at
      t.timestamps
    end
    add_index :hof_filings, %i[source doc_id], unique: true
    add_index :hof_filings, :parse_status

    create_table :hof_holdings do |t|
      t.references :filing, null: false, foreign_key: { to_table: :hof_filings }
      t.string :owner,       null: false # self / SP / JT / DC
      t.text   :asset_name,  null: false
      t.string :ticker
      t.string :asset_type
      t.string :value_label
      t.bigint :value_min
      t.bigint :value_max
      t.timestamps
    end

    create_table :hof_transactions do |t|
      t.references :filing, null: false, foreign_key: { to_table: :hof_filings }
      t.string :owner,           null: false
      t.text   :asset_name,      null: false
      t.string :ticker
      t.string :asset_type_code # House 方括號代碼，如 ST / OP
      t.string :tx_type          # P / S / S_partial / E
      t.date   :tx_date
      t.date   :notified_date
      t.string :amount_label
      t.bigint :amount_min
      t.bigint :amount_max
      t.text   :description
      t.timestamps
    end
    add_index :hof_transactions, :ticker

    create_table :hof_option_details do |t|
      t.references :transaction, null: false, index: { unique: true },
                                 foreign_key: { to_table: :hof_transactions }
      t.string  :option_right # call / put
      t.decimal :strike,              precision: 12, scale: 4
      t.date    :expiration
      t.integer :contracts_stated
      t.decimal :underlying_close,    precision: 12, scale: 4
      t.decimal :premium_ref,         precision: 12, scale: 4
      t.string  :premium_source # stated_contracts / barchart_dom / bs_model
      t.integer :contracts_est_min
      t.integer :contracts_est_max
      t.decimal :premium_implied_min, precision: 12, scale: 4
      t.decimal :premium_implied_max, precision: 12, scale: 4
      t.text    :calc_note
      t.timestamps
    end

    create_table :hof_sync_runs do |t|
      t.string   :source,            null: false
      t.datetime :started_at,        null: false
      t.datetime :finished_at
      t.integer  :new_filings_count, null: false, default: 0
      t.integer  :error_count,       null: false, default: 0
      t.text     :error_log
      t.jsonb    :http_validators,   null: false, default: {}
      t.timestamps
    end
    add_index :hof_sync_runs, %i[source started_at]
  end
end

# frozen_string_literal: true

# LEAPS 頁面三個價格情境 widget（POI / 52 週區間 / 當日區間）的資料層。
#
# 兩張表分工：
#   volap_snapshots — Barchart interactive-chart 的 VOLAP 指標算好的分箱結果。
#                     POC 與 Value Area 是 Barchart 自己算的，我們不重算
#                     （見 reference_barchart_volap_dom 記憶）。
#   daily_bars      — 逐根日線 OHLCV。VOLAP 只給分箱統計、沒有 K 棒，
#                     而結構型 POI（FVG／缺口／Order Block／供需區）與當日高低
#                     都需要原始 K 棒；主圖 plot 的 record.storage 實測是空的，撈不到。
#
# 欄位命名刻意避開 open / close / min / max：
#   open  會蓋掉 Kernel#open（model 內部若呼叫 open("...") 會打到 attribute）
#   min / max 會蓋掉 Enumerable 的同名方法
# 一律加 _price / price_ 前後綴，寧可囉唆也不留這種只在特定路徑才炸的地雷。
#
# 精度沿用既有慣例：價格 decimal(10,4)（同 leaps_option_chain_snapshots）。
class CreatePriceContextTables < ActiveRecord::Migration[8.1]
  def change
    create_table :volap_snapshots do |t|
      t.string   :symbol,      null: false
      t.datetime :scraped_at,  null: false
      # 爬蟲抓取當下把圖固定到的設定，存下來才能判斷這份快照是什麼尺度算出來的。
      # VOLAP 是 periodType: "VisibleScreen"——換個期間結果就完全不同。
      t.string   :period_key,  null: false          # 例：period.1Y
      t.string   :aggregation, null: false          # 例：CHART.DAILY
      t.decimal  :price_min,   null: false, precision: 10, scale: 4
      t.decimal  :price_max,   null: false, precision: 10, scale: 4
      t.decimal  :zone,        null: false, precision: 10, scale: 6   # 每箱高度
      t.integer  :poc_index,   null: false                            # POC 所在的箱
      t.jsonb    :inputs,      null: false, default: {}               # LevelMode/LevelSize/…
      t.jsonb    :bars,        null: false, default: []               # [{up:,down:,is_value:}, …]

      t.timestamps
    end
    add_index :volap_snapshots, [ :symbol, :scraped_at ], name: "idx_volap_symbol_scraped"
    add_check_constraint :volap_snapshots, "price_max > price_min", name: "volap_range_ordered"
    add_check_constraint :volap_snapshots, "zone > 0",              name: "volap_zone_positive"
    add_check_constraint :volap_snapshots, "poc_index >= 0",        name: "volap_poc_index_non_negative"

    create_table :daily_bars do |t|
      t.string  :symbol,      null: false
      t.date    :bar_date,    null: false
      t.decimal :open_price,  null: false, precision: 10, scale: 4
      t.decimal :high_price,  null: false, precision: 10, scale: 4
      t.decimal :low_price,   null: false, precision: 10, scale: 4
      t.decimal :close_price, null: false, precision: 10, scale: 4
      t.bigint  :volume

      t.timestamps
    end
    # 唯一鍵讓爬蟲能直接 upsert_all，重抓同一天不會長出重複列。
    add_index :daily_bars, [ :symbol, :bar_date ], unique: true, name: "idx_daily_bars_unique"
    add_check_constraint :daily_bars, "high_price >= low_price", name: "daily_bars_high_ge_low"
    add_check_constraint :daily_bars, "low_price > 0",           name: "daily_bars_low_positive"
    add_check_constraint :daily_bars, "volume IS NULL OR volume >= 0", name: "daily_bars_volume_non_negative"
  end
end

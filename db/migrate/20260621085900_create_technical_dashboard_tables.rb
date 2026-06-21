class CreateTechnicalDashboardTables < ActiveRecord::Migration[8.1]
  def change
    # ===== technical_analyses =====
    create_table :technical_analyses do |t|
      t.string   :symbol,        null: false
      t.date     :snapshot_date, null: false
      t.datetime :fetched_at,    null: false

      # Moving Average (6 periods)
      %w[5d 20d 50d 100d 200d ytd].each do |p|
        t.decimal :"ma_#{p}",           precision: 10, scale: 2
        t.decimal :"ma_price_chg_#{p}", precision: 10, scale: 2
        t.decimal :"ma_pct_chg_#{p}",   precision: 8,  scale: 4
        t.bigint  :"ma_avg_vol_#{p}"
      end

      # Stochastic (5 periods)
      %w[9d 14d 20d 50d 100d].each do |p|
        t.decimal :"stoch_raw_#{p}", precision: 8, scale: 4
        t.decimal :"stoch_k_#{p}",   precision: 8, scale: 4
        t.decimal :"stoch_d_#{p}",   precision: 8, scale: 4
        t.decimal :"stoch_rs_#{p}",  precision: 8, scale: 4
      end

      # Average True Range (5 periods)
      %w[9d 14d 20d 50d 100d].each do |p|
        t.decimal :"atr_#{p}",     precision: 10, scale: 4
        t.decimal :"atr_pct_#{p}", precision: 8,  scale: 4
        t.decimal :"adr_#{p}",     precision: 10, scale: 4
        t.decimal :"adr_pct_#{p}", precision: 8,  scale: 4
      end

      # Directional Index / ADX (5 periods)
      %w[9d 14d 20d 50d 100d].each do |p|
        t.decimal :"adx_#{p}",      precision: 8, scale: 4
        t.decimal :"di_plus_#{p}",  precision: 8, scale: 4
        t.decimal :"di_minus_#{p}", precision: 8, scale: 4
        t.decimal :"hist_vol_#{p}", precision: 8, scale: 4
      end

      t.timestamps
    end

    add_index :technical_analyses, [ :symbol, :snapshot_date ], unique: true

    # ===== fundamentals =====
    create_table :fundamentals do |t|
      t.string   :symbol,        null: false
      t.date     :snapshot_date, null: false
      t.datetime :fetched_at,    null: false

      # Fundamentals block
      t.bigint   :market_cap_k
      t.bigint   :shares_outstanding_k
      t.decimal  :annual_revenue_m,  precision: 12, scale: 2
      t.decimal  :annual_income_m,   precision: 12, scale: 2
      t.decimal  :ebit_m,            precision: 12, scale: 2
      t.decimal  :ebitda_m,          precision: 12, scale: 2
      t.decimal  :beta_60m,          precision: 6,  scale: 4
      t.decimal  :pe_ttm,            precision: 8,  scale: 2
      t.decimal  :ps_ratio,          precision: 8,  scale: 2
      t.decimal  :pb_ratio,          precision: 8,  scale: 2
      t.decimal  :pcf_ratio,         precision: 8,  scale: 2
      t.decimal  :eps_ttm,           precision: 10, scale: 4
      t.decimal  :most_recent_eps,   precision: 10, scale: 4
      t.date     :most_recent_earnings_date
      t.date     :next_earnings_date
      t.string   :earnings_time       # "AMC" / "BMO"
      t.decimal  :dividend_annual,   precision: 8,  scale: 4
      t.decimal  :dividend_yield,    precision: 6,  scale: 4
      t.string   :sector

      # Analyst rating block
      t.integer  :analyst_strong_buy
      t.integer  :analyst_moderate_buy
      t.integer  :analyst_hold
      t.integer  :analyst_sell

      # Options overview block
      t.decimal  :iv,                 precision: 8, scale: 4
      t.decimal  :hist_vol,           precision: 8, scale: 4
      t.integer  :iv_percentile
      t.decimal  :iv_rank,            precision: 5, scale: 2
      t.decimal  :expected_move_pct,  precision: 8, scale: 4
      t.decimal  :put_call_vol_ratio, precision: 6, scale: 4
      t.decimal  :put_call_oi_ratio,  precision: 6, scale: 4
      t.integer  :options_volume
      t.integer  :options_avg_volume
      t.integer  :open_interest

      t.timestamps
    end

    add_index :fundamentals, [ :symbol, :snapshot_date ], unique: true

    # ===== options_flows =====
    create_table :options_flows do |t|
      t.string   :symbol,        null: false
      t.date     :snapshot_date, null: false
      t.datetime :fetched_at,    null: false

      t.bigint   :bullish_sentiment  # $, positive
      t.bigint   :bearish_sentiment  # $, stored as positive (absolute value)
      t.bigint   :net_sentiment      # positive=bullish, negative=bearish
      t.bigint   :bullish_delta
      t.bigint   :bearish_delta      # negative value
      t.bigint   :delta_imbalance    # positive=bullish, negative=bearish

      t.timestamps
    end

    add_index :options_flows, [ :symbol, :snapshot_date ], unique: true

    # ===== fetch_logs =====
    create_table :fetch_logs do |t|
      t.string   :symbol,       null: false
      t.string   :fetch_type,   null: false  # 'technical' / 'fundamental' / 'options_flow'
      t.string   :status,       null: false  # 'success' / 'barchart_session_expired' / 'dom_structure_changed' / 'error'
      t.text     :error_detail
      t.datetime :fetched_at,   null: false

      t.timestamps
    end

    add_index :fetch_logs, [ :symbol, :fetched_at ]
    add_index :fetch_logs, [ :status ]
  end
end

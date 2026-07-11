FactoryBot.define do
  sequence(:leaps_strike) { |n| (8.0 + n * 0.5).round(1) }

  factory :leaps_option_chain_snapshot do
    symbol           { "NOK" }
    expiration_date  { Date.today + 400 }
    dte              { 400 }
    strike           { generate(:leaps_strike) }
    option_type      { "Call" }
    bid              { 3.10 }
    ask              { 3.30 }
    last_price       { 3.20 }
    underlying_price { 13.08 }
    volume           { 431 }
    open_interest    { 72_921 }
    delta            { 0.7767 }
    iv               { 0.7619 }
    itm_probability  { 0.82 }
    vol_oi_ratio     { 0.006 }
    vega             { 0.0134 }
    scraped_at       { Time.current }

    # Phase H：模擬 persist_leaps 的真實寫入狀態——production 每筆 row 都帶
    # 內在/外在價值（同一公式 derived_values，不是第二份公式）。
    # 測試若明確指定這兩欄（例如驗證排行層讀 DB 不重算），以指定值為準。
    after(:build) do |snap, _evaluator|
      if snap.intrinsic_value.nil? && snap.extrinsic_value.nil?
        mid = snap.bid.nil? || snap.ask.nil? ? nil : (snap.bid.to_f + snap.ask.to_f) / 2.0
        d = LeapsOptionChainSnapshot.derived_values(
          option_type:      snap.option_type,
          strike:           snap.strike,
          underlying_price: snap.underlying_price,
          mid:              mid
        )
        snap.intrinsic_value = d[:intrinsic_value]
        snap.extrinsic_value = d[:extrinsic_value]
      end
    end
  end
end

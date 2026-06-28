FactoryBot.define do
  factory :options_flow_trade do
    symbol          { "NOK" }
    snapshot_date   { Date.current }
    fetched_at      { Time.current }
    option_type     { "Call" }
    sequence(:strike) { |n| (8.0 + n * 0.5).round(1) }
    expires_at      { Date.current + 202 }
    dte             { 202 }
    trade_price     { 3.20 }
    size            { 100 }
    side            { "ask" }
    premium         { 320_000 }
    volume          { 431 }
    open_interest   { 72_921 }
    iv              { 0.76 }
    delta           { 0.78 }
    trade_condition { "AUTO" }
    open_close      { "BuyToOpen" }
    trade_time      { Time.current }
    is_cancelled    { false }
    is_multi_leg    { false }
    is_stock_combo  { false }
    urgency_high    { false }
    likely_institutional { false }
    low_liquidity_period { false }
    timing_anomaly  { false }
    large_premium   { false }
  end
end

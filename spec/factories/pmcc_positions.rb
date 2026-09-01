FactoryBot.define do
  factory :pmcc_position do
    user
    ticker          { "BE" }
    long_contracts  { 1 }
    long_strike     { 100.0 }
    long_expiration { Date.new(2028, 1, 21) }
    long_entry_cost { 120.50 }
    long_entry_date { Date.today - 30 }
    status          { "active" }
  end

  factory :pmcc_short_leg do
    association :position, factory: :pmcc_position
    contracts         { 1 }
    short_strike      { 230.0 }
    short_expiration  { Date.today + 30 }
    premium_collected { 3.20 }
    opened_at         { Time.current }
    status            { "open" }
  end

  factory :pmcc_pnl_event do
    association :position, factory: :pmcc_position
    event_type   { "short_closed" }
    realized_pnl { 210.0 }
    fees         { 0 }
    occurred_at  { Time.current }
  end

  factory :pmcc_leg_quote do
    symbol           { "BE" }
    expiration_date  { Date.new(2028, 1, 21) }
    strike           { 100.0 }
    option_type      { "Call" }
    dte              { 508 }
    bid              { 128.0 }
    ask              { 131.4 }
    mid              { 129.7 }
    delta            { 0.897774 }
    iv               { 0.8885 }
    open_interest    { 3893 }
    underlying_price { 206.3 }
    scraped_at       { Time.current }
  end
end

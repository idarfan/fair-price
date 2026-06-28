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
  end
end

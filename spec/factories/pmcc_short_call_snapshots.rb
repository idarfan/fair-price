FactoryBot.define do
  sequence(:pmcc_short_strike) { |n| (10.0 + n * 0.5).round(1) }

  factory :pmcc_short_call_snapshot do
    symbol            { "NOK" }
    expiration_date   { Date.today + 6 }
    dte               { 6 }
    strike            { generate(:pmcc_short_strike) }
    option_type       { "Call" }
    bid               { 0.23 }
    ask               { 0.25 }
    mid_price         { 0.24 }
    last_price        { 0.23 }
    moneyness         { -0.045 }
    underlying_price  { 12.44 }
    change            { -0.1 }
    percent_change    { -0.0085 }
    volume            { 5285 }
    open_interest     { 26_278 }
    oi_change         { 3912 }
    vol_oi_ratio      { 0.20 }
    iv                { 0.7163 }
    delta             { 0.3339 }
    gamma             { 0.3185 }
    theta             { -0.0349 }
    vega              { 0.0058 }
    rho               { 0.0006 }
    theoretical_price { 0.24 }
    itm_probability   { 0.3158 }
    scraped_at        { Time.current }

    after(:build) do |snap, _evaluator|
      if snap.intrinsic_value.nil? && snap.extrinsic_value.nil?
        d = LeapsOptionChainSnapshot.derived_values(
          option_type:      snap.option_type,
          strike:           snap.strike,
          underlying_price: snap.underlying_price,
          mid:              snap.mid_price
        )
        snap.intrinsic_value = d[:intrinsic_value]
        snap.extrinsic_value = d[:extrinsic_value]
      end
    end
  end
end

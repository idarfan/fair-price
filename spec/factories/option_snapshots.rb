FactoryBot.define do
  factory :option_snapshot do
    association     :tracked_ticker
    contract_symbol { "AAPL230120P00150000" }
    option_type     { "put" }
    expiration      { Date.today + 30 }
    strike          { 150.0 }
    snapshot_date   { Date.today }
    snapped_at      { Time.current }
    in_the_money    { false }
  end
end

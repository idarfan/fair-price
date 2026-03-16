FactoryBot.define do
  factory :ownership_holder do
    association :ownership_snapshot
    sequence(:name) { |n| "Institution #{n}" }
    pct          { 5.1234 }
    market_value { 500_000_000 }
    filing_date  { Date.current }
  end
end

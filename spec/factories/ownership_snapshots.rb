FactoryBot.define do
  factory :ownership_snapshot do
    ticker         { "AAPL" }
    sequence(:quarter) { |n| "2025-Q#{(n % 4) + 1}" }
    snapshot_date  { Date.current }
    institutional_pct { 42.3 }
    insider_pct       { 8.7 }
    institution_count { 156 }
  end
end

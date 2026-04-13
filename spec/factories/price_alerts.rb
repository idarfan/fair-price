FactoryBot.define do
  factory :price_alert do
    symbol      { "AAPL" }
    target_price { 200.0 }
    condition    { "above" }
    active       { true }
  end
end

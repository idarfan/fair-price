FactoryBot.define do
  factory :portfolio do
    sequence(:symbol) { |n| "STK#{n}" }
    shares      { 10 }
    unit_cost   { 100.0 }
    sell_price  { nil }
    position    { 0 }
  end
end

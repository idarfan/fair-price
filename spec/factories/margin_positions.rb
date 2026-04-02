# frozen_string_literal: true

FactoryBot.define do
  factory :margin_position do
    symbol     { "AAPL" }
    buy_price  { 180.00 }
    shares     { 100.0 }
    sell_price { nil }
    opened_on  { 30.days.ago.to_date }
    closed_on  { nil }
    status     { "open" }
    position   { 0 }

    trait :closed do
      status    { "closed" }
      sell_price { 200.00 }
      closed_on  { Date.current }
    end

    trait :tqqq do
      symbol    { "TQQQ" }
      buy_price { 30.00 }
      shares    { 100.0 }
    end
  end
end

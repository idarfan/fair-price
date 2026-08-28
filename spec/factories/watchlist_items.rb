FactoryBot.define do
  factory :watchlist_item do
    user
    sequence(:symbol)   { |n| "SYM#{n}" }
    sequence(:position) { |n| n }
  end
end

FactoryBot.define do
  factory :tracked_ticker do
    sequence(:symbol) { |n| "TKR#{n}" }
    active { true }
    config { {} }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :iv_watchlist do
    user
    sequence(:symbol) { |n| "IVW#{(?A.ord + n % 26).chr}#{(?A.ord + n / 26 % 26).chr}" }
    group_tag { "general" }
    active    { true }
  end
end

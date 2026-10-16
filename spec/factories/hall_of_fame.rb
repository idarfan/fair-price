# frozen_string_literal: true

FactoryBot.define do
  factory :hof_official, class: "HallOfFame::Official" do
    sequence(:slug) { |n| "official#{n}" }
    display_name { "Test Official" }
    category     { "congress" }
    source       { "house" }
    last_name    { "Official" }
    first_name   { "Test" }
    district     { "CA11" }
  end

  factory :hof_filing, class: "HallOfFame::Filing" do
    association :official, factory: :hof_official
    source       { "house" }
    sequence(:doc_id) { |n| (20_000_000 + n).to_s }
    filing_type  { "ptr" }
    year         { 2026 }
    parse_status { "pending" }
  end

  factory :hof_holding, class: "HallOfFame::Holding" do
    association :filing, factory: :hof_filing
    owner       { "self" }
    asset_name  { "Apple Inc. - Common Stock (AAPL)" }
    ticker      { "AAPL" }
    value_label { "$1,001 - $15,000" }
    value_min   { 1001 }
    value_max   { 15_000 }
  end

  factory :hof_trade, class: "HallOfFame::Trade" do
    association :filing, factory: :hof_filing
    owner        { "SP" }
    asset_name   { "Intel Corporation - Common Stock (INTC) [OP]" }
    ticker       { "INTC" }
    tx_type      { "P" }
    amount_label { "$1,000,001 - $5,000,000" }
    amount_min   { 1_000_001 }
    amount_max   { 5_000_000 }
  end

  factory :hof_option_detail, class: "HallOfFame::OptionDetail" do
    association :trade, factory: :hof_trade
    option_right { "call" }
    strike       { 50 }
    expiration   { Date.new(2027, 3, 19) }
  end

  factory :hof_sync_run, class: "HallOfFame::SyncRun" do
    source     { "house" }
    started_at { Time.current }
  end
end

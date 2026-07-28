FactoryBot.define do
  factory :user_activity do
    user
    kind       { :page_view }
    path       { "/valuations/AAPL" }
    started_at { Time.current }
  end
end

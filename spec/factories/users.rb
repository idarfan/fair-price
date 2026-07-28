FactoryBot.define do
  factory :user do
    sequence(:email)      { |n| "user#{n}@example.com" }
    sequence(:google_uid) { |n| "google-uid-#{n}" }
    status { :pending }
  end
end

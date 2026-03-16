FactoryBot.define do
  factory :flight_message do
    association :flight_conversation
    role    { "user" }
    content { Faker::Lorem.sentence }

    trait :user do
      role { "user" }
    end

    trait :assistant do
      role    { "assistant" }
      content { "## 航班建議\n\n直飛：華航每日 2 班" }
    end
  end
end

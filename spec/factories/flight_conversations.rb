FactoryBot.define do
  factory :flight_conversation do
    token { SecureRandom.urlsafe_base64(24) }
  end
end

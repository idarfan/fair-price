require "rails_helper"

RSpec.describe FlightMessage, type: :model do
  describe "validations" do
    it "is valid with role user" do
      expect(build(:flight_message, :user)).to be_valid
    end

    it "is valid with role assistant" do
      expect(build(:flight_message, :assistant)).to be_valid
    end

    it "rejects invalid role" do
      expect(build(:flight_message, role: "admin")).not_to be_valid
    end

    it "requires content" do
      expect(build(:flight_message, content: nil)).not_to be_valid
    end

    it "requires role" do
      expect(build(:flight_message, role: nil)).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to a flight_conversation" do
      msg = create(:flight_message)
      expect(msg.flight_conversation).to be_a(FlightConversation)
    end
  end
end

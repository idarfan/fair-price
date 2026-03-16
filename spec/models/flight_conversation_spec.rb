require "rails_helper"

RSpec.describe FlightConversation, type: :model do
  describe "validations" do
    it "is valid with a unique token" do
      expect(build(:flight_conversation)).to be_valid
    end

    it "requires a token" do
      expect(build(:flight_conversation, token: nil)).not_to be_valid
    end

    it "requires a unique token" do
      create(:flight_conversation, token: "abc123")
      expect(build(:flight_conversation, token: "abc123")).not_to be_valid
    end
  end

  describe "associations" do
    it "destroys messages when conversation is destroyed" do
      conv = create(:flight_conversation)
      create(:flight_message, :user,      flight_conversation: conv)
      create(:flight_message, :assistant, flight_conversation: conv)

      expect { conv.destroy }.to change(FlightMessage, :count).by(-2)
    end
  end

  describe ".find_or_create_for_token" do
    it "returns an existing conversation by token" do
      conv = create(:flight_conversation)
      expect(described_class.find_or_create_for_token(conv.token)).to eq(conv)
    end

    it "creates a new conversation when token is nil" do
      expect { described_class.find_or_create_for_token(nil) }
        .to change(FlightConversation, :count).by(1)
    end

    it "creates a new conversation when token is unknown" do
      expect { described_class.find_or_create_for_token("nonexistent") }
        .to change(FlightConversation, :count).by(1)
    end
  end

  describe "#message_pairs" do
    it "returns empty array when no messages" do
      conv = create(:flight_conversation)
      expect(conv.message_pairs).to eq([])
    end

    it "pairs user and assistant messages in order" do
      conv = create(:flight_conversation)
      u1 = create(:flight_message, :user,      flight_conversation: conv, content: "問題一")
      a1 = create(:flight_message, :assistant, flight_conversation: conv, content: "回覆一")
      u2 = create(:flight_message, :user,      flight_conversation: conv, content: "問題二")
      a2 = create(:flight_message, :assistant, flight_conversation: conv, content: "回覆二")

      pairs = conv.message_pairs
      expect(pairs.length).to eq(2)
      expect(pairs[0]).to include(index: 0, question: "問題一", answer: "回覆一")
      expect(pairs[1]).to include(index: 1, question: "問題二", answer: "回覆二")
    end

    it "handles a dangling user message with no reply yet" do
      conv = create(:flight_conversation)
      create(:flight_message, :user, flight_conversation: conv, content: "未回覆的問題")

      pairs = conv.message_pairs
      expect(pairs.length).to eq(1)
      expect(pairs[0][:answer]).to be_nil
    end
  end

  describe "#history_for_api" do
    it "returns messages as role/content hashes" do
      conv = create(:flight_conversation)
      create(:flight_message, :user,      flight_conversation: conv, content: "問")
      create(:flight_message, :assistant, flight_conversation: conv, content: "答")

      history = conv.history_for_api
      expect(history).to eq([
        { role: "user",      content: "問" },
        { role: "assistant", content: "答" }
      ])
    end
  end
end

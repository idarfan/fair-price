require "rails_helper"

RSpec.describe "Flight", type: :request do
  # 所有 request spec 共用同一個 conversation token
  let(:conv) { create(:flight_conversation) }

  before do
    # 注入 session token，讓 before_action 找到正確的 conversation
    allow_any_instance_of(FlightController)
      .to receive(:session).and_return({ flight_conversation_token: conv.token })
  end

  describe "GET /flight" do
    it "returns 200 OK" do
      get flight_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the chat interface" do
      get flight_path
      expect(response.body).to include("台日航班專家")
    end

    it "shows existing question history" do
      create(:flight_message, :user,      flight_conversation: conv, content: "去石垣島怎麼搭？")
      create(:flight_message, :assistant, flight_conversation: conv, content: "直飛：虎航每週 3 班")

      get flight_path
      expect(response.body).to include("去石垣島怎麼搭？")
    end
  end

  describe "POST /flight/chat" do
    before do
      allow_any_instance_of(FlightChatService)
        .to receive(:call).and_return("## 直飛\n虎航每週 3 班")
    end

    it "returns JSON with reply_html and question" do
      post flight_chat_path, params: { message: "石垣島怎麼去？" }, as: :json
      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["reply_html"]).to match(/<h2[^>]*>/)
      expect(json["question"]).to eq("石垣島怎麼去？")
      expect(json["index"]).to eq(0)
    end

    it "saves user and assistant messages to DB" do
      expect {
        post flight_chat_path, params: { message: "測試問題" }, as: :json
      }.to change(FlightMessage, :count).by(2)
    end

    it "returns 422 for blank message" do
      post flight_chat_path, params: { message: "" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to be_present
    end

    it "increments index correctly after multiple questions" do
      create(:flight_message, :user,      flight_conversation: conv)
      create(:flight_message, :assistant, flight_conversation: conv)

      post flight_chat_path, params: { message: "第二個問題" }, as: :json
      expect(response.parsed_body["index"]).to eq(1)
    end
  end

  describe "GET /flight/clear" do
    it "redirects to flight index" do
      get clear_flight_path
      expect(response).to redirect_to(flight_path)
    end
  end
end

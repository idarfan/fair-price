require "rails_helper"

RSpec.describe FlightChatService do
  let(:service) { described_class.new }

  let(:success_body) do
    { "content" => [ { "type" => "text", "text" => "## 回覆\n直飛華航每日 2 班" } ] }.to_json
  end

  let(:success_response) do
    instance_double(HTTParty::Response,
                    success?: true,
                    code: 200,
                    parsed_response: JSON.parse(success_body))
  end

  describe "#call" do
    before do
      allow(HTTParty).to receive(:post).and_return(success_response)
    end

    it "returns markdown text from the API" do
      result = service.call("請問石垣島直飛嗎？")
      expect(result).to eq("## 回覆\n直飛華航每日 2 班")
    end

    it "sends the user message as the last history item" do
      service.call("新問題", [ { role: "user", content: "舊問題" } ])

      expect(HTTParty).to have_received(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["messages"].last["content"]).to eq("新問題")
        expect(body["messages"].length).to eq(2)
      end
    end

    it "raises on non-200 response" do
      error_response = instance_double(HTTParty::Response, success?: false, code: 529)
      allow(HTTParty).to receive(:post).and_return(error_response)

      expect { service.call("test") }.to raise_error(RuntimeError, /529/)
    end

    it "includes system prompt in request" do
      service.call("test")

      expect(HTTParty).to have_received(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["system"]).to include("台灣出發")
      end
    end
  end

  describe ".system_prompt" do
    it "strips YAML frontmatter" do
      expect(described_class.system_prompt).not_to start_with("---")
    end

    it "contains core skill content" do
      expect(described_class.system_prompt).to include("台灣出發")
    end
  end
end

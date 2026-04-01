# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortfolioOcrService do
  subject(:service) { described_class.new(image_file) }

  let(:image_file) do
    instance_double(
      ActionDispatch::Http::UploadedFile,
      read:         "fake_image_bytes",
      content_type: "image/png"
    )
  end

  let(:groq_success_body) do
    {
      "choices" => [
        { "message" => { "content" => '[{"symbol":"AAPL","shares":10.5,"unit_cost":150.25},{"symbol":"TSLA","shares":5,"unit_cost":200.00}]' } }
      ]
    }
  end

  def stub_groq(body:, status: 200)
    response = instance_double(HTTParty::Response,
      success?: status == 200,
      code:     status,
      parsed_response: body
    )
    allow(HTTParty).to receive(:post).and_return(response)
  end

  before { stub_const("ENV", ENV.to_h.merge("GROQ_API_KEY" => "test-key")) }

  # ── 正常情況 ────────────────────────────────────────────────────────────────

  describe "#call 正常回傳" do
    before { stub_groq(body: groq_success_body) }

    it "回傳正確筆數" do
      expect(service.call.length).to eq(2)
    end

    it "正確解析 symbol" do
      symbols = service.call.map { |h| h[:symbol] }
      expect(symbols).to eq(%w[AAPL TSLA])
    end

    it "正確解析 shares" do
      expect(service.call.first[:shares]).to eq(10.5)
    end

    it "正確解析 unit_cost" do
      expect(service.call.first[:unit_cost]).to eq(150.25)
    end
  end

  # ── symbol 清理 ─────────────────────────────────────────────────────────────

  describe "symbol 清理" do
    before do
      stub_groq(body: {
        "choices" => [
          { "message" => { "content" => '[{"symbol":"aapl ","shares":5,"unit_cost":100}]' } }
        ]
      })
    end

    it "轉為大寫並去除非法字元" do
      expect(service.call.first[:symbol]).to eq("AAPL")
    end
  end

  # ── 過濾無效列 ──────────────────────────────────────────────────────────────

  describe "過濾無效列" do
    before do
      stub_groq(body: {
        "choices" => [
          { "message" => { "content" => '[
            {"symbol":"AAPL","shares":10,"unit_cost":150},
            {"symbol":"MSFT","shares":0,"unit_cost":300},
            {"symbol":"","shares":5,"unit_cost":200},
            {"symbol":"GOOG","shares":3,"unit_cost":0}
          ]' } }
        ]
      })
    end

    it "只保留 shares > 0、unit_cost > 0、symbol 非空的列" do
      result = service.call
      expect(result.length).to eq(1)
      expect(result.first[:symbol]).to eq("AAPL")
    end
  end

  # ── API 錯誤 ────────────────────────────────────────────────────────────────

  describe "Groq API 回傳非 200" do
    before { stub_groq(body: {}, status: 500) }

    it "拋出錯誤" do
      expect { service.call }.to raise_error(RuntimeError, /API error/)
    end
  end

  # ── 回應格式異常 ────────────────────────────────────────────────────────────

  describe "回應中沒有 JSON array" do
    before do
      stub_groq(body: {
        "choices" => [ { "message" => { "content" => "找不到持股資料" } } ]
      })
    end

    it "拋出找不到 JSON 的錯誤" do
      expect { service.call }.to raise_error(RuntimeError, /No JSON array found/)
    end
  end

  describe "回應 JSON 格式錯誤" do
    before do
      stub_groq(body: {
        "choices" => [ { "message" => { "content" => "[{broken json}]" } } ]
      })
    end

    it "拋出解析失敗的錯誤" do
      expect { service.call }.to raise_error(RuntimeError, /OCR 結果無法解析/)
    end
  end

  # ── 缺少 API Key ────────────────────────────────────────────────────────────

  describe "缺少 GROQ_API_KEY" do
    before { stub_const("ENV", ENV.to_h.except("GROQ_API_KEY")) }

    it "拋出錯誤訊息說明 key 未設定" do
      expect { service.call }.to raise_error(RuntimeError, /GROQ_API_KEY not set/)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::AttributionAuditor do
  describe "規格 S8.3 必測案例" do
    it "1. 文字含機構名、白名單空 → 回傳非空" do
      result = described_class.call(text: "目標價來自美銀的預估", sources: [])
      expect(result).not_to be_empty
      expect(result.map(&:keyword)).to include("美銀")
    end

    it "2. 文字含機構名、白名單含該名 → 回傳空" do
      expect(described_class.call(text: "目標價來自美銀的預估", sources: [ "美銀" ])).to be_empty
    end

    it "3. 乾淨文字 → 回傳空" do
      expect(described_class.call(text: "FY2028 需要 EPS $7.45", sources: [])).to be_empty
    end

    it "4. 繁簡兩種寫法都要命中" do
      expect(described_class.call(text: "美銀報告", sources: []).map(&:keyword)).to include("美銀")
      expect(described_class.call(text: "美银报告", sources: []).map(&:keyword)).to include("美银")
      expect(described_class.call(text: "巴克萊", sources: []).map(&:keyword)).to include("巴克萊")
      expect(described_class.call(text: "巴克莱", sources: []).map(&:keyword)).to include("巴克莱")
    end

    it "英文機構名同樣命中" do
      %w[Goldman Barclays UBS Stifel].each do |kw|
        expect(described_class.call(text: "source: #{kw} research", sources: []).map(&:keyword)).to include(kw)
      end
    end
  end

  describe "白名單比對" do
    # 要求逐字相等等於逼使用者填得跟黑名單一模一樣。
    it "白名單項目包含該關鍵字即算放行" do
      expect(described_class.call(text: "高盛目標價", sources: [ "高盛 2026/09 研報" ])).to be_empty
    end

    it "不相關的白名單不會誤放行" do
      expect(described_class.call(text: "高盛目標價", sources: [ "自己推算" ])).not_to be_empty
    end
  end

  describe "#hits（警示視窗要顯示因為什麼被放行）" do
    it "同時列出被擋下與被放行的命中" do
      auditor = described_class.new(text: "美銀與高盛都提到", sources: [ "美銀報告" ])
      hits = auditor.hits

      expect(hits.map(&:keyword)).to contain_exactly("美銀", "高盛")
      expect(hits.find { |h| h.keyword == "美銀" }.allowed_by).to eq("美銀報告")
      expect(hits.find { |h| h.keyword == "高盛" }).not_to be_allowed
    end
  end

  describe "邊界" do
    it "空文字回傳空" do
      expect(described_class.call(text: "", sources: [])).to be_empty
    end

    it "nil 文字不拋例外" do
      expect { described_class.call(text: nil, sources: nil) }.not_to raise_error
    end

    it "白名單中的空字串不會放行任何東西" do
      expect(described_class.call(text: "高盛", sources: [ "", "  " ])).not_to be_empty
    end
  end
end

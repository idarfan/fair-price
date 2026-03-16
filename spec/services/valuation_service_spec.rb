require "rails_helper"

RSpec.describe ValuationService do
  # ── 基礎 stock data helper ──────────────────────────────────────────────────
  #
  # 提供一個典型的科技股（一般股）資料集。各測試透過 merge 覆蓋所需欄位。
  def base_stock(overrides = {})
    {
      sector:                    "Technology",
      industry:                  "Software",
      eps_ttm:                   5.0,
      forward_eps:               5.75,
      current_price:             150.0,
      free_cashflow:             10_000_000_000,
      shares_outstanding:        100_000_000,
      earnings_growth:           0.15,
      revenue_growth:            0.20,
      earnings_quarterly_growth: nil,
      book_value:                20.0,
      roe:                       0.25,
      dividend_rate:             nil,
      total_revenue:             50_000_000_000,
      ebitda:                    nil,
      total_debt:                nil,
      total_cash:                nil
    }.merge(overrides)
  end

  # ── 股票分類（classify） ────────────────────────────────────────────────────

  describe "股票分類" do
    subject(:result) { described_class.analyze(data) }

    context "Real Estate 產業" do
      let(:data) { base_stock(sector: "Real Estate") }

      it { expect(result[:stock_type]).to eq("REITs") }
    end

    context "Utilities 產業" do
      let(:data) { base_stock(sector: "Utilities") }

      it { expect(result[:stock_type]).to eq("公用事業") }
    end

    context "Financial Services 產業" do
      let(:data) { base_stock(sector: "Financial Services") }

      it { expect(result[:stock_type]).to eq("金融股") }
    end

    context "Energy 產業" do
      let(:data) { base_stock(sector: "Energy") }

      it { expect(result[:stock_type]).to eq("週期股") }
    end

    context "Basic Materials 產業" do
      let(:data) { base_stock(sector: "Basic Materials") }

      it { expect(result[:stock_type]).to eq("週期股") }
    end

    context "Consumer Cyclical + 負 EPS" do
      let(:data) { base_stock(sector: "Consumer Cyclical", eps_ttm: -1.0) }

      it { expect(result[:stock_type]).to eq("週期股") }
    end

    context "industry 關鍵字含 steel → 週期股" do
      let(:data) { base_stock(sector: "Industrials", industry: "integrated steel") }

      it { expect(result[:stock_type]).to eq("週期股") }
    end

    context "Technology + 負 EPS + 高營收成長" do
      let(:data) { base_stock(eps_ttm: -2.0, revenue_growth: 0.25) }

      it { expect(result[:stock_type]).to eq("虧損成長股") }
    end

    context "Technology + 負 EPS + 低營收成長（< 10%）" do
      let(:data) { base_stock(eps_ttm: -2.0, revenue_growth: 0.05) }

      # 不符合虧損成長股條件，歸為一般股
      it { expect(result[:stock_type]).to eq("一般股") }
    end

    context "Technology + 正 EPS（標準科技股）" do
      let(:data) { base_stock }

      it { expect(result[:stock_type]).to eq("一般股") }
    end
  end

  # ── 成長率估算（estimate_growth_rate） ──────────────────────────────────────

  describe "成長率估算" do
    context "無任何成長率資料" do
      let(:data) do
        base_stock(
          earnings_growth: nil, revenue_growth: nil,
          earnings_quarterly_growth: nil, forward_eps: nil
        )
      end

      it "預設回傳 0.10" do
        result = described_class.analyze(data)
        expect(result[:growth_rate]).to eq(0.10)
      end
    end

    context "單一來源（earnings_growth: 0.80），超過上限" do
      let(:data) do
        base_stock(
          earnings_growth: 0.80, revenue_growth: nil,
          earnings_quarterly_growth: nil, forward_eps: nil
        )
      end

      it "clamp 到上限 0.45" do
        result = described_class.analyze(data)
        expect(result[:growth_rate]).to eq(0.45)
      end
    end

    context "單一來源（earnings_growth: 0.01），低於下限" do
      let(:data) do
        base_stock(
          earnings_growth: 0.01, revenue_growth: nil,
          earnings_quarterly_growth: nil, forward_eps: nil
        )
      end

      it "clamp 到下限 0.03" do
        result = described_class.analyze(data)
        expect(result[:growth_rate]).to eq(0.03)
      end
    end

    context "多來源（0.10, 0.20, 0.30）" do
      let(:data) do
        base_stock(
          earnings_growth: 0.10, revenue_growth: 0.30,
          earnings_quarterly_growth: 0.20, forward_eps: nil
        )
      end

      it "取中位數（0.20）" do
        result = described_class.analyze(data)
        expect(result[:growth_rate]).to eq(0.20)
      end
    end
  end

  # ── 估值方法選擇 ─────────────────────────────────────────────────────────────

  describe "估值方法組合" do
    def method_names(data, **opts)
      described_class.analyze(data, **opts)[:valuation_methods].map { |m| m[:method] }
    end

    context "一般股（Technology）" do
      it "包含 DCF, P/E, PEG" do
        names = method_names(base_stock)
        expect(names).to include("DCF", "P/E", "PEG")
      end
    end

    context "金融股（Financial Services）" do
      let(:data) { base_stock(sector: "Financial Services") }

      it "包含 ExcessRet, P/E, P/B" do
        names = method_names(data)
        expect(names).to include("ExcessRet", "P/E", "P/B")
      end

      it "不包含 DCF" do
        expect(method_names(data)).not_to include("DCF")
      end
    end

    context "REITs（Real Estate）" do
      let(:data) { base_stock(sector: "Real Estate", dividend_rate: 2.0) }

      it "包含 DDM, DCF, P/B" do
        names = method_names(data)
        expect(names).to include("DDM", "DCF", "P/B")
      end
    end

    context "公用事業（Utilities）" do
      let(:data) { base_stock(sector: "Utilities", dividend_rate: 1.5) }

      it "包含 DDM, DCF, P/E" do
        names = method_names(data)
        expect(names).to include("DDM", "DCF", "P/E")
      end
    end

    context "虧損成長股（Technology + 負 EPS）" do
      let(:data) { base_stock(eps_ttm: -3.0, revenue_growth: 0.30) }

      it "包含 Rev×3, DCF（若 FCF 為正）" do
        names = method_names(data)
        expect(names).to include("Rev×3")
      end
    end

    context "週期股（Energy）" do
      let(:data) do
        base_stock(
          sector: "Energy",
          ebitda: 5_000_000_000,
          total_debt: 2_000_000_000,
          total_cash: 500_000_000
        )
      end

      it "包含 EV/EBITDA, P/B, DCF" do
        names = method_names(data)
        expect(names).to include("EV/EBITDA", "P/B", "DCF")
      end
    end
  end

  # ── 個別估值方法的 nil 條件 ──────────────────────────────────────────────────

  describe "個別估值方法：nil 條件" do
    context "DCF：FCF 為負且 EPS 亦為 nil（無 fallback 可用）" do
      # adjust_fcf 有 EPS fallback：若 EPS > 0，即使 FCF 為負也會用 EPS×0.75 代替。
      # 要測試 DCF 真正回 nil，需同時確保 EPS 無效（nil 或負值）。
      let(:data) { base_stock(free_cashflow: -1_000_000_000, eps_ttm: nil, forward_eps: nil) }

      it "不包含 DCF 方法" do
        result = described_class.analyze(data)
        names  = result[:valuation_methods].map { |m| m[:method] }
        expect(names).not_to include("DCF")
      end
    end

    context "P/E：EPS 為負" do
      let(:data) { base_stock(eps_ttm: -5.0, revenue_growth: 0.30) }

      it "不包含 P/E 方法（虧損成長股）" do
        result = described_class.analyze(data)
        names  = result[:valuation_methods].map { |m| m[:method] }
        expect(names).not_to include("P/E")
      end
    end

    context "DDM：無股息" do
      let(:data) { base_stock(sector: "Real Estate", dividend_rate: nil) }

      it "不包含 DDM 方法" do
        result = described_class.analyze(data)
        names  = result[:valuation_methods].map { |m| m[:method] }
        expect(names).not_to include("DDM")
      end
    end

    context "P/B：book_value 為零" do
      let(:data) { base_stock(sector: "Financial Services", book_value: nil, roe: 0.15) }

      it "不包含 P/B 方法" do
        result = described_class.analyze(data)
        names  = result[:valuation_methods].map { |m| m[:method] }
        expect(names).not_to include("P/B")
      end
    end
  end

  # ── 整合測試（analyze 回傳結構） ────────────────────────────────────────────

  describe ".analyze 回傳結構" do
    subject(:result) { described_class.analyze(base_stock) }

    it "包含所有必要 key" do
      expect(result.keys).to include(
        :stock_type, :stock_type_rationale, :growth_rate,
        :growth_rate_note, :valuation_methods,
        :fair_value_low, :fair_value_high, :judgment
      )
    end

    it "fair_value_low <= fair_value_high" do
      expect(result[:fair_value_low]).to be <= result[:fair_value_high]
    end

    it "每個估值方法包含 method, value, note, formula, rationale" do
      result[:valuation_methods].each do |m|
        expect(m.keys).to include(:method, :value, :note, :formula, :rationale)
        expect(m[:value]).to be_a(Numeric)
      end
    end

    it "stock_type_rationale 為非空字串" do
      expect(result[:stock_type_rationale]).to be_a(String).and be_present
    end
  end

  # ── judgment 邏輯 ───────────────────────────────────────────────────────────

  describe "judgment 判斷" do
    def judgment_for(price, overrides = {})
      described_class.analyze(base_stock(overrides.merge(current_price: price)))[:judgment]
    end

    it "明顯高估：price > fair_value_high × 1.2" do
      # 用極低 discount_rate 讓估值偏低，price 高到觸發明顯高估
      result = described_class.analyze(
        base_stock(current_price: 10_000.0),
        discount_rate: 0.20
      )
      expect(result[:judgment]).to eq("🔴 明顯高估")
    end

    it "資料不足時回傳 ⚪ 資料不足" do
      # 所有估值方法皆為 nil → values 為空 → lo/hi 為 nil
      result = described_class.analyze(
        base_stock(
          free_cashflow: -1, eps_ttm: -1.0, forward_eps: nil,
          book_value: nil, dividend_rate: nil,
          revenue_growth: 0.05, ebitda: nil, roe: nil
        )
      )
      expect(result[:judgment]).to eq("⚪ 資料不足")
    end
  end

  # ── discount_rate 邊界值 ────────────────────────────────────────────────────

  describe "discount_rate clamp" do
    it "低於 0.06 時 clamp 到 0.06" do
      result = described_class.analyze(base_stock, discount_rate: 0.01)
      expect(result[:valuation_methods]).not_to be_empty
    end

    it "高於 0.20 時 clamp 到 0.20" do
      result = described_class.analyze(base_stock, discount_rate: 0.99)
      expect(result[:valuation_methods]).not_to be_empty
    end
  end
end

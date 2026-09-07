# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::ScenarioForm do
  def build(**overrides) = described_class.new(**overrides)

  describe "負向案例（規格 S2 第 1–14 案）" do
    it "1. price = -1 被擋下" do
      form = build(price: -1)
      expect(form).not_to be_valid
      expect(form.errors[:price].join).to include("必須大於 0")
    end

    # 規格 S2 原案例 2 要求空陣列回 invalid。2026-09-07 依使用者要求改為
    # 「輸入框預設留空、留空則套預設值」——留空是使用者最自然的動作，
    # 為它報錯會讓圖 A 整張消失，而使用者只是沒動那一格。
    # 「計算器不會收到零個倍數」這個不變式改由預設值保證，而不是由錯誤訊息保證。
    it "2. chart_a_multiples 留空時套用預設值，不視為錯誤" do
      form = build(chart_a_multiples: [])
      expect(form).to be_valid
      expect(form.chart_a_multiples).to eq([ 25.0, 30.0, 35.0 ])
      expect(form.chart_a_multiples_provided?).to be(false)
    end

    it "2b. 填了 0 這種無意義的倍數仍被擋下" do
      form = build(chart_a_multiples: [ 25, 0 ])
      expect(form).not_to be_valid
      expect(form.errors[:chart_a_multiples].join).to include("大於 0")
    end

    it "3. chart_a_multiples 有重複值被擋下" do
      form = build(chart_a_multiples: [ 25, 25 ])
      expect(form).not_to be_valid
      expect(form.errors[:chart_a_multiples].join).to include("不可重複")
    end

    it "4. chart_a_multiples 超過 5 個被擋下" do
      form = build(chart_a_multiples: [ 10, 15, 20, 25, 30, 35 ])
      expect(form).not_to be_valid
      expect(form.errors[:chart_a_multiples].join).to include("最多 5 個")
    end

    it "5. fiscal_year_label 為空字串被擋下，且訊息說得出為什麼" do
      form = build(fiscal_year_label: "")
      expect(form).not_to be_valid
      expect(form.errors[:fiscal_year_label].join).to include("沒有時間")
    end

    it "6. eps_band_low 大於 eps_band_high 被擋下" do
      form = build(eps_band_low: 8.0, eps_band_high: 7.0, eps_band_label: "分析師預測")
      expect(form).not_to be_valid
      expect(form.errors[:eps_band_high].join).to include("大於或等於下限")
    end

    it "7. eps_band_low 有值但 eps_band_high 留空被擋下" do
      form = build(eps_band_low: 6.6)
      expect(form).not_to be_valid
      expect(form.errors[:eps_band_high].join).to include("同時填寫")
    end

    it "8. eps 有值且 entry_b_price 等於 entry_a_price 被擋下" do
      form = build(eps: 11.02, price: 223.55, entry_b_price: 223.55)
      expect(form).not_to be_valid
      expect(form.errors[:entry_b_price].join).to include("完全重疊")
    end

    it "9. discount_rate = 1.5 被擋下" do
      form = build(discount_rate: 1.5, discount_years: 2)
      expect(form).not_to be_valid
      expect(form.errors[:discount_rate].join).to include("0 到 1")
    end

    it "10. ticker 為空字串被擋下" do
      form = build(ticker: "")
      expect(form).not_to be_valid
      expect(form.errors[:ticker]).to be_present
    end

    it "11. ticker = TOOLONG1 格式不符被擋下" do
      form = build(ticker: "TOOLONG1")
      expect(form).not_to be_valid
      expect(form.errors[:ticker].join).to include("格式不正確")
    end

    it "12. eps 有值但 chart_b_fiscal_year_label 為空被擋下" do
      form = build(eps: 11.02, chart_b_fiscal_year_label: "")
      expect(form).not_to be_valid
      expect(form.errors[:chart_b_fiscal_year_label].join).to include("哪一年")
    end

    it "13. attribution_sources 有 6 項被擋下" do
      form = build(attribution_sources: %w[a b c d e f])
      expect(form).not_to be_valid
      expect(form.errors[:attribution_sources].join).to include("最多 5 項")
    end

    it "14. attribution_sources 單項超過 30 字被擋下" do
      form = build(attribution_sources: [ "來" * 31 ])
      expect(form).not_to be_valid
      expect(form.errors[:attribution_sources].join).to include("30 字")
    end
  end

  describe "正向案例（規格 S2 第 15–17 案）" do
    it "15. ticker 小寫 mrvl 正規化為 MRVL 且通過驗證" do
      form = build(ticker: "mrvl")
      expect(form).to be_valid
      expect(form.ticker).to eq("MRVL")
    end

    # 這是 S2 的重點案例。eps 留空是空狀態，不是錯誤——
    # 若讓整張表單失效，圖 A 也會跟著消失。
    it "16. eps 留空、圖 A 欄位齊全 → valid?，且 chart_b_ready? 為 false" do
      form = build(price: 223.55, chart_a_multiples: [ 25, 30, 35 ], fiscal_year_label: "FY2028")
      expect(form).to be_valid
      expect(form.chart_b_ready?).to be(false)
    end

    it "17. entry_a_link_price 為 true 時改 price，entry_a_price 同步變動" do
      form = build(price: 223.55)
      expect(form.entry_a_price).to eq(223.55)
      form.price = 300
      expect(form.entry_a_price).to eq(300)
    end
  end

  describe "輸入框留空與使用者自填的區別" do
    it "使用者自填時 provided? 為 true，畫面才回填該值" do
      form = build(chart_a_multiples: "40,50")
      expect(form.chart_a_multiples_provided?).to be(true)
      expect(form.chart_a_multiples).to eq([ 40.0, 50.0 ])
    end

    it "空字串（欄位留空送出）視同沒填" do
      form = build(chart_a_multiples: "")
      expect(form).to be_valid
      expect(form.chart_a_multiples_provided?).to be(false)
      expect(form.chart_a_multiples).to eq([ 25.0, 30.0, 35.0 ])
    end

    it "只有逗號與空白也視同沒填" do
      form = build(chart_a_multiples: " , , ")
      expect(form.chart_a_multiples_provided?).to be(false)
    end
  end

  describe "連結解除" do
    it "entry_a_link_price 為 false 時 entry_a_price 不跟著 price 變" do
      form = build(price: 223.55, entry_a_link_price: false, entry_a_price: 180)
      form.price = 300
      expect(form.entry_a_price).to eq(180)
    end
  end

  describe "自動組出的標籤" do
    it "價格一變，標籤裡的金額跟著變（寫死的標籤會讓圖例說謊）" do
      form = build(price: 223.55, entry_b_price: 365)
      expect(form.entry_a_label).to eq("買入基準 $223.55")
      expect(form.entry_b_label).to eq("假設買入價 $365.00")

      form.price = 300
      expect(form.entry_a_label).to eq("買入基準 $300.00")
    end
  end

  describe "不阻擋出圖的提示" do
    it "年度與持有年數明顯不一致時給提示，但仍然 valid" do
      form = build(eps: 11.02, chart_b_fiscal_year_label: "FY2031", holding_years: 2.5, entry_b_price: 365)
      expect(form).to be_valid
      expect(form.warnings.join).to include("持有年數")
    end

    it "一致時沒有提示" do
      form = build(eps: 11.02, chart_b_fiscal_year_label: "FY#{Date.current.year + 2}",
                   holding_years: 2, entry_b_price: 365)
      expect(form.warnings).to be_empty
    end
  end

  describe ".from_params（情境狀態走 query string）" do
    it "吃逗號分隔字串的 multiples" do
      form = described_class.from_params(ActionController::Parameters.new(
        chart_a_multiples: "25,30,35", price: "300"
      ).permit!)
      expect(form.chart_a_multiples).to eq([ 25.0, 30.0, 35.0 ])
      expect(form.price).to eq(300)
    end

    it "無參數時全部落回預設值且 valid" do
      form = described_class.from_params(ActionController::Parameters.new({}).permit!)
      expect(form).to be_valid
      expect(form.ticker).to eq("MRVL")
      expect(form.price).to eq(223.55)
      expect(form.fiscal_year_label).to eq("FY2028")
    end
  end

  describe "price_as_of 來源標示" do
    it "有時間戳時顯示報價時間" do
      form = build(price_as_of: Time.zone.local(2026, 9, 7, 13, 45))
      expect(form.price_source_label).to include("2026-09-07 13:45")
    end

    it "沒有時間戳時顯示手動輸入" do
      expect(build.price_source_label).to eq("手動輸入")
    end
  end
end

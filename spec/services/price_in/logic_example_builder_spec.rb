# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::LogicExampleBuilder do
  # 存在的理由是一個具體的誤判：把「現價 ÷ TTM EPS」算出來的倍數填回去當假設，
  # 需要的 EPS 必然等於 TTM EPS，因為那只是把除法倒推回去。
  describe "循環論證偵測" do
    subject(:rows) do
      described_class.call(price: 223.59, multiples: [ 73.8, 50, 30 ],
                           band_low: 3.92, band_high: 4.34,
                           fiscal_year_label: "FY2027",
                           implied_current: 223.59 / 3.03)[:rows]
    end

    it "把現價反推的倍數標記為循環論證" do
      circular = rows.select { |r| r[:circular] }
      expect(circular.length).to eq(1)
      expect(circular.first[:multiple]).to eq("73.8 倍")
      expect(circular.first[:verdict]).to include("循環論證")
    end

    it "循環那一列算出來的正是 TTM EPS 本身" do
      expect(rows.find { |r| r[:circular] }[:required_eps]).to eq("$3.03")
    end

    it "使用者自己判斷的倍數不被標記" do
      expect(rows.reject { |r| r[:circular] }.map { |r| r[:multiple] }).to eq([ "50 倍", "30 倍" ])
    end

    # 沒抓到報價時寧可不標記，也不要把使用者自己判斷的倍數誤標成無效。
    it "沒有 implied_current 時完全不做標記" do
      rows = described_class.call(price: 223.59, multiples: [ 73.8 ], band_low: 3.92, band_high: 4.34)[:rows]
      expect(rows.none? { |r| r[:circular] }).to be(true)
    end
  end

  describe "判讀" do
    def verdict(multiple)
      described_class.call(price: 223.59, multiples: [ multiple ],
                           band_low: 3.92, band_high: 4.34,
                           fiscal_year_label: "FY2027")[:rows].first[:verdict]
    end

    it "需要的 EPS 低於預測下限 → 現有預測撐得住" do
      # 223.59 / 60 = 3.73 < 3.92
      expect(verdict(60)).to include("撐得住")
    end

    it "需要的 EPS 落在區間之中 → 需要偏上緣" do
      # 223.59 / 55 = 4.07，介於 3.92 與 4.34
      expect(verdict(55)).to include("偏上緣")
    end

    it "需要的 EPS 高於預測上限 → 額外的樂觀" do
      expect(verdict(30)).to include("額外的樂觀")
    end

    it "判讀一律標註年度（缺年度的比較無效）" do
      expect(verdict(30)).to include("FY2027")
    end

    it "沒有預測區間時不妄下判讀" do
      rows = described_class.call(price: 223.59, multiples: [ 30 ])[:rows]
      expect(rows.first[:verdict]).to include("填入 EPS 預測區間")
    end
  end

  describe "反向視角（不需要先給倍數，因此沒有循環論證）" do
    it "算出現價相當於預測區間兩端的幾倍" do
      note = described_class.call(price: 223.59, multiples: [ 30 ],
                                  band_low: 3.92, band_high: 4.34,
                                  fiscal_year_label: "FY2027")[:footnote]
      expect(note).to include("51.5 倍")   # 223.59 / 4.34
      expect(note).to include("57.0 倍")   # 223.59 / 3.92
    end
  end

  describe "邊界" do
    it "股價為 0 時回傳 nil，不拋例外" do
      expect { described_class.call(price: 0, multiples: [ 30 ]) }.not_to raise_error
      expect(described_class.call(price: 0, multiples: [ 30 ])).to be_nil
    end

    it "沒有倍數時回傳 nil" do
      expect(described_class.call(price: 223.59, multiples: [])).to be_nil
    end

    it "倍數由大到小排列，與圖 A 的列順序一致" do
      rows = described_class.call(price: 223.59, multiples: [ 30, 73.8, 50 ])[:rows]
      expect(rows.map { |r| r[:multiple] }).to eq([ "73.8 倍", "50 倍", "30 倍" ])
    end
  end
end

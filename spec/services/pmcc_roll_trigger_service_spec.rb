# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccRollTriggerService do
  let(:short_leg) { build(:pmcc_short_leg) }

  def result(quote, manual: false)
    described_class.call(short_leg, quote: quote, manual: manual)
  end

  def codes(res)
    res[:reasons].map(&:code)
  end

  # pmcc-tracker Phase 2 驗收：4 組已知案例，觸發結果與手算一致。
  # moneyness 正=價內、負=價外（見 pmcc_short_call_snapshots 的慣例）
  describe "驗收：四組已知案例" do
    it "深度價內 → 觸發（Delta 0.72 ≥ 0.60）" do
      res = result({ delta: 0.72, dte: 30, moneyness: 0.18 })

      expect(res[:should_roll]).to be true
      expect(codes(res)).to eq([ :deep_itm ])
    end

    it "價平但天期還長 → 不觸發" do
      res = result({ delta: 0.50, dte: 30, moneyness: 0.0 })

      expect(res[:should_roll]).to be false
      expect(res[:reasons]).to be_empty
    end

    it "價外且天期還長 → 不觸發" do
      res = result({ delta: 0.22, dte: 30, moneyness: -0.12 })

      expect(res[:should_roll]).to be false
    end

    it "近到期且接近價內 → 觸發" do
      res = result({ delta: 0.48, dte: 3, moneyness: -0.01 })

      expect(res[:should_roll]).to be true
      expect(codes(res)).to eq([ :near_expiry_at_money ])
    end
  end

  describe "規則 1：深度價內" do
    it "邊界 0.60 觸發，0.59 不觸發" do
      expect(result({ delta: 0.60, dte: 30, moneyness: 0.1 })[:should_roll]).to be true
      expect(result({ delta: 0.59, dte: 30, moneyness: 0.1 })[:should_roll]).to be false
    end

    it "訊息帶出實際 Delta，讓畫面說得出依據" do
      res = result({ delta: 0.72, dte: 30, moneyness: 0.18 })

      expect(res[:reasons].first.message).to include("0.72", "0.6")
    end
  end

  describe "規則 2：近到期且接近價內" do
    it "邊界 DTE 5 觸發，6 不觸發" do
      expect(result({ delta: 0.3, dte: 5, moneyness: 0.0 })[:should_roll]).to be true
      expect(result({ delta: 0.3, dte: 6, moneyness: 0.0 })[:should_roll]).to be false
    end

    it "邊界 moneyness −5% 觸發，−5.1% 不觸發" do
      expect(result({ delta: 0.3, dte: 3, moneyness: -0.05 })[:should_roll]).to be true
      expect(result({ delta: 0.3, dte: 3, moneyness: -0.051 })[:should_roll]).to be false
    end

    # 近到期但深度價外：被指派風險低，讓它自然歸零比滾倉划算
    it "近到期但很價外 → 不觸發" do
      expect(result({ delta: 0.05, dte: 2, moneyness: -0.30 })[:should_roll]).to be false
    end
  end

  describe "規則 3：手動觸發" do
    it "沒有任何規則成立也照樣回傳建議" do
      res = result({ delta: 0.22, dte: 30, moneyness: -0.12 }, manual: true)

      expect(res[:should_roll]).to be true
      expect(codes(res)).to eq([ :manual ])
    end

    it "報價缺失時仍可手動觸發（使用者自己知道要滾）" do
      res = result(nil, manual: true)

      expect(res[:should_roll]).to be true
      expect(res[:error]).to be_nil
    end
  end

  describe "多條規則同時成立" do
    it "回傳全部原因，不是只回第一個" do
      res = result({ delta: 0.85, dte: 2, moneyness: 0.22 }, manual: true)

      expect(codes(res)).to contain_exactly(:deep_itm, :near_expiry_at_money, :manual)
    end
  end

  describe "報價缺失" do
    # 沒有資料就回「不需滾倉」是危險的：使用者會以為系統看過了說沒事
    it "回 :no_quote 而不是「不需滾倉」" do
      res = result(nil)

      expect(res[:should_roll]).to be false
      expect(res[:error]).to eq(:no_quote)
    end

    it "欄位全空的報價也算缺失" do
      expect(result({ delta: nil, dte: nil, moneyness: nil })[:error]).to eq(:no_quote)
    end

    it "只有 delta 也能判斷規則 1" do
      res = result({ delta: 0.72, dte: nil, moneyness: nil })

      expect(res[:error]).to be_nil
      expect(codes(res)).to eq([ :deep_itm ])
    end
  end

  describe "資料來源相容" do
    let(:snapshot) do
      create(:pmcc_short_call_snapshot, delta: 0.72, dte: 30, moneyness: 0.18)
    end

    it "吃得下 PmccShortCallSnapshot" do
      expect(described_class.call(short_leg, quote: snapshot)[:should_roll]).to be true
    end

    it "吃得下字串 key 的 Hash" do
      res = described_class.call(short_leg, quote: { "delta" => 0.72, "dte" => 30, "moneyness" => 0.18 })

      expect(codes(res)).to eq([ :deep_itm ])
    end
  end

  it "回傳判斷當下用到的數值，畫面才說得出依據" do
    res = result({ delta: 0.72, dte: 30, moneyness: 0.18 })

    expect(res[:evaluated]).to eq({ delta: 0.72, dte: 30, moneyness: 0.18 })
  end
end

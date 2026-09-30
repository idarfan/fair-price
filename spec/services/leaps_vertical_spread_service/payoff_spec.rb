# frozen_string_literal: true

require "rails_helper"

# 預估股價 → 平倉理論損益＋到期損益（leaps-call-spread-spec P7；tasks/leaps-vertical-fix.md S3）。
# 兩腳參數由區塊渲染時帶到頁面上（data-vs-payoff-params），這裡只重算、不抓 Barchart。
# FX-1：LC 100 bid 74.95／ask 79.05、SC 240 bid 29.70／ask 33.70、S₀ 150、報價日 2026-09-30、到期 2028-12-15。
RSpec.describe LeapsVerticalSpreadService::Payoff do
  let(:spread) do
    { long_strike: "100.0", long_bid: "74.95", long_ask: "79.05", long_price: "77.0",
      short_strike: "240.0", short_bid: "29.7", short_ask: "33.7", short_price: "31.7",
      spot: "150.0", quote_date: "2026-09-30", expiry: "2028-12-15", dividend_annual: "0",
      spot_quoted_at: "2026-09-30T14:00:00Z", option_quoted_at: "2026-09-30T14:00:00Z", contracts: "1" }
  end

  before { allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0")) }

  def call(target, **overrides)
    described_class.call(spread.merge(target_price: target).merge(overrides))
  end

  describe "到期損益" do
    it "預估價 200：+$5,470.00（+120.75%）" do
      result = call("200")
      expect(result[:expiry][:display]).to eq(pnl: "+$5,470.00", pct: "+120.75%")
      expect(result[:expiry][:tone]).to eq(:profit)
    end

    it "預估價低於買入腳：虧掉全部淨成本，-100%" do
      expect(call("90")[:expiry][:display]).to eq(pnl: "-$4,530.00", pct: "-100.00%")
    end

    it "預估價剛好在兩平點：$0.00、tone breakeven" do
      result = call("145.30")
      expect(result[:expiry][:display]).to eq(pnl: "$0.00", pct: "0.00%")
      expect(result[:expiry][:tone]).to eq(:breakeven)
    end

    it "預估價 0（標的歸零）：屬於低於買入腳" do
      expect(call("0")[:expiry][:display][:pnl]).to eq("-$4,530.00")
    end

    it "2 口：金額加倍" do
      expect(call("200", contracts: "2")[:expiry][:display][:pnl]).to eq("+$10,940.00")
    end
  end

  describe "平倉理論損益" do
    it "平倉日 = 到期日：平倉損益文字等於到期損益文字；保守 +$4,660.00" do
      result = call("200", close_date: "2028-12-15")
      expect(result[:close][:display][:pnl]).to eq(result[:expiry][:display][:pnl])
      expect(result[:close][:display][:conservative]).to eq("+$4,660.00")
    end

    it "平倉日空白：以報價日計算，損益低於到期損益" do
      result = call("200")
      expect(result[:close][:pnl]).to be_between(0, BigDecimal("5470")).exclusive
    end

    it "IV 調整 +10：平倉損益低於不調整" do
      expect(call("200", iv_shift: "10")[:close][:pnl]).to be < call("200")[:close][:pnl]
    end

    it "反推 IV 失敗：平倉部分回錯誤，到期損益照常" do
      result = call("200", long_bid: "49", long_ask: "51", long_price: "50")
      expect(result[:close]).to eq(error: "無法反推 IV，平倉損益不可用")
      expect(result[:expiry][:display][:pnl]).to be_present
    end

    it "平倉日超出範圍：平倉部分回錯誤" do
      expect(call("200", close_date: "2029-01-01")[:close]).to have_key(:error)
    end

    it "年股息 > 0、賣出腳價內：early_assignment_risk" do
      expect(call("250", dividend_annual: "1.00")[:flags][:early_assignment_risk]).to be(true)
      expect(call("200", dividend_annual: "1.00")[:flags][:early_assignment_risk]).to be(false)
    end
  end

  it "預估價空白：回 nil（不顯示結果）" do
    expect(call("")).to be_nil
    expect(call(nil)).to be_nil
  end

  it "預估價不是數字、非有限值或為負數：回錯誤" do
    %w[abc -5 NaN Infinity].each do |bad|
      expect(call(bad)).to eq(error: "預估股價格式錯誤：#{bad}")
    end
  end

  it "IV 調整超出 −50～+50 或不是數字：回錯誤" do
    %w[51 -51 abc NaN].each { |bad| expect(call("200", iv_shift: bad)).to have_key(:error) }
  end

  it "平倉日格式錯誤：回錯誤" do
    expect(call("200", close_date: "2026-13-40")).to have_key(:error)
  end

  it "兩腳參數不合法（K_S ≤ K_L、淨成本 ≤ 0 或 ≥ 寬度、格式錯誤、口數非正整數）：回錯誤" do
    expect(call("150", short_strike: "100")).to have_key(:error)
    expect(call("150", long_price: "31.7")).to have_key(:error)
    expect(call("150", long_price: "200", short_price: "10")).to have_key(:error)
    expect(call("150", long_strike: "x")).to have_key(:error)
    expect(call("150", contracts: "0")).to have_key(:error)
    expect(call("150", contracts: "1.5")).to have_key(:error)
    expect(call("150", expiry: "x")).to have_key(:error)
  end

  it "選填欄位有值卻解析不出來（股息、bid／ask、報價時間）：回錯誤，不當成沒有值" do
    expect(call("150", dividend_annual: "abc")).to have_key(:error)
    expect(call("150", short_bid: "abc")).to have_key(:error)
    expect(call("150", spot_quoted_at: "yesterday")).to have_key(:error)
  end

  it "選填欄位空白：股息未知（dividend_unknown）、沒有保守基準" do
    result = call("200", dividend_annual: "", long_bid: "", long_ask: "")
    expect(result[:flags][:dividend_unknown]).to be(true)
    expect(result[:close][:display][:conservative]).to eq("—")
  end
end

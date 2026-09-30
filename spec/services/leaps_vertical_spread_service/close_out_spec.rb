# frozen_string_literal: true

require "rails_helper"

# tasks/leaps-vertical-fix.md S2：指定日平倉理論損益（Black-Scholes，以報價時兩腳 mid 反推 IV）。
# FX-1：報價日 2026-09-30、到期日 2028-12-15、S₀ 150、r 0.04、q 0、1 口、費用 0。
RSpec.describe LeapsVerticalSpreadService::CloseOut do
  let(:quote_date) { Date.new(2026, 9, 30) }
  let(:expiry)     { Date.new(2028, 12, 15) }
  let(:quoted_at)  { Time.zone.parse("2026-09-30 14:00") }
  let(:long_leg)   { { strike: BigDecimal("100"), bid: BigDecimal("74.95"), ask: BigDecimal("79.05") } }
  let(:short_leg)  { { strike: BigDecimal("240"), bid: BigDecimal("29.70"), ask: BigDecimal("33.70") } }

  def build(long: long_leg, short: short_leg, dividend_annual: BigDecimal("0"), spot_quoted_at: quoted_at)
    described_class.new(
      long: long, short: short, spot: BigDecimal("150"), quote_date: quote_date, expiry: expiry,
      contracts: 1, fee_per_leg: BigDecimal("0"), rate: BigDecimal("0.04"),
      dividend_annual: dividend_annual, spot_quoted_at: spot_quoted_at, option_quoted_at: quoted_at
    )
  end

  def pnl(price, date, iv_shift: 0, close_out: build)
    close_out.call(price: BigDecimal(price.to_s), date: date, iv_shift: BigDecimal(iv_shift.to_s))
  end

  describe "反推 IV" do
    it "在 S = 150、t = 報價日用反推 IV 重新定價，兩腳都等於 mid（±0.01）" do
      close_out = build
      expect(close_out.error).to be_nil
      expect((close_out.leg_value(:long, BigDecimal("150"), quote_date) - 77.00).abs).to be <= 0.01
      expect((close_out.leg_value(:short, BigDecimal("150"), quote_date) - 31.70).abs).to be <= 0.01
    end

    it "LC mid 50（低於理論下限）且沒有 Barchart IV → 回傳錯誤，不輸出 NaN" do
      close_out = build(long: long_leg.merge(bid: BigDecimal("49"), ask: BigDecimal("51")))
      expect(close_out.error).to be_present
      result = pnl(200, quote_date, close_out: close_out)
      expect(result[:error]).to be_present
      expect(result[:pnl]).to be_nil
    end
  end

  describe "t = 到期日（τ = 0，取內在價值，不呼叫 BS）" do
    { 90 => "-4530", "145.30" => "0", 200 => "5470", 300 => "9470" }.each do |price, expected|
      it "S = #{price} → 平倉損益 #{expected}" do
        result = pnl(price, expiry)
        expect((result[:pnl] - BigDecimal(expected)).abs).to be <= BigDecimal("0.005")
        expect(result.values_at(:pnl, :pnl_conservative, :value, :value_conservative).map(&:to_f)).to all(be_finite)
      end
    end

    it "保守平倉：S = 200 → 價值 95.95、損益 +4,660.00" do
      result = pnl(200, expiry)
      expect(result[:value_conservative]).to eq(BigDecimal("95.95"))
      expect((result[:pnl_conservative] - BigDecimal("4660")).abs).to be <= BigDecimal("0.005")
    end
  end

  describe "t = 報價日" do
    it "S = 200：0 < 平倉損益 < 5,470.00" do
      result = pnl(200, quote_date)
      expect(result[:pnl]).to be > 0
      expect(result[:pnl]).to be < BigDecimal("5470")
    end

    it "ΔIV +10 的平倉損益 < ΔIV 0（S 高於兩履約價中點，淨 Vega 為負）" do
      expect(pnl(200, quote_date, iv_shift: 10)[:pnl]).to be < pnl(200, quote_date)[:pnl]
    end
  end

  # 2026-09-30 使用者裁示：與到期損益（Metrics）統一，到期作廢時不扣平倉費。
  describe "費用（每口每腳 0.05）" do
    def with_fee
      described_class.new(
        long: long_leg, short: short_leg, spot: BigDecimal("150"), quote_date: quote_date, expiry: expiry,
        contracts: 1, fee_per_leg: BigDecimal("0.05"), rate: BigDecimal("0.04"), dividend_annual: BigDecimal("0")
      )
    end

    def metrics_payoff(price)
      LeapsVerticalSpreadService::Metrics.dual(long: long_leg, short: short_leg, contracts: 1,
                                               fee_per_leg: BigDecimal("0.05"), target_price: BigDecimal(price.to_s))
    end

    it "到期作廢（S = 90）：只扣開倉費 −4,530.10，與到期損益相同" do
      result = pnl(90, expiry, close_out: with_fee)
      expect(result[:pnl]).to eq(BigDecimal("-4530.10"))
      expect(result[:pnl]).to eq(metrics_payoff(90)[:mid][:payoff][:pnl])
      expect(result[:pnl_conservative]).to eq(metrics_payoff(90)[:conservative][:payoff][:pnl])
    end

    it "到期價內（S = 200）：扣來回費用，與到期損益相同" do
      result = pnl(200, expiry, close_out: with_fee)
      expect(result[:pnl]).to eq(BigDecimal("5469.80"))
      expect(result[:pnl]).to eq(metrics_payoff(200)[:mid][:payoff][:pnl])
    end

    it "到期前平倉（S = 90、報價日）：即使價值很低也要買賣兩腳，照扣來回費用" do
      no_fee = pnl(90, quote_date)[:pnl]
      expect(pnl(90, quote_date, close_out: with_fee)[:pnl]).to eq(no_fee - BigDecimal("0.20"))
    end
  end

  it "平倉日不在報價日～到期日之間 → 回傳錯誤" do
    expect(pnl(200, quote_date - 1)[:error]).to be_present
    expect(pnl(200, expiry + 1)[:error]).to be_present
  end

  describe "旗標" do
    it "兩個 chain 的爬取時間相差 16 分鐘 → stale_quote；14 分鐘 → 否" do
      expect(pnl(200, quote_date, close_out: build(spot_quoted_at: quoted_at - 16.minutes))[:flags][:stale_quote]).to be(true)
      expect(pnl(200, quote_date, close_out: build(spot_quoted_at: quoted_at - 14.minutes))[:flags][:stale_quote]).to be(false)
    end

    it "年股息 1.00、平倉日 = 報價日：S = 250 → early_assignment_risk；S = 200 → 否" do
      close_out = build(dividend_annual: BigDecimal("1.00"))
      expect(pnl(250, quote_date, close_out: close_out)[:flags][:early_assignment_risk]).to be(true)
      expect(pnl(200, quote_date, close_out: close_out)[:flags][:early_assignment_risk]).to be(false)
    end

    it "年股息 0、S = 250 → early_assignment_risk 為否" do
      expect(pnl(250, quote_date)[:flags][:early_assignment_risk]).to be(false)
    end

    it "年股息 1.00 但平倉日距到期不足 90 天 → early_assignment_risk 為否" do
      close_out = build(dividend_annual: BigDecimal("1.00"))
      expect(pnl(250, expiry - 89, close_out: close_out)[:flags][:early_assignment_risk]).to be(false)
    end

    it "沒有股息資料 → q 取 0，dividend_unknown；有資料 → 否" do
      expect(pnl(200, quote_date, close_out: build(dividend_annual: nil))[:flags][:dividend_unknown]).to be(true)
      expect(pnl(200, quote_date)[:flags][:dividend_unknown]).to be(false)
    end
  end

  it "有股息時 IV 以 q = 年股息 ÷ S₀ 反推，仍能還原 mid" do
    close_out = build(dividend_annual: BigDecimal("3"))
    expect((close_out.leg_value(:short, BigDecimal("150"), quote_date) - 31.70).abs).to be <= 0.01
  end
end

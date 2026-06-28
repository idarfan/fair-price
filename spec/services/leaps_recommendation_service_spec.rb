# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeapsRecommendationService do
  def candidate(overrides = {})
    {
      expiration_date:          Date.new(2027, 6, 18),
      dte:                      400,
      strike:                   10.0,
      delta:                    0.82,
      open_interest:            50_000,
      volume:                   300,
      bid:                      3.10,
      ask:                      3.30,
      mid:                      3.20,
      iv:                       0.45,
      vega:                     0.0120,
      itm_probability:          0.85,
      vol_oi_ratio:             0.006,
      underlying_price:         13.08,
      liquidity_tier:           "充足",
      no_recent_volume_warning: false,
      time_value_pct:           0.025,
      bid_ask_spread_pct:       0.062
    }.merge(overrides)
  end

  # ── 近天期 / 遠天期 分組 ─────────────────────────────────────────────────────

  describe "group assignment" do
    let(:near) { candidate(dte: 400) }
    let(:boundary_near) { candidate(dte: 550) }
    let(:far) { candidate(dte: 600) }

    it "assigns DTE 364–550 to near_term and DTE>550 to far_term" do
      result = described_class.new([ near, boundary_near, far ]).call
      expect(result[:near_term][:no_candidates]).to be false
      expect(result[:far_term][:no_candidates]).to be false
    end

    it "returns no_candidates true when no candidates in that group" do
      result = described_class.new([ near ]).call
      expect(result[:far_term][:no_candidates]).to be true
      expect(result[:far_term][:pick]).to be_nil
    end
  end

  # ── 挑選邏輯：流動性優先，再 OI 降序 ────────────────────────────────────────

  describe "pick selection" do
    it "prefers 充足 tier over 普通 regardless of OI" do
      low_oi_good  = candidate(dte: 400, liquidity_tier: "充足", open_interest: 1_000)
      high_oi_mid  = candidate(dte: 400, liquidity_tier: "普通", open_interest: 99_999)
      result = described_class.new([ high_oi_mid, low_oi_good ]).call
      expect(result[:near_term][:pick][:liquidity_tier]).to eq("充足")
    end

    it "breaks ties within same tier by OI descending" do
      low_oi  = candidate(dte: 400, liquidity_tier: "充足", open_interest: 1_000)
      high_oi = candidate(dte: 400, liquidity_tier: "充足", open_interest: 80_000)
      result = described_class.new([ low_oi, high_oi ]).call
      expect(result[:near_term][:pick][:open_interest]).to eq(80_000)
    end

    it "sets runner_up to the second-best candidate" do
      first  = candidate(dte: 400, liquidity_tier: "充足", open_interest: 80_000)
      second = candidate(dte: 400, liquidity_tier: "充足", open_interest: 50_000)
      third  = candidate(dte: 400, liquidity_tier: "普通", open_interest: 99_000)
      result = described_class.new([ third, second, first ]).call
      expect(result[:near_term][:runner_up][:open_interest]).to eq(50_000)
    end
  end

  # ── 近期無成交警示排除邏輯 ────────────────────────────────────────────────────

  describe "no_recent_volume_warning exclusion" do
    it "excludes warned candidates when unwarnced alternatives exist" do
      warned   = candidate(dte: 400, no_recent_volume_warning: true,  open_interest: 99_999)
      clean    = candidate(dte: 400, no_recent_volume_warning: false, open_interest: 1_000)
      result   = described_class.new([ warned, clean ]).call
      expect(result[:near_term][:pick][:no_recent_volume_warning]).to be false
    end

    it "falls back to warned candidates when ALL are warned" do
      all_warned = [
        candidate(dte: 400, no_recent_volume_warning: true, open_interest: 50_000),
        candidate(dte: 400, no_recent_volume_warning: true, open_interest: 30_000)
      ]
      result = described_class.new(all_warned).call
      expect(result[:near_term][:all_warned]).to be true
      expect(result[:near_term][:pick]).not_to be_nil
    end

    it "includes all_warned flag in the group result" do
      clean  = candidate(dte: 400, no_recent_volume_warning: false)
      result = described_class.new([ clean ]).call
      expect(result[:near_term][:all_warned]).to be false
    end
  end

  # ── 理由文字包含必要資訊 ──────────────────────────────────────────────────────

  describe "reason text" do
    let(:pick)     { candidate(dte: 400, open_interest: 80_000, strike: 10.0) }
    let(:runner_up) { candidate(dte: 400, open_interest: 50_000, strike: 11.0) }
    subject(:reason) { described_class.new([ pick, runner_up ]).call[:near_term][:reason] }

    it "includes expiration date and strike" do
      expect(reason).to include(pick[:expiration_date].to_s)
      expect(reason).to include("10.00")
    end

    it "includes OI comparison with runner_up" do
      expect(reason).to include("80,000")
      expect(reason).to include("50,000")
    end

    it "includes time value pct" do
      expect(reason).to include("Time Value")
    end

    it "warns on high bid-ask spread" do
      high_spread = candidate(dte: 400, bid_ask_spread_pct: 0.12)
      reason = described_class.new([ high_spread ]).call[:near_term][:reason]
      expect(reason).to include("Spread 偏高")
    end

    it "includes IV and Vega when present" do
      expect(reason).to include("IV")
      expect(reason).to include("Vega")
    end

    it "includes all_warned warning when all candidates are warned" do
      all_warned = [
        candidate(dte: 400, no_recent_volume_warning: true),
        candidate(dte: 400, no_recent_volume_warning: true)
      ]
      reason = described_class.new(all_warned).call[:near_term][:reason]
      expect(reason).to include("近期無成交")
    end

    it "ends with the standard disclaimer" do
      expect(reason).to include("非投資建議")
    end
  end
end

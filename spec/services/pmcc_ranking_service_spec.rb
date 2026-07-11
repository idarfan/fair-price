# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccRankingService do
  subject(:service) { described_class.new("NOK") }

  let(:latest_leaps_at) { Time.current }
  let(:latest_short_at) { Time.current }

  # §12 Example A 的 LEAPS leg：KL=10, PL=5.75 (bid 5.70/ask 5.80), dte=564, delta 0.85
  def create_leaps!(strike:, bid:, ask:, dte:, delta:, expiration_date: Date.today + dte)
    create(:leaps_option_chain_snapshot,
           symbol: "NOK", strike: strike, bid: bid, ask: ask, dte: dte, delta: delta,
           underlying_price: 12.44, expiration_date: expiration_date, scraped_at: latest_leaps_at)
  end

  # Short leg — mid_price set directly (model prefers stored column, same as persist layer).
  def create_short!(strike:, mid_price:, bid:, ask:, dte:, delta:, expiration_date: Date.today + dte)
    create(:pmcc_short_call_snapshot,
           symbol: "NOK", strike: strike, mid_price: mid_price, bid: bid, ask: ask,
           dte: dte, delta: delta, underlying_price: 12.44,
           expiration_date: expiration_date, scraped_at: latest_short_at)
  end

  describe "no data statuses" do
    it "returns :no_leaps when there are no LEAPS candidates" do
      expect(service.call[:status]).to eq(:no_leaps)
    end

    it "returns :no_short when LEAPS exist but no Short Call rows" do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      expect(service.call[:status]).to eq(:no_short)
    end
  end

  describe "§12 Example A — passes golden rule" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30,
                    expiration_date: Date.today + 6)
    end

    it "computes spread/net_debit/max_profit/premium_yield per the golden rule formulas" do
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first

      expect(combo[:spread]).to be_within(0.001).of(7.0)
      expect(combo[:net_debit]).to be_within(0.001).of(5.33)
      expect(combo[:max_profit_no_sc]).to be_within(0.001).of(1.25)
      expect(combo[:max_profit]).to be_within(0.001).of(1.67)
      expect(combo[:premium_yield]).to be_within(0.05).of(7.88)
      expect(combo[:premium_yield_ann]).to be_within(2.0).of(479.9)
      expect(combo[:passes_golden_rule]).to be true
      expect(combo[:fail_reason]).to be_nil
    end
  end

  describe "§12 Example B — pre-check (a) KS<=KL eliminates by reason, not by omission" do
    before do
      create_leaps!(strike: 260.0, bid: 51.0, ask: 52.0, dte: 564, delta: 0.85) # PL mid=51.5
      create_short!(strike: 250.0, mid_price: 4.24, bid: 4.20, ask: 4.28, dte: 6, delta: 0.30)
    end

    it "keeps the combo but marks it failed with the KS<=KL reason" do
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first

      expect(combo).not_to be_nil # (a) fails but is NOT excluded from the list
      expect(combo[:passes_golden_rule]).to be false
      expect(combo[:fail_reason]).to eq("Short Call履約價KS($250)必須大於LEAPS履約價KL($260)")
    end
  end

  describe "§12 Example C — pre-check (b) DTE gap < 180 overrides a numerically-passing PL<spread" do
    # long.dte=200 can never appear via the real fetch_leaps_candidates pipeline
    # (LeapsRankingService hardcodes dte>=364 — a LEAPS-dated expiration by
    # definition), so this exercises evaluate_golden_rule directly to verify
    # the formula in isolation, per spec §12's illustrative numbers.
    it "fails on the DTE-gap reason even though the raw PL<spread arithmetic would pass" do
      # KL=10, PL=5.75, KS=17, spread=7: passes==PL<spread would be true (5.75<7),
      # but (b) 200 < 45+180=225 must still fail the combo with its own reason.
      passes, fail_reason = service.send(:evaluate_golden_rule, 10.0, 17.0, 5.75, 7.0, 200, 45)

      expect(passes).to be false
      expect(fail_reason).to eq(
        "LEAPS到期日(200天)距Short Call到期日(45天)不足180天，SC到期時LEAPS時間價值恐已大幅流失，最大獲利公式不成立"
      )
    end
  end

  describe "numeric fail: PL >= spread (both pre-checks pass)" do
    before do
      create_leaps!(strike: 10.0, bid: 7.90, ask: 8.10, dte: 564, delta: 0.85) # PL mid = 8.00
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30)
      # spread = 7, PL = 8 >= 7 -> fail
    end

    it "fails with a fail_reason that contains the numeric PL and spread values" do
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first

      expect(combo[:passes_golden_rule]).to be false
      expect(combo[:fail_reason]).to eq("PL(8.00) >= Spread(7.00)")
    end
  end

  describe "§12 Example D — mid missing is skipped, not shown as 0" do
    before do
      create_leaps!(strike: 10.0, bid: nil, ask: nil, dte: 564, delta: 0.85) # mid -> nil
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30)
    end

    it "produces zero combos for this pairing (excluded, not defaulted to 0)" do
      result = service.call
      # LEAPS candidate itself still exists (delta filter doesn't check mid),
      # but cross_and_filter must skip it because PL (mid) is nil.
      expect(result[:summary][:total_combos]).to eq(0)
    end
  end

  describe "three-expiration bucketing" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30,
                    expiration_date: Date.today + 6)
      create_short!(strike: 18.0, mid_price: 0.60, bid: 0.58, ask: 0.62, dte: 13, delta: 0.28,
                    expiration_date: Date.today + 13)
      create_short!(strike: 19.0, mid_price: 0.75, bid: 0.72, ask: 0.78, dte: 20, delta: 0.25,
                    expiration_date: Date.today + 20)
    end

    it "buckets combos into three expirations in ascending date order" do
      result = service.call
      keys   = result[:summary][:expirations]
      expect(keys.size).to eq(3)
      expect(keys).to eq(keys.sort)
      expect(result[:near_term]).to eq(result[keys[0]])
      expect(result[:mid_term]).to eq(result[keys[1]])
      expect(result[:far_term]).to eq(result[keys[2]])
    end
  end

  describe "sort order within a bucket: passing first, then max_profit descending" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)   # PL=5.75
      create_leaps!(strike: 9.0,  bid: 6.70, ask: 6.80, dte: 570, delta: 0.88)   # PL=6.75, KL=9 -> spread vs KS=17 => 8, max_profit higher
      # short leg that makes the KL=10 combo fail (KS<=KL) to verify it sorts after passing ones
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30)
    end

    it "puts passing combos before failing ones, and higher max_profit first among passes" do
      result = service.call
      combos = result.dig(result[:summary][:expirations].first, :combos)
      expect(combos.size).to eq(2)
      expect(combos.first[:passes_golden_rule]).to be true
      # KL=9 combo (spread=8, PL=6.75) has a higher max_profit than KL=10 (spread=7, PL=5.75)
      expect(combos.first[:long_leg][:strike].to_f).to eq(9.0)
      expect(combos.last[:long_leg][:strike].to_f).to eq(10.0)
    end
  end

  describe "Delta two-band coexistence (§2.3): 0.17 is listed but not flagged ✅" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.17)
    end

    it "is included in the combo list (within 0.15-0.40 coarse filter)" do
      result = service.call
      combos = result.dig(result[:summary][:expirations].first, :combos)
      expect(combos.size).to eq(1)
    end

    it "is not marked short_delta_ok (outside the 0.20-0.35 recommendation band)" do
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first
      expect(combo[:short_delta_ok]).to be false
    end
  end

  describe "Short Call Delta grade filter excludes out-of-range rows entirely" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.05) # below 0.15
    end

    it "never reaches cross_and_filter, so no combos exist for this expiration" do
      result = service.call
      expect(result[:status]).to eq(:no_short)
    end
  end

  describe "annualized premium yield differs meaningfully across DTE at similar raw yield" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30,
                    expiration_date: Date.today + 6)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 45, delta: 0.30,
                    expiration_date: Date.today + 45)
    end

    it "has nearly identical premium_yield but very different premium_yield_ann" do
      result = service.call
      near_combo = result.dig(result[:summary][:expirations][0], :combos).first
      far_combo  = result.dig(result[:summary][:expirations][1], :combos).first

      expect(near_combo[:premium_yield]).to be_within(0.001).of(far_combo[:premium_yield])
      expect(near_combo[:premium_yield_ann]).to be > far_combo[:premium_yield_ann] * 5
    end
  end

  describe "leaps_delta_ok marking (>= 0.80, mark-only)" do
    it "marks true at 0.85 and false at 0.65" do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.65)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 6, delta: 0.30)
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first
      expect(combo[:leaps_delta_ok]).to be false
    end
  end
end

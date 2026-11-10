require "rails_helper"

RSpec.describe LeapsRankingService do
  include ActiveSupport::Testing::TimeHelpers

  # All rows in one example share the same scraped_at so maximum() returns them all.
  around { |ex| freeze_time { ex.run } }

  def make(attrs)
    create(:leaps_option_chain_snapshot, attrs)
  end

  # ── Delta filter ─────────────────────────────────────────────────────────────

  describe "delta filter" do
    # extrinsic_value 明確指定正值，避免 factory 的遞增 strike 序列在深 ITM
    # 時算出負外在價值，被新加的「負外在價值排除」規則誤傷（見下方
    # negative extrinsic_value filter 區塊）——這裡要測的是 delta 篩選本身。
    before do
      make(delta: 0.59, extrinsic_value: 0.5)   # just below min — excluded
      make(delta: 0.60, extrinsic_value: 0.5)   # boundary — included
      make(delta: 0.82, extrinsic_value: 0.5)   # mid-range — included
      make(delta: 0.90, extrinsic_value: 0.5)   # no upper bound — included
      make(delta: 0.99, extrinsic_value: 0.5)   # no upper bound — included
    end

    it "includes rows with delta >= 0.60, with no upper bound" do
      results = described_class.new("NOK").call
      deltas  = results.map { |e| e[:delta].to_f }
      expect(deltas).to all(be >= 0.60)
      expect(results.size).to eq(4)
    end
  end

  # ── Liquidity tiers (value-based percentile) ──────────────────────────────────

  describe "liquidity_tiers" do
    context "distinct OI values" do
      before do
        make(delta: 0.80, open_interest: 90_000)
        make(delta: 0.80, open_interest: 50_000)
        make(delta: 0.80, open_interest: 10_000)
      end

      it "assigns 充足 to the top-OI row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 90_000 }
        expect(r[:liquidity_tier]).to eq("充足")
      end

      it "assigns 普通 to the middle row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 50_000 }
        expect(r[:liquidity_tier]).to eq("普通")
      end

      it "assigns 偏低 to the bottom row" do
        r = described_class.new("NOK").call.find { |e| e[:open_interest] == 10_000 }
        expect(r[:liquidity_tier]).to eq("偏低")
      end
    end

    context "two rows with identical OI (tie)" do
      before do
        make(delta: 0.80, open_interest: 80_000)
        make(delta: 0.80, open_interest: 80_000)
        make(delta: 0.80, open_interest: 30_000)
      end

      it "gives tied-OI rows the same liquidity tier" do
        results = described_class.new("NOK").call
        tier_80k = results.select { |e| e[:open_interest] == 80_000 }.map { |e| e[:liquidity_tier] }
        expect(tier_80k.uniq.size).to eq(1), "tied OI rows should share a single tier"
      end
    end
  end

  # ── 成交相對清淡（leaps-thin-trading-flag S1）────────────────────────────────
  #
  # 判定改用同一列 volume ÷ OI 自算（不四捨五入），不再讀 Barchart V&G 頁的
  # vol_oi_ratio（只到小數第 2 位、與 Options 頁不同時間抓、深價內履約價常缺）。
  # 界線公式不變：非 nil 值升冪排序，cutoff = max(floor(n/3), 1)，取 ratios[cutoff-1]。
  # 下列既有案例的輸入從 vol_oi_ratio 改成 volume／OI，故意把 vol_oi_ratio 設成
  # 與自算值相反的排序，證明判定不讀它。

  describe "no_recent_volume_warning" do
    context "with enough candidates (n >= 4)" do
      before do
        make(delta: 0.80, open_interest: 90_000, volume: 3_600, vol_oi_ratio: 0.0)   # 0.04
        make(delta: 0.80, open_interest: 70_000, volume: 2_100, vol_oi_ratio: 0.0)   # 0.03
        make(delta: 0.80, open_interest: 50_000, volume: 1_000, vol_oi_ratio: 0.0)   # 0.02
        make(delta: 0.80, open_interest: 10_000, volume: 20,    vol_oi_ratio: 0.99)  # 0.002
      end

      it "flags candidates at or below the bottom-third computed Vol/OI boundary" do
        results = described_class.new("NOK").call
        flagged = results.select { |e| e[:no_recent_volume_warning] }
        expect(flagged.map { |e| e[:open_interest] }).to contain_exactly(10_000)
      end

      it "does not flag higher computed Vol/OI candidates" do
        results   = described_class.new("NOK").call
        unflagged = results.reject { |e| e[:no_recent_volume_warning] }
        expect(unflagged.size).to eq(3)
      end
    end

    context "with too few candidates (n < 4) — relative threshold meaningless" do
      before do
        make(delta: 0.80, open_interest: 90_000, volume: 90)   # tiny ratio
        make(delta: 0.80, open_interest: 50_000, volume: 100)
        make(delta: 0.80, open_interest: 10_000, volume: 30)
      end

      it "does not flag any candidate (threshold returns nil)" do
        results = described_class.new("NOK").call
        expect(results.none? { |e| e[:no_recent_volume_warning] }).to be true
      end
    end

    context "when OI is 0 (computed Vol/OI is nil) and threshold exists" do
      before do
        make(delta: 0.80, open_interest: 90_000, volume: 3_600)
        make(delta: 0.80, open_interest: 70_000, volume: 2_100)
        make(delta: 0.80, open_interest: 50_000, volume: 1_000)
        make(delta: 0.80, open_interest: 0, volume: 50, vol_oi_ratio: nil)
      end

      it "does not flag the row — insufficient data is not judged" do
        result = described_class.new("NOK").call.find { |e| e[:open_interest].to_i.zero? }
        expect(result[:no_recent_volume_warning]).to be false
        expect(result[:computed_vol_oi]).to be_nil
      end
    end

    context "when OI is nil and threshold is nil (n < 4)" do
      before do
        make(delta: 0.80, open_interest: nil, vol_oi_ratio: nil)
      end

      it "does not flag the row" do
        result = described_class.new("NOK").call.first
        expect(result[:no_recent_volume_warning]).to be false
      end
    end
  end

  describe ".computed_vol_oi" do
    it "returns volume / OI without rounding" do
      expect(described_class.computed_vol_oi(9, 8045)).to be_within(1e-12).of(9.0 / 8045)
    end

    it "returns 0.0 when volume is 0 and OI > 0" do
      expect(described_class.computed_vol_oi(0, 500)).to eq(0.0)
    end

    it "returns nil when OI is 0 or nil, or volume is nil" do
      expect(described_class.computed_vol_oi(50, 0)).to be_nil
      expect(described_class.computed_vol_oi(50, nil)).to be_nil
      expect(described_class.computed_vol_oi(nil, 500)).to be_nil
    end
  end

  # 驗收資料：2026-11-09 23:07 台北（10:07 EST）NVDA 那批的實例。
  describe "acceptance data (7 candidates from the 2026-11-09 NVDA batch)" do
    # 代號 => [volume, OI, DB vol_oi_ratio, 自算值]
    let(:acceptance) do
      {
        "A" => [ 9,    8_045,  0.0,  0.001119 ],
        "B" => [ 96,   226,    0.19, 0.424779 ],
        "C" => [ 5,    10,     0.0,  0.5 ],
        "D" => [ 3583, 15_725, nil,  0.227854 ],
        "E" => [ 0,    500,    nil,  0.0 ],
        "F" => [ 50,   0,      nil,  nil ],
        "G" => [ 724,  14_764, 0.05, 0.049038 ]
      }
    end
    let(:service) { described_class.new("NOK") }
    let(:results) { service.call }
    let(:rows)    { by_code(results, acceptance) }

    def by_code(results, acceptance)
      acceptance.to_h do |code, (vol, oi, _db, _calc)|
        [ code, results.find { |e| e[:volume] == vol && e[:open_interest] == oi } ]
      end
    end


    before do
      acceptance.each_value do |vol, oi, db_ratio, _calc|
        make(delta: 0.80, volume: vol, open_interest: oi, vol_oi_ratio: db_ratio, extrinsic_value: 0.5)
      end
    end

    it "computes Vol/OI to 6 decimal places; F is nil" do
      acceptance.each do |code, (_vol, _oi, _db, calc)|
        actual = rows.fetch(code)[:computed_vol_oi]
        if calc.nil?
          expect(actual).to be_nil, "#{code} should be nil"
        else
          expect(actual.round(6)).to eq(calc), "#{code}: #{actual}"
        end
      end
    end

    it "keeps the stored vol_oi_ratio untouched" do
      expect(rows.fetch("B")[:vol_oi_ratio].to_f).to eq(0.19)
      expect(rows.fetch("D")[:vol_oi_ratio]).to be_nil
    end

    # 界線手算：非 nil 自算值 {E 0.0, A 0.001119, G 0.049038, D 0.227854, B 0.424779, C 0.5}
    # n = 6，cutoff = max(floor(6/3), 1) = 2，界線 = ratios[2 - 1] = 0.001119（A）。
    # 被標記 = 自算值 ≤ 0.001119 → E、A。
    it "flags exactly E and A (computed Vol/OI <= 0.001119)" do
      flagged = rows.select { |_code, e| e[:no_recent_volume_warning] }.keys
      expect(flagged).to contain_exactly("E", "A")
    end

    it "does not flag F (nil), D (old logic flagged NULL) or C (old logic flagged stored 0)" do
      %w[F D C].each do |code|
        expect(rows.fetch(code)[:no_recent_volume_warning]).to be(false), code
      end
    end

    it "all_zero_volume? is false" do
      results
      expect(service.all_zero_volume?).to be false
    end

    it "call still returns an Array" do
      expect(results).to be_an(Array)
    end
  end

  describe "all OI are 0" do
    let(:service) { described_class.new("NOK") }

    before { 5.times { make(delta: 0.80, volume: 10, open_interest: 0) } }

    it "has no threshold, so nothing is flagged" do
      expect(service.call.none? { |e| e[:no_recent_volume_warning] }).to be true
      expect(service.all_zero_volume?).to be false
    end
  end

  describe "all computed Vol/OI are 0 (e.g. before the market opens)" do
    let(:service) { described_class.new("NOK") }

    before do
      [ 8_045, 226, 10, 15_725, 500, 300, 14_764 ].each do |oi|
        make(delta: 0.80, volume: 0, open_interest: oi, extrinsic_value: 0.5)
      end
    end

    it "flags no row and reports all_zero_volume? true" do
      results = service.call
      expect(results.size).to eq(7)
      expect(results.none? { |e| e[:no_recent_volume_warning] }).to be true
      expect(service.all_zero_volume?).to be true
    end
  end

  describe "#all_zero_volume? before #call" do
    it "is false" do
      expect(described_class.new("NOK").all_zero_volume?).to be false
    end
  end

  describe "#all_zero_volume? when there are no candidates" do
    it "is false" do
      service = described_class.new("NOK")
      expect(service.call).to eq([])
      expect(service.all_zero_volume?).to be false
    end
  end

  # ── Sorting ───────────────────────────────────────────────────────────────────

  describe "sort order" do
    # extrinsic_value 明確指定：factory 的 strike 序列在 suite 前段很低（8.5 起），
    # 內在價值大於 Mid 會算出負外在價值而被排除。隨機順序下此案例排在前面就會失敗
    # （seed 17594 重現，BASE 上單跑亦同），與 delta filter 區塊同樣處理。
    before do
      make(delta: 0.80, open_interest: 30_000, dte: 730, extrinsic_value: 0.5)
      make(delta: 0.80, open_interest: 80_000, dte: 400, extrinsic_value: 0.5)  # was 180 (< 364, now excluded)
      make(delta: 0.80, open_interest: 80_000, dte: 540, extrinsic_value: 0.5)
    end

    it "sorts by OI descending, then DTE descending on tie" do
      results = described_class.new("NOK").call
      expect(results.map { |e| [ e[:open_interest], e[:dte] ] }).to eq([
        [ 80_000, 540 ],
        [ 80_000, 400 ],
        [ 30_000, 730 ]
      ])
    end
  end

  # ── time_value_pct ───────────────────────────────────────────────────────────

  describe "time_value_pct" do
    # underlying=13.08, strike=10, mid=3.2
    # intrinsic=3.08, time_value=0.12, time_value_pct=0.12/13.08
    before { make(delta: 0.80, underlying_price: 13.08, strike: 10.0, bid: 3.1, ask: 3.3) }

    it "calculates time_value_pct correctly" do
      result = described_class.new("NOK").call.first
      expect(result[:time_value_pct]).to be_within(0.0001).of(0.12 / 13.08)
    end
  end

  # ── bid_ask_spread_pct ────────────────────────────────────────────────────────

  describe "bid_ask_spread_pct" do
    # mid=3.2, spread=0.2, spread_pct=0.2/3.2=0.0625
    before { make(delta: 0.80, bid: 3.1, ask: 3.3) }

    it "calculates bid_ask_spread_pct correctly" do
      result = described_class.new("NOK").call.first
      expect(result[:bid_ask_spread_pct]).to be_within(0.0001).of(0.2 / 3.2)
    end
  end

  # ── Empty when no candidates ──────────────────────────────────────────────────

  it "returns [] when no rows match the delta filter" do
    make(delta: 0.50)
    expect(described_class.new("NOK").call).to eq([])
  end

  # ── DTE >= 364 hard floor ─────────────────────────────────────────────────────
  #
  # 實測 NOK 時抓到 DTE=5/13/20 的近期合約混進排行（2026-06-28 教訓）。
  # 這組測試確認 DTE<364 的候選真的被排除，DTE>=364 的才進來。

  describe "DTE >= 364 filter" do
    before do
      # Near-term — mirrors the NOK 5/13/20-day garbage data seen in production
      make(delta: 0.82, dte: 5,   expiration_date: Date.today + 5)
      make(delta: 0.82, dte: 13,  expiration_date: Date.today + 13)
      make(delta: 0.82, dte: 20,  expiration_date: Date.today + 20)
      # Boundary: exactly 363 days — still excluded
      make(delta: 0.82, dte: 363, expiration_date: Date.today + 363)
      # Boundary: exactly 364 days — included
      make(delta: 0.82, dte: 364, expiration_date: Date.today + 364)
      # Normal LEAPS DTE — included
      make(delta: 0.82, dte: 400, expiration_date: Date.today + 400)
    end

    it "excludes candidates with DTE < 364" do
      dtes = described_class.new("NOK").call.map { |e| e[:dte] }
      expect(dtes).to all(be >= 364)
    end

    it "includes candidates with DTE >= 364" do
      results = described_class.new("NOK").call
      expect(results.size).to eq(2)   # 364 + 400
    end

    it "explicitly excludes DTE=20 (the NOK near-term case)" do
      results = described_class.new("NOK").call
      expect(results.map { |e| e[:dte] }).not_to include(20)
    end
  end

  # ── 外在價值為負 → 排除（報價品質問題，跟 Delta 篩選無關）───────────────────
  #
  # 外在價值為負代表 Mid < 內在價值，通常是低成交量/寬價差下失真的報價，
  # 這種候選不該被列出（不是「不建議」，是根本不進排行）。extrinsic_value
  # 為 null（bid/ask/spot 缺值）維持既有行為，不受此規則排除。

  describe "negative extrinsic_value filter" do
    before do
      make(delta: 0.80, open_interest: 266, intrinsic_value: 7.34, extrinsic_value: -0.39)  # bad quote — excluded
      make(delta: 0.80, open_interest: 4714, intrinsic_value: 3.0, extrinsic_value: 0.5)     # good quote — included
      make(delta: 0.80, open_interest: 100, bid: nil, ask: nil)                              # extrinsic nil — included
    end

    it "excludes candidates with negative extrinsic_value" do
      results = described_class.new("NOK").call
      expect(results.map { |e| e[:open_interest] }).not_to include(266)
    end

    it "includes candidates with positive extrinsic_value" do
      results = described_class.new("NOK").call
      expect(results.map { |e| e[:open_interest] }).to include(4714)
    end

    it "includes candidates with nil extrinsic_value (missing bid/ask/spot)" do
      results = described_class.new("NOK").call
      expect(results.map { |e| e[:open_interest] }).to include(100)
    end
  end

  # ── Phase H：intrinsic/extrinsic 讀 DB 欄位，排行層不重算 ────────────────────
  describe "Phase H derived columns" do
    describe "reads stored DB values (single formula source)" do
      # 故意存入跟公式算不一樣的值：enrich 若重算會回傳 3.08/0.12，
      # 讀 DB 則回傳 9.99/0.88 —— 用這個差異證明排行層沒有第二份公式。
      before do
        make(delta: 0.80, underlying_price: 13.08, strike: 10.0, bid: 3.1, ask: 3.3,
             intrinsic_value: 9.99, extrinsic_value: 0.88)
      end

      it "returns the stored values, not recomputed ones" do
        result = described_class.new("NOK").call.first
        expect(result[:intrinsic_value].to_f).to eq(9.99)
        expect(result[:extrinsic_value].to_f).to eq(0.88)
      end

      it "time_value_pct uses the stored extrinsic_value" do
        result = described_class.new("NOK").call.first
        expect(result[:time_value_pct]).to be_within(0.0001).of(0.88 / 13.08)
      end
    end

    describe "extrinsic_pct (display layer, denominator = mid)" do
      before { make(delta: 0.80, underlying_price: 13.08, strike: 10.0, bid: 3.1, ask: 3.3) }

      it "= extrinsic_value / mid" do
        result = described_class.new("NOK").call.first
        # factory 依公式補值：mid 3.2, intrinsic 3.08, extrinsic 0.12
        expect(result[:extrinsic_pct]).to be_within(0.0001).of(0.12 / 3.2)
      end
    end

    describe "extrinsic_pct when bid/ask missing" do
      before do
        make(delta: 0.80, underlying_price: 13.08, strike: 10.0, bid: nil, ask: nil)
      end

      it "is nil (rendered as —), not 0% or NaN" do
        result = described_class.new("NOK").call.first
        expect(result[:extrinsic_pct]).to be_nil
        expect(result[:intrinsic_value]).to be_nil
        expect(result[:extrinsic_value]).to be_nil
      end
    end
  end
end

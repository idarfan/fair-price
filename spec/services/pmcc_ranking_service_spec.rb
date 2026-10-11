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

  # 另案 3（leaps-deep-itm-fix.md 結案報告，使用者裁示 2026-10-10）：Short 腳 DTE 19–45
  # 由「標記」改為篩選；Δ 0.20–0.35 維持標記（寬階梯標的會整桶空，見 DELTA_SHORT_* 註解）。
  describe "Short 腳 DTE 19–45 篩選" do
    before { create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85) }

    it "只有 DTE 落在 SHORT_DTE_MIN..SHORT_DTE_MAX 的到期日進桶（含兩端）" do
      [ 13, 18, 19, 45, 46, 55 ].each_with_index do |dte, i|
        create_short!(strike: 17.0 + i, mid_price: 0.42, bid: 0.40, ask: 0.44,
                      dte: dte, delta: 0.30, expiration_date: Date.today + dte)
      end

      result = service.call
      dtes   = result[:summary][:expirations].map { |k| result[k][:short_dte] }
      expect(dtes).to eq([ 19, 45 ])
    end

    it "有 Short Call 資料但全部不在 19–45 天時回 :no_short_in_window，不混成 :no_short" do
      [ 6, 13, 52 ].each do |dte|
        create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44,
                      dte: dte, delta: 0.30, expiration_date: Date.today + dte)
      end

      expect(service.call[:status]).to eq(:no_short_in_window)
    end
  end

  describe "§12 Example A — passes golden rule" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30,
                    expiration_date: Date.today + 20)
    end

    it "computes spread/net_debit/max_profit/premium_yield per the golden rule formulas" do
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first

      expect(combo[:spread]).to be_within(0.001).of(7.0)
      expect(combo[:net_debit]).to be_within(0.001).of(5.33)
      expect(combo[:max_profit_no_sc]).to be_within(0.001).of(1.25)
      expect(combo[:max_profit]).to be_within(0.001).of(1.67)
      expect(combo[:premium_yield]).to be_within(0.05).of(7.88)
      # Short DTE 20（另案 3 起 DTE < 19 不進桶，原範例的 6 天改 20 天）：7.88% / 20 × 365
      expect(combo[:premium_yield_ann]).to be_within(1.0).of(143.9)
      expect(combo[:passes_golden_rule]).to be true
      expect(combo[:fail_reason]).to be_nil
    end
  end

  describe "§12 Example B — pre-check (a) KS<=KL eliminates by reason, not by omission" do
    before do
      create_leaps!(strike: 260.0, bid: 51.0, ask: 52.0, dte: 564, delta: 0.85) # PL mid=51.5
      create_short!(strike: 250.0, mid_price: 4.24, bid: 4.20, ask: 4.28, dte: 20, delta: 0.30)
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
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
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
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
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
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30,
                    expiration_date: Date.today + 20)
      create_short!(strike: 18.0, mid_price: 0.60, bid: 0.58, ask: 0.62, dte: 27, delta: 0.28,
                    expiration_date: Date.today + 27)
      create_short!(strike: 19.0, mid_price: 0.75, bid: 0.72, ask: 0.78, dte: 34, delta: 0.25,
                    expiration_date: Date.today + 34)
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

  # 2026-09-01：到期日上限從 3 提高到 6（scraper 端已用 DTE≤60 篩過）。
  # 另案 3 起只收 DTE 19–45；每日到期的標的在這個區間仍可能超過上限，所以上限保留。
  # （原「45–60 天那段會進桶」的測試隨使用者裁示作廢，改由「Short 腳 DTE 19–45 篩選」涵蓋。）
  describe "multi-expiration bucketing（上限 SC_EXPIRATION_COUNT）" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      (19..30).each_with_index do |dte, i|
        create_short!(strike: 17.0 + i, mid_price: 0.42, bid: 0.40, ask: 0.44,
                      dte: dte, delta: 0.30, expiration_date: Date.today + dte)
      end
    end

    it "最多取 SC_EXPIRATION_COUNT 個到期日，依日期升序" do
      keys = service.call[:summary][:expirations]

      expect(keys.size).to eq(PmccRankingService::SC_EXPIRATION_COUNT)
      expect(keys).to eq(keys.sort)
    end

    it "near/mid/far_term 別名仍對應前三桶" do
      result = service.call
      keys   = result[:summary][:expirations]

      expect(result[:near_term]).to eq(result[keys[0]])
      expect(result[:mid_term]).to eq(result[keys[1]])
      expect(result[:far_term]).to eq(result[keys[2]])
    end
  end

  # 2026-09-03：年化收租率插在 max_profit 之前，所以同一短腳配不同長腳時，
  # 排序看的是「投入多少資本收到這筆租」，不再是 spread 撐出來的理論上限。
  describe "sort order within a bucket: passing first, then annualized premium yield" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85) # PL=5.75, net_debit=5.33
      create_leaps!(strike: 9.0,  bid: 5.95, ask: 6.05, dte: 570, delta: 0.88) # PL=6.00, net_debit=5.58, spread=8 -> max_profit 2.42（高於 KL=10 的 1.67）
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
    end

    it "ranks by annualized premium yield, not by the spread-inflated max_profit" do
      result = service.call
      combos = result.dig(result[:summary][:expirations].first, :combos)

      expect(combos.size).to eq(2)
      expect(combos.all? { |c| c[:passes_golden_rule] }).to be true

      # KL=10 投入較少（net_debit 5.33 vs 5.58）收同一筆 0.42 權利金 -> 年化收租率較高
      expect(combos.first[:long_leg][:strike].to_f).to eq(10.0)
      expect(combos.first[:premium_yield_ann]).to be > combos.last[:premium_yield_ann]
      # 而 max_profit 的高低恰好相反，證明排序不是被 max_profit 主導
      expect(combos.first[:max_profit]).to be < combos.last[:max_profit]
    end
  end

  # 2026-09-03：粗篩放寬到 0.05–0.60 後，max_profit 排序天然偏袒極價外短腳
  # （spread 越大 max_profit 越高），會把真正該賣的 Delta 擠出 TOP_COMBOS_PER_EXPIRATION。
  describe "sort order within a bucket: short_delta_ok outranks max_profit" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85) # PL=5.75
      # 極價外：spread 大 -> max_profit 高，但 Delta 0.07 不在 0.20-0.35 建議區間
      create_short!(strike: 40.0, mid_price: 0.38, bid: 0.36, ask: 0.40, dte: 20, delta: 0.07,
                    expiration_date: Date.today + 20)
      # 建議區間內：spread 小 -> max_profit 低，但 Delta 0.30 合格
      create_short!(strike: 17.0, mid_price: 2.03, bid: 2.00, ask: 2.06, dte: 20, delta: 0.30,
                    expiration_date: Date.today + 20)
    end

    it "ranks the short_delta_ok combo first even though its max_profit is lower" do
      combos = service.call.dig(service.call[:summary][:expirations].first, :combos)

      expect(combos.first[:short_leg][:strike].to_f).to eq(17.0)
      expect(combos.first[:short_delta_ok]).to be true
      expect(combos.last[:short_leg][:strike].to_f).to eq(40.0)
      expect(combos.last[:short_delta_ok]).to be false
      # 確認這不是因為 max_profit 恰好也比較高——極價外那組的 max_profit 確實更大
      expect(combos.last[:max_profit]).to be > combos.first[:max_profit]
    end

    it "still lists the out-of-band combo (標記不淘汰)" do
      combos = service.call.dig(service.call[:summary][:expirations].first, :combos)
      expect(combos.size).to eq(2)
    end
  end

  describe "Delta two-band coexistence (§2.3): 0.17 is listed but not flagged ✅" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.17)
    end

    it "is included in the combo list (within 0.05-0.60 coarse filter)" do
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
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.02) # below 0.05
    end

    it "never reaches cross_and_filter, so no combos exist for this expiration" do
      result = service.call
      expect(result[:status]).to eq(:no_short)
    end
  end

  describe "annualized premium yield differs meaningfully across DTE at similar raw yield" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30,
                    expiration_date: Date.today + 20)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 45, delta: 0.30,
                    expiration_date: Date.today + 45)
    end

    it "has nearly identical premium_yield but very different premium_yield_ann" do
      result = service.call
      near_combo = result.dig(result[:summary][:expirations][0], :combos).first
      far_combo  = result.dig(result[:summary][:expirations][1], :combos).first

      expect(near_combo[:premium_yield]).to be_within(0.001).of(far_combo[:premium_yield])
      # 20 天 vs 45 天：年化約差 45/20 = 2.25 倍（另案 3 起 DTE < 19 不進桶，原本 6 天改 20 天）
      expect(near_combo[:premium_yield_ann]).to be > far_combo[:premium_yield_ann] * 2
    end
  end

  # leaps-deep-itm-fix.md P4：Long Δ ≥ 0.80 由「僅標記」改為篩選條件（原 PMCC v3 §2.3
  # 的 mark-only 規則作廢）。Δ 0.65 的腳不再以 leaps_delta_ok=false 留在組合裡，而是
  # 根本不進組合；進得來的組合 leaps_delta_ok 一律為 true。
  describe "leaps_delta_ok（>= 0.80 由標記改為篩選）" do
    it "Δ 0.65 的腳不進組合" do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.65)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
      expect(service.call[:status]).to eq(:no_qualified_leaps)
    end

    it "Δ 0.85 的腳進組合且標記為 true" do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.85)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
      result = service.call
      combo  = result.dig(result[:summary][:expirations].first, :combos).first
      expect(combo[:leaps_delta_ok]).to be true
    end
  end

  # T3（leaps-deep-itm-fix.md P1）：2026-10-09 INTC 的建倉規範寫 Long Delta ≥ 0.80，
  # 組合表的 Long Δ 卻是 0.671–0.732，說明卡範例也用了 Δ 0.671 的腳。
  # 兩條 LEAPS 腳都能通過黃金法則；Δ 0.70 那條年化收租較高，現況會排在前面。
  describe "T3 — Long 腳 Δ < 0.80 不得通過、不得當說明卡範例" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.70) # PL 5.75 < spread 7
      create_leaps!(strike: 9.0,  bid: 6.20, ask: 6.30, dte: 564, delta: 0.85) # PL 6.25 < spread 8
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
    end

    let(:all_combos) do
      result = service.call
      result[:summary][:expirations].flat_map { |k| result[k][:combos] }
    end

    it "通過清單裡沒有 Long Δ < 0.80 的組合" do
      passing_deltas = all_combos.select { |c| c[:passes_golden_rule] }.map { |c| c[:long_leg][:delta].to_f }

      expect(passing_deltas).not_to be_empty
      expect(passing_deltas).to all(be >= 0.80)
    end

    it "Long 腳在取 OI 前 N 名之前就先篩 Δ ≥ 0.80（高 OI 的低 Δ 腳不能把合格腳擠掉）" do
      # Δ 0.70 的腳 OI 遠高於 Δ 0.85 的腳；TOP_LEAPS_PER_GROUP 截斷前沒先篩的話，
      # 合格腳可能被擠出候選。
      stub_const("PmccRankingService::TOP_LEAPS_PER_GROUP", 1)
      LeapsOptionChainSnapshot.where(symbol: "NOK", strike: 10.0).update_all(open_interest: 999_999)
      LeapsOptionChainSnapshot.where(symbol: "NOK", strike: 9.0).update_all(open_interest: 1)

      long_strikes = all_combos.map { |c| c[:long_leg][:strike].to_f }.uniq
      expect(long_strikes).to eq([ 9.0 ])
    end

    it "說明卡範例選用的 Long 腳 Δ ≥ 0.80" do
      host = Class.new do
        include LeapsRecommendations::PmccEducation
        def initialize(ranking) = @pmcc_ranking = ranking
      end
      pick = host.new(service.call).pmcc_edu_pick

      expect(pick[:long_leg][:delta].to_f).to be >= 0.80
    end
  end

  describe "T3b — 沒有任何 Δ ≥ 0.80 的 Long 腳" do
    before do
      create_leaps!(strike: 10.0, bid: 5.70, ask: 5.80, dte: 564, delta: 0.70)
      create_short!(strike: 17.0, mid_price: 0.42, bid: 0.40, ask: 0.44, dte: 20, delta: 0.30)
    end

    it "回傳 :no_qualified_leaps，不回空表也不混成 :no_leaps" do
      expect(service.call[:status]).to eq(:no_qualified_leaps)
    end
  end

  # 審查 r1 問題 1：爬蟲只抓 Short DTE 區間內的到期日，兩邊的數字必須同源；
  # 只改一邊的話，不是抓了用不到，就是該列的到期日沒抓到。
  describe "Short DTE 區間與 pmcc_short_call_scraper.py 一致" do
    let(:scraper_src) { Rails.root.join("lib/barchart_scrapers/pmcc_short_call_scraper.py").read }

    def py_const(src, name)
      src[/^#{name}\s*=\s*(\d+)/, 1]&.to_i
    end

    it "MIN_SHORT_DTE／MAX_SHORT_DTE 等於 SHORT_DTE_MIN／SHORT_DTE_MAX" do
      expect(py_const(scraper_src, "MIN_SHORT_DTE")).to eq(described_class::SHORT_DTE_MIN)
      expect(py_const(scraper_src, "MAX_SHORT_DTE")).to eq(described_class::SHORT_DTE_MAX)
    end
  end
end

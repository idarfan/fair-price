# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment.md P3：「名詞與公式」測試向量逐一對應，加上狀態、期間、PMCC 合併。
RSpec.describe LeapsIvEnvironmentService do
  let(:sym)   { "TSM" }
  let(:today) { Date.new(2026, 11, 5) }
  let(:now)   { Time.zone.parse("2026-11-06 05:20:00") }

  def snapshot!(date, cm540: nil, spot: 355.0, captured_at: now, **attrs)
    LeapsIvSnapshot.create!(symbol: sym, as_of_date: date, spot: spot, cm540_atm_iv: cm540, source: "adhoc",
                            captured_at: captured_at, source_url: "https://www.barchart.com/stocks/quotes/TSM/options", **attrs)
  end

  # 每個到期日放兩檔履約價（夾住 spot），IV 相同 → 該到期日 ATM IV＝iv
  def surface!(date, dte_iv, strikes: [ 350.0, 360.0 ])
    dte_iv.each do |dte, iv|
      strikes.each do |k|
        LeapsIvSurfacePoint.create!(symbol: sym, as_of_date: date, expiration: date + dte, dte: dte, strike: k,
                                    moneyness: (k / 355.0).round(4), call_iv: iv, captured_at: now)
      end
    end
  end

  # 歷史快照：當日之前每天一筆，cm540 依序取 values
  def history!(values)
    values.each_with_index { |v, i| snapshot!(today - (i + 1), cm540: v) }
  end

  describe "名詞與公式的測試向量" do
    it "內插：T1=0.5 σ1=0.40、T2=1.5 σ2=0.44，T=1.0 → 0.4304（總變異數內插）" do
      expect(described_class.constant_maturity_iv([ [ 0.5, 0.40 ], [ 1.5, 0.44 ] ], 1.0)).to be_within(0.0001).of(0.4304)
    end

    it "Rank／Percentile：歷史 [0.30, 0.50, 0.40]、現值 0.45 → Rank 75.0、Percentile 66.7（min_history: 1）" do
      snapshot!(today)
      surface!(today, { 442 => 0.45, 589 => 0.45 })
      history!([ 0.30, 0.50, 0.40 ])

      result = described_class.new(min_history: 1).call(symbol: sym)
      expect(result[:cm540]).to be_within(1e-9).of(0.45)
      expect(result[:rank]).to be_within(0.05).of(75.0)
      expect(result[:percentile]).to be_within(0.05).of(66.7)
      expect(result[:history_count]).to eq(3)
    end

    it "相等值：歷史 [0.40, 0.40, 0.50]、現值 0.40 → Percentile 0.0、Rank 0.0" do
      expect(described_class.iv_percentile([ 0.40, 0.40, 0.50 ], 0.40)).to eq(0.0)
      expect(described_class.iv_rank([ 0.40, 0.40, 0.50 ], 0.40)).to eq(0.0)
    end

    it "最高等於最低：歷史 [0.40, 0.40]、現值 0.40 → Rank nil" do
      expect(described_class.iv_rank([ 0.40, 0.40 ], 0.40)).to be_nil
    end

    it "ATM 內插：S=353.10，K=350 IV 0.425、K=360 IV 0.424 → 0.42469" do
      expect(described_class.atm_iv([ [ 350.0, 0.425 ], [ 360.0, 0.424 ] ], 353.10)).to be_within(0.00001).of(0.42469)
    end
  end

  describe "#call 狀態與期間" do
    before do
      snapshot!(today)
      surface!(today, { 442 => 0.45, 589 => 0.45 })
    end

    it "歷史 19 筆 → :accumulating，Rank／Percentile 為 nil" do
      history!(Array.new(19) { |i| 0.30 + (i * 0.01) })

      result = described_class.new.call(symbol: sym)
      expect(result).to include(status: :accumulating, history_count: 19, rank: nil, percentile: nil)
      expect(result[:cm540]).to be_within(1e-9).of(0.45)
    end

    it "歷史 20 筆 → :ok，算出 Rank／Percentile" do
      history!(Array.new(20) { |i| 0.30 + (i * 0.01) })

      result = described_class.new.call(symbol: sym)
      expect(result).to include(status: :ok, history_count: 20)
      expect(result[:rank]).to be_within(1e-9).of((0.45 - 0.30) / (0.49 - 0.30) * 100)
      expect(result[:percentile]).to be_within(1e-9).of(75.0) # 0.30–0.44 共 15 筆小於 0.45
    end

    it "365 天前的快照不計入期間（364 天前的要計入）" do
      snapshot!(today - 364, cm540: 0.30)
      snapshot!(today - 365, cm540: 0.10)

      result = described_class.new(min_history: 1).call(symbol: sym)
      expect(result[:history_count]).to eq(1)
      expect(result[:rank]).to be_nil # 只剩一筆 → 最高＝最低
    end

    it "當日與之後的快照、cm540 為 nil 的快照都不算歷史" do
      snapshot!(today - 1, cm540: nil)
      snapshot!(today + 1, cm540: 0.50)

      expect(described_class.new(min_history: 1).call(symbol: sym, as_of_date: today)[:history_count]).to eq(0)
    end

    it "期間最多取最近 252 筆" do
      history!(Array.new(260) { |i| 0.30 + ((i % 7) * 0.01) })

      expect(described_class.new.call(symbol: sym)[:history_count]).to eq(252)
    end
  end

  describe "CM540 與 ATM IV 的邊界" do
    it "540 天無法被夾住 → cm540 nil，Rank／Percentile 也 nil（不外插）" do
      snapshot!(today)
      surface!(today, { 407 => 0.42, 500 => 0.43 })
      history!(Array.new(20) { 0.40 })

      result = described_class.new.call(symbol: sym)
      expect(result).to include(cm540: nil, rank: nil, percentile: nil)
    end

    it "夾住 540 的到期日算不出 ATM IV（現價不在兩檔之間）→ cm540 nil" do
      snapshot!(today, spot: 380.0)
      surface!(today, { 442 => 0.45, 589 => 0.45 })

      result = described_class.new.call(symbol: sym)
      expect(result[:term_structure].map { |p| p[:atm_iv] }).to eq([ nil, nil ])
      expect(result[:cm540]).to be_nil
    end

    it "現價恰等於某履約價 → ATM IV＝該檔 IV" do
      snapshot!(today, spot: 350.0)
      LeapsIvSurfacePoint.create!(symbol: sym, as_of_date: today, expiration: today + 442, dte: 442, strike: 350,
                                  moneyness: 1.0, call_iv: 0.4246, captured_at: now)
      LeapsIvSurfacePoint.create!(symbol: sym, as_of_date: today, expiration: today + 442, dte: 442, strike: 360,
                                  moneyness: 1.0286, call_iv: 0.4240, captured_at: now)

      expect(described_class.new.call(symbol: sym)[:term_structure].first[:atm_iv]).to eq(0.4246)
    end
  end

  it "無任何資料 → :no_data" do
    expect(described_class.new.call(symbol: sym)).to include(status: :no_data, cm540: nil, term_structure: [],
                                                             surface: [], barchart: nil)
  end

  describe "#persist!" do
    it "把 cm540 寫回快照（寫入 cm540 的唯一入口）" do
      snapshot!(today)
      surface!(today, { 442 => 0.40, 589 => 0.44 })

      value = described_class.new.persist!(symbol: sym, as_of_date: today)

      t1 = 442 / 365.0
      t2 = 589 / 365.0
      t  = 540 / 365.0
      expected = Math.sqrt(((0.40**2 * t1) + ((t - t1) / (t2 - t1)) * ((0.44**2 * t2) - (0.40**2 * t1))) / t)
      expect(value).to be_within(1e-9).of(expected)
      expect(LeapsIvSnapshot.find_by(symbol: sym, as_of_date: today).cm540_atm_iv).to eq(BigDecimal(expected.round(5).to_s))
    end
  end

  describe "PMCC 短天期合併（讀取時，P2 r2 質詢 2）" do
    def pmcc!(dte:, strike:, iv:, scraped_at:)
      PmccShortCallSnapshot.create!(symbol: sym, expiration_date: today + dte, dte: dte, strike: strike, option_type: "Call",
                                    iv: iv, scraped_at: scraped_at)
    end

    before do
      snapshot!(today)
      surface!(today, { 442 => 0.45, 589 => 0.45 })
    end

    it "同一次抓取（scraped_at 與快照 captured_at 相差 1 小時內）的短天期點併進 surface 與 term_structure" do
      pmcc!(dte: 22, strike: 350, iv: 0.60, scraped_at: now + 2.minutes)
      pmcc!(dte: 22, strike: 360, iv: 0.58, scraped_at: now + 2.minutes)
      pmcc!(dte: 22, strike: 500, iv: 0.70, scraped_at: now + 2.minutes) # moneyness 1.41，曲面範圍外

      result = described_class.new.call(symbol: sym)
      expect(result[:term_structure].map { |p| p[:dte] }).to eq([ 22, 442, 589 ])
      expect(result[:term_structure].first[:atm_iv]).to be_within(1e-9).of(0.59)
      expect(result[:surface].select { |p| p[:dte] == 22 }.map { |p| p[:moneyness] }).to eq([ 0.9859, 1.0141 ])
      expect(result[:cm540]).to be_within(1e-9).of(0.45) # 短天期不影響 540 天的內插
    end

    it "不是同一次抓取的 PMCC 資料（相差超過 1 小時）不併入" do
      pmcc!(dte: 22, strike: 350, iv: 0.60, scraped_at: now - 3.hours)
      pmcc!(dte: 22, strike: 360, iv: 0.58, scraped_at: now - 3.hours)

      result = described_class.new.call(symbol: sym)
      expect(result[:term_structure].map { |p| p[:dte] }).to eq([ 442, 589 ])
      expect(result[:surface].map { |p| p[:dte] }.uniq).to eq([ 442, 589 ])
    end
  end

  describe "barchart 區塊" do
    def bc!(date, iv_rank:)
      BarchartIvHistory.create!(symbol: sym, trade_date: date, imp_vol: 0.5, iv_rank: iv_rank, iv_pctl: 90.0,
                                last_price: 350, captured_at: now,
                                source_url: "https://www.barchart.com/stocks/quotes/TSM/options-history")
    end

    it "取 trade_date ≤ as_of_date 的最新一列（頁面值，不重算）、hv 讀快照、history 由舊到新" do
      snapshot!(today, bc_hv: 0.4666, bc_hv_label: "HV 30 天")
      bc!(today - 1, iv_rank: 25.58)
      bc!(today, iv_rank: 82.44)
      bc!(today + 1, iv_rank: 10.00) # 之後的日期不採用

      bc = described_class.new.call(symbol: sym)[:barchart]
      expect(bc).to include(trade_date: today, iv_rank: 82.44, iv_pctl: 90.0, hv: 0.4666, hv_label: "HV 30 天")
      expect(bc[:history].map { |h| h[:trade_date] }).to eq([ today - 1, today ])
    end

    it "history 最多 252 列" do
      snapshot!(today)
      300.times { |i| bc!(today - i, iv_rank: 50) }

      expect(described_class.new.call(symbol: sym)[:barchart][:history].size).to eq(252)
    end
  end
end

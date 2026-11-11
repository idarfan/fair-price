# frozen_string_literal: true

require "rails_helper"

# leaps-best-value.md S1：驗收基準資料（2026-11-09 NVDA，S = 186.64）。
RSpec.describe LeapsBestValueService do
  let(:spot) { 186.64 }

  # 到期, DTE, K, Delta, Bid, Ask, OI, Vol, 無成交
  let(:baseline) do
    [
    [ "2028-01-21", 440, 120, 0.8710, 79.10, 80.50,  2069,  18, true  ],
    [ "2028-01-21", 440, 125, 0.8569, 75.40, 76.85,   634,  10, false ],
    [ "2028-01-21", 440, 130, 0.8417, 72.00, 73.20,  2264, 160, false ],
    [ "2028-01-21", 440, 140, 0.8092, 65.40, 66.25,  4163, 191, false ],
    [ "2028-01-21", 440, 180, 0.6562, 42.00, 42.50, 14764, 724, false ],
    [ "2027-12-17", 405, 130, 0.8453, 70.65, 72.10,  7565,  22, true  ],
    [ "2028-06-16", 587, 140, 0.8042, 69.60, 71.25,   499,  13, false ],
    [ "2028-12-15", 769, 120, 0.8540, 87.40, 89.65,  6168,   6, true  ],
    [ "2028-12-15", 769, 140, 0.8047, 74.60, 76.15,  4898,  60, true  ],
    [ "2029-01-19", 804, 120, 0.8530, 88.25, 90.50,   221,   5, false ],
    [ "2029-01-19", 804, 140, 0.8045, 75.80, 77.00,   502, 107, false ]
    ]
  end
  let(:candidates) { baseline.map { |row| candidate(*row) } }
  let(:config) { LeapsBestValueConfig.load }

  # LeapsRankingService#call 產出的候選 hash 形狀；「近期無成交」以既有欄位
  # :no_recent_volume_warning 注入（S0 質詢 2：讀候選 hash，不改既有判定方法）。
  def candidate(exp, dte, strike, delta, bid, ask, oi, vol, no_trade)
    {
      expiration_date:          Date.parse(exp),
      dte:                      dte,
      strike:                   BigDecimal(strike.to_s),
      delta:                    BigDecimal(delta.to_s),
      bid:                      BigDecimal(bid.to_s),
      ask:                      BigDecimal(ask.to_s),
      open_interest:            oi,
      volume:                   vol,
      underlying_price:         BigDecimal(spot.to_s),
      no_recent_volume_warning: no_trade
    }
  end


  def label(pick)
    [ pick[:expiration_date].iso8601, pick[:strike].to_i ]
  end

  def graded(service, exp, strike)
    service.graded_candidates.find { |c| c[:expiration_date] == Date.parse(exp) && c[:strike].to_i == strike }
  end

  describe "config/leaps_best_value.yml" do
    it "讀到使用者指定的預設門檻" do
      expect(config).to include(
        "delta_min" => 0.80, "delta_max" => 0.92, "spread_pct_max" => 3.0,
        "oi_min" => 1000, "volume_min" => 50, "exclude_no_recent_trade" => false, "iv_rank_warn" => 70
      )
    end

    it "缺少門檻鍵時直接報錯，不默默用預設值" do
      expect { described_class.new(candidates, config: config.except("oi_min")) }
        .to raise_error(KeyError, /oi_min/)
    end
  end

  describe ".metrics（S1 計算公式）" do
    it "以 ask 計外在價值，算出年化時間成本、損益兩平、Spread %" do
      m = described_class.metrics(candidate(*baseline[2]))
      expect(m[:annual_cost_pct].round(2)).to eq 7.36
      expect(m[:breakeven_pct].round(2)).to eq((((130 + 73.20) / spot * 100) - 100).round(2))
      expect(m[:spread_pct].round(2)).to eq((1.20 / 72.60 * 100).round(2))
    end

    it "價外時內在價值為 0" do
      m = described_class.metrics(candidate("2028-01-21", 440, 200, 0.5, 30.0, 31.0, 1000, 100, false))
      expect(m[:annual_cost_pct].round(4)).to eq((31.0 / spot * 365 / 440 * 100).round(4))
    end

    it "ask、現價或 DTE 缺值時回傳 nil，不算成 0" do
      expect(described_class.metrics(candidate(*baseline[2]).merge(ask: nil))).to be_nil
      expect(described_class.metrics(candidate(*baseline[2]).merge(underlying_price: nil))).to be_nil
      expect(described_class.metrics(candidate(*baseline[2]).merge(dte: 0))).to be_nil
    end
  end

  describe "預設設定" do
    subject(:service) { described_class.new(candidates, config: config) }

    let(:result) { service.call }

    it "近天期主推 2028-01-21 $130（7.36）、次選 $140（8.72）" do
      near = result[:near_term]
      expect(label(near[:pick])).to eq [ "2028-01-21", 130 ]
      expect(near[:pick][:annual_cost_pct].round(2)).to eq 7.36
      expect(near[:pick][:liquidity_grade]).to eq "A"
      expect(label(near[:runner_up])).to eq [ "2028-01-21", 140 ]
      expect(near[:runner_up][:annual_cost_pct].round(2)).to eq 8.72
      expect(near[:runner_up][:liquidity_grade]).to eq "A"
    end

    it "遠天期主推 2028-12-15 $140（A 級，7.50）、次選 2029-01-19 $120（B 級，5.80）" do
      far = result[:far_term]
      expect(label(far[:pick])).to eq [ "2028-12-15", 140 ]
      expect(far[:pick][:annual_cost_pct].round(2)).to eq 7.50
      expect(far[:pick][:liquidity_grade]).to eq "A"
      expect(label(far[:runner_up])).to eq [ "2029-01-19", 120 ]
      expect(far[:runner_up][:annual_cost_pct].round(2)).to eq 5.80
      expect(far[:runner_up][:liquidity_grade]).to eq "B"
    end

    it "回傳每筆含規格列出的欄位" do
      expect(result[:near_term][:pick].keys).to include(
        :expiration_date, :dte, :strike, :delta, :ask, :annual_cost_pct, :breakeven_pct,
        :spread_pct, :open_interest, :volume, :liquidity_grade
      )
    end

    it "$180（delta 0.6562）被 delta 篩掉" do
      expect(graded(service, "2028-01-21", 180)[:liquidity_grade]).to be_nil
    end

    it "2028-01-21 $125 被 OI（634）篩出 A 級" do
      expect(graded(service, "2028-01-21", 125)[:liquidity_grade]).to eq "B"
    end

    it "2028-12-15 $140 雖標無成交仍入選 A 級" do
      row = graded(service, "2028-12-15", 140)
      expect(row[:no_recent_volume_warning]).to be true
      expect(row[:liquidity_grade]).to eq "A"
    end

    it "2028-12-15 $120 被成交量（6）篩出 A 級" do
      expect(graded(service, "2028-12-15", 120)[:liquidity_grade]).to eq "B"
    end

    it "2029-01-19 $120、$140 與 2028-06-16 $140 被 OI 篩出 A 級" do
      expect(graded(service, "2029-01-19", 120)[:liquidity_grade]).to eq "B"
      expect(graded(service, "2029-01-19", 140)[:liquidity_grade]).to eq "B"
      expect(graded(service, "2028-06-16", 140)[:liquidity_grade]).to eq "B"
    end
  end

  describe "流動性等級補位" do
    it "Spread 超過上限只剩 Delta 區間時為 C 級，仍有主推" do
      wide = candidate("2028-01-21", 440, 130, 0.84, 60.0, 73.20, 5000, 500, false)
      near = described_class.new([ wide ], config: config).call[:near_term]
      expect(near[:pick][:liquidity_grade]).to eq "C"
      expect(near[:runner_up]).to be_nil
    end

    it "bid 為 0 是三級共同硬條件：A／B／C 都不會選到，就算區間因此變成 nil" do
      zero_bid = candidate("2028-01-21", 440, 130, 0.84, 0.0, 73.20, 5000, 500, false)
      service  = described_class.new([ zero_bid ], config: config.merge("spread_pct_max" => 1_000))
      expect(service.graded_candidates.first[:liquidity_grade]).to be_nil
      expect(service.call[:near_term]).to be_nil
    end

    it "bid 為 0 的合約不會從 C 級補位，主推改由其他合約擔任" do
      zero_bid = candidate("2028-01-21", 440, 120, 0.87, 0.0, 70.00, 9000, 900, false)
      wide     = candidate("2028-01-21", 440, 130, 0.84, 60.0, 73.20, 5000, 500, false)
      near = described_class.new([ zero_bid, wide ], config: config).call[:near_term]
      expect(label(near[:pick])).to eq [ "2028-01-21", 130 ]
      expect(near[:runner_up]).to be_nil
    end

    it "Delta 區間內沒有任何合約時該天期回傳 nil" do
      only_shallow = [ candidate(*baseline[4]) ]
      result = described_class.new(only_shallow, config: config).call
      expect(result[:near_term]).to be_nil
      expect(result[:far_term]).to be_nil
    end
  end

  describe "exclude_no_recent_trade: true" do
    let(:service) { described_class.new(candidates, config: config.merge("exclude_no_recent_trade" => true)) }

    it "無成交合約不出現在任何等級（三級共同硬條件）" do
      no_trade = service.graded_candidates.select { |c| c[:no_recent_volume_warning] }
      expect(no_trade.size).to eq 4
      expect(no_trade.map { |c| c[:liquidity_grade] }).to all(be_nil)
    end

    it "主推與次選都不是無成交合約" do
      result = service.call
      expect(label(result[:near_term][:pick])).to eq [ "2028-01-21", 130 ]
      expect(label(result[:near_term][:runner_up])).to eq [ "2028-01-21", 140 ]
      expect(label(result[:far_term][:pick])).to eq [ "2029-01-19", 120 ]
      expect(label(result[:far_term][:runner_up])).to eq [ "2029-01-19", 140 ]
    end

    it "區間內全是無成交合約時回傳 nil" do
      only_no_trade = baseline.select { |row| row[8] && row[1] > 550 }.map { |row| candidate(*row) }
      result = described_class.new(only_no_trade, config: config.merge("exclude_no_recent_trade" => true)).call
      expect(result[:far_term]).to be_nil
    end
  end

  describe "覆寫設定 oi_min: 500, volume_min: 10" do
    let(:result) do
      described_class.new(candidates, config: config.merge("oi_min" => 500, "volume_min" => 10)).call
    end

    it "近天期主推 2028-01-21 $120（6.16，無成交仍入選）、次選 $125（6.76）" do
      near = result[:near_term]
      expect(label(near[:pick])).to eq [ "2028-01-21", 120 ]
      expect(near[:pick][:annual_cost_pct].round(2)).to eq 6.16
      expect(near[:pick][:no_recent_volume_warning]).to be true
      expect(label(near[:runner_up])).to eq [ "2028-01-21", 125 ]
      expect(near[:runner_up][:annual_cost_pct].round(2)).to eq 6.76
    end

    it "遠天期主推 2029-01-19 $140（7.38）、次選 2028-12-15 $140（7.50）" do
      far = result[:far_term]
      expect(label(far[:pick])).to eq [ "2029-01-19", 140 ]
      expect(far[:pick][:annual_cost_pct].round(2)).to eq 7.38
      expect(label(far[:runner_up])).to eq [ "2028-12-15", 140 ]
      expect(far[:runner_up][:annual_cost_pct].round(2)).to eq 7.50
    end
  end

  describe "天期分區沿用 LeapsRecommendationService 常數" do
    it "DTE 550 歸近天期、551 歸遠天期、363 不列入" do
      rows = [ 363, 550, 551 ].map { |dte| candidate("2028-01-21", dte, 130, 0.84, 72.0, 73.2, 5000, 500, false) }
      result = described_class.new(rows, config: config).call
      expect(result[:near_term][:pick][:dte]).to eq 550
      expect(result[:near_term][:runner_up]).to be_nil
      expect(result[:far_term][:pick][:dte]).to eq 551
    end
  end
end

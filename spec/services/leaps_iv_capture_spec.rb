# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P2：原始資料寫入。數值取自 2026-11-06 TSM 實測（P0 偵察）。
RSpec.describe LeapsIvCapture do
  subject(:capture) { described_class.new("tsm", source: "adhoc") }

  let(:as_of) { Date.new(2026, 11, 5) }

  describe ".as_of_date" do
    it "頁面報價日期 MM/DD/YY 換成日期" do
      expect(described_class.as_of_date("11/05/26")).to eq(as_of)
    end

    it "讀不到報價日期就失敗，不用系統時間代替" do
      expect { described_class.as_of_date(nil) }.to raise_error(LeapsIvCapture::CaptureError, /報價日期/)
      expect { described_class.as_of_date("19:59 ET") }.to raise_error(LeapsIvCapture::CaptureError, /無法辨識/)
    end
  end

  describe ".regular_session?（盤中不寫 IV 資料）" do
    def et(str) = Time.find_zone("Eastern Time (US & Canada)").parse(str)

    it "美東週一～五 09:30–16:00 為盤中（含兩端），盤前、盤後、週末不是" do
      expect(described_class.regular_session?(et("2026-11-06 09:29"))).to be false
      expect(described_class.regular_session?(et("2026-11-06 09:30"))).to be true
      expect(described_class.regular_session?(et("2026-11-06 16:00"))).to be true
      expect(described_class.regular_session?(et("2026-11-06 16:01"))).to be false
      expect(described_class.regular_session?(et("2026-11-07 11:00"))).to be false # 週六
    end

    it "以美東時間判斷：台北 22:30（冬令）＝美東 09:30 開盤；P4 排程台北 14:00 不在盤中" do
      taipei = Time.find_zone("Asia/Taipei")
      expect(described_class.regular_session?(taipei.parse("2026-11-06 22:30"))).to be true
      expect(described_class.regular_session?(taipei.parse("2026-11-07 14:00"))).to be false
    end
  end

  it "source 只接受 scheduled／adhoc" do
    expect { described_class.new("TSM", source: "manual") }.to raise_error(ArgumentError)
  end

  describe "#persist_leaps_chain" do
    let(:leaps_data) do
      {
        "underlying_price" => 353.1, "quote_date_text" => "11/05/26",
        "source_url" => "https://www.barchart.com/stocks/quotes/TSM/options",
        "iv_surface" => [
          # moneyness = K / 353.1：200 → 0.5664（範圍外）、220 → 0.6231、350 → 0.9912、
          # 440 → 1.2461、450 → 1.2744（範圍外）
          { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 200, "iv" => 0.47, "delta" => 0.85 },
          { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 220, "iv" => 0.46, "delta" => 0.82 },
          { "expiration_date" => "2028-01-21", "dte" => 442, "strike" => 350, "iv" => 0.4246, "delta" => 0.625828 },
          { "expiration_date" => "2028-06-16", "dte" => 589, "strike" => 440, "iv" => 0.43, "delta" => 0.41 },
          { "expiration_date" => "2028-06-16", "dte" => 589, "strike" => 450, "iv" => 0.43, "delta" => 0.39 }
        ]
      }
    end

    it "只寫入 moneyness 0.60–1.25 的點，moneyness＝K／S，含篩 Delta 前的價外履約價" do
      expect(capture.persist_leaps_chain(leaps_data)).to eq(3)

      points = LeapsIvSurfacePoint.where(symbol: "TSM", as_of_date: as_of).order(:expiration, :strike)
      expect(points.map { |p| [ p.strike.to_f, p.moneyness.to_f ] }).to eq([ [ 220.0, 0.6231 ], [ 350.0, 0.9912 ], [ 440.0, 1.2461 ] ])
      expect(points.find_by(strike: 350)).to have_attributes(call_iv: BigDecimal("0.4246"), delta: BigDecimal("0.6258"), dte: 442)
    end

    it "快照寫入現價、source、來源網址，as_of_date 取頁面報價日期" do
      capture.persist_leaps_chain(leaps_data)

      expect(LeapsIvSnapshot.find_by(symbol: "TSM", as_of_date: as_of))
        .to have_attributes(spot: BigDecimal("353.1"), source: "adhoc",
                            source_url: "https://www.barchart.com/stocks/quotes/TSM/options", cm540_atm_iv: nil)
    end

    it "同一天再寫一次，後寫覆蓋先寫（盤中 adhoc → 收盤後 scheduled）" do
      capture.persist_leaps_chain(leaps_data)
      later = leaps_data.merge("underlying_price" => 360.55)
      later["iv_surface"] = [ leaps_data["iv_surface"][2].merge("iv" => 0.43) ]
      described_class.new("TSM", source: "scheduled").persist_leaps_chain(later)

      expect(LeapsIvSnapshot.where(symbol: "TSM").count).to eq(1)
      expect(LeapsIvSnapshot.find_by(symbol: "TSM")).to have_attributes(source: "scheduled", spot: BigDecimal("360.55"))
      expect(LeapsIvSurfacePoint.find_by(symbol: "TSM", strike: 350).call_iv).to eq(BigDecimal("0.43"))
    end

    it "讀不到報價日期時整筆不寫" do
      expect { capture.persist_leaps_chain(leaps_data.merge("quote_date_text" => nil)) }
        .to raise_error(LeapsIvCapture::CaptureError)
      expect(LeapsIvSnapshot.count + LeapsIvSurfacePoint.count).to eq(0)
    end

    it "曲面沒有任何範圍內的點時失敗（訊息帶上爬蟲回報的原因）" do
      data = leaps_data.merge("iv_surface" => [], "iv_surface_error" => "沒有 DTE ≥ 364 的到期日")
      expect { capture.persist_leaps_chain(data) }.to raise_error(LeapsIvCapture::CaptureError, /364/)
    end
  end

  describe "#persist_barchart_history" do
    # 2026-11-05 列為 P0 偵察讀到的 bc-data-grid 原始值
    let(:raw_row) do
      { "date" => "2026-11-05", "weightedImpliedVolatility" => 0.51924588452348,
        "impliedVolatilityRank1y" => 82.442713996768, "impliedVolatilityPercentile1y" => 0.92430278884462,
        "putCallVolumeRatio" => 0.91820624020098, "totalVolume" => 418_426,
        "putCallOpenInterestRatio" => 0.98123225700671, "totalOpenInterest" => 1_921_298,
        "historicalLastPrice" => 353.1 }
    end
    let(:history_data) do
      { "rows" => [ raw_row ], "quote_date_text" => "11/05/26", "hv_pct" => 46.66,
        "source_url" => "https://www.barchart.com/stocks/quotes/TSM/options-history",
        "hv_source_url" => "https://www.barchart.com/stocks/quotes/TSM/overview" }
    end

    it "單位換算：IV 小數、IV Rank 照頁面值、IV Pctl 由小數 ×100（與規格 P2 驗收值一致）" do
      expect(capture.persist_barchart_history(history_data)).to eq(1)

      expect(BarchartIvHistory.find_by(symbol: "TSM", trade_date: as_of)).to have_attributes(
        imp_vol: BigDecimal("0.51925"), iv_rank: BigDecimal("82.44"), iv_pctl: BigDecimal("92.43"),
        pc_vol_ratio: BigDecimal("0.9182"), options_volume: 418_426, pc_oi_ratio: BigDecimal("0.9812"),
        total_oi: 1_921_298, last_price: BigDecimal("353.1"),
        source_url: "https://www.barchart.com/stocks/quotes/TSM/options-history"
      )
    end

    it "HV 寫進當天快照：小數、標籤固定「HV 30 天」，不洗掉 LEAPS 寫的現價與來源" do
      LeapsIvSnapshot.create!(symbol: "TSM", as_of_date: as_of, spot: 353.1, source: "adhoc",
                              captured_at: 1.minute.ago, source_url: "https://www.barchart.com/stocks/quotes/TSM/options")
      capture.persist_barchart_history(history_data)

      expect(LeapsIvSnapshot.find_by(symbol: "TSM", as_of_date: as_of)).to have_attributes(
        bc_hv: BigDecimal("0.4666"), bc_hv_label: "HV 30 天", spot: BigDecimal("353.1"),
        source_url: "https://www.barchart.com/stocks/quotes/TSM/options"
      )
    end

    it "還沒有當天快照時，HV 照樣寫入（來源網址記 overview）" do
      capture.persist_barchart_history(history_data)

      expect(LeapsIvSnapshot.find_by(symbol: "TSM", as_of_date: as_of))
        .to have_attributes(bc_hv: BigDecimal("0.4666"), spot: nil,
                            source_url: "https://www.barchart.com/stocks/quotes/TSM/overview")
    end

    it "IV Pctl 換算後超出 0–100（頁面單位變了）就整批不寫" do
      bad = history_data.merge("rows" => [ raw_row.merge("impliedVolatilityPercentile1y" => 92.43) ])
      expect { capture.persist_barchart_history(bad) }.to raise_error(LeapsIvCapture::CaptureError, /IV Pctl/)
      expect(BarchartIvHistory.count).to eq(0)
    end

    it "backfill 多列一次 upsert，重跑不產生重複列" do
      rows = [ raw_row, raw_row.merge("date" => "2026-11-04", "impliedVolatilityRank1y" => 25.58) ]
      2.times { capture.persist_barchart_history(history_data.merge("rows" => rows)) }

      expect(BarchartIvHistory.where(symbol: "TSM").pluck(:trade_date, :iv_rank).sort)
        .to eq([ [ Date.new(2026, 11, 4), BigDecimal("25.58") ], [ as_of, BigDecimal("82.44") ] ])
    end

    it "讀不到 HV 時失敗" do
      expect { capture.persist_barchart_history(history_data.merge("hv_pct" => nil)) }
        .to raise_error(LeapsIvCapture::CaptureError, /Historical Volatility/)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# `CompositeSignalService` 是三維度儀表板的核心：把 Barchart 抓回來的技術面、
# 基本面、Options Flow 各自算成一個分數，**刻意不合併成單一數字**——背離本身
# 才是重點（見 class 註解）。
#
# 稽核 L-1：這支 388 行長期 0% 覆蓋。這裡釘住的是「分數門檻」與「背離判斷」，
# 因為那是投資決策直接依賴、而且改動時最容易在無聲中偏掉的部分。
#
# 註：評分權重本身未經回測（見 memory project_scoring_weights_unvalidated），
# 這些測試釘的是**目前的行為**，不代表權重是對的。要調權重時，這些測試會如實
# 失敗——那正是它們的用途：讓調整是有意識的，而不是改了沒人發現。
RSpec.describe CompositeSignalService do
  let(:symbol) { "TEST" }
  let(:date)   { Date.new(2026, 6, 15) }

  def make_technical(**attrs)
    TechnicalAnalysis.create!(
      symbol: symbol, snapshot_date: date, fetched_at: Time.current, **attrs,
    )
  end

  def make_fundamental(**attrs)
    Fundamental.create!(
      symbol: symbol, snapshot_date: date, fetched_at: Time.current, **attrs,
    )
  end

  def make_flow(**attrs)
    OptionsFlow.create!(
      symbol: symbol, snapshot_date: date, fetched_at: Time.current, **attrs,
    )
  end

  def result = described_class.new(symbol, date: date).call

  # ---------------------------------------------------------------------------
  describe "資料缺漏" do
    it "三個維度都沒有資料時，全部回 neutral 並標記 missing" do
      r = result

      expect(r[:technical]).to include(score: :neutral, missing: true)
      expect(r[:fundamental]).to include(score: :neutral, missing: true)
      expect(r[:options_flow]).to include(score: :neutral, missing: true)
      expect(r[:max_pain]).to be_nil
      expect(r[:fetched_at]).to be_nil
    end

    it "缺漏時不產生任何背離訊息" do
      expect(result[:divergences]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  describe "技術面評分" do
    # 滿分組合：20/50/200 日均線之上（1+1+2）、ADX 強勢多頭（+2）、超賣（+1）= 7
    it "均線全部之上 + ADX 多頭 + 超賣 → bullish" do
      make_technical(
        ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 5.0, ma_pct_chg_200d: 10.0,
        adx_14d: 30.0, di_plus_14d: 25.0, di_minus_14d: 15.0,
        stoch_k_14d: 15.0,
      )

      tech = result[:technical]
      expect(tech[:points]).to eq(7)
      expect(tech[:score]).to eq(:bullish)
    end

    it "均線全部之下 + ADX 空頭 → bearish" do
      make_technical(
        ma_pct_chg_20d: -3.0, ma_pct_chg_50d: -5.0, ma_pct_chg_200d: -10.0,
        adx_14d: 30.0, di_plus_14d: 15.0, di_minus_14d: 25.0,
      )

      tech = result[:technical]
      expect(tech[:points]).to eq(-6)
      expect(tech[:score]).to eq(:bearish)
    end

    # 門檻刻意不對稱：>= 4 才偏多，<= -3 就偏空。這裡把兩側邊界都釘住，
    # 之後若有人調整門檻，會明確看到是哪一側改了。
    it "門檻是不對稱的：+3 仍是 neutral，-3 已經是 bearish" do
      make_technical(ma_pct_chg_20d: 1.0, ma_pct_chg_50d: 1.0, ma_pct_chg_200d: 1.0)
      expect(result[:technical]).to include(points: 4, score: :bullish)

      TechnicalAnalysis.delete_all
      # 20 日之上(+1)、200 日之上(+2) = 3，差一分 → 仍是 neutral
      # （這一格是門檻 >= 4 與 >= 3 的唯一分界；少了它，門檻被改小也看不出來）
      make_technical(ma_pct_chg_20d: 1.0, ma_pct_chg_200d: 1.0)
      expect(result[:technical]).to include(points: 3, score: :neutral)

      TechnicalAnalysis.delete_all
      # 20 日之上(+1)、50 日之下(-1)、200 日之下(-2) = -2 → neutral
      make_technical(ma_pct_chg_20d: 1.0, ma_pct_chg_50d: -1.0, ma_pct_chg_200d: -1.0)
      expect(result[:technical]).to include(points: -2, score: :neutral)

      TechnicalAnalysis.delete_all
      # 三條都在下方但 200 日權重 2 → -1-1-2 = -4，先確認 -3 這一格
      make_technical(ma_pct_chg_20d: -1.0, ma_pct_chg_200d: -1.0)
      expect(result[:technical]).to include(points: -3, score: :bearish)
    end

    it "ADX 介於 20~25 時不計分，只給中性訊號" do
      make_technical(adx_14d: 22.0, di_plus_14d: 30.0, di_minus_14d: 5.0)

      tech = result[:technical]
      expect(tech[:points]).to eq(0)
      expect(tech[:signals].map { |s| s[:sentiment] }).to eq([ :neutral ])
    end

    it "nil 欄位直接略過，不當成 0 計分" do
      make_technical(ma_pct_chg_20d: 3.0)

      tech = result[:technical]
      expect(tech[:points]).to eq(1)
      expect(tech[:signals].length).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  describe "基本面評分" do
    it "分析師看多 + 盈利 + 估值合理 → bullish" do
      make_fundamental(
        analyst_strong_buy: 8, analyst_moderate_buy: 2, analyst_hold: 1, analyst_sell: 0,
        eps_ttm: 5.0, pe_ttm: 15.0,
      )

      fund = result[:fundamental]
      expect(fund[:points]).to eq(4) # 分析師 +2、EPS +1、PE +1
      expect(fund[:score]).to eq(:bullish)
    end

    it "虧損 + 估值偏高 → bearish" do
      make_fundamental(eps_ttm: -1.5, pe_ttm: 60.0)

      fund = result[:fundamental]
      expect(fund[:points]).to eq(-3) # EPS -2、PE -1
      expect(fund[:score]).to eq(:bearish)
    end

    it "門檻邊界：+2 仍是 neutral、-1 仍是 neutral" do
      # 分析師 ratio 0.6 → +1、EPS 盈利 → +1，合計 2，差一分
      make_fundamental(analyst_strong_buy: 6, analyst_hold: 4, eps_ttm: 5.0)
      expect(result[:fundamental]).to include(points: 2, score: :neutral)

      Fundamental.delete_all
      # PE 偏高 → -1，差一分
      make_fundamental(pe_ttm: 60.0)
      expect(result[:fundamental]).to include(points: -1, score: :neutral)
    end

    it "財報前 7 天內會覆蓋所有其他訊號，直接回 watching" do
      make_fundamental(
        next_earnings_date: Date.today + 3, earnings_time: "盤後",
        # 這些本來會算成 bullish，但財報前一律讓位
        analyst_strong_buy: 10, eps_ttm: 5.0, pe_ttm: 15.0,
      )

      fund = result[:fundamental]
      expect(fund[:score]).to eq(:watching)
      expect(fund[:signals].length).to eq(1)
      expect(fund[:signals].first[:sentiment]).to eq(:watching)
      expect(fund).not_to have_key(:points) # 提前 return，不計分
    end

    it "財報超過 7 天則照常評分，並附上財報日期訊號" do
      make_fundamental(next_earnings_date: Date.today + 30, earnings_time: "盤後", eps_ttm: 5.0)

      fund = result[:fundamental]
      expect(fund[:score]).to eq(:neutral)
      expect(fund[:signals].map { |s| s[:text] }).to include(a_string_including("下次財報"))
    end

    it "財報日期已過就不再顯示（DB 尚未更新的情況）" do
      make_fundamental(next_earnings_date: Date.today - 30, earnings_time: "盤後", eps_ttm: 5.0)

      texts = result[:fundamental][:signals].map { |s| s[:text] }
      expect(texts).not_to include(a_string_including("下次財報"))
    end
  end

  # ---------------------------------------------------------------------------
  describe "Options Flow 評分" do
    it "淨情緒與 Delta 皆偏多 + Ask C/P 強力主導 → bullish" do
      make_flow(net_sentiment: 1_000_000, delta_imbalance: 50_000, ask_call_put_ratio: 2.5)

      flow = result[:options_flow]
      expect(flow[:points]).to eq(4) # +1 +1 +2
      expect(flow[:score]).to eq(:bullish)
    end

    it "Ask C/P <= 0.5 記 -2，門檻兩側對稱" do
      make_flow(ask_call_put_ratio: 0.4)
      expect(result[:options_flow]).to include(points: -2, score: :bearish)

      OptionsFlow.delete_all
      make_flow(ask_call_put_ratio: 0.6) # 落在 0.5~0.67 → -1
      expect(result[:options_flow]).to include(points: -1, score: :neutral)
    end

    it "門檻邊界：+1 仍是 neutral" do
      make_flow(net_sentiment: 1_000_000) # 只有淨情緒 +1，差一分
      expect(result[:options_flow]).to include(points: 1, score: :neutral)
    end

    it "net_sentiment 為 0 時不計分（0 不代表方向）" do
      make_flow(net_sentiment: 0, delta_imbalance: 0)

      flow = result[:options_flow]
      expect(flow[:points]).to eq(0)
      expect(flow[:signals]).to be_empty
    end

    it "大單筆數相同時給中性訊號、不計分" do
      make_flow(large_call_count: 3, large_put_count: 3)

      flow = result[:options_flow]
      expect(flow[:points]).to eq(0)
      expect(flow[:signals].first[:sentiment]).to eq(:neutral)
    end

    it "高 Delta Call 一筆只給訊號、兩筆以上才計分" do
      make_flow(high_delta_call_count: 1)
      expect(result[:options_flow][:points]).to eq(0)

      OptionsFlow.delete_all
      make_flow(high_delta_call_count: 2)
      expect(result[:options_flow][:points]).to eq(1)
    end

    it "沒有 CSV 逐筆資料時 trade_csv_loaded 為 false" do
      make_flow(net_sentiment: 1)
      expect(result[:options_flow][:trade_csv_loaded]).to be(false)
    end

    it "有 CSV 逐筆資料時會納入 BuyToOpen 方向確認" do
      make_flow(net_sentiment: 1)
      # BuyToOpen Call 的 ask 權利金遠大於 Put → bto_ratio >= 2 → +1
      3.times do
        create(:options_flow_trade, symbol: symbol, snapshot_date: date,
                                    option_type: "Call", side: "ask",
                                    open_close: "BuyToOpen", premium: 400_000)
      end
      create(:options_flow_trade, symbol: symbol, snapshot_date: date,
                                  option_type: "Put", side: "ask",
                                  open_close: "BuyToOpen", premium: 100_000)

      flow = result[:options_flow]
      expect(flow[:trade_csv_loaded]).to be(true)
      expect(flow[:bto_call_ask_prem]).to eq(1_200_000)
      expect(flow[:bto_put_ask_prem]).to eq(100_000)
      expect(flow[:points]).to eq(2) # 淨情緒 +1、BTO 方向確認 +1
      expect(flow[:score]).to eq(:bullish)
    end

    it "被取消與多腿的成交不列入方向統計" do
      make_flow(net_sentiment: 1)
      create(:options_flow_trade, symbol: symbol, snapshot_date: date,
                                  option_type: "Call", side: "ask",
                                  open_close: "BuyToOpen", premium: 900_000,
                                  is_cancelled: true)
      create(:options_flow_trade, symbol: symbol, snapshot_date: date,
                                  option_type: "Call", side: "ask",
                                  open_close: "BuyToOpen", premium: 900_000,
                                  is_multi_leg: true)

      flow = result[:options_flow]
      expect(flow[:total_count]).to eq(2)
      expect(flow[:directional_count]).to eq(0)
      expect(flow[:bto_call_ask_prem]).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  describe "背離判斷" do
    # 技術面偏多、Flow 偏空 → warning（最需要提醒的組合）
    it "技術面偏多但 Flow 偏空 → warning" do
      make_technical(ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 3.0, ma_pct_chg_200d: 3.0)
      make_flow(ask_call_put_ratio: 0.3)

      divs = result[:divergences]
      expect(divs.map { |d| d[:level] }).to include(:warning)
      expect(divs.find { |d| d[:level] == :warning }[:message]).to include("機構可能在做對沖")
    end

    it "財報前的同一組背離會換成專屬文案" do
      make_technical(ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 3.0, ma_pct_chg_200d: 3.0)
      make_flow(ask_call_put_ratio: 0.3)
      make_fundamental(next_earnings_date: Date.today + 2, earnings_time: "盤後")

      msg = result[:divergences].find { |d| d[:level] == :warning }[:message]
      expect(msg).to include("財報前")
      expect(msg).to include("不宜追多")
    end

    it "Flow 偏多但技術面偏空 → caution" do
      make_technical(ma_pct_chg_20d: -3.0, ma_pct_chg_50d: -3.0, ma_pct_chg_200d: -3.0)
      make_flow(ask_call_put_ratio: 2.5, net_sentiment: 1_000_000)

      levels = result[:divergences].map { |d| d[:level] }
      expect(levels).to include(:caution)
      expect(levels).not_to include(:warning)
    end

    it "三維度一致看多 → confirm_bull" do
      make_technical(ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 3.0, ma_pct_chg_200d: 3.0)
      make_fundamental(analyst_strong_buy: 9, analyst_hold: 1, eps_ttm: 5.0, pe_ttm: 15.0)
      make_flow(ask_call_put_ratio: 2.5, net_sentiment: 1_000_000)

      expect(result[:divergences].map { |d| d[:level] }).to include(:confirm_bull)
    end

    it "三維度一致看空 → confirm_bear" do
      make_technical(ma_pct_chg_20d: -3.0, ma_pct_chg_50d: -3.0, ma_pct_chg_200d: -3.0)
      make_fundamental(eps_ttm: -1.0, pe_ttm: 60.0)
      make_flow(ask_call_put_ratio: 0.3, net_sentiment: -1_000_000)

      expect(result[:divergences].map { |d| d[:level] }).to include(:confirm_bear)
    end

    # watching（財報前）會被排除在一致性判斷之外，避免財報前誤報「三維度一致」
    it "財報前的 watching 不列入一致性判斷" do
      make_technical(ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 3.0, ma_pct_chg_200d: 3.0)
      make_flow(ask_call_put_ratio: 2.5, net_sentiment: 1_000_000)
      make_fundamental(next_earnings_date: Date.today + 2, earnings_time: "盤後")

      # 技術面 + Flow 兩個都 bullish，watching 被剔除後仍有 2 個 → 仍會 confirm_bull
      expect(result[:divergences].map { |d| d[:level] }).to include(:confirm_bull)
      expect(result[:fundamental][:score]).to eq(:watching)
    end

    it "neutral 不算背離" do
      make_technical(ma_pct_chg_20d: 3.0, ma_pct_chg_50d: 3.0, ma_pct_chg_200d: 3.0)
      make_flow(ask_call_put_ratio: 1.0) # neutral

      expect(result[:divergences].map { |d| d[:level] }).not_to include(:warning, :caution)
    end
  end

  # ---------------------------------------------------------------------------
  describe "Max Pain" do
    it "沒有快照時回 nil" do
      expect(result[:max_pain]).to be_nil
    end

    it "有快照時回傳圖表所需欄位" do
      MaxPainSnapshot.create!(
        symbol: symbol, snapshot_date: date, fetched_at: Time.current,
        expiration: "2026-07-17 (m)", strikes_filter: "show_all",
        volume_oi_filter: "open_interest", dte: 32,
        last_price: 10.5, max_pain_strike: 11.0,
        strikes: %w[10 11 12], call_pain: [ 1, 2, 3 ], put_pain: [ 3, 2, 1 ],
        call_oi: [ 10, 20, 30 ], put_oi: [ 30, 20, 10 ], iv_combined: [ 0.5, 0.6, 0.7 ],
      )

      mp = result[:max_pain]
      expect(mp[:max_pain_strike]).to eq(11.0)
      expect(mp[:last_price]).to eq(10.5)
      expect(mp[:strikes]).to eq(%w[10 11 12])
      # 沒有 MaxPainContractSnapshot 時這兩個是空陣列，不是 nil
      expect(mp[:max_pain_by_expiry]).to eq([])
      expect(mp[:available_expirations]).to eq([])
    end

    it "指定到期日時只取該到期日的快照" do
      %w[2026-07-17 2026-08-21].each_with_index do |exp, i|
        MaxPainSnapshot.create!(
          symbol: symbol, snapshot_date: date, fetched_at: Time.current,
          expiration: exp, strikes_filter: "show_all", volume_oi_filter: "open_interest",
          max_pain_strike: 10.0 + i,
        )
      end

      svc = described_class.new(symbol, date: date, mp_expiration: "2026-08-21")
      expect(svc.call[:max_pain][:max_pain_strike]).to eq(11.0)
    end
  end

  # ---------------------------------------------------------------------------
  describe "fetched_at" do
    it "取三個維度中最新的時間" do
      oldest = Time.current - 3.hours
      newest = Time.current - 10.minutes

      TechnicalAnalysis.create!(symbol: symbol, snapshot_date: date, fetched_at: oldest)
      OptionsFlow.create!(symbol: symbol, snapshot_date: date, fetched_at: newest)

      expect(result[:fetched_at]).to be_within(1.second).of(newest)
    end
  end
end

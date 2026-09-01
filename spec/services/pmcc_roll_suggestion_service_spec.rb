# frozen_string_literal: true

require "rails_helper"

RSpec.describe PmccRollSuggestionService do
  # 長腳：KL 100、實付成本 120.5、2028-01-21 到期
  # 目前短腳：KS 230、收租 3.2，買回要 1.1
  let(:position) do
    create(:pmcc_position, long_strike: 100, long_entry_cost: 120.5,
                           long_expiration: Date.current + 500)
  end
  let!(:open_leg) do
    create(:pmcc_short_leg, position: position, short_strike: 230,
                            premium_collected: 3.2, status: "open")
  end
  let(:current_quote) { { mid: 1.1 } }

  def candidate(strike:, delta: 0.25, mid: 4.0, dte: 30)
    { strike: strike, delta: delta, mid: mid, dte: dte,
      expiration_date: Date.current + dte }
  end

  def call(candidates, quote: current_quote)
    described_class.call(position, candidates: candidates, current_quote: quote)
  end

  describe "候選篩選" do
    it "只往上滾：履約價必須高於目前短腳" do
      res = call([ candidate(strike: 240), candidate(strike: 230), candidate(strike: 220) ])

      expect(res[:suggestions].map { |s| s[:strike] }).to eq([ 240.0 ])
    end

    it "Delta 落在 0.15–0.30 才列入（滾倉專用區間）" do
      res = call([
        candidate(strike: 240, delta: 0.14),
        candidate(strike: 245, delta: 0.15),
        candidate(strike: 250, delta: 0.30),
        candidate(strike: 255, delta: 0.31)
      ])

      expect(res[:suggestions].map { |s| s[:delta] }).to contain_exactly(0.15, 0.30)
    end

    it "缺 mid 的候選不列入（算不出滾動現金流）" do
      res = call([ candidate(strike: 240, mid: nil), candidate(strike: 250) ])

      expect(res[:suggestions].map { |s| s[:strike] }).to eq([ 250.0 ])
    end

    # 天期不在 19–45 只標記、不過濾——同本專案「列出候選、只標分級」的原則
    it "天期在建議區間外仍列出，只標記 in_suggested_dte" do
      res = call([ candidate(strike: 240, dte: 10), candidate(strike: 250, dte: 30) ])

      by_strike = res[:suggestions].index_by { |s| s[:strike] }
      expect(by_strike[240.0][:in_suggested_dte]).to be false
      expect(by_strike[250.0][:in_suggested_dte]).to be true
    end
  end

  describe "數字計算" do
    subject(:suggestion) { call([ candidate(strike: 240, mid: 4.0) ])[:suggestions].first }

    it "新 Spread = 新履約價 − 長腳履約價" do
      expect(suggestion[:spread]).to eq(140.0)   # 240 − 100
    end

    it "滾動淨現金流 = 新腳收租 − 舊腳買回成本" do
      expect(suggestion[:roll_cash_flow]).to eq(2.9)   # 4.0 − 1.1
    end

    # NetDebit 以實付成本為基準（2026-09-01 決定），跟損益帳本同一把尺
    it "NetDebit = 長腳實付成本 − (歷史淨收 + 本次滾動現金流)" do
      # 120.5 − (3.2 + 2.9) = 114.4
      expect(suggestion[:net_debit]).to eq(114.4)
    end

    it "MaxProfit = 新 Spread − 新 NetDebit" do
      expect(suggestion[:max_profit]).to eq(25.6)   # 140.0 − 114.4，服務端 round(4)
    end

    it "歷史短腳的收租與買回成本都算進 NetDebit" do
      create(:pmcc_short_leg, position: position, short_strike: 220,
                              premium_collected: 5.0, close_cost: 1.0, status: "rolled")
      # 歷史淨收 = (3.2 − 0) + (5.0 − 1.0) = 7.2；120.5 − (7.2 + 2.9) = 110.4
      expect(call([ candidate(strike: 240, mid: 4.0) ])[:suggestions].first[:net_debit]).to eq(110.4)
    end
  end

  describe "黃金法則" do
    # 方向與 PmccRankingService 一致：NetDebit < Spread 才通過。
    # pmcc-tracker.md 原本寫成 `PL >= Spread 通過`，與它自己引用的
    # P_L < K_S − K_L 以及既有實作都相反，已修正。
    it "NetDebit < Spread 通過" do
      res = call([ candidate(strike: 240, mid: 4.0) ])   # net 114.4 < spread 140

      expect(res[:suggestions].first[:passes_golden_rule]).to be true
    end

    it "NetDebit >= Spread 不通過，附帶數值化原因" do
      # 注意：不能用「較低的履約價」來造不通過——低於目前短腳會先被
      # 「只往上滾」篩掉，根本進不了候選。要拉高長腳實付成本。
      position.update!(long_entry_cost: 200)
      res = call([ candidate(strike: 240, mid: 4.0) ])   # spread 140 < net 193.9

      s = res[:suggestions].first
      expect(s[:passes_golden_rule]).to be false
      expect(s[:fail_reason]).to include("NetDebit", "Spread")
    end

    it "長腳與新短腳天期差不足 180 天則不通過" do
      position.update!(long_expiration: Date.current + 100)
      res = call([ candidate(strike: 240, mid: 4.0, dte: 30) ])

      s = res[:suggestions].first
      expect(s[:passes_golden_rule]).to be false
      expect(s[:fail_reason]).to include("180")
    end
  end

  describe "排序與筆數" do
    it "通過的排前面，同組依 MaxProfit 由高到低" do
      # 長腳成本 150：spread 140（strike 240）不足 → 不通過；
      # spread 160/180（strike 260/280）足夠 → 通過
      position.update!(long_entry_cost: 150)
      res = call([
        candidate(strike: 240, mid: 4.0),   # 不通過
        candidate(strike: 260, mid: 4.0),   # 通過，MaxProfit 較低
        candidate(strike: 280, mid: 4.0)    # 通過，MaxProfit 較高
      ])

      expect(res[:suggestions].map { |s| s[:strike] }).to eq([ 280.0, 260.0, 240.0 ])
    end

    it "最多回 5 筆" do
      cands = (1..8).map { |i| candidate(strike: 240 + i * 5, mid: 4.0) }

      expect(call(cands)[:suggestions].size).to eq(5)
    end
  end

  # 使用者要求：計算用當初買入成本，同時在上方顯示 Barchart 查到的目前市價
  describe "長腳資訊（計算用成本、顯示用市價）" do
    subject(:long_leg) { call([ candidate(strike: 240) ])[:long_leg] }

    let!(:long_quote) do
      create(:pmcc_leg_quote, symbol: position.ticker, strike: position.long_strike,
                              expiration_date: position.long_expiration, mid: 129.7, delta: 0.8978)
    end


    it "同時給出實付成本與目前市價，兩者分開標示" do
      expect(long_leg[:entry_cost]).to eq(120.5)
      expect(long_leg[:market_mid]).to eq(129.7)
    end

    it "附上未實現損益（每股）供畫面顯示" do
      expect(long_leg[:unrealized_per_share]).to eq(9.2)   # 129.7 − 120.5
    end

    it "附上報價時間，讓使用者知道市價多新" do
      expect(long_leg[:quoted_at]).to be_present
    end

    # 計算一律用實付成本，市價只是顯示——市價變動不該影響黃金法則判定
    it "市價不影響 NetDebit 與黃金法則" do
      before_net = call([ candidate(strike: 240) ])[:suggestions].first[:net_debit]
      long_quote.update!(mid: 300)

      expect(call([ candidate(strike: 240) ])[:suggestions].first[:net_debit]).to eq(before_net)
    end

    it "沒有長腳報價時 market_mid 為 nil，其餘照常運作" do
      long_quote.destroy!
      res = call([ candidate(strike: 240) ])

      expect(res[:long_leg][:market_mid]).to be_nil
      expect(res[:long_leg][:entry_cost]).to eq(120.5)
      expect(res[:status]).to eq(:ok)
    end
  end

  describe "前置狀態" do
    it "沒有 open 短腳時回 :no_open_leg" do
      open_leg.update!(status: "rolled", close_cost: 1.1)

      expect(call([ candidate(strike: 240) ])[:status]).to eq(:no_open_leg)
    end

    # 買回成本硬給 0 會讓每個候選的現金流都灌水，寧可明確回報缺報價
    it "沒有目前短腳報價時回 :no_buyback_quote，不假設買回成本為 0" do
      res = call([ candidate(strike: 240) ], quote: nil)

      expect(res[:status]).to eq(:no_buyback_quote)
      expect(res[:suggestions]).to be_empty
    end

    it "候選全被篩掉時回 :no_candidates" do
      expect(call([ candidate(strike: 220) ])[:status]).to eq(:no_candidates)
    end
  end

  it "吃得下 PmccShortCallSnapshot 當候選" do
    snap = create(:pmcc_short_call_snapshot, strike: 240, delta: 0.25,
                                             mid_price: 4.0, dte: 30)

    expect(call([ snap ])[:suggestions].first[:strike]).to eq(240.0)
  end
end

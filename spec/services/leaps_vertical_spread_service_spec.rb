# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P2。chain 一律以 stub 的 fetcher 提供（不讀快取表、不跑 sidecar）。
RSpec.describe LeapsVerticalSpreadService do
  def d(value) = value.nil? ? nil : BigDecimal(value.to_s)

  def quote(strike, bid: nil, ask: nil, last: nil, delta: nil)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: d(last), delta: d(delta) }
  end

  def expiry(name, dte, calls)
    { expiry: name, date: Date.parse(name[0, 10]), dte: dte, fetched_at: Time.zone.parse("2026-09-25 18:31"),
      calls: calls }
  end

  def fetch_result(spot, *expirations)
    { status: :ok, symbol: "ORCL", spot: d(spot), expirations: expirations }
  end

  def fetcher_returning(result)
    instance_double(LeapsCallChainFetcher, call: result)
  end

  def run(result, ticker: "ORCL", long_strike: "110", **opts)
    described_class.new(ticker: ticker, long_strike: long_strike, fetcher: fetcher_returning(result), **opts).call
  end

  before { allow(LeapsRankingService).to receive(:new).and_return(instance_double(LeapsRankingService, call: [])) }

  let(:exp1) { "2028-01-21-m" }

  describe "計算" do
    let(:chain) do
      fetch_result(139.54, expiry(exp1, 483, [
        quote(110, bid: 54.5, ask: 55.5, delta: 0.8),
        quote(200, bid: 19, ask: 21, delta: 0.3)
      ]))
    end

    it "基本：淨成本 3500、最大虧損 3500、最大獲利 5500、損益兩平 145、風險報酬比 1 : 1.57" do
      r = run(chain, expiry: exp1, short_strike: "200")[:result]

      expect(r[:width]).to eq(d(90))
      expect(r[:d_mid]).to eq(d(35))
      expect(r[:net_cost]).to eq(d(3500))
      expect(r[:max_loss]).to eq(d(3500))
      expect(r[:max_profit]).to eq(d(5500))
      expect(r[:breakeven]).to eq(d(145))
      expect(r[:display]).to include(net_cost: "$3,500.00", max_loss: "$3,500.00", max_profit: "$5,500.00",
                                     breakeven: "$145.00", risk_reward: "1 : 1.57", width: "$90.00")
    end

    it "保守成交：ask_L = 56、bid_S = 19 → D_nat × 100 = 3700.00" do
      nat = fetch_result(139.54, expiry(exp1, 483, [
        quote(110, bid: 54, ask: 56, delta: 0.8),
        quote(200, bid: 19, ask: 21, delta: 0.3)
      ]))
      r = run(nat, expiry: exp1, short_strike: "200")[:result]

      expect(r[:net_cost_nat]).to eq(d(3700))
      expect(r[:display][:net_cost_nat]).to eq("$3,700.00")
    end

    it "BigDecimal 精度：mid_L = 10.125、mid_S = 3.335 → D_mid = 6.790，顯示 $679.00" do
      precise = fetch_result(120, expiry(exp1, 483, [
        quote(100, bid: 10.10, ask: 10.15, delta: 0.8),
        quote(150, bid: 3.33, ask: 3.34, delta: 0.3)
      ]))
      r = run(precise, long_strike: "100", expiry: exp1, short_strike: "150")[:result]

      expect(r[:d_mid]).to eq(BigDecimal("6.790"))
      expect(r[:d_mid]).to be_a(BigDecimal)
      expect(r[:display][:net_cost]).to eq("$679.00")
    end
  end

  describe "無效組合（不含 result，紅字說明哪個條件不成立）" do
    it "賣腳 ≤ 買腳：K_S = 110、K_L = 110" do
      chain = fetch_result(100, expiry(exp1, 483, [ quote(110, bid: 20, ask: 21) ]))
      out = run(chain, expiry: exp1, short_strike: "110")

      expect(out[:result]).to be_nil
      expect(out[:error][:message]).to include("賣出腳履約價 110.00 必須高於買入腳履約價 110.00")
    end

    it "淨成本 ≥ 寬度：W = 10、D_mid = 10" do
      chain = fetch_result(100, expiry(exp1, 483, [
        quote(110, bid: 15, ask: 15), quote(120, bid: 5, ask: 5)
      ]))
      out = run(chain, expiry: exp1, short_strike: "120")

      expect(out[:result]).to be_nil
      expect(out[:error][:message]).to include("淨成本 10.00 ≥ 價差寬度 10.00")
    end
  end

  describe "報價規則" do
    it "無報價（bid、ask、last 皆 0）：選項 disabled，不能成為預設" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(110, bid: 54, ask: 56, delta: 0.8),
        quote(180, bid: 0, ask: 0, last: 0, delta: 0.3),
        quote(200, bid: 19, ask: 21, delta: 0.2)
      ]))
      out = run(chain)
      dead = out[:short_options].find { |o| o[:strike] == d(180) }

      expect(dead).to include(disabled: true)
      expect(dead[:label]).to include("無報價")
      expect(out[:selected][:short_strike]).to eq(d(200))
    end

    it "盤後參考價：賣腳只有 last → 以 11.20 計算、選項與結果都標示、D_nat 為 nil" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(110, bid: 54, ask: 56, delta: 0.8),
        quote(210, bid: 0, ask: 0, last: 11.20, delta: 0.3)
      ]))
      out = run(chain, expiry: exp1, short_strike: "210")
      r = out[:result]

      expect(r[:d_mid]).to eq(d(55) - d("11.20"))
      expect(out[:short_options].first[:label]).to eq("210.00｜last 11.20（盤後參考價）｜Δ 0.30")
      expect(r[:after_hours_legs]).to eq([ :short ])
      expect(r[:net_cost_nat]).to be_nil
      expect(r[:display][:net_cost_nat]).to eq("—（盤後無買賣價）")
    end

    it "兩腳都正常：不出現「盤後參考價」" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(110, bid: 54, ask: 56, delta: 0.8), quote(210, bid: 10, ask: 12, delta: 0.3)
      ]))
      out = run(chain, expiry: exp1, short_strike: "210")

      expect(out.to_s).not_to include("盤後參考價")
      expect(out[:result][:after_hours_legs]).to be_empty
    end
  end

  describe "必填" do
    it "缺少價格：只給 ticker → nil" do
      expect(described_class.new(ticker: "ORCL", long_strike: nil, fetcher: fetcher_returning({})).call).to be_nil
    end

    it "缺少標的：只給 long_strike → nil" do
      expect(described_class.new(ticker: " ", long_strike: "100", fetcher: fetcher_returning({})).call).to be_nil
    end
  end

  describe "選項與預設值" do
    let(:exp0) { "2027-10-15-m" }
    let(:exp2) { "2029-01-19-m" }
    let(:multi) do
      fetch_result(139.54,
        expiry(exp0, 385, [ quote(100, bid: 44, ask: 46, delta: 0.85), quote(150, bid: 9, ask: 11, delta: 0.45),
                            quote(170, bid: 4, ask: 6, delta: 0.31), quote(190, bid: 2, ask: 3, delta: 0.2) ]),
        expiry(exp2, 847, [ quote(100, bid: 54, ask: 56, delta: 0.8), quote(160, bid: 19, ask: 21, delta: 0.42),
                            quote(200, bid: 11, ask: 13, delta: 0.29), quote(230, bid: 8, ask: 9, delta: 0.22) ]),
        expiry(exp1, 483, [ quote(100, bid: 48, ask: 50, delta: 0.82), quote(180, bid: 9, ask: 10, delta: 0.3) ]))
    end

    it "只有標的和價格：買入腳全是 100.00、預設最遠有報價的到期日、賣腳 > max(K_L, 現價) 且 delta 最接近 0.30" do
      out = run(multi, long_strike: "100")

      expect(out[:long_options].map { |o| o[:strike] }).to all(eq(d(100)))
      expect(out[:selected][:expiry]).to eq(exp2)
      expect(out[:short_options].map { |o| o[:strike] }).to all(be > d("139.54"))
      expect(out[:selected][:short_strike]).to eq(d(200))
      expect(out[:result]).to be_present
    end

    it "同履約價多個到期日：依 DTE 由近到遠；切換 expiry 後賣腳換成該到期日的 chain" do
      out = run(multi, long_strike: "100")
      expect(out[:long_options].map { |o| o[:expiry] }).to eq([ exp0, exp1, exp2 ])
      expect(out[:long_options].first[:label]).to eq("2027-10-15 · 385 DTE｜100.00｜mid 45.00｜Δ 0.85")

      switched = run(multi, long_strike: "100", expiry: exp0)
      expect(switched[:short_options].map { |o| o[:strike] }).to eq([ d(150), d(170), d(190) ])
      expect(switched[:selected][:short_strike]).to eq(d(170))
    end

    it "買入腳預設優先取候選排行第 1 名（履約價等於 K_L）的到期日" do
      snapshot = instance_double(LeapsOptionChainSnapshot, strike: d(100), expiration_date: Date.parse(exp0[0, 10]))
      allow(LeapsRankingService).to receive(:new).with("ORCL")
        .and_return(instance_double(LeapsRankingService, call: [ { snapshot: snapshot } ]))

      expect(run(multi, long_strike: "100")[:selected][:expiry]).to eq(exp0)
    end

    it "賣腳必須價外：K_L = 100、現價 139.54，chain 有 120、130、140、150 → 只有 140、150" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(100, bid: 45, ask: 47), quote(120, bid: 25, ask: 27), quote(130, bid: 18, ask: 20),
        quote(140, bid: 12, ask: 14), quote(150, bid: 8, ask: 10)
      ]))
      expect(run(chain, long_strike: "100")[:short_options].map { |o| o[:strike] }).to eq([ d(140), d(150) ])
    end

    it "履約價格式：100、100.0、100.00 結果完全相同" do
      outs = %w[100 100.0 100.00].map { |s| run(multi, long_strike: s) }
      expect(outs.uniq.size).to eq(1)
    end

    it "沒有 delta：賣腳預設取履約價最接近 現價 × 1.3 的那一檔" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(100, bid: 45, ask: 47), quote(150, bid: 12, ask: 14), quote(180, bid: 6, ask: 8),
        quote(200, bid: 3, ask: 5)
      ]))
      # 139.54 × 1.3 = 181.402
      expect(run(chain, long_strike: "100")[:selected][:short_strike]).to eq(d(180))
    end
  end

  describe "錯誤（功能定義 6，不含任何計算數字）" do
    it "找不到履約價：列出上下最接近的一檔" do
      chain = fetch_result(139.54, expiry(exp1, 483, [ quote(100, bid: 45, ask: 47), quote(105, bid: 42, ask: 44) ]))
      out = run(chain, long_strike: "101.37")

      expect(out[:error][:message]).to eq("ORCL 的 LEAPS 中查無履約價 101.37；最接近的履約價：100.00、105.00")
      expect(out[:result]).to be_nil
    end

    it "有這個履約價，但所有到期日都沒有有效報價" do
      chain = fetch_result(139.54, expiry(exp1, 483, [ quote(100, bid: 0, ask: 0, last: 0), quote(150, bid: 1, ask: 2) ]))
      expect(run(chain, long_strike: "100")[:error][:message]).to eq("履約價 100.00 在所有 LEAPS 到期日都沒有有效報價")
    end

    it "沒有合格的賣出腳：價外選項全都無報價" do
      chain = fetch_result(139.54, expiry(exp1, 483, [
        quote(100, bid: 45, ask: 47), quote(150, bid: 0, ask: 0, last: 0), quote(200)
      ]))
      out = run(chain, long_strike: "100")

      expect(out[:error][:message]).to eq("2028-01-21 沒有符合條件的價外賣出腳")
      expect(out[:result]).to be_nil
    end

    it "fetcher 的查無代號、沒有 LEAPS 原文傳出" do
      out = run({ status: :error, code: :symbol_not_found, message: "查無股票代號 ZZZZQ" }, ticker: "ZZZZQ")
      expect(out[:error]).to include(kind: :symbol_not_found, message: "查無股票代號 ZZZZQ")
    end

    it "fetcher 停滯或失敗 → 「Barchart 讀取失敗：{原因}」，可重試" do
      out = run({ status: :error, code: :stalled, message: "讀取 2028-01-21 chain 超過 30 秒沒有回應" })
      expect(out[:error]).to include(kind: :fetch_failed, retryable: true,
                                     message: "Barchart 讀取失敗：讀取 2028-01-21 chain 超過 30 秒沒有回應")
    end
  end

  it "選了特定到期日時，只要求 fetcher 刷新那個到期日" do
    fetcher = fetcher_returning(fetch_result(139.54, expiry(exp1, 483, [ quote(110, bid: 54, ask: 56) ])))
    described_class.new(ticker: "orcl", long_strike: "110", expiry: exp1, fetcher: fetcher).call
    expect(fetcher).to have_received(:call).with(only_expiry: exp1)
  end
end

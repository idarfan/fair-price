# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P6：8 格 tooltip 與賣出腳導覽的句子，一律以當下實際兩腳與現價組成。
RSpec.describe LeapsVerticalSpreadService::Explanation do
  def d(value) = value.nil? ? nil : BigDecimal(value.to_s)

  def quote(strike, bid: nil, ask: nil, last: nil, delta: nil)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: d(last), delta: d(delta) }
  end

  def outcome(calls, spot: "138.38", **params)
    allow(LeapsRankingService).to receive(:new).and_return(instance_double(LeapsRankingService, call: []))
    chain = { status: :ok, symbol: "ORCL", spot: d(spot), expirations: [
      { expiry: "2028-01-21-m", dte: 483, fetched_at: Time.current, calls: calls }
    ] }
    fetcher = instance_double(LeapsCallChainFetcher, call: chain)
    LeapsVerticalSpreadService.new(ticker: "ORCL", long_strike: "100", fetcher: fetcher, **params).call
  end

  let(:calls) do
    [ quote(100, bid: 54.75, ask: 55.70, delta: 0.795), quote(190, bid: 21.6, ask: 22.55, delta: 0.45),
      quote(250, bid: 12.75, ask: 13.05, delta: 0.301) ]
  end
  let(:out) { outcome(calls) }
  let(:tips) { described_class.tips(out) }
  let(:tour) { described_class.tour(out) }

  def tour_text(steps) = steps.flat_map { |s| s[:lines] }.map { |line| line.map(&:first).join }.join("\n")

  describe ".tips（8 格）" do
    it "8 個 key 齊全，第一列是當下數值，三個格子帶顏色" do
      expect(tips.keys).to eq(%i[long_leg short_leg net_cost max_profit breakeven max_loss risk_reward width])
      expect(tips[:max_profit]).to include(value: "$10,767.50", tone: :profit)
      expect(tips[:breakeven]).to include(value: "$142.33", tone: :breakeven)
      expect(tips[:max_loss]).to include(value: "$4,232.50", tone: :loss)
      expect(tips[:net_cost][:tone]).to be_nil
    end

    it "說明句用實際兩腳與現價計算" do
      # 買入腳 mid 55.225 是半分：算式保留三位（P6 審查 r1），格子數值仍四捨五入到兩位
      expect(tips[:net_cost][:lines].join).to include("55.225", "12.90", "42.325", "$4,232.50")
      expect(tips[:net_cost][:lines].join).to include("55.70", "12.75", "$4,295.00")
      expect(tips[:max_profit][:lines].join).to include("$150.00", "42.325", "250.00", "+80.66%")
      expect(tips[:breakeven][:lines].join).to include("100.00", "142.325", "138.38", "+2.85%")
      expect(tips[:breakeven][:value]).to eq("$142.33")
      expect(tips[:width][:lines].join).to include("250.00", "100.00", "$150.00")
      expect(tips[:short_leg][:lines].join).to include("250.00", "138.38", "23.36%")
    end

    it "換一組報價，句子跟著改變（不是固定範例）" do
      other = outcome([ quote(100, bid: 60, ask: 62, delta: 0.8), quote(250, bid: 10, ask: 11, delta: 0.3) ], spot: "150")
      other_tips = described_class.tips(other)

      expect(other_tips[:net_cost][:lines].join).to include("61.00", "10.50", "50.50")
      expect(other_tips[:net_cost][:lines].join).not_to include("42.33")
      expect(other_tips[:breakeven][:lines].join).to include("150.50", "150.00")
    end

    # P6 審查 r1 問題 1：mid 為半分時，算式若用四捨五入後的兩位數，照著算會對不上。
    describe "mid 為半分時算式照著算對得上" do
      def nums(text) = text.scan(/[\d,]+\.\d+/).map { |s| BigDecimal(s.delete(",")) }

      let(:half) do
        outcome([ quote(100, bid: 54.10, ask: 55.00, delta: 0.79), quote(250, bid: 12.80, ask: 13.15, delta: 0.30) ], spot: "137.10")
      end
      let(:half_tips) { described_class.tips(half) }

      it "淨成本：(買入腳 − 賣出腳) × 100 = 每股淨成本 × 100 = 金額" do
        # 「100」沒有小數點，不會被 nums 抓到
        long, short, per_share, total = nums(half_tips[:net_cost][:lines].first)
        expect([ long, short ]).to eq([ d("54.55"), d("12.975") ])
        expect(long - short).to eq(per_share)
        expect(per_share * 100).to eq(total)
      end

      it "最大獲利：(寬度 − 每股淨成本) × 100 = 金額" do
        _k, width, per_share, total = nums(half_tips[:max_profit][:lines].first)
        expect((width - per_share) * 100).to eq(total)
      end

      it "損益兩平：買入腳履約價 + 每股淨成本 = 損益兩平" do
        k_long, per_share, be = nums(half_tips[:breakeven][:lines].first)
        expect(k_long + per_share).to eq(be)
      end

      it "兩位數就精確的值維持兩位" do
        expect(tips[:net_cost][:lines].first).to include("(買入腳 55.225 − 賣出腳 12.90)")
      end
    end

    it "使用者改選賣出腳時，說明預設是哪一檔" do
      changed = described_class.tips(outcome(calls, expiry: "2028-01-21-m", short_strike: "190"))
      expect(changed[:short_leg][:lines].join).to include("你改選了 190.00", "預設", "250.00")
    end

    it "賣出腳只有 last 時標示盤後參考價" do
      ah = described_class.tips(outcome([ calls[0], quote(250, bid: 0, ask: 0, last: 12.9, delta: 0.3) ]))
      expect(ah[:short_leg][:lines].join).to include("盤後參考價")
      expect(ah[:net_cost][:lines].join).to include("沒有買賣價")
    end

    it "沒有 Δ 時說明改用 現價 × 1.3" do
      nd = described_class.tips(outcome([ quote(100, bid: 54, ask: 56), quote(180, bid: 20, ask: 22) ], spot: "138.38"))
      expect(nd[:short_leg][:lines].join).to include("現價 × 1.3", "179.89")
    end
  end

  describe ".tour（7 步）" do
    it "7 步的標題與錨點" do
      expect(tour.map { |s| s[:title] }).to eq([
        "賣出腳在做什麼", "Δ（Delta）是什麼", "為什麼建議 Δ 0.30", "最大獲利",
        "損益兩平", "提前履約與配息：LEAPS 價差為什麼很少遇到", "0.30 是起點，不是答案"
      ])
      expect(tour.map { |s| s[:anchor] }).to eq(%i[short_leg short_leg short_leg max_profit breakeven short_leg short_leg])
    end

    it "內容用當下數據，賺／平／賠的數字帶顏色" do
      text = tour_text(tour)
      expect(text).to include("250.00", "0.30", "483", "12.90", "+80.66%", "23.36%", "+2.85%")
      segments = tour.flat_map { |s| s[:lines] }.flatten(1)
      expect(segments).to include([ "$10,767.50", :profit ], [ "$142.33", :breakeven ])
      expect(text).to include("不構成投資建議")
    end

    it "提前履約一步寫出時間價值與觸發條件，不渲染成常見風險" do
      step = tour_text([ tour[5] ])
      expect(step).to include("除息日", "時間價值", "12.90", "483")
      expect(step).to include("很少")
    end

    it "這個到期日沒有接近 0.30 的賣出腳時，說明實際選到的 Δ" do
      far = described_class.tour(outcome([ calls[0], quote(230, bid: 29, ask: 30, delta: 0.48) ]))
      expect(tour_text([ far.last ])).to include("最接近 0.30 的是 230.00", "Δ 0.48", "履約價不夠高")
    end

    # P6 審查 r1 質詢 2：最接近的一檔 Δ 低於 0.30 太多時，原因是履約價間距大，不是履約價不夠高。
    it "最接近 0.30 的一檔 Δ 偏低時，說明是履約價間距太大" do
      low = described_class.tour(outcome([ calls[0], quote(190, bid: 21, ask: 22, delta: 0.46), quote(250, bid: 8, ask: 9, delta: 0.20) ]))
      text = tour_text([ low.last ])
      expect(text).to include("最接近 0.30 的是 250.00", "Δ 0.20", "間距")
      expect(text).not_to include("履約價不夠高")
    end
  end

  it "沒有結果（錯誤）時回傳空的 tips 與 tour" do
    err = { error: { kind: :no_short, message: "x" }, result: nil }
    expect(described_class.tips(err)).to eq({})
    expect(described_class.tour(err)).to eq([])
  end
end

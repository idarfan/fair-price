# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P4：垂直價差區塊的 4 種狀態。數字一律由 LeapsVerticalSpreadService
# 算好（這裡用 stub 的 fetcher 跑真的 service），元件只負責呈現。
RSpec.describe LeapsRecommendations::VerticalSpreadSection do
  def d(value) = value.nil? ? nil : BigDecimal(value.to_s)

  def quote(strike, bid: nil, ask: nil, last: nil, delta: nil)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: d(last), delta: d(delta) }
  end

  let(:spot) { d("139.54") }
  let(:chain) do
    { status: :ok, symbol: "ORCL", spot: spot, expirations: [
      { expiry: "2027-10-15-m", dte: 385, fetched_at: Time.zone.parse("2026-09-25 13:44 UTC"),
        calls: [ quote(100, bid: 52, ask: 54, delta: 0.81), quote(120, bid: 30, ask: 32, delta: 0.6),
                 quote(150, bid: 9, ask: 11, delta: 0.45), quote(170, bid: 4, ask: 6, delta: 0.31) ] },
      { expiry: "2029-01-19-m", dte: 847, fetched_at: Time.zone.parse("2026-09-25 13:44 UTC"),
        calls: [ quote(100, bid: 65, ask: 68, delta: 0.8), quote(200, bid: 0, ask: 0, last: 21, delta: 0.3) ] }
    ] }
  end

  def outcome_for(result, long_strike: "100", **params)
    allow(LeapsRankingService).to receive(:new).and_return(instance_double(LeapsRankingService, call: []))
    fetcher = instance_double(LeapsCallChainFetcher, call: result)
    LeapsVerticalSpreadService.new(ticker: "ORCL", long_strike: long_strike, fetcher: fetcher, **params).call
  end

  def render_html(**kwargs)
    Nokogiri::HTML(described_class.new(symbol: "ORCL", user_strike: "100", **kwargs).call)
  end

  describe "結果" do
    let(:html) { render_html(outcome: outcome_for(chain, expiry: "2027-10-15-m")) }

    it "有 2 個 select；買入腳每個選項的履約價都是 K_L；賣出腳都 > max(K_L, 現價)" do
      expect(html.css("select").size).to eq(2)

      long_strikes = html.css('select[name="expiry"] option').map { |o| o.text.split("｜")[1] }
      expect(long_strikes).to all(eq("100.00"))

      short_strikes = html.css('select[name="short_strike"] option').map { |o| d(o["value"]) }
      expect(short_strikes).to eq([ d(150), d(170) ])
      expect(short_strikes).to all(be > [ d(100), spot ].max)
    end

    it "結果卡依規格順序：實付淨成本、最大獲利、損益兩平、最大虧損、風險報酬比、價差寬度" do
      labels = html.css(".grid > div > p:first-child").map { |p| p.text.delete_suffix(" ⓘ") }
      expect(labels).to eq(%w[實付淨成本 最大獲利 損益兩平 最大虧損 風險報酬比 價差寬度])
    end

    it "標題列顯示台北時間的報價時間，並有固定提示" do
      expect(html.text).to include("報價時間：2026-09-25 21:44（台北時間）")
      expect(html.text).to include(described_class::NOTE)
    end

    it "兩腳都有買賣價時不出現盤後標籤" do
      expect(html.text).not_to include("盤後參考價")
    end
  end

  describe "P6：8 格 tooltip、顏色、導覽" do
    let(:out) { outcome_for(chain, expiry: "2027-10-15-m") }
    let(:html) { render_html(outcome: out) }
    let(:tips) { LeapsVerticalSpreadService::Explanation.tips(out) }

    it "8 格都有 data-tip-key，值與句子來自當下的兩腳" do
      keys = html.css("[data-tip-key^='vs_']").map { |n| n["data-tip-key"] }
      expect(keys).to match_array(%w[vs_long_leg vs_short_leg vs_net_cost vs_max_profit vs_breakeven
                                     vs_max_loss vs_risk_reward vs_width])

      node = html.at_css("[data-tip-key='vs_net_cost']")
      expect(node["data-tip-value"]).to eq(tips[:net_cost][:value])
      expect(JSON.parse(node["data-tip-lines"])).to eq(tips[:net_cost][:lines])
    end

    it "選單的 tooltip 掛在標題文字上，不掛在 select（點選單不會跳出說明）" do
      expect(html.css("select[data-tip-key]")).to be_empty
      expect(html.at_css("[data-tip-key='vs_short_leg']").name).to eq("span")
    end

    it "最大獲利綠、損益兩平黃、最大虧損紅；實付淨成本維持深灰" do
      tone = ->(key) { html.at_css("[data-tip-key='#{key}']")["data-tip-tone"] }
      value_class = ->(key) { html.at_css("[data-tip-key='#{key}'] [data-vs-value]")["class"] }

      expect(tone.("vs_max_profit")).to eq("profit")
      expect(tone.("vs_breakeven")).to eq("breakeven")
      expect(tone.("vs_max_loss")).to eq("loss")
      expect(value_class.("vs_max_profit")).to include("vs-tone-profit")
      expect(value_class.("vs_breakeven")).to include("vs-tone-breakeven")
      expect(value_class.("vs_max_loss")).to include("vs-tone-loss")
      expect(value_class.("vs_net_cost")).not_to include("vs-tone")
      expect(html.at_css("[data-tip-key='vs_net_cost']")["data-tip-tone"]).to be_nil
    end

    it "賣出腳旁有導覽按鈕，導覽資料以 JSON 隨片段輸出（7 步），錨點都在畫面上" do
      expect(html.at_css("button[data-vs-tour]").text).to eq("為什麼建議 Δ 0.30？")
      steps = JSON.parse(html.at_css("script[data-vs-tour-data]").text)
      expect(steps.size).to eq(7)
      steps.map { |s| s["anchor"] }.uniq.each do |anchor|
        expect(html.at_css("[data-vs-tour-anchor='#{anchor}']")).to be_present
      end
    end

    it "錯誤狀態沒有 tooltip 與導覽" do
      err = render_html(outcome: outcome_for(chain, long_strike: "101.37"))
      expect(err.css("[data-tip-key^='vs_'], button[data-vs-tour], script[data-vs-tour-data]")).to be_empty
    end
  end

  it "盤後參考價：黃色標籤寫出是哪一腳，選項旁也標註" do
    html = render_html(outcome: outcome_for(chain, expiry: "2029-01-19-m", short_strike: "200"))

    # S3 起黃色框還有旗標警示（dividend_unknown 等），要找寫著盤後參考價的那一個
    badge = html.css(".bg-yellow-50").map(&:text).find { |t| t.include?(described_class::AFTER_HOURS_BADGE) }
    expect(badge).to include("賣出腳")
    expect(html.at_css('select[name="short_strike"] option[selected]').text).to include("（盤後參考價）")
  end

  it "配色（2026-09-27 使用者選定 C3）：六格都有 vs-card，獲利／虧損／實付淨成本另帶角色 class" do
    html = render_html(outcome: outcome_for(chain, expiry: "2027-10-15-m"))
    cards = html.css(".grid-cols-2 > div[data-vs-tour-anchor]").to_h { |c| [ c["data-vs-tour-anchor"], c["class"].split ] }

    expect(cards.keys).to eq(%w[net_cost max_profit breakeven max_loss risk_reward width])
    expect(cards.values).to all(include("vs-card"))
    expect(cards.slice("max_profit", "max_loss", "net_cost").transform_values { |c| c.grep(/vs-card-/) })
      .to eq("max_profit" => [ "vs-card-profit" ], "max_loss" => [ "vs-card-loss" ], "net_cost" => [ "vs-card-cost" ])
    expect(cards.except("max_profit", "max_loss", "net_cost").values.flat_map { |c| c.grep(/vs-card-/) }).to be_empty
  end

  describe "到期日預估股價（P7）" do
    let(:html) { render_html(outcome: outcome_for(chain, expiry: "2027-10-15-m")) }

    it "位在選單與結果卡之間、置中；帶著 service 算好的兩腳參數，結果一開始是空的" do
      row = html.at_css("[data-vs-payoff]")
      expect(row.at_css("[data-vs-payoff-inputs]")["class"]).to include("justify-center")
      expect(row.at_css("input#vs-target-price")["value"]).to be_nil
      expect(row.at_css("label[for='vs-target-price']").text).to eq("到期日預估股價")
      expect(row.at_css("[data-vs-payoff-result]").text).to eq("")
      # 預設：買入腳 100（bid 52／ask 54）、賣出腳 170（bid 4／ask 6）
      params = JSON.parse(row["data-vs-payoff-params"])
      expect(params).to include("long_strike" => "100.0", "long_price" => "53.0", "long_bid" => "52.0",
                                "long_ask" => "54.0", "short_strike" => "170.0", "short_price" => "5.0",
                                "expiry" => "2027-10-15", "quote_date" => "2026-09-25", "contracts" => "1")

      body = html.to_html
      expect(body.index("data-vs-form")).to be < body.index("data-vs-payoff")
      expect(body.index("data-vs-payoff")).to be < body.index("實付淨成本")
    end

    it "載入中、錯誤狀態沒有輸入欄位" do
      expect(render_html(state: :loading).at_css("[data-vs-payoff]")).to be_nil
      expect(render_html(outcome: outcome_for(chain, long_strike: "101.37")).at_css("[data-vs-payoff]")).to be_nil
    end
  end

  describe LeapsRecommendations::VerticalSpreadPayoff do
    def render_payoff(result) = Nokogiri::HTML.fragment(described_class.new(result: result).call)

    # FX-1（費用 0）
    let(:fx1) do
      { long_strike: "100", long_bid: "74.95", long_ask: "79.05", long_price: "77", short_strike: "240",
        short_bid: "29.7", short_ask: "33.7", short_price: "31.7", spot: "150", quote_date: "2026-09-30",
        expiry: "2028-12-15", dividend_annual: "0", contracts: "1" }
    end

    before { allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0")) }

    def payoff_for(**params) = LeapsVerticalSpreadService::Payoff.call(fx1.merge(params))

    it "S3 第 4 點格式：→ 平倉理論損益 +$X（保守 +$Y）｜到期損益 +$X（+Y%）" do
      frag = render_payoff(payoff_for(target_price: "200", close_date: "2028-12-15"))
      expect(frag.at_css("[data-vs-payoff-line]").text)
        .to eq("→ 平倉理論損益 +$5,470.00（保守 +$4,660.00）｜到期損益 +$5,470.00（+120.75%）")
      expect(frag.at_css("[data-vs-close-pnl]").text).to eq("+$5,470.00")
      expect(frag.at_css("[data-vs-expiry-pnl]").text).to eq("+$5,470.00")
      expect(frag.css(".vs-tone-profit").size).to eq(2)
    end

    it "虧損：紅字" do
      frag = render_payoff(payoff_for(target_price: "90", close_date: "2028-12-15"))
      expect(frag.at_css("[data-vs-expiry-pnl]").text).to eq("-$4,530.00")
      expect(frag.at_css("[data-vs-expiry-pnl]")["class"]).to include("vs-tone-loss")
    end

    it "反推 IV 失敗：平倉部分顯示固定訊息，到期損益照常" do
      frag = render_payoff(payoff_for(target_price: "200", long_bid: "49", long_ask: "51", long_price: "50"))
      expect(frag.text).to start_with("→ 無法反推 IV，平倉損益不可用｜到期損益 ")
    end

    it "early_assignment_risk：顯示固定警示文字" do
      frag = render_payoff(payoff_for(target_price: "250", dividend_annual: "1"))
      expect(frag.text).to include("賣出腳為價內且標的有配息，到期前可能在除息前被提前指派")
      expect(render_payoff(payoff_for(target_price: "200", dividend_annual: "1")).text).not_to include("提前指派")
    end

    it "nil：空白；錯誤：紅字訊息" do
      expect(render_payoff(nil).text).to eq("")
      expect(render_payoff({ error: "預估股價格式錯誤：abc" }).at_css(".vs-tone-loss").text)
        .to eq("預估股價格式錯誤：abc")
    end
  end

  # tasks/leaps-vertical-fix.md S3：FX-1（LC 100 74.95／79.05、SC 240 29.70／33.70、S₀ 150、費用 0、q 0）。
  describe "S3 雙基準與平倉日（FX-1）" do
    let(:fx1_chain) do
      { status: :ok, symbol: "ORCL", spot: d(150), expirations: [
        { expiry: "2028-12-15-m", dte: 807, fetched_at: Time.zone.parse("2026-09-30 14:00 UTC"),
          calls: [ quote(100, bid: "74.95", ask: "79.05", delta: 0.84), quote(240, bid: "29.70", ask: "33.70", delta: 0.5) ] }
      ] }
    end

    before do
      allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0"))
      Fundamental.create!(symbol: "ORCL", snapshot_date: Date.new(2026, 9, 30), fetched_at: Time.current, dividend_annual: 0)
    end

    def fx1_html(chain: fx1_chain, **params) = render_html(outcome: outcome_for(chain, **params))

    def card(html, key) = html.at_css("[data-vs-tour-anchor='#{key}']")

    it "五張卡同時出現 mid 與保守的數值（S1 表格）" do
      html = fx1_html
      {
        net_cost: [ "$4,530.00", "保守 $4,935.00" ], max_profit: [ "$9,470.00", "保守 $9,065.00" ],
        max_loss: [ "$4,530.00", "保守 $4,935.00" ], breakeven: [ "$145.30", "保守 $149.35" ],
        risk_reward: [ "1 : 2.09", "保守 1 : 1.84" ]
      }.each do |key, (mid, nat)|
        expect(card(html, key).at_css("[data-vs-value]").text).to eq(mid)
        expect(card(html, key).at_css("[data-vs-conservative]").text).to eq(nat)
      end
      expect(card(html, :width).at_css("[data-vs-conservative]")).to be_nil
    end

    it "口數 2 → 淨成本卡 $9,060.00，口數欄的值是 2" do
      html = fx1_html(contracts: "2")
      expect(card(html, :net_cost).at_css("[data-vs-value]").text).to eq("$9,060.00")
      expect(html.at_css("input[name='contracts']")["value"]).to eq("2")
    end

    it "口數欄：預設 1、只接受正整數" do
      input = fx1_html.at_css("form[data-vs-form] input[name='contracts']")
      expect(input.to_h.slice("type", "min", "step", "value")).to eq("type" => "number", "min" => "1", "step" => "1", "value" => "1")
      expect(fx1_html(contracts: "0").text).to include("口數須為正整數：0")
    end

    it "保守淨成本 ≥ 寬度：最大獲利卡顯示「保守成交下無獲利空間」" do
      chain = fx1_chain.deep_dup
      chain[:expirations][0][:calls] = [ quote(100, bid: "74.95", ask: "160", delta: 0.84),
                                         quote(240, bid: "10", ask: "33.70", delta: 0.5) ]
      html = fx1_html(chain: chain)
      expect(card(html, :max_profit).text).to include("保守成交下無獲利空間")
    end

    it "平倉日欄：預設報價日，範圍報價日～到期日；IV 調整欄：預設 0，−50～+50" do
      html = fx1_html
      expect(html.at_css("input[data-vs-close-date]").to_h.slice("type", "value", "min", "max"))
        .to eq("type" => "date", "value" => "2026-09-30", "min" => "2026-09-30", "max" => "2028-12-15")
      expect(html.at_css("input[data-vs-iv-shift]").to_h.slice("type", "value", "min", "max"))
        .to eq("type" => "number", "value" => "0", "min" => "-50", "max" => "50")
    end

    it "兩腳選單旁顯示反推的 IV" do
      html = fx1_html
      expect(html.at_css("[data-vs-tour-anchor='long_leg'] [data-vs-iv]").text).to eq("IV 60.9%")
      expect(html.at_css("[data-vs-tour-anchor='short_leg'] [data-vs-iv]").text).to eq("IV 57.3%")
    end

    it "反推 IV 失敗：顯示固定訊息，其他欄位照常" do
      chain = fx1_chain.deep_dup
      chain[:expirations][0][:calls][0] = quote(100, bid: 49, ask: 51, delta: 0.84)
      html = fx1_html(chain: chain)
      expect(html.at_css("[data-vs-payoff]").text).to include("無法反推 IV，平倉損益不可用")
      expect(card(html, :net_cost).at_css("[data-vs-value]").text).to eq("$1,830.00")
    end

    it "ⓘ 說明文字與常駐提示（固定文字）" do
      html = fx1_html
      expect(html.at_css("[data-vs-close-out-tip]")["title"]).to eq(
        "理論值：以報價時兩腳中間價反推 IV，並假設各履約價的 IV 維持不變。股價大幅變動時 IV skew 會移動，" \
        "實際平倉價可能與理論值有偏差，可用 IV 調整欄做情境測試。實際成交以買賣價為準。"
      )
      expect(html.at_css("[data-vs-expiry-hint]").text)
        .to eq("到期時若股價介於兩履約價之間，買入腳會自動履約、需付款買股；建議到期前平倉")
    end

    it "stale_quote：兩個 chain 爬取時間差 16 分鐘 → 固定警示" do
      chain = fx1_chain.deep_dup
      chain[:expirations] << { expiry: "2029-01-19-m", dte: 842, fetched_at: Time.zone.parse("2026-09-30 14:16 UTC"),
                               calls: [ quote(100, bid: 77, ask: 78, delta: 0.84) ] }
      html = fx1_html(chain: chain, expiry: "2028-12-15-m")
      expect(html.at_css("[data-vs-flag='stale_quote']").text).to eq("股價與期權報價時間不一致，IV 與平倉損益可能失真")
      expect(fx1_html.at_css("[data-vs-flag]")).to be_nil
    end

    it "五張卡的 ⓘ 末尾補口數與費用說明（算式維持每口、不含費用）；價差寬度不補" do
      html = fx1_html(contracts: "2")
      note = "以上算式以 1 口、不含費用計算；卡片數字為 2 口，並計入每口每腳 $0.00 的監管費。"
      %i[net_cost max_profit max_loss breakeven risk_reward].each do |key|
        expect(JSON.parse(card(html, key)["data-tip-lines"]).last).to eq(note)
      end
      expect(JSON.parse(card(html, :width)["data-tip-lines"])).not_to include(note)
    end

    it "S4：賣出腳 Δ 0.50 → 選單下方提示偏離；沒有 Δ 資料 → 不提示" do
      html = fx1_html
      hint = html.at_css("[data-vs-tour-anchor='short_leg'] [data-vs-delta-deviation]")
      expect(hint.text).to eq("目前 Δ 0.50，偏離建議值 0.30")

      chain = fx1_chain.deep_dup
      chain[:expirations][0][:calls][1] = quote(240, bid: "29.70", ask: "33.70")
      expect(fx1_html(chain: chain).at_css("[data-vs-delta-deviation]")).to be_nil
    end

    it "dividend_unknown：沒有股息資料 → 固定警示" do
      Fundamental.delete_all
      expect(fx1_html.at_css("[data-vs-flag='dividend_unknown']").text).to eq("未取得股息資料，以無股息計算")
    end
  end

  it "載入中：進度條與進度文字，沒有任何計算數字" do
    html = render_html(state: :loading)

    expect(html.at_css("[data-vs-progress]")).to be_present
    expect(html.at_css("[data-vs-progress-text]").text).to include("讀取 Barchart 報價中")
    expect(html.text).not_to include("實付淨成本")
  end

  it "錯誤（功能定義 6）：紅字訊息，沒有任何計算數字" do
    html = render_html(outcome: outcome_for(chain, long_strike: "101.37"))

    expect(html.at_css(".bg-red-50").text).to include("ORCL 的 LEAPS 中查無履約價 101.37")
    expect(html.text).not_to include("實付淨成本")
    expect(html.at_css("[data-vs-retry]")).to be_nil
  end

  it "讀取失敗：紅字加重試按鈕，沒有任何計算數字" do
    html = render_html(outcome: outcome_for({ status: :error, code: :stalled,
                                              message: "讀取 2028-01-21 chain 超過 30 秒沒有回應" }))

    expect(html.at_css(".bg-red-50").text).to include("Barchart 讀取失敗：讀取 2028-01-21 chain 超過 30 秒沒有回應")
    expect(html.at_css("[data-vs-retry]").text).to eq("重試")
    expect(html.text).not_to include("實付淨成本")
  end

  it "CDP 離線：顯示訊息與重試" do
    html = render_html(state: :cdp_offline, message: CdpPrecheckable::CDP_OFFLINE_MESSAGE)

    expect(html.text).to include("CDP 未連線")
    expect(html.at_css("[data-vs-retry]")).to be_present
  end
end

# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P5：/leaps 的 IV 環境區塊。數字一律來自 LeapsIvEnvironmentService#call 的回傳值，
# 這裡直接給元件一份同形狀的 hash，元件只負責呈現。
RSpec.describe LeapsRecommendations::IvEnvironmentSection do
  let(:as_of) { Date.new(2026, 11, 6) }

  # 兩個到期日：440 天在 1.00 欄沒有點（atm_iv nil 的那一個）、587 天點齊
  let(:surface) do
    [
      { expiration: Date.new(2028, 1, 21), dte: 440, moneyness: 0.70, call_iv: 0.47 },
      { expiration: Date.new(2028, 1, 21), dte: 440, moneyness: 0.744, call_iv: 0.46 }, # 0.75 欄（差 0.006）
      { expiration: Date.new(2028, 1, 21), dte: 440, moneyness: 0.77, call_iv: 0.45 },  # 0.75 欄較遠的點，不取
      { expiration: Date.new(2028, 6, 16), dte: 587, moneyness: 0.60, call_iv: 0.50 },
      { expiration: Date.new(2028, 6, 16), dte: 587, moneyness: 1.00, call_iv: 0.42 },
      { expiration: Date.new(2028, 6, 16), dte: 587, moneyness: 1.25, call_iv: 0.40 }
    ]
  end

  let(:barchart) do
    { trade_date: as_of, imp_vol: 0.3951, iv_rank: 82.44, iv_pctl: 91.0, hv: 0.2836, hv_label: "HV 30 天",
      history: [
        { trade_date: as_of - 1, imp_vol: 0.38, iv_rank: 75.1, last_price: 353.1 },
        { trade_date: as_of, imp_vol: 0.3951, iv_rank: 82.44, last_price: 375.44 }
      ] }
  end

  let(:env) do
    { as_of_date: as_of, cm540: 0.42085, rank: 37.5, percentile: 41.2, history_count: 60, status: :ok,
      term_structure: [
        { expiration: Date.new(2027, 12, 17), dte: 405, atm_iv: 0.41429 },
        { expiration: Date.new(2028, 1, 21), dte: 440, atm_iv: nil },
        { expiration: Date.new(2028, 6, 16), dte: 587, atm_iv: 0.42271 }
      ],
      surface: surface, barchart: barchart, spot: 375.44,
      captured_at: Time.zone.parse("2026-11-07 06:01:07 UTC"), source: "scheduled",
      source_url: "https://www.barchart.com/stocks/quotes/TSM/options" }
  end

  let(:near_pick) { { strike: 350.0, expiration_date: "2027-12-17", vega: 1.2314 } }
  let(:html) { render_html }
  let(:root) { html.at_css("details#leaps-iv-environment") }

  def render_html(env: self.env, near_pick: self.near_pick)
    Nokogiri::HTML.fragment(described_class.new(symbol: "TSM", env: env, near_pick: near_pick).call)
  end


  describe "外殼（沿用 pc-card）" do
    it "根元素是 details#leaps-iv-environment.pc-card，沒有 open 屬性（預設收合）" do
      expect(root).to be_present
      expect(root["class"].split).to include("pc-card", "bg-white", "rounded-2xl", "border", "border-gray-200",
                                             "shadow-sm", "flex", "flex-col")
      expect(root.key?("open")).to be(false)
    end

    it "summary 有標題、副標與摘要文字" do
      summary = root.at_css("> summary.pc-summary")
      expect(summary.at_css("h3.pc-title").text).to eq("IV 環境 · TSM")
      expect(summary.at_css("p.pc-sub").text).to eq("LEAPS 天期 IV Rank ＋ Barchart 參考")
      expect(summary.text).to include("Barchart IV Rank 82 · ATM IV（540 天）42.1%")
    end

    it "ivenv_overview 掛在 summary 內標題旁的 ⓘ，不掛在整條 summary（使用者裁示）" do
      summary = root.at_css("> summary")
      expect(summary["data-tip-key"]).to be_nil
      expect(summary.at_css("[data-tip-key='ivenv_overview']").text).to eq("ⓘ")
    end

    it "累積中時摘要的 LEAPS 部分顯示「累積中 n/252」" do
      summary = render_html(env: env.merge(status: :accumulating, rank: nil, percentile: nil, history_count: 7))
                .at_css("summary")
      expect(summary.text).to include("Barchart IV Rank 82", "累積中 7/252")
    end
  end

  describe "名詞 tooltip" do
    it "名詞表 14 個 key 各至少出現一次 data-tip-key" do
      keys = %w[ivenv_overview ivenv_leaps_rank ivenv_leaps_pct ivenv_cm540 ivenv_accumulating ivenv_bc_rank
                ivenv_bc_pctl ivenv_bc_iv ivenv_bc_hv ivenv_bc_trend ivenv_term ivenv_surface ivenv_moneyness ivenv_meta]
      keys.each { |k| expect(html.css("[data-tip-key='#{k}']")).not_to be_empty, "缺 #{k}" }
    end

    it "有數值的徽章帶 data-tip-value" do
      expect(html.at_css("[data-tip-key='ivenv_bc_rank']")["data-tip-value"]).to eq("Barchart IV Rank 82.44")
      expect(html.at_css("[data-tip-key='ivenv_cm540']")["data-tip-value"]).to eq("ATM IV（540 天）42.1%")
    end

    it "近天期 Vega 1.2314 → ivenv_leaps_rank 的 data-tip-lines 第二句為「IV 每下降 5 點，每口約損失 $616」" do
      lines = JSON.parse(html.at_css("[data-tip-key='ivenv_leaps_rank']")["data-tip-lines"])
      expect(lines).to eq([ "以推薦近天期 350 / 2027-12-17（Vega 1.2314）計算", "IV 每下降 5 點，每口約損失 $616" ])
    end

    it "Vega 為 nil 或沒有近天期推薦時沒有 data-tip-lines 屬性" do
      [ near_pick.merge(vega: nil), nil ].each do |pick|
        el = render_html(near_pick: pick).at_css("[data-tip-key='ivenv_leaps_rank']")
        expect(el.key?("data-tip-lines")).to be(false)
      end
    end
  end

  describe "徽章列" do
    it "LEAPS 組：Rank、Percentile、ATM IV（540 天）；Barchart 組另列並標天期說明" do
      expect(html.at_css("[data-tip-key='ivenv_leaps_rank']").text).to include("38")
      expect(html.at_css("[data-tip-key='ivenv_leaps_pct']").text).to include("41")
      expect(html.text).to include("Barchart 參考（天期依頁面定義）")
      expect(html.at_css("[data-tip-key='ivenv_bc_iv']").text).to include("39.5%")
      expect(html.at_css("[data-tip-key='ivenv_bc_hv']").text).to include("28.4%", "HV 30 天")
      expect(html.at_css("[data-tip-key='ivenv_bc_pctl']").text).to include("91")
    end

    it ":accumulating 顯示「資料累積中 n/252 天」，Rank／Percentile 不顯示 0 或空白" do
      doc = render_html(env: env.merge(status: :accumulating, rank: nil, percentile: nil, history_count: 7))
      expect(doc.at_css("[data-tip-key='ivenv_accumulating']").text).to include("資料累積中 7/252 天")
      %w[ivenv_leaps_rank ivenv_leaps_pct].each do |k|
        value = doc.at_css("[data-tip-key='#{k}'] [data-ivenv-value]").text.strip
        expect(value).not_to be_empty
        expect(value).not_to eq("0")
      end
    end

    it ":no_data 顯示「尚無 IV 資料，請按查詢」，摘要也不是空白" do
      no_data = { as_of_date: nil, cm540: nil, rank: nil, percentile: nil, history_count: 0, status: :no_data,
                  term_structure: [], surface: [], barchart: nil, spot: nil, captured_at: nil, source: nil, source_url: nil }
      doc = render_html(env: no_data)
      expect(doc.at_css("summary").text).to include("尚無 IV 資料，請按查詢")
      expect(doc.text).to include("尚無 IV 資料，請按查詢")
      expect(doc.css("canvas")).to be_empty
    end

    it "讀取失敗（:error）照實顯示失敗，不假裝「尚無資料」" do
      doc = render_html(env: { status: :error })
      expect(doc.at_css("summary").text).to include("讀取失敗")
      expect(doc.text).to include("IV 環境資料讀取失敗")
      expect(doc.text).not_to include("尚無 IV 資料")
    end

    it "cm540 為 nil、Barchart 沒資料時顯示「—」，不顯示 0" do
      doc = render_html(env: env.merge(cm540: nil, rank: nil, percentile: nil, barchart: nil))
      expect(doc.at_css("summary").text).to include("Barchart IV Rank — · ATM IV（540 天）—")
      expect(doc.at_css("[data-tip-key='ivenv_cm540'] [data-ivenv-value]").text).to eq("—")
    end
  end

  describe "IV 曲面熱圖" do
    let(:table) { html.at_css("table[data-ivenv-heatmap]") }

    it "14 欄 moneyness 0.60, 0.65, …, 1.25（欄標題列帶 ivenv_moneyness）" do
      headers = table.css("thead th[data-ivenv-col]").map(&:text)
      expect(headers).to eq(%w[0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25])
      expect(table.at_css("thead tr[data-tip-key='ivenv_moneyness']")).to be_present
    end

    it "列依 DTE 由小到大；每格取 ±0.025 內最接近的點，沒有點顯示「—」" do
      rows = table.css("tbody tr")
      expect(rows.map { |r| r.at_css("th").text }).to eq([ "2028-01-21（440 天）", "2028-06-16（587 天）" ])
      cells = rows.first.css("td").map { |td| td.text.strip }
      expect(cells.size).to eq(14)
      expect(cells[2]).to eq("47.0%")  # 0.70
      expect(cells[3]).to eq("46.0%")  # 0.75 取 0.744，不取 0.77
      expect(cells[0]).to eq("—")
      expect(cells[8]).to eq("—")      # 1.00 沒有點
    end

    it "色階依表內 IV 最小→最大線性對應：最低最淺、最高最深；最接近現價的一欄（1.00）加橘框" do
      cells = table.css("tbody td[data-accent-bg]")
      by_iv = cells.to_h { |td| [ td.text.strip, td["data-accent-bg"] ] }
      expect(by_iv["40.0%"]).to eq(described_class::HEAT_LOW)
      expect(by_iv["50.0%"]).to eq(described_class::HEAT_HIGH)
      expect(table.css("tbody tr").last.css("td")[8]["class"]).to include("ivenv-atm-col")
    end
  end

  # P5.1（使用者裁示）：PMCC 短天期點不參與色階、排在 LEAPS 列之後；期限結構只畫 LEAPS 段
  describe "短天期點的呈現（P5.1）" do
    let(:short_exp) { Date.new(2026, 11, 27) }
    let(:with_short) do
      short = [ { expiration: short_exp, dte: 20, moneyness: 0.65, call_iv: 0.90 },
                { expiration: short_exp, dte: 20, moneyness: 1.00, call_iv: 0.50 } ]
      term = env[:term_structure] + [ { expiration: short_exp, dte: 20, atm_iv: 0.50 } ]
      env.merge(surface: short + surface, term_structure: term)
    end
    let(:doc) { render_html(env: with_short) }
    let(:table) { doc.at_css("table[data-ivenv-heatmap]") }

    it "色階只依 LEAPS 列：LEAPS 最高 IV＝HEAT_HIGH、最低＝HEAT_LOW；短天期格不上色但照常顯示數字" do
      leaps = table.css("tbody tr[data-ivenv-row='leaps'] td[data-accent-bg]").to_h { |td| [ td.text.strip, td["data-accent-bg"] ] }
      expect(leaps["50.0%"]).to eq(described_class::HEAT_HIGH)
      expect(leaps["40.0%"]).to eq(described_class::HEAT_LOW)

      short_cells = table.css("tbody tr[data-ivenv-row='short'] td")
      expect(short_cells.map { |td| td.text.strip }).to include("90.0%", "50.0%")
      expect(short_cells.select { |td| td["data-accent-bg"] }).to be_empty
    end

    it "短天期列在分隔標題之後、所有 LEAPS 列之後" do
      kinds = table.css("tbody tr").map { |tr| tr["data-ivenv-row"] }
      expect(kinds).to eq(%w[leaps leaps divider short])
      expect(table.at_css("tbody tr[data-ivenv-row='divider']").text).to include("PMCC 短天期（參考，不上色）")
      expect(table.at_css("tbody tr[data-ivenv-row='short'] th").text).to eq("2026-11-27（20 天）")
    end

    it "期限結構資料不含 DTE < 364 的點" do
      points = JSON.parse(doc.at_css("canvas[data-ivenv-chart='term']")["data-ivenv-points"])
      expect(points.map { |p| p["x"] }).to eq([ 405, 587 ])
    end

    it "沒有短天期時沒有分隔標題" do
      expect(html.at_css("tbody tr[data-ivenv-row='divider']")).to be_nil
    end
  end

  describe "圖表與資料資訊" do
    it "期限結構資料只含 atm_iv 不為 nil 的到期日" do
      points = JSON.parse(html.at_css("canvas[data-ivenv-chart='term']")["data-ivenv-points"])
      expect(points.map { |p| p["x"] }).to eq([ 405, 587 ])
      expect(points.first["y"]).to eq(41.43)
    end

    it "Barchart IV Rank 走勢：IV Rank 與股價兩組資料，標「Barchart 30 天天期」" do
      canvas = html.at_css("canvas[data-ivenv-chart='barchart']")
      data = JSON.parse(canvas["data-ivenv-points"])
      expect(data["labels"]).to eq(%w[2026-11-05 2026-11-06])
      expect(data["rank"]).to eq([ 75.1, 82.44 ])
      expect(data["price"]).to eq([ 353.1, 375.44 ])
      expect(html.text).to include("Barchart 30 天天期")
    end

    it "底部顯示 as_of_date（美東）、captured_at（台北）、source、來源 URL" do
      meta = html.at_css("[data-tip-key='ivenv_meta']")
      expect(meta.text).to include("2026-11-06（美東）", "2026-11-07 14:01（台北）", "scheduled")
      expect(meta.at_css("a")["href"]).to eq("https://www.barchart.com/stocks/quotes/TSM/options")
    end

    it "「更新中」標記預設隱藏，查詢送出時由 leapsLoading 顯示" do
      expect(html.at_css("[data-ivenv-updating]")["class"]).to include("hidden")
    end
  end
end

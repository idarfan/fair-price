# frozen_string_literal: true

# /leaps 伺服器 HTML 的回歸比對（leaps-call-spread-spec P3 案例 9）。
#
# 基準在「加入垂直價差之前」的程式碼上擷取（spec/fixtures/leaps_vertical_spread/server_baseline/），
# 比對時把新增的 #leaps_vertical_spread 外框拿掉，其餘必須一字不差。
# 每次請求都不同的值（CSRF token、CSP nonce）先移除；時間固定在 FROZEN_AT。
# 資源檔名的雜湊（behaviors-XXXXXXXX.js）也正規化：任何前端修改都會改變它，
# 與既有區塊的 HTML 無關（P3 在 behaviors 註冊表加一行，雜湊就變了）。基準檔保留
# 原始擷取內容，比對時兩邊都套 canonical（strip_digests＋crossorigin 同義寫法）。
module LeapsPageHtml
  FROZEN_AT = Time.zone.parse("2026-09-25 12:00:00")
  BASELINE_DIR = Rails.root.join("spec/fixtures/leaps_vertical_spread/server_baseline")

  CASES = {
    "a_empty"           => { params: {} },
    "b_symbol_only"     => { params: { symbol: "ORCL" } },
    "c_symbol_strike"   => { params: { symbol: "ORCL", user_strike: "100" } },
    "d_invalid_strike"  => { params: { symbol: "ORCL", user_strike: "abc" } },
    "e_with_candidates" => { params: { symbol: "NOK", user_strike: "10" }, candidates: true }
  }.freeze

  module_function

  def normalize(body)
    doc = Nokogiri::HTML(body)
    doc.css("#leaps_vertical_spread").each(&:remove)
    doc.css('meta[name="csrf-token"]').each { |n| n["content"] = "CSRF" }
    doc.css('meta[name="csp-nonce"]').each { |n| n["content"] = "NONCE" }
    doc.css('input[name="authenticity_token"]').each { |n| n["value"] = "CSRF" }
    doc.css("[data-csrf]").each { |n| n["data-csrf"] = "CSRF" }
    doc.css("[nonce]").each { |n| n["nonce"] = "NONCE" }
    mask_release_notes(doc)
    strip_poll_timeout(doc)
    canonical(doc.to_html)
  end

  # 2026-10-01 價格情境輪詢根節點新增 data-poll-timeout-ms（前端輪詢上限，
  # 跟 ScrapePriceContextJob 的最長時間同源），與垂直價差無關。
  # 值的正確性由 spec/requests/leaps_price_context_spec.rb 驗證。
  def strip_poll_timeout(doc)
    doc.css("#leaps-price-context[data-poll-timeout-ms]").each { |n| n.remove_attribute("data-poll-timeout-ms") }
  end

  # 全站 layout 的版本號與「版本更新說明」內容每次發版都會變（config/initializers/release_notes.rb），
  # 與 /leaps 既有區塊無關：版本號換成固定字串、說明視窗的內容清空（外框保留）。
  def mask_release_notes(doc)
    doc.css("[data-app-version], .release-notes-version").each { |n| n.content = "VERSION" }
    doc.css("#release-notes-overlay .release-notes-panel").each { |n| n.children.each(&:remove) }
  end

  # Vite 的雜湊是 base64url，可能含「-」（例如 behaviors-DaqtVP-V.js）。
  DIGEST = /-[A-Za-z0-9_-]{8}(?=\.(?:js|css)\b)/

  # vite_rails 3.10 起 vite 標籤輸出 crossorigin=""（基準擷取時是 crossorigin="anonymous"）。
  # 依 HTML 規範，空字串與 "anonymous" 同為 Anonymous 狀態，瀏覽器行為相同，只是寫法不同。
  CROSSORIGIN_ANONYMOUS = 'crossorigin="anonymous"'

  def canonical(html) = strip_digests(html).gsub(CROSSORIGIN_ANONYMOUS, 'crossorigin=""')

  def strip_digests(html) = html.gsub(DIGEST, "-DIGEST")

  def baseline_path(name) = BASELINE_DIR.join("#{name}.html")

  # 基準檔擷取時已經過 normalize；再套一次，讓版本號遮蔽等後來新增的規則也作用在基準上。
  def read_baseline(name) = normalize(File.read(baseline_path(name)))

  # 「有候選」情境：沿用 spec/requests/leaps_recommendations_spec.rb 的做法，stub 掉資料層。
  def stub_candidates!(example_group, symbol)
    candidate = {
      expiration_date: Date.new(2027, 12, 17), dte: 448, strike: 10.0, delta: 0.78,
      open_interest: 72_921, volume: 431, bid: 3.10, ask: 3.30, mid: 3.20, iv: 0.76, vega: 0.0134,
      itm_probability: 0.82, vol_oi_ratio: 0.006, underlying_price: 13.08, liquidity_tier: "充足",
      no_recent_volume_warning: false, time_value_pct: 0.025, bid_ask_spread_pct: 0.062
    }
    flow = { status: :ok, date: Date.current, call_premium_total: 500_000, put_premium_total: 200_000,
             large_orders: [], highlighted_trades: [], aggregate: {} }

    example_group.instance_exec do
      allow(LeapsOptionChainSnapshot).to receive(:fresh_for?).and_return(true)
      allow(LeapsRankingService).to receive(:new).with(symbol)
        .and_return(instance_double(LeapsRankingService, call: [ candidate ]))
      allow(LeapsOptionsFlowPanelService).to receive(:new)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: flow))
    end
  end
end

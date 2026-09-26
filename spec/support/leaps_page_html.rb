# frozen_string_literal: true

# /leaps 伺服器 HTML 的回歸比對（leaps-call-spread-spec P3 案例 9）。
#
# 基準在「加入垂直價差之前」的程式碼上擷取（spec/fixtures/leaps_vertical_spread/server_baseline/），
# 比對時把新增的 #leaps_vertical_spread 外框拿掉，其餘必須一字不差。
# 每次請求都不同的值（CSRF token、CSP nonce）先移除；時間固定在 FROZEN_AT。
# 資源檔名的雜湊（behaviors-XXXXXXXX.js）也正規化：任何前端修改都會改變它，
# 與既有區塊的 HTML 無關（P3 在 behaviors 註冊表加一行，雜湊就變了）。基準檔保留
# 原始擷取內容，比對時兩邊都套 strip_digests。
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
    strip_digests(doc.to_html)
  end

  # Vite 的雜湊是 base64url，可能含「-」（例如 behaviors-DaqtVP-V.js）。
  DIGEST = /-[A-Za-z0-9_-]{8}(?=\.(?:js|css)\b)/

  def strip_digests(html) = html.gsub(DIGEST, "-DIGEST")

  def baseline_path(name) = BASELINE_DIR.join("#{name}.html")

  def read_baseline(name) = strip_digests(File.read(baseline_path(name)))

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

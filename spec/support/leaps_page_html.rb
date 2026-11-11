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
    "e_with_candidates" => { params: { symbol: "NOK", user_strike: "10" }, candidates: true },
    # leaps-best-value-card-style S1（使用者 2026-11-11 指示新增）：a–e 都沒有「最划算」卡，
    # 左卡結構不在回歸保護範圍內。用 leaps-best-value 驗收基準的 11 筆真快照（不 stub 服務），
    # 讓左右兩卡同時出現。
    "f_with_best_value" => { params: { symbol: "NVDA" }, best_value: true }
  }.freeze

  # leaps-best-value 驗收基準資料（2026-11-09 NVDA，S = 186.64）：到期, DTE, K, Delta, Bid, Ask, OI, Vol。
  # 與 spec/requests/leaps_recommendations_spec.rb「最划算推薦接線」describe 的 baseline 相同。
  BEST_VALUE_ROWS = [
    [ "2028-01-21", 440, 120, 0.8710, 79.10, 80.50,  2069,  18 ],
    [ "2028-01-21", 440, 125, 0.8569, 75.40, 76.85,   634,  10 ],
    [ "2028-01-21", 440, 130, 0.8417, 72.00, 73.20,  2264, 160 ],
    [ "2028-01-21", 440, 140, 0.8092, 65.40, 66.25,  4163, 191 ],
    [ "2028-01-21", 440, 180, 0.6562, 42.00, 42.50, 14764, 724 ],
    [ "2027-12-17", 405, 130, 0.8453, 70.65, 72.10,  7565,  22 ],
    [ "2028-06-16", 587, 140, 0.8042, 69.60, 71.25,   499,  13 ],
    [ "2028-12-15", 769, 120, 0.8540, 87.40, 89.65,  6168,   6 ],
    [ "2028-12-15", 769, 140, 0.8047, 74.60, 76.15,  4898,  60 ],
    [ "2029-01-19", 804, 120, 0.8530, 88.25, 90.50,   221,   5 ],
    [ "2029-01-19", 804, 140, 0.8045, 75.80, 77.00,   502, 107 ]
  ].freeze

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
    strip_build_rules_note(doc)
    strip_strike_hint(doc)
    strip_hall_of_fame_entry(doc)
    strip_iv_environment(doc)
    canonical(doc.to_html)
  end

  # 2026-11-07 /leaps 新增 IV 環境區塊（leaps-iv-environment P5，使用者裁示例外更新本檔），與既有區塊無關。
  # 內容由 spec/components/leaps_recommendations/iv_environment_section_spec.rb 與
  # spec/requests/leaps_recommendations_spec.rb 的「IV 環境區塊（P5）」驗證。
  def strip_iv_environment(doc)
    doc.css("#leaps-iv-environment").each do |node|
      # 同 strip_build_rules_note：區塊前面的換行文字節點一起拿掉，兩邊才一致。
      node.previous_sibling.remove if node.previous_sibling&.text? && node.previous_sibling.text.strip.empty?
      node.remove
    end
  end

  # 2026-10-18 sidebar 最末位新增「投資名人堂」（hall-of-fame-spec P5-4，使用者裁示例外更新本檔）。
  # 分隔線固定畫在倒數第二項之後，新增一列就會位移，所以兩邊都拿掉入口與分隔線；與 /leaps 既有區塊無關。
  # 入口本身由 spec/requests/hall_of_fame_spec.rb 驗證。
  def strip_hall_of_fame_entry(doc)
    doc.css('a[role="menuitem"][href="/hall_of_fame"]').each(&:remove)
    doc.css("div").select { |n| n["class"] == "mx-3 border-t border-gray-100" }.each do |divider|
      # 同 strip_build_rules_note：基準檔的分隔線後面跟著一個換行文字節點，一起拿掉兩邊才一致。
      divider.next_sibling.remove if divider.next_sibling&.text? && divider.next_sibling.text.strip.empty?
      divider.remove
    end
  end

  # 2026-10-12 搜尋表單新增履約價提示（未填履約價時不顯示垂直價差區塊），與既有區塊無關。
  # 內容由 spec/requests/leaps_recommendations_spec.rb 的履約價提示測試驗證。
  def strip_strike_hint(doc)
    doc.css("#leaps-strike-hint").each(&:remove)
  end

  # 2026-10-10 另案 3：建倉規範卡底下那行說明從「本表抓 DTE 60 天以內…」改成
  # 「本表只列 Short DTE 19–45 天…」（Short DTE 由標記改為篩選），與垂直價差無關。
  # 概念卡第 3 點同理（審查 r1 問題 2：「60 天內到期日」改讀常數），只遮蔽文字、保留節點。
  # 內容由 spec/requests/leaps_recommendations_spec.rb 的建倉規範卡測試驗證。
  # 審查 r1 質詢 2：只動 .pmcc-edu-root 內的這兩處，別的「本表…」段落（concept_cards 等）照常比對。
  def strip_build_rules_note(doc)
    doc.css(".pmcc-edu-root p").select { |p| p.text.start_with?("本表抓 DTE", "本表只列 Short DTE") }.each do |p|
      # 基準檔是排版過的 HTML，說明後面跟著一個換行文字節點；一起拿掉，兩邊才一致。
      p.next_sibling.remove if p.next_sibling&.text? && p.next_sibling.text.strip.empty?
      p.remove
    end
    doc.css(".pmcc-edu-root span").select { |s| s.text.start_with?("短期虛值 SC：") }.each do |s|
      s.content = "SHORT_CALL_RULE"
    end
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

  # 各情境請求前的準備：candidates → stub 資料層；best_value → 寫入 11 筆真快照。
  def prepare!(example_group, spec)
    stub_candidates!(example_group, spec[:params][:symbol]) if spec[:candidates]
    seed_best_value!(spec[:params][:symbol]) if spec[:best_value]
  end

  # 寫入驗收基準快照（同一批 scraped_at），交易式 fixture 會在案例結束時回滾。
  def seed_best_value!(symbol)
    scraped_at = Time.current
    BEST_VALUE_ROWS.each do |exp, dte, strike, delta, bid, ask, oi, vol|
      FactoryBot.create(:leaps_option_chain_snapshot,
                        symbol: symbol, expiration_date: Date.parse(exp), dte: dte, strike: strike, delta: delta,
                        bid: bid, ask: ask, open_interest: oi, volume: vol, vol_oi_ratio: (vol.to_f / oi).round(4),
                        underlying_price: 186.64, scraped_at: scraped_at)
    end
  end

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
        .and_return(instance_double(LeapsRankingService, call: [ candidate ], all_zero_volume?: false))
      allow(LeapsOptionsFlowPanelService).to receive(:new)
        .and_return(instance_double(LeapsOptionsFlowPanelService, call: flow))
    end
  end
end

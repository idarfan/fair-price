# frozen_string_literal: true

require "rails_helper"

# tasks/leaps-vertical-fix.md S3：真的開瀏覽器，注入 FX-1，斷言 DOM 文字。
# FX-1：報價日 2026-09-30、到期日 2028-12-15、S₀ 150、LC 100 74.95／79.05、SC 240 29.70／33.70、
# 1 口、費用 0、q 0。sidecar 一律換成替身，不連 Barchart。
RSpec.describe "LEAPS 垂直價差卡片（S3）", type: :system do
  let(:totp_secret) { AuthHelpers::DEFAULT_TOTP_SECRET }
  let(:fx1_expiration) do
    { expiry: "2028-12-15-m", dte: 807, fetched_at: Time.zone.parse("2026-09-30 14:00 UTC"),
      calls: [ quote(100, bid: "74.95", ask: "79.05", delta: "0.84"), quote(240, bid: "29.70", ask: "33.70", delta: "0.5") ] }
  end
  let(:expirations) { [ fx1_expiration ] }
  let(:user) { FactoryBot.create(:user, status: :enabled, totp_enabled: true, totp_secret: totp_secret) }

  def d(value) = BigDecimal(value.to_s)

  def quote(strike, bid:, ask:, delta:)
    { strike: d(strike), bid: d(bid), ask: d(ask), last: nil, delta: d(delta) }
  end


  around do |example|
    # /leaps 頁的其他區塊可能排入抓取工作；system spec 一律只排隊不執行。
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  before do
    chain = { status: :ok, symbol: "ORCL", spot: d(150), expirations: expirations }
    allow(LeapsCallChainFetcher).to receive(:new).and_return(instance_double(LeapsCallChainFetcher, call: chain))
    allow(LeapsRankingService).to receive(:new).and_return(instance_double(LeapsRankingService, call: []))
    allow_any_instance_of(LeapsRecommendationsController).to receive(:cdp_online?).and_return(true)
    allow(LeapsVerticalSpreadService::Config).to receive(:fee_per_contract_leg).and_return(BigDecimal("0"))
    Fundamental.create!(symbol: "ORCL", snapshot_date: Date.new(2026, 9, 30), fetched_at: Time.current, dividend_annual: 0)

    sign_in_through_browser
    visit "/leaps?symbol=ORCL&user_strike=100"
    find("[data-vs-tour-anchor='net_cost'] [data-vs-value]") # 等區塊片段載入（find 會等待）
  end

  def sign_in_through_browser
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: user.google_uid, info: { email: user.email })
    visit "/auth/google_oauth2/callback"
    fill_in "code", with: ROTP::TOTP.new(totp_secret).now
    click_button "驗證"
    expect(page).to have_no_current_path("/two_factor/challenge")
  end

  def card(key) = find("[data-vs-tour-anchor='#{key}']")

  # date input 的鍵盤輸入格式隨語系而異，直接設值並發出 input 事件（與使用者選日期後的事件相同）。
  def set_input(selector, value)
    page.execute_script(<<~JS, selector, value)
      const el = document.querySelector(arguments[0]);
      el.value = arguments[1];
      el.dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end

  def close_pnl = find("[data-vs-close-pnl]").text
  def expiry_pnl = find("[data-vs-expiry-pnl]").text
  def money(text) = BigDecimal(text.delete("+$,"))

  it "五張卡同時出現 S1 表格中 mid 與保守的數值" do
    {
      net_cost: [ "$4,530.00", "保守 $4,935.00" ], max_profit: [ "$9,470.00", "保守 $9,065.00" ],
      max_loss: [ "$4,530.00", "保守 $4,935.00" ], breakeven: [ "$145.30", "保守 $149.35" ],
      risk_reward: [ "1 : 2.09", "保守 1 : 1.84" ]
    }.each do |key, (mid, conservative)|
      expect(card(key).find("[data-vs-value]")).to have_text(mid, exact: true)
      expect(card(key).find("[data-vs-conservative]")).to have_text(conservative, exact: true)
    end
  end

  it "預估股價 200：平倉日 = 到期日 → 平倉損益文字等於到期損益；平倉日 = 報價日 → 平倉損益 < 5,470" do
    fill_in "vs-target-price", with: "200"
    set_input("[data-vs-close-date]", "2028-12-15")
    expect(page).to have_css("[data-vs-close-pnl]", exact_text: "+$5,470.00")
    expect(close_pnl).to eq(expiry_pnl)

    set_input("[data-vs-close-date]", "2026-09-30")
    expect(page).to have_no_css("[data-vs-close-pnl]", exact_text: "+$5,470.00")
    expect(money(close_pnl)).to be < BigDecimal("5470")
    expect(money(close_pnl)).to be > 0
  end

  it "口數改為 2 → 淨成本卡顯示 $9,060.00" do
    find("input[name='contracts']").set("2").send_keys(:tab)
    expect(card(:net_cost).find("[data-vs-value]")).to have_text("$9,060.00", exact: true)
  end

  it "常駐提示文字完全等於規格第 11 點" do
    expect(find("[data-vs-expiry-hint]"))
      .to have_text("到期時若股價介於兩履約價之間，買入腳會自動履約、需付款買股；建議到期前平倉", exact: true)
  end

  it "S4：底部說明文字完全等於規格固定文字" do
    expect(find("[data-vs-note]")).to have_text(
      "需 Firstrade 選擇權 Level 3。價差單請用 Firstrade 網頁版一次成交兩腳；若只能單腳下單：" \
      "建倉先買入 LC 再賣出 SC，平倉先買回 SC 再賣出 LC，避免出現裸賣買權。最大獲利要到到期日才完整實現。",
      exact: true
    )
  end

  # S4：FX-1 加入 SC 候選 200（Δ 0.62）、260（Δ 0.31）、280（Δ 0.29）。
  context "S4 Δ 偏離提示" do
    let(:fx1_expiration) do
      { expiry: "2028-12-15-m", dte: 807, fetched_at: Time.zone.parse("2026-09-30 14:00 UTC"),
        calls: [ quote(100, bid: "74.95", ask: "79.05", delta: "0.84"), quote(200, bid: "40", ask: "42", delta: "0.62"),
                 quote(240, bid: "29.70", ask: "33.70", delta: "0.5"), quote(260, bid: "27", ask: "29", delta: "0.31"),
                 quote(280, bid: "24", ask: "26", delta: "0.29") ] }
    end

    def short_select = find("select[name='short_strike']")
    def hint_selector = "[data-vs-delta-deviation]"

    def choose_short(strike)
      short_select.find("option[value='#{strike}']").select_option
      expect(page).to have_css("select[name='short_strike'] option[value='#{strike}'][selected]")
    end

    it "預設選中 260（|Δ − 0.30| 與 280 同為 0.01，取較低履約價），不出現提示" do
      expect(short_select.value).to eq("260.00")
      expect(page).to have_no_css(hint_selector)
    end

    it "改選 240（Δ 0.50）→ 出現提示；改回 260 或 280 → 不出現" do
      choose_short("240.00")
      expect(page).to have_css(hint_selector, exact_text: "目前 Δ 0.50，偏離建議值 0.30")

      choose_short("280.00")
      expect(page).to have_no_css(hint_selector)

      choose_short("260.00")
      expect(page).to have_no_css(hint_selector)
    end
  end

  context "兩個 chain 的爬取時間相差 16 分鐘（注入 stale_quote）" do
    # 預設選有報價的最遠到期日（2029）；它比現價所屬的 FX-1 chain（14:00）早爬 16 分鐘。
    let(:expirations) do
      [ fx1_expiration,
        { expiry: "2029-01-19-m", dte: 842, fetched_at: Time.zone.parse("2026-09-30 13:44 UTC"),
          calls: [ quote(100, bid: 77, ask: 78, delta: "0.84"), quote(240, bid: 32, ask: 34, delta: "0.5") ] } ]
    end

    it "出現對應的警示文字" do
      expect(page).to have_css("[data-vs-flag='stale_quote']",
                               exact_text: "股價與期權報價時間不一致，IV 與平倉損益可能失真")
    end
  end
end

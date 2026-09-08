# frozen_string_literal: true

require "rails_helper"

RSpec.describe "期權小學堂教材頁", type: :request do
  # 2026-09-08 事故：教材頁整個版面消失。
  #
  # 原因是 CSP 標頭裡 style-src 同時有 'unsafe-inline' 與 'nonce-...'。
  # CSP 規範明訂：style-src 一旦出現 nonce，'unsafe-inline' 一律被瀏覽器忽略。
  # 教材頁是手寫靜態 HTML、內嵌樣式約 840 處，全部被擋掉——畫面上沒有任何
  # 錯誤訊息，只有 console 裡一長串 CSP 違規，所以極難聯想到是 CSP。
  describe "CSP style-src" do
    before { get "/csp/index.html" }

    it "回 200 並送出教材頁" do
      expect(response).to have_http_status(:ok)
    end

    it "放行內嵌樣式" do
      expect(csp_directive("style-src")).to include("'unsafe-inline'")
    end

    it "style-src 不得帶 nonce（帶了會讓 unsafe-inline 失效）" do
      expect(csp_directive("style-src")).not_to include("nonce-")
    end
  end

  # 這 12 頁共有 350 個內嵌事件屬性（onclick／oninput／onchange），
  # 朗讀、字級調整、名詞說明全靠它們。CSP 擋內嵌事件屬性，而 nonce 對它們
  # 無效（只對 <script> 區塊有效），所以只能靠 unsafe-inline。
  describe "CSP script-src" do
    before { get "/csp/option-basics-lesson9.html" }

    it "放行內嵌 script 與事件屬性" do
      expect(csp_directive("script-src")).to include("'unsafe-inline'")
    end

    it "script-src 不得帶 nonce（帶了會讓 unsafe-inline 失效）" do
      expect(csp_directive("script-src")).not_to include("nonce-")
    end

    it "教材頁確實含有內嵌事件屬性（回歸哨兵）" do
      expect(response.body).to match(/\son(?:click|input|change)="/)
    end
  end

  describe "應用程式本體不受影響" do
    # 分區的意義在於只放寬教材頁。本體一旦跟著鬆掉，這個例外就白開了。
    it "一般頁面的 script-src 仍不放行內嵌 script" do
      get "/price_in"
      directive = csp_directive("script-src")
      expect(directive).to include("nonce-")
      expect(directive).not_to include("'unsafe-inline'")
    end

    it "一般頁面的 style-src 仍不放行內嵌樣式" do
      get "/price_in"
      expect(csp_directive("style-src")).not_to include("'unsafe-inline'")
    end
  end

  describe "路徑穿越防護" do
    it "不允許跳出教材目錄" do
      get "/csp/../../config/database.yml"
      expect(response).not_to have_http_status(:ok)
    end
  end

  def csp_directive(name)
    response.headers["Content-Security-Policy"].to_s
            .split(";").map(&:strip)
            .find { |d| d.start_with?("#{name} ") }.to_s
  end
end

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

    # nonce 對 style="..." 屬性本來就無效，只對 <style> 區塊有效，
    # 因此把 style-src 移出 nonce 清單不損失防護；script-src 必須保留。
    it "script-src 仍然帶 nonce，且不放行內嵌 script" do
      expect(csp_directive("script-src")).to include("nonce-")
      expect(csp_directive("script-src")).not_to include("'unsafe-inline'")
    end
  end

  # 課程清單、拖曳排序、可編輯筆記全在內嵌 <script> 裡。script-src 不放行
  # unsafe_inline，不注入 nonce 的話畫面有樣式卻整片空白，而且不會報錯。
  describe "內嵌 script 的 nonce 注入" do
    before { get "/csp/index.html" }

    it "每個內嵌 script 都被加上 nonce" do
      inline = response.body.scan(/<script(?![^>]*\bsrc=)[^>]*>/i)
      expect(inline).not_to be_empty
      expect(inline).to all(match(/nonce="/))
    end

    it "注入的 nonce 與回應標頭中的一致" do
      nonce = response.body[/<script[^>]*nonce="([^"]+)"/i, 1]
      expect(csp_directive("script-src")).to include("'nonce-#{nonce}'")
    end

    it "課程資料仍在頁面上（沒有被改壞）" do
      expect(response.body).to include("DEFAULT_COURSES")
    end

    it "非 HTML 檔案照舊直接送出，不進 nonce 注入" do
      get "/csp/diagrams/csp/csp-flow.svg"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/svg+xml")
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

# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self

    # 稽核 H-3：所有內嵌 <script> 都已搬進 Vite 模組（app/frontend/behaviors/），
    # 唯一剩下的是 layout 裡還原字級的那一段——它必須在瀏覽器繪製前執行，
    # 不能等 module 的 defer，所以改用 CSP nonce 放行（見 nonce_directives）。
    # 因此 script-src 不再需要 :unsafe_inline，CSP 對 XSS 才真正有防護力。
    policy.script_src :self, "https://cdn.jsdelivr.net"
    policy.script_src(*policy.script_src, :unsafe_eval, "http://#{ViteRuby.config.host_with_port}") if Rails.env.development?

    # style-src 目前仍放行 :unsafe_inline，正在收斂中。
    #
    # 這條比 script-src 難：**CSP nonce 對 style="..." 屬性無效**，只對 <style>
    # 區塊有效。拿掉 :unsafe_inline 等於禁止所有內嵌 style 屬性，動態值必須改由
    # JS 設定——CSSOM（el.style.width = ...）不受 CSP 限制，被擋的只有
    # 「HTML 屬性」這個形式。
    #
    # 收斂進度由 CspStyleSrcReport（見下）以 report-only 標頭實測，
    # 違規歸零後把這裡的 :unsafe_inline 拿掉、並移除那個 concern。
    policy.style_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"

    policy.img_src     :self, :https, :data
    policy.font_src    :self, :https, :data
    policy.connect_src :self
    policy.connect_src(*policy.connect_src, "ws://#{ViteRuby.config.host_with_port}") if Rails.env.development?
    policy.media_src   :self, "http://127.0.0.1:5051"
    policy.object_src  :none
    policy.frame_ancestors :none
  end

  # 每個回應一組隨機 nonce。專案沒有使用 fragment cache，不會有「快取到舊 nonce」
  # 的問題（加 fragment cache 之前務必重新確認這一點）。
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # 刻意不使用 config.content_security_policy_report_only——那會讓「整份」政策
  # 變成報告模式，連已經收緊的 script-src 也一起失去強制力。
  # style-src 的收斂改用另一份 report-only 標頭，見
  # app/controllers/concerns/csp_style_src_report.rb
end

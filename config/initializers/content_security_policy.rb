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

    # style-src 不再放行 :unsafe_inline（2026-08-30 完成收斂）。
    #
    # 這條比 script-src 難的地方：**CSP nonce 對 style="..." 屬性無效**，
    # 只對 <style> 區塊有效。所以「用 nonce 放行」那招在這裡不管用，
    # 內嵌樣式必須真的移除。收斂後的三種承載方式：
    #
    #   靜態樣式  → CSS class（Tailwind utility 或 app/assets/tailwind/application.css）
    #   動態數值  → data attribute + CSSOM（app/frontend/behaviors/shared/dataStyles.ts）
    #               CSSOM 賦值不受 CSP 限制，被擋的只有「HTML 屬性」這個形式
    #   <style>   → nonce（例如 BCVS 的 @font-face，需要 Propshaft digest 路徑）
    #
    # 期權小學堂（private/csp_lessons/）另有寬鬆政策，見 CspLessonsController——
    # 那些是 send_file 的靜態教材頁，零使用者輸入。
    policy.style_src :self, "https://cdn.jsdelivr.net"

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
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end

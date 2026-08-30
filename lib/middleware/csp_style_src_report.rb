# frozen_string_literal: true

# style-src 收斂用的暫時性量測 middleware（2026-08-30 起）。
#
# 目的：在不動主政策的前提下，量出還有哪些內嵌樣式會被收緊後的 style-src 擋下。
#
# ── 為什麼不用 config.content_security_policy_report_only ──
# 那個開關會讓**整份**政策變成報告模式，連已經收緊的 script-src 也一起失去
# 強制力。過渡期不該用安全倒退換取觀測能力。
#
# ── 為什麼不用 after_action ──
# 這是踩過的坑：ActionDispatch::ContentSecurityPolicy::Middleware 開頭是
#
#     return response if policy_present?(headers)
#     def policy_present?(headers)
#       headers[CONTENT_SECURITY_POLICY] || headers[CONTENT_SECURITY_POLICY_REPORT_ONLY]
#     end
#
# 判斷用的是「或」。controller 的 after_action 比 middleware 早執行，
# 先放上 Report-Only 標頭就會讓 middleware 認定政策已存在，**整個跳過主政策**——
# 主 CSP 標頭直接消失，而且沒有任何錯誤訊息。
#
# 所以改成 middleware，並用 insert_before 掛在 Rails CSP middleware 的外層：
# 請求階段先跑到這裡，回應階段則在它「之後」才跑，那時主政策已經寫好了。
#
# ── 移除時機 ──
# 違規歸零後：把主政策的 :unsafe_inline 拿掉，然後刪掉這個檔案與
# config/application.rb 裡的 insert_before。
module Middleware
  class CspStyleSrcReport
    # 只回報 style-src，其餘指令由主政策負責。
    POLICY = "style-src 'self' https://cdn.jsdelivr.net"

    # 期權小學堂是 send_file 的靜態教材頁（零使用者輸入），不在收斂範圍，
    # 量它只會製造上千筆雜訊。
    SKIP_PATHS = %r{\A/csp(/|\z)}

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, _body = response = @app.call(env)

      return response if status == 304
      return response if env["PATH_INFO"].to_s.match?(SKIP_PATHS)
      return response unless headers["content-type"].to_s.include?("text/html")

      # 主政策此時已由 ActionDispatch 的 middleware 寫好；沒寫好就不要蓋，
      # 免得重演「report-only 把主政策擠掉」那個問題。
      return response if headers["content-security-policy"].blank?

      headers["content-security-policy-report-only"] = POLICY
      response
    end
  end
end

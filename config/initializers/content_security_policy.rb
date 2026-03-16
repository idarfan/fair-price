# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# 注意：script_src 使用 unsafe_inline 是為了允許 layout 中的 NProgress inline script。
# 後續改進：將 inline script 移至獨立 .js 檔案後，可移除 unsafe_inline 以強化安全性。

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # cdn.jsdelivr.net：Sortable.js, html-to-image, NProgress
    # unsafe_inline：layout 中的 NProgress 設定 inline script
    policy.script_src  :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    # unsafe_inline：部分元件可能使用 inline style；cdn.jsdelivr.net：nprogress.css
    policy.style_src   :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    policy.img_src     :self, :https, :data
    policy.font_src    :self, :https, :data
    # self：SSE streaming（/momentum/analysis）及一般 AJAX 呼叫
    # Anthropic/Finnhub 等外部 API 皆從 server 端呼叫，不需列於此
    policy.connect_src :self
    policy.object_src  :none
    policy.frame_ancestors :none
  end
end

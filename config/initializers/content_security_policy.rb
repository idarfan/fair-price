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
    # Allow @vite/client to hot reload javascript changes in development
    policy.script_src *policy.script_src, :unsafe_eval, "http://#{ViteRuby.config.host_with_port}" if Rails.env.development?

    # unsafe_inline：部分元件可能使用 inline style；cdn.jsdelivr.net：nprogress.css
    policy.style_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    # Allow @vite/client to hot reload style changes in development
    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?

    policy.img_src     :self, :https, :data
    policy.font_src    :self, :https, :data
    # self：SSE streaming（/momentum/analysis）及一般 AJAX 呼叫
    # Groq/Finnhub 等外部 API 皆從 server 端呼叫，不需列於此
    policy.connect_src :self
    # Allow @vite/client to hot reload changes in development
    policy.connect_src *policy.connect_src, "ws://#{ViteRuby.config.host_with_port}" if Rails.env.development?

    policy.object_src  :none
    policy.frame_ancestors :none
  end
end

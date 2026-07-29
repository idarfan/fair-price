Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]
end

# Cloudflare Tunnel 把外部 https 請求轉成內部 http 送進 Rails,若不強制
# full_host,OmniAuth 組出的 callback URL 會變成 http:// 開頭,跟 GCP
# Console 登記的 https:// redirect_uri 對不上(redirect_uri_mismatch)。
# 只在打 fairprice-ohmy.com 這個 host 時強制 https,本機 localhost 開發
# 流程不受影響。
OmniAuth.config.full_host = lambda do |env|
  request = Rack::Request.new(env)
  request.host == "fairprice-ohmy.com" ? "https://fairprice-ohmy.com" : "#{request.scheme}://#{request.host_with_port}"
end

OmniAuth.config.on_failure = ->(env) { SessionsController.action(:failure).call(env) }

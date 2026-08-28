require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # 對外流量走 Cloudflare Tunnel（cloudflared），TLS 在 Cloudflare 端終結，
  # 回源是 http://localhost:3003，cloudflared 會帶 X-Forwarded-Proto: https。
  #
  # 這裡刻意「不」開 config.assume_ssl：它是無條件把每個請求都標記成 https，
  # 連本機直連 http://localhost:3003 也會被當成 https，導致所有 redirect_to
  # 產生 https:// 網址，本機瀏覽與 Playwright 流程整個壞掉。
  # 不開的話 Rails 依 X-Forwarded-Proto 判斷，公網是 https、本機是 http，兩邊都正確。
  config.force_ssl = true

  # exclude 同時關掉「導向 https」與「把 cookie 標記 Secure」兩件事，
  # 所以本機直連（http://localhost:3003）與健康檢查都不受影響——本機沒有 TLS
  # 監聽器，一旦被導向 https 或拿到 Secure cookie，開發與 Playwright 流程就會壞掉。
  # 公網網域走完整的 force_ssl。
  #
  # HSTS 由 Rails 這邊關掉，改在 Cloudflare 端設定：ActionDispatch::SSL 的 HSTS
  # header 不受 exclude 管轄，會一起送給 localhost，把瀏覽器對 localhost 的
  # http 存取永久鎖成 https。
  config.ssl_options = {
    hsts:     false,
    redirect: {
      exclude: lambda { |request|
        request.path == "/up" || %w[localhost 127.0.0.1 ::1].include?(request.host)
      }
    }
  }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Enable DNS rebinding protection and other `Host` header attacks.
  # 注意:production 環境沒有 development 那組 0.0.0.0/0 預設允許清單,
  # 不設定 config.hosts 會導致所有請求被 Host Authorization 擋下(全站
  # 403)。localhost 是給本機直接存取(如健康檢查)用。
  config.hosts << "fairprice-ohmy.com"
  config.hosts << "localhost"
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

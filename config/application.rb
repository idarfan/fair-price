require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# middleware 要在 boot 階段就取得常數（insert_before 需要真正的 class，
# Rails 8.1 起不接受字串），所以明確 require 並排除在 autoload 之外。
require_relative "../lib/middleware/csp_style_src_report"

module Fairprice
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Taipei"
    # config.eager_load_paths << Rails.root.join("extras")

    config.generators.system_tests = nil

    # style-src 收斂期間的量測標頭（暫時性，見 lib/middleware/csp_style_src_report.rb）。
    #
    # insert_before 是關鍵：這樣它在「請求」階段跑在 Rails CSP middleware 之前，
    # 在「回應」階段就跑在它之後——那時主政策已經寫好了。若順序反過來，
    # ActionDispatch 的 middleware 會因為看到 Report-Only 標頭而跳過主政策。
    #
    config.middleware.insert_before(
      ActionDispatch::ContentSecurityPolicy::Middleware,
      Middleware::CspStyleSrcReport
    )

    # development 與 production 共用同一個資料庫（見 config/database.yml），
    # 而 Rails 的破壞性指令保險是看「資料庫裡存的環境標記」，那個標記會被
    # db:migrate 寫成當下的 RAILS_ENV——只保護 production 的話，隨手跑一次
    # 不帶 RAILS_ENV 的 db:migrate 就會把標記翻成 development，保險靜靜失效。
    #
    # 兩個名字都保護，db:drop / db:reset / db:schema:load 不管標記漂到哪一邊
    # 都會被擋下。test 資料庫的標記是 "test"，不受影響，db:test:prepare 照常。
    config.active_record.protected_environments = %w[production development]
  end
end

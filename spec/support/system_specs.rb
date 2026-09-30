# frozen_string_literal: true

# System spec：真的開瀏覽器跑前端 behavior（tasks/leaps-vertical-fix.md S3／S4）。
# Rails 預設組合 capybara + selenium-webdriver，driver 用 headless Chrome；
# chromedriver 由 Selenium Manager 依本機 Chrome 版本自動取得。
# WebMock 已 allow_localhost（external_apis.rb），selenium 對 chromedriver 的連線不受影響。
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
  end
end

# frozen_string_literal: true

# N+1 查詢偵測（只在 development 載入 gem，見 Gemfile）。
#
# 刻意「只記錄、不拋錯、不彈窗」：
#   * raise = true 會讓開發中的頁面直接掛掉。這個專案以資料抓取為主，
#     有些地方本來就是要跑 N 次查詢，攔截成例外的干擾大於幫助。
#   * alert / console / 頁面注入會改動 HTML 與執行 inline JS，違反本專案 CSP。
#
# 輸出：log/bullet.log（已進 .gitignore）+ log/development.log。
#
# 註：設定直接寫在 initializer 本體，不要包進 config.after_initialize——
# 包起來時 UniformNotifier 的設定不會生效（實測 raise / customized_logger
# 都留在預設值），是靜默失效，很難發現。
if defined?(Bullet)
  Bullet.enable        = true
  Bullet.bullet_logger = true   # → log/bullet.log
  Bullet.rails_logger  = true   # → log/development.log
  Bullet.raise         = false
  Bullet.alert         = false
  Bullet.console       = false
end

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  # traceroute gem 的前半（路由指向不存在的 action）。後半（action 沒有路由）
  # 由 spec/routing/unreachable_actions_spec.rb 負責，隨 RSpec 一起跑。
  step "Style: 未使用的路由", "bin/rails routes --unused"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # 2026-08-30：原本的 bin/ci 完全沒有跑測試——lint 與資安都過了但一行 spec 都沒執行。
  step "Tests: RSpec (含覆蓋率門檻)", "COVERAGE=1 bundle exec rspec"
  step "Tests: 前端 tsc + eslint + vitest", "npm run check"

  # 報告用，不設閘門：40 項發現裡含刻意的取捨與已知誤報
  # （四個 MissingUniqueIndexChecker 是誤報，那些 model 存檔前都會 upcase）。
  # 用 bin/audit schema 單獨檢視。


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end

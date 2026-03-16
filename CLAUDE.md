# CLAUDE.md — FairPrice / Daily Momentum

This file provides guidance to Claude Code when working with this repository.

## Session Start

- **Always review `tasks/lessons.md`** for relevant project patterns and past corrections.

## Work Habits

- **Plan Mode Default**：非瑣碎任務（3+ 步驟或架構決策）一律先進 plan mode；出問題立刻停下重新規劃
- **Subagent Strategy**：善用 subagent 分擔研究、探索、平行分析，保持主 context window 乾淨
- **Self-Improvement**：每次被修正後，立刻更新 `tasks/lessons.md`，寫下防止重犯的規則
- **Verification**：完成前必須證明可運作（跑測試、查 log、展示結果）
- **Demand Elegance**：非瑣碎修改先問「有沒有更優雅的做法？」，簡單修正不過度設計
- **Autonomous Bug Fixing**：收到 bug 回報就直接修，不要反問使用者

## Task Management

1. 寫計畫到 `tasks/todo.md`（含可勾選項目）
2. 開工前先確認計畫
3. 邊做邊標記完成
4. 每步驟附高階摘要
5. 完成後在 `tasks/todo.md` 加 review section
6. 被修正後更新 `tasks/lessons.md`

## Git 工作流

- **Commit message 格式**：`<類型>: <簡述>`（繁體中文）
  - 類型：`feat` / `fix` / `refactor` / `docs` / `test` / `chore`
  - 範例：`feat: 新增 watchlist 批次編輯功能`
- **每次完成功能修改並通過測試後，主動執行 `git add . && git commit`**
- **推送前必須確認 `bundle exec rspec` 全部通過**
- **禁止 `git push --force`**
- **`git push` 禁止自動執行**，完成 commit 後提醒使用者手動 push

## Commands

```bash
# Server（port 3003）
systemctl --user restart fairprice
systemctl --user status  fairprice
journalctl --user -u fairprice -n 30

# Boot check
bundle exec rails runner "puts 'Boot OK'"

# Routes
bundle exec rails routes

# Lookbook previews
open http://localhost:3003/lookbook
```

## Architecture

**No database. No React. No Vite.** Pure Phlex + Tailwind CDN app backed by Finnhub HTTP calls.

Two tools under one process on port 3003:

| Tool | Route | Controller | Namespace |
|------|-------|------------|-----------|
| FairPrice | `/`, `/valuations/:ticker` | `ValuationsController` | `FairValue::` |
| Daily Momentum | `/momentum` | `ReportsController` | `DailyMomentum::` |
| JSON API | `/api/v1/valuations/:ticker` | `Api::V1::ValuationsController` | — |

Shared infrastructure:
- `ApplicationComponent`：格式化 helpers（`fmt_currency`, `fmt_percent`, `fmt_large`, `change_color`, `upside_color`）
- `ApplicationHelper`：momentum risk helpers（`risk_level`, `max_position_note`）
- `FairValue::AppSwitcherComponent`：左側 sidebar
- `app/views/layouts/application.html.erb`：共用 layout

## FairPrice data flow

```
ValuationsController#show
  └── StockDataService.fetch(ticker)       → Finnhub /quote, /metric, /profile2, /recommendation
        └── ValuationService.calculate(data, discount_rate)
              → classifies stock type → applies DCF/P-E/PEG/DDM/P-B/EV-EBITDA
```

Stock type classification drives which valuation methods are used. To add a new method: write a private method returning `{ method:, value:, note:, formula: }` and add it to the relevant `*_methods` array.

## Daily Momentum data flow

```
ReportsController#index
  └── MomentumReportService#call
        ├── FinnhubService#quote("^VIX")   → vix
        ├── FinnhubService#quote(symbol)×N → stocks（symbols from config/watchlist.yml）
        ├── FinnhubService#market_news     → news
        └── FinnhubService#earnings_calendar → earnings
```

Edit `config/watchlist.yml` to change tracked symbols — no code change needed.

Market time segment derived from ET clock in `MomentumReportService#time_segment`.

## Adding a new tool to the sidebar

1. Add route in `config/routes.rb`
2. Create controller + view under new namespace
3. Add entry to `APP_LINKS` in `app/components/fair_value/app_switcher_component.rb`

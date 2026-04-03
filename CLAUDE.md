# CLAUDE.md — FairPrice / Daily Momentum

This file provides guidance to Claude Code when working with this repository.

## Session Start

- **Always review `tasks/lessons.md`** for relevant project patterns and past corrections.

## MCP Tools

本專案已設定 `rails-mcp-server`，修改 model / route / controller **之前**先用以下工具確認現有結構：

```
switch_project fairprice       # 切換到本專案
execute_tool project_info      # 查看專案結構
execute_tool analyze_models    # 分析 model 關聯
execute_tool get_routes        # 查看路由
execute_tool get_schema        # 查看資料庫 schema
load_guide rails               # 查詢 Rails 官方文件
```

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

# Vite dev server（port 3036）
systemctl --user restart fairprice-vite
systemctl --user status  fairprice-vite

# Boot check
bundle exec rails runner "puts 'Boot OK'"

# Routes
bundle exec rails routes

# Lookbook / Storybook previews
open http://localhost:3003/lookbook
```

## Architecture

PostgreSQL 持久化資料（ownership snapshots 等）。Rails 後端 + 混合前端架構：

- **Phlex + Tailwind**：適用於 Rails 傳統頁面（FairPrice、Daily Momentum、Watchlist 等）
- **Vite + React + Recharts**：適用於需要互動圖表的獨立頁面（持股結構等）
- **Storybook**：React 元件開發與預覽

### 前端技術選擇原則

| 頁面類型 | 建議技術 |
|---------|---------|
| 靜態資料展示、表單 | Phlex + Tailwind |
| 互動圖表、複雜 UI 狀態 | Vite + React + Recharts |
| 元件開發預覽 | Storybook（React 元件）/ Lookbook（Phlex 元件）|

**不強制使用 Phlex**：新功能依複雜度與互動需求自由選擇技術棧。

Two tools under one process on port 3003:

| Tool | Route | Controller | Namespace |
|------|-------|------------|-----------|
| FairPrice | `/`, `/valuations/:ticker` | `ValuationsController` | `FairValue::` |
| Daily Momentum | `/momentum` | `ReportsController` | `DailyMomentum::` |
| 持股結構 | `/ownership` | `OwnershipController` | — |
| JSON API | `/api/v1/...` | `Api::V1::*` | — |

Shared infrastructure:
- `ApplicationComponent`：格式化 helpers（`fmt_currency`, `fmt_percent`, `fmt_large`, `change_color`, `upside_color`）
- `ApplicationHelper`：momentum risk helpers（`risk_level`, `max_position_note`）
- `FairValue::AppSwitcherComponent`：左側 sidebar
- `app/views/layouts/application.html.erb`：共用 layout

## FairPrice data flow

```
ValuationsController#show
  └── StockDataService.fetch(ticker)       → Finnhub /quote, /metric, /profile2, /recommendation
        └── ValuationService.analyze(data, discount_rate)
              → classify() → estimate_growth_rate() → apply_methods(stock_type, growth_rate)
                    → 一般股:   [DCF, P/E, PEG]
                    → 金融股:   [ExcessRet, P/E, P/B]
                    → REITs:    [DDM, DCF, P/B]
                    → 公用事業: [DDM, DCF, P/E]
                    → 虧損成長股: [Rev×3, DCF]
                    → 週期股:   [EV/EBITDA, P/B, DCF]
```

Stock type classification drives which valuation methods are used. To add a new method: write a private method returning `{ method:, value:, note:, formula: }` and add it to the relevant `*_methods` array.

## Daily Momentum data flow

```
ReportsController#index
  └── MomentumReportService#call
        ├── VixService#fetch               → vix
        ├── FinnhubService#quote(symbol)×N → stocks（symbols from config/watchlist.yml）
        ├── YahooFinanceService#chart      → es_change, nq_change（期貨）
        ├── YahooFinanceService#chart      → 52 週高低點
        └── FinnhubService#earnings_calendar → earnings
```

Edit `config/watchlist.yml` to change tracked symbols — no code change needed.

Market time segment derived from ET clock in `MomentumReportService#time_segment`.

## 持股結構 data flow

```
OwnershipApp.tsx（React）
  └── GET  /api/v1/ownership_snapshots/:ticker?range=1w|1m|90d
  └── POST /api/v1/ownership_snapshots/:ticker（手動更新快照）
        └── Api::V1::OwnershipSnapshotsController
              └── YahooFinanceService#holders（失敗則 fallback: SecEdgarService#holders）
                    → OwnershipSnapshotService#save_snapshot
                          → OwnershipSnapshot（ticker+quarter 唯一）+ OwnershipHolder
```

## Adding a new tool to the sidebar

1. Add route in `config/routes.rb`
2. Create controller + view（Phlex 或 React 均可）
3. Add entry to `APP_LINKS` in `app/components/fair_value/app_switcher_component.rb`

## Storybook + Chromatic 視覺回歸測試

**執行指令：**
```bash
npx chromatic
```
Token 存放位置：**`.env`**（根目錄，key: `CHROMATIC_PROJECT_TOKEN`）

# ARCHITECTURE.md — FairPrice 架構說明

## 設計原則

- **無資料庫依賴**（估值 / 動量功能）：所有股票數據即時從 Finnhub / Yahoo Finance 抓取，不落地存儲
- **混合前端架構**：靜態頁面用 Phlex 元件（伺服器端渲染），互動圖表 / 複雜 UI 用 Vite + React（見下表）
- **無 Hotwire**：明確禁用 Turbo / Stimulus，避免隱式行為
- **單一 process**：所有工具共用一個 Rails 應用，監聽 port 3003

---

## 技術棧

| 層次 | 技術 |
|------|------|
| 框架 | Ruby on Rails 8.1 |
| 資源管線 | Propshaft |
| UI 元件 | Phlex 2.x（phlex-rails）— 靜態頁面 |
| 前端打包 | Vite（vite-plugin-ruby）+ React 19 — 互動頁面 |
| 互動圖表 | Recharts（持股結構）、Lightweight Charts（技術圖） |
| 可調整佈局 | react-resizable-panels v4（Options 頁面）|
| CSS | Tailwind CSS v4（tailwindcss-rails，本地編譯） |
| Markdown | kramdown + kramdown-parser-gfm（伺服器端） |
| HTTP 客戶端 | HTTParty |
| AI 分析 | Groq API（llama-3.3-70b-versatile，SSE 串流） |
| 元件預覽 | Lookbook（Phlex）/ Storybook（React） |
| Lint | RuboCop（rubocop-rails-omakase）、ESLint、TypeScript strict |
| 程序管理 | pm2（禁止直接用 systemctl --user） |

### 前端技術選擇原則

| 頁面類型 | 建議技術 |
|---------|---------|
| 靜態資料展示、表單 | Phlex + Tailwind |
| 互動圖表、可調整佈局、複雜 UI 狀態 | Vite + React + Recharts |
| Phlex 元件開發預覽 | Lookbook |
| React 元件開發預覽 | Storybook |

---

## 目錄結構

```
fairprice/
├── app/
│   ├── components/                # Phlex UI 元件
│   │   ├── application_component.rb          # 基底類別（格式化 helpers）
│   │   ├── fair_value/                       # 共用 Navbar / AppSwitcher 元件
│   │   │   ├── app_switcher_component.rb     # 左側 App 切換側欄
│   │   │   ├── font_size_controls_component.rb  # Navbar 字體大小按鍵（5 個）
│   │   │   ├── navbar_component.rb           # 頂部導覽列
│   │   │   └── search_bar_component.rb
│   │   ├── daily_momentum/                   # Daily Momentum 工具元件
│   │   │   ├── analysis_panel_component.rb   # 歐歐 AI 分析面板
│   │   │   └── watchlist_table_component.rb
│   │   ├── options/                          # Options Analyzer 掛載點
│   │   │   └── page_component.rb             # React app 掛載容器（flex flex-col）
│   │   ├── ownership/                        # Ownership React app 掛載點
│   │   ├── portfolio/                        # Portfolio 工具元件
│   │   └── stock_alert/                      # Watchlist 警示元件
│   ├── controllers/
│   │   ├── valuations_controller.rb          # FairPrice 估值
│   │   ├── reports_controller.rb             # Daily Momentum 報告
│   │   ├── options_controller.rb             # Options Analyzer
│   │   ├── ownership_controller.rb           # 持股結構
│   │   ├── margin_controller.rb              # 保證金試算
│   │   ├── stock_alerts_controller.rb        # 價格警示
│   │   ├── portfolios_controller.rb          # 投資組合
│   │   └── api/v1/                           # JSON API
│   ├── frontend/                             # Vite + React 前端原始碼
│   │   ├── options/                          # Options Analyzer App
│   │   │   ├── OptionsAnalyzerApp.tsx        # 主元件（react-resizable-panels v4）
│   │   │   ├── components/                   # PayoffChart, StrategyDetail 等
│   │   │   ├── strategies.ts                 # 期權策略定義
│   │   │   └── types.ts
│   │   ├── ownership/                        # 持股結構 App
│   │   └── entrypoints/                      # Vite 入口點
│   ├── services/
│   │   ├── stock_data_service.rb
│   │   ├── valuation_service.rb
│   │   ├── finnhub_service.rb
│   │   ├── yahoo_finance_service.rb
│   │   ├── momentum_report_service.rb
│   │   ├── ouou_analysis_service.rb          # AI 分析（Groq + cache）
│   │   ├── vix_service.rb
│   │   ├── telegram_service.rb
│   │   └── stock_price_checker.rb
│   └── views/
│       └── layouts/
│           └── application.html.erb          # 主 layout（含早期字體大小腳本）
├── config/
│   ├── routes.rb
│   └── watchlist.yml                         # 動量報告自選股清單
├── docs/                                     # 專案文件（本目錄）
│   ├── ARCHITECTURE.md
│   ├── USER_MANUAL.md
│   ├── INSTALL.md
│   └── DAILY_MOMENTUM.md
└── tasks/
    └── lessons.md                            # 踩坑教訓紀錄
```

---

## 工具路由表

| 工具 | 路由 | Controller | 前端 |
|------|------|------------|------|
| FairPrice 估值 | `GET /` `GET /valuations/:ticker` | `ValuationsController` | Phlex |
| Daily Momentum | `GET /momentum` | `ReportsController` | Phlex |
| 歐歐 AI 分析（SSE） | `GET /momentum/analysis` | `ReportsController#analysis` | Phlex |
| 技術圖表 | `GET /reports/:ticker/technicals` | `ReportsController#technicals` | Vite + React |
| 美股期權分析 | `GET /options` `GET /options/:symbol` | `OptionsController` | Vite + React |
| 持股結構 | `GET /ownership` | `OwnershipController` | Vite + React |
| 保證金試算 | `GET /margin` | `MarginController` | Vite + React |
| 期權價格追蹤 | `GET /option_price_tracker` | `OptionPriceTrackerController` | Vite + React |
| Watchlist | `GET/POST /watchlist` 等 | `StockAlertsController` | Phlex |
| Portfolio | `GET/POST /portfolio` 等 | `PortfoliosController` | Phlex |
| JSON API | `GET /api/v1/...` | `Api::V1::*` | — |
| 元件預覽 | `GET /lookbook` | Lookbook Engine | — |

---

## FairPrice 估值資料流

```
ValuationsController#show
  └── StockDataService.fetch(ticker)
        ├── FinnhubService#quote         → 現價、漲跌
        ├── FinnhubService#metrics       → EPS、本益比、股息等基本面
        ├── FinnhubService#profile2      → 公司名稱、產業、市值
        └── FinnhubService#recommendation → 分析師買賣建議
              └── ValuationService.calculate(data, discount_rate)
                    → 依股票類型分類
                    → 執行適用的估值方法（各回傳 { method:, value:, note:, formula: }）
                    → Phlex 元件自動渲染結果列表
```

### 新增估值方法

在 `ValuationService` 新增私有方法，回傳：
```ruby
{ method: "方法名", value: 150.0, note: "說明", formula: "計算公式" }
```
再加入對應股票類型的 `*_methods` 陣列，Phlex 元件自動渲染。

---

## Daily Momentum 資料流

```
ReportsController#index
  └── MomentumReportService#call
        ├── FinnhubService#quote("^VIX")        → VIX 指數
        ├── FinnhubService#quote(symbol) × N     → 各股報價（平行化 Thread）
        │     └── YahooFinanceService#fetch(symbol) → 歷史價格、成交量（平行化）
        ├── FinnhubService#market_news           → 財經新聞
        └── FinnhubService#earnings_calendar     → 財報日曆
```

市場時段判斷（ET 時鐘）在 `MomentumReportService#time_segment`，回傳：
`:market_hours` | `:pre_market` | `:after_hours` | `:closed`

---

## AI 分析（歐歐）架構

```
ReportsController#analysis（SSE endpoint）
  └── OuouAnalysisService#call
        ├── [Cache hit]  Rails.cache 讀取 → 直接 yield 全文（TTL 3 小時）
        └── [Cache miss] Groq API（llama-3.3-70b-versatile）
              → 組合 prompt（含 Ruby 預建 Markdown 表格）
              → SSE 串流逐 chunk yield
              → 串流完成後寫入 Rails.cache
              → append 分析時間 footer（ET 時間戳記）
```

**Markdown 表格策略**：凡資料已在伺服器端計算好，一律由 Ruby 預建表格放入 prompt，告知 AI 原文輸出，不讓 AI 自行排版（見 `OuouAnalysisService#build_momentum_table`）。

---

## Markdown 渲染管線

```
AI 輸出（raw markdown）
  └── normalize_md_tables（備用保障：修正非 ASCII 破折號、移除 separator 前空行）
        └── Kramdown::Document.new(text, input: "GFM").to_html
              → 注入頁面 .md-body div
```

`separator_row?` 判斷邏輯：`!s.match?(/[\p{L}\p{N}]/)` — 無字母無數字即為 separator row，不用字元白名單，容錯各種破折號變體。

---

## 共用元件與 Helpers

### ApplicationComponent（`app/components/application_component.rb`）

所有 Phlex 元件的基底類別，提供格式化 helper：

| Helper | 說明 |
|--------|------|
| `fmt_currency(val)` | 格式化金額（如 $185.50） |
| `fmt_percent(val)` | 格式化百分比 |
| `fmt_large(val)` | 大數字縮寫（如 1.2B） |
| `change_color(val)` | 漲跌色彩（Tailwind class） |
| `upside_color(val)` | 上漲空間色彩 |

### ApplicationHelper

提供動量風險 helpers：`risk_level`、`max_position_note`

### FairValue::AppSwitcherComponent

左側側欄，`APP_LINKS` 常數維護所有工具入口。新增工具時需在此常數新增一筆。

### FairValue::FontSizeControlsComponent

Navbar 字體大小控制（5 個按鍵，14–18px）。點擊修改 `document.documentElement.style.fontSize`，Tailwind 所有 rem 值等比縮放。偏好存至 `localStorage['fairprice:font-size']`，`application.html.erb` head 含早期渲染腳本防止 FOUC。

### Options::PageComponent

React app 掛載容器。需設定 `flex flex-col` 確保 React 根元件的 `flex-1 min-h-0` 能正確繼承高度。

---

## Options Analyzer 架構（React）

```
OptionsController#index / #show
  └── Options::PageComponent（Phlex 掛載容器，flex flex-col）
        └── OptionsAnalyzerApp.tsx（React）
              ├── react-resizable-panels v4（三組可調整邊界）
              │     ├── Group horizontal：sidebar（13%）↔ 主區（87%）
              │     ├── Group vertical：損益圖（34%）↔ 策略區（66%）
              │     └── Group horizontal：策略列表（22%）↔ 策略解說（78%）
              ├── useDefaultLayout({ id })  → localStorage 記憶面板大小
              ├── PanelResetButton          → setLayout() 還原預設比例
              ├── PayoffChart               → Recharts 損益圖
              ├── StrategyRecommendList     → 推薦策略清單
              ├── StrategyDetailPanel       → 策略詳細說明
              └── HeaderUploadZone          → 截圖上傳 + AI 分析
```

**Panel 尺寸規則（v4 特殊注意）：**
```tsx
// ✅ 必須用字串百分比，純數字 = px（會被 maxSize 鎖死）
<Panel defaultSize="13%" minSize="8%" maxSize="25%">
// setLayout 的 layout 物件用 0–100 純數字（百分比格式不同）
ref.current?.setLayout({ "lr-sidebar": 13, "lr-main": 87 })
```

---

## 新增工具步驟

### Phlex 頁面

1. 在 `config/routes.rb` 新增路由
2. 建立 Controller（與對應 namespace 目錄）
3. 建立 Phlex 元件（`app/components/<namespace>/`）
4. 在 `FairValue::AppSwitcherComponent` 的 `APP_LINKS` 新增入口
5. 建立 Lookbook Preview 檔案（`test/components/previews/`）

### React 頁面（Vite）

1. 在 `config/routes.rb` 新增路由
2. 建立 Controller，`render <Namespace>::PageComponent.new(...)`
3. 建立 `app/components/<namespace>/page_component.rb`（掛載 div 需有 `flex flex-col`）
4. 建立 `app/frontend/<namespace>/` 目錄與 React 元件
5. 在 `app/frontend/entrypoints/` 建立入口點（`<name>.tsx`）
6. 在 `app/views/layouts/application.html.erb` 加 `vite_javascript_tag '<name>.tsx'` 條件判斷
7. 在 `FairValue::AppSwitcherComponent` 的 `APP_LINKS` 新增入口

---

## 安全性設計

- 股票代號路由限制正規表達式：`/[A-Za-z0-9.\-]{1,10}/`，防止任意路徑注入
- 所有外部 API 呼叫透過 Service 封裝，不直接暴露於 Controller
- API Key 透過環境變數注入，不寫入程式碼
- 伺服器端渲染 Markdown，避免 XSS（不使用 client-side JS markdown 函式庫）

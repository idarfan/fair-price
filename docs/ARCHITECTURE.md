# ARCHITECTURE.md — FairPrice 架構說明

## 設計原則

- **無資料庫依賴**（估值 / 動量功能）：所有股票數據即時從 Finnhub / Yahoo Finance 抓取，不落地存儲
- **無前端框架**：UI 全由 Phlex 元件（伺服器端渲染）組成，互動邏輯用原生 JavaScript + 事件委派
- **無 Hotwire**：明確禁用 Turbo / Stimulus，避免隱式行為
- **單一 process**：所有工具共用一個 Rails 應用，監聽 port 3003

---

## 技術棧

| 層次 | 技術 |
|------|------|
| 框架 | Ruby on Rails 8.1 |
| 資源管線 | Propshaft |
| UI 元件 | Phlex 2.x（phlex-rails） |
| CSS | Tailwind CSS v4（tailwindcss-rails，本地編譯） |
| Markdown | kramdown + kramdown-parser-gfm（伺服器端） |
| HTTP 客戶端 | HTTParty |
| AI 分析 | Groq API（llama-3.3-70b-versatile，SSE 串流） |
| 元件預覽 | Lookbook |
| Lint | RuboCop（rubocop-rails-omakase） |
| 程序管理 | systemd user service |

---

## 目錄結構

```
fairprice/
├── app/
│   ├── components/                # Phlex UI 元件
│   │   ├── application_component.rb     # 基底類別（格式化 helpers）
│   │   ├── fair_value/                  # FairPrice 估值工具元件
│   │   │   ├── app_switcher_component.rb  # 左側 App 切換側欄
│   │   │   ├── page_layout_component.rb
│   │   │   ├── valuation_table_component.rb
│   │   │   └── ...
│   │   ├── daily_momentum/              # Daily Momentum 工具元件
│   │   │   ├── analysis_panel_component.rb  # 歐歐 AI 分析面板
│   │   │   ├── watchlist_table_component.rb
│   │   │   └── ...
│   │   ├── portfolio/                   # Portfolio 工具元件
│   │   └── stock_alert/                 # Watchlist 警示元件
│   ├── controllers/
│   │   ├── valuations_controller.rb     # FairPrice 估值
│   │   ├── reports_controller.rb        # Daily Momentum 報告
│   │   ├── stock_alerts_controller.rb   # 價格警示
│   │   ├── portfolios_controller.rb     # 投資組合
│   │   └── api/v1/valuations_controller.rb  # JSON API
│   ├── services/
│   │   ├── stock_data_service.rb        # Finnhub 資料聚合
│   │   ├── valuation_service.rb         # 估值計算（DCF/P-E/PEG/DDM/P-B/EV-EBITDA）
│   │   ├── finnhub_service.rb           # Finnhub API 客戶端
│   │   ├── yahoo_finance_service.rb     # Yahoo Finance API 客戶端
│   │   ├── momentum_report_service.rb   # 動量報告聚合
│   │   ├── ouou_analysis_service.rb     # AI 分析（Claude API + cache）
│   │   ├── exchange_rate_service.rb     # 匯率
│   │   ├── vix_service.rb               # VIX 指數
│   │   ├── telegram_service.rb          # Telegram 推播
│   │   ├── portfolio_ocr_service.rb     # OCR 持倉辨識
│   │   └── stock_price_checker.rb       # 價格警示背景檢查
│   └── views/
│       └── layouts/
│           ├── application.html.erb     # 主 layout（navbar + sidebar）
│           └── component_preview.html.erb  # Lookbook 預覽 layout
├── config/
│   ├── routes.rb
│   └── watchlist.yml                    # 動量報告自選股清單
├── docs/                                # 專案文件（本目錄）
│   ├── ARCHITECTURE.md
│   ├── INSTALL.md
│   └── USER_MANUAL.md
└── test/
    └── components/previews/             # Lookbook 元件預覽
```

---

## 工具路由表

| 工具 | 路由 | Controller | 命名空間 |
|------|------|------------|----------|
| FairPrice 估值 | `GET /` `GET /valuations/:ticker` | `ValuationsController` | `FairValue::` |
| Daily Momentum | `GET /momentum` | `ReportsController` | `DailyMomentum::` |
| 歐歐 AI 分析（SSE） | `GET /momentum/analysis` | `ReportsController#analysis` | — |
| Markdown 渲染 | `POST /momentum/render_markdown` | `ReportsController#render_markdown` | — |
| 新聞 | `GET /momentum/news` | `ReportsController#company_news` | — |
| Watchlist | `GET/POST /watchlist` 等 | `StockAlertsController` | — |
| Portfolio | `GET/POST /portfolio` 等 | `PortfoliosController` | — |
| JSON API | `GET /api/v1/valuations/:ticker` | `Api::V1::ValuationsController` | `Api::V1::` |
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

---

## 新增工具步驟

1. 在 `config/routes.rb` 新增路由
2. 建立 Controller（與對應 namespace 目錄）
3. 建立 Phlex 元件（`app/components/<namespace>/`）
4. 在 `FairValue::AppSwitcherComponent` 的 `APP_LINKS` 新增入口
5. 建立 Lookbook Preview 檔案（`test/components/previews/`）

---

## 安全性設計

- 股票代號路由限制正規表達式：`/[A-Za-z0-9.\-]{1,10}/`，防止任意路徑注入
- 所有外部 API 呼叫透過 Service 封裝，不直接暴露於 Controller
- API Key 透過環境變數注入，不寫入程式碼
- 伺服器端渲染 Markdown，避免 XSS（不使用 client-side JS markdown 函式庫）

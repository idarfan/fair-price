# FairPrice

美股公平價值分析 + 每日動能報告工具，運行於 port 3003。

## 技術棧

- **Ruby on Rails 8.1** + Propshaft
- **Phlex 2.x** — UI 元件（禁止 ERB partial）
- **Lookbook** — 元件預覽（開發環境）
- **kramdown** — 伺服器端 Markdown 渲染
- **Tailwind CSS v4**（tailwindcss-rails gem，本地編譯）
- **Finnhub API** — 股票報價來源
- 無資料庫、無 Hotwire、無 React

## 啟動

```bash
systemctl --user restart fairprice
systemctl --user status  fairprice
journalctl --user -u fairprice -n 30
```

開發時需同步編譯 Tailwind：

```bash
bin/dev
```

或手動 rebuild：

```bash
bundle exec rails tailwindcss:build
```

## 工具路由

| 工具 | 路由 | Controller |
|------|------|------------|
| FairPrice | `/`, `/valuations/:ticker` | `ValuationsController` |
| Daily Momentum | `/momentum` | `ReportsController` |
| JSON API | `/api/v1/valuations/:ticker` | `Api::V1::ValuationsController` |
| 元件預覽 | `/lookbook` | Lookbook Engine |

## Lint

```bash
bundle exec rubocop
bundle exec rubocop -a   # 自動修正
```

---

## 變更記錄

### 2026-04-17 — Options 頁面可調整框格 + Navbar 字體大小控制

**動機：** 提升 Options 頁面彈性：三個固定框格改為可拖動調整並記憶位置；Navbar 加入 5 個字體大小按鍵。

**異動內容：**
- `app/frontend/options/OptionsAnalyzerApp.tsx`：改用 `react-resizable-panels` v2，三個 `Group`/`Panel`/`Separator` 結構；`useDefaultLayout` 自動 localStorage 持久化；header 加入「↺ 還原版面」按鈕
- `app/components/fair_value/font_size_controls_component.rb`：新建，5 個遞增大小的 A 按鍵（14-18px），修改 `html` 根字體，localStorage 持久化
- `app/components/fair_value/navbar_component.rb`：AppSwitcher 右側加入字體大小控制元件
- `app/views/layouts/application.html.erb`：head 最頂加 early-paint script 防止字體閃爍 (FOUC)
- `app/assets/tailwind/application.css`：加入 resize handle 所需 CSS（cursor-col/row-resize、w/h-1.5、hover:bg-blue-400）

### 2026-03-17 — 修復歐歐分析重複點擊導致串流衝突

**動機：** 串流進行中再次點擊 🐱 按鈕會開第二條 EventSource 連線，兩條互相寫同一面板，導致分析停頓或需點第二次才出現結果。

**異動內容：**
- `app/components/daily_momentum/analysis_panel_component.rb`：新增 `streaming` 狀態物件，串流進行中防止重複觸發；`onerror` 無論 buffer 是否有內容都顯示重試按鈕

### 2026-03-17 — 切換至 Groq (Llama 3.3)，修正 Llama markdown 格式

**動機：** 使用 Groq 免費 API（llama-3.3-70b-versatile）取代 Anthropic Claude，速度更快；Llama 輸出的 markdown 標題無換行導致 Kramdown 渲染破版，需加入正規化處理。

**異動內容：**
- `app/services/ouou_analysis_service.rb`：改用 Groq API，OpenAI 相容格式（SSE streaming、messages 結構）；新增 `[MOMENTUM_TABLE]` 佔位符替換機制；更新 system prompt 為完整 markdown 範本
- `app/controllers/reports_controller.rb`：新增 `normalize_llama_output`，處理五種 Llama 格式問題（mid-line heading、##N. 無空格、表格黏標題、blockquote 黏標題）
- `app/components/daily_momentum/analysis_panel_component.rb`：標示更新為 Powered by Groq / Llama 3.3；PDF 匯出 CSS 同步調整
- `app/assets/tailwind/application.css`：md-body heading 層次更明確，blockquote 樣式強化

### 2026-03-16 — 持股結構資料修正與 UX 調整

**動機：** 修正 Yahoo Finance 回傳的持股百分比顯示錯誤、機構數量欄位名稱錯誤，並調整 UX 為手動更新模式。

**異動內容：**
- `app/services/yahoo_finance_service.rb`：修正 `pct_to_f` 將 0~1 小數 ×100 轉為百分比；修正 `institutionsCount` 欄位名稱；`pctChange` 同步換算
- `app/controllers/api/v1/ownership_snapshots_controller.rb`：時間範圍改為 1w/1m/90d；`pct_change` 加入 holder 序列化
- `app/frontend/ownership/OwnershipApp.tsx`：左側點擊只切換股票，不自動抓取；加「更新快照」手動按鈕
- `app/frontend/ownership/components/TimeRangeSelector.tsx`：範圍改為週/月/90天
- DB schema：唯一鍵恢復為 `ticker + quarter`（每季一筆，重複更新同一筆）

### 2026-03-16 — 持股結構改版：趨勢追蹤、季度比較、機構持有人詳表

**動機：** 將持股結構從「單一快照」升級為「趨勢追蹤」，支援季度對比、時間範圍篩選、機構持有人季度變化分析。

**異動內容：**
- `db/migrate/*_redesign_ownership_schema.rb`：重建 `ownership_snapshots`（ticker + quarter unique）+ 新增 `ownership_holders` 資料表
- `app/models/ownership_snapshot.rb` / `ownership_holder.rb`：改寫 Model，建立 has_many 關聯
- `app/services/ownership_snapshot_service.rb`：新建 Service，封裝 upsert / load_history / previous_snapshot 邏輯
- `app/controllers/api/v1/ownership_snapshots_controller.rb`：新增 JSON API，支援 `?range=90d|1q|6m|1y`
- `config/routes.rb`：新增 API 路由 `GET/POST /api/v1/ownership_snapshots/:ticker`
- `app/frontend/ownership/`：全面改版，新增 MetricCards、TimeRangeSelector、OwnershipTrendChart（ComposedChart + Area）、HoldersTable（季度變化 + NEW badge）、utils/format.ts

### 2026-03-16 — 新增「持股結構」工具（Vite + React + PostgreSQL 歷史快照）

**動機：** 提供 Watchlist 股票的持股結構歷史追蹤，可查看機構持股% 與內部人持股% 隨時間的變化趨勢。

**異動內容：**
- `db/migrate/*_create_ownership_snapshots.rb`：新增 `ownership_snapshots` 資料表（symbol、機構持股%、內部人持股%、top_holders JSONB、fetched_at）
- `app/models/ownership_snapshot.rb`：新增 Model，含 `history_for`、`latest_for` 類別方法
- `app/controllers/ownership_controller.rb`：新增 Controller，提供 index/history/fetch 三個 action
- `config/routes.rb`：新增 `/ownership`、`/ownership/history`、`/ownership/fetch` 路由
- `app/frontend/ownership/`：Vite + React 前端（OwnershipApp、SymbolList、OwnershipPanel、OwnershipChart），使用 Recharts 繪製折線圖
- `app/frontend/entrypoints/ownership.tsx`：React 掛載點
- `app/components/ownership/page_component.rb`：Phlex shell（渲染 `#ownership-root` 掛載 div）
- `app/views/layouts/application.html.erb`：條件性載入 ownership.tsx bundle
- `app/components/fair_value/app_switcher_component.rb`：Sidebar 新增「🏦 持股結構」入口
- `config/initializers/content_security_policy.rb`：開發環境啟用 Vite HMR（unsafe_eval + WebSocket）
- `Gemfile`：新增 `vite_rails ~> 3.0`

### 2026-03-16 — 安全性強化：CSP 啟用、ValuationService 測試、open_timeout 修正

**動機：** Rails 審計發現三項安全/品質問題：CSP header 未啟用、核心估值邏輯 0% 測試覆蓋率、Groq API 連線無 open_timeout 可能永久阻塞 worker。

**異動內容：**
- `config/initializers/content_security_policy.rb`：啟用 Content Security Policy，設定 `default_src :self`、`script_src/style_src` 允許 `cdn.jsdelivr.net` 及 `unsafe_inline`（NProgress inline script）、`connect_src :self`（SSE streaming）、`object_src/frame_ancestors :none`
- `app/services/ouou_analysis_service.rb`：`Net::HTTP.start` 加入 `open_timeout: 10`，防止 Groq API 不可達時 worker 永久阻塞
- `spec/services/valuation_service_spec.rb`：新增 ValuationService 測試，33 個 examples 涵蓋股票分類、成長率估算、估值方法選擇、nil 邊界條件、整合測試及 judgment 判斷邏輯

### 2026-03-12 — Portfolio 持股點擊浮動面板（機構/大戶持股佔比）

**動機：** 讓使用者在持股頁面快速查閱任意股票的機構持股比例與主要大戶名單，無需離開頁面。

**異動內容：**
- `app/services/yahoo_finance_service.rb`：新增 `holders(symbol)` 方法，呼叫 Yahoo Finance quoteSummary API 取得 `majorHoldersBreakdown` 與 `institutionOwnership`
- `config/routes.rb`：新增 `GET /portfolio/ownership` 路由
- `app/controllers/portfolios_controller.rb`：新增 `ownership` action，回傳 JSON
- `app/components/portfolio/holding_row_component.rb`：`render_symbol` td 加上 `data-ownership-symbol` 屬性與 cursor-pointer
- `app/components/portfolio/holding_list_component.rb`：新增 `render_ownership_modal` 方法（浮動面板 HTML）與對應 JS（fetch、渲染、ESC/backdrop 關閉）

### 2026-03-12 — 建立 docs 目錄與三份主要文件

**動機：** 為專案建立完整文件體系，提升可維護性與交接效率。

**異動內容：**
- 新增 `docs/` 目錄
- 新增 `docs/INSTALL.md`：系統需求、安裝步驟、環境變數、常見問題
- 新增 `docs/USER_MANUAL.md`：功能操作說明、JSON API 範例
- 新增 `docs/ARCHITECTURE.md`：設計原則、技術棧、資料流程、元件說明

**設定更新：**
- `CLAUDE.md`（專案）：新增文件規範區塊
- `~/.claude/CLAUDE.md`（全域）：新增「建立新 app 必須建立 docs 目錄」規則

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `docs/INSTALL.md` | 新建 |
| `docs/USER_MANUAL.md` | 新建 |
| `docs/ARCHITECTURE.md` | 新建 |
| `CLAUDE.md` | 新增文件規範區塊 |

---

### 2026-03-11 — 移除 CDN 依賴，改用本地資源

**動機：** 消除對外部 CDN 的執行期依賴，提升可靠性與安全性。

**Markdown 渲染（marked.js → kramdown）**

- 移除 `cdn.jsdelivr.net/npm/marked` CDN script
- 新增 `kramdown` gem（伺服器端渲染）
- `ReportsController#company_news`：將 `content_md` 欄位改為伺服器端預先渲染成 `content_html`（HTML 字串）後回傳 JSON
- 新增 `POST /momentum/render_markdown` endpoint：供歐歐 AI 分析 SSE 串流結束後，將完整 markdown 文字送至伺服器轉成 HTML 再注入頁面
- `DailyMomentum::NewsTabPanelComponent`：改用 `content_html`，移除 `marked.parse()` 呼叫
- `DailyMomentum::AnalysisPanelComponent`：SSE `[DONE]` 後改以 `fetch POST /momentum/render_markdown` 取得 HTML

**Tailwind CSS（CDN → 本地編譯）**

- 移除 `cdn.tailwindcss.com` CDN script（原存在於 `application.html.erb`、`component_preview.html.erb`、`FairValue::PageLayoutComponent`）
- 新增 `tailwindcss-rails` gem，執行 `tailwindcss:install` 初始化
- 編譯輸出：`app/assets/builds/tailwind.css`（由 propshaft 提供）
- 原 `application.html.erb` inline `<style>` 區塊（`.md-body` 樣式、NProgress 顏色）移至 `app/assets/tailwind/application.css`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `Gemfile` | 新增 `kramdown`, `tailwindcss-rails` |
| `config/routes.rb` | 新增 `POST /momentum/render_markdown` |
| `app/controllers/reports_controller.rb` | 新增 `render_markdown` action；`company_news` 改回傳 `content_html` |
| `app/assets/tailwind/application.css` | 新建；移入 `.md-body` 與 NProgress 樣式 |
| `app/views/layouts/application.html.erb` | 移除 CDN scripts/styles；改用 `stylesheet_link_tag "tailwind"` |
| `app/views/layouts/component_preview.html.erb` | 同上 |
| `app/components/fair_value/page_layout_component.rb` | 移除硬編碼 Tailwind CDN script |
| `app/components/daily_momentum/analysis_panel_component.rb` | 改用 `fetch POST` 取得伺服器端渲染 HTML |
| `app/components/daily_momentum/news_tab_panel_component.rb` | 改用 `content_html` |

---

### 2026-03-11 — 強化歐歐分析品質與效能

**動機：** 補充更豐富的技術面數據給 AI 分析，並消除 `fetch_stocks` 的序列 HTTP 瓶頸。

**分析品質提升（`OuouAnalysisService`）**

- 新增「52週位置」：計算現價在52週區間的百分位（%），並附距高點/低點距離
- 新增「20日動量」：原本只有5日動量，現在同時提供20日動量供趨勢判斷
- 新增「成交量 vs 20日均量」：判斷是否放量，格式：`今日量 vs 均量（比率%）`
- `compute_momentum` 重構為接受 `days` 參數，統一5日/20日計算邏輯

**Yahoo Finance 資料擴充（`YahooFinanceService`）**

- 新增 `volumes` 陣列（從 `indicators.quote.volume` 取出），供均量計算使用
- `empty_result` 同步補上 `volumes: []`

**效能優化（`MomentumReportService`）**

- `fetch_stocks` 改為平行化：每個 symbol 各開一個 Thread 同時呼叫 Finnhub + Yahoo
- 原本5個 symbol 最差需等待 100 秒（序列），現在縮短為單次 timeout（10秒）

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/yahoo_finance_service.rb` | 新增 `volumes` 陣列欄位 |
| `app/services/momentum_report_service.rb` | `fetch_stocks` 平行化，抽出 `fetch_stock` 私有方法 |
| `app/services/ouou_analysis_service.rb` | 新增 `position_in_52w`、`volume_vs_avg`、`fmt_vol`；`compute_momentum` 接受 `days` 參數；prompt 加入三項新指標 |

---

### 2026-03-11 — 修正 Markdown 表格無法正確渲染

**問題：** Claude 生成的 markdown 表格使用 GFM 格式（`|---|---|`），但 `Kramdown::Document.new(text)` 預設使用 kramdown 自己的 parser，對 GFM 表格相容性不足，導致 pipe 字元全部輸出為純文字，表格完全走版。

**修正：**

- 新增 `kramdown-parser-gfm` gem
- 所有 `Kramdown::Document.new(text)` 改為 `Kramdown::Document.new(text, input: "GFM")`，使用 GFM parser 解析

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `Gemfile` | 新增 `kramdown-parser-gfm ~> 1.1` |
| `app/controllers/reports_controller.rb` | `render_markdown` 與 `company_news` 兩處改用 `input: "GFM"` |

---

### 2026-03-11 — 修正 em-dash 破折號導致表格仍然壞版及標題不解析

**問題：** Claude 在 table separator row 使用中文破折號 `——`（U+2014）而非 ASCII `-`，即使 GFM parser 也無法識別此 separator，導致整個表格被當成純文字段落輸出，並連帶使後續 `###` 標題無法正確解析。

**修正：**

- 新增 `normalize_md_separators` 私有方法：逐行掃描，若某行符合「全由 `|`、空白、`-`、`:`、`—`、`–` 組成」的 separator 特徵，則將破折號替換為 `---`
- 新增 `render_gfm` 私有方法統一呼叫流程：`normalize → Kramdown GFM → HTML`
- `render_markdown` action 與 `company_news` 改用 `render_gfm`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/reports_controller.rb` | 新增 `render_gfm`、`normalize_md_separators` 私有方法 |

---

### 2026-03-11 — 歐歐分析結果 3 小時 Cache

**動機：** 同一股票在 1 小時內重複按下分析按鈕，不應重新呼叫 Groq API，直接回傳快取內容，節省 API 費用並提升回應速度。

**實作方式（純 server 端，JS 無需改動）：**

- Cache key：`ouou_analysis:{SYMBOL}`，TTL 3 小時
- **Cache hit**：`OuouAnalysisService#call` 直接 yield 完整快取文字，controller 照常寫入 SSE stream，client 端收到後一次性觸發 `[DONE]` → `renderMarkdown`，體驗與首次相同，僅速度差異
- **Cache miss**：串流過程中累積所有 chunks，串流結束後寫入 `Rails.cache`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/ouou_analysis_service.rb` | 新增 `CACHE_TTL`、`CACHE_PREFIX` 常數；`call` 加入 cache 讀寫邏輯；新增 `cache_key` 私有方法 |

---

### 2026-03-11 — 歐歐分析匯出 PNG / PDF，並附加分析日期

**動機：** 讓使用者可將歐歐分析結果儲存為 PNG 圖片或列印成 PDF，並在文末標記分析時間。

**分析日期標記（`OuouAnalysisService`）**

- 串流完成後自動 append markdown footer：`*📌 歐歐分析時間：YYYY-MM-DD HH:MM ET*`
- 連同日期一起寫入 cache，cache hit 時日期也自動帶出
- 日期以 italic 段落呈現在分析面板底部

**匯出功能（`AnalysisPanelComponent`）**

- `renderMarkdown` 完成後，在分析內容下方加入兩個按鈕：**⬇ 下載 PNG**、**⬇ 下載 PDF**
- **PNG**：`html2canvas` 擷取 `.md-body` div（含日期），scale=2 高解析度，下載檔名格式 `{SYMBOL}_歐歐分析_{DATE}.png`
- **PDF**：開新視窗並注入完整 CSS（含 `.md-body` 所有樣式），呼叫 `window.print()` 讓瀏覽器另存 PDF

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/ouou_analysis_service.rb` | 新增 `analysis_date_footer` 方法；串流完成後 emit footer chunk 並寫入 cache |
| `app/views/layouts/application.html.erb` | 新增 `html2canvas@1.4.1` CDN script |
| `app/components/daily_momentum/analysis_panel_component.rb` | `renderMarkdown` 加入匯出按鈕；新增 `exportPng`、`exportPdf` 函式與 click 委派 |

### 2026-04-17 — Options 頁面三框格可調整大小 + Navbar 字體大小控制

**新增功能**

- `react-resizable-panels` v4 接入 Options 頁面，支援三組可拖動邊界（左側 sidebar / 損益圖 / 策略列表）
- 各面板位置自動記憶至 localStorage（`react-resizable-panels:options-*`）
- Header 新增「↺ 還原版面」按鈕，一鍵恢復預設比例（13/87/34/66/22/78%）
- Navbar AppSwitcher 右側加入五個字體大小按鍵（14–18px），含 `fairprice:font-size` localStorage 記憶與早期渲染腳本（防 FOUC）

**修正 Bug**

- `react-resizable-panels` v4 Panel 尺寸 prop 必須為字串百分比（如 `"13%"`），傳入純數字會被解讀為 px，導致面板被 maxSize 鎖死在 ~2%
- `options-root` 缺少 `flex flex-col`，造成 React `h-full` 失效、Group 高度僅 288px（修正後 517px）
- React 根容器改為 `flex-1 min-h-0`，確保在 flex 父容器中正確撐開高度

**涉及檔案**

| 檔案 | 說明 |
|------|------|
| `app/frontend/options/OptionsAnalyzerApp.tsx` | 主要改寫：Panel 尺寸改字串 %、根容器高度修正 |
| `app/components/options/page_component.rb` | 加入 `flex flex-col` 解決高度鏈問題 |
| `app/components/fair_value/font_size_controls_component.rb` | 新建：5 個字體大小按鍵元件 |
| `app/components/fair_value/navbar_component.rb` | 加入 FontSizeControls |
| `app/views/layouts/application.html.erb` | 加入早期渲染字體大小腳本 |
| `app/assets/tailwind/application.css` | 新增 resize handle 靜態 class 定義 |
| `package.json` | 新增 react-resizable-panels ^4.10.0 |

### 2026-04-03 — routes.rb 重構：抽常數、改用 resources

整理 `config/routes.rb`，消除重複定義與手動展開的 REST 路由。

**異動內容**

- 抽出 `TICKER_CONSTRAINT` 常數，取代原本分散在 7 處的相同正規表達式
- `api/v1/margin_positions`：手動 `get price_lookup` + 手動 `post close` 改用 `resources` + `collection`/`member` block
- `watchlist`：9 條手動路由改用 `resources :watchlist_alerts, controller: :stock_alerts`
- `portfolio`：8 條手動路由改用 `resources :portfolios`，collection 補上 `ocr_import`/`reorder`/`quotes`/`ownership`
- 同步更新 named route helper：`watchlist_path` → `watchlist_alerts_path`、`portfolio_index_path` → `portfolios_path`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `config/routes.rb` | 重構 |
| `app/controllers/stock_alerts_controller.rb` | 更新 named route helper |
| `app/controllers/portfolios_controller.rb` | 更新 named route helper |
| `app/components/stock_alert/alert_form_component.rb` | 更新 named route helper |
| `app/components/stock_alert/alert_list_component.rb` | 更新 named route helper |

---

### 2026-03-31 — 技術圖表：lightweight-charts 蠟燭圖、S&R 線、RSI 雙線

重寫 `TechnicalsChart.tsx`，從 Recharts 改用 lightweight-charts（TradingView 開源）。

**主要功能**

- 蠟燭圖（K 線）取代折線圖
- 支撐/阻力線：`createPriceLine()` 直接標註在 Y 軸（阻力橘、支撐翠綠）
- RSI14（紫）/ RSI7（藍）雙線，`lastValueVisible: true` 在軸上顯示即時數值
- 時間範圍新增 1D（5 分線）、5D（15 分線），日內不顯示 S&R
- 後端 `calc_rsi` 修正為 Wilder's EMA（非簡單平均）
- `YahooFinanceService` 補齊 open/high/low 欄位，zip 後過濾 nil-close bars

**防錯工具（同日新增）**

- `eslint.config.js`：`eslint-plugin-react-hooks` — 自動 hook 於每次 TSX 編輯後執行
- `spec/requests/api/v1/charts_rsi_spec.rb`：鎖定 Wilder's EMA 算法，7 examples
- `stories/TechnicalsChart.stories.tsx`：Chromatic 三種寬度視覺回歸（1280/768/375px）

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/frontend/technicals/TechnicalsChart.tsx` | 完整重寫，Recharts → lightweight-charts |
| `app/controllers/api/v1/charts_controller.rb` | 新增 1D/5D range、open/high/low、Wilder's RSI |
| `app/services/yahoo_finance_service.rb` | 補齊 OHLC，zip 過濾 nil-close |
| `eslint.config.js` | 新增（ESLint + react-hooks + typescript-eslint）|
| `spec/requests/api/v1/charts_rsi_spec.rb` | 新增（RSI 算法單元測試）|
| `stories/TechnicalsChart.stories.tsx` | 新增（Chromatic 視覺回歸）|

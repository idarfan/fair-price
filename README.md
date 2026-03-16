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

### 2026-03-16 — 安全性強化：CSP 啟用、ValuationService 測試、open_timeout 修正

**動機：** Rails 審計發現三項安全/品質問題：CSP header 未啟用、核心估值邏輯 0% 測試覆蓋率、Anthropic API 連線無 open_timeout 可能永久阻塞 worker。

**異動內容：**
- `config/initializers/content_security_policy.rb`：啟用 Content Security Policy，設定 `default_src :self`、`script_src/style_src` 允許 `cdn.jsdelivr.net` 及 `unsafe_inline`（NProgress inline script）、`connect_src :self`（SSE streaming）、`object_src/frame_ancestors :none`
- `app/services/ouou_analysis_service.rb`：`Net::HTTP.start` 加入 `open_timeout: 10`，防止 Anthropic API 不可達時 worker 永久阻塞
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

**動機：** 同一股票在 1 小時內重複按下分析按鈕，不應重新呼叫 Anthropic API，直接回傳快取內容，節省 API 費用並提升回應速度。

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

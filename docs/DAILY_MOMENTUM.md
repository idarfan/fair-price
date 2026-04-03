# DAILY_MOMENTUM.md — Daily Momentum 運作邏輯說明

本文件深入說明 `http://localhost:3003/momentum` 的完整運作邏輯，補充 `ARCHITECTURE.md` 中的高層概覽。

---

## 一、路由總表

| HTTP 方法 | 路徑 | Controller#Action | 說明 |
|-----------|------|-------------------|------|
| GET | `/momentum` | `ReportsController#index` | 主頁面 |
| GET | `/momentum/analysis` | `ReportsController#analysis` | AI 分析（SSE 串流） |
| POST | `/momentum/render_markdown` | `ReportsController#render_markdown` | Markdown → HTML |
| GET | `/momentum/news` | `ReportsController#company_news` | 個股新聞 |
| POST | `/momentum/watchlist` | `ReportsController#add_to_watchlist` | 新增自選股 |
| DELETE | `/momentum/watchlist/:symbol` | `ReportsController#remove_from_watchlist` | 刪除自選股 |
| PATCH | `/momentum/watchlist/reorder` | `ReportsController#reorder_watchlist` | 拖曳排序 |
| PATCH | `/momentum/watchlist/:symbol` | `ReportsController#update_watchlist_symbol` | 編輯代號 |

---

## 二、頁面載入資料流

```
GET /momentum
  └── ReportsController#index
        ├── WatchlistItem.ordered
        │     → 從 PostgreSQL 取得自選股清單（依 position 欄位排序）
        │     → 若 DB 為空，降回 config/watchlist.yml
        └── MomentumReportService.new(symbols: [...]).call
              ├── VixService#fetch
              │     → Yahoo Finance ^VIX 現值
              ├── YahooFinanceService#quote("ES=F")
              │     → E-mini S&P 500 期貨日漲跌幅
              ├── YahooFinanceService#quote("NQ=F")
              │     → Nasdaq 100 期貨日漲跌幅
              ├── Thread.new × N（平行）
              │     └── fetch_stock(symbol)
              │           ├── FinnhubService#quote(symbol)
              │           │     → 現價、日漲跌、OHLC
              │           └── YahooFinanceService#candles(symbol, 1y)
              │                 → 52週高低、20日均量
              └── FinnhubService#earnings_calendar(from: today, to: today+7)
                    → 未來 7 天財報日曆

回傳凍結 Hash → derive_stance(@vix) → 渲染各 Phlex 元件
```

**市場時段判斷**（`MomentumReportService#time_segment`，以 ET 時鐘為準）：

| 時段 | ET 時間 | Badge 文字 |
|------|---------|-----------|
| `:pre_market` | 08:00–09:30 | 盤前 🌅 |
| `:market_hours` | 09:30–16:00 | 盤中 🟢 |
| `:after_hours` | 16:00–20:00 / 00:00–02:00 | 盤後 🌙 |
| `:closed` | 其他 | 休市 💤 |

---

## 三、AI 分析（歐歐 🐱）串流流程

```
使用者點擊 watchlist 列的 🐱 按鈕
  └── AnalysisPanelComponent（JS）
        → 建立 EventSource: GET /momentum/analysis?symbol=AAPL
              └── ReportsController#analysis（SSE endpoint）
                    └── OuouAnalysisService#call(symbol) do |chunk|
                          response.stream.write "data: #{chunk}\n\n"
                        end

OuouAnalysisService#call 內部：

  [Cache hit]
    Rails.cache 鍵值：ouou_analysis:SYMBOL（TTL 3 小時）
    → yield 快取全文（逐 chunk）

  [Cache miss]
    ├── FinnhubService#quote(symbol)         → 現價、OHLC
    ├── YahooFinanceService#candles(1y)      → 歷史收盤、成交量
    ├── FinnhubService#company_news(5)       → 最近 5 則新聞標題
    ├── VixService#fetch                     → VIX 現值
    ├── build_momentum_table                 → Ruby 預建 Markdown 表格
    │     含：5 日動量%、20 日動量%、成交量 vs 20日均量
    ├── build_prompt                         → 組合完整 prompt（含表格與數據）
    └── stream_request（HTTP POST to Groq API）
          模型：llama-3.3-70b-versatile
          max_tokens：4096
          → 解析 SSE content_block_delta 事件
          → 逐 chunk yield 給 controller
          → 串流結束後 Rails.cache.write（含 ET 時間戳記 footer）

串流結束（[DONE] 事件）
  └── AnalysisPanelComponent（JS）
        → POST /momentum/render_markdown { text: rawMarkdown }
              └── ReportsController#render_markdown
                    ├── normalize_md_tables(text)
                    │     → Pass 1：重建所有 separator row（處理非 ASCII 破折號）
                    │     → Pass 2：移除 separator row 前的空白行
                    └── Kramdown::Document.new(normalized, input: "GFM").to_html
                          → 回傳 JSON { html: "..." }
                          → JS 注入 .md-body div
```

**Markdown 表格策略**：凡伺服器端已計算好的數據，一律由 Ruby 在 `build_momentum_table` 中預建表格，並告知 AI「原文輸出，不得更改任何符號或格式」，避免 AI 自行排版造成格式損壞。`normalize_md_tables` 則作為備用保障，修正 AI 可能帶入的非標準破折號。

---

## 四、個股新聞載入流程

```
使用者點擊 watchlist 列的新聞按鈕
  └── NewsTabPanelComponent（JS）
        → 若 loaded[symbol] 已存在 → 直接切換至該 tab
        → 否則 fetch GET /momentum/news?symbol=AAPL
              └── ReportsController#company_news
                    └── FinnhubService#company_news(symbol, from: 7天前, to: 今天)
                          → 回傳 JSON 新聞陣列
                          → JS 動態建立 tab + 渲染新聞清單
```

---

## 五、Watchlist 管理流程

```
新增自選股
  └── SearchBarComponent（form POST /momentum/watchlist）
        → ReportsController#add_to_watchlist
              → WatchlistItem.create(symbol:, position: 最末)

刪除自選股
  └── WatchlistManagerComponent（DELETE /momentum/watchlist/:symbol）
        → ReportsController#remove_from_watchlist
              → WatchlistItem.find_by(symbol:).destroy

拖曳排序
  └── SortableJS（onEnd 事件）
        → PATCH /momentum/watchlist/reorder { symbols: [...] }
              → ReportsController#reorder_watchlist
                    → WatchlistItem.reorder!(symbols)

資料來源優先順序：
  1. PostgreSQL（WatchlistItem model，依 position 排序）
  2. config/watchlist.yml（DB 為空時的備用）
```

---

## 六、各 Phlex 元件職責

| 元件 | 檔案 | 職責 |
|------|------|------|
| `TimeSegmentBadgeComponent` | `daily_momentum/time_segment_badge_component.rb` | 市場時段 badge + ET 時間 |
| `MarketStanceComponent` | `daily_momentum/market_stance_component.rb` | 歐歐立場（VIX 閾值驅動）+ ES/NQ 期貨 |
| `SearchBarComponent` | `daily_momentum/search_bar_component.rb` | 新增自選股表單 |
| `WatchlistManagerComponent` | `daily_momentum/watchlist_manager_component.rb` | 可排序表格、Logo、編輯/刪除 |
| `RiskAlertComponent` | `daily_momentum/risk_alert_component.rb` | VIX 風險等級、財報日曆、倉位建議 |
| `NewsTabPanelComponent` | `daily_momentum/news_tab_panel_component.rb` | 個股新聞分頁（on-demand） |
| `AnalysisPanelComponent` | `daily_momentum/analysis_panel_component.rb` | AI 分析串流 + Markdown 渲染 + 匯出 |

### MarketStanceComponent — VIX 立場對應

| VIX 區間 | 立場 | 顏色 |
|----------|------|------|
| < 16 | 🟢 激進買入 | 綠色 |
| 16–22 | 🟡 保守買入 | 黃色 |
| > 22 | 🔴 持幣觀望 | 紅色 |

---

## 七、重要設計決策

| 決策 | 原因 |
|------|------|
| Markdown 表格由 Ruby 預建 | AI 排版不穩定，預建後告知原文輸出，保證格式正確 |
| AI 分析 Rails.cache 3 小時 TTL | 避免重複呼叫 Claude API（高成本），市場動態 3 小時內變化有限 |
| 平行 Thread 抓取股價 | watchlist N 支股票若序列抓取等待時間為 O(N)，平行化降至 O(1) |
| 純原生 JS + 事件委派 | 明確禁用 Hotwire，避免 Turbo 隱式行為干擾 SSE 串流 |
| SSE 而非 WebSocket | 單向推播場景，SSE 實作更簡單，Rails 原生支援，無需額外基礎設施 |
| Logo 多層備用 | Parqet → Finnhub → 文字 Initials，確保任何股票代號都有視覺識別 |

---

## 八、改善方向

### 1. 股價快取缺失（優先順序：高）

**現況：** 每次頁面載入都重新呼叫 Finnhub（N 支股票 × 2 API each），頁面等待時間隨 watchlist 大小線性增加。

**建議：** 在 `MomentumReportService#fetch_stock` 加入 `Rails.cache`，TTL 設為 60 秒（盤中）或 5 分鐘（盤後/休市）：

```ruby
def fetch_stock(symbol)
  Rails.cache.fetch("momentum_quote:#{symbol}", expires_in: 60.seconds) do
    # 現有 fetch 邏輯
  end
end
```

**預期效益：** 同一分鐘內刷新頁面直接命中快取，API 消耗降低約 80%。

---

### 2. `market_news` 廢棄呼叫（優先順序：中）

**現況：** `FinnhubService#market_news` 曾被 `MomentumReportService` 呼叫，但結果目前未渲染至頁面任何區塊，屬於無用 API 請求。

**建議：** 確認是否有保留計畫；若無，從 `MomentumReportService#call` 移除此呼叫，並清理相關 instance variable。

---

### 3. SSE 串流無重連機制（優先順序：中）

**現況：** `AnalysisPanelComponent` 的 `EventSource` 在網路中斷時會靜默失敗，使用者不知道串流是否成功。

**建議：** 在 JS 加入 `onerror` 處理：

```javascript
source.onerror = () => {
  source.close();
  // 顯示「串流中斷，請點此重試」按鈕
  showRetryButton(symbol);
};
```

---

### 4. Finnhub 平行請求無上限（優先順序：中）

**現況：** watchlist 有 N 支股票時，Thread 同時發出最多 2N 個 Finnhub API 請求，可能觸發 rate limit（Finnhub 免費方案每分鐘 60 次）。

**建議：** 使用 `Concurrent::Semaphore` 或分批處理（每批 5 支），控制同時在飛的請求數：

```ruby
semaphore = Mutex.new
results = []
symbols.each_slice(5) do |batch|
  threads = batch.map { |sym| Thread.new { fetch_stock(sym) } }
  results.concat(threads.map(&:value))
end
```

---

### 5. VIX 立場閾值硬編碼（優先順序：低）

**現況：** VIX < 16 / 16–22 / > 22 的門檻分散硬編碼在 `ReportsController#derive_stance`、`ApplicationHelper#risk_level`、`MarketStanceComponent` 等多處。

**建議：** 集中至常數模組或 `config/momentum.yml`：

```yaml
# config/momentum.yml
vix_thresholds:
  aggressive_below: 16
  conservative_above: 22
```

修改策略時只需更新一處。

---

### 6. 行動裝置體驗（優先順序：低）

**現況：** `WatchlistManagerComponent` 的表格在小螢幕橫向滾動，52 週 range bar 等欄位在手機上可讀性差。

**建議：** 加入 `sm:hidden` / `md:table-cell` Tailwind 條件，小螢幕只保留 symbol + price + change%；或改為 card 樣式：

```ruby
# 範例：中等螢幕以下隱藏次要欄位
th { "成交量"; css_class "hidden md:table-cell" }
```

---

---

## 九、相關檔案索引

| 分類 | 檔案路徑 |
|------|---------|
| Controller | `app/controllers/reports_controller.rb` |
| 報告聚合服務 | `app/services/momentum_report_service.rb` |
| AI 分析服務 | `app/services/ouou_analysis_service.rb` |
| Finnhub 客戶端 | `app/services/finnhub_service.rb` |
| Yahoo Finance 客戶端 | `app/services/yahoo_finance_service.rb` |
| VIX 服務 | `app/services/vix_service.rb` |
| 自選股設定 | `config/watchlist.yml` |
| 元件目錄 | `app/components/daily_momentum/` |
| 主頁面模板 | `app/views/reports/index.html.erb` |

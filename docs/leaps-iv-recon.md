# LEAPS IV 環境 — P0 偵察紀錄

> 規格：`leaps-iv-environment.md`（BASE `1d03c66`）。偵察日 2026-11-06（台北），只讀，未改任何程式。
> Barchart 實測一律在 9222 的 Chrome **另開分頁**、測完關閉（前後分頁數皆為 1），Premier 已登入（頁首 `barchartPremier`、`Hi, Idar`）。

## LEAPS 爬蟲

- Python 爬蟲：`lib/barchart_scrapers/leaps_scraper.py`，進入點 `main(symbol, user_strike=None)`（`:367`），CLI：`python3 leaps_scraper.py SYMBOL [user_strike]`。
- 觸發鏈：`LeapsRecommendationsController#analyze`（`app/controllers/leaps_recommendations_controller.rb:127`）→ `ScrapeLeapsJob.join_or_start`／`perform_later`（`:167-169`）→ `ScrapeLeapsJob#scrape_and_record`（`app/jobs/scrape_leaps_job.rb:55`）→ `BarchartScraperService#fetch_leaps(user_strike:)`（`app/services/barchart_scraper_service.rb:78`）→ `#run_scraper("leaps", …)`（`:96`、定義於 `:533`）→ 寫入 `#persist_chain_snapshot`＋`#persist_leaps`（`:106-107`、`:652`）。
- `fetch_leaps` 在 `LeapsOptionChainSnapshot.fresh_for?` 為真時直接回 `cached`，不跑爬蟲（`:90-94`）；`FRESH_WINDOW = 1.hour`（`app/models/leaps_option_chain_snapshot.rb:7`）。
- 同一 job 之後另跑 `fetch_pmcc_short_calls`（`scrape_leaps_job.rb:69`、`:91`），失敗不影響 LEAPS 狀態。
- 爬蟲讀取順序（`leaps_scraper.py`）：
  1. Stage 1：`/options?moneyness=10`（近月）讀 `NEAR_MONEY_JS`（`:61-77`，只有 strike、delta）與現價 `UNDERLYING_JS`（`:92`）。
  2. 取第一個 DTE ≥ 364 的到期日，開 `/options?moneyness=100&expiration=…` 讀該到期日完整履約價（`:428-444`，同樣只有 strike、delta）。
  3. `_pick_candidates`（`:200-282`）挑候選履約價（`:506-512`）。
  4. Stage 2：每個候選履約價開 `/options?view=stacked&strike=X`（`:519-602`），`STACKED_OPTIONS_JS`（`:125-148`）一次讀出**該履約價所有到期日**的 bid/ask/mid/last/volume/oi/delta/**iv（`r.volatility`）**/moneyness；再開 `/volatility-greeks?expiration=…&strike=X`（`:604-`）讀 vega/itm_prob/vol_oi。

## 期權鏈快照資料表

- Model：`app/models/leaps_option_chain_snapshot.rb`；table：`leaps_option_chain_snapshots`（`db/schema.rb:169-193`）。
- 欄位：`id`, `ask` decimal(10,4), `bid` decimal(10,4), `created_at`, `delta` decimal(8,6), `dte` integer, `expiration_date` date not null, `extrinsic_value` decimal(10,4), `intrinsic_value` decimal(10,4), `itm_probability` decimal(8,6), `iv` decimal(8,6), `last_price` decimal(10,4), `open_interest` integer, `option_type` string not null, `scraped_at` datetime not null, `strike` decimal(10,4) not null, `symbol` string not null, `underlying_price` decimal(10,4), `updated_at`, `vega` decimal(10,6), `vol_oi_ratio` decimal(8,4), `volume` integer。
- 索引：唯一 `[symbol, expiration_date, strike, option_type]`（`idx_leaps_chain_unique`）、`[symbol, scraped_at]`。
- **沒有歷史**：`persist_leaps` 每次先 `where(symbol:).delete_all` 再 `insert_all`（`barchart_scraper_service.rb:701-704`），表裡只留最新一次抓取。
- 相關：`strike_chain_snapshots`（`db/schema.rb:560-570`，每 symbol 一列：`strikes` jsonb、`spot_price`、`chain_expiration_date`、`last_query_strike`）。

## Delta 篩選位置

- **主要篩選在爬蟲端（頁面端）**：`leaps_scraper.py` 的 `_pick_candidates`（`:200-282`），auto 模式取 `LEAPS_MIN_DELTA 0.60 ≤ delta ≤ LEAPS_MAX_DELTA 0.90`（常數 `:54`、`:58`；判斷 `:235`、`:259-260`）；manual 模式（有 user_strike）取中心±緩衝、不看 Delta（`:230`）。
- Rails 端另有排行篩選：`LeapsRankingService`（`app/services/leaps_ranking_service.rb:4` `DEFAULT_DELTA_MIN = 0.60`，`:42` `.where("delta >= ?", @delta_min)`），只作用在已存進 DB 的列。
- **未通過篩選的履約價 IV 沒有被存下**：Stage 1 的兩次讀取只取 strike 與 delta（`NEAR_MONEY_JS` `:71-74`），IV 只在 Stage 2 對「候選履約價」讀取；非候選履約價從未讀到 IV。
- 實測（TSM，2026-11-06 05:20 UTC 那次抓取）：DB 只有履約價 200–360 共 17 檔（moneyness 約 0.57–1.02），現價 353.10；規格要求的 0.60–1.25 上半段（≈ 360–441）大多缺。這次 ATM 剛好算得出來，是因為 2028-01-21 的 360 Call Delta = 0.603069 恰好 ≥ 0.60；換一天或換標的，夾住現價的上側履約價可能落在 Delta < 0.60 而缺 IV。→ P2 必須依規格 P2.1 後段改為「讀完整履約價列表後再篩」。

## PMCC 短天期鏈

- `app/models/pmcc_short_call_snapshot.rb`；table `pmcc_short_call_snapshots`（`db/schema.rb:444-478`）。
- **有 IV、DTE、strike**：`iv` decimal(8,6)、`dte` integer、`strike` decimal(10,4) not null；另有 `expiration_date`、`delta`、`moneyness` decimal(8,4)、`underlying_price`、`scraped_at` 等。唯一索引 `[symbol, expiration_date, strike]`。
- 爬蟲 `lib/barchart_scrapers/pmcc_short_call_scraper.py`：Short DTE 19–45 天的近三個到期日 × 全履約價（另加持有中短腳的到期日，`barchart_scraper_service.rb:711-720`）。
- 可作為曲面短天期段（全履約價、有 IV）。注意：與 LEAPS 表一樣每次覆蓋，沒有歷史；`FRESH_WINDOW` 同為 1 小時。

## Barchart IV 指標 DOM

頁面：`https://www.barchart.com/stocks/quotes/TSM/options-history`（Premier 已登入）。截圖 `tmp/recon/barchart_iv.png`（2 Years 區間）。

- **表格**：Angular `bc-data-grid`（頁面唯一一個），資料讀 `document.querySelector('bc-data-grid')._data`，每列 `r.raw || r`（同既有爬蟲的讀法，見 `reference_barchart_options_flow_dom`）。畫面欄位順序：Date、Imp Vol、1D IV Chg、IV Rank、IV Pctl、P/C Vol、Options Vol、P/C OI、Total OI、Last（與規格人工實測一致）。對應 raw key（同順序）：`date`、`weightedImpliedVolatility`、`weightedImpliedVolatilityChange`、`impliedVolatilityRank1y`、`impliedVolatilityPercentile1y`、`putCallVolumeRatio`、`totalVolume`、`putCallOpenInterestRatio`、`totalOpenInterest`、`historicalLastPrice`。
- **單位（實測 2026-11-05 列）**：`weightedImpliedVolatility` 0.51924588（小數，畫面 51.92%）；`impliedVolatilityRank1y` 82.442713996768（已是 0–100，畫面 82.44%）；`impliedVolatilityPercentile1y` 0.92430278884462（**小數**，畫面 92%）→ 存 `iv_pctl` 時要 ×100；`putCallVolumeRatio` 0.91820624；`totalVolume` 418426；`putCallOpenInterestRatio` 0.98123226；`totalOpenInterest` 1921298；`historicalLastPrice` 353.1。與規格 P2 驗收值（0.51920／82.44／92.00／0.9200／353.1000）一致（四捨五入後）。
- **Select History**：自訂下拉，不是 `<select>`。容器 `div.bc-price-history-periods`，開關 `.bc-price-history-periods .bc-dropdown-flexible-toggle`，選項 `#bc-price-history-time-frame li`（`data-ng-click="changePeriod(item)"`，目前選項帶 `.active`）。選項只有 **1M、3M、6M、1Y、2Y**。實測列數：

  | 選項 | 列數 | 日期範圍 |
  |---|---|---|
  | 1M | 22 | 2026-10-07 ～ 2026-11-05 |
  | 3M（預設） | 65 | 2026-08-06 ～ 2026-11-05 |
  | 6M | 130 | 2026-05-04 ～ 2026-11-05 |
  | 1Y | 260 | 2025-10-23 ～ 2026-11-05 |
  | **2Y（最長）** | **520** | 2024-10-09 ～ 2026-11-05 |

  頁面說明「available back to October 2018」**無法透過表格取得**：最長只有 2Y。
- **區間選擇會被記住**：切到 2Y 後重新開頁，預設就是 2Y（520 列）。爬蟲每次都必須明確切換區間，不能假設預設 3M；偵察結束時已切回 3M 並重新載入確認（65 列、「3 Months」）。
- **download**：`a.bc-btn-icon.download`（屬性 `data-ref=historical`、`data-use-limit=true`、`data-add-field=underlyingLastPrice,totalVolume,callVolume,putVolume,callOpenInterest,putOpenInterest,totalOpenInterest`）。實測兩次：第一次點擊後分頁跳到 CloudFront **504 Gateway Timeout**；第二次 Playwright 收到 download 事件，但 `connect_over_cdp` 下 `Download.save_as` 回 `canceled`，**CSV 未取得、欄位未驗證**。因表格 2Y 已能完整讀出 520 列，backfill 依規格優先用表格即可，不需要下載。
- **頁首 HV：本頁沒有**。options-history 頁只有右欄「52-Week Implied Volatility：IV High 56.28% on 07/06/26、IV Low 31.49% on 10/15/26」。HV 出現在：
  - `/stocks/quotes/TSM/options` 與 `/volatility-greeks` 的標題列：`span.base-next-title`（內含 `span.hide-for-small-only`「Historic Volatility:」與 `span.show-for-small-only`「HV:」），其父元素文字為 `Historic Volatility: HV: 46.66%`。
  - `/stocks/quotes/TSM/overview`：`Implied Volatility 51.92% (+14.09%) Historical Volatility 46.66% IV Percentile 92% IV Rank 82.44% …`；同頁名詞說明為「30-Day Historical Volatility」。
  - **兩處標籤都不含天數**；「30-Day」只出現在 overview 頁的名詞說明。規格 `bc_hv_label`「含天數，例如 HV 20 天」無法照字面從標籤讀出。
- **報價時間（as_of_date 來源）**：頁首 `div.pricechangerow` 內的日期 span，實測 `11/05/26`（`[NYSE]`），盤後另有 `POST-MARKET 360.55 … 19:59 ET`。`pricechangerow` 帶 `data-ng-if="session && session !== 'Realtime'"`，盤中 session 為 Realtime 時結構可能不同，**盤中未實測**。

## pm2 排程

- ecosystem 檔：`ecosystem.config.cjs`（repo 根目錄）。
- **`margin-reminder` 不存在**：ecosystem 檔、`pm2 jlist`、`crontab -l` 都找不到。最接近的既有寫法是 `iv-daily-snapshot`（`ecosystem.config.cjs:73-78`）：`script: './bin/iv-daily-snapshot.sh'`、`cwd: '/home/idarfan/fairprice'`、`interpreter: '/bin/bash'`、`cron_restart: '30 20 * * 1-5'`、`autorestart: false`；`iv-skew-snapshot`（`:84-89`）、`iv-skew-intraday`（`:96-101`）同型。
- **時區**：pm2 daemon 為 **UTC**（`/proc/<PM2 pid>/environ` 實測 `TZ=UTC`；系統 `/etc/localtime` 為 Asia/Taipei）。既有 pm2 cron 都以 UTC 撰寫（`30 20 * * 1-5` ＝ 台北 04:30）。規格 P4 的 `30 6 * * 2-6`（註明「系統時區 Asia/Taipei」）在 pm2 會變成 **UTC 06:30＝台北 14:30**；若要台北 06:30，pm2 要寫 `30 22 * * 1-5`（UTC）。→ 需使用者裁示後 patch 規格。

## 圖表元件

- Chart.js 由 layout 以 CDN 載入：`app/views/layouts/application.html.erb:24`（`chart.js@4.4.1` UMD）、`:28`（`chartjs-plugin-annotation@3.0.1`）；型別宣告 `app/frontend/types/globals.d.ts`。
- IV Skew Tracker（`/iv_watchlists`）：`app/frontend/behaviors/ivWatchlists.ts`，`new Chart(...)` 於 `:126`（IV 折線）與 `:162`（Skew 長條），實例存在 `ivCharts` 物件、重繪前 `destroy()`（`:80-84`）；頁面元件 `app/components/iv_watchlists/index_view.rb`。
- 其他 Chart.js 使用：`ivEducationChart.ts`、`priceInCharts.ts`、`techDashOptionsCharts.ts`。

## 爬蟲併發控制

- **互動查詢與排程共用同一個 Chrome：9222**。`BarchartScraperService::CDP_URL = "http://127.0.0.1:9222"`（`barchart_scraper_service.rb:19`）、`cdp_helper.py:19` `CDP_BASE = "http://127.0.0.1:9222"`。**目前沒有 cdp-relay 9223**（pm2 只有 `chrome-cdp-keeper`（9222）與 `chrome-cdp-keeper-9224`），規格寫的「cdp-relay 9223」與現況不符。
- 既有機制：
  - `app/services/scraper_slots.rb`：`ScraperSlots`，`Concurrent::Semaphore` 上限 3（`MAX_CONCURRENT`），所有 `run_scraper` 都經過它（`barchart_scraper_service.rb:539`）。**程序內**號誌，只在 Puma 程序內有效。
  - `ScrapeLeapsJob` 的 `INFLIGHT_MUTEX`＋`Rails.cache` 登記（`scrape_leaps_job.rb:11-45`）：同 symbol＋同 user_strike 共用 job_id，同樣是程序內。
  - `app/services/leaps_spread_fetch_lock.rb`：`LeapsSpreadFetchLock`，PostgreSQL advisory lock（`pg_advisory_lock(hashtext('leaps_spread_fetch:SYMBOL'))`），**只給垂直價差 sidecar 用、依 symbol 分鎖**。
- **跨程序（pm2 排程 ↔ Puma 互動查詢）的 CDP 互斥：無**。→ P4 依規格新增 advisory lock。

## LEAPS 查詢紀錄

- 來源：`fetch_logs`（`app/models/fetch_log.rb`，`db/schema.rb:69-79`），`BarchartScraperService#log_fetch`（`:900-924`）每次 `fetch_leaps` 都寫一列，`fetch_type = 'leaps'`，`status` 白名單見 `fetch_log.rb:12-27`。
- `user_activities` 不可用：最近 30 天 `/leaps%` 有 99 筆瀏覽，但 `metadata` 沒有 symbol（0 筆）。
- 可執行 SQL（2026-11-06 實跑，回 9 個 symbol：AMD、BTI、CSCO、INTC、NOK、ORCL、SHOP、TSM、WULF；排除只有 error 的 `INTL`）：

  ```sql
  SELECT DISTINCT symbol
  FROM fetch_logs
  WHERE fetch_type = 'leaps'
    AND status IN ('success', 'cached', 'partial_error')
    AND fetched_at >= now() - interval '30 days'
  ORDER BY symbol;
  ```
- 限制：controller 若在 1 小時新鮮期內直接用快取（`leaps_recommendations_controller.rb:368-372` `fresh_data_exists?`），不會建立 job、也不寫 `fetch_logs`；同一 symbol 只要 30 天內有過一次實際抓取就會出現，對「是否查詢過」的判斷沒影響。

## 到期日與 DTE

TSM 最近一次 LEAPS 抓取（`leaps_option_chain_snapshots`，`scraped_at` 2026-11-06 05:20:50 UTC，現價 353.10）共 19 個到期日；stacked 頁一次回傳該履約價所有到期日（含短天期）：

| 到期日 | DTE | 到期日 | DTE |
|---|---|---|---|
| 2026-11-06 | 1 | 2027-03-19 | 134 |
| 2026-11-13 | 8 | 2027-04-16 | 162 |
| 2026-11-20 | 15 | 2027-06-17 | 224 |
| 2026-11-27 | 22 | 2027-09-17 | 316 |
| 2026-12-04 | 29 | 2027-12-17 | 407 |
| 2026-12-11 | 36 | **2028-01-21** | **442** |
| 2026-12-18 | 43 | **2028-06-16** | **589** |
| 2026-12-24 | 49 | 2028-12-15 | 771 |
| 2027-01-15 | 71 | 2029-01-19 | 806 |
| 2027-02-19 | 106 | | |

- LEAPS 段（DTE ≥ 364）為 407–806，與規格「唯一實測樣本 407–806」一致。
- **540 天被夾住**：442（2028-01-21）< 540 < 589（2028-06-16）。
- 夾住現價 353.10 的兩檔：2028-01-21 K=350 IV 0.4246／K=360 IV 0.4240；2028-06-16 K=350 IV 0.4295／K=360 IV 0.4287。
- 全年是否都夾得住 540 天：本次只有單日樣本，**未驗證**（規格已註明）。

## 收摺卡片與 tooltip

- `#leaps-week52-card`：`app/components/leaps_recommendations/price_context_component.rb`。外殼 `#card`（`:49-61`）：`details(id: anchor_id, class: "#{CARD_CLASS} pc-card", open: true, data: { pc_key: key })`，`CARD_CLASS = "bg-white rounded-2xl border border-gray-200 shadow-sm flex flex-col"`（`:15`）；summary class 與規格 P5 所列相同（`:51-52`），內含 `div.min-w-0 > h3.pc-title + p.pc-sub`（`:53-56`）與 `span.pc-chevron`（`:57`）。id 由 `render_range_card` 組成 `"leaps-#{key}-card"`（`:163`）。
- **與規格 P5 的差異（供 P5 參考）**：既有卡片是 `open: true`（伺服器端預設展開），收合狀態由 `app/frontend/behaviors/leapsPriceContext.ts` 存 `localStorage`（`STORAGE_PREFIX = "leaps-price-context:"` `:20`，讀 `:40`、寫 `:51`、套用 `:65`、監聽 `:69`），且 summary 有 `span.pc-chevron`。規格 P5 要求新區塊「預設收合（不加 open）」「不記憶展開狀態」，與既有卡片行為不同，但與規格明文一致。
- tooltips 原始檔：`app/assets/javascripts/leaps_recommendations/tooltips.js`（751 行）。正式站目前的 `public/assets/leaps_recommendations/tooltips-e7ec9843.js` 與原始檔逐位元組相同（`cmp`）。
  - `TIP_H` `:5`、`TIP_L` `:8`、`linesFor` `:36`、`LEAPS_COL_EXPLAIN` `:59`
  - `week52_card` `:500-511`、`day_card` `:512-`
  - `VERTICAL_SPREAD_EXPLAIN` `:534`；併入 `LEAPS_COL_EXPLAIN` 的 `Object.keys(...).forEach` `:576-578`
  - `TOUR_ORDER` `:584`；`"day_card"` 在 `:589`
  - `#leaps-col-tip` 建立 `:622`；點擊聚光 `overlayOpacity: 0.35` `:707`；欄位導覽 `:724`（`overlayOpacity: 0.4` `:744`）
- `#leaps-col-tip` 樣式：`app/assets/tailwind/application.css:226-` 起（`.tip-t` `:245`、`.tip-v` `:249`、`.tip-h` `:261`、`.tip-l` `:265`）；`.pc-*` 卡片樣式 `:11-49`。
- 既有 tooltip 測試：`app/frontend/behaviors/leapsTooltips.test.ts`。

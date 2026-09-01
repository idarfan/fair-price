# FairPrice

### 2026-09-01（二）— PMCC 部位追蹤 Phase 2–5 完成（滾倉判斷／建議／損益帳本／前端）

#### Phase 2 滾倉觸發判斷

`PmccRollTriggerService`：`delta >= 0.60`、`DTE <= 5 且 moneyness >= -5%`、手動觸發。
除息日規則因 schema 沒有 ex-dividend date 而移除。

- **寫規則前先確認 `moneyness` 慣例**（正=價內、負=價外，有既有測試佐證），
  否則 `>= -5%` 的方向會寫反，而且測試也抓不到——因為測資是自己編的
- **報價缺失回 `:no_quote` 而不是「不需滾倉」**：沒資料卻說沒事，
  使用者會以為系統看過了

#### Phase 3 滾倉建議

`PmccRollSuggestionService`，與 `PmccRankingService` 平行（那支回答「現在建倉
哪組最好」，這支回答「我手上這一腳該滾去哪」）。

**修正 `pmcc-tracker.md` 的黃金法則方向**：文件原本寫 `PL >= Spread` 通過，
與它自己引用的 `P_L < K_S − K_L` 相反，也與既有實作 `PmccRankingService:223`
的 `pl < spread` 相反。統一成 **NetDebit < Spread 才通過**。

**PL 基準用實付成本，市價只做顯示**：NetDebit／MaxProfit／黃金法則一律以
長腳實付成本計算，與損益帳本同一把尺；目前市價由 `pmcc_leg_quotes` 查出並列，
**不參與任何計算**（有 spec 釘住：市價從 129.7 改成 300，`net_debit` 一分不變）。

#### Phase 4 損益帳本

`PmccPnlService`。各事件類型的金額公式集中在 class method，Phase 5 直接呼叫，
不在表單各寫一份。**三個「回 nil 而不是 0」**：沒有長腳報價、未實現未知、
資本已回收完（`capital_deployed <= 0`）——理由都是「沒有資料不等於沒有問題」。

年化報酬率分母用 `capital_deployed`（實付成本 − 累積已實現）而非原始成本，
滾倉收租會持續降低實際投入。

#### Phase 5 前端

`pmcc_position_tracker.rb` ＋ `Api::V1::PmccPositionsController` ＋ `pmcc_tracker.js`。

- **與 `@pmcc_ranking` 解耦**是本期最重要的一條：只看 `current_user + symbol`，
  渲染放在 `if @candidates.any?` **外面**。部位是持久資料，抓取失敗不該消失
- `roll` **整段 transaction**：中途失敗留下「舊腳關了、新腳沒開」會讓帳本
  永遠對不起來，有 spec 驗整段回滾
- **偏離原 spec 一處**：原本寫「無部位時整個區塊不顯示」，那樣沒有入口建立
  第一筆部位、功能無法啟用，改為顯示精簡的「建立 PMCC 部位」收折列
- **class 命名撞車被既有測試抓到**：追蹤面板一開始共用 `.leaps-pmcc-bucket`，
  讓數到期日桶數的 spec 從 3 變 4。改用 `.leaps-pmcc-panel`，CSS 共用、語意分開

### 2026-09-01（二）— PMCC 部位追蹤 Phase 0–1，並修好 V&G 少帶 moneyness 的資料缺失

#### 先做可行性驗證，才發現最大的坑不在原本以為的地方

`pmcc-tracker.md` 的檢討結論是先加一個 **Phase 0**：證明長腳報價拿得到，
再蓋依賴它的損益帳本。做法是讓 `pmcc_short_call_scraper.py` 的
`select_expirations()` 接受 `extra` 參數，把長腳到期日一併帶進去抓——
**不新增第二支爬蟲**，因為抓取迴圈本身完全不看 DTE，能力一直都在，
差別只在沒人叫它去讀那個到期日。

```
python3 pmcc_short_call_scraper.py BE --expirations 2028-01-21
→ BE 100 @2028-01-21：dte 508, mid 129.7, delta 0.8978, OI 3893
```

長腳只需要 mid/delta（兩者都在 Options Prices 頁上），所以**跳過 V&G**，
固定成本從兩次頁面載入降到一次。

#### 實跑挖出的既有 bug：V&G 的 URL 少一個參數

DB 裡 BE 的 465 列**只有 140 列**有 theta/gamma/itm_probability。先猜是逾時
（當天上午才修過同類問題），把上限拉到 60 秒——**沒用**，
`skipped_expirations` 是空的，代表 V&G 有讀到資料只是對不起來。實測比對：

| 頁面 | 列數 | 履約價範圍 |
|---|---|---|
| V&G（原本，無 `moneyness`）| 20 | 160–255 |
| V&G（加 `moneyness=100`）| 49 | 115–355 |
| Options Prices（對照）| 49 | 115–355 |

`_merge_vg` 用 `(strike, expiration_date)` 對接，兩邊範圍不同就只有交集拿得到
greeks。補上參數後 **140/465 → 465/465**。這個 bug 直接卡住滾倉建議
（需要短腳的 theta 與 itm_probability），不做 Phase 0 會等到很後面才炸出來。

#### Phase 1 資料模型

`pmcc_positions` / `pmcc_short_legs` / `pmcc_pnl_events` / `pmcc_leg_quotes`。

- `rolled_to` 是 self-reference，migration 必須明寫
  `foreign_key: { to_table: :pmcc_short_legs }`，用簡寫 Rails 會去找不存在的
  `rolled_tos` 表
- DB 層 check constraint 不只靠 model 驗證（口數 > 0、履約價 > 0、
  買回成本 ≥ 0 允許 NULL、手續費 ≥ 0），比照 `margin_positions`
- `realized_pnl` **只記真實現金流**——已實現帳本的價值在於可稽核，
  混進估算就跟券商對帳單永遠對不起來
- `quote_snapshot`（jsonb）留存事件當下的報價，因為 `pmcc_leg_quotes`
  是覆蓋式快照、事後查不到

#### per-user 隔離：先決定不做，當天翻轉

原本判斷「不介意其他帳號看到持倉」就不加 `user_id`。翻轉的理由**不是可見性
而是寫入**：Phase 5 會做建部位／滾倉／平倉表單，沒有 `user_id` 的話其他 4 個
enabled 帳號能新增假部位、把持倉標成已平倉、寫進損益帳本，而且事後查不出
是誰做的。執行面照抄 `MarginPositionsController` 的 pattern，
**只加欄位不 scope 等於白加**，spec 直接把這件事釘住。

### 2026-09-01（二）— PMCC 到期日涵蓋到 60 天，每個到期日表格可收摺

#### 為什麼原本的「固定前三個到期日」不夠用

舊規則（spec §3）取 `Expiration` 下拉的前三個，DTE 通常整組落在 6–50 天，
**前一兩個還短於 lesson9 的 19–45 天建議區間**，使用者真正要看的 45–60 天
往往一個候選都沒有。改成 `select_expirations()`：**DTE ≤ 60 的前 8 個**。

上限一開始設 6，**實跑 BE 才發現不夠**——週選標的 7 天一檔，前 6 個只到 DTE 38，
把 45–60 整段切掉。實測 BE 的 DTE≤60 共 7 個，落在 45–60 的只有 `2026-10-16`
（DTE 45）那一個。上限改 8 後重跑，BE 抓到 7 個到期日、最遠 DTE 46，
排行服務算出 7 桶（總組合 159 / 通過 101）。

`PmccRankingService::SC_EXPIRATION_COUNT` 要跟 scraper 的 `MAX_EXPIRATIONS`
一起改——這是兩個各自獨立的常數，只改一邊會靜靜地少幾桶。

#### 收摺

每桶從 `div` 改成原生 `details/summary`（沿用 `concept_cards` 的做法，零 JS，
也避開 Phlex 2.x 封鎖 `on*` 屬性），第一桶展開、其餘收起。

- 收起的表格**仍在 DOM**，所以 `data-sort-scope` 的排序 toggle 照常生效
- `export.js` 匯出 PNG 前強制展開所有 `details`、匯出後還原——不然收摺的桶
  會整塊從截圖消失（向量 PDF 不受影響，PMCC 本來就不在 `pdf_export_payload`）
- 位置式標籤（近/中/遠月）只標得到前三桶，改成依 DTE：19–45「建議區間」、
  > 45「偏遠」、< 19 維持原本的橘色警示 badge

#### 展開箭頭改成固定尺寸

原本是裸的 `▸` 字元，沒有 `font-size`，會**跟著頁首「字體調整」一起縮放**，
大小不可控。改成 24×24 px 綠底（green-600）方框 ＋ 白色三角形，與字級脫鉤。
`summary` 是 flex 容器，`::before` 會成為 flex item，必須 `flex: 0 0 24px`
鎖住，否則標題長時方框會被壓扁。

### 2026-09-01（二）— Options Flow 拿掉 CSV 下載，逐筆交易改由 grid 轉出

查 LEAPS 會連帶補抓 Options Flow（`refresh_options_flow_if_stale`），而那支 scraper
除了用 CDP 讀 `bc-data-grid._data` 算彙總指標，還會**再去點 Barchart 的下載鈕存一份
CSV** 來取得逐筆大單。實測後確認這條路多餘，而且正在污染資料。

#### 三個實測依據

1. **grid raw 是 CSV 的超集**：先前以為只有 CSV 有的 5 欄，對應
   `volume` / `openInterest` / `volatility` / `label` / `tradeTime`，全都在 `_data[*].raw` 裡
2. **筆數一致**：BE 當日 grid 翻頁 200 筆，CSV 扣掉表頭與頁尾也是 200 筆
3. **CSV 每個快照塞一列垃圾**：末行是 `"Downloaded from Barchart.com as of ..."`，
   `csv.DictReader` 沒過濾，於是產生一筆全 null 的假交易。DB 實查 67 列，
   而快照組數也正好 67 —— 每個快照剛好一列（已清除，刪除前備份 `options_flow_trades`）

#### label 要正規化，否則方向判斷會安靜失效

grid 的 `label` 是長格式 `"(S) - Sell To Open"`，而
`OptionsFlowClassifierService#derive_direction` 是拿短格式 `"SellToOpen"` 做 pattern
match。不轉的話所有交易都會掉到 `INDETERMINATE`，**而且完全不報錯**。
這是實跑才發現的——單元測試當初用了我自己假設的短格式樣本，測試全綠卻是假的綠燈。

#### 其他

- `iv` 改成無條件 ÷100，順帶修掉舊 `_parse_pct`「>1 才除」對小 IV（如 0.8%）算錯的邊界
- 移除 `to_windows_path` / `Browser.setDownloadBehavior` / `wait_for_csv` 整條下載路徑，
  以及 Ruby 端的 `csv_error` 分支；不再往工作目錄寫檔
- 新增 `test_options_flow_scraper.py` 18 則（這支 scraper 原本零測試）

### 2026-08-31（一）— LEAPS 抓取的兩種逾時：分頁凍結 vs 頁面真的慢

同一句「查詢失敗」底下其實是兩個獨立原因，分開處理才修得掉。

#### 1. 一次 eval 逾時就毀掉整趟抓取

Windows Chrome 凍結背景分頁時 `Runtime.evaluate` 不會有回應，`cdp_eval` 丟出的
`TimeoutError` **直接穿過 `_wait_for_grid` 冒到 `main` 外面**——那支函式本來設計成
「等不到就回 `None`，讓上層走 partial／`page_load_timeout`」，但那條優雅路徑從來
沒被走到過，畫面吐的是原始 Python 例外 `TimeoutError: CDP eval timed out`。

- `cdp_eval` 逾時後先重新 `activate_target`（解凍 renderer）再試一次
- `_wait_for_grid` / `_confirm_empty` 把 eval 逾時視同「還沒好」繼續輪詢

#### 2. Barchart 的 grid 掛載時間本來就會超過舊上限

實測 SONY 的 `volatility-greeks?strike=20.5` 需要 **34.3 秒**才把 `_data` 填好，
舊上限（opts 30 秒／V&G 25 秒）直接判逾時，重試幾次都一樣——慢的是頁面本身。
統一為 `GRID_MAX_WAIT_S = 60`；Ruby 端錯誤訊息也不再寫死「30 秒內未完成載入」。

同樣修正套用到 `pmcc_short_call` / `bcvs_call_chain` / `bpus_put_chain`。

### 2026-08-31（一）— LEAPS 排行表欄位可拖曳排序（admin 專屬，順序存 DB 全站套用）

#### 為什麼順序要存 DB 而不是 localStorage

欄位順序是**站台設定**不是個人偏好：只有 admin 能改，改完所有人看到同一個順序，
換裝置、換瀏覽器都一致。新增 `column_orders` 表（`table_key` 唯一 + `column_keys` jsonb
+ `updated_by_id`），一個 table_key 一列，日後 PMCC 表要可拖曳只要多一列。

#### 欄位定義與顯示順序拆開

新增 `LeapsTableColumns`（PORO）持有 `DEFAULT_KEYS`／`LABELS`／`SUBLABELS`／
`DEFAULT_HIDDEN_KEYS`／`PDF_EXCLUDED_KEYS`，component、PDF payload、API 驗證三邊
共用同一份定義。`ColumnOrder.keys_for` 只負責「這次用什麼順序」。

`LeapsTableColumns.sanitize` 是這組設計的關鍵：DB 存的是當下那批欄位的快照，
日後程式加減欄位時舊快照會對不上——先丟掉不存在的 key，再把缺漏的 key 依
`DEFAULT_KEYS` 的相對位置插回去，所以**新增欄位不需要動資料，也不會整欄消失**。

#### `render_candidate_row` 從寫死順序改為 renderer hash

欄位順序可變，td 就不能再是 19 段固定順序的呼叫。改成
`candidate_cell_renderers` 回傳 `{ key => lambda }`，再依 `ordered_col_keys` 逐一
`fetch(key).call`——少一個 key 會直接炸掉，比默默少渲染一欄好抓。

#### 為什麼用 pointer events 而不是 HTML5 drag-and-drop

兩個理由：HTML5 DnD 的游標由瀏覽器決定，做不到「按住拖動時變成 `move` 游標」；
而且表頭的 click 已經被 tooltips.js 用來開欄位教學 popover，需要自己控制
「位移超過 4px 才算拖曳」，並在拖曳結束後於 capture 階段吃掉那一次 click。

#### 權限

前端的 `data-col-reorder` 只是「要不要掛拖曳」的提示；真正的權限在
`Api::V1::LeapsColumnOrdersController#require_admin!`。寫入只接受**完整排列**
（不多、不少、不重複）——允許缺漏等於讓前端一個 bug 永久刪掉欄位。

### 2026-08-31（一）— LEAPS 排行表 IV 配色分級與欄位說明排版重整

#### IV 欄位依水位上色

`LeapsRecommendations::Formatting#iv_color_class`，門檻常數 `IV_GREEN_MAX = 0.30`／
`IV_YELLOW_MAX = 0.50`（`row[:iv]` 是小數，0.634 代表 63.4%）：

| IV | 顏色 | 判讀 |
|---|---|---|
| ≤ 30% | 綠色粗體 | 理想進場點，權利金相對便宜 |
| 30%–50% | 黃色粗體 | 可接受，但非最佳時機 |
| > 50% | 紅色粗體 | 不建議買進，IV 均值回歸會侵蝕獲利（vega 逆風）|

`nil` 走 `text-gray-400` 顯示破折號。邊界以 rails runner 實測確認：
0.30 → 綠、0.3001 → 黃、0.50 → 黃、0.5001 → 紅。

#### 欄位說明改成結構化排版

IV／內在價值／外在價值／Spread% 四個欄位補上判讀說明後，原本用 `\n` 串起來的
多段文字擠成一團。改成 `TIP_H()` 小標題 ＋ `TIP_L()` 條列的 HTML 結構，
四則統一為「定義句 → 小標題 → bullet」。

hover 小提示原本是 `tB.textContent = d.desc`，改成 `innerHTML`，與 driver.js
popover（本來就是 `description.innerHTML`）共用同一份文案；`.tip-h` / `.tip-l`
在 `application.css` 一次定義、兩邊套用，tooltip 寬度 340 → 380px。

#### Spread% 表頭註記不能併進欄名

第一版把「（買賣差價比）」直接寫進 `TABLE_COLS`，結果 `th` 是 `whitespace-nowrap`，
該欄被撐寬、把「流動性判斷」的標籤擠到換行。改用 `TABLE_COL_SUBLABELS`，
在表頭下方多渲染一行 10px 灰字，欄寬不受影響。

### 2026-08-30（六）— 維運健檢：pm2 排程時區錯 8 小時、測試會打真實 API

#### pm2 的 cron 走的是 daemon 時區

`pm2` 的 `cron_restart` 由 daemon 解讀，用的是 **daemon 自己的時區**。
開機用的 `/etc/systemd/system/pm2-idarfan.service` 只設了 `PATH` 與 `PM2_HOME`，
沒有 `TZ`，daemon 因此沿用 `/etc/localtime`（Asia/Taipei）——
而 `bin/iv-*.sh` 的註解明確假設「pm2 daemon 必須以 `TZ=UTC` 啟動」。
**這個前提從來沒有成立。**

三個排程因此全部早 8 小時：

| job | cron | 應該 | 實際 |
|---|---|---|---|
| `iv-skew-intraday` | `*/30 13-20 * * 1-5` | ET 09:00–16:00 盤中 | ET 01:00–08:00 盤前 |
| `iv-daily-snapshot` | `30 20 * * 1-5` | ET 16:30 收盤後 | ET 08:30 開盤前 |
| `iv-skew-snapshot` | `45 20 * * 1-5` | ET 16:45 收盤後 | ET 08:45 開盤前 |

intraday 每次都落在非交易時段被跳過——`skew_rank_intradays` 從 2026-05-19 起
就沒有新資料，**靜默了 3.5 個月**。另外兩個抓到的是前一日收盤。

修法：`scripts/fix-pm2-timezone.sh`，用 systemd drop-in 加 `Environment=TZ=UTC`
（附加式、可逆）。三種模式：套用 / `--check` 零改動診斷 / `--rollback`。
已執行驗證：daemon TZ 從 `/proc` 讀出確認是 UTC、20 個 process 全數回復、
手動執行 intraday 報出的 ET 時刻與真實 ET 一致。

**防復發**：新增 `rake ops:freshness`（`bin/audit freshness`）主動比對五張排程表
的最新時間與預期更新頻率。排程壞掉不會拋例外、不會有紅字，只會「沒有新資料」
——這就是它能靜默 3.5 個月的原因。

#### 測試套件會打真實外部 API

沒有 WebMock/VCR。六支 request spec 會渲染 `/momentum` 這類真實頁面，
而那條路徑會呼叫 `VixService`、`FinnhubService#quote`×N、`YahooFinanceService#chart`×N。
這些包在 `Rails.cache.fetch` 裡，但 test 環境的 `cache_store` 是 **`:null_store`**
——快取永遠不命中，每次都真的出網。

`absolute_timeout_spec` 更是 `25.times { travel 1.hour; get "/momentum" }`，
單支 138 秒，而且遇過一次偶發失敗。

引入 WebMock 後：**3 分 03 秒 → 41.9 秒（4.4 倍）**，726 examples 全過。

#### 查證後排除的（不是問題）

| 現象 | 真相 |
|---|---|
| `technical_analyses` 停在 6/26 | **使用者觸發式**（技術面儀表板按「分析」），不是排程 |
| `options-intraday.timer` 顯示「從未執行」 | 機器當天才開機，該 timer 只在週一~五觸發 |
| systemd `options-*` 系列 | `OnCalendar` 明寫 `UTC`，時區無關 |
| DB 備份 | 正常，21MB × 7 天輪替 |
| 磁碟 / DB | 24% 已用、359MB、90 天清理排程正常 |

#### 順帶

npm 最後一個漏洞（esbuild、dev-server、Windows、low）藏在 storybook 巢狀相依，
`npm audit fix` 宣稱有修法卻不套用，升到 storybook 最新版也沒解。
改用 `overrides` 強制 `esbuild ^0.28.1`，Vite / tsc / eslint / vitest / Storybook
五個建置全過，`npm audit` 歸零。

### 2026-08-30（六）— tracked_tickers：修正錯誤盤點，補上閘門測試與 UI

#### 先修正我自己的錯誤

我把「`tracked_tickers` 沒有 per-user ownership」列為待辦，說要重新 key
81 萬筆 `option_snapshots`。**查證後發現這個設計決定早就做完並記載在程式碼裡。**

`Api::V1::TrackedTickersController` 開頭就寫著：

> `tracked_tickers` 是共用的蒐集設定，不是個人清單：systemd 的
> options-collector.timer 直接讀 `SELECT ... FROM tracked_tickers WHERE active = true`，
> 蒐集結果 `option_snapshots` 綁的是 `tracked_ticker_id` 而非 symbol，
> 所以沒辦法像觀察清單那樣簡單地分給每個使用者。
> 折衷做法：讀取所有人都可以，但**只有 admin 能改動**。

`before_action :require_admin!` 已在把關，`User` model 有對應說明，
`watchlist_isolation_spec` 已覆蓋 destroy 的三種情況。

背景佐證：6 個 tracked_tickers 全部建立於 2026-04-11～04-20，**早於使用者系統
（2026-07-29）**，是單人時代留下的共用設定。

#### 實際發現的兩個缺口

**1. 閘門有四個 action，只測了一個**

`only: %i[create update destroy collect]`，但只有 `destroy` 有測試——
把 `create` 從清單拿掉不會有任何測試失敗。補上另外三個，四個突變全部驗證會被抓到。

**2. 前端完全不知道 admin 的存在**

非 admin 看得到「新增」「移除」按鈕，按下去只拿到一句「新增失敗」，
**看起來像功能壞掉而不是權限限制**。已把 `@can_manage_tickers` 一路傳到
`TickerSidebar`：非 admin 的新增表單換成說明文字，移除按鈕不渲染。

這個旗標**不是安全邊界**——真正的把關仍在後端 `require_admin!`，
註解裡寫明了，免得日後有人以為拿掉旗標就等於開放權限。

新增 `spec/requests/option_price_tracker_spec.rb` 釘住旗標值（突變驗證過）。

**719 examples 全過**（原 712）。

### 2026-08-30（六）— CSP style-src 收斂完成，內嵌樣式歸零

`style-src` 拿掉 `'unsafe_inline'`。18 頁的伺服器 HTML 內嵌樣式從 **575 → 0**。

#### 為什麼這條比 script-src 難

**CSP nonce 對 `style="..."` 屬性無效，只對 `<style>` 區塊有效。**
所以 script-src 用的那招（把唯一的內嵌 script 加 nonce）在這裡完全不管用，
內嵌樣式必須真的移除。收斂後的三種承載方式：

| 樣式類型 | 承載方式 |
|---|---|
| 靜態 | CSS class（Tailwind utility 或 `app/assets/tailwind/application.css`）|
| 動態數值 | data attribute + CSSOM（`shared/dataStyles.ts`）—— **CSSOM 賦值不受 CSP 限制** |
| `<style>` 區塊 | nonce（BCVS 的 `@font-face`，需要 Propshaft digest 路徑）|

#### 範圍怎麼縮小的

原本 1071 處。`CspLessonsController` 保留 `unsafe_inline`——期權小學堂是
`send_file` 的靜態教材頁（約 840 處內嵌樣式），**零使用者輸入**，攻擊者無法注入。
分區後只剩 219 處要處理。

#### 量測方式

一開始想靠 Playwright 的 console 抓 CSP 違規，**抓不到**——那些訊息走 CDP 的
`Log.entryAdded`，不是 `Runtime.consoleAPICalled`。改成直接解析伺服器送出的
HTML，反而更精確（DOM 裡的 `style` 屬性有些是 JS 用 CSSOM 設的，那些 CSP 不管）。

過渡期用一份獨立的 report-only 標頭量測，主政策完全不動——
**刻意不用 `config.content_security_policy_report_only`**，那會讓整份政策
（含已收緊的 `script-src`）都失去強制力。

#### 兩個踩過的坑

**1. `after_action` 設 Report-Only 標頭會讓主 CSP 標頭整個消失**

`ActionDispatch::ContentSecurityPolicy::Middleware` 開頭是
`return response if policy_present?(headers)`，而 `policy_present?` 判斷的是
「CSP **或** CSP-Report-Only 任一存在」。controller 的 `after_action` 比
middleware 早跑，先放上 Report-Only 就讓它認定政策已存在而跳過主政策——
為了量測反而把真正的 CSP 關掉，**而且沒有任何錯誤訊息**。
改成 middleware 並 `insert_before`，回應階段才會在它之後執行。

**2. 逐行替換腳本造成 `class:` 重複，靜默吃掉樣式**

`class:` 與 `style:` 分屬不同行時，腳本把 `style:` 直接換成 `class:`，
同一個呼叫就有兩個 `class` 鍵——Ruby 的 hash 後者覆蓋前者，`px-4 py-3`
被靜默吃掉，兩張公式拆解卡的內距整個消失（截圖比對才發現）。

修正後改用 **`ruby -w -c` 的 `key :class is duplicated` 警告**來定位，
精確到行號。自己寫的正規式區塊偵測會把相鄰 span 誤判成同一個呼叫——
那次誤判還一度把某個 span 的 class 整個吃掉。

#### 驗證

- 18 頁伺服器 HTML：style 屬性 **0**、`<style>` 區塊 1 且帶 nonce、未授權區塊 0
- BCVS 的 `@font-face` 經 nonce 生效（`fontFaceRuleCount` 1、Noto Sans TC 已套用）
- IV 教學面板逐一比對 computed style：`#e8f5a3` / `#7ecaf5` / `#b0bec5` /
  `#ffb74d` / `#58a6ff` / `#112240`、TTS 藍紅與 `margin-left: 20px` 全部精確吻合
- 字級按鈕改動前後 computed 值完全一致（10/12/14/16/18px、行高 1.2×）
- 截圖確認 `/momentum`、`/iv_analysis`、`/bcvs` 版面無變化
- 712 examples 全過、RuboCop 0 offense、console errors 0

### 2026-08-30（六）— database_consistency 40 項歸零

「全部修掉」不是正確目標——其中 8 項若照做會產生**永遠不會執行的驗證器**。
最終：修 32 項、逐項註明理由忽略 8 項，`bin/audit schema` exit 0。

#### `case_sensitive: false` 是 8 項發現的共同根因

`UniqueIndexChecker`（索引沒有對應驗證器）與 `MissingUniqueIndexChecker`
（應該建 `lower()` 索引）看似兩件事，其實是同一件事的兩面：
`WatchlistItem` / `WatchedTicker` / `TrackedTicker` / `IvWatchlist` 都寫
`uniqueness: { case_sensitive: false }`。

正解不是加 `lower()` 索引，而是**拿掉那個選項**：這四張表存檔前一律 `upcase`，
DB 裡只有大寫，比對大小寫毫無意義；而 `case_sensitive: false` 產生的
`LOWER(symbol) = LOWER($1)` **用不到既有的 btree 唯一索引**。

**連帶修掉一個潛在 500：** `TrackedTicker` 與 `IvWatchlist` 的正規化原本寫在
`before_save`——也就是驗證「之後」。單獨拿掉 `case_sensitive: false` 會讓
`aapl` 通過唯一性驗證、存檔時才 upcase 成 `AAPL` 撞上唯一索引，
使用者看到的是 500 而不是驗證錯誤。正規化已移到 `before_validation`。
順帶修正 `IvWatchlist` 的 format 驗證原本跑在未 strip 的值上（`" aapl "` 會被誤擋）。

#### 三支 migration

| migration | 內容 | 前置查證 |
|---|---|---|
| `DropRedundantIndexes` | 刪 7 個冗餘索引 | 逐一用 `pg_indexes` 確認是真的 leftmost-prefix 重複，**沒有 partial index**——工具不檢查 `WHERE` 條件 |
| `AddNotNullConstraints` | 3 個 NOT NULL + `iv_queries.low_iv_signal` 補 default 後設 NOT NULL | 現有 NULL 筆數皆為 0 |
| `AddNumericalityCheckConstraints` | 7 個 CHECK constraint | 違反筆數皆為 0 |

金額與股數為負會直接汙染損益計算（`Portfolio#total_cost`、`MarginPosition#balance`
都是直接相乘），所以這層防護值得放在 DB 而不只在 model。

**三支的 `down` 都實測往返過**（索引 7 → 0 → 7 → 0）——
memory `feedback_migration_rollback_risk` 記著 down 失敗可能連鎖回滾前一個 migration。

#### 不修的 8 項

8 張 snapshot 表全部由爬蟲以 `upsert` / `insert_all` 寫入
（`barchart_scraper_service.rb:608/677/699` 等），**這兩個 API 完全跳過
ActiveRecord 驗證**。加上去只會是死碼，還製造「這張表有唯一性驗證」的假象。

`OptionSnapshot` 另有無解之處：索引是
`(tracked_ticker_id, date_trunc('hour', snapped_at), contract_symbol)`，
Rails 的 uniqueness 驗證器無法表達 `date_trunc` 這種運算式。

理由逐項寫在 `.database_consistency.yml`（注意是**底線**不是連字號）。

#### 其他

`bin/audit schema` 從報告用升格為**閘門**，`config/ci.rb` 同步加上——
既然歸零了，不設閘門就會慢慢漂回去。

新增 9 個測試釘住正規化順序，**反向驗證過**：改回 `before_save` 立刻紅。
順帶補上原本不存在的 `iv_watchlist_spec.rb` 與 `watched_ticker_spec.rb`。

RSpec **712 examples / 0 failures**，`bin/audit all` exit 0。

### 2026-08-30（六）— traceroute 的替代方案：內建指令 + 一支 spec

`traceroute` gem 停更於 2020-04-28 不予採用。它報兩件事，各自有更好的替代：

| traceroute 的功能 | 替代方案 |
|---|---|
| 路由指向不存在的 action | **Rails 內建** `bin/rails routes --unused`（7.1 起）|
| action 沒有任何路由指到它 | `spec/routing/unreachable_actions_spec.rb`（新增）|

兩者都已接進 `bin/audit style` 與 `config/ci.rb`。評估過但未採用：`coverband`
（需 production 常駐 + Redis）、`debride`（對 Rails 動態呼叫誤報多）。

#### 第二半抓到的兩個真問題

**1. `Charts::TechnicalIndicators` 的 6 個方法是公開 action**

`Api::V1::ChartsController` 做了 `include Charts::TechnicalIndicators`。Rails 把
controller 上的每一個 public method 都視為可路由的 action，所以這 6 個純計算方法
跟 `#show` 一樣，只差一條路由就能被外部呼叫。

目前沒有路由匹配（全庫僅有的兩條無 action 路由是 `/csp` 與 `/lookbook` 這兩個
mount，不是 `:controller/:action` 萬用路由），**所以沒有實際可達的漏洞**。已改為：

```ruby
private(*Charts::TechnicalIndicators.public_instance_methods)
```

寫成 splat 而非逐一列名，之後在模組裡新增方法會自動涵蓋。

**2. `PagesController` 是死碼**

從 initial commit 起就沒有路由、全庫零引用，view 只有一行註解。已刪除
controller 與 `app/views/pages/`。

#### 覆蓋率數字要打折看

新 spec 需要 `Rails.application.eager_load!` 才能列舉 controller，副作用是所有
類別的 body 都被執行一次，那些行被算成「已覆蓋」但其實沒被測到——
**line 覆蓋率因此從 51.72% 跳到 58.36%，不是真的變好。**
branch 覆蓋率不受影響（40.59% → 41.08%），要看真實測試強度請以 branch 為準。

門檻調到 line 56 / branch 38，並在 `spec_helper.rb` 註明這個高估。

### 2026-08-30（六）— 補齊稽核工具鏈，發現 Brakeman 一直在空轉

#### 裝了什麼

| gem | 用途 | 接在哪 |
|-----|------|--------|
| `simplecov` | 測試覆蓋率（含 branch） | `spec/spec_helper.rb`，`COVERAGE=1` 才啟用 |
| `database_consistency` | DB 結構稽核：缺索引、冗餘索引、validation 與 NOT NULL 不一致 | `bin/audit schema`（報告用，不設閘門） |
| `rubocop-rspec` | spec 本身的 lint | `.rubocop.yml` |
| `bullet` | N+1 查詢偵測 | `config/initializers/bullet.rb`，僅 development |

未採用 `traceroute`（偵測未使用的路由）——最後一版停在 2020-04-28，違反「引入前確認仍在維護」。

新增 `bin/audit` 作為單一入口：`style` / `security` / `coverage` / `frontend` / `schema` / `n1`。

#### 最重要的發現：Brakeman 掃描一直沒有真的執行

`bin/brakeman` binstub 會注入 `--ensure-latest`。本機裝的是 8.0.5、最新是 8.0.6，
於是 Brakeman **在掃描開始前就 exit 5**，只印一行版本訊息。`bin/ci` 的
「Security: Brakeman code analysis」步驟因此長期空轉——就算真有漏洞也不會被回報，
而失敗訊息只有一行版本提示，看起來完全不像掃描沒跑。

升到 8.0.6 後掃描恢復：**Security Warnings: 0、Errors: 0**。同時清掉 2 筆過期的
忽略項（`config/brakeman.ignore` 5 → 3），過期的忽略項留著會遮蔽未來的警告。

#### 第二個發現：`bin/ci` 根本沒跑測試

`config/ci.rb` 只有 Setup / RuboCop / bundler-audit / Brakeman 四步，
**一行 spec 都沒執行**。已補上 RSpec（含覆蓋率門檻）與 `npm run check`。

#### rubocop-rspec：657 → 0

導入時 657 個 offense，但**沒有任何一個是缺陷偵測類**（`RepeatedDescription`、
`EmptyExampleGroup`、`VoidExpect` 全部 0）。597 個集中在八個「風格偏好」cop
（`MultipleExpectations` 252、`ExampleLength` 116、`ContextWording` 38——後者要求
context 用英文 when/with 開頭，本專案 spec 一律繁中）。

**一個永遠紅的閘門等於沒有閘門**，所以把偏好類關掉並在 `.rubocop.yml` 寫明理由，
剩下的 60 個全部修完：自動修正 63 個、手動修 `LeakyConstantDeclaration`（describe
區塊裡的 `X = ...` 其實定義在全域 `Object` 上，兩支 spec 撞名會靜默取到別人的值）
與 `LetSetup`。同時開啟 `AllCops: NewCops: enable`。

#### 覆蓋率現況

**line 51.72%（4525/8748）、branch 40.59%（1148/2828）。**
門檻設 50 / 38 當棘輪防倒退。已驗證閘門會真的擋（只跑單一 spec 會失敗），不是擺設。

#### database_consistency：40 項發現，4 項是誤報

4 筆 `MissingUniqueIndexChecker`（WatchlistItem / WatchedTicker / TrackedTicker /
IvWatchlist 建議加 `lower(symbol)` 唯一索引）**是誤報**——這四個 model 都在存檔前
把代號 `upcase`，DB 裡只會有大寫，現有的 case-sensitive 索引已經足夠。

其餘 36 項多為「validation 與 DB constraint 不對稱」，需要 migration；
dev/prod 共用同一個資料庫，未擅自執行，列為待辦。

### 2026-08-29（九）— `CompositeSignalService` 補測（稽核 L-1）

三維度儀表板的核心服務，388 行長期 **0% 覆蓋**。新增
`spec/services/composite_signal_service_spec.rb`，**33 個測試**。

測試釘住的是**分數門檻**與**背離判斷**——那是投資決策直接依賴、而且改動時最容易
在無聲中偏掉的部分。評分權重本身未經回測（見 memory
`project_scoring_weights_unvalidated`），這些測試釘的是**目前的行為**，不代表權重
是對的；要調權重時它們會如實失敗，那正是用途：讓調整是有意識的。

**用 mutation testing 驗證測試是否真的有效**

第一版 33 個測試一次全過，但拿 mutation 一試就發現破口：

| Mutation | 第一版 | 補強後 |
|---|---|---|
| 技術面門檻 `>= 4` → `>= 3` | **沒抓到** ❌ | 1 failure ✅ |
| 基本面門檻 `>= 3` → `>= 2` | — | 1 failure ✅ |
| Flow 門檻 `>= 2` → `>= 1` | — | 1 failure ✅ |
| 200 日均線權重 `2` → `1` | — | 7 failures ✅ |
| `opposite?` 判斷反轉 | — | 3 failures ✅ |
| 財報前提前 `return` 拿掉 | 2 failures ✅ | ✅ |
| CSV 統計不排除已取消成交 | 1 failure ✅ | ✅ |

破口的原因很典型：我只驗了「達到門檻 → bullish」，沒驗「**差一分 → 仍是
neutral**」。少了那一格，門檻被改小完全看不出來。三個維度各補一個邊界測試後補齊。

**順帶記錄的行為**

- 技術面門檻**刻意不對稱**：`>= 4` 才偏多，`<= -3` 就偏空
- 財報前 7 天內基本面直接 `return :watching`，**不計分**（結果沒有 `:points` 鍵）
- `:watching` 會被排除在「三維度一致」判斷之外，避免財報前誤報
- `net_sentiment == 0` 不計分也不產生訊號（0 不代表方向）

**註**：SimpleCov 不在 Gemfile 裡（稽核時的 43.59% 是臨時裝了量的），所以無法直接
報出覆蓋率變化。要讓覆蓋率可持續追蹤需另外決定是否常駐。

RSpec 669 → **702**，0 failures。

### 2026-08-29（八）— 開啟 `noUncheckedIndexedAccess`，並修好 `/options/:symbol` 的 500

**`noUncheckedIndexedAccess: true`**（global rules 要求，原本掛著 TODO）

開啟後 46 個錯誤**全在 React/TSX 側**——剛型別化完的 30 支 behaviors 一個都沒有，
那批當初就寫得防禦性。

| 檔案 | 錯誤 | 修法 |
|---|---:|---|
| `options/payoff.ts` | 15 | 係數陣列標成 tuple 型別（索引即 `number`，不需 `as`）；`calcSummary` 補一道不會觸發的防護 |
| `option_price_tracker/components/OptionsChainTable.tsx` | 13 | `buildTips` 從 `Record<string, TipDef>` 改用 **`satisfies`**——每項仍檢查 `TipDef`，但 key 保持精確 |
| `options/components/SentimentPanel.tsx` | 6 | `data[0]` 取出當 reduce 種子，同時取代原本的 `!data.length` 判斷 |
| `options/strategies.ts` | 6 | `offsetAt()` helper，**回 NaN 而非 `?? 0`**——`?? 0` 會把越界從 NaN 悄悄變成價平，那是行為改變 |
| `options/components/StrategyDetailPanel.tsx` | 3 | `bes.length === 1` 不會幫 `bes[0]` 收窄，補明確判斷 |
| `margin/utils/format.ts` | 2 | `toISOString().split('T')[0]` → `.slice(0, 10)` |
| `options/OptionsAnalyzerApp.tsx` | 1 | `strategies[0]` 先取出再判斷 |

**零個 `as` 強轉**（`satisfies` 是驗證不是斷言）。7 個檔案的數值常數比對全部零差異。

**過程中自己製造又抓到的一個 bug**：用字串取代插入 `offsetAt` helper 時，同一次
`replace` 把 helper **自己內文**的 `offsets[i]` 也換掉，變成
`return offsetAt(offsets, i) ?? NaN`——**無限遞迴**。TS 完全不抱怨（型別對得上），
執行時會 stack overflow。同一次還把 `export function` 的 `export` 跟函式拆開。
教訓：批次字串取代會咬到自己剛插入的內容。

**順帶修好一個既有的 500**

驗證時發現 `/options/AAPL` 直接 500，見上一則 commit（`OptionsController#show`
的常數解析少了前綴 `::`，從 `ca052af` 起就一直壞著）。

**瀏覽器驗證**

| 頁面 | 驗到 |
|---|---|
| `/options/AAPL` | Call Wall 361 / Put Wall 281、最大獲利 $1675、損益兩平 $273.25；切「大波動」→ 跨式 → 雙 BE $229.25 / $370.75，「盈利走廊」分支出現 |
| `/option_price_tracker` | 切 Calls → 13 個展開欄位全部渲染且各帶 ⓘ（tips 若為 undefined，`TipContent` 讀 `title` 會直接爆）|
| `/margin` | 30d / 90d / 365d 日期計算與手算逐項相符 |

`npm run check` 全綠、RSpec 669/0、RuboCop 無 offense、console 零錯誤。

### 2026-08-29（七）— npm 安全漏洞 8 → 1，並確認 Storybook 在 vite 8 下正常

升 vite 8 時跑了一次 `npm audit`，才看見既有的 8 個漏洞（含 4 個 critical）。
**這些不是升級引入的**——`@vitest/browser-playwright`、`@storybook/addon-vitest`、
`@vitest/coverage-v8` 早在 `99012c5`（Storybook/Chromatic 修正那次）就在
`package.json` 裡了，只是先前沒跑過 audit。

| 嚴重度 | 前 | 後 |
|---|---:|---:|
| critical | 4 | **0** |
| high | 2 | **0** |
| low | 2 | **1** |

**4 個 critical 全部來自 `@vitest/browser`**，而拉它進來的三個套件查證後都沒在用：

| 套件 | 實際狀況 | 處置 |
|---|---|---|
| `@storybook/addon-vitest` | 不在 `.storybook/main.js` 的 addons 清單 | 移除 |
| `@vitest/browser-playwright` | 全專案零引用（測試用 happy-dom，不是 browser mode）| 移除 |
| `@vitest/coverage-v8` | `@vitest/browser` 是它的 **optional** peer | 保留 |

移除前兩個之後 `npm ls @vitest/browser` 變成 `(empty)`，4 個 critical 一次消失。
再跑 `npm audit fix` 收掉 `brace-expansion`（high）、`picomatch`（high）、
`@babel/core`（low）。

**剩下的一個**：`esbuild` 巢狀在 `storybook` 底下，`npm audit fix` 動不了（要等
Storybook 更新自己的相依），且該漏洞只影響**在 Windows 上跑 dev server**——
本專案跑在 WSL2/Linux，不成立。

**Storybook 在 vite 8 下正常**

升級時留下的未知數（`@joshwooding/vite-plugin-react-docgen-typescript@0.6.4`
只支援到 vite 7）已實測：`npm run build-storybook` 成功（Vite ✓ built in 12.15s）。
那個 peer 不符只是宣告問題，功能沒壞，`npx chromatic` 應該正常。

**驗證**：`npm run check` 全綠、production build 1.01s、manifest 仍是 30 個
behaviors + 8 個 entrypoints、RSpec 665/0、RuboCop 無 offense。

### 2026-08-29（六）— 升 vite 8、解開兩個相依衝突、補上前端單元測試

> **歷史說明**：這一輪同樣被自動提交 hook 拆成兩筆並已推送
> （`567f579` json 測試＋vitest 設定、`a18c5ea` 升 vite 8＋dom 測試）。
> 禁止 force push，說明補在這裡。

**兩個先前就存在的相依衝突**

`npm install` 一直裝不了任何新套件，原因是兩組 peer dependency 互斥：

```
@vitejs/plugin-react@6.0.1        要 vite@^8.0.0，專案卻釘 vite@^6.4.1
eslint-plugin-react-hooks@7.0.1   peer 只到 eslint@^9，專案已裝 eslint@10.2.0
```

兩者都是先前用 `--force` 之類硬裝起來的。升級前先確認所有 vite 消費端都接受
`^8`（`vite-plugin-ruby >=5.0.0`、`@storybook/react-vite` 與 `vitest@4.1.1`
都列了 `^8`），才動手。

| 套件 | 前 | 後 |
|---|---|---|
| `vite` | 6.4.1 | **8.2.2** |
| `eslint-plugin-react-hooks` | 7.0.1 | **7.1.1** |
| `happy-dom` | 未安裝 | **20.11.15** |

**production build 從約 10 秒降到 1.80 秒**，`react-resizable-panels` 的
`"use client"` 警告也消失。

**剩一個不影響 Rails 的 peer 不符**：`@joshwooding/vite-plugin-react-docgen-typescript@0.6.4`
（`@storybook/react-vite` 的相依）只支援到 vite 7。**只影響 Storybook**，
Rails 建置與測試都不碰它——跑 `npx chromatic` 前要留意。

**前端單元測試（28 個）**

之前說「這專案沒有前端測試框架」是錯的——`vitest@4.1.1` 早就裝好了，缺的是
DOM 環境（被上面的衝突擋住）。

| 檔案 | 測試數 | 重點 |
|---|---:|---|
| `shared/json.test.ts` | 17 | 把 `num()`（嚴格）與 `numeric()`（parseFloat 語意）的差別釘死——那正是 Skew Rank 回歸的根因 |
| `shared/dom.test.ts` | 11 | 釘住「取不到就安靜回退」的新語意（型別化前那些寫法會拋 TypeError）|

新增 `vitest.config.ts`（獨立於 `vite.config.ts`，不載入 `vite-plugin-ruby`）。
`package.json` 加 `test` / `test:watch`；`check` 改成
`tsc --noEmit && eslint . && vitest run`；`lint` 從已失效的 `--ext` 改成 `eslint .`。

**兩支測試都驗證過是有效防護**：把 `numeric()` 改回嚴格 → 3 個失敗；拿掉
`closestFrom` 的 `instanceof` 保護 → 1 個失敗。

**順帶把 `portfolioHoldings` 補驗完**

`/portfolio` 無持股資料，改用元件真實標記建合成 DOM、攔截 `/portfolio/quotes`
回 Finnhub 真實形狀（實測 `c`/`d`/`dp` 都是 `Float`，所以嚴格的 `num()` 在那裡
是對的）。六個報價欄位與手算逐項相符（市值 $3,197.00、損益 +$1,697.00、
損益率 +113.13%），雙向試算 160.00 / 50.00 也對。未動任何真實資料。

**驗證**

`npm run check` 全綠、RSpec 665/0、RuboCop 無 offense。vite 8 換掉所有 chunk
hash，重啟後逐頁重驗 `/iv_analysis`、`/watchlist`、`/technical_dashboard`，
console 零錯誤。

### 2026-08-29（五）— behaviors 全面型別化：765 個 strict error → 0

30 支 behaviors、共用模組與 entrypoints 全部從 `.js` 轉成 `.ts`。
`tsconfig.json` 的 `allowJs` / `checkJs` 已移除——**現在每一支前端程式碼都在
strict 型別檢查之下，沒有例外**。

> **歷史說明**：這一輪被自動提交 hook 拆成四筆 `chore: 自動提交` 且已推送
> （`5272f58` 基礎建設＋前 16 檔、`6772c7d` 中段 8 檔、`47acfd7` 最後 3 檔＋
> tsconfig 收尾、`9efc16e` `numeric()` 回歸修正）。因為禁止 force push，
> 歷史保持原樣，說明補在這裡。

**新增的基礎建設**

| 檔案 | 作用 |
|---|---|
| `types/globals.d.ts` | CDN 全域：`Chart` / `Sortable` / `NProgress` / `htmlToImage` / `jspdf` / `window.driver` / `ttsSpeak` / `switchDashMode` |
| `behaviors/shared/dom.ts` | `closestFrom` / `valueOf` / `csrfToken` |
| `behaviors/shared/json.ts` | fetch 回應收窄：`isRecord` / `str` / `num` / `numeric` / `arr` / `firstString` |

**零 `as`、零 `!`**

Global rules 要求 API 回應用 Zod 驗證、禁 `as`，但本專案 `npm install` 卡在
vite 的 peer dependency 衝突，Zod 裝不了。改用手寫 type predicate，整批轉換
**沒有任何 `as` 強轉，也沒有任何 `!` 非空斷言**（narrowing 在巢狀 function
declaration 裡會失效，一律改用明確型別的 const）。

**一個型別化造成的回歸（已修）**

Rails 把 BigDecimal 序列化成**字串**——`/api/iv_analysis/watchlist` 回的是
`skew_rank: "78.87"`、`strike: "100.0"`。原碼 `parseFloat` 吃得下，改成嚴格的
`num()`（`typeof === "number"`）之後整批被丟掉：Skew Rank 三張卡全變「—」、
摘要計數 3/0/0 變 0/0/0、觀察清單的履約價欄消失。

修法是新增 `numeric()`（parseFloat 語意），`ivAnalysis` 30 處改用。
**刻意不放寬 `num()`**：價差頁的 `fmt()` 原本就用 `typeof === 'number'` 判斷，
字串本來就顯示「—」，一起放寬會改壞那邊。

**保護機制：字面值比對**

型別化不該改動任何數值。`literal_check.py` 每批轉完就跟 `77c504f` 的原檔比對
數值與字串的多重集合。它抓到一次真錯：`ivEducationChart` 的 `normCDF` 常數被我
打成 `0.3989422804`（1/√(2π) 的真值），原碼是 `0.3989422820`。肉眼與測試都
抓不到。**30 支最終全部「數值零差異」。**

需要解釋的差異逐一程式化驗證：`techDashOptionsCharts` 的 4 份 tooltip CSS、
`momentumAnalysisPanel` 的 1309 字元 PDF CSS、`ivEducationChainTooltip` 的
177 條中文教學文案，都確認逐字相同。

**兩個靜態檢查抓不到、會炸站的問題**

- `entrypoints/application.js` → `.ts` 後 `vite_javascript_tag 'application'`
  解析失敗（實測 `ViteRuby.instance.manifest.path_for` 拋錯），layout 已改用
  `vite_typescript_tag 'application.ts'`
- `window.mountTechChart` 在 `technicals.tsx` 已宣告且簽名不同，重複宣告觸發
  TS2717，移除我的版本以實作端為準

**驗證**

`tsc --noEmit` 0 error、`eslint .` 0 error（warning 10 → 2）、RSpec 665/0、
RuboCop 無 offense。12 個頁面在瀏覽器逐頁實測，`/bpus` 與 `/bcvs` 走完整
Barchart 抓取流程，數字與型別化前逐項相同（bcvs K2 $327.50、淨成本 $6.40）。

**未驗到**：`portfolioHoldings` 的拖曳排序與獲利↔賣價雙向試算——`/portfolio`
目前無持股資料，那些路徑進不去。

### 2026-08-29（四）— M-6：兩支價差試算頁抽出共用模組

`bull_put_spreads` 與 `bull_call_spreads` 的重複程式碼在 H-3 之後變成兩支並排的
`.js`，這次把真正重複的部分抽掉。實測兩檔完全相同的行有 101 行（占 put 檔 22%），
其餘差異幾乎只是 DOM id 前綴（`bpus-` / `bcvs-`）。

**新增兩個共用模組**

- `behaviors/shared/spreadHelpers.js` —— `createSpreadHelpers({ prefix, statusPath })`
  回傳 `csrf` / `fmt` / `fmtLots` / `currentLots` / `showProgress` / `pollJob`
- `behaviors/shared/colTooltip.js` —— `initColTooltip({ prefix, colExplain })`，
  回傳 `{ drv, hide }` 供呼叫端擴充

Vite 確認兩對頁面各自 import 同一份 chunk（`_spreadHelpers`、`_colTooltip`），
不是各打包一份。

| 檔案 | 前 | 後 |
|---|---:|---:|
| `bullPutSpreads.js` | 503 | 471 |
| `bullCallSpreads.js` | 434 | 403 |
| `bullPutTooltips.js` | 57 | **19** |
| `bullCallTooltips.js` | 73 | 57 |

**三個實作決定**

1. **tip 容器 id 用 prefix 參數化，不改名**——`application.css` 對
   `#bpus-col-tip` 與 `#bcvs-col-tip` 各有一份樣式，`.tip-t` 字級還不同
   （13px vs 22px）。`prefix + '-col-tip'` 產生完全相同的 id，CSS 一行不用改。
2. **`pollJob` 的 statusPath 改成建立時綁定**——原本 put 版讀 `CFG.routes.status`、
   call 版當第二個參數傳，統一後 call 端兩處呼叫各少一個參數。
3. **bcvs 的 9 步導覽改成獨立 click listener**——原本接在欄位 popover 的 `return`
   之後。共用核心只處理 `[data-tip-key]`、這裡只處理 `#bcvs-tour-btn`，同一次點擊
   不會同時命中（已實測：點欄位只開 1 of 1，不會誤觸 1 of 9）。

順帶清掉 bcvs 版 `fmt` / `fmtLots` 多寫的 `n !== null`——前面已有
`typeof n === 'number'`，而 `typeof null === 'object'`，那個檢查永遠不成立。

**驗證**

665 examples / 0 failures、RuboCop 通過、`tsc` 0 error、`eslint .` 0 error。

兩頁在瀏覽器各跑完整流程，數字與重構前逐項相同：

| | `/bpus` | `/bcvs` |
|---|---|---|
| 選擇權鏈 | 108 列 | 105 列 |
| 試算 | 淨權利金 $55.00、ROC 5.8% | K2 $327.50、淨成本 $6.40 |
| 口數 3 | `$55.00 × 3 = $165.00` | `$640.00 × 3 = $1920.00` |
| tooltip | 13px ✅ | 22px ✅ |
| 其他 | — | 修復模式 $-530/-60/+720、導覽 1 of 9 |

console 零錯誤零警告。

### 2026-08-29（三）— 全面清掃「原始碼裡有、執行時到不了」的死碼

把當天稍早發現的兩類問題掃過整個 codebase：預設關閉但沒人開啟的可選功能，
以及被上游 constraint 蓋掉的驗證。

**刪掉 3 個正式碼零呼叫端的元件（171 行）**

| 死元件 | 被什麼取代 |
|---|---|
| `DailyMomentum::NewsCardComponent` | `NewsTabPanelComponent` + `momentumNewsTabs.js` |
| `DailyMomentum::WatchlistTableComponent` | `WatchlistManagerComponent` |
| `FairValue::PageLayoutComponent` | `app/views/layouts/application.html.erb` |

`PageLayoutComponent` 在 `log/development.log` 裡留有 `undefined method
'stylesheet_link_tag'` 的例外記錄——它不只沒人用，最後一次被渲染時就已經壞了。
三個都只剩 Lookbook preview 在引用，preview 一併刪除。

**清掉 4 處死碼／no-op**

- `bullPutSpreads.js` `hideProgress()`——沒有任何呼叫處。`showProgress()` 之後
  每條路徑都是整頁導覽，頁面直接被銷毀，所以本來就不需要收起進度條
- `bullPutSpreads.js` 重複的 `runCalculate()`——函式宣告會提升，後面同名那份
  永遠覆蓋前面這份（少了 `lastCalcResult` 與追蹤事件），從未執行過
- `bullCallSpreads.js` `k2Bid`——先用 `tab.k2 - tab.breakeven + k1` 算一次，
  下面必定覆寫，算出來的值從來沒被讀過
- `bullCallSpreads.js` `fillRepairFromTab()`——寫進 `basisInput` 的兩個 data
  attribute 全專案沒人讀（其中一行的三元運算子兩邊還都是空字串），
  `runRepairIfReady()` 是從 `lastTabs[activeTab]` 與鏈上那一列取值。移除後整個
  包裝函式只剩一行轉呼叫且參數已無用，直接內聯

**ESLint 閘門修好**

`npx eslint .` 原本會吐出兩萬多則來自 `storybook-static/`、`vendor/assets/`、
`venv/` 的雜訊——等於整個 lint 閘門沒人跑得動（先前回報的「0 error」是限定範圍
跑出來的）。補上建置產物的 ignores，再為 `app/assets/javascripts/**`（Wave 1 拆出
的 LEAPS 靜態檔）與 `.cjs` 補上正確的 globals，剩下的 12 個 error 逐一處理完。

現在 `npx eslint .` 全庫 **0 error**，10 個 warning 是逐字搬移的 ES5 慣用寫法
（`no-redeclare`、三元運算子當敘述）與兩處刻意的 `set-state-in-effect`，留給
型別化那一輪。

**沒有動的**

`ValuationTableComponent` 的 `show_formulas` 也是永遠 false，但呼叫端
（`valuations/show.html.erb:39`）是**明確傳 `false`**，屬於刻意關閉而非疏漏，
跟 `alert-dismiss` 那種沒人想過的情況不同，留待產品決定。

**驗證**

665 examples / 0 failures、RuboCop 通過、`tsc --noEmit` 0 error、`eslint .` 0 error。
瀏覽器實測受影響的兩支：`/bpus` 走完到 108 列選擇權鏈 → 選腳 → 試算（$55.00
淨權利金）→ 改口數重繪（`$55.00 × 3 = $165.00`，證明 `lastCalcResult` 有寫入）；
`/bcvs` 走完到 105 列 → K1 推薦三分頁 → 修復模式試算（≤K1 $-530.00／口、
中間情境 $-60.00／口、≥K2 鎖定 $720.00／口）。

### 2026-08-29（二）— 兩處「原始碼裡有、執行時到不了」的死碼修好

同日稍早的瀏覽器驗證挖出兩個同一類問題：程式碼寫了、測試也掃得到，但實際跑起來
永遠不會執行。

**1. 提示訊息的關閉按鈕（`alert-dismiss`）**

`FairValue::AlertComponent` 的 `dismissible` 預設 `false`，而全部 5 個呼叫端都沒有
傳 `true`（只有 Lookbook preview 會），所以那顆 ✕ 在正式站從來不會渲染。

預設值改成 `true`——現有用法全是 flash 提示，本來就該能關掉。要保留不可關閉的
用法仍可明確傳 `dismissible: false`。

**2. `ValuationsController#validate_ticker`**

HTML 路由的 `TICKER_CONSTRAINT` 與 controller 裡的檢查等價，不合法代號在路由層
就被擋成 404，那段「無效的股票代號」的友善提示永遠進不去。

但搜尋列（`tickerSearch.ts`）只檢查非空就直接 `window.location.href = ...`，所以
使用者打「台積電」或帶空白的代號，看到的是原始 404 頁。

HTML 路由改成收下整個 segment、由 controller 驗證並導回首頁。兩個實測確認的細節：

- `format: false` 是必要的——放寬 constraint 之後 Rails 會把 `BRK.B` 的 `.B` 當成
  格式後綴切掉（原本的 constraint 剛好含 `.` 才沒發生）
- API 端（`api/v1/valuations`）維持嚴格 constraint：對 API 而言 404 才是對的回應

**新增測試**

`behavior_registry_spec` 掃原始碼，看到 `behavior: "alert-dismiss"` 就算通過，
但那證明的是「原始碼裡有」，不是「執行時會渲染」。新增的兩支 request spec 補的
就是那一層：

- `spec/requests/alert_dismiss_spec.rb`（4）
- `spec/requests/valuation_ticker_validation_spec.rb`（8）

**涉及檔案**

- `app/components/fair_value/alert_component.rb`
- `app/controllers/valuations_controller.rb`
- `config/routes.rb`
- `test/components/previews/fair_value/alert_component_preview.rb`

### 2026-08-29 — H-3 瀏覽器實測 30 個 behavior，順手修掉字級還原白名單漂移

H-3 搬遷完成當下，30 個 behavior 裡只有 4 個（登入頁上的）驗過。這次登入後在真實
瀏覽器把 12 個頁面全部走完，確認每個 chunk 都以 200 載入、CSP 沒擋下任何 script，
並對互動類的實際操作過（tooltip hover、分頁切換、拖曳排序掛載、刪除確認攔截、
Chart.js 建立、bpus/bcvs 完整跑到選擇權鏈 108 列）。

`alert-dismiss` 是唯一無法在正式站觸發的——所有呼叫端都沒傳 `dismissible: true`
（只有 Lookbook preview 會），它在正式站從來不會渲染。這是搬遷前就存在的死路，
改用直接載入 chunk + 重建元件 DOM 形狀的方式驗證模組本身。

**修正：字級選 19–22px 換頁後被打回預設**

`FontSizeControlsComponent::SIZES` 給的是 18–22px，但 layout 裡「繪製前還原字級」
的白名單寫死 `['14','15','16','17','18']`，交集只有 `18`。`git show cdd4964^`
確認搬遷前就是這樣，不是 H-3 造成的。

改成兩邊都從同一個常數推導（元件新增 `.allowed_sizes`，layout 與 behavior 都讀它，
behavior 改吃 `data-sizes`），避免兩份寫死再次漂移。

**涉及檔案**

- `app/components/fair_value/font_size_controls_component.rb`
- `app/views/layouts/application.html.erb`
- `app/frontend/behaviors/fontSizeControls.js`

### 2026-08-28 — H-3 完成：內嵌 JavaScript 全數搬進 Vite，CSP 拿掉 `unsafe_inline`

接續同日的 Wave 1。Wave 2 處理有 Ruby 插值的 6 個元件（707 行，改用 data attribute
傳值），Wave 3 處理 `bull_put_spreads` / `bull_call_spreads`（1,038 行、35 處插值，
路由與頁面狀態改用單一 `data-config` JSON——`dataset` 只能給字串，會把 `nil` 變成
空字串而改變 truthiness，用 JSON 才能保留 `null` 與數值型別）。

最後把 layout 自己的 3 段與 `stock_alerts/index.html.erb`、`alert_component.rb`
也一併清掉。

**成果**

| | 前 | 後 |
|---|---|---|
| 元件內嵌 JS | 3,933 行 / 18 個元件 | **0** |
| 全站 inline `<script>` | 22 段 | **1 段**（帶 CSP nonce） |
| CSP `script-src` | `'self' 'unsafe-inline' cdn` | **`'self' cdn 'nonce-…'`** |
| `npx tsc --noEmit` | 跑不動（沒有 tsconfig） | **0 error** |
| ESLint | 22 problems（20 個是假陽性） | **0 error** |

唯一保留的 inline script 是還原字級那段——它必須在瀏覽器繪製前執行，不能等
Vite module 的 defer，否則每次換頁都會看到字級閃動。改用
`javascript_tag nonce: true` + `content_security_policy_nonce_generator`
放行（專案沒有 fragment cache，不會有快取到舊 nonce 的問題；日後要加 fragment
cache 前務必重新確認這點）。

`style-src` 仍保留 `unsafe_inline`：Phlex 與 Tailwind 大量使用 inline style
屬性與 `<style>` 區塊，那是另一件事。

**ESLint 上線後在搬遷的程式碼裡抓到的**（都是搬遷前就存在的）：
`bullPutSpreads.js` 的 `hideProgress()` 全專案沒有任何呼叫處；
`bullCallSpreads.js` 的 `k2Bid`（L378）下一個分支必定覆寫，計算結果永遠沒被讀。
刻意不在搬遷這一輪動它們（優先保證行為完全不變），已在 `eslint.config.js` 註記。

**瀏覽器實測**（`/login`，唯一不需登入的頁面）：CSP header 已無 `unsafe-inline`、
inline script 帶 nonce 且正常執行、`releaseNotes` 與 `appSwitcher` 兩個搬遷後的
模組點擊開關都正常運作、console 零錯誤零警告。

**尚未驗證**：其餘 26 個 behavior 分布在登入閘門後的頁面，尚未做視覺與互動驗證。

**後續**：`behaviors/*.js` 型別化成 `.ts`（逐字搬進 strict TS 光 `ivAnalysis`
一支就有 209 個錯誤）；`bull_put` / `bull_call` 兩支之間的大量重複（稽核 M-6）
現在變成兩個並排的 `.js`，可以直接 diff 抽共用，比在 Ruby heredoc 裡容易得多。

### 2026-08-28 — H-3 Wave 1：內嵌 JavaScript 搬進 Vite，並補上 TypeScript / ESLint 把關

**前置：把前端的檢查機制建起來**

- 新增 `tsconfig.json`（`strict: true`）。原本專案沒有 tsconfig，`npx tsc --noEmit`
  根本跑不動。修掉既有的 9 個型別錯誤後，型別檢查現在是 **0 error** 的真實 gate。
  `noUncheckedIndexedAccess` 暫時關閉——開啟後還有約 30 個「可能是 undefined」要處理，
  集中在 `OptionsChainTable.tsx` 與 `payoff.ts`，留給獨立的一輪
- `eslint.config.js` 補上瀏覽器全域宣告。原本沒有宣告，導致 `document` / `window` /
  `fetch` 一律被 `no-undef` 判成錯誤——**20 個假陽性，等於 ESLint 對前端形同虛設**。
  修好之後又修掉 4 個真錯誤（2 個未使用的 catch 參數、2 個 `any`），
  現在是 **0 error / 2 warning**
- `package.json` 新增 `npm run typecheck` 與 `npm run check`

**搬遷**

新增 `app/frontend/entrypoints/behaviors.ts`：掃描 `[data-behavior]`，用動態 import
只載入該頁真正需要的模組，Vite 自動 code-split。Phlex 元件只留一行掛載標記
`div(data: { behavior: "..." })`，新增行為不需要動 layout。

搬遷 10 個元件、12 段、**2,188 行**（占全部內嵌 JS 的 56%）：

| 元件 | 檔案行數 |
|---|---|
| `iv_analysis/page_component.rb` | 751 → **30** |
| `iv_analysis/education_component.rb` | 1348 → 884 |
| `daily_momentum/analysis_panel_component.rb` | 277 → 49 |
| `iv_watchlists/index_view.rb` | 263 → 46 |
| `portfolio/holding_list_component.rb` | 326 → 170 |
| `shared/ownership_panel_component.rb` | 213 → 72 |
| `daily_momentum/news_tab_panel_component.rb` | 184 → 49 |
| `daily_momentum/watchlist_manager_component.rb` | 149 → 77 |
| `stock_alert/alert_list_component.rb` | 177 → 143 |
| `fair_value/search_bar_component.rb` | 147 → 127 |

擷取用 **Ruby 自己求值**而不是純文字複製：unquoted heredoc（`<<~JS`）Ruby 會先處理
反斜線跳脫，直接複製會讓 `'\n'` 從換行變成 literal `\n`、`/\d+/` 變成 `/\\d+/`。
實際有 14 行受影響。

最小的兩支（`tickerSearch` / `alertList`）直接改寫成 strict TypeScript；其餘 10 段
逐字搬成 `.js`（`allowJs: true, checkJs: false`，誠實標示未型別化），
優先保證行為完全不變。逐字搬進 strict TS 光 `ivAnalysis` 一支就有 209 個型別錯誤，
全部型別化是獨立的一輪工作。

**ESLint 上線後立刻抓到的東西**：`window.switchDashMode` 被以 bare call 呼叫
（語意正確但靜態分析看不到，已改成 `window.` 前綴）、`Option` / `Audio` /
`EventSource` 等未宣告全域、6 處 `var` 重複宣告。

新增 `spec/frontend/behavior_registry_spec.rb`（5 個案例）把元件與模組之間那條
只剩字串的連結釘住：未註冊的 marker、註冊了卻沒有檔案、模組沒 export `init`、
沒人使用的孤兒、以及「已搬遷的元件不可以又把 JS 塞回 heredoc」。

**驗收**：RSpec 653 examples / 0 failures、`tsc --noEmit` 0 error、
ESLint 0 error、RuboCop 無 offense、12 個 behavior chunk 都有產出 source map。

**剩餘**：8 個元件、1,745 行內嵌 JS（`bull_put_spreads` 552、`bull_call_spreads` 486、
`technical_dashboard` 458 是大宗，都有較多 Ruby 插值），以及 layout 自己的
inline `<script>`。要拿掉 CSP 的 `unsafe_inline` 得等這些全部清完。

### 2026-08-28 — 觀察清單加上使用者歸屬（C-2 第二階段）

稽核 C-2 原本只做了 `margin_positions` / `portfolios` / `price_alerts`，
剩下三張表被擱置的原因是**它們都有排程在讀，而排程沒有 `current_user`**：

| 表 | 誰在讀 | 頻率 |
|---|---|---|
| `tracked_tickers` | systemd `options-collector.timer` + `options-intraday.timer` → `options_collector.py:138` | 每日 EOD + 每 30 分 |
| `watchlist_items` | pm2 `ouou-pre-market` → `OuouPreMarketService#watchlist_symbols` | 每日盤前 Telegram |
| `iv_watchlists` | pm2 `iv-skew-snapshot` / `iv-skew-intraday` → `lib/tasks/iv.rake:25,51`、`backfill_iv_skew.py:168` | 每日 + 盤中 |

能不能分人，取決於**蒐集結果怎麼 key**：`iv_daily_snapshots` / `skew_rank_daily` /
`skew_rank_intradays` 都是 ticker-keyed，一個代號只會有一份，多人追蹤不會重複抓；
`option_snapshots` 則是綁 `tracked_ticker_id` 且有 80 萬列。

- `watchlist_items`、`iv_watchlists` 加 `user_id`，既有資料歸給 admin。
  `symbol` 的唯一索引從「全站唯一」改成 `[user_id, symbol]`，
  否則第二個使用者連加入同一個代號都會被擋
- 排程改取**所有使用者的聯集**（`WatchlistItem.ordered.pluck(:symbol).uniq`、
  `IvWatchlist.active.pluck(:symbol).uniq`）。既有資料全歸 admin，
  所以聯集 == 目前的集合，排程行為完全不變（實測盤前 23 個代號、skew 7 個代號，與修改前一致）
- `db/seeds.rb` 改成掛在 admin 底下；沒有任何使用者時跳過而不是炸掉
- `tracked_tickers` 維持共用，改為**只有 admin 能寫入**（`create` / `update` /
  `destroy` / `collect`），避免其他帳號刪代號時連帶 `dependent: :destroy`
  掉整段歷史快照；讀取仍開放給所有登入者
- 新增 `spec/requests/watchlist_isolation_spec.rb`：跨使用者看不到／刪不掉、
  排程取聯集、tracked_tickers 的 admin 限制，共 9 個案例

**仍未處理**：`tracked_tickers` 要真正分人，得先把 `option_snapshots` 從
`tracked_ticker_id` 改成 symbol-keyed 再拆出個人訂閱表——那是 80 萬列的遷移，另開。

**驗收**：RSpec 648 examples / 0 failures、Brakeman 0 warnings、RuboCop 349 檔無 offense；
正式資料完好（WatchlistItem 23、IvWatchlist 6、OptionSnapshot 801,222）。

### 2026-08-28 — 正式資料庫更名，並補回 Rails 破壞性指令的保險

接續同日的稽核修正。稽核時發現「測試環境連到正式資料庫」，堵住測試那一側之後
追下去，根因是**正式資料住在一個叫 `fairprice_development` 的資料庫裡**，
`fairprice_production` 根本不存在。

連帶造成 Rails 最重要的一道保險失效：`protected_environments` 檢查的是
**資料庫裡存的環境標記**，而那個標記是 `development`——
`rails db:drop` / `db:reset` / `db:schema:load` 打在正式資料上，一句都不會攔。
（先前 `db:test:prepare` 之所以被擋，撞到的是另一道 `EnvironmentMismatchError`，
是名字對不上的運氣，不是保護。）

- `ALTER DATABASE fairprice_development RENAME TO fairprice_production`，
  `ar_internal_metadata.environment` 改為 `production`
- `.env` 的 `DATABASE_URL`、`scripts/backup_db.sh`、`install.sh`、
  `python/fix_missing_prices.py`、`scripts/options_collector.py` 一併更新
- `config/database.yml` 的 `development` 也指向 `fairprice_production`
  ——這台機器上本來就沒有獨立的開發資料庫，明寫出來比讓它看起來像分開的好
- `config/application.rb` 設 `protected_environments = %w[production development]`：
  兩個環境共用同一個庫時，那個標記會被 `db:migrate` 寫成當下的 `RAILS_ENV`，
  只保護 `production` 的話，隨手跑一次不帶 `RAILS_ENV` 的 `db:migrate`
  就會把標記翻回 `development`，保險靜靜失效。兩個名字都保護才擋得住

**驗收**：`rails db:drop`（development 模式）已被 `ProtectedEnvironmentError` 擋下；
`db:test:prepare` 與備份腳本照常運作；RSpec 638 examples / 0 failures；
資料完好（User 5、OptionSnapshot 796,822）；公網 UI 302、API 未登入 401。

### 2026-08-28 — 稽核修正：關閉 `/api/*` 公網匿名存取，個人資料加上使用者歸屬

以 `RAILS_AUDIT_REPORT.md` 的稽核結果為依據執行修正。

**Critical**

- **`/api/*` 整個命名空間過去不需要登入，且 CSRF 關閉**。`ApplicationController` 的
  `GATE_EXEMPT_PREFIXES` 含 `/api`，導致 Google OAuth + 強制 TOTP + 雙重逾時那一整套
  防護在 API 上完全不生效。實測 `https://fairprice-ohmy.com/api/v1/tracked_tickers`
  從公開網際網路匿名回 200 + 真實資料，`DELETE /api/v1/margin_positions/:id` 等
  破壞性端點同樣匿名可打。現在 API 與 UI 共用同一份閘門，只是把 302 導頁換成
  401/403 JSON（新增 `JsonAuthGate` concern）；CSRF 由 `null_session` 改為 `exception`
- 前綴白名單由 `start_with?` 改成 anchored regex，避免 `/logout_backdoor` 這類路徑誤入白名單
- **個人性資料加上 `user_id`**（`margin_positions` / `portfolios` / `price_alerts`），
  既有資料歸給 admin。目前有 5 個 enabled 帳號，這些表過去是全站共用的；最嚴重的是
  `PortfoliosController#ocr_import` 裡的 `Portfolio.delete_all`——任何使用者匯入截圖
  就會清空所有人的持股。`TrackedTicker` / `WatchlistItem` / `IvWatchlist` 刻意不加歸屬，
  它們是共用的市場資料與排程來源
- **測試環境連到正式資料庫**：`.env` 的 `DATABASE_URL` 寫死指向 `fairprice_development`，
  而 dotenv-rails 在 test 環境同樣會載入 `.env`，整套 RSpec 一直跑在正式資料上
  （`db:test:prepare` 曾試圖 purge 正式資料庫，被 Rails protected environments 擋下）。
  `config/database.yml` 的 test 區塊改為明確指定 `url:` 壓過 `DATABASE_URL`。
  隔離後原本 13 個失敗中有 8 個消失——那些是正式資料污染造成的假結果

**High**

- `tracked_tickers#collect` 從 request 內同步跑 Python 子行程改成 `CollectOptionSnapshotsJob`
  背景執行，加上 5 分鐘硬性 timeout 與子行程強制回收。過去無 timeout，`RAILS_MAX_THREADS`
  只有 5，五個請求就能讓整站沒有回應。前端改為輪詢 `collect_status`
- `config.force_ssl` 啟用（Secure cookie）。刻意不開 `assume_ssl`——它會無條件把每個請求
  標記成 https，讓本機 `http://localhost:3003` 的 redirect 也變成 https。改為依
  cloudflared 送來的 `X-Forwarded-Proto` 判斷，公網 https、本機 http 兩邊都正確。
  HSTS 交給 Cloudflare 端設定，避免把 localhost 鎖成 https
- `TrackedTicker#last_snapshot_date` 的 N+1：兩個 controller 各自維護一份重複的
  serializer 且都逐筆查 `MAX(snapshot_date)`（`option_snapshots` 有 79 萬列）。
  抽成 `TrackedTickerSerializer`，改用單次 group query（實測 3 個代號由 3 次降為 1 次）
- `api/iv_analysis#watchlist` 每個代號開 3 條 thread 且無上限，改為比照
  `MomentumReportService` 的分批寫法
- `bundle update mail`（GHSA-mvxr-6m87-mv2q）

**Medium**

- 移除 `public/tech_prototype.html`——`public/` 下的檔案繞過登入閘門與瀏覽軌跡記錄
- 三處把 `e.message` 直接回傳給客戶端的地方改為 log 詳細、回籠統訊息
  （`Api::V1::Valuations#show`、`Api::V1::Options#analyze_image`、`Portfolios#ocr_import`）
- `BarchartScraperService#cdp_available?` 的裸 `rescue` 補上記錄（全專案唯一一處無記錄的）
- `TrackController#page_view` 檢查 `save` 回傳值
- `iv_queries` 補上 `[ticker, queried_at]` 索引（全專案唯一沒有任何索引的表）
- 三處前端寫入請求缺 `X-CSRF-Token` 已補齊，`csrfToken` 重複定義抽成 `app/frontend/lib/csrf.ts`

**驗收**：RSpec 638 examples / 0 failures（隔離的 test DB）、Brakeman 0 warnings、
RuboCop 339 檔無 offense、bundler-audit 無漏洞、ESLint 無新增問題。
公網實測 `/api/*` 未登入回 401。

### 2026-08-27 — 修復 playwright-chrome MCP 連不上，`@playwright/mcp` 升到 0.0.79

- `@playwright/mcp` 由 0.0.77 升到 0.0.79（local + global）
- MCP log 顯示 2026-08-07 ~ 08-27 每一次 session 都是同一則錯誤「Chrome CDP（port 9224）連不上」，並非 playwright-mcp 崩潰 —— 8/06 改連 9224 時沒有對應的 keeper，重開機後沒人拉起那個視窗。已在 `x-order-manager-systems` 補上 pm2 `chrome-cdp-keeper-9224`
- 移除重複的 MCP 定義：user scope 的 `railsMcpServer` 刪除，保留專案 scope 的 `rails-mcp-server`
- 移除已廢棄的 pm2 `cdp-relay`（Docker 端早已改用 `network_mode: host` 直連 9222）

### 2026-08-26 — 修復失效已久的排程備份，並將備份異地同步到 Windows 桌面

- pm2 `fairprice-db-backup`（每日 22:00）產出的備份長期都是 0 或 20 bytes 的無效檔。根因是 `scripts/backup_db.sh` 從未 `source .env`，`DB_PASSWORD` 永遠為空，`pg_dump` 轉為互動式索取密碼而失敗
- 次要根因：空檔檢查只有 `[[ ! -s ]]`（僅擋 0 bytes），但 `pg_dump` 失敗時 `gzip` 仍會產生 20 bytes 的有效空壓縮檔，通過檢查後冒充成功的備份
- `scripts/backup_db.sh` 重寫：加 `source .env`；`pg_dump -w` 絕不互動式問密碼；完整性驗證改為 `gzip -t` + 檢查 `PostgreSQL database dump complete` 結尾標記；`pg_isready` 重試等待 PostgreSQL 就緒；備份成功後同步一份到 Windows 桌面 `fairprice backup/`；保留策略 7 天並涵蓋 `pre_edit_*`（舊版只清 `fairprice_development_*`，是本機堆積到 1.7 GB 的原因）
- 清理空檔必須用 `find -size -1024c`（byte 單位）。`-size -1k` 以 1k 區塊計算且向上取整，20 bytes 算作 1 個區塊，永遠刪不到

### 2026-08-10 — 修正 LEAPS 推薦分析誤用「近期無成交」警示排除高 OI 候選

- `LeapsRankingService#low_vol_oi?` 的「近期無成交」其實是 Volume/OI 比值在查詢池中的後 1/3 分位（相對排名），不是字面上的零成交，OI 極高但比值偏低的合約也會被誤標
- `LeapsRecommendationService#recommend_group` 原本拿這個警示做 `reject` 排除，導致近天期推薦選中 OI 遠低於候選表榜首的合約，`build_reason` 卻寫「為此天期區間最高」，跟候選排行表對不上
- 修正：移除排除邏輯，推薦挑選純依 `liquidity_tier` + OI 排序（跟候選表邏輯一致）；警示改為對 `pick` 本身的資訊性提示，文案改為「Volume/OI 比率偏低」
- 詳見 `tasks/lessons.md` 2026-08-10 條目

### 2026-07-13 — 新增牛市差價看跌期權(三級版)試算工具

- 新增 `/bpus` 頁面：輸入代號 → 選履約日 → 從 Barchart Put 鏈選保護腳(Long Put)/CSP 腳(Short Put) → 即時算淨權利金、押金、損益平衡點、ROC、風險報酬比，並標示賠錢情境
- 新增 Python sidecar `bpus_expirations_scraper.py` / `bpus_put_chain_scraper.py`，沿用既有 CDP 9222 直連模式（未經 9223 relay）
- 新增 `BullPutSpreadCalculatorService` 純計算 service、`BullPutSpreadsController`、`BpusFetchExpirationsJob`/`BpusFetchChainJob`、`BullPutSpreads::PageComponent`
- Sidebar 最後一項加入口
- 修正過程中發現並修正兩個既有機制的相容性問題：`FetchLog::FETCH_TYPES` 白名單需同步加入新 fetch_type（否則 `log_fetch` 內部 rescue 會靜默吞掉 `RecordInvalid`）；Barchart Options 頁面帶 `view=sbs` 時會同時掛載多個 `bc-data-grid`（Call/Put/合併），不能只抓第一個 grid

### 2026-06-21 — 技術面/基本面/Options Flow 三維度判斷儀表板

- 新增 Barchart CDP scraper 三件套（, , ）
- 直接 WebSocket 連 CDP（非 Playwright），解決 Windows Chrome 背景 tab 凍結問題（Target.activateTarget）
- 新增 DB 表：, , , 
- ：依序爬取三維度資料，任一步驟 session 過期即中止
- ：三個獨立分數（技術/基本面/Options Flow），絕不合併，背離時生成警示文字
- Phlex ：深色評分卡、背離警示、5 分鐘快取
- 路由：，已加入側邊欄 🧭 三維度判斷


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

### 2026-08-06 — LEAPS 排行移除 Delta 0.90 上限，改為 Delta>=0.60 全部列出

**動機：** 使用者查 NOK 履約價 4.5，推薦分析卻換成鄰近的 $5.00。查明是 `LeapsRankingService` 的 `DEFAULT_DELTA_MAX = 0.90` 從未被移除過——2026-07-01 那次「放寬 Delta 篩選」只調了下限（0.75→0.60），上限一直卡著。$4.5 在 2028-01-21 到期的 Delta 是 0.9008，只差 0.0008 就超過舊上限，整檔被排除候選名單。

**異動內容：**
- `app/services/leaps_ranking_service.rb`：拿掉 `DEFAULT_DELTA_MAX`，`fetch_candidates` 只用 `delta >= @delta_min` 篩選，深度價內（Delta 逼近 1）候選不再被排除
- `app/components/leaps_recommendations/page_component.rb`、`app/components/fair_value/app_switcher_component.rb`：sidebar 與頁面說明文字同步從「Delta 0.60–0.90」改成「Delta ≥ 0.60」
- `leaps-call-recommendation-spec.md`：更新規格文件所有 0.60–0.90 篩選描述為 Delta>=0.60（無上限），記錄變更日期
- `lib/barchart_scrapers/leaps_scraper.py`：更新 comment 說明 Stage 2 最終篩選同步移除上限
- `spec/services/leaps_ranking_service_spec.rb`：更新 delta filter 邊界測試

### 2026-08-05 — 全專案安全性維護：rubocop 修正、Brakeman 升級、22 個 CVE gem 升級

**動機：** CI 的 `lint` 與 `scan_ruby` job 長期處於失敗狀態（在這次修改之前就已經壞了），順手一次清乾淨，讓 CI 恢復綠燈當作日常品質關卡。

**異動內容：**
- `bundle exec rubocop -A` 修掉 29 個檔案、136 筆違規（主要是 `Layout/SpaceInsideArrayLiteralBrackets`），修正後全專案 0 offenses
- Brakeman 8.0.4 → 8.0.5；升級後掃出 5 個警告，逐項審查確認皆非真漏洞（Open3 用 argv 陣列非 shell 字串、SQL 已用 `connection.quote()`/`clamp` 防護、`send_file` 已有路徑穿越邊界檢查），寫入 `config/brakeman.ignore`
- `bundler-audit` 抓到的 22 個有已知 CVE 的 gem 全部升級：Rails 全家桶 8.1.2 → 8.1.3.1（`actionpack`/`actionview`/`activestorage`/`activesupport` 等，修 XSS 相關 CVE）、`action_text-trix`、`view_component`、`websocket-driver`、`yard`、`rack`、`nokogiri`、`puma`、`json` 等
- `~/.claude/hooks/pre-commit-rubocop.sh`（新增）：commit 前對 staged `.rb` 檔案跑 rubocop 檢查模式，補上 `post-edit-ruby.sh` 只在 Claude Code Edit/Write 時觸發的覆蓋盲區
- `~/.claude/hooks/post-edit-ruby.sh`：修正 exit code bug（`rubocop -A | head -20` 讓 `$?` 恆為 head 的結束碼，改用 `PIPESTATUS[0]`）
- `~/.claude/hooks/pre-commit-xss-scan.sh`：加上「單行 >400 字元視為 minified/vendored 略過」的過濾規則，避免誤判內建在課程 html 裡的 driver.js 等第三方套件

### 2026-08-05 — 修復 public/csp 未登入即可存取漏洞，新增全站閒置逾時機制

**動機：** 使用者反應 `https://fairprice-ohmy.com/csp/index.html` 不需登入就能看到、也不會留下瀏覽記錄。查明是 `public/csp/` 整包靜態檔案（381 個檔案，含期權小學堂工具、內部筆記、截圖、開發過程遺留的 `.claude/` 設定殘留）繞過 `enforce_auth_gate`——`ActionDispatch::Static` 直接把 `public/` 下的檔案吐給瀏覽器，根本沒進到 Rails controller，pm2 日誌顯示已有外部 IP（61.230.110.224）實際掃到並存取過。

**異動內容：**
- 期權小學堂工具本體（12 個課程 html + 5 個圖片/svg）搬到非 public 的 `private/csp_lessons/`，其餘 364 個開發過程遺留檔直接刪除
- `app/controllers/csp_lessons_controller.rb`（新增）：serve `private/csp_lessons/`，走登入驗證 + 記錄 `page_view` 瀏覽記錄
- `config/routes.rb`：新增 `get "csp/*path"`（注意 `format: false`，否則 `.html` 副檔名會被當成 format 參數吃掉導致 404）
- `app/components/fair_value/app_switcher_component.rb`：sidebar 新增「期權小學堂」入口
- `app/controllers/application_controller.rb`、`app/controllers/sessions_controller.rb`：新增全站閒置 2 小時強制重新登入機制（`enforce_idle_timeout`），`mr.idarfan@gmail.com` 例外不受限
- `lib/barchart_scrapers/leaps_scraper.py`：`main()` 例外不再印出裸 Python traceback，改為結構化 JSON 錯誤輸出
- `app/services/barchart_scraper_service.rb`：正確處理 scraper 回傳的 `error` 狀態（原本會誤判成 success），並記錄完整 stderr 到 log
- `app/models/leaps_option_chain_snapshot.rb`：`FRESH_WINDOW` cache 新鮮窗從 30 分鐘調整為 1 小時
- `spec/requests/csp_lessons_spec.rb`、`spec/requests/idle_timeout_spec.rb`（新增）：涵蓋登入閘門、路徑穿越防護、閒置逾時三種情境

### 2026-04-19 — 期權鏈 Tippy+KaTeX tooltip 升級、水平溢出修正、中文欄位標籤

**動機：** 單選 Calls/Puts 模式新增 TradingView 風格欄位後表格水平溢出；tooltip 說明過於簡陋，缺乏數學公式；Bid/Ask 欄位應維持中文。

**異動內容：**
- `app/frontend/option_price_tracker/components/OptionsChainTable.tsx`：安裝 `@tippyjs/react` + `katex`，以 Tippy 取代 CSS hover tooltip（支援跨 overflow 容器定位、居中顯示）；各欄位 tooltip 含 KaTeX 數學公式、中文說明、黃底範例；改用 `table-layout: fixed` + 百分比欄寬消除水平捲動；單選模式欄位標籤改回出價/要價；修正 both-mode thead 多餘欄造成的錯位

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

### 2026-08-18 — 新增每日強制登出（24 小時絕對逾時）

- 除了原本的「閒置 2 小時登出」，新增「登入滿 24 小時強制登出」，即使持續有活動也一樣，避免瀏覽器分頁長期開著不關導致 session 一直存活。
- 登入時（`SessionsController#google_callback`）記錄 `session[:login_at]`，`ApplicationController#enforce_absolute_timeout` 每次請求檢查是否超過 24 小時。
- `IDLE_TIMEOUT_EXEMPT_EMAIL`（`mr.idarfan@gmail.com`）沿用既有排除設定，兩種逾時機制皆不套用在此帳號。
- 動機：`/track`、`/api` 皆在 `GATE_EXEMPT_PREFIXES`，不會觸發閒置檢查，若分頁不關、只靠背景 sendBeacon 心跳，session 可能無限期存活，導致帳戶管理頁的「累積停留時間」失真。強制每日登出可限制單一 session 的最長存活時間。

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/application_controller.rb` | 新增 `ABSOLUTE_SESSION_TIMEOUT` 常數與 `enforce_absolute_timeout` |
| `app/controllers/sessions_controller.rb` | 登入時記錄 `session[:login_at]` |
| `spec/requests/absolute_timeout_spec.rb` | 新增（24 小時強制登出測試，含排除帳號）|

### 2026-08-18 — 帳戶管理列表新增每日停留時間拆分

- 「累積停留時間」欄位維持全部歷史加總的總使用時數不變；新增可展開的近 7 天每日拆分（`<details>/<summary>`），方便判斷總數字是長期累積還是單日異常暴增。
- `Admin::UsersController#index` 新增 `daily_dwell_by_user`，沿用既有 `UserActivity.recent`（7 天）scope，依日期分組加總 `duration_ms`。
- `Admin::Users::PageComponent` / `RowComponent` 新增 `daily_dwell` 參數並傳遞、渲染。

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/admin/users_controller.rb` | 新增 `daily_dwell_by_user` |
| `app/components/admin/users/page_component.rb` | 新增 `daily_dwell` 參數 |
| `app/components/admin/users/row_component.rb` | 新增 `daily_dwell` 參數與可展開的每日拆分渲染 |
| `app/views/admin/users/index.html.erb` | 傳入 `daily_dwell` |
| `spec/requests/admin_users_spec.rb` | 新增每日拆分測試 |

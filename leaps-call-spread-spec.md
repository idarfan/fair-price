# LEAPS 垂直價差區塊 規格（leaps-call-spread-spec.md）

## 執行狀態表

> Claude Code 每完成一個階段、驗證通過後，立即用 patch 更新本表。接續 session 只需讀本表和「進行中」階段的章節。
> 狀態值：`待辦` / `進行中` / `通過` / `跳過（附理由）`

| 階段 | 名稱 | 狀態 | 驗證證據（指令與輸出摘要、截圖路徑） |
|---|---|---|---|
| P0 | 探勘與定位 | 通過 | 2026-09-25。4 項與規格衝突的待決事項已由使用者裁示（附錄 A「決議」），規格相關段落已修改。驗證：附錄 A 內 TBD = 0；附錄 A 列出的 22 個既有路徑 `test -f` 全部存在（規劃中的 `app/services/leaps_call_chain_fetcher.rb` 除外）；第 12 步前後 `git diff -- app lib` 皆無變更；禁用 grep 對兩支 bcvs sidecar 皆 0 行；`cdp_helper.py` 的 4 處 `urlopen`／`Request` 目標皆為 `{CDP_BASE}`。實測：ORCL 6 個 LEAPS 到期日 max_strike／spot 最低 1.65；單一到期日最慢 7.61 秒 → `STALL_TIMEOUT = 30`；delta 100% 有值；查無代號與沒有 LEAPS 在既有 sidecar 皆為 `no_candidates`，判定 selector 已記錄（P1 需補判定） |
| P1 | 即時抓取與快取 | 通過（改版） | 2026-09-25 首版共用 bcvs，同日依決議 5 改成**不碰 bcvs**並重新驗證。新增：`db/migrate/20260925120000_create_leaps_spread_quotes.rb`、`app/models/leaps_spread_quote.rb`、`app/services/leaps_spread_cache.rb`、`app/services/leaps_call_chain_fetcher.rb`（`STALL_TIMEOUT = 30`）、`app/services/leaps_call_chain_fetcher/sidecar_runner.rb`（逐階段時限、終止程序群組、JSON 以 BigDecimal 解析）、`app/services/leaps_spread_fetch_lock.rb`、`lib/barchart_scrapers/leaps_spread_expirations_scraper.py`、`lib/barchart_scrapers/leaps_spread_chain_scraper.py`。**驗證**：`spec/services/leaps_call_chain_fetcher_spec.rb` 17 examples 0 failures（案例 1–11、不寫 bcvs 表、BigDecimal 回傳、SidecarRunner 實際逾時終止 2 例；「sidecar 呼叫次數」以到期日 chain 抓取次數計，到期日清單另外斷言）；`spec/services/leaps_spread_cache_spec.rb` 7 examples 0 failures；反向驗證：拿掉鎖後案例 8 失敗。Python：`test_leaps_spread_expirations_scraper.py` 7 項通過。實測 sidecar：ZZZZQ → `symbol_not_found`、BRK.A → `no_options`、ORCL → success（21 個到期日），chain ORCL 2029-01-19 29 列 delta 100%。實抓 ORCL（不 stub）：43 秒、6 個 LEAPS 到期日、270 列寫入 `leaps_spread_quotes`，max_strike／spot = 2.65、3.65、3.37、2.65、1.72、1.65（全部 ≥ 1.5），每個到期日都有履約價 100，數值皆 BigDecimal；bcvs 兩張表 ORCL 仍為 0 筆；再查命中快取 0.17 秒。禁用 grep：兩支垂直價差 sidecar 0 行。靜態檢查 `to_f\|Float(`（fetcher、runner、cache）：0 行。**bcvs 無回歸**：bcvs 所有程式與 spec 檔對 `57cdff9` 的 diff 為空，bcvs 相關 spec 全數通過。整體 `bundle exec rspec`：**1135 examples, 0 failures**（P0 基準 1111，全部保留）。備註：chain 的抓取時間取「全部成功後寫入」的時刻，同一輪各到期日相同 |
| P2 | 計算服務 | 通過 | 2026-09-25。新增 `app/services/leaps_vertical_spread_service.rb`（全部公式、預設值、報價規則、無效組合、錯誤訊息）與 `app/services/leaps_vertical_spread_service/format.rb`（選項文字、金額 `$` 千分位、ROUND_HALF_UP 2 位）。**驗證**：`spec/services/leaps_vertical_spread_service_spec.rb` **22 examples, 0 failures**（規格表格 17 案例 + 候選排行第 1 名預設、fetcher 錯誤原文傳出、停滯轉「Barchart 讀取失敗：…」可重試、選定到期日時只要求刷新該到期日、保守成交顯示）。反向驗證：植入「盤後也算 D_nat」→ 2 例失敗；植入「賣腳預設取第一檔」→ 3 例失敗。靜態檢查 `to_f\|Float(`（service、format、fetcher）：0 行。真實資料（ORCL、K_L = 100，不 stub）：買入腳 6 個到期日皆 100.00；候選排行無 100 → 取最遠有報價 `2029-01-19-m`；賣腳預設 230（該到期日最高履約價）；D_mid 36.925、W 130 → 實付淨成本 $3,692.50（保守 $4,085.00）、最大獲利 $9,307.50、損益兩平 $136.93、風險報酬比 1 : 2.52，D_mid 為 BigDecimal |
| P3 | 路由與 Controller | 通過 | 2026-09-25。新增 `GET /leaps/vertical_spread`（`LeapsRecommendationsController#vertical_spread`：422、CDP 預檢、呼叫 service、回傳不含 layout 的片段；進度查詢走同一條路由帶 `progress=1` 回 JSON，不觸發抓取也不做 CDP 預檢，以維持「只有一條路由」）。`page_component.rb` 在 `render_pmcc_section` 前插入 `render_vertical_spread_frame`，並在候選區塊外補一行「沒有候選時也顯示」；PMCC 那一行未修改。新增 `app/components/leaps_recommendations/vertical_spread_frame.rb`、`vertical_spread_section.rb`。因 `spec/…behavior registry` 防護測試要求 `data-behavior` 必須註冊，前端 `app/frontend/behaviors/leapsVerticalSpread.ts`（取片段、選單變動、重試、進度輪詢）提前在 P3 完成。**回歸基準**：P0 的基準是瀏覽器 DOM（P5 用），request spec 另在**尚未修改程式時**擷取伺服器 HTML 基準 `spec/fixtures/leaps_vertical_spread/server_baseline/`（5 種輸入：空白、只有代號、代號＋100、不合法價格、有候選且 PMCC 顯示；commit `dbf8aac`），正規化 CSRF、CSP nonce、資源檔名雜湊，時間固定，連續擷取兩次相同。**驗證**：`bin/rails routes \| grep vertical_spread` 1 行，前綴 `/leaps/`；`spec/requests/leaps_vertical_spread_spec.rb` **21 examples, 0 failures**（案例 1–9，含 3b 無候選、CDP 離線不呼叫 fetcher、progress JSON）；反向驗證：外框之外多輸出一個元素 → 回歸 5 例中 4 例失敗（空白頁不輸出，正確）；vitest `leapsVerticalSpread.test.ts` 6 例通過（全部 45 例）；整體 `bundle exec rspec` **1178 examples, 0 failures**（P0 基準 1111 全部保留） |
| P4 | UI 元件 | 通過 | 2026-09-25。元件 `app/components/leaps_recommendations/vertical_spread_section.rb`、外框 `vertical_spread_frame.rb`、前端 `leapsVerticalSpread.ts` 已於 P3 完成（見 P3 列）；P4 補元件測試與版面核對。版面：第一列買入腳／賣出腳兩個選單；第二列結果卡依序為實付淨成本（附保守成交）、最大獲利、損益兩平、最大虧損、風險報酬比、價差寬度；最後固定提示；標題列右側報價時間（台北時間）；標題列沿用 PMCC 區塊的 `px-4 py-3 border-b border-gray-100 bg-gray-50` 與外框 `bg-white rounded-xl border border-gray-200 shadow-sm`。4 種狀態：載入中（進度條＋「已完成 n / N 個到期日」＋已經過秒數，由前端輪詢 `progress=1`）、結果、錯誤（紅字）、讀取失敗（紅字＋重試）；另有 CDP 離線（紅字＋重試）。**驗證**：`spec/components/leaps_recommendations/vertical_spread_section_spec.rb` **9 examples, 0 failures**（結果：2 個 select、買入腳皆 100.00、賣出腳皆 > max(K_L, 現價)、卡片順序、報價時間與提示、無盤後標籤；盤後標籤寫出哪一腳；載入中、錯誤、讀取失敗、CDP 離線皆不含「實付淨成本」）。元件先於測試完成，改以反向驗證確認測試有效：卡片順序倒過來 → 1 例失敗；拿掉重試按鈕 → 2 例失敗。實機截圖（P3 上線後，ORCL／100）：`tmp/p3/after_loading.png`（第 4 秒「讀取到期日清單（已經過 5 秒）」）、`tmp/p3/after_result.png`（53 秒完成，數值與 P2 一致）；改前 `tmp/p3/before_leaps_orcl_100.png` 無此區塊。整體 `bundle exec rspec` **1187 examples, 0 failures** |
| P5 | E2E 驗收 | 通過 | 2026-09-25。腳本 `e2e/leaps_vertical_spread.e2e.mjs`（專案原本沒有 E2E 目錄，新建 `e2e/`；以 Playwright `connectOverCDP` 連 9224，沿用使用者的真實登入）。證據存於 `e2e/evidence/2026-09-25/`。**exit code 0**（run 8，23:47:43–23:49:15）。**與規格字面順序的差異**：①第 9 步回歸移到最前面，因為第 2 步送出後 ORCL＋100 的 LEAPS 資料會新鮮 1 小時（`FRESH_WINDOW = 1.hour`），無法重現 P0 基準的狀態；回歸證據取自 run 7（23:43，條件正確）`run7_regression.json`：a／b／c 三種輸入，區塊數 6／9／9 與基準相同，差異 0；**遮蔽 selector：`#leaps-price-context` 的內部內容**（即時行情：現價、POI、52 週、當日區間，由背景 job 更新；外層屬性照常比對），run 8 以 `--skip-regression` 執行並在證據中標示 skipped。②第 3 步「2 秒內出現進度條」從送出後跳轉、頁面載入完成起算。③第 8 步直接開網址（表單送出時既有驗證會擋下不存在的履約價）。④第 0 步只能用 psql 刪除 chain 快取（270 列）；到期日清單存在伺服器記憶體（development `memory_store`），psql 刪不到，本輪清單命中快取（`expirations_list_cached: true`），chain 6 個到期日全部重抓（N = 6 = 實際寫入的到期日數）。**各步結果**：第 1 步無區塊。第 2 步表單輸入 ORCL、100 送出，2 秒後導向 `http://localhost:3003/leaps?symbol=ORCL&user_strike=100`。第 3 步進度條於載入後 322 ms 出現，總耗時 42 秒、N = 6，逐段進度「已完成 0 / 6 … 5 / 6」，無停滯（`STALL_TIMEOUT = 30` 讀自常數）；區塊在 PMCC 之前；買入腳皆 100.00；報價時間 2026-09-25 23:48（台北時間）。第 4 步預設 `2028-01-21-m`（候選排行第 1 名）、K_S 250 > 現價 138.38；DOM／psql 期望值：實付淨成本 4232.50／4232.50、最大獲利 10767.50／10767.50、損益兩平 142.33／142.33（買腳 bid 54.75 ask 55.70、賣腳 bid 12.75 ask 13.05，皆 mid，非盤後）。第 5 步改賣出腳 140：1870.00／1870.00、2130.00／2130.00、118.70／118.70。第 6 步換到 `2027-10-15-m`：賣出腳選單換成 30 檔、皆 > max(100, 現價)，預設 K_S 230：4035.00／4035.00、8965.00／8965.00、140.35／140.35。第 7 步重新整理 1.5 秒出結果、無抓取進度、報價時間與第 3 步相同（23:48）。第 8 步 ZZZZQ →「查無股票代號 ZZZZQ」；ORCL 101.37 →「ORCL 的 LEAPS 中查無履約價 101.37；最接近的履約價：100.00、105.00」。第 10 步禁用 grep：兩支 sidecar 皆 0。截圖：`step3_default.png`（預設）、`step5_changed_short.png`（修改後）、`step8_strike_not_found.png`、`p3_loading.png`（載入中）。頁面 JS 錯誤 0 |

## 共通規則

- 依序執行。**驗證沒有通過，禁止進入下一階段。**驗證失敗時修到通過為止，並在狀態表記錄失敗原因和修法。
- 本檔的 repo 版本是唯一的真實來源。修改一律用 patch，不整檔重寫。
- 不新增頂層路由，也不新增 sidebar 入口：本功能是 `/leaps` 頁面（`LeapsRecommendationsController#index`）裡的一個區塊，入口就是既有的 `/leaps` 頁面。
- 抓取 Barchart 只能用 Playwright／CDP 解析 DOM。**禁止呼叫 Barchart 內部 API 或任何 Barchart API**（沒有付費訂閱）。這包括攔截 XHR／fetch 回應後直接讀 JSON，以及在 Python 中用 requests／httpx 打 Barchart 的任何端點。
- 不新增 gem、憑證，也不新增資料表。P1 若判定必須新增，要先停下來回報。
  - **例外（2026-09-25 使用者裁示）**：本功能**不碰 bcvs**（程式碼、sidecar、快取資料皆不修改、不共用），改建垂直價差專用的快取表 `leaps_spread_quotes` 與專用 sidecar（自 bcvs 複製）。詳見附錄 A 決議 5。
- **既有行為不得改變**：`/leaps` 既有的所有區塊（候選排行、PMCC 等）和既有的輸入驗證，在加入本區塊前後的行為必須完全相同。驗收方式見 P0 第 12 步（建立基準）和 P3、P5 的回歸比對。
- **數值一律用 BigDecimal**：履約價比對、mid、淨成本、所有公式全程使用 BigDecimal，只在顯示時才四捨五入。禁止在計算路徑中出現 Float（`to_f`、浮點數字面值）。

## 功能定義

在 `/leaps` 頁面「PMCC 黃金法則組合」區塊**之前**，插入「LEAPS 垂直價差」區塊：

0. **顯示條件**
   - 使用者**同時**輸入標的（例如 ORCL）和價格（既有的履約價輸入欄，參數名稱以附錄 A 為準）時，才渲染本區塊。任何一項沒有輸入，DOM 中就不能出現本區塊（連空的外框都不要）。
   - 輸入的價格就是**買入腳的履約價 K_L**，固定不變，是整個區塊的基底。
   - LEAPS 到期日的範圍**不另外定義**：沿用既有 `/leaps` 篩選 LEAPS 到期日的邏輯（位置記錄在附錄 A）。
   - 履約價比對：輸入值和 chain 的履約價都轉成 BigDecimal、取 2 位小數後再比對（`100`、`100.0`、`100.00` 視為相同）。

1. **下拉選單（2 個）**
   - **買入腳**：列出所有「履約價等於 K_L」的 LEAPS 到期日，一個到期日一個選項。選項格式為 `2028-01-21 · 483 DTE｜100.00｜mid 53.50｜Δ 0.82`，依 DTE 由近到遠排序。只能在不同到期日之間切換，不能改履約價。
   - **賣出腳**：和買入腳同一個到期日，而且履約價 > K_L，**同時在查詢當下必須是價外（履約價 > 現價）**。也就是 `K_S > max(K_L, 現價)`。選項格式為 `210.00｜mid 11.20｜Δ 0.30`。
   - **報價規則**（每一檔依序判定）：
     1. bid 和 ask 都 > 0：使用 `mid = (bid + ask) / 2`，視為一般報價。
     2. 否則 last > 0：以 last 代替 mid，這一檔標記為「盤後參考價」。選項文字改成 `210.00｜last 11.20（盤後參考價）｜Δ 0.30`。
     3. 以上都不成立：以 `disabled` 顯示，並標註「無報價」。
   - 任何一個選單變動時，自動重新計算（不需要按鈕）。切換買入腳的到期日時，賣出腳重新套用預設值。
   - 選單變動時，如果所選到期日的快取已經超過 30 分鐘，就重新抓取該到期日（顯示進度條，只抓這一個到期日），抓完才計算。
2. **預設值**（使用者剛輸入標的和價格時）
   - 買入腳的到期日：「LEAPS Call 候選排行」中，履約價等於 K_L 的第 1 名的到期日；如果候選排行裡沒有這個履約價，就取含有 K_L、而且有有效報價的最遠到期日。
   - 賣出腳：在合格的賣出腳選項中，只取符合 `0 < D_mid < W` 的，再取 delta 最接近 0.30 的那一檔；如果 P0 第 11 步確認 DOM 上沒有 delta，就取履約價最接近 `現價 × 1.3` 的那一檔。
3. **輸出欄位（每口）**

| 欄位 | 公式 |
|---|---|
| 價差寬度 | `W = K_S − K_L` |
| 淨成本（mid） | `D_mid = mid_L − mid_S`，`mid` 依報價規則（盤後以 last 代替） |
| 淨成本（保守成交） | `D_nat = ask_L − bid_S`；任一腳使用盤後參考價時，不計算，顯示「—（盤後無買賣價）」 |
| **實付淨成本（每口）** | `D_mid × 100`；旁邊以小字顯示保守成交的 `D_nat × 100` |
| 最大虧損 | `D_mid × 100` |
| **最大獲利** | `(W − D_mid) × 100` |
| **損益兩平** | `K_L + D_mid` |
| 風險報酬比 | `(W − D_mid) / D_mid`，顯示為 `1 : x.xx` |

   - 全程用 BigDecimal 計算，只在顯示時四捨五入到小數 2 位（ROUND_HALF_UP），加 `$` 和千分位；風險報酬比取 2 位小數。
   - **無效組合**（`K_S ≤ K_L`、`K_S ≤ 現價`、`D_mid ≤ 0`，或 `D_mid ≥ W`）：不顯示數字，改顯示紅字提示，說明是哪一個條件不成立。
   - **盤後標示**：任一腳使用盤後參考價時，結果卡上方顯示黃色標籤「盤後參考價：以最後成交價計算，實際成交價可能不同」，並在使用 last 的那一腳旁標註。
4. **固定提示（一行）**：「需 Firstrade 選擇權 Level 3；請用價差單一次成交兩腳。最大獲利要到到期日才完整實現。」
5. **資料來源與載入（即時抓取）**
   - 使用者輸入標的和價格後，由 Python sidecar 即時讀取 Barchart 的 call chain：先取到期日清單，再取每個 LEAPS 到期日的全部履約價。使用垂直價差專用的 sidecar（`lib/barchart_scrapers/leaps_spread_expirations_scraper.py`、`leaps_spread_chain_scraper.py`，選擇器自 bcvs 複製），不呼叫、不修改 bcvs 的腳本。
   - **非同步載入**：`GET /leaps` 只渲染本區塊的外框（`id="leaps_vertical_spread"`、`data-behavior="leaps-vertical-spread"`、`data-src` 指向 `/leaps/vertical_spread?...`）。前端 behavior 以 fetch 取回片段替換外框內容；抓取和計算都在這個片段請求裡進行，不能讓 `/leaps` 本身等待 sidecar。（原規格為 Turbo Frame，依附錄 A 決議 2 改為既有 `data-behavior` 慣例。）
   - **同一標的只抓一次**：以 PostgreSQL advisory lock 對標的上鎖。同一個標的已經在抓取時（連點、多個分頁），後來的請求不啟動新的 sidecar，改為等待並共用同一次抓取的結果與進度。
   - **部分快取**：快取以 `(ticker, expiry)` 為單位判斷。只重新抓取已經過期或還沒有快取的到期日，仍在 30 分鐘內的到期日直接讀快取。進度條的 N 等於這次實際要抓的到期日數。
   - chain 必須包含**全部履約價**，不能只有 near-the-money 視窗。Barchart 頁面預設只列部分履約價時，要用 DOM 操作（例如切換 "Show All" 之類的控制項）展開後再解析。
   - 快取：以 `(ticker, expiry)` 為 key，存進 PostgreSQL，TTL 30 分鐘。30 分鐘內重複查詢時直接讀快取，不啟動 sidecar。
   - 進度條：快取未命中、sidecar 執行期間，區塊內顯示進度條和階段文字（例如「讀取到期日清單」→「讀取 2028-01-21 chain（2/3）」→「計算中」），完成後由結果取代。
   - **逾時採「停滯判定」，不設固定總時長**：sidecar 每完成一個階段（到期日清單、每一個到期日的 chain）就回報一次進度。只要進度有持續推進就一直等；距離上一次進度回報超過 `STALL_TIMEOUT` 秒時，才判定為逾時。
     - `STALL_TIMEOUT = max(30, ceil(P0 第 10 步實測「單一到期日最慢耗時」× 3))`。這個值集中寫在一個設定常數裡（位置記錄在附錄 A），後端 fetcher 和 E2E 都讀同一個常數，不能各自寫死。
     - 進度條顯示「已完成 n / N 個到期日」和已經過的秒數。N 是到期日清單抓到之後的實際數量。
   - 逾時或抓取失敗：進度條改成紅字「Barchart 讀取失敗：{原因}」，並附上「重試」按鈕，不顯示任何計算數字。逾時的原因文字要寫出停在哪個階段，例如「讀取 2028-01-21 chain 超過 45 秒沒有回應」。
   - 區塊標題列顯示「報價時間：YYYY-MM-DD HH:MM（台北時間）」，取自目前所選到期日那一筆快取的抓取時間。
6. **錯誤訊息**（都以紅字顯示在區塊內，而且不顯示任何計算數字）

| 情況 | 訊息 |
|---|---|
| 標的代號在 Barchart 查不到 | `查無股票代號 {TICKER}` |
| 標的存在，但沒有任何 LEAPS 到期日 | `{TICKER} 沒有適合的 LEAPS 標的` |
| 任何 LEAPS 到期日都沒有這個履約價 | `{TICKER} 的 LEAPS 中查無履約價 {K_L}；最接近的履約價：{低}、{高}`（K_L 上下各 1 檔，只有一邊時只列一檔） |
| 有這個履約價，但所有到期日都沒有有效報價 | `履約價 {K_L} 在所有 LEAPS 到期日都沒有有效報價` |
| 沒有任何合格的賣出腳（價外、有報價、`0 < D_mid < W`） | `{expiry} 沒有符合條件的價外賣出腳` |
| 抓取失敗或逾時 | 依功能定義 5 |

   - 標的代號一律先 `strip.upcase` 再使用（`orcl ` 等同 `ORCL`）。
   - 「查無代號」和「沒有 LEAPS」的判定依據是 DOM 上的實際內容（例如 Barchart 的查無頁面或空的到期日清單），判定所用的 selector 記錄在附錄 A。

## P0 探勘與定位（不寫程式碼）

步驟（每一項都要把指令輸出摘要寫進附錄 A）：
1. `git ls-files | grep -E 'pmcc-golden-rule-spec-v3.md|leaps-call-spread-spec.md'`：把本檔移到和 `pmcc-golden-rule-spec-v3.md` 同一個目錄，然後 commit。
2. 找出 `/leaps` 的 view 或頁面元件中，渲染 `app/components/leaps_recommendations/pmcc_section.rb` 的位置（檔案路徑和行號）。
3. 找出「LEAPS Call 候選排行」使用的 model、service、欄位名稱（到期日、履約價、bid、ask、delta、現價），以及排序第 1 名的取法。
4. 找出 `/leaps` 的標的參數名稱（例如 `ticker`／`symbol`）和價格輸入欄的參數名稱（例如 `user_strike`），以及這兩個參數在 controller 中的驗證邏輯（檔案:行號）。同時找出既有 `/leaps` 篩選 LEAPS 到期日的邏輯（檔案:行號，以及實際條件，例如 DTE 門檻）。
5. 找出前端互動的慣例（Stimulus controller 目錄、是否使用 Turbo Frame），並列出一個既有的範例檔路徑。
6. 找出 E2E 測試登入的既有做法（Google OAuth 加 TOTP 的測試 helper 或 bypass），列出檔案路徑。
7. 找出 bpus／bcvs 的以下實作，記錄檔案路徑和行號：
   - sidecar 讀取 chain 的腳本（bpus 讀 put、bcvs 讀 call），以及 Rails 端呼叫它的 service。
   - 30 分鐘 psql 快取：資料表名稱、key 欄位、TTL 判斷的位置。
   - 進度條：前端元件，以及後端回報進度的機制（輪詢、Turbo Stream 或其他）。
8. 判斷 bcvs 的 call chain 快取表能不能直接共用：key 是否包含 ticker 和 expiry、是否存有 bid、ask、last、delta，以及是否存全部履約價。把結論寫進附錄 A。
9. 用 bcvs 既有的 sidecar 手動抓一次 ORCL 最遠的 LEAPS 到期日，記錄抓到的最高履約價、現價，以及比值 `max_strike / spot`。
10. 耗時實測：用 bcvs 既有的 sidecar，對 ORCL 所有 LEAPS 到期日各抓一次，共跑 3 輪。記錄每一個階段的耗時（到期日清單、每一個到期日的 chain），取「單一到期日最慢耗時」，依「功能定義 5」的公式算出 `STALL_TIMEOUT`。
11. delta 欄位：確認 Barchart 期權鏈頁面的 DOM 上是否有 delta（記錄頁面 URL 和 selector）。如果只在另一個分頁或頁面才有，記錄取得方式（同樣只能讀 DOM）。完全取不到時，在附錄 A 註明「無 delta」，P2 改以 `現價 × 1.3` 規則為主。
12. 回歸基準：在**還沒有改任何程式碼**之前，用 Playwright 對以下 3 種輸入各開一次 `/leaps`，把既有各區塊的 `outerHTML` 存成檔案（路徑記錄在附錄 A）：(a) 不輸入任何東西；(b) 只輸入 ORCL；(c) 輸入 ORCL 和 100。同時記錄既有 spec 的執行結果：`bundle exec rspec` 的 examples 數和 failures 數。
13. 查無代號與沒有 LEAPS 的 DOM 判定：用 sidecar 各試一次不存在的代號（例如 `ZZZZQ`），以及一個沒有 LEAPS 的標的，記錄 Barchart 顯示的內容和判定用的 selector。

**驗證**（全部符合才算通過）
- `grep -c 'TBD' leaps-call-spread-spec.md` 在附錄 A 範圍內為 0。
- 附錄 A 的每一個路徑都要通過 `test -f <path>`（逐一執行，全部回傳 0）。
- 第 9 步的比值和第 8 步的共用結論都已經記錄。
- 第 10 步 3 輪的各階段耗時原始數據，以及算出的 `STALL_TIMEOUT`，都已經記錄在附錄 A。
- 第 11、13 步的結論和 selector 都已經記錄；第 12 步的基準檔案都存在（`test -f`），而且在這一步之前 `git diff --stat` 沒有任何 `app/` 或 `lib/` 的變更。
- **API 禁用檢查**（以下稱「禁用 grep」）：
  `grep -rnE "barchart\.com/proxies|/api/|requests\.(get|post)|httpx|urllib|page\.on\(['\"]response|page\.route\(|context\.route\(|\.json\(\)|expect_response|wait_for_response" <第 7 步的 sidecar 路徑>` 的結果為 0 行。有任何命中，要先停下來回報，不能進入 P1。sidecar 只能用 `locator`／`query_selector` 系列讀 DOM。

## P1 即時抓取與快取

（2026-09-25 依附錄 A 決議 5 改版：不碰 bcvs。）

- 新增 `app/services/leaps_call_chain_fetcher.rb`：輸入 `ticker`，回傳每個 LEAPS 到期日的全部 call（履約價、bid、ask、last、delta、抓取時間）。last 同樣只能從 DOM 讀取。
  - 流程：先查快取，30 分鐘內有資料就直接回傳；否則呼叫垂直價差專用的 sidecar，寫入快取後再回傳。
  - 快取：新增資料表 `leaps_spread_quotes`（每檔履約價一列，strike／bid／ask／last／delta／underlying_price 為 decimal 欄位，唯一鍵 `(symbol, expiration, strike)`，`scraped_at` 判斷 30 分鐘），由 `app/services/leaps_spread_cache.rb` 讀寫；bid、ask 皆為 0 的列也要存。到期日清單存 `Rails.cache`（以 `scraped_at` 判斷 30 分鐘，TTL 1 天，供選單切換時沿用）。**注意**：目前 pm2 的 `fairprice-rails` 以 `RAILS_ENV=development` 執行，開發環境的 `cache_store` 是 `:memory_store`（存在伺服器程序記憶體），所以清單快取與抓取進度**重啟後會消失**，重啟後第一次查詢會多抓一次到期日清單（約 10 秒）；進度輪詢能運作的前提是只有單一 Rails 程序（2026-09-25 P5 前確認）。
  - sidecar：`lib/barchart_scrapers/leaps_spread_expirations_scraper.py`（自 bcvs 複製，另加查無代號／沒有選擇權判定，不抓 volatility 摘要）、`lib/barchart_scrapers/leaps_spread_chain_scraper.py`（自 `bcvs_call_chain_scraper.py` 逐字複製，只改說明）。Barchart 改版時兩邊都要檢查。
  - 同一標的互斥：`app/services/leaps_spread_fetch_lock.rb`（advisory lock），只在垂直價差內部使用。
- P0 第 9 步的比值 < 1.5 時，修改垂直價差 sidecar 的 DOM 操作，讓它展開全部履約價（P0 實測最低 1.65，不需修改）。
- 進度回報寫入 `Rails.cache`（`LeapsCallChainFetcher.progress`），階段文字依照「功能定義 5」。

新增 `spec/services/leaps_call_chain_fetcher_spec.rb`（sidecar 用 stub），至少包含：
1. 快取未命中：sidecar 被呼叫 1 次，並寫入快取。
2. 29 分鐘內再查：sidecar 被呼叫 0 次。
3. 31 分鐘後再查：sidecar 被呼叫 1 次。
4. 停滯逾時：stub 在第 2 個到期日之後，超過 `STALL_TIMEOUT` 都沒有回報進度 → 回傳 error，原因含有停住的階段名稱，而且不寫入快取。
5. 慢但有進度：stub 的總耗時超過 `STALL_TIMEOUT × 3`，但每個階段的間隔都 < `STALL_TIMEOUT` → 成功回傳，不能判定為逾時。
6. 測試中的 `STALL_TIMEOUT` 讀自設定常數，不能寫死數字（`grep` 測試檔案，不能出現 P0 算出的那個數值）。
7. 部分快取：3 個到期日中，1 個已經過期、2 個還在 30 分鐘內 → sidecar 只被要求抓那 1 個到期日，進度的 N = 1。
8. 同一標的同時查詢：兩個執行緒同時查 ORCL → sidecar 只被呼叫 1 次，兩邊拿到相同的結果。
9. 查無代號、沒有 LEAPS：stub 回傳對應的 DOM 判定結果 → 回傳功能定義 6 的對應 error。
10. 代號正規化：輸入 ` orcl ` → 查詢和快取 key 都使用 `ORCL`。
11. 選單變動遇到過期快取：所選到期日的快取是 31 分鐘前 → sidecar 被要求只抓這 1 個到期日；其他到期日不重抓。

**驗證**
- `bundle exec rspec spec/services/leaps_call_chain_fetcher_spec.rb` 的結果為 0 failures。
- 實際抓一次 ORCL（不用 stub），每個 LEAPS 到期日的 `max_strike / spot` 都 ≥ 1.5。把數值記錄進狀態表。
- 重跑「禁用 grep」，結果仍為 0 行。
- bcvs 沒有回歸：`bundle exec rspec` 中 bcvs 相關的 spec 結果為 0 failures。

## P2 計算服務

新增 `app/services/leaps_vertical_spread_service.rb`：
- 輸入：`ticker`（必填）、`long_strike`（必填，也就是使用者輸入的價格）、`expiry`（可選，買入腳所選的到期日）、`short_strike`（可選）。
- `ticker` 或 `long_strike` 缺少任何一個時：不做查詢，直接回傳 `nil`。
- 輸出：`long_options`（履約價 = K_L 的各到期日）、`short_options`、`selected`（實際套用的 expiry 和 short_strike）、`quoted_at`，以及 `result`（上表所有欄位）或 `error`（功能定義 6 的訊息）。
- `expiry`、`short_strike` 缺漏時，套用「功能定義 2」的預設規則。**所有公式只能寫在這個 service 裡**，前端不做任何計算。
- chain 資料只能透過 `LeapsCallChainFetcher` 取得，不能直接讀快取表或呼叫 sidecar。unit spec 中以 stub 取代 fetcher。

新增 `spec/services/leaps_vertical_spread_service_spec.rb`，至少包含以下案例：

| 案例 | 輸入 | 期望 |
|---|---|---|
| 基本 | K_L = 110、mid_L = 55、K_S = 200、mid_S = 20 | 淨成本 3500.00、最大虧損 3500.00、最大獲利 5500.00、損益兩平 145.00、風險報酬比 1 : 1.57 |
| 保守成交 | ask_L = 56、bid_S = 19 | D_nat × 100 = 3700.00 |
| 賣腳 ≤ 買腳 | K_S = 110、K_L = 110 | error，且不含 result |
| 淨成本 ≥ 寬度 | W = 10、D_mid = 10 | error |
| 無報價 | bid = 0、ask = 0、last = 0 | 該選項 disabled，不能成為預設 |
| 盤後參考價 | 賣腳 bid = 0、ask = 0、last = 11.20；買腳有正常 bid/ask | 賣腳以 11.20 計算 D_mid；選項文字含「盤後參考價」；結果含盤後標籤；D_nat 為 nil，畫面顯示「—（盤後無買賣價）」 |
| 兩腳都正常 | bid、ask 都 > 0 | 不出現「盤後參考價」字樣 |
| 缺少價格 | 只給 ticker | 回傳 nil |
| 缺少標的 | 只給 long_strike | 回傳 nil |
| 只有標的和價格 | ticker、long_strike = 100 | long_options 的履約價全部 = 100.00；expiry 依「功能定義 2」的規則；賣腳的履約價 > max(100, 現價)，而且 delta 最接近 0.30 |
| 同履約價多個到期日 | 3 個到期日都有 100 | long_options 有 3 筆，依 DTE 由近到遠；切換 expiry 後 short_options 換成該到期日的 chain |
| 賣腳必須價外 | K_L = 100、現價 = 139.54，chain 有 120、130、140、150 | short_options 只有 140、150 |
| 找不到履約價 | long_strike = 101.37，chain 有 100、105 | error 為「ORCL 的 LEAPS 中查無履約價 101.37；最接近的履約價：100.00、105.00」 |
| 履約價格式 | long_strike = "100"、"100.0"、"100.00" | 3 者結果完全相同 |
| BigDecimal 精度 | mid_L = 10.125、mid_S = 3.335 | D_mid = 6.79（BigDecimal 6.790），顯示為 $679.00；計算途中沒有 Float |
| 沒有 delta | chain 的 delta 全為 nil | 賣腳預設取履約價最接近 `現價 × 1.3` 的那一檔 |
| 沒有合格的賣出腳 | 所有 K > max(K_L, 現價) 的選項都無報價 | error 為「{expiry} 沒有符合條件的價外賣出腳」 |

另外加一條靜態檢查：`grep -nE "to_f|Float\(" app/services/leaps_vertical_spread_service.rb app/services/leaps_call_chain_fetcher.rb` 的結果為 0 行。

**驗證**：`bundle exec rspec spec/services/leaps_vertical_spread_service_spec.rb` 的結果為 0 failures，且 examples 數 ≥ 17；靜態檢查為 0 行。

## P3 路由與 Controller

- 在既有的 leaps 路由下新增 `GET /leaps/vertical_spread`（collection route），由 `LeapsRecommendationsController#vertical_spread` 處理，回傳區塊內容的 HTML 片段（不含 layout），由前端 behavior 放進 `#leaps_vertical_spread` 外框。
- 新增 request spec：`spec/requests/leaps_vertical_spread_spec.rb`（這是強制交付項目，等級和 unit spec 相同）。

Request spec 至少包含：
1. **`GET /leaps` 不帶標的和價格**：body 不含 `leaps_vertical_spread`。
2. **`GET /leaps` 只帶標的**：body 不含 `leaps_vertical_spread`。
3. **`GET /leaps` 帶標的和價格 100（核心情境）**：body 含有 `id="leaps_vertical_spread"` 的外框，帶 `data-behavior="leaps-vertical-spread"` 與指向 `/leaps/vertical_spread` 的 `data-src`；這個外框出現的位置在 PMCC 區塊之前（比較字串 index）。這個請求中 fetcher 被呼叫 0 次（`/leaps` 不能等待 sidecar）。
4. **`GET /leaps/vertical_spread` 只帶標的和價格 100**：body 含有 `實付淨成本`、`最大獲利`、`損益兩平`、`報價時間`；買入腳選單的每個選項履約價都是 100.00；數值等於用 service 直接計算的結果。
4b. `GET /leaps/vertical_spread` 帶完整參數（含 expiry、short_strike）：body 的數值等於用 service 直接計算的結果。
5. `GET /leaps/vertical_spread` 缺少 ticker 或 long_strike：回傳 422。
6. 無效組合：回傳 200，且 body 含有紅字錯誤提示。
7. fetcher 回傳 error（例如 sidecar 逾時）：body 含有「Barchart 讀取失敗」和「重試」，而且不含 `實付淨成本`。
8. 功能定義 6 的每一種錯誤各一個案例：body 含有對應的訊息，而且不含 `實付淨成本`。
9. **既有行為回歸**：對 P0 第 12 步的 3 種輸入各發一次 `GET /leaps`，把既有各區塊的 HTML 和基準檔案比對，除了新增的 `leaps_vertical_spread` frame 之外必須完全相同。既有輸入驗證的錯誤訊息（例如不合法的價格）也要和基準相同。

以上案例都以 stub 取代 sidecar；request spec 不能真的連到 Barchart。

**驗證**
- `bin/rails routes | grep vertical_spread` 只有 1 行，而且路徑前綴是 `/leaps/`。
- `bundle exec rspec spec/requests/leaps_vertical_spread_spec.rb` 的結果為 0 failures。
- `bundle exec rspec` 整體：failures 為 0，而且 P0 第 12 步記錄的既有 examples 全部還在（數量只增不減）。

## P4 UI 元件

- 新增 `app/components/leaps_recommendations/vertical_spread_section.rb`（Phlex），在 P0 第 2 步找到的位置、`pmcc_section` 之前渲染。只在 service 回傳值不是 `nil` 時才渲染。
- 整個區塊包在 `div(id: "leaps_vertical_spread", data_behavior: "leaps-vertical-spread", data_src: ...)` 外框裡；新增 `app/frontend/behaviors/leapsVerticalSpread.ts`：載入時 fetch `data-src` 取得片段放進外框，select 的 `change` 事件以目前選值組成 GET 參數重新 fetch `/leaps/vertical_spread` 並替換內容（依附錄 A 決議 2，比照 `leapsLoading.ts` 的 behavior 慣例；不引入 Turbo／Stimulus）。
- 版面：第一列放 2 個下拉選單（買入腳、賣出腳）；第二列放結果卡，順序是實付淨成本、最大獲利、損益兩平、最大虧損、風險報酬比、價差寬度；最後放固定提示。標題列右側顯示報價時間。視覺沿用同一頁 PMCC 區塊的表格樣式 class（P0 記錄的實際 class 名稱列在附錄 A）。
- 4 種狀態都要有對應畫面：載入中（進度條，含「已完成 n / N 個到期日」和已經過的秒數）、結果、錯誤（功能定義 6）、讀取失敗（紅字加「重試」按鈕）。版面參考示意圖：https://claude.ai/artifact/EzpHKtiDsoMZ2cLz3rH8g6（以本 spec 的文字為準，示意圖的報價是假數據）。

**驗證**
- 新增 `spec/components/leaps_recommendations/vertical_spread_section_spec.rb`：
  - 結果狀態：render 之後含有 2 個 `select`；買入腳所有選項的履約價都等於 K_L；賣出腳所有選項的履約價都 > max(K_L, 現價)。
  - 載入中、錯誤、讀取失敗 3 種狀態各一個案例：含有對應的文字，而且不含 `實付淨成本`。
  - 執行結果 0 failures。
- `bundle exec rspec` 整體 0 failures（不能造成回歸）。

## P5 E2E 驗收（核心使用情境）

用 Playwright 腳本（放在 P0 記錄的既有 E2E 目錄，依既有做法登入）：
0. 前置：用 psql 刪除 ORCL 的所有快取資料，確保第 3 步一定是快取未命中。
1. 打開 `/leaps`，不輸入任何東西：斷言 DOM 中**沒有**「LEAPS 垂直價差」區塊。
2. 在頁面的輸入欄中輸入 ORCL 和價格 100，然後送出（依照使用者實際的操作方式，不直接拼 URL）。
3. 斷言：送出後 2 秒內，區塊內出現進度條。等待進度條消失，採停滯判定：每次輪詢讀取進度文字「n / N」，n 有增加就重新計時；n 超過 `STALL_TIMEOUT` 秒都沒有變化，才判定失敗。`STALL_TIMEOUT` 從設定常數讀取。狀態表中記錄這次的總耗時和 N。
   斷言：「LEAPS 垂直價差」區塊出現，而且位置在「PMCC 黃金法則組合」之前；買入腳選單的每個選項履約價都是 100.00；標題列有「報價時間」，而且和現在時間相差 ≤ 30 分鐘。
4. 讀取預設選到的到期日和賣出腳 K_S。斷言 K_S > 頁面顯示的現價。用 psql 查出這兩檔的 bid、ask、last，依報價規則和公式算出期望值，再和 DOM 上的實付淨成本、最大獲利、損益兩平比對，誤差要 ≤ $0.01。如果有任一腳是盤後參考價，斷言畫面上有盤後標籤，並在狀態表註明這次是盤後執行。
5. 把賣出腳改成另一檔，等 `#leaps_vertical_spread` 的內容更新後，重做第 4 步的比對。
6. 把買入腳切換到另一個到期日（買入腳選單有 2 個以上選項時才執行；只有 1 個時在狀態表記錄「ORCL 的 100 只有 1 個到期日」）：斷言賣出腳選單換成新到期日的選項，而且全部 > max(100, 現價)；重做第 4 步的比對。
7. 重新整理頁面，再查一次 ORCL 和 100：斷言沒有出現進度條，而且「報價時間」和第 3 步相同（命中快取）。
8. 錯誤情境：依序查詢 `ZZZZQ` 和 100、ORCL 和 101.37，斷言分別顯示功能定義 6 的「查無股票代號」和「查無履約價……最接近的履約價」訊息。
9. 既有行為回歸：對 P0 第 12 步的 3 種輸入各開一次 `/leaps`，擷取既有各區塊的 `outerHTML` 和基準比對，除了新增區塊之外必須相同。報價類的動態數字（例如即時價格、時間戳）如果本來就會變動，比對前可以遮蔽，但遮蔽的 selector 要列在狀態表中。
10. 「禁用 grep」重跑一次，結果為 0 行（取代以網路紀錄判斷的做法）。

**驗證**（全部要記錄進狀態表）
- 腳本 exit code 為 0。
- 狀態表中記錄：實際導向的 URL、DOM 讀到的值、psql 算出的期望值（兩組並列）、截圖路徑（預設情境與修改後情境各 1 張）。
- 沒有以上證據，就不能把 P5 或整份規格標記為「通過」。

## 附錄 A：P0 探勘結果（Claude Code 填寫）

| 項目 | 結果 |
|---|---|
| 規格目錄 | repo 根目錄（與 `pmcc-golden-rule-spec-v3.md` 同層，原本就在，免搬移）；commit `9844a6b` |
| pmcc_section 渲染位置（檔案:行號） | `app/components/leaps_recommendations/page_component.rb:49`（`render_pmcc_section`，位於 `if @candidates.any?` 區塊內 :45–50）；定義在 `app/components/leaps_recommendations/pmcc_section.rb:23` |
| 候選排行 model／service／欄位 | `LeapsRankingService`（`app/services/leaps_ranking_service.rb`）讀 `LeapsOptionChainSnapshot`（`db/schema.rb:169–193`）；欄位：`expiration_date`、`strike`、`bid`、`ask`、`delta`、`underlying_price`、`last_price`、`dte`、`open_interest`。controller 呼叫處 `app/controllers/leaps_recommendations_controller.rb:16` |
| 候選排行第 1 名的取法 | `leaps_ranking_service.rb:26`：`sort_by { [-open_interest, -dte] }` 的第一筆（OI 最大，同 OI 取 DTE 最遠） |
| 標的參數名稱、價格參數名稱、驗證邏輯位置 | `symbol`（`leaps_recommendations_controller.rb:6`：`upcase.strip.gsub(/[^A-Z0-9.\-]/, "")`）；`user_strike`（index `:12` 只取 `presence` 不驗證；analyze `:118–124` 驗證正數且最多兩位小數，`:128–135` 以 `StrikeChainSnapshot#valid_strike?` 驗證） |
| 前端慣例與範例檔 | **本專案沒有 Turbo 也沒有 Stimulus**（`package.json`、`Gemfile` 皆無 hotwired／turbo／stimulus；全 repo 無 `turbo_frame_tag`）。慣例是 `app/frontend/entrypoints/behaviors.ts:88` 掃描 `[data-behavior]` 動態載入模組；範例 `app/frontend/behaviors/leapsLoading.ts`（Phlex 端 `page_header.rb` 的 `render_loading_script` 掛 `data-behavior="leaps-loading"`） |
| PMCC 表格樣式 class | `pmcc_section.rb:106` table `w-full text-xs text-gray-700`；`:107` thead `bg-gray-50 text-gray-500 text-xs`；`:118` th `px-3 py-2 text-center font-medium whitespace-nowrap`；`:157` tr `border-t border-gray-100 hover:bg-purple-200`；`:160` td `px-3 py-2 text-center` |
| E2E 目錄與登入 helper | **沒有既有 E2E 目錄**（無 `spec/system`、無 playwright config）。request spec 用 `spec/support/auth_helpers.rb`（`sign_in_and_pass_totp!`：OmniAuth mock + 真的 TOTP challenge）。瀏覽器層驗證目前以 Playwright `connectOverCDP("http://localhost:9224")` 搭配 9224 profile 的真實登入進行 |
| bpus／bcvs sidecar 腳本與 Rails 呼叫端（檔案:行號） | bcvs：`lib/barchart_scrapers/bcvs_expirations_scraper.py`、`lib/barchart_scrapers/bcvs_call_chain_scraper.py`；Rails 端 `app/services/barchart_scraper_service.rb:313`（`fetch_bcvs_expirations`，`run_scraper` 於 `:325`）、`:358`（`fetch_bcvs_call_chain`，`run_scraper` 於 `:369`）。bpus：`bpus_expirations_scraper.py`、`bpus_put_chain_scraper.py`；Rails 端 `barchart_scraper_service.rb:189`、`:230` |
| 30 分鐘快取：資料表、key、TTL 判斷位置 | bcvs：`bcvs_chain_snapshots`（`db/schema.rb:17–26`，唯一索引 `(symbol, expiration)`，履約價存在 `strikes` jsonb）、`bcvs_expiration_snapshots`（`:28–41`，唯一 `symbol`）；TTL `app/models/bcvs_chain_snapshot.rb:4`（`FRESH_WINDOW = 30.minutes`）、`:9`（`scope :fresh`），判斷 `app/services/bcvs_cache_service.rb:44`。bpus 不用資料表，用 `Rails.cache`（`barchart_scraper_service.rb:236` key `bpus_put_chain_#{symbol}_#{expiration}`） |
| 進度條：前端元件與後端回報機制 | bcvs：controller 寫 `Rails.cache["bcvs_job_#{job_id}"] = {status: "pending"}` 後排 job（`app/controllers/bull_call_spreads_controller.rb:107–108`），job 結束時只寫最終狀態（`app/jobs/bcvs_fetch_chain_job.rb:14–18`），前端 `app/frontend/behaviors/bullCallSpreads.ts` 輪詢 `GET /bcvs/status`（`bull_call_spreads_controller.rb:113`）。**沒有逐階段進度** |
| bcvs 快取表能否共用（附理由） | **有條件，見待決事項 1、3**。可以的部分：key 含 ticker 與 expiry；`strikes` jsonb 含 `bid`、`ask`、`last`、`delta`（另有 iv、mid、dte、oi 等）；存全部履約價（AAPL 2026-09-18 共 104 檔，最低 50）；到期日清單含 LEAPS（AAPL 最遠 `2028-12-15-m`）。到期日字串帶後綴（`-m` 月選／`-w` 週選） |
| ORCL 最遠到期日、最高履約價、現價、比值（sidecar 實抓） | 2026-09-25 實抓（`bcvs_call_chain_scraper.py`，URL `https://www.barchart.com/stocks/quotes/ORCL/options?view=sbs&expiration={exp}&moneyness=100`）。LEAPS 到期日（DTE ≥ 364）共 6 個：`2027-10-15-m`、`2027-12-17-m`、`2028-01-21-m`、`2028-09-15-m`、`2028-12-15-m`、`2029-01-19-m`。**最遠 `2029-01-19-m`：最高履約價 230、現價 139.54、比值 1.65**。各到期日 max_strike／spot：2.65、3.65、3.37、2.65、1.72、1.65，全部 ≥ 1.5 → P1 不需修改 sidecar 展開邏輯。各到期日 delta 皆 100% 有值；當次無「bid、ask 皆 0」的列 |
| 各階段耗時（3 輪原始數據）、單一到期日最慢耗時、STALL_TIMEOUT、設定常數位置 | 原始數據（秒）：到期日清單 10.42／9.96／16.76；`2027-10-15-m` 6.1／6.3／7.0；`2027-12-17-m` 5.3／7.5／5.4；`2028-01-21-m` 6.8／4.6／5.2；`2028-09-15-m` **7.6**／4.7／5.6；`2028-12-15-m` 5.1／5.5／5.8；`2029-01-19-m` 6.5／6.5／5.3（第 1／2／3 輪）。完整 JSON 在 `tmp/p0/measure.json`（gitignore，量測腳本 `tmp/p0/measure.py`）。**單一到期日最慢 7.61 秒 → `STALL_TIMEOUT = max(30, ceil(7.61 × 3)) = max(30, 23) = 30` 秒**。設定常數規劃位置：`LeapsCallChainFetcher::STALL_TIMEOUT`（`app/services/leaps_call_chain_fetcher.rb`，P1 建立；P0 階段檔案尚不存在，不列入 `test -f` 檢查） |
| 既有 LEAPS 到期日篩選邏輯（檔案:行號、條件） | `app/services/leaps_ranking_service.rb:31`（`MIN_DTE = 364`）、`:41`（`where("dte >= ?", MIN_DTE)`）；候選另加 `delta >= 0.60`（`:42`）與外在價值非負（`:46`），但後兩者是候選條件，不是到期日篩選 |
| delta 的來源頁面 URL 與 selector（或「無 delta」） | 有 delta。頁面 `https://www.barchart.com/stocks/quotes/{SYMBOL}/options?view=sbs&expiration={exp}&moneyness=100`；selector `bc-data-grid`（頁面上有 3 個，需全掃再以 `optionType === 'Call'` 篩選），欄位讀 `_data[].raw.delta`（`lib/barchart_scrapers/bcvs_call_chain_scraper.py:43–66`）。讀的是頁面元件的資料，未攔截網路請求 |
| 回歸基準檔案路徑、既有 rspec examples／failures 數 | `spec/fixtures/leaps_vertical_spread/baseline/a_empty.html`（6 區塊）、`b_symbol_only.html`（9 區塊）、`c_symbol_strike.html`（9 區塊），內容為 `#leaps-export-root` 各子元素 `outerHTML`，以 `<!-- ===== block ===== -->` 分隔，2026-09-25 08:57 於 localhost 擷取。**注意**：擷取時 ORCL 資料已超過 30 分鐘，(b)(c) 不含候選排行與 PMCC 區塊。`bundle exec rspec`：**1111 examples, 0 failures**（commit `817febd`） |
| 查無代號／沒有 LEAPS 的 DOM 判定 selector | 2026-09-25 實測。既有 `bcvs_expirations_scraper.py` 對兩者**都回 `no_candidates`，無法區分**，P1 需在 sidecar 加判定。**查無代號**（`ZZZZQ`）：`https://www.barchart.com/stocks/quotes/ZZZZQ/options` 顯示 404 頁，`document.title === "Page not found"`，selector `.bc-error-404-page` 存在（文字「404 Error … Oops, something's wrong.」）。**沒有 LEAPS**（`BRK.A`，完全沒有上市選擇權）：頁面正常（h1「Berkshire Hathaway Cl A (BRK.A)」），無 `.bc-error-404-page`，到期日選項 0 個，`.error-page` 文字「There is no option data for this symbol and month, or the options for the selected month have already expired.」。有選擇權但沒有 DTE ≥ 364 到期日的標的，判定為「到期日清單中 DTE ≥ 364 者為 0」（由 Rails 端依清單計算，不需額外 selector）。探查腳本 `tmp/p0/probe.py`、`tmp/p0/probe2.py` |

### 待決事項（P0 停下回報，2026-09-25）

1. **bcvs 快取會剔除無買賣價的履約價**：`app/services/bcvs_cache_service.rb:83–89` 的 `filter_quotable` 在寫入前剔除 bid 與 ask 皆為 0／null 的列。規格報價規則第 2 條（bid、ask 皆無 → 以 last 計算、標「盤後參考價」）需要的正是這些列，共用快取就永遠拿不到。依規格「判定不能共用時先停下回報、不得新增資料表」。
2. **本專案沒有 Turbo／Stimulus**：規格 P3／P4 指定 `turbo_frame_tag`、`requestSubmit()`。引入 turbo-rails 違反「不新增 gem」，引入 `@hotwired/turbo` 則是新的前端依賴。既有慣例是 `data-behavior` + fetch HTML 片段。
3. **jsonb 數值讀進 Ruby 是 Float**：`strikes` 的 bid／ask／last 經 ActiveRecord 讀出為 Float，與「計算路徑禁止 Float」衝突。可行解法：讀取時以 SQL 取 `strikes::text` 再用 `JSON.parse(..., decimal_class: BigDecimal)`，不必改表。
4. **禁用 grep 命中 `cdp_helper.py`**：兩支 bcvs sidecar 本身 0 行；但它們 import 的 `lib/barchart_scrapers/cdp_helper.py` 有 5 行 `urllib`（:10、:18、:24、:25、:56），連的是本機 Chrome 控制端點 `127.0.0.1:9222/json*`，不是 Barchart。規格寫「有任何命中要先停下回報」。
5. （非衝突，備註）bcvs 沒有逐階段進度回報，規格的停滯判定需要新增進度回報（沿用 `Rails.cache`，不需資料表）。

### 決議（使用者 2026-09-25 裁示）

1. **（已被決議 5 取代，2026-09-25）** ~~改成讀取時才篩選~~：`bcvs_chain_snapshots` 改存全部履約價（含 bid、ask 皆為 0 者），`filter_quotable` 從寫入移到 bcvs 的讀取路徑，bcvs 畫面行為不變；垂直價差讀取時保留這些列以套用盤後參考價規則。不新增資料表。需補 bcvs 回歸測試。
2. **沿用 `data-behavior` 慣例**：不引入 Turbo／Stimulus。本規格中的 Turbo Frame 一律改為「Phlex 輸出外框 + `data-behavior`，TS 以 fetch 取回 `/leaps/vertical_spread` 的 HTML 片段替換外框內容」；`requestSubmit()` 改為 select `change` 事件觸發 fetch。
3. **（已被決議 5 取代，2026-09-25）** ~~jsonb 以 BigDecimal 解析~~：改用 `leaps_spread_quotes` 的 decimal 欄位，讀出即 BigDecimal；sidecar 輸出也以 `JSON.parse(..., decimal_class: BigDecimal)` 解析，全程不經過 Float。
4. **禁用 grep 排除 `cdp_helper.py`**：它是本機 CDP 控制層（`127.0.0.1:9222/json*`），所有爬蟲共用、不連 Barchart。禁用 grep 只檢查 sidecar 腳本本身（目前兩支 bcvs sidecar 皆 0 行）。`cdp_helper.py` 另做一項檢查：每一個 `urlopen(`／`Request(` 的目標都必須以 `{CDP_BASE}` 開頭（`git grep -n -E "urlopen\(|Request\(" -- lib/barchart_scrapers/cdp_helper.py` 逐行確認；2026-09-25 為 :18、:24、:25、:56 共 4 處，全部是 `{CDP_BASE}`）。檔內出現的 `barchart.com`（:31、:38、:161）是比對分頁網址與讓瀏覽器導覽，屬 DOM 操作，允許。改版後禁用 grep 的對象改為垂直價差專用的兩支 sidecar（`leaps_spread_expirations_scraper.py`、`leaps_spread_chain_scraper.py`）。
5. **不碰 bcvs，另建專用快取表與 sidecar**（使用者 2026-09-25 第二次裁示，取代決議 1、3）：
   - bcvs 的程式碼、sidecar、快取資料一律不修改、不共用。先前依決議 1 對 bcvs 做的修改（`BcvsCacheService` 篩選時點、`bcvs_expirations_scraper.py` 新狀態、bcvs 兩個 job 的標的鎖）全部還原至 `57cdff9`；P1 首版實抓時寫進 bcvs 表的 ORCL 資料（chain 7 筆、清單 1 筆，皆 2026-09-25 18:30 後建立）已刪除。
   - 快取：新表 `leaps_spread_quotes`（每檔履約價一列、decimal 欄位）；到期日清單存 `Rails.cache`（使用者選「一張表、每檔履約價一列」）。
   - sidecar：複製成垂直價差專用腳本（使用者選「複製成自己的腳本」）。
   - advisory lock 只在垂直價差內部互斥，不再與 bcvs job 共用；功能定義 5 已刪除「bcvs 同時在抓」。
   - `FetchLog::STATUSES` 保留 `symbol_not_found`、`no_options`（新腳本會回傳；`spec/models/fetch_log_spec.rb` 會掃描所有 sidecar 的狀態）。

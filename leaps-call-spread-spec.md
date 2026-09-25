# LEAPS 垂直價差區塊 規格（leaps-call-spread-spec.md）

## 執行狀態表

> Claude Code 每完成一個階段、驗證通過後，立即用 patch 更新本表。接續 session 只需讀本表和「進行中」階段的章節。
> 狀態值：`待辦` / `進行中` / `通過` / `跳過（附理由）`

| 階段 | 名稱 | 狀態 | 驗證證據（指令與輸出摘要、截圖路徑） |
|---|---|---|---|
| P0 | 探勘與定位 | 待辦 | |
| P1 | 即時抓取與快取 | 待辦 | |
| P2 | 計算服務 | 待辦 | |
| P3 | 路由與 Controller | 待辦 | |
| P4 | UI 元件 | 待辦 | |
| P5 | E2E 驗收 | 待辦 | |

## 共通規則

- 依序執行。**驗證沒有通過，禁止進入下一階段。**驗證失敗時修到通過為止，並在狀態表記錄失敗原因和修法。
- 本檔的 repo 版本是唯一的真實來源。修改一律用 patch，不整檔重寫。
- 不新增頂層路由，也不新增 sidebar 入口：本功能是 `/leaps` 頁面（`LeapsRecommendationsController#index`）裡的一個區塊，入口就是既有的 `/leaps` 頁面。
- 抓取 Barchart 只能用 Playwright／CDP 解析 DOM。**禁止呼叫 Barchart 內部 API 或任何 Barchart API**（沒有付費訂閱）。這包括攔截 XHR／fetch 回應後直接讀 JSON，以及在 Python 中用 requests／httpx 打 Barchart 的任何端點。
- 不新增 gem、憑證，也不新增資料表。P1 若判定必須新增，要先停下來回報。
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
   - 使用者輸入標的和價格後，由 Python sidecar 即時讀取 Barchart 的 call chain：先取到期日清單，再取每個 LEAPS 到期日的全部履約價。沿用 bpus／bcvs 的抓取架構，實際檔案路徑以附錄 A 為準。
   - **非同步載入**：`GET /leaps` 只渲染本區塊的外框，以及一個帶 `src` 的 Turbo Frame（指向 `/leaps/vertical_spread`）。抓取和計算都在這個 frame 的請求裡進行，不能讓 `/leaps` 本身等待 sidecar。
   - **同一標的只抓一次**：以 PostgreSQL advisory lock 對標的上鎖。同一個標的已經在抓取時（連點、多個分頁、bcvs 同時在抓），後來的請求不啟動新的 sidecar，改為等待並共用同一次抓取的結果與進度。
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

- 新增 `app/services/leaps_call_chain_fetcher.rb`：輸入 `ticker`，回傳每個 LEAPS 到期日的全部 call（履約價、bid、ask、last、delta、抓取時間）。last 同樣只能從 DOM 讀取；bcvs 快取表沒有 last 欄位時，依 P0 第 8 步的規則停下來回報。
  - 流程：先查快取，30 分鐘內有資料就直接回傳；否則呼叫 P0 第 7 步記錄的 bcvs sidecar，寫入快取後再回傳。
  - P0 第 8 步判定可以共用時，使用 bcvs 的快取表；判定不能共用時，先停下來回報，不能自行新增資料表。
- P0 第 9 步的比值 < 1.5 時，修改 sidecar 的 DOM 操作，讓它展開全部履約價。只准修改既有腳本，而且要維持 bcvs 原本的行為。
- 進度回報沿用 P0 第 7 步記錄的 bcvs 機制，階段文字依照「功能定義 5」。

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

- 在既有的 leaps 路由下新增 `GET /leaps/vertical_spread`（collection route），由 `LeapsRecommendationsController#vertical_spread` 處理，回傳 Turbo Frame `leaps_vertical_spread` 的片段。
- 新增 request spec：`spec/requests/leaps_vertical_spread_spec.rb`（這是強制交付項目，等級和 unit spec 相同）。

Request spec 至少包含：
1. **`GET /leaps` 不帶標的和價格**：body 不含 `leaps_vertical_spread`。
2. **`GET /leaps` 只帶標的**：body 不含 `leaps_vertical_spread`。
3. **`GET /leaps` 帶標的和價格 100（核心情境）**：body 含有 `id="leaps_vertical_spread"` 的 Turbo Frame，而且帶有指向 `/leaps/vertical_spread` 的 `src`；這個 frame 出現的位置在 PMCC 區塊之前（比較字串 index）。這個請求中 fetcher 被呼叫 0 次（`/leaps` 不能等待 sidecar）。
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
- 整個區塊包在 `turbo_frame_tag "leaps_vertical_spread", src: ...` 裡；表單以 GET 送到 `/leaps/vertical_spread`，select 變動時執行 `requestSubmit()`（依照 P0 第 5 步記錄的前端慣例實作）。
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
5. 把賣出腳改成另一檔，等 Turbo Frame 更新後，重做第 4 步的比對。
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
| 規格目錄 | TBD |
| pmcc_section 渲染位置（檔案:行號） | TBD |
| 候選排行 model／service／欄位 | TBD |
| 候選排行第 1 名的取法 | TBD |
| 標的參數名稱、價格參數名稱、驗證邏輯位置 | TBD |
| 前端慣例與範例檔 | TBD |
| PMCC 表格樣式 class | TBD |
| E2E 目錄與登入 helper | TBD |
| bpus／bcvs sidecar 腳本與 Rails 呼叫端（檔案:行號） | TBD |
| 30 分鐘快取：資料表、key、TTL 判斷位置 | TBD |
| 進度條：前端元件與後端回報機制 | TBD |
| bcvs 快取表能否共用（附理由） | TBD |
| ORCL 最遠到期日、最高履約價、現價、比值（sidecar 實抓） | TBD |
| 各階段耗時（3 輪原始數據）、單一到期日最慢耗時、STALL_TIMEOUT、設定常數位置 | TBD |
| 既有 LEAPS 到期日篩選邏輯（檔案:行號、條件） | TBD |
| delta 的來源頁面 URL 與 selector（或「無 delta」） | TBD |
| 回歸基準檔案路徑、既有 rspec examples／failures 數 | TBD |
| 查無代號／沒有 LEAPS 的 DOM 判定 selector | TBD |

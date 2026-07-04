# FairPrice 新功能規格：LEAPS 查詢 user_strike 合理性驗證（履約價鏈快照比對）

> 依主規格慣例：新 session 接手前先跑 CDP 三行預檢 + 確認 `mcp__playwright-chrome__*` 工具可用（見 `leaps-call-recommendation-spec.md` 第 0、0.2 節），工具不可用就停下回報，不繞路。

## 起因（2026-07-03 實際事故）

使用者查完 NOK（user_strike=7）後把 symbol 換成 KLAC，履約價欄位還留著 7。KLAC 現價一百多美元，strike 7 極度偏離，Barchart stacked 頁渲染不出格線 → 白等 30 秒輪詢 timeout → `partial_error`。錯誤訊息是準的（前次修復生效），但這種輸入根本不該走到爬蟲那一步。

## 核心設計原則（使用者定調，不要改成別的方案）

**驗證依據是「該 symbol 實際存在的履約價陣列」，不是現價比例區間之類的啟發式猜測。**

流程：先查股價現價 → 把該 symbol 的履約價讀入陣列 → user_strike 不在陣列覆蓋範圍內就立即排除。履約價陣列的來源是**資料庫儲存的歷史查詢記錄**（每次 Stage 1 抓取結果落地），**只有完全沒有歷史紀錄時才需要讀 Barchart**——而「讀 Barchart」就是這次查詢本身的 Stage 1，不是額外的抓取動作。

## 資料庫：履約價鏈快照

- 每個 symbol 儲存一份履約價鏈快照：`strikes` 陣列（Stage 1 Near-the-Money 實際抓到的所有 strike）、當時的現價 `spot_price`（**從 Stage 1 導航的 Barchart 頁面 DOM 直接擷取**——選擇權頁面本身就顯示標的現價，抓 strikes 時順手一併抓，零額外請求）、`scraped_at`。
- **每次 Stage 1 成功抓取後 upsert 更新**（同一 symbol 覆蓋舊快照）——這是既有抓取流程的副產品，零額外 Barchart 請求。
- **推導 vs 建新表的決策程序（2026-07-03 已完成，結論：建新表）**：

  查 schema 結果：`leaps_option_chain_snapshots` 欄位含 `symbol, strike, expiration_date, delta, underlying_price` 等，每筆 = 一個 expiration × strike 組合（Stage 2 候選結果）。`persist_leaps` 路徑：`return if rows.blank?` → delete_all + insert_all。

  四判準逐條回答：

  1. **Stage 1 全清單 vs 篩選後候選？** → 篩選後候選。Stage 1 near-the-money 取到 NOK 6.5/7.0/7.5，`_pick_candidates` 保留 2–3 個中心 strike，Stage 2 只爬選出的 strike，入表只有 7.0/8.0。用現有表推導 `[min, max]` 會把 6.5 誤判為 invalid_strike——false positive 直接出局。
  2. **`spot_price` 有沒有地方存？** → `underlying_price` 欄位存在（值 = 12.07），但是 per-row 欄位（每筆選擇權都帶），不是 per-symbol 快照。取 `first/last` 可拿到值但語意隱含假設，加 per-symbol 快照欄位仍需改 schema，兩案成本拉平。
  3. **中止路徑能不能落地？** → 不能。`persist_leaps` L269 `return if rows.blank?`，Stage 1 後中止時 rows 為空，快照寫不進去，驗收場景 C 直接失敗。快照寫入必須獨立於 rows persist，不受短路影響。
  4. **覆蓋語意？** → 現有表是整批 replace（delete_all + insert_all）語意；快照需要 per-symbol upsert 語意，語意不同，硬塞不乾淨。

  **結論：建新表 `strike_chain_snapshots`**（四判準中 1、3、4 直接排除推導方案，判準 2 也無法省略 schema 修改）。欄位：`symbol`（unique index）、`strikes` jsonb not null、`spot_price` decimal(10,4)、`scraped_at` datetime。

  **chain_snapshot 資料流設計（Python → Ruby）**：scraper JSON 輸出新增 `chain_snapshot: {strikes: [...], spot_price: ...}` 欄位，所有退出路徑（success / invalid_strike 中止 / partial）只要 Stage 1 成功抓到清單，都帶此欄位。Ruby 端 `persist_chain_snapshot` 獨立方法，只要 `result` 含 `chain_snapshot` 就寫入，與候選 rows persist 完全解耦，無條件呼叫不受 `rows.blank?` 短路影響。

  **spot_price DOM selector**：待 Playwright 實測後補入（本節與 `reference_barchart_technical_dom.md` 同步記錄）。
- 快照過舊不作廢：履約價鏈的間距與範圍變動緩慢，舊快照仍可用於排除「明顯不合理」的輸入（KLAC 配 strike 7 這種），而每次成功查詢都會刷新快照。不設「太舊就當沒有」的邏輯，避免不必要的 Barchart 依賴。

## 驗證流程

### Controller 入列前（權威判定）

1. 讀該 symbol 的履約價鏈快照（`strikes` 陣列 + `spot_price` 一次讀出）。**現價就用快照裡 Barchart 來源的 `spot_price`，不打 Finnhub、不打 yfinance、不新增任何外部報價依賴**——使用者是 Barchart 付費會員，Barchart 頁面資料就是本專案的價格權威來源。快照的 spot_price 可能是上次查詢時的值，用於排除明顯不合理輸入綽綽有餘（判定主依據本來就是 strikes 範圍，現價只是訊息顯示用）。
2. **有快照** → 檢查 `user_strike` 是否落在 `[min(strikes) − 容差, max(strikes) + 容差]`（容差 = 一個 strike 間距，容納快照後新增的邊緣 strike）：
   - 範圍外 → **不入列**，回新狀態 `invalid_strike`，訊息帶實據：「Strike {N} 不在 {SYMBOL} 的履約價範圍（實際範圍 ${min}–${max}，現價 ${P}），請重新輸入」。不是 `partial_error`，不共用任何既有錯誤文案。
   - 範圍內 → 照常入列。
3. **無快照**（該 symbol 第一次查）→ 照常入列，由下面的 Stage 1 後檢查兜底；本次 Stage 1 結果落地後，下次查詢就有快照可用。

### Scraper 內 Stage 1 後檢查（無快照時的兜底）

- Stage 1 抓完，`_pick_candidates` 拿到 `user_strike` 時，若 `user_strike` 落在 Stage 1 清單範圍外（同一套容差規則），**立即中止回報**，不導航 stacked 頁去撞 30 秒 timeout。
- 回報訊息同樣帶實據（Stage 1 實際範圍），狀態歸 `invalid_strike` 類別，不是 `partial`。
- Stage 1 導航到 Barchart 頁面時，**從頁面 DOM 一併擷取標的現價**，跟 strikes 一起寫入快照的 `spot_price`。
- **不論中止與否，Stage 1 抓到的 strikes 與現價都要落地成快照**——中止的這次查詢也要留下紀錄，下次同 symbol 的驗證就能在 controller 層毫秒擋下。

### 前端表單即時檢查（毫秒級，體驗層）

- 頁面渲染時嵌入該 symbol 的快照範圍（min/max）與現價；使用者點「查詢」時前端先比對，範圍外直接紅字擋下不送出，訊息與後端同一句。
- 無快照或嵌入失敗 → 前端不擋，放行給 controller。**驗證功能自身失效時，不能反過來讓正常查詢不能用**——三層任何一層拿不到資料都是放行，不是阻擋。

## 附帶 UX 修正（本次事故的直接成因）

- **切換 symbol 時清空 `user_strike` 欄位**（或欄位旁灰字提示「已切換標的，請確認履約價」）。實作擇一，選了哪個寫回本節。

## 路由與前端入口（主動聲明）

- 不新增頂層路由，全部掛在既有 `/leaps` 流程內。
- 不新增導覽列項目（無新頁面）。
- 若前端取快照/現價需要輕量端點，掛在既有 namespace 結構下，實際路徑補回本節。

## 交付與驗收

1. **Request spec（必交付，跟單元測試同級）**：覆蓋 controller 完整 HTTP 路徑——
   - 有快照 + `user_strike` 範圍外 → 回 `invalid_strike`，**斷言 job enqueue 次數為 0**
   - 有快照 + 範圍內 → 照常入列
   - 無快照 → 放行入列
2. Python 端單元測試：Stage 1 後檢查的中止路徑、訊息含實際範圍值、**中止時快照仍落地**。
3. 快照 upsert 的測試：Stage 1 成功後快照更新（strikes、spot_price、scraped_at 皆刷新），且 spot_price 的值來自 Barchart 頁面 DOM 擷取（測試斷言擷取路徑，不是來自其他報價服務）。
4. **端到端驗收（Playwright 截圖三件套，缺一不算完成）**：
   - 場景 A（事故重現）：先查一次 KLAC（建立快照），再輸入 KLAC + strike 7 → **兩秒內**看到 `invalid_strike` 訊息含實際範圍，截圖；Rails log 確認該次請求沒有 enqueue job。
   - 場景 B（核心基本情境，必跑）：合理 symbol **不帶 user_strike** 的最基本查詢 → 完整跑通出結果，截圖。
   - 場景 C：首查 symbol（無快照）+ 明顯不合理 strike → Stage 1 後快速中止並顯示範圍訊息（不是等 30 秒 timeout），且快照已落地（查 DB 佐證），截圖。
   - 場景 D：合理 symbol + 合理 user_strike → 照常出結果，截圖。
   - 每張截圖附實際導航 URL 與關鍵 DOM 值，不接受只有文字說「修好了」。
5. 驗收全過後更新 `leaps-call-recommendation-spec.md`（錯誤狀態表加 `invalid_strike`，註明不屬於 partial），本檔記錄 commit hash。

## 邊界規則（沿用主規格）

- 現價來源就是 Barchart 頁面 DOM（Stage 1 抓取時一併擷取），**不引入 Finnhub、yfinance 或其他外部報價服務作為本功能的依賴**。禁止呼叫 Barchart 內部 API——擷取現價一樣只准讀頁面實際渲染的 DOM，這跟 strikes 的抓取邊界是同一條規則。
- 所有瀏覽器驗收操作走 `mcp__playwright-chrome__*`，禁止 raw WebSocket CDP。
- 實作決策若偏離本規格，先更新本檔再動手。

## 驗收結果（2026-07-04）

### 實作 commit
- `14cb8ee` feat: user_strike 三層防護 — strike_chain_snapshots + 即時驗證
- `132b714` fix: run_scraper 補上 invalid_strike case + cdp_online? timeout 調至 5s

### 修正紀錄
**Root cause（`run_scraper` missing case）**: Python 正確回傳 `{status: "invalid_strike"}` 但 Ruby 的 `run_scraper` 沒有 `when "invalid_strike"` case，落入 `else → {status: "success"}`，導致 Stage 1 中止邏輯完全失效。修正：在 `run_scraper` 加上 `when "invalid_strike" then { status: "invalid_strike", data: data }`。

**`cdp_online?` timeout**: 從 2s 調至 5s，符合 WSL2 mirrored 模式實際延遲。

### 測試覆蓋
- 單元測試：`spec/models/strike_chain_snapshot_spec.rb`（9 examples）
- Request spec：`spec/requests/leaps_recommendations_spec.rb`（加入 3 contexts）
- Python 測試：`test_leaps_scraper.py TestInvalidStrike`（2 examples）
- 全套 RSpec：**332 examples, 0 failures**

### 端到端場景驗收

**場景 A**（Controller fast-path，snapshot 已存在）  
Symbol: KLAC，user_strike: 7，DB snapshot strikes=[195..225]，spot=$235.55  
URL: `http://localhost:3003/leaps?symbol=KLAC&job_status=invalid_strike&user_strike=7` (from analyze action)  
結果：Strike 7.0 不在 KLAC 的履約價範圍（$195.00–$225.00，現價 $235.55），請重新輸入  
Rails log：`StrikeChainSnapshot Load` only，**NO `Enqueued ScrapeLeapsJob`**，完成於 1489ms  
✅ Controller 快速路徑驗證通過

**場景 B**（基本查詢，無 user_strike）  
Symbol: NOK，user_strike: 無  
URL: `http://localhost:3003/leaps?symbol=NOK&job_status=success`  
結果：推薦分析頁面正常顯示（近天期 $12.00/2027-12-17 Delta 0.679，遠天期 $12.00/2028-01-21 Delta 0.683）  
✅ 基本查詢路徑未被 chain_snapshot 改動破壞

**場景 C**（首查 symbol + 明顯不合理 strike → Stage 1 abort + 快照落地）  
Symbol: MSFT（無 snapshot），user_strike: 1  
URL: `http://localhost:3003/leaps?symbol=MSFT&job_status=invalid_strike&user_strike=1`  
結果：Strike 1.0 不在 MSFT 的履約價範圍（實際範圍 $367.50–$415.00，現價 $390.49），請重新輸入  
完成時間：~3 秒（Stage 1 抓完立即中止，無 Stage 2）  
DB 驗證：`SELECT symbol, strikes, spot_price, scraped_at FROM strike_chain_snapshots WHERE symbol='MSFT'`  
→ strikes=[367.5..415.0]，spot_price=390.49，scraped_at=2026-07-04 07:36:38 UTC，option rows=0  
✅ Stage 1 post-check 攔截 + chain_snapshot 落地

**場景 D**（合理 symbol + 合理 user_strike → 完整出結果）  
Symbol: MSFT，user_strike: 390（在 [367.5..415.0] 範圍內）  
URL: `http://localhost:3003/leaps?symbol=MSFT&job_status=success&user_strike=390`  
結果：推薦分析頁面正常顯示（近天期 $390.00/2027-09-17 Delta 0.611，遠天期 $390.00/2028-01-21 Delta 0.624）  
✅ 有效 user_strike 正常完整查詢

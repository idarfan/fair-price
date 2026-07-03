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
- **推導 vs 建新表的決策程序（第一步就做，回報確認後才開工）**：先查既有 schema（貼出表名、關鍵欄位、現有 persist 路徑的程式碼位置），然後逐條回答以下四個判準，據此選擇並把選擇與理由寫回本節：

  1. **現有表存的是 Stage 1 全清單，還是 Delta 0.60–0.90 篩選後的候選？** 若是篩選後的結果，推導出的範圍會偏窄——正常存在、只是 Delta 不在區間內的履約價會被誤判成 `invalid_strike`，驗證功能自己製造 false positive。此情況推導方案直接出局；若要補存 Stage 1 原始清單，那就等於建新表。
  2. **`spot_price` 目前有沒有任何地方存？** 快照必須含 Barchart 頁面擷取的現價。現有表若無此欄位，推導方案一樣要動 schema 加欄位，「不建新表比較省事」的優勢消失，兩案成本拉平時選語意乾淨的新表。
  3. **中止路徑能不能落地？** 本規格要求 Stage 1 後檢查中止時快照**仍要**落地，但已知 `persist_leaps` 在 `rows.blank?` 時直接 return（主規格第 255 行）——中止情境下候選 rows 很可能是空的，快照卻必須照寫。推導方案若綁在現有 persist 流程上，中止時寫不進去，驗收場景 C 的 DB 佐證直接過不了。快照的寫入路徑必須獨立於候選 rows 的 persist，不受 `rows.blank?` 短路影響。
  4. **覆蓋語意合不合？** 快照是「每 symbol 一份、upsert 覆蓋」；現有 rows 表若是 append 或整批 replace 語意，硬塞會讓「該 symbol 最近一次的 strikes」查詢依賴隱含假設（例如靠 scraped_at 取最新批次），語意不乾淨就別省這張表。

  預判：判準 2、3 大概率會把答案推向新表（例如 `strike_chain_snapshots`：`symbol`（unique index）、`strikes` jsonb、`spot_price` decimal、`scraped_at`），但以實際查到的 schema 為準。**回報格式：schema 實況 + 四判準逐條回答 + 選擇與理由，經使用者確認後才開工。**
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

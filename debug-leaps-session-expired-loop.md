# 診斷：LEAPS 查詢反覆出現「Session 在抓取 Strike 7.0 的 Options Prices 時過期」

## 現象（2026-07-03，使用者截圖）

- URL：`http://localhost:3003/leaps?symbol=NOK&job_status=partial_error&user_strike=7`
- 黃色 banner：「Session 在抓取 Strike 7.0 的 Options Prices 時過期，已抓到的部分資料可能不完整，請重新登入 Barchart 後點查詢重試」
- 同一畫面按鈕顯示「查詢中...」+「抓取資料中，請稍候...（約 3–5 分鐘）」
- **反覆出現，每次都斷在同一個位置（Strike 7.0 的 Options Prices 層）**

## 關鍵事實（診斷前提，不要再質疑這兩點）

1. **使用者是 Barchart 付費帳戶**——沒有免費帳號的頁面瀏覽配額問題，也不存在「動不動就要重新登入」的正常情境。配額牆假設不成立，不要往這個方向查。
2. **每次都斷在同一個位置（Strike 7.0 的 Options Prices）**——隨機的 session 過期不會每次精準斷在同一頁。這是**確定性的失敗**。

兩者合起來，結論幾乎只剩一個方向：**「session 過期」這個錯誤分類本身就是誤判**。真正的失敗原因另有其事，只是被 scraper 的偵測邏輯錯誤地歸類成 session 過期，然後前端忠實地顯示了一句誤導使用者的「請重新登入」。

假設排序：

- **H1（主要懷疑）：偵測條件把「其他失敗」誤分類成 session 過期**。最典型的寫法問題：「預期的資料表格/元素沒找到 → 判定 session 過期」。`user_strike=7` 這條路徑導航到的頁面（單一 strike 的 stacked/篩選 view）DOM 結構可能跟一般 Options Prices 頁不同、或載入更慢、或有彈窗遮擋，導致偵測條件每次都在這一頁誤觸發。
- **H2：CDP 連的 Chrome 實例/profile 跟使用者登入的不是同一個**——但如果 Options Flow CSV 抓取等其他功能在同一條鏈路上一直正常，此假設機率低，用第一步的截圖一次排除即可。
- **H3：Barchart 對這個特定頁面/參數組合回應異常**（例如該 URL 參數組合觸發轉址回登入頁）——跟 H1 相鄰，第一步導航就能看出來。

另注意：`user_strike=7` 是**選填覆寫參數的路徑**。之前結案驗收是否真的端到端跑過「帶 user_strike + Options Prices 中途斷線」這個組合，要一併回答。

## 前置（不做完不准開始診斷）

1. CDP 三行預檢（spec 第0.2節）：
   ```bash
   curl -s http://localhost:9222/json/version | head -3
   pm2 status cdp-relay
   ls /mnt/c/ 2>&1 | head -3
   ```
2. 實際呼叫一次 `mcp__playwright-chrome__browser_navigate` 確認工具活著。工具不可用 → 停下回報，不繞路。

## 第一步：用 Playwright 親眼看 Barchart 現在長什麼樣（判斷 H1/H2/H3）

1. 從 scraper 程式碼（`lib/barchart_scrapers/leaps_scraper.py`）找出「Strike 7 的 Options Prices」實際導航的完整 URL，**把該段程式碼貼出來**。
2. 用 `mcp__playwright-chrome__browser_navigate` 導航到**同一個 URL**（用 scraper 實際用的那條 CDP 鏈路，不是另開瀏覽器）。
3. 等頁面載入完成後截圖，回答：
   - 頁面是正常資料頁？登入彈窗？還是「頁面瀏覽次數已達上限／升級」之類的配額牆？
   - 右上角登入狀態顯示什麼（已登入帳號名？還是 Log In 按鈕）？
4. **判斷分岔**：
   - 正常資料頁、右上角顯示已登入（付費帳戶）→ **H1 確認**：頁面根本沒問題，是偵測誤判。進第二步找出誤判的確切條件。
   - 登入彈窗／被轉址到登入頁 → 分辨 H2（這個 CDP Chrome 實例沒有登入 cookie，跟使用者平常用的不是同一個 profile）或 H3（特定參數組合觸發轉址）：檢查同一個 Chrome 實例導航到 Barchart 首頁時登入狀態是否正常。
   - 頁面載入極慢或有彈窗遮擋 → H1 的變體：偵測時機太早或 selector 被彈窗撞到。

## 第二步：把過期偵測邏輯攤開對照，找出誤分類的確切程式碼路徑

1. 把 scraper 裡**所有**會導致回傳 `session_expired`／`partial` + 過期訊息的程式碼路徑完整列出來（不只登入彈窗偵測那一段——包括「表格沒找到」「元素等待逾時」「rows 為空」等 fallback 分支，任何一條最後被歸類成 session 過期的都要列）。
2. 逐條回答：這條分支的觸發條件，跟「session 真的過期」之間是充分條件還是只是相關？「等不到表格」「抓到 0 列」都**不是** session 過期的證據，如果程式碼把這些當成 session 過期回報，這就是誤分類的來源。
3. 對照第一步截圖的實際 DOM：在這個正常已登入的頁面上，是哪一條分支被觸發了？特別檢查：
   - 是否有等待頁面載入完成（networkidle / 特定元素出現）才檢查，還是導航後立即檢查？
   - `user_strike` 路徑導航到的 view，表格的 selector 跟一般 Options Prices 頁是否相同？如果 DOM 結構不同，scraper 用舊 selector 等不到元素 → 逾時 → 被誤報成 session 過期，這就完整解釋「每次都斷在同一點」。
   - 偵測的 selector 是否會被 Barchart 的廣告彈窗、cookie 同意窗、promo 窗撞到？
4. 如果偵測在 Playwright 手動導航時不會觸發、但 scraper 跑就觸發 → 比對兩者差異（等待時間、導航方式、檢查時機）。

## 第三步：釐清「partial_error banner 跟查詢中同時出現」

1. 回答：畫面上的「查詢中...」是使用者手動點重試造成的，還是頁面載入時**自動**重新排了 job？
2. 檢查 `LeapsRecommendationsController#index`：當 `job_status=partial_error` 且 rows 未寫入（快取 miss）時，是否會自動重新 enqueue job？如果會，這就是死循環的成因——session/配額問題沒解決前，每次進頁面都白跑 3–5 分鐘再撞同一面牆。
3. 檢查前端 JS：帶 `job_status=partial_error` 載入頁面時，loading 狀態（按鈕 disabled + spinner）的觸發條件是什麼？把該段程式碼貼出來。
4. 如果確認是自動重排 → 修正方向：`partial_error`（尤其是 session/配額類）不應自動重試，應停在 banner 等使用者處理完再手動點查詢。

## 第四步：查 log 佐證

```bash
# Rails log：找這幾次 partial_error 的 job 排程與回傳
grep -n "partial_error\|leaps\|Strike 7" log/development.log | tail -40
```

- 確認最近 N 次查詢：每次都斷在 Strike 7.0 嗎？每次從開始到 partial_error 間隔多久（幾十秒 = 一開始就撞牆；幾分鐘 = 抓到一半才斷）？
- scraper 的 stderr/stdout（若有落地檔）貼出斷線當下的完整訊息。

## 驗收（不做完不算查完）

1. 明確回答是 H1/H2/H3 哪一個，附證據：
   - Playwright 實際導航的完整 URL
   - 截圖顯示的頁面實際狀態（正常頁／登入窗／轉址）與登入狀態
   - 被觸發的那條偵測分支的程式碼，以及它跟實際 DOM 的對照——要能指著程式碼說「就是這一行把 X 誤報成 session 過期」
   - 修正時錯誤訊息必須跟真實原因對應：如果根因是 selector 等不到元素，訊息就不能再叫使用者「重新登入 Barchart」（使用者是付費帳戶且已登入，這句話只會誤導）
2. 明確回答「查詢中 + partial_error 同框」是手動重試還是自動循環，附 controller/前端程式碼證據。
3. 明確回答：之前結案的驗收，有沒有端到端跑過「帶 user_strike 選填參數 + Options Prices 中途斷線」這個組合？沒有的話老實說沒有。
4. 先回報診斷結論，**經確認後才動手修**，修完的驗收另立標準。

## 邊界規則（沿用 spec）

- 所有瀏覽器互動一律 `mcp__playwright-chrome__*`，禁止 raw WebSocket CDP。
- 禁止呼叫 Barchart 內部 API、禁止任何形式的自動登入。偵測到未登入只回報，不補救。
- 診斷過程中每個結論都要附「實際看到的證據」，不接受「應該是」「推測是」而沒有對應截圖或程式碼。

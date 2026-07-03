# FairPrice 新功能規格：LEAPS 查詢 user_strike 合理性驗證（快速失敗）

> 依主規格慣例：新 session 接手前先跑 CDP 三行預檢 + 確認 `mcp__playwright-chrome__*` 工具可用（見 `leaps-call-recommendation-spec.md` 第 0、0.2 節），工具不可用就停下回報，不繞路。

## 起因（2026-07-03 實際事故）

使用者查完 NOK（user_strike=7）後把 symbol 換成 KLAC，**履約價欄位還留著 7**。KLAC 現價一百多美元，strike 7 極度偏離，Barchart 的 stacked 頁面渲染不出對應格線 → 白等 30 秒輪詢 timeout → `partial_error`「頁面 30 秒內未完成載入」。

錯誤訊息本身是準的（上一輪修復生效），但問題在更上游：**這種明顯不合理的輸入，應該在送出查詢的瞬間就被擋下，而不是排 job、開瀏覽器、等 30 秒之後才用 timeout 的形式告訴使用者**。

## 目標

`user_strike` 明顯偏離該 symbol 現價時，**毫秒到一兩秒內**回饋「請輸入合理履約價（建議區間 $A–$B）」，完全不進入爬蟲流程。

## 三層防線（由快到慢，各自獨立生效）

### 第 1 層：前端表單即時檢查（毫秒級）

- 頁面渲染時，把該 symbol 的**最近已知現價**（來源見「現價來源」一節）嵌入頁面（data attribute 或 JS 變數）。
- 使用者點「查詢」時，前端先檢查：`user_strike` 是否落在 `現價 × [下限%, 上限%]` 區間內（門檻見下方常數定義）。
- 超出區間 → **不送出**，在履約價欄位旁顯示紅字：「Strike {N} 偏離 {SYMBOL} 現價 ${P} 過遠，深度價內 Call 建議輸入 ${A}–${B} 之間」。
- 現價嵌不到（DB 沒有該 symbol 的快取價）→ 前端不擋，放行到第 2 層（**驗證功能自身失效時不能反過來讓正常查詢不能用**）。

### 第 2 層：Controller 入列前檢查（權威判定，~1 秒內）

- `LeapsRecommendationsController` 在 enqueue job **之前**做同一套區間檢查（前端檢查可被繞過，後端才是權威）。
- 現價來源：優先讀 FairPrice 既有的價格快取；快取太舊（門檻可設，例如 > 1 個交易日）或不存在時，走既有的快速報價管道補一次（不准為此新增對 Barchart 的抓取）。
- 超出區間 → 不入列，直接以新狀態 `invalid_strike` 回應，前端顯示同一句建議區間訊息。**不是 partial_error，不共用任何既有錯誤文案。**
- 快速報價也拿不到 → 放行照舊執行（同第 1 層原則），並在 log 記一筆「strike 驗證跳過：無現價可用」。

### 第 3 層：Scraper 內 Stage 1 後檢查（兜底）

- Stage 1（Near-the-Money）抓回的 strikes 清單本身就是「這個 symbol 當前合理履約價」的實據。`_pick_candidates` 拿到 `user_strike` 後，若 `user_strike` 偏離 Stage 1 清單的最近 strike 超過門檻（例如超過清單價距的 N 倍，常數可調），**立即中止並回報**，不要去導航 stacked 頁然後等 30 秒 timeout。
- 回報訊息帶實據：「Strike {N} 不在 {SYMBOL} 的近價履約價範圍（Stage 1 實際範圍 ${min}–${max}），請重新輸入」。
- 這層的狀態同樣是 `invalid_strike` 類別，不是 `partial`。

## 常數定義（集中一處，不要散在三層各寫一份）

- `STRIKE_LOWER_RATIO = 0.30`、`STRIKE_UPPER_RATIO = 1.30`（現價的 30%–130%，初始值，可調）。
- 建議區間顯示值 `$A–$B` 用同一組常數算，三層訊息一致。
- 定義位置：Ruby 端一處（controller 與前端嵌入共用），Python 端 Stage 1 門檻另一個常數（因為依據不同：一個是現價比例、一個是 Stage 1 實際清單）。

## 附帶 UX 修正（同一起事故的直接成因）

- **切換 symbol 時清空 `user_strike` 欄位**（或至少在欄位旁顯示灰字提示「已切換標的，請確認履約價」）。這次事故的直接成因就是換股後舊 strike 殘留。實作擇一即可，但要在本規格記錄選了哪個、為什麼。

## 路由與前端入口（主動聲明）

- 本功能**不新增路由**，全部掛在既有 `/leaps` 流程內（controller 檢查 + 既有頁面內的前端行為），不另開頂層路由。
- 不新增導覽列項目（無新頁面）。
- 若第 2 層需要輕量報價端點（前端即時取價用），必須掛在既有 namespace 下（例如既有 quotes/API 結構內），並在本節補上實際路徑。

## 交付與驗收

1. **Request spec（跟單元測試同等級的必交付）**：覆蓋 `LeapsRecommendationsController` 的完整 HTTP 路徑——
   - `user_strike` 超出區間 → 回 `invalid_strike`，job **沒有**入列（斷言 enqueue 次數為 0）
   - `user_strike` 合理 → 照常入列
   - 無現價可用 → 放行入列 + log 留痕
2. Python 端單元測試：Stage 1 後檢查的中止路徑 + 訊息內容含實際範圍值。
3. **端到端驗收（Playwright 截圖三件套，缺一不算完成）**：
   - 場景 A（本次事故重現）：KLAC + strike 7 → 送出後**兩秒內**看到 invalid_strike 訊息與建議區間，截圖；確認 Rails log 中該次請求**沒有** enqueue job。
   - 場景 B（核心基本情境，必跑）：合理 symbol **不帶 user_strike** 的最基本查詢 → 完整跑通出結果，截圖。
   - 場景 C：合理 symbol + 合理 user_strike → 照常出結果，截圖。
   - 每張截圖附實際導航 URL 與關鍵 DOM 值，不接受只有文字說「修好了」。
4. 驗收全過後更新 `leaps-call-recommendation-spec.md` 的相關章節（partial_error 訊息表加上 `invalid_strike` 不屬於 partial 的註記），並在本檔記錄 commit hash。

## 邊界規則（沿用主規格）

- 禁止為取現價而呼叫 Barchart 內部 API；報價一律走 FairPrice 既有管道（DB 快取 / yfinance sidecar）。
- 所有瀏覽器驗收操作走 `mcp__playwright-chrome__*`，禁止 raw WebSocket CDP。
- 實作決策若偏離本規格，先更新本檔再動手。

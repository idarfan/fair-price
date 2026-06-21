# FairPrice 新功能規格：技術面/基本面/Options Flow 三維度判斷儀表板

## 背景與核心目標

FairPrice 現有 IV Skew Tracker（PostgreSQL 表 `iv_rank_daily`、`skew_rank_daily`，
資料來自 yfinance，邏輯詳見 `iv-skew-dashboard` skill）。

這次要新增的功能：使用者輸入股票代號 → 自動從 Barchart 網頁抓取技術面、基本面資料，
連同現有 Options Flow / IV Skew 資料，以**三個獨立分數**呈現，並標記三者出現背離時的警示。

**核心原則：Options Flow 只是情緒指標，不代表方向一定正確（機構可能用期權做對沖，
與持股方向相反）。技術面、基本面、Options Flow 三者必須獨立判斷、並列顯示，
絕對不可合併成單一綜合分數**，否則會掩蓋掉「機構避險 vs 方向性押注」這種關鍵背離訊號。

---

## 登入機制（重要，請完整遵守，不可變動）

Barchart 用 **Google OAuth** 登入（流程：Login → Continue with Google → 選擇帳號），
登入永遠由使用者手動操作。腳本絕對不可：

- 自動填寫帳密
- 自動點擊「Continue with Google」或自動選擇帳戶
- 儲存、快取、或重放任何登入憑證
- 嘗試任何形式的自動登入、模擬登入、或繞過登入彈窗

腳本只負責「使用」使用者已登入的 Chrome CDP session：

1. 連線到 Chrome CDP（沿用 `playwright-automation` skill 既有流程）
2. 導航到目標頁面後，**立即檢查是否出現登入彈窗**
   （selector 需實際讀取 DOM 後確認，類似「Welcome to Barchart」的彈窗，
   不可假設 class 名稱）
3. 若偵測到登入彈窗 → 不嘗試任何補救，立即中止這次抓取，
   標記狀態為 `barchart_session_expired`，往上層回報給使用者：
   「Barchart 登入已過期，請手動登入後重試」
4. 若登入有效 → 正常抓取資料

**這是唯一允許的「未登入提醒」處理方式。不需要做到自動登入，使用者會自行手動登入。**

---

## 步驟 1：Technical Analysis 頁面 DOM 探查（先做這步，不要跳過）

1. 確認 Chrome CDP 已連線：`curl -s http://localhost:9222/json/version`
2. 導航到 MU 的 Technical Analysis 頁面：
   `https://www.barchart.com/stocks/quotes/MU/technical-analysis`
   （請先確認實際 URL 格式是否如此，不要假設，以瀏覽器實際導航結果為準）
3. 讀取 DOM，找出四個表格的 selector（已知欄位結構如下，供比對用，
   實際 class/id 仍須讀取確認）：

   **Moving Average 表格**
   欄位：Period, Moving Average, Price Change, Percent Change, Average Volume
   Period 列：5-Day, 20-Day, 50-Day, 100-Day, 200-Day, Year-to-Date

   **Stochastic 表格**
   欄位：Period, Raw Stochastic, Stochastic %K, Stochastic %D, Relative Strength
   Period 列：9-Day, 14-Day, 20-Day, 50-Day, 100-Day

   **Average True Range 表格**
   欄位：Period, Average True Range, Average True Range %, Average Daily Range, Average Daily Range %
   Period 列：同上（9/14/20/50/100-Day）

   **Directional Index 表格**
   欄位：Period, Directional Index (ADX), Positive Direction (+DI), Negative Direction (-DI), Historic Volatility
   Period 列：同上

4. 同時找出**登入彈窗**的 selector（用於判斷 session 是否有效，這是後續所有抓取邏輯的前置檢查）
5. 注意事項：
   - 頁面可能用 React/Vue 渲染，表格需等資料載入後才出現，用 `wait_for_selector`，不要用固定 `sleep`
   - 用精準查詢讀 DOM，不要 `innerHTML` 整頁倒出來
   - 數字欄位可能含 `+`/`-`/`%` 符號與千分位逗號，記錄下實際格式供後續清洗
6. 將確認後的 selector 與頁面結構寫入 memory：`reference_barchart_technical_dom.md`

**完成此步驟後，回報實際讀到的 DOM 結構與 selector，等待確認後才進入步驟 2。**

---

## 步驟 2：基本面頁面 DOM 探查

基本面資料的確切頁面與欄位尚未確認。請：

1. 導航到 MU 的 Overview 頁面（`https://www.barchart.com/stocks/quotes/MU/overview`，
   請先確認實際路徑，不要假設）
2. 列出頁面上看到的所有基本面相關數據區塊，可能包含但不限於：
   - EPS（含成長率/estimate）
   - 營收成長率
   - 下次財報日期（Next Earnings Date）
   - P/E、PEG
   - Analyst Rating / Consensus
   - 機構持股變化
3. **不要假設欄位有哪些，回報你實際在頁面上看到的內容跟對應 selector**，
   等使用者確認要抓哪些欄位後，才進入後續資料庫設計

**完成此步驟後，回報實際看到的頁面內容，等待確認後才進入步驟 3。**

---

## 步驟 3：資料庫設計

新增 PostgreSQL table（請先檢查現有 schema 命名慣例，欄位風格須與既有 table 一致）：

### `technical_analyses`
- wide format：一個 `symbol` + 日期一行，所有指標展平成欄位（**不要用 EAV 設計**）
- 欄位命名建議用週期當前綴，例如：`ma_5d`, `ma_20d`, `stoch_k_9d`, `stoch_d_9d`,
  `adx_14d`, `atr_pct_14d` 等（請規劃完整欄位清單，**先給使用者看過再建 migration**）
- Unique constraint：`(symbol, fetched_at::date)`

### `fundamentals`
- 欄位待步驟 2 確認後再設計

### `fetch_logs`（建議新增）
- 記錄每次抓取狀態：`success` / `barchart_session_expired` / `dom_structure_changed` 等
- 方便後續追蹤失敗原因，欄位至少包含：symbol, fetch_type, status, error_detail, fetched_at

**完成此步驟後，先列出完整欄位清單給使用者確認，再執行 migration。**

---

## 步驟 4：抓取與查詢流程

### `app/services/barchart_scraper_service.rb`
1. 輸入 symbol
2. 依序：檢查登入狀態 → 抓取 Technical Analysis → 抓取基本面
3. 任何一步偵測到登入彈窗，立即中止並回傳 `barchart_session_expired` 狀態
   （不重試、不嘗試任何登入相關操作）

### 非同步處理
1. Playwright 抓取需要數秒，**使用 ActiveJob 背景任務處理**
2. 前端用 Turbo Stream 或 polling 顯示「抓取中」狀態，完成後更新畫面

### 快取策略
- 每次查詢都即時抓最新資料，**不使用過舊的快取資料**
- 例外：同一 symbol 在短時間內（例如 5 分鐘內）已抓取過，可直接讀 DB 結果，
  避免對 Barchart 重複請求造成過高頻率

### 反爬蟲考量
- 若同一次操作需要抓取多個 symbol，每個 symbol 之間加入隨機間隔（例如 3-8 秒）

**完成此步驟後，跟使用者確認抓取邏輯運作正常，再進入步驟 5。**

---

## 步驟 5：Composite Signal 邏輯（核心，必須遵守「不合併分數」原則）

### `app/services/composite_signal_service.rb`

輸入 symbol，輸出**三個獨立分數**：

1. **technical_score**：根據以下綜合判斷（偏多/中性/偏空）
   - MA 排列方向（價格相對 20/50/200 MA 的位置）
   - ADX 強度（>25 視為有明確趨勢，<20 視為盤整）
   - +DI vs -DI 哪個較強（方向性）
   - Stochastic %K/%D、Relative Strength 是否超買（>80）超賣（<20）

2. **fundamental_score**：依步驟 2 實際拿到的欄位設計
   - 先以 EPS 趨勢、是否接近財報日（例如財報前 7 天內）為基礎判斷
   - 輸出：偏多/中性/偏空/觀察中（財報前可標記「觀察中」而非強行給方向）

3. **options_flow_score**：沿用現有 IV Skew Rank 邏輯
   - 讀取既有 `iv_rank_daily`、`skew_rank_daily` 表

4. **divergence_flag**：任意兩個分數方向相反時標記
   - 並產生對應的說明文字，例如：
     「財報前 7 天內，Options Flow 偏空但技術面偏多，可能為機構避險而非方向性押注」
     「Options Flow 與技術面同向，但基本面偏空，建議留意財報後股價反應」

**三個分數務必獨立輸出，絕不可合併成單一綜合分數或加權平均分數。**

**完成此步驟後，跟使用者確認判斷邏輯是否合理，再進入步驟 6。**

---

## 步驟 6：路由與前端

1. `config/routes.rb` 新增獨立資源路由（例如 `resources :technical_dashboards, only: [:index, :show]`，
   或更合適的 RESTful 設計）
2. 頁面用 **Phlex 元件**（沿用專案既有的 Phlex + Tailwind CDN 慣例，**不使用 ERB/Hotwire**）
3. 頁面結構：
   - Symbol 輸入框 → 送出後顯示「抓取中」狀態 → 完成後顯示結果
   - 三個獨立卡片並排：技術面 / 基本面 / Options Flow
   - 背離時用黃/橘色明顯警示，並附文字說明可能原因
   - 若抓取狀態為 `barchart_session_expired`，顯示明確提示文字：
     「Barchart 登入已過期，請手動登入後重試」（不要顯示成一般錯誤訊息，要讓使用者明確知道要做什麼）
4. 視覺風格可參考 `iv-skew-dashboard` skill 的深色卡片 + gauge 設計，
   保持整體介面一致性

---

## 排程

此功能**不需要每日自動排程**，採「使用者觸發查詢時才抓取」模式，
不要額外設計 cron / 定時任務。

---

## 執行方式（請務必分階段進行）

請按照以下順序執行，**每完成一階段就跟使用者確認，再進入下一階段，不要一次做完全部**：

- **階段 A**：步驟 1（Technical Analysis DOM 探查）→ 回報結果，等待確認
- **階段 B**：步驟 2（基本面 DOM 探查）→ 回報結果，等待確認
- **階段 C**：步驟 3 + 4（資料庫設計 + 抓取邏輯）→ 回報結果，等待確認
- **階段 D**：步驟 5 + 6（判斷邏輯 + 前端）→ 回報結果，等待確認

每一步都必須以**實際讀取到的 DOM 結構 / 實際查到的現有 schema** 為準，
不可假設或猜測欄位名稱、selector、或現有架構慣例。
若實際情況跟本文件描述不一致，請回報差異，等待使用者確認後再繼續。

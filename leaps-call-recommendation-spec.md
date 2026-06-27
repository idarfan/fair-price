# FairPrice 新功能規格：LEAPS Call 操作建議

## 背景與目標

在 FairPrice 新增一個功能：使用者輸入股票代號後，系統自動從 Barchart 抓取該標的的選擇權報價、Greeks/波動率、Options Flow 三組資料，依 Delta 鎖定深度價內（LEAPS Call 候選）範圍後，**直接輸出履約價 × 到期日的排行表格**（OI 高到低排序），不額外篩選成單一推薦，由使用者自己看表決定。

這個功能的定位是「**LEAPS 候選排行表**」，資料層邏輯對應到你過去手動幫 NOK／NVTS／AAPL／LIN 挑 LEAPS 履約價時做的事：比較多個到期日 × 多個履約價，用 Delta 鎖定深度價內範圍，再看 OI／Volume／Bid-Ask Spread 判斷流動性。這次把「抓資料、算 Delta 範圍、排序」自動化，但**不自動下結論挑單一答案**，最終判斷留給使用者自己看表格決定。

**用途範圍**：純方向性 LEAPS Call（取代持股／槓桿做多），不是 PMCC 完整建倉（PMCC 還需要再選 Short Call，那是下一個獨立功能，不在這份規格內）。

---

## 核心原則（不可違反，沿用專案既有規範）

1. **登入機制**：Barchart 用 Google OAuth 登入。系統**只負責偵測**目前 Chrome CDP session 是否已登入（導航後檢查是否出現登入彈窗），**絕對不嘗試任何形式的自動登入**（不填帳密、不點 "Continue with Google"、不處理 OAuth 流程）。偵測到未登入 → 立即中止，回報「請手動登入 Barchart 後重試」，不做任何補救嘗試。
2. **禁止呼叫內部 API**：所有資料一律透過 Playwright 讀取頁面實際渲染的 DOM，或使用頁面本身提供的合法「匯出/下載」功能（沿用 Options Flow CSV 下載的既有模式）。**禁止**用 XHR 攔截、攔截 session cookie、或直接呼叫 Barchart 內部 API 端點（例如 `/proxies/core-api/...`），即使技術上抓得到也不可以。
3. **三維度獨立原則延伸**：這個功能產出的「LEAPS 排行表」，**只能由 Delta 區間篩選 + OI/DTE 排序組成**，**不可把 Options Flow 情緒訊號混進排序或拿來篩選候選**。Options Flow 資料以獨立面板呈現（見第 7 節），作為「這個排行跟今天的市場情緒方向是否一致」的參考，由使用者自行判斷，不自動加減分、不自動排除候選。
4. **不假設 DOM／資料格式**：三個頁面目前都還沒有做過完整 DOM 探查，Claude Code **必須先完成 Phase A（第 4 節）拿到真實欄位**，才能進入後續資料庫設計與抓取邏輯，不可憑猜測或本文件的範例欄位名稱直接寫死 selector。
5. **分階段執行**：嚴格按照第 10 節的階段順序進行，每階段做完跟使用者確認後才能進下一階段。

---

## 使用者流程

```
使用者輸入股票代號（例如 NOK）
        ↓
系統檢查 Chrome CDP 連線 + Barchart 登入狀態
        ↓ 未登入                    ↓ 已登入
回報「請先登入 Barchart」      依序抓取三個頁面：
（不繼續往下）                  1. Options Prices（所有可用到期日的報價）
                                2. Volatility & Greeks（同上頁面的 Delta/IV）
                                3. Options Flow（今天的成交流量）
                                       ↓
                                存進 PostgreSQL
                                       ↓
                                跑 LEAPS 候選排行（第 6 節）
                                       ↓
                                畫面顯示：
                                ① 履約價 × 到期日排行表格（不分天期區間，
                                   不限制最低天數，依排序鍵列出全部候選）
                                ② 決策當天的 Options Flow 面板（獨立顯示）
```

---

## Phase A：三個頁面的 DOM 探查（先做這步，不要跳過、不要假設）

### A.1 Options Prices
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/options?expiration={DATE}`

需要實際確認：
- 到期日清單從哪裡讀（通常頁面上有 expiration 的 `<select>` 或 tab 清單，**用這個清單拿到全部可用到期日，不要自己猜日期格式**，要包含遠期 LEAPS 到期日，不是只有近期週選）
- 表格實際欄位有哪些（推測會有 Strike、Bid、Ask、Last、Volume、Open Interest，但要以實際讀到的 column header 為準）
- Call / Put 是左右並排兩個表格，還是分頁切換，需確認 DOM 結構
- 頁面是否也有合法的 CSV/Export 下載功能（如果有，優先用下載，不用解析 DOM 表格，沿用 Options Flow 的既有模式）

### A.2 Volatility & Greeks
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/volatility-greeks?expiration={DATE}`

需要實際確認：
- 表格欄位是否包含 Delta、Gamma、Theta、Vega、IV（推測會有，但要實際確認欄位名稱與單位，例如 IV 是百分比還是小數）
- 這個頁面的 Strike 清單跟 A.1 的 Strike 清單是否完全對得上（用來做 merge by strike+expiration 的 key）
- 是否也有合法匯出功能

### A.3 Options Flow
參考 URL：`https://www.barchart.com/stocks/quotes/{TICKER}/options-flow`

這個頁面之前已經驗證過合法 CSV 匯出可用，欄位已知為：
```
Symbol, Price~, Type, Strike, Expires, DTE, "Bid x Size", "Ask x Size",
Trade, Size, Side, Premium, Volume, "Open Int", IV, Delta, Code, *, Time
```
沿用既有 `csv_files/options_flow/{SYMBOL}_{YYYY-MM-DD}.csv` 下載與命名規則即可，**這頁不需要重新 DOM 探查**，除非既有抓取流程還沒接到這個新功能上，需確認既有 service/job 能不能直接複用（見第 9 節）。

> Phase A 做完，請把三個頁面實際拿到的欄位/selector/URL 規則回報給使用者確認，再進 Phase B。

---

## 資料庫設計（暫定，Phase A 確認欄位後可能要調整）

新增一張選擇權報價快照表（暫名 `option_chain_snapshots`），最低需要欄位：

| 欄位 | 說明 |
|---|---|
| `ticker` | 股票代號 |
| `expiration_date` | 到期日 |
| `dte` | 距到期天數（抓取當下計算） |
| `strike` | 履約價 |
| `option_type` | call / put（這個功能只需要 call，但表結構保留兩者以備未來 PMCC 功能共用） |
| `bid`, `ask`, `last` | 報價 |
| `volume`, `open_interest` | 流動性 |
| `delta`, `iv` | 來自 Volatility & Greeks 頁面，merge by (ticker, expiration_date, strike) |
| `underlying_price` | 抓取當下的標的股價（用於算 time value %） |
| `scraped_at` | 抓取時間 |

如果專案裡已經有類似的選擇權報價表（之前三維度儀表板規格裡有沒有做過這塊請先確認 `app/models` 與既有 migration），**優先擴充既有表，不要重複建表**。

Options Flow 資料如果之前的三維度儀表板專案已經有對應 model/table，直接複用；如果只做到 CSV 下載沒接資料庫，這次順便把既有 CSV 解析存進 DB（沿用既有的 Code 分類邏輯，不重新設計）。

---

## LEAPS 候選排行表

這部分是純計算，不依賴 DOM 探查結果，可以先寫好。

**這次不做「篩選後挑出最佳一組+寫理由」，改成直接輸出排行表格，所有候選都列出來，使用者自己看表決定到底要選哪一個**；但流動性夠不夠這件事，**由程式判斷並標示出來，不是甩給使用者自己瞪著 OI 數字猜**：

- **不預設遠天期的最低天數門檻**（不寫死 `min_dte`），所有到期日都進表格，DTE 本身就是表格的其中一個排序/顯示欄位，由使用者自己依天數判斷遠近，系統不幫忙劃線。
- **OI／Volume 顯示 Barchart 抓到的原始數值**，同時程式額外算出一欄「流動性判斷」（見下方），不是只丟原始數字讓使用者自己猜夠不夠。
- Delta 仍用區間篩選縮小候選範圍到「深度價內」（這是篩 LEAPS 候選的基本定義，不是流動性門檻），預設區間維持 0.75–0.90，可調。

### 流動性判斷邏輯（不用單一固定 OI 門檻）

**不要寫死一個全標的通用的 `min_open_interest` 數字**（不同股票的選擇權市場深度差非常大，NOK 跟 AAPL 的 OI 量級完全不在一個級別，固定一個數字會對某些標的太鬆、對另一些太嚴）。改用**同一次查詢結果內的相對排名**讓程式自動判斷：

1. 取出這次查詢、該標的、Delta 區間篩選後的所有候選（不分到期日，一起算）。
2. 計算這些候選的 OI 分布，依百分位排名分三級：
   - 該標的本次候選 OI 前 1/3 → `流動性：充足`
   - 中間 1/3 → `流動性：普通`
   - 後 1/3 → `流動性：偏低`
3. 額外規則：若候選的 `volume` 為 0 或極低（例如連續多日無成交，需依 Phase A 實際資料判斷怎麼偵測「近期無成交」），即使 OI 排名落在前 1/3，仍額外標註「⚠ 近期無成交」警示，因為 OI 高但近期沒人交易，代表是舊倉位掛著，不代表現在進出容易。

這個分級邏輯是**程式自動算好直接顯示在表格裡**，不是文字描述，使用者一眼就能在表格上看到每個候選的流動性等級，不用自己再去比較數字。

### 輸入參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `delta_min` / `delta_max` | 0.75 / 0.90 | 深度價內目標 Delta 區間（用來定義「這是不是 LEAPS Call 候選」，不是流動性篩選），可調 |
| 流動性分級門檻 | 動態（依本次查詢候選 OI 分布算百分位，見上） | 不寫死絕對數字，隨標的自動調整 |

### 計算與排序流程

1. 取出所有到期日（不限制 DTE 下限），每個到期日內篩出 `delta_min <= delta <= delta_max` 的履約價（deep ITM 區間）。
2. 對篩出的每一筆候選，帶出 Barchart 原始 OI、Volume 數值，並依上方流動性判斷邏輯計算出 `liquidity_tier`（充足／普通／偏低）與是否有「近期無成交」警示。
3. 計算 `time_value_pct`（供表格欄位顯示用，不是篩選條件）：
   ```
   intrinsic_value = max(0, underlying_price - strike)
   time_value = call_mid_price - intrinsic_value
   time_value_pct = time_value / underlying_price
   ```
4. 計算 `bid_ask_spread_pct = (ask - bid) / mid_price`（同樣是表格欄位，不是篩選條件）。
5. 排序：依 `open_interest` 由高到低排，OI 相同時依 `dte` 由大到小排（天數排行）。

### 表格輸出（取代原本的narrative推薦文字）

直接列出表格，欄位：

| 到期日 | DTE | 履約價 | Delta | OI | Volume | 流動性判斷 | Bid | Ask | Mid | Spread% | Time Value% | IV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

- 表格本身就是排行（OI 高到低，同 OI 依 DTE 大到小），不額外寫每一列的推薦理由段落，但「流動性判斷」欄是程式算好的結論，不是原始數字。
- 表格上方加一行固定提示：「依 OI 由高到低排序；流動性判斷依本次查詢候選的 OI 相對排名計算，非固定門檻，不同標的會自動調整基準。」
- 表格下方固定提示：「以上為 Delta 區間篩選後的排行結果，僅供策略篩選參考，非投資建議，請自行評估。」

---

## 決策當天的 Options Flow 顯示（獨立面板，不併入排序）

在排行表格下方，另開一個獨立區塊顯示**抓取當天**該股票的 Options Flow：

- 沿用既有 Code／Side／`*` 分類邏輯（多腿代碼標記不可信、標準單腿代碼可信）
- 顯示當天 Call 與 Put 的總 Premium 量、大單（依既有 Block/Sweep/Floor 等 Flags 或 Code 分類)清單
- 若當天的成交剛好落在排行表前幾名的到期日／履約價附近，特別標出來（純顯示提示，例如「今天在排行第一的 $X 履約價附近有一筆大額買權買入」），但**不自動把這個訊號加進排行排序**，標題上明確寫「情緒參考，非排序依據」

---

## 路由與前端

- 路由不要憑空另開一個孤立的頂層資源：先看 `config/routes.rb` 現有結構，三維度儀表板（`technical_dashboards` 或類似名稱，請依實際檔案確認）跟既有的 `iv_skew_dashboard`／options flow 相關路由放在哪個 namespace／哪個區塊下，這次新增的 `leaps_recommendations` 應該跟著放在同一層級／同一 namespace 下，維持路由結構一致，不要平行另開一塊。
- **要加進現有的導覽列/選單**：找到目前 Phlex layout 裡放導覽連結的位置（例如 header 或 sidebar 的 nav 元件），把這個新頁面的連結加進去，不能只新增 controller/route 卻沒有任何入口可以點進去，使用者不該需要自己手動輸入網址才能用到這個功能。
- Phlex 元件，沿用專案既有慣例（不用 ERB/Hotwire）
- 頁面流程：輸入股票代號 → 送出後顯示抓取中狀態（Playwright 抓取需要數秒，用 ActiveJob + Turbo Stream/polling）→ 完成後顯示：
  1. LEAPS 候選排行表格（第 6 節，OI 高到低排序，所有 Delta 0.75–0.90 區間內的候選都列出來，不分天期區間、不做篩選後只留少數）
  2. 當天 Options Flow 面板（獨立區塊）
- 表格可加履約價/到期日的欄位排序（點欄位標頭切換排序鍵），方便使用者自己依 DTE 或 OI 重新排

### 配色：直接沿用三維度儀表板（Technical/Fundamental/Options Flow）既有樣式，不要另外設計新色票

**這點很重要，請先讀檔再寫樣式，不要憑印象或重新設計一套配色：**

1. 先找出三維度儀表板（`composite_signal_service` 對應的前端，含 `divergence_flag` 色塊：`confirm_bull` 綠色確認區塊、`warning`／`caution` 橘黃警示色塊）目前的 Phlex/CSS 檔案在哪裡，把實際用到的顏色變數、class、或 inline 樣式值讀出來。
2. LEAPS 這個新頁面**直接複用同一組顏色變數/CSS class**（卡片底色、邊框、字體顏色、綠/橘黃/紅的語義色），不要重新定義一套新的色碼。
   - 流動性分級（充足／普通／偏低）沿用三維度儀表板既有的「偏多／中性／偏空」或「confirm／warning／caution」同一組顏色語義對應，充足對應偏多那組顏色，偏低對應警示那組顏色。
   - Options Flow 面板的看多/看空/中性判斷，同樣直接套用既有 `divergence_flag` 用的綠/橘黃/紅，不要另外發明新的顏色語義。
3. 如果三維度儀表板的樣式是寫在共用的 CSS（例如共用的 partial、stylesheet、或 Tailwind class 組合），這個新頁面應該直接 `import`／複用該檔案或共用 component，不要複製貼上一份新的，避免之後兩邊顏色又走偏。
4. 表格 hover 效果：列出滑鼠移過去時的底色，若三維度儀表板本身有定義 hover 樣式，直接沿用；若沒有，可採用偏紫色調的淡色 hover（與專案配色不衝突即可），這部分次要，以複用既有樣式為優先。
5. 視覺風格可參考既有 `iv-skew-dashboard` skill 的卡片設計（半圓 gauge 那部分不需要套用在這個表格型頁面，只取卡片/配色的概念）。

---

## 排程

不需要每日自動排程，使用者觸發查詢時才抓取最新資料。同一 symbol 短時間內（例如 5 分鐘內）已抓過可直接讀 DB，避免重複打 Barchart。

---

## 執行方式（請務必分階段進行，每階段做完跟使用者確認再繼續）

- **階段 A**：完成第 4 節三個頁面的 DOM 探查，回報實際欄位/selector/URL 規則 → 確認
- **階段 B**：依階段 A 結果，確認/調整第 5 節資料庫設計，寫好抓取與存儲邏輯（含登入偵測、CSV 下載或 DOM 解析） → 確認
- **階段 C**：實作第 6 節排行表計算邏輯（Delta 篩選 + OI/DTE 排序，這部分本身不依賴階段 A，可以先用假資料寫好單元測試） → 確認
- **階段 D**：實作第 7 節 Options Flow 獨立面板（檢查既有 Options Flow 抓取/分類邏輯是否能直接複用） → 確認
- **階段 E**：第 8 節路由與前端整合 → 確認

每一步都要以實際讀到的 DOM／資料為準，不要假設或猜測欄位名稱與資料格式。

---

## 驗收標準 Checklist

- [ ] 未登入 Barchart 時，系統正確中止並提示手動登入，沒有任何自動登入嘗試。
- [ ] 三個頁面的資料抓取全部走 DOM 解析或合法匯出，沒有呼叫任何內部 API 端點。
- [ ] 排行表格的排序只用 OI（主）+ DTE（次），沒有把 Options Flow 數字混進排序，也沒有額外設定 `min_dte` 之類的天數隱藏門檻把候選排除在表格外。
- [ ] 流動性判斷（充足／普通／偏低）是程式依本次查詢候選的 OI 相對排名動態算出，不是寫死一個固定 OI 數字套用在所有標的上。
- [ ] OI／Volume 欄位同時顯示 Barchart 原始數值與程式算出的流動性判斷結果，兩者都看得到。
- [ ] 結果以表格呈現，不是逐筆寫長段推薦理由文字。
- [ ] Options Flow 面板獨立顯示，標題清楚標示「情緒參考，非排序依據」。
- [ ] 同一 symbol 5 分鐘內重複查詢會讀快取，不重複打 Barchart。
- [ ] 表格下方有「僅供策略篩選參考，非投資建議」提示文字。
- [ ] 配色（卡片底色、邊框、綠/橘黃/紅語義色、hover 效果）直接讀取並複用三維度儀表板既有的 CSS/變數，沒有另外設計一套新色票；流動性分級與 Options Flow 看多/看空判斷的顏色語義跟 `divergence_flag` 的 confirm/warning/caution 對應一致。
- [ ] 新路由跟既有三維度儀表板/IV Skew 相關路由放在同一 namespace／層級下，不是憑空另開一個不相關的頂層路由。
- [ ] 導覽列/選單裡有連結可以直接點進 LEAPS 頁面，不需要手動輸入網址。

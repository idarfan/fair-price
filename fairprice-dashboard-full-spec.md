# FairPrice 三維度判斷儀表板：完整規格（整合版）

> 本文件整合所有已確認的設計決策，取代之前分散的多份文件。
> 若內容有衝突，以本文件為準。

---

## 0. 核心目標與原則

使用者輸入股票代號 → 自動抓取技術面、基本面、Options Flow 三類資料 →
以**三個獨立分數**呈現（技術面 / 基本面 / Options Flow），絕對不合併成單一
綜合分數，並標記三者出現背離時的警示。

**核心原則：Options Flow 只是情緒指標，不代表方向一定正確（機構可能用期權
做對沖，與持股方向相反）。技術面、基本面、Options Flow 三者必須獨立判斷、
並列顯示**，否則會掩蓋「機構避險 vs 方向性押注」這種關鍵背離訊號。

這個原則同樣適用於 Options Flow 內部的子指標——Max Pain、Skew、OI 集中度
彼此之間也可能互相矛盾，矛盾本身是正常現象，不需要、也不應該強行整合成
單一結論。

---

## 1. 安全邊界（最高優先級，所有開發階段都必須遵守）

### 1.1 登入機制：完全不處理登入，僅偵測並提醒

Barchart 用 Google OAuth 登入，**登入這件事完全是使用者自己的事，已經
手動完成，跟程式碼無關**。請用以下心態理解這件事：

- 使用者會自行在瀏覽器手動登入 Barchart，這個動作發生在程式碼執行之前，
  與本系統無關
- 程式碼的職責只有一件事：**連線到 Chrome CDP 後，檢查當前頁面是否已經
  是登入狀態**。如果是，正常抓取資料；如果不是（看到登入彈窗），就停下
  來回報「尚未登入」，然後結束，不做任何其他事

腳本絕對不可：

- 自動填寫帳密
- 自動點擊「Continue with Google」或自動選擇帳戶
- 儲存、快取、或重放任何登入憑證
- 嘗試任何形式的自動登入、模擬登入、或繞過登入彈窗
- 提示使用者「請登入」之後，自己又嘗試做任何登入相關動作

具體流程：

1. 連線到 Chrome CDP（沿用 `playwright-automation` skill 既有流程）
2. 導航到目標頁面後，**立即檢查是否出現登入彈窗**（selector 需實際讀取
   DOM 確認，類似「Welcome to Barchart」彈窗，不可假設 class 名稱）
3. 若偵測到登入彈窗 → 代表使用者目前未登入，立即中止這次操作，標記狀態
   為 `barchart_not_logged_in`，回報給使用者：
   「Barchart 尚未登入，請先手動登入後重試」
4. 若沒有登入彈窗（代表已登入）→ 正常執行抓取/下載

**這個偵測邏輯只是「讀取畫面上有沒有登入彈窗」這個單純的判斷，不涉及
任何登入流程的處理。**

### 1.2 禁止呼叫未授權的內部 API 端點

**絕對禁止**：透過 DevTools/Network 攔截頁面背景請求（XHR/fetch）發現的
內部端點（例如曾發現的 `/proxies/core-api/v1/options/flow`），即使該端點
技術上可行、即使只帶著使用者的 session cookie 而非偽造憑證，也不可呼叫。

判斷標準：

- ✅ **允許**：Playwright 模擬使用者操作（點擊按鈕、填寫篩選器、觸發頁面
  既有的下載功能）——這跟人類親自操作行為一致，風險可控
- ❌ **禁止**：繞過 UI，直接用程式碼呼叫頁面背後打的 API 端點，即使帶著
  合法的 session token

若開發過程中又發現任何類似的內部端點，即使「看起來」是某個功能的一部分，
也要停下回報，不要嘗試呼叫，由使用者決定是否進一步評估。**預設不使用。**

### 1.3 反爬蟲與頻率控制

- 每個 symbol 的抓取/下載之間加入隨機間隔（3-8 秒）
- 不使用固定 `sleep`，用 `wait_for_selector` 等待頁面真正渲染完成
- 同一 symbol 短時間內（例如 5 分鐘內）已抓取過，直接讀資料庫，不重複請求

---

## 2. Options Flow 資料（現有功能，本次新增分類邏輯）

### 2.1 資料取得方式：CSV 匯出（已驗證為合法官方功能）

Options Flow 頁面本身提供 CSV 下載功能，**優先採用此方式**，不需要解析
渲染後的 HTML 表格。

**CSV 實際欄位**（已驗證）：

```
Symbol, Price~, Type, Strike, Expires, DTE, "Bid x Size", "Ask x Size",
Trade, Size, Side, Premium, Volume, "Open Int", IV, Delta, Code, *, Time
```

關鍵欄位說明：

- `Side`：文字值 `mid` / `bid` / `ask`，代表成交發生的位置，**不需要自己用
  Trade 相對 Bid/Ask 計算**
- `*`：值為 `SellToOpen` / `BuyToOpen`（可能還有 `SellToClose`/`BuyToClose`
  等其他值，請依實際資料確認完整值域，不要假設只有這兩種）——**這是直接
  判斷開倉方向的關鍵欄位**
- `Code`：交易執行方式代碼，定義詳見第 4 節
- `Expires`：ISO8601 格式含時區（例：`2026-07-17T16:30:00-05:00`），注意
  時區轉換是否與現有資料一致

### 2.2 自動下載實作方式

**只能用 Playwright 模擬使用者點擊下載按鈕**，等同於使用者親自操作：

1. Chrome CDP 連線到已登入的 session（依第 1.1 節原則處理登入檢查）
2. 導航到目標 symbol 的 Options Flow 頁面
3. 確認篩選器狀態（Side / Trade Sentiment / Flags 等，預設皆為 ALL）
4. 找到頁面上的 Download/Export 按鈕，用 Playwright 點擊觸發下載
5. **設定下載路徑為專案內固定資料夾 `csv_files/`**（見下方 2.2.1 節），
   等待瀏覽器完成下載
6. 讀取下載完成的 CSV 檔案，解析後寫入資料庫

請先讀取 DOM 確認下載按鈕的 selector，回報後等待確認，再執行實際點擊。

**重複提醒：不可用 DevTools 攔截下載按鈕背後呼叫的端點直接呼叫，必須透過
模擬點擊觸發瀏覽器原生下載行為。**

#### 2.2.1 CSV 檔案存放規範（固定路徑，利於日後整理）

所有透過 Playwright 自動下載的 CSV，統一存放在專案根目錄下的
**`csv_files/`** 資料夾，不可散落在其他位置（例如系統暫存目錄、
`/tmp`、或隨機路徑）。

建議的子結構（請先檢查專案現有檔案組織慣例，若有衝突以實際慣例為準，
並回報差異）：

```
csv_files/
  options_flow/
    {SYMBOL}_{YYYY-MM-DD}.csv       # 例：LIN_2026-06-22.csv
  fundamentals/                      # 若第6節基本面也走CSV下載,同樣規範
    {SYMBOL}_{YYYY-MM-DD}.csv
```

規則：

1. 檔名格式固定為 `{SYMBOL}_{YYYY-MM-DD}.csv`，日期為下載當天日期
   （非到期日），避免檔名衝突時直接覆蓋舊檔——同一天重複下載同一
   symbol 時，**覆蓋舊檔即可**，不需要保留多版本
2. `csv_files/` 資料夾須加入 `.gitignore`，避免大量資料檔案被誤
   commit 進版控
3. 資料解析寫入資料庫成功後，CSV 原始檔**不要刪除**，保留作為原始
   資料備查與除錯用途（之後若分類邏輯需要調整，可重新解析既有 CSV
   不必重新下載）
4. 若 `csv_files/` 資料夾不存在，腳本執行時自動建立，不要假設它已存在

**完成下載功能後，請回報實際存放路徑與檔名範例，確認符合此規範後
再繼續。**

### 2.3 Trade 方向 + Code 交叉比對分類邏輯

**核心原則：Code 不能用來判斷方向，只能用來判斷「是否該排除」、「是否為
多腿/組合策略（此時單腿方向不可信）」、以及「可信度權重」。方向性判斷
回到 `Side` + `*` 欄位組合計算。**

#### 方向判斷對照表

| Type | Side | `*` | 解讀 |
|---|---|---|---|
| Call | ask | BuyToOpen | 買方主動開倉買入 Call → **偏多方向性** |
| Call | bid | SellToOpen | 賣方主動開倉賣出 Call → 可能 Covered Call（中性偏多）或裸賣（偏空），**需查 Code 是否多腿** |
| Put | ask | BuyToOpen | 買方主動開倉買入 Put → **偏空或避險**（無法單獨區分） |
| Put | bid | SellToOpen | 賣方主動開倉賣出 Put → **收租策略，偏多訊號** |

#### Code 分類規則（完整定義見第 4 節）

- **應排除**（不納入任何統計）：`CANC`, `CNCL`, `CNCO`, `CNOL`
- **標記為「多腿策略，單腿方向不可信」**：`MLET`, `MLCT`, `MLAT`, `MLFT`,
  `MESL`, `CBMO`, `MCTP`
- **標記為「含股票對沖組合，方向判斷不適用」**：`TLET`, `TLCT`, `TLAT`,
  `TLFT`, `TESL`
- **提高可信度權重**（傾向機構/急迫性）：`ISOI`（急迫性）、`SLFT`,
  `MLFT`, `TLFT`（場內人工大單）
- **降低可信度權重**：`EXHT`（延長時段，流動性較差）
- **標記時間異常**：`LATE`, `OSEQ`, `OPEN`, `REOP`
- **標準單腿交易，可直接判斷方向**：`AUTO`, `SLAN`, `SLAI`, `SLCN`, `SCLI`

#### 彙總邏輯（務必分組統計，不可混合）

對同一個 symbol + strike + expiry，產出**兩組獨立統計**：

**純方向性交易統計**（排除多腿/股票組合類交易）：
```
{
  strike: ...,
  pure_directional_premium_total: ...,
  buyer_initiated_call_pct: ...,
  seller_initiated_call_pct: ...,
  buyer_initiated_put_pct: ...,
  seller_initiated_put_pct: ...,
  institutional_weighted_pct: ...
}
```

**策略性交易統計**（僅多腿/股票組合類交易，不嘗試判斷方向）：
```
{
  strike: ...,
  strategic_premium_total: ...,
  multi_leg_pct: ...,
  stock_combo_pct: ...
}
```

**這兩組統計絕對不可合併成單一方向分數。**

### 2.4 前端呈現

在 Open Interest by Strike 圖表或對應儀表板區塊，當某 strike 的 OI 顯著
高於平均時：

1. 顯示該 strike 的「純方向性交易」分類佔比
2. 若同時有顯著的「策略性交易」佔比，附註：「此 strike 有 N% 的交易為多
   腿策略/股票組合的一部分，這部分交易的方向性無法單獨判斷」
3. 若時間異常佔比偏高，附註：「此 strike 部分交易報告時間有異常，時間序
   列解讀請謹慎」

**UI 務必保留提示**：「此為交易特徵推測，非確定性結論」，避免使用者誤以
為這是精確的方向判斷。

---

## 3. Max Pain / Skew 圖表判讀提醒（通用版，適用所有美股標的）

以下提醒文字加註於對應圖表下方。

### 3.1 Max Pain（Calls / Puts by Strike）

> Max Pain 理論假設選擇權賣方有能力、也有意願將股價推向未平倉量最集中的
> 價位，但這個假設在流動性好、市值大的標的上很難成立。遠月合約的 OI 結構
> 通常較分散、雜訊較多，深度價外的高 OI 較可能反映長期佈局或避險需求，不
> 必過度解讀為方向性訊號。
>
> **使用建議**：僅作為到期日附近短期磁吸效應的參考，不作為中長期方向判
> 斷依據。到期日越遠，參考價值越低。

### 3.2 Open Interest by Strike（Call/Put 分佈）

> 高 OI 集中的 strike，不能直接等同於「市場看多」或「市場看空」。同一個
> 高 OI，可能是方向性押注，也可能是避險或收租策略（中性偏多）。圖表本身
> 無法區分是哪一種。
>
> **使用建議**：須搭配本文件第 2 節的 Trade 方向 + Code 交叉比對結果，不
> 可單獨依據 OI 集中度判斷方向。

### 3.3 Options Volatility Skew

> 下傾斜（downward sloping）的波動率偏斜是選擇權市場的結構性常態，反映
> Put 端避險需求長期高於 Call 端，多數股票皆呈現類似形狀，不宜直接視為
> 看空訊號。單一時間點的 Skew 形狀本身不具判斷力，必須與該標的自身的歷史
> Skew 數據比較（Skew Rank）才有意義。
>
> **使用建議**：務必對照既有 IV Skew Tracker 的 Skew Rank 歷史百分位數據
> 一併判讀，不可僅憑當下曲線形狀下結論。

### 3.4 Max Pain by Contract（隨到期日變化）

> 若某到期日的 Max Pain 數值明顯偏離其他到期日（形成離群值），優先檢查
> 該到期日是否緊鄰財報公布日期。財報前後的跨事件倉位佈局會讓 OI 結構暫時
> 失真，使 Max Pain 參考價值降低。
>
> **使用建議**：自動比對每個到期日與最近財報日的天數差，財報前後 14 天
> 內的到期日數據加註「財報週期，Max Pain 可信度降低」標記。

### 3.5 整合判讀核心原則

1. Skew 形狀不是方向訊號，要看相對該標的自身歷史的 Skew Rank
2. 財報日期附近的 Max Pain 數據可信度會打折
3. 不同到期日、不同圖表傳遞出矛盾訊息是正常現象，不需強行整合成單一結論
4. Options Flow / Max Pain / Skew 三者皆屬情緒指標，反映「市場參與者在做
   什麼」，不是「股價接下來會怎麼走」的預測。出現背離時，優先懷疑是避
   險、財報效應、或結構性常態造成的雜訊
5. 這些原則適用於任何美股標的，市值大、流動性好的標的，Max Pain 磁吸效
   應參考價值更低；流動性差的標的，圖表雜訊比例更高，更需謹慎解讀

---

## 4. Barchart Options Flow Code 代碼定義參考

> 來源：Barchart 官方客服確認。核心原則：這些代碼描述「交易執行方式/管
> 道/時機」，不是「交易方向」，不可直接拿來判斷多空。

### 4.1 電子與自動化交易

| Code | 說明 |
|---|---|
| AUTO | 電子交易，自動撮合成交，最常見方式 |
| ISOI | 跨市場掃單，同時向多交易所下單，代表急迫性較強 |

### 4.2 多腿交易（價差策略等）

| Code | 說明 |
|---|---|
| MLET | 多腿電子交易 |
| MESL | 多腿電子對單腿交易 |
| MLAT | 多腿拍賣 |
| MLCT | 多腿交叉交易 |
| MLFT | 多腿場內交易 |

### 4.3 股票 + 期權組合交易

| Code | 說明 |
|---|---|
| TLET | 股權組合電子交易 |
| TESL | 股權組合電子對單腿交易 |
| TLAT | 股權組合拍賣 |
| TLCT | 股權組合交叉交易 |
| TLFT | 股權組合場內交易 |

### 4.4 單腿交易

| Code | 說明 |
|---|---|
| SLAN | 單腿非 ISO 拍賣 |
| SLAI | 單腿 ISO 拍賣 |
| SLCN | 單腿非 ISO 交叉交易 |
| SCLI | 單腿 ISO 交叉交易 |
| SLFT | 單腿場內交易 |

### 4.5 修正與取消（應整筆排除）

| Code | 說明 |
|---|---|
| CANC | 取消交易（非最後一筆或開盤交易） |
| CNCL | 最後一筆取消 |
| CNCO | 開盤取消 |
| CNOL | 唯一交易取消 |

### 4.6 時間與特殊時段

| Code | 說明 |
|---|---|
| EXHT | 延長時段交易，流動性通常較差 |
| LATE | 延遲報告，順序正確 |
| OSEQ | 順序錯誤的延遲報告 |
| OPEN | 開盤延遲報告，順序錯誤 |
| REOP | 重新開盤交易 |

### 4.7 其他專業交易

| Code | 說明 |
|---|---|
| CBMO | 自營產品多腿場內交易（至少3腿，價格可能在 NBBO 之外） |
| MCTP | 多邊壓縮交易（自營產品平倉，通常非交易時段） |

### 4.8 注意事項

此分類規則依據執行管道/型態的邏輯推論，**這是合理推論，不是 Barchart 官
方對「機構 vs 散戶」的明確分類**。若日後要驗證這套權重規則的準確性，建
議觀察大量歷史交易記錄與後續股價走勢的關聯，而非僅憑邏輯推論視為定論。

---

## 5. 技術面（Technical Analysis）資料

### 5.1 資料取得方式：Playwright + DOM 解析

此頁面**無 CSV 下載功能**（已確認），須用 Playwright 讀取渲染後的 DOM。

目標頁面：`https://www.barchart.com/stocks/quotes/{SYMBOL}/technical-analysis`
（請先確認實際 URL 格式，不要假設）

### 5.2 DOM 探查（先做，不要跳過）

讀取 DOM，找出四個表格的 selector：

**Moving Average**：Period, Moving Average, Price Change, Percent Change,
Average Volume（Period: 5-Day, 20-Day, 50-Day, 100-Day, 200-Day,
Year-to-Date）

**Stochastic**：Period, Raw Stochastic, Stochastic %K, Stochastic %D,
Relative Strength（Period: 9/14/20/50/100-Day）

**Average True Range**：Period, Average True Range, Average True Range %,
Average Daily Range, Average Daily Range %（Period 同上）

**Directional Index**：Period, Directional Index (ADX), Positive
Direction (+DI), Negative Direction (-DI), Historic Volatility（Period
同上）

同時找出登入彈窗的 selector（依第 1.1 節判斷 session 是否有效）。

頁面可能用 React/Vue 渲染，用 `wait_for_selector`，不要用固定 `sleep`。
數字欄位可能含 `+`/`-`/`%` 與千分位逗號，需清洗成數字。

將確認後的 selector 寫入 memory：`reference_barchart_technical_dom.md`。

**完成此步驟後，回報實際 DOM 結構，等待確認後才進入下一步。**

---

## 6. 基本面（Fundamental）資料

### 6.1 資料取得方式待探查

基本面資料的確切頁面與欄位尚未確認。導航到 Overview 頁面（請先確認實際
路徑），列出實際看到的基本面相關區塊（EPS、營收成長率、下次財報日期、
P/E、Analyst Rating 等），回報後再決定要抓哪些欄位。

**不要假設欄位有哪些，以實際看到的內容為準。**

---

## 7. 資料庫設計

### 7.1 `technical_analyses`

wide format，一個 symbol + 日期一行，欄位用週期前綴展平（例如 `ma_5d`,
`stoch_k_9d`, `adx_14d`, `atr_pct_14d`），**不要用 EAV 設計**。
Unique constraint：`(symbol, fetched_at::date)`。
請規劃完整欄位清單，先給使用者看過再建 migration。

### 7.2 `fundamentals`

欄位待第 6 節探查結果確認後再設計。

### 7.3 `options_flow_trades`（或現有對應表，需先確認）

儲存 CSV 解析後的逐筆交易資料，欄位對應第 2.1 節的 CSV 欄位，並新增分類
標記欄位：`is_multi_leg`, `is_stock_combo`, `urgency_high`,
`likely_institutional`, `low_liquidity_period`, `timing_anomaly`。

### 7.4 `fetch_logs`

記錄每次抓取狀態：`success` / `barchart_not_logged_in` /
`dom_structure_changed` 等，欄位至少包含：symbol, fetch_type, status,
error_detail, fetched_at。

---

## 8. Composite Signal 邏輯

`app/services/composite_signal_service.rb`，輸入 symbol，輸出三個獨立分數：

1. **technical_score**（偏多/中性/偏空）：根據 MA 排列方向、ADX 強度
   （>25 視為有明確趨勢，<20 視為盤整）、+DI vs -DI、Stochastic 超買超
   賣（>80/<20）綜合判斷
2. **fundamental_score**（偏多/中性/偏空/觀察中）：依第 6 節實際拿到的
   欄位設計，財報前可標記「觀察中」而非強行給方向
3. **options_flow_score**：沿用既有 IV Skew Rank 邏輯，搭配第 2 節的
   Trade 方向 + Code 分類結果
4. **divergence_flag**：任意兩個分數方向相反時標記，並產生說明文字（例
   如「財報前 7 天內，Options Flow 偏空但技術面偏多，可能為機構避險而
   非方向性押注」）

**三個分數務必獨立輸出，絕不可合併成單一綜合分數或加權平均分數。**

---

## 9. 路由與前端

1. `config/routes.rb` 新增獨立資源路由（例如
   `resources :technical_dashboards, only: [:index, :show]`）
2. 頁面用 **Phlex 元件**（沿用既有 Phlex + Tailwind CDN 慣例，不使用
   ERB/Hotwire）
3. 頁面結構：
   - Symbol 輸入框 → 送出後顯示「抓取中」狀態 → 完成後顯示結果
   - 三個獨立卡片並排：技術面 / 基本面 / Options Flow
   - 背離時用黃/橘色警示，並附文字說明可能原因
   - 若狀態為 `barchart_not_logged_in`，顯示明確提示：「Barchart 尚未
     登入，請先手動登入後重試」
4. 視覺風格可參考 `iv-skew-dashboard` skill 的深色卡片 + gauge 設計
5. Playwright 抓取需數秒，使用 ActiveJob 背景處理，前端用 Turbo Stream
   或 polling 顯示進度，避免使用者等待時頁面卡住

---

## 10. 排程

此功能採「使用者觸發查詢時才抓取」模式，**不需要每日自動排程**，不要額
外設計 cron / 定時任務。

---

## 11. 執行方式（請務必分階段進行）

每完成一階段就跟使用者確認，再進入下一階段，**不要一次做完全部**：

- **階段 A**：第 5 節技術面 DOM 探查 → 回報，等待確認
- **階段 B**：第 6 節基本面 DOM 探查 → 回報，等待確認
- **階段 C**：第 2.2 節 Options Flow CSV 自動下載（先讀取下載按鈕
  selector，回報後才執行實際點擊）→ 回報，等待確認
- **階段 D**：第 7 節資料庫設計 → 列出完整欄位清單，等待確認後才建
  migration
- **階段 E**：第 2.3 節分類邏輯 + 第 8 節 Composite Signal 邏輯 → 回報，
  等待確認
- **階段 F**：第 9 節路由與前端 → 回報，等待確認

每一步都必須以**實際讀取到的 DOM 結構 / 實際查到的現有 schema** 為準，不
可假設或猜測。若實際情況與本文件描述不一致，回報差異，等待確認後再繼續。

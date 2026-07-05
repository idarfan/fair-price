# FairPrice 新功能規格：LEAPS Call 操作建議

> **新 session 開始前，請先完整重讀本檔案 `leaps-call-recommendation-spec.md`，特別是最前面這段「接手前必讀」，不要跳過直接開始做事。**

## 接手前必讀（2026-07-05 歸檔版）

LEAPS Call 候選排行功能已結案（2026-07-02）；後續增量 fresh window 30 分鐘（commit `2e46139`）、Phase H 內在/外在價值欄位（`2f9159a`＋`6abc533`）、Phase I 匯出 PNG/PDF（`f233b1f`＋`3f416ca`）均已交付並通過驗收，僅餘文末「待辦」的 live 對照補驗一項。本檔只保留現行有效規範（核心原則、DOM 參考、schema、公式唯一定義處、fresh window 規範、Phase H/I 規格）；歷代開發脈絡、CDP 事件記錄、各階段交付記錄、已完成 checklist 與證據，全部在 `leaps-call-recommendation-history.md`，僅在追查歷史問題時才讀。新功能需求請另開新規格文件，不要在本檔累加。

> 歷史記錄（原「接手前必讀」全文、工具驗證教訓、CDP 事件、待辦狀態演進）見 `leaps-call-recommendation-history.md` 第 1 節。
## 背景與目標

在 FairPrice 新增一個功能：使用者輸入股票代號後，系統自動從 Barchart 抓取該標的的選擇權報價、Greeks/波動率、Options Flow 三組資料，依 Delta 鎖定深度價內（LEAPS Call 候選）範圍後，**直接輸出履約價 × 到期日的排行表格**（OI 高到低排序），不額外篩選成單一推薦，由使用者自己看表決定。

這個功能的定位是「**LEAPS 候選排行表**」，資料層邏輯對應到你過去手動幫 NOK／NVTS／AAPL／LIN 挑 LEAPS 履約價時做的事：比較多個到期日 × 多個履約價，用 Delta 鎖定深度價內範圍，再看 OI／Volume／Bid-Ask Spread 判斷流動性。這次把「抓資料、算 Delta 範圍、排序」自動化，但**不自動下結論挑單一答案**，最終判斷留給使用者自己看表格決定。

**用途範圍**：純方向性 LEAPS Call（取代持股／槓桿做多），不是 PMCC 完整建倉（PMCC 還需要再選 Short Call，那是下一個獨立功能，不在這份規格內）。

---

## 核心原則（不可違反，沿用專案既有規範）

1. **登入機制 + CDP 連線必須在最前面就先擋下來，不能讓使用者白等**：Barchart 用 Google OAuth 登入。系統**只負責偵測**目前 Chrome CDP session 是否已登入（導航後檢查是否出現登入彈窗），**絕對不嘗試任何形式的自動登入**（不填帳密、不點 "Continue with Google"、不處理 OAuth 流程）。偵測到未登入 → 立即中止，回報「請手動登入 Barchart 後重試」，不做任何補救嘗試。
   - **這條規則涵蓋兩層，缺一不可**：(a) `BarchartScraperService` 內部在真正開始抓取前檢查一次（既有設計）；(b) **Controller 在送出抓取 job 之前，必須先做 CDP 連線預檢**（檢查 `http://localhost:9222/json/version` 或等效方式能不能連上），連不上就在這裡直接回報「CDP 未連線，請確認 Chrome 已以 remote-debugging 模式啟動」，不能讓 job 排進去之後過了好幾秒才在 scraper 內部才報錯——使用者點查詢應該幾乎立即知道環境沒就位，不是等 13 秒。**這兩層檢查曾經只做了 (a) 沒做 (b)，導致使用者每次都要等 job 跑到一半失敗才知道是環境問題，這條規則就是要把這個漏洞釘死，之後任何重新檢視這份規格的人都要確認這兩層都還在，不能只看到 (a) 就以為夠了。**
   - **環境背景（WSL2 mirrored 網路模式）**：這個專案的 Chrome CDP 是在 WSL2 mirrored 網路模式下、Windows 端開啟 Chrome 並指定 `--remote-debugging-port=9222`，WSL2 這邊透過 `localhost:9222` 連線。預檢失敗時，錯誤訊息應該提示具體檢查步驟（Windows 上的 Chrome 是否用 remote-debugging 啟動、`http://localhost:9222/json/version` 能不能在瀏覽器打開看到版本資訊），不要只回一句模糊的「CDP 連線或程式錯誤」。
2. **禁止呼叫內部 API**：所有資料一律透過 Playwright 讀取頁面實際渲染的 DOM，或使用頁面本身提供的合法「匯出/下載」功能（沿用 Options Flow CSV 下載的既有模式）。**禁止**用 XHR 攔截、攔截 session cookie、或直接呼叫 Barchart 內部 API 端點（例如 `/proxies/core-api/...`），即使技術上抓得到也不可以。
3. **三維度獨立原則延伸**：這個功能產出的「LEAPS 排行表」，**只能由 Delta 區間篩選 + OI/DTE 排序組成**，**不可把 Options Flow 情緒訊號混進排序或拿來篩選候選**。Options Flow 資料以獨立面板呈現（見第 7 節），作為「這個排行跟今天的市場情緒方向是否一致」的參考，由使用者自行判斷，不自動加減分、不自動排除候選。
4. **不假設 DOM／資料格式**：Phase A 已確認 Options Prices 頁面含 Delta/IV，Volatility & Greeks 頁面只額外抓 Vega 一欄（方案 A + Vega，見第 4 節）；其他未探查欄位仍需以實際 DOM 為準，不可憑猜測或本文件範例欄位名稱直接寫死 selector。
5. **分階段執行**：嚴格按照第 10 節的階段順序進行，每階段做完跟使用者確認後才能進下一階段。

---

## 使用者流程

```
使用者輸入股票代號（例如 NOK）＋ 選填：手動指定履約價（留空則自動偵測）
        ↓
系統檢查 Chrome CDP 連線 + Barchart 登入狀態
        ↓ 未登入                    ↓ 已登入
回報「請先登入 Barchart」      Stage 1：取得候選履約價中心點
（不繼續往下）                  （使用者填了履約價 → 直接當中心點；
                                   留空 → Near the Money 檢視 Delta>=0.60 自動偵測）
                                       ↓
                                Stage 2：以中心點上下加緩衝檔，
                                  鎖履約價 Stacked 檢視抓全到期日資料
                                       ↓
                                存進 PostgreSQL
                                       ↓
                                跑 LEAPS 候選排行 + 推薦分析（第 6 節，套用 0.60–0.90 最終篩選）
                                       ↓
                                畫面顯示：
                                ① 推薦分析（近天期／遠天期 LEAPS 各一組明確建議＋理由文字；
                                   若手動指定的履約價篩不出任何候選，明確顯示原因，不留白）
                                ② 完整排行表格（DTE>=364，依 OI 排序列出全部候選）
                                ③ 決策當天的 Options Flow 面板（獨立顯示）
```

---

## Phase A：頁面 DOM 探查（已確認結果如下）

### A.1 Options Prices（主要資料來源）
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/options?expiration={DATE}`

**Phase A 確認結果：Delta 與 IV 這頁本身就有。** Strike、Bid、Ask、Last、Volume、Open Interest、Delta、IV 都從這一頁取得。

需要實際確認：
- 到期日清單從哪裡讀（通常頁面上有 expiration 的 `<select>` 或 tab 清單，**用這個清單拿到全部可用到期日，不要自己猜日期格式**，要包含遠期 LEAPS 到期日，不是只有近期週選）
- 表格實際欄位有哪些（已確認包含 Strike、Bid、Ask、Last、Volume、Open Interest、Delta、IV，以實際讀到的 column header 為準）
- Call / Put 是左右並排兩個表格，還是分頁切換，需確認 DOM 結構
- 頁面是否也有合法的 CSV/Export 下載功能（如果有，優先用下載，不用解析 DOM 表格，沿用 Options Flow 的既有模式）

### ⚠️ 抓取策略修正：用「鎖履約價、Stacked 檢視」取代逐到期日序列爬

**實測發現（已由使用者實際操作＋截圖驗證，不是猜測）**：Options Prices 頁面選擇 **Stacked 檢視 + 鎖定某個履約價**後，會一次顯示**該履約價在所有到期日**的 Moneyness/Bid/Mid/Ask/Volume/Open Interest/OI Chg/Delta/IV，橫跨近兩年半、18個到期日，**一次頁面操作就拿到全部**，不需要逐到期日切換。

URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/options?view=stacked&strike={STRIKE}`（`expiration=` 參數已確認在 `strike=` 存在時不影響顯示範圍，可以省略，不需要費心算這個參數要填哪個值）。

**為什麼這個方向特別適合 LEAPS（不是泛用最佳化，是這個用途剛好命中這個頁面特性）**：深度價內選擇權的 Delta 對到期日遠近相對不敏感，同一個履約價橫跨整條到期日曲線，Delta 變化幅度通常比想像中小——這代表**鎖少數幾個履約價、看它們在所有到期日的表現，比鎖一個到期日、看所有履約價，更貼近「找深度價內 LEAPS 候選」這個任務的形狀**。

**新抓取流程（兩階段，取代原本逐到期日序列爬）**：

1. **第一階段：估出候選履約價**——選擇 Barchart「Near the Money」檢視（畫面上預設靠近現價的履約價清單），這個檢視本身就直接顯示 Delta 欄位，**不需要另外用股價/權利金反推公式去算錨點**（曾經考慮過用「股價 vs 履約價+權利金」的價格關係去反推候選履約價，但這個公式在深度價內時差距連續縮小、不會有明確交叉點，且越往深價內越容易撞到 Delta=0.0000、IV=0%、無成交記錄的死報價，這個方向已放棄，不要實作）。直接讀 Delta 欄位，篩出 **Delta >= 0.60** 的履約價，當作第二階段要鎖定的候選對象。
   - **這個 0.60 門檻只用在「Stage 1 該鎖哪幾檔履約價」這一步，是快速篩選規則，跟最終進排行表/推薦分析的 0.60–0.90 區間是兩條不同用途的規則，不互相取代**：Stage 1 用 0.60 寬鬆地圈出值得鎖定深入查詢的履約價（沒有上限，因為這階段只是要找「夠深價內」的候選對象，不是最終篩選），Stage 2 拿到該履約價在所有到期日的完整資料後，**還是要套用 0.60–0.90 這個區間做最終篩選**（因為同一履約價在不同到期日的 Delta 會漂移，0.60 篩出來的履約價，到了某些到期日 Delta 可能會落在 0.60 以上甚至超過 0.90，也可能落到 0.60 以下——這些都要交給 Stage 2 的 0.60–0.90 篩選去判斷，不是 Stage 1 篩過就直接算數）。
   - **新增：使用者可以手動輸入履約價，覆寫 Stage 1 的自動估算**——輸入框是選填，留空時維持現有的 Delta>=0.60 自動偵測；填了之後，**這個輸入值直接取代 Stage 1 算出來的「中心履約價」，後面的流程完全不變**：仍然以這個值為中心，照第4點的規則上下加緩衝檔，再進 Stage 2 鎖履約價拿全到期日資料，最終一樣套用 0.60–0.90 篩選。這代表手動輸入**不是「只查這一檔」、也不是「跳過 0.60–0.90 篩選」**，只是換掉 Stage 1 那一步的資料來源（從自動偵測換成使用者指定），Stage 2 跟最終篩選邏輯一律不變。
   - **邊界情況**：如果使用者輸入的履約價跟現價差太遠（例如根本不是深價內，或反而是價外），Stage 2 抓回來的資料在套用 0.60–0.90 篩選後可能完全沒有候選通過——這種情況要明確顯示「這個履約價（含緩衝檔）在所有到期日都沒有符合 Delta 0.60–0.90 的候選」，不要顯示空白或誤導成查詢失敗，這是輸入值本身不適合做 LEAPS、不是系統錯誤。
2. **第二階段：逐履約價拿全到期日資料**——針對第一階段選出的每個履約價，各開一次「Stacked + 鎖履約價」頁面，一次拿到該履約價在所有到期日的數值。原本「N個到期日 × 2頁」的序列爬蟲，縮減成「2–4個履約價 × 2頁」。
3. **篩選邏輯不變**：拿到資料後，還是套用 Delta 0.60–0.90 篩選——**這一步不能省略**，鎖履約價只是換一種方式收資料，不代表這幾個履約價在每個到期日都符合 Delta 範圍，仍要逐筆檢查。
4. **鎖定履約價的數量要覆蓋足夠範圍，不能只鎖一個**：深度價內 Delta 對到期日「比較不敏感」不等於「完全不變」——同一履約價，到期日拉長，Delta 通常會逐漸往中間值靠近（時間價值增加稀釋 Delta）。只鎖一個履約價，可能在近天期符合 Delta 範圍、但遠天期就跌出範圍，導致遠天期那組漏掉本該存在、由「隔壁履約價」覆蓋的候選。**第一階段挑選候選履約價時，要往兩個方向各多留一檔緩衝**（例如預估中心履約價之外，上下各多抓一檔），確保 Delta 隨到期日漂移的部分還能被其他履約價覆蓋到，不要只算剛好卡在中心估計值的那一個。

**待驗證（V&G 頁面是否支援同樣模式）**：這次驗證的是 Options Prices 頁面，Volatility & Greeks 頁面**還沒驗證**是否也支援「鎖履約價、Stacked」模式。如果支援，V&G 那層（Vega/itm_probability/vol_oi_ratio）可以用同樣兩階段流程縮減；如果不支援，V&G 那層維持原本逐到期日抓取，只是抓取的到期日清單改成「第二階段那幾個履約價各自有資料的到期日聯集」，而不是全部到期日都要抓。

### A.2 Volatility & Greeks（方案 A + Vega + itmProbability + volumeOpenInterestRatio）
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/volatility-greeks?expiration={DATE}`

**Phase A 最終確認：這頁額外抓 3 欄，其餘略過。**

| 欄位 | 抓不抓 | 理由 |
|---|---|---|
| `vega` | 抓 | 量化「IV 偏高、未來 IV 回落侵蝕權利金」的風險提示 |
| `itmProbability` | 抓 | 同頁面零額外成本，且跟手動選 LEAPS 時用的「被指派機率」邏輯一致 |
| `volumeOpenInterestRatio` | 抓 | Barchart 已算好，直接取代規格內自行用 `volume<=3` 門檻判斷「近期無成交」的粗略邏輯（見第 6 節） |
| `gamma` / `theta` / `rho` | 不抓 | 深度價內 LEAPS 場景下參考價值低，目前沒有任何邏輯會用到 |
| `theoretical` | 不抓 | 回答的是「定價是否合理」，目前功能沒有任何邏輯需要這個問題的答案 |

**Merge key（Phase A 確認）**：`(strikePrice, expirationDate)`，兩頁完全對得上，不需要額外的容錯比對邏輯。

> 跳過的部分：Gamma/Theta/Rho/Theoretical 不抓、不存。多抓的部分：Vega/itmProbability/volumeOpenInterestRatio 三欄，merge key 確認乾淨對得上，沒有額外風險。

### A.3 Options Flow
參考 URL：`https://www.barchart.com/stocks/quotes/{TICKER}/options-flow`

這個頁面之前已經驗證過合法 CSV 匯出可用，欄位已知為：
```
Symbol, Price~, Type, Strike, Expires, DTE, "Bid x Size", "Ask x Size",
Trade, Size, Side, Premium, Volume, "Open Int", IV, Delta, Code, *, Time
```
沿用既有 `csv_files/options_flow/{SYMBOL}_{YYYY-MM-DD}.csv` 下載與命名規則即可，**這頁不需要重新 DOM 探查**。

**Phase A 確認結果：既有爬蟲已完整，`OptionsFlowTrade` model 已存在，直接複用，不需要新寫抓取邏輯。**

> Phase A 全部確認完畢，進 Phase B。

---

## 資料庫設計

### 為什麼需要新表，不是擴充 `option_snapshots`（Phase A 確認）

| | `option_snapshots`（既有） | LEAPS 需求 |
|---|---|---|
| 識別方式 | `tracked_ticker_id`（FK 到 `tracked_tickers`，需預先登記） | 任意 ticker 字串，使用者輸入即查，不需預先登記 |
| `delta` 欄位 | 無 | 核心篩選欄位，必須有 |
| 主 key 結構 | `tracked_ticker_id` + `contract_symbol` | `(symbol, expiration_date, strike, option_type, scraped_at)` |
| 用途／粒度 | 追蹤特定合約的價格歷史（每 symbol 一筆彙總快取） | 每次查詢的全標的快照，篩完即用（per-contract） |

兩者 grain 完全不同，不是「順手擴充舊表」能解決的差異，新建表是必要的，不是為了偷懶繞過既有結構。

### `leaps_option_chain_snapshots` 欄位（Phase B 實際建表結果）

| 欄位 | 說明 |
|---|---|
| `symbol` | 股票代號 |
| `expiration_date` | 到期日 |
| `dte` | 距到期天數（抓取當下計算） |
| `strike` | 履約價 |
| `option_type` | call / put（這個功能只需要 call，但表結構保留兩者以備未來 PMCC 功能共用） |
| `bid`, `ask`, `last_price` | 報價 |
| `underlying_price` | 抓取當下的標的股價（用於算 time value %） |
| `volume`, `open_interest` | 流動性（原始值） |
| `delta`, `iv` | 來自 Options Prices 頁面 |
| `itm_probability`, `vol_oi_ratio` | 來自 Volatility & Greeks 頁面 |
| `scraped_at` | 抓取時間 |
| `intrinsic_value` 🆕 Phase H | 內在價值（Intrinsic Value），**Ruby persist 層計算後存入**，不是 Barchart 抓來的欄位。公式見 Phase H 一節 |
| `extrinsic_value` 🆕 Phase H | 外在價值（Extrinsic Value / Time Value），**以 Mid 為權利金基準計算**（Mid = (bid + ask) / 2，等同 Barchart 頁面的 Mid 欄；**不是用 `last_price`**，因為 Latest 是最後成交價，可能是數小時前的陳舊價格，Mid 才貼近當下實際要付的權利金）。公式見 Phase H 一節 |

**Merge key（Phase A 確認）**：`(strike_price, expiration_date)`，Options Prices 與 Volatility & Greeks 兩頁完全對得上，不需要額外容錯比對。

**主 key**：`(symbol, expiration_date, strike, option_type, scraped_at)`。

**不新增 gamma/theta/rho/theoretical 欄位**：理由見第 4 節 A.2，本次 Phase B 補欄位也不重新討論這三個。

> ⚠️ **已知缺漏，待補**：Phase B migration 漏了 `vega`——這不是新提案，是「方案 A + Vega」當時就批准、Phase A 確認結果（第 4 節 A.2）也明確列了的欄位，純粹是建表時漏寫。**決議：補一個小 migration 加 `vega` 欄位即可，不需要整張表重建；gamma/theta/rho 維持不加，沒有新理由推翻原決定。**

`vega`、`itm_probability`、`vol_oi_ratio` 在排行表上都是**獨立顯示欄位**，跟其他流動性/Greeks 欄位一樣不參與排序或篩選公式。

> ⚠️ 第 6 節「近期無成交」警示規則需同步更新：原規則是用自行設的 `volume<=3` 門檻判斷，現在改用 Barchart 算好的 `vol_oi_ratio`（見第 6 節更新後內容），門檻數值需要重新依這個比率的實際分布設定，不能直接沿用舊的 `<=3` 那個是針對原始 volume 設計的數字。

---

## LEAPS 候選排行表 + 推薦分析（兩層）

這部分是純計算，不依賴 DOM 探查結果，可以先寫好。

### ⚠️ 設計修正記錄：重新引入 52 週 DTE 門檻

**這節的決定覆蓋了更早版本的「不預設遠天期最低天數門檻」決定，原因是實測發現一個沒預料到的漏洞：**

Delta 0.60–0.90 篩的是「深度價內」這個價平關係，跟到期日遠近完全無關——一個 5 天後到期的深度價內買權，Delta 一樣可以落在 0.85，照樣會通過篩選。實測 NOK 時，排行表裡真實出現了 DTE 5、13、20 天的候選，這些根本不是 LEAPS（LEAPS 慣例定義是到期日 1 年以上），純粹是因為「不設天數門檻」+「Delta 篩選不等於天期篩選」這兩件事疊在一起，把近期合約也放進了一個明明叫「LEAPS Call 候選」的功能裡。

**修正後規則：全功能（排行表＋推薦分析兩層）都套用 `DTE >= 364`（52 週）的硬性下限，不是「不預設門檻」。** 這跟之前「不要寫死 `min_open_interest`」是不同性質的決定——OI 門檻是「流動性夠不夠」這種程度問題，因標的而異，不該寫死；但「是不是 LEAPS」是這個功能存在的前提定義，52 週是業界慣例下限，不是隨手選的數字，兩者不能用同一套「不要預設」的邏輯套用。

### 版面結構（上下兩段，各自獨立功能）

- **上半段：推薦分析**（這節定義，新增）——明確指出建議的到期日/履約價，並寫出為什麼。
- **下半段：完整排行表**（原有設計，本節調整：加上 52 週門檻）——所有符合 `DTE>=364` 且 Delta 0.60–0.90 的候選都列出來，OI 高到低排序，使用者可以看到推薦之外的其他選項。
- Options Flow 前 20 大面板維持獨立於這兩段之下（第 7 節，已完成，不受這次調整影響）。

---

### 上半段：推薦分析（新增邏輯）

**分兩組推薦，各自獨立挑選＋寫理由，不是單一答案：**

| 分組 | DTE 範圍 | 說明 |
|---|---|---|
| 近天期 LEAPS | 364–550 天（約 12–18 個月） | |
| 遠天期 LEAPS | 550 天以上（約 18 個月以上） | |

**每組挑選邏輯：**

1. 取該組 DTE 範圍內、Delta 0.60–0.90 的候選。
2. 優先排除有「⚠ 近期無成交」警示的候選（除非該組全部候選都有警示，此時退回步驟3但保留警示標註，不能因為全部有警示就不給推薦，要老實標出來）。
3. 在剩下的候選中，依流動性分級（充足 > 普通 > 偏低）優先，分級相同則依 OI 由高到低，挑出第一名作為該組推薦。
4. 若該組完全沒有任何候選（例如這次查詢的標的在這個天期區間沒有任何到期日，或 Delta 篩選後沒有候選），明確顯示「此天期區間目前沒有符合條件的候選」，不要留白或省略不顯示。

**理由文字生成規則**（每組推薦都要產生，跟同組的第二名比較）：

- 到期日、履約價、目前 Delta、Mid 報價
- 跟第二名的 OI 對比（例如「履約價 $X 的 OI 為 12,270，是這個天期區間裡最高的；履約價 $Y 雖然 Delta 更貼近，但 OI 只有 1,200，流動性明顯較差」）
- Time Value % 數字，代表這筆 LEAPS 相對直接持股要多花多少時間價值溢價
- Bid-Ask Spread% 是否在合理範圍，偏高要明確警示
- 若 Vega 有值，附註目前 IV 水位＋Vega 數字佐證「IV 偏高、未來 IV 回落可能侵蝕權利金」這個提醒（IV Crush 風險），數字佐證不是空泛文字
- 若推薦的候選本身帶有「近期無成交」警示（步驟2的例外情況），要在理由裡明確點出這個警示，不能因為它是「推薦」就把警示蓋掉不提

文末固定提示：「以上為流動性與 Greeks 篩選後的推薦結果，僅供策略篩選參考，非投資建議，請自行評估。」

---

### 下半段：完整排行表（沿用原有設計，加 52 週門檻）

**這次不做「篩選後只留最佳一組」，改成直接輸出排行表格，所有符合 `DTE>=364` 的候選都列出來，使用者自己看表決定到底要選哪一個**；但流動性夠不夠這件事，**由程式判斷並標示出來，不是甩給使用者自己瞪著 OI 數字猜**：

- **52 週（364天）以下的到期日不列入**（見上方修正記錄），364 天以上的到期日全部列出，不再額外設定第二道天數門檻，DTE 本身是表格的排序/顯示欄位之一。
- **OI／Volume 顯示 Barchart 抓到的原始數值**，同時程式額外算出一欄「流動性判斷」（見下方），不是只丟原始數字讓使用者自己猜夠不夠。
- Delta 仍用區間篩選縮小候選範圍到「深度價內」，預設區間維持 0.60–0.90，可調。

#### 流動性判斷邏輯（不用單一固定 OI 門檻）

**不要寫死一個全標的通用的 `min_open_interest` 數字**（不同股票的選擇權市場深度差非常大，NOK 跟 AAPL 的 OI 量級完全不在一個級別，固定一個數字會對某些標的太鬆、對另一些太嚴）。改用**同一次查詢結果內的相對排名**讓程式自動判斷：

1. 取出這次查詢、該標的、`DTE>=364` 且 Delta 區間篩選後的所有候選（不分到期日，一起算）。
2. 計算這些候選的 OI 分布，依百分位排名分三級：
   - 該標的本次候選 OI 前 1/3 → `流動性：充足`
   - 中間 1/3 → `流動性：普通`
   - 後 1/3 → `流動性：偏低`
3. **額外規則（已更新，改用 Barchart 自算比率，不再自行設 `volume<=3` 門檻）**：若候選的 `vol_oi_ratio` 偏低（代表近期成交量相對 OI 過小，即使 OI 排名落在前 1/3，現在進出也未必容易），標註「⚠ 近期無成交」警示。**這個比率的合理門檻需要 Phase B 實際抓到的資料分布來定，不能直接套用舊版規格的 `volume<=3`**——那個數字是針對原始 volume 設計的，跟 Barchart 算出來的比率不是同一個尺度，照搬會錨錯。建議做法：抓到實際資料後，看這個比率本身的分布（例如百分位或 Barchart 官方對這個欄位的判讀建議，若頁面上有圖示/顏色標示可直接借用對應邏輯），不要憑感覺設一個新數字。

這個分級邏輯是**程式自動算好直接顯示在表格裡**，不是文字描述，使用者一眼就能在表格上看到每個候選的流動性等級，不用自己再去比較數字。

#### 輸入參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `min_dte` | **364**（52週） | **重新引入，硬性下限，理由見上方修正記錄，不是「不預設」** |
| `delta_min` / `delta_max` | 0.60 / 0.90 | 深度價內目標 Delta 區間（用來定義「這是不是 LEAPS Call 候選」，不是流動性篩選），可調 |
| 流動性分級門檻 | 動態（依本次查詢候選 OI 分布算百分位，見上） | 不寫死絕對數字，隨標的自動調整 |

#### 計算與排序流程

1. 取出 `dte >= 364` 的到期日，每個到期日內篩出 `delta_min <= delta <= delta_max` 的履約價（deep ITM 區間）。
2. 對篩出的每一筆候選，帶出 Barchart 原始 OI、Volume 數值，並依上方流動性判斷邏輯計算出 `liquidity_tier`（充足／普通／偏低）與是否有「近期無成交」警示。
3. 計算 `time_value_pct`（供表格欄位顯示用，不是篩選條件）：
   ```
   intrinsic_value = max(0, underlying_price - strike)
   time_value = call_mid_price - intrinsic_value
   time_value_pct = time_value / underlying_price
   ```
   > 🆕 **Phase H 調整**：`intrinsic_value` 與 `time_value`（= `extrinsic_value`）改為**直接讀取 DB 已存欄位**（persist 時已用同一公式算好，見 Phase H），這一步只做 `time_value_pct = extrinsic_value / underlying_price` 的除法，**不要在排行層重算一次內在/外在價值**——兩處各算一次，未來只要其中一邊改了公式（例如權利金基準從 Mid 換掉）就會出現兩邊數字對不上的漂移，這種雙軌計算是已知的 bug 溫床。
4. 計算 `bid_ask_spread_pct = (ask - bid) / mid_price`（同樣是表格欄位，不是篩選條件）。
5. 排序：依 `open_interest` 由高到低排，OI 相同時依 `dte` 由大到小排（天數排行）。

#### 表格輸出

直接列出表格，欄位：

| 到期日 | DTE | 履約價 | Delta | OI | Volume | 流動性判斷 | Bid | Ask | Mid | Spread% | 內在價值 | 外在價值 | 外在佔比 | Time Value% | IV | Vega | 被指派機率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

- 🆕 **Phase H 新增三欄**：「內在價值」「外在價值」直接顯示 DB 存的 `intrinsic_value`／`extrinsic_value`；「外在佔比」= `extrinsic_value / mid`（display 層計算，不落地，mid 由 bid/ask 重算，結果具決定性），顯示為百分比。**外在佔比跟 Time Value% 是兩個不同分母的指標，都要顯示、不要合併**：外在佔比的分母是權利金 Mid（回答「這口權利金裡有多少比例是保險費」，深 ITM LEAPS 篩選的核心指標）；Time Value% 的分母是股價（回答「相對直接持股要多付百分之幾的溢價」）。`mid <= 0` 或 bid/ask 缺值時外在佔比顯示「—」，不要顯示 0% 或 NaN。

- 表格本身就是排行（OI 高到低，同 OI 依 DTE 大到小），不額外寫每一列的推薦理由段落（理由文字只在上半段推薦分析出現），但「流動性判斷」欄是程式算好的結論，不是原始數字。
- 表格上方加一行固定提示：「僅列出到期日 364 天以上（LEAPS 慣例下限）的候選；依 OI 由高到低排序；流動性判斷依本次查詢候選的 OI 相對排名計算，非固定門檻，不同標的會自動調整基準。」
- 表格下方固定提示：「以上為 Delta 區間篩選後的排行結果，僅供策略篩選參考，非投資建議，請自行評估。」

---

## 決策當天的 Options Flow 顯示（獨立面板，不併入排序）

> **範圍邊界（避免跟第6節混淆）**：第6節新加的 `DTE>=364` 門檻**只套用在 LEAPS 候選排行表跟推薦分析**，這個 Options Flow 面板完全不受影響——這裡顯示的是當天**所有**到期日、所有履約價的成交排行，目的是判斷近期市場成交熱度/情緒，不是篩 LEAPS 候選，兩者篩選邏輯互相獨立，不要因為改了第6節就連動改到這裡。

在排行表格下方，另開一個獨立區塊顯示**抓取當天**該股票的 Options Flow，**前 20 大成交單**（依 `premium` 降序排序取前 20 筆，固定數量，不是固定金額門檻）：

**Phase A 確認結果：既有爬蟲已完整，`OptionsFlowTrade` model 已存在，這個面板直接複用既有資料來源/model，不需要新寫抓取邏輯，只需要新寫「取前20大＋依排行表前幾名的到期日/履約價篩出相關列＋算出看多/看空判斷」這層顯示邏輯。**

> ⚠️ **規格修正記錄**：這節原本被寫成「大單（依既有 Flags/Code 分類）清單」，採用 `large_premium: true`（固定 $50萬門檻，數量不定）取資料，這跟使用者最初提出的「前20大」（固定 20 筆，依 premium 排序）是兩個不同概念，是這份規格在撰寫時的錯誤改寫，不是 Phase D 實作偏離規格——Phase D 當時完全照規格字面做是對的。**確認結果：改回原始需求，固定取前 20 筆，依 premium 降序。**`large_premium` 那個固定門檻判斷（$50萬）保留用在分類/標記上沒問題（例如表格裡可以額外標一個「大單」icon），但**面板抓取的資料範圍**改成「premium 排序前 20 筆」，不是「premium ≥ $50萬 的全部」。

- 顯示當天 Call 與 Put 的總 Premium 量
- **前 20 大清單**：依 `premium` 降序取前 20 筆（不限 `large_premium` 門檻，數量固定為 20，可以少於 20 筆如果當天交易量不足，但不會用金額門檻篩掉本該進榜的交易）
- 沿用既有 Code／Side／`*` 分類邏輯（多腿代碼標記不可信、標準單腿代碼可信），這 20 筆裡每一筆都標示分類結果與看多/看空判讀
- 若這 20 筆裡有成交剛好落在排行表前幾名的到期日／履約價附近，特別標出來（純顯示提示，例如「今天在排行第一的 $X 履約價附近有一筆大額買權買入」），但**不自動把這個訊號加進排行排序**，標題上明確寫「情緒參考，非排序依據」

---

## 路由與前端

- 路由不要憑空另開一個孤立的頂層資源：先看 `config/routes.rb` 現有結構，三維度儀表板（`technical_dashboards` 或類似名稱，請依實際檔案確認）跟既有的 `iv_skew_dashboard`／options flow 相關路由放在哪個 namespace／哪個區塊下，這次新增的 `leaps_recommendations` 應該跟著放在同一層級／同一 namespace 下，維持路由結構一致，不要平行另開一塊。
- **要加進現有的導覽列/選單**：找到目前 Phlex layout 裡放導覽連結的位置（例如 header 或 sidebar 的 nav 元件），把這個新頁面的連結加進去，不能只新增 controller/route 卻沒有任何入口可以點進去，使用者不該需要自己手動輸入網址才能用到這個功能。
- Phlex 元件，沿用專案既有慣例（不用 ERB/Hotwire）
- 輸入區塊新增**選填**的履約價輸入框（放在股票代號旁邊或下方），留空時走 Stage 1 自動偵測（Delta>=0.60），填了則直接當 Stage 2 的中心履約價，後續流程（上下加緩衝檔、Stage 2 抓取、最終 0.60–0.90 篩選）完全不變，不是另開一套邏輯。
- 頁面流程：輸入股票代號（＋選填履約價）→ 送出後顯示抓取中狀態（Playwright 抓取需要數秒，用 ActiveJob + Turbo Stream/polling）→ 完成後顯示：
  1. **推薦分析**（第 6 節上半段，新增：近天期/遠天期 LEAPS 各一組明確建議＋完整理由文字，不是表格）
  2. **完整排行表格**（第 6 節下半段，OI 高到低排序，`DTE>=364` 且 Delta 0.60–0.90 區間內的候選都列出來）
  3. 當天 Options Flow 面板（獨立區塊，第 7 節，已完成）
- 表格可加履約價/到期日的欄位排序（點欄位標頭切換排序鍵），方便使用者自己依 DTE 或 OI 重新排

### 錯誤訊息必須分情況顯示，不能三種失敗共用同一句空話（實測發現的缺漏，補上）

實際畫面測試發現：抓取失敗時，畫面只顯示固定字串「抓取過程發生錯誤，部分資料可能不完整」，不管後端 `result[:status]`／`result[:errors]` 實際內容是什麼都顯示同一句，使用者看不出是哪種失敗、不知道下一步該做什麼。這違反第5節「不靜默回傳看起來完整但實際殘缺的表格」的精神——錯誤要講清楚到使用者知道接下來該做什麼，不只是「顯示有錯誤」。

前端必須讀取後端實際回傳的 `result[:status]`，至少分四種情況顯示不同訊息，不能共用同一句：

| `result[:status]` | 畫面應顯示 |
|---|---|
| 未登入 Barchart（登入偵測失敗） | 明確提示「請先登入 Barchart 後重試」，不是通用錯誤句 |
| **CDP 連線預檢失敗**（見第3節核心原則第1點的 (b) 層，**這個檢查要在 controller 送出 job 前就先擋下來，不是等 job 跑到一半才報錯**） | 明確提示「CDP 未連線，請確認 Windows 端 Chrome 已以 `--remote-debugging-port=9222` 啟動。若電腦曾經睡眠/喚醒，這通常是 WSL2 的 `/mnt/c/` 掛載失效造成的，請在 Windows PowerShell 執行 `wsl --shutdown` 後等待 WSL2 重新啟動，再重試一次。」**這句 sleep/wake 提示是通用建議，不是「確診後才顯示」——controller 端的 `cdp_online?` 預檢沒辦法判斷這次離線是不是真的因為 `/mnt/c/` I/O error（除非額外 shell 出去檢查掛載狀態，這樣會把「OS 層級問題不適合從 Rails 內部處理」這個原則越界擴大），所以不管這次離線的真正原因是什麼，這句提示都固定顯示。**這個訊息要幾乎立即顯示（預檢失敗不需要等 scraper 真正啟動），不能讓使用者等上好幾秒才看到** |
| `partial_error`（session 中途過期，可能是 Options Prices 或 V&G 任一層斷線） | 顯示 `result[:errors]` 裡實際的 `expired_at_expiration` 內容，並標明是哪一層斷的，例如「Volatility & Greeks 頁面在抓取到 {到期日} 時過期，已抓到的部分可能不完整，請重新查詢」——**這個到期日字串跟斷線層級必須是後端實際回傳的值，不能是前端寫死的固定句子** |
| `invalid_strike`（**不是** partial，屬於主動中止） | 顯示紅色 inline 訊息（不跳轉頁面、不等 job）：「Strike {n} 不在 {symbol} 的履約價範圍（實際範圍 ${min}–${max}，現價 ${spot}），請重新輸入」——來源：Controller-layer 快速路徑（有快照時毫秒內回傳）或 Stage 1 後驗證（首次查詢無快照時由 scraper 計算）；兩條路徑都**不排 job**，scraper 路徑的 chain_snapshot 仍落地 DB。 |
| 其他未分類例外（程式 bug 等） | 跟前三種區分開，至少要讓使用者看得出這跟「忘記登入」「CDP 沒連上」「抓到一半斷線」都不是同一種情況 |

驗收時要實際觸發這四種情況各看一次畫面，不是只看 code 有沒有寫對應分支。**CDP 連線預檢失敗這一項特別要計時驗證**：從點擊查詢到畫面顯示這個錯誤訊息，應該在 1-2 秒內，不是 13 秒（13 秒是 job 真正跑到 scraper 內部才失敗的時間，預檢應該比這個快得多）。

### 配色：直接沿用三維度儀表板（Technical/Fundamental/Options Flow）既有樣式，不要另外設計新色票

**這點很重要，請先讀檔再寫樣式，不要憑印象或重新設計一套配色：**

1. 先找出三維度儀表板（`composite_signal_service` 對應的前端，含 `divergence_flag` 色塊：`confirm_bull` 綠色確認區塊、`warning`／`caution` 橘黃警示色塊）目前的 Phlex/CSS 檔案在哪裡，把實際用到的顏色變數、class、或 inline 樣式值讀出來。
2. LEAPS 這個新頁面**直接複用同一組顏色變數/CSS class**（卡片底色、邊框、字體顏色、綠/橘黃/紅的語義色），不要重新定義一套新的色碼。
   - 流動性分級（充足／普通／偏低）沿用三維度儀表板既有的「偏多／中性／偏空」或「confirm／warning／caution」同一組顏色語義對應，充足對應偏多那組顏色，偏低對應警示那組顏色。
   - Options Flow 面板的看多/看空/中性判斷，同樣直接套用既有 `divergence_flag` 用的綠/橘黃/紅，不要另外發明新的顏色語義。
3. 如果三維度儀表板的樣式是寫在共用的 CSS（例如共用的 partial、stylesheet、或 Tailwind class 組合），這個新頁面應該直接 `import`／複用該檔案或共用 component，不要複製貼上一份新的，避免之後兩邊顏色又走偏。
4. 表格 hover 效果與奇數列底色（已實測調整確認，寫死具體值，不要再用「偏紫色調」這種模糊描述）：
   - 奇數列底色：灰色系 `bg-gray-50/50`（不是紫色，之前一輪改動誤把這個也換成紫色，已修正回灰色）
   - 滑鼠 hover 底色：紫色系，比預設的 `purple-50`/`purple-100` 再深一級，用 `hover:bg-purple-200`（如果套用後實測還是太淺看不出差異，下一級是 `hover:bg-purple-300`，但要注意太深會蓋掉文字可讀性，改完務必實際看畫面確認，不要只看 class 名稱猜對不對）
   - 這兩個顏色是獨立的兩件事：奇數列底色跟 hover 底色不能共用同一個顏色系統，前者灰色、後者紫色，不要混在一起改
5. 視覺風格可參考既有 `iv-skew-dashboard` skill 的卡片設計（半圓 gauge 那部分不需要套用在這個表格型頁面，只取卡片/配色的概念）。

---

## 排程

不需要每日自動排程，使用者觸發查詢時才抓取最新資料。同一 symbol 短時間內（**30 分鐘內**）已抓過可直接讀 DB，避免重複打 Barchart。

### 🆕 設計修正記錄（2026-07-04）：fresh window 由 5 分鐘延長為 30 分鐘

**使用者已明確要求把 fresh 判斷從 5 分鐘延長到 30 分鐘，但多個 session 後實作仍回報「fresh = 5 分鐘內」，未真正改到。** 根因研判：本規格多處寫死「5 分鐘」，新 session 重讀規格後以規格為準，把口頭修改覆蓋回去；且程式端 5 分鐘可能散落多處（model `fresh` scope、`fetch_leaps` cache 判斷、controller `fresh_data_exists?`、`Rails.cache` `expires_in` 如 `leaps_last_errors_*` 等），改一處漏其他處。本節是這個數值的**唯一權威定義**，本文件其他地方出現的「5 分鐘」若屬歷史驗證記錄則維持原文（記錄的是當時事實），若屬規範描述一律以本節為準：

1. **fresh window = 30 分鐘**（`scraped_at >= 30.minutes.ago`）。
2. **單一定義來源**：程式內建立一個常數（例如 `LeapsOptionChainSnapshot::FRESH_WINDOW = 30.minutes`），model `fresh` scope、`BarchartScraperService#fetch_leaps`、controller `fresh_data_exists?`、以及所有相關 `Rails.cache` `expires_in` 全部引用這個常數，**全 codebase 不允許再出現第二個寫死的 `5.minutes`／`300`／`30.minutes` 字面值**（測試檔用 `FRESH_WINDOW` 加減運算表達邊界，不寫死數字）。
3. **修復回報必附證據，不接受口頭「已改」**（本項已有連續多 session 回報未真改的前科）：
   - (a) `grep -rn "5\.minutes\|expires_in.*300" app/ lib/` 輸出，證明沒有殘留舊值；
   - (b) 邊界單元測試：`travel_to` 凍結時間，`scraped_at` 29 分鐘前 → cache hit（`persist_leaps` 不執行、不排 job）；31 分鐘前 → cache miss（重新抓取）；
   - (c) 核心情境實測：同一 symbol 查詢後，間隔 >5 分鐘、<30 分鐘再查一次，Rails log 證明第二次走 cache、沒有觸發 scraper——這一條正是「5 分鐘舊行為」與「30 分鐘新行為」的鑑別區間，只在 5 分鐘內重查是驗不出差異的。

---

## 執行方式（請務必分階段進行，每階段做完跟使用者確認再繼續）

> 階段 A／B／C／D／C.5／C.5b／G／F／E 的交付記錄與驗證證據，見 `leaps-call-recommendation-history.md` 第 2 節。

- **階段 H（✅ 2026-07-04 已交付結案，驗收證據見 history 第 3 節）**：`intrinsic_value`／`extrinsic_value` 衍生欄位

  **背景**：使用者手動評估 NVTS LEAPS（2027-01 與 2028-01 兩條鏈）時，發現「外在價值」與「外在佔比」是深 ITM LEAPS 篩選裡比單看 Delta 更能反映「付了多少保險費」的指標（尤其在 IV 破百的標的上，同一履約價在 197 DTE 外在佔比 33%、拉到 568 DTE 變 52%，直接改變了履約價的優劣排序）。目前這兩個數字每次都要人工從 Mid/現價心算，本階段把它落地成 DB 欄位＋排行表顯示欄。

  **公式（唯一定義處，其他章節引用這裡，不要在別處重抄一份）**：

  ```
  mid             = (bid + ask) / 2        # 等同 Barchart 頁面的 Mid 欄；DB 沒有 mid 欄位，由 bid/ask 計算
  intrinsic_value = max(0, underlying_price - strike)          # option_type = call
  intrinsic_value = max(0, strike - underlying_price)          # option_type = put（本功能只抓 call，但公式必須依 option_type 分支，表結構保留 put 是為了未來 PMCC 共用，不要寫死 call 公式埋地雷）
  extrinsic_value = mid - intrinsic_value
  ```

  **⚠️ 權利金基準明確規定為 Mid，不是 Latest（`last_price`）**：Latest 是最後成交價，LEAPS 深 ITM 檔位成交稀疏，Latest 可能是數小時甚至數天前的陳舊價格；Mid = (bid+ask)/2 才貼近當下實際進場要付的權利金。這個選擇是本階段的核心規格，不是實作細節，實作時不得擅自改用 `last_price` 或其他價格欄位。

  **實作位置與範圍**：
  1. Migration：`leaps_option_chain_snapshots` 加 `intrinsic_value`、`extrinsic_value` 兩欄（`decimal`，precision/scale 跟同表既有的 `bid`/`ask` 報價欄位一致，允許 null——bid/ask 任一缺值時存 null，不要存 0 假裝有值）。**只加這兩欄**，「外在佔比」不落地（純比例，display 層由 `extrinsic_value / mid` 算出，決定性可重現，存了反而多一個要跟著同步的欄位）。
  2. 計算層：**放在 Ruby 的 `persist_leaps`（bulk insert 前對每筆 row 計算），不動 Python scraper**。理由：這是純算術衍生欄位，輸入（bid/ask/underlying_price/strike/option_type）全部已在抓取結果裡，放 Ruby 層代表 (a) `leaps_scraper.py` 零改動，不需要重跑 Playwright DOM 驗證那一整套流程；(b) 公式跟 `LeapsRankingService` 同在 Ruby 端，未來改公式只動一個 repo 一種語言。
  3. 舊資料 backfill：寫一個一次性 rake task（或 migration 內 `update_all` 等價 SQL）把既有 rows 依同一公式補值；bid/ask 為 null 的舊 rows 維持 null。5 分鐘 cache 機制代表舊資料很快會被覆蓋，但「排行表某些列有值、某些列空白」這種不一致畫面連短暫出現都不應該。
  4. 排行表新增「內在價值／外在價值／外在佔比」三個顯示欄（見第 6 節表格輸出的 Phase H 註記）；`time_value_pct` 改讀已存的 `extrinsic_value`，移除排行層的重複計算（見第 6 節計算流程步驟 3 的 Phase H 調整）。
  5. 推薦分析理由文字**本階段不強制**加入外在佔比（既有 Time Value% 已在理由裡），若順手加上則沿用同一 DB 欄位，不得另算。

  **路由與前端範圍說明**（對照本規格「路由與前端」一節的既有要求）：本階段**沒有新路由、沒有新頁面**，只在既有 `/leaps` 排行表加顯示欄，導覽列不需變動——這是有意識確認過的「不適用」，不是漏掉。

  **測試要求**：
  1. 單元測試至少覆蓋：深 ITM call（intrinsic > 0）、OTM call（intrinsic = 0、extrinsic = mid）、bid/ask 任一為 null（兩欄皆存 null）、put 分支公式（即使目前抓取層不會產生 put rows，公式分支要有測試釘住，防止未來 PMCC 接上時才發現寫死 call）。
  2. display 層外在佔比：mid > 0 正常計算、mid = 0 或欄位 null 顯示「—」。
  3. **request spec（必交付，不是事後補）**：走完整 HTTP 路徑（route → controller → service）驗證回應頁面包含新欄位且數值正確——本專案已發生過「兩個 service 單元測試 38/38 全過、controller 串接處從未被 request 過、使用者手動一按就炸 ArgumentError」的前例，單元測試通過不能替代這條。
  4. **核心情境 E2E（結案前置條件，凌駕以上所有測試數字）**：實際跑一次**最基本、不帶任何選填參數**的查詢（例如 NVTS 或 NOK，不帶 user_strike），確認排行表每一列的內在/外在價值/外在佔比都有值且合理。只測帶 user_strike 的情境不算數。
  5. **人工已知值對照**——⚠️ 分成兩層，不要混用：
     - **fixture 層（釘公式）**：使用者 2026-07-03 提供的 NVTS 截圖數值寫成單元測試 fixture——2028-01-21 鏈、spot 14.46：strike 5（bid 10.70/ask 11.30 → Mid 11.00 → 內在 9.46、外在 1.54、佔比 14%）、strike 10（bid 8.70/ask 9.95 → Mid 9.325 → 內在 4.46、外在 4.87、佔比 52%）。這組數字是歷史快照，**只用於測試,不要拿去對 live 抓取的輸出**——live 的 spot/bid/ask 早就變了,對不上是正常的,對上了反而有鬼。
     - **live 層（驗 E2E）**：核心情境 E2E 跑完後,從**當次**抓到的資料任取兩筆,用當次的 bid/ask/spot **手算**內在/外在/佔比,跟頁面顯示值比對。一致才算通過（容許四捨五入位數差異）,對不上就是公式或欄位接錯,不是「差不多就好」。回報需附上手算過程與頁面數值的對照。

- **階段 I（✅ 2026-07-05 已交付結案，驗收證據見 history 第 3 節）**：頁面匯出 PNG／PDF

  **需求**：LEAPS 推薦頁面**右上角**新增兩個按鈕「匯出 PNG」「匯出 PDF」，把當前頁面**完整內容**（包含排行表、推薦分析、user_strike 結果等所有已渲染區塊，不是只有視窗可見範圍）輸出成檔案下載。

  **架構決定（實作前先讀，不得擅自改走後端方案）**：
  1. **純前端 client-side 實作，零後端變動**——不新增 route、controller、service。理由：(a) 專案的 Playwright/CDP 是 Barchart 爬蟲專用基礎設施，不得拿來截自己的頁面，避免匯出功能與爬蟲耦合（scraper 掛掉時連匯出都不能用是不合理的）；(b) 符合本專案「Tailwind CDN + 原生 JS + 事件委派」約束。
  2. 函式庫**vendor 本地檔載入，不用 CDN**（⚠️ 2026-07-04 修正：原文寫「CDN 載入對齊 Tailwind CDN 模式」是基於過時的專案狀態——專案已改用 `tailwindcss-rails` 本地編譯，不再有 Tailwind CDN。修正後的規格：把函式庫的 UMD build 下載到專案的 vendor JS 目錄（依專案現行 asset 管線的慣例位置），檔名含版本號釘死版本，例如 `html2canvas-1.4.1.min.js`、`jspdf-2.5.2.umd.min.js`，commit 進 repo）。理由：匯出功能不因外部 CDN 斷線/被擋而失效；版本釘死可重現。PNG 用 `html2canvas`（或 `html-to-image`，實作者擇一後在交付說明裡寫明選擇理由），選定後**兩個匯出共用同一個渲染路徑**。PDF 用 `jsPDF`。
  3. **PDF 一律採「先轉 PNG、再把圖嵌入 PDF」**，不用 jsPDF 文字 API 重排版面。理由：頁面含中文，jsPDF 文字模式需要另外嵌 CJK 字型檔（檔案肥大且易出豆腐字），圖片嵌入完全繞開字型問題，且保證 PNG 與 PDF 兩種輸出畫面一致。PDF 頁面尺寸依圖片長寬比自訂（單頁長條式即可，不強制切 A4 分頁；若實作者選擇分頁，切點不得腰斬表格列）。

  **UI 規格**：
  1. 按鈕位置在頁面**右上角**（與查詢表單同一行右對齊，或其上方右對齊），沿用頁面既有深色主題樣式，兩顆按鈕：「匯出 PNG」「匯出 PDF」。
  2. 事件綁定走專案既有的**事件委派**模式，不要 inline `onclick`。
  3. 匯出範圍是內容根容器（整個 LEAPS 頁面的 wrapper div），**按鈕本身要從輸出畫面排除**（截圖時暫時隱藏或用函式庫的 filter/ignore 選項），導覽列可一併排除。
  4. 檔名格式：`leaps_{symbol}_{YYYYMMDD_HHmm}.png` / `.pdf`（例如 `leaps_NVTS_20260704_2130.pdf`），symbol 取當前查詢的 ticker；尚未查詢、頁面沒有資料時按鈕停用（disabled），不是匯出一張空頁。
  5. 匯出進行中按鈕顯示處理中狀態並防止重複點擊（大表格 rasterize 可能需要數秒）。

  **已知風險（實作時要實際驗證，不是寫了就當沒事）**：html2canvas 對部分 CSS（oklch 色彩函式、某些 Tailwind 效果）支援不完整，可能出現顏色跑掉或區塊缺失；深色背景要確認有被畫進輸出（不是透明底配黑字）。如果選用的函式庫在本頁面渲染有明顯瑕疵，換另一個函式庫重試，兩者都不行才回頭討論方案——不要交付一個「有輸出但畫面破損」的結果。

  **路由與前端範圍說明**：本階段沒有新路由（純前端），入口就是頁面右上角按鈕本身——這是有意識確認過的「不適用」，不是漏掉。

  **測試要求**：
  1. 因為零後端變動，**不需要**新的 request spec（對照本規格既有規則：那條管的是「新 service 接進 controller」，本階段沒有這件事）。
  2. **核心情境 E2E（結案前置條件）**：實際查詢一個 symbol（不帶 user_strike），等頁面渲染完成後分別點兩顆按鈕，**打開下載的 PNG 和 PDF 檔案逐一檢查**：(a) 內容完整——排行表每一列、推薦分析區塊都在，長頁面沒有被腰斬；(b) 深色主題背景正確、中文沒有變豆腐字或亂碼；(c) 檔名符合規格。「檔案有下載下來」不等於「內容正確」，必須真的打開看過並在回報附上輸出檔或其截圖，這是本專案一貫的「有結果≠結果正確」驗收原則。
  3. 邊界情境：頁面無資料時按鈕為 disabled；匯出進行中重複點擊不會觸發第二次匯出。

每一步都要以實際讀到的 DOM／資料為準，不要假設或猜測欄位名稱與資料格式。

---

## 驗收標準 Checklist

> 已完成的全部驗收項目與證據（含 fresh window／Phase H／Phase I），見 `leaps-call-recommendation-history.md` 第 3 節。

## 待辦（歸檔後仍未關閉）

- [ ] **Phase H live 層對照補驗**：2026-07-05 的 live 對照跑在休市期間（7/3 國慶補假＋週末），報價凍結、鑑別力不足。美股開盤後（台灣時間 2026-07-06 週一約 21:30 後）重查一次 NVTS，從當次抓到的資料任取一筆，用當次 bid/ask/spot 手算內在/外在/佔比，與頁面顯示值比對並附手算過程。一致後 fresh window／Phase H／Phase I 三項才算真正全部結案。

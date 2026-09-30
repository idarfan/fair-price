# LEAPS 垂直價差試算卡 — 修正規格（leaps-vertical-fix.md）

## 修改動機

現有卡片的數學計算正確，但**會誤導使用者的交易決策**。以下問題依對決策的影響程度排序：

| # | 問題 | 會誤導什麼 | 修正理由 |
|---|---|---|---|
| P2 | 只能算「到期損益」 | 使用者輸入股價 200，看到 +$5,470，會以為「今天漲到 200 就能賺這麼多」。實際上 SC 240 此時還有大量時間價值，提前平倉的獲利遠低於此。這會直接導致錯誤的獲利了結判斷。 | 垂直價差最常見的決策是「漲了要不要提前平倉」，這個問題只有指定日的平倉損益能回答。用報價時的 mid 反推 IV，不需要新增資料源。 |
| P1 | 保守成交價沒有連動其他指標 | 最大獲利、兩平點、報酬比都用中間價計算。LEAPS 的買賣價差很寬，實際成交通常偏向保守價，所以報酬比會被高估（本例 2.09 vs 1.84），兩平點會被低估（145.30 vs 149.35）。 | 讓使用者看到最壞情況下的成交數字，再決定進場的限價。 |
| P3 | 建議 Δ 0.30，卻允許選 Δ 0.50 而且沒有提示 | 介面說法與實際選擇互相矛盾，使用者不知道自己已經偏離了建議配置：成本較低，但封頂也較早。 | 偏離時提示即可，不強制，保留使用者的選擇權。 |
| P4 | 底部只寫「請用價差單」 | Firstrade App 沒有組合單。使用者若單腳下單，順序一旦錯誤（平倉時先賣 LC），就會暫時持有**裸賣買權**，面臨無上限的風險。 | 補上網頁版的路徑和單腳下單的正確順序。 |
| P5 | 平倉也會吃買賣價差 | 提前平倉時，要以 bid 賣出 LC、以 ask 買回 SC。以本例兩腳的價差寬度計算，一來一回約損失 $400/口，但只用 mid 算的平倉損益看不到這筆成本。 | 平倉損益同樣提供 mid 和保守兩個基準。 |
| P6 | 固定 1 口、不計費用 | 金額只是單口的數字。Firstrade 雖然零佣金，但仍會代收監管費：ORF 買賣雙向按口收，SEC fee 只對賣出收。 | 標準公式本身就含口數，兩平點也應計入費用。費率寫在設定檔，不寫死。 |
| P7 | BS 假設沒有揭露 | 對不配息的股票，美式 call 的價值等於歐式，BS 可以直接用；但遇到配息股，SC 可能在除息前被提前指派，BS 也會高估 call 的價值。另外，股價和期權報價若不在同一時點（例如盤後），反推出的 IV 會失真。 | 加入 q（股息率）、報價時間同步檢查，以及配息警示。 |
| P8 | 到期損益假設「現金結算」 | 若到期時股價落在兩個履約價之間，LC 會被自動履約，變成必須付款買進 100 股（本例需 $10,000/口），而 SC 還有盤後變成價內的風險。卡片上的到期損益並沒有提示這一點。 | 加上「到期前平倉」的警示。 |
| P9 | IV 固定是 sticky-strike 假設 | 股價大幅變動後，各履約價的 IV 會跟著 skew 和整體 IV 水位移動，方向因標的而異，理論平倉值因此有誤差。 | 不建 IV 曲面模型（沒有資料源）。改為在介面上揭露這個假設，並讓使用者自行加減 IV 做情境測試。 |

**計算依據**（公式皆為業界標準）
- 淨成本 = 買入腳價格 − 賣出腳價格
- 最大獲利 = 寬度 − 淨成本；最大虧損 = 淨成本；兩平 = 低履約價 + 淨成本
- 檢核式：最大獲利 + 最大虧損 = 寬度
- 金額 = 每股 × 100 × 口數
- 到期前的理論損益：用 BS 分別計算兩腳價值（業界稱為 T+0 曲線）
- 參考來源：
  - https://ryanoconnellfinance.com/calculators/bull-call-spread-calculator/
  - https://app.certfuel.com/series7/learn/options/options-taxation-and-calculations/spread-profit-and-loss
  - https://help.en-US.firstrade.com/article/134-does-firstrade-pass-regulatory-transaction-fees-to-its-customers
  - https://tastytrade.com/learn/trading-products/options/short-call-vertical-spread/

## 執行狀態表

| 階段 | 內容 | 狀態 | 審查 | 驗證證據 |
|---|---|---|---|---|
| S0 | 定位檔案、盤點資料欄位 | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S0-r1.md） | 路徑表 7 個路徑 `test -f` 全部 exit 0（Barchart IV 填「無」）；`config/leaps_vertical.yml` 載入為 `{risk_free_rate: 0.04, fee_per_contract_leg: 0.02, iv_bounds: {min: 0.005, max: 10}}`；capybara 3.40.0／selenium-webdriver 4.41.0 安裝，暫存 smoke system spec 1 example 0 failures；`bin/rubocop` 0 offenses；`bundle exec rspec` 1236 passed（測試庫 fairprice_test） |
| S1 | 計算核心：中間價／保守價雙基準 | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S1-r1.md） | 新增 `LeapsVerticalSpreadService::Metrics`（dual／call）與 `::Config`；`rspec metrics_spec.rb config_spec.rb` 14 examples 0 failures exit 0（FX-1 雙基準六項指標、檢核式 1／2 口、no_profit_room、S1-b）；`bin/rubocop` 0 offenses；全套 1250 examples 0 failures。尚未接進 controller／畫面（S3 接上並交付 request spec） |
| S2 | 計算核心：指定日平倉理論損益（BS） | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S2-r1.md） | 新增 `LeapsVerticalSpreadService::BlackScholes`、`::CloseOut`；`rspec close_out_spec.rb` 16 examples 0 failures exit 0；FX-1 反推 IV LC 60.92%／SC 57.29%，重新定價 77.0000／31.7000；S=200 報價日平倉 +1,578.20（保守 +768.20）、ΔIV+10 → +984.13、到期日 +5,470.00（保守 +4,660.00）；LC mid 50 → 「無法反推 IV，平倉損益不可用」；`bin/rubocop` 0 offenses；全套 1266 examples 0 failures。尚未接進 controller／畫面（S3） |
| S3 | UI：雙基準顯示＋平倉日輸入 | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S3-r1.md） | system spec `spec/system/leaps_vertical_spread_spec.rb` 5 examples 0 failures（FX-1 五卡 mid／保守、平倉日＝到期日文字相等、報價日 < 5,470、2 口 $9,060.00、stale_quote 警示、常駐提示）；component／request／payoff spec 與 Vitest 13 例通過；全套 1298 examples 0 failures、rubocop 0、typecheck／lint／vitest exit 0。真實頁面 SHOP：改前 `~/fairprice-review/evidence/leaps-vertical-fix-S3-before.png`、改後 `…-S3-after.png`；預估 200 →「平倉理論損益 +$1,605.17（保守 +$795.17）｜到期損益 +$5,469.92（+120.75%）」；口數 2 → 淨成本 $9,060.00、最大虧損 $9,060.08 |
| S4 | UI：Δ 偏離提示＋底部下單說明 | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S4-r1.md） | system spec 8 examples 0 failures（S4 新增 3 例：預設 260、選 240 出現「目前 Δ 0.50，偏離建議值 0.30」、選 260／280 不出現、底部說明逐字相等）；component spec 34 例（含沒有 Δ 不提示）；全套 1302 examples 0 failures、rubocop 0。真實頁面 SHOP：`~/fairprice-review/evidence/leaps-vertical-fix-S4-after.png`，預設賣出腳 240（Δ 0.50）顯示偏離提示。預設規則沿用既有 `default_short`（`min_by [|Δ−0.30|, strike]`，同分取較低），未改 |
| S5 | 端到端驗收 | ✅ | ✅ PASS r1（verdict-leaps-vertical-fix-S5-r1.md） | `node e2e/leaps_vertical_fix.e2e.mjs` exit 0（PASS）。URL http://localhost:3003/leaps?symbol=SHOP&user_strike=100；截圖 `~/fairprice-review/evidence/s5-loaded.png`、`s5-payoff.png`；證據 `~/fairprice-review/evidence/evidence.json`。快照（LC mid 78.225、SC mid 32.625、1 口、費率 0.02）顯示／重算：淨成本 $4,560.00／4560.00、最大獲利 $9,439.92／9439.92、兩平 $145.60／145.60，差距皆 0。平倉日＝到期日：平倉 +$5,439.92 ＝ 到期 +$5,439.92；平倉日＝報價日、預估 200：平倉 +$1,567.45 < 到期 +$5,439.92。輪詢：無報價輪詢，快照後進度請求 0、區塊重取 0。全套：rspec 1302 examples 0 failures、vitest 69 passed、typecheck／lint exit 0 |

狀態：⬜ 未開始／🔄 進行中／✅ 驗證通過。

**狀態表更新規則**
- 每個階段驗證一通過，就立即 patch 本表。證據欄填寫：驗證指令＋輸出摘要，或截圖路徑。
- 接續的 session 只讀本表和 🔄 階段的章節。

## 通則（Loop）

1. **每階段的流程**：實作 → 執行本階段驗證 → 審查官檢查 → 全部通過才標 ✅ → 進入下一階段。**任何一項驗證沒過，禁止進入下一階段。**
2. **規格來源**：本檔以 repo 內版本為唯一真實來源。修改一律用 patch，不整檔重寫。
3. **Barchart 資料限制**：Barchart 資料只能用 Playwright/CDP 解析 DOM 取得。**禁止呼叫任何 Barchart API 或內部 API。**
4. **不改爬蟲**：本次修正不得改動爬蟲。S0 若發現缺少欄位，停下來回報，不得自行補抓。
5. **不新增依賴**：不新增 gem、資料表、路由。
   - 例外（2026-09-30 使用者裁示）：為了 S3、S4 的 system spec，在 `:test` group 加裝 `capybara`、`selenium-webdriver`（Rails 預設組合，driver 用 headless Chrome），於 S0 安裝。
6. **Request spec 要求**：計算若放在 Ruby service 並接進 controller，必須同時交付 request spec，覆蓋完整 HTTP 路徑（route → service）。
7. **數值規則**
   - 金額、價格、百分比、報酬比：一律四捨五入到小數點後 2 位。
   - 測試比對容差：±0.005。
   - T = 日曆天數 ÷ 365。
8. **參數集中管理**：r、q 預設值、每口費用，全部放在 S0 確認的設定檔中，不得寫死在程式碼裡。

## 背景

### 現有行為：已驗算正確，不得改變
以 SHOP 報價為例（LC 100 mid 77.00、SC 240 mid 31.70、寬度 140）：

| 指標 | 數值 |
|---|---|
| 淨成本 | 4,530 |
| 最大獲利 | 9,470 |
| 最大虧損 | 4,530 |
| 損益兩平 | 145.30 |
| 風險報酬比 | 1 : 2.09 |
| 到期股價 200 的損益 | +5,470（+120.75%） |

（2026-09-30 使用者裁示：上表數字在費用 0 時成立。卡片接上 `fee_per_contract_leg` 0.02 後，最大虧損、最大獲利、到期損益會差幾分錢，屬 P6 的預期變動。）

### 待修問題
P1～P9 見頂部「修改動機」。

## 共用測試資料 FX-1

- 報價日 2026-09-30；到期日 2028-12-15；現價 S₀ = 150.00；r 從設定檔讀取（測試用 0.04）。
- LC 100：bid 74.95／ask 79.05（mid 77.00）
- SC 240：bid 29.70／ask 33.70（mid 31.70）
- 保守淨成本 = LC ask − SC bid = 49.35
- 口數 1；每口每腳費用 0（例外：S1-b 用 0.05）；股息率 q = 0
- 股價與期權的報價時間相同

---

## S0 定位與盤點

**要做的事**
1. 用 `grep -rn "LEAPS Vertical Spread" app/ lib/` 和 `grep -rn "為什麼建議" app/` 找出相關檔案，填入下方路徑表（用 patch 寫回本檔）。
   - **命中多個檔案時**：從 `bin/rails routes` 找出實際渲染這張卡片的 controller → view/component 呼叫鏈，只採用鏈上的檔案；其他命中的檔案列入證據欄，標註為「未使用」。
   - **呼叫鏈仍無法唯一確定時**：停下來回報，不得自行挑選。
2. 確認前端拿得到以下欄位：兩腳的 bid、ask、mid、Δ；現價 S₀；報價時間；到期日。
3. 確認 Δ 0.30 這個常數定義在哪裡。
4. 確認 repo 既有的測試機制（system spec／JS 測試）。
5. 確認參數設定檔的路徑：有既有的就沿用；沒有就新建 `config/leaps_vertical.yml`，內容包含 `risk_free_rate`、`fee_per_contract_leg`、`iv_bounds`。
6. 確認以下兩項資料是否已存在於 repo（只盤點，不新增資料源）：
   - 股息資料（例如公允價值模組使用的 Finnhub 資料）
   - Barchart 頁面上是否已抓取各履約價的 IV 欄位
7. 確認股價報價時間和期權報價時間是否都能取得。
8. 確認頁面是否有報價輪詢或自動更新機制，並記下停用方式（S5 會用到）。

**路徑表**

| 項目 | 路徑 |
|---|---|
| 卡片元件 | app/components/leaps_recommendations/vertical_spread_section.rb |
| 計算邏輯（Ruby／JS） | app/services/leaps_vertical_spread_service.rb |
| Δ 建議常數 | app/services/leaps_vertical_spread_service.rb |
| 參數設定檔 | config/leaps_vertical.yml |
| 股息資料來源（沒有則填「無」） | app/models/fundamental.rb |
| Barchart IV 欄位（沒有則填「無」） | 無 |
| 路由與 controller | app/controllers/leaps_recommendations_controller.rb |
| 既有測試 | spec/services/leaps_vertical_spread_service_spec.rb |

**S0 盤點結果（2026-09-30，BASE fbac2db）**
- 呼叫鏈：`GET /leaps/vertical_spread` → `LeapsRecommendationsController#vertical_spread` → `LeapsVerticalSpreadService#call` → `LeapsRecommendations::VerticalSpreadSection`（Phlex，伺服器渲染）；到期損益走同一路由 `payoff=1` → `LeapsVerticalSpreadService::Payoff` → `VerticalSpreadPayoff`。前端 `app/frontend/behaviors/leapsVerticalSpread.ts` 只搬 HTML，不做計算。`grep "LEAPS Vertical Spread"` 只命中一個檔案；`/bcvs`（BullCallSpreadsController）是另一個工具，未使用。
- 兩腳 bid／ask／last／delta、履約價、到期日：有（`LeapsSpreadCache::QUOTE_FIELDS`）；mid 由 service 的 `priced` 算出。
- 現價 S₀：有，`leaps_spread_quotes.underlying_price`（與期權同一次爬取）。
- Δ 常數：`LeapsVerticalSpreadService::TARGET_DELTA`（service 第 9 行）；另有寫死文字「為什麼建議 Δ 0.30」在 section 與 `explanation.rb`。既有 `default_short` 同分時已取較低履約價（`min_by [|Δ−0.30|, strike]`，BigDecimal 無浮點誤差）。
- 參數設定檔：repo 無既有設定（`config/valuation.yml` 屬公允價值模組），新建 `config/leaps_vertical.yml`。使用者裁示：`risk_free_rate` 0.04；`fee_per_contract_leg` 0.02（Firstrade 官方說明：ORF 自 2026-07-01 起每口 $0.02、買賣雙向；SEC fee 依賣出金額計、每口約幾美分，忽略不計）；`iv_bounds` 0.005～10。
- 股息：`fundamentals.dividend_annual`（Barchart 前瞻年股息，每股金額），可算 q = 股息 ÷ S₀。**沒有除息日資料**（Finnhub `dividendPerShareTTM` 只在 StockDataService 即時取用、未存）。
- Barchart IV：爬蟲 `leaps_spread_chain_scraper.py` 有輸出 `iv`，但 `QUOTE_FIELDS` 不含 iv、`leaps_spread_quotes` 無 iv 欄位 → service 拿不到，填「無」。
- 報價時間：只有爬取時間 `scraped_at`（股價與期權同一次爬取），**沒有交易所的股價／期權成交時間**。
- 輪詢：只有載入期間每秒查進度（`setInterval`，載入完成即停），沒有報價自動更新，S5 不需停用。
- 測試機制：RSpec（service／component／request spec）、Vitest（`leapsVerticalSpread.test.ts`）、Playwright e2e（`e2e/leaps_vertical_spread.e2e.mjs`）。原本沒有 system spec（無 Capybara）；依使用者裁示於 S0 加裝 capybara＋selenium-webdriver，S3、S4 照原文寫 system spec。其他既有測試：`spec/services/leaps_vertical_spread_service/{payoff,format}_spec.rb`、`spec/services/leaps_vertical_spread_explanation_spec.rb`、`spec/requests/leaps_vertical_spread_spec.rb`、`spec/components/leaps_recommendations/vertical_spread_section_spec.rb`。

**驗證**
- 路徑表每一格恰好填一個路徑（或填「無」），且每個路徑都通過 `test -f <path>`（exit 0）。
- 欄位盤點結果寫入證據欄。
- 只要缺任何一個欄位 → 狀態標 🔄 並停止，向使用者回報。

## S1 雙基準計算（P1）

**要做的事**
- 用同一組函式，分別以兩種淨成本計算全部指標：
  - **mid 基準**：LC mid − SC mid
  - **保守基準**：LC ask − SC bid
- 需要計算的指標：淨成本、最大獲利、最大虧損、兩平點、報酬比、到期損益（金額與 %）。

**邊界情況**
- 保守淨成本 ≥ 寬度時：最大獲利以 ≤ 0 呈現，並回傳警示旗標 `no_profit_room`。

**驗證**（單元測試，FX-1，到期股價 200）

| 指標 | mid | 保守 |
|---|---|---|
| 淨成本 | 4,530.00 | 4,935.00 |
| 最大獲利 | 9,470.00 | 9,065.00 |
| 最大虧損 | 4,530.00 | 4,935.00 |
| 兩平 | 145.30 | 149.35 |
| 報酬比 | 1 : 2.09 | 1 : 1.84 |
| 到期損益 | +5,470.00（+120.75%） | +5,065.00（+102.63%） |

- 邊界測試：LC ask = 160、SC bid = 10 → 回傳 `no_profit_room = true`。
- 檢核式：費用為 0 時，兩種基準都要滿足「最大獲利 + 最大虧損 = 140 × 100 × 口數」。

**S1-b 口數與費用**
- 計算規則：
  - 金額 = 每股 × 100 × 口數
  - 開倉費用 = 費率 × 2 腳 × 口數；平倉費用相同
  - 最大虧損 = 淨成本金額 + 開倉費用（假設到期作廢、不需平倉）
  - 最大獲利 = 金額 − 開倉費用 − 平倉費用
  - 兩平 = 低履約價 + 淨成本 + 來回費用 ÷ (100 × 口數)
- 驗證（FX-1，改為 2 口、費率 0.05，mid 基準）：

  | 指標 | 預期值 |
  |---|---|
  | 淨成本 | 9,060.00 |
  | 最大虧損 | 9,060.20 |
  | 最大獲利 | 18,939.60 |
  | 兩平 | 145.30 |
- 測試指令 exit 0。

## S2 指定日平倉理論損益（P2）

**要做的事**
1. **反推 IV**：用 Black-Scholes（歐式，q 依第 4 點）和報價日的兩腳 mid，各自反推 IV。
   - 演算法：二分法，容差 1e-6。
   - 搜尋範圍：讀設定檔 `iv_bounds`，預設 0.5%～1000%。
2. **計算損益**：
   - 輸入：股價 S、平倉日 t（報價日 ≤ t ≤ 到期日）、IV 調整量 ΔIV（預設 0，兩腳同步加減，單位為百分點）
   - 兩腳 IV = 反推值 + ΔIV，下限 0.5%
   - 平倉價值 = V(LC) − V(SC)
   - 平倉損益 = (平倉價值 − mid 淨成本) × 100 × 口數 − 來回費用
   - **V 的定義**：剩餘時間 τ = (到期日 − t) ÷ 365。
     - τ > 0 時，V 採 BS 計算。
     - τ ≤ 0 時，**不得呼叫 BS**，V 直接取內在價值 max(S − K, 0)，避免 σ√τ = 0 造成 NaN 或 Infinity。
3. **反推失敗的處理**：當 mid 低於理論下限（S₀·e^(−qT) − K·e^(−rT)）或高於 S₀ 時，依序處理：
   1. 若 S0 盤點到有 Barchart IV 欄位，改用該腿的 Barchart IV。
   2. 若沒有，回傳錯誤，不得輸出 NaN。
4. **股息**：BS 使用連續股息率 q。
   - 若 S0 盤點到有股息資料，就用它計算 q。
   - 若沒有，q 取 0，並回傳旗標 `dividend_unknown`。
   - 若到期前有除息日，且在指定股價下 SC 為價內，回傳旗標 `early_assignment_risk`。
     （2026-09-30 使用者裁示：repo 沒有除息日資料，改判定為「年股息 > 0、SC 在指定股價下為價內、平倉日到到期日至少 90 天」。）
5. **報價時間同步**：股價和期權的報價時間相差超過 15 分鐘時，回傳旗標 `stale_quote`。
   （2026-09-30 使用者裁示：repo 只有爬取時間，改為比對「現價所屬到期日 chain 的 `scraped_at`」與「選中到期日 chain 的 `scraped_at`」。）
6. **保守平倉**：
   - 兩腳的半價差 h = (ask − bid) ÷ 2，沿用報價時的數值。
   - 保守平倉價值 = (BS(LC) − h_LC) − (BS(SC) + h_SC)，下限為 0。
   - 保守平倉損益 = (保守平倉價值 − 保守淨成本) × 100 × 口數 − 來回費用。

**驗證**（單元測試，FX-1）
- 在 S = 150、t = 報價日，用反推出的 IV 重新定價，兩腳都要等於 mid（誤差 ±0.01）。
- t = 到期日時的平倉損益：

  | S | 預期損益 |
  |---|---|
  | 90 | −4,530.00 |
  | 145.30 | 0.00 |
  | 200 | +5,470.00 |
  | 300 | +9,470.00 |

- S = 200、t = 報價日時：0 < 平倉損益 < 5,470.00（嚴格不等式）。
- 反推失敗測試：LC mid 改為 50，且沒有 Barchart IV → 回傳錯誤。
- τ = 0 測試：t = 到期日時，輸出不含 NaN 或 Infinity，並且與上表數值一致。
- ΔIV 測試：S = 200、t = 報價日時，ΔIV = +10 算出的平倉損益 < ΔIV = 0 的平倉損益（本例 S 高於兩履約價中點，淨 Vega 為負）。
- 保守平倉測試：S = 200、t = 到期日時，h_LC = 2.05、h_SC = 2.00，保守平倉價值 = (100 − 2.05) − (0 + 2.00) = 95.95，保守平倉損益 = (95.95 − 49.35) × 100 = +4,660.00。
- 旗標測試：
  - 兩個 chain 的 `scraped_at` 相差 16 分鐘 → `stale_quote = true`；相差 14 分鐘 → `false`。
  - 年股息 1.00、平倉日 = 報價日：S = 250 → `early_assignment_risk = true`；S = 200 → `false`；年股息 0、S = 250 → `false`。
- 測試指令 exit 0。

## S3 UI 雙基準與平倉日（P1、P2）

**要做的事**
1. **五張指標卡**（淨成本、最大獲利、最大虧損、兩平、報酬比）：主值顯示 mid 基準，第二行顯示「保守 $X」，樣式沿用現有「保守成交 $4,935.00」那一行。
2. **`no_profit_room` 為 true 時**：在最大獲利卡顯示「保守成交下無獲利空間」。
3. **平倉日輸入欄**：在「到期日預估股價」旁新增日期欄位。
   - 預設值：報價日
   - 可選範圍：最早報價日，最晚到期日
4. **損益輸出列**：`→ 平倉理論損益 +$X（保守 +$Y）｜到期損益 +$X（+Y%）`
5. **ⓘ 說明文字**：「理論值：以報價時兩腳中間價反推 IV，並假設各履約價的 IV 維持不變。股價大幅變動時 IV skew 會移動，實際平倉價可能與理論值有偏差，可用 IV 調整欄做情境測試。實際成交以買賣價為準。」
5-b. **IV 調整欄**：放在平倉日旁，數字輸入，單位百分點，預設 0，範圍 −50～+50。
6. **IV 顯示**：兩腳下拉選單旁加上小字 `IV xx.x%`。
7. **反推 IV 失敗時**：顯示「無法反推 IV，平倉損益不可用」，其他欄位照常運作。
8. **口數輸入欄**：預設 1，只接受正整數。所有金額都隨口數連動。
10. **旗標對應的警示文字**（固定文字）：

    | 旗標 | 警示文字 |
    |---|---|
    | `stale_quote` | 股價與期權報價時間不一致，IV 與平倉損益可能失真 |
    | `dividend_unknown` | 未取得股息資料，以無股息計算 |
    | `early_assignment_risk` | 賣出腳為價內且標的有配息，到期前可能在除息前被提前指派 |

11. **常駐提示**（放在到期損益旁）：「到期時若股價介於兩履約價之間，買入腳會自動履約、需付款買股；建議到期前平倉」

**驗證**（system spec 注入 FX-1，斷言 DOM 文字）
- 五張卡同時出現 S1 表格中 mid 和保守的數值。
- 預估股價 200、平倉日 = 到期日 → 平倉損益文字等於到期損益文字。
- 預估股價 200、平倉日 = 報價日 → 平倉損益數值 < 5,470。
- 口數改為 2 → 淨成本卡顯示 $9,060.00。
- 注入 `stale_quote` 旗標 → 出現對應的警示文字。
- 常駐提示文字完全等於第 11 點的固定文字。
- 測試指令 exit 0。

## S4 Δ 提示與下單說明（P3、P4）

**要做的事**
1. **預設 SC**：選擇 |Δ − 0.30| 最小的履約價；若差距相同（容差 1e-9 內，避免浮點誤差），取較低的履約價。
2. **偏離提示**：當選中的 SC 滿足 |Δ − 0.30| > 0.05 時，在 SC 下拉選單下方顯示：`目前 Δ {x.xx}，偏離建議值 0.30`。
3. **底部說明**改為下列固定文字：

   > 需 Firstrade 選擇權 Level 3。價差單請用 Firstrade 網頁版一次成交兩腳；若只能單腳下單：建倉先買入 LC 再賣出 SC，平倉先買回 SC 再賣出 LC，避免出現裸賣買權。最大獲利要到到期日才完整實現。

**驗證**（system spec）
- 在 FX-1 加入 SC 候選 200（Δ 0.62）、260（Δ 0.31）、280（Δ 0.29）：
  - 預設應選中 260。
  - 改選 240（Δ 0.50）時，出現提示文字 `目前 Δ 0.50，偏離建議值 0.30`。
  - 選 260 或 280 時，不出現提示。
- 底部說明文字完全等於上方固定文字。
- 測試指令 exit 0。

## S5 端到端驗收

**核心用例**：真實頁面、代號 SHOP、所有欄位不帶任何選填參數（最基本、最常用的情境）。

**防止報價跳動造成誤判**
- 若頁面有定時輪詢或即時更新報價，腳本必須先停用它（沿用 S0 盤點到的機制，例如停止計時器或攔截更新請求），並把停用方式記錄在證據欄。
- 所有 DOM 值必須在**同一次** `page.evaluate` 中一次讀出，形成一份快照；重算只能使用這份快照。
- **禁止用重試來掩蓋不一致。**

**驗證**（Playwright 腳本）
1. 記錄實際導航到的 URL，並截圖（截圖路徑填入證據欄）。
2. 用快照中兩腳的 mid，以 S1 的公式重算淨成本、最大獲利、兩平點，與快照中的顯示值比對，差距 ≤ 0.01。
3. 平倉日設為到期日時，平倉損益等於到期損益；設為報價日且預估股價 200 時，平倉損益小於到期損益。
4. 全部測試套件執行，exit 0。

**證據要求**：URL、截圖、DOM 讀值和重算值的對照表，三者都要填入證據欄，缺一不得標 ✅。

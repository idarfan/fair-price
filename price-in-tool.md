# price-in — Price-In 反推工具（FairPrice 功能規格）

版本 v1 ｜ 建立日 2026-09-07 ｜ 交付對象：Claude Code
取代先前的 `pricein-charts.md`（Python 版本作廢，不要參考）

---

## 執行狀態表

> Claude Code 每完成一階段驗證即以 patch 更新本表。接續 session 只讀本表 ＋ 進行中階段章節。

| 階段 | 名稱 | 狀態 | 驗證指令 | 最後更新 |
|---|---|---|---|---|
| S0 | 路徑勘查與規格對齊 | ✅ 已驗證通過 | 見 §S0 | 2026-09-07 |
| S1 | 計算 Service + 定值測試 | ✅ 已驗證通過 | `bundle exec rspec spec/services/price_in/` | 2026-09-07（33 examples, 0 failures）|
| S2 | Form Object 與參數驗證 | 🟡 進行中 | `bundle exec rspec spec/forms/price_in/` | — |
| S2B | 股票代號與現價帶入 | ⬜ 未開始 | 見 §S2B | — |
| S3 | 路由・控制器・sidebar 入口 | ⬜ 未開始 | `bundle exec rspec spec/requests/price_in_spec.rb` | — |
| S4 | 輸入介面（含欄位用途說明卡） | ⬜ 未開始 | 見 §S4 | — |
| S5 | 圖 A 渲染與判讀說明 | ⬜ 未開始 | 見 §S5 | — |
| S6 | 圖 B 渲染與判讀說明 | ⬜ 未開始 | 見 §S6 | — |
| S7 | driver.js 導覽 | ⬜ 未開始 | 見 §S7 | — |
| S8 | PNG 匯出與歸屬稽核 | ⬜ 未開始 | 見 §S8 | — |
| S9 | 端到端驗收 | ⬜ 未開始 | 見 §S9 | — |

狀態值：⬜ 未開始 / 🟡 進行中 / ✅ 已驗證通過 / ❌ 驗證失敗

**鐵則：上一階段驗證未通過，禁止進入下一階段。**

---

## 1. 功能定位

### 1.1 這個工具在回答什麼問題

散戶最常講的一句廢話是「這檔已經 price in 太多了」。這句話不可討論，因為它沒有數字。

本工具把這句話拆成三個可填寫的欄位 —— **哪一年的 EPS、給幾倍、從什麼價格買進** —— 然後用兩張圖把結論畫出來。填完之後，「貴」或「便宜」變成一個可以被反駁的具體主張。

### 1.2 兩張圖的分工

| | 圖 A：反推所需 EPS | 圖 B：買入價報酬對照 |
|---|---|---|
| **標題** | `{price} 美元，需要多少盈利？` | `同樣兌現盈利，報酬為什麼不同？` |
| **副標** | `Fixed share price. Different earnings requirements.` | `Same earnings. Different entry prices.` |
| **固定什麼** | 股價 | 未來 EPS |
| **變動什麼** | 本益比假設 | 本益比假設 × 買入價 |
| **回答什麼** | 這個價格正在要求公司賺到多少？ | 同樣的結果兌現，買貴和買便宜差多少？ |
| **打掉什麼誤解** | 「便宜／貴」是感覺 → 變成一個可查核的 EPS 門檻 | 「公司成長 = 我會賺」→ 買入價決定你分到多少 |
| **關鍵讀法** | 圓點落在色帶左側 = 現有預測撐得住 | 同一列兩條長條的落差 = 買入價的代價 |

**兩張圖必須成組使用。** 圖 A 回答「多少盈利」，圖 B 回答「多少價格」，缺一邊就會落回單點估值的錯覺。頁面需同時呈現，不可拆成兩個獨立路由。

### 1.3 非目標（不要自行擴充）

- **EPS 與倍數全部手動輸入**，不接資料庫既有預測表、不做預測推薦
- 股價可由股票代號自動帶入現價（見 §S2B），但帶入後仍可手動覆寫；除股價外不自動帶入任何欄位
- 不建新資料表；情境狀態一律走 query string，讓 URL 可分享
- 不做兩張圖以外的圖型
- 不做多標的批次比較

---

## 2. 技術定位

- Rails + Phlex + PostgreSQL（FairPrice 既有 stack）
- 圖表：Chart.js 4.4.1（**沿用 layout 既有的 CDN 載入**）＋ `chartjs-plugin-annotation`（同樣走 CDN）
- 導覽：driver.js 1.6.0（layout 已全域載入，vendor 本地檔）
- 匯出：html-to-image + jsPDF（layout 已全域載入的 vendor 本地檔）**，不是 html2canvas**
- **前端套件載入方式以 repo 現況為準**：v1 原訂「一律 self-host，禁 CDN」，但 S0 勘查發現
  Chart.js 本體在 `app/views/layouts/application.html.erb:24` 就是 CDN 載入。若只把
  annotation plugin 單獨 vendor，會變成同一套圖表庫一半 CDN、一半本地，版本對不上時
  極難追查。2026-09-07 決議：**plugin 跟隨 Chart.js 走 CDN**，理由是本工具使用頻度不高，
  不值得為它動全站 layout 並回歸驗證三維度判斷／IV 等既有頁面

---

## S0 — 路徑勘查與規格對齊

**目標**：本規格不得憑檔名猜測 repo 結構。動工前先勘查，再把實際路徑 patch 回本節。

**必須勘查並回報的項目**

1. `config/routes.rb` 中既有的估值／工具類命名空間為何？（工具需掛在既有命名空間下，**禁止**開一個孤立的頂層路由）
2. sidebar 元件的實際檔案路徑為何？新入口要加在哪個區塊、哪個位置？
3. Chart.js 目前的載入方式與版本（`app/javascript/` 下的實際路徑）
4. driver.js 是否已在 repo 中；若有，實際路徑為何
5. `/home/idarfan/csp/option-basics-lesson8.html`（**絕對路徑，repo 外**）中 driver.js 的 tooltip CSS 區塊 —— 讀出來，供 S7 移植
6. **既有的即時報價來源**為何？（Finnhub、Barchart sidecar、或其他）實際的 service 類別名稱、方法簽章、回傳格式、快取機制。**禁止為本功能新增第三方 API 憑證或新 gem**，一律沿用既有管道
7. 既有是否已有可重用的 JSON 報價 endpoint？若有，直接沿用，不要另開一個
8. **`Rails.cache` 在各環境的實際 store 設定**（`config/environments/*.rb`）。若 development 或 test 為 `:null_store`，S2B 的快取測試會假通過，必須在測試中顯式指定 `:memory_store`

**路徑表**（S0 完成後由 Claude Code patch 為實際值）

| 用途 | 規劃路徑 | 實際路徑（S0 已填） |
|---|---|---|
| 控制器 | `app/controllers/price_in_controller.rb` | 同左 |
| 路由 | 掛於既有估值命名空間下 | **改為頂層 `get "price_in"`**，見下方差異說明 |
| 頁面元件 | `app/components/price_in/page.rb` | `app/components/price_in/page_component.rb`（repo 慣例為 `*_component.rb`）|
| 表單元件 | `app/components/price_in/input_form.rb` | `app/components/price_in/input_form_component.rb` |
| 說明卡元件 | `app/components/price_in/field_help_card.rb` | `app/components/price_in/field_help_card_component.rb` |
| 圖 A 元件 | `app/components/price_in/chart_a_card.rb` | `app/components/price_in/chart_a_card_component.rb` |
| 圖 B 元件 | `app/components/price_in/chart_b_card.rb` | `app/components/price_in/chart_b_card_component.rb` |
| 計算 Service | `app/services/price_in/required_eps_calculator.rb` | 同左 ✅ S1 已建 |
| 計算 Service | `app/services/price_in/entry_return_calculator.rb` | 同左 ✅ S1 已建 |
| 格式化 | （規格未列） | `app/services/price_in/formatter.rb` ✅ S1 已建，集中負號／小數位規則 |
| Form Object | `app/forms/price_in/scenario_form.rb` | 同左（`app/forms/` 為新目錄）|
| 稽核 Service | `app/services/price_in/attribution_auditor.rb` | 同左 |
| 報價 Service | `app/services/price_in/quote_fetcher.rb` | 同左，內部呼叫既有 `FinnhubService` |
| 報價 endpoint | 同命名空間下 `#quote`（JSON） | `get "price_in/quote"` → `PriceInController#quote` |
| JS | `app/javascript/controllers/price_in_ticker_controller.js` | `app/frontend/behaviors/priceInTicker.ts`（repo 用 Vite + behaviors，無 Stimulus）|
| 文案 locale | `config/locales/price_in.zh-TW.yml` | 同左 |
| JS | `app/javascript/controllers/price_in_chart_controller.js` | `app/frontend/behaviors/priceInCharts.ts` |
| JS | `app/javascript/controllers/price_in_tour_controller.js` | `app/frontend/behaviors/priceInTour.ts` |

**S0 勘查結果與規格的差異（依 S0「以 repo 慣例為準並說明差異」處理）**

1. **沒有估值命名空間。** `config/routes.rb` 中 margin／leaps／bpus／bcvs／option_profit_calc
   等同類工具全部是頂層 `get "xxx", to: "xxx#index"`。本工具比照辦理，不另開命名空間。
2. **Chart.js 走 CDN**（layout:24，v4.4.1）。見 §2 已改。
3. **`chartjs-plugin-annotation` 原本不存在**，S5 需在 layout 補一行 CDN。
4. **driver.js 1.6.0 已全域載入**（layout:41-42），S7 直接使用，不需再引入。
5. **匯出堆疊是 html-to-image + jsPDF**（layout:27/39），非規格所寫的 html2canvas。S8 沿用既有。
6. **報價管道**：`FinnhubService#quote(symbol)` → Finnhub `/quote`（`c` 為現價、`t` 為時間戳）；
   `FinnhubService#basic_metrics(symbol)` → `/stock/metric?metric=all`（含 `peTTM`、`epsTTM`）。
   不新增 gem 或憑證。
7. **無可直接沿用的 JSON 報價 endpoint**：既有的都綁在各自工具的參數與回傳格式上，
   因此本工具自建 `#quote`，但內部一律走上述既有 service。
8. **`Rails.cache` 各環境**：development `:memory_store`、test **`:null_store`**、
   production 未設定（走預設）。⚠️ S2B 的快取測試必須顯式指定 `:memory_store`，
   否則在 test 環境會假通過。

**驗證**
```bash
grep -n "namespace\|resources\|get " config/routes.rb | head -60
ls -la app/components/ | head -40
test -f /home/idarfan/csp/option-basics-lesson8.html && echo "lesson8 可讀"
```

**通過條件**：三條指令均有輸出；上表「實際路徑」欄已 patch 完成；若規劃路徑與 repo 慣例不符，以 repo 慣例為準並在回報中說明差異。

---

## S1 — 計算 Service + 定值測試

**目標**：全部公式落地，純 Ruby，不碰 view。

### 公式

圖 A：
```
required_eps = price / multiple
```

圖 B：
```
target_price  = eps * multiple
total_return  = target_price / entry_price - 1
annualized    = (1 + total_return) ** (1.0 / years) - 1
```

折現（選用）：
```
discounted_target = (eps * multiple) / (1 + rate) ** years
implied_rate      = (target_future / price_today) ** (1.0 / years) - 1
```

參考倍數（圖 A 的本益比卡片用）：
```
implied_multiple(price, eps) = price / eps
```
`eps` 為 0 或 nil 時回傳 nil，不得拋例外。

### 格式化規則

| 用途 | 規則 | 範例 |
|---|---|---|
| EPS／股價 | 2 位小數，前綴 `$` | `$7.45` |
| 報酬率 | 1 位小數 + `%`，正數強制 `+` | `+62.7%`、`-0.4%` |
| 負號 | ASCII hyphen-minus（U+002D），**禁 U+2212** | `-39.6%` |

### 必測定值（容差 1e-6）

圖 A，price = 223.55：

| multiple | required_eps | 顯示 |
|---|---|---|
| 25 | 8.942000 | `$8.94` |
| 30 | 7.451667 | `$7.45` |
| 35 | 6.387143 | `$6.39` |

圖 B，eps = 11.02（**測試專用常數，寫死在 spec 檔內；不得改由設定檔預設值提供**）：

| multiple | target_price | entry 223.55 | 顯示 | entry 365 | 顯示 |
|---|---|---|---|---|---|
| 20 | 220.40 | -0.0140908 | `-1.4%` | -0.3961644 | `-39.6%` |
| 25 | 275.50 | +0.2323865 | `+23.2%` | -0.2452055 | `-24.5%` |
| 33 | 363.66 | +0.6267502 | `+62.7%` | -0.0036712 | `-0.4%` |

> **2026-09-07 勘誤**：33 倍那一列原寫 `+0.6267949`，與同列的 `target_price = 363.66`
> 自相矛盾（`363.66 / 223.55 - 1 = 0.6267502`；`0.6267949` 反推出來的 entry 是 223.5439，
> 不是 223.55）。顯示值 `+62.7%` 兩者相同，差異在第 5 位小數之後。已改為與 target 一致的值。

折現：`discounted_target(15.04, 31, 0.13, 2)` ≈ 365.24（容差 0.5）；`implied_rate(466.24, 365, 2)` ≈ 0.1302079（容差 1e-4）。

> **2026-09-07 勘誤**：`implied_rate` 原寫 ≈ 0.13003，但 `(466.24 / 365) ** 0.5 - 1 = 0.1302079`，
> 差距 1.8e-4 已超出同一行給的 1e-4 容差。0.13003 是拿 `discounted_target` 未捨入的結果
> （365.16）反推來的 —— 規格在這一格混用了捨入前與捨入後的 `price_today`。已改為以
> 明寫輸入 365 計算的值，並另加一個「兩者互為逆運算」的測試把關係鎖住。

隱含倍數，price = 223.55：

| eps | implied_multiple | 顯示 |
|---|---|---|
| 6.60 | 33.8712 | `33.9 倍` |
| 7.24 | 30.8771 | `30.9 倍` |
| 11.02 | 20.2859 | `20.3 倍` |
| 0 或 nil | nil | `—` |

隱含倍數一律顯示 1 位小數。

**驗證**
```bash
bundle exec rspec spec/services/price_in/ --format documentation
grep -rn "ActionView\|Phlex\|render\|helper" app/services/price_in/ && echo "FAIL: service 混入 view 依賴" || echo "service 純度 ok"
```

**通過條件**：spec 全綠且 example 數 ≥ 22；純度檢查印出 `service 純度 ok`。

---

## S2 — Form Object 與參數驗證

**目標**：使用者輸入在進計算之前就被擋下，錯誤訊息說得出「為什麼」。

### 欄位定義

| 欄位 | 型別 | 必填 | 預設 | 驗證 |
|---|---|---|---|---|
| `ticker` | string | ✅ | "MRVL" | 上傳前轉大寫；符合 `\A[A-Z]{1,5}(\.[A-Z])?\z` |
| `price` | decimal | ✅ | 223.55 | > 0，≤ 100000 |
| `price_as_of` | datetime | ❌ | nil | 由報價帶入時寫入；手動改價或改代號時清空 |
| `chart_a_multiples` | array<decimal> | ❌ | [25, 30, 35] | 有填才驗：1–5 個，各 > 0，不重複。**留空套預設值** |
| `fiscal_year_label` | string | ✅ | "FY2028" | 非空 |
| `eps_band_low` | decimal | ❌ | nil | 與 high 同時填或同時空 |
| `eps_band_high` | decimal | ❌ | nil | ≥ low |
| `eps_band_label` | string | ❌ | — | 有 band 時必填 |
| `eps` | decimal | ❌ | 無預設（placeholder 提示格式） | 填了則 > 0；**留空時圖 B 進空狀態，不算錯誤** |
| `chart_b_fiscal_year_label` | string | 條件 | "FY2029" | **僅當 `eps` 有值時必填** |
| `chart_b_multiples` | array<decimal> | 條件 | [20, 25, 33] | 僅當 `eps` 有值時驗證：1–5 個，各 > 0，不重複 |
| `entry_a_price` | decimal | 條件 | 鏡射 `price` | 僅當 `eps` 有值時驗證：> 0 |
| `entry_a_link_price` | boolean | ❌ | true | true 時 `entry_a_price` 恆等於 `price` |
| `entry_b_price` | decimal | 條件 | 365 | 僅當 `eps` 有值時驗證：> 0，≠ `entry_a_price` |
| `holding_years` | decimal | ❌ | nil | > 0，≤ 20 |
| `discount_rate` | decimal | ❌ | nil | 0–1 之間 |
| `discount_years` | decimal | ❌ | nil | 與 rate 同時填或同時空 |
| `attribution_sources` | array<string> | ❌ | [] | 最多 5 項，單項 ≤ 30 字；見 §S8 |

**條件必填的意義**：圖 A 與圖 B 是兩組獨立的輸入。使用者只填圖 A 的欄位就該看到圖 A，圖 B 顯示引導填寫的空狀態。**`eps` 留空絕不可讓整個 Form invalid**，否則圖 A 也會跟著消失。

**`entry_a_label` / `entry_b_label` 不是輸入欄位**，由價格自動組出（`買入基準 $#{price}` / `假設買入價 $#{price}`），價格一變標籤跟著變。理由：寫死的標籤在報價帶入後會與長條對不上，圖例直接說謊。

**`entry_a_price` 預設鏡射 `price`**。`entry_a_link_price` 為 true（預設）時兩者恆等，改任一邊另一邊跟著變；使用者可明確解除連結以比較「現價 vs 我的成本」。理由：兩張圖標榜成組使用，若圖 A 用 300、圖 B 基準還是 223.55，兩張圖在講不同的價格。

**`holding_years` 無預設值**。填了才顯示年化。若 `holding_years` 與 `chart_b_fiscal_year_label` 明顯不一致（例如年度是 FY2031 但年數填 2.5），畫面顯示提示，但不阻擋出圖。理由：年化值錯得很隱蔽，看不出來。

**`fiscal_year_label` 為什麼必填**：`price / multiple` 這個算式裡沒有時間。「FY2028 賺到 7.45」和「FY2031 賺到 7.45」是完全不同的兩件事，前者便宜、後者是災難。缺年度的圖會誤導，因此在 Form 層就擋死，不允許產出。

### 必測負向案例（各需回傳對應錯誤訊息）

1. `price = -1`
2. ~~`chart_a_multiples = []`~~ → **2026-09-07 變更：留空改為套用預設值，不再視為錯誤**
3. `chart_a_multiples = [25, 25]`
4. `chart_a_multiples` 有 6 個元素
5. `fiscal_year_label = ""`
6. `eps_band_low = 8.0, eps_band_high = 7.0`
7. `eps_band_low` 有值但 `eps_band_high` 為空
8. `eps = 11.02` 且 `entry_b_price == entry_a_price`
9. `discount_rate = 1.5`
10. `ticker = ""`
11. `ticker = "TOOLONG1"`（不符格式）
12. `eps = 11.02` 但 `chart_b_fiscal_year_label = ""`
13. `attribution_sources` 有 6 項
14. `attribution_sources` 單項超過 30 字

### 必測正向案例

15. `ticker = "mrvl"` → 正規化為 `MRVL` 且通過驗證
16. **`eps` 留空、圖 A 欄位齊全 → `valid? == true`**（這是空狀態，不是錯誤）
17. `entry_a_link_price = true` 時改 `price` → `entry_a_price` 同步變動

**驗證**
```bash
bundle exec rspec spec/forms/price_in/ --format documentation
```

**通過條件**：負向案例全數回傳 `valid? == false` 且錯誤訊息非空；正向案例通過。**第 16 案是重點 —— `eps` 留空必須是有效狀態。**

> **2026-09-07 規格變更（案例 2）**：`chart_a_multiples` 留空原本回 invalid。
> 改為套用預設值，理由是輸入框本身也改成預設留空（只給 placeholder 提示）——
> 預先在欄位裡塞 `25,30,35`，使用者按「帶入現價的本益比」時會變成預設值加上
> 帶入值的一長串，而他從沒打算保留那些預設值。
>
> 「計算器不會收到零個倍數」這個不變式改由預設值保證，而不是由錯誤訊息保證。
> 填了 `0` 或重複值等真正無意義的輸入仍然被擋下。

---

## S2B — 股票代號與現價帶入

**目標**：輸入代號按一下就帶入現價，抓不到也不能卡住使用者。

### 行為規格

- `ticker` 欄位旁置「帶入現價」按鈕
- 點擊 → 打 `#quote` JSON endpoint → 成功則同時寫入：
  - `price`（圖 A）
  - `entry_a_price`（圖 B 的基準買入價）
  - `price_as_of`（報價時間戳，顯示於欄位下方與卡片頁尾）
- **帶入後兩個價格欄位仍可手動修改**。使用者一旦手動改動，`price_as_of` 清空，頁尾改顯示「手動輸入」
- **代號一改動，價格立即標記為失效**：`price_as_of` 清空，價格欄位旁顯示警示「代號已變更，價格尚未更新」，**且圖表頁首與標題暫不重繪**，直到使用者按下「帶入現價」或手動確認價格。理由：頁首寫著 AVGO、標題寫著 223.55 的圖不會報錯也不會測試失敗，就是安靜地輸出一張錯誤的圖，而錯的那張看起來跟對的一模一樣
- 頁面載入時**不自動抓價**，一律由使用者主動觸發。理由：這是估值工具不是報價看板，自動抓價會讓使用者誤以為圖表隨行情更新

### Service 規格

- `PriceIn::QuoteFetcher.call(ticker) -> Result`
- 資料來源沿用 S0 勘查出的既有管道，**禁止新增第三方 API 憑證或新 gem**
- 快取：`Rails.cache`，key `price_in:quote:{TICKER}`，TTL 15 分鐘。**不建新資料表**
- 回傳 `{ ok:, price:, as_of:, error_code: }`
- 錯誤碼至少涵蓋：`not_found`（查無代號）、`upstream_error`（來源掛掉）、`rate_limited`

> **2026-09-07 規格變更：移除 `pe_ttm` / `eps_ttm` / `pe_basis`。**
> v1 要求 `pe_basis` 標明本益比口徑（`gaap` / `non_gaap` / `unknown`），但 S0 勘查確認
> 上游（Finnhub `/stock/metric`）的 `peTTM` **沒有任何欄位說明它用哪一套口徑**，無從判定。
>
> GAAP 與 non-GAAP 的 EPS 常差到倍數等級（non-GAAP 扣掉股權薪酬、併購無形資產攤銷等，
> 幾乎永遠較高，本益比因而較低）。預設標的 MRVL 正是併購攤銷極大的重災區。一個口徑
> 不明的本益比，放在一張專門用來拆穿含糊估值的圖旁邊，本身就是這張圖要打掉的東西。
>
> 改採：**隱含本益比一律由使用者自己填的 EPS 算出**（`implied_multiple(price, eps)`，
> 已於 S1 實作），與 §1.3「EPS 與倍數全部手動輸入」一致。報價 endpoint 只負責帶入股價。

### 失敗處理

| 情況 | 行為 |
|---|---|
| 查無代號 | 欄位下方顯示「查無此代號」，價格欄位維持原值不動 |
| 來源失敗／逾時 | 顯示「暫時取不到報價，請手動輸入」，價格欄位維持原值 |
| 任何失敗 | **圖表照常以現有價格重繪，絕不阻擋出圖** |

### 必測案例

1. 合法代號、上游回傳正常 → `ok: true`，price 正確
2. 相同代號連打兩次 → 第二次命中快取，上游只被呼叫一次。**測試需顯式使用 `:memory_store`**（見 S0 第 8 項）；若在 `:null_store` 下執行，此案會假通過
3. 上游回 404 → `error_code: :not_found`，不拋例外
4. 上游逾時 → `error_code: :upstream_error`，不拋例外
5. endpoint 帶合法代號 → 200 JSON，含 `price` 與 `as_of`
6. endpoint 帶非法代號格式 → 422，body 含錯誤訊息
7. endpoint 上游失敗 → 200 或 503（擇一並固定），body 含 `error_code`，**不可 500**
8. 改變 `ticker` → `price_as_of` 被清空，畫面出現「價格尚未更新」警示
9. 帶入報價成功 → `price` 與 `entry_a_price`（`entry_a_link_price` 為 true 時）同步更新，且兩個 entry label 文字中的金額同步變動

**驗證**
```bash
bundle exec rspec spec/services/price_in/quote_fetcher_spec.rb --format documentation
bundle exec rspec spec/requests/price_in_quote_spec.rb --format documentation
# 確認未偷加憑證或 gem
git diff --stat -- Gemfile Gemfile.lock .env.example | grep . && echo "FAIL: 動到依賴或憑證" || echo "未新增依賴 ok"
# 確認測試未在 null_store 下跑快取案例
grep -rn "memory_store" spec/services/price_in/quote_fetcher_spec.rb \
  || (echo "FAIL: 快取測試未指定 memory_store，可能假通過"; exit 1)
```

**通過條件**：9 個案例全綠；上游一律以 WebMock stub，測試不得打真實網路；依賴檢查與 cache store 檢查均 ok。



**目標**：完整 HTTP 路徑打得通，且使用者找得到入口。

**實作要點**
- 路由掛在 S0 勘查出的既有命名空間下，**禁止孤立頂層路由**
- 控制器只有 `#index`，讀 query string → Form Object → Service → 傳給 Phlex 元件
- 無參數時：`price` 與 `ticker` 使用預設值，`eps`、`eps_band` 留空 → 頁面顯示表單與引導文字，圖表區為空狀態（**不是錯誤狀態**），提示使用者填入 EPS 後即可出圖
- 參數不合法時：回 200、顯示錯誤訊息、圖表區顯示空狀態，**不可 500**
- sidebar 加入入口，位置置於既有工具清單最末

**request spec 必含案例**

1. 無參數 GET → 200，body 含 `$7.45`（圖 A 以預設 price 出圖），圖 B 區為空狀態且**不含**錯誤字樣
2. 帶合法參數 GET（`price=300`）→ 200，body 含 `$12.00`（300/25）
3. 帶 `eps=11.02` → 200，body 含 `+62.7%`
4. 帶非法參數 GET（`price=-1`）→ 200，body 含錯誤訊息，**不含**圖表 canvas id
5. sidebar 元件渲染結果含新入口的 href，且該 href 可被 `Rails.application.routes.recognize_path` 解析

**驗證**
```bash
bundle exec rspec spec/requests/price_in_spec.rb --format documentation
bundle exec rails runner 'puts Rails.application.routes.routes.map{|r| r.path.spec.to_s}.grep(/price_in/)'
```

**通過條件**：5 個案例全綠；路由列印出實際 path。

---

## S4 — 輸入介面（含欄位用途說明卡）

**目標**：使用者看得懂每一個欄位在問什麼、填錯會怎樣。

### 視覺規範（沿用既有「色帶卡片」v3 定稿）

**字級三級制（鐵則，全頁禁止 20px 以下字級）**

| 用途 | 字級 | 字重 |
|---|---|---|
| 內文、表格內容、輸入框、軸刻度、列標籤 | 20px | 400 |
| 卡帶標題、圖表主標 | 22px | 500 |
| 主數字（圖上的 EPS 與報酬率標籤） | 24px | 700 |

**易讀性優先於單頁不捲動，允許整頁垂直捲動。** 不得為了塞進一個畫面而縮字級或改用兩欄擠壓；表單與兩張圖一律單欄由上而下排列。

**容器寬度（兩種寬度都置中，共用同一條垂直軸線）**

| 區塊 | 寬度 | 理由 |
|---|---|---|
| 所有區塊（輸入卡、圖表卡、頁首） | `width: 96%`，`margin-inline: auto` | 使用者指定全版面 |

> **2026-09-07 規格變更**：v1 訂輸入卡 760px、圖表卡 960px，並明文「禁止讓任何區塊
> 鋪滿全寬」，理由是 20px 字級配全寬每行會到 130 字左右、眼睛換行容易跳行。
> 使用者要求改為全版面 96%，取代上述所有寬度限制與該禁令。
>
> 原本的行長顧慮仍然存在，但已由使用者判斷後接受：說明卡內的長句在寬螢幕上
> 每行字數會明顯增加。若日後覺得難讀，改 `PriceIn::PageComponent` 的 `NARROW`
> 與 `WIDE` 兩個常數即可，其餘元件都引用它們，不需逐頁改。

- **畫面上的圖表卡不需固定尺寸**，它只是預覽。成品尺寸一律由 §S8.1 的離屏容器決定，與畫面寬度無關

**色帶卡片結構**

- 圓角 12px；深色標題色帶（22px/500 淺色字 ＋ 24px 3D 圖示）＋ 同色系最淺階卡身 ＋ 同色系中階邊框
- 單側邊框不加圓角；要圓角就四邊都要有邊框
- **卡身內容以「有標頭列的表格」呈現**，不是段落散文。說明卡固定四列，標頭列為 `項目 / 說明`：

| 項目 | 說明 |
|---|---|
| 要填什麼 | … |
| 為什麼要填 | … |
| 怎麼用 | … |
| 注意 | … |

（§S4 各卡片的文案已按此四列撰寫，照搬即可；沒有「注意」內容的卡片可略去該列，但不得改成段落）

- 表格資料列 hover 背景 `#EEEDFE`，`transition: 0.12s`

**色系語意分配**（色帶用深階、卡身用最淺階、邊框用中階）

| 語意 | 用途 | 色帶（深階） | 卡身（最淺階） | 邊框（中階） |
|---|---|---|---|---|
| 綠 | 獲利／公式／基準 | `#3B6D11` | `#EAF3DE` | `#97C459` |
| 橙 | 對照／規範 | `#993C1D` | `#FAECE7` | `#F0997B` |
| 黃 | 決策／警示 | `#854F0B` | `#FAEEDA` | `#EF9F27` |
| 紅 | 虧損／關鍵警語 | `#A32D2D` | `#FCEBEB` | `#F09595` |
| 中性 | 一般文字 | `#5F5E5A` | — | — |

**S0 補充勘查**：repo 若已有色票 partial 或 CSS 變數檔，以 repo 既有色票為準，上表為 fallback；勘查結果 patch 回本表。

**各卡片的色系與 3D 圖示指派**

| 卡片 | 色系 | Fluent Emoji |
|---|---|---|
| 0 股票代號 | 綠 | 🔎 magnifying-glass |
| 1 你要檢驗的價格 | 橙 | 🏷️ label |
| 2 你願意給的本益比 | 黃 | ⚖️ balance-scale |
| 3 對應年度 · 必填 | 紅 | ⏳ hourglass |
| 4 EPS 一致預期區間 | 綠 | 📊 bar-chart |
| 5 假設兌現的 EPS | 綠 | 🎯 direct-hit |
| 6 兩個買入價 | 橙 | 🔀 shuffle |
| 7 持有年數與折現 | 黃 | 📅 calendar |

圖示採 Microsoft Fluent Emoji 3D（MIT），PNG **下載進 repo**，禁 CDN 熱連。

**斷句排版（一句一行）**

所有說明文字 —— 說明卡表格的「說明」欄、判讀說明卡、導覽 tooltip 內容 —— **一個句號結束就換行**，每句自成一行。

- locale 檔中這類文案**存成陣列，一個元素一句**，不存成含多個句號的長字串。理由：在 locale 就切好，比在 view 用 `split("。")` 可靠，也讓譯文與排版的責任分離
- 渲染時每句一個 block 元素，`line-height: 1.6`，句與句之間不額外加段落間距（視覺上是連續的多行，不是多個段落）
- **句號保留在句尾**，不因換行而省略
- 只對全形句號「。」斷行。半形句點「.」不斷行 —— 數字（`223.55`）、網址（`stockanalysis.com`）、縮寫都會用到它
- 問號「？」與驚嘆號「！」比照句號處理
- 單句過長仍會自然折行，這是正常的；斷句規則是「句末必換行」，不是「一句一定只佔一行」

範例（locale 寫法）：

```yaml
zh-TW:
  price_in:
    cards:
      multiples:
        why:
          - 唯一由你決定的變數，是假設不是預測。
          - 填三檔是為了逼自己面對憑什麼給這個倍數。
```

**字體**：Noto Sans TC self-host（禁 Google Fonts 熱連），fallback PingFang TC → Microsoft JhengHei；公式與數字用等寬字體。

**收摺式清單（`<details>` / `<summary>`）**

用於卡片 4 的「去哪裡查這兩個數字？」查詢指引。規範：

- 原生 `<details>` / `<summary>`，不引入第三方 accordion 套件
- 預設**收合**；`summary` 為 20px/500，右側置 `ti-chevron-down` 方向指示，展開時轉 180°
- `summary` 高度 ≥ 44px，整條可點擊
- 展開內容沿用同色系卡身底色，與 `summary` 之間加一條中階色分隔線
- 內部表格沿用 §S4 表格規範（標頭列、20px、hover `#EEEDFE`）
- **網址一律 `<a>` 可點擊、`target="_blank"`、`rel="noopener noreferrer"`**，並以等寬字體顯示
- 網址中的代號**用表單當前 `ticker` 動態代入**（模板 `https://stockanalysis.com/stocks/{ticker_downcase}/forecast/`）。清單中所有網址皆可只換代號，不得放入需要產業分類或公司全名的路徑
- 展開狀態不需記憶，每次載入皆為收合

### 表單分區與說明卡文案

每個欄位群組上方置一張說明卡。以下文案**逐字採用**，不要改寫。

---

**卡片 0 ｜ 股票代號**（色系：綠＝公式/基準）

> **要填什麼**：美股代號，例如 MRVL。填完可按「帶入現價」自動抓當前價格。
>
> **為什麼要填**：代號有兩個用途。一是帶入現價，省得手動查；二是**成為圖表頁首的標題**（`老衲敝人在下我 / MRVL`），匯出的圖一眼就看得出在講哪一檔。
>
> **抓不到怎麼辦**：手動填價格即可，圖表照常產出。這是估值工具，不是報價看板 —— 價格是你要檢驗的假設，不是必須即時的數據。
>
> **注意**：帶入現價後，價格欄位仍可自由修改。一旦手動改動，頁尾的報價時間戳會改成「手動輸入」，避免你把假設價誤當成真實報價發出去。

---

**卡片 1 ｜ 圖 A 輸入 · 你要檢驗的價格**（色系：橙＝對照/規範）

> **要填什麼**：你想檢驗的股價。可以是現價，也可以是你在考慮的任何一個價位。
>
> **為什麼要填**：Price-in 討論的起點永遠是「已經付了多少錢」。這個數字是分子，它決定了整張圖在要求公司交出什麼成績。填現價，你看到的是市場目前的要求；填一個更高的假設價，你看到的是「漲到那裡之後，門檻會變多高」。
>
> **怎麼用**：先填現價看基準，再填一個你心中的目標價，比較兩者的 EPS 門檻差多少。

---

**卡片 2 ｜ 圖 A 輸入 · 你願意給的本益比**（色系：黃＝決策/警示）

**卡身頂部固定顯示「參考倍數」區塊**（在三個輸入框上方），三個數字：

| 標籤 | 來源 | 說明文字（逐字採用） |
|---|---|---|
| 現價隱含倍數（圖 A 年度） | `price / eps_band` 兩端，顯示為區間 | 以你填的預期 EPS 反推 |
| 現價隱含倍數（圖 B 年度） | `price / eps` | 以你填的假設 EPS 反推 |

顯示規則：

- `eps_band` 留空時，圖 A 隱含倍數格顯示 `—`，不顯示錯誤
- `eps` 留空時，圖 B 隱含倍數格顯示 `—`
- 兩個數字皆為**唯讀參考**，**嚴禁自動填入下方的倍數輸入框**

> **2026-09-07 規格變更**：本區塊原有第三個數字「目前 TTM 本益比」，取自 `pe_ttm`
> 並以 `pe_basis` 標註口徑。該欄位已於 §S2B 整組移除（上游無法判定 GAAP／非 GAAP），
> 因此參考倍數只剩兩個由使用者自填 EPS 反推的隱含倍數。卡片 2 的「參考倍數怎麼看」
> 說明文字亦同步改寫。

> | 項目 | 說明 |
> |---|---|
> | 要填什麼 | 1 到 5 個本益比數字。 |
> | 為什麼要填 | 唯一由你決定的變數，是假設不是預測。填三檔是為了逼自己面對憑什麼給這個倍數。 |
> | 怎麼用 | 拿公司的歷史本益比中位數當錨點。要給高於中位數的倍數，你必須說得出理由（能見度改善、成長加速、客戶結構變化）；說不出來就往中位數靠。 |
> | 參考倍數怎麼看 | 兩個隱含倍數的意思是「現價相當於你填的 EPS 的幾倍」。它們不是建議值，只是把你自己填的數字換個角度呈現：如果你願意給的倍數比隱含倍數低，代表你認為現價太貴。 |
> | 注意 | 把倍數當成客觀事實是最常見的錯誤。它是你的出價意願。參考倍數只是對照，不會自動填進輸入框。 |

---

**卡片 3 ｜ 圖 A 輸入 · 對應年度**（色系：紅＝關鍵警語）

> **要填什麼**：這個 EPS 門檻對應的財政年度，例如 FY2028。**必填，不能留空。**
>
> **為什麼必填**：`股價 ÷ 倍數 = 所需 EPS` 這個算式裡**沒有時間**。同樣是 7.45 美元，如果 FY2028 就做到，這個價格很便宜；如果要等到 FY2031，這個價格是災難。年度沒寫清楚，整張圖就失去意義，所以系統不允許產出沒有年度標示的圖。
>
> **怎麼填**：填你打算用來檢驗的那個年度，並且**確認你引用的 EPS 預測也是同一個年度**。兩邊年度對不上，是最常見的 Price-in 誤判來源。

---

**卡片 4 ｜ 圖 A 輸入 · EPS 一致預期區間（選填）**（色系：綠＝公式/基準）

> | 項目 | 說明 |
> |---|---|
> | 要填什麼 | 市場對該年度 EPS 的預測**下緣與上緣**，以及一行來源說明。可以留空。 |
> | 為什麼要填 | 前三個欄位只給你算術結果 —— 這個價格需要多少 EPS。但「需要 7.45」本身不告訴你難不難。填入預測區間後，圖上會出現色帶，你就能直接看出現有預測撐不撐得住你的倍數假設。 |
> | 留空會怎樣 | 圖照常產出，只是變成純算術對照，少了難易度的判斷基準。 |
> | 注意 | 各家調整口徑不同（股票薪酬算不算費用差很多），因此填**區間**而不是單點，並在說明文字裡註明取樣範圍與日期。 |

**本卡片無預設值。** `eps_band` 三個欄位一律留空，由使用者自行查詢填入。理由：預設一組數字會被當成系統提供的權威值，但這個區間的正確性只有填的人能負責。

**卡身下方置一個收摺式清單**，標題「去哪裡查這兩個數字？」，預設收合。展開後內容如下（逐字採用）：

---

**步驟**

1. 先確定你要哪一個財政年度。Marvell 的 FY2028 對應自然年 2027，各家標示方式不同，**一定要看清楚是 fiscal year 還是 calendar year**
2. 找到該年度的 EPS 預測**低標與高標**，不是平均值。色帶要畫的是分歧程度，不是共識點
3. 記下取樣日期與分析師家數，填進說明文字

**免費查得到區間的來源**

| 站點 | 網址（把 `MRVL` 換成你的代號） | 拿得到什麼 |
|---|---|---|
| Stock Analysis | `https://stockanalysis.com/stocks/mrvl/forecast/` | 逐年 EPS 預測、分析師家數。頁面明載採非 GAAP 調整後數字、資料來自 S&P Global |
| ChartMill | `https://www.chartmill.com/stock/quote/MRVL/analyst-ratings` | 逐年 EPS 估值、修正趨勢、涵蓋分析師數 |
| Market Chameleon | `https://marketchameleon.com/Overview/MRVL/` | 最近一季實際值與預期差，用來檢查前一季有沒有大幅偏離 |

三個站都不需註冊或訂閱即可看到年度預測。清單只收免費可讀的來源 —— 付費牆後的資料再準，工具裡放了也是給使用者添堵。

**個別投行的數字去哪找**

投行研報本身要付費。免費管道是財經媒體的轉述，搜尋關鍵字用「代號 + 分析師姓名 + price target」或「代號 + EPS estimate + 年度」，常見會轉述的媒體：TheStreet、CNBC、Investing.com、Finbold、TipRanks。轉述的數字**務必回頭確認三件事**：哪一個財政年度、EPS 口徑（股票薪酬算不算費用）、目標價有沒有折現。

**三個常見的坑**

| 坑 | 後果 | 怎麼避免 |
|---|---|---|
| 拿平均值當區間 | 色帶變成一條線，看不出分歧 | 一定要找 Low / High 欄位 |
| 混用不同口徑 | 下緣是 GAAP、上緣是非 GAAP，區間毫無意義 | 同一來源、同一口徑取兩端 |
| 用過期估值 | 財報後估值會大幅修正，舊數字失效 | 只取最近一次財報後更新的估值，並記下日期 |

---

**卡片 5 ｜ 圖 B 輸入 · 假設兌現的 EPS**（色系：綠）

> | 項目 | 說明 |
> |---|---|
> | 要填什麼 | 你假設公司未來某一年會賺到的每股盈利，以及對應的財政年度。 |
> | 這個數字代表什麼 | 三個限定缺一不可 —— **特定財政年度**（FY2029 對應自然年 2028）、**單一年度**（那一年賺的，不是累計）、**經過調整**（非 GAAP，剔除項目各家不同）。 |
> | 為什麼要填 | 圖 B 的設計是把盈利這個變數**固定住**。固定之後，剩下的差異就全部來自估值倍數和買入價 —— 這正是要證明的東西：公司表現一樣，你的報酬還是可能天差地遠。 |
> | 怎麼用 | 可以填市場一致預期，也可以填某個你認同的樂觀情境。它不需要是「對的預測」，但必須是**你說得出來歷的數字**。誠實標註它是哪一種、哪一年。 |
> | 注意 | 引用某家投行的數字時，務必回頭核對三件事：哪一個財政年度、股票薪酬算不算費用、目標價有沒有折現。三者任一搞錯，整張圖的結論會反過來。 |

**本卡片無預設值。** `eps` 欄位留空，由使用者自行查詢填入。理由同卡片 4：預設一組數字會被當成系統提供的權威值。輸入框以 placeholder 提示格式（例如 `11.02`）即可，**不得預先填入**。

**卡身下方置一個收摺式清單**，標題「這個數字去哪裡查？」，預設收合。展開後內容如下（逐字採用）：

---

**三種來源，可信度不同**

| 來源 | 特性 | 適合什麼情境 |
|---|---|---|
| 市場一致預期 | 多家平均，變動較緩，最容易查 | 想知道「市場目前相信什麼」 |
| 單一投行模型 | 分歧大，可能遠高或遠低於共識 | 想檢驗某個特定的多空論點 |
| 自己推算 | 完全可控，來歷最清楚 | 想檢驗自己的假設而非別人的 |

**免費查一致預期**

| 站點 | 網址（把 `MRVL` 換成你的代號） | 拿得到什麼 |
|---|---|---|
| Stock Analysis | `https://stockanalysis.com/stocks/mrvl/forecast/` | 逐年 EPS 預測。頁面明載採非 GAAP 調整後數字、資料來自 S&P Global |
| ChartMill | `https://www.chartmill.com/stock/quote/MRVL/analyst-ratings` | 逐年 EPS 估值與修正趨勢 |

查到之後記下三件事：**年度標示**（fiscal 還是 calendar）、**口徑**（頁面有沒有說明是否為調整後）、**取樣日期**。

**自己推算的方法**

```
調整後 EPS = 年營收 × 調整後淨利率 ÷ 稀釋在外股數
```

三個輸入的來源：

- **年營收**：一致預期網站有逐年營收預測；或用公司財報電話會議中自己給的目標
- **調整後淨利率**：取最近幾季的實際值，再依你對規模效應的判斷調整。成長期公司通常會擴張，但不要外推得太樂觀
- **稀釋在外股數**：財報中有；注意它會**逐年變動** —— 買回庫藏股會減少、股票薪酬會增加。用當前股數推算三年後的 EPS 是常見錯誤

自己推算的好處是每一個假設都攤在你面前。當有人說你的數字不合理，你能指出到底是營收、利潤率、還是股數的分歧。

**用投行數字時的三個核對點**

| 核對點 | 為什麼重要 |
|---|---|
| 財政年度 | FY2029 和 2029 自然年差一年；FY2030 和 FY2029 的 EPS 可能差三成 |
| 股票薪酬 | 算不算費用，同一家公司的 EPS 可以差 20% 以上 |
| 有沒有折現 | 折現過的目標價，在該價位買入仍可賺到折現率；未折現的才等於把未來全部付光 |

媒體轉述常常漏掉這三項。看到「某投行預估 X 元」，先找原始報告的年度與口徑，找不到就不要用。

---

**卡片 6 ｜ 圖 B 輸入 · 兩個買入價**（色系：橙）

> **要填什麼**：兩個不同的買入價。預設是現價 223.55 與假設價 365。
>
> **為什麼要填兩個**：這是整張圖的核心。同樣的 EPS、同樣的倍數，從不同價格買進，報酬完全不同。填一個價格你只會看到一組數字，填兩個你才會看到**買入價的代價**。
>
> **怎麼填**：一個填你的實際成本或現價（基準），另一個填你想檢驗的價位 —— 例如某個目標價，或你在考慮加碼的價位。
>
> **重要提醒**：如果第二個價格取自某家機構的目標價，務必先確認那個目標價**有沒有折現**。折現過的目標價，在該價位買入仍可賺到折現率本身；未折現的目標價才等於把未來成長提前付光。搞錯這一點，整張圖的結論會反過來。

---

**卡片 7 ｜ 圖 B 輸入 · 持有年數與折現（選填）**（色系：黃）

> **持有年數**：填了之後，每個報酬數字下方會加註年化值。`-1.4%` 和 `+62.7%` 如果都是兩年半的成果，年化後是 `-0.6%` 對 `21%` —— 差距比絕對值更有感。
>
> **折現率與年數**：用來檢驗一個目標價背後的隱含報酬。輸入後系統會算出「在該價格買入、如期兌現」對應的年化報酬。這是判斷一個目標價到底有沒有留下空間給你的直接方法。
>
> **兩者都可留空**，圖照常產出。

---

**驗證**
```bash
bundle exec rspec spec/components/price_in/ --format documentation
curl -s "http://localhost:3003$(bundle exec rails runner 'print Rails.application.routes.routes.map{|r| r.path.spec.to_s.sub("(.:format)","")}.grep(/price_in/).first')" \
  | grep -c "為什麼要填" | xargs -I{} sh -c 'test {} -ge 7 && echo "說明卡 ok: {}" || (echo "FAIL: 說明卡不足 {}"; exit 1)'
# 字級鐵則：不得出現 20px 以下的 font-size
grep -rnE "font-size:\s*(1[0-9]|[0-9])(px|\.[0-9]+px)" app/components/price_in/ app/assets/stylesheets/ \
  && echo "FAIL: 出現 20px 以下字級" || echo "字級鐵則 ok"
# 說明卡須為表格結構，不得為段落
grep -rn "為什麼要填" app/components/price_in/ | grep -qi "<p\|paragraph" \
  && echo "FAIL: 說明卡用段落而非表格" || echo "說明卡結構 ok"
# 參考倍數不得自動填入輸入框
grep -rnE "pe_ttm.*(value=|\.value\s*=)|implied_multiple.*(value=|\.value\s*=)" \
  app/components/price_in/ app/javascript/controllers/price_in_*.js \
  && echo "FAIL: 參考倍數被寫進輸入框" || echo "參考倍數唯讀 ok"
# 收摺清單須為原生 details/summary，且外連需 noopener
curl -s "<S0 實際路徑>" | grep -c "<details" | xargs -I{} sh -c 'test {} -ge 1 && echo "收摺清單 ok" || (echo "FAIL: 無收摺清單"; exit 1)'
curl -s "<S0 實際路徑>" | grep -o 'target="_blank"[^>]*' | grep -qv "noopener" \
  && echo "FAIL: 外連缺 noopener" || echo "外連屬性 ok"
# 一句一行：locale 中不得有含兩個以上句末標點的單一字串
bundle exec rails runner '
  require "yaml"
  bad = []
  walk = ->(node, path) {
    case node
    when Hash  then node.each { |k, v| walk.(v, path + [k]) }
    when Array then node.each_with_index { |v, i| walk.(v, path + [i]) }
    when String then bad << path.join(".") if node.scan(/[。？！]/).size > 1
    end
  }
  walk.(YAML.load_file("config/locales/price_in.zh-TW.yml"), [])
  raise "未斷句的長字串: #{bad.join(", ")}" if bad.any?
  puts "斷句排版 ok"
'
```

**通過條件**：component spec 全綠；頁面 HTML 中「為什麼要填」出現 ≥ 7 次；字級、結構、參考倍數唯讀、收摺清單、外連屬性、斷句排版六項檢查均 ok；人工確認卡片為「深色色帶 ＋ 最淺階卡身 ＋ 中階邊框」三段式，說明內容為有標頭列的表格，每句自成一行，收摺清單內的網址代號會隨表單 `ticker` 變動。

**容器寬度另需 Playwright 量測**（在 1440px 視窗下）：

| 量測對象 | 期望值 |
|---|---|
| 輸入卡實際寬度 | 760px |
| 圖表卡實際寬度 | 960px |
| 兩者中心 x 座標 | 相同（誤差 ≤ 1px） |
| 視窗縮到 800px 時 | 兩者皆為 768px（100% 減去兩側 16px） |

附上四項量測的實際數值，不是「應該是」。

---

## S5 — 圖 A 渲染與判讀說明

**目標**：畫出圖 A，並在圖旁寫清楚怎麼看。

### 圖表規格（Chart.js 橫條）

- `indexAxis: 'y'`，由上而下依 multiple 由大到小排列
- 橫條由 x=0 起，長度 = `required_eps`，填色 `#C5D2DB`，無邊框
- 橫條右端疊一個 scatter 資料集畫實心圓點，色 `#1F5673`，圓點右側標數值（`$8.94`）
- `eps_band` 存在時，用 `chartjs-plugin-annotation` 畫 `box` 型垂直色帶（x 從 low 到 high，貫穿全高），色 `#CDE3D2`，alpha 0.55，**繪製層級在橫條之上**
- x 軸自 0 起，上限取 `max(required_eps) * 1.15` **向上取整到 5 的倍數**（8.94 → 10.28 → 10）。**不可取整到偶數** —— 那會得到 12，刻度變成 0/3/6/9/12，色帶擠到左半邊、圓點的分辨度變差
- 列標籤：`{multiple} 倍`
- 年度標示必須出現在圖標題或圖例列中至少一次
- **字級**：圖主標 22px/500、數值標籤（`$8.94`）24px/700、列標籤與軸刻度 20px。Chart.js 需明確設定 `font.size`，不可沿用預設 12px
- 圖表高度依 20px 字級自然撐開，**不得為了塞進一個畫面壓縮列高**；整頁允許捲動
- 判讀說明卡沿用 §S4 色帶卡片結構（綠色系，圖示 🔍 magnifying-glass-tilted-left）

### 判讀說明卡（置於圖表下方，逐字採用）

**「怎麼看這張圖」**

> **1. 圓點在色帶的哪一側，是這張圖最重要的資訊。**
> 圓點 = 這個倍數所需要的 EPS。色帶 = 市場目前的預測範圍。
> 　· 圓點落在色帶**左側** → 現有預測撐得住這個倍數，門檻已經達到
> 　· 圓點落在色帶**之中** → 需要落在預測區間偏上緣，有機會但不寬裕
> 　· 圓點落在色帶**右側** → 需要盈利超出目前所有預測，這個倍數是額外的樂觀
>
> **2. 長條越長，代表要求越高，不是越好。**
> 一般看長條圖會直覺認為長 = 好。這張圖相反：長條長度是「公司必須賺到的金額」，越長代表門檻越高、越難達成。給的倍數越低，長條越長。
>
> **3. 這張圖不做任何預測。**
> 圖上唯一的計算是 `股價 ÷ 倍數`。倍數是你填的假設，色帶是你引用的第三方預測。這張圖只負責把你的假設攤開，不負責告訴你哪個對。
>
> **4. 換一個價格再看一次。**
> 把股價改成你的目標價重跑，比較兩張圖的門檻差多少 —— 那個差額，就是漲到目標價需要額外 price in 的東西。

**驗證**
```bash
bundle exec rspec spec/components/price_in/chart_a_card_spec.rb
# DOM 值檢查
curl -s "<S0 實際路徑>" | grep -o 'data-chart-a-payload="[^"]*"' | head -1
```

payload JSON 需含：`8.94`、`7.45`、`6.39`、`25`、`30`、`35`、`FY2028`。帶 `eps_band_low=6.60&eps_band_high=7.24` 時另需含 band 的 `6.6` 與 `7.24`；不帶時 payload 中 band 為 null 且圖上無色帶。

**負號檢查須涵蓋三種形式**（payload 在 HTML attribute 中可能被 escape）：
```bash
curl -s "<S0 實際路徑>" | grep -E "−|&#8722;|&minus;" \
  && echo "FAIL: 出現 U+2212 或其 escape 形式" || echo "負號 ok"
```

**通過條件**：spec 全綠；payload 各項全數命中；負號三形式檢查通過；人工開啟頁面（帶 band 參數）確認色帶落在 6.60–7.24、`$6.39` 圓點在色帶左側、x 軸上限為 10。

---

## S6 — 圖 B 渲染與判讀說明

**目標**：畫出圖 B，並在圖旁寫清楚怎麼看。

### 圖表規格（Chart.js 分組橫條）

- 每個 multiple 一組，組內 2 條（entry A 在上、entry B 在下），組間留白 ≥ 組內間距 2 倍
- 橫條由 x=0 起，向正負兩側延伸
- 零軸畫垂直線，色 `#26333C`，線寬 1.5
- entry A 色 `#2E6C8E`，entry B 色 `#B5654A`
- **顏色編碼的是買入價，不是損益方向**。因此這裡刻意**不套用**專案語意色 `#A32D2D`（虧損）／`#3B6D11`（獲利）—— 若套用，同一買入價的三條長條會因正負而變色，讀者會誤以為顏色代表盈虧而非入場價，整張圖的對照邏輯就毀了。此為既有語意色規範的明列例外。
- 數值標籤：長條夠長時置內側（白字），過短時置外側（`#26333C`）
- 左側列標籤：主標 `{multiple} 倍`，下方小字 `對應 ${target_price}`
- `holding_years` 非 null 時，每個數值標籤下方加註年化值，x 軸標題後追加持有期間說明
- 圖例列顯示兩個 entry label；EPS 橫幅顯示 `未來估值時點：統一假設年度調整後 EPS = ${eps}`
- **字級**：圖主標 22px/500、數值標籤（`+62.7%`）24px/700、列標籤與軸刻度 20px。Chart.js 需明確設定 `font.size`
- **最小長條寬度 3px**：`-1.4%`、`-0.4%` 這類接近零的值若按比例畫會細到看不見，須設下限，否則使用者會誤以為該列沒畫出來
- 左側列標籤欄寬 ≥ 90px（20px 字級下「對應 $220.40」才不會擠行）
- 判讀說明卡沿用 §S4 色帶卡片結構（橙色系，圖示 🔀 shuffle）

### 判讀說明卡（置於圖表下方，逐字採用）

**「怎麼看這張圖」**

> **1. 先看同一列的兩條長條，這是這張圖的主角。**
> 同一列代表同樣的估值倍數、同樣的盈利兌現。兩條長條的落差，**完全來自買入價的不同**。
> 以預設值為例，33 倍那一列：從 223.55 買進是 `+62.7%`，從 365 買進是 `-0.4%`。公司做到一模一樣的事，一個賺六成，一個原地踏步。這就是 price-in 的完整證明。
>
> **2. 再看跨列的變化，那是估值倍數的威力。**
> 同一個買入價，20 倍和 33 倍的結果可以差六十個百分點以上。這說明「公司賺多少」只是報酬的一半，「市場願意給幾倍」是另一半。
>
> **3. 兩者是相乘關係，不是相加。**
> 　`總報酬 = (未來 EPS ÷ 現在 EPS) × (未來倍數 ÷ 現在倍數) − 1`
> 盈利成長 50%、倍數收縮 40%，你的報酬是 **−10%**，不是 +10%。這就是高本益比的股票下跌起來特別兇的機制，也是「公司成長了但我沒賺到」的完整解釋。
>
> **4. 負報酬不代表公司變差。**
> 圖上所有情境的盈利假設都相同。出現負數，唯一的原因是買入價太高 —— 買的時候已經把這些成長付掉了。
>
> **5. 別忘了問折現。**
> 如果第二個買入價來自某個機構目標價，先確認它有沒有折現回今天。折現過的目標價，在該價位買入仍可賺到折現率本身；未折現的才等於把未來全部付光。這一點搞錯，圖的結論會反過來。

**驗證**
```bash
bundle exec rspec spec/components/price_in/chart_b_card_spec.rb
curl -s "<S0 實際路徑>?eps=11.02&chart_b_fiscal_year_label=FY2029" \
  | grep -o 'data-chart-b-payload="[^"]*"' | head -1
```

payload JSON 需含：`-1.4`、`23.2`、`62.7`、`-39.6`、`-24.5`、`-0.4`、`220.4`、`275.5`、`363.66`、`FY2029`、`11.02`。

**負號檢查須涵蓋三種形式**：
```bash
curl -s "<S0 實際路徑>?eps=11.02&chart_b_fiscal_year_label=FY2029" \
  | grep -E "−|&#8722;|&minus;" \
  && echo "FAIL: 出現 U+2212 或其 escape 形式" || echo "負號 ok"
```

另需驗證空狀態：不帶 `eps` 時，頁面**不含** `data-chart-b-payload`，且顯示引導文字而非錯誤訊息。

另需驗證年化不一致提示：帶 `eps=11.02&chart_b_fiscal_year_label=FY2031&holding_years=2.5` 時，畫面出現持有年數與年度不符的提示，但**圖表仍正常渲染**。

**通過條件**：spec 全綠；payload 11 項全數命中；負號三形式檢查通過；空狀態與年化提示兩案通過。

---

## S7 — driver.js 導覽

**目標**：第一次使用的人，點一下就知道每個欄位在問什麼、圖怎麼看。

**實作要點**
- tooltip CSS **必須**與 `/home/idarfan/csp/option-basics-lesson8.html`（絕對路徑，repo 外）一致。做法：讀出該檔的 driver.js 樣式區塊，**把資產移植進 repo**，不要用連結或 `@import` 指向 repo 外檔案
- 頁面右上角置「使用導覽」按鈕，手動觸發
- 首次造訪自動觸發一次，記錄於 `localStorage`，之後不再自動彈出
- 導覽分兩段：`輸入導覽`（步驟 1–7）與 `讀圖導覽`（步驟 8–14），可分別觸發
- **錨點不存在時必須自動略過該步，不得中斷或報錯**。圖 B 在 `eps` 留空時不會渲染，步驟 11–13 的錨點（圖 B canvas、倍數列、跨列區域）不在 DOM 裡。實作需在啟動前過濾掉錨點不存在的步驟，並重新編號進度指示
- **`讀圖導覽` 在圖表未渲染時，按鈕標示為「先填入 EPS 才能看讀圖導覽」並停用**（保留可點擊、點擊後捲動到對應輸入欄位，不做灰階 disabled）
- tooltip 內容比照 §S4 斷句規則：一句一行，locale 存成陣列

### 導覽步驟（逐字採用）

| # | 錨點 | 標題 | 內容 |
|---|---|---|---|
| 1 | 頁面標題 | 這個工具在做什麼 | 把「已經 price in 太多了」這句廢話，拆成三個可以填的數字：哪一年的 EPS、給幾倍、從什麼價格買。填完之後，貴或便宜就變成一個可以被反駁的具體主張。 |
| 2 | `price` 欄位 | 你要檢驗的價格 | 填現價，看市場目前在要求什麼；填目標價，看漲到那裡之後門檻會變多高。這是分母的分子，整張圖的起點。 |
| 3 | `chart_a_multiples` | 你的出價意願 | 這是唯一由你決定的變數，是假設不是預測。填三檔是為了逼自己面對「憑什麼給這個倍數」。拿歷史中位數當錨點，要給更高就得說得出理由。 |
| 4 | `fiscal_year_label` | 為什麼這欄不能空 | 股價÷倍數這個算式裡沒有時間。同樣是 7.45 美元，FY2028 做到很便宜，FY2031 才做到是災難。所以系統不允許產出沒有年度的圖。 |
| 5 | `eps_band` 群組 | 難易度的基準線（選填） | 前面算出「需要多少」，這裡告訴你「難不難」。填入市場預測區間，圖上會出現色帶，你就能看出現有預測撐不撐得住你的倍數。留空也能出圖，只是少了判斷基準。 |
| 6 | 圖 B `eps` 欄位 | 把盈利固定住 | 圖 B 的設計是鎖死盈利這個變數。鎖死之後，剩下的差異就全部來自倍數和買入價 —— 這正是要證明的事。 |
| 7 | 兩個買入價欄位 | 這張圖的核心 | 填兩個價格，你才看得到買入價的代價。如果第二個取自機構目標價，先確認它有沒有折現 —— 折現過的目標價，在該價位買入仍可賺到折現率本身。 |
| 8 | 圖 A canvas | 圖 A：這個價格在要求什麼 | 固定股價，變動倍數，反推公司必須賺到多少。圖上唯一的計算是股價除以倍數，不含任何預測。 |
| 9 | 圖 A 色帶 | 圓點在色帶哪一側 | 這是圖 A 最重要的資訊。圓點在色帶左側，現有預測撐得住；落在色帶中，需要偏上緣；落在右側，需要超出目前所有預測。 |
| 10 | 圖 A 最長的橫條 | 長不代表好 | 長條長度是公司必須賺到的金額。越長代表門檻越高、越難達成。倍數給得越低，長條越長。方向和一般長條圖的直覺相反。 |
| 11 | 圖 B canvas | 圖 B：買入價的代價 | 盈利固定，只變買入價和倍數。這張圖回答的是：同樣的結果兌現，買貴和買便宜差多少。 |
| 12 | 圖 B 倍數最高那一列 | 同一列的落差就是答案 | 同樣的盈利、同樣的倍數，只因為買入價不同，一個賺六成，一個原地踏步。公司成長不等於你會賺，這就是完整的證明。 |
| 13 | 圖 B 跨列區域 | 倍數是報酬的另一半 | 同一個買入價，低倍數和高倍數可以差六十個百分點以上。盈利與倍數是相乘關係：盈利成長 50%、倍數收縮 40%，結果是負 10%，不是正 10%。 |
| 14 | 匯出按鈕 | 帶著數字去吵架 | 下次有人說「已經 price in 太多」，把這張圖丟出去，問他：用哪一年的 EPS？什麼口徑？給幾倍？有沒有折現？四項答不出來的，就是在講廢話。 |

**驗證**
```bash
bundle exec rspec spec/components/price_in/tour_spec.rb
# 步驟數與錨點存在性
curl -s "<S0 實際路徑>?eps=11.02&chart_b_fiscal_year_label=FY2029" \
  | grep -o 'data-tour-step="[0-9]*"' | sort -u | wc -l   # 需為 14
# 空狀態下圖 B 相關錨點不存在，導覽須自動略過而非報錯
curl -s "<S0 實際路徑>" | grep -o 'data-tour-step="[0-9]*"' | sort -u | wc -l   # 需為 11
# CSS 移植確認：repo 內必須有本地副本，且不得指向 repo 外絕對路徑
grep -rn "/home/idarfan/csp" app/ && echo "FAIL: 仍指向 repo 外路徑" || echo "CSS 已移植 ok"
```

**通過條件**：帶 `eps` 時 14 個錨點齊備；不帶 `eps` 時剩 11 個且導覽可完整跑完不報錯（人工跑一輪確認 console 無錯誤）；repo 內無任何指向 `/home/idarfan/csp` 的參照。

---

## S8 — PNG 匯出與歸屬稽核

### 8.1 PNG 匯出

**目標**：產出尺寸穩定的成品圖供自用存檔與轉貼，**尺寸永遠鎖死 1920×1080**。

> **2026-09-07 規格變更**：v1 多處以「要發到社群」作為理由。實際用途是自用，
> 不對外發布。尺寸鎖死的理由改為：同一組參數在任何機器上匯出必須得到同一張圖，
> 否則存檔前後無法比對。§8.3 的歸屬稽核原本的威脅模型（有人構造 URL 讓你的品牌
> 掛在錯誤歸屬的圖上）在自用情境下不成立，是否保留待進入 S8 時再定。

**匯出與畫面完全脫鉤。** 不截取畫面上那張卡片，而是另建一個離屏容器渲染匯出版本：

- 離屏容器固定 **960×540 CSS px**，用 `position: absolute; left: -99999px` 移出視野（**不可用 `display: none`** —— html2canvas 量不到尺寸）
- html2canvas `scale: 2` → 產出**恆為 1920×1080**
- 為什麼是 960×540 而不是直接開 1920×1080：容器若真的用 1920 寬，20px 的字只佔畫面寬度的百分之一，成品圖上小到看不清。在 960 寬用 20px 排版、再以 2 倍捕捉，字才有正確的相對大小
- 匯出結果**不受瀏覽器視窗寬度、頁面縮放、裝置 DPR 影響**。同一組參數在任何機器上匯出，PNG 必須尺寸一致

**匯出版面內容**（比畫面版本精簡）：

頁首列（左：品牌字串／右：`PRICE IN`）→ 主標 → 副標 → 圖例／EPS 橫幅 → 圖表 → 判讀重點 → 頁尾列（左：署名／右：報價基準）

**不進匯出**：輸入表單、收摺式查詢清單、導覽按鈕、匯出按鈕本身。

**內容超出 540px 的處理**：整張卡片等比縮放至 fit（`transform: scale(k)`，`transform-origin: top center`），**不裁切、不改字級、不改行距**。`k` 低於 0.75 時，畫面顯示提示「內容過多，建議減少倍數檔數或縮短判讀文字」，但仍照常匯出。理由：寧可整體小一點，也不能讓判讀重點被切掉半句。

- 檔名：`price-in-{TICKER}-chart-a-YYYYMMDD.png` / `price-in-{TICKER}-chart-b-YYYYMMDD.png`。**必須含代號**，否則連續匯出多檔股票會難以分辨甚至覆蓋
- **頁尾署名固定為 `@ohmy48915286`**，置於 locale 檔，不硬編在元件裡
- **品牌字串為 `老衲敝人在下我 / {ticker}`**，由 locale 模板 ＋ 表單 `ticker` 組出。代號部分**禁止硬編**，換一檔股票頁首必須跟著變
- 頁尾右側顯示規則：`price_as_of` 有值時顯示「報價基準 YYYY-MM-DD HH:MM」；為 nil 時顯示「價格為手動輸入」
- 頁首頁尾文字由 locale 檔提供，**不可硬編**
- **本工具只支援繁體中文**，不做語系切換、不建簡體 locale 檔。文案集中於 `price_in.zh-TW.yml` 是為了不硬編字串，不是為了多語系。

### 8.2 頁面寬度

見 §S4「容器寬度」—— 輸入卡 760px、圖表卡 960px，皆置中共用同一條垂直軸線。

匯出既已與畫面脫鉤，畫面寬度就只需服務閱讀，不必遷就成品尺寸；反之，改動畫面寬度也不得影響匯出的 1920×1080。

### 8.3 歸屬稽核

**背景**：手工製圖時曾把某投行的目標價依據標錯 —— 年度、EPS 口徑、有無折現三項全錯。歸屬一旦寫錯，整張圖的結論就站不住。因此機構名只能來自使用者明確填入的白名單。

**實作要點**
- `PriceIn::AttributionAuditor` 掃描即將匯出的卡片文字
- 內建機構關鍵字黑名單：`美銀`、`美银`、`BofA`、`Bank of America`、`Arya`、`高盛`、`Goldman`、`摩根`、`Morgan`、`大摩`、`小摩`、`巴克萊`、`巴克莱`、`Barclays`、`UBS`、`瑞銀`、`瑞银`、`花旗`、`Citi`、`Wells Fargo`、`KeyBanc`、`Stifel`、`Cantor`
- 命中黑名單但不在 `attribution_sources` 者 → 匯出前跳警示 modal，列出命中詞，要求使用者確認來源正確或移除
- **`attribution_sources` 走 query string，是稽核的繞過口**：任何人可構造一個 URL 塞進白名單字串，讓稽核靜默放行，匯出的圖上就掛著你的品牌字串。防護三層：
  1. Form 層限制最多 5 項、單項 ≤ 30 字（見 §S2）
  2. 白名單由 URL 帶入時（非本次 session 中使用者手動輸入），畫面於稽核區顯示「來源由網址帶入，請確認」提示
  3. 警示 modal 一律顯示命中詞與對應的白名單項，讓使用者看到「因為什麼被放行」
- locale 檔與元件內**禁止**出現任何機構名（S8 驗證會 grep）

**必測案例**
1. 文字含「美銀」、白名單空 → 回傳非空
2. 文字含「美銀」、白名單為 `["美銀"]` → 回傳空
3. 乾淨文字 → 回傳空
4. 簡繁兩種寫法都要命中
5. `attribution_sources` 有 6 項 → Form 層擋下，稽核不執行
6. 白名單由 query string 帶入 → 稽核區顯示「來源由網址帶入」提示

**驗證**
```bash
bundle exec rspec spec/services/price_in/attribution_auditor_spec.rb
grep -rniE "美銀|美银|BofA|高盛|Goldman|摩根|Morgan|巴克萊|巴克莱|Barclays|UBS|花旗|Citi|Stifel|Cantor" \
  config/locales/price_in.zh-TW.yml app/components/price_in/ \
  && echo "FAIL: 程式碼硬編機構名" || echo "無硬編機構名 ok"
# 確認未殘留多語系檔
ls config/locales/price_in.* | grep -v "zh-TW" && echo "FAIL: 出現非繁中 locale 檔" || echo "單一語系 ok"
# 品牌字串不得硬編代號
grep -rn "老衲敝人在下我 / MRVL\|老衲敝人在下我 /MRVL" app/ config/locales/ \
  && echo "FAIL: 品牌字串硬編代號" || echo "品牌字串為模板 ok"
# 匯出尺寸必須恆為 1920x1080（以 Playwright 觸發匯出後檢查產出檔）
python3 -c "
from PIL import Image
import sys
for p in sys.argv[1:]:
    w, h = Image.open(p).size
    assert (w, h) == (1920, 1080), f'{p} 尺寸為 {w}x{h}，應為 1920x1080'
print('匯出尺寸 ok')
" <匯出的圖A路徑> <匯出的圖B路徑>
# 離屏容器不得用 display:none（html2canvas 量不到尺寸）
grep -rn "display:\s*none" app/components/price_in/ app/javascript/controllers/price_in_export*.js \
  && echo "FAIL: 離屏容器疑似使用 display:none" || echo "離屏容器 ok"
```

**通過條件**：6 個稽核案例全綠；無硬編機構名；`config/locales/` 下只有 `price_in.zh-TW.yml`；品牌字串為模板；匯出檔名含代號；**兩張匯出圖尺寸均為 1920×1080**。

---

## S9 — 端到端驗收

**目標**：確認最基本的使用路徑真的跑得起來，而不是只有測試數字漂亮。

**必須完成並在回報中附上證據**

1. **最基本用法**：不帶任何 query string 開啟頁面 → 圖 A 以預設 price 畫出、圖 B 顯示引導填寫的空狀態（非錯誤）。附上實際 URL 與 Playwright 截圖。
2. **填入 EPS 後出圖**：在圖 B 的 EPS 欄位填 `11.02`、年度填 `FY2029` → 圖 B 畫出六條長條。附截圖。
3. **DOM 值交叉核對**：從畫面 DOM 取出圖 A 三個數值與圖 B 六個報酬率，逐項對照 §S1 定值表。附上取出的實際值，不是「應該是」。
4. **修改參數重繪**：把 `price` 改成 300，確認圖 A 數值變為 `$12.00` / `$10.00` / `$8.57`。附截圖。
5. **導覽跑一輪**：觸發導覽走完 14 步，附首步與末步截圖，確認 tooltip 樣式與 lesson8 一致。
6. **匯出兩張 PNG**：附產出檔案路徑、檔案大小、以及 `identify` 或 PIL 讀出的實際尺寸 —— **必須是 1920×1080**。另在兩種不同視窗寬度（例如 1280 與 1920）各匯出一次，確認兩次產出的尺寸完全相同。
7. **報價帶入**：輸入一個非 MRVL 的代號（例如 AVGO），按「帶入現價」→ 價格自動更新、頁首標題變為 `老衲敝人在下我 / AVGO`、兩張圖重繪。附截圖與 DOM 取出的價格值。
8. **報價失敗不擋路**：輸入不存在的代號（例如 ZZZZ），確認顯示錯誤訊息、價格維持原值、**圖表仍正常顯示**。附截圖。
9. **代號變更保護**：只改代號、不按「帶入現價」→ 確認出現「價格尚未更新」警示，且**頁首標題未變成新代號配舊價格**。附截圖。
10. **標籤同步**：帶入報價後確認圖 B 圖例文字中的金額與長條實際使用的價格一致。附截圖與 DOM 值。
11. **參考倍數**：帶入報價後，確認本益比卡片顯示 TTM 本益比與兩個隱含倍數，且下方三個輸入框**未被自動改動**。附截圖與 DOM 取出的三個參考值。
12. **全套測試**：`bundle exec rspec` 全綠。

**驗證**
```bash
bundle exec rspec
# 其餘為人工 + Playwright 證據，見上列 1–11
```

**通過條件**：12 項證據齊備。**測試通過數不能作為完成證據**；未附截圖與 DOM 實際值者視為未完成。

---

## 附錄 A — 禁止事項

1. 禁止在元件或 Service 硬編顯示字串，全部走 locale 檔
2. 禁止硬編機構名或目標價來源
3. 禁止 CDN 熱連（Chart.js / driver.js / html2canvas / 字體 / 圖示一律 self-host）
4. 禁止 Service 混入 view 依賴
5. 禁止用 U+2212 作負號
6. 禁止在 `fiscal_year_label` 缺席時產出圖表
7. 禁止全頁出現 20px 以下字級；禁止為了單頁不捲動而縮字級或改兩欄擠壓；禁止任何區塊鋪滿全寬（輸入卡 760px、圖表卡 960px，皆置中）
8. 禁止把說明卡內容寫成段落散文 —— 一律「有標頭列的表格」
9. 禁止開孤立頂層路由；禁止只做路由不做 sidebar 入口
10. 禁止把 repo 外檔案（`/home/idarfan/csp/*`）以連結方式引用，一律移植進 repo
11. 禁止做語系切換或建立繁中以外的 locale 檔
12. 禁止為報價功能新增第三方 API 憑證、新 gem 或新資料表；禁止頁面載入時自動抓價；禁止報價失敗時阻擋出圖
13. 禁止在品牌字串中硬編股票代號
14. 禁止把 TTM 本益比或任何參考倍數自動填入倍數輸入框；禁止在 `pe_ttm` 為 nil 時報錯或阻擋出圖
15. 禁止為 `eps` 與 `eps_band` 設任何預設值（只能用 placeholder 提示格式）；收摺清單只收**免費可讀**且**網址只需替換代號**的來源，禁止放付費牆後的站點或自行拼湊的網址
16. 禁止讓 `eps` 留空導致整個 Form invalid；禁止把圖 B 的空狀態當成錯誤狀態呈現
17. 禁止在代號變更後、價格尚未更新時輸出圖表；禁止把買入價標籤做成獨立的自由文字欄位（必須由價格自動組出）
18. 禁止在 `:null_store` 下驗收快取行為
19. 禁止在 locale 檔中把多句塞進同一個字串（一句一元素）；禁止在 view 用 `split("。")` 代替 locale 層斷句；禁止對半形句點「.」斷行
20. 禁止直接截取畫面上的卡片作為匯出來源；禁止讓匯出尺寸隨視窗、縮放或 DPR 變動；禁止用裁切的方式處理內容溢出
21. 規格修改一律 patch/diff，不整檔重寫

## 附錄 B — 完成回報要求

宣告任一階段完成時，回報需附：

1. 該階段驗證指令的完整終端輸出（含 exit code）
2. 涉及畫面的階段需附 Playwright 截圖 ＋ 實際 URL ＋ 從 DOM 取出的關鍵欄位值
3. S9 需明確確認**最基本用法**（無任何 query string）已完整跑過，而非只跑帶參數的變體

「有輸出」不等於「輸出正確」。單元測試數量不是完成證據。

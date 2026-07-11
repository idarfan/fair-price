# PMCC 黃金法則區塊規格 v3

> 在 `/leaps` 的 Options Flow 區塊下方新增 PMCC 自動組合試算。使用者僅輸入 `symbol`，程式自動完成 LEAPS + 三到期日 Short Call 抓取、黃金法則組合、列出可做 PMCC 的組合與權利金細項。全程自動化，無手算。

## §0 前置閱讀

1. 本檔全文（§2 公式節為權威）
2. `leaps-call-recommendation-spec.md`：核心原則（禁內部API、CDP兩層檢查、fresh window、三層驗證）、Phase A 抓取策略、DB 設計
3. `option-basics-lesson9.html:990-1135`：黃金法則公式與錯誤文案來源
4. 現有實作：
   - `lib/barchart_scrapers/leaps_scraper.py`（兩階段骨架、JS snippets）
   - `lib/barchart_scrapers/cdp_helper.py`（`prepare_page`, `cdp_eval`, `cdp_navigate`, `_wait_for_grid`）
   - `lib/barchart_scrapers/max_pain_scraper.py`（Expiration 下拉讀取模式）
   - `app/services/barchart_scraper_service.rb`（`fetch_leaps`, `persist_leaps`, `run_scraper`）
   - `app/jobs/scrape_leaps_job.rb`
   - `app/models/leaps_option_chain_snapshot.rb`（`FRESH_WINDOW`, `derived_values`, `mid_price`）
   - `app/controllers/leaps_recommendations_controller.rb`（`fresh_for?`, `cdp_online?`）
   - `app/components/leaps_recommendations/page_component.rb`（`view_template`, `TABLE_COLS`, `LIQUIDITY_STYLE`, `fmt_*`）

## §1 現況與鐵律

- DB 已有 `leaps_option_chain_snapshots`、`strike_chain_snapshots`、`options_flow_trades`。`pmcc_short_call_snapshots` migration `20260711054225` 已建檔但曾中斷 → 第一步 `db:migrate:status` 確認。
- 現有流程：`symbol`(+選填 `user_strike`) → `fresh_for?` → CDP預檢 → `ScrapeLeapsJob` → `leaps_scraper.py` → persist + 刷新 Flow → 前端輪詢 → index 渲染。PMCC 沿用，不另開觸發路徑。
- `user_strike` 存在時，Short Call 中心點仍用 auto OTM，不受影響。
- **鐵律**：禁 `/proxies/core-api/` 內部API；禁 Black-Scholes 反推 Delta；禁 `last_price` 作權利金基準；禁第二個 `30.minutes` 字面值（引用 `FRESH_WINDOW`）；禁發明新色票（用 `SIGNAL_COLORS`）；Short Call 獨立表；`fresh_for?` 唯一權威。
- PMCC 失敗**不可**讓 LEAPS 查詢變 error（同 Flow 失敗不影響排行）。

---

## §2 公式（唯一定義處）

### §2.1 Mid 的唯一定義 ⚠️ 先讀，實作順序 Step0

每一列的 mid **只能有一個值**，決定順序：

```
mid = Barchart midpoint 原值
    → 無值時 fallback (bid + ask) / 2
    → bid/ask 任一缺值則 mid = null（該列不參與組合，不以 0 代）
```

這個決定好的 mid：
1. **存入 `mid_price` 欄**
2. **作為參數傳入 `derived_values`** 計算 intrinsic/extrinsic
3. 作為黃金法則的 PL / PS

**`derived_values` 必須改為接收 mid 參數，不得自行從 bid/ask 重算**（若現行簽名是自己重算，本階段一併重構；LEAPS 呼叫端傳 `(bid+ask)/2`，行為不變，需回歸測試證明 LEAPS 既有數值未變）。

公式唯一來源仍是 `LeapsOptionChainSnapshot.derived_values`，PMCC 禁止重寫公式——但 mid 來源由呼叫端決定。同一列的 `mid_price` 欄與計算 `extrinsic_value` 所用的 mid 必須是同一個數字。

### §2.2 黃金法則

```
PL = Long LEAPS mid_price
PS = Short Call mid_price
KL = Long LEAPS strike
KS = Short Call strike
spread = KS - KL

前置檢查（依序，任一不過即淘汰並記 fail_reason）：
  (a) KS > KL
      fail_reason:「Short Call履約價KS($xxx)必須大於LEAPS履約價KL($yyy)」
  (b) long.dte >= short.dte + 180
      fail_reason:「LEAPS到期日($long_dte天)距Short Call到期日($short_dte天)不足180天，
                   SC到期時LEAPS時間價值恐已大幅流失，最大獲利公式不成立」
  (c) PL 或 PS 為 null → 跳過該組合，不列入

passes = PL < spread（嚴格小於）

net_debit         = PL - PS                            # 實際投入資金
max_profit_no_sc  = spread - PL                        # 不賣SC的天花板（參考值）
max_profit        = spread - net_debit                 # ★PMCC真正最大獲利（含收租），主排序鍵
                  = max_profit_no_sc + PS
premium_yield     = PS / net_debit * 100%              # 收租相對實際投入
premium_yield_ann = premium_yield / short.dte * 365    # ★年化，跨到期日比較唯一有意義的數字
```

**前置 (b) 的理由**：`max_profit` 公式隱含假設「SC 到期時 LEAPS 仍保有時間價值可續持或轉倉」。兩腿到期日太近則此假設不成立，算出的獲利無法實現。目前 LEAPS DTE≥364、Short 取最近三到期日（6–50天）天然滿足，但必須釘死，不可依賴巧合。

**命名**：`max_profit` = 含 SC 的真實上限（主排序、表格主欄）；`max_profit_no_sc` = 參考值，次要顯示。兩者都要顯示但不可混淆。

### §2.3 Delta 兩條規則，互不取代

| 用途 | 區間 | 說明 |
|---|---|---|
| **粗篩**（`DELTA_SHORT_MIN/MAX`，決定哪些 SC 進入組合運算） | **0.15 – 0.40** | 寬鬆，避免誤刪邊緣候選。錯誤訊息「無 Delta 0.15-0.40 的 Short Call」用此區間 |
| **建議標記**（表格 ✅／⚠️ 顯示判定） | **0.20 – 0.35** | lesson9 建倉規範理想區間。落在 0.15–0.20 或 0.35–0.40 的候選**仍列出**，只是不打 ✅ |

Long Delta 同理：粗篩沿用 LEAPS 既有 0.60–0.90；建議標記 `✅ if ≥ 0.80`。

**列出 ≠ 推薦**——同 LEAPS 排行表列出全部候選、只標流動性分級。

---

## §3 三時段定義

- **三時段 = Barchart Options Prices 頁面 `Expiration:` 下拉的前三個到期日**（DOM 順序，已按日期升序），含 m/w 不區分，如 `["2026-07-17 (m)", "2026-07-24 (w)", "2026-07-31 (w)"]`。
- 若下拉僅 1–2 個，有幾個抓幾個。
- PMCC 按**到期日字串**分桶，非 DTE 範圍。前端 label 顯示實際到期日字串 + 近/中/遠月 badge。

### DTE 警示（不過濾，只標示）

最近三個到期日的 DTE 通常落在 6–50 天，**其中前一兩個往往短於 lesson9 建倉規範的 19–45 天建議區間**（例如 NOK 常見為 6 / 13 / 20 DTE，前兩個都不在建議區內）。

**規則：不篩掉、不過濾——列出全部，但明確標示風險。** 這與本專案「列出全部候選、只標分級、不自動下結論」的一貫原則一致（同 LEAPS 排行表列出全部候選、只標流動性分級）。

- **`short.dte < 19` 的到期日桶**：卡片標題加警示 badge
  `⚠️ 短於 lesson9 建議區間（19–45 天）：Gamma 風險高、被指派機率陡增、收租金額低`
- badge 用 `SIGNAL_COLORS` 的橘黃警示色，不另造色票。
- **該桶的組合仍照常計算與列出**，黃金法則判定不受影響——警示是給人看的，不是篩選條件。

---

## §4 資料流

```
輸入 symbol (+選填 user_strike)
  → LeapsRecommendationsController#analyze
    ├─ StrikeChainSnapshot fast-path（沿用）
    ├─ fresh_for?（沿用）
    ├─ cdp_online?（沿用）
    └─ ScrapeLeapsJob(symbol, job_id, user_strike:)
        ├─ fetch_leaps → leaps_scraper.py → persist_leaps + chain_snapshot + 刷新Flow（沿用）
        └─ fetch_pmcc_short_calls(NEW) → pmcc_short_call_scraper.py → persist_pmcc_short_calls
            └─ try/catch 隔離，失敗不讓整 job 變 error

Controller#index
  ├─ LeapsRankingService → @candidates
  ├─ LeapsRecommendationService → @recommendation
  ├─ LeapsOptionsFlowPanelService → @flow_panel
  └─ PmccRankingService(NEW) → @pmcc_ranking

PageComponent
  ├─ render_pmcc_section(@pmcc_ranking)   # §8.1
  └─ render_pmcc_edu_section              # §8.2，獨立於資料，無資料也不崩
```

---

## §5 DB

### 現狀處置

`20260711054225_create_pmcc_short_call_snapshots.rb` 曾中斷：
- 若 `down`：直接改檔加入下方完整欄位再 `db:migrate`
- 若 `up`：另開 `add_missing_columns_to_pmcc_short_call_snapshots` 補欄

### DDL

欄位來源：Options Prices + Volatility & Greeks 兩頁，`(strike, expiration)` merge。

```ruby
create_table :pmcc_short_call_snapshots do |t|
  t.string   :symbol,             null: false
  t.date     :expiration_date,    null: false
  t.integer  :dte
  t.decimal  :strike,             precision: 10, scale: 4, null: false
  t.string   :option_type,        null: false, default: "Call"
  t.decimal  :bid,                precision: 10, scale: 4
  t.decimal  :ask,                precision: 10, scale: 4
  t.decimal  :mid_price,          precision: 10, scale: 4  # §2.1 決定的唯一 mid
  t.decimal  :last_price,         precision: 10, scale: 4
  t.decimal  :moneyness,          precision: 8,  scale: 4  # +3.54% 存 0.0354
  t.decimal  :underlying_price,   precision: 10, scale: 4
  t.decimal  :change,             precision: 10, scale: 4
  t.decimal  :percent_change,     precision: 8,  scale: 4  # -37.61% 存 -0.3761
  t.integer  :volume
  t.integer  :open_interest
  t.integer  :oi_change                                    # unch 存 NULL
  t.decimal  :vol_oi_ratio,       precision: 8,  scale: 4
  t.decimal  :iv,                 precision: 8,  scale: 6
  t.decimal  :delta,              precision: 8,  scale: 6
  t.decimal  :gamma,              precision: 10, scale: 6
  t.decimal  :theta,              precision: 10, scale: 6
  t.decimal  :vega,               precision: 10, scale: 6
  t.decimal  :rho,                precision: 10, scale: 6
  t.decimal  :theoretical_price,  precision: 10, scale: 4
  t.decimal  :itm_probability,    precision: 8,  scale: 6
  t.decimal  :intrinsic_value,    precision: 10, scale: 4  # derived_values(mid) 算
  t.decimal  :extrinsic_value,    precision: 10, scale: 4
  t.date     :last_trade_date
  t.datetime :scraped_at,         null: false
  t.timestamps
end
add_index :pmcc_short_call_snapshots, [:symbol, :expiration_date, :strike], unique: true, name: "idx_pmcc_short_unique"
add_index :pmcc_short_call_snapshots, [:symbol, :scraped_at], name: "idx_pmcc_short_symbol_scraped"
```

`moneyness` 存小數。`oi_change` `unch` → NULL。`last_trade_date` 解析 `MM/DD/YY`。中間橫幅（ATM IV / Historic Vol / IV Rank）為批次 metadata，寫 `fetch_logs.error_detail` JSON 或 Rails.cache 即可，不強制落地。

### Model `app/models/pmcc_short_call_snapshot.rb`

複製 LEAPS model 寫法：`FRESH_WINDOW` **引用** `LeapsOptionChainSnapshot::FRESH_WINDOW`（禁自訂）、`scope :for_symbol`、`scope :fresh`、`def mid_price`（依 §2.1 決定順序）、`validates`、`self.fresh_for?(symbol)`。

---

## §6 Python 抓取器 `lib/barchart_scrapers/pmcc_short_call_scraper.py`

### 與 LEAPS 的差異

| 項 | LEAPS | PMCC Short |
|---|---|---|
| 選時段 | Delta≥0.60 ITM strike 為中心，stacked 全到期日 | 讀 Expiration 下拉前3，每到期日 `?expiration=&moneyness=100` 全履約價 |
| 請求數 | N strikes × 2頁 | 3 expirations × ~2頁 ≈ 6 次導航，20–40 秒 |
| 最終篩選 | DTE≥364, Delta 0.60–0.90 | **不在 Python 硬濾**，交 Ruby 處理（避免誤刪） |

### Stage 1：讀 Expiration 下拉

1. 進入 `https://www.barchart.com/stocks/quotes/{SYMBOL}/options`
2. 讀下拉全部選項：

```javascript
const sel = document.querySelector('select[name="expiration"]') ||
  [...document.querySelectorAll('select')].find(s => [...s.options].some(o => /20\d{2}-/.test(o.value)));
const expirations = [...sel.options].map(o => o.value.trim()).filter(v => /20\d{2}-/.test(v));
```

取前 3：`selected_expirations = expirations.slice(0, 3)`

3. 同步讀 `underlying_price`（`UNDERLYING_JS`）

### Stage 2：逐到期日抓取

對每個 `exp`：

1. URL：`https://www.barchart.com/stocks/quotes/{SYMBOL}/options?expiration={exp_value}&moneyness=100`
   - `exp_value` 原始 value 可能含 `string:` 前綴，參考 `max_pain_scraper.py` 的轉換，**需實測**
2. `cdp_navigate` + `_wait_for_grid` 讀該到期日全部 Call 行。空則 `_confirm_empty` 二次確認；超時 30 秒則 `SESSION_EXPIRED_JS` 分類 `session_expired` vs `page_load_timeout` → `partial`
3. V&G 補抓：導航 `volatility-greeks?expiration={exp_value}`，`_merge_vg` 以 `(strike, expiration_date)` 合併

### JS Snippets

Options Prices：

```javascript
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid || !grid._data) return null;
  return grid._data.map(r=>r.raw||r).filter(r=>r.optionType==='Call'||r.symbolType==='Call')
    .map(r=>({
      expiration_date: r.expirationDate||r.expirationDateString||null,
      dte: typeof r.daysToExpiration==='number'?r.daysToExpiration:null,
      strike: r.strikePrice,
      bid: typeof r.bidPrice==='number'?r.bidPrice:null,
      ask: typeof r.askPrice==='number'?r.askPrice:null,
      mid: typeof r.midpoint==='number'?r.midpoint:null,
      last: typeof r.lastPrice==='number'?r.lastPrice:null,
      volume: typeof r.volume==='number'?r.volume:null,
      oi: typeof r.openInterest==='number'?r.openInterest:null,
      oi_chg: typeof r.openInterestChange==='number'?r.openInterestChange:(typeof r.oiChange==='number'?r.oiChange:null),
      moneyness: typeof r.moneyness==='number'?r.moneyness:null,
      delta: typeof r.delta==='number'?r.delta:null,
      iv: typeof r.volatility==='number'?r.volatility:null,
      change: typeof r.change==='number'?r.change:null,
      pct_change: typeof r.changePercent==='number'?r.changePercent:null,
    }));
})()
```

V&G：

```javascript
(() => {
  const grid = document.querySelector('bc-data-grid');
  if (!grid||!grid._data) return null;
  return grid._data.map(r=>r.raw||r).filter(r=>r.optionType==='Call'||r.symbolType==='Call')
    .map(r=>({
      expiration_date: r.expirationDate||r.expirationDateString||null,
      strike: r.strikePrice,
      theoretical: typeof r.theoretical==='number'?r.theoretical:null,
      iv: typeof r.volatility==='number'?r.volatility:null,
      delta: typeof r.delta==='number'?r.delta:null,
      gamma: typeof r.gamma==='number'?r.gamma:null,
      theta: typeof r.theta==='number'?r.theta:null,
      vega: typeof r.vega==='number'?r.vega:null,
      rho: typeof r.rho==='number'?r.rho:null,
      itm_prob: typeof r.itmProbability==='number'?r.itmProbability:null,
      vol_oi: typeof r.volumeOpenInterestRatio==='number'?r.volumeOpenInterestRatio:null,
    }));
})()
```

輸出 JSON（stdout，對齊 leaps）：

```json
{"status":"success","rows":[{"expiration_date":"2026-07-17","dte":6,"strike":13.0,"bid":0.23,"ask":0.25,"mid":0.24,"last_price":0.23,"moneyness":-0.045,"volume":5285,"open_interest":26278,"oi_change":3912,"delta":0.3339,"iv":0.7163,"gamma":0.3185,"theta":-0.0349,"vega":0.0058,"rho":0.0006,"theoretical_price":0.24,"itm_probability":0.3158,"vol_oi_ratio":0.20,"underlying_price":12.44}],"underlying_price":12.44}
```

失敗狀態：`barchart_session_expired` / `partial`（含 `expired_at_strike`, `expired_layer`, `reason`, `skipped_expirations`）/ `error` / `no_candidates`，供 `run_scraper` 共用解析。

同時更新 `leaps_scraper.py` 的 `STACKED_OPTIONS_JS` 補 `oi_chg` / `mid`。

---

## §7 Ruby Services

### `BarchartScraperService` 擴充

```ruby
def fetch_pmcc_short_calls
  # cdp_available? guard
  # run_scraper("pmcc_short_call")
  # case: barchart_session_expired / success / partial / no_candidates / error
  # persist_pmcc_short_calls(data) on success/partial
  # log_fetch("pmcc_short", status, detail)
end

def persist_pmcc_short_calls(data)
  rows = data["rows"]; return if rows.blank?
  # 每列先依 §2.1 決定 mid → 存 mid_price 欄 → 傳入 derived_values 算 intrinsic/extrinsic
  # 必須含 §5 DDL 全部欄位
  # 防護：expiration_date/strike blank check、strike > 0，否則 raise 人話錯誤
  # transaction { where(symbol: @symbol).delete_all; insert_all(records) }
end
```

`run_scraper` 已通用，檔名符合 `{type}_scraper.py` 即可。

### `PmccRankingService`（NEW）

純計算，吃 DB 最新 batch，不打 Barchart、不寫 DB。

```ruby
SC_EXPIRATION_COUNT       = 3
TOP_SHORT_PER_EXPIRATION  = 8
TOP_COMBOS_PER_EXPIRATION = 5
DELTA_SHORT_MIN = 0.15
DELTA_SHORT_MAX = 0.40
TOP_LEAPS_PER_GROUP = 3
```

步驟：

1. `fetch_leaps_candidates`：`LeapsRankingService.new(symbol).call` 取已含 liquidity tier 的候選，近天期(364–550)／遠天期(550+)各取前 3。
2. `fetch_short_candidates`：`PmccShortCallSnapshot` 最新 batch，按 `expiration_date` 分組取前 3 到期日（日期升序），每桶 Delta 0.15–0.40 粗篩後 OI 降序取前 8。
3. `cross_and_filter`：LEAPS(≤6) × SC(≤24) ≤ 144 組合。依 §2.2 前置檢查順序：**(a) KS≤KL → (b) long.dte < short.dte+180 → (c) mid 缺值**。(a)(b) 未過仍保留並記 `fail_reason`；(c) 直接不列入。
4. `enrich_combo`：`net_debit, max_profit_no_sc, max_profit, premium_yield, premium_yield_ann`（命名依 §2.2，**`max_profit` 是含 SC 的那個**）；`leaps_delta_ok(≥0.80)` / `short_delta_ok(0.20–0.35)` 供 ✅/⚠️ 標記，**僅標記不淘汰**。
5. `bucket_and_sort`：按到期日分桶，每桶 passes 在前，同組依 **`max_profit`（含SC）** 高→低，取前 5。

輸出：

```ruby
{
  "2026-07-17": {
    expiration: "2026-07-17 (m)", expiration_date: Date,
    combos: [{
      long_leg:  { strike:KL, mid:PL, bid, ask, delta, dte, oi, expiration_date, intrinsic, extrinsic },
      short_leg: { strike:KS, mid:PS, bid, ask, theoretical_price, moneyness, delta, gamma, theta, vega,
                   iv, itm_probability, vol, oi, vol_oi_ratio, oi_change, expiration_date, dte },
      spread, net_debit, max_profit_no_sc, max_profit, premium_yield, premium_yield_ann,
      passes_golden_rule, fail_reason
    }],
    has_passing: bool
  },
  "2026-07-24": {...}, "2026-07-31": {...},
  near_term: →第一到期日, mid_term: →第二, far_term: →第三,
  summary: { total_combos, passing_combos, leaps_count, short_count, symbol, expirations },
  status: :ok | :no_leaps | :no_short | :no_data
}
```

---

## §8 Controller & Job

`ScrapeLeapsJob#perform`：既有 `fetch_leaps` 後接 `fetch_pmcc_short_calls`，**try/catch 隔離**，Short Call 失敗不讓整 job rescue 成 error。

`LeapsRecommendationsController#index`：既有 `@candidates/@recommendation/@flow_panel` 後，若 `@candidates.any?` 且 `PmccShortCallSnapshot.for_symbol(@symbol).exists?` → `@pmcc_ranking = PmccRankingService.new(@symbol).call`，否則 `status: :no_data`。傳入 `PageComponent.new(..., pmcc_ranking: @pmcc_ranking)`。

`analyze` 不需額外參數，Short Call 為內部 side-effect。

---

## §9 Phlex 前端

`view_template` 順序：

```
render_header → render_search_form → render_status_bar → render_recommendation
→ render_ranking_table → render_flow_panel
→ render_pmcc_section → render_pmcc_edu_section
→ render_vocab_cards + scripts
```

### §9.1 PMCC 表格 `render_pmcc_section`

Header：`⚖️ PMCC黃金法則組合 — #{@symbol}` + 公式 reminder `PL < KS-KL · 每到期日前5` + summary bar `總組合 N / 通過 M`。

三到期日卡片垂直堆疊：`render_pmcc_bucket(key, label, bucket_data)`，label 為實際到期日字串（`2026-07-17 (m) · 6 DTE`）+ 近/中/遠月 badge。

**DTE 警示 badge（§3）**：`short.dte < 19` 的桶，標題另加橘黃警示 badge
`⚠️ 短於 lesson9 建議區間（19–45 天）：Gamma 風險高、被指派機率陡增、收租金額低`
用 `SIGNAL_COLORS` 警示色，不另造色票。**該桶組合照常列出，不篩掉。**

### ⚠️ 表格列樣式（硬性規範，沿用主 spec 既有值，不得自行設計）

| 項目 | 值 |
|---|---|
| 奇數列底色 | `bg-gray-50/50`（灰色系） |
| **滑鼠懸停底色** | **`hover:bg-purple-200`（淺紫）** |
| 黃金法則未通過的列 | `bg-red-50` |

**這三者是獨立的顏色系統，不得混用或連動修改。** hover 淺紫必須套用在 PMCC 表格的**每一列**（含未通過的列——未通過列的底色是 `bg-red-50`，hover 時仍變 `purple-200`）。這條與 LEAPS 排行表完全一致，是使用者已習慣的互動回饋，實作時不得省略或改色。

`render_pmcc_table(combos)`：`overflow-x-auto`，**預設 12 關鍵欄**，其餘放 `details/summary` 展開列。

| 分組 | 欄位 | 格式/風控 |
|---|---|---|
| Long | 履約價 KL | 藍 $xx.xx |
| Long | PL (mid) | $x.xx，黃金法則分子 |
| Long | Bid/Ask、DTE/OI/Vol | 流動性 |
| Long | Delta | ✅ if ≥0.80（僅標記） |
| Short | 到期日 | YYYY-MM-DD + m/w badge |
| Short | 履約價 KS | 紅 $xx.xx |
| Short | PS (mid) | $x.xx，收入 |
| Short | Bid/Ask/Theo. | Theo. 與 Mid 對比 %差 |
| Short | Moneyness | +綠 −紅 |
| Short | Delta | ✅ if 0.20–0.35（僅標記，見 §2.3） |
| Short | Gamma/Theta/Vega/IV/ITM Prob% | Gamma>0.20 ⚠️；Theta 為收租核心 |
| Short | Vol/OI/Vol-OI比/OI Chg | +綠 −紅 unch紫 |
| 計算 | Spread / NetDebit / **MaxProfit(含SC)** / MaxProfit(未收租) / 收租率 / **年化收租率** | 綠>0 紅<0；**主排序＝MaxProfit(含SC)**；年化欄不可省略 |
| 判定 | Golden Rule | ✅通過 / ❌ + fail_reason（KS≤KL、DTE不足180天） |

樣式：`SIGNAL_COLORS` 綠通過/紅未過/橘警告；列樣式見上方硬性規範表；沿用 `fmt_*` helpers；新常數 `PMCC_TABLE_COLS`。表頭可 `colspan` 分色（Long / Short / Calc）。

無資料：`status :no_short` → 「尚無 Short Call 資料，請重新查詢」；`combos.empty?` → 「此到期日無 KS>KL 組合」。

### §9.2 教育說明區 `render_pmcc_edu_section`

來源：`option-basics-lesson9.html` 的黃金法則(黃盒) + 最大獲利(綠盒) + 建倉規範(小卡) + PMCC定義(大白卡)。置於 PMCC 表後、`render_vocab_cards` 前。**無資料也要獨立渲染**，代入值缺失時顯示「—」，不得 500。

**CSS Token（精確移植 lesson9 `:root`，禁止重新設計）**：

```
bg #FAF3E8 / page-bg #FFF9F2 / panel-bg #FFFCF7 / ink #2A1A0E / muted #7A6555 / border #E2D4C2
gold #D4900A / gold-bg #FEF4D8 / gold-bdr #E8B840 / 黃盒 #FFF7C0
green #2E9E52 / green-bg #E8F8EE / green-bdr #8ED4A8 / 綠盒 #F0FAF0
red #D04040 / red-bg #FDEAEA / red-bdr #F5AAAA / blue #3A70C0 / blue-bg #EBF2FF / blue-bdr #9ABCE8
r-lg 16px / r-md 10px / r-sm 6px
```

根容器 `pmcc-edu-root` scoped，複製 lesson9 的 `.hfb`, `.hfb-row.gold-row/green-row`, `.hfb-icon/title/formula/note/detail`, `.contract-box/.cb-title/ticker/grid/item`, `.full-card/.tag-row/.step-badge/.pill/.ptitle/.bullets/.bullet-num` 為 scoped 版，或用 Tailwind arbitrary values（`bg-[#FFF7C0]`）。**驗收取色誤差 < 5**。

四張卡（值全自動代入，不提手算）：

1. **黃金法則黃盒**：`#FFF7C0 + 1.5px #E8B840 + 10px radius`，icon ⚖，title「黃金法則（建倉前必驗算）」，formula `LEAPS買入成本 < Short Call履約價 − LEAPS履約價`(gold)，note「差價=KS−KL 代表最多能賺多少（程式自動算，列於 Spread 欄）」+「費用超過差價即使方向對仍**保證虧損**」（紅粗）。自動代入：取第一組通過的 `{symbol} {KL}→{KS} 差價{spread} 費用{PL} → ✅`，無通過組則取第一組失敗 + `fail_reason`。

2. **最大獲利綠盒**：`#F0FAF0 + #8ED4A8`，title「最大獲利 = 差價 − 淨成本」，formula `(KS−KL) − (PL−PS)`(green)，detail「漲至 KS 以上時實現，列於 MaxProfit(含SC) 欄」。自動代入實際數值。

3. **建倉規範小卡** `.contract-box`：`#FEF4D8 + 2px #E8B840 + 16px radius`，title「📐 建倉規範」，ticker「PMCC · 黃金法則」，2×2 grid：Long Delta ≥0.80(藍) / Long DTE ≥180天(藍) / Short Delta 0.20–0.35(紅) / Short DTE 19–45天(紅)。附註：本表抓最近三到期日，天然落在 6–50 天。

4. **PMCC 定義大白卡** `.full-card`：`#FFFCF7 + 2px #E2D4C2 + 16px radius`，header 黑圓「1」+ `WHAT IS PMCC` + pill「窮人版備兌買權」，title「PMCC = LEAPS Long Call + Short Call」，bullets ①②③④（橘框圓）：① 買100股成本 `underlying×100` ② LEAPS 成本 `PL×100` ③ 短期虛值 SC：最近三到期日、Delta 0.20–0.35、收租 `PS×100` ④ 資金比例 `PL×100 / (underlying×100)` %。底部免責灰小字。

```ruby
def render_pmcc_edu_section
  div(class: "pmcc-edu-root space-y-4") do
    render_pmcc_edu_golden_rule
    render_pmcc_edu_max_profit
    render_pmcc_edu_build_rules
    render_pmcc_edu_what_is_pmcc
  end
end
```

---

## §10 錯誤與快取

沿用 `leaps-call-recommendation-spec.md` 的 5 種錯誤分流，新增：

| 狀態 | 顯示 |
|---|---|
| Short `partial` | 黃 alert「Short Call 在 Strike X 時 V&G 中斷，已抓部分用於組合」 |
| `no_short_candidates` | 藍提示「近三到期日無 Delta 0.15–0.40 的 Short Call，可能流動性不足」 |
| 全組 KS≤KL | bucket 顯示「無 KS>KL 組合」，**不算後端錯誤** |

Fresh：`PmccShortCallSnapshot.fresh` 引用 `LeapsOptionChainSnapshot::FRESH_WINDOW`。

配色：Moneyness +綠−紅；Change/OI Chg +綠−紅 unch紫；Strike 藍；Theta 以 Short 視角顯示（`+0.03/day 收租`）；Gamma > 0.20 標 ⚠️。

---

## §11 驗收

### DB / Model / Service

- [ ] `db:migrate:status` → `pmcc_short_call_snapshots` up；columns 含 §5 DDL 全部
- [ ] Model：`fresh`, `mid_price`, `for_symbol`, `fresh_for?` 存在
- [ ] **mid 一致性測試**：造一筆 Barchart `mid`=0.24、`bid`=0.23、`ask`=0.26 的資料（`(bid+ask)/2`=0.245，與 mid 不等），驗證 `mid_price` 欄存 0.24 **且** `extrinsic_value` 是用 0.24 算的，不是 0.245
- [ ] **LEAPS 回歸**：`derived_values` 改為接收 mid 參數後，用 Phase H 的 NVTS fixture 重跑，LEAPS 既有 intrinsic/extrinsic 數值**完全未變**
- [ ] `PmccRankingService` RSpec ≥7 case：KS≤KL 淘汰 / **long.dte < short.dte+180 淘汰** / PL≥spread 標 fail 且 fail_reason 含數值 / PL<spread 標 pass / mid 缺值跳過不以 0 代 / 三到期日分桶正確 / 排序依 `max_profit`(含SC) 高→低每桶前 5
- [ ] **年化收租率**有計算且顯示：同 symbol 的 6 DTE 與 45 DTE 候選，未年化收益率相近但年化後差異顯著
- [ ] **Delta 兩區間並存**：Delta 0.17 的 Short Call **有列出**（0.15–0.40 粗篩內）但**未打 ✅**（不在 0.20–0.35）
- [ ] Python：`py_compile` 過；單測涵蓋 Delta 篩選、`oi_change` unch→null、moneyness 正負、theoretical_price
- [ ] `fetch_pmcc_short_calls` spec：mock `run_scraper` success → assert delete_all + insert_all
- [ ] Controller：有 LEAPS+Short 資料時 `@pmcc_ranking` 非 nil，PageComponent 渲染不拋

### ★ 核心情境 E2E（結案前置條件）

- [ ] **不帶任何選填參數的最基本查詢實跑一次**（`/leaps?symbol=NOK`，**不帶 user_strike**）。只測過帶 user_strike 的情境不算通過。
- [ ] 該次查詢的 PMCC 三到期日皆有資料、表格每列數值皆有值（無 NaN、無空白）

### ★ lesson9 對帳

- [ ] 取 §12 範例 A 的數字（KL=10, PL=5.75, KS=17, PS=0.42）輸入 `option-basics-lesson9.html` 的計算器，**逐項比對** lesson9 輸出與 `PmccRankingService` 輸出（spread / passes / netDebit / maxProfit）。附兩邊輸出截圖。
- [ ] 若 lesson9 的 `maxProfit` 對應本規格的 `max_profit_no_sc`，在對帳報告中明確指出對應關係

### 瀏覽器

- [ ] `/leaps?symbol=NOK` → Options Flow 後出現 PMCC 區塊三到期日標籤，表格含 PL/PS/Spread/NetDebit/**MaxProfit(含SC)**/**年化收租率**/Golden Rule，截圖
- [ ] 完整欄（Gamma/Theta/Moneyness/Theo./ITM Prob）在展開列可見，截圖
- [ ] **hover 淺紫實測**：用 Playwright 對表格列觸發 hover，以 `getComputedStyle(row).backgroundColor` 取**實際生效值**，確認為 `purple-200` 對應的 RGB。**每一列都要驗**，含黃金法則未通過的紅底列（紅底 + hover 仍須變紫）。驗的是渲染後生效值，不是 CSS 檔裡寫的 class，也不是截圖目測。
- [ ] **DTE 警示 badge**：`short.dte < 19` 的到期日桶標題出現橘黃警示 badge，且**該桶組合仍照常列出**（不因警示而被篩掉），截圖
- [ ] **手算驗證**：任選一列，手算 spread / net_debit / max_profit / 年化收租率，與頁面顯示逐項比對，附手算過程
- [ ] 教育說明區四張卡風格一致 lesson9、取色誤差 < 5、有資料時自動代入、無資料顯示「—」不 500，截圖
- [ ] 空狀態：新 symbol 無 Short 資料時顯示「尚無資料」非 500
- [ ] **PMCC 抓取失敗時 LEAPS 查詢仍正常**（實際觸發一次驗證）
- [ ] `bundle exec rspec` 綠燈

---

## §12 對照範例（供 RSpec 斷言）

**A — ✅通過**：KL=10, PL=5.75, KS=17, PS=0.42, long.dte=564, short.dte=6
```
spread = 7
(a) 17 > 10 ✅   (b) 564 ≥ 6+180 ✅   passes: 5.75 < 7 ✅
net_debit        = 5.33
max_profit_no_sc = 1.25
max_profit       = 1.67   ← 主排序鍵
premium_yield     = 0.42 / 5.33 = 7.9%
premium_yield_ann = 7.9% / 6 × 365 = 480%
實際：投入 $533/張、收租 $42/張、最大獲利 $167/張
```

**B — ❌前置(a)淘汰**：KL=260, PL=51.5, KS=250, PS=4.24
```
KS ≤ KL → fail_reason「Short Call履約價KS($250)必須大於LEAPS履約價KL($260)」
即便改 KS=265：spread=5，PL 51.5 ≥ 5 → ❌ "PL(51.50) >= Spread(5.00)"
```

**C — ❌前置(b)淘汰**：KL=10, PL=5.75, KS=17, PS=0.42, **long.dte=200, short.dte=45**
```
(a) 通過、passes 公式上也會過（5.75 < 7）
但 200 < 45+180=225 → 淘汰
fail_reason「LEAPS到期日(200天)距Short Call到期日(45天)不足180天，
            SC到期時LEAPS時間價值恐已大幅流失，最大獲利公式不成立」
```

**D — mid 缺值**：跳過不以 0 代，display「—」

**E — mid 一致性**：Barchart mid=0.24, bid=0.23, ask=0.26
```
mid_price 欄存 0.24（原值優先，非 0.245）
extrinsic_value 必須用 0.24 計算
```

---

## §13 實作順序

```
Step0  重構 derived_values 改為接收 mid 參數（§2.1）。LEAPS 呼叫端傳 (bid+ask)/2，
       跑 Phase H 的 NVTS fixture 回歸測試證明數值未變。先做，否則 Step3 會踩地雷。
Step1  DB：db:migrate:status 看 20260711054225。down → 直接改檔貼 §5 DDL 再 migrate；
       up → 另開 add_pmcc_columns migration 補欄。runner 驗 columns。
Step2  Python：pmcc_short_call_scraper.py（§6）；同步更新 leaps_scraper.py 的 STACKED_OPTIONS_JS
       補 oi_chg/mid。py_compile + 單測。
Step3  Ruby：BarchartScraperService#fetch_pmcc_short_calls + persist_pmcc_short_calls
       （§7，含 §2.1 mid 決定順序 + derived_values(mid)）。
Step4  PmccRankingService（§7，按 expiration_date 分桶非 DTE 範圍）。
       rails runner 用 §12 範例 A/B/C 驗證後寫 RSpec。
Step5  Job：ScrapeLeapsJob 接 fetch_pmcc_short_calls，try/catch 隔離。
Step6  Controller：index 載入 @pmcc_ranking，PageComponent 傳參。
Step7  Phlex：render_pmcc_section（§9.1）+ render_pmcc_edu_section（§9.2，CSS 移植 lesson9）。
Step8  tailwindcss:build + Playwright 截圖（改前/改後）。
Step9  §11 驗收全跑，rspec 綠燈，更新本檔 checklist 後 commit。
```

## §14 參考程式碼位置

```
lib/barchart_scrapers/leaps_scraper.py          · 完整範本
lib/barchart_scrapers/cdp_helper.py             · CDP 工具
lib/barchart_scrapers/test_leaps_scraper.py     · Python 單測範本
lib/barchart_scrapers/max_pain_scraper.py       · Expiration 下拉讀取模式
app/services/barchart_scraper_service.rb:270-320 · persist_leaps 範本
app/services/leaps_ranking_service.rb           · 純計算 service 範本
app/services/leaps_recommendation_service.rb    · 分組 + 理由文字範本
app/models/leaps_option_chain_snapshot.rb       · FRESH_WINDOW / derived_values / mid_price
app/models/strike_chain_snapshot.rb             · tolerance / valid_strike?
app/components/leaps_recommendations/page_component.rb · view_template / TABLE_COLS / fmt_*
option-basics-lesson9.html:990-1135             · 黃金法則公式唯一前端參考
option-basics-lesson9.html :root 1-150          · CSS token
config/routes.rb:12-16                          · leaps 路由
db/schema.rb                                    · leaps 表結構參考
```

---

# 進度追蹤（2026-07-11）

> 規則同 Phase J：狀態只有三種——`未開始`／`進行中`／`已完成（附證據）`。

## 實作進度（§13 Step0–7）

| Step | 項目 | 狀態 | 證據 |
|---|---|---|---|
| 0 | `derived_values` 改接收 `mid:` 參數 | 已完成（附證據） | `app/models/leaps_option_chain_snapshot.rb`；LEAPS 呼叫端傳 `(bid+ask)/2`；NVTS fixture 回歸測試數值不變；356→356 examples 全過 |
| 1 | DB migration（`pmcc_short_call_snapshots`） | 已完成（附證據） | 原 migration 狀態確認為 `down`，改檔補齊 §5 完整 DDL（29 欄）後 `db:migrate` 成功；欄位逐一比對 §5 清單全數存在 |
| 2 | Python scraper `pmcc_short_call_scraper.py` | 已完成（附證據） | 24 個單元測試全過；**真實 CDP 對 NOK 即時頁面驗證揪出規格本身兩個錯誤**：(a) §6 給的 `EXPIRATIONS_JS` 抓錯 select（改用 leaps_scraper 已驗證的 `className.includes('ng-')` 邏輯，實測 18 個到期日日期升序）(b) `change`/`percent_change` 欄位名寫錯（`r.change`→`r.priceChange`，`r.changePercent`→`r.percentChange`，實測修正前恆為 null，修正後有值）；`leaps_scraper.py` 同步補 `oi_chg` 並實測 |
| 3 | Ruby Service（`fetch_pmcc_short_calls`／`persist_pmcc_short_calls`） | 已完成（附證據） | `PmccShortCallSnapshot` model + `BarchartScraperService` 新方法；23 個測試涵蓋 mid 一致性（原始 midpoint 優先於 (bid+ask)/2）、mid 缺值 nil、partial 仍落地、delete_all scope 隔離 |
| 4 | `PmccRankingService` | 已完成（附證據） | 14 個測試，§12 範例 A/B/C 數字逐項比對相符；(a)(b) 未過保留＋fail_reason／(c) mid 缺值不列入；三桶分桶、桶內排序、Delta 兩區間並存、年化收租率分化，皆有對應測試 |
| 5 | `ScrapeLeapsJob` 接上 `fetch_pmcc_short_calls` | 已完成（附證據） | 獨立 `begin/rescue`；新增測試證明 PMCC 拋例外時 `leaps_job_#{job_id}` 仍寫入 LEAPS 的成功狀態、`perform_now` 不往外拋例外 |
| 6 | Controller 載入 `@pmcc_ranking` | 已完成（附證據） | `pmcc_ranking_for` helper（無候選／無 Short Call 資料 → `:no_data`，不硬跑空計算）；PageComponent 新增 `pmcc_ranking:` kwarg；2 個新 request spec |
| 7 | Phlex `render_pmcc_section` + `render_pmcc_edu_section` | 已完成（附證據） | 見下方「瀏覽器驗收」小節 |

## 瀏覽器驗收（Playwright，NOK 實測，2026-07-11）

用 dev DB 既有 129 筆 LEAPS 快照（touch `scraped_at` 使其 fresh）+ 手動 seed 7 筆 Short Call 快照（近似真實 Barchart 數值），實際開 `/leaps?symbol=NOK` 驗證：

- PMCC 區塊三到期日標籤（6/13/20 DTE）皆正確渲染，表格 12 關鍵欄 + 展開列皆有值
- **DTE 警示 badge**：13 DTE 桶正確顯示橘黃警示，且該桶組合照常列出（未被篩掉）
- **黃金法則未通過列**：紅底（`bg-red-50`）+ `fail_reason`（例："PL(6.25) >= Spread(6.00)"）正確顯示
- **hover 淺紫實測**（`getComputedStyle`，非目測非 class 檢查）：對紅底失敗列 hover，`backgroundColor` 從透明變為 `oklch(0.902 0.063 306.703)`（Tailwind purple-200），證實 hover 確實蓋過紅底生效
- **教育說明區四張卡**：無資料時全部顯示「—」不 500（symbol 未查詢狀態下截圖確認）；有資料時自動代入實際數字（黃金法則卡："NOK $7→$15 差價8.00 費用6.25 → ✅"；最大獲利卡："(15.00-7.00) - (6.25-0.11) = 1.86"；PMCC 定義卡：買100股成本$1,195／LEAPS成本$625／收租$11／資金比例52.3%）
- 空狀態（無 Short Call 資料）：request spec 確認顯示「尚無 Short Call 資料，請重新查詢」非 500
- 全套 `bundle exec rspec`：**397 examples, 0 failures**

## 未完成 / 待決事項（誠實記錄，不假裝已完成）

- [ ] **★ 核心情境 E2E 真實抓取**：`/leaps?symbol=NOK` 不帶 `user_strike`，**從空白狀態走完整條 job 流程**（`ScrapeLeapsJob` → 真實 CDP 抓 LEAPS + PMCC Short Call → persist → 渲染）尚未跑過。目前瀏覽器驗收用的是「既有 LEAPS 快照 touch 成 fresh ＋ 手動 seed 的 PMCC 資料」，不是真實 job 觸發的一條龍流程。scraper 本身（Python 層 JS 抓取邏輯）已對 Barchart 即時頁面驗證過，但**沒有驗證過 job → `fetch_pmcc_short_calls` → `persist_pmcc_short_calls` 這段接線在真實 CDP 環境下跑一次完整成功**。
- [ ] **★ lesson9 對帳**：規格要求把 §12 範例 A 的數字實際輸入 `option-basics-lesson9.html` 的計算器逐項比對。這個檔案不在本 repo 內，`localhost:8765` 也未啟動（`ERR_CONNECTION_REFUSED`），本次**沒有機會做這項對帳**。目前的替代驗證是：`spec/services/pmcc_ranking_service_spec.rb` 已經用範例 A 的原始數字（KL=10, PL=5.75, KS=17, PS=0.42, dte=564/6）跑過 `PmccRankingService`，逐項斷言 spread/net_debit/max_profit/premium_yield/premium_yield_ann 與規格給的期望值相符——這驗證了「本專案公式實作」與「規格文件寫的公式」一致，但**未驗證過「規格文件寫的公式」與「lesson9 計算器本身」一致**，兩者不是同一件事。
- [ ] 手算驗證（任選一列手算 spread/net_debit/max_profit/年化收租率，與頁面顯示逐項比對，附手算過程）：未做書面手算記錄，等同前項以 RSpec 精確數值斷言替代，但規格要求的是「人工拿計算機算一次」這個動作本身，尚未執行。

**這三項都需要使用者提供環境（真實登入 Barchart 的 Chrome session／lesson9 網頁能連上）才能完成，AI 端目前無法自行補完。**

## 變更記錄

| 日期 | 內容 |
|---|---|
| 2026-07-11 | Step0–7 全部實作完成；發現並修正規格 §6 兩個 JS 錯誤（expiration 下拉選錯 select、change/percent_change 欄位名錯誤）；瀏覽器驗收完成；三項需要真實環境才能補完的驗收項誠實記錄為未完成 |

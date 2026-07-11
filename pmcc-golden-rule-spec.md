# PMCC 黃金法則區塊規格 — Options Flow後新增

> 目標：在 `/leaps` 已有區塊下方新增 PMCC 自動組合試算，遵守 `option-basics-lesson9.html` 黃金法則。使用者僅輸入 `symbol`（如 NOK），程式自動完成 LEAPS + 三到期日 Short Calls 抓取、黃金法則組合、列出適合做 PMCC 的標的與權利金細項。全程自動化，無手算。

## 需求來源

「在 Options Flow 後面新增一區塊，主程式目前輸入美股股票代號，無需提供履約價即會顯示適合做 leaps 的標的。這個新的區塊要讀取輸入代號後得到的資料，並依履約價區間抓三個時間段（資料從 Barchart 讀取，付費帳戶），並遵行 option-basics-lesson9.html 的黃金法則，列出適合做 PMCC 的標的。列出適合做 CC 的履約價也一併列出需支付的權利金等細項。」

後續截圖釐清：
- **三時段 = Barchart Options Prices 頁面 `Expiration:` 下拉選單的前三個到期日**（如 `2026-07-17 (m)` / `2026-07-24 (w)` / `2026-07-31 (w)`），不是 DTE 範圍。
- **Short Leg 完整欄位**：兩張截圖（Options Prices + Volatility & Greeks）含建倉所需的全部欄位，必須全存（見 §5）。
- **教育說明區**：在 PMCC 表格後面，新增與 `option-basics-lesson9.html` 同風格的黃金法則/最大獲利/建倉規範/PMCC定義說明，CSS 同源（見 §8）。

---

## §0 前置閱讀（接手必讀）

1. 本檔全文（§1-§9 為最新權威，舊版 DTE 15-30/31-50/51-90 已作廢，以 §2 為準）
2. `leaps-call-recommendation-spec.md`：核心原則（禁止內部API、CDP兩層檢查、fresh window、三層驗證）、Phase A抓取策略、資料庫設計
3. `option-basics-lesson9.html:990-1135`：`ks<=kl` 檢查、`spread=ks-kl`、`netDebit`、`maxProfit`、`passes=pl<spread` 公式與錯誤文案
4. 現有實作（精確路徑）：
   - `lib/barchart_scrapers/leaps_scraper.py`（兩階段骨架、JS snippets、chain_snapshot修復）
   - `lib/barchart_scrapers/cdp_helper.py`（`prepare_page`, `cdp_eval`, `cdp_navigate`, `_wait_for_grid`）
   - `lib/barchart_scrapers/max_pain_scraper.py`（`expiration` 下拉讀取模式，供 PMCC 參考）
   - `app/services/barchart_scraper_service.rb`（`fetch_leaps`, `persist_leaps`, `run_scraper`）
   - `app/jobs/scrape_leaps_job.rb`（`leaps_job_{id}` / `leaps_last_errors_{symbol}` cache）
   - `app/models/leaps_option_chain_snapshot.rb`（`FRESH_WINDOW` 唯一定義、`derived_values` 公式、`mid_price`）
   - `app/controllers/leaps_recommendations_controller.rb`（`fresh_for?` 唯一權威、`cdp_online?`）
   - `app/components/leaps_recommendations/page_component.rb`（`view_template` 順序、`TABLE_COLS`, `LIQUIDITY_STYLE`, `fmt_*`）

## §1 現況與鐵律

- DB 已有 `leaps_option_chain_snapshots`、`strike_chain_snapshots`、`options_flow_trades`。`pmcc_short_call_snapshots` 的 migration `20260711054225` 已建檔但曾中斷，接手第一步 `bundle exec rails db:migrate:status` + `db:migrate`。
- 現有 LEAPS 流程：輸入 `symbol` (+選填 `user_strike`) → `fresh_for?` → CDP預檢 → `ScrapeLeapsJob` → `leaps_scraper.py` → persist + 刷新 Flow → cache job狀態 → 前端輪詢 → index 渲染。PMCC 沿用此流程，不另開觸發路徑。`user_strike` 存在時，Short Call 中心點仍用 auto OTM，不被它影響。
- **專案鐵律**（主規格延伸，PMCC 同樣遵守）：禁止 `/proxies/core-api/` 內部API；禁止 Black-Scholes 反推 Delta；禁止 `last_price` 作權利金基準（用 `Mid=(bid+ask)/2`）；禁止第二個 `30.minutes` 字面值（引用 `FRESH_WINDOW`）；禁止發明新色票（用 `SIGNAL_COLORS`）；Short Call 獨立表；`fresh_for?` 唯一權威。

## §2 三時段正解與黃金法則

### 三時段定義（以本節為準，舊版 §3 DTE範圍作廢）

- **三時段 = `Expiration` 下拉的前三個到期日**，按 DOM 順序（已按日期升序），含 m/w 不區分，如 `["2026-07-17 (m)", "2026-07-24 (w)", "2026-07-31 (w)"]`。
- 若下拉僅 1-2 個，有幾個抓幾個。DTE 自然落在 6-50 天，符合 lesson9 19-45 天建議的精神，不需 DTE 硬性過濾。
- PMCC 按**到期日字串**分桶，非 DTE 範圍。前端 label 顯示實際到期日字串（如 `2026-07-17 (m) · 6 DTE · 月選`）+ 近/中/遠月 badge。

### 黃金法則公式（唯一定義，對齊 lesson9:1047-1135）

```
PL = Long LEAPS Mid = (bid+ask)/2（或 Barchart midpoint原值）
PS = Short Call Mid 同理（權利金基準必須用Mid，不得用last_price，Phase H唯一定義）
KL = Long LEAPS strike
KS = Short Call strike
spread = KS - KL
前置：KS > KL，否則淘汰，文案沿用lesson9：「Short Call履約價KS($xxx)必須大於LEAPS履約價KL($yyy)」
passes = PL < spread（嚴格小於）
netDebit = PL - PS
maxProfit = spread - PL
maxProfitWithSC = spread - netDebit = maxProfit + PS
roi = PS / PL *100%（PS>0才算）
```

`maxProfit` 不含 SC、`maxProfitWithSC` 含 SC，兩者都顯示。

## §3 資料流

```
輸入 symbol (+選填 user_strike)
  → LeapsRecommendationsController#analyze
    ├─ StrikeChainSnapshot fast-path（沿用）
    ├─ fresh_for?（LEAPS，沿用）
    ├─ cdp_online?（沿用）
    └─ ScrapeLeapsJob(symbol, job_id, user_strike:)
        ├─ fetch_leaps(user_strike:) → leaps_scraper.py → persist_leaps + chain_snapshot + 刷新Flow（沿用）
        ├─ fetch_pmcc_short_calls(NEW) → pmcc_short_call_scraper.py → persist_pmcc_short_calls
        │   └─ 狀態 success/partial/no_candidates/barchart_session_expired/error
        └─ PmccRankingService.new(symbol).call → Rails.cache "pmcc_{symbol}"（可選，FRESH_WINDOW）

Controller#index
  ├─ LeapsRankingService → @candidates
  ├─ LeapsRecommendationService → @recommendation
  ├─ LeapsOptionsFlowPanelService → @flow_panel
  └─ PmccRankingService(NEW) → @pmcc_ranking
       讀 leaps最新batch + pmcc_short_call_snapshots最新batch
       按3到期日分桶 × 黃金法則 → 每到期日前5
       { 2026-07-17:{expiration,combos,has_passing}, 2026-07-24:{...}, 2026-07-31:{...},
         near_term/mid_term/far_term別名, summary:{total,passing,leaps_count,short_count,symbol,expirations}, status }
PageComponent
  ├─ render_pmcc_section(@pmcc_ranking)      # §6 三到期日表格
  └─ render_pmcc_edu_section                  # §8 教育說明，獨立於資料，無資料也不崩
```

Short Call 失敗不可讓 LEAPS 查詢變 error，PMCC 區塊顯示「暫無資料」即可（同 Flow失敗不影響排行）。

## §4 DB

### 現狀處置

`20260711054225_create_pmcc_short_call_snapshots.rb` 曾中斷：
- 若 `down`：直接改檔加入 §4.1 完整欄位再 `db:migrate`。
- 若 `up`：另開 `add_missing_columns_to_pmcc_short_call_snapshots` 補欄。

### §4.1 完整 DDL（最終表，精確到欄）

欄位來源：兩張截圖（Options Prices + Volatility & Greeks，`(strike,expiration)` Merge）。`option_type` 預設 Call，雖 PMCC 只取 Call 仍保留。

```ruby
create_table :pmcc_short_call_snapshots do |t|
  t.string   :symbol,             null: false
  t.date     :expiration_date,    null: false
  t.integer  :dte
  t.decimal  :strike,             precision: 10, scale: 4, null: false
  t.string   :option_type,        null: false, default: "Call"
  t.decimal  :bid,                precision: 10, scale: 4
  t.decimal  :ask,                precision: 10, scale: 4
  t.decimal  :mid_price,          precision: 10, scale: 4  # Barchart midpoint原值，供對照
  t.decimal  :last_price,         precision: 10, scale: 4
  t.decimal  :moneyness,          precision: 8, scale: 4   # 如+3.54%存0.0354
  t.decimal  :underlying_price,   precision: 10, scale: 4
  t.decimal  :change,             precision: 10, scale: 4
  t.decimal  :percent_change,     precision: 8, scale: 4   # 如-37.61%存-0.3761
  t.integer  :volume
  t.integer  :open_interest
  t.integer  :oi_change                                # OI Chg，unch存NULL
  t.decimal  :vol_oi_ratio,       precision: 8, scale: 4
  t.decimal  :iv,                 precision: 8, scale: 6
  t.decimal  :delta,              precision: 8, scale: 6
  t.decimal  :gamma,              precision: 10, scale: 6  # NEW: Gamma風險
  t.decimal  :theta,              precision: 10, scale: 6  # NEW: 收租核心
  t.decimal  :vega,               precision: 10, scale: 6
  t.decimal  :rho,                precision: 10, scale: 6
  t.decimal  :theoretical_price,  precision: 10, scale: 4  # Theor.
  t.decimal  :itm_probability,    precision: 8, scale: 6   # 被指派機率，★必填
  t.decimal  :intrinsic_value,    precision: 10, scale: 4  # Ruby derived_values算
  t.decimal  :extrinsic_value,    precision: 10, scale: 4
  t.date     :last_trade_date
  t.datetime :scraped_at,         null: false
  t.timestamps
end
add_index :pmcc_short_call_snapshots, [:symbol, :expiration_date, :strike], unique: true, name: "idx_pmcc_short_unique"
add_index :pmcc_short_call_snapshots, [:symbol, :scraped_at], name: "idx_pmcc_short_symbol_scraped"
```

Derived：`intrinsic = max(0, underlying-strike)` Call，`extrinsic=mid-intrinsic`，`bid_ask_spread_pct=(ask-bid)/mid`，公式唯一來源 `LeapsOptionChainSnapshot.derived_values`，PMCC 禁止重寫。

中間橫幅 `ATM IV/Historic Vol/IV Rank/Expiration DTE` 為批次 metadata，寫 `fetch_logs.error_detail` JSON 或 Rails.cache 即可，不強制落地。

### Model：`app/models/pmcc_short_call_snapshot.rb`

複製 Leaps model 寫法：`FRESH_WINDOW` 引用 `LeapsOptionChainSnapshot::FRESH_WINDOW`（禁止自訂）、`scope :for_symbol`, `scope :fresh`, `def mid_price` 回 `(bid+ask)/2` 或 `mid_price` 欄位 fallback、`validates`、`self.fresh_for?(symbol)`（不需 user_strike 維度）。

## §5 Python抓取器：`lib/barchart_scrapers/pmcc_short_call_scraper.py`

### 與 LEAPS 差異對照

| 項 | LEAPS（參考） | PMCC Short（本次） |
|----|---------------|--------------------|
| 選時段策略 | Delta≥0.60 ITM strike為中心，stacked全到期日 | 讀 Expiration下拉前3，每到期日 `?expiration=&moneyness=100` 全履約價 |
| 請求數 | N strikes×2頁 | 3 expirations×~2頁(Options+V&G)=~6次導航，20-40秒 |
| 最終篩選 | DTE≥364, Delta 0.60-0.90 | 不在Python硬濾，交Ruby Delta 0.15-0.40、OI排序（避免誤刪） |
| chain_snapshot | 需LEAPS到期日修復 | 可選，Fail不影響PMCC |

### Stage 1：讀 Expiration下拉 + NTM

1. 進入 `https://www.barchart.com/stocks/quotes/{SYMBOL}/options`（NTM預設）。
2. 讀 Expiration下拉全部選項：
```javascript
const sel = document.querySelector('select[name="expiration"]') ||
  [...document.querySelectorAll('select')].find(s => [...s.options].some(o => /20\d{2}-/.test(o.value)));
const expirations = [...sel.options].map(o => o.value.trim()).filter(v => /20\d{2}-/.test(v));
// e.g. ["2026-07-17 (m)", "2026-07-24 (w)", ...]
```
   取前3 `selected_expirations = expirations.slice(0, 3)`。
3. 同步讀 `underlying_price`（`UNDERLYING_JS`）與 NTM Call strikes/Delta（`NEAR_MONEY_JS`，可選）。

### Stage 2：逐到期日抓取

對每個 `exp`：
1. URL：`https://www.barchart.com/stocks/quotes/{SYMBOL}/options?expiration={exp_value}&moneyness=100`
   - `exp_value` 原始value可能含 `string:` 前綴，參考 `max_pain_scraper.py` / `build_max_pain_args` 轉換，需實測。
2. `cdp_navigate` + `_wait_for_grid(STACKED_OPTIONS_JS擴充版)` 讀該到期日全部 Call 行。空則 `_confirm_empty` 二次確認，超時30秒則 `SESSION_EXPIRED_JS` 分類 `session_expired` vs `page_load_timeout` 回 `partial`。
3. 累加至 `all_rows`。

V&G補抓（可選）：每到期日導航 `volatility-greeks?expiration={exp_value}`，用擴充版 V&G JS 讀 `theoretical, gamma, theta, vega, rho, itm_prob, vol_oi`，`_merge_vg` 以 `(strike, expirationDate)` 合併。

### JS Snippets（擴充版，二合一）

Options Prices（圖A）：
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
V&G（圖B擴充）：
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
批次橫幅（ATM IV/IV Rank，可選）：
```javascript
(()=>{const t=document.body.innerText||'';const atm=(t.match(/Implied Volatility \(ATM\)\s*:\s*([\d.]+)%/)||[])[1];const hist=(t.match(/Historic Volatility\s*:\s*([\d.]+)%/)||[])[1];const rank=(t.match(/IV Rank\s*:\s*([\d.]+)%/)||[])[1];return {atm_iv:atm?parseFloat(atm)/100:null,hist_vol:hist?parseFloat(hist)/100:null,iv_rank:rank?parseFloat(rank)/100:null};})()
```

輸出 JSON（stdout，對齊 leaps）：
```json
{"status":"success","rows":[{"expiration_date":"2026-07-17","dte":6,"strike":13.0,"bid":0.23,"ask":0.25,"mid":0.24,"last_price":0.23,"moneyness":-0.045,"volume":5285,"open_interest":26278,"oi_change":3912,"delta":0.3339,"iv":0.7163,"gamma":0.3185,"theta":-0.0349,"vega":0.0058,"rho":0.0006,"theoretical_price":0.24,"itm_probability":0.3158,"vol_oi_ratio":0.20,"underlying_price":12.44}], "underlying_price":12.44}
```
失敗：`barchart_session_expired` / `partial`（`expired_at_strike`+`expired_layer`+`reason`+`skipped_strikes` / `skipped_expirations`）/ `error` / `no_candidates`，供 `run_scraper` 共用解析。

同時更新 `leaps_scraper.py` 的 `STACKED_OPTIONS_JS` 補 `oi_chg/mid`，同步受益不算越界。

## §6 Ruby Services

### `BarchartScraperService` 擴充

```ruby
def fetch_pmcc_short_calls
  # cdp_available? guard
  # run_scraper("pmcc_short_call", extra_args: [])
  # case: barchart_session_expired/success/partial/no_candidates/error
  # persist_pmcc_short_calls(data) on success/partial
  # log_fetch("pmcc_short", status, detail)
end

def persist_pmcc_short_calls(data)
  rows = data["rows"]; return if rows.blank?
  now = Time.current
  # records 必須含 §4.1 全部欄位：gamma/theta/rho/theoretical_price/mid_price/moneyness/oi_change/change/percent_change/last_trade_date/intrinsic_value/extrinsic_value
  # intrinsic/extrinsic 用 LeapsOptionChainSnapshot.derived_values 算，禁止重寫
  # 防護：expiration_date/strike blank check >0 raise 人話錯誤
  # transaction { where(symbol:@symbol).delete_all; insert_all(records) }
end
```
`run_scraper` 已通用，檔名符合 `{type}_scraper.py` 即可。

`mid_price` 優先取 Barchart `mid` 原值，無則 `(bid+ask)/2` fallback。`moneyness` 存小數（如 -0.045 = -4.5%）。`oi_change` `unch`→NULL。`last_trade_date` 解析 `MM/DD/YY`。

### `PmccRankingService` (NEW)

**職責**：純計算，吃 DB最新兩batch，產黃金法則組合，不打Barchart不寫DB。

常數：
```ruby
SC_EXPIRATION_COUNT = 3
TOP_SHORT_PER_EXPIRATION = 8
TOP_COMBOS_PER_EXPIRATION = 5
DELTA_SHORT_MIN = 0.15; DELTA_SHORT_MAX = 0.40
TOP_LEAPS_PER_GROUP = 3
```

步驟：
1. `fetch_leaps_candidates`：`LeapsOptionChainSnapshot` 最新batch，`LeapsRankingService.new(symbol).call` 已得 liquidity tiers，近天期364-550/遠天期550+各取前3。
2. `fetch_short_candidates`：`PmccShortCallSnapshot` 最新batch，按 `expiration_date` 分組取前3到期日（按日期升序），每桶 `delta 0.15-0.40` 粗篩後 OI降序取前8。
3. `cross_and_filter`：LEAPS(6)×SC(≤24)=≤144組合，跳過 `KS<=KL`，mid缺值跳過，`spread=KS-KL`，`passes=PL<spread`，未過也保留供fail文案。
4. `enrich_combo`：`net_debit, max_profit, max_profit_with_sc, roi`，`leaps_delta_ok(l≥0.80)/short_delta_ok(0.20-0.35)` 供✅/⚠️。
5. `bucket_and_sort`：按到期日分桶，每桶 passes在前，同組 `max_profit_with_sc`高→低，取前5。
6. 輸出：
```ruby
{
  "2026-07-17": { expiration:"2026-07-17 (m)", expiration_date:Date, combos:[{long_leg:{strike:KL,mid:PL,bid,ask,delta,dte,oi,expiration_date,intrinsic,extrinsic}, short_leg:{strike:KS,mid:PS,bid,ask,theoretical_price,moneyness,delta,gamma,theta,vega,iv,itm_probability,vol,oi,vol_oi_ratio,oi_change,expiration_date}, spread,net_debit,max_profit,max_profit_with_sc,roi,passes_golden_rule,fail_reason},...], has_passing:bool },
  "2026-07-24": {...}, "2026-07-31": {...},
  near_term:->{同第一到期日}, mid_term:->{第二}, far_term:->{第三}, # 別名相容舊模板
  summary:{total_combos,passing_combos,leaps_count,short_count,symbol,expirations},
  status: :ok|:no_leaps|:no_short|:no_data
}
```

## §7 Controller & Job

`ScrapeLeapsJob#perform`：
- 既有 `fetch_leaps` 後接 `fetch_pmcc_short_calls`，Short Call失敗用 try/catch 隔離，不讓整job rescue成error。`PmccRankingService` 結果可寫 `Rails.cache "pmcc_#{symbol}"`，expires `FRESH_WINDOW`。

`LeapsRecommendationsController#index`：
- 既有 `@candidates/@recommendation/@flow_panel` 後，若 `@candidates.any?` 且 `PmccShortCallSnapshot.for_symbol(@symbol).exists?`，則 `@pmcc_ranking = PmccRankingService.new(@symbol).call`，否則 `status: :no_data`，傳 `PageComponent.new(..., pmcc_ranking: @pmcc_ranking)`。
- `fresh_data_exists?` 短期複用 LEAPS fresh，後續可加 `PmccShortCallSnapshot.fresh.exists?`，MVP先不擋。

`analyze` 不需額外參數，Short Call為內部 side-effect。

## §8 Phlex 前端

`PageComponent#view_template` 順序：
```
render_header → render_search_form → render_status_bar → render_recommendation → render_ranking_table → render_flow_panel → render_pmcc_section → render_pmcc_edu_section → render_vocab_cards + scripts
```
`render_pmcc_edu_section` 無資料也要獨立渲染，自動代入值無資料時顯示 —。

### §8.1 PMCC 表格（`render_pmcc_section`）

Header：`⚖️ PMCC黃金法則組合 — #{@symbol}` + 公式 reminder `PL < KS-KL · 每到期日前5` + summary bar `總組合 N / 通過 M`。

三到期日卡片（垂直堆疊，單欄防過窄）：`render_pmcc_bucket(key, label, bucket_data)`，label為實際到期日字串 `2026-07-17 (m) · 6 DTE` + 近/中/遠月 badge。

`render_pmcc_table(combos)`：`overflow-x-auto`，精簡預設12關鍵欄（KL/PL/Delta/KS/PS/Delta/DTE/Spread/NetDebit/MaxProfit+SC/ROI/判定），其餘 Gamma/Theta/Theo./Moneyness 放 `details/summary` 展開列（參考 Concept Cards）。

完整欄位（25欄，實作可先12關鍵+展開）：

| 分組 | 欄位 | 來源 | 格式/風控 |
|------|------|------|-----------|
| Long | 履約價 KL | long.strike | 藍 $xx.xx |
| Long | PL Mid | long.mid | $x.xx，金規則分子 |
| Long | Bid/Ask | | 流動性 |
| Long | Delta | long.delta | 0.8xxx + ✅≥0.80 |
| Long | DTE/OI/Vol | | |
| Short | 到期日 | short.expiration_date | YYYY-MM-DD (m/w badge)，三時段分組 |
| Short | 履約價 KS | short.strike | 紅 $xx.xx，金規則分母 |
| Short | PS Mid | short.mid_price/(bid+ask)/2 | $x.xx，收入 |
| Short | Bid/Ask/Theo. | | Theo.與Mid對比%差 |
| Short | Moneyness | short.moneyness | +x%綠/-x%紅，沿用截圖 |
| Short | Delta | short.delta | ✅ if 0.20-0.35 |
| Short | Gamma/Theta/Vega/IV/ITM Prob% | short.* | Gamma>0.20 ⚠️；Theta收租；★必填 |
| Short | Vol/OI/Vol/OI / OI Chg | | 流動性，+綠-紅-unch紫 |
| 計算 | Spread/NetDebit/MaxProfit/MaxProfit+SC/ROI | KS-KL / PL-PS / ... | 綠>0紅<0，主排序MaxProfit+SC |
| 判定 | Golden Rule | passes? | ✅通過/❌ + fail_reason |

樣式：`SIGNAL_COLORS` 綠通過、紅未過、橘警告；表格奇偶 `bg-gray-50/50`、hover `hover:bg-purple-200`；失敗列 `bg-red-50`；沿用 `fmt_*` helpers；定義新常數 `PMCC_TABLE_COLS`。左右分組表頭可 `colspan` 分色（Long Group/Short Group/Calc Group）。

無資料：`status :no_short` 顯示「尚無Short Call資料，請重新查詢」；`combos.empty?` 顯示「此到期日無KS>KL組合」。

### §8.2 教育說明區（`render_pmcc_edu_section`）

來源：`option-basics-lesson9.html` 首屏黃金法則(黃盒)+最大獲利(綠盒)+建倉規範(右小卡)+PMCC定義(What is PMCC大白卡)。置於 PMCC表後、`render_vocab_cards` 前。

**CSS Token（精確移植lesson9 `:root`，禁止重設計）**：
```
bg #FAF3E8 / page-bg #FFF9F2 / panel-bg #FFFCF7 / ink #2A1A0E / muted #7A6555 / border #E2D4C2
gold #D4900A / gold-bg #FEF4D8 / gold-bdr #E8B840 / 黃盒 #FFF7C0
green #2E9E52 / green-bg #E8F8EE / green-bdr #8ED4A8 / 綠盒 #F0FAF0
red #D04040 / red-bg #FDEAEA / red-bdr #F5AAAA / blue #3A70C0 / blue-bg #EBF2FF / blue-bdr #9ABCE8
r-lg 16px / r-md 10px / r-sm 6px
```
落實：根容器 `pmcc-edu-root` scoped，複製 `.hfb`, `.hfb-row.gold-row/green-row`, `.hfb-icon/title/formula/note/detail`, `.contract-box/.cb-title/ticker/grid/item`, `.full-card/.tag-row/.step-badge/.pill/.pill-outline/.ptitle/.bullets/.bullet/.bullet-num` 為 scoped版，或用 `bg-[#FFF7C0]` arbitrary values。驗收取色誤差<5。

**文案3卡**（全自動代入，不提手算）：

1. 黃金法則黃盒：`#FFF7C0 + 1.5px #E8B840 + 10px radius + 10/14 padding`，icon ⚖，title `黃金法則（建倉前必驗算）`，formula `LEAPS買入成本 < Short Call履約價 − LEAPS履約價` (gold)，? tooltip沿用 `leaps-q` 藍圓，note `差價=KS-KL代表最多能賺多少（由程式自動算，列於PMCC表Spread欄）` + `費用超過差價即使方向對仍保證虧損`（保證虧損紅粗）。自動代入：`{symbol} {KL}→{KS} 差價{spread} 費用{PL} PL<差價? ✅/❌` 取第一組通過，無則第一組失敗+原因。

2. 最大獲利綠盒：`#F0FAF0 + #8ED4A8`，title `最大獲利=差價−淨成本`，formula `(KS−KL)−(PL−PS)` (green)，detail `漲至KS以上時實現，由程式自動算，列於Max Profit欄`。自動代入 `Max Profit=(KS-KL)-PL=...`。

3. 建倉規範小卡 + PMCC定義大白卡：
   - 小卡 `.contract-box`：`#FEF4D8+2px #E8B840+16px radius+14/16 padding`，title `📐 建倉規範` (gold 10px uppercase)，ticker `PMCC·黃金法則`，2×2 grid：Long Delta≥0.80藍/DTE≥180天藍/Short Delta 0.20-0.35紅/DTE 19-45天紅（附註：本表抓最近三到期日天然6-50天）。
   - 大白卡 `.full-card`：`#FFFCF7+2px #E2D4C2+16px radius+20 padding`，header 黑圓26px「1」+ `WHAT IS PMCC` + pill `窮人版備兌買權`，title `PMCC=LEAPS Long Call+Short Call`，bullets ①②③④ 橘框圓22px：① 100股成本 `underlying×100` 自動帶入，② LEAPS成本 `PL×100` 自動帶入，③ 短期虛值 Short Call 最近三到期日6-50 DTE Delta 0.20-0.35 收租PS自動列，④ 資金比例 `PL×100/(underlying×100)%` 自動算。底部免責灰小字。

Phlex簽名：
```ruby
def render_pmcc_edu_section; div(class:"pmcc-edu-root space-y-4"){render_pmcc_edu_golden_rule; render_pmcc_edu_max_profit; render_pmcc_edu_build_rules; render_pmcc_edu_what_is_pmcc}; end
```

## §9 錯誤與快取

- 沿用 `leaps-call-recommendation-spec.md` 第8節5種分流，新增：
  - Short `partial` → 黃alert「Short Call在Strike X時V&G中斷，已抓部分用於組合」
  - `no_short_candidates` → 藍提示「近三到期日無Delta 0.15-0.40的Short Call，可能流動性不足」
  - `KS<=KL` 組不出 → 前端bucket顯示「無KS>KL組合」，不算後端錯誤
- PMCC失敗不可讓LEAPS整查詢error（同Flow）。
- Fresh：`LeapsOptionChainSnapshot::FRESH_WINDOW` 單一定義，`PmccShortCallSnapshot.fresh` 同 `where(scraped_at: FRESH_WINDOW.ago..)`，`Rails.cache "pmcc_#{symbol}"` 可選同expires。
- Moneyness配色：+綠-紅；Change/OI Chg：+綠-紅-unch紫；Strike藍；Delta ✅/⚠️；Theta Short視角 `+0.03/day收租`；Gamma>0.20 ⚠️。

## §10 驗收

- [ ] `db:migrate:status` → `pmcc_short_call_snapshots` up，`columns` 含 §4.1 全部（含 gamma/theta/rho/theoretical_price/mid_price/moneyness/oi_change/change/percent_change/option_type/last_trade_date/intrinsic/extrinsic）
- [ ] Model：`fresh`, `mid_price`, `for_symbol`, `fresh_for?` 存在
- [ ] `PmccRankingService` RSpec ≥5 case：KS≤KL淘汰 / PL≥spread標fail+fail_reason含數值 / PL<spread標pass / 三到期日分桶正確 / 排序maxProfitWithSC高→低每桶前5
- [ ] Python：`py_compile` 過；`TestPickShortCallCandidates` Delta 0.15-0.40 + buffer + oi_change unch→null + moneyness正負 + theoretical_price
- [ ] `BarchartScraperService#fetch_pmcc_short_calls` spec：mock `run_scraper` success assert delete_all+insert_all
- [ ] Controller：有LEAPS+Short資料時 `@pmcc_ranking` 非nil，PageComponent渲染不拋（`spec/requests/leaps_recommendations_spec.rb` 全過）
- [ ] 瀏覽器：
  - [ ] `/leaps?symbol=NOK` Options Flow後出現PMCC區塊三到期日標籤，表格含PL/PS/Spread/NetDebit/MaxProfit/ROI/Golden Rule，截圖
  - [ ] 表格含Gamma/Theta/Moneyness/Theo./ITM Prob等完整欄（或展開列），截圖
  - [ ] 自動計算驗證：任選一列，頁面Spread/PL/passes由`PmccRankingService`自動判定一致，無手算
  - [ ] 教育說明區：黃金法則黃盒+最大獲利綠盒+建倉規範+PMCC定義卡，風格一致lesson9，取色誤差<5，有資料時自動代入KL→KS差價，無資料時顯示—不500，截圖
  - [ ] 空狀態：新symbol無Short資料時PMCC顯示「尚無資料」非500
- [ ] `bundle exec rspec` 綠燈

## §11 實作順序

```
Step1 DB: status看20260711054225，若down直接改檔貼§4.1 DDL再migrate，若up另開add_pmcc_columns migration補gamma/theta/rho/theoretical/mid/moneyness/oi_change/change/percent_change/option_type/last_trade_date/intrinsic/extrinsic；runner驗columns
Step2 Python: 新增pmcc_short_call_scraper.py（§5 Stage1讀Expiration前3+Stage2逐到期日moneyness=100+ V&G擴充版JS）；同步更新leaps的STACKED JS補oi_chg/mid；py_compile+單測
Step3 Ruby Service: BarchartScraperService fetch_pmcc_short_calls + persist_pmcc_short_calls（含§4.1全欄+derived_values）；run_scraper命名符合
Step4 Ranking: pmcc_ranking_service.rb（§6按expiration_date分組，非DTE範圍）；rails runner假資料驗證KL=10 PL=5.75 KS=17 PS=0.42→spread7 pass true max1.25 maxSC1.67 / KL=260 KS=250→淘汰；RSpec
Step5 Job: ScrapeLeapsJob fetch_leaps後接fetch_pmcc_short_calls，try/catch隔離，cache pmcc_{symbol}可選
Step6 Controller: index載入@pmcc_ranking，PageComponent參數pmcc_ranking:
Step7 Phlex: render_pmcc_section（§8.1 25欄，預設12關鍵+展開）+ render_pmcc_edu_section（§8.2 3卡，CSS移植lesson9 :root，scoped）
Step8 樣式: tailwindcss:build + Playwright截圖（改前/改後）
Step9 測試文件: rspec全過，更新本檔驗收commit
```

## §12 參考程式碼位置

```
lib/barchart_scrapers/leaps_scraper.py · 完整範本
lib/barchart_scrapers/cdp_helper.py · CDP工具
lib/barchart_scrapers/test_leaps_scraper.py · Python單測範本
lib/barchart_scrapers/max_pain_scraper.py · Expiration下拉讀取模式
app/services/barchart_scraper_service.rb:270-320 · persist_leaps範本
app/services/leaps_ranking_service.rb · 純計算service範本
app/services/leaps_recommendation_service.rb · 分組+理由文字範本
app/services/leaps_options_flow_panel_service.rb · 獨立面板情緒參考範本
app/models/leaps_option_chain_snapshot.rb · FRESH_WINDOW+derived_values+mid_price
app/models/strike_chain_snapshot.rb · tolerance+valid_strike?
app/components/leaps_recommendations/page_component.rb · view_template順序/TABLE_COLS/LIQUIDITY_STYLE/fmt_*
option-basics-lesson9.html:990-1135 · 黃金法則公式唯一前端參考
:root 1-150 · CSS token（黃金法則/最大獲利/建倉規範/PMCC定義樣式）
config/routes.rb:12-16 · leaps路由
db/schema.rb · leaps表結構參考
```

## §13 對照範例（程式自動算，供RSpec斷言）

**A NOK — 程式自動判定✅**：KL=10 PL=5.75 KS=17 PS=0.42 spread=7 PL<7→✅ netDebit=5.33 maxProfit=1.25 maxSC=1.67 ROI 7.3%，資金575/張收42/張最大獲利167/張
**B KLAC倒掛 — 程式自動判定❌**：KL=260 PL=51.5 KS=250 PS=4.24 KS<=KL前置淘汰「KS($250)必須大於KL($260)」；即便KS=265 spread=5 PL≥5→❌ fail_reason "PL(51.50)>=Spread(5.00)"
**C AAPL高價 —**：Mid缺值跳過不以0代，display —，沿用Phase H規範。

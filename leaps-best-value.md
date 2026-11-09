# leaps-best-value.md — LEAPS 推薦改為「最低年化時間成本」最優解

## 問題回報（給使用者）

- **日期時間**：2026-11-09 18:17（Asia/Taipei）
- **頁面**：`https://fairprice-ohmy.com/leaps?symbol=NVDA`（未輸入履約價）
- **症狀**：「推薦分析」近天期推 $180 / 2028-01-21（Delta 0.656，外在佔比 84.3%，年化時間成本約 15.8%，需漲 19.1% 才損益兩平）；遠天期推 $120 / 2028-12-15（當日成交量僅 6）。同頁 2028-01-21 $125/$130/$140 年化時間成本只有 6.8–8.7%，流動性正常，卻沒被推薦。
- **主訴**：推薦結果是「OI 最高」，不是「最划算」。

## 找到的問題

1. 推薦邏輯以 OI 最大值選主推，沒有成本指標。
2. 沒有流動性門檻（OI、成交量、Spread）與成本指標的組合篩選。「近期無成交」依使用者決定不排除，照常列出。
3. Delta 下限沿用排行的 0.60，主推可能落在時間價值偏重的淺價內。

## 建議修改順序

S0 定位既有程式 → S1 成本計算與篩選服務（單元測試）→ S2 接上 controller（request spec）→ S3 前端顯示 → S4 E2E 核心案例驗收。

## 怎麼測試

S1 用本文「驗收基準資料」（2026-11-09 NVDA 實際頁面數值）跑單元測試，結果必須與「預期結果」完全一致；S4 用 Playwright 開核心網址（不帶履約價）截圖比對。

## 怎麼回報

每階段完成後 patch 狀態表；最終回報附：S4 截圖檔路徑、實際網址、DOM 擷取的近／遠天期主推與次選字串、與預期結果的逐項比對。

---
（以下給 Claude Code）

## 執行狀態表

| 階段 | 內容 | 狀態 | 驗證證據 | 審查 |
|---|---|---|---|---|
| S0 | 定位既有程式並記錄路徑 | 完成 | BASE `f63ffd5`。①推薦：`app/services/leaps_recommendation_service.rb`（`call`→`recommend_group`、`sort_by_liquidity`：先比 `liquidity_tier`〔OI 三分位〕再比 OI，回傳 `{near_term:, far_term:}` 各含 `pick`／`runner_up`）；顯示：`app/components/leaps_recommendations/page_component.rb:51` 呼叫 `render_recommendation`（定義於 `concept_cards.rb:6`），其在 `concept_cards.rb:17-18` 呼叫 `render_recommendation_group`（定義於 `concept_cards.rb:237`）；PDF：`pdf_export.rb`。②無成交：`app/services/leaps_ranking_service.rb` `vol_oi_threshold`（候選 Vol/OI 後三分之一界線）＋`low_vol_oi?(ratio, floor)`，於 `enrich` 寫入候選 hash `:no_recent_volume_warning`；顯示 `ranking_table.rb:200`。兩方法皆 private（`leaps_ranking_service.rb:29`），門檻依同批候選相對計算，候選 < `MIN_CANDIDATES_FOR_VOL_OI_TIER`（4）時不警示。S1 做法：讀候選 hash 已算好的 `:no_recent_volume_warning`，不改可見性、不動 `LeapsRankingService`；單元測試以候選 hash 注入 true/false。③欄位（`leaps_option_chain_snapshots`／候選 hash 同名）：`bid`、`ask`、`delta`、`dte`、`open_interest`、`volume`、`strike`、`expiration_date`、現價 `underlying_price`；另 DB 欄位 `intrinsic_value`、`extrinsic_value`（以 mid 計；S1 的 `extrinsic_ask` 以 ask 計，一律以 `ask − max(S−K,0)` 重算，不得讀此欄）；`bid_ask_spread_pct` **只在候選 hash**、DB 無此欄（`leaps_ranking_service.rb` `calc_spread_pct`，分母 mid，小數非 %），S1 的 `spread_pct` 依規格 `(ask−bid)/mid×100` 自算。候選來源 `LeapsRankingService#call`（delta ≥ 0.60、DTE ≥ 364、排除 extrinsic < 0）。④天期常數 `LeapsRecommendationService::NEAR_DTE_MIN=364`、`NEAR_DTE_MAX=550`（近：364 ≤ DTE ≤ 550，閉區間）、`FAR_DTE_MIN=550`（遠：DTE > 550，開區間）；前置核對 405、440→近，587、678、769、804→遠，全部符合。⑤`leaps-call-recommendation-spec.md` 在 repo 根目錄，本檔也在根目錄（`dirname` 皆為 `.`）；本檔未納入版控，`git mv` 不適用，也不需要搬。IV Rank 評語：`iv_rank_note.rb`。 | 異端審查官表示: VERDICT: PASS（r2，`~/fairprice-review/verdict-leaps-best-value-S0-r2.md`） |
| S1 | `LeapsBestValueService` + 單元測試 | 完成 | 新檔 `app/services/leaps_best_value_service.rb`、`app/services/leaps_best_value_config.rb`、`config/leaps_best_value.yml`、`spec/services/leaps_best_value_service_spec.rb`。`LeapsBestValueConfig.load` 為 `config/leaps_best_value.yml` 唯一讀取點（S3 的「預設選擇標準」與 `iv_rank_warn` 也從這裡讀）。三級共同硬條件 `bid > 0`、`exclude_no_recent_trade` 實作於 `hard_requirements_met?`。r2 驗證見 `~/fairprice-review/request-leaps-best-value-S1-r2.md`。預設與覆寫兩組預期結果全數符合（到小數第 2 位）。 | 異端審查官表示: VERDICT: PASS（r2，`~/fairprice-review/verdict-leaps-best-value-S1-r2.md`） |
| S2 | controller 接線 + request spec | 完成 | BASE `cb4c8f5`。`LeapsRecommendationsController#index` 在 fresh 分支以同一批 `@candidates` 呼叫 `LeapsBestValueService`，結果以 `best_value:` 傳入 `PageComponent`（只接住、不改畫面）。request spec「最划算推薦接線（leaps-best-value S2）」以真實 DB 快照（驗收基準 11 筆）驗證：服務呼叫 1 次、best_value 近天期主推 $130 / 2028-01-21、OI 推薦近天期主推 $180 / 2028-01-21。整份 request spec 92 examples、全套 1694 examples 皆 0 failures；整頁 HTML 回歸比對（`leaps_vertical_spread_spec.rb`）30 examples 0 failures，基準未修改。補充案例（`leaps-best-value-s2-addendum.md`，commit `0502764`）：案例 1 分支條件＝快照 `scraped_at` 超出 `FRESH_WINDOW`（1 小時）使 `fresh_for?` 為 false，服務未呼叫、best_value nil；2a 上次中心 180＋`user_strike=180` → 產生，近天期主推 $130、OI $180；2b 上次未帶履約價＋`user_strike=180` → 不產生，best_value nil；2c `strike=180` 被忽略，結果與不帶履約價相同。四案在未改 controller 時即通過，與預期一致、controller 未修改。全套 1698 examples, 0 failures，`tmp/rspec-failures.txt` 為空；無 seed：`spec_helper.rb:118` 的 `config.order = :random` 位於 81–125 行 `=begin/=end` 註解內，測試以定義順序執行。 | 異端審查官表示: VERDICT: PASS（r1，`~/fairprice-review/verdict-leaps-best-value-S2-r1.md`）；補充案例 VERDICT: PASS（r2，`~/fairprice-review/verdict-leaps-best-value-S2-r2.md`） |
| S3 | 推薦卡與排行表顯示 | 未開始 | | |
| S4 | E2E 核心案例驗收 | 未開始 | | |

規則：驗證未過禁止進入下一階段；每階段過驗證立即 patch 本表；接續 session 只讀本表＋進行中階段。每階段完成交審查官，審查欄填「異端審查官表示:」結論後才算完成。

## 全域限制

- 本功能**不新增任何爬取**，只用既有 LEAPS snapshot 資料。若需補欄位，Barchart 資料一律只能用 Playwright/CDP 解析 DOM 取得，**禁止呼叫 Barchart 內部 API 或任何 Barchart API**。
- 不新增 route、不新增 sidebar 入口（屬於既有 `/leaps` 頁面 `LeapsRecommendationsController#index` 的區塊）。
- 既有排行表的 OI 排序、PMCC 區塊、Vertical Spread 區塊行為不得改變。
- 門檻值全部集中在 `config/leaps_best_value.yml`，程式內禁止硬編。

## S0 定位既有程式

動作：
1. `grep -rn "次選\|推薦分析" app/` 找出產生「推薦分析」近／遠天期主推與次選的 service 與 component。
2. `grep -rn "近期無成交" app/` 找出無成交旗標的判定方法（方法名＋檔案）。
3. 找出 snapshot model 中 bid、ask、delta、dte、open_interest、volume、strike、expiration、現價的欄位名。
4. 找出既有近／遠天期 DTE 區間常數（名稱、值、邊界開閉）。
5. 規格檔位置：`git ls-files '*.md' | grep -i leaps` 找出 `leaps-call-recommendation-spec.md` 所在目錄，用 `git mv` 把本檔搬到同一目錄。

產出：把上述檔案的 repo 相對路徑、方法名、欄位名、常數名與值、本檔新路徑寫進狀態表「驗證證據」欄。

驗證（機器可判定）：每個列出的路徑 `test -f` 成功；每個方法名 `grep -n "def <方法名>"` 在該檔有命中；本檔與 `leaps-call-recommendation-spec.md` 的 `dirname` 相同。

前置核對：依既有常數，DTE 405、440 須屬近天期，587、678、769、804 須屬遠天期。（678＝2028-09-15，只出現在 S4 實際頁面，不在 S1 基準資料表；列入是為了確保 S4 的分區正確，基準資料表不用補。）任一不符 → 停止，回報常數值，不得自行重算 S1 預期結果（由規格撰寫端修正）。

## S1 `LeapsBestValueService`

新檔：`app/services/leaps_best_value_service.rb`、`spec/services/leaps_best_value_service_spec.rb`、`config/leaps_best_value.yml`。

### 設定檔（推估值，未驗證，交實測確認）

```yaml
delta_min: 0.80
delta_max: 0.92
spread_pct_max: 3.0      # (ask-bid)/mid*100
oi_min: 1000             # 使用者指定預設（2026-11-09）
volume_min: 50           # 使用者指定預設（2026-11-09）
exclude_no_recent_trade: false   # 使用者決定：近期無成交照常列出
iv_rank_warn: 70
# 天期區間不在本檔設定：一律引用 S0 找到的既有近／遠天期常數（含邊界的開閉規則），不得另訂。
```

### 計算（逐合約）

- `intrinsic = max(S - K, 0)`
- `extrinsic_ask = ask - intrinsic`（以 ask 計，價差寬自然被懲罰）
- `annual_cost_pct = extrinsic_ask / S * 365 / DTE * 100`
- `breakeven_pct = (K + ask) / S * 100 - 100`

### 篩選（全部成立才入選）

`delta_min ≤ delta ≤ delta_max`、`spread_pct ≤ spread_pct_max`、`OI ≥ oi_min`、`volume ≥ volume_min`、`bid > 0`；`exclude_no_recent_trade: true` 時另排除「近期無成交」（直接呼叫 S0 找到的既有判定方法，不得另寫）。預設 false，不排除，無成交合約照常列出、照常顯示既有 ⚠ 近期無成交標記。

### 選擇

每個天期區間：`annual_cost_pct` 升冪；同值依 `spread_pct` 升冪、再依 OI 降冪。依流動性等級補位，保證主推與次選都有值、永不回傳「無合格」：
- A 級：全部篩選條件成立。
- B 級：只看 Delta 區間＋Spread 上限（忽略 OI、成交量）。
- C 級：只看 Delta 區間。

A／B／C 三級共同硬條件（任何等級都不得違反）：`bid > 0`；`exclude_no_recent_trade: true` 時排除「近期無成交」。因此兩者都可能讓區間回傳 nil，這是允許的例外。

流動性等級與履約價無關，只表示合約通過幾項流動性條件。

依 A→B→C 等級順序取，同等級內依上述排序，取前 2 名：第 1 名＝主推，第 2 名＝次選。只有 Delta 區間內完全沒合約時才回傳 nil，前端該列直接不顯示（不顯示任何「無合格」字樣）。每筆回傳附 `liquidity_grade`（"A"/"B"/"C"）供測試斷言，前端不顯示。

回傳每筆含：expiration、DTE、strike、delta、ask、annual_cost_pct、breakeven_pct、spread_pct、OI、volume。

### 驗收基準資料（2026-11-09 NVDA，S = 186.64）

| 到期 | DTE | K | Delta | Bid | Ask | OI | Vol | 無成交 |
|---|---|---|---|---|---|---|---|---|
| 2028-01-21 | 440 | 120 | 0.8710 | 79.10 | 80.50 | 2069 | 18 | 是 |
| 2028-01-21 | 440 | 125 | 0.8569 | 75.40 | 76.85 | 634 | 10 | 否 |
| 2028-01-21 | 440 | 130 | 0.8417 | 72.00 | 73.20 | 2264 | 160 | 否 |
| 2028-01-21 | 440 | 140 | 0.8092 | 65.40 | 66.25 | 4163 | 191 | 否 |
| 2028-01-21 | 440 | 180 | 0.6562 | 42.00 | 42.50 | 14764 | 724 | 否 |
| 2027-12-17 | 405 | 130 | 0.8453 | 70.65 | 72.10 | 7565 | 22 | 是 |
| 2028-06-16 | 587 | 140 | 0.8042 | 69.60 | 71.25 | 499 | 13 | 否 |
| 2028-12-15 | 769 | 120 | 0.8540 | 87.40 | 89.65 | 6168 | 6 | 是 |
| 2028-12-15 | 769 | 140 | 0.8047 | 74.60 | 76.15 | 4898 | 60 | 是 |
| 2029-01-19 | 804 | 120 | 0.8530 | 88.25 | 90.50 | 221 | 5 | 否 |
| 2029-01-19 | 804 | 140 | 0.8045 | 75.80 | 77.00 | 502 | 107 | 否 |

測試中「無成交」以 stub 既有判定方法注入上表值。

### 預期結果

| 區間 | 主推 | annual_cost_pct | 次選 | annual_cost_pct |
|---|---|---|---|---|
| near | 2028-01-21 $130 | 7.36 | 2028-01-21 $140 | 8.72 |
| far | 2028-12-15 $140（A 級） | 7.50 | 2029-01-19 $120（B 級） | 5.80 |

另需斷言：$180（delta 0.6562）被 delta 篩掉；2028-01-21 $125 被 OI（634 < 1000）篩掉；2028-12-15 $140 雖標無成交仍入選；2028-12-15 $120 被成交量（6）篩出 A 級；2029-01-19 $120 被 OI 篩掉；2029-01-19 $140 被 OI（502）篩掉；2028-06-16 $140 被 OI（499）篩掉；Delta 區間內無合約時回傳 nil。
另跑一組覆寫設定 `oi_min: 500, volume_min: 10`：near 主推須變為 2028-01-21 $120（6.16，無成交仍入選）、次選 $125（6.76）；far 主推 2029-01-19 $140（7.38）、次選 2028-12-15 $140（7.50）。證明門檻確實由設定檔驅動。

驗證：`bundle exec rspec spec/services/leaps_best_value_service_spec.rb` 0 failures；數值比對到小數第 2 位。

## S2 controller 接線

`LeapsRecommendationsController#index` 呼叫 `LeapsBestValueService`，結果傳給推薦分析 component。原 OI 推薦邏輯**完全不改**，兩組結果同時傳入、並列呈現（見 S3）。

必交：`spec/requests/leaps_recommendations_spec.rb` 新增案例——`GET /leaps?symbol=NVDA`（不帶履約價，用 fixture snapshot）回 200，且 `LeapsBestValueService` 被呼叫一次、`PageComponent` 收到的 best_value 結果近天期主推為 `$130 / 2028-01-21`、既有 OI 推薦結果不變（近天期主推 `$180 / 2028-01-21`）。S2 不改畫面，既有整頁 HTML 回歸比對必須照常通過、不得修改基準。

驗證：`bundle exec rspec spec/requests/leaps_recommendations_spec.rb` 0 failures。

## S3 前端顯示

推薦分析卡（S0 找到的 component）：近天期、遠天期各一列，每列**左右並列兩張等寬卡**：

| 左：💰 最划算（最低年化時間成本） | 右：🔓 流動性最佳（OI 最高） |
|---|---|
| `LeapsBestValueService` 結果 | 既有 OI 推薦邏輯，內容與現行版本完全相同 |

- 兩張卡用同一組欄位、同一順序：履約價／到期日、Delta、Ask、OI、成交量、Spread %、年化時間成本 %、損益兩平 %。OI 卡也要補算年化時間成本與損益兩平（同 S1 公式），方便直接比較。
- 兩卡各自顯示主推＋次選。全頁不得出現「無合格」「無符合條件」類字樣（request spec 斷言 body 不含 `無合格`、`無符合`）。
- 近期無成交合約照常列出，沿用既有 ⚠ 近期無成交標記，不另加警示。
- 兩卡主推為同一合約時，左卡加標籤「與流動性最佳相同」。
- 手機寬度（< 768px）改上下堆疊，最划算在上。
- 既有 IV Rank ≥ `iv_rank_warn` 時顯示：「IV 偏高，優先深度價內以降低 Vega 與外在價值」。IV Rank 只讀頁面既有值，不新增來源。
- 推薦分析卡最底下（既有免責聲明之上）加「預設選擇標準」註記，數值一律讀設定檔、禁止硬編，預設顯示為：

  > **預設選擇標準**
  > 1. 排序：年化時間成本最低者優先 ＝（Ask − 內在價值）÷ 現價 × 365 ÷ DTE。同值依 Spread 小、OI 大排序。
  > 2. Delta 0.80–0.92（深度價內，接近持股）
  > 3. Spread（買賣差價比）≤ 3%
  > 4. OI ≥ 1,000
  > 5. 當日成交量 ≥ 50
  > 6. 近期無成交合約照常列入
  > 7. 天期：近天期 DTE {near_min}–{near_max}／遠天期 DTE 超過 {far_min}，各自挑選
  > 若符合 2–5 的合約不足兩檔，依序放寬：先忽略 OI 與成交量，再忽略 Spread，只保留 Delta 區間。
  > 排序先比流動性等級，同等級再比年化成本，因此次選的年化成本可能低於主推。
  > 「流動性最佳」依 OI 由高到低挑選，不套用以上條件。

  實作說明（不顯示）：以上引用區塊整段都是頁面註記。`{near_min}` 等值由既有常數產生，禁止硬編；邊界值只能歸入一個區間。request spec 斷言註記數字與既有常數一致，且邊界不重疊：DTE＝`near_max` 歸近天期、DTE＝`near_max`＋1 歸遠天期（以 `LeapsRecommendationService` 實際分區方法驗證）。

排行表：新增欄「年化時間成本」（放在 Time Value% 右側）；主推與次選列加徽章「最優」「次選」。排序維持 OI。

驗證：`spec/requests/leaps_recommendations_spec.rb` 的 `GET /leaps?symbol=NVDA` 案例，body 同時含 `最划算`、`流動性最佳`、最划算近天期主推 `$130.00 / 2028-01-21`、OI 近天期主推 `$180.00 / 2028-01-21`、`年化時間成本`、`預設選擇標準`，以及上述註記與邊界斷言；rspec 全套 0 failures。

整頁 HTML 回歸基準（`spec/support/leaps_page_html.rb`）：使用者裁示例外，S3 重新產生基準一次，不得新增 strip 規則隱藏新區塊。送審時附新舊基準 diff，審查官確認變更只限推薦分析區塊與排行表新欄。

## S4 E2E 核心案例

核心案例＝**不帶任何選填參數**：`/leaps?symbol=NVDA`。

動作：Playwright 開該網址（已登入 session），截圖存 `tmp/e2e/leaps-best-value-nvda.png`；擷取 DOM 中近／遠天期主推、次選、流動性最佳三段字串。

驗證：
1. 實際網址＝`/leaps?symbol=NVDA`（無 strike 參數）。
2. DOM 主推的 annual_cost_pct 等於用頁面排行表同列 Ask／Delta 依 S1 公式重算的值（誤差 ≤ 0.01）。
3. 若排行表中存在A 級合約，主推必為 A 級（Delta 0.80–0.92、Spread% ≤ 3.0%、OI ≥ 1000、Volume ≥ 50）；近期無成交不影響入選。頁面 DOM 不含「無合格」「無符合」。
4. 排行表中不存在其他與主推同等級、且年化時間成本更低的合約（腳本逐列重算比對）。
5. 推薦分析卡底部 DOM 含「預設選擇標準」，且其中 OI、成交量數值為 `1,000`、`50`。
6. 近、遠天期各自同時存在「最划算」與「流動性最佳」兩張卡；流動性最佳卡的主推＝該區間排行表 OI 最大的合約（腳本比對）。

有輸出不等於輸出正確：六項都要附擷取值才算完成。

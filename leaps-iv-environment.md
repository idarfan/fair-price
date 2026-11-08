# LEAPS IV 環境（IV Rank + IV 曲面）整合規格

> 目標：在 `/leaps` 頁面加入「LEAPS 天期 IV Rank」與「IV 期限結構／曲面」，資料**完全自算**，不爬第三方研究網站。

## 用途（給使用者看；實作不依此判斷）

既有 LEAPS 表回答「哪一檔合約流動性好、外在價值低」；本區塊補上三個問題：

| 問題 | 看哪裡 | 讓使用者明白什麼 |
|---|---|---|
| **現在買，時間價值貴不貴？** | LEAPS IV Rank（540 天） | 今天的 LEAPS 天期 IV 在過去一年的相對位置。高 → 權利金裡的波動溢價偏貴，買進後 IV 回落會吃掉獲利（虧損 ≈ Vega × IV 下降點數）；低 → 相對便宜。用來決定一次買、分批買或先等。 |
| **買哪個到期日？** | ATM IV 期限結構 | 各到期日的 IV 是否差很多。曲線平 → 拉長天期不必多付波動溢價，可依「每月外在價值成本」挑；某段突然翹高 → 那段期間市場預期有事件，該到期日相對貴。 |
| **買哪個履約價？** | IV 曲面 | 同一到期日不同履約價的 IV 差異（skew）。用來判斷某檔 IV 是否明顯偏離鄰近檔（可能是報價過時或定價失衡），並提醒：深價內 IV% 較高不代表貴，貴不貴仍看外在價值金額。 |

為什麼要「LEAPS 天期」而不只看 Barchart IV Rank：Barchart 的 IV 是最近一個 30 天以上的月選擇權，會被財報、單日大跌劇烈拉動（例：2026-11-05 TSM 單日 -10.8%，Barchart IV Rank 從 25.58 跳到 82.44）；LEAPS 的價格主要受長天期 IV 影響，兩者常不同步。Barchart 那組保留為短期情緒參考。

限制：IV Rank 只說明「相對過去貴或便宜」，不預測股價方向；不構成買賣建議。
> 入口：既有 `/leaps`（`LeapsRecommendationsController#index`）內新增區塊，**不新增 route**，故不需新增 sidebar 項目。

## 執行狀態表（每階段驗證通過後立即 patch 更新本表）

| 階段 | 名稱 | 狀態 | 驗證證據（檔案/指令輸出摘要） | 審查 | 更新時間 |
|---|---|---|---|---|---|
| P0 | 偵察（只讀） | ✅ 完成 | `docs/leaps-iv-recon.md` 11 個標題齊全；`tmp/recon/barchart_iv.png`；`git diff --stat -- app lib db config` 為空。偵察發現規格與現況不符 5 處（P4 pm2 時區、9223 不存在、margin-reminder 不存在、HV 標籤無天數、Barchart 歷史最長 2Y／520 列），進入對應階段前須使用者裁示後 patch | PASS（r1，附 4 條質詢） | 2026-11-06 |
| P1 | Schema | ✅ 完成 | 3 個 migration（一表一個）＋3 個 model；`db:migrate` → `rollback STEP=3` → `db:migrate` 全成功，`column_names` 含規格全部欄位；`spec/models/leaps_iv_tables_spec.rb` 9 examples 0 failures；完整 rspec 1411 passed。schema.rb 排除正式庫中名人堂分支的 `hof_*` 表（合併名人堂後須以完整 dump 重新產生） | PASS（r1，附 4 條質詢） | 2026-11-06 |
| P2 | 爬蟲擴充 | ✅ 完成 | LEAPS 爬蟲 Stage 3（篩 Delta 前全履約價 IV）＋`barchart_iv_history_scraper.py`（latest／backfill，切回原區間）＋`LeapsIvCapture`；TSM 實查：曲面 5 到期日×23 點＝頁面數、快照全欄非 null、2Y 回補 520 列＝頁面列數；排行回歸 SAME（83 筆）；合約 IV 與歷史 3 日期截圖逐欄一致；盤中不寫 IV（`--skip-iv-surface`）；完整 rspec 1445 passed | PASS（r2；r1 FAIL：缺中段／最舊列截圖） | 2026-11-06 |
| P3 | 計算服務 | ✅ 完成 | `LeapsIvEnvironmentService`（call／persist!）；規格測試向量逐一對應 + PMCC 讀取時合併（與快照同一次抓取、相差 1 小時內才併）；TSM 實資料 CM540＝0.427937（Python 獨立重算一致）；完整 rspec 1465 passed | PASS（r1，附 2 條質詢） | 2026-11-06 |
| P4 | 每日快照排程 | ✅ 完成 | pm2 `leaps-iv-snapshot`（`0 6 * * 2-6` UTC）＋`LeapsIvCdpLock`（shared／exclusive advisory lock）＋`LeapsIvSnapshotRunner`；11/07 手動連跑兩輪＋cron 正式觸發一輪（台北 14:00）9 檔全 success、0 重複；CSCO／NOK／ORCL／TSM 頁首收盤價＝DB spot＝Barchart 歷史收盤價；TSM 曲面 5 到期日 68／64／52／59／51＝頁面全部 call 履約價數，CM540 0.42085 獨立重算一致；鎖逾時畫面 `tmp/regress/p4_lock_timeout_ui.png`；完整 rspec 1609 passed | PASS（r2，附 2 條質詢：pm2 不明來源啟動、missing 保留舊點實跑，P7 回覆；r1 FAIL：最終程式碼未實跑、22:08 結果寫錯） | 2026-11-07 |
| P5 | UI 區塊 | ✅ 完成 | `IvEnvironmentSection`（＋`IvEnvironmentHeatmap`）放在推薦分析上方、預設收合；tooltips.js `IV_ENV_EXPLAIN` 14 key（無刪改既有行，導覽第 6 步）；`leapsIvEnvironment.ts` 第一次展開才畫兩張圖；查詢中標「更新中」；正式站 TSM 實測：熱圖 14 欄、Vega 計算句「每口約損失 $595」；component 20／request 83／完整 rspec 1636 passed、vitest 91 passed | PASS（r1，附 2 條質詢：PMCC 短天期併入後熱圖色階與期限結構被壓扁需使用者裁示、同日多次查詢覆寫說明，P6／P7 前回覆） | 2026-11-07 |
| P5.1 | 短天期點的呈現（使用者裁示） | ✅ 完成 | 熱圖色階只依 LEAPS 列（DTE ≥ 364），短天期列移到分隔標題下方、灰底不上色；期限結構只畫 LEAPS 段；正式站已併入 PMCC 的 TSM：LEAPS 70 格端點 39.6%＝HEAT_LOW、49.4%＝HEAT_HIGH，短天期 56 格 0 格上色，期限結構點 405–804 天；完整 rspec 1640 passed | PASS（r1） | 2026-11-07 |
| P6 | 推薦文字整合 | ✅ 完成 | `LeapsRecommendations::IvRankNote`（推薦分析標題下方、近天期之前；門檻讀 `LeapsIvConfig.fetch(:rank_thresholds)`）；request spec 29.4→29 便宜／29.6→30 中性／60.4→60 中性／60.6→61 偏貴／nil 不出現、整頁只出現一次、位置、改設定檔門檻即改判斷，7 examples；完整 rspec 1647 passed；正式站 TSM（rank nil、累積中 1/252）推薦分析下 0 句 | PASS（r1；審查記錄：歷史滿 20 天後須補一次有句子的實頁證據） | 2026-11-08 |
| P7 | 端到端驗收 | ⬜ | | | |

接續 session：只讀本表＋進行中階段章節。
「審查」欄：依撰寫端審查協定填異端審查官結論；審查未通過不得進入下一階段。

---

## 全域硬規則

1. **Barchart 資料一律只能用 Playwright/CDP 解析 DOM（或點擊頁面 UI 下載）取得，絕對禁止呼叫 Barchart 內部 API 或任何 Barchart API**（無 API 訂閱）。可使用 Barchart Premier 網頁會員登入後才看得到的頁面。
2. Loop Engineering：依序執行；每階段驗證未過，**禁止進入下一階段**。
3. 本檔（repo 內版本）為唯一真實來源；規格修改一律 patch，不整檔重寫。
4. 「完成」需實際證據（URL、DOM 值、psql 查詢結果、截圖路徑），不接受只報測試數；最基本情境（不填任何選填參數）沒跑通，任何階段都不得標記完成。
5. 新服務接進 controller 時，**必須同時交付 request spec**（route → service 完整 HTTP 路徑）。
6. 不得依賴 options-education-website.com 或任何第三方研究網站。

---

## 名詞與公式（全階段共用）

- **單位**：IV 一律以小數存（0.4304＝43.04%），UI 才轉百分比；Barchart 的 Rank/Percentile 存 0–100。
- **as_of_date**：取 Barchart 頁面 DOM 上的報價時間，換算為美東日期（`America/New_York`）。讀不到報價時間時該次抓取視為失敗，不得用系統時間代替。
- **ATM IV（單一到期日）**：取履約價夾住現價 S 的上下兩檔 call IV，依履約價線性內插至 S；S 恰等於某履約價時直接取該檔；S 不在任何兩檔之間時記 `nil`。
- **固定天期 ATM IV（CM540）**：以總變異數 `w = σ² × T`（T＝DTE/365）在夾住 540 天的相鄰兩到期日間對 T 線性內插，`σ = sqrt(w / T)`；無法夾住時記 `nil`，不外插。
  - 選 540 天的理由：唯一實測樣本（2026-11-06 TSM）的到期日 DTE 為 407–806，365 天無法被夾住、540 天可以。全年是否都能夾住 540 天**未驗證**，以 P0 第 10 點實測為準；若實測無法夾住，停在 P0 回報，不得自行改天期。
- **IV Rank（指標固定為 CM540）** = `(現值 − 期間最低) / (期間最高 − 期間最低) × 100`。期間＝`as_of_date` 早於當日、且在 365 個日曆天內的快照（最多 252 筆）。最高等於最低時記 `nil`。
- **IV Percentile** = 期間內「嚴格小於現值」的筆數 ÷ 期間筆數 × 100（相等不計入）。
- **歷史筆數 n**＝上述期間筆數（不含當日）。n < 20 時 Rank/Percentile 回傳 `nil`、狀態 `accumulating`，UI 顯示「資料累積中 n/252 天」。
- **曲面 moneyness** = `K / S`，顯示範圍 0.60–1.25（含端點）。`leaps_iv_surface_points` 存 LEAPS 到期日的**全部**履約價，0.60–1.25 只在讀取曲面（P3 `surface`、P5 熱圖）時篩；ATM IV 用全部履約價找夾住現價的上下兩檔（2026-11-06 使用者裁示：NOK 現價 7.46、上一檔 10＝1.34，存入時先篩掉就算不出 ATM 與 CM540）。

**測試向量（P3 必用）**
- 內插：T1=0.5、σ1=0.40；T2=1.5、σ2=0.44；目標 T=1.0 → σ=**0.4304**（±0.0001）。
- Rank/Percentile：歷史 [0.30, 0.50, 0.40]、現值 0.45 → Rank **75.0**、Percentile **66.7**（以參數 `min_history: 1` 關閉 n < 20 限制）。
- 相等值：歷史 [0.40, 0.40, 0.50]、現值 0.40 → Percentile **0.0**、Rank **0.0**。
- 最高等於最低：歷史 [0.40, 0.40]、現值 0.40 → Rank **nil**。
- ATM 內插：S=353.10，K=350 IV 0.425、K=360 IV 0.424 → **0.42469**（±0.00001）。

---

## P0 偵察（只讀，不改任何程式）

產出 `docs/leaps-iv-recon.md`，必須包含以下 11 個標題，各自填入**實際路徑／欄位名／行號**：

1. `## LEAPS 爬蟲` — 檔案路徑、進入點方法、觸發它的 Ruby service 方法
2. `## 期權鏈快照資料表` — model 路徑、table 名、所有欄位
3. `## Delta 篩選位置` — `Delta ≥ 0.60` 篩選發生在爬蟲端還是 Rails 端（檔案:行號）；未通過篩選的履約價 IV 是否有被存下
4. `## PMCC 短天期鏈` — `app/models/pmcc_short_call_snapshot.rb` 欄位中是否有 IV、DTE、strike（可否作為曲面短天期段）
5. `## Barchart IV 指標 DOM` — 用 Playwright（Premier 已登入）開 `https://www.barchart.com/stocks/quotes/TSM/options-history`，記錄：
   - 歷史表格的 DOM selector 與欄位順序（2026-11-06 人工實測欄位：Date、Imp Vol、1D IV Chg、IV Rank、IV Pctl、P/C Vol、Options Vol、P/C OI、Total OI、Last）
   - 「Select History」所有選項，以及選最長區間時的列數（頁面說明寫可回溯到 2018-10，**未驗證能否全部顯示**）
   - 「download」按鈕能否用 Playwright 點擊下載 CSV，CSV 欄位是否與表格相同
   - 頁首 `HV` 數值與 selector
   - 截圖存 `tmp/recon/barchart_iv.png`
6. `## pm2 排程` — ecosystem 檔路徑、既有 margin-reminder 的排程寫法（2026-11-06 P0 實測：margin-reminder 不存在，改以 `iv-daily-snapshot` 為範本）
7. `## 圖表元件` — 既有 Chart.js 使用位置（IV Skew Tracker 的檔案路徑）
8. `## 爬蟲併發控制` — 互動查詢與排程是否共用同一個 CDP Chrome（2026-11-06 P0 實測：cdp-relay 9223 不存在，兩者都直接連 9222）；既有的鎖／佇列機制檔案路徑；若沒有，明寫「無」
9. `## LEAPS 查詢紀錄` — 「最近 30 天在 /leaps 查詢過的 symbol」可從哪張表／哪個欄位取得（活躍度追蹤或 LEAPS job 表），附一條可執行的 SQL
10. `## 到期日與 DTE` — 本次 TSM 查詢實際抓到的所有到期日與 DTE，並確認 540 天被夾住
11. `## 收摺卡片與 tooltip` — 渲染 `#leaps-week52-card` 的 Phlex 元件路徑；正式站 `/assets/leaps_recommendations/tooltips-*.js` 對應的 repo 原始檔路徑；`VERTICAL_SPREAD_EXPLAIN` 與 `TOUR_ORDER` 所在行號；`#leaps-col-tip` 樣式所在 CSS 檔路徑

**驗證（全過才可進 P1）**
```bash
for h in "LEAPS 爬蟲" "期權鏈快照資料表" "Delta 篩選位置" "PMCC 短天期鏈" "Barchart IV 指標 DOM" "pm2 排程" "圖表元件" "爬蟲併發控制" "LEAPS 查詢紀錄" "到期日與 DTE" "收摺卡片與 tooltip"; do
  grep -q "^## $h" docs/leaps-iv-recon.md || echo "MISSING: $h"; done   # 須無輸出
test -s tmp/recon/barchart_iv.png && echo OK
git diff --stat -- app lib db config   # 須為空（P0 不得改碼）
```

---

## P1 Schema

新增 migration，三張表：

`leaps_iv_snapshots`（每標的每日一筆）
| 欄位 | 型別 | 說明 |
|---|---|---|
| symbol | string, not null | |
| as_of_date | date, not null | 美東交易日 |
| spot | decimal(12,4) | |
| cm540_atm_iv | decimal(8,5) | 可為 null |
| bc_hv | decimal(8,5) | Barchart Historical Volatility，讀自 `/stocks/quotes/{SYMBOL}/overview`（options-history 頁沒有 HV） |
| bc_hv_label | string | 固定存「HV 30 天」：頁面標籤沒有天數，天數依據 overview 頁名詞說明「30-Day Historical Volatility」（2026-11-06 使用者裁示） |
| source | string, not null | `scheduled` / `adhoc` |
| captured_at | datetime, not null | 實際抓取時間 |
| source_url | string, not null | 實際抓取 URL |
| timestamps | | |
唯一索引：`[symbol, as_of_date]`。寫入規則：upsert，後寫覆蓋先寫（盤中 adhoc 會被收盤後的 scheduled 覆蓋）。

`leaps_iv_surface_points`
| 欄位 | 型別 |
|---|---|
| symbol, as_of_date | 同上 |
| expiration | date, not null |
| dte | integer |
| strike | decimal(12,4), not null |
| moneyness | decimal(6,4) |
| call_iv | decimal(8,5) |
| delta | decimal(6,4) |
| captured_at | datetime, not null |
| timestamps | |
唯一索引：`[symbol, as_of_date, expiration, strike]`。寫入規則同上。expiration、strike 為唯一索引欄位，設 not null（PostgreSQL 唯一索引不把 NULL 視為相等，允許 NULL 會讓 upsert 寫出重複列；P1 r1 審查後 patch）。

`barchart_iv_histories`（Barchart Options Overview History 每日一列；Barchart IV 指標的唯一來源）
| 欄位 | 型別 |
|---|---|
| symbol | string, not null |
| trade_date | date, not null |
| imp_vol | decimal(8,5) |
| iv_rank | decimal(6,2) |
| iv_pctl | decimal(6,2) |
| pc_vol_ratio | decimal(8,4) |
| options_volume | bigint |
| pc_oi_ratio | decimal(8,4) |
| total_oi | bigint |
| last_price | decimal(12,4) |
| captured_at | datetime, not null |
| source_url | string, not null |
| timestamps | |
唯一索引：`[symbol, trade_date]`；upsert。

**驗證**
```bash
bin/rails db:migrate && bin/rails db:rollback STEP=3 && bin/rails db:migrate   # 全部成功（3 張表）
bin/rails runner 'p LeapsIvSnapshot.column_names.sort; p LeapsIvSurfacePoint.column_names.sort; p BarchartIvHistory.column_names.sort'
# 輸出須包含上表全部欄位
```

---

## P2 爬蟲擴充

1. 在 P0 找到的 LEAPS 爬蟲中，**篩選 Delta 之前**，把 LEAPS 各到期日**全部履約價**的 call（strike、IV、delta）寫入 `leaps_iv_surface_points`（原寫「moneyness 0.60–1.25 的 call」，P4 實跑後使用者裁示改為全部，理由見「名詞與公式」曲面 moneyness）。若 P0 第 3 點確認篩選發生在頁面端（未篩的履約價根本沒讀到），則改為讀完整履約價列表後再篩。
2. 既有 `Delta ≥ 0.60` 候選排行行為**不得改變**：改動前先對 TSM 存一份候選排行（到期日＋履約價＋Mid）為 `tmp/regress/leaps_before.json`，改動後同一份原始資料重算存 `leaps_after.json`，兩檔須完全相同。
3. 若 P0 確認 PMCC 短天期快照有 IV，曲面讀取時合併（不重抓）；沒有則曲面只含 LEAPS 段，不另開爬蟲。
4. 新增 Options Overview History 讀取（selector／下載方式用 P0 第 5 點記錄的），兩種模式：
   - `latest`：每次抓取時讀表格最新列，upsert 進 `barchart_iv_histories`；同時從 overview 頁讀 Historical Volatility 寫入 `leaps_iv_snapshots.bc_hv`，`bc_hv_label` 存「HV 30 天」
   - `backfill`：選 P0 實測可用的最長區間（2Y；Barchart 會記住上次選的區間，每次都要明確切換，不得假設預設值），整段 upsert（優先用表格 DOM；表格顯示不全才用 download CSV，仍須透過 Playwright 點擊 UI，不得直接請求下載網址）
   - 百分比欄位轉小數（51.92% → 0.5192），IV Rank／IV Pctl 存 0–100
5. 寫入 `source_url`、`captured_at`；`as_of_date` 依「名詞與公式」規則。
6. 本階段只存原始資料；`cm540_atm_iv` 由 P3 服務計算後寫入，爬蟲不得自行計算。
7. **美股正常交易時段（美東週一～五 09:30–16:00；定義同 `StockPriceChecker#market_open?`，只排除週末，美股假日的同一時段也視為盤中而不寫入）不寫入任何 IV 環境資料**：不寫曲面點與快照，也不跑 Barchart 歷史表爬蟲；LEAPS 爬蟲以 `--skip-iv-surface` 略過 Stage 3（不白跑）；LEAPS 查詢本身照常（2026-11-06 使用者裁示；P2 r1 質詢 1、3 後 patch）。原因：盤中頁首 `div.pricechangerow` 帶 `data-ng-if="session !== 'Realtime'"`，讀不到收盤報價日期，期權 IV 也在變動。盤前實測（美東 05:29）`pricechangerow` 仍顯示前一交易日收盤與日期，可正常寫入。

**驗證**
```bash
# 觸發一次 TSM 查詢（不填 user_strike）後：
psql -c "select expiration, count(*) from leaps_iv_surface_points where symbol='TSM' and as_of_date=(select max(as_of_date) from leaps_iv_surface_points where symbol='TSM') group by 1 order by 1;"
# 每個到期日的筆數 = 該到期日 Barchart 頁面上的全部 call 履約價數（報告列出兩邊數字，須相等；P4 後改，原為 0.60–1.25 的履約價數）

psql -c "select as_of_date, bc_hv, bc_hv_label, source_url from leaps_iv_snapshots where symbol='TSM' order by as_of_date desc limit 1;"
# 全部非 null

# backfill 後：
psql -c "select min(trade_date), max(trade_date), count(*) from barchart_iv_histories where symbol='TSM';"
# count 須等於驗收當下 Barchart 2Y 區間的表格列數（P0 實測 2026-11-06 為 520，列數隨日期變動，驗收時重測並列出兩邊數字）
psql -c "select imp_vol, iv_rank, iv_pctl, pc_vol_ratio, last_price from barchart_iv_histories where symbol='TSM' and trade_date='2026-11-05';"
# 存頁面資料（bc-data-grid）的原始值、依欄位精度四捨五入，不是畫面顯示值（2026-11-06 使用者裁示）：
# 須為 0.51925 | 82.44 | 92.43 | 0.9182 | 353.1000；四捨五入到畫面位數後須與頁面一致（51.92% | 82.44% | 92% | 0.92 | 353.10）
# 報告附 DOM 原始值（impliedVolatilityPercentile1y 為小數 0.9243…）與 DB iv_pctl（×100）的對照

diff tmp/regress/leaps_before.json tmp/regress/leaps_after.json && echo SAME   # 須輸出 SAME
bundle exec rspec $(git ls-files 'spec/**/*leaps*_spec.rb')                  # 全數通過
```
交叉核對（以 Barchart 頁面為準，不是拿自己存的資料比自己）：任取 2 個合約（1 個價內、1 個價外），截圖 Barchart 期權鏈頁該列，報告列出「頁面 IV / DB call_iv」，差 ≤ 0.1 個百分點；`barchart_iv_histories` 任取 3 個日期（最新、中段、最舊）與頁面截圖逐欄一致。

---

## P3 計算服務

新增 `app/services/leaps_iv_environment_service.rb`：

- `call(symbol:, as_of_date: nil)`（nil＝該 symbol 最新的 as_of_date）回傳：
  `{ as_of_date:, cm540:, rank:, percentile:, history_count:, status: :ok|:accumulating|:no_data, term_structure: [{expiration, dte, atm_iv}], surface: [{expiration, dte, moneyness, call_iv}], barchart: {trade_date, imp_vol, iv_rank, iv_pctl, hv, hv_label, history: [{trade_date, imp_vol, iv_rank, last_price}]} }`
- `barchart.*` 讀 `barchart_iv_histories` 中 `trade_date ≤ as_of_date` 的最新一列；`history` 為最近 252 列（供 P5 畫 Barchart IV Rank 走勢）；`hv` 讀 `leaps_iv_snapshots.bc_hv`。Barchart 的 IV Rank／Pctl 直接採用頁面值，**不得自行重算**。
- `persist!(symbol:, as_of_date:)`：計算 cm540 並寫回 `leaps_iv_snapshots`；P2 抓取完成後（adhoc 與 scheduled 皆同）呼叫此方法，**這是寫入 cm540 的唯一入口**。
- 計算一律照「名詞與公式」章節；不得另訂公式；`min_history` 預設 20，只有測試可改。

**驗證**
```bash
bundle exec rspec spec/services/leaps_iv_environment_service_spec.rb
```
spec 必含：「名詞與公式」全部測試向量（逐一對應 example）、歷史 19 筆回 `:accumulating`／20 筆回 `:ok`、365 天前的快照不計入期間、540 天無法被夾住回 `nil`、現價恰等於某履約價時 ATM IV＝該檔 IV、無任何資料回 `:no_data`。

---

## P4 每日快照排程

- 建立 `config/leaps_iv.yml`，內容照 P6 章節的完整 YAML（含 `rank_thresholds`）。
- 新增 `bin/leaps_iv_snapshot`：標的＝`config/leaps_iv.yml` 的 `watchlist` ∪ P0 第 9 點 SQL 取得的 symbol，去重後依字母排序，最多 `max_symbols` 個（超出寫 log 並略過）。
- 每標的依序（不並行）執行 P2 抓取 → `persist!`，`source='scheduled'`；單一標的逾時 `per_symbol_timeout_sec` 或失敗不中斷其他標的，錯誤寫 `log/leaps_iv_snapshot.log`。
- 併發：沿用 P0 第 8 點的鎖／佇列；若 P0 寫「無」，則新增以 PostgreSQL advisory lock 實作的互斥，互動查詢與排程都要取同一把鎖，取不到就等待（上限 `lock_wait_sec`），不得同時操作 CDP Chrome。
- 只抓 LEAPS 鏈與 Barchart IV 指標（`latest` 模式），不產生候選排行或 PMCC 結果。實作：LEAPS 爬蟲帶 `--iv-surface-only`，讀完到期日與現價後直接跑 Stage 3（不挑候選、不跑 Stage 2），不寫 `leaps_option_chain_snapshots`／`strike_chain_snapshots`，使用者最後一次查詢的排行不被覆蓋。
- 鎖的實作（P4 實跑後定案）：互動查詢取 **shared**、排程取 **exclusive**（多個互動查詢仍可並行）；鎖用**獨立的 PG 連線**（不向 ActiveRecord 連線池借，連線池只有 5 條）；排程每個標的放鎖後停 5 秒再拿下一個（advisory lock 不排隊，否則等鎖的互動查詢只能等整輪跑完）。
- 標的在 `barchart_iv_histories` 沒有任何列時，先跑一次 `backfill` 模式。
- 另提供 `bin/leaps_iv_snapshot --backfill SYMBOL` 手動回補單一標的。
- pm2 排程：cron `0 6 * * 2-6`，`autorestart: false`，沿用 `iv-daily-snapshot`（`ecosystem.config.cjs`）的寫法。pm2 daemon 時區為 **UTC**（P0 實測），UTC 06:00＝台北 14:00（週二～週六），抓前一個美國交易日的收盤資料；選台北 14:00 是因為使用者電腦此時通常開著（2026-11-06 使用者裁示）。
- 美股休市日：頁面報價日期不變，`as_of_date` 相同，自然 upsert，不產生新的一天。

**驗證**
```bash
bin/leaps_iv_snapshot && bin/leaps_iv_snapshot   # 連跑兩次
psql -c "select symbol, as_of_date, count(*) from leaps_iv_snapshots group by 1,2 having count(*)>1;"   # 須 0 筆
pm2 jlist | jq '.[] | select(.name=="leaps-iv-snapshot") | {cron: .pm2_env.cron_restart, autorestart: .pm2_env.autorestart}'
# 須為 {"cron":"0 6 * * 2-6","autorestart":false}
```
併發測試：手動跑排程的同時在 `/leaps` 按查詢，log 須顯示其中一方等待鎖，兩者都成功完成，無 CDP 錯誤。

---

## P5 UI 區塊

新增 `app/components/leaps_recommendations/iv_environment_section.rb`（Phlex），放在 `/leaps` 頁面「推薦分析」**上方**，DOM id `leaps-iv-environment`。

### 可收摺（沿用既有 pc-card 寫法）

以下行為是 2026-11-06 從正式站 `/leaps?symbol=TSM` 實測的既有寫法，新區塊必須逐項相同：
- 根元素是 `<details id="leaps-iv-environment" class="bg-white rounded-2xl border border-gray-200 shadow-sm flex flex-col pc-card">`，與 `#leaps-week52-card`、`#leaps-day-card` 同一組 class。
- 標題列是 `<summary class="pc-summary flex items-start justify-between gap-3 px-5 pt-5 pb-4 cursor-pointer rounded-2xl select-none hover:bg-gray-50 transition-colors">`，內含 `h3.pc-title`（文字「IV 環境 · {SYMBOL}」）與 `p.pc-sub`（文字「LEAPS 天期 IV Rank ＋ Barchart 參考」）。
- **預設收合**（不加 `open` 屬性），收合時只佔一行 summary，原有區塊位置與外觀不變。
- 收合時 summary 右側顯示摘要：「Barchart IV Rank {整數} · ATM IV（540 天）{x.x}%」；累積中時 LEAPS 部分顯示「累積中 n/252」。
- 不新增 JS 控制收合，只用原生 `<details>`；不記憶展開狀態。
- 新元件照 P0 第 11 點記錄的 `#leaps-week52-card` 元件的 summary 結構寫。

### 名詞 tooltip（沿用既有 tooltips.js 機制）

既有機制（正式站實測，原始檔即正式站 `/assets/leaps_recommendations/tooltips-*.js` 的來源檔，P0 記錄其 repo 路徑）：
- 文案集中在 `LEAPS_COL_EXPLAIN` 物件，每項 `{title, desc, side, el?}`；`desc` 可用 `TIP_H()`／`TIP_L()` 排版。
- 元素加 `data-tip-key="<key>"`，可選 `data-tip-value`（顯示在說明最上方的實際數值）。
- 滑過 → `#leaps-col-tip` 浮動小卡；點擊 → driver.js 單步聚光 popover（`overlayOpacity: 0.35`）。兩者共用同一份文案。
- 有 `el` 的項目才放進 `TOUR_ORDER`（「欄位導覽」按鈕的多步導覽）。

新區塊的做法：
1. 在 tooltips.js 新增 `IV_ENV_EXPLAIN` 物件，寫法比照既有 `VERTICAL_SPREAD_EXPLAIN`：最後用 `Object.keys(...).forEach` 併入 `LEAPS_COL_EXPLAIN`。**不得改動既有任何 key 的文案或行為。**
2. 只有 `ivenv_overview` 帶 `el: "#leaps-iv-environment > summary"`，插入 `TOUR_ORDER` 中 `"day_card"` 之後；其他 key 不進導覽。
3. 每個名詞元素加 `data-tip-key`，有數值的加 `data-tip-value`（例：`data-tip-value="Barchart IV Rank 82.44"`）。
4. 文案如下表（`title` 照抄；`desc` 可微調語句但不得改變意思，數字門檻不得改）：

| key | 掛在哪個元素 | title | desc |
|---|---|---|---|
| ivenv_overview | summary 內標題右側的 ⓘ（2026-11-07 使用者裁示：不掛整條 summary，避免每次展開／收合都跳出聚光說明；導覽 `el` 仍為 summary） | 🌡 IV 環境 | 補上排行表沒回答的三個問題。TIP_H「三個問題」＋TIP_L：「<b>什麼時候買</b> → 看 LEAPS IV Rank（540 天）」「<b>買哪個到期日</b> → 看 ATM IV 期限結構」「<b>買哪個履約價</b> → 看 IV 曲面」。TIP_H「兩組指標」＋TIP_L：「左組：FairPrice 自算的 LEAPS 天期，決定 LEAPS 價格的主要是這組」「右組：Barchart 短天期參考，容易被財報、單日大跌拉動，當短期情緒看」「兩組天期不同，不能直接比大小」。 |
| ivenv_leaps_rank | LEAPS IV Rank（540 天）徽章 | 📊 LEAPS IV Rank（540 天） | 回答「現在買，時間價值貴不貴」：今天的 540 天 ATM IV 落在過去一年最低～最高之間的位置（0–100）。TIP_H「為什麼重要」＋TIP_L：「IV 偏高時買進，之後 IV 回落會直接吃掉獲利：損失 ≈ Vega × IV 下降點數 × 100（每口）」「天期越長 Vega 越大，越怕 IV 回落」。TIP_H「怎麼看」＋TIP_L：「< 30：時間價值相對便宜」「30–60：中性」「> 60：偏貴，可分批進場或改選更深價內（外在價值較低）」「只說明跟過去比貴或便宜，不預測股價方向」。另加 `data-tip-lines`（見下方規則）。 |
| ivenv_leaps_pct | IV Percentile 徽章 | 📈 IV Percentile | 過去一年中，有幾 % 的交易日 540 天 ATM IV 比今天低。和 IV Rank 互相參照：Rank 看位置，Percentile 看天數。 |
| ivenv_cm540 | ATM IV（540 天）徽章 | 🌊 ATM IV（540 天） | 把夾住 540 天的兩個到期日的價平 IV，用總變異數內插成「剛好 540 天」的 IV，讓每天的數字可以比較。 |
| ivenv_accumulating | 「資料累積中」文字 | ⏳ 資料累積中 | 自算的 Rank 需要歷史資料：滿 20 個交易日才顯示，滿 252 個交易日才是完整一年。 |
| ivenv_bc_rank | Barchart IV Rank 徽章 | 📊 Barchart IV Rank | Barchart 依它自己的 IV 定義算的 IV Rank，取自 Options Overview History 頁面，本系統不重算。TIP_H「和 LEAPS IV Rank 的差別」＋TIP_L：「天期是最近一個 30 天以上的月選擇權，不是 LEAPS 天期」「財報、單日大跌會讓它一天大幅跳動，但 LEAPS 的價格主要受長天期 IV 影響，兩者常不同步」「只看這個數字，可能在 LEAPS 其實不貴時被嚇跑，或反過來」。 |
| ivenv_bc_pctl | IV Pctl 徽章 | 📈 Barchart IV Percentile | 過去一年中，Barchart IV 比今天低的交易日比例。 |
| ivenv_bc_iv | Imp Vol 徽章 | 🌊 Barchart Implied Volatility | Barchart 定義的 IV：最近一個 30 天以上月選擇權的平均隱含波動率。 |
| ivenv_bc_hv | HV 徽章 | 📉 Historic Volatility | 股價過去實際的波動率（天數見標籤）。IV 明顯高於 HV，代表期權價格比實際波動貴。 |
| ivenv_bc_trend | Barchart IV Rank 走勢圖標題 | 📉 Barchart IV Rank 走勢 | 最近 252 個交易日的 Barchart IV Rank 與股價。可看出 IV 是否因大跌、財報等事件衝高。 |
| ivenv_term | 期限結構圖標題 | 📐 ATM IV 期限結構 | 回答「買哪個到期日」：把各 LEAPS 到期日的價平 IV 連成一條線，虛線標出 540 天。TIP_H「怎麼看」＋TIP_L：「曲線平 → 拉長天期不必多付波動溢價，可直接比『每月外在價值成本』（外在價值 ÷ 剩餘月數）挑到期日」「某段突然翹高 → 市場預期那段期間有事件（如財報），該到期日相對貴」「一般是遠天期略高，屬正常」。 |
| ivenv_surface | 曲面熱圖標題 | 🗺 IV 曲面 | 回答「買哪個履約價」：每個到期日 × 每個履約價位置的 Call IV，顏色越深 IV 越高，橘框是最接近現價的一欄。TIP_H「讓你明白兩件事」＋TIP_L：「IV% 高不代表貴：深價內的 IV 數字常比價平高，但外在價值金額反而最小，貴不貴看排行表的外在價值」「抓異常：某格 IV 明顯偏離左右兩格，常是報價過時（呼應『近期無成交』）或定價失衡，下單前先確認報價」。 |
| ivenv_moneyness | 熱圖欄標題列 | ➗ 履約價 ÷ 現價（moneyness） | 小於 1 是價內，等於 1 是價平，大於 1 是價外。例：0.70 代表履約價約為現價的 7 成。 |
| ivenv_meta | 底部資料資訊列 | 🕒 資料時間與來源 | as_of_date 是報價所屬的美東交易日；captured_at 是實際抓取時間（台北）；scheduled 是收盤後排程寫入，adhoc 是手動查詢寫入。 |

`ivenv_leaps_rank` 的 `data-tip-lines`（沿用既有 `linesFor` 機制，伺服器端組 JSON 字串陣列）：
- 取「推薦分析」近天期合約的 Vega；沒有近天期推薦或 Vega 為 nil 時不輸出此屬性。
- 內容固定兩句：`"以推薦近天期 {strike} / {expiration}（Vega {vega}）計算"`、`"IV 每下降 5 點，每口約損失 ${vega × 5 × 100，四捨五入到整數}"`。
- 驗收例：Vega 1.2314 → `"IV 每下降 5 點，每口約損失 $616"`。
- 文案不得寫死任何標的的數字；所有數字一律來自 `data-tip-value` 或 `data-tip-lines`。

### 內容

資料來源一律為 `LeapsIvEnvironmentService#call(symbol:)` 的回傳值（最新 as_of_date），元件不得自行查 DB。

1. **徽章列**：`LEAPS IV Rank（540 天）`、`IV Percentile`、`ATM IV（540 天）`；Barchart `IV Rank / IV / HV（附 hv_label）` 另列一組，標「Barchart 參考（天期依頁面定義）」。`:accumulating` 顯示「資料累積中 n/252 天」；`:no_data` 顯示「尚無 IV 資料，請按查詢」；任何情況不得顯示 0 或空白。
2. **Barchart IV Rank 走勢圖**（`barchart.history`，最近 252 列）：IV Rank 與股價雙軸折線，標「Barchart 30 天天期」。
3. **期限結構折線圖**（沿用 P0 第 7 點的 Chart.js 寫法）：x＝DTE、y＝ATM IV%；atm_iv 為 nil 的到期日不畫點。
4. **IV 曲面熱圖**：列＝到期日（DTE 由小到大）、欄＝moneyness 0.60, 0.65, …, 1.25（共 14 欄）。每格取 |moneyness − 欄值| ≤ 0.025 中最接近的點，沒有點則留白並顯示「—」；格內顯示 IV%（一位小數），色階依該表 IV 最小值→最大值線性對應。
5. 區塊底部顯示 as_of_date（美東）、captured_at（台北）、source（scheduled/adhoc）、來源 URL。
6. 查詢進行中顯示既有最新資料並標「更新中」，不得整塊消失。

**驗證**
```bash
bundle exec rspec spec/components/leaps_recommendations/iv_environment_section_spec.rb
bundle exec rspec spec/requests/leaps_recommendations_spec.rb
```
request spec 必含：`GET /leaps?symbol=TSM&job_status=success` 回應包含 `id="leaps-iv-environment"` 與 fixture 的 CM540 數值（百分比格式）；`GET /leaps?symbol=TSM&job_status=success&user_strike=350` 同樣包含該區塊；三種狀態（ok / accumulating / no_data）各一個 example 斷言對應文字。
component spec 必含：熱圖 14 欄、無點的格顯示「—」、atm_iv nil 不輸出該點；根元素為 `details#leaps-iv-environment.pc-card` 且**沒有** `open` 屬性；summary 含摘要文字；名詞表 14 個 key 各至少出現一次 `data-tip-key`。fixture 近天期 Vega 1.2314 時，`ivenv_leaps_rank` 元素的 `data-tip-lines` 解析後第二句為「IV 每下降 5 點，每口約損失 $616」；Vega 為 nil 時沒有 `data-tip-lines` 屬性。

JS 檢查（純文字比對 tooltips 原始檔，P0 第 11 點路徑）：
```bash
for k in ivenv_overview ivenv_leaps_rank ivenv_leaps_pct ivenv_cm540 ivenv_accumulating ivenv_bc_rank ivenv_bc_pctl ivenv_bc_iv ivenv_bc_hv ivenv_bc_trend ivenv_term ivenv_surface ivenv_moneyness ivenv_meta; do
  grep -q "$k:" <tooltips 原始檔> || echo "MISSING $k"; done        # 須無輸出
git diff <tooltips 原始檔> | grep '^-' | grep -v '^---'              # 只允許 TOUR_ORDER 那一行的變動，其餘既有行不得刪改
```

---

## P5.1 短天期點的呈現（2026-11-07 使用者裁示，P5 r1 審查質詢 1）

背景：查詢後曲面會依 P2.3 併入 PMCC 短天期到期日（例：TSM 20–41 天，IV 最高 92.9%）。依 P5 原文「色階依該表最小→最大」，LEAPS 列（40–49%）全擠在最淺的色階；期限結構的 x 軸從 20 天起算，LEAPS 段被壓扁。

LEAPS 列的定義：DTE ≥ `LeapsRankingService::MIN_DTE`（364，與爬蟲 `LEAPS_MIN_DTE`、推薦近天期下限同一個值）；其餘為短天期。

1. **熱圖**：
   - 色階只依 LEAPS 列的 IV 最小→最大計算。
   - LEAPS 列照 DTE 由小到大排在上方；短天期列排在 LEAPS 列下方，前面加一列分隔標題「PMCC 短天期（參考，不上色）」。
   - 短天期格仍顯示 IV% 數字，用灰底、不套色階。
   - 沒有短天期列時，不出現分隔標題。
2. **期限結構圖**：只畫 LEAPS 段（DTE ≥ 364）的點，短天期點不畫。
3. CM540、Rank、Percentile 的計算不變（仍用 P3 的 term_structure，含短天期點，只影響畫面）。

**驗證**
- component spec：fixture 含 1 個短天期到期日（IV 0.90）與 2 個 LEAPS 到期日。驗證：
  - 色階端點取自 LEAPS 列：LEAPS 最高 IV 那格＝`HEAT_HIGH`、最低 IV 那格＝`HEAT_LOW`。
  - 短天期格沒有 `data-accent-bg`，數字照常顯示。
  - 短天期列位於分隔標題之後、所有 LEAPS 列之後。
  - 期限結構資料不含 DTE < 364 的點。
  - 沒有短天期時沒有分隔標題。
- e2e：查詢後已併入 PMCC 的 TSM 頁面，附展開截圖與 DOM 取值（各列的 DTE 順序、LEAPS 格色階的端點、期限結構點的 DTE）。

---

## P6 推薦文字整合

`config/leaps_iv.yml` 新增：
```yaml
rank_thresholds:
  cheap: 30       # rank < 30
  expensive: 60   # rank > 60；30 ≤ rank ≤ 60 為中性
watchlist: [TSM]
max_symbols: 20
per_symbol_timeout_sec: 300   # P4 r1 質詢 2 後由 600 改 300：加 Barchart 歷史時限 300，持鎖最多 600 秒 < lock_wait_sec 900
lock_wait_sec: 900
```
（此檔由 P4 建立並寫入全部鍵；P6 只讀取 `rank_thresholds`，不得另建設定檔。）

在「推薦分析」標題下方、近天期段落之前加**一句**（整個區塊只出現一次；rank 為 nil 時不加）。rank 先四捨五入到整數，**顯示與判斷都用這個整數**：
- rank < 30：「LEAPS IV Rank {x}，時間價值相對便宜。」
- 30 ≤ rank ≤ 60：「LEAPS IV Rank {x}，IV 中性。」
- rank > 60：「LEAPS IV Rank {x}，時間價值偏貴；可考慮分批進場或改選更深價內（外在價值較低）的履約價。」

門檻只能讀設定檔，不得硬編。

**驗證**：request spec 以 rank 29.4 / 29.6 / 60.4 / 60.6 / nil 五組 fixture 斷言：29.4→29 便宜、29.6→30 中性、60.4→60 中性、60.6→61 偏貴、nil→三句皆不出現；且句子在頁面中只出現一次。

---

## P7 端到端驗收

在 `http://localhost:3003` 用 Playwright（已登入 session）執行：

1. **基本情境（必做）**：`/leaps?symbol=TSM`，不填履約價，按「查詢」等待完成。
2. **附加情境**：`/leaps?symbol=TSM&user_strike=350`。

每個情境回報：
- 實際最終 URL
- 截圖路徑（整頁，含 `#leaps-iv-environment`）
- DOM 讀出的 ATM IV（540 天）、Rank（或累積中文字）、Percentile、Barchart IV Rank
- 同一時間 psql 查到的對應值（須一致；Rank 若為累積中，報告 n 值並與 psql 筆數核對）
- 曲面熱圖 2 格（最短與最長到期日各 1 格）的 IV 與 `leaps_iv_surface_points` 該點核對
- 候選排行表與 P2 的 `leaps_after.json` 一致（證明排行未被改壞）
- 收摺：頁面載入時 `#leaps-iv-environment` 的 `open` 為 false，截圖顯示只有一行 summary；點 summary 後 `open` 為 true，再截一張
- tooltip：展開後滑過 `[data-tip-key="ivenv_bc_rank"]`，`#leaps-col-tip` 的 opacity 為 1 且 `.tip-t` 文字為「📊 Barchart IV Rank」；點擊同一元素，出現 `.driver-popover` 且標題相同（各截一張）
- 回歸：滑過既有 `[data-tip-key="poi_fvg"]` 仍顯示原文案；按「欄位導覽」，步驟數＝改動前步驟數＋1

另跑一次 `bin/leaps_iv_snapshot`，貼 log 與 psql 新增的 scheduled 列。

---

## 回報格式（每階段結束）

```
階段：Pn 名稱
結果：通過 / 未通過
驗證指令與關鍵輸出：（貼原始輸出，截斷時註明）
變更檔案：（git diff --stat）
已更新執行狀態表：是
下一步：
```

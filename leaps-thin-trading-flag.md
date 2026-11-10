# leaps-thin-trading-flag.md — 「近期無成交」誤判修正＋改名「成交相對清淡」

## 問題回報（給使用者）

- **日期時間**：2026-11-09 23:40（Asia/Taipei，美東 10:40 開盤中）
- **頁面**：`https://fairprice-ohmy.com/leaps?symbol=NVDA`
- **症狀**：排行候選 107 筆中 61 筆標「⚠ 近期無成交」，其中多數當日有成交（例：$100 / 2027-12-17 volume 3,583）。
- **主訴**：標記大量誤判，且名稱與實際判定（同批相對 Vol/OI 後三分之一）不符。

## 找到的問題

1. **NULL 一律判無成交（30 筆）**：`vol_oi_ratio` 來自 V&G 頁另抓再合併；Barchart V&G 頁在 $95–$115 深價內履約價不列 LEAPS 到期日，合併對不上 → NULL。`low_vol_oi?`（`app/services/leaps_ranking_service.rb:138`）`ratio.nil? && floor` 回 true。
2. **四捨五入成 0（31 筆）**：Barchart Vol/OI 只到小數第 2 位（9 ÷ 8045 → 0），界線算出 0.0，所有 0 全被標記；其中 26 筆 volume > 0。
3. **時間差**：V&G 與 Options 頁不同時間抓，存的 Vol/OI 與同列 volume／OI 對不上（$120 / 2029-01-19：存 0.19，自算 0.42）。
4. **名稱不符**：判定是「同批候選 Vol/OI 後三分之一」，非「沒有成交」。

## 建議修改順序

S0 定位 → S1 改用同列 volume／OI 自算、nil 不判定（單元測試）→ S2 全站改名＋回歸基準 → S3 實頁 E2E。

## 怎麼測試

S1 用本文驗收資料跑單元測試；S3 於美股開盤時段開核心網址，逐列重算比對。

## 怎麼回報

每階段 patch 狀態表；最終附：抓取時間（台灣＋美東）、修改前後標記筆數、被標記合約逐列 volume／OI／自算比值／界線、截圖路徑。

---
（以下給 Claude Code）

## 執行狀態表

| 階段 | 內容 | 狀態 | 驗證證據 | 審查 |
|---|---|---|---|---|
| S0 | 定位改名點與界線公式 | 完成 | 「無成交」出現處（app/config）：`ranking_table.rb:107,205`、`pdf_export.rb:71,147,161`、`best_value_cards.rb:48,131`、`concept_cards.rb:79`、`tooltips.js:99,693`、`config/leaps_best_value.yml:10`（註解）、`leaps_best_value_service.rb:5,9,110`（註解）；範圍外：`hall_of_fame/premium_reference.rb:33,41`（名人堂「當天無成交」，與本標記無關）。界線公式 `leaps_ranking_service.rb:71-80`：候選數 < `MIN_CANDIDATES_FOR_VOL_OI_TIER`（=4，第 6 行）→ nil（第 72 行，以候選總數計、含 nil 列）；非 nil 值升冪排序（74）；空 → nil（75）；`cutoff_count = max(floor(n/3), 1)`（78，無條件捨去）；界線＝`ratios[cutoff_count - 1]`（79，即後三分之一中最大值）。判定 `low_vol_oi?` 137–142：`ratio <= floor`（含等號）。讀 `vol_oi_ratio` 做判定：僅 `leaps_ranking_service.rb:74,106`；讀旗標者：`leaps_best_value_service.rb:113`、`leaps_recommendation_service.rb:96`、`ranking_table.rb:107,194`、`best_value_cards.rb:47`、`concept_cards.rb:67`、`pdf_export.rb:53,161`；`pmcc_ranking_service.rb:168` 讀 ratio 僅顯示。`LeapsRankingService#call` 回傳 Array，呼叫端 4 處：controller:25、`pmcc_ranking_service.rb:40`、`leaps_vertical_spread_service.rb:117`、（`leaps_best_value_service` 吃其結果）。`pdf_export.rb:147` 的 `group[:all_warned]` 全專案無人設定（死碼）。驗收資料手算：6 非 nil 值 floor(6/3)=2 → 界線＝第 2 小＝0.001119 → 標 E、A。 | 異端審查官表示: VERDICT: PASS（verdict-leaps-thin-trading-flag-S0-r1.md） |
| S1 | 自算 Vol/OI＋nil 處理＋單元測試 | 完成 | `leaps_ranking_service.rb`：`self.computed_vol_oi`（volume.to_f / OI，不四捨五入；OI nil/0 或 volume nil → nil）、界線改吃自算值（公式不變）、`low_vol_oi?` nil → false、全 0 → 不逐列標記＋`all_zero_volume?` true、候選 hash 加 `:computed_vol_oi`（`:vol_oi_ratio` 保留）、`call` 仍回傳 Array。RED：37 例 14 失敗 → GREEN。驗收 7 筆：界線 0.001119，只標 E、A；D、C、F 不標。`leaps_ranking_service_spec`＋`leaps_best_value_service_spec` 60 例 0 失敗（seed 17594／1／2／3）。完整 rspec seed 35801：1725 examples, 0 failures。順序相依修正：sort order 案例補 `extrinsic_value: 0.5`（BASE 上單跑即失敗）。 | 異端審查官表示: VERDICT: PASS（verdict-leaps-thin-trading-flag-S1-r1.md） |
| S2 | 改名「成交相對清淡」＋request spec＋回歸基準 | 未開始 | | |
| S3 | E2E 實頁驗收 | 未開始 | | |

規則：驗證未過禁止進入下一階段；每階段過驗證立即 patch 本表；接續 session 只讀本表＋進行中階段。每階段完成交審查官，審查欄填「異端審查官表示:」結論後才算完成。

## 全域限制

- **不改爬蟲、不改 DB schema、不新增抓取**。`vol_oi_ratio` 欄位照存（V&G 仍提供 vega 等），判定改為不讀它。若需看 Barchart 頁面，一律只用 Playwright/CDP 解析 DOM，**禁止呼叫 Barchart 內部 API 或任何 Barchart API**。
- 不新增 route、sidebar 入口。
- 相對後三分之一的界線演算法（`vol_oi_threshold`）**公式不變**，只換輸入值。
- 內部 key（`:no_recent_volume_warning`、`exclude_no_recent_trade`）不改名，只改使用者看得到的文字。
- 已知問題不在本範圍：$95–$115 的 vega、itm_probability 仍為 NULL（V&G 無資料），照現狀顯示「—」。

## S0 定位

動作：
1. `grep -rn "無成交" app/ spec/ config/ lib/` 列出所有出現處（含 tooltip、PDF 匯出、`leaps_best_value` 的「預設選擇標準」第 6 點、推薦卡注意事項）。
2. 記錄 `vol_oi_threshold`（71–80 行）的精確公式：取哪個索引、四捨五入方向、`MIN_CANDIDATES_FOR_VOL_OI_TIER`。
3. 列出所有讀 `vol_oi_ratio` 來做判定的位置（`LeapsRankingService`、`LeapsBestValueService` 等）。

產出：路徑＋行號、公式原文，寫入狀態表證據欄。

驗證：每個路徑 `test -f` 成功；列出的行號 `grep -n` 命中。

## S1 自算 Vol/OI

修改 `app/services/leaps_ranking_service.rb`：

- 新增 `computed_vol_oi(volume, open_interest)`：`open_interest` 為 nil 或 0 → nil；`volume` 為 nil → nil；否則 `volume.to_f / open_interest`，**不四捨五入**。
- `vol_oi_threshold` 與 `low_vol_oi?` 改用 `computed_vol_oi`，不再讀 `vol_oi_ratio`。
- `low_vol_oi?`：ratio 為 nil → **false**（資料不足不判定）；其餘邏輯不變。
- 全 0 情況：同批非 nil 的自算值全部為 0 時，**逐列不標記**，改由頁面（與 PDF）在排行表上方顯示一行：「所有候選當日成交量皆為 0（可能尚未開盤或標的冷門），報價可能未更新。」`LeapsRankingService#call` 回傳形狀不變（陣列）；另加公開方法 `all_zero_volume?`（於 `call` 之後可讀），由 controller 讀取傳給元件。PMCC、垂直價差等既有呼叫端不得修改。
- 候選 hash 新增 `:computed_vol_oi`（供 S3 比對與 tooltip），既有 `:vol_oi_ratio` 保留不動。

### 驗收資料（單元測試，7 筆同批候選）

| 代號 | volume | OI | DB vol_oi_ratio | 自算值 |
|---|---|---|---|---|
| A | 9 | 8045 | 0 | 0.001119 |
| B | 96 | 226 | 0.19 | 0.424779 |
| C | 5 | 10 | 0 | 0.5 |
| D | 3583 | 15725 | NULL | 0.227854 |
| E | 0 | 500 | NULL | 0.0 |
| F | 50 | 0 | NULL | nil |
| G | 724 | 14764 | 0.05 | 0.049038 |

預期：
- 自算值比對到小數第 6 位；F 為 nil。
- 界線依 S0 記錄的公式，以 {E, A, G, D, B, C} 六個非 nil 值手算，算式寫進測試註解；被標記者＝自算值 ≤ 界線者。
- **F 不被標記**（nil 不判定）；**D 不被標記**（舊邏輯因 NULL 會標）；**C 不被標記**（舊邏輯因存 0 會標）。
- 另一案：全部 OI 為 0 → 界線 nil → 無人被標記。
- 另一案：7 筆 volume 皆為 0、OI 皆 > 0 → 無人被標記、`all_zero_volume?` 為 true。
- 另一案：驗收資料原 7 筆 → `all_zero_volume?` 為 false。
- 另一案：`call` 回傳值仍為陣列（`be_an(Array)`），既有呼叫端 spec 不需修改即全過。
- 另一案：候選 < `MIN_CANDIDATES_FOR_VOL_OI_TIER` → 無人被標記（既有行為不變）。

驗證：`bundle exec rspec spec/services/leaps_ranking_service_spec.rb` 0 failures；`spec/services/leaps_best_value_service_spec.rb` 0 failures（其注入旗標的測試不受影響）；完整 rspec 0 failures（記 seed）。

## S2 改名

S0 列出的所有使用者可見文字：
- 「近期無成交」→「成交相對清淡」（⚠ 符號保留）。
- `leaps_best_value` 預設選擇標準第 6 點 →「成交相對清淡合約照常列入」。
- 標記的 tooltip 改為：「本次查詢候選中，當日成交量／未平倉量（自行計算）落在後三分之一。不代表沒有成交。」
- 遠天期推薦卡既有注意事項中的相關文字一併改用新名稱。
- 下列逐處替換為指定文字：

| 位置 | 新文字 |
|---|---|
| `concept_cards.rb:79`、`pdf_export.rb:71` | 「成交量相對未平倉量偏低，掛單可能較少；進出場前先確認報價與價差。」 |
| `pdf_export.rb:147` | 「所有候選當日成交量皆為 0（可能尚未開盤或標的冷門），報價可能未更新。」（僅在第 4 點的全 0 情況顯示） |
| `pdf_export.rb:161`「（⚠無成交）」 | 「（⚠成交相對清淡）」 |
| `leaps_recommendation_service.rb:97` 注意事項 | 「成交量相對未平倉量偏低，掛單可能較少；進出場前先確認報價與價差。」 |
| `ranking_table.rb:107` 標記滑鼠提示 | 即上方指定的新 tooltip，取代原句 |
| `tooltips.js:99` 排名欄說明 | 「⚠ 近期無成交」→「⚠ 成交相對清淡」，其餘不變 |
| `tooltips.js:693` IV 偏斜教學 | 「報價過時（呼應『近期無成交』）」→「報價過時（成交清淡時常見）」 |

必交：
- request spec：`GET /leaps?symbol=NVDA` body 含「成交相對清淡」、不含「無成交」。
- PDF 匯出案例：不含「無成交」、不出錯。
- request spec 追加：全 0 資料狀態下，body 含上述一行提示、排行表無任何「成交相對清淡」標記。
- 整頁 HTML 回歸基準：使用者裁示例外，重新產生一次；不得新增 strip 規則；送審附新舊 diff，審查官確認變更只限標記文字與 tooltip。

驗證：`grep -rn "無成交" app/ config/ --exclude-dir=hall_of_fame` 無結果（`app/services/hall_of_fame/premium_reference.rb:33`「當天無成交」與本標記無關，不改）；request spec＋回歸比對全過；完整 rspec 0 failures（記 seed）。

重啟：每次重啟前詢問使用者。重啟前先跑 `assets:precompile`（`tooltips.js` 屬 asset）。

## S3 E2E 實頁驗收

時段：美股開盤後 15 分鐘以上（台灣 22:45–05:00）。

動作：按「查詢」重抓 NVDA，開 `/leaps?symbol=NVDA`（不帶選填參數），截桌面圖 `tmp/e2e/leaps-thin-trading-nvda.png`。腳本擷取排行表每列 volume、OI、標記有無。

驗證：
1. 實際網址＝`/leaps?symbol=NVDA`，記抓取時間（台灣＋美東）。
2. 每列以 volume ÷ OI 重算，依 S0 公式算界線；被標記集合＝重算值 ≤ 界線的集合，完全一致。
3. OI 為 0 或空的列，無一被標記。
4. $95–$115 列：標記與否只由自算值決定（逐列列出）。
5. 修改前（2026-11-09 23:07 那批 61 筆）與本次被標記筆數並列回報；開盤時段本次筆數約為候選數三分之一（推估，未驗證，以實測為準）；全 0 情況不適用此估計。
6. 頁面 DOM 不含「無成交」。

有輸出不等於輸出正確：六項都附擷取值才算完成。

# leaps-best-value-card-style.md — 「最划算」卡改為與「流動性最佳」卡同一風格

## 問題回報（給使用者）

- **日期時間**：2026-11-11 18:35（Asia/Taipei）
- **頁面**：`/leaps`，推薦分析「近天期」列（使用者截圖：主推 $240 / 2028-01-21 vs. $300 / 2028-01-21）
- **症狀**：
  1. 右卡（流動性最佳）主推是綠色膠囊（履約價／到期日＋Delta），旁邊灰字「次選：…」，下面一段說明文字，再接明細格；左卡（最划算）只有「主推」小字＋標題＋明細格，沒有膠囊、沒有說明文字。
  2. 左卡明細只有 Ask，沒有 Mid；右卡的說明文字有寫 Mid。
- **主訴**：左右兩卡風格不一致，左卡要列 Mid，版面要跟右卡相同。

## 找到的問題

1. 兩卡由不同程式畫：右卡沿用既有 `render_recommendation_group`，左卡是 S3 新寫的 `best_value_cards.rb`，各自排版。
2. 明細格欄位清單兩邊各寫一份，左卡缺 Mid。

## 建議修改順序

S0 定位 → S1 抽出共用的「膠囊＋明細格」元件，兩卡共用，補 Mid、補左卡說明文字 → S2 實頁截圖驗收。

## 怎麼測試

request spec 比對兩卡的 DOM 結構與 class；Playwright 截桌面／手機圖並排比對。

## 怎麼回報

每階段 patch 狀態表；最終附改前改後截圖、兩卡 DOM 結構比對輸出。

---
（以下給 Claude Code）

## 執行狀態表

| 階段 | 內容 | 狀態 | 驗證證據 | 審查 |
|---|---|---|---|---|
| S0 | 定位兩卡的繪製程式 | 完成 | 外框：`concept_cards.rb:241-252` `render_recommendation_group`（左 `render_best_value_card`、右 `div[data-leaps-oi-card]`）。**右卡** `render_oi_recommendation` 256-275：膠囊 `render_pick_badge` 278-288（呼叫於 264；class 依 `pick[:liquidity_tier]` 取 `LIQUIDITY_STYLE` 顏色，非固定綠色）、次選灰字 268-270、說明文字 272（`group[:reason]`，來自 `LeapsRecommendationService`）、明細 273 → `best_value_cards.rb:36-39` `render_oi_metric_blocks`。**左卡** `best_value_cards.rb:17-33` `render_best_value_card`：標題＋「與流動性最佳相同」、`render_contract_block` 42-55（「主推／次選」小字＋`$K / 到期日`＋⚠）；無膠囊、無說明文字。**明細格兩卡已共用** `render_metric_list` 59-71＋`metric_items` 73-84，欄位同為：履約價／到期日、Delta、Ask、OI、成交量、Spread %、年化時間成本、損益兩平（兩卡都沒有 Mid；右卡 Mid 只出現在說明文字）。左卡的列來自 `LeapsBestValueService#graded_candidates` 61-62 的 `slice`，不含 `:mid`、`:liquidity_tier`（但含 bid、ask）。**PDF**：`pdf_export.rb:113-126` `pdf_reco_group` 只輸出右卡的膠囊與說明文字（說明文字 135 行已含「Mid $x」），沒有明細格，最划算卡完全不進 PDF。規格「找到的問題 2」（兩邊各寫一份明細）前提不成立：兩卡已共用明細格，都缺 Mid（S0 r1 質詢 4）。右卡 Mid 來源 `LeapsOptionChainSnapshot#mid_price`（model 47-52）：bid、ask 皆有時為 `(bid + ask) / 2.0`，缺一邊時取另一邊。 | 異端審查官表示: VERDICT: PASS（verdict-leaps-best-value-card-style-S0-r1.md） |
| S1 | 共用元件＋補 Mid＋左卡說明文字 | 完成 | 使用者裁示 1a（Mid 在元件依 `mid_price` 同規則由 bid／ask 自算，不改 service）、2a（左卡膠囊固定綠色＝`LIQUIDITY_STYLE["充足"]`）、3a（「PDF 含 Mid」為回歸測試）。新增 `pick_card_parts.rb`（`render_capsule_row`／`render_pick_capsule`／`render_pick_reason`／`render_pick_details`／`render_metric_list`／`metric_items`／`mid_of`），兩卡共用；明細欄位：Delta、Mid、Ask、OI、成交量、Spread %、年化時間成本、損益兩平（`sm:grid-cols-5`，無「履約價／到期日」列）；次選以 `[data-leaps-runner-up-title]`「次選 $K / 到期日」＋⚠ 呈現。右卡文字內容與順序不變（膠囊顏色仍依 tier、說明文字＝`LeapsRecommendationService` 原文）。左卡加說明文字（規格範本）。PDF 不改（最划算卡本來不進 PDF）。刪除 `render_pick_badge`、`render_contract_block`、`render_oi_metric_blocks`。紅燈：新增 7 例舊程式下 7 敗（PDF 回歸例通過）。回歸基準：使用者同意後重產，只有 e_with_candidates 變（18 行語意差異，限卡片結構與 Mid），a–d 不變；依使用者指示新增 `f_with_best_value`（11 筆驗收真快照，左右兩卡各 2 張、5 種零件 class 兩卡相同）。完整 rspec seed 12629：1740 examples, 0 failures。右卡說明文字「與改前相同」以服務產出加上 e 基準 diff 證明內容不變（S1 r1 質詢 1）。r2：重建 `tailwind.css`（新增 `sm:grid-cols-5`、移除全站已無人使用的 `first:mt-0`）並與 S1 一起 commit；實測兩卡並排時 5 欄每格約 98px，「年化時間成本」數值溢出 3px 壓到下一格，使用者裁示明細格改為標籤在上、數值在下（`flex flex-col`），e／f 基準隨之重產（只差這個 class）。r3：**使用者裁示以容器寬度取代 sm 門檻**（原「sm 以上 5＋3」改為依卡片內容寬度）：明細外框加 `@container`，dl 改 `@md:grid-cols-5`（容器 ≥ 28rem＝448px 才 5 欄，每格 ≥ 80px，對最寬標籤「年化時間成本」72px）。結果 640–767px 單卡 5＋3、768–1103px 兩卡並排 2 欄、1104px 起 5＋3；新增 request spec 斷言 class，版面量測腳本 `measure_pick_details.mjs` 可重跑（headless 瀏覽器版面測試不做，列入工作日誌待辦）。 | 異端審查官表示: VERDICT: PASS（verdict-leaps-best-value-card-style-S1-r3.md；r1、r2 FAIL）。質詢 1（375px 頁首工具列橫向捲動）留待 S2 確認正式站。 |
| S2 | 實頁截圖驗收 | 完成 | 經使用者同意 precompile＋`pm2 restart fairprice-rails`（tailwind-b49612d0.css no-store 200）。TSM（快照 2026-11-11 22:05:34 台北，重啟後資料過期，經頁面「查詢」重抓）。正式站量測 `measure_pick_details.mjs`：639–767 5＋3、768–1103 2 欄、1104（外框 448.00）起 5＋3，最小餘裕 8px，與測試環境逐格相同。四卡 Mid 與資料庫 (bid＋ask)／2 相同（203.00／149.00／219.00／143.00）；兩卡明細無「履約價／到期日」，次選以標題列呈現；左卡近天期主推 $230 / 2028-01-21 為實際資料中的成交相對清淡，⚠ 在膠囊後、次選灰字前。375px：每組最划算在上、卡內無溢出。**375px 頁首橫向捲動為既有問題，非本規格造成**：來源 `navbar_component.rb:18,39`（不在 S1 diff），`/momentum` 同樣 scrollWidth 684／360，改前截圖已有橫向捲軸；列入工作日誌待辦，之後另開規格。 | 異端審查官表示: VERDICT: PASS（verdict-leaps-best-value-card-style-S2-r1.md）。質詢 1：375px 另有 `#leaps-export-root` 按鈕列、`#leaps-iv-environment` 更新列超出視窗（皆不在 S1 diff），併入工作日誌待辦。 |

規則：驗證未過禁止進入下一階段；每階段過驗證立即 patch 本表；接續 session 只讀本表＋進行中階段。每階段完成交審查官，審查欄填「異端審查官表示:」結論後才算完成。

## 全域限制

- 不改任何選擇邏輯（`LeapsBestValueService`、既有 OI 推薦）。
- 右卡現有的文字內容、順序不變；只把它的膠囊與明細格改成呼叫共用元件，畫面需與改前一致（Mid 新增除外）。
- 不新增抓取；Mid 一律 `(bid + ask) / 2`，取自候選 hash 既有值，不另算來源。
- 重啟、回歸基準重產：依既有規則每次先問使用者。

## S0 定位

動作：
1. 找出右卡膠囊、次選灰字、說明文字、明細格各自的繪製方法（預期在 `app/components/leaps_recommendations/concept_cards.rb` 的 `render_recommendation_group` 一帶），記錄檔案與行號。
2. 找出左卡繪製方法（預期 `app/components/leaps_recommendations/best_value_cards.rb`），記錄行號。
3. 列出兩邊明細格目前的欄位與順序。
4. 確認 PDF 匯出（`pdf_export.rb`）是否也畫這兩張卡；若有，記錄行號。

驗證：路徑 `test -f`；行號 `grep -n` 命中。

## S1 共用元件

1. 新增共用元件（名稱自訂，放 `app/components/leaps_recommendations/`），提供兩個方法：
   - **膠囊列**：綠色膠囊「`$K / 到期日`  Delta x.xxx」＋右側灰字「次選：`$K / 到期日`」。樣式完全沿用右卡現有 class。
   - **明細格**：每張合約一組。**不含「履約價／到期日」列**（主推已在膠囊、次選已在次選標題列出）。欄位與順序固定為：

     | 第 1 列 | Delta | Mid | Ask | OI | 成交量 |
     |---|---|---|---|---|---|
     | 第 2 列 | Spread % | 年化時間成本 | 損益兩平 | | |

     合約有「⚠ 成交相對清淡」時，標記照現行位置顯示。
   - 次選明細格上方加一行標題「次選 `$K / 到期日`」（有 ⚠ 標記時接在標題後），取代原本的「履約價／到期日」列。
2. 右卡、左卡都改用此元件。
3. 左卡在膠囊列與明細格之間加說明文字（字型、大小、顏色同右卡說明文字），範本：
   > 建議到期日：{到期日}（DTE {dte}），履約價 ${K}，Delta {delta}，Mid ${mid}。
   > 年化時間成本 {x}%，股價需漲 {y}% 才損益兩平。
   > Bid-Ask Spread {z}%。
   > 以上依「預設選擇標準」篩選，僅供策略篩選參考，非投資建議，請自行評估。
4. PDF 匯出若有畫兩卡，同步改用相同欄位（含 Mid）。

必交測試（先寫、先確認在舊程式下失敗）：
- request spec：兩卡的膠囊、次選灰字、說明文字、明細格各自存在，且**同一元素在兩卡使用相同 CSS class 集合**（以 Nokogiri 取 class 比對）。
- 兩卡明細格的欄位標籤序列完全相同，且含「Mid」。
- 以驗收基準資料斷言左卡主推 Mid＝`(bid+ask)/2` 到小數第 2 位。
- 右卡說明文字內容與改前相同（字串比對）。
- PDF 匯出含「Mid」且不出錯。
- 兩卡 DOM 皆不含「履約價 / 到期日」標籤文字。

驗證：上述 spec＋完整 rspec 0 failures（記 seed）；回歸基準經使用者同意後重產，送審附新舊 diff，差異只限兩卡結構與 Mid。

## S2 實頁截圖驗收

1. 改前截圖（若 S1 前未截，以使用者 2026-11-11 18:35 截圖為改前基準）。
2. 經使用者同意重啟後，開 `/leaps?symbol=<當時資料新鮮的標的>`，截桌面與手機寬度。
3. 驗證：
   - 兩卡膠囊、次選灰字、說明文字、明細格位置一致（截圖並排附證據）。
   - 左卡明細有 Mid，數值＝頁面同列 (Bid+Ask)/2。
   - 手機寬度上下堆疊，最划算在上，元件不溢出。
   - 兩卡明細格皆無「履約價／到期日」列；次選以標題列呈現。

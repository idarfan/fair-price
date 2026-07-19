# bcvs.md — 牛市看漲價差（Bull Call Vertical Spread）試算工具

> 執行模式：Loop Engineering — 依序完成各階段，每階段結束執行對應驗證。
> 任何驗證失敗：修正後從該階段重跑，直到全部通過才可宣告完成。
> 禁止跳過驗證、禁止在驗證未過時進入下一階段。
>
> 本檔入 repo 後即為單一事實來源；後續修改一律 patch/diff 式，禁止整檔重寫。
> 架構全面沿用 Lesson 10 bpus 工具（bpus.md）的既有模式：Python sidecar
> 兩段式 Barchart 抓取（僅 DOM 解析，禁止呼叫 Barchart 內部 API）、
> 進度條機制、口數輸入、driver.js tooltip（CSS 與 `/home/idarfan/csp/option-basics-lesson8.html` 一致 — 注意該檔在 repo 之外的獨立目錄，直接讀此絕對路徑，
> 具體行為見「導覽與欄位說明規範」，禁止只放單一 ? 圖示交差）、
> 字級以單頁不捲動為準。差異僅在：讀 **call chain**（bpus 讀 put chain）、
> 快取層為本工具新增。

## 執行狀態（Claude Code 負責維護，接續工作的唯一入口）

**維護規則**：每完成一階段的驗證，立即以 patch 方式更新本表（狀態＋證據）。
**接續規則**：session 接續時先讀本表，只重讀「進行中」階段的對應章節，
已完成階段不重讀、不重做（其驗證已有證據者視為有效）。

| 階段 | 狀態 | 證據（路徑/連結，由 Claude Code 填寫）|
|---|---|---|
| 1 資料層（快取表/sidecar/TTL）| ✅ 已完成 | `spec/services/bcvs_cache_service_spec.rb`（9 例全過）；RKLB 真實 ticker 手動跑過兩支 sidecar，DOM bid/ask 與 Barchart 頁面比對一致 |
| 2 服務與控制器（K2 建議/request spec）| ✅ 已完成 | `spec/services/bull_call_spread_calculator_service_spec.rb`、`bull_call_spread_recommender_service_spec.rb`、`spec/requests/bull_call_spreads_spec.rb`（26 例全過，含 basis 恰等於分水嶺邊界）|
| 3 前端 | ✅ 已完成（見下方清單逐項打勾＋證據；本輪重讀規格另補上「淨成本/每口成本分開顯示」與「修復模式中間情境」兩個缺漏）| `app/components/bull_call_spreads/page_component.rb` |
| 4 端到端驗收 | ✅ 已完成 | 見階段 4「驗證 4」段落；NOK K1=$7/K2=$12/2028-01-21 全流程 Playwright 驗證，9 步導覽逐步點擊確認；修復模式三情境（≤K1／中間／≥K2）數字與手算一致（中間情境 $-82/口 = (10.12−7)+2.96−6.90 ×100）|

**階段 3 本輪重做清單**（皆為規格已定案的既有章節，逐項打勾）：

- [x] 3-0 參照資產徹查（見「參照資產清單」；已填妥，見下表）
- [x] 說明區卡片配色（視覺規範節；純文字不過）—— `CARD_GREEN`/`CARD_GOLD`/`CARD_ORANGE` 三色卡片＋`render_card_header` emoji 標題，Playwright 截圖確認
- [x] 損益區間表：動態數字＋列色（虧損紅/損平灰/獲利綠）—— `renderIntervalTable()`，NOK K1=$7 實測 debit=$194／breakeven=$8.94／max_profit=$306 與規格逐字相符
- [x] 裸買 LEAPS 對照表＋交叉價 S\* = K2 + K2 bid —— `BullCallSpreadCalculatorService#s_star`，NOK 實測 S\*=$14.96
- [x] 提前平倉指引：收回/獲利雙口徑並列＋Y（已實現獲利比例）≥ 80% 法則 —— `closeout_value`/`closeout_profit`/`realized_pct`，公式為 (現值−成本)÷最大獲利
- [x] chain 表欄位 hover tooltip（九欄文案照規格表）—— `COLUMN_EXPLAIN` desc 改為規格固定文案逐字；Playwright hover moneyness/volume/delta 三欄，`.tip-b` 文字與規格表完全一致
- [x] driver.js 九步導覽（參照 /home/idarfan/csp/option-basics-lesson8.html，資產移植進 repo）—— `TOUR_STEPS` 常數＋`#bcvs-tour-btn`；過程中發現並修正 `application.html.erb` 遺漏 `controller_name == 'bull_call_spreads'` 的 driver.js include（修正前 `window.driver` 為 undefined，功能完全無法動作），以及 `#bcvs-col-tip` CSS 缺失（hover tooltip 先前無樣式）。Playwright 逐步點擊驗證 9 步全部就位且順序正確：①股票代號→②到期日→③K1→④三tab建議→⑤損益區間表→⑥裸買對照表→⑦提前平倉指引→⑧修復模式→⑨Level3提醒，"9 of 9" 確認
- [x] 切換 K1/tab 所有說明數字連動（防寫死）—— 切換 K1 由 $7→$5 後裸買對照表/提前平倉指引全部同步重算，S\*（僅依賴 K2）維持不變

## 策略定義

同到期日：買入低履約價 Call（第一腳 K1）＋賣出高履約價 Call（第二腳 K2），
淨支出（debit）建倉。每口：

| 項目 | 公式 |
|---|---|
| 淨成本 debit | K1 ask − K2 bid（保守估）；另示 mid 供參 |
| 每口成本 | debit × 100 |
| 最大損失 | debit × 100（K1 以下兩腳歸零）|
| 最大獲利 | (K2 − K1 − debit) × 100（K2 以上）|
| 損益兩平 | K1 + debit |
| 報酬風險比 | 最大獲利 ÷ 最大損失 |

## 功能流程

1. 輸入股票代號 → sidecar 抓取該標的已開設的期權**到期日清單** → 下拉選單
2. 選到期日 → 抓取該到期日 call chain → 第一腳 K1 履約價下拉選單
   （鏈上依 bpus 慣例將建議區間 highlight）
3. 選 K1 → 系統計算並給出**第二腳 K2 建議**（三檔，tab 樣式沿用 bpus
   保守/激進的既有樣式）：

   | Tab | 選取規則（以 debit÷價差寬度 比值 r 從候選 K2 中選最接近者）|
   |---|---|
   | 保守 | r ≈ 0.60（損益兩平最低、達陣機率最高、報酬比最低）|
   | 平衡 | r ≈ 0.50（1:1 報酬風險）|
   | 積極 | r ≈ 0.35（報酬比最高、需較大漲幅）|

   候選 K2 = 鏈上所有 > K1 的履約價；bid 為 0 或 open interest 為 0 者剔除；
   三檔重複時往外遞補。每檔顯示：K2、淨成本、每口成本、最大獲利、
   最大損失、損益兩平、報酬風險比。
4. 口數輸入（預設 1，沿用 bpus）；所有金額隨口數連動。

### 修復模式（選配輸入）

「第一腳成本覆寫」欄位：使用者已持有 K1 長倉（如虧損中的 LEAPS）時填入
實際進場成本 basis，計算改用 basis：

- 鎖定結果（≥K2）＝ (K2 − K1) + K2 bid − basis
- 上式 < 0 時以紅色警示「此組合鎖定虧損 $X／口」，並顯示分水嶺
  basis 門檻 = (K2 − K1) + K2 bid
- 補充顯示「對照現在直接平倉」：以 K1 現價 bid 計算平倉收回金額，
  與三種到期情境（≤K1／中間／≥K2）並列

## 說明區（建議結果下方，固定顯示）

### 視覺規範（沿用既有 LEAPS/PMCC 黃金法則頁的卡片系統，禁止無配色的純文字堆疊）

- 每個區塊＝一張圓角卡片：淺色底＋同色系邊框＋emoji 標題，
  直接重用該頁既有的 CSS 類別/變數，不得另創配色
- 卡片色系分配：**綠色**＝獲利與公式類（損益區間表、好處）；
  **黃色**＝決策與警示類（提前平倉指引、注意事項、黃金法則式驗算）；
  **橙色**＝規範類（裸買 LEAPS 對照表＋交叉價 S\*）；
  **紅色字**＝虧損金額與關鍵警語（如 Level 3、鎖定虧損）
- 公式以等寬字體＋色彩標示（如 `(K2−K1) − D` 的樣式比照
  LEAPS 頁的 `(KS−KL) − (PL−PS)`），公式下附「本次範例：<即時數字>」一行
- 損益區間表列色：虧損列紅字、損平列灰字、獲利列綠字

**鐵則：所有數字一律以「使用者所選 K1」＋「系統建議（或使用者切換的）K2」
即時計算，隨選擇連動更新；本規格中的示範例（NOK、K1=$7、K2=$12 等）
僅定義輸出格式與語感，嚴禁寫死於 UI。**

### 損益區間表（動態，D = 淨成本 debit）

| 到期股價區間 | 結果 | 金額（每口）|
|---|---|---|
| ≤ K1 | 賠掉全部成本 | −D × 100 |
| K1 ～ 損益兩平（K1+D）| 部分虧損，隨股價遞減 | (股價 − K1 − D) × 100 |
| = K1 + D | 損益兩平 | $0 |
| K1+D ～ K2 | 開始獲利，隨股價遞增 | (股價 − K1 − D) × 100 |
| ≥ K2 | 最大獲利（封頂）| (K2 − K1 − D) × 100 |

表格以實際數字渲染，不得只顯示公式。**示範例（規格基準，UI 文案照此語感）**：
NOK 現價 $10.12、到期 2028-01-21（552d）、K1=$7（ask $4.90）、K2=$12、
D=$1.94：

| 到期股價 | 結果 |
|---|---|
| ≤ $7.00 | 賠掉全部成本 −$194 |
| $7.00 ～ $8.94 | 部分虧損（如 $8.00 → −$94）|
| = $8.94 | 損益兩平 $0 |
| $8.94 ～ $12.00 | 開始獲利（如以現價 $10.12 到期 → +$118）|
| ≥ $12.00 | 最大獲利 +$306（封頂）|

### 為什麼不直接裸買 LEAPS Call？（動態對照表）

本策略的獲利上限**注定比不上**大漲行情下的裸買 LEAPS — 頁面必須誠實
呈現這點，並用同一組 chain 數據算出取捨。對照表（裸買 = 只買 K1 單腳）：

| 項目 | 裸買 K1 Call | 價差（K1/K2）|
|---|---|---|
| 每口成本 | K1 ask × 100 | D × 100 |
| 最大損失 | 全部成本 | 全部成本（但金額小得多）|
| 損益兩平 | K1 + ask | K1 + D（低得多）|
| 最大獲利 | 無上限 | (K2−K1−D) × 100 封頂 |

**到期損益交叉價 S\* = K2 ＋ 短腳收到的權利金（K2 bid）**，必須計算並顯示：
到期價 < S\* 時價差策略勝出，> S\* 時裸買勝出。

示範例：裸買成本 $490、損平 $11.90；價差成本 $194、損平 $8.94；
S\* = 12 + 2.96 = **$14.96** — 即 NOK 到期站上約 $15 裸買才反超，
在那之前價差全面佔優（成本少 60%、損平低 $2.96、$8.94–14.96 整段
賺得比裸買多或虧得比裸買少）。

**採用本策略的理由（隨上表動態呈現）**：你買的不是「最大獲利」，
是「獲利門檻大幅降低＋同資金風險減半以上」— 適合「看漲但不確定漲多少」
的判斷；只有強烈確信股價將遠超 S\* 時，裸買才是更好的選擇。

### 提前平倉指引（不必等到期）

- **兩個口徑必須並列顯示、嚴禁混用**：「現在平倉可收回 $X」（毛額，
  價差現值）與「等於獲利/虧損 $X−成本」（淨額）。上限也成對呈現：
  收回上限 = (K2−K1)×100，獲利上限 = 收回上限 − 成本（即畫面的最大獲利）
- **判斷基準 Y ＝ 已實現獲利比例 ＝ (現值 − 成本) ÷ 最大獲利**。
  現值以快取 chain 保守估（K1 bid − K2 ask）
- **Y ≥ 80% 即建議考慮獲利了結**（預設閾值）：剩餘 20% 獲利要再抱數月，
  報酬/時間比急遽變差，還多扛提前指派與回檔風險
- **沿用示範例說明（數值為示意，UI 以即時計算取代）**：成本 $194、
  收回上限 $500、獲利上限 $306。現價 $10.12、距到期 552 天時，
  現值約 $250 → 收回 $250＝獲利 $56、Y ≈ 18%，續抱；若日後 NOK
  漲至 $13、現值約 $440 → 獲利 $246、Y ≈ 80%，可平倉落袋，
  不必再等一年多賺那 $60
- **必須解釋的反直覺點（沿用示範例）**：NOK 若下個月就衝上 $12，
  現值可能僅約 $320（獲利 $126、Y ≈ 41%）而非收回上限 $500 —
  短腳仍含大量時間價值，漲越早、距滿值越遠，這是正常現象不是計算錯誤；
  距到期越近或價內越深才越貼近滿值
- 平倉一律組合單兩腳同出

### 好處

成本低於裸買 call、最大損失封頂於淨成本、賣腳權利金部分對沖 theta、
修復模式可壓縮虧損 LEAPS 在橫盤～小漲區間的損失。

### 注意事項

K2 以上獲利封頂（大漲行情跑輸裸買）；短腳深度價內＋除息日前
有提前指派風險（被指派後以長腳處理，損益不變）；平倉一律用組合單兩腳同出，
避免單腳滑價；留意兩腳的買賣價差與
流動性；財報前 IV 變化影響成交價。

**權限提醒（頁面頂部常駐 banner）**：本策略含賣出期權腳，需
**三級（Level 3）期權交易權限**方可開設。

## 快取機制（本工具新增）

- PostgreSQL 新表存 chain 快照：ticker、expiration、抓取時間、
  strikes JSONB（含 bid/ask/mid/OI）
- TTL **30 分鐘**：查詢時快照未過期 → 直接回快取，**不重建資料表、
  不觸發 sidecar**；已過期 → 重抓並 UPSERT 更新該 ticker+expiration
  的既有列（不新增重複列）
- 到期日清單與各到期日 chain 分開快取，皆適用 30 分鐘 TTL
- 前端：每次觸發 sidecar 抓取時顯示**進度條**（沿用 bpus 機制），
  進度中下拉選單置為 disabled；快取命中則跳過進度條直接渲染

## 參照資產清單（階段 3 開工前必先徹查填妥，patch 回本表）

「沿用」的每一項都必須先落到具體路徑與類別名，嚴禁邊做邊猜：

| 參照項 | 來源 | 徹查方法 | 查得結果（Claude Code 填寫）|
|---|---|---|---|
| driver.js 資產與 tooltip CSS | `/home/idarfan/csp/option-basics-lesson8.html`（repo 外）| 直接讀該檔，列出 driver.js 版本/載入方式、tooltip 相關 CSS 區塊 | lesson8.html 本身**不**載入 driver.js（`#col-tip` 是純 hover tooltip，非 driver.js 多步導覽），CSS 選擇器：`#col-tip{background:#1a2535;border:1.5px solid var(--gold)/*#D4900A*/;border-radius:11px;...}`＋`#col-tip .tip-t{color:var(--gold);}`。driver.js 本體已由 bpus/LEAPS 移植進 repo：`vendor/assets/javascripts/driver-1.6.0.iife.js`＋`vendor/assets/stylesheets/driver-1.6.0.css`，本工具直接重用（不重新 vendor）。移植目的地：`app/assets/tailwind/application.css`（新增 `#bcvs-col-tip` 區塊，逐字比照 `#bpus-col-tip` 對齊 `#col-tip`）＋`app/views/layouts/application.html.erb`（補上 `controller_name == 'bull_call_spreads'` 條件式 include，此前遺漏導致 `window.driver` undefined）|
| 說明區卡片配色系統 | LEAPS/PMCC 黃金法則頁 | 從 sidebar 的 LEAPS/PMCC 入口追 route → controller → view，找出卡片的 partial/元件與 CSS 類別名 | `app/components/leaps_recommendations/page_component.rb`：`render_pmcc_edu_golden_rule`（黃卡）/`render_pmcc_edu_max_profit`（綠卡）/`render_pmcc_edu_build_rules`（黃卡）/`render_pmcc_edu_what_is_pmcc`（米卡），皆為 `div(class: "bg-[#XXXXXX] border-[1.5px] border-[#XXXXXX] rounded-[10px] p-4")` 模式。色彩變數來自 `/home/idarfan/csp/option-basics-lesson9.html` 的 `:root`：`--gold:#D4900A/--gold-bg:#FEF4D8/--gold-bdr:#E8B840`、`--green:#2E9E52/--green-bg:#E8F8EE/--green-bdr:#8ED4A8`、`--red:#D04040/--red-bg:#FDEAEA/--red-bdr:#F5AAAA`（lesson9 無獨立橙色 token，本工具沿用同一卡片語彙延伸 `#FFE8D1`/`#E8935A` 供裸買對照表使用）|
| 進度條機制 | bpus（Lesson 10）工具 | 同法從 sidebar bpus 入口追到實作 | `app/components/bull_put_spreads/page_component.rb#render_progress_bar`：`div(id:"bpus-progress")>div(id:"bpus-progress-fill", class:"...bpus-progress-anim")`；JS `showProgress()`/`hideProgress()` 切換 `hidden` class；動畫定義於 `app/assets/tailwind/application.css` 的 `.bpus-progress-anim`/`@keyframes bpus-progress-slide`。本工具對應新增 `.bcvs-progress-anim`/`@keyframes bcvs-progress-slide`（同款左右跑動）|
| 保守/激進 tab 樣式 | bpus 工具 | 同上 | `app/components/bull_put_spreads/page_component.rb#render_recommend_tabs`：`data-bpus-recommend-tab` attribute 標記按鈕，JS `setActiveTab()` 切換 `bg-blue-600 text-white border-blue-600`（active）vs `bg-white text-gray-700 border-gray-300`（inactive）。本工具三檔對應 `data-bcvs-recommend-tab`＋同款 class 切換邏輯（`render_recommend_tabs`/`setActiveTab()`）|

**驗證（列為階段 3 的前置驗證 3-0）**：本表四列的「查得結果」全數填妥
且路徑經 `ls`/`grep` 證實存在，才可開始寫階段 3 的程式碼；
查得結果一併 patch 回本規格，後續 session 直接引用、不重查。
✅ 已完成：四列皆已徹查並填入具體路徑/類別名/CSS 選擇器，並在階段 3 程式碼
中依此徹查結果實作（見上方階段 3 清單各項的證據欄）。

## 導覽與欄位說明規範

**A. chain 表欄位說明（hover tooltip，每個欄位標頭都要有）**，文案固定：

| 欄位 | tooltip 文案 |
|---|---|
| MONEYNESS | 價內程度：股價相對履約價的位置，越高越深價內 |
| BID / MID / ASK | 買價／中間價／賣價；本工具 K1 以 ask、K2 以 bid 保守計價 |
| LAST | 最近成交價（可能過時，以 bid/ask 為準）|
| CHANGE / %CHANGE | 當日漲跌（金額／百分比）|
| VOLUME | 當日成交口數 |
| OI | 未平倉量：流動性指標，0 代表無人持倉、勿選 |
| OI CHG | 未平倉量變化 |
| IV | 隱含波動率：越高權利金越貴 |
| DELTA | 對沖比率：可近似解讀為到期價內機率 |

**B. 頁面導覽（driver.js 分步導覽，實作與 CSS 參照 `/home/idarfan/csp/option-basics-lesson8.html` — 該檔在 repo 之外，直接讀此絕對路徑，抽取其 driver.js 設定與 tooltip CSS 移植進本工具的 Phlex view，不得以連結方式依賴 repo 外檔案）**：
右上角「導覽」按鈕啟動，依序 highlight：代號輸入 → 到期日 → K1 選擇 →
三 tab 建議 → 損益區間表 → 裸買對照表（S\*）→ 提前平倉指引 →
修復模式 → Level 3 提醒（共 9 步），每步附一句中文說明（文案由實作
依本規格各節內容撰寫）。

**驗證（併入階段 3 與階段 4）**：Playwright hover 任三個欄位標頭，
tooltip 文字與上表一致；點擊「導覽」出現 driver.js overlay 且步驟數 = 9；
僅有孤立 ? 圖示而無上述兩項行為者，驗收不過。

## 路由與入口（鐵則）

- 路由掛在既有 namespace 之下，不得新開頂層路由
- Sidebar **最末位**新增入口「牛市看漲價差試算」；無入口即視為未完成

---

## 階段 1：資料層

migration（快取表）＋ sidecar call-chain 抓取（兩段式，DOM only）＋
快取服務（TTL 判斷、UPSERT）。

**驗證 1**：單元測試涵蓋 — 快取命中不觸發抓取、過期觸發重抓且 UPSERT
不產生重複列、bid=0/OI=0 剔除邏輯。以真實 ticker 手動跑一次 sidecar，
比對 DOM 抓到的 bid/ask 與 Barchart 頁面顯示值一致。

## 階段 2：服務與控制器

K2 建議計算服務（三檔規則＋修復模式公式）＋ controller ＋ namespace 路由。

**驗證 2**：單元測試（含鎖定虧損警示的邊界：basis 恰等於分水嶺）＋
**request spec 覆蓋完整 HTTP 路徑（route → service）— 與單元測試同級的
必交付項**，含最基本情境（無任何選配參數）。

## 階段 3：前端

Phlex view：代號輸入 → 到期日下拉 → K1 下拉 → 三 tab 建議 →
損益區間表（動態數字）→ 裸買 LEAPS 對照表（含交叉價 S*）→
提前平倉指引（含現在平倉可收回金額與已實現比例 Y%）→
好處/注意事項 → 口數 → 修復模式欄位 →
Level 3 banner → 進度條 → sidebar 入口。
driver.js 依下方「導覽與欄位說明規範」實作；字級以單頁
不捲動為準。

**驗證 3**：頁面可從 sidebar 進入；抓取中進度條顯示且下拉 disabled；
快取命中時無進度條。

## 階段 4：端到端驗收

**核心用例優先**：以示範例組合（NOK、2028-01-21、K1=$7、K2=$12）走完
代號 → 到期日 → K1 → 建議 → 損益區間表 → 提前平倉指引全流程至少一次，
其後才驗修復模式。行情變動屬正常，驗的是**一致性**：區間表五列金額須與
頁面當下顯示的 debit 換算吻合（±$1），Y% 須與(現值−成本)/最大獲利換算吻合，
對照表的裸買成本/損平須與 K1 ask 換算吻合，S\* 須等於 K2 + K2 bid；
**切換 K1 或 tab 後所有說明數字須同步變動**（驗證非寫死）；
Playwright 截圖須可見說明區各卡片之配色與 emoji 標題（與 LEAPS 頁
同一套視覺），純文字無配色即驗收不過。

**驗證 4（完成宣告的必要證據）**：
- Playwright 截圖＋實際導覽 URL＋DOM 關鍵值（三 tab 的 K2、淨成本、
  最大獲利/損失、損益兩平、損益區間表五列的實際金額、
  現在平倉可收回金額與 Y%）
- 上述 DOM 值與人工在 Barchart 頁面核對的已知值交叉比對 —
  「有輸出 ≠ 輸出正確」
- 快取驗證：同 ticker 30 分鐘內二次查詢，log 證明未觸發 sidecar；
  psql 查表證明無重複列
- 修復模式：以 NOK 實例（K1=$10、basis=$6.90、K2=$12）驗算鎖定虧損
  警示金額 = basis − (2 + K2 bid)，與手算一致

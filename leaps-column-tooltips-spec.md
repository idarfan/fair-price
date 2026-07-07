# FairPrice 新功能規格：LEAPS 欄位教學說明（driver.js tooltips）

> 來源指令：`leaps-column-tooltips-instruction.md`（2026-07-05）。依主規格「新功能另開規格文件」規則獨立成檔。
> 參考模式：`~/csp/option-basics-lesson8.html` 的三層互動架構（已實地解析其實作）。

> 2026-07-07 重組：依 `leaps-teaching-features-instruction.md`，本 spec 涵蓋兩部分——第一部分「推薦分析圖卡」（本節新增）、第二部分「欄位 tooltips 與術語字卡」（已於 2026-07-05/06 交付，見下方原有章節與 checklist）。

# 第一部分：推薦分析區收摺式名詞解釋圖卡（2026-07-07）

## 需求（第一部分）

推薦分析區塊（近天期/遠天期推薦文字）下方加四張收摺式圖卡，標題為名詞本身，預設收合：Bid-Ask Spread／IV（隱含波動率）／Vega／IV Crush 風險。

## 架構（第一部分）

1. 原生 `<details>/<summary>`，零 JS、無新函式庫；深色卡面沿用字卡同一組 gray 色階。
2. **Phlex server-side 渲染，動態代入當次推薦合約實際數值**（ask−bid、spread_pct、mid、iv、vega、dte、外在價值、現價）。**數值來源合約 = 遠天期推薦優先、無則近天期**（與 instruction 示意「DTE 568」一致；圖卡標註來源合約的到期日/履約價）。完全無推薦時整組不渲染。
3. `{latest_earnings}`：唯讀查既有 `fundamentals.next_earnings_date`（Barchart overview 抓取的既有資料，不新增 service、不打外部 API）；無資料時顯示「暫無財報日資料」降級，不報錯。
4. **IV Crush 試算防呆**：instruction 試算式寫死「回落至 90%」；若合約 iv ≤ 90%，改為「回落 10 個百分點」試算（損失 = 10 × Vega），文案同步切換，避免負數損失。
5. 圖卡是欄位 tooltips 的**深入版**（含損失試算），兩者各自維護；圖卡屬頁面內容，**匯出要入鏡**（不加 data-export-exclude），以當下展開狀態呈現。
6. 純前端顯示層：無新路由、無新 service（controller 加一行既有表唯讀查詢傳入 component）、無 request spec 需求（有意識確認的不適用）。

## 驗收（第一部分；✅ 2026-07-07 全部驗收完成，證據如下）

- [x] NVTS 實測（開盤後新報價）：四卡預設收合、逐一展開；動態數字三方一致（卡內 Spread $1.25/12.3%/Mid $10.12 = 排行表 = 推薦文字）；**IV Crush 手算驗證**：(125.5−90)×0.0418 = $1.484/股、每口 $148、佔權利金 1.484/10.125 = 14.7%，與卡內顯示一致（容許捨入位差）。IV 卡月波動 36.2% = 125.5/√12 ✓；Vega 卡 $4.18 = 0.0418×100 ✓；DTE 564 動態正確。財報日無資料 → 「暫無財報日資料」降級 ✓。
- [x] 空狀態頁：`.leaps-concept-card` 數量 0，整組不渲染。
- [x] 深色卡面、details 展開/收合正常；匯出 PNG 實際開檔（2850×4554）：四卡以展開狀態完整入鏡、文字可讀、無破版，排行表接續正常。
- [x] 回歸：352 examples, 0 failures；tooltips／字卡／匯出下載事件（`leaps_NVTS_20260707_1313.png`）不受影響。

---

# 第二部分：欄位 tooltips 與術語字卡（已交付）

## 需求

LEAPS 頁面（`/leaps`）的排行表 18 欄與 Options Flow 面板 10 欄標題，接上三層教學互動：

1. **hover 欄位標題** → 輕量 tooltip（跟隨滑鼠、防出界）
2. **點擊欄位標題** → driver.js 單步聚光 popover（overlay 壓暗、聚焦該欄標題）
3. **「欄位導覽」按鈕**（放匯出按鈕旁）→ driver.js 多步 tour（`showProgress: true`，排行表 18 步 → Options Flow 10 步）

## 架構（沿用 lesson8 模式 + 本專案既有約束）

1. **文案唯一來源**：`LEAPS_COL_EXPLAIN` 一份 JS map（`{ key: { el, title, desc, side } }`），三種互動全部引用它，不得複製第二份。
2. **hover 引擎**：document 層級事件委派（`mouseover`/`mousemove`/`mouseout` + `closest('[data-tip-key]')`），單一 fixed tooltip 元素 `#leaps-col-tip`（掛在 body、位於 `#leaps-export-root` 之外 → 天然不入匯出畫面）。
3. **點擊**：同一 document 委派，`[data-tip-key]` 點擊 → `window.driver.js.driver({ steps: [單步] }).drive()`。
4. **標頭定位**：排行表與 Flow 面板的每個 `th` 加 `id="leaps-th-{key}"` + `data-tip-key="{key}"`；Phlex 端以 `TABLE_COL_KEYS`／`FLOW_COL_KEYS` 陣列與既有 `TABLE_COLS`／`FLOW_COLS` 對齊（長度斷言，防錯位）。
5. **driver.js v1.x vendor 本地檔**（同 html-to-image 模式，零 CDN）：
   - `vendor/assets/javascripts/driver-1.6.0.iife.js`（IIFE build，暴露 `window.driver.js.driver`，與 lesson8 呼叫慣例一致）
   - `vendor/assets/stylesheets/driver-1.6.0.css`
   - ⚠️ `vendor/assets/stylesheets/` 是**新 asset 目錄**——依 `tasks/lessons.md` 2026-07-05 教訓，propshaft load path 在 boot 時固定，**建目錄後必須重啟 `fairprice-rails`（先徵求同意）**，否則全站 `Propshaft::MissingAssetError`。
   - 兩者僅在 LEAPS 頁載入（layout 的 `controller_name == 'leaps_recommendations'` 條件塊，與 jspdf 同模式）。
5b. **字級（2026-07-06 新增，不沿用第 8 課的 15/13/12.5px，偏小）**：

   | 元素 | 字級 |
   |---|---|
   | driver popover 標題（`.driver-popover-title`） | 17px |
   | driver popover 內文（`.driver-popover-description`） | 15px，line-height 1.8 |
   | driver popover 卡片寬度 | max-width 400px |
   | hover tooltip 標題 | 15px |
   | hover tooltip 內文 | 14px，max-width 340px |

   驗收驗的是 `getComputedStyle(el).fontSize` **實際生效值**，不是 CSS 檔面值、不是截圖目測。

6. **深色主題 override**：driver popover 預設白底；在 `app/assets/tailwind/application.css` 加 `.driver-popover` 系列 override（深色卡片：bg `#111827`/gray-900、標題 `#f9fafb`、內文 `#d1d5db`、按鈕深色描邊），hover tooltip `#leaps-col-tip` 同套色。色值對齊頁面既有 Tailwind gray 色階，不另造色票。修改後重建 CSS（`tailwindcss:build`）。
7. **純前端零後端**：無新路由、無 controller/service 變動，無 request spec 需求（有意識確認過的「不適用」）。
8. **無資料時**：「欄位導覽」按鈕 disabled（與匯出按鈕同規則——表格不存在時 tour 無錨點）。hover/點擊天然無效（標頭不存在）。
9. **與匯出功能的互動**：tooltip 與 driver popover 都掛在 body（export root 之外），匯出畫面不受影響；驗收仍須實際開 PNG 檔確認。

## 文案（LEAPS 買方視角；來源：instruction 檔，逐字採用）

### 排行表 18 欄（key 依序對齊 `TABLE_COLS`）

| key | 欄位 | 標題 | 說明 |
|---|---|---|---|
| expiration | 到期日 | 📅 Expiration | 合約到期日。LEAPS 慣例為一年以上，本表只列 364 天以上 |
| dte | DTE | ⏱ Days to Expiration | 距到期天數。364–550 近天期、550+ 遠天期；越長時間緩衝越大，Vega 曝險也越高 |
| strike | 履約價 | 🎯 Strike | 約定買入股價。深價內的 Call 行為越接近持有正股 |
| delta | Delta | ⚡ Delta | 股價每動 $1 權利金的理論變化。本表篩 0.60–0.90；越接近 1 越像股票替代品，槓桿越低但越穩 |
| oi | OI | 🔓 Open Interest | 未平倉合約數，本表排序主鍵。OI 高流動性通常較好；只在盤後更新 |
| volume | Volume | 📊 Volume | 當日成交量（即時）。OI 高但 Volume 長期為零，進出仍可能困難 |
| liquidity | 流動性判斷 | 🚦 流動性判斷 | 依本次查詢候選的 OI 三分位相對排名（充足/普通/偏低），非固定門檻；「⚠ 近期無成交」由 Vol/OI 比率判斷 |
| bid | Bid | ⬇️ Bid | 市場最高買價（賣出時的底價參考） |
| ask | Ask | ⬆️ Ask | 市場最低賣價（買入時的天花板參考） |
| mid | Mid | ⚖️ Mid | (Bid+Ask)/2，掛限價單參考價。本系統衍生欄位一律以 Mid 為權利金基準，不用可能過時的最後成交價 |
| spread | Spread% | ↔️ Spread% | (Ask−Bid)/Mid，一次進出的滑價成本。深價內常偏寬，>10% 要注意 |
| intrinsic | 內在價值 | 💎 Intrinsic Value | max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不流失 |
| extrinsic | 外在價值 | 🎈 Extrinsic Value | Mid−內在價值，時間＋波動率溢價（保險費），隨時間與 IV 回落流失 |
| extrinsic_pct | 外在佔比 | 🧮 外在佔比 | 外在÷Mid，「權利金裡幾 % 是保險費」。深 ITM LEAPS 核心指標：越低越接近持股替代，高 IV 環境尤其要壓低 |
| time_value_pct | Time Value% | 📐 Time Value% | 外在÷股價，「相對直接持股多付幾 % 溢價」。與外在佔比分母不同，回答不同問題 |
| iv | IV | 🌊 Implied Volatility | 該檔位隱含波動率。IV 越高權利金越貴；高 IV 買 LEAPS 要留意回落侵蝕（搭配 Vega） |
| vega | Vega | 🌀 Vega | IV 每變 1% 權利金的理論變化。DTE 越長 Vega 越大；IV Crush 風險量化：IV 回落 10% ≈ 損失 Vega×10 |
| itm_prob | 被指派機率 | 🎲 ITM Probability | Barchart 估到期價內機率。買方視角＝到期仍有內在價值的機率，與 Delta 相關但獨立模型計算 |

### Options Flow 面板 10 欄（key 依序對齊 `FLOW_COLS`；依 instruction 要點展開為 1–3 句）

| key | 欄位 | 標題 | 說明 |
|---|---|---|---|
| f_type | 類型 | 🏷 Type | Call（買權）或 Put（賣權）。搭配 Side 與方向欄一起判讀該筆大單的多空含義 |
| f_strike | 履約價 | 🎯 Strike | 該筆成交合約的履約價 |
| f_expiration | 到期日 | 📅 Expiration | 該筆成交合約的到期日。本面板不限 LEAPS，任何到期日都會入榜 |
| f_dte | DTE | ⏱ DTE | 距到期天數。與排行表的 364 天門檻無關，這裡看的是當天市場在哪些天期活動 |
| f_delta | Delta | ⚡ Delta | 正值=Call、負值=Put；絕對值越大越深價內 |
| f_code | Code | 🏳 Code | 交易所成交代碼。標準單腿代碼可信；AUTO／多腿類（SLAN、MLET、ISOI 等）標記普遍缺失，判讀需保守 |
| f_size | Size | 📦 Size | 該筆成交口數（1 口 = 100 股） |
| f_side | Side | ↕️ Side | 成交價位置：靠 bid=賣方主動（偏空）、靠 ask=買方主動（偏多）、mid=中性 |
| f_premium | Premium | 💰 Premium | 該筆成交的權利金總額。本面板依 Premium 降序取前 20 筆 |
| f_direction | 方向 | 🧭 方向 | 綜合 Type／Side／Code 的看多/看空/中性判讀。情緒參考，不參與排行排序 |

## 術語字卡區（含發音，2026-07-06 新增）

頁面底部新增「術語字卡」區（教學資源，不依賴查詢資料、空狀態也顯示），參考第 8 課字卡模式、適配深色卡面：

- **容器**：`<details>` 收合，預設收合，summary「📚 術語字卡（點擊翻面 · 🔊 聽發音）」。位於 export root 內但標 `data-export-exclude`（教學元素不入匯出畫面）。
- **互動**：正面＝英文術語＋KK/IPA 音標＋中文名＋一句提示；點卡片翻面（rotateY）看詳細解釋與實例；正面 🔊 朗讀英文術語（點 🔊 不翻面）。
- **發音**：Web Speech API `SpeechSynthesisUtterance`，`lang='en-US'`、`rate=0.85`；朗讀中按鈕加 `speaking` 樣式、結束移除；再次點擊先 `speechSynthesis.cancel()`。零外部服務。**降級**：`speechSynthesis` 不存在時隱藏全部 🔊，不報錯。
- **事件綁定**：第 8 課的 inline onclick 改為 document 委派＋`data-term`（點擊含 `.speak-btn` → 朗讀不翻面；否則含 `.leaps-vocab-card` → 翻面）。
- **字卡 15 張**（音標依 instruction 檔逐字使用）：LEAPS、Strike Price、Delta、Open Interest、Volume、Bid、Ask、Mid Price、Spread、Intrinsic Value、Extrinsic Value、Implied Volatility、Vega、IV Crush、Assignment。
- **背面文案**：沿用 `LEAPS_COL_EXPLAIN` 文案擴寫（LEAPS 買方視角），每張含一個實際數字例子（取自本頁實測資料，如 spot 14.46／strike 10／Mid 9.325），不另寫矛盾版本。

### 字卡驗收（2026-07-06 新增；✅ 自動化部分全過，🔊 聲音待使用者抽聽）

- [x] 字級 computed 驗證（`getComputedStyle` 實際生效值）：popover 標題 **17px**／內文 **15px**／line-height **27px**（=15×1.8）／maxWidth **400px**；tooltip 標題 **15px**／內文 **14px**／maxWidth **340px**。全部符合規格表。
- [x] 15 張全數渲染（順序與清單一致）、逐一翻面 15/15 正常＋翻回 toggle 正常（真實 click 路徑：點 Strike Price 卡只翻該卡）、點 🔊 不觸發翻面、speaking 樣式套用/移除正常。
- [x] Playwright spy：`speechSynthesis.speak` 被以正確 term（"Strike Price"、"LEAPS"）、`lang='en-US'`、`rate=0.85` 呼叫。**實際聲音輸出：待使用者抽聽 2–3 張（人工驗收，Playwright 聽不到聲音）。**
- [x] 匯出 PNG 重跑開檔：**修正記錄**——首驗發現 details 展開時輸出底部多 2208px 空白（html-to-image 的 filter 只是不畫內容，root 量測高度仍含字卡區）；修法是匯出前對 `[data-export-exclude]` 元素暫時 `display:none`、完成後還原（實測 details 匯出後恢復可見）。修復後輸出 2850×3160、**md5 `9d5f0aec…` 與 Phase I 驗收版逐位元組一致**（休市中資料凍結，同資料確定性渲染），字卡零入鏡。
- [x] 回歸：352 examples, 0 failures；匯出下載事件正常（`leaps_NVTS_20260706_1506.png`）。

## 驗收 Checklist（✅ 2026-07-05 全部驗收完成，證據如下）

- [x] driver.js **1.6.0**（v1.x 最新維護版）vendor 本地檔：`driver-1.6.0.iife.js` + `driver-1.6.0.css`（新目錄 `vendor/assets/stylesheets/` 依 propshaft 教訓重啟 server 後生效）；頁面上兩檔皆走 `/assets` digest 路徑，零 CDN。
- [x] 三種互動實測附截圖（NVTS live 頁）：hover 深色 tooltip（🧮 外在佔比）✓；點擊 th → driver 聚光 popover **深色主題**（實測 computed bg `rgb(17,24,39)` = gray-900；首驗抓到白底問題——driver.css 晚於 tailwind.css 載入蓋掉 override，以 selector specificity 升級修正，未動 vendor 檔、未用 !important）✓；「欄位導覽」28 步 tour（1 of 28 → 28 of 28，showProgress 顯示）✓。
- [x] 28 欄逐一程式化驗證：28 個 th 全有 `data-tip-key`＋id，0 dead key（逐一 dispatch mouseover 確認 tooltip 有內容）；key↔標籤對應正確（expiration=到期日 … f_direction=方向）；tour 28 步標題序列與規格文案表完全一致（排行 18 → Flow 10）。
- [x] 匯出 PNG 重跑＋實際開檔：輸出 md5 `9d5f0aec…` 與 Phase I 驗收版**逐位元組一致**，教學元素（導覽按鈕/tooltip/driver DOM）零入鏡；下載事件觸發（`leaps_NVTS_20260705_2242.png`）。
- [x] 無資料時「欄位導覽」按鈕 disabled（空狀態頁實測）。
- [x] 回歸：零後端變動（git diff 無 routes/controllers/services）；全套 RSpec **352 examples, 0 failures**；匯出下載事件正常。

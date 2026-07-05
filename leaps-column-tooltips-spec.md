# FairPrice 新功能規格：LEAPS 欄位教學說明（driver.js tooltips）

> 來源指令：`leaps-column-tooltips-instruction.md`（2026-07-05）。依主規格「新功能另開規格文件」規則獨立成檔。
> 參考模式：`~/csp/option-basics-lesson8.html` 的三層互動架構（已實地解析其實作）。

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

## 驗收 Checklist（E2E 實際操作，不是看 code）

- [ ] driver.js v1.x vendor 本地檔（檔名含版本號、已 commit），LEAPS 頁零新增 CDN script/link 標籤（git diff 可證）。
- [ ] 三種互動實測附截圖：hover 出深色 tooltip、點擊出 driver 聚光 popover（**深色主題，不是白底**）、「欄位導覽」按鈕走完整 28 步 tour（showProgress 顯示進度）。
- [ ] 排行表 18 欄＋Options Flow 10 欄逐一驗證：無 dead key（每個 th 的 data-tip-key 都在 map 裡）、無文案錯位（程式化比對 th 文字 vs map 標題對應）。
- [ ] 匯出 PNG 重跑並**實際開檔**：tooltip／導覽相關元素未入鏡。
- [ ] 無資料時「欄位導覽」按鈕 disabled。
- [ ] 回歸：匯出、user_strike 流程不受影響；全套 RSpec 352 examples 通過。

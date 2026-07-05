# 新功能指令：LEAPS 頁面欄位教學說明（driver.js tooltips）

依主 spec 規則**另開新規格檔** `leaps-column-tooltips-spec.md`（與主 spec 同目錄），寫完 spec 後直接實作。

## 參考模式

`option_basics_lesson8.html`（期權小學堂第 8 課）的三層互動，照搬架構：**一份資料 map 作為文案唯一來源**，三種互動共用：

1. hover 欄位標題 → 輕量 tooltip
2. 點擊欄位標題 → driver.js 單步聚光 popover
3. 「欄位導覽」按鈕（放匯出按鈕旁）→ 多步 tour（showProgress: true）

hover 引擎用 document 層級事件委派＋ `data-tip-key` 屬性。

## 架構約束

1. driver.js v1.x 走 **vendor 本地檔**（同 html-to-image 模式：UMD build、檔名含版本號、commit 進 repo、零 CDN）。CSS 一併本地化，補**深色主題 override**（driver popover 預設白底，改用頁面既有深色卡片顏色變數，不另造色票）。
2. 純前端、零後端變動——無新路由、無 request spec 需求（有意識確認過的「不適用」）。
3. 文案 map 只定義一份（`LEAPS_COL_EXPLAIN`），三種互動引用同一份，不得複製。
4. 排行表與 Options Flow 面板的欄位標題都要接上；標頭加可定位的 id 或 data 屬性。

## 文案（LEAPS 買方視角，直接使用；不要沿用第 8 課的 CSP 賣方文案）

### 排行表 18 欄

| 欄位 | 標題 | 說明 |
|---|---|---|
| 到期日 | 📅 Expiration | 合約到期日。LEAPS 慣例為一年以上，本表只列 364 天以上 |
| DTE | ⏱ Days to Expiration | 距到期天數。364–550 近天期、550+ 遠天期；越長時間緩衝越大，Vega 曝險也越高 |
| 履約價 | 🎯 Strike | 約定買入股價。深價內的 Call 行為越接近持有正股 |
| Delta | ⚡ Delta | 股價每動 $1 權利金的理論變化。本表篩 0.60–0.90；越接近 1 越像股票替代品，槓桿越低但越穩 |
| OI | 🔓 Open Interest | 未平倉合約數，本表排序主鍵。OI 高流動性通常較好；只在盤後更新 |
| Volume | 📊 Volume | 當日成交量（即時）。OI 高但 Volume 長期為零，進出仍可能困難 |
| 流動性判斷 | 🚦 流動性判斷 | 依本次查詢候選的 OI 三分位相對排名（充足/普通/偏低），非固定門檻；「⚠ 近期無成交」由 Vol/OI 比率判斷 |
| Bid | ⬇️ Bid | 市場最高買價（賣出時的底價參考） |
| Ask | ⬆️ Ask | 市場最低賣價（買入時的天花板參考） |
| Mid | ⚖️ Mid | (Bid+Ask)/2，掛限價單參考價。本系統衍生欄位一律以 Mid 為權利金基準，不用可能過時的最後成交價 |
| Spread% | ↔️ Spread% | (Ask−Bid)/Mid，一次進出的滑價成本。深價內常偏寬，>10% 要注意 |
| 內在價值 | 💎 Intrinsic Value | max(0, 現價−履約價)，權利金裡「已在錢裡」的部分，股價不動也不流失 |
| 外在價值 | 🎈 Extrinsic Value | Mid−內在價值，時間＋波動率溢價（保險費），隨時間與 IV 回落流失 |
| 外在佔比 | 🧮 外在佔比 | 外在÷Mid，「權利金裡幾 % 是保險費」。深 ITM LEAPS 核心指標：越低越接近持股替代，高 IV 環境尤其要壓低 |
| Time Value% | 📐 Time Value% | 外在÷股價，「相對直接持股多付幾 % 溢價」。與外在佔比分母不同，回答不同問題 |
| IV | 🌊 Implied Volatility | 該檔位隱含波動率。IV 越高權利金越貴；高 IV 買 LEAPS 要留意回落侵蝕（搭配 Vega） |
| Vega | 🌀 Vega | IV 每變 1% 權利金的理論變化。DTE 越長 Vega 越大；IV Crush 風險量化：IV 回落 10% ≈ 損失 Vega×10 |
| 被指派機率 | 🎲 ITM Probability | Barchart 估到期價內機率。買方視角＝到期仍有內在價值的機率，與 Delta 相關但獨立模型計算 |

### Options Flow 面板 10 欄

每欄 1–3 句，比照上表格式展開：

| 欄位 | 說明要點 |
|---|---|
| 類型 | Call / Put |
| 履約價 | 該筆成交的合約履約價 |
| 到期日 | 該筆成交的合約到期日 |
| DTE | 距到期天數 |
| Delta | 正=Call、負=Put |
| Code | 標準單腿代碼可信；AUTO/多腿標記不可信，判讀保守 |
| Size | 成交口數 |
| Side | 靠 bid=賣方主動、靠 ask=買方主動、mid=中性 |
| Premium | 權利金總額，本面板依此取前 20 |
| 方向 | 看多/看空/中性判讀，情緒參考、不參與排行排序 |

## 驗收（E2E 實際操作，不是看 code）

1. 實際查詢後三種互動各實測並附截圖：hover 出 tooltip、點擊出 driver 聚光 popover（**深色主題，不是白底**）、導覽按鈕走完整 tour。
2. 排行表 18 欄＋Options Flow 10 欄逐一點過：無 dead key、無文案錯位。
3. 匯出 PNG 重跑，**實際開檔**確認 tooltip/導覽元素未入鏡（不是推論確認）。
4. 回歸：匯出、排序、user_strike 不受影響，352 examples 全過。

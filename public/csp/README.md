# CSP — 期權教學工具

## 檔案說明

- `option-basics-lesson0.html` — 期權小學堂第0課：四種基本部位（Long/Short Call/Put）
- `option-basics-lesson4.html` — 期權小學堂第4課：Roll Position CSP 滾倉策略

---

### 2026-05-26 — 第4課加入語音朗讀（TTS）及字型大小調整

- 固定頂部 TTS 列：▶ 朗讀全文 / ⏹ 停止 / 進度點 / 段落名稱顯示
- 語速選單（0.8× ～ 1.2×）、音量滑桿
- A− / A+ 字型縮放（0.7× ～ 2.0×，persist 至 `l4-font-zoom`）
- 即時字幕（逐字高亮 `.sub-c.now`）
- 朗讀 SCRIPT 涵蓋 8 段：開場白、什麼時候需要滾倉、範例部位、Roll Out、Roll Down、Roll Out+Down、比較圖、洞察
- 朗讀中對應段落自動高亮（`.tts-active` outline）並自動捲動至視窗

### 2026-05-25 — 第5課追加：造市商完整說明 + Delta 對沖互動導覽

擴充 `option-basics-lesson5.html`，在 Bonus Panel 後新增四個說明章節：

- **Section 6 — 造市商與交易所合約**：Market Maker Agreement 特權（零手續費、優先撮合、股票出借、自有訂單流）vs 義務（雙邊連續報價、最大 Spread 限制、不可單方面撤市）
- **Section 7 — 商業模式：靠 Spread（價差）賺錢**：Bid/Ask 圖解，NOK Put $2.00/$2.05 例子，每口 $5 利潤
- **Section 8 — Delta 對沖實現「無風險」收 Spread**：NOK 4 步流程（買 Put → −300 Delta → 買 300 股 → Net ≈ 0 → 只留 Spread），附「為什麼是 300 股不是 1,000 股」對比表、Delta 含義說明、動態 Delta 表（OTM/ATM/ITM）、「你的 CSP Delta 決定造市商持股數」表格、兩個實戰推論（ATM Spread 較寬、OTM→ITM 磁吸效應）
- **Section 9 — 沒有造市商會怎樣**：4 格後果（Spread 暴漲、期權無法成交、滾倉失敗、只有完美時機才能交易）+ 金色三者關係總結框

其他更新：
- **A+ / A− 字體調整按鈕**加入 TTS bar（per-element WeakMap 實作，`l5-font-zoom` key）
- **Driver.js 7 步互動導覽**（「🎯 啟動 Delta 對沖導覽」）：逐步說明 Market Maker（造市商）從接單到 Delta 歸零到保留 Spread 的完整流程
- Driver.js popover 寬度 360 → 480px，標題不換行

---

### 2026-05-25 — 第8課 如何看懂 Barchart Options Prices & Volatility & Greeks

新增 `option-basics-lesson8.html`：模擬 Barchart 期權鏈兩個頁籤的互動教學頁。Driver.js 導覽（Options Prices 8步 + Greeks 5步）、15張翻轉字卡含🔊英文發音、TTS 朗讀、拖曳版面。`index.html` 新增第8課卡片，堂課計數更新為8堂。

---

### 2026-05-21 — CC 課 Covered Call 備兌買權完全教學

新增 `cc-covered-call-lesson.html`：
- 4 大面板（CC 定義、Strike 選擇、聰明掛單、Delta 分析）
- 全寬 Bonus（三種到期情境 + 實戰總結口訣）
- TTS 朗讀列：▶ 朗讀全文 / ⏸ 暫停 / ⏹ 停止 / 語速調整 / 點擊進度點跳段
- 編輯模式：Ctrl+E 進入，點擊任意文字編輯，底部工具列調整字型/大小/顏色

### 2026-05-11 — 第5課 造市商與滾倉的關係

新建 `option-basics-lesson5.html`，內容源自 `造市商與滾倉的關係.md`，風格與 csp-comic.html 完全一致：
- Panel 1：造市商市場結構——三方角色圖（你 ↔ 造市商 ↔ 真正對手方），Citadel/SIG/Virtu 等機構說明
- Panel 2：Delta 對沖機制——流程鏈（你賣Put → MM買Put → SQQQ股票對沖），SQQQ Gamma 特殊性警示，MM三大風險
- Panel 3：滾倉三種操作——Roll Net 公式框、Roll Out / Roll Down / Roll Out+Down 三種類型卡片、真實 SQQQ Roll Credit +$1,904 結果
- Panel 4：觸發時機——四格觸發條件（DTE≤21、獲利≥50%、Delta>-0.50、IV上升）、ITM/OTM SVG 判斷圖、不建議Roll警示
- Bonus Panel：真實案例（04/16-20 開倉 → 05/01 Roll Out → 09/18 到期）三節點 Timeline、Premium 總帳（$4,083.84）、造市商視角對比表、Wheel 策略五大實務啟示
- 完整 Edit Mode（✏️ 按鈕 + Ctrl+E，點任意文字可編輯字體/大小/粗斜/顏色/行距）

### 2026-05-11 — 期權小學堂入口頁面 index.html

新建 `index.html`，作為所有期權教學課程的入口導覽頁：
- 承襲 `csp-comic.html` 的暖色牛皮紙設計系統（--bg、--ink、--gold 等 CSS 變數）
- 橫向滾動的五張課程卡片，每張含：課程編號 banner、標籤 pill、標題、可編輯描述、重點摘要、難度標示、「開始學習」連結
- **可拖曳重排**：HTML5 Drag & Drop API，拖曳任意卡片改變學習順序
- **可編輯筆記**：點擊課程描述區域即可 contenteditable 修改，Enter/blur 自動儲存
- 順序與筆記均持久化至 `localStorage`（key: `idx-courses-v1`），重整頁面保留設定
- 進度列（頂部 prog-dots）連結各課程頁面
- 「↺ 還原順序」按鈕可重設所有設定，「💾 儲存筆記」手動全部同步

### 2026-05-02 — 第4課 Roll Position 滾倉教學頁面

新建 `option-basics-lesson4.html`，風格與 lesson0 一致，以 SQQQ CSP 為示範部位，包含：
- 三種滾倉互動教學：Roll Out（延期）、Roll Down（降履約）、Roll Out+Down（雙向）
- 每種滾倉均有：仿真券商 持有倉位／新開倉位 下單表單、Net Price 計算、calc bar
- Chart.js 4.x + annotation plugin 繪製 P&L 折線圖（滾倉前 vs 滾倉後即時對比）
- 三種滾倉疊加比較圖、總結表格、關鍵原則 insight grid
- 完整可拖曳版面（drag layout）+ 文字編輯模式（與 lesson0 相同系統）
- localStorage key：`l4-layout-v1`、`l4-state-v1`

### 2026-05-01 — Long Call 下單範例互動介面

在 `option-basics-lesson0.html` 的 Long Call 章節下方新增 `longcall-order` 可拖曳區塊，包含：
- 參照真實券商截圖的互動下單表單（配色完全一致）
- 合約數、股票代號、到期日、履約價、限價均為可編輯輸入框，驅動即時計算
- 動態損益分析表（損益兩平、最大虧損、情境模擬）
- SQQQ 特殊性說明

修正 HTML DOM 結構問題：`#drag-canvas` 被多餘 `</div>` 提早關閉，導致 8 個 `data-drag-id` 元素游離在 canvas 之外、layout 系統無法定位。

### 2026-06-15 — 第9課 PMCC 黃金法則與建倉試算

新建 `option-basics-lesson9.html`，風格與第7、8課完全一致，主題為 Poor Man's Covered Call（PMCC）：
- PMCC 概念介紹與 LEAPS vs 正股資金比較表（NOK 實際數據）
- Long LEAPS 選擇標準（Delta ≥ 0.80、DTE ≥ 180）與 Short Call 選股條件（Delta 0.20–0.35、19–45 DTE）
- **黃金法則試算器**：P_L < K_S − K_L，Delta 與 ITM Prob 為強制必填欄位，缺填時紅色高亮提示
- 三種市場情境（橫盤/大跌/暴漲）與對應損益說明
- 完整平倉策略 A/B/C 情境，含程式碼範例，及滾倉三種方式（Roll Up / Roll Out / Roll Up&Out）
- TTS 朗讀、拖曳版面、字體縮放、文字編輯模式全部齊備
- localStorage keys：`l9-layout-v1`、`l9-state-v1`、`l9-font-zoom`
- index.html 新增第9課卡片（banner-l9 金棕色漸層）

### 2026-06-17 — 第10課 Net Trade Sentiment 與 Delta Imbalance 指標

在 `option-basics-lesson10.html` 工具區新增兩個彙總方向性指標：

- **Net Trade Sentiment**：依 Side 欄位分類（ask=Bullish、bid=Bearish、mid=排除），加總各方向 Premium，計算淨多空溢價差
- **Delta Imbalance**：同樣分類邏輯，計算各筆 Delta×Size×100 的方向性淨值
- 兩指標以水平色條並排顯示，左端（紅）=空方總額、右端（綠）=多方總額、中間標記線=淨值位置
- 隨週選（W）/月選（M）篩選器即時重新計算
- 加入 mid-side 排除說明與官方數字差異免責備註

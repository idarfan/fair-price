# 功能指令：LEAPS 頁面教學功能（依交辦順序實作）

開新規格檔 `leaps-column-tooltips-spec.md`（與主 spec 同目錄），以下兩部分寫成同一份 spec 的第一、二節，**依序實作：先第一部分（推薦分析圖卡），再第二部分（欄位 tooltips 與術語字卡）**。

例外：第二部分的「文案 map」與「vendor driver.js」是共用地基，若第一部分需要引用文案體系，可先建 map 再做圖卡，但交付順序仍是圖卡先驗收。

---

# 第一部分：推薦分析區收摺式名詞解釋圖卡


## 需求

推薦分析區塊（近天期/遠天期推薦文字）**下方**加四張收摺式圖卡，標題為名詞本身，預設收合：

1. Bid-Ask Spread
2. IV（隱含波動率）
3. Vega
4. IV Crush 風險

## 架構約束

1. 收摺用原生 `<details>/<summary>`，零 JS、無新函式庫；樣式沿用頁面深色卡片配色變數。
2. **Phlex 元件 server-side 渲染，動態代入當次推薦合約的實際數值**（spread_pct、iv、vega、mid、外在價值），不是寫死的教科書範例。推薦不存在（無候選）時整組圖卡不渲染。
3. 純前端顯示層變動，無新路由、無新 service、無 request spec 需求（有意識確認的不適用）。
4. 名詞若與欄位 tooltips 文案重疊，圖卡是**深入版**（含損失試算），tooltips 是一句話版，兩者各自維護、互不取代。

## 圖卡文案（`{...}` 為動態代入值，以下數字僅為示意）

### 📉 Bid-Ask Spread（買賣價差）

買方掛單的天花板（Ask）與底價（Bid）的距離，是**進出場的隱形成本**。
以本次推薦為例：Spread ${ask−bid}（{spread_pct}%）——用市價單買進再賣出，一來一回直接損失約 **${(ask−bid)×100}/口**，還沒算股價變動。
LEAPS 深價內檔位成交稀疏，Spread 普遍偏寬；**務必用限價單掛 Mid（${mid}）附近**，可省下約一半的滑價成本。Spread% 超過 10% 的合約，進出場成本已足以吃掉數個百分點的獲利，部位規劃要把這筆成本算進去。

### 🌊 IV（隱含波動率）

市場從權利金反推出的**預期年化波動率**。本合約 IV {iv}%，代表市場預期未來一年股價年化波動約 ±{iv}%（換算每月約 ±{iv/√12}%）。
對買方的意義：**IV 越高，你買的權利金越貴**——外在價值裡的波動率溢價成分越大。在高 IV 時買進 LEAPS，等於用貴的價格買保險；就算方向看對，IV 回落也會侵蝕獲利（詳見 IV Crush 卡）。

### 🌀 Vega（IV 敏感度）

IV 每變動 1%，權利金的理論變化量。本合約 Vega {vega}，即 **IV 每降 1%，每口損失約 ${vega×100}**。
天期越長 Vega 越大——這正是 LEAPS 的特性：DTE 568 天給了 IV 均值回歸充分的時間，Vega 曝險遠高於短天期合約。壓低 Vega 風險的方法是選更深價內（外在佔比更低）的履約價。

### ⚡ IV Crush 風險（波動率回落損失）

高 IV 不會永遠維持——財報公布、事件落地、恐慌消退後，IV 常快速回落，權利金中的波動率溢價瞬間蒸發，這就是 IV Crush。**股價沒跌，你的合約照樣虧損。**
用本合約試算：IV {iv}% 若回落至 90%（對高波動股仍屬偏高水位），損失 ≈ ({iv}−90) × Vega {vega} ≈ **${損失}/股（每口 ${損失×100}）**，約佔權利金 {損失/mid}%——等於股價要先漲 {損失/現價}% 才能打平這筆隱形損耗。
防禦方式：(1) 選外在佔比低的深價內履約價（本卡損失全部發生在外在價值上，內在價值不受 IV 影響）；(2) 避開財報前 IV 高峰進場（下次財報：{latest_earnings}）；(3) 用 IV Rank 判斷目前 IV 處於歷史高位或低位。

## 驗收（E2E 實際操作）

1. 實際查詢有推薦結果的 symbol：四張卡預設收合、逐一展開，**動態數字與上方推薦文字一致**（例：推薦顯示 Spread 13.4% → 圖卡內同為 13.4%），並任選一張手算驗證試算式（如 IV Crush 損失額）正確。
2. 無候選的天期區間不出現圖卡；完全無推薦時整組不渲染。
3. 深色主題、展開/收合動作正常；匯出 PNG **實際開檔**確認圖卡以當下展開狀態正確入鏡、無破版。
4. 回歸：tooltips、匯出、排序、user_strike 不受影響，全套測試通過。

---

# 第二部分：欄位 tooltips 與術語字卡


## 參考模式

`option_basics_lesson8.html`（期權小學堂第 8 課）的三層互動，照搬架構：**一份資料 map 作為文案唯一來源**，三種互動共用：

1. hover 欄位標題 → 輕量 tooltip
2. 點擊欄位標題 → driver.js 單步聚光 popover
3. 「欄位導覽」按鈕（放匯出按鈕旁）→ 多步 tour（showProgress: true）

hover 引擎用 document 層級事件委派＋ `data-tip-key` 屬性。

## 架構約束

1. driver.js v1.x 走 **vendor 本地檔**（同 html-to-image 模式：UMD build、檔名含版本號、commit 進 repo、零 CDN）。CSS 一併本地化，補**深色主題 override**（driver popover 預設白底，改用頁面既有深色卡片顏色變數，不另造色票）。
   **字級不沿用第 8 課（第 8 課的 15/13/12.5px 偏小），依下表為準**：

   | 元素 | 字級 |
   |---|---|
   | driver popover 標題（`.driver-popover-title`） | 17px |
   | driver popover 內文（`.driver-popover-description`） | 15px，line-height 1.8 |
   | driver popover 卡片寬度 | max-width 400px（配合字級放大，避免卡片過長） |
   | hover tooltip 內文 | 14px，max-width 340px |
   | hover tooltip 標題 | 15px |
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

## 術語字卡區（含發音）

頁面**底部**（推薦分析之後）新增「術語字卡」區，參考第 8 課字卡模式，適配深色主題：

**互動**：卡片正面顯示英文術語＋KK/IPA 音標＋中文名稱＋一句提示；點卡片翻面（rotateY）看詳細解釋與實例；正面 🔊 按鈕朗讀英文術語（點 🔊 不翻面）。整區包在 `<details>` 收合容器內，預設收合，標題「📚 術語字卡（點擊翻面 · 🔊 聽發音）」。

**發音實作**：照搬第 8 課——瀏覽器原生 Web Speech API，`SpeechSynthesisUtterance`，`lang='en-US'`、`rate=0.85`；朗讀中按鈕加 `speaking` 樣式、結束移除；再次點擊先 `speechSynthesis.cancel()`。零外部服務、零新函式庫。**降級處理**：`speechSynthesis` 不存在或無可用語音時隱藏 🔊 按鈕，不得報錯。

**⚠️ 事件綁定改寫**：第 8 課的 🔊 用 inline `onclick`，違反本專案慣例——改成事件委派＋`data-term` 屬性，翻面與朗讀都走 document 層級委派（點擊目標含 `.speak-btn` 時朗讀不翻面，否則翻面）。

**字卡清單（15 張，音標直接使用，不要自行發明）**：

| 英文 | 音標 | 中文 |
|---|---|---|
| LEAPS | /liːps/ | 長天期選擇權 |
| Strike Price | /straɪk praɪs/ | 履約價 |
| Delta | /ˈdɛltə/ | 方向敏感度 |
| Open Interest | /ˈoʊpən ˈɪntrəst/ | 未平倉量 |
| Volume | /ˈvɑːljuːm/ | 成交量 |
| Bid | /bɪd/ | 買價 |
| Ask | /æsk/ | 賣價 |
| Mid Price | /mɪd praɪs/ | 中間價 |
| Spread | /sprɛd/ | 買賣價差 |
| Intrinsic Value | /ɪnˈtrɪnsɪk ˈvæljuː/ | 內在價值 |
| Extrinsic Value | /ɛkˈstrɪnsɪk ˈvæljuː/ | 外在價值 |
| Implied Volatility | /ɪmˈplaɪd ˌvɑːləˈtɪləti/ | 隱含波動率 |
| Vega | /ˈveɪɡə/ | IV 敏感度 |
| IV Crush | /aɪ viː krʌʃ/ | 波動率回落 |
| Assignment | /əˈsaɪnmənt/ | 被指派 |

卡片背面解釋文字沿用本檔欄位文案 map 的內容擴寫（LEAPS 買方視角、每張含一個實際數字例子），不要另寫一套互相矛盾的版本。

## 驗收（E2E 實際操作，不是看 code）

1. 實際查詢後三種互動各實測並附截圖：hover 出 tooltip、點擊出 driver 聚光 popover（**深色主題，不是白底**）、導覽按鈕走完整 tour。字級驗證用 Playwright 在彈出元素上執行 `getComputedStyle(el).fontSize` 取**實際生效值**，確認符合規格表（popover 內文 15px、tooltip 內文 14px）——驗的是渲染後生效的值，不是 CSS 檔裡寫的值，也不是截圖目測。
2. 排行表 18 欄＋Options Flow 10 欄逐一點過：無 dead key、無文案錯位。
3. 匯出 PNG 重跑，**實際開檔**確認 tooltip/導覽元素未入鏡（不是推論確認）。
4. 字卡：15 張全數渲染、逐一翻面正常、點 🔊 不觸發翻面；用 Playwright spy 驗證 `speechSynthesis.speak` 被以正確 term 與 `lang='en-US'` 呼叫（自動化部分）；實際聲音輸出由使用者抽聽 2–3 張確認（Playwright 聽不到聲音，這部分誠實標註為人工驗收）。
5. 回歸：匯出、排序、user_strike 不受影響，全套測試通過。

# CSP 互動漫畫動態化規格書

> 目標檔案：`csp-comic.html`（單檔 HTML，無框架，純 JS + SVG + localStorage 拖曳系統 + Web Speech TTS）
> 任務：把目前**寫死 SQQQ 範例**（$60 履約價／$5 權利金／3口／300股／5/15 到期）的版面，改成**接受使用者輸入任意參數**並自動重算所有衍生數值、文字與 SVG 圖表。

---

## 1. 目標與範圍

### 必須做
1. 新增一個輸入區塊，讓使用者輸入 5 個核心參數：
   - 股票代號（ticker）
   - 履約價格（strike）
   - 權利金金額（premium，每股）
   - 口數（contracts）
   - 到期日（expiration date）
2. 所有目前寫死在 HTML 文字、`spill`/`result-box`/`ledger`/SVG 文字節點裡的數字，全部改為由上述 5 個輸入即時計算後動態填入。
3. Panel 2 / Panel 3 的 SVG 股價示意曲線終點數字、Panel 4 損益圖的座標軸標籤，也要依輸入比例自動調整（仍是示意圖，非真實報價）。
4. TTS 朗讀逐字稿（`SCRIPT` 陣列）目前是寫死字串，內含具體數字，需改成依目前參數動態組字串，否則畫面數字換了但語音還唸舊數字。
5. **移除 Bonus Panel（第 5 格・Wheel 融資接股情境）**：CSP 被指派接股的成本來自原本就凍結的保證金（現金帳戶），不會、也不該再疊加融資槓桿去買股票；原版面把「融資接股」接在 CSP Wheel 教學後面，邏輯本身就有問題，直接整塊刪除，不用改寫成動態版本（見第 5 節）。

### 不要做（保留原樣）
- 拖曳 / 縮放排版系統（`drag-canvas`、`data-drag-id`、localStorage layout）完全不動。
- 編輯模式工具列（字體/大小/顏色/行距/圖片定位）完全不動。
- TTS 播放引擎機制（dots、字幕逐字高亮、語速/音量控制、`pronounce()`）不動，只動 `SCRIPT[].text` 的**內容組成方式**。
- 整體配色 CSS 變數、版面結構（panel 數量、grid）不動。
- 兩個角色頭像（大野狼／小紅帽）與其隱喻文字不動，與標的代號無關。

---

## 2. 核心輸入參數規格

新增一個輸入面板（建議放在 `.page-header` 的 `.contract-box` 旁或上方，給一個新的 `data-drag-id="csp-controls"` 讓它也能被現有拖曳系統管理）。

| 欄位 | 變數名 | 型態 | 預設值（沿用原範例） | 驗證規則 |
|---|---|---|---|---|
| 股票代號 | `ticker` | string | `SQQQ` | 1–6 個英文字母，自動轉大寫 |
| 履約價格 | `strike` (K) | number | `60` | > 0，可 2 位小數 |
| 權利金（每股） | `premium` (P) | number | `5.00` | > 0，2 位小數；若 `premium >= strike` 顯示警告（損益平衡會 ≤ 0） |
| 口數 | `contracts` (N) | integer | `3` | 整數，≥ 1 |
| 到期日 | `expDate` | date | `2026-05-15` | 合法日期；若早於今天顯示警告但不阻擋 |

### 互動行為
- 任一欄位 `input`/`change` 事件觸發 → 統一呼叫 `recalcAll()` 重新計算並重新渲染整頁，不需要送出按鈕（可加 150ms debounce）。
- 所有計算與字串組裝集中在一個 state object（例如 `window.cspState`），單一資料來源，避免到處重複計算。
- 數字格式化請統一用 2 個 helper：
  - `fmtMoney0(n)`：整數 + 千分位，例如 `$1,500`
  - `fmtMoney2(n)`：2 位小數 + 千分位，例如 `$5.00`
  - `fmtPct1(n)`：1 位小數百分比，例如 `57.0%`

---

## 3. 衍生計算公式（主要 5 輸入）

```text
shares          = contracts × 100
margin          = shares × strike                      // 保證金（凍結現金）
totalPremium    = shares × premium                      // 收到的總權利金 = 最大獲利
breakeven       = strike − premium                       // 損益平衡點／實際持股成本
maxLoss         = shares × (strike − premium)            // = margin − totalPremium，股票歸零時的最大虧損

// 僅供 Panel 2 / Panel 3 示意曲線終點用的「範例到期價」，非真實預測：
exampleUpPrice   = round(strike × 1.133)   // 情境A 示意：股價維持在 strike 之上
exampleDownPrice = round(strike × 0.867)   // 情境B 示意：股價跌破 strike

// Panel 4 損益圖座標軸的左右兩端標籤（示意刻度，依 strike 等比例縮放）：
chartLow   = round(strike × 0.67)
chartHigh  = round(strike × 1.33)
```

> 註：`exampleUpPrice` / `exampleDownPrice` / `chartLow` / `chartHigh` 純粹是讓 SVG 曲線「看起來合理」的示意數字，公式可以接受微調，重點是**必須隨 strike 連動**，不能再寫死 60/68/52/40/80。

---

## 4. 各區塊「舊寫死值 → 新動態值」對照表

### 4.1 合約內容卡（`.contract-box`）
| 位置 | 舊內容 | 新內容 |
|---|---|---|
| `.cb-ticker` | `SQQQ` | `{{ticker}}` |
| `.cb-item` 行權價 | `$60` | `${{strike}}` |
| `.cb-item` 權利金 | `$5.00` | `${{fmtMoney2(premium)}}` |
| `.cb-item` 到期日 | `5/15` | `{{expDate 格式化為 M/D}}` |
| `.cb-item` 張數 | `3口／300股` | `{{contracts}}口／{{shares}}股` |

### 4.2 Panel 1（賣出 Put）
- 標題、SVG 文字「← 收 Premium +$1,500」→ `+${{fmtMoney0(totalPremium)}}`
- 三條 bullet 文字改為模板字串：
  1. `我向市場賣出 {{contracts}} 張 {{ticker}} 賣權，答應到期日可能以 ${{strike}} 買 {{shares}} 股。`
  2. `券商先凍結 ${{fmtMoney0(margin)}} 現金當保證金（{{shares}} × ${{strike}}）。`
  3. `對方把 ${{fmtMoney0(totalPremium)}} 權利金馬上付給我（{{shares}} × ${{fmtMoney2(premium)}}）。`

### 4.3 Panel 2（情境A・股價不跌）
- 標題「到期日股價 ≥ $60」→ `≥ ${{strike}}`
- SVG「行權價 $60」→ `${{strike}}`；曲線終點「到期 $68」→ `到期 ${{exampleUpPrice}}`
- 軸標籤「5/15 到期」→ `{{expDate 格式化}} 到期`
- `result-box` 「+$1,500」→ `+${{fmtMoney0(totalPremium)}}`

### 4.4 Panel 3（情境B・股價下跌）
- 標題「到期日股價 < $60 / 我要以 $60 買入 300 股」→ 代入 `strike` / `shares`
- SVG「行權價 $60」→ `strike`；「損益平衡 $55」→ `breakeven`；曲線終點「到期 $52」→ `exampleDownPrice`
- `stat-pills`：被行權股數=`shares`、名義成本/股=`strike`、損益平衡=`breakeven`
- `result-box`「$55 ／ 股」→ `${{breakeven}} ／ 股`

### 4.5 Panel 4（損益圖）
- 標題「獲利上限 $1,500，損失上限 $16,500」→ `獲利上限 ${{fmtMoney0(totalPremium)}}，損失上限 ${{fmtMoney0(maxLoss)}}`
- SVG 軸標籤：`$55 BE`→`breakeven`、`$60 K`→`strike`、`$40`/`$80`→`chartLow`/`chartHigh`
- y 軸：`+1,500`→`+{{fmtMoney0(totalPremium)}}`、`-16,500`→`-{{fmtMoney0(maxLoss)}}`
- 「最多賺 $1,500」→ `最多賺 ${{fmtMoney0(totalPremium)}}`
- `payoff-stats` 三行：最大獲利=`+totalPremium`、損益平衡點=`breakeven／股`、最大風險=`−maxLoss`

> SVG 折線座標（`polyline points="..."`）目前是手刻的像素座標，對應「strike 在圖表中間偏右」的版面比例。Claude Code 可以保留目前的版面比例邏輯（loss zone / profit zone 的分割點對應 breakeven 與 strike 在 x 軸上的相對位置），不需要做成完全精確的座標轉換引擎，示意圖等級即可，但**轴上文字必須對應正確數值**。

---

## 5. 移除 Bonus Panel（Wheel 融資接股情境）

**直接整塊刪除**，不做動態化：

- HTML：移除 `<div id="csp-bonus-panel" data-drag-id="csp-bonus-panel" class="bonus-panel">...</div>` 整段（含內部 Timeline、Ledger、`summary-pills`、底部 `.warning` 融資警語）。
- CSS：`.bonus-panel`、`.bonus-body`、`.timeline`、`.ledger*`、`.summary-pills`、`.sum-pill*`、`.warning` 等若確認沒有被其他區塊共用，可一併清掉；若不確定是否共用，保留 CSS 規則本身無妨，只刪 HTML 即可。
- 拖曳系統：`localStorage` 的 layout 記錄裡會有 `csp-bonus-panel` 的座標，元素刪除後該 key 自然失效，不需要特別處理；但要確認 `resetLayout()`／`relayoutAfterZoom()` 等遍歷 `[data-drag-id]` 的邏輯在少一個節點時不會出錯（目前看程式是用 `querySelectorAll` 動態收集，應該沒問題）。

**原因**：CSP 被指派後買進股票，資金來源是賣 Put 時券商就已凍結的保證金（現金帳戶操作），不會也不該疊加融資槓桿；原版面把「融資接股 Wheel」接在 CSP 教學最後，概念上是錯的，所以不保留、不改寫，直接拿掉。

> 若之後想另外做一支「Covered Call / Wheel 現金接股」教學頁，那是完全獨立的新主題，跟這份 CSP 規格無關，屆時再開新規格。

---

## 6. TTS 朗讀稿動態化

`SCRIPT` 陣列（約在 `var SCRIPT = [...]`）目前每個 `text` 是寫死字串，包含 60、5、300、1500、55 等數字，且最後一段（`id: 'csp-bonus-panel'`）是 Bonus Panel 的朗讀內容——**這一段也要連同移除**，`SCRIPT` 陣列應只剩策略介紹 + Panel 1–4 共 5 段。

請把剩下的段落改成函式回傳模板字串（在每次 `recalcAll()` 後，或在朗讀前即時組出當前文字），例如：

```js
function buildScript(s) {
  return [
    { id: null, label: '策略介紹',
      text: `歡迎來到期權小學堂第一課。今天學習 Cash-Secured Put，中文叫現金抵押賣出權。我們用 ${s.ticker} 的一張真實合約，一步步看懂整個操作流程：賣出 Put，收到權利金，然後等待到期日的結果。` },
    { id: 'csp-panel-1', label: '賣出 Put',
      text: `第一步，賣出 Put。你跟對方約定，你願意在到期日用 ${s.strike} 元的行權價買入 ${s.ticker}。作為交換，對方先付給你每股 ${s.premium} 元的權利金。${s.contracts} 張合約共 ${s.shares} 股，立刻收到 ${s.totalPremium} 元現金入帳，無論之後怎樣都不退還。這筆錢就是你的最大獲利。` },
    // ...Panel 2 / Panel 3 / Panel 4 同理代入 s.breakeven / s.maxLoss / s.exampleUpPrice / s.exampleDownPrice 等，
    // 不再有對應 Bonus Panel 的第 6 段。
  ];
}
```

朗讀時呼叫 `buildScript(window.cspState)` 取得當下版本，而不是用最初載入時就固定的陣列。`initDots()` 等依 `SCRIPT.length` 算點數的邏輯不用改，少一段會自動只生成 5 個點。

---

## 7. 邊界案例與防呆

- `premium >= strike` → `breakeven <= 0`：在輸入區下方顯示一行警告文字（黃色提示框，可沿用現有 `.warning` 樣式），但不阻擋計算，照樣顯示（會出現負數或 0，讓使用者自己判斷）。
- `strike <= 0` 或 `premium <= 0` 或 `contracts <= 0`：阻擋計算，輸入框標紅，畫面保留上一次合法的計算結果。
- `expDate` 早於今天：顯示提示「到期日已過」但仍正常計算（教學情境不必強制檔掉）。
- 股票代號允許 1–6 碼英文字母，多餘字元自動過濾、轉大寫。

---

## 8. 驗收標準 Checklist

- [ ] 修改任一輸入欄位（ticker / strike / premium / contracts / expDate）後，**不需重新整理頁面**，全部文字與 SVG 數字即時更新。
- [ ] 全文搜尋 `60`、`5.00`、`300`、`1500`、`1,500`、`55` 等原範例數字，確認在「計算結果文字節點」中都已替換為變數，不再有殘留寫死值（裝飾性/結構性數字如 SVG viewBox、step-badge 編號 1-4 不需更動）。
- [ ] TTS 朗讀內容（按下「朗讀全文」）唸出的數字與畫面當前參數一致，且共只有 5 段（無 Bonus Panel 那一段）。
- [ ] 確認 `#csp-bonus-panel` 整個 DOM 節點、`SCRIPT` 裡對應該節點的朗讀段落都已移除，畫面上不再出現「進階・融資接股」相關文字或圖示。
- [ ] `premium >= strike` 時出現警告，但畫面不會壞掉（無 `NaN`、無版面跑掉）。
- [ ] 拖曳/縮放/編輯模式/字體縮放/TTS 播放控制等既有功能全部維持正常運作，未被改動破壞（移除 Bonus Panel 後，拖曳排版不會因為少一個節點而報錯）。
- [ ] 金額顯示一致使用千分位（如 `$1,500`），股價/權利金顯示到合理小數位。

---

## 9. 建議實作順序

1. 建立 `cspState` 物件 + `recalcAll()` / `render()` 骨架，先把第 3 節公式寫好（純計算，不碰 DOM）。
2. 新增輸入面板 UI，綁定 `oninput` → `recalcAll()`。
3. 依第 4 節對照表，把 Panel 1–4 的寫死文字節點改成由 `render()` 寫入（建議幫每個需要動態更新的文字節點加 `id`，方便 `render()` 用 `document.getElementById(...).textContent = ...` 操作，比重新產生整段 innerHTML 安全）。
4. SVG 數字標籤同理，用 `id` 定位後改 `textContent`；曲線 `points` 屬性若要連動可選擇性微調，非必須做到精確比例。
5. 處理第 5 節：刪除 Bonus Panel（HTML 節點 + 對應 TTS 段落）。
6. 處理第 6 節 TTS 動態化（連同確認少一段後 dots/朗讀流程仍正常）。
7. 套用第 7 節防呆規則。
8. 跑一輪第 8 節 Checklist。

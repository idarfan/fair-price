# 期權小學堂第7課 — Claude Code 建置指令

## 目標
建立一個**單一 HTML 檔案**，瀏覽器直接開啟即可使用，不需任何後端或 API Key。
手動輸入期權鏈數值 → 選行權價 → 輸入目標權利金 → BSM 反推計算股價需跌多少。

---

## 輸出檔案

```
~/csp-calculator/options_lesson7.html   ← 唯一檔案
```

---

## 使用方式

```bash
open ~/csp-calculator/options_lesson7.html       # macOS
xdg-open ~/csp-calculator/options_lesson7.html   # Linux / WSL
start ~/csp-calculator/options_lesson7.html      # Windows
```

---

## 完整規格

### 技術
- 純 HTML5 + Vanilla JS，單一 `.html` 檔案
- 不依賴任何外部 CDN 或套件
- 支援 light / dark mode（`prefers-color-scheme`）

---

## UI 佈局（由上至下）

### 區塊 1：Header
```
期權小學堂第7課
預估權利金上漲需要的股價波動
```

---

### 區塊 2：新增行權價

一排輸入欄位 + 「新增」按鈕，讓使用者逐行輸入期權鏈數據：

| 欄位 | type | placeholder | 說明 |
|------|------|-------------|------|
| 到期日 | text | 2026-06-18 | 第一行輸入後之後自動帶入 |
| DTE | number | 28 | 第一行輸入後之後自動帶入 |
| 行權價 K | number step=0.5 | 14.50 | 必填 |
| IV (%) | number step=0.01 | 68.85 | 必填 |
| Put Delta | number step=0.0001 | -0.5042 | 選填 |
| ITM Prob (%) | number step=0.01 | 45.34 | 選填 |

**「新增」按鈕**：按下後將這行加入下方表格，並清空 K / IV / Put Delta / ITM Prob 欄位（到期日與 DTE 保留）。

**「清除全部」按鈕**：清空已輸入的所有行。

---

### 區塊 3：已輸入的行權價表格

顯示所有已新增的行，欄位：

| 行權價 | IV | Put Delta | ITM Prob | OTM 距離 | 操作 |
|--------|-----|-----------|----------|---------|------|
| $14.50 | 68.85% | -0.5042 | 45.34% | — | [刪除] |

- OTM 距離由股價 S 與行權價計算，隨 S slider 即時更新
- 每行可點擊選取（高亮），或點「刪除」移除
- 點擊某行 → 自動選取該行權價並更新下方計算

---

### 區塊 4：選定行權價後的資訊卡

選定行權價後顯示：

上排 3 欄：
| 到期日 | DTE | IV (σ) |

下排 5 欄：
| Put Delta | ITM Prob | OTM 距離 | 當前股價 S | 目前 Put 理論價 |

---

### 區塊 5：微調 Slider

```
當前股價 S  [========●========]  $14.90   (range: 5–50, step: 0.01)
無風險利率  [====●============]   4.5%    (range: 1–8, step: 0.1)
```

---

### 區塊 6：目標 Put 權利金

```
我希望權利金達到  [ 2.00 ]  美元   目前 Put ≈ $1.20
```

- 大字 number input（step: 0.05）
- badge 即時顯示目前 Put 理論估值

---

### 區塊 7：計算結果

```
股價需跌至
$12.90
需下跌 13.42%（跌 $2.00）

┌─────────────────┐  ┌──────────────────────┐
│ 目前 Put 理論價  │  │ 目標時 Put Delta      │
│    $1.203       │  │    -0.6890            │
└─────────────────┘  └──────────────────────┘

┌──────────────────────────────────────┐
│  到達目標股價時，被 Assign 機率       │
│            75.40%                    │   ← 紅底大字
└──────────────────────────────────────┘
```

若目前 Put 已超過目標值，顯示黃色警告：
```
目前 Put 已是 $X.XXX，已達目標 $X.XX，無需股價下跌。
```

---

### 區塊 8：二分法迭代過程

`<details><summary>查看迭代過程</summary>` 預設收起：

```
步驟 1：S = 7.456，Put = 7.044，誤差 = 5.044
步驟 2：S = 11.178，Put = 3.622，誤差 = 1.622
步驟 3：S = 13.039，Put = 2.113，誤差 = 0.113
步驟 4：S = 13.970，Put = 1.649，誤差 = -0.351
步驟 5：S = 13.504，Put = 1.875，誤差 = -0.125
步驟 6：S = 13.272，Put = 1.991，誤差 = -0.009
步驟 7：S = 13.155，Put = 2.051，誤差 = 0.051
步驟 8：S = 13.213，Put = 2.021，誤差 = 0.021
```

---

## BSM 公式實作（內嵌於 HTML 的 JavaScript）

```javascript
function ncdf(x) {
  const a = [0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429];
  const p = 0.3275911;
  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x) / Math.sqrt(2);
  const t = 1 / (1 + p * x);
  const y = 1 - (((((a[4]*t+a[3])*t+a[2])*t+a[1])*t+a[0])*t) * Math.exp(-x*x);
  return 0.5 * (1 + sign * y);
}

function bsmPut(S, K, T, r, sigma) {
  if (S <= 0 || T <= 0 || sigma <= 0) return { put: NaN, delta: NaN, itm: NaN };
  const d1 = (Math.log(S/K) + (r + 0.5*sigma*sigma)*T) / (sigma*Math.sqrt(T));
  const d2 = d1 - sigma * Math.sqrt(T);
  return {
    put:   K * Math.exp(-r*T) * ncdf(-d2) - S * ncdf(-d1),
    delta: -ncdf(-d1),
    itm:   ncdf(-d2) * 100
  };
}

// 二分法反推：股價越低 Put 越貴
// diff > 0（put 太高）→ lo = mid（往高股價找）
// diff < 0（put 太低）→ hi = mid（往低股價找）
function inversePut(S_cur, K, T, r, sigma, target) {
  let lo = 0.01, hi = S_cur;
  const steps = [];
  for (let i = 0; i < 80; i++) {
    const mid = (lo + hi) / 2;
    const val = bsmPut(mid, K, T, r, sigma).put;
    const diff = val - target;
    if (i < 8) steps.push(
      `步驟 ${i+1}：S = ${mid.toFixed(3)}，Put = ${val.toFixed(4)}，誤差 = ${diff.toFixed(5)}`
    );
    if (Math.abs(diff) < 0.00005) return { S: mid, steps };
    if (diff > 0) lo = mid; else hi = mid;
  }
  return { S: (lo+hi)/2, steps };
}
```

---

## 資料結構

```javascript
// 所有行權價資料
let chainData = {};
// 格式：
// {
//   14.50: { expiry:'2026-06-18', dte:28, iv:68.85, put_delta:-0.5042, itm_prob:45.34 },
//   15.00: { expiry:'2026-06-18', dte:28, iv:70.97, put_delta:-0.5702, itm_prob:38.74 },
// }

let selectedK = null;  // 目前選定的行權價
```

---

## 事件流程

```
使用者填入欄位 → 按「新增」
  → 加入 chainData
  → 更新表格顯示
  → 若是第一行，自動選取 → calcResult()

點擊表格中某行
  → selectedK = 該 strike
  → 更新資訊卡
  → calcResult()

調整股價 slider / 利率 slider / 目標權利金
  → calcResult()
    → bsmPut(S, K, T, r, sigma) 計算目前理論價
    → 若 target <= currentPut → 顯示警告
    → 否則 inversePut() → 顯示結果
```

---

## CSS 變數

```css
:root {
  --bg: #ffffff; --bg2: #f5f5f4; --bg3: #eeede8;
  --text: #1a1a18; --text2: #6b6b67; --text3: #9b9b97;
  --border: rgba(0,0,0,0.12); --border2: rgba(0,0,0,0.22);
  --green-bg: #e1f5ee; --green: #0f6e56; --green-bd: #1d9e75;
  --amber-bg: #faeeda; --amber: #633806;
  --red-bg: #fcebeb; --red: #791f1f; --red-v: #a32d2d;
  --r: 8px; --rl: 12px;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1c1c1a; --bg2: #252523; --bg3: #2e2e2b;
    --text: #f0efe9; --text2: #a8a8a4; --text3: #6b6b67;
    --green-bg: #0a3328; --green: #5dcaa5;
    --amber-bg: #412402; --amber: #fac775;
    --red-bg: #3d1212; --red: #f09595; --red-v: #f09595;
  }
}
```

---

## 測試驗證

對照 NOK 2026-06-18 期權鏈，手動輸入以下資料後驗證：

| K | IV | Put Delta | ITM Prob |
|---|-----|-----------|----------|
| 13.00 | 65.28 | -0.2820 | 31.78 |
| 13.50 | 67.23 | -0.3534 | 39.17 |
| 14.00 | 67.68 | -0.4312 | 47.31 |
| 14.50 | 69.51 | -0.5042 | 45.34 |
| 15.00 | 68.75 | -0.5702 | 38.74 |

選 $14.50，股價設 $14.90，目標權利金輸入 $2.00：
- 應顯示股價需跌至約 **$12.90**
- 跌幅約 **-13%**
- 被 Assign 機率約 **75%**

# 專案教訓紀錄

## 2026-04-17 — react-resizable-panels v4 + CSS 高度鏈三個教訓

### 教訓 A：npm 套件裝完必須讀 `.d.ts`，不能從文件/記憶寫 code

**過錯：** 計畫基於 v2 文件研究，但裝上的是 v4。v4 Panel 的 `defaultSize`/`minSize`/`maxSize` 傳入純數字會被解讀為 **px**（非 %）。`maxSize={25}` = 25px = ~1.96% 容器寬，sidebar 被硬鎖，`setLayout()` 也因此無效。

**診斷關鍵：** `panel.style.flexGrow = "1.962"` 而非 "13"；`25px / 1273px = 1.963%`，精確吻合。

**防治規則：**
```
引入新 npm 套件三步驟（必做，不可跳過）：
1. 確認 package.json 裡實際安裝的 semver（npm install 後版本可能比預期高）
2. head -80 node_modules/<pkg>/dist/*.d.ts   ← 讀實際型別
3. 查 CHANGELOG 或 README 確認有無 breaking change
禁止直接從文件/記憶/計畫寫 code，必須先確認實際型別。
```

**本例正確格式：**
```tsx
// ✅ v4 Panel 尺寸一律用字串百分比
<Panel defaultSize="13%" minSize="8%" maxSize="25%">
// setLayout 的 layout 物件用 0-100 數字（%），與 Panel prop 格式不對稱
ref.current?.setLayout({ "lr-sidebar": 13, "lr-main": 87 })
```

---

### 教訓 B：全高佈局改前必須追蹤 CSS 高度鏈

**過錯：** `options-root` 缺少 `flex flex-col`，React `h-full` 失效，Group 只有 288px（應 517px）。改之前截圖已顯示所有面板壓扁在左上角，但誤判成 localStorage 問題沒有繼續追查。

**防治規則：**
```
新增任何 h-full / flex-1 / overflow-hidden 容器前，
先用 browser_evaluate 量從 body 到目標元素的每一層高度：
  root → main → outer-div → react-div → group
確認每層 getBoundingClientRect().height 與預期一致，
再動手寫 code。
```

改用 `flex-1 min-h-0` 比 `h-full` 更可靠，因為不依賴父層有明確 height。

---

### 教訓 C：截圖異常就要量數字，不要跳過繼續

**過錯：** 第一張截圖看到 sidebar 顯示垂直字（壓扁狀態），應立即 `browser_evaluate` 量 `panel.style.flexGrow`，就能在 5 分鐘內定位問題。但選擇先假設是 localStorage 壞掉，多繞了一大圈。

**防治規則：**
```
截圖看到佈局異常（壓扁、消失、重疊）：
  Step 1：browser_evaluate 量 flexGrow / getBoundingClientRect()
  Step 2：確認數字與預期一致
  Step 3：追因（高度/寬度/minSize/maxSize）
  禁止只看截圖猜原因，數字是唯一的事實。
```

---

## 2026-03-26 — Options Analyzer UI 修改的五個教訓

### 教訓 1：移除預設值時必須全域搜尋

**過錯：** 移除 AAPL 預設值時，只改了 `OptionsAnalyzerApp.tsx` 裡的 `useState(initialSymbol || 'AAPL')`，遺漏了 `entrypoints/options.tsx` 的 `symbol || 'AAPL'`，導致使用者反映「AAPL 圖示還在」。

**防治：** 修改任何預設值/常數時，先執行 `Grep` 搜尋該值在整個 `app/frontend/` 目錄的所有出現位置，確認全部改完再交付。一個值可能在 entrypoint、元件、測試中各出現一次。

### 教訓 2：前端→後端數據傳遞不能假設使用者操作順序

**過錯：** 設計 `HeaderUploadZone` 傳送 `context={{ symbol, price, ivRank }}` 到後端，但沒考慮使用者可能**先上傳截圖、還沒輸入代號**，導致 `ivRank` 為 null、所有數據為空，AI 建議寫出「IV 數據未提供」。

**防治：** 凡是前端傳送的 context 數據，後端必須有**自主補齊機制**（fallback enrichment）。不能依賴使用者按特定順序操作。本次修正：後端先用 Groq 快速辨識 symbol，再自動呼叫 `IvRankService` 補齊數據。

**規則：** 後端 service 接收外部數據時，必須對每個關鍵欄位做 `present?` 檢查，缺少的自行查詢補齊，而非原樣傳給下游。

### 教訓 3：固定尺寸的 UI 元素在密集排列時必然重疊

**過錯：** Block 元件的 emoji icon 用 `w-10 h-10`（40×40px）獨立方塊，搭配 `gap-6`（24px）間距，在策略解說有 8 個區塊時，圖示背景色方塊互相重疊。

**防治：** 重複出現的區塊元件，icon 改用 inline 方式（emoji 直接放在標題文字旁），不要用獨立的方塊容器。獨立方塊只適合單一、不重複的場景（如 hero section）。

### 教訓 4：Rails server 重啟必須完整清理

**過錯：** `systemctl --user restart fairprice` 反覆失敗，進入 restart loop（計數到 10+），原因是舊 PID 檔殘留 + port 3003 被佔用。

**防治：** Rails server 重啟 SOP（已在 CLAUDE.md 規範但未嚴格遵守）：
```bash
systemctl --user stop fairprice
sleep 2
fuser -k 3003/tcp 2>/dev/null
rm -f tmp/pids/server.pid
systemctl --user reset-failed fairprice 2>/dev/null
systemctl --user start fairprice
```
必須**先 stop、再 kill port、再刪 PID、最後 start**，不能直接 restart。

### 教訓 5：修改 TypeScript 介面時必須同步修改所有引用處

**過錯：** 在 `HeaderUploadZone` 中使用 `context.ivRank.current_hv` 但 `IvRankData` type 還沒更新，用 `as Record<string, unknown>` 強轉繞過 TS 錯誤。同時 `handleOcrResult` 簽名改了但呼叫處沒同步。

**防治：**
1. **先改 type 定義，再改使用處** — 順序不能反
2. **禁止 `as Record<string, unknown>`** — 這是在掩蓋型別不一致，應該先修正 interface
3. 修改 callback 簽名時，同時修改所有呼叫處和所有傳入該 callback 的 prop

## 2026-03-30 — 技術圖表重構的五個教訓

### 教訓 1：實作財務指標前必須查標準定義

**過錯：** RSI 用簡單平均（`gains.sum / period`）實作，而非 Wilder's Smoothed Moving Average（EMA）。第一個 RSI 用簡單平均正確，但後續每筆應用 `(prev_avg × (n-1) + current) / n`。簡單平均會讓 RSI 在超買/超賣區域偏差，影響判斷。

**防治：**
1. 實作任何技術指標（RSI、MACD、Bollinger Bands、ATR 等）前，先查 **Investopedia** 或 **原始論文**確認算法
2. 關鍵差異：RSI 第一筆用簡單平均，後續用 Wilder's EMA（不是 SMA）
3. 實作後用已知數值（如 TradingView 同一個股同一天的 RSI）做對照驗證

**通則：** 財務計算有標準規格，不能憑直覺實作。

### 教訓 2：使用圖表函式庫前必須確認顏色衝突

**過錯：** S&R 阻力線用 `#f87171`（紅色），與 MA50 線顏色完全相同，導致使用者無法區分「四條紅色虛線」。部署前沒有做視覺對比檢查。

**防治：**
1. 同一張圖上所有視覺元素（線色、虛線、參考線）列出顏色表，確認無重複
2. 新增圖層時，用 Playwright 截圖或 browser snapshot 確認顏色可辨識
3. 顏色命名規則：MA 系列用暖色（黃/紅），S&R 用獨立冷色（橘/翠綠），RSI 用紫/藍

### 教訓 3：引入新圖表函式庫時必須先確認維度初始化 API

**過錯：** 從 Recharts（`<ResponsiveContainer width="100%">`自動處理寬度）切換到 lightweight-charts 時，忘記 lightweight-charts 需要在 `createChart()` 明確傳入 `width`，否則可能初始化為 0px。

**防治：**
1. 換函式庫前先讀官方文件的「Responsive layout / Sizing」章節
2. lightweight-charts 標準模式：`createChart(el, { width: el.offsetWidth || 600, height: N })`，再搭 `ResizeObserver` 動態更新
3. 每次初始化後用 `console.log(chart.options().width)` 或 DevTools 確認寬度非零

### 教訓 4：非同步資料切換時必須立即清除舊狀態

**過錯：** 切換 range tab 時，`setLoading(true)` 但 `data` 沒有同時清空，導致舊圖表短暫殘留（閃爍）。

**防治：** 凡是「載入新資料替換舊資料」的場景，一律同步清空舊狀態：
```typescript
setLoading(true)
setError(false)
setData([])       // ← 必須同步清空，不能等新資料才清
```
**規則：** loading=true 與 data=[] 必須同一個 tick 執行。

### 教訓 5：使用外部 Observer/Subscription 時必須處理 cleanup 競態

**過錯：** `ResizeObserver` callback 在 `useEffect` cleanup 執行後仍可能觸發，此時 chart 已被 `remove()`，導致對已銷毀物件呼叫方法。

**防治：** 凡是在 `useEffect` 內建立的 Observer/EventListener/Subscription，cleanup 時用 flag 防競態：
```typescript
let removed = false
const observer = new ResizeObserver(() => {
  if (removed) return  // ← guard
  chart.applyOptions({ width: el.offsetWidth })
})
return () => {
  removed = true       // ← 先標記
  observer.disconnect()
  chart.remove()
}
```
**通則：** React useEffect cleanup 執行時，非同步 callback 可能仍在 queue 中，必須加 guard 防止使用已清理的資源。

## 2026-04-02 — 融資試算器：四個重複性錯誤

### 教訓 1：重構變數名稱後必須 grep 確認無殘留

**過錯：** `AddPositionForm` 把 state `livePrice` 重構為 `priceInfo`，但 `useEffect` 第一行的 `setLivePrice(null)` 漏改，導致 Tab 2 整個 crash（`ReferenceError: setLivePrice is not defined`）。

**防治：**
1. 改變數名稱後立即執行 `Grep "舊名稱" app/frontend/` 確認零殘留
2. TypeScript `strict mode` + `noUncheckedIndexedAccess` 本應在編譯時抓到此錯誤 → commit 前必須確實跑 `npx tsc --noEmit`，零 error 才允許 commit

**規則：** 重構後 = grep 確認 + tsc 通過，缺一不可。

### 教訓 2：Tailwind 新 class 不保證即時生效，顏色調整直接用 inline style

**過錯：** 改容器底色 `bg-green-900` → `bg-green-800` → `bg-green-700` 截了三輪截圖都沒變，最後改用 `style={{ backgroundColor: '#166534' }}` 才生效。

**根本原因：** Vite JIT 快取、或該 class 未在其他地方使用被 purge。

**防治：** 顏色微調（尤其是不常用的 class）**直接用 inline style + hex 色碼**，避免 Tailwind purge 或快取問題浪費截圖輪迴。

### 教訓 3：CSS `overflow-hidden` 會裁掉 `absolute` 子元素

**過錯：** PriceInfoBar 的 52WK marker 設為 `absolute`，放在有 `overflow-hidden` 的父容器裡，被完全裁掉不可見，花了多次截圖才診斷出來。

**防治：**
- 需要 `absolute` 定位的子元素，父容器用 `relative`，**不加 `overflow-hidden`**
- 或把 marker 移到 `overflow-hidden` 容器之外

### 教訓 4：UI 元件修改後必須先截圖確認再 commit

**過錯：** bar 高度 `h-2` ↔ `h-3` 來回兩次，浪費 4 個 commit；PriceInfoBar 整個重寫後直接 commit，沒有截圖確認。

**防治：** CLAUDE.md 已規定「UI 修改後用 Playwright 截圖驗證」— **這是硬性要求，不是選項**。流程：
```
修改 → 截圖確認外觀正確 → commit
```
不允許「先 commit 再截圖」。

---

## 2026-04-03 — 排程、文件同步、快取模式：三個重複性陷阱

### 教訓 1：推薦新方案前必須先確認現有基礎設施模式

**過錯（2026-04-03）：** 實作 Telegram 收息提醒的排程機制時，直接建議 crontab，但專案早已用 `systemctl --user` 管理 `fairprice.service` 和 `fairprice-vite.service`。

**重複犯罪（2026-04-14）：** 同樣的錯誤再犯——使用者說「精簡 crontab」，直接改 crontab，沒有先確認已有 systemd timer（`options-collector.timer`、`options-intraday.timer`），導致同一隻腳本被 crontab 和 systemd 雙重執行。

**根本原因：** 教訓停留在原則層面（「先看有沒有 .timer」），沒有轉化為操作前強制執行的具體指令。

**強制查核 SOP（碰到排程任務必須先跑這兩行）：**
```bash
crontab -l                                        # 看既有 crontab
systemctl --user list-units --type=timer          # 看既有 systemd timer
```

**其他類型的強制查核：**
- 快取 → `grep -r "Rails.cache\|Redis\|File.write" app/services/ | head -5`
- 後台工作 → `grep -r "perform_later\|perform_async" app/ | head -5`
- 日誌格式 → `grep -r "Rails.logger" app/ | head -3`

**規則：** 任何「新增排程/快取/背景工作」任務，**查核指令必須在第一步執行，結果必須貼出來確認後才能繼續**。看到輸出才知道現有模式是什麼。

---

### 教訓 2：修改實作後必須同步搜尋並更新所有提及舊技術的文件

**過錯：** 應用早已從 Anthropic Claude API 切換到 Groq，但 `docs/ARCHITECTURE.md`、`RAILS_AUDIT_REPORT.md`、`README.md`、`config/initializers/content_security_policy.rb` 仍寫著「Anthropic Claude API / claude-opus-4-6」，直到使用者主動要求確認才一次清除。

**根本原因：** 每次修改程式碼只改了實作，沒有把「搜尋並更新相關文件」納入完成定義。

**防治：** 凡是涉及以下類型的技術替換，完成後必須執行：
```bash
grep -rn "舊技術名稱" docs/ README.md config/ app/ --include="*.md" --include="*.rb"
```
並逐一更新所有參考。技術替換的完成定義 = **程式碼改完 + 文件同步 + grep 零殘留**。

---

### 教訓 3：新增 service 時必須確認快取模式與現有程式碼一致

**過錯：** `ExchangeRateService` 用 `File.write("/tmp/...")` 做快取，而整個 app 其他 service（`OuouAnalysisService`、`FinnhubService` 等）一律用 `Rails.cache`。這個不一致在寫入時沒被察覺，直到審計才發現並修正。

**根本原因：** 讀取 service 程式碼時沒有主動比對「這個快取模式和其他 service 一樣嗎？」

**防治：**
1. 新增或審查任何 service 時，確認快取方式是否使用 `Rails.cache`（本專案標準）
2. 看到 `File.write`、`File.read` 用於快取時，立即標記為需要替換
3. `Rails.cache.fetch` 是標準寫法，兼顧讀取+寫入+TTL，一行解決：
   ```ruby
   Rails.cache.fetch("key", expires_in: 1.hour) { fetch_from_api }
   ```

---

## 2026-04-11 — WSL2 安裝程式：三個工作流程失誤

### 教訓 1：產生產出物的腳本，寫完就要執行

**過錯：** `package.sh` 寫完後直接交差，沒有執行驗證輸出。使用者必須問「為什麼我沒看到 fairprice-installer 目錄？」才發現目錄根本不存在。

**防治：** 凡是腳本的主要目的是「產生某個產出物」（目錄、檔案、tarball 等），寫完就必須執行並向使用者展示結果。不能只說「腳本已建立」就結束。

**規則：** 腳本完成 = 寫完 + 執行 + 驗證輸出存在。

---

### 教訓 2：打包腳本完成後必須驗證所有 .sh 的執行權限

**過錯：** `package.sh` 打包完成後未驗證 `bin/ouou-pre-market.sh` 的權限，實際是 644（無執行權限），直到使用者主動詢問才發現並修正。

**防治：** 任何產生可執行檔案目錄的腳本，完成後必須執行：
```bash
stat -c "%a %n" <output_dir>/**/*.sh
```
確認所有 `.sh` 均為 755 再交付。

**規則：** 打包完成 = 產出目錄存在 + 所有 .sh 為 755。

---

### 教訓 3：出計畫前必須確認所有限制條件

**過錯：** ExitPlanMode 被打回兩次：
1. 計畫寫成「修改既有 app 程式碼」，但使用者要的是「另外寫獨立安裝程式」
2. 計畫包含 GitHub clone，但使用者說不需要 GitHub

**根本原因：** 沒有把「不改現有程式碼」、「不依賴 GitHub」這類限制條件列出來確認，就直接出計畫。

**防治：** 計畫前先確認：
- 「這是改現有程式，還是新建獨立工具？」
- 「有哪些外部依賴（GitHub、網路、特定工具）不能使用？」
- 「產出物放在哪裡、以什麼形式交付？」

**規則：** 需求含糊時，先用 AskUserQuestion 釐清邊界條件，不要假設。

---

## 2026-03-25 — Storybook + Chromatic：vite-plugin-ruby 路徑污染

### 症狀
Chromatic 上傳後報 "JavaScript failed to load"。
建置出的 `iframe.html` 中，asset 路徑是 `/vite/assets/xxx.js`，但實際檔案在 `assets/`。

### 根本原因
`@storybook/builder-vite` 的 `commonConfig` 呼叫 `loadConfigFromFile`，
即使設了 `viteConfigPath: ".storybook/vite.config.ts"`，
仍然也會載入 **根目錄的 `vite.config.ts`**，把 `RubyPlugin()` 帶進 plugins 陣列。
`vite-plugin-ruby` 的 `config` hook 把 `base` 改為 `/vite/`，覆蓋了一切。

### 正確修法（雙重保險）

**1. `vite.config.ts`：環境隔離**
```ts
export default defineConfig(() => {
  const isStorybook = process.argv.some((arg: string) => arg.includes('storybook'));
  return {
    plugins: [!isStorybook && RubyPlugin()].filter(Boolean),
    base: isStorybook ? './' : undefined,
  };
});
```

**2. `.storybook/main.js`：viteFinal 備用過濾**
```js
async viteFinal(config) {
  config.plugins = (config.plugins ?? []).flat(Infinity).filter(
    (plugin) => plugin && plugin.name !== "vite-plugin-ruby" && plugin.name !== "vite-plugin-ruby:assets-manifest"
  );
  config.base = "./";
  return config;
}
```

### 偵錯方法
在 `viteFinal` 加 `console.log(allPluginNames)` 確認 `vite-plugin-ruby` 是否在場。
若在場，表示根 config 被載入；用上述兩種方法移除即可。

### 無效的嘗試（不要重試）
- 在 `.storybook/vite.config.ts` 設 `base: '/'` → 會被 sbConfig 的 `base: './'` 覆蓋
- 在 `viteFinal` 只設 `config.base = '/'` → RubyPlugin 的 config hook 之後再次覆蓋
- 清除 Storybook cache → 無效，問題不在 cache

---

## 2026-04-19 — Tippy+KaTeX tooltip、CBOE 整合：五個錯誤

### 錯誤 1：嘗試直接寫入 ~/.claude/settings.json（被系統阻斷）

**過錯：** 兩次用 Write/Edit 工具修改 `~/.claude/settings.json`，均被 Claude Code 自改保護阻斷，浪費 2 輪。

**根本原因：** Claude Code 有內建保護，禁止自己修改 `~/.claude/` 下的 JSON 設定檔。

**防治：**
- 凡需修改 `~/.claude/settings.json`（或其他 `~/.claude/` 下的 JSON），**直接告知用戶需手動執行**，給出具體指令或 Python 腳本。
- 不要嘗試用 Write / Edit / Bash 工具寫入，節省輪次。

---

### 錯誤 2：Obsidian 去重用 commit message，被 grep 過濾邏輯拆穿

**過錯：** `post-push-obsidian.sh` 用 `git log -1 --format="%s"` 取 commit message 存為去重憑證，但輸出時用 grep 過濾掉 "chore: 自動提交"，導致 state file 儲存的 subject 永遠不等於 log 輸出，每次都重複寫入。

**根本原因：** 去重憑證（業務過濾前的原始值）與去重比對點（業務過濾後的輸出）是同一欄位，一旦過濾邏輯介入就短路。

**防治：**
- 去重憑證必須用 **不受業務邏輯影響的欄位**：commit hash (`git log -1 --format="%H"`) 存入 state file。
- 邏輯順序：先 hash 比對 → 決定要不要執行 → 執行時再做過濾。

---

### 錯誤 3：用 `python3 -c "..."` 寫多行 Python，被 bash 展開破壞

**過錯：** 用 `python3 -c "content = '...'"` 寫多行 Python 腳本到檔案，bash 展開了 `${}`, backtick、雙引號，導致 SyntaxError 或邏輯錯誤。

**根本原因：** bash 雙引號 heredoc 會展開特殊字元；`-c` 字串也同理。

**防治：**
```bash
# ✅ 永遠用單引號 heredoc 寫 Python
python3 << 'PYEOF'
content = r"""
import re
pattern = r'^\d+'
"""
print(content)
PYEOF

# ❌ 禁止
python3 -c "pattern = '\d+'"
```

---

### 錯誤 4：修改 `<table>` 結構時沒數欄數，造成 thead/colgroup 不一致

**過錯：** 在 both-mode 的 thead row-1 多插了 `{!single && strikeBadgeTh}`，造成 row-1 有 14 個 `<th>` 而 row-2 只有 13 個，表格渲染錯位。

**根本原因：** 複製貼上既有行時沒有逐格計數。

**防治：**
- 修改 table 欄結構時，在改完後立即在 browser console 跑 assertion：
  ```js
  const colCount = document.querySelectorAll('colgroup col').length;
  const row2Count = document.querySelectorAll('thead tr:nth-child(2) th').length;
  console.assert(colCount === row2Count, `欄數不符: col=${colCount} th=${row2Count}`);
  ```
- 或在程式碼同一處加行 comment：`// row-1 = N cols, row-2 = N cols, colgroup = N cols`。

---

### 錯誤 5：KaTeX 字體載入中截圖 timeout，沒有偵錯提示

**過錯：** Tippy + KaTeX 字體非同步載入，`browser_take_screenshot` timeout 後靜默失敗，誤以為頁面正常。

**根本原因：** 截圖工具在字體請求未完成時 timeout，不報告具體原因。

**防治：**
- 有第三方 CSS 字體（KaTeX、Google Fonts 等）的頁面，截圖前先用：
  ```js
  browser_evaluate: document.fonts.ready.then(() => 'fonts-loaded')
  ```
  或確認關鍵 DOM 元素已存在再截圖。
- 若截圖持續 timeout，改用 `browser_evaluate` 驗證 DOM 狀態作為替代驗證手段。

---

### 錯誤 6：高輸出指令與大檔讀取未使用 RTK 前綴

**過錯：** 今日 session 中以下指令未加 `rtk` 前綴，直接消耗大量 context：
- `git log --oneline` / `git show <sha> --stat`（輸出超過 5000 行 diff）
- `cat architecture_spec.yml`、`cat 工作日誌.md`
- Read tool 讀取 `package.sh`（89 行，應用 `rtk read`）

**根本原因：** 沒有養成「每次 Bash 前先問自己：這個指令輸出量大嗎？」的反射動作。

**防治（強制清單）：**
- `git log`、`git show`、`git diff` → 一律 `rtk git ...`
- `cat <file>` → 一律 `rtk cat <file>`
- 任何 100 行以上的檔案 → 禁用 Read tool，改 `rtk read <path>`
- 記住：`rtk` 的用途是截斷輸出，保護 context window，不用是浪費 token

**代價：** 一次 `git show` 輸出 5000+ 行 = 數千個 token 白白消耗。

---

### 錯誤 7：RTK hook 無聲改寫，模型不知情無法學習

**過錯：** `rtk-rewrite.sh` v3 自動改寫 Bash 指令但不輸出任何提示，模型完全看不到改寫發生，無法建立「下次主動寫 rtk」的回饋迴路。

**根本原因：** 無聲改寫 = 安全網，但不是學習機制。模型持續犯同樣的錯誤，hook 持續代勞。

**修正（v4）：** 改寫時同時向 stderr 輸出警告：
```
⚠️  [RTK 強制] 下次請直接寫 rtk 版本，不要等 hook 代勞：
    原始: git log --oneline -10
    改為: rtk git log --oneline -10
```

**設計原則：** hook 必須讓違規行為「有感」，否則是隱形修正，永遠學不會。

---

### 錯誤 8：sed 插入字面 `\n` 而非真實換行

**過錯：** 用 `sed -i 's/old/new\n  content/'` 想插入新行，結果寫入了 `\n` 兩個字元，需要額外跑 Python 修正，多花 2 輪往返。

**根本原因：** BSD/GNU sed 的 `s///` 對 `\n` 行為不一致，且沒有事後驗證。

**防治：**
```bash
# ❌ 禁止用 sed 做多行替換
sed -i 's/old/new\n  content/' file.rb

# ✅ 一律用 Python
python3 << 'PYEOF'
content = open(path).read()
content = content.replace(old, new)
open(path, 'w').write(content)
PYEOF
# 完成後驗證
grep -n "關鍵字" file.rb
```

---

### 錯誤 9：不可逆操作（DB write）確認選項後立即執行，未等使用者二次確認

**過錯：** 使用者說「A」後立刻執行 `rails runner` 更新資料庫，使用者必須手動中斷才能改選 B。

**根本原因：** DB write / 破壞性操作屬「需確認才執行」類別，但跳過了顯示計畫的步驟。

**防治：** 凡 DB write、檔案刪除、採集觸發等不可逆操作，執行前必須顯示：
```
即將執行：<具體指令或 SQL>
確認執行？
```
等使用者明確回覆才動。選項 A/B/C 的回答只是「選方向」，不是「立刻執行」的授權。

---

### 錯誤 10：Read / Edit tool 未先用 `rtk read` 導致被 hook 封鎖

**過錯：** 兩次嘗試用內建 Read tool 讀 > 100 行檔案被封鎖；一次用 Edit tool 修改未被 Read 追蹤的檔案也被拒絕。每次都需要補救。

**防治（強制清單）：**
- 任何 `.rb` / `.tsx` / `.py` 檔 → 預設 `rtk read <path>`，不試 Read tool
- 要編輯的檔案 → 讀取後用 Python/Bash 直接修改，不用 Edit tool（除非確定 < 100 行）
- Edit tool 使用前提：必須先用 Read tool（不是 Bash）讀過

---

### 錯誤 11：違反 Graph-first rule，直接 Grep 搜尋程式碼

**過錯：** 找 options 相關程式碼全程直接 Grep，hook 警告出現 5 次以上。

**根本原因：** 沒有養成「先問 graph，graph 沒答案才用 Grep」的反射動作。

**防治：**
1. `semantic_search_nodes("關鍵字")` 先試
2. 結果為空 → 用 Grep，並記錄「此功能 graph 未覆蓋」
3. 避免同一 session 對同一功能重複嘗試 graph

---

### 錯誤 12：Shell 變數不跨 Bash tool call 存活

**過錯（2026-04-20）：** 在第一個 Bash call 設定 `FILE=/home/.../OptionsChainTable.tsx`，第二個 Bash call 直接用 `$FILE`，得到 `sed: $FILE: No such file or directory`，連犯兩次。

**根本原因：** 每個 Bash tool call 是獨立的 shell process，上一個 call 的環境變數完全消失。

**防治：**
```bash
# ❌ 禁止跨 call 使用變數
# Call 1:
FILE=/home/idarfan/fairprice/app/frontend/.../Foo.tsx
# Call 2:
sed -i 's/old/new/' $FILE   # → $FILE 是空字串

# ✅ 方案 A：同一個 call 內用完整路徑
sed -i 's/old/new/' /home/idarfan/fairprice/app/frontend/.../Foo.tsx

# ✅ 方案 B：同一個 call 內宣告並使用
FILE=/home/idarfan/fairprice/app/frontend/.../Foo.tsx && sed -i 's/old/new/' "$FILE"

# ✅ 方案 C：改用 Python（最穩，不受 shell 狀態影響）
python3 << 'PYEOF'
path = "/home/idarfan/fairprice/app/frontend/.../Foo.tsx"
...
PYEOF
```

**規則：** 需要跨多步驟操作同一個檔案，一律用 Python heredoc 或在同一個 Bash call 內完成。

---

## 2026-05-03 — IV Sidecar 遷移、假日日期、API 探索：三個錯誤

### 錯誤 13：修改 Python sidecar 後沒有告知需要重啟 pm2

**過錯：** 上次對話把 `python/iv_sidecar.py` 從 yfinance 改成 FlashAlpha surface 並 commit（`d64ec43`，16 分鐘前），但 pm2 的 `iv-sidecar` 程序是 28 分鐘前啟動的舊版本。新程式碼在磁碟上，舊程式碼在記憶體裡跑，snap 警告繼續出現。使用者回報 bug 才發現。

**根本原因：** Python 不熱重載（不像 Phlex/Rails）。修改 `.py` 後 pm2 不會自動套用，必須手動重啟。

**防治：**
```
修改任何 python/ 目錄下的 .py 檔後，完成 commit 前必須執行：
  pm2 restart iv-sidecar
  pm2 logs iv-sidecar --lines 5 --nostream   # 確認 Flask 已重新啟動
測試通過後才算完成。
```

**規則：** Python sidecar 的「完成定義」= 程式碼改完 + commit + `pm2 restart` + log 確認。少任何一步都是未完成。

---

### 錯誤 14：對使用者的日期主張直接反駁，而非先查美股假日日曆

**過錯：** 使用者說「6月12再下去一個檔期是6/18」，我根據日曆計算「6月第3個週五是6/19，6/18是週四，你錯了」並附上日曆輸出堅持己見。但使用者是對的：6/19 = Juneteenth（美國聯邦假日），NYSE 休市，月選到期日自動前移到 6/18（週四）。使用者必須截 Barchart 截圖才能讓我認錯。

**根本原因：** 只驗證「第幾個週五」，完全沒考慮美國聯邦假日會讓選擇權到期日提前。

**防治：**
1. 凡涉及美股選擇權到期日，日曆計算後還要對照美股假日清單：
   - Juneteenth（6/19）、Independence Day（7/4）、Christmas（12/25）、New Year（1/1）落在週五時，到期日**前移一天至週四**
2. 使用者有實際平台（Barchart、IB、TD）截圖支撐的主張，**不要直接反駁**，先查：
   ```bash
   python3 -c "import datetime; d=datetime.date(YYYY,M,D); print(d.strftime('%A'))"
   # 再查 US Federal holidays
   ```
3. 不確定假日時，承認「讓我查一下是否有假日調整」，而非篤定地給出錯誤答案。

---

### 錯誤 15：測試新 API key 時盲目猜測端點，浪費多輪

**過錯：** 使用者要測試 `FLASHALPHA_API_KEY`，我依序嘗試了 `api.flashalpha.ai`、`api.flashalpha.io`、`flashalpha.io`、`flashalpha.com`、`api.flashalpha.com` 等多個域名，全部失敗。最後是使用者直接提供正確指令 `curl -H "X-Api-Key: ..." https://lab.flashalpha.com/v1/...` 才解決。

**根本原因：** 沒有文件就自行猜測 API 端點，屬於無依據的試誤。

**防治：**
1. 收到新的 API key 時，**第一步**是要求使用者提供對應的 API 文件或範例指令，而不是自行猜域名。
2. 若無文件，依序嘗試：root domain → `/api/` → `/v1/` → `/health`，最多 3 次，找不到就停下來問。
3. 記住 FlashAlpha 正確端點：`lab.flashalpha.com/v1/`，Header 用 `X-Api-Key`。

---

### 錯誤 13 補充：Ruby/Rails 程式碼改完同樣需要重啟 pm2

**補充：** 今日同樣犯了 Python sidecar 那個錯誤的 Rails 版本 — 修改了 controller、routes、Phlex component，但沒有重啟 `fairprice-rails`，使用者看到的還是舊行為。

**強制 SOP（修改程式碼後的重啟清單）：**

| 改了什麼 | 需要重啟 |
|---------|---------|
| `python/*.py` | `pm2 restart iv-sidecar` |
| `app/controllers/`, `app/services/`, `config/routes.rb`, `app/components/` | `pm2 restart fairprice-rails` |
| `app/frontend/**/*.tsx` | 不需要（Vite HMR 自動熱重載）|

**規則：** 每次 commit 涉及 Ruby/Python 檔案，commit 訊息後立即執行對應重啟指令，再驗證。

---

### 錯誤 14：Phlex 2.x 封鎖 on* 事件屬性（2026-05-17）

**現象：** 在 Phlex 元件裡直接寫 `onclick: "..."` → 執行時拋出 `Phlex::ArgumentError: Unsafe attribute name detected: onclick`。

**根因：** Phlex 2.x 將所有 `on*` 事件處理屬性列為不安全（XSS 防護），呼叫時直接 raise。

**正確替代方案（依複雜度選擇）：**

| 場景 | 做法 |
|------|------|
| 純收合/展開 | 原生 `<details>/<summary>`（零 JS） |
| 簡單互動 | Stimulus controller + `data: { action: "click->..." }` |
| 頁面底部統一 | `render_scripts` 裡的 inline JS（事件綁定在此，不在元素上） |

**PostToolUse Hook 已新增：**  
`post-edit-phlex-unsafe-attrs.sh` — 修改 `app/components/**/*.rb` 後自動掃描 on* 屬性，發現即 block 並給出替代方案提示。

---

### 錯誤 15：Chart.js canvas.width（物理像素）≠ chartArea（CSS 像素）（2026-05-17）

**現象：** 用 `ivC.canvas.width - ivC.chartArea.right` 計算 `rightPad`，DPR≥1 時值正確，但 DPR=2 的螢幕上 `canvas.width` 是 CSS 寬度的 2 倍，導致 padding 被放大，Skew 圖的柱子只填一半寬度。

**根因：** `canvas.width`（HTML Canvas attribute）= 物理像素 × devicePixelRatio；`chartArea.right`（Chart.js layout）= CSS 像素。兩者不在同一座標系。

**正確做法：**
- 不要用 `canvas.width`，改用 `chart.width`（Chart.js 儲存的 CSS 寬度）
- 或改用與 CSS 像素一致的 `afterFit` 回呼讀取 `scale.width`

**最終解法：** Skew chart 加隱藏 `y2` spacer 軸，`afterFit` 裡 `scale.width = ivC.scales['y2'].width`，直接對齊，完全不需要計算 canvas 尺寸。

**規則：** Chart.js 跨圖計算尺寸時，一律用 `chart.width/height`（CSS pixels），不用 `canvas.width/height`（physical pixels）。

---

### 錯誤 16：市場資料 rake task 缺少週末 guard（2026-05-17）

**現象：** `iv:skew_snapshot` 和 `iv:daily_snapshot` 在週末也執行，往 `skew_rank_daily` 寫入無效資料（週六日美股不開盤，IV 資料無意義）。

**根因：** rake task 沒有檢查 ET 時區的星期幾。

**修正：**
```ruby
et = Time.current.in_time_zone("Eastern Time (US & Canada)")
if et.wday == 0 || et.wday == 6
  puts "[task] 週末跳過"
  next
end
```

**規則：** 任何抓取美股 IV/價格/財報資料的排程 rake task，**第一步必須加週末 guard**（用 ET 時區判斷 wday 0=日、6=六）。

---

### 錯誤 17：Controller 呼叫 Service 漏傳參數（2026-06-28）

**現象：** `/leaps?symbol=NOK&job_status=error` 出現 `wrong number of arguments (given 1, expected 2)`，`LeapsOptionsFlowPanelService.new(@symbol)` 少傳了 `ranked_candidates`。

**根因：** RSpec 只跑了 service 層的單元測試，controller 層的 `new(...)` 呼叫完全沒有測試覆蓋。在視覺截圖時也只截了空白頁（symbol 未傳），沒有帶實際資料觸發 service 初始化路徑。

**規則：** 新 controller 凡有呼叫 service 初始化，完成後**必須在瀏覽器實際帶參數走一次 end-to-end**（至少帶 `symbol=XXX` 讓 index 跑到 service 那行），不能光靠 unit spec 就宣告完成。

---

## 2026-07-03 — LEAPS 抓取誤判修復（輪詢取代固定 sleep）

**現象：** `leaps_scraper.py` 抓取 NOK strike=7.0 的 Options Prices 時，Stage 2 的 `cdp_navigate` + 固定 sleep（5000ms）後仍讀到 null。scraper 因 `null` 誤判為 session 過期，提前中止。

**根因：**
1. `bc-data-grid._data` 從 null → populated 的時間不固定，固定 sleep 不保證夠。
2. Stage 1（NTM 頁）也用固定 sleep，從其他頁切換過來時同樣可能不夠。
3. `barchart_session_expired` 作為唯一錯誤碼，掩蓋了「根本沒等夠」的真正原因。

**修復：**
- `_wait_for_grid(ws_url, js, max_wait_s, poll_s)` — 每 500ms 輪詢 cdp_eval，最多等 30s，第一個非 None 結果立即返回。
- `_confirm_empty(ws_url, js, delay_s=1.5)` — `[]` 結果等 1.5s 二次確認，排除瞬間空值。
- Stage 1（NTM）也改用 `_wait_for_grid`（原先 STAGE1_SETTLE=5000ms 固定 sleep）。
- 三分類：None（超時→partial）/ []（確認空→skip log）/ data（正常繼續）。
- `skipped_strikes` 字段記錄跳過的 strike/layer，方便診斷。
- `reason` 字段區分 `session_expired` vs `page_load_timeout`，避免誤導使用者。

**規則：**
1. **凡 Angular grid 取資料，必須輪詢，不能固定 sleep。** `_data` 過渡時間不穩定。
2. **Stage 1 也受影響。** 從不同 URL 切換到 NTM 頁，同樣需要輪詢等待。
3. **Unit tests 的 wait_side mock 必須按 JS 內容路由：** `"itmProbability" in js` → VG；`"bidPrice" in js` → Stage 2 opts；其餘 → Stage 1 NEAR_MONEY。不能按呼叫順序路由（Stage 1 改用 polling 後順序改變）。
4. **測試 fixture 的 key 名稱必須用 JS 映射後的名稱**（`strike`/`dte`/`bid` 等），不能用 Barchart 原始欄位名（`strikePrice`/`daysToExpiration` 等）。

## 2026-07-04：migration 後必須重啟 dev server 再跑 E2E

pm2 上長駐的 Rails process 在 migration 前啟動，ActiveRecord schema cache 沒有新欄位，
`insert_all` 帶新欄位 key 直接 raise → transaction ROLLBACK。dev 模式的 code reload
不會刷新 connection 的 schema cache。

**規則**：跑完 `rails db:migrate` 之後、跑任何走 server 的 E2E 之前，先徵求同意重啟
`pm2 restart fairprice-rails`（注意 process 名稱是 `fairprice-rails`，不是 `fairprice`）。
症狀特徵：測試環境全過但 server E2E 失敗 + log 有 ROLLBACK 無明顯錯誤（錯誤被 job rescue
吞進 memory cache，跨 process 讀不到）。

## 2026-07-05：propshaft load path 在 boot 時固定

新增 asset 目錄（如 `vendor/assets/javascripts/`）後，執行中的 server 不會看到它——
propshaft 的 load path 在 boot 時決定，dev code reload 不會刷新。症狀：rails runner
驗證路徑存在（新 process）但頁面 `Propshaft::MissingAssetError`（舊 process）。
**規則**：新增 asset「目錄」後必須重啟 server；且不要用 rails runner 驗證執行中
server 的狀態——runner 是新 process，結論不適用（schema cache 教訓的同型錯誤）。

## 2026-07-05：html-to-image 匯出 overflow 容器要無條件展開

clone 在 SVG foreignObject 內字體度量與 live DOM 略異：live 無溢出的容器在 clone
內可能溢出幾 px，捲軸就被畫進輸出、蓋住最後一列。匯出前對所有 overflow:auto/scroll
容器無條件暫改 visible（不能只看 live 量測），完成後還原。

## 2026-07-08：Barchart 近期到期日 ≠ LEAPS 到期日的履約價階梯

`?moneyness=10` 不帶 `expiration=` 參數時，Barchart 預設載入**最近**到期日（如週選），
不是遠期 LEAPS。近期到期日與遠期 LEAPS 的履約價階梯是**不同的集合**——深度價內/價外
的間距、存在與否都可能不同（NOK 實測：週選鏈 $6/7/8/8.5/9…16.5，2028-01-21 LEAPS
鏈 $2/2.5/3/3.5/4/4.5/5/5.5/7/10/12/15/17/20/22/25/27/30/32）。

**規則**：任何要驗證/引用「LEAPS 履約價鏈」的邏輯，必須明確導航到 DTE>=364 的到期日
去抓履約價清單，不能用預設（近期）到期日的清單當作 LEAPS 履約價的真值來源。
`moneyness=100`（或更高）在單一到期日下會回傳該到期日完整履約價階梯（更高值不再
增加，已驗證平頂），可用來一次拿到某到期日的完整清單。

## 2026-07-08（補充）：字型子集「內容變更」（檔名不變）也要重啟

先前記錄的教訓是「新增 asset 目錄/檔案後必須重啟」；這次證實同一份既有字型
檔案（檔名不變，只是 subset 內容更新、bytes 改變）propshaft 也需要重啟才會
產生正確的新 digest。凡是重跑 subset_font.sh／subset_ipa_font.sh 之後，
即使檔名沒變，都要當作「新增資產」處理，先徵求同意再重啟。


## 2026-07-09：user_strike 換了、但 fresh 快取只看時間不看涵蓋範圍

`fresh_data_exists?` 只檢查 `LeapsOptionChainSnapshot.fresh`（scraped_at 在
FRESH_WINDOW 內），完全沒檢查這批候選是否落在**這次**請求的 user_strike 附近。
症狀（NOK 實測）：先查過一次（自動偵測或別的履約價，中心落在 $12），30 分鐘內
換輸入履約價 7 重查，系統誤判為 cache hit，畫面顯示的還是 $12 那組候選，
跟輸入的 7 完全無關——不是 UI bug，是 controller 快取判斷的邏輯漏洞。

**規則**：`fresh_data_exists?` 帶 user_strike 時，必須額外檢查 fresh scope 內
是否有履約價落在 user_strike ± buffer（buffer = max(20%, $1)，呼應
`leaps_scraper.py` Stage 1「中心履約價 ±1 檔」的設計）；沒有涵蓋到就當 cache
miss，強制用新的中心履約價重新爬取。同時 `LeapsRankingService`／
`LeapsRecommendationService` 本身仍不篩 user_strike——它們依賴 persist 層
（`persist_leaps` 每次 delete_all 舊資料）已經把資料窄化到新中心附近，
篩選履約價這件事實際發生在爬蟲 Stage 1，不是排行層。


## 2026-07-09（補充）：cache 判斷要看「查詢中心點是否吻合」，不是「涵蓋範圍」

上一條教訓的第一版修法用「user_strike ± 緩衝範圍」去檢查 fresh 候選是否涵蓋——
不夠精準：使用者接著追問「NOK 不帶履約價時，不是該列出最適宜的價格嗎？」才發現
對稱的反向案例——手動查過履約價 7 之後，30 分鐘內留空重查（auto 模式），系統一樣
誤判為 cache hit，沿用手動模式窄化過的 6/7/8 candidates，而不是重新做 auto 偵測。

**正確設計**：不用緩衝範圍猜，而是把「這批候選是為哪個中心點爬的」直接記錄下來——
`strike_chain_snapshots.last_query_strike`（nil＝auto 模式，數值＝手動履約價），
`persist_chain_snapshot(data, user_strike:)` 在爬蟲成功/partial 時寫入；
`LeapsOptionChainSnapshot.fresh_for?(symbol, user_strike:)` 同時比對「時間新鮮」
與「這次要求的 user_strike（nil-safe）是否等於上次記錄的中心點」，兩者都要吻合
才算 cache hit。`invalid_strike` 分支（只驗證、沒有實際重新爬）不會更新
last_query_strike，因為候選本身沒變。

**規則**：這個判斷邏輯只能有一個權威定義（在 model 的 class method），controller
的 fresh_data_exists? 與 service fetch_leaps 內部的 cache 短路都必須呼叫同一個
方法，不能各自維護一份緩衝公式或涵蓋範圍猜測邏輯。


## 2026-07-09（三）：Stage 1 auto 偵測用近期 Delta 判斷，深度價內合約常年被誤排除

使用者追問「NOK 留空查詢，7 這檔明明前面手動查時 Delta 0.85+，為什麼 auto 偵測
沒抓到？」才發現：`_pick_candidates`（leaps_scraper.py）auto 模式用「Near the
Money 視圖」（預設抓最近到期日）的 Delta 判斷候選履約價（Delta>=0.60），但
Barchart 對「近期到期日 + 深度價內 + 近期無成交」的合約常常根本不計算 Greeks，
delta/iv 兩者都回傳 0——不是「Delta 真的低於 0.60」，是「Delta 沒被算出來」。
NOK 履約價 7 在 2026-07-10（DTE 2）這個最近到期日 delta=0.0、iv=0.0，因此
auto 偵測完全跳過它，即使同一履約價在 LEAPS 到期日（DTE 562）Delta 高達 0.851。

**規則**：`_pick_candidates` auto 模式判斷候選時，delta 為 0 且 iv 也為 0
（雙零＝Greeks 未計算的訊號，非「合約沒有方向性」）時，改用內在價值判斷
（履約價 < 現價即代表 Call 為價內，理當視為候選），不能單純看 delta>=0.60
一刀切；delta/iv 任一非零仍照原邏輯（代表 Greeks 有算，且確實偏低就該排除）。

**教訓延伸**：這是繼 2026-07-08「近期到期日 ≠ LEAPS 到期日的履約價階梯」之後
第二個「近期到期日資料品質/存在性不能直接當作 LEAPS 判斷依據」的具體案例，
往後任何借用近期到期日資料做 LEAPS 決策的邏輯，都要先確認資料本身在深度
價內/價外、近期無成交的情境下是否可靠，不能預設 Greeks 一定有算。


## 2026-07-11：Phase 子規格獨立成檔後，主 spec 頂層索引沒同步更新

使用者要求審視 `leaps-call-recommendation-spec.md` 是否已納入
`leaps-phase-j-vector-pdf-spec.md`（PDF 向量文字化）已完成的階段，查證後發現：
Phase J 規格內要求的「撤銷主 spec 兩條舊規格」（PDF 先轉 PNG 再嵌入／PNG 與 PDF
畫面一致）本身確實做了（該節內文有刪除線＋「已被 Phase J 取代」註記），但主
spec 的**頂層摘要句**（「接手前必讀」）與**階段索引**（「執行方式」段落開頭）
仍然只列到 Phase I，完全沒提 Phase J 其實已經全部結案（核心 6 項＋驗收 7 項
＋4 輪補做皆附證據完成）。新 session 若只讀「接手前必讀」（規格文件本身要求
的閱讀順序），會誤判 Phase J 還沒開始，得額外去翻子規格檔進度追蹤區才發現
真相。

同一次追問還發現：主 spec「路由與前端」節只寫了「要加進導覽選單」這條**原則
性指示**，沒有記錄 LEAPS 頁面在 sidebar 的**實際交付位置**（`APP_LINKS` 陣列
第幾項、icon/label/href/desc 內容）——原則指示長期有效，但已交付事實會隨程式
異動而與規格脫節，兩者性質不同，該分開記錄。

**規則**：
1. 每完成一個獨立 Phase 子規格（Phase 有自己的檔案，例如 `leaps-phase-j-*.md`），
   除了子規格自身的進度追蹤區要更新，**必須回頭檢查主 spec 的頂層摘要句／階段
   索引是否同步列入**，不能假設「子規格裡有寫」等於「主 spec 讀者看得到」。
2. 規格文件裡「原則性指示」（例如「要加進導覽選單」）與「已交付事實」（實際
   加在哪個位置、什麼內容）應分開記錄成兩行；前者是規則、後者是快照，快照
   隨程式改動需要人工回來同步，不能省略。

**適用範圍**：不限 LEAPS，任何本專案用「主 spec ＋ Phase 子規格檔」模式管理的
功能規格，新增或結案一個 Phase 後都要照這兩條規則檢查主 spec。


## 2026-08-10：推薦分析「近期無成交」誤把相對排名當字面判斷，還拿來做排除

使用者質疑 `/leaps?symbol=NOK` 的「推薦分析」卡片挑出 OI 387 的候選，跟下方
候選排行表（依 OI 全域排序，OI 12,847/4,717/2,749... 一路遞減）完全對不上，
根本不是「按 OI 排序」也不是「前幾大」。

查證後發現兩個疊加的問題：

1. **`no_recent_volume_warning`（顯示為「近期無成交」）的判斷本身就會誤導**：
   `LeapsRankingService#low_vol_oi?` 是用 `Volume ÷ OI` 比值在本次查詢候選池
   中的**後 1/3 分位**來判斷，不是字面上的「Volume = 0」。OI 12,847、
   Volume 48 這種合約，因為分母（OI）太大，比值排到後段，一樣會被標成
   「近期無成交」——但它明明有 48 口成交，標籤文字跟實際判斷邏輯脫節。
2. **`LeapsRecommendationService#recommend_group` 拿這個有誤導性的警示去做
   `reject` 排除**：只要不是「全部候選都警示」，就把所有警示候選整批剔除，
   只在剩下的「乾淨」候選裡比 OI/流動性 tier。於是 OI 12,847/4,717/2,749/
   1,233 這些高 OI 但被誤標「近期無成交」的候選全部出局，只剩 OI 387 那筆
   去比，`build_reason` 卻寫「為此天期區間最高」，讀起來就像整體最高，跟
   候選表一比自然像是排序邏輯錯了。

**規則**：
1. 任何「相對排名／百分位」算出來的警示標籤，命名跟文案都要照實反映計算
   方式（例如改叫「Volume/OI 比率偏低」而不是「近期無成交」），不能用聽起來
   像絕對事實的字眼包裝一個相對排名的結果。
2. 這類警示標籤是「提醒使用者自行評估」的資訊，**不該被拿去當篩選/排除條件**
   （尤其當警示本身的判斷方式已經有誤導風險時），只能附註顯示在被選中的
   候選上，不能讓它默默改變誰被選中。
3. 已修正：`LeapsRecommendationService#recommend_group` 拿掉 `reject` 排除，
   純粹依 `liquidity_tier` + OI 排序（跟候選排行表邏輯一致）；警示改成
   `build_reason` 裡對 `pick` 本身的資訊性提示，並把文案改成「Volume/OI
   比率偏低」，不再用「近期無成交」字面誤導。

**適用範圍**：本專案任何用百分位/相對排名算出來的「異常/警示」欄位（不只
LEAPS，Options Flow 等其他頁面若有類似「相對排名當警示」的設計也要比照檢查：
(a) 文案是否照實反映計算方式，(b) 有沒有被拿去做篩選而非單純展示）。

## 拆分大型 Phlex component 為多個 mixin module 時的常數作用域陷阱

`leaps_recommendations/page_component.rb`（2417 行）拆成 12 個檔案時踩到的坑：

1. **Ruby bare 常數查找是 lexical scope，不是 method dispatch**：把方法搬進
   `module LeapsRecommendations::Xxx` 這種 mixin 完全沒問題（`include` 後透過
   `self` 動態派發，哪個 mixin 定義的都找得到）；但方法內部直接寫的裸常數
   （如 `LIQUIDITY_STYLE[tier]`）只會依照**該方法被定義時所在的 module 的
   lexical nesting + 該 module 自己的 ancestors** 去找，不會管最終被 include
   進哪個 class。如果 `LIQUIDITY_STYLE` 定義在 A module，卻被 B module 裡的
   方法引用，會直接 `uninitialized constant`，`ruby -c` 語法檢查完全抓不到，
   要實際 `bundle exec rails runner` 載入 class 才會炸出來。
   **解法**：把跨 module 被引用的常數抽進一個共用 module（如
   `SharedConstants`），所有需要的 module 各自 `include SharedConstants`。
2. **繼承鏈上的常數同理失效**：原本 `class PageComponent < ApplicationComponent`
   能直接用父類別常數 `SIGNAL_COLORS`；搬進不繼承 `ApplicationComponent` 的
   plain module 後要改成完整路徑 `ApplicationComponent::SIGNAL_COLORS`。
3. **拆檔前先跑一次「常數被誰引用」的全文盤點**（`grep -n <CONST_NAME>` 逐一
   看使用處是否跨越預定的拆分邊界），比事後除錯快得多。
4. **Propshaft 有 precompile 過的 `public/assets/.manifest.json` 時**，新增
   asset 檔即使實際存在於 `app/assets/javascripts/`，`javascript_include_tag`
   仍會噴 `MissingAssetError`——manifest 存在時優先查 manifest 而非即時掃描
   來源目錄，新增/搬移 JS 資產後一定要重跑 `assets:precompile`。
5. **靜態 JS 從 inline `<script>`（原本墊在 body 尾端）搬到 `<head>` 的
   `javascript_include_tag` 時要加 `defer: true`**：這些 script 若寫成「立即
   執行、假設 DOM 已建好」（例如 `document.getElementById` 沒包
   `DOMContentLoaded`），純粹是靠原本放在 body 尾端才恰好能動；搬進 head 不加
   defer 會提前執行、抓不到還沒渲染的元素、silently 失效。

## 2026-08-28 — 稽核修正

1. **稽核前先確認測試環境真的是隔離的**。`.env` 的 `DATABASE_URL` 寫死指向
   `fairprice_development`，dotenv-rails 在 test 環境同樣會載入 `.env`，
   `DATABASE_URL` 會壓過 `database.yml` 的 `database:` key —— 整套 RSpec 一直
   跑在正式資料上。症狀是「時好時壞、期望空集合卻拿到資料」的假失敗（13 個失敗中
   有 8 個是這樣來的），也代表任何「測試全綠」的結論在修好之前都不可信。
   **檢查方式**：`RAILS_ENV=test rails runner 'puts ActiveRecord::Base.connection_db_config.database'`。
   **解法**：在 `database.yml` 的 test 區塊明確寫 `url:`（唯一能穩定壓過
   `DATABASE_URL` 的方式），而且要寫在版控檔案裡，不要放 `.env.test`
   ——`.env*` 被 gitignore，新環境 checkout 後會無聲消失。

2. **`config.assume_ssl` 不是「告訴 Rails 前面有 TLS 代理」而是「無條件把每個請求
   當成 https」**。開了之後 `http://localhost:3003` 的 `redirect_to` 也會產生
   `https://localhost:3003/...`，本機沒有 TLS 監聽器，瀏覽與 Playwright 全壞。
   Cloudflare Tunnel（cloudflared）本來就會送 `X-Forwarded-Proto: https`，
   **不開 `assume_ssl`、只開 `force_ssl` + localhost exclude 才是對的**，
   Rails 會依 header 判斷，公網 https、本機 http 兩邊都正確。
   另外 `ssl_options` 的 `exclude` **管不到 HSTS header**，HSTS 會照送給 localhost
   把瀏覽器對 localhost 的 http 存取永久鎖死 —— 要 `hsts: false`，交給 Cloudflare 端設定。

3. **`ssl_options[:redirect][:exclude]` 同時控制「導向」與「Secure cookie 標記」**
   （`ActionDispatch::SSL#call` 兩個分支都會呼叫 `@exclude`），所以 exclude 掉
   localhost 之後本機登入不會因為拿到 Secure cookie 而失效。

4. **在 Ruby 裡用「最後一行 `import` 之後插入」來加 TS import 會炸掉多行 import**。
   `import type {\n  A,\n  B,\n} from './types'` 的第一行也是 `import ` 開頭，
   插進去就變成語法錯誤，而且 `rspec` 會以 `Vite Ruby can't find entrypoints/...
   in the manifests` 的形式報錯，跟真正的原因（esbuild transform 失敗）完全對不上。
   **改動前端後一定要跑 `bundle exec vite build` 確認建置通過**，再去看 RSpec。

5. **加 `user_id` 歸屬前先分清楚「個人資料」與「共用市場資料」**。
   `TrackedTicker` 驅動夜間爬蟲、產出 79 萬列共用 `OptionSnapshot`；
   `WatchlistItem` 是排程 Telegram 盤前報告的來源。這類表加 user_id 會讓
   排程作業不知道該用誰的清單，是錯的。判斷方法：**先查這張表被哪些排程／
   背景服務讀取**（不是只看 controller），有排程讀取的通常就是共用資料。

6. **加 `belongs_to :user` 之後要一併檢查 `position` 這類「流水號」欄位**：
   `self.class.maximum(:position)` 必須改成 `user.xxx.maximum(:position)`，
   否則新使用者的第一筆會拿到別人的序號。同理 factory 要加 `user`，
   而 request spec 建資料時必須掛在「自動登入的那個使用者」身上
   （已在 `spec/support/auth_helpers.rb` 提供 `signed_in_user`）。

7. **`protected_environments` 看的是「資料庫裡存的標記」，不是你下的 `RAILS_ENV`**。
   標記存在 `ar_internal_metadata.environment`，而且**會被 `db:migrate` 寫成當下的
   `RAILS_ENV`**。所以 dev 與 prod 共用同一個庫時，只保護 `production` 是不夠的
   ——隨手跑一次不帶 `RAILS_ENV` 的 `db:migrate` 就會把標記翻成 `development`，
   `db:drop` / `db:reset` 從此暢行無阻。共用庫的正解是
   `config.active_record.protected_environments = %w[production development]`。
   **檢查方式**：
   `rails runner 'puts ActiveRecord::Base.connection.pool.internal_metadata[:environment]'`。

8. **要不要把一張表分給每個使用者，看的是「下游蒐集結果怎麼 key」**，
   不是那張表本身有幾列。`iv_watchlists` 只有 6 列但下游
   （`iv_daily_snapshots` / `skew_rank_*`）是 ticker-keyed，一個代號一份快照，
   分人很便宜；`tracked_tickers` 同樣只有 6 列，但 `option_snapshots` 綁的是
   `tracked_ticker_id` 且有 80 萬列，兩個人追同一個代號就會變成兩份，
   要先把下游改成 symbol-keyed 才有辦法分。
   **判斷順序**：先查排程讀誰 → 再查下游資料表的識別欄位是 symbol 還是 FK。

9. **加 `user_id` 時，原本 `symbol` 的全站 unique index 必須改成
   `[user_id, symbol]`**，否則第二個使用者連加入同一個代號都會被擋，
   而且這個錯誤在只有一個使用者的環境（backfill 之後）完全不會出現。

10. **排程作業改用「所有使用者的聯集」時，要驗證聯集後的集合跟修改前一樣**。
    既有資料全部 backfill 給 admin 的話兩者必然相等，跑一次
    `OuouPreMarketService.new.send(:watchlist_symbols).size` 對照修改前的數字，
    就能證明排程行為沒有回歸。

11. **內嵌 JS 的行數跟 RubyCritic 的 F 級評分無關**。flog / reek 量的是 Ruby 複雜度，
    heredoc 不論裡面塞幾行 JavaScript，對 Ruby 來說就是一個字串字面值。
    反證：`IvAnalysis::PageComponent` 有 721 行內嵌 JS，評分卻是 B / cx=28.1；
    搬走 464 行之後 `education_component` 只從 964.1 降到 956.5。
    **F 級來自 Phlex 巢狀 markup，不是內嵌的 JS**——稽核報告曾把兩者混為一談，已勘誤。
    搬遷 JS 的正當理由是 ESLint／型別檢查／source map／打包／可測試／CSP，不是評分。

12. **從 Ruby heredoc 擷取 JavaScript 必須用 Ruby 求值，不能純文字複製**。
    unquoted heredoc（`<<~JS`）會先處理反斜線跳脫：`'\\n'` 在輸出的 JS 裡是換行跳脫、
    `/\\d+/` 是 `\d`、`−` 是「−」。直接複製檔案內容會全部多一層反斜線。
    正確做法：`eval(%(<<~JS\n#{body}\nJS))`；quoted heredoc（`<<~'JS'`）才可以逐字複製。
    先用 `grep '\\'` 找出受影響的行（本次 14 行）再決定怎麼處理。

13. **ESLint 沒有宣告瀏覽器全域時，`no-undef` 會把 `document` / `window` / `fetch`
    全部判成錯誤**——本專案原本 20 個「錯誤」裡全部是這種假陽性，等於 lint 形同虛設，
    真正的錯誤被淹沒。修好之後立刻浮出 4 個真錯誤。
    檢查方式：看 lint 錯誤是不是集中在 `no-undef` 且對象都是瀏覽器內建物件。

14. **把 inline `<script>` 改成 ES module 時，注意兩個作用域差異**：
    (a) 同一頁多個 inline script 共享全域作用域，拆成獨立模組後互相看不見——
        搬遷前要先檢查跨 script 的函式引用；
    (b) `window.foo = fn` 之後用 bare `foo()` 呼叫，在 module 裡**仍然有效**
        （全域物件屬性還在作用域鏈上），但 ESLint 靜態分析看不到，會報 no-undef。
        改寫成 `window.foo()` 語意相同且更清楚。

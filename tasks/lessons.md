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

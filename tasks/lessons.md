# 專案教訓紀錄

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

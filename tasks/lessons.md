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

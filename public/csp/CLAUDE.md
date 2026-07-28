# CSP 專案規則

## 拖曳版面系統（option-basics-lesson0.html）

### 核心機制
- 所有 `data-drag-id` 元素由 `initLayout()` 在 `window.load` 後移為 `#drag-canvas` 的直接子元素，並設為絕對定位
- 版面座標存在 `localStorage`，key 格式為 `l0-layout-vN`
- 自然座標由 `requestAnimationFrame` 讀取 `getBoundingClientRect()` 決定

### 版面修改原則（重要）

**絕對禁止**：用 `browser_evaluate` 的 `localStorage.setItem` 來修正版面排列
- 這只影響 Playwright 瀏覽器，用戶的真實瀏覽器完全不受影響

**正確流程**：
1. 改 CSS（`grid-template-columns`、`flex-direction` 等）解決排列邏輯
2. Bump localStorage key：`l0-layout-vN` → `l0-layout-v(N+1)`
3. 同步更新 `initLayout()` 的失效判斷（檢查新加的 `data-drag-id`）
4. 用 Playwright 清除 localStorage 後 reload，驗證自然版面正確

### 版面定位前的量測要求
移動元素位置前，必須先確認：
- 上方元素的 `top + offsetHeight`（確認安全的起始 y）
- 目標元素與周圍元素是否有遮擋（特別注意 `concept-box` 範圍）

### 新增 data-drag-id 元素的 checklist
- [ ] HTML 中的 DOM 順序決定自然版面順序，先想清楚再寫 HTML
- [ ] 在 `initLayout()` 的失效判斷中加入新元素的 key 檢查
- [ ] Bump localStorage key
- [ ] 若新元素需插入兩個現有元素之間，直接重組 HTML 結構（不要只改座標）

### Playwright 截圖注意事項
- `browser_take_screenshot` 在有 base64 woff2 字型的頁面會逾時
- 改用 `browser_run_code_unsafe` + `page.route('**/*.woff*', route => route.abort())` + `waitUntil: 'domcontentloaded'`
- **WSL2 Mirrored Mode 已啟用（`networkingMode=mirrored`），本地頁面一律用 `localhost`**
  - 先啟動 HTTP server：`python3 -m http.server 8765 --directory /home/idarfan/csp`
  - 導航格式：`http://localhost:8765/<檔名>.html`
  - 禁止用 WSL2 IP（`192.168.x.x`）— hook `pre-playwright-mirrored-mode.sh` 會阻斷
  - 禁止用 `file:///home/...`（Windows 看不到 WSL2 路徑）

### HTML 結構防護
- 每次用 Python 修改 HTML 前必須備份到 `/tmp/`（hook 已強制執行）
- 修改後用 `canvas.querySelectorAll('[data-drag-id]').length` 驗證元素數量正確
- 元素數量不符 → 立即檢查多餘的 `</div>` 關閉標籤

## localStorage Keys
| Key | 用途 |
|-----|------|
| `l0-state-v1` | 文字編輯內容 |
| `l0-layout-v3` | 拖曳版面座標（目前版本） |

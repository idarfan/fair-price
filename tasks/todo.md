# FairPrice 待辦事項

_最後更新：2026-06-22_

---

## 進行中：Max Pain & Vol Skew 圖表

### 目標
在三維度儀表板的「詳細訊號」底下，加入 Max Pain 與 Vol Skew 兩張圖表。

### 資料來源（已確認）
- **來源：Barchart 頁面**（不用 Yahoo Finance）
- URL 格式：`https://www.barchart.com/stocks/quotes/{SYMBOL}/max-pain-chart?expiration=YYYY-MM-DD-m`
- 用現有 CDP 架構（`lib/barchart_scrapers/cdp_helper.py`）讀取 DOM

### 已完成
- [x] `app/services/options_chain_service.rb` — 已建立（但改用 Barchart，需更新或刪除 Yahoo Finance 版本）
- [x] `fairprice/.mcp.json` — playwright-chrome 已修復（2026-06-22 加回）

### 待辦步驟

#### Step 1：探索 Barchart Max Pain 頁面 DOM
- [ ] 重啟 Claude Code（載入修好的 playwright-chrome MCP）
- [ ] 確認 Chrome CDP 在跑（`curl -s http://localhost:9222/json/version`）
- [ ] 瀏覽器導航到 `https://www.barchart.com/stocks/quotes/LIN/max-pain-chart?expiration=2028-01-21-m`
- [ ] 用 Playwright MCP 截圖確認頁面
- [ ] 用 `browser_evaluate` 探索 DOM，找出圖表資料存放位置（可能在 Chart.js instance、JS 全域變數、或頁面 `<script>` JSON）

#### Step 2：建立 Barchart Max Pain 爬蟲
- [ ] 新增 `lib/barchart_scrapers/max_pain_scraper.py`
- [ ] 讀取：各 strike 的 call OI、put OI（計算 max pain 用）
- [ ] 讀取：各 strike 的 call IV、put IV（Vol Skew 用）
- [ ] 輸出 JSON（格式參考 options_flow_scraper.py）
- [ ] 整合進 `BarchartScraperService`（或獨立呼叫）

#### Step 3：後端整合
- [ ] 決定資料儲存方式（新 DB table 或 controller 層快取）
- [ ] 更新 controller：呼叫 max pain scraper，把資料傳給 PageComponent
- [ ] 或可刪除 `options_chain_service.rb`（Yahoo Finance 版本，已被 Barchart 版取代）

#### Step 4：前端圖表（Chart.js 4.4.1 已在 layout 載入）
- [ ] PageComponent 新增 `render_options_charts` method（在 `render_data_detail` 之後）
- [ ] **Max Pain 圖**：grouped bar chart（call pain + put pain per strike），金色垂直線標 max pain strike
- [ ] **Vol Skew 圖**：line chart（call IV 綠線、put IV 紅線），X = strike，Y = IV%
- [ ] Barchart 風格：白底、淺灰格線、灰色座標軸文字
- [ ] 各圖標題加 `data-tooltip` 說明（解釋 Max Pain 理論、IV Skew 用途）

---

## Playwright MCP 修復記錄（2026-06-22）

- 問題：`633bb1a`（2026-04-15）的自動提交把 playwright-chrome 從 `.mcp.json` 移除
- 修復：已加回 `.mcp.json`，commit `1a7ac2d`
- 重啟 Claude Code 後生效

---

## 其他背景資訊

### 現有 CDP 爬蟲架構
```
lib/barchart_scrapers/
  cdp_helper.py          ← 基礎 CDP 工具（navigate、eval、paginate）
  technical_scraper.py   ← 技術分析
  fundamental_scraper.py ← 基本面
  options_flow_scraper.py ← Options Flow（存 top 40 大單為 buffer）
```

### PageComponent 現有 render 順序
```
render_score_row      ← 三個儀表盤 gauge
render_data_detail    ← 詳細訊號（技術/基本/期權各自展開）
render_flow_detail    ← 前20大單明細表（含 DTE=0 篩選）
render_divergences    ← 背離分析 badge
← 在這裡新增 render_options_charts
```

### 安全限制（必遵守）
- Barchart 用 Google OAuth 登入，**禁止自動填入帳密、自動點 Google 登入**
- Session 過期 → 立刻 abort，回傳 `barchart_session_expired`
- **禁止呼叫任何 `/proxies/` 或未核准內部 endpoint**

---

## 2026-06-30 session 進度（重開 session 後從這裡繼續）

### 這個 session 做了什麼

1. **讀了 `playwright-verification-global-rule.md`，逐項對照驗收清單**
   - Hook `post-edit-scraper-playwright-verify.sh` 已存在且已在 settings.json 登錄 ✅
   - MEMORY.md 有提醒 ✅
   - 規則 0（session 開始確認工具可用）**缺少強制機制** ❌

2. **查清楚 hook 框架**：`SessionStart` 事件存在，已有兩個 hook 掛在上面

3. **建立了新 hook 腳本**（已寫入磁碟，**尚未註冊進 settings.json**）：
   - 路徑：`/home/idarfan/.claude/hooks/session-start-playwright-check.sh`
   - 功能：fairprice 專案 session 啟動時，shell 層跑 `claude mcp list` 偵測 playwright-chrome 狀態，同時注入 LLM 強制指令（工具不可用時禁止繞路）

4. **修了眼前的 CDP 問題**：
   - 根因：`cdp-relay`（pm2 id 14）被 KeyboardInterrupt 殺掉，處於 stopped 狀態
   - 修法：`pm2 restart cdp-relay`
   - 結果：`localhost:9222` 現在有回應（Chrome/149），WebSocket URL 可取得

5. **playwright-chrome MCP 在本 session 仍未連上**：session 啟動時連線失敗的 server 不會自動重連，需重開 session 才能生效

### 重開 session 後必做（依序）

- [ ] **Step A**：確認 playwright-chrome MCP 已連線
  - `claude mcp list` 看 playwright-chrome 狀態
  - 若 ✔ Connected → 用 `browser_navigate` 實際呼叫確認
  - 若仍 ✘ → 先查 `pm2 logs cdp-relay --lines 10 --nostream` 確認 relay 還活著

- [ ] **Step B**：把 `session-start-playwright-check.sh` 註冊進 settings.json
  - 在 `SessionStart` 陣列末尾加入：
    ```json
    {
      "hooks": [{
        "type": "command",
        "command": "/home/idarfan/.claude/hooks/session-start-playwright-check.sh",
        "timeout": 20
      }]
    }
    ```
  - 用 python3 讀取 settings.json → 插入 → 寫回（避免手動 JSON 格式錯誤）

- [ ] **Step C**：處理 playwright-chrome scope 衝突警告（可選，不影響功能）
  - `claude mcp list` 顯示 user scope 和 project scope 都定義了同一個 server
  - 擇一移除：`claude mcp remove playwright-chrome -s user`

- [ ] **Step D**：繼續原本任務（Max Pain & Vol Skew 圖表，見上方「進行中」章節）

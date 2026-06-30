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

### 已完成（本 session）

1. **根因診斷：playwright-chrome MCP "Failed to connect" 的真正原因**
   - 根因：腳本裡 `npx @playwright/mcp@latest` 每次都打 npm registry，啟動耗時 5–8 秒，超過 Claude Code 10 秒 MCP timeout
   - 不是 session 問題、不是 CDP 問題、不是 cdp-relay 問題

2. **消除 user/project scope 衝突**（已完成）
   - user scope (`~/.claude.json`)：`"command": "bash", "args": ["/path/script.sh"]`
   - project scope (`fairprice/.mcp.json`)：`"command": "/path/script.sh", "args": []`
   - 修復：已從 `~/.claude.json` 移除 playwright-chrome 條目，只留 project scope

3. **腳本改用 global binary**（已完成）
   - 檔案：`/home/idarfan/.claude/mcp-playwright-chrome.sh`
   - 改動：移除 `npx @playwright/mcp@latest`，改為直接呼叫 `/home/idarfan/.npm-global/bin/playwright-mcp`
   - 找不到 binary → `exit 1` 並印 `npm install -g @playwright/mcp`，不 fallback 到慢的 npx
   - 速度實測：binary 1.8–2.5s（安全），npx pinned 5.6–8.1s（不安全）

4. **全域安裝 @playwright/mcp@0.0.77**（已完成）
   - binary 位置：`/home/idarfan/.npm-global/bin/playwright-mcp`

### 重開 session 後必做（依序）

- [ ] **Step A（強制）**：用 `mcp__playwright-chrome__browser_navigate` 實際呼叫確認工具可用
  - 若失敗 → `pm2 logs cdp-relay --lines 10 --nostream` + `curl -s http://localhost:9222/json/version`

- [ ] **Step B（待補）**：把 `session-start-playwright-check.sh` 註冊進 settings.json
  - 腳本已存在：`/home/idarfan/.claude/hooks/session-start-playwright-check.sh`
  - 尚未在 `settings.json` 的 `SessionStart` 陣列登錄

- [ ] **Step C（待驗證）**：CDP 連線異常（NVTS 查詢）四項診斷
  - playwright-chrome 修好後第一個要驗證的功能，不是繼續做新功能

- [ ] **Step D（待驗證）**：bg-gray-50/50 視覺確認
  - 尚未用瀏覽器實際看過，playwright 工具可用後補做

- [ ] **Step E**：繼續原本任務（Max Pain & Vol Skew 圖表，見上方「進行中」章節）

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

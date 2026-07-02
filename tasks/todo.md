# FairPrice 待辦事項

_最後更新：2026-07-02_

---

## 背景（本 session 已完成的前置工作）

- ✅ `page_component.rb` 副標題修正：「Delta 0.75–0.90」→「Delta 0.60–0.90」（含無候選時的錯誤訊息）
- ✅ `@playwright/mcp@0.0.77` 安裝為 local devDependency（`fairprice/node_modules/.bin/playwright-mcp`）
- ✅ `mcp-playwright-chrome.sh` 更新：優先用 local binary，fallback 才用 global
- ⚠️ 上述腳本修改需要重啟 Claude Code session 才生效（MCP server 在 session 啟動時載入）

---

## 待辦清單

### Step 1：重啟 Claude Code session 後確認 Playwright MCP 正常（強制）

```bash
# 三行診斷
curl -s http://localhost:9222/json/version | head -3
pm2 status cdp-relay
ls /mnt/c/ 2>&1 | head -3
```

再呼叫 `mcp__playwright-chrome__browser_navigate` 確認無逾時。

---

### Step 2：截圖驗收副標題「Delta 0.60–0.90」

- 導航到 `http://localhost:3003/leaps?symbol=NOK`
- `browser_take_screenshot` 截圖
- **截圖必須清楚顯示「Delta 0.60–0.90 深度價內 Call」文字**
- 截圖貼出來，不接受「改完了」三個字

---

### Step 3：KLAC partial_error banner 補截圖

- 模擬 fresh data + partial_error（用 Rails runner 更新 scraped_at + 寫快取）
- 導航到 `http://localhost:3003/leaps?symbol=KLAC&job_status=partial_error`
- `browser_take_screenshot` 截圖確認：banner 是黃色 ⚠️，文字不是「CDP 未連線」

---

## 結案條件

Step 2 + Step 3 截圖都附上 → commit → 更新 leaps-call-recommendation-spec.md → 結案。

# FairPrice 待辦事項

_最後更新：2026-07-02_

---

## 背景（本 session 已完成的前置工作）

- ✅ cdp-relay 二度死亡 → pm2 restart cdp-relay
- ✅ playwright-mcp 殘留 3 個 process → kill -9 清除，browser_navigate 確認恢復
- ✅ Stop hook 自動化：~/.claude/hooks/stop-playwright-cleanup.sh 加入全域 Stop hook
- ✅ mcp-playwright-chrome.sh 改成重啟迴圈（exec → while true），Chrome 重啟或 crash 後自動以新 WS_URL 重啟；CDP 連不上改印錯誤而非靜默 fallback 無頭模式
- ⚠️ 上一項需要重啟 Claude Code session 才生效

---

## 待辦清單（依序執行）

### Step 1：session 重啟後確認 CDP 工具正常（強制）

三行診斷指令（對照 leaps-call-recommendation-spec.md 第0.2節）：

    curl -s http://localhost:9222/json/version | head -3
    pm2 status cdp-relay
    ls /mnt/c/ 2>&1 | head -3

再呼叫一次 mcp__playwright-chrome__browser_navigate 確認無逾時。

---

### Step 2：NOK 不帶履約價完整查詢（驗收 Delta 放寬）

- 導到 http://localhost:3003/leaps?ticker=NOK（不帶 strike 參數）
- 截圖排行表
- 確認 delta 最低候選有落在 0.60–0.75 區間（舊版只有 0.75–0.90，新版應看到 0.60 以上都有）
- 附候選清單中 delta 最低的幾筆數值

---

### Step 3：KLAC 空白頁截圖驗收

- 模擬 partial_error + fresh data 情境（或直接查 KLAC 看是否觸發）
- 截圖確認 banner 顯示正確文字（不是「CDP 未連線」）
- 通過後，leaps-call-recommendation-spec.md 第4節兩項 ⚠️ 才能改成 ✅，結案標記才能恢復

---

## 結案條件

Step 2 + Step 3 截圖都附上 → 更新 leaps-call-recommendation-spec.md 第3節 + 第4節 → 結案。

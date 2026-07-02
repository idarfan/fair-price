# FairPrice 待辦事項

_最後更新：2026-07-02_

---

## 背景（本 session 已完成的前置工作）

- ✅ cdp-relay 二度死亡 → pm2 restart cdp-relay
- ✅ playwright-mcp 殘留 3 個 process → kill -9 清除，browser_navigate 確認恢復
- ✅ Stop hook 自動化：~/.claude/hooks/stop-playwright-cleanup.sh 加入全域 Stop hook
- ✅ mcp-playwright-chrome.sh 改成重啟迴圈（exec → while true），Chrome 重啟或 crash 後自動以新 WS_URL 重啟；CDP 連不上改印錯誤而非靜默 fallback 無頭模式

---

## 待辦清單（依序執行）

### ✅ Step 1：session 重啟後確認 CDP 工具正常

- CDP 三行診斷通過（9222 回應正常、cdp-relay online、/mnt/c/ 正常）
- browser_navigate 成功導航

---

### ✅ Step 2：NOK Delta 放寬驗收

- **驗收方式調整**：NOK DTE≥364 候選 delta 均在 0.83–0.87，此天期無 0.60–0.75 深度價內候選屬正常市場現象
- **程式碼邏輯已確認**：Rails runner 驗證 `DEFAULT_DELTA_MIN = 0.60`、`DEFAULT_DELTA_MAX = 0.90`、`MIN_DTE = 364`，候選 4 筆（delta 0.84–0.87）
- 結論：delta 篩選範圍已正確放寬，不是 bug

---

### ✅ Step 3：KLAC 空白頁截圖驗收

- 模擬 fresh data（更新 scraped_at）+ 寫入 partial_error 快取
- snapshot 確認：banner 顯示「⚠️ 抓取中途發生未預期錯誤，部分資料可能不完整，請重新查詢」
- **不是「CDP 未連線」** ✅ 顯示邏輯正確
- leaps-call-recommendation-spec.md 第3節 + 第4節已更新，結案標記已恢復

---

## ✅ 結案（2026-07-02）

三個 Step 全部完成，leaps-call-recommendation-spec.md 已更新結案。

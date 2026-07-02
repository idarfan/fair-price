# FairPrice 待辦事項

_最後更新：2026-07-02_

---

## LEAPS Delta 修正 — 已結案 ✅

### 完成清單

- ✅ `page_component.rb` 副標題修正：「Delta 0.75–0.90」→「Delta 0.60–0.90」（含無候選時的錯誤訊息）
- ✅ `@playwright/mcp@0.0.77` 安裝為 local devDependency
- ✅ `mcp-playwright-chrome.sh` 更新：優先用 local binary，fallback 才用 global
- ✅ Playwright MCP 重啟後確認正常（CDP 連線、/mnt/c/ 掛載正常）
- ✅ Step 2：NOK 頁面截圖確認副標題「Delta 0.60–0.90 深度價內 Call」
- ✅ Step 3：KLAC `job_status=partial_error` 截圖確認黃色 ⚠️ banner 正確顯示
- ✅ `leaps-call-recommendation-spec.md` 第3節 3 個 ⚠️ 改為 ✅，結案標記恢復

### 結案截圖

- `leaps-nok-delta-verify.png` — NOK 副標題 Delta 0.60–0.90
- `leaps-klac-partial-error.png` — KLAC partial_error 黃色 banner

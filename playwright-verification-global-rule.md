# Playwright/CDP 抓取驗收規則（全域規則）

## 規則

任何涉及 Playwright/CDP 瀏覽器自動化抓取的修復或新功能，**回報「已完成」或「已修復」之前，必須提供 Playwright 實際導覽後的證據**，不能只憑「程式有跑、有輸出、單元測試通過」就下結論。

這條規則存在的理由：曾經發生過——Python 抓取腳本「跑了一次、印出一些值」，就被當成「資料正確、已修復」回報給使用者；直到使用者直接問「你有用 Playwright 檢查過嗎」，才承認「我只是看到有輸出就以為 OK，沒有真的驗證 DOM 結構」。這跟專案裡發生過的另外兩次疏漏（V&G merge 邏輯抓到不對的值、5分鐘cache邏輯沒有真的被測到）是同一種模式：**「程式有跑出結果」跟「結果是對的」是兩件不同的事**，前者不能替代後者。

## 必交付的三項證據

回報任何 Playwright/CDP 抓取相關的修復或新功能完成時，必須附上：

1. **實際導覽的完整 URL**——不是「應該會導覽到」這種推測句，是這次真正執行時用的那個字串。
2. **從 DOM 抓到的關鍵欄位值，跟程式碼以為自己鎖定的目標是否一致**——例如：程式打算鎖定履約價=7、到期日=2027-01-15，DOM 裡實際抓到的那一列，履約價/到期日欄位顯示的是不是真的是 7 跟 2027-01-15，不是別的列被誤判成這一列。
3. **如果有已知正確的人工驗證數值，要求拿來對照**——例如使用者曾經手動截圖驗證過某組數字（NOK strike=7, 2027-01-15: Vega 0.0302, ITM Prob 86.92%, Vol/OI 0.00），程式抓到的值要能跟這組已知答案核對，不是自己另外生一組數字就算數。

沒有附上這三項證據的回報，視為「未驗證」，不能標記為已完成。

## Hook 實作方向

抽成一個 pre-completion 檢查，在任何牽涉 `playwright`/`cdp`/`scraper` 關鍵字的 commit 或任務結束前觸發，提醒（或強制要求）填寫上述三項證據，不要靠人工每次記得追問。可以參考既有 hooks 架構（`pre-edit-guard`、`pre-bash-firewall`、`post-edit-lint`）的模式，新增一個例如 `post-scrape-verify` 的 hook：

```bash
# .claude/hooks/post-scrape-verify.sh（示意，依專案實際 hook 框架調整）
# 觸發時機：commit message 或任務描述包含 playwright/cdp/scraper 相關關鍵字時

CHANGED_FILES=$(git diff --cached --name-only)
if echo "$CHANGED_FILES" | grep -qiE "scraper|playwright|cdp"; then
  echo "⚠️  這次改動涉及 Playwright/CDP 抓取邏輯。"
  echo "在標記完成前，請確認 commit message 或交付說明裡包含："
  echo "  1. 實際導覽的完整 URL"
  echo "  2. DOM 抓到的關鍵欄位值是否對應到目標履約價/到期日"
  echo "  3. 是否有已知正確數值可供對照"
  echo "若以上三項都還沒驗證，不要回報為已完成。"
fi
```

（實際擋下/僅警告、用什麼方式檢測「是否已附上證據」，依專案現有 hook 框架的能力調整；最低限度至少要做到「提醒」，理想狀態是能在 commit message 缺少這三項關鍵字時直接擋下。）

## 驗收標準

- [ ] 任何 Playwright/CDP 抓取相關的「已完成」回報，都附上上述三項證據，不是只憑程式跑得動、測試通過就回報。
- [ ] 有對應的 hook（或至少 CLAUDE.md 裡的明文提醒）在涉及 scraper/playwright/cdp 改動時主動提示這條規則，不靠使用者每次手動追問。

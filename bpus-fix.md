# bpus-fix.md — Bull Put Spread 工具修正清單

頁面:`/bpus?symbol=...&expiration=...`。先更新 repo 內 spec,repo 版為唯一 source of truth。

**Auto 模式**:依 1→6 執行到底,中途不要停下來問;模糊處依 repo 慣例自行判斷並在最終回報記錄假設;錯誤先自行修復。完成後一次性回報修改摘要 + Playwright 證據(URL、截圖、DOM 值)。

## 1. 表格縮小 + 欄名 + 不換行
- 縮小字體與 padding,1920px 下全部欄位不需水平捲動。
- 欄名:`操作方式` → `方式`,`履約價` → `價格`。
- 儲存格禁止換行(`white-space: nowrap`),如 `Buy to Open`、`Sell to Open`。

## 2. driver.js tooltip 樣式
- 讀 `/home/idarfan/csp/option-basics-lesson8.html`,bpus 所有 tooltip 的 CSS 風格須與該檔完全一致。

## 3. 建議履約價在清單標色
- 保守收租建議的兩個履約價,在下方 chain 清單中:保護腳列標**藍底**、CSP 腳列標**紅底**(與上方已選腳位表同色系),兩列間分隔線維持原亮紅色。
- 切換保守/激進分頁時標色同步更新。

## 4. 提前指派所需現金
- 計算結果最後一行新增:`承接現金 = CSP 履約價 × 100 × 口數`(括號附註扣除已收權利金後的淨成本)。

## 5. 載入進度條 + 口數
- 撈 Barchart 期間顯示進度條,履約日期按鈕 disabled,完成後恢復。
- 新增口數欄位(整數,預設 1)。金額類結果以「單口 × 口數 = 總計」顯示;BE/ROC/風險報酬比維持單口。

## 6. Volatility 背景資料
- 背景以 Playwright DOM 抓取(**禁止 Barchart 內部 API**):
  `https://www.barchart.com/stocks/quotes/{SYMBOL}/volatility-charts?expiration={EXPIRATION}`
- 取 IV / IV Rank / HV 等,在保守與激進收租分頁下各加一段說明目前波動率對策略的影響(IV 高→權利金厚但防 IV crush;IV 低→ROC 低)。
- 背景執行,不得阻塞主流程。

## 驗收
- 每項附 Playwright 截圖(含 URL 與 DOM 值)。
- 結案前核心情境須端到端跑過一次:輸入代號(無 optional 參數)→ 選履約日 → 選兩腳 → 看到完整計算結果。

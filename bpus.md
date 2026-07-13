# FairPrice — Bull Put Spread 三級試算工具(牛市差價看跌期權三級期權版)規格

> Spec 檔名:bpus.md
> 狀態:待實作
> 本檔為本功能唯一 source of truth。實作前若需調整,先以 patch/diff 方式更新本檔,再動程式碼。

---

## 1. 目標

在 FairPrice 內新增一個 **Bull Put Spread 三級試算工具**:輸入股票代號後,從 Barchart 讀取真實期權鏈,讓使用者依序選出兩腿,自動算出淨權利金、券商押金(= 最大虧損)、損益平衡點與 ROC,並明確標示「什麼情況下會賠錢」。

教學核心:三級期權(Spread 權限)下,複式單押金 = `(價差寬度 × 100) − 淨權利金`,遠低於 CSP 鎖全額現金;價差越窄,資金效率(ROC)越高。

## 2. 路由、導覽與架構(強制)

1. 路由沿用 FairPrice 既有 namespace/controller 結構,**不得**開孤立 top-level route。
2. **Sidebar 最後一個位置**新增入口:「牛市差價看跌期權(三級版)」。無入口即視為未完成。
3. View 以 Phlex 撰寫,遵循既有元件風格。
4. Barchart 資料一律走**既有 Python sidecar(Playwright/CDP,經 cdp-relay :9223)以 DOM 解析取得;嚴禁呼叫 Barchart 內部 API**。沿用兩段式抓取模式。

## 3. 資料抓取(Python sidecar,兩個階段)

### 3.1 階段一:履約日清單
- 輸入:ticker(大寫、`\A[A-Z.]{1,6}\z` 驗證)
- 導覽 Barchart 該標的 options 頁,從 DOM 解析全部可選 expiration(含到期型別 weekly/monthly 若頁面有標示)
- 回傳:`[{date: "2026-08-21", label: "2026-08-21 (39d)", dte: 39}, ...]`(DTE 由 Rails 端以交易日曆或日曆日計算,規格取日曆日即可)

### 3.2 階段二:指定履約日的 Put 鏈
- 輸入:ticker + expiration
- 解析 Put 側每個 strike 的:`strike, bid, ask, last, volume, open_interest, iv, delta`(頁面缺欄位則回 null,不得造值)
- 一併解析現價(underlying last price)
- 回傳 JSON;Rails 端過濾掉 bid 與 ask 皆為 null/0 的 strike(無報價不可選)

### 3.3 快取與錯誤
- 兩階段結果各以 (ticker, expiration) 為 key 快取 5 分鐘(Rails cache 即可),避免重複開頁
- 錯誤情境需回傳可辨識代碼並在 UI 顯示友善訊息:代號不存在 / 抓取逾時 / sidecar 未啟動
- 每次抓取需 log 實際導覽 URL(驗收會查)

## 4. UI 流程(單頁、步驟式)

```
Step 1  輸入代號 [RKLB] → 載入履約日
Step 2  點選履約日 → 載入 Put 鏈 + 顯示現價
Step 3  先選「保護腳」(Long Put,買入,取 ask 價)
Step 4  再選「CSP 腳」(Short Put,賣出,取 bid 價)
        → 僅允許 strike 高於保護腳的選項可點
Step 5  自動計算與賠錢情境即時顯示
```

- Strike 清單以表格呈現(strike / bid / ask / IV / delta / OI),點列即選取;已選腳高亮(保護腳藍、CSP 腳紅,沿用小學堂配色)。
- 兩腿必須同一 expiration(同一鏈選取,天然保證)。
- 換履約日或換代號時清空已選腳。
- 保守計價原則:**賣方取 bid、買方取 ask**(頁面註明「以最不利成交價估算,實際可用 mid 價掛單」)。

## 5. 自動計算(選滿兩腿後即時顯示)

| 欄位 | 公式(每股→合約 ×100) |
|---|---|
| 淨權利金收入 | `(bid_short − ask_long) × 100` |
| 價差寬度 | `K_short − K_long` |
| 最大獲利 | 淨權利金 |
| 最大風險 | `寬度 × 100` |
| 最大虧損 | `寬度 × 100 − 淨權利金` |
| 券商押金(約) | 同最大虧損 |
| 損益平衡點 | `K_short − 淨權利金/100` |
| ROC(押金報酬率) | `淨權利金 ÷ 押金`,一位小數,gold 高亮 |
| 風險報酬比 | `1 : (最大虧損 ÷ 淨權利金)`,兩位小數 |

防呆:
- 淨權利金 ≤ 0(倒貼)→ 紅字警告「此組合為 debit,非收租結構」,仍顯示數字但不給 ROC
- 任一腿無報價不可被選取;計算不得輸出 NaN/Infinity

## 6. 「什麼情況下會賠錢」區塊(動態,依選取值生成)

以三色區間呈現到期損益(文字 + 簡單橫條區間圖):

| 到期股價區間 | 結果 |
|---|---|
| ≥ `K_short` | 🌞 全額獲利 = 淨權利金 |
| BE ~ `K_short` | 🌤 獲利遞減,仍為正 |
| `K_long` ~ BE | 🧊 **開始賠錢**,虧損 = `(BE − 股價) × 100` |
| ≤ `K_long` | 🥶 **最大虧損鎖定** = 押金金額 |

並以實際數字帶入(例:「RKLB 收盤低於 $76.50 開始虧損;低於 $71 虧損封頂 $550」)。

## 7. 注意事項(頁面最後,靜態區塊)

1. **必須以單一 spread order 下單**:兩腿分開成交,券商可能按裸賣 Put 計押金,三級帳戶甚至會被拒單。
2. **提前指派風險**:Short Put 進入 ITM(尤其深 ITM、剩餘時間價值極低時)可能被提前指派;被指派後保護腳仍在,最大虧損不變,但需要資金或融資承接股票再處理。
3. **財報與 IV**:跨財報的價差需預期 IV crush 與跳空;權利金厚通常代表事件風險高。
4. **流動性**:遠 OTM 保護腳 spread 常常很寬,實際成交價可能明顯差於畫面估算;OI 過低的 strike 慎選。
5. **寬價差陷阱**:width-based 押金可能高於四級裸賣的公式押金;三級的甜蜜點在**窄價差**。
6. **到期日風險(pin risk)**:到期日股價貼著 short strike 時,是否被指派有不確定性,建議到期前主動平倉或 roll。
7. 資料來源為 Barchart 頁面快照(延遲報價),僅供試算,非下單依據。

## 8. 測試與驗收(強制)

1. **Request spec**(與 unit test 同級交付):覆蓋完整 HTTP path — 路由 → controller → service 呼叫,包含:
   - 履約日查詢 endpoint(帶 ticker)
   - Put 鏈查詢 endpoint(帶 ticker + expiration)
   - service 初始化參數完整性(防止 wiring 未被執行的 ArgumentError 重演)
2. **核心情境優先**:最基本流程(輸入 RKLB → 選最近月履約日 → 選兩腿 → 出數字)必須先 end-to-end 跑通一次,才算其他情境。
3. Playwright 驗收證據需包含:
   - sidecar 實際導覽的 Barchart URL
   - DOM 解析出的關鍵欄位值(現價、至少 3 個 strike 的 bid/ask)**對照使用者手動截圖或 Barchart 頁面人工核對值** — 有輸出 ≠ 輸出正確
   - FairPrice 頁面截圖:sidebar 最後一項入口 → 點入 → 完成一次完整選腿 → 計算結果 DOM 值
   - 手算交叉驗證一組:以畫面上實際 bid/ask 手算淨權利金、押金、BE、ROC,與 DOM 顯示逐項一致
   - 防呆截圖:debit 組合警告、無報價 strike 不可選
4. 「完成」宣告缺上述任一證據即視為未完成;test 通過數不可替代。

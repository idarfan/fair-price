# Max Pain & Vol Skew 篩選器可控邏輯 — 開發前置確認指令

## 背景

規格文件 `fairprice-dashboard-full-spec.md` 第3節已新增「Max Pain & Vol
Skew 篩選器可控邏輯」需求。前一輪確認時，發現 Barchart 的 CSV 下載功能
只涵蓋「Max Pain by Strike」這一張圖（4個欄位：Strike, Puts - Max Pain,
Calls - Max Pain, Max Pain），另外三張圖（OI by Strike、Options
Volatility Skew、Max Pain by Contract）並未包含在CSV裡。

已向 Barchart 官方客服（AI助手）確認：**CSV下載功能本質上只匯出「檢視表
中的文字數值欄位」，圖表本身是視覺化呈現，不會被包進CSV**——這個回覆只
是確認了「CSV格式限制」這個事實，不影響我們要走的路。

## 關鍵疑點：現有系統怎麼做的？

**這四張圖表（Max Pain、OI by Strike、Volatility Skew、Max Pain by
Contract）目前已經正常顯示在FairPrice儀表板上**（驗證divergence_flag
時截圖確認過），代表現有的 `max_pain_scraper`（或對應檔案）跟
`CompositeSignalService#max_pain_data` **一定已經有方法抓到這四張圖的
底層資料**，否則不可能顯示出來。

**在重新設計任何新的抓取邏輯之前，必須先搞清楚現有系統是怎麼抓到這四張
圖資料的**，很可能答案已經存在於現有程式碼裡，這次只是需要在現有邏輯前
面加上「先操作篩選器（到期日/Strikes範圍/Volume-OI）再觸發抓取」這個步
驟，而不是重新發明一套抓取方式。

---

## 第一步：請先回答以下問題（不要寫任何新程式碼）

1. 請直接讀取現有的 max_pain 抓取程式碼檔案（可能是
   `lib/barchart_scrapers/max_pain_scraper.py` 或類似路徑，請先用
   `find` 或 `grep` 確認實際檔名與路徑），把裡面實際抓取以下三項資料
   的程式碼邏輯貼出來：
   - OI by Strike 的抓取邏輯
   - Options Volatility Skew 的抓取邏輯
   - Max Pain by Contract 的抓取邏輯

2. 現有抓取邏輯，是用以下哪一種方式取得這三張圖的資料？
   - (A) DOM解析，讀取頁面渲染後底層的JS資料物件（例如 `_data`、
     `$scope`，類似你們之前驗證Options Flow `*`欄位N/A根因時，讀取
     `bc-data-grid._data[i].raw.label` 的方式）
   - (B) 直接呼叫某個Barchart的API端點
   - (C) 其他方式

   **若是(B)，請立即停止並回報，這可能違反規格文件第1.2節「禁止呼叫
   未授權的內部API端點」原則，需要重新評估，不可繼續沿用。**

3. 現有抓取邏輯，目前是固定抓「頁面預設顯示的到期日」（dropdown未被
   手動切換的狀態），還是已經支援指定任意到期日的參數？

4. 如果現有邏輯是方式(A)（DOM解析讀底層資料物件），請確認這個讀取
   時機是：使用者已經完成「設定篩選器 → 點擊SHOW CHART → 等待圖表
   渲染完成」這個流程之後，去讀取頁面上已經存在的渲染結果，而不是另
   外發送新的網路請求去呼叫API。請明確說明你的判斷依據。

---

## 第二步：依據第一步的回報結果，選擇對應的後續行動

### 情境一：現有邏輯已經是方式(A)，只是沒有參數化到期日

→ 只需要在現有抓取邏輯前面，加上規格文件第3.1/3.2節描述的「設定篩選器
→ SHOW CHART → 等待渲染 → 觸發抓取」流程，沿用現有的資料解析邏輯，
不需要重新設計資料結構或儲存方式。

### 情境二：現有邏輯是方式(B)（呼叫內部API）

→ 停止沿用，回報詳細狀況（呼叫的端點、是否依賴session cookie），等待
進一步決策，不可繼續使用。需要改為方式(A)重新設計。

### 情境三：現有邏輯也只抓了 Max Pain by Strike，OI/Skew/Max Pain by
Contract 目前在儀表板上顯示的其實是別的資料來源（例如別的scraper、或
其實目前顯示的內容跟你以為的不一樣）

→ 請明確指出目前儀表板上這三張圖實際顯示的資料來源是什麼，回報後再
討論下一步。

---

## 補充：三張圖的儲存結構建議（待第一步確認後使用）

若採用方式(A)，建議的資料儲存結構（比照Max Pain by Strike的CSV欄位
邏輯，各自設計對應結構，不要用同一張表硬塞四種不同維度的資料）：

- **Max Pain by Strike**：`Strike, Puts_Max_Pain, Calls_Max_Pain,
  Max_Pain_Value`（已有CSV，直接沿用既有結構）
- **OI by Strike**：`Strike, Call_OI, Put_OI`
- **Options Volatility Skew**：`Strike, Call_IV, Put_IV,
  Combined_IV`（需先確認實際資料物件裡的欄位名稱，不要假設）
- **Max Pain by Contract**：`Expiry_Date, Max_Pain_Value`（這張圖
  不受到期日篩選器影響，只需要在預設情況抓取一次，不需要隨篩選器
  變動重新抓取——已在規格文件第3.3節第2點驗證確認）

---

## 安全與操作原則提醒（沿用規格文件第1節）

- 點擊 SHOW CHART / Download 全程用 Playwright 模擬點擊，不可攔截
  或直接呼叫背後的內部API端點
- 登入狀態偵測僅偵測是否已登入並提醒，不處理登入流程
- 用 `wait_for_selector` 確認圖表/篩選器已完成渲染，不使用固定 `sleep`
- 若發現現有邏輯使用了未授權的內部API（情境二），立即停止並回報，
  不可因為「現有程式碼已經這樣寫」就視為理所當然繼續沿用

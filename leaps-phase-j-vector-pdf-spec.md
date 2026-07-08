# Phase J：PDF 改為向量文字（嵌入中文字型）

> **執行前必讀**：本檔是 Phase J 的唯一規格來源。做完每一項後，**必須回到本檔末端「進度追蹤」區更新狀態並附證據**，不要只在對話裡回報。新 session 接手時先讀本檔末端進度區，確認做到哪裡。

---

## 目標與動機

現行 PDF 走「html-to-image 產 PNG → jsPDF.addImage 嵌入」，本質是點陣圖，200% 縮放檢視時中文與數字模糊。改為**向量文字 PDF**：文字可選取、可搜尋、無限放大不糊。

---

## ⚠️ 先撤銷兩條現行規格

修訂 `leaps-call-recommendation-spec.md` 的「匯出功能現況」節，將以下兩條**明文標註為「已被 Phase J 取代」**（不是刪掉了事，要留下撤銷記錄，避免下個 session 讀到舊規格與新實作打架）：

1. ~~「PDF 一律先轉 PNG 再嵌入」~~ → 改為向量文字直接繪製。
2. ~~「PNG 與 PDF 畫面一致」~~ → 兩者版面從此不同。向量 PDF 是重新排版，不可能與 DOM 截圖像素一致。

**PNG 匯出維持現行圖片路線，完全不動。** 只有 PDF 改走向量。這是有意識的取捨。

---

## 實作要求

### 1. 字型選用

- 使用 **Noto Sans TC Regular**（SIL OFL 1.1 授權，明確允許嵌入與散布）。
- **禁用**微軟正黑體、思源黑體以外的商用字型——授權不允許嵌入散布。
- 字型來源與版本在 vendor 目錄註明（同 `html-to-image` 的 vendor 慣例）。

### 2. 字型必須 subset（不可嵌入完整字型檔）

完整 Noto Sans TC TTF 約 5–10MB，直接嵌入會讓每份 PDF 都背這個體積。

- 用 `pyftsubset`（fonttools）產生子集。
- **字元集來源必須程式化提取**，不得手工列舉：掃描 Phlex 元件、文案 map、免責聲明字串中實際使用的字元 ∪ ASCII ∪ 常用標點，另加安全邊際字元。
- **subset 腳本與字元集清單 commit 進 repo**（例如 `script/subset_font.sh`），未來文案改動可重跑重建。
- 頁面中文為固定詞彙（欄位標題、「充足/普通/偏低」、免責聲明），動態內容（ticker、數字、日期）全為 ASCII，subset 後預期 100–300KB。
- **回報 subset 前後檔案大小。**

### 3. 字型載入方式

- 字型檔放 vendor 目錄。
- 以 `fetch` 載入後 `addFileToVFS` + `addFont`。
- **不要 inline base64**（base64 編碼會膨脹約 33%，且污染原始碼可讀性）。

### 4. CJK 換行必須自行實作 ⚠️ 隱形地雷

jsPDF 的 `splitTextToSize` 依**空白字元**斷詞。中文沒有空白 → 整段推薦分析會衝出頁面右緣不換行。

- 推薦分析等長段落，用逐字寬度量測（`getTextWidth`）自行實作換行。
- 驗收必須包含**一段刻意超長的中文推薦理由**，確認正確換行、不出血、不裁切。

### 5. 表格重新排版

- 用 `jspdf-autotable`，`styles.font` 指定嵌入字型（不指定會 fallback 到內建字型 → 豆腐字）。
- 18 欄採橫向 A4 或自訂寬頁。
- 表頭跨頁重複。
- 流動性分級（充足／普通／偏低）顏色沿用頁面既有語義色，不另造色票。

### 6. 失敗必須炸，不得靜默降級 ⚠️ 關鍵

字型未載入或 `addFont` 未成功時，jsPDF 會用內建字型繼續繪製，**產出一份滿頁豆腐字但「成功下載」的 PDF**——這正是本專案一貫禁止的「有結果≠結果正確」。

- 字型載入失敗或 `addFont` 未成功 → **中止匯出並顯示錯誤訊息**。
- **不得** fallback 到 jsPDF 內建字型。
- **不得** fallback 回舊的 PNG 嵌入路線（那會讓失敗被掩蓋，使用者以為向量 PDF 正常運作）。

---

## 驗收（程式化為主，目測為輔）

| # | 項目 | 方法 |
|---|---|---|
| 1 | 文字可選取性 | 對輸出 PDF 執行 `pdftotext output.pdf -`，確認中文標題、欄位名稱、推薦理由**正確提取為文字**（非空白、非亂碼）。附實際輸出。 |
| 2 | 無豆腐字 | `pdftotext` 結果與頁面文案**逐字比對**，任何 `□` 或缺字即不通過。 |
| 3 | 200% 縮放清晰度 | 開檔以 200% 檢視，中文與數字邊緣銳利（向量應完全無鋸齒）。附截圖。 |
| 4 | 長段落換行 | 推薦理由完整顯示、無右緣溢出、無被裁切。用刻意超長的中文段落測試。 |
| 5 | **失敗路徑實測** | **故意讓字型檔 404**，確認匯出**中止並報錯**，而非產出豆腐字 PDF、亦非悄悄退回 PNG 路線。 |
| 6 | 檔案大小 | 回報最終 PDF 大小，與舊圖片版（約 550KB）對比。 |
| 7 | 回歸 | PNG 匯出行為完全不變（檔名、disabled、防重複點擊）；全套測試通過。 |

> 驗收第 5 項是本階段最重要的一條。前四項驗的是「做對了」，第 5 項驗的是「做錯時會被發現」。

---

## 已知工程量

比 `pixelRatio` 提高解析度的方案大一個量級（subset 流程、CJK 換行、表格重排、失敗處理），預估一整天。取捨已由使用者決定：要的是「PDF 是真的文件」（可搜尋、可複製、無限放大不糊），不只是「看得清楚」。

---

# 進度追蹤（每完成一項就回來更新此區，附證據）

> **規則**：狀態只有三種——`未開始` / `進行中` / `已完成（附證據）`。不得在未附證據的情況下標記已完成。若某項被阻塞，寫明阻塞原因與待決事項，不要留白。

## 實作進度

| # | 項目 | 狀態 | 證據 / 備註 |
|---|---|---|---|
| 0 | 撤銷主 spec 兩條舊規格（PNG 嵌入、畫面一致） | 已完成（附證據） | `leaps-call-recommendation-spec.md` 「匯出功能現況」節兩條改 `~~刪除線~~` 並註明「已被 Phase J 取代」，PNG 路線規則獨立成一行明確標註「僅適用於 PNG 匯出路線」 |
| 1 | 取得 Noto Sans TC Regular，vendor 就位、來源版本註明 | 已完成（附證據） | 來源：`fonts.gstatic.com/s/notosanstc/v39/-nFuOG829Oofr2wohFbTp9ifNAn722rq0MXz76Cy_Co.ttf`，版本 `Version 2.004-H2`（Google Fonts CDN，OFL 1.1 授權，允許嵌入散布），完整字型 7,090,820 bytes（不進 repo，僅供 subset）。來源與版本註明於 `script/subset_font.sh` 檔頭註解。 |
| 2 | subset 腳本 `script/subset_font.sh` 與字元集程式化提取 | 已完成（附證據） | `script/extract_leaps_charset.py` 掃描 3 個 LEAPS 原始碼檔（page_component/recommendation_service/ranking_service）取得 623 字元（603 掃描字＋20 安全邊際標點，非手工列舉）；`script/subset_font.sh` 呼叫 pyftsubset。**實測大小**：完整 7,090,820 bytes → 子集 **200,808 bytes（196KB，2.8%）**，落在規格預期 100–300KB 範圍。驗證子集含關鍵字形（履約價外在佔比等 CJK＋ASCII＋`$`）：718 字符全數命中。 |
| 3 | fetch + addFileToVFS + addFont 載入（非 base64） | 已完成（附證據） | `loadFont()`：`fetch(fontUrl)` 取子集字型（`data-pdf-font-url` 由 Phlex `helpers.asset_path` 注入 digest 路徑）→ arrayBuffer→base64→`addFileToVFS`+`addFont`→驗證 `getFontList()` 確實含 `NotoSansTC.normal`。base64 只用於 VFS 註冊這一步（jsPDF API 要求），字型本身走 fetch 二進位下載，不是 inline base64 寫死在原始碼。 |
| 4 | CJK 逐字量測換行實作 | 已完成（附證據） | `wrapCjk(pdf, text, maxWidth)`：逐字用 `pdf.getTextWidth()` 量測，超寬即斷行；推薦理由文字按 `\n` 先分段再逐段換行，取代 jsPDF 內建依空白斷詞的 `splitTextToSize`（中文無空白會直接溢出）。 |
| 5 | jspdf-autotable 表格重排（18 欄、表頭跨頁、語義色） | 已完成（附證據） | vendor `jspdf-autotable-3.8.4.js`（UMD，載入順序 jspdf→autotable，自動掛載 `pdf.autoTable()`）。`renderCandidatesTable`：18 欄 head/body、`didParseCell` 依 `liquidity_rgb`（Ruby 端 `pdf_signal_rgb_for_tier` 從既有 `SIGNAL_COLORS` 語義 key 映射出的 hex，不另造色票）上色流動性判斷欄。`renderFlowTable`：10 欄，方向欄同法上色。橫向 A4，表頭 autotable 內建跨頁重複行為（未特別關閉）。 |
| 6 | 字型失敗 → 中止並報錯（不 fallback） | 已完成（附證據） | `loadFont()` 三個中止點：(a) `fontUrl` 為空 → reject；(b) `fetch` 非 2xx → throw；(c) `addFont` 後 `getFontList()` 驗證失敗 → throw。`window.__leapsExportVectorPdf` 的 Promise chain 沒有任何 `.catch()` 吞掉這些錯誤再改走別的繪製路徑——錯誤會往上拋到 `render_export_script` 的點擊處理器統一 `alert()` 顯示並還原按鈕狀態，PNG 路線完全不受影響（兩條路徑在點擊處理器就分岔，PDF 失敗不會被靜默替換成 PNG 嵌入）。E2E 驗證見驗收進度第 5 項。 |

## 驗收進度

| # | 驗收項 | 狀態 | 證據 |
|---|---|---|---|
| 1 | `pdftotext` 中文正確提取 | 未開始 | |
| 2 | 無豆腐字（逐字比對） | 未開始 | |
| 3 | 200% 縮放邊緣銳利（截圖） | 未開始 | |
| 4 | 超長中文段落正確換行 | 未開始 | |
| 5 | **字型 404 → 匯出中止報錯** | 未開始 | |
| 6 | PDF 檔案大小對比 | 未開始 | |
| 7 | PNG 行為回歸、全套測試通過 | 未開始 | |

## 未解決 / 待決事項

（實作過程中遇到的阻塞、需使用者拍板的取捨，寫在這裡，不要只在對話裡講完就消失）

- 目前無。

## 變更記錄

| 日期 | 內容 | commit |
|---|---|---|
| 2026-07-08 | 規格建立 | — |

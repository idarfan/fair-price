# Phase H：intrinsic_value / extrinsic_value 衍生欄位

_最後更新：2026-07-04_

規格：`leaps-call-recommendation-spec.md` Phase H 節（2026-07-04 版，人工對照已拆 fixture/live 兩層）

- [x] 改前截圖（UI 強制流程第 1 步）
- [x] Migration：加 `intrinsic_value`/`extrinsic_value`（decimal 10,4，允許 null）+ up_only SQL backfill
- [x] `LeapsOptionChainSnapshot.derived_values`：公式唯一定義（Mid 基準、option_type 分支、bid/ask/spot 缺值 → 雙欄 null）
- [x] `persist_leaps`：每筆 row 呼叫 derived_values 存入；`leaps_scraper.py` 零改動
- [x] `LeapsRankingService#enrich`：改讀 DB 欄位，移除排行層重複公式；新增 `extrinsic_pct = extrinsic_value / mid`（display 層，mid≤0 或缺值 → nil）
- [x] `page_component.rb`：表格加「內在價值／外在價值／外在佔比」三欄（Spread% 之後、Time Value% 之前），nil 顯示「—」
- [x] 單元測試：深 ITM call／OTM call／bid 或 ask null／put 分支／NVTS 2026-07-02 fixture 釘公式
- [x] display 層測試：mid=0 或 null → 佔比 nil
- [x] request spec：完整 HTTP 路徑驗證新欄位渲染
- [x] `rails db:migrate` + 全套 RSpec
- [x] rebuild CSS + E2E：NVTS 不帶 user_strike 完整查詢，新欄位全數有值
- [x] live 層人工對照：當次抓到的 bid/ask/spot 手算兩筆 vs 頁面顯示（不得對 2026-07-02 歷史數值）
- [x] 改後截圖比對（UI 強制流程第 3 步）
- [x] 規格 checklist 打勾附證據、commit、Obsidian 日誌

---

## LEAPS Delta 修正 — 已結案 ✅（2026-07-02）

截圖：`leaps-nok-delta-verify.png`、`leaps-klac-partial-error.png`；詳見 git log 與規格第 3 節。

---

## Review（2026-07-04 收尾）

- 全套 RSpec：352 examples, 0 failures（+15：derived_values 9、fixture 層 2、ranking 4、request 2，減去既有重跑）
- E2E：NVTS 不帶 user_strike，76/76 rows 新欄位有值；live 手算兩筆與頁面一致
- 插曲：首跑 E2E 因 pm2 server schema cache 過期（migration 前啟動）→ insert_all ROLLBACK；
  transaction 設計正確保住舊資料；重啟後通過。教訓：migration 後必須重啟 dev server 再跑 E2E。
---

## Phase I：匯出 PNG/PDF — 已結案 ✅（2026-07-05）

- vendor 本地檔（html-to-image-1.11.11 + jspdf-2.5.2，版本釘死）、layout CDN 標籤一併替換
- 右上角雙按鈕、事件委派、無資料 disabled、匯出中防重複
- PDF = PNG 嵌入 + FAST 壓縮（48MB→550KB）
- 修正：clone 內捲軸 → 無條件展開 overflow 容器再還原
- E2E：真實點擊下載事件 ×2 + 開檔驗收（20 列 flow 完整、中文正常、背景正確）
- 352 examples, 0 failures
---

## 待辦：Phase H live 對照補驗（台灣時間 2026-07-06 週一 ~21:30 美股開盤後）

- [ ] 重查 NVTS（不帶 user_strike），從當次抓到的資料任取一筆，用當次 bid/ask/spot
  手算內在/外在/佔比，與頁面顯示值比對，附手算過程。
  背景：2026-07-05 的 live 對照跑在休市期間、報價凍結、鑑別力不足。
  一致後 fresh window／Phase H／Phase I 三項才算真正全部結案。
---

## LEAPS 欄位教學（driver.js tooltips）— 已結案 ✅（2026-07-05）

三層互動全驗收：hover 深色 tooltip、點擊聚光 popover（深色）、28 步 tour；
28 欄 0 dead key；匯出 PNG md5 與前版逐位元組一致；352 examples 全過。
規格：leaps-column-tooltips-spec.md（checklist 已附證據打勾）
---

## LEAPS 主 spec 索引同步（規格文件，非程式碼）— 已結案 ✅（2026-07-11）

- [x] 審視 `leaps-call-recommendation-spec.md` 是否已納入 `leaps-phase-j-vector-pdf-spec.md`（PDF 向量文字化）的完成狀態
- [x] 補「接手前必讀」摘要句：加入 Phase J 交付內容＋4 輪補做清單（名詞解釋圖卡／Flow 總額與重疊提示／語意色與推薦徽章／術語字卡＋IPA 音標字型）
- [x] 補「執行方式」階段索引：Phase J 已結案，指向子規格檔進度追蹤區
- [x] 補「路由與前端」節：記錄 LEAPS 頁面在 sidebar 的現行位置（`APP_LINKS` 第 12 項、icon/label/href/desc、所屬 app = FairPrice port 3003）
- [x] commit + push（`a11ac6b..4357146`）
- [x] Obsidian 工作日誌寫入（`fairprice/2026-07-11 工作日誌.md`）

## Review（2026-07-11）

- 純規格文件同步，無程式碼異動，未觸發 RSpec/E2E。
- 根因：Phase J 獨立成子規格檔後，主 spec 的頂層摘要句／階段索引沒有同步更新，造成新 session 讀「接手前必讀」時會誤判 Phase J 還沒開始，需額外去查子規格檔進度追蹤區才發現其實已結案。
- 教訓（已寫入 Obsidian 日誌，待補進 `tasks/lessons.md`）：往後每完成一個獨立 Phase 子規格，除子規格自身的進度追蹤區外，也要回頭檢查主 spec 頂層摘要是否同步列入；規格中的「原則性指示」與「已交付事實」應分開記錄，避免事實面隨程式改動而與規格脫節。

# PMCC 部位追蹤與滾倉建議

## 執行狀態表
| 階段 | 狀態 | 驗證方式 |
|---|---|---|
| Phase 1 資料模型 | 未開始 | migration 執行成功 + schema.rb 含三張表 |
| Phase 2 滾倉觸發判斷 | 未開始 | RSpec：給定 4 組已知案例（深度ITM/價平/價外/近到期），觸發布林值正確 |
| Phase 3 滾倉建議服務 | 未開始 | 給定真實 option chain fixture，輸出建議履約價與 Phase2 手算結果一致（誤差<$1） |
| Phase 4 損益帳本 | 未開始 | 建立3筆模擬 roll 事件後，累積已實現損益=手算值；含未實現長腳損益欄位 |
| Phase 5 前端整合 | 未開始 | Playwright 截圖：建立部位→模擬滾倉→損益帳本頁面皆可操作，非僅 API 回應 |

> 接續 session 只需讀本表 + 進行中階段章節。

---

## 背景
使用者持有 PMCC（Poor Man's Covered Call）部位：長腳 LEAPS Call（深度ITM，長期不動）+ 短腳 Call（短天期，需定期滾倉收租）。現況：手動看盤決定滾倉時機與履約價，無自動追蹤損益。

## 名詞定義
- **長腳（Long Leg）**：一筆部位僅一組，履約價/到期日固定，僅在使用者手動平倉時才變動
- **短腳（Short Leg）**：可有多筆歷史紀錄（每次 roll 產生一筆新紀錄，舊紀錄標記為 closed）
- **黃金法則**：`PL(長腳現值) >= Spread(短腳履約價 − 長腳履約價)`，沿用既有 `P_L < K_S − K_L` 邏輯（見 fairprice.md screening 標準）

---

## Phase 1：資料模型

### `pmcc_positions`（一組 PMCC 部位 = 一筆長腳）
| 欄位 | 型別 | 說明 |
|---|---|---|
| ticker | string | |
| long_strike | decimal | 長腳履約價（固定） |
| long_expiration | date | |
| long_entry_cost | decimal | 長腳買入成本（PL, 每股） |
| long_entry_date | date | |
| status | enum | active / closed |
| closed_at | datetime | nullable |

### `pmcc_short_legs`（短腳歷史，多筆屬於一個 position）
| 欄位 | 型別 | 說明 |
|---|---|---|
| pmcc_position_id | FK | |
| short_strike | decimal | |
| short_expiration | date | |
| premium_collected | decimal | 賣出時收到的權利金（每股） |
| opened_at | datetime | |
| status | enum | open / expired_worthless / rolled / assigned |
| close_cost | decimal | nullable，買回平倉成本（每股）；expired_worthless 為 0 |
| closed_at | datetime | nullable |
| rolled_to_id | FK | nullable，self-reference 指向下一筆短腳（roll 鏈） |

### `pmcc_pnl_events`（損益帳本，每次短腳了結/長腳異動各產生一筆）
| 欄位 | 型別 | 說明 |
|---|---|---|
| pmcc_position_id | FK | |
| event_type | enum | short_expired / short_closed / short_assigned / long_exercised / long_closed |
| realized_pnl | decimal | 該事件實現損益（每口 ×100） |
| occurred_at | datetime | |
| note | text | |

**驗收**：三表 migration 跑通，`pmcc_position has_many short_legs has_many pnl_events`（透過 position）關聯可查。

---

## Phase 2：滾倉觸發判斷

輸入：目前 active short leg + 即時報價（Delta, DTE, 標的現價）

觸發規則（任一成立即建議滾倉，回傳觸發原因清單，不自動執行）：
1. `short_leg.delta >= 0.60`（深度價內，時間價值近枯竭）
2. `DTE <= 5` 且 `moneyness >= -5%`（近到期且接近/價內，被指派風險陡增，對照本次對話 4 DTE 警示邏輯）
3. 距離除息日 `<= 3` 天 且短腳為價內（提早指派風險）
4. 使用者手動觸發（前端按鈕）

**驗收**：4 組已知案例（深度ITM/價平/價外/近到期）跑過規則，觸發結果與手算一致。

---

## Phase 3：滾倉建議服務

輸入：pmcc_position + 觸發原因 + option chain

**資料源沿用現有管線，不新建抓取**：`PmccShortCallSnapshot` model（`app/models/pmcc_short_call_snapshot.rb`）+ `lib/barchart_scrapers/pmcc_short_call_scraper.py`，觸發方式沿用 `BarchartScraperService#fetch_pmcc_short_calls`（由 `ScrapeLeapsJob` 內 `fetch_pmcc_short_calls_isolated` 呼叫）。若候選履約價/到期日在 snapshot 內無資料，需求呼叫既有排程重抓，不得繞過此管線另建 Python script（避免重複維護兩套 Barchart 爬蟲，違反單一資料源原則）。

篩選候選：
- DTE 落在 19–45 天（lesson9 區間），扣外可標記「不符建議區間」但仍列出供參考
- Delta 落在 0.15–0.30（沿用使用者過去操作習慣區間，可設定檔調整）
- Strike > 目前短腳履約價（僅列 roll up，不含 roll down）

每個候選輸出：
```
新短腳履約價 / 到期日 / DTE / Delta / Mid權利金
新Spread = 新短腳履約價 − 長腳履約價
滾動淨現金流 = 新短腳權利金 − 目前短腳買回成本(mid)
新NetDebit = 長腳現值 − (原短腳累積淨收 + 本次滾動淨現金流)
新MaxProfit = 新Spread − 新NetDebit
黃金法則 = 長腳現值 >= 新Spread ? 通過 : 不通過
```
按「黃金法則通過 → 新MaxProfit 由高到低」排序，取前 5 筆。

**驗收**：用一組真實 option chain fixture（可用本次對話 245 履約價那張截圖數據當測試資料），輸出的候選與手算結果一致（誤差 <$1，因報價可能有 bid/ask/mid 微差）。

---

## Phase 4：損益帳本

### 已實現損益（每個 pnl_event 加總）
- `short_expired`：`realized_pnl = premium_collected × 100`
- `short_closed`（含滾倉時的買回）：`realized_pnl = (premium_collected − close_cost) × 100`
- `short_assigned`：`realized_pnl = (short_strike − 長腳履約成本basis) × 100 − 長腳剩餘時間價值損失估算`，並寫入 note 說明估算方式
- `long_closed`：`realized_pnl = (賣出價 − long_entry_cost) × 100`

### 未實現損益
- 長腳現值（現價 − long_entry_cost）× 100，需即時查價，不寫入 pnl_events（僅前端顯示，避免頻繁報價污染帳本）

### 部位總覽
```
累積已實現損益 = SUM(pnl_events.realized_pnl WHERE position_id = X)
未實現損益（長腳）= 現值 − 成本
部位總損益 = 累積已實現 + 未實現
年化報酬率 = 部位總損益 / long_entry_cost / 持有天數 × 365
```

**驗收**：建立3筆模擬 roll 事件（含1筆 assigned）後，累積已實現損益與手算值一致；頁面同時顯示未實現長腳損益。

---

## Phase 5：前端整合

### 掛點（現況，非新建）
- **無獨立路由**：PMCC 現況是 `/leaps` 頁面（`config/routes.rb` 的 `leaps_recommendations#index`）內的一個區塊，靠 `?symbol=XXX` 帶入，且 `candidates.blank?` 時直接回 `{ status: :no_data }`（見 `LeapsRecommendationsController#pmcc_ranking_for`，第157行）。**本功能沿用此掛點，不新建路由/controller，也不新增 sidebar 入口。**
- **版面位置**：不與既有 `pmcc_section.rb`（黃金法則排行表）並排（並排造成版面壅擠、難閱讀）。改為**垂直堆疊在 `pmcc_section.rb` 正下方**，同屬一個折疊群組容器：黃金法則排行表在上、部位追蹤區塊在下，兩者視覺上是同一張卡片的兩個子區塊，不是左右分欄
- **收折行為**：部位追蹤區塊預設**收折（collapsed）**，僅顯示摘要列（例如：`目前部位：KL100/KS230，累積損益 +$XXX`），使用者點擊展開才顯示完整內容（滾倉建議、損益帳本時間軸、操作表單）。與 `pmcc_section.rb` 既有的收摺行為保持一致的互動模式（沿用同一套 UI 元件/CSS class，不另外設計一套收折邏輯）
- **新增區塊位置**：新建 `app/components/leaps_recommendations/pmcc_position_tracker.rb`，由 `LeapsRecommendations::PageComponent` include 進去，渲染順序上緊接在 `pmcc_section.rb` 之後（同一父容器內的下一個子元件）
- **資料進入點**：`LeapsRecommendationsController#index`（第76、87行附近）比照 `@pmcc_ranking = pmcc_ranking_for(...)` 的寫法，新增 `@pmcc_position = pmcc_position_for(@symbol)`（新 private method，若無 active position 回 nil，component 內判斷是否渲染；無部位時整個區塊不顯示，不顯示空的收折列）
- **計算服務**：Phase 3 滾倉建議服務新建 `app/services/pmcc_roll_suggestion_service.rb`，與既有 `app/services/pmcc_ranking_service.rb` 平行放置，不合併進同一服務（黃金法則排序 vs 滾倉建議是兩種不同查詢，避免職責混雜）

### 操作流程
- 建部位表單：輸入長腳（履約價/到期日/成本）即建立 `pmcc_positions` 記錄，關聯到當前 `symbol`
- 部位詳情區塊：目前短腳狀態、滾倉建議（呼叫 Phase3 服務）、損益帳本時間軸
- **滾倉操作**：使用者從建議清單點選一筆 → 表單預填 → 確認送出 → 建立 `pnl_event(short_closed)` + 新 `short_leg`
- **整個部位平倉（新增）**：不透過履約交割，改「兩腳一起平倉」——Sell to Close 長腳 + Buy to Close 短腳，同組合單。表單輸入：長腳賣出價（每股）、短腳買回價（每股）→ 建立 `pnl_event(long_closed)` + `pnl_event(short_closed)`（若當時仍有 open short leg）→ `pmcc_position.status = closed`。此為結束部位的**預設建議路徑**，履約交割（`long_exercised`）僅在無法市場平倉時才使用，UI 上不做為主要按鈕

### 完成驗收
Playwright 截圖跑過以下完整流程，非僅 API 層測試：
1. `/leaps?symbol=XXX` 頁面建部位
2. 觸發滾倉建議 → 確認滾倉 → 損益帳本更新
3. 整個部位平倉（兩腳一起平倉）→ position 狀態變 closed、帳本寫入兩筆 pnl_event

---

## 未決事項（需使用者確認後補入 spec）
- [ ] 長腳現值查價：即時抓 Barchart 或用使用者手動輸入？（影響 Phase4 未實現損益即時性）
- [ ] `short_assigned` 情境的長腳剩餘時間價值損失，用何種估算模型（Black-Scholes 理論價 vs 抓取當下市價）？
- [ ] roll 候選 Delta 區間 0.15–0.30 是否要做成可調參數（存在 position 或全域設定）？

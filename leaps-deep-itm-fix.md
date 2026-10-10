# FairPrice 修正規格

**問題一：LEAPS 候選遺漏深度價內履約價**

**問題二：PMCC Long Δ ≥ 0.80 規則未落實**

## 回報程式問題：請程式開發者介入處理

- **發現時間**：2026-10-09（五）21:41–21:49 台北時間（UTC+8）
- **規格撰寫**：2026-10-09 21:49 初版；21:57 修訂
- **發現情境**：想用 FairPrice 找 INTC 適合進場的 LEAPS Call，查詢 strike 80
- **當時行情**：INTC 現價 $106.76（前收 $113.12，當日區間 $105.24–$111.60）

| # | 我做了什麼 | 預期 | 實際 |
|---|---|---|---|
| 1 | 開啟 `/leaps?symbol=INTC&user_strike=80` | 列出 $80 的 LEAPS 候選（$80 深度價內，Δ 應遠高於 0.60） | 警告「履約價 80 在所有到期日都沒有 Delta ≥ 0.60 的候選」。但同一頁的 Options Flow 顯示 $80C 2028-12-15 的 Δ 0.802，當天有數百萬美元大單，POI 也標示 OI 104,625 |
| 2 | 不填履約價，按「查詢」 | 列出 Δ ≥ 0.60 的所有深度價內 Call | 只出現 $100、$105 兩個履約價（Δ 0.67–0.73），$80–$95 全部沒出現 |
| 3 | 看 PMCC 區塊 | 組合的 Long 腳符合規範卡上寫的「Long Delta ≥ 0.80」 | 組合表的 Long Δ 是 0.671–0.732，全部不符合。說明卡的範例也用 Δ 0.671 的 $105 |

**審視程式後，發現以下問題：**

1. **候選涵蓋範圍不足**：LEAPS 候選只取現價附近的履約價，Δ 較高的深度價內履約價（$80–$95）沒有被納入。推薦結果因此偏向 Δ 偏低、時間價值偏高的合約。
2. **指定履約價判定錯誤**：`user_strike` 的驗證疑似只依據窗口內的 snapshot 判斷，把實際存在、而且 Δ ≈ 0.80 的 $80 誤判為「無候選」。這和先前 NOK $7 的缺陷同類，可能是回歸。
3. **PMCC 規則沒有落實**：規範卡寫明 Long Δ ≥ 0.80，但組合篩選沒有執行這個條件，說明卡的範例也採用不合規的長腳。介面文字和運算邏輯不一致。
4. **快取可能掩蓋修正結果**：同一個 symbol + strike 會共用查詢結果。修正後如果沒有清除舊快取，頁面仍可能顯示錯誤結果，影響驗收。

---

> **以下給 Claude Code。**

> Loop Engineering 模式：依序執行各階段，每階段跑完「驗證」且全部通過，才能進下一階段。驗證沒過就留在原階段修，不准跳階、不准併階。
> 每通過一階段，就 patch 更新 E 節狀態表（只改該列，不整檔重寫），並依 D 節格式回報。

## A. 問題清單（要修什麼）

| ID | 問題 | 症狀（2026-10-09 實測，INTC ≈ $106.76） | 影響 |
|---|---|---|---|
| B1 | 深度價內履約價沒進候選 | 自動查詢的候選表只有 $100/$105。$95/$90/$85/$80 全部缺席 | 推薦結果偏向低 Delta、時間價值偏高的合約 |
| B2 | `user_strike` 誤判無候選 | `user_strike=80` 顯示「所有到期日都沒有 Delta ≥ 0.60」，但實際 $80C 2028-12 的 Δ ≈ 0.80、OI 104,625 | 使用者查不到最該看的履約價 |
| B3 | PMCC Long Δ ≥ 0.80 沒落實 | 規範卡寫 Long Δ ≥ 0.80，但組合表的 Long Δ 是 0.671–0.732 | 文字和邏輯矛盾，組合不符合自訂規則 |
| B4 | PMCC 說明卡範例違規 | 範例「$105→$190」「LEAPS 成本 $3,203」用的是 Δ 0.671 的腳 | 教學範例示範了錯誤的做法 |
| B5 | 快取可能保留錯誤結果 | 同一個 symbol + strike 共用結果。修好後，舊快取可能繼續顯示錯誤 | 修好了但看起來沒修好，驗收失真 |

## B. 修改順序（依序執行，前一項驗證通過才做下一項）

| 順序 | 階段 | 解決 | 要改什麼（一句話） |
|---|---|---|---|
| 1 | P0 | B1 B2 B5 | 不改碼。先重現問題、畫出資料流、確認根因與快取機制 |
| 2 | P1 | B1–B4 | 先寫測試，而且測試必須先失敗 |
| 3 | P2 | B1 B5 | 擴大履約價涵蓋範圍到 0.60 ≤ Δ ≤ 0.95，並清掉舊快取 |
| 4 | P3 | B2 | 資料過期／被其他查詢取代時顯示「已不是最新，請重新查詢」，不再誤報 Delta 不足；並把「無此履約價」和「Delta 不足」兩種訊息分開（2026-10-09 依 P0 結論改寫，使用者裁示：過期顯示訊息，不自動重抓） |
| 5 | P4 | B3 B4 | PMCC 的 Long 腳強制 Δ ≥ 0.80（常數化），說明卡範例改從合格腳選 |
| 6 | P5 | 全部 | Request spec 走完非同步全流程 |
| 7 | P6 | 全部 | 正式環境 Playwright 實測，並和實測值交叉比對 |
| 8 | P7 | 全部 | 全套回歸、檢查沒新增 API 呼叫、寫結案報告 |

## C. 怎麼測試（每個問題的通過標準）

| ID | 單元/整合測試 | E2E 判定（P6） |
|---|---|---|
| B1 | T1：fixture 的 LEAPS 履約價鏈中，所有 0.60 ≤ Δ ≤ 0.95 的履約價都要送進 Stage 2（scraper 層） | INTC 候選表的最低履約價 ≤ 85，而且含 80 |
| B2 | T2：`job_status=success` 但資料不新鮮時，不出現 Delta 不足警告，改出現「已不是最新」訊息。T2b：不存在的履約價出現「期權鏈無此履約價」。T2c：Δ 不足出現原本的警告 | `user_strike=80` 頁面沒有 Delta 不足的警告 |
| B3 | T3：Long Δ < 0.80 不進通過清單。T3b：無合格腳時顯示指定訊息 | PMCC 通過組合的 Long Δ 最小值 ≥ 0.80 |
| B4 | T3c：範例選用的 Long Δ ≥ 0.80 | 說明卡的 LEAPS 履約價 Δ ≥ 0.80 |
| B5 | P2 驗證：清除後查快取確認已經沒有舊資料 | 從空白輸入框按「查詢」觸發新 job，結果符合上面各項 |
| 回歸 | NOK $7 舊測試、全套 rspec/pytest | NOK `user_strike=7` 仍有候選 |

## D. 怎麼回報

**每完成一階段**，依序做三件事：
1. Patch 下方狀態表的該列（只改該列）
2. 在對話中貼出以下格式的回報，交給審查官 session
3. 審查官沒有異議、而且使用者同意後，才進下一階段

```
【P? 回報】
解決問題：B?
修改檔案：git diff --stat 輸出
驗證結果：每一條驗證都標 ✅/❌，並附指令和輸出原文（不准用摘要代替）
證據位置：截圖、JSON 的路徑
未解決/疑點：沒有就寫「無」
```

**結案**（P7）時，依序回答第 P7 節列的 5 題。第 1 題是「核心用例（不填履約價的預設查詢）有沒有端到端跑過」，必須附 URL 和截圖。

## E. 執行狀態表

| 階段 | 解決 | 狀態 | 審查 | 證據位置 / 備註 |
|---|---|---|---|---|
| P0 | B1 B2 B5 | ✅ 通過 | r2 PASS（verdict-leaps-deep-itm-P0-r2.md）；P6 截圖須截到排行表區塊 | 本檔「附錄 P0」、`tmp/e2e/leaps-deep-itm/P0/`；B1 假設證實、B2 假設推翻，見 §0「P0 根因結論」 |
| P1 | B1–B4 | ✅ 通過 | r1 PASS（verdict-leaps-deep-itm-P1-r1.md）；P2 須回應質詢 1（導航順序）、2（送出檔數與耗時） | T1 `test_leaps_scraper.py::TestAutoModeCoversDeepItmLeapsStrikes`、T2 `spec/requests/leaps_recommendations_spec.rb`、T3 `spec/services/pmcc_ranking_service_spec.rb`；P1/P3 已依 P0 結論與使用者裁示改寫（T1 移到 scraper 層、T2 改測過期訊息、T4 不適用） |
| P2 | B1 B5 | ✅ 通過 | r2 PASS（verdict-leaps-deep-itm-P2-r2.md）；P6/P7 的 NOK 回歸須附 DOM 與排行表截圖 | `tmp/e2e/leaps-deep-itm/P2/`；LEAPS_MAX_DELTA 依使用者裁示改 0.90；INTC 23 檔、143 秒（基準 72–74 秒） |
| P3 | B2 | ✅ 通過 | r1 PASS（verdict-leaps-deep-itm-P3-r1.md）；待 P4/P5 回應質詢 1（controller 採信舊清單快照）、2（P5 補不 stub 排名的 T2c）、3（訊息日期來源） | `tmp/e2e/leaps-deep-itm/P3/`；T2b 依使用者裁示 (i) 以第一個 LEAPS 到期日的鏈判斷；附錄 P0 Q5 更正（server 實為 production、file_store） |
| P4 | B3 B4 | ✅ 通過 | r1 PASS（verdict-leaps-deep-itm-P4-r1.md）；P5 前回應質詢 1（migration 後先以擁有者跑 `RAILS_ENV=test bin/rails db:test:prepare`，核對 `schema_sha1` 與 `sha1sum db/schema.rb` 一致再送審）；P7 附 options_flow→leaps 耗時對照 143 秒；P6 截圖要看得到 PMCC 組合表 | `tmp/e2e/leaps-deep-itm/P4/`；併做 P3 r1 質詢 1（清單快照 1 天內才判斷）、3（新增 `chain_expiration_date`）。**另案**：Short 腳 Δ 0.20–0.35 與 DTE 19–45 目前只做標記（✅/⚠️、「建議區間」），沒有篩選 |
| P5 | 全部 | ⬜ 未開始 | | |
| P6 | 全部 | ⬜ 未開始 | | |
| P7 | 全部 | ⬜ 未開始 | | |

狀態值只能填：⬜ 未開始 / 🔄 進行中 / ✅ 通過 / ❌ 卡關（附原因）

接續的 session 只需要讀 A–E 這五節，以及狀態表中「🔄 進行中」那一階段的章節。

---

## 0. 背景與已知事實（2026-10-09 實測，INTC 現價 ≈ $106.76）

| # | 觀察 | 來源 |
|---|---|---|
| F1 | `/leaps?symbol=INTC&user_strike=80` 顯示「這個履約價 80（含緩衝檔）在所有到期日都沒有符合 Delta ≥ 0.60 的候選」 | 頁面警告文字 |
| F2 | 同一頁 Options Flow 有 $80C 2028-12-15，Delta 0.802、0.804，大單成交約 $51–52/股 | Options Flow 表 |
| F3 | POI 圖標示 `80.00 履約 · OI 104625` | POI 卡 |
| F4 | 不填履約價（自動）時，候選排行**只有 $100 和 $105 兩個履約價**。$95/$90/$85/$80 等 Delta ≥ 0.60 的深度價內履約價全部沒出現 | LEAPS 候選排行表 |
| F5 | PMCC 建倉規範寫「Long Delta ≥ 0.80」，但 PMCC 黃金法則組合表的 Long Δ 是 0.671–0.732，**規則沒有被程式落實** | PMCC 區塊 |
| F6 | 先前修過 NOK $7 的同類 bug（把有窗口限制的 snapshot 誤當成完整期權鏈）。本次可能是**回歸**，也可能是**同一根因的另一條路徑** | 歷史紀錄 |
| F7 | 查詢是非同步流程：`POST /leaps/analyze` → 輪詢 `GET /leaps/status?job_id=…` → 跳轉到 `GET /leaps?symbol=…&job_status=success` 渲染結果 | 瀏覽器 network 紀錄 |
| F8 | v20261002 起，同一個 symbol + 同一個 strike 的查詢會共用結果（有快取）。修好之後，舊快取可能讓頁面繼續顯示錯誤結果 | 版本更新說明 |
| F9 | PMCC 說明卡範例「INTC $105→$190」「LEAPS 成本 $3,203」用的是 $105 腳（Δ 0.671），也違反 Long Δ ≥ 0.80 | PMCC 說明卡 |

**Delta 方向提醒**：Call 的履約價越低（越價內），Delta 越高、越接近 1。「Delta ≥ 0.60 的區域」是**從某個履約價往下一直到期權鏈底部**。

**根因假設（P0 必須證實或推翻，不准直接照假設改）**：抓取或篩選只取現價附近的窗口（±N 檔，或只取現價上下各一檔「緩衝檔」），沒有往下（更價內）延伸到 Delta 更高的履約價。另一種可能是有抓到，但候選數量上限或排序截斷把它們擠掉了。F1 和 F4 疑似同一個病，F5/F9 是另一個獨立問題。

**P0 根因結論（2026-10-09 實查，證據見本檔「附錄 P0」）**

- **B1／F4：假設證實（是窗口問題）**。但窗口不是「±N 檔」，而是「近月到期日的 `?moneyness=10` 視圖」。Stage 1 只從這張表（近月、現價附近）挑 Δ ≥ 0.60 的履約價，再上下各加一檔緩衝。INTC 當天的近月表是 $97–$107（每 $1 一檔），挑出 97–107 共 11 檔。其中只有 $100、$105 在 LEAPS 到期日有掛牌，所以排行只剩這兩檔。$80–$95 從來沒有送進 Stage 2。LEAPS 排行**沒有** top-N 截斷；PMCC 的 LEAPS 腳有 `TOP_LEAPS_PER_GROUP=3`，留給 P4 處理。
- **B2／F1：假設推翻**。$80 其實有抓到：19:39 的 `user_strike=80` job 成功，rows=27；22:21 重新實跑，$80 在 5 個 LEAPS 到期日都有 Δ 0.789–0.801 的候選，頁面沒有警告（附錄 P0「E2E 實測」）。F1 的警告是 21:42:48（登入後）重新開啟**兩小時前**的 `…&job_status=success&user_strike=80` 網址造成的。當時資料已超過 `FRESH_WINDOW`（1 小時），21:43 的 auto 查詢又整批覆蓋了 INTC 快照。controller 把「job_status=success 但資料不新鮮」一律歸為 `:no_candidates`，畫面才顯示「含緩衝檔…沒有 Delta ≥ 0.60」。這是**誤導性訊息**，不是 Delta 判斷錯。
- **F6（NOK）**：兩個修正都還在（`_pick_candidates` 的缺 Greeks 回退；chain_snapshot 改讀 LEAPS 到期日的完整履約價鏈）。本次不是回歸。
- **F5／F9**：`LEAPS_DELTA_OK_MIN = 0.80` 只用來標記 ✅/⚠️。這是原本 PMCC v3 §2.3 刻意的「僅標記、不淘汰」。說明卡範例挑的是「第一個通過黃金法則的組合」，不看 Long Δ。

## 1. 硬性限制（每階段都適用）

1. Barchart 資料**只能**用 Playwright/CDP 解析 DOM 取得。**絕對禁止**呼叫 Barchart 內部 API 或任何 Barchart API（沒有付費訂閱）。修正時不准用「改打 API 拿完整期權鏈」來繞過。
2. repo 內的規格檔是唯一真相。要改規格就先改本檔（用 patch），再改程式。
3. 「完成」要有端到端證據：實際導覽的 URL、DOM 擷取值、截圖。只拿測試數量（例如「38/38 綠燈」）不算完成。
4. **核心用例優先**：(a) 不填履約價的預設查詢；(b) `user_strike=80`。兩者都要實跑過。只測了帶參數的情境，不算通過。
5. 不准調低 Delta 0.60 門檻，也不准用硬編碼 INTC/80 這類方式讓測試通過。
6. 開新分支 `fix/leaps-deep-itm`。每通過一階段 commit 一次，commit 訊息開頭寫階段編號（例如 `P2: …`）。
7. 每一階段的驗證貼出後，先交給右側 tmux 的審查官 session 檢查（回覆前綴「異端審查官表示:」）。審查官提出的質詢要逐條回應；經使用者同意後才可以修改，然後才能把狀態表標 ✅。
8. 不准為了 E2E 測試而在正式環境關閉或繞過 Google OAuth / TOTP，也不准新增任何在 production 生效的後門登入。

---

## P0 重現 + 定位根因

**動作**
1. 用以下指令找出相關程式。路徑以搜尋結果為準，**不准憑檔名猜**：
   ```
   grep -rn "含緩衝檔" app lib config
   grep -rn "user_strike" app lib config
   grep -rn "Delta ≥ 0.60\|0\.6\b\|0\.60" app/services app/controllers lib/barchart_scrapers
   grep -rn "Long Delta\|0\.80\|0\.8\b" app/services/pmcc_ranking_service.rb app/components/leaps_recommendations/
   ```
   已知的進入點：`LeapsRecommendationsController#index`（route `/leaps`）、`app/services/pmcc_ranking_service.rb`、`app/components/leaps_recommendations/pmcc_section.rb`、`lib/barchart_scrapers/`。
2. 在 `docs/` 或本檔附錄寫一張**資料流表**：Barchart DOM → scraper（檔案:函式）→ 寫入哪個資料表 → 哪個 service 篩選 → controller → component。每一格都要標明「檔案:行號」。
3. 對 INTC 跑一次預設查詢，然後查 DB：最新一批 INTC LEAPS snapshot 實際存了哪些履約價、哪些到期日。
4. 回答下面三題，每題都要附程式碼行號：
   - Q1 為什麼自動模式只抓到 $100/$105？窗口是怎麼決定的（±N 檔？以現價為中心？上限幾檔？）
   - Q2 `user_strike=80` 的「緩衝檔」邏輯為什麼判定無候選？是 80 根本沒被抓到，還是有抓到但被篩掉？
   - Q3 F6 的 NOK 修正還在不在？這次是回歸，還是另一條路徑？
   - Q4 候選表有沒有數量上限、或依 OI 排序後截斷（top-N）？如果有，上限是多少，寫在哪裡？
   - Q5 F8 的快取：key 由哪些欄位組成？存在哪裡（DB 表、Rails.cache、記憶體）？TTL 多久？要怎麼針對單一 symbol 清除？

**驗證（全部滿足才算通過）**
- [ ] 資料流表每一格都有「檔案:行號」
- [ ] 貼出 DB 查詢**原文**和輸出，證明 snapshot 裡有或沒有 strike 80/85/90/95
- [ ] Q1–Q5 都有答案，而且附上可重跑的指令或程式片段當證據
- [ ] 根因假設標記為「證實」或「推翻」。推翻的話，要寫出新的根因並 patch 本檔第 0 節

---

## P1 失敗測試先行

**動作**：依 P0 證實的根因，先寫測試，而且這些測試**現在必須失敗**：
- T1（**scraper 候選挑選**，`lib/barchart_scrapers/test_leaps_scraper.py`）：fixture 是近月窗口（現價 106.76，$97–$107 每 $1 一檔）加上一條 LEAPS 到期日的完整期權鏈（履約價 70–130，每 5 一檔，Delta 依價內程度遞減，$80 ≈ 0.80，$70 > 0.95）。在 auto 模式跑 `main()`，預期：LEAPS 鏈上所有 0.60 ≤ Δ ≤ 0.95 的履約價都要送進 Stage 2（`?view=stacked&strike=X`），至少包含 80/85/90/95/100/105。
  - 2026-10-09 依 P0 改寫：原本寫的是「篩選/排名 service 單元測試」，但 P0 證實 `LeapsRankingService` 不截斷，DB 裡有的列都會列出。根因在 scraper 只從近月窗口挑候選，所以 T1 放在 scraper 層。
- T2（**資料不新鮮的訊息**，request spec）：`job_status=success&user_strike=80`，但資料不新鮮（`fresh_for?` 為 false）時，body 不得出現「含緩衝檔）在所有到期日都沒有符合」，要出現「已不是最新」的訊息。
  - 2026-10-09 依 P0 改寫：P0 證實新鮮查詢 80 本來就有候選，F1 來自這條路徑。
- T3（PMCC）：Long 腳 Delta < 0.80 的組合不得出現在通過清單，也不得被說明卡範例選用。
- T4（scraper 窗口）：**不適用**。P0 證實 DOM 解析層已經抓到完整履約價鏈（`strike_chain_snapshots` 有 63 檔，含 80–95），問題在挑選層，已由 T1 涵蓋。

**驗證**
- [ ] `bundle exec rspec <T2、T3 檔案>` 與 `pytest <T1 檔案>` 輸出顯示**失敗**，而且失敗原因符合根因（不是語法錯或 fixture 錯）。貼出輸出原文
- [ ] fixture 不准硬編 INTC 專屬邏輯

---

## P2 修正履約價涵蓋範圍

**動作**：照 P0 的根因修抓取、篩選窗口或截斷上限。規則如下：
- 涵蓋範圍：以**第一個 DTE ≥ 364 的 LEAPS 到期日**的完整鏈為準，所有 `0.60 ≤ Delta ≤ LEAPS_MAX_DELTA` 的履約價，加上上下各一檔緩衝，都要進入候選。（2026-10-09 P2 r1 使用者裁示 (b)：原文為「每個到期日」。遠月 Δ 曲線較平，邊界外 Δ 0.60–0.66 或 0.89–0.90 的少數檔可能漏掉；若要涵蓋所有到期日，估計耗時 2.4–2.6 倍，超過 2 倍上限。）`LEAPS_MAX_DELTA` 預設 0.95，放在設定常數裡，用來避免抓取一路延伸到 Delta≈1 的極深價內。往上（價外方向）以 Delta 跌破 0.60 為界。
- 如果根因是 top-N 截斷：要確保至少每個到期日都有 Δ ≥ 0.80 的履約價（只要期權鏈裡存在）進入候選，不能全被 OI 較高的 Δ 0.6–0.7 擠掉。
- 如果是抓取層：還是只能用 DOM 解析。真的需要多抓一段，就要在 Barchart 頁面的 DOM 上操作（例如切換 strike 範圍的選單），不准打 API。
- 抓取量增加的話，要記錄每次查詢多花的秒數。如果超過現行耗時 2 倍，就停下來回報，不准自行決定。

**驗證**
- [ ] T1（和 T4）轉綠
- [ ] 實跑 INTC 預設查詢後，查 DB 確認 snapshot 有 80、85、90、95。貼出查詢和輸出
- [ ] 記錄修正前後的查詢耗時（秒）
- [ ] 依 P0 Q5 的結論，清除 INTC、NOK 的舊快取或舊 snapshot。貼出清除指令，以及清除後查詢的結果（確認快取裡已經沒有舊資料）
- [ ] 如果快取 key 不含「抓取邏輯版本」：在 key 加入版本欄位，或在部署時清空 LEAPS 快取，二擇一並寫明。目的是確保之後改抓取範圍時，不會再讀到舊結果

**P2 實作決定（2026-10-09）**
- P2 r1 使用者裁示：(1) 候選以第一個 LEAPS 到期日為準（見上方涵蓋範圍）；(2) 從 LEAPS 鏈挑時，「缺 Greeks 回退」不得低於「有算出 Δ 且落在區間內」的最低履約價（`_pick_candidates(from_leaps_chain=True)`），近月窗口的回退行為不變；(3) 耗時 143 秒（基準 72–74 秒的 1.93–1.99 倍）接受。
- `LEAPS_MAX_DELTA` 由 0.95 改為 **0.90**（使用者裁示）。實測 0.95：INTC 第一個 LEAPS 到期日（2027-12-17，DTE 434）的 Δ 曲線很平，0.60–0.95 從 $42 一路涵蓋到 $115，加上緩衝共 29 檔，LEAPS 抓取 174 秒，是基準 74 秒的 2.35 倍，超過上方「2 倍停下回報」的上限。證據：`tmp/e2e/leaps-deep-itm/P2/sql-leaps-exp-deltas.txt`、`dom-auto.json`（0.95 那一輪）。上方涵蓋範圍規則中的「預設 0.95」以本條為準。
- 候選來源：auto 模式改從 Stage 1 已讀到的 LEAPS 到期日完整鏈（`?moneyness=100&expiration=<第一個 DTE ≥ 364>`）挑 `LEAPS_MIN_DELTA ≤ Δ ≤ LEAPS_MAX_DELTA` 的履約價，±1 緩衝與缺 Greeks 回退維持原樣。沒有 LEAPS 到期日時才退回近月窗口。user_strike 模式不變（P3 範圍）。**導航順序與次數不變**，沒有多抓頁面。
- B5 採「部署時清空」，不在 key 加版本。理由：
  1. 「共用結果」只在 DB 快照，TTL 只有 1 小時（`FRESH_WINDOW`）。
  2. Rails.cache 的 `leaps_job_<id>` 只存 job 狀態、不存結果，index 一律再經 `fresh_for?` 判斷，舊 job 狀態不會帶出舊候選。
  3. 加版本欄位需要 migration 或改動 `fresh_for?` 的語意，超出本次範圍。

  **部署步驟**：改了 `leaps_scraper.py` 的挑選邏輯後，執行 `DELETE FROM leaps_option_chain_snapshots WHERE symbol IN (…)`（或不帶條件清全部）。Python sidecar 每次查詢都重新啟動，不需要 `pm2 restart`。

---

## P3 修正 user_strike 驗證

**動作**（2026-10-09 依 P0 結論改寫；P0 證實 user_strike 的 Delta 判斷本身沒錯，F1 來自 controller 把「job 成功但資料不新鮮」當成無候選）：
- `job_status=success`（或 cached）但 `fresh_for?` 為 false：顯示「這筆查詢結果已不是最新（超過 1 小時，或已被其他查詢取代），請重新按查詢」，**不**顯示 Delta 不足警告。使用者裁示：只顯示訊息，不自動重抓。時間數字從 `LeapsOptionChainSnapshot::FRESH_WINDOW` 讀取，不准寫死。
- 履約價存在、而且至少一個到期日的 Delta ≥ 0.60：列出候選（現況已正確，維持）
- 履約價存在、但所有到期日 Delta 都 < 0.60：維持現有警告
- 履約價根本不存在於期權鏈：顯示另一則訊息「期權鏈無此履約價」，不能和「Delta 不足」混用
- 既有測試「success 不再顯示未知錯誤」（`spec/requests/leaps_recommendations_spec.rb`）目前期望 auto 模式「success 但不新鮮」時顯示「沒有符合篩選條件的候選」。這條期望與本節新規則衝突，P3 要一併改成新訊息（依使用者裁示，屬於測試本身要更新，不是為了讓測試通過而改）。

**驗證**
- [ ] T2 轉綠
- [ ] 新增 T2b：不存在的履約價（從 fixture 取兩檔之間的值，例如 fixture 每 5 一檔時用 81）會得到「期權鏈無此履約價」訊息
- [ ] 新增 T2c：存在但 Delta 不足的履約價（fixture 中 Delta < 0.60 的一檔，例如 125）會得到原本的 Delta 警告
- [ ] NOK $7 的舊測試仍然綠燈（貼出測試名稱和輸出）

---

## P4 PMCC Long Δ ≥ 0.80 落實

**動作**：
- `pmcc_ranking_service.rb`：Long 腳候選加上 `delta >= 0.80` 篩選。門檻放進既有的設定常數，不准散落成魔術數字。
- LEAPS 候選排行（Delta ≥ 0.60）**維持原樣**，不受這條影響。
- PMCC 區塊的「總組合 X / 通過 Y」計數要反映新的篩選。如果某檔標的沒有 Δ ≥ 0.80 的 Long 腳，要顯示「無符合 Long Δ ≥ 0.80 的 LEAPS」，不能顯示空表。
- 建倉規範卡上寫的數字，要從同一個常數讀取，不准寫死，避免文字和邏輯再次不一致。
- PMCC 說明卡的範例（黃金法則驗算、最大獲利範例、「LEAPS 成本」「資金比例」）要改從 Δ ≥ 0.80 的 Long 腳中選取（F9）。
- Short 腳規則（Δ 0.20–0.35、DTE 19–45）本次不改，但要確認現有程式**有**落實。如果沒有，在狀態表記為「另案」，不在本次修。

**驗證**
- [ ] T3 轉綠
- [ ] `grep -rn "0\.80\|0\.8\b" app/components/leaps_recommendations/ app/services/pmcc_ranking_service.rb`：除了常數定義以外，沒有寫死的 0.80
- [ ] 新增測試 T3b：沒有任何 Δ ≥ 0.80 候選時，會顯示指定的訊息
- [ ] 新增測試 T3c：說明卡範例選用的 Long 腳 Δ ≥ 0.80

---

## P5 Request spec 全路徑

**動作**：新增或擴充 request spec，走完 F7 的完整非同步流程，兩種情境都要（預設查詢、`user_strike=80`）：
1. `POST /leaps/analyze`（帶 CSRF / 已登入的 session）→ 取得 job_id
2. 執行 job（測試中用 `perform_enqueued_jobs` 或等效方式，**不准**跳過 job 直接塞 DB）
3. `GET /leaps/status?job_id=…` → 斷言 status 為 success
4. `GET /leaps?symbol=INTC[&user_strike=80]&job_status=success` → 斷言 render 結果

Barchart 抓取在 sidecar 邊界用 fixture 替換，**不准 mock 掉 service 本身**。登入用 test 環境既有的 session helper；沒有的話，新增一個只在 `Rails.env.test?` 生效的 helper。

**驗證**
- [ ] request spec 綠燈，四個步驟都有斷言。最後的 response body 斷言：
  - 預設查詢的候選表含 `80.00`（或 fixture 對應值）
  - `user_strike=80` 的 body **不含**「含緩衝檔）在所有到期日都沒有符合」
  - PMCC 區塊所有 Long Δ ≥ 0.80
- [ ] 貼出 `bundle exec rspec spec/requests/<檔名>` 輸出原文

---

## P6 E2E 實測 + 交叉比對

**動作**：在本機正式環境（port 3003）用 Playwright 實跑。
- 登入方式：透過 CDP（cdp-relay，port 9223）連到使用者已經登入 FairPrice 的 Windows Chrome，在新分頁操作。如果使用者 Chrome 沒有登入，就停下來請使用者登入，**不准自行處理 OAuth/TOTP**（硬性限制 8）。
- 每頁都要從空白的輸入框實際按「查詢」，觸發 F7 的完整流程。不准直接開 `job_status=success` 的網址（那會讀到快取，見 F8）。

1. `/leaps?symbol=INTC`（預設，**核心用例，必跑**）
2. `/leaps?symbol=INTC&user_strike=80`
3. `/leaps?symbol=NOK&user_strike=7`（回歸）

每一頁都要記錄：實際導覽的 URL（含 `job_status=success`）、截圖路徑，以及從 DOM 擷取下表欄位的 JSON。

**交叉比對基準**（2026-10-09 的實測值；市場會變動，所以比對的是「存在性 + 合理區間」，不是精確值）

| 檢查項 | 期望 |
|---|---|
| INTC 候選表含 strike 80 | 有 |
| $80C 2028-12-15 Delta | 0.75–0.88 |
| $80C 2028-12-15 報價 | Bid ≤ Mid ≤ Ask，而且 Mid ≥ 內在價值（現價 − 80） |
| $80C 2028-12-15 內在價值欄 | 等於（頁面現價 − 80），誤差 ±0.02 |
| INTC 候選表的最低履約價 | ≤ 85 |
| PMCC 通過組合的 Long Δ 最小值 | ≥ 0.80 |
| user_strike=80 頁面 | 沒有「沒有符合 Delta ≥ 0.60」警告 |
| NOK user_strike=7 | 仍有候選 |

**驗證**
- [ ] 三頁的 DOM JSON 和截圖都存進 repo 的 `tmp/e2e/leaps-deep-itm/`（路徑寫進狀態表）
- [ ] 上表 8 項逐項標 ✅/❌，**全部 ✅** 才算通過
- [ ] 如果 2028-12-15 這個到期日已經不在 Barchart 的清單（日期變動），改用 DTE 最接近 799 的到期日，並在報告註明
- [ ] 如果有任何一項 ❌，退回 P2–P4 中對應的階段，並在狀態表註明原因

---

## P7 回歸 + 結案報告

**動作 / 驗證**
- [ ] `bundle exec rspec` 全套綠燈（貼出總結那一行）
- [ ] `pytest lib/barchart_scrapers` 全套綠燈
- [ ] `git diff main...fix/leaps-deep-itm | grep -nE '^\+.*(proxies|/api/|fetch\(|requests\.(get|post)|httpx|urllib)'` 輸出為空，證明這次修改沒有新增任何 API 呼叫。貼出指令和輸出原文
- [ ] 結案報告依序回答：
  1. 核心用例（預設查詢，不帶參數）有沒有端到端跑過？附 URL 和截圖
  2. 根因是什麼（引用 P0 的結論）
  3. 修改了哪些檔案（附 `git diff --stat`）
  4. 查詢耗時變化
  5. 有沒有尚未解決或刻意延後的問題

狀態表 P0–P7 全部 ✅ 才能宣告完成。

---

## 附錄 P0：資料流與證據（2026-10-09，BASE e711fd5）

### 資料流表

| # | 層 | 檔案:行號 | 做什麼 |
|---|---|---|---|
| 1 | 前端送出 | `app/controllers/leaps_recommendations_controller.rb:122` `analyze` | 驗證 user_strike；`:137-145` 用 StrikeChainSnapshot 擋範圍外的履約價；`:147` 資料新鮮就回 ready；`:156` 排 job |
| 2 | Job | `app/jobs/scrape_leaps_job.rb:55` `scrape_and_record` | 呼叫 `fetch_leaps`；`:58-66` cached 與 success 都寫成 success；`:72` 寫入 `leaps_job_<id>`（Rails.cache） |
| 3 | Service → sidecar | `app/services/barchart_scraper_service.rb:78` `fetch_leaps` | `:90` 用 fresh_for? 短路；`:96` 執行 `leaps_scraper.py SYMBOL [STRIKE]` |
| 4 | Barchart DOM Stage 1 | `lib/barchart_scrapers/leaps_scraper.py:360` | 導覽到 `?moneyness=10`（**近月到期日、現價附近**）；`:56` 用 `NEAR_MONEY_JS` 讀 grid 的 strike 與 delta |
| 5 | 完整履約價鏈 | `leaps_scraper.py:419` | 導覽到第一個 DTE ≥ 364 到期日的 `?moneyness=100`，取得完整鏈。只用於 chain_snapshot 與 user_strike 範圍驗證，**不用於挑候選** |
| 6 | 挑候選（**B1 根因**） | `leaps_scraper.py:195` `_pick_candidates`、`:228` `_qualifies`、`:251` ±1 緩衝 | 只在第 4 步的近月窗口內挑 Δ ≥ 0.60，再上下各加一檔 |
| 7 | Stage 2 | `leaps_scraper.py:471` 迴圈、`:476` `?view=stacked&strike=X` | 每個候選履約價抓所有到期日。如果這個履約價沒有 LEAPS 到期日，就只會拿到近月的列 |
| 8 | 寫入 DB | `barchart_scraper_service.rb:652` `persist_leaps`、`:702-703` | `leaps_option_chain_snapshots`：**整個 symbol 先刪後插**。`:779/794` upsert `strike_chain_snapshots`（含 `last_query_strike`） |
| 9 | 新鮮度判斷（**B5 快取**） | `app/models/leaps_option_chain_snapshot.rb:7` `FRESH_WINDOW = 1.hour`、`:22` `fresh_for?` | scraped_at 在一小時內，**而且** `last_query_strike` 等於這次的 user_strike |
| 10 | 排名篩選 | `app/services/leaps_ranking_service.rb:33-47` | 只取最新一批、`dte >= 364`、`delta >= 0.60`、外在價值 ≥ 0；`:24-26` 只排序、不截斷 |
| 11 | Controller render（**B2 訊息根因**） | `leaps_recommendations_controller.rb:24` 資料新鮮才讀排名；`:74-87` job_status=success 但不新鮮 → `:no_candidates` | |
| 12 | Component | `app/components/leaps_recommendations/page_header.rb:104-106` | `:no_candidates` 加上 user_strike → 顯示「含緩衝檔…沒有 Delta ≥ 0.60」 |
| 13 | PMCC | `app/services/pmcc_ranking_service.rb:23` `LEAPS_DELTA_OK_MIN`（只標記）、`:82-95` LEAPS 腳取 OI 前 3、`:203` `leaps_delta_ok` | |
| 14 | PMCC 說明卡 | `app/components/leaps_recommendations/pmcc_education.rb:14-18` `pmcc_edu_pick`、`:86` 寫死「Long Delta ≥ 0.80」 | |

### DB 證據（21:43 auto 查詢之後）

```
$ source .env; psql "$DATABASE_URL" -c "SELECT strike, count(*) n, min(expiration_date) min_exp, max(expiration_date) max_exp, round(min(delta)::numeric,3) min_d, round(max(delta)::numeric,3) max_d, max(scraped_at) scraped FROM leaps_option_chain_snapshots WHERE symbol='INTC' GROUP BY strike ORDER BY strike;"
strike	n	min_exp	max_exp	min_d	max_d	scraped
97.0000	6	2026-10-09	2026-10-30	0.748	0.951	2026-10-09 13:44:42.897773
98.0000	6	2026-10-09	2026-10-30	0.729	0.947	2026-10-09 13:44:42.897773
99.0000	9	2026-10-09	2026-11-27	0.682	0.943	2026-10-09 13:44:42.897773
100.0000	22	2026-10-09	2029-01-19	0.657	0.930	2026-10-09 13:44:42.897773
101.0000	9	2026-10-09	2026-11-27	0.651	0.908	2026-10-09 13:44:42.897773
102.0000	9	2026-10-09	2026-11-27	0.635	0.883	2026-10-09 13:44:42.897773
103.0000	9	2026-10-09	2026-11-27	0.619	0.841	2026-10-09 13:44:42.897773
104.0000	9	2026-10-09	2026-11-27	0.603	0.785	2026-10-09 13:44:42.897773
105.0000	22	2026-10-09	2029-01-19	0.584	0.718	2026-10-09 13:44:42.897773
106.0000	9	2026-10-09	2026-11-27	0.562	0.618	2026-10-09 13:44:42.897773
107.0000	9	2026-10-09	2026-11-27	0.516	0.556	2026-10-09 13:44:42.897773
```

→ snapshot **沒有** 80、85、90、95。只有 100、105 有 LEAPS 到期日的列。

```
$ psql "$DATABASE_URL" -c "SELECT symbol, last_query_strike, spot_price, scraped_at, jsonb_array_length(strikes) n, strikes FROM strike_chain_snapshots WHERE symbol IN ('INTC','NOK');"
INTC		106.7600	2026-10-09 13:44:42.673273	63	[3.0, 5.0, 10.0, 13.0, 15.0, 18.0, 20.0, 22.0, 25.0, 27.0, 30.0, 32.0, 35.0, 37.0, 40.0, 42.0, 45.0, 47.0, 50.0, 52.5, 55.0, 57.5, 60.0, 62.5, 65.0, 67.5, 70.0, 72.5, 75.0, 77.5, 80.0, 82.5, 85.0, 87.5, 90.0, 92.5, 95.0, 97.5, 100.0, 105.0, 110.0, …, 240.0]
NOK		10.2900	2026-10-01 14:51:58.45826	16	[1.0, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0, 12.0, 15.0, 17.0, 20.0, 22.0, 25.0, 27.0, 30.0, 32.0]
```

→ 完整的 LEAPS 履約價鏈**已經抓到**（含 80–95），只是沒有拿來挑候選。

### 時間軸證據

來源：`~/.pm2/logs/fairprice-rails-out.log`（時間為 +0800）、`fetch_logs`（時間為 UTC，下表已換成台北時間）。

```
19:39:15 POST /leaps/analyze                         → ScrapeLeapsJob("INTC", "0276abd9a16839c6", {user_strike: 80.0})
19:39:51 fetch_logs#1100 leaps success rows=27       （user_strike=80 這一輪，$80 有抓到）
19:40:54 GET /leaps?symbol=INTC&job_status=success&user_strike=80
21:42:01 GET /leaps?job_status=success&symbol=INTC&user_strike=80（34.162.191.81）→ 302 /login（enforce_auth_gate），未渲染
21:42:24 GET /leaps?symbol=INTC&job_status=success&user_strike=80 → 302 /login（enforce_auth_gate），未渲染
21:42:48 GET 同上 → 200（登入後）：兩小時前的舊網址、資料不新鮮 → :no_candidates → 顯示 F1 警告
21:43:31 POST /leaps/analyze                         → ScrapeLeapsJob("INTC", "4e5a103ce1bbc550", {user_strike: nil})
21:44:43 fetch_logs#1108 leaps success rows=119      （auto；job 開始到 leaps 完成約 72 秒，作為 P2 的耗時基準）
21:45:53 GET /leaps?symbol=INTC&job_status=success   （F4：只有 100/105）
```

### E2E 實測（P0 r2，2026-10-09 22:21–22:28 台北時間，Playwright 9224，從空白輸入框按「查詢」）

證據目錄：`tmp/e2e/leaps-deep-itm/P0/`

**1. `user_strike=80`**（22:21:18 POST /leaps/analyze → job `{user_strike: 80.0}` → fetch_logs#1110 leaps success rows=28 → 22:22:54 跳轉）

- URL：`http://localhost:3003/leaps?symbol=INTC&job_status=success&user_strike=80`
- DB（`sql-user_strike-80.txt`）：快照只有 80（22 列，到 2029-01-19）和 97（6 列，到 2026-10-30），`last_query_strike = 80`
  ```
  SELECT strike, expiration_date, dte, delta, extrinsic_value FROM leaps_option_chain_snapshots WHERE symbol='INTC' AND strike=80 AND dte>=364 ORDER BY expiration_date;
  80  2027-12-17  434  0.789012  15.8050
  80  2028-01-21  469  0.789279  16.5550
  80  2028-06-16  616  0.791523  21.1300
  80  2028-12-15  798  0.799921  25.1300
  80  2029-01-19  833  0.801236  25.7800
  ```
  五列都符合 `leaps_ranking_service.rb:41-46`（dte ≥ 364、Δ ≥ 0.60、外在價值 ≥ 0）。
- DOM（`dom-user_strike-80.json`）：候選表 5 列，全部是「80.00 ★ 你查詢的履約價」，Δ 0.7890–0.8012；`warning_present: false`
- 截圖：`user_strike-80.png`

→ **B2 推翻有直接證據**：新鮮查詢 80 會有候選。F1 只出現在資料過期的舊網址上。

**2. auto（不填履約價，核心用例）**（22:25:49 POST → job `{user_strike: nil}` → fetch_logs#1112 leaps success rows=110，job 開始到 leaps 完成 74 秒 → 22:28:22 跳轉）

- URL：`http://localhost:3003/leaps?symbol=INTC&job_status=success`
- DB（`sql-auto.txt`）：快照 97–106 共 10 檔，只有 100、105 延伸到 2029-01-19
- DOM（`dom-auto.json`）：候選表 10 列，`distinct_strikes: [100, 105]`，`min_strike: 100`
- 截圖：`auto.png`（只截到可視範圍；整頁截圖逾時）

→ **B1 重現**。同一輪 fetch_logs#1113 pmcc_short `partial_error`（`expired_at=2026-10-12 layer=volatility_greeks reason=page_load_timeout`），與本規格無關，只記錄。

### Q1–Q5

- **Q1**：窗口是近月到期日 `?moneyness=10` 的 grid（`leaps_scraper.py:360`），以現價為中心，寬度由 Barchart 決定（INTC 當天是 97–107），沒有檔數上限。`_pick_candidates`（`:195-264`）在這個窗口內取 Δ ≥ 0.60，再加 ±1 緩衝。候選只能從這個近月窗口裡挑；窗口裡除了 100、105 以外的履約價（97–99、101–104、106–107）在 LEAPS 到期日根本沒有掛牌（DB 中 max_exp ≤ 2026-11-27），所以最後只剩 100、105。落選和 Δ 高低無關，是窗口本身不在 LEAPS 鏈上。
- **Q2**：$80 有抓到（user_strike 模式直接用 80 當中心點，`:226`）。F1 是 controller `:74-87` 把「job 成功但資料不新鮮」當成 no_candidates 造成的誤導訊息，見時間軸。
- **Q3**：NOK 的兩個修正都還在：`leaps_scraper.py:228-243` 的缺 Greeks 回退，以及 `:391-433` 改讀 LEAPS 到期日的完整鏈（commit e361f6f）。不是回歸。
- **Q4**：`LeapsRankingService#call`（`:17-27`）只排序、不截斷，ranking table 也沒有 `.first`。PMCC 有截斷：`pmcc_ranking_service.rb:89,92` 的 LEAPS 腳近月、遠月各取 OI 前 3（`TOP_LEAPS_PER_GROUP = 3`），`:50` 每桶組合取前 5。
- **Q5**：「共用結果」有兩層。
  1. **DB**：`leaps_option_chain_snapshots` 加上 `strike_chain_snapshots.last_query_strike`。key 是 (symbol, user_strike)，TTL 是 `FRESH_WINDOW` 1 小時（`leaps_option_chain_snapshot.rb:7,22`）。清除單一 symbol：`LeapsOptionChainSnapshot.where(symbol: "INTC").delete_all`。
  2. **Rails.cache**：key 有 `leaps_job_<id>`、`leaps_last_errors_<SYM>`（1 小時），以及 `leaps_inflight_<SYM>_<strike>`（30 分鐘，`scrape_leaps_job.rb:11,15`）。
     - **2026-10-09 P3 更正**：原本寫「pm2 以 development 執行、`memory_store`、`rails runner` 清不到、只能 `pm2 restart`」是錯的。pm2 的環境變數雖然是 development，但 `bin/start-rails.sh:7` 寫死了 `export RAILS_ENV=production`，所以 server 實際以 production 模式執行。`config/environments/production.rb:68` 的 `cache_store` 被註解掉，Rails 預設改用 `file_store`（`tmp/cache/`），存在磁碟上：`pm2 restart` 清不掉，`rails runner` 或 `Rails.cache.delete` 清得到。production 也不會自動重新載入 Ruby 程式碼，改了 Ruby 要重啟才會生效。
     - B5 的結論不受影響：這一層只存 job 狀態與錯誤訊息，不存候選結果。

  兩層的 key 都**不含**抓取邏輯版本。

# 投資名人堂（Hall of Fame）規格 v1

> Loop Engineering：依序執行；每階段驗證全過才可進下一階段；驗證未過 → 修到過，禁止跳階。
> 每完成一階段驗證，立即 patch 更新下方狀態表（只改該列）。接續 session 只讀狀態表＋「進行中」階段章節。
> 本檔為唯一真相來源；規格變更一律 patch，不整檔重寫。

## 執行狀態表

| 階段 | 名稱 | 狀態 | 審查 | 證據（指令輸出摘要／截圖路徑） | 完成時間 |
|---|---|---|---|---|---|
| P0 | 現況盤點與決策 | 完成 | r1 PASS | 路由：頁面 `/hall_of_fame`（與 `/ownership` 同層）、API `api/v1/hall_of_fame/*`，`TICKER_CONSTRAINT` 在 `config/routes.rb:3`。React 模式：`entrypoints/ownership.tsx` 掛 `#ownership-root`，controller render Phlex `Ownership::PageComponent` 只輸出 root div；layout `application.html.erb:78-96` 依 controller_name 掛 entrypoint（→ §1-0 增列 layout）。sidebar：`app/components/fair_value/app_switcher_component.rb:4-21` `APP_LINKS`，第 88 行分隔線在倒數第二項後，加在最末位會讓分隔線改在名人堂前。pm2 TZ=UTC（`/proc/<pid>/environ`）。psql：`.env` `DATABASE_URL` → fairprice_production、user mygame。curl：2026FD.zip `HTTP/2 200` `application/x-zip-compressed`；20004433.pdf `HTTP/2 200` `application/pdf`。ZIP 含 `2026FD.xml`，`<Member>` 1782。差異：pdfplumber 未安裝、repo 無 venv／requirements（P3 處理）。 | 2026-10-17 |
| P1 | Schema | 完成 | r1 PASS | migrate 至 fairprice_production，6 張 hof_ 表；rollback STEP=1 → migrate 來回成功；seed 兩次皆 11；model／seeder spec 27 examples 0 failures；完整 rspec 1428 passed／1 failed（technical_dashboards_spec:24，既有時段性失敗，TZ=UTC 重跑 9 passed）。差異：hof_sync_runs 加 http_validators（§1-10）；交易 model 名 HallOfFame::Trade。 | 2026-10-17 |
| P2 | House 索引同步 | 完成 | r1 PASS | `hall_of_fame:sync_house_index` 首跑 run#1 新增 87、錯誤 0（crenshaw 1／gottheimer 23／khanna 22／mccaul 20／pelosi 8／shreve 13；StateDst 全符，yml 未改）；重跑 run#2 新增 0、兩年皆 304，hof_filings 仍 87；隨機 3 筆 pdf_url 皆 HTTP/2 200 application/pdf。House IIS 需同時帶 If-None-Match＋If-Modified-Since 才回 304。spec 13 examples 0 failures；完整 rspec 1441 passed／1 failed（timed_capture_spec:27 負載偶發，單獨重跑 3 次皆過）。解壓用系統 unzip（rubyzip 僅 test 群組）。 | 2026-10-17 |
| P3 | House PDF 解析 | 完成 | r2 PASS | `hall_of_fame:parse_house_pdfs` 全量 87 份：parsed 44（ptr 42、annual 2）、needs_review 43、failed 0、pending 0；hof_transactions 1246、hof_holdings 779。needs_review：42 份掃描檔（文字層 0 字，Khanna PTR 21＋年報、McCaul PTR 19＋年報，皆 8/9 開頭紙本申報）、10075701 第 59 列 `Undetermined`。自洽檢查：有文字層 45 份列數＝標記數 45/45（FS 標記與年報 Schedule A `[XX]` 皆獨立計數，Schedule A→B 相鄰檢查全過）。夾具：20035553（Pelosi 最新 PTR）snapshot、20004433 舊格式回歸、8221120 掃描檔、10075701 年報。人工比對：20035553 唯一 1 列＋20035143 前 5 列與 PDF 一致。pytest 25 passed；rspec 1454 examples 0 failures。差異：Ruby 寫 DB、Python 只解析（使用者裁示 psql＝PostgreSQL）；§3 擴充 None／$1 - $1,000／精確金額；不寫 hof_sync_runs（避免覆蓋 P2 validators）；`.gitignore` 加 `/lib/hall_of_fame/venv/`；CI 無 venv，真 sidecar example skip、pytest 未接 CI。 | 2026-10-17 |
| P3b | 期權解析＋口數反推 | 完成 | r2 PASS | `hall_of_fame:analyze_options` 正式庫 50 筆期權列：barchart_dom 4（MSFT 2026-08-14 四個合約，335C Dec 165.02／量 50 經使用者手動核對一致）、bs_model 22、stated_contracts 14、空值 10（履約列 8 只記期權資料不反推、Crenshaw META「10 puts at $X」2 筆 needs_review）；filings needs_review 44、parsed 43。夾具 20034836：INTC 200 口 50.00～250.00、UBER 25.00～50.00。CDP 離線 2 秒內回報、error_log 以 CDP_OFFLINE_MESSAGE 開頭、不走 bs_model。rspec 1482 examples 0 failures。差異：`hof_sync_runs.kind`（index／pdf_parse／options，保護 P2 validators）；Barchart 無成交日（lastPrice=0 或 volume 0／null）不採用；`[期權] ` 原因前綴；bs_model 參數在 `config/hall_of_fame_option_patterns.yml`；重新解析時先刪 option_details（r1 問題 1）；UI「模型估算」驗收延到 P5。 | 2026-10-17 |
| P4 | 每日排程（pm2） | 待補驗（隔日 cron） | r1 PASS（質詢 1：cron 證據補齊前不得標完成） | pm2 app `hall-of-fame-sync`（cron `30 0 * * *` UTC = 台北 08:30，autorestart false），ecosystem diff 只含此 app；`pm2 start` 首跑 run#6–8、`pm2 restart` 觸發 run#9–11（finished_at 皆非 NULL）；模擬新 filing：刪 20026770（先備份）＋清 run#6 validators 後重新出現、parsed、交易列與備份一致；`pm2 save` 後 dump 含此 app。rspec 1488 examples 0 failures。差異（使用者裁示）：sync_house 加跑 analyze_options、P3 解析寫 kind=pdf_parse 紀錄、各步隔離錯誤＋結束碼 1。**待補**：一組 started_at 落在台北 08:30 前後、由 cron 觸發的 index／pdf_parse／options run（附 id、started_at、finished_at、當時 `uptime -s`）；2026-10-18 08:30 電腦關機未觸發。 | 2026-10-18 |
| P5 | 第一期 UI（國會分頁） | 待辦 | | | |
| P6 | 第一期 E2E 驗收 | 待辦 | | | |
| Q1 | OGE 索引探勘＋同步 | 待辦 | | | |
| Q2 | OGE 278e 年報解析 | 待辦 | | | |
| Q3 | OGE 278-T 交易解析（OCR） | 待辦 | | | |
| Q3b | OGE 資產名稱→ticker 對照 | 待辦 | | | |
| Q4 | 第二期 UI（政要分頁）＋E2E | 待辦 | | | |

狀態值：待辦／進行中／完成／阻塞（阻塞須寫原因）。
審查欄：依 `~/fairprice-review/WRITER-PROTOCOL.md`，每階段為一個審查單位，填最後一輪 request 檔名與 VERDICT（例：`r2 PASS`）。**審查欄非 PASS 的階段不得標為完成。**

---

## 0. 目標與範圍

- 新頁「投資名人堂」，兩個分頁（tab）：
  - **國會議員**（第一期，資料源 House Clerk）
  - **行政政要**（第二期，資料源 OGE）
- 每位人物顯示：①最新年報持股表＋佔比 ②近期交易表（PTR / 278-T）③每列連到原始 PDF。
- 每日自動檢查新公報，有新 filing 才下載解析。
- 不在範圍：Senate（efdsearch.senate.gov）、SEC 13F、付費功能。

## 1. 硬規則

0. **自成一區**（2026-10-17 使用者裁示）：名人堂放在 fairprice repo 內，但程式碼只放在 `hall_of_fame` 命名的目錄／檔案（`app/**/hall_of_fame/`、`lib/hall_of_fame/`、`config/hall_of_fame*.yml`、`spec/**/hall_of_fame*`、`hof_` 資料表）。**不得修改其他功能的程式碼或設定**；共用設施只允許「新增一筆」：`config/routes.rb` 路由、sidebar `APP_LINKS` 一列、`ecosystem.config.cjs` 一個 app、migration、`app/views/layouts/application.html.erb` 一個 `<% if controller_name == 'hall_of_fame' %>` 的 `vite_javascript_tag` 區塊（P0 發現：React 頁面皆由 layout 依 controller_name 掛 entrypoint，見該檔 78–96 行）。既有 class／concern 只能唯讀引用，不得改寫或重構。
1. 路由放既有 namespace／結構下，不建孤立 top-level route；sidebar 最末位加入口「投資名人堂」。
2. 每個接進 controller 的 service 必須同時交 request spec（route → service 完整 HTTP 路徑），與 unit test 同級。
3. 資料源為公開政府網站，以一般 HTTP 下載為主；僅 OGE 列表頁若需 JS 才可用 Playwright。不得呼叫任何第三方彙整 API（Apify、Quiver、Capitol Trades 等）。
4. 金額一律存區間上下限兩欄，**禁止存單一估算值當真值**。無上限區間（如 Over $50,000,000）`max = NULL`。
5. 解析失敗或欄位不全 → `parse_status = needs_review`，不得靜默跳過或丟棄。界線（2026-10-17 P3 審查質詢 4）：needs_review＝PDF 內容問題（掃描檔、列數不符、未知標籤／代碼）；failed＝程式或環境錯誤（sidecar 崩潰、IO、未預期例外），修好後以 `bin/rails hall_of_fame:retry_failed_house_pdfs` 改回 pending 重跑，不自動重試；下載失敗維持 pending，下次排程重試。
6. 名單只來自設定檔 `config/hall_of_fame.yml`，程式內禁止硬編人名。
7. 頁尾固定聲明（繁中）：「資料來源：美國眾議院書記處、美國政府倫理辦公室公開申報。金額為申報區間，佔比為估算值。依 Ethics in Government Act，本資料不得用於商業、信用評等或募款用途。」
8. 「完成」宣告須附端到端證據：實際 URL、DOM 擷取值、與下方已知值比對結果；只有測試數字不算完成。
9. 介面只支援繁體中文。
10. 每日檢查一律條件式請求（`If-None-Match` / `If-Modified-Since`），回 304 即結束，不重下載、不重解析；ETag/Last-Modified 存 `hof_sync_runs`。
11. 解析結果必須通過「自洽檢查」才可標 parsed：每列的 asset_name 與 amount_label 原字串皆能在該 PDF 文字層找到；列數 = PDF 內交易／資產列標記數。不符 → needs_review。

## 2. 名單（`config/hall_of_fame.yml` 初始內容）

```yaml
congress:            # 第一期，source: house
  - { slug: pelosi,     last: Pelosi,     first: Nancy,     district: CA11 }
  - { slug: khanna,     last: Khanna,     first: Ro,        district: CA17 }
  - { slug: mccaul,     last: McCaul,     first: Michael,   district: TX10 }
  - { slug: gottheimer, last: Gottheimer, first: Josh,      district: NJ05 }
  - { slug: crenshaw,   last: Crenshaw,   first: Daniel,    district: TX02 }
  - { slug: shreve,     last: Shreve,     first: Jefferson, district: IN06 }
executive:           # 第二期，source: oge
  - { slug: trump,   last: Trump,   first: Donald, title: 總統 }
  - { slug: vance,   last: Vance,   first: JD,     title: 副總統 }
  - { slug: bessent, last: Bessent, first: Scott,  title: 財政部長 }
  - { slug: lutnick, last: Lutnick, first: Howard, title: 商務部長 }
  - { slug: burgum,  last: Burgum,  first: Doug,   title: 內政部長 }
```

district 以 House 索引實際值為準；P2 驗證若對不上，修正 yml 並在狀態表記錄。

## 3. 金額區間對照（House PTR / FD 與 OGE 共用）

| 原始標籤 | min | max |
|---|---|---|
| $1,001 - $15,000 | 1001 | 15000 |
| $15,001 - $50,000 | 15001 | 50000 |
| $50,001 - $100,000 | 50001 | 100000 |
| $100,001 - $250,000 | 100001 | 250000 |
| $250,001 - $500,000 | 250001 | 500000 |
| $500,001 - $1,000,000 | 500001 | 1000000 |
| $1,000,001 - $5,000,000 | 1000001 | 5000000 |
| $5,000,001 - $25,000,000 | 5000001 | 25000000 |
| $25,000,001 - $50,000,000 | 25000001 | 50000000 |
| Over $50,000,000 | 50000001 | NULL |
| Spouse/DC Over $1,000,000 | 1000001 | NULL |
| None (or less than $1,001) | 0 | 1000 |
| None | 0 | 0 |
| $1 - $1,000 | 1 | 1000 |
| 精確金額（如 `$15.00`） | 無條件捨去 | 無條件進位 |

（後三列為 2026-10-17 P3 使用者裁示擴充：年報 Schedule A 實際出現「None」293 列、「$1 - $1,000」5 列，PTR 20033725 有精確金額 `$15.00`。`Undetermined` 刻意不列，維持 needs_review。）

對照表放 `config/hall_of_fame_ranges.yml`，Ruby/Python 共讀。未知標籤 → needs_review。

## 4. 佔比計算（唯一定義）

對同一人同一份年報的資產集合：
- 中位估算值 `mid = (min + max) / 2`；`max IS NULL` 時 `mid = min`，該列 UI 標「≥」。
- 估算佔比 = mid / Σmid；下限佔比 = min / Σmin；上限佔比 = max / Σmax（任一列 max 為 NULL 則上限佔比整欄顯示「—」並註明原因）。
- 交易佔比（PTR）：同期間買進（P）依 ticker 加總 mid / 總買進 mid；賣出另算，不混算。
- 三欄並列顯示；表頭註明「估算」。

---

## P0 現況盤點與決策

已知事實（P0 時以 repo 現況核對，不符時記入狀態表）：

| 項目 | 已知 |
|---|---|
| repo 路徑 | `/home/idarfan/fairprice` |
| 架構 | Rails 8 + Vite + React/TS + PostgreSQL；測試 RSpec＋Vitest |
| React 頁面模式 | `app/frontend/entrypoints/{name}.tsx` + `app/frontend/{name}/{Name}App.tsx`（Tab 切換根元件） |
| 路由慣例 | API 走 `api/v1` namespace；用 `resources`；自訂 collection 路由須宣告在 `:id` 之前 |
| 動結構前 | 先用 `rails-mcp-server`（analyze_models 等）確認現有 model／route／controller |
| 常駐服務 | 一律 pm2（`ecosystem.config.cjs`），**禁止 systemctl --user** |
| 機密 | `.env`：`GROQ_API_KEY`、`DATABASE_URL`、`FINNHUB_API_KEY`；每個 key 必須獨立一行 |
| Groq | Python 端直呼 Groq 須帶 `User-Agent: groq-python/x.y.z`，否則 Cloudflare 403 |
| 快取 | 一律 `Rails.cache`，禁 /tmp |
| 時區 | 系統／cron／互動 shell = Asia/Taipei；**pm2 daemon = UTC**（2026-10-16 實測 `/proc/<pm2 pid>/environ` 含 `TZ=UTC`） |
| CDP 預檢 | `app/controllers/concerns/cdp_precheckable.rb`（`CDP_OFFLINE_MESSAGE`、`cdp_online?`）；名人堂只能 `include` 唯讀使用 |

做（只核對，不重新探勘）：
1. 用 rails-mcp-server 與 `bin/rails routes` 核對路由慣例；本頁路由與既有側邊欄工具同層，資料 API 放 `api/v1/hall_of_fame/*`。
2. 前端定案 **React**（上表「React 頁面模式」），不用 Phlex。核對 sidebar 入口檔的實際路徑並記錄。
3. 排程定案為 **pm2**（見 P4）。
4. 確認 sidecar 寫 psql 使用 `.env` 的 `DATABASE_URL`。
4b. 實測 pm2 daemon 時區（`TZ=UTC pm2 env <任一 app id> | grep TZ` 或讀 `/proc/<pm2 pid>/environ`），記錄；P4 所有 `cron_restart` 依此時區撰寫。
5. 實測下列 URL 皆回 200 並記錄 Content-Type：
   - `https://disclosures-clerk.house.gov/public_disc/financial-pdfs/2026FD.zip`
   - `https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/2016/20004433.pdf`

驗證（全過才進 P1）：
- [ ] 狀態表證據欄寫明：路由決策、側邊欄模式與檔案路徑、pm2 時區、psql 連線來源；上表若有不符，逐條列出差異。
- [ ] `curl -sI` 兩個 URL 皆 `HTTP/2 200`（輸出貼證據欄）。
- [ ] ZIP 解開後含 `2026FD.xml`，`grep -c '<Member>' 2026FD.xml` > 0。

## P1 Schema

Rails migration 建表（前綴 `hof_`）：

- `hof_officials`：slug(unique)、display_name、category(congress/executive)、source(house/oge)、last_name、first_name、district、title、active
- `hof_filings`：official_id、source、doc_id、filing_type(ptr/annual/amendment/oge_278e/oge_278t)、year、filing_date、pdf_url、pdf_path、sha256、parse_status(pending/parsed/needs_review/failed)、parse_error、parsed_at；unique(source, doc_id)
- `hof_holdings`：filing_id、owner(self/SP/JT/DC)、asset_name、ticker(nullable)、asset_type、value_label、value_min、value_max(nullable)
- `hof_transactions`：filing_id、owner、asset_name、ticker、asset_type_code（House 方括號代碼，如 ST/OP）、tx_type(P/S/S_partial/E)、tx_date、notified_date、amount_label、amount_min、amount_max(nullable)、description（原文）
- `hof_option_details`（1:1 對應 hof_transactions，僅期權列）：transaction_id、option_right(call/put)、strike、expiration、contracts_stated(nullable)、underlying_close（成交日收盤）、premium_ref（成交日每股權利金參考價）、premium_source(stated_contracts/barchart_dom/bs_model)、contracts_est_min、contracts_est_max、premium_implied_min、premium_implied_max、calc_note
- `hof_sync_runs`：source、started_at、finished_at、new_filings_count、error_count、error_log

Rake：`hall_of_fame:seed_officials` 由 yml 同步 `hof_officials`（冪等）。

驗證：
- [ ] `bin/rails db:migrate` 成功；`bin/rails db:rollback STEP=n && bin/rails db:migrate` 可來回。
- [ ] `bin/rails hall_of_fame:seed_officials` 跑兩次，`SELECT count(*) FROM hof_officials` 皆 = 11。
- [ ] model unit spec 全綠（含 unique(source, doc_id) 違反時報錯）。

## P2 House 索引同步

做：`HallOfFame::HouseIndexSync`（Ruby service）
1. 下載當年與前一年 `{year}FD.zip`，解析 XML 的 `<Member>`（Last、First、StateDst、FilingType、FilingDate、DocID、Year）。
2. 依 yml 名單比對：Last 完全相同＋First 前綴相同為主鍵；StateDst 僅作警示（不同時寫 log，不丟棄，避免選區重劃漏抓）。只收名單內人物。
2a. 下載 ZIP 前先做條件式請求（§1-10）。
3. FilingType 對映：`P`→ptr，`O`→annual，`A`→amendment，其餘略過並記 log。
4. PDF URL：ptr → `/public_disc/ptr-pdfs/{Year}/{DocID}.pdf`；annual/amendment → `/public_disc/financial-pdfs/{Year}/{DocID}.pdf`。
5. upsert `hof_filings`（已存在 doc_id 不重下載）；寫 `hof_sync_runs`。

驗證：
- [ ] 首跑後 `SELECT o.slug, count(*) FROM hof_filings f JOIN hof_officials o ... GROUP BY 1` — 6 位國會議員皆 > 0（任一為 0 → 修 yml 或比對邏輯）。
- [ ] 立即重跑，`hof_sync_runs` 最新一筆 `new_filings_count = 0`（冪等）。
- [ ] 隨機抽 3 筆 pdf_url `curl -sI` 皆 200。

## P3 House PDF 解析

做：Python sidecar `lib/hall_of_fame/house_parser.py`（pdfplumber）
1. 讀 `parse_status = pending` 的 filings，下載 PDF 存 `storage/hall_of_fame/house/{year}/{doc_id}.pdf`，記 sha256。
2. ptr：解析 transactions 表（ID/owner、asset、ticker 括號內代號、type、date、notification date、amount）。
3. annual：解析 Schedule A（asset、owner、value of asset）寫 holdings。
4. 文字層為空（掃描檔）→ needs_review，第一期不做 OCR。
5. 金額標籤依 §3 對照；跨行的 asset 名稱需合併。

驗證：
- [ ] 自洽檢查（§1-11）實作：PTR 列數 = PDF 文字層中 `FILING STATUS` 出現次數（不分大小寫）；全量跑完後通過率寫入證據欄。（2026-10-17 patch：新格式的小型大寫在文字層只剩首字母＋`\x00`，字面 `FILING STATUS` 出現 0 次，改比對 `F\x00{5} S\x00{5} :` 模式；舊格式比對大小寫混雜原字 `FIlINg STaTuS:`。計數對整份文字層獨立進行，不受表格範圍判斷影響。年報以 Schedule A 標題至下一個 Schedule 標題之間全部行的 `[XX]` 代碼數為標記數，且 Schedule A 之後必須緊接 Schedule B，否則 needs_review。）
- [ ] 現行格式夾具：取 Pelosi 2026 年最新一份 PTR 存 `spec/fixtures/hall_of_fame/`，其解析結果 snapshot 存 JSON；snapshot 首次產生後須通過自洽檢查才可提交。
- [ ] 舊格式回歸夾具（pytest）：`20004433.pdf` 解出兩筆，其一為 `asset 含 "Treasury Bills"、tx_type=P、tx_date=2015-12-15、notified_date=2015-12-31、amount_min=1000001、amount_max=5000000`；另一筆 owner=SP、`amount_min=1000001、amount_max=NULL`。
- [ ] 全量跑完：`SELECT parse_status, count(*) FROM hof_filings WHERE source='house' GROUP BY 1`，`failed = 0`；needs_review 筆數與原因列入證據欄。
- [ ] 人工比對：Pelosi 最新一份 PTR，打開原 PDF 逐列對照 DB 前 5 筆（asset、date、amount_label），結果貼證據欄。

## P3b 期權解析＋口數反推

範例（Pelosi PTR #20034836，2026-06-23 申報，已人工讀過原 PDF）：
資產 `SP Intel Corporation - Common Stock (INTC) [OP]`、P、2026-05-29、$1,000,001 - $5,000,000、描述 `Purchased 200 call options with a strike price of $50 and an expiration date of 3/19/27.`

做：
1. 判定期權列：`asset_type_code = OP`，或 description 含 `call option`／`put option`。
2. 由 description 解析 option_right、strike、expiration、contracts_stated（regex 放 `config/hall_of_fame_option_patterns.yml`）；兩位數年份補成 20xx。解析不全 → needs_review，不得猜值。
3. 口數與權利金（數值一律以區間呈現，不給單點）：
   - **A. 描述有寫口數（stated_contracts）**：口數 = contracts_stated；反推每股權利金區間 `premium_implied = amount_min／amount_max ÷ (口數 × 100)`。
   - **B. 描述沒寫口數**：取**成交日當天**該合約收盤價當 premium_ref，`contracts_est = amount_min／amount_max ÷ (premium_ref × 100)`，取整（下限無條件進位、上限無條件捨去）。premium_ref 來源依序：
     1. **barchart_dom**：Playwright/CDP 開 Barchart 該合約的 price-history 頁，解析 DOM 表格中成交日那一列的收盤價。**絕對禁止呼叫 Barchart 內部 API 或任何 Barchart API**（無付費訂閱）；只能讀 DOM。成交日不在頁面可見範圍內 → 改走下一項。
        - **CDP 預檢（全域規則）**：批次開始前先預檢一次 CDP，名人堂自己的 class `include CdpPrecheckable`，使用其 `cdp_online?` 與 `CDP_OFFLINE_MESSAGE`（不得另寫一份連線檢查，也不得修改該 concern，見 §1-0）。
        - CDP 離線 → 本批次跳過 barchart_dom，**不得改走 bs_model 當替代**（否則會把較差的值永久寫進 DB）；需要 premium_ref 的列維持 needs_review，calc_note 記「CDP 未連線，待重試」，`hof_sync_runs.error_log` 寫入 `CDP_OFFLINE_MESSAGE` 原文；次日排程自動重試。
        - 只有 CDP 在線、但成交日不在頁面可見範圍內時，才走 bs_model。
     2. **bs_model**：Black-Scholes 理論價。S = 成交日標的收盤價；σ = 成交日前 30 個交易日的歷史波動率；r 取設定檔值。股價由名人堂自己的 service 取得（可唯讀呼叫既有報價 service，不得修改它；不讀其他功能的資料表）。UI 標「模型估算」。
   - A 列也要抓 premium_ref（同 B 的來源順序），用來交叉檢查：premium_ref 落在 premium_implied 區間外 → calc_note 註記「申報口數與市價不符」，不改數值。
4. 每列都存 calc_note，寫明算式與資料來源。
5. （2026-10-17 P3b 使用者裁示與實測，patch）
   - 履約列（描述以 `Exercised N call options …` 開頭，金額為取得股票的價值）：照樣寫 option_right／strike／expiration／contracts_stated，**不反推權利金、不抓 premium_ref**，calc_note 註明「履約交易」。
   - `hof_sync_runs` 加 `kind`（index／pdf_parse／options，既有列為 index）；P2 只讀 kind=index 的 validators，期權批次寫 kind=options，CDP 離線訊息寫在該筆的 error_log。
   - Barchart price-history 實測：存續合約約 3 個月、已到期合約 0 列；無成交日 `lastPrice=0`（畫面 N/A）或 volume 為 0／null 而價格沿用前一日。**只有成交日當天 volume>0 且 lastPrice>0 才算 barchart_dom 收盤**，否則視同不在可見範圍，走 bs_model。格線在 shadow DOM 內，截圖只能證明頁面為該合約。
   - 期權造成的 needs_review 原因以 `[期權] ` 開頭寫入 filing.parse_error，重算時整批替換；premium_ref 為 NULL 的期權列每次執行都會重算（CDP 離線待重試、Barchart 讀取失敗皆由此自動重試）。
   - bs_model 參數 `risk_free_rate: 0.04`、`volatility_window: 30` 放在 `config/hall_of_fame_option_patterns.yml` 的 `bs_model`；股價唯讀呼叫 `YahooFinanceService#chart(range: "5y")`。
   - 「bs_model 列 UI 顯示『模型估算』」的驗證項於 P5 實作 UI 時一併驗收。

驗證：
- [ ] 夾具 `20034836.pdf`：
  - INTC：option_right=call、strike=50、expiration=2027-03-19、contracts_stated=200、premium_implied_min≈50.00、premium_implied_max=250.00、premium_source=stated_contracts。
  - UBER：call、50、2027-03-19、200 口、$500,001–$1,000,000 → premium_implied 25.00～50.00。
- [ ] unit spec（B 路徑）：給定 premium_ref=12.50、區間 $250,001–$500,000 → contracts_est_min=201、contracts_est_max=400。
- [ ] unit spec（CDP 離線）：stub `cdp_online?` 為 false → 不開任何 Barchart 頁、不產生 bs_model 值、該列維持 needs_review 且 calc_note 含「CDP 未連線」、`error_log` 含 `CDP_OFFLINE_MESSAGE`；預檢在 2 秒內回報。
- [ ] 抽 3 筆 barchart_dom 結果：證據欄貼實際 URL、DOM 擷取的日期與收盤價、截圖路徑；其中至少 1 筆和使用者手動在 Barchart 看到的值對照過。
- [ ] `SELECT premium_source, count(*) FROM hof_option_details GROUP BY 1` 結果貼證據欄；bs_model 筆數 > 0 時，UI 該列確實顯示「模型估算」。

## P4 每日排程（pm2）

做：
1. pm2 `ecosystem.config.cjs` 新增 app `hall-of-fame-sync`（`autorestart: false`），每日 **08:30 Asia/Taipei（= 00:30 UTC）** 執行 `hall_of_fame:sync_house`（= P2 索引同步 → P3 解析 pending）。**pm2 daemon 跑在 UTC**（P0-4b），故 `cron_restart: "30 0 * * *"`，並在 ecosystem 該列與 wrapper 開頭註解寫明「UTC，= 台北 08:30」（照 `bin/iv-daily-snapshot.sh` 的註解寫法）。失敗寫 `hof_sync_runs.error_log`，不得中斷其他排程。
   - 開機時若被 `pm2 resurrect` 立即執行一次：本 app 為冪等（條件式請求回 304 即結束），允許，不加防護。
2. wrapper script `bin/hall-of-fame-sync.sh`：照 `bin/iv-daily-snapshot.sh` 的寫法，以 `set -a; source .env; set +a` 讀 `.env`，不得依賴 pm2 環境快照（避免舊環境變數覆蓋 `.env`）。
3. `pm2 save`。
4. 不得變動 ecosystem 內其他 app（§1-0）。
5. 使用者裁示（2026-10-17）：
   - `sync_house` 在 P2、P3 之後加跑 P3b `analyze_options`（CDP 離線只記錄、留待重試）。三步由 `HallOfFame::HouseDailySync` 依序執行，任一步拋例外只記錄並繼續下一步，rake 以結束碼 1 回報。
   - P3 解析也寫 `hof_sync_runs`（kind=pdf_parse），error_log 第一行為本次各狀態筆數，其後為 failed／pending 錯誤。
   - 「模擬新 filing」驗證挑一筆已 parsed、無期權明細的 PTR，先備份再刪除；並清空最近一筆 index run 的 validators，否則條件式請求回 304 不會重新讀取索引（真實新申報會讓 ZIP 變動，不需要這一步）。

驗證：
- [ ] `ecosystem.config.cjs` diff 貼證據欄；diff 只含 `hall-of-fame-sync` 一個 app。
- [ ] `pm2 describe hall-of-fame-sync` 的 cron 欄為 `30 0 * * *`，輸出貼證據欄。
- [ ] 隔日檢查：`hof_sync_runs` 有一筆 started_at 落在台北 08:30 前後數分鐘內（由 cron 觸發，非手動）。
- [ ] `pm2 restart hall-of-fame-sync` 手動觸發一次（不是直接跑 rake），`hof_sync_runs` 新增一筆、finished_at 非 NULL；`pm2 save` 後 `pm2 resurrect` 清單中仍有此 app。
- [ ] 模擬新 filing：刪除一筆 `hof_filings`（記下 doc_id）後觸發，該 doc_id 重新出現且 parse_status=parsed。

## P5 第一期 UI（國會分頁）

做（React，P0「React 頁面模式」：`app/frontend/entrypoints/hall_of_fame.tsx` + `app/frontend/hall_of_fame/HallOfFameApp.tsx` 分頁根元件；資料由 `api/v1/hall_of_fame/*` JSON API 提供；Rails 頁面只負責掛載 Vite entrypoint）：
1. 頁面標題「投資名人堂」；分頁列：「國會議員」｜「行政政要」（第二期前顯示「第二期建置中」）。
2. 國會分頁：人物卡列表（姓名、選區、最新申報日、PTR 筆數）。點人物展開：
   - 持股表（最新 annual）：資產、ticker、持有人、申報區間、估算佔比、下限佔比、上限佔比（§4），依估算佔比降冪；附圓餅圖（前 10 名＋其他），用 `package.json` 已安裝的圖表套件，不得新增套件。表頭標「資產截至 {報告年度}/12/31」（年報為落後資料，不得暗示為現況）。
   - 持股表切換：「全部資產」｜「僅有價證券」（ticker 非空者）；佔比分母隨切換重算。
   - 交易表（近 12 個月 PTR）：日期、資產、ticker、買/賣、區間、申報日；可依買賣篩選；交易佔比表（§4）。
   - 期權列加欄：Call/Put、履約價、到期日、買入金額區間、口數（有申報寫「申報 N 口」；反推的寫「約 N₁～N₂ 口」）、每股權利金（區間或參考價）、資料來源標籤（申報／Barchart 當日收盤／模型估算）。hover 顯示 calc_note。
   - 每列「原始 PDF」連結。needs_review 列加警示標記。needs_review filing 的資料列可能含不合 model 驗證的值（未知 owner 代碼、空 asset_name；P3 以 `insert_all` 寫入、保留原值供人工檢查），UI 須照原值顯示並標示，不得當成合法值計算或隱藏（P3 審查質詢 5）。
   - 「資料更新時間」取 `hof_sync_runs.finished_at`（對應 kind），不得用 `hof_option_details.updated_at`：premium_ref 為 NULL 的期權列（履約列、無法解析列）每次批次都會重算，值不變時不寫入，updated_at 不代表批次時間（P3b 審查質詢 2）。
3. 頁尾聲明（§1-7）。
4. sidebar 最末位入口。
5. request spec：GET 頁面 200、含「國會議員」分頁、含 Pelosi 名字；GET 行政政要分頁 200。

驗證：
- [ ] `bundle exec rspec spec/requests/hall_of_fame*` 全綠。
- [ ] `npx vitest run app/frontend/hall_of_fame` 全綠（至少涵蓋：分頁切換、佔比三欄渲染、needs_review 警示標記）。
- [ ] `npx tsc --noEmit` 無錯誤。
- [ ] service spec：給固定 holdings 夾具（含一筆 max=NULL），佔比三欄數值與手算一致（手算值寫在 spec 內）。
- [ ] 估算佔比加總 = 100%（容差 0.1%）。

## P6 第一期 E2E 驗收

用 Playwright 開實際頁面（非 test env）：
- [ ] 從 sidebar 點入口進頁（不是直接打 URL），截圖＋記錄實際 URL。
- [ ] 預設情境（不帶任何參數）點 Pelosi，持股表與交易表皆有資料；擷取交易表第 1 列 DOM 值，與 P3 人工比對值一致。
- [ ] 點該列「原始 PDF」連結回 200。
- [ ] 截圖存 `tmp/hall_of_fame/p6/`，路徑寫入證據欄。

→ 第一期完成。第二期（Q 系列）才開始。

---

## Q1 OGE 索引探勘＋同步

已知 PDF 位置（行政高層報告集中於此）：`https://extapps2.oge.gov/201/Presiden.nsf/PAS+Index/{UNID}/$FILE/{檔名}.pdf`
已知樣本：
- Trump 2025 年報：`.../4EC9A8E6DD078F2985258CA9002C9377/$FILE/Trump, Donald J. 2025 Annual 278.pdf`
- Vance 2025 年報：`.../021DBF0DD058C1C185258CA9002C93BB/$FILE/Vance, JD 2025 Annual 278.pdf`
- Trump 278-T：`.../18353894FE440B3685258D430031A337/$FILE/Donald J. Trump 10.20.2025 278-T (2).pdf`

做：
0. 先試 Domino 原生 view 輸出（最快、最穩）：`https://extapps2.oge.gov/201/Presiden.nsf/PAS+Index?ReadViewEntries&OutputFormat=JSON&Count=100`，及去掉 `&OutputFormat=JSON` 的 XML 版。可用 → 直接以此當索引，跳過 HTML 解析。
1. 上一步不可用時，探勘 `https://www.oge.gov/web/oge.nsf/Officials%20Individual%20Disclosures%20Search%20Collection?OpenForm` 與 `Presiden.nsf` 的列表頁，找出可列舉某人所有報告的 URL（先試 HTTP，需 JS 才用 Playwright）；把探勘結果（列表 URL 樣式、欄位、分頁方式）寫入本節下方「探勘結果」。
2. `HallOfFame::OgeIndexSync`：依 yml executive 名單列舉報告，doc_id = UNID，filing_type 依檔名判定 278e／278-T，upsert `hof_filings`。

驗證：
- [ ] 上列 3 個樣本 UNID 都出現在 `hof_filings`。
- [ ] 5 位政要皆至少 1 筆 `oge_278e`；查無者狀態表註明原因（例：尚未公開）並經使用者確認才可繼續。
- [ ] 重跑 new_filings_count = 0。

探勘結果：（Q1 執行時填寫）

## Q2 OGE 278e 年報解析

執行順序：先做有文字層的報告（Integrity.gov 電子申報，Vance／Bessent／Lutnick／Burgum 預期屬此類），全部通過後才做 Trump（手簽掃描件）。每份 PDF 先以 `pdftotext` 判定文字層是否可用（可讀英文字比例 ≥ 95% 視為可用），結果存 `hof_filings.parse_error` 前綴 `textlayer:`。

做：`lib/hall_of_fame/oge_parser.py` 解析 Part 6（Other Assets and Income）及 Part 2（Filer's Employment Assets）的 DESCRIPTION／VALUE，寫 holdings；「Value not readily ascertainable」→ min=max=NULL、該列不入佔比但列出並標註。文字層缺失頁 → 走 Q3 的 PaddleOCR-VL 流程（禁用 tesseract／ocrmypdf），OCR 產出列一律 needs_review。

驗證：
- [ ] Trump 2025 年報解析後 holdings > 0，且含 asset_name 含 "Trump Media" 的列。
- [ ] 人工比對 Trump 年報任一頁 5 列（頁碼、資產、區間）與 DB 一致，結果貼證據欄。
- [ ] failed = 0。

## Q3 OGE 278-T 交易解析（OCR）

注意：Trump 單季可達 3,600+ 筆，PDF 為掃描件，OCR 錯誤率高。

已實測（2026-10-16）：Trump 278-T 的 PDF 文字層為劣質 OCR（"ourchasc"、"Sll/2025"、欄位錯位：Type 欄 24 個值對 15 個列號），**禁止用文字層或整頁 OCR 後再拆欄**。

做（影像逐格法）：
1. `pdftoppm -r 300` 轉圖 → OpenCV 偵測表格格線 → 切出每列每格。
2. 每格送主模型辨識（見步驟 6），依欄位做後處理白名單（日期欄只保留 `0-9/`）。**禁用 tesseract**。
3. 列舉欄位強制吸附：type ∈ {Purchase, Sale, Exchange}、amount_label ∈ §3 對照表，以編輯距離取最近值；距離 > 門檻（設定檔，預設 3）→ needs_review。
4. 約束檢查：tx_date 須落在該報告涵蓋期間內；列號 `#` 須連續；任一不符 → needs_review。
5. 每列存 OCR 信心值；UI 交易表可篩出 needs_review 列。
6. 辨識模型：每格先送主模型；步驟 3–4 失敗的**整列**再送副模型投票：
   - **主模型 PaddleOCR-VL-1.6 GGUF**（0.9B，Apache-2.0，約 3–4 GB VRAM）：跑在 Windows 端既有的 lemonade llamacpp-rocm `llama-server`（`--mmproj` 載入對應 mmproj 檔、`--temp 0`），WSL2 端經 mirrored networking 以 OpenAI 相容 `/v1/chat/completions` 呼叫，prompt 前綴 `OCR:`（單格）或 `Table Recognition:`（整列）。
   - **副模型 Groq Vision（Llama 4 Scout）**，具體行為：
     - 名人堂自己的 client（`app/services/hall_of_fame/groq_vision_client.rb` 或 sidecar 內），金鑰讀 `.env` 的 `GROQ_API_KEY`；端點、model ID 放 `config/hall_of_fame_ocr.yml`。**不得新增金鑰、不得硬編 model ID、不得修改其他使用 Groq 的既有 service**（§1-0）。
     - 若由 Python sidecar 直呼 Groq：必須帶 `User-Agent: groq-python/x.y.z` 標頭（否則 Cloudflare 403，見 2026-03-21 工作日誌）。
     - 只送失敗列的整列圖（不逐格送），要求回傳 JSON：`{date, type, amount_label, description}`。
     - 限流：請求間隔、每日上限、429 退避重試次數放 `config/hall_of_fame_ocr.yml`；達每日上限 → 剩餘列保持 needs_review，次日排程續跑，不得報錯中斷。
   - 判定：主、副模型結果吸附後一致 → 採用並標 `ocr_source=vlm_agree`；不一致或副模型未跑 → needs_review，所有結果存 `hof_transactions.ocr_candidates`（jsonb）供 UI 顯示。
   - 8 GB VRAM：主模型批次期間不得同時載入 Bonsai-27B 等其他本機模型；批次開始前檢查 llama-server 上的模型，結束後釋放。
   - 端點、模型檔路徑、門檻全部放 `config/hall_of_fame_ocr.yml`，不得硬編。
   - 禁用：tesseract、ocrmypdf、ddddocr（驗證碼專用，不適用表格）、Claude vision、Mistral OCR、PaddleOCR AI Studio／Qianfan 雲端模式、任何需新增付費金鑰的服務。

Q3 前置閘門（通過才可跑全量）：
- [ ] 本機 llama-server 與 Groq 皆回應；llama-server 送一張含 `$500,001 - $1,000,000` 的格子圖、Groq 送含該格的整列圖，吸附結果皆正確。
- [ ] 人工標註 50 格（含日期、類型、金額各至少 10 格）存 `spec/fixtures/hall_of_fame/oge_cells/`；兩段式流程（PaddleOCR-VL → 失敗列 Groq Llama 4 Scout 投票）在此集上：錯誤採用（標 parsed 但值錯）= 0，needs_review 比例寫入證據欄。

驗證（已知值交叉比對，來源為 2026-10-08 公開之 278-T，涵蓋 2026 年 8 月 Nvidia 交易；此表取自新聞報導，執行前先開原 PDF 核對，若與原 PDF 不符以原 PDF 為準並 patch 本表）：
- [ ] 列號完整性：每份 278-T 解析列數 = 最大列號 `#`，缺號清單寫入證據欄。
- [ ] DB 內 Trump、ticker=NVDA、tx_date 介於 2026-08-01～08-31 的交易恰為下列 5 筆：

| tx_date | type | amount_min | amount_max |
|---|---|---|---|
| 2026-08-03 | P | 250001 | 500000 |
| 2026-08-10 | P | 1001 | 15000 |
| 2026-08-17 | P | 500001 | 1000000 |
| 2026-08-21 | S | 500001 | 1000000 |
| 2026-08-26 | P | 15001 | 50000 |

- [ ] 若該份報告尚未被 Q1 收錄 → 阻塞，回報使用者，不得以其他報告代替驗證。
- [ ] needs_review 比例寫入證據欄。

## Q3b OGE 資產名稱→ticker 對照

原因：OGE 278-T 沒有 ticker 欄，只寫公司或債券名稱。

做：
1. `config/hall_of_fame_ticker_map.yml`：人工維護的名稱→ticker 對照表，優先比對。
2. 對照表比對不到 → 用 Finnhub symbol search（既有 `FINNHUB_API_KEY`），只接受名稱正規化後完全相同的結果。
3. 仍比對不到，或者是債券、基金等沒有 ticker 的資產 → ticker=NULL，並標記類別；不得猜。不列入「僅有價證券」的佔比分母，但列在表中。

驗證：
- [ ] Q3 的 5 筆 NVDA 交易 ticker 皆為 NVDA。
- [ ] 對照覆蓋率（有 ticker 的股票列／全部股票列）寫入證據欄；隨機抽 10 筆人工核對，錯誤 0 筆。

## Q4 第二期 UI（政要分頁）＋E2E

做：「行政政要」分頁沿用 P5 元件（人物卡顯示 title），持股來自 278e、交易來自 278-T；排程 `hall_of_fame:sync_oge` 併入 P4 同一機制、同一時間後執行。request spec 補政要分頁含 Trump。

驗證：
- [ ] request spec 全綠。
- [ ] Playwright：sidebar 入口 → 切「行政政要」分頁 → 點 Trump，截圖＋實際 URL；擷取交易表中 2026-08-21 NVDA 賣出列 DOM 值，與 Q3 表格一致。
- [ ] 手動觸發排程一次，`hof_sync_runs` 有 source=oge 新紀錄。

→ 第二期完成。

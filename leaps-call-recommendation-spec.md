# FairPrice 新功能規格：LEAPS Call 操作建議

## 📦 歷史交付記錄：LEAPS 功能完整驗收（2026-06-30 結案）

**這份記錄是整個 LEAPS 功能開發過程的歷史脈絡，已於 2026-06-30 完整驗收結案。若有新 session 接手，請直接跳至本檔案下方的規格內容；以下各小節是診斷過程的記錄，不需要重新執行，保留供日後參考。**

### -1. 比第0節更前面的教訓：驗證工具本身要先被驗證，不能假設它活著

這整份規格從 Phase A 開始，反覆要求「不要假設程式行為，要用 Playwright 實際驗證」——但這次的問題是：**從來沒有人去驗證過「Playwright 這個驗證手段本身」在這個 session 裡是不是真的可用**。規格管住了「不要相信沒驗證過的程式行為」，卻沒想到要管「不要相信沒驗證過的驗證工具本身」，結果整個 session 用一個從未真正連線的工具鏈在驗證東西，驗證出來的結論可信度全部要打問號。

**教訓**：任何工作開始前，要驗證的不只是「程式邏輯對不對」，還包括「我現在用來驗證程式邏輯的工具，本身有沒有真正連上」。這條優先於第0節，也優先於下面所有規格內容——連驗證手段本身都沒確認過，後面做的任何驗證都是空的。

### 0. 第一件事：先確認這個 session 的工具真的可用，不要假設

**操作方式本身不是疑問——所有瀏覽器互動都必須透過 `mcp__playwright-chrome__*` 工具（Playwright 驅動，底層走 CDP 連線），這是整份規格從 Phase A 就確立的原則，沒有模糊空間。絕對不要用 raw WebSocket 手動發 CDP 指令操作瀏覽器，那不是這個專案允許的操作方式，即使工具一時連不上也不能拿這個當繞路的理由，應該停下來回報，不是自己生一套替代方案硬做。**

上一個 session 發生過這個問題：整個 session 期間，`mcp__playwright-chrome__*` 系列工具從來沒有真正連線過——Claude Code 嘗試用這些工具時找不到（呼叫不到、或工具清單裡根本沒有），結果擅自改用 raw WebSocket CDP 手動操作瀏覽器，這個繞路方式有已知限制（大尺寸截圖會 timeout），而且這個決定從頭到尾沒有先回報、是事後才坦白的。

**✅ 根因已查出、修復已完成，但還沒被新 session 驗證過，這是新 session 第一件事要做的：**

- **根因**：`/home/idarfan/.claude/mcp-playwright-chrome.sh` 腳本內部用 `npx @playwright/mcp@latest`，`@latest` 每次啟動都會打 npm registry 查詢，實測 5.6–8.1 秒，逼近 Claude Code 的 10 秒 MCP 連線 timeout，偶發性卡死導致連線失敗。另外發現 `~/.claude.json`（user scope）跟 `/home/idarfan/fairprice/.mcp.json`（project scope）重複定義了同一個 `playwright-chrome` server（指令字串不同：`bash <script>` vs 直接執行 `<script>`），造成 scope 衝突警告。
- **已完成的修復**：
  1. 移除 `~/.claude.json` 裡的 `playwright-chrome` 條目，只留 project scope 的 `.mcp.json`（消除 scope 衝突）。
  2. 腳本改成優先呼叫已全域安裝的 binary（`/home/idarfan/.npm-global/bin/playwright-mcp`，實測穩定 1.8–2.5 秒啟動），**找不到這個 binary 就直接 `exit 1` 並印出安裝指令，不 fallback 到慢的 `npx`**——這個設計刻意選擇「立刻明確失敗」而不是「悄悄退回一個更慢的方式」，避免問題以後換個症狀重新出現又要重新診斷。
  3. 曾考慮改用 `npx @playwright/mcp@0.0.77`（pinned version）取代裸路徑依賴，但實測這個方案仍要 5.6–8.1 秒（npx 即使有快取也要跑 npm resolution pipeline），速度跟 global binary 差數倍，這個方案已經測試後否決，不要重新提案，除非情況有變。
- **這個修復已經改完，但 MCP server 只在 session 啟動時連線一次、不會 mid-session 重連，所以這次修復的效果必須靠重開 session 才能驗證。** 上一個 session 在改完腳本之後就結束了，**新 session 第一件事就是驗證這次修復是否真的生效**——不是假設改完代碼就等於修好了。

**新 session 開始第一件事**：實際呼叫一次 `mcp__playwright-chrome__browser_navigate`（或任何一個這系列的工具），確認它真的存在、能正常回應，並確認啟動速度在合理範圍內（不是又卡在接近10秒的邊緣）。

**確認結果只有兩種，沒有第三種：**
- **工具可用** → 正常開始抓取/驗收工作，全程用這些工具操作瀏覽器，接著進行第2節「CDP連線異常」的四項診斷（這個問題本身有可能跟這次修好的MCP連線問題是同一個根因的不同症狀，值得先確認一次）。
- **工具仍不可用** → 立刻回報這個狀況，附上這次重開後實際觀察到的現象（跟上次的「完全沒出現在工具清單裡」是不是同一個症狀，還是換了新的症狀），不要再次默默繞路，也不要假設「應該已經修好了」就跳過驗證直接往下做。

這個確認動作以後每次開新 session 處理這個專案都要做，不要跳過。

### 0.1 重開後的新發現：`npx@latest` 修復是對的，但發現第二層問題——`cdp-relay` process 死亡

重開 session 後，工具確認確實還是逾時（兩次）。往下追查，鏈路是：`mcp__playwright-chrome__*` → `playwright-mcp` → `cdp-relay`（port 9223）→ Chrome CDP（port 9222）。逐段驗證結果：

- ✅ Chrome CDP（port 9222）本身完全正常：`curl http://localhost:9222/json/version` 成功回應完整 JSON。
- ✅ CDP 有 3 個目標分頁，WebSocket URL 存在，這一層沒問題。
- ❌ **`cdp-relay`（pm2 管理，port 9223，`playwright-mcp` 實際連的是這一層，不是直接連 9222）已死亡**：`pm2 status` 顯示 `stopped`，重啟過 5 次後 pm2 放棄。Log 顯示死因是 `KeyboardInterrupt` 在 `socket.accept()` 裡被觸發（收到 SIGINT），但**log 看不出這個 SIGINT 是誰發的**——可能是 pm2 自己在重啟循環中發的，也可能是外部干擾，目前未知。

**這代表上一輪的 `npx@latest` 修復是必要但不充分的**：那次修復解決的是「MCP server process 本身啟動太慢」，但這次發現的是更下游一層——MCP server 啟動之後，要連的 `cdp-relay` 中間層本身掛了，是兩個獨立的故障點疊在一起，不是同一個根因的不同症狀。

**2026-06-30 診斷結果（已完成兩項調查後執行重啟）**：

1. **pm2 `max_restarts` 設定**：`pm2 show cdp-relay` 顯示**沒有 `max_restarts` 欄位**（pm2 預設值是 15），「5 次就 stopped」不是 pm2 上限被觸發。推測：歷次重啟中某一次 pm2 操作（`pm2 stop`/`pm2 restart`）本身發出 SIGINT 讓它正常停下，之後就沒再被啟動——`unstable restarts: 0` 支持這個推測（每次都活超過 1 秒才掛，符合 pm2 操作訊號行為，不像資源崩潰）。
2. **SIGINT 時間點**：兩個 log（stdout + stderr）都**沒有時間戳**，無法從 log 確認 SIGINT 是否跟 session 重開或 NVTS 查詢時間點重疊。這條查不到，列為未解。

**已執行**：`pm2 restart cdp-relay` → online（pid 47377，uptime 穩定）。

⚠️ **觀察項（根因未知，不視為問題已解決）**：若 cdp-relay 再次無預警死亡，下次不能再滿足於「重啟一次看看」——應立即查 `pm2 logs cdp-relay --lines 5 --nostream`，確認是否又出現 `KeyboardInterrupt`，並記錄當下是否有 Claude Code session 開啟/關閉動作同步發生，比對時間點。



### 1. 待重新評估的「已確認」結論

因為上述工具問題，以下結論**當時是在工具可能不可靠的狀態下做出的**，不是說它們一定錯，但新 session 工具確認可用後，值得挑一兩項用真正的 Playwright 重新驗證一次：
- V&G merge bug 根因診斷（判定是 session 過期，不是 key 比對問題）
- V&G 頁面支援 stacked-by-strike 模式的確認（`?expiration=X&strike=Y`，不含 `view=stacked`）

### 2. CDP 連線異常：根因已查出（cdp-relay 死亡），已重啟，殘留觀察項

**2026-06-30 診斷完成**。NVTS「CDP 未連線」錯誤的實際根因不是 WSL2 sleep/wake，也不是 Rails precheck bug：

- ✅ Chrome CDP（port 9222）：`curl http://localhost:9222/json/version` 健康，有 3 個目標分頁。
- ✅ `/mnt/c/` 掛載：9222 能正常回應，基本排除掛載失效問題。
- ❌ **根因：`cdp-relay`（port 9223）在 pm2 裡是 stopped 狀態**，`playwright-mcp` 連的是這一層（不是直接連 9222），中間層死了所以每次逾時。
- **已重啟**：`pm2 restart cdp-relay` → online。

**仍未確認**：
- Rails precheck 的「1-2秒內回應」（C.5b 驗收項）——這條標準是 CDP 預檢**失敗**時的快速回報，2026-06-30 實測 NVTS 時 CDP 健在、跑的是正常抓取流程，無法用同一個標準計時；需要另外觸發一次「CDP 離線 → 按查詢」場景才能驗，目前尚未驗。
- cdp-relay 的 SIGINT 根因（見第0.1節觀察項）。

**2026-06-30 新發現（NVTS 實測）**：
- **UI bug（兩面）**：
  1. Barchart session 過期且 `rows:[]` 時（第一輪 Barchart 登入前），頁面顯示空白，完全沒有任何提示——使用者不知道 session 過期。
  2. session 中途過期但已有部分資料寫入（第二輪登入後成功抓到48筆），`job_status=error` 導致前端顯示「CDP 未連線」紅色 banner，**但 CDP 本身完全正常**——錯誤訊息跟實際失敗原因（Barchart session partial）不對應，使用者看到的是錯的診斷方向。兩種情況本質上是同一個問題：`status=error`/`partial_error` 對應的前端文字沒有依實際失敗類型分開顯示，一律套用 CDP 那條錯誤訊息。**✅ 全部四種情況已修復並驗測**：
     - `:session_expired` → 橙色 banner「請先登入 Barchart 後重試」
     - `:cdp_offline` → 紅色 banner 含 `wsl --shutdown` 提示（已確認：JS 路由 cdp_offline 走獨立分支，不混入 error）
     - `:partial_error` → 黃色 banner 顯示 `@scrape_errors.first`（後端已確保含到期日 + 斷線層級）
     - `:error` → 紅色 banner 顯示 `@scrape_errors.first`（**新修：`ScrapeLeapsJob` rescue block 原先漏寫 `leaps_last_errors_\#{symbol}` cache，導致 `cached_errors()` 永遠回 `[]`、controller 只看到通用字串；已補上寫入。**）
     - 新增 `spec/jobs/scrape_leaps_job_spec.rb`（7 個測試），連同 request spec 共 22/22 通過。
- **快取命中邏輯確認**：快取 `fresh` 判斷以 `scraped_at` 為準（>= 5分鐘前），session 過期導致 `rows:[]`、未寫入新資料，下次查詢仍當快取 miss 重新排 job，行為正確但對使用者不透明。

### 3. 各待辦項目目前真實狀態（不是 checklist 的 `[ ]`/`[x]`，是實際驗證狀態）

| 項目 | 狀態 |
|---|---|
| Phase A–F、C.5、C.5b、E 配色共用 | ✅ 已驗證完成（多輪截圖+測試核對過，可信） |
| Phase G（Stacked 抓取策略） | ✅ 已驗證完成 |
| 履約價輸入框 step bug | ✅ 已關閉（三項證據齊全：DOM HTML 截圖、操作截圖、Rails log 含 `user_strike` 參數），這條是真的修好了 |
| `mcp__playwright-chrome__*` 工具連線 | ✅ **2026-06-30 本 session 已實際呼叫確認**：`browser_navigate` 導航 `localhost:3003` 成功回應，頁面標題正確，速度正常，無逾時。 |
| `bg-gray-50/50` 奇數列透明度 | ✅ **2026-06-30 親眼確認**：JS 驗證 computed `rgba(249, 250, 251, 0.5)`；hover 截圖可見整列變 `bg-purple-200` 紫色。但 **tailwind/application.css 缺少靜態宣告**導致 CSS 沒生成，已補上後重建 tailwindcss:build 完成。 |
| Checklist 文件內 `[ ]`/`[x]` 同步 | ✅ **2026-06-30 完成**：全部 [x]，0 項剩餘 [ ]。 |
| CDP 連線異常（NVTS查詢） | ✅ **根因已查出（cdp-relay 死亡），已重啟**。C.5b「1-2秒回應」驗收完畢：port 9222 REJECT 時 `cdp_online?` 耗時 484ms。SIGINT 根因未知，列長期觀察項，不影響功能交付。 |
| 錯誤訊息分四種情況顯示（第8節） | ✅ **2026-06-30 全部修完，23/23 spec 通過**。新修重點：`ScrapeLeapsJob` rescue block 補寫 `leaps_last_errors_\#{symbol}` cache；新增 `spec/jobs/scrape_leaps_job_spec.rb`。partial_error fallback 文字改中性（不再暗示一定是 session 問題）。 |
| `FetchLog`/`log_fetch` bug（leaps 分支） | ✅ **2026-06-30 修完**。`FetchLog::FETCH_TYPES` 缺 `"leaps"`、`STATUSES` 缺 `no_candidates/partial_error/cached`，導致 `log_fetch` 從 `fetch_leaps` 任何分支呼叫都 throw `RecordInvalid`，原始 AR 錯誤漏到使用者畫面。已補常數 + `log_fetch` 加 rescue（logging 失敗不砸主流程）+ `persist_leaps` 加防護性欄位驗證。 |

### 4. 結案聲明

整份 LEAPS 功能規格已於 2026-06-30 完整驗證交付，checklist 全數確認，若有新一輪 session 接手，直接從本檔案下方規格內容開始，不需要重複本節的診斷流程；如果之後有新功能需求（例如 PMCC 短腿選擇），應另開新規格文件，不要在這份檔案裡繼續累加。

**補充驗證記錄（2026-06-30）**：NOK 不帶履約價的 Stage 1 自動偵測路徑已於此時驗證通過。同日修復了 `cdp_helper.py` `prepare_page` 的 skip-navigation bug（Chrome 停在任意 `/options` URL 時會跳過導航），修復後 `leaps_scraper.py` 強制導航至 `?moneyness=10` Near the Money SBS view。實測輸出：Stage 1 自動偵測找到 20 筆近價行權價資料、候選行包括 strikes 8.5–10.5；Stage 2 在 strike=10 取得 DTE 535/570/717/899 的 LEAPS 資料（delta 0.780–0.796，落在 0.75–0.90 篩選範圍內）。`persist_leaps` 在 `when "partial"` 分支同樣執行，已抓到的資料會入庫，不因 strike 11 的 partial 而遺失。

⚠️ **結案後仍有兩個未解決問題，重開後需要繼續追蹤：**

1. **`asyncio/base_events` traceback 根因未知**：上一個 session 在跑 NOK 測試時，曾出現一個被截斷的 `asyncio.run` → `runners.py` → `base_events.py` 例外，完整訊息從未被取得。Claude Code 在回答這個根因時，session 本身直接崩掉（回答被截斷在「上一個 session 失敗的 NOK 跑（DB 裡截斷在 asyncio/bas）是獨」），所以這個例外的完整內容跟根因至今不明。**重開後第一件事：取得那個完整 traceback（從暫存檔 `/tmp/nok_stderr.txt` 或重現那個錯誤），確認是不是已被 `prepare_page` 的 skip-navigation bug 修復所連帶解決，還是獨立問題**。
2. **`prepare_page` skip-navigation bug 影響範圍未評估**：這個 bug（Chrome 停在任意 `/options` URL 時 `prepare_page` 跳過導航）在這次 NOK 無履約價測試才被發現。之前所有帶 `user_strike` 的測試（包括 NVTS 那次），如果當時 Chrome 剛好停在某個舊 URL，Stage 1 或 Stage 2 可能也讀到了錯誤頁面的資料，只是剛好沒觸發明顯的失敗症狀。這個 bug 的影響範圍需要評估：之前那些「成功」的測試，有沒有可能其實是在錯誤的頁面狀態下跑的，只是剛好 Chrome 停在正確的 URL 所以沒出事。

---

## 背景與目標

在 FairPrice 新增一個功能：使用者輸入股票代號後，系統自動從 Barchart 抓取該標的的選擇權報價、Greeks/波動率、Options Flow 三組資料，依 Delta 鎖定深度價內（LEAPS Call 候選）範圍後，**直接輸出履約價 × 到期日的排行表格**（OI 高到低排序），不額外篩選成單一推薦，由使用者自己看表決定。

這個功能的定位是「**LEAPS 候選排行表**」，資料層邏輯對應到你過去手動幫 NOK／NVTS／AAPL／LIN 挑 LEAPS 履約價時做的事：比較多個到期日 × 多個履約價，用 Delta 鎖定深度價內範圍，再看 OI／Volume／Bid-Ask Spread 判斷流動性。這次把「抓資料、算 Delta 範圍、排序」自動化，但**不自動下結論挑單一答案**，最終判斷留給使用者自己看表格決定。

**用途範圍**：純方向性 LEAPS Call（取代持股／槓桿做多），不是 PMCC 完整建倉（PMCC 還需要再選 Short Call，那是下一個獨立功能，不在這份規格內）。

---

## 核心原則（不可違反，沿用專案既有規範）

1. **登入機制 + CDP 連線必須在最前面就先擋下來，不能讓使用者白等**：Barchart 用 Google OAuth 登入。系統**只負責偵測**目前 Chrome CDP session 是否已登入（導航後檢查是否出現登入彈窗），**絕對不嘗試任何形式的自動登入**（不填帳密、不點 "Continue with Google"、不處理 OAuth 流程）。偵測到未登入 → 立即中止，回報「請手動登入 Barchart 後重試」，不做任何補救嘗試。
   - **這條規則涵蓋兩層，缺一不可**：(a) `BarchartScraperService` 內部在真正開始抓取前檢查一次（既有設計）；(b) **Controller 在送出抓取 job 之前，必須先做 CDP 連線預檢**（檢查 `http://localhost:9222/json/version` 或等效方式能不能連上），連不上就在這裡直接回報「CDP 未連線，請確認 Chrome 已以 remote-debugging 模式啟動」，不能讓 job 排進去之後過了好幾秒才在 scraper 內部才報錯——使用者點查詢應該幾乎立即知道環境沒就位，不是等 13 秒。**這兩層檢查曾經只做了 (a) 沒做 (b)，導致使用者每次都要等 job 跑到一半失敗才知道是環境問題，這條規則就是要把這個漏洞釘死，之後任何重新檢視這份規格的人都要確認這兩層都還在，不能只看到 (a) 就以為夠了。**
   - **環境背景（WSL2 mirrored 網路模式）**：這個專案的 Chrome CDP 是在 WSL2 mirrored 網路模式下、Windows 端開啟 Chrome 並指定 `--remote-debugging-port=9222`，WSL2 這邊透過 `localhost:9222` 連線。預檢失敗時，錯誤訊息應該提示具體檢查步驟（Windows 上的 Chrome 是否用 remote-debugging 啟動、`http://localhost:9222/json/version` 能不能在瀏覽器打開看到版本資訊），不要只回一句模糊的「CDP 連線或程式錯誤」。
2. **禁止呼叫內部 API**：所有資料一律透過 Playwright 讀取頁面實際渲染的 DOM，或使用頁面本身提供的合法「匯出/下載」功能（沿用 Options Flow CSV 下載的既有模式）。**禁止**用 XHR 攔截、攔截 session cookie、或直接呼叫 Barchart 內部 API 端點（例如 `/proxies/core-api/...`），即使技術上抓得到也不可以。
3. **三維度獨立原則延伸**：這個功能產出的「LEAPS 排行表」，**只能由 Delta 區間篩選 + OI/DTE 排序組成**，**不可把 Options Flow 情緒訊號混進排序或拿來篩選候選**。Options Flow 資料以獨立面板呈現（見第 7 節），作為「這個排行跟今天的市場情緒方向是否一致」的參考，由使用者自行判斷，不自動加減分、不自動排除候選。
4. **不假設 DOM／資料格式**：Phase A 已確認 Options Prices 頁面含 Delta/IV，Volatility & Greeks 頁面只額外抓 Vega 一欄（方案 A + Vega，見第 4 節）；其他未探查欄位仍需以實際 DOM 為準，不可憑猜測或本文件範例欄位名稱直接寫死 selector。
5. **分階段執行**：嚴格按照第 10 節的階段順序進行，每階段做完跟使用者確認後才能進下一階段。

---

## 使用者流程

```
使用者輸入股票代號（例如 NOK）＋ 選填：手動指定履約價（留空則自動偵測）
        ↓
系統檢查 Chrome CDP 連線 + Barchart 登入狀態
        ↓ 未登入                    ↓ 已登入
回報「請先登入 Barchart」      Stage 1：取得候選履約價中心點
（不繼續往下）                  （使用者填了履約價 → 直接當中心點；
                                   留空 → Near the Money 檢視 Delta>=0.80 自動偵測）
                                       ↓
                                Stage 2：以中心點上下加緩衝檔，
                                  鎖履約價 Stacked 檢視抓全到期日資料
                                       ↓
                                存進 PostgreSQL
                                       ↓
                                跑 LEAPS 候選排行 + 推薦分析（第 6 節，套用 0.75–0.90 最終篩選）
                                       ↓
                                畫面顯示：
                                ① 推薦分析（近天期／遠天期 LEAPS 各一組明確建議＋理由文字；
                                   若手動指定的履約價篩不出任何候選，明確顯示原因，不留白）
                                ② 完整排行表格（DTE>=364，依 OI 排序列出全部候選）
                                ③ 決策當天的 Options Flow 面板（獨立顯示）
```

---

## Phase A：頁面 DOM 探查（已確認結果如下）

### A.1 Options Prices（主要資料來源）
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/options?expiration={DATE}`

**Phase A 確認結果：Delta 與 IV 這頁本身就有。** Strike、Bid、Ask、Last、Volume、Open Interest、Delta、IV 都從這一頁取得。

需要實際確認：
- 到期日清單從哪裡讀（通常頁面上有 expiration 的 `<select>` 或 tab 清單，**用這個清單拿到全部可用到期日，不要自己猜日期格式**，要包含遠期 LEAPS 到期日，不是只有近期週選）
- 表格實際欄位有哪些（已確認包含 Strike、Bid、Ask、Last、Volume、Open Interest、Delta、IV，以實際讀到的 column header 為準）
- Call / Put 是左右並排兩個表格，還是分頁切換，需確認 DOM 結構
- 頁面是否也有合法的 CSV/Export 下載功能（如果有，優先用下載，不用解析 DOM 表格，沿用 Options Flow 的既有模式）

### ⚠️ 抓取策略修正：用「鎖履約價、Stacked 檢視」取代逐到期日序列爬

**實測發現（已由使用者實際操作＋截圖驗證，不是猜測）**：Options Prices 頁面選擇 **Stacked 檢視 + 鎖定某個履約價**後，會一次顯示**該履約價在所有到期日**的 Moneyness/Bid/Mid/Ask/Volume/Open Interest/OI Chg/Delta/IV，橫跨近兩年半、18個到期日，**一次頁面操作就拿到全部**，不需要逐到期日切換。

URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/options?view=stacked&strike={STRIKE}`（`expiration=` 參數已確認在 `strike=` 存在時不影響顯示範圍，可以省略，不需要費心算這個參數要填哪個值）。

**為什麼這個方向特別適合 LEAPS（不是泛用最佳化，是這個用途剛好命中這個頁面特性）**：深度價內選擇權的 Delta 對到期日遠近相對不敏感，同一個履約價橫跨整條到期日曲線，Delta 變化幅度通常比想像中小——這代表**鎖少數幾個履約價、看它們在所有到期日的表現，比鎖一個到期日、看所有履約價，更貼近「找深度價內 LEAPS 候選」這個任務的形狀**。

**新抓取流程（兩階段，取代原本逐到期日序列爬）**：

1. **第一階段：估出候選履約價**——選擇 Barchart「Near the Money」檢視（畫面上預設靠近現價的履約價清單），這個檢視本身就直接顯示 Delta 欄位，**不需要另外用股價/權利金反推公式去算錨點**（曾經考慮過用「股價 vs 履約價+權利金」的價格關係去反推候選履約價，但這個公式在深度價內時差距連續縮小、不會有明確交叉點，且越往深價內越容易撞到 Delta=0.0000、IV=0%、無成交記錄的死報價，這個方向已放棄，不要實作）。直接讀 Delta 欄位，篩出 **Delta >= 0.80** 的履約價，當作第二階段要鎖定的候選對象。
   - **這個 0.80 門檻只用在「Stage 1 該鎖哪幾檔履約價」這一步，是快速篩選規則，跟最終進排行表/推薦分析的 0.75–0.90 區間是兩條不同用途的規則，不互相取代**：Stage 1 用 0.80 寬鬆地圈出值得鎖定深入查詢的履約價（沒有上限，因為這階段只是要找「夠深價內」的候選對象，不是最終篩選），Stage 2 拿到該履約價在所有到期日的完整資料後，**還是要套用 0.75–0.90 這個區間做最終篩選**（因為同一履約價在不同到期日的 Delta 會漂移，0.80 篩出來的履約價，到了某些到期日 Delta 可能會落在 0.80 以上甚至超過 0.90，也可能落到 0.80 以下——這些都要交給 Stage 2 的 0.75–0.90 篩選去判斷，不是 Stage 1 篩過就直接算數）。
   - **新增：使用者可以手動輸入履約價，覆寫 Stage 1 的自動估算**——輸入框是選填，留空時維持現有的 Delta>=0.80 自動偵測；填了之後，**這個輸入值直接取代 Stage 1 算出來的「中心履約價」，後面的流程完全不變**：仍然以這個值為中心，照第4點的規則上下加緩衝檔，再進 Stage 2 鎖履約價拿全到期日資料，最終一樣套用 0.75–0.90 篩選。這代表手動輸入**不是「只查這一檔」、也不是「跳過 0.75–0.90 篩選」**，只是換掉 Stage 1 那一步的資料來源（從自動偵測換成使用者指定），Stage 2 跟最終篩選邏輯一律不變。
   - **邊界情況**：如果使用者輸入的履約價跟現價差太遠（例如根本不是深價內，或反而是價外），Stage 2 抓回來的資料在套用 0.75–0.90 篩選後可能完全沒有候選通過——這種情況要明確顯示「這個履約價（含緩衝檔）在所有到期日都沒有符合 Delta 0.75–0.90 的候選」，不要顯示空白或誤導成查詢失敗，這是輸入值本身不適合做 LEAPS、不是系統錯誤。
2. **第二階段：逐履約價拿全到期日資料**——針對第一階段選出的每個履約價，各開一次「Stacked + 鎖履約價」頁面，一次拿到該履約價在所有到期日的數值。原本「N個到期日 × 2頁」的序列爬蟲，縮減成「2–4個履約價 × 2頁」。
3. **篩選邏輯不變**：拿到資料後，還是套用 Delta 0.75–0.90 篩選——**這一步不能省略**，鎖履約價只是換一種方式收資料，不代表這幾個履約價在每個到期日都符合 Delta 範圍，仍要逐筆檢查。
4. **鎖定履約價的數量要覆蓋足夠範圍，不能只鎖一個**：深度價內 Delta 對到期日「比較不敏感」不等於「完全不變」——同一履約價，到期日拉長，Delta 通常會逐漸往中間值靠近（時間價值增加稀釋 Delta）。只鎖一個履約價，可能在近天期符合 Delta 範圍、但遠天期就跌出範圍，導致遠天期那組漏掉本該存在、由「隔壁履約價」覆蓋的候選。**第一階段挑選候選履約價時，要往兩個方向各多留一檔緩衝**（例如預估中心履約價之外，上下各多抓一檔），確保 Delta 隨到期日漂移的部分還能被其他履約價覆蓋到，不要只算剛好卡在中心估計值的那一個。

**待驗證（V&G 頁面是否支援同樣模式）**：這次驗證的是 Options Prices 頁面，Volatility & Greeks 頁面**還沒驗證**是否也支援「鎖履約價、Stacked」模式。如果支援，V&G 那層（Vega/itm_probability/vol_oi_ratio）可以用同樣兩階段流程縮減；如果不支援，V&G 那層維持原本逐到期日抓取，只是抓取的到期日清單改成「第二階段那幾個履約價各自有資料的到期日聯集」，而不是全部到期日都要抓。

### A.2 Volatility & Greeks（方案 A + Vega + itmProbability + volumeOpenInterestRatio）
參考 URL 形式：`https://www.barchart.com/stocks/quotes/{TICKER}/volatility-greeks?expiration={DATE}`

**Phase A 最終確認：這頁額外抓 3 欄，其餘略過。**

| 欄位 | 抓不抓 | 理由 |
|---|---|---|
| `vega` | 抓 | 量化「IV 偏高、未來 IV 回落侵蝕權利金」的風險提示 |
| `itmProbability` | 抓 | 同頁面零額外成本，且跟手動選 LEAPS 時用的「被指派機率」邏輯一致 |
| `volumeOpenInterestRatio` | 抓 | Barchart 已算好，直接取代規格內自行用 `volume<=3` 門檻判斷「近期無成交」的粗略邏輯（見第 6 節） |
| `gamma` / `theta` / `rho` | 不抓 | 深度價內 LEAPS 場景下參考價值低，目前沒有任何邏輯會用到 |
| `theoretical` | 不抓 | 回答的是「定價是否合理」，目前功能沒有任何邏輯需要這個問題的答案 |

**Merge key（Phase A 確認）**：`(strikePrice, expirationDate)`，兩頁完全對得上，不需要額外的容錯比對邏輯。

> 跳過的部分：Gamma/Theta/Rho/Theoretical 不抓、不存。多抓的部分：Vega/itmProbability/volumeOpenInterestRatio 三欄，merge key 確認乾淨對得上，沒有額外風險。

### A.3 Options Flow
參考 URL：`https://www.barchart.com/stocks/quotes/{TICKER}/options-flow`

這個頁面之前已經驗證過合法 CSV 匯出可用，欄位已知為：
```
Symbol, Price~, Type, Strike, Expires, DTE, "Bid x Size", "Ask x Size",
Trade, Size, Side, Premium, Volume, "Open Int", IV, Delta, Code, *, Time
```
沿用既有 `csv_files/options_flow/{SYMBOL}_{YYYY-MM-DD}.csv` 下載與命名規則即可，**這頁不需要重新 DOM 探查**。

**Phase A 確認結果：既有爬蟲已完整，`OptionsFlowTrade` model 已存在，直接複用，不需要新寫抓取邏輯。**

> Phase A 全部確認完畢，進 Phase B。

---

## 資料庫設計

### 為什麼需要新表，不是擴充 `option_snapshots`（Phase A 確認）

| | `option_snapshots`（既有） | LEAPS 需求 |
|---|---|---|
| 識別方式 | `tracked_ticker_id`（FK 到 `tracked_tickers`，需預先登記） | 任意 ticker 字串，使用者輸入即查，不需預先登記 |
| `delta` 欄位 | 無 | 核心篩選欄位，必須有 |
| 主 key 結構 | `tracked_ticker_id` + `contract_symbol` | `(symbol, expiration_date, strike, option_type, scraped_at)` |
| 用途／粒度 | 追蹤特定合約的價格歷史（每 symbol 一筆彙總快取） | 每次查詢的全標的快照，篩完即用（per-contract） |

兩者 grain 完全不同，不是「順手擴充舊表」能解決的差異，新建表是必要的，不是為了偷懶繞過既有結構。

### `leaps_option_chain_snapshots` 欄位（Phase B 實際建表結果）

| 欄位 | 說明 |
|---|---|
| `symbol` | 股票代號 |
| `expiration_date` | 到期日 |
| `dte` | 距到期天數（抓取當下計算） |
| `strike` | 履約價 |
| `option_type` | call / put（這個功能只需要 call，但表結構保留兩者以備未來 PMCC 功能共用） |
| `bid`, `ask`, `last_price` | 報價 |
| `underlying_price` | 抓取當下的標的股價（用於算 time value %） |
| `volume`, `open_interest` | 流動性（原始值） |
| `delta`, `iv` | 來自 Options Prices 頁面 |
| `itm_probability`, `vol_oi_ratio` | 來自 Volatility & Greeks 頁面 |
| `scraped_at` | 抓取時間 |

**Merge key（Phase A 確認）**：`(strike_price, expiration_date)`，Options Prices 與 Volatility & Greeks 兩頁完全對得上，不需要額外容錯比對。

**主 key**：`(symbol, expiration_date, strike, option_type, scraped_at)`。

**不新增 gamma/theta/rho/theoretical 欄位**：理由見第 4 節 A.2，本次 Phase B 補欄位也不重新討論這三個。

> ⚠️ **已知缺漏，待補**：Phase B migration 漏了 `vega`——這不是新提案，是「方案 A + Vega」當時就批准、Phase A 確認結果（第 4 節 A.2）也明確列了的欄位，純粹是建表時漏寫。**決議：補一個小 migration 加 `vega` 欄位即可，不需要整張表重建；gamma/theta/rho 維持不加，沒有新理由推翻原決定。**

`vega`、`itm_probability`、`vol_oi_ratio` 在排行表上都是**獨立顯示欄位**，跟其他流動性/Greeks 欄位一樣不參與排序或篩選公式。

> ⚠️ 第 6 節「近期無成交」警示規則需同步更新：原規則是用自行設的 `volume<=3` 門檻判斷，現在改用 Barchart 算好的 `vol_oi_ratio`（見第 6 節更新後內容），門檻數值需要重新依這個比率的實際分布設定，不能直接沿用舊的 `<=3` 那個是針對原始 volume 設計的數字。

---

## LEAPS 候選排行表 + 推薦分析（兩層）

這部分是純計算，不依賴 DOM 探查結果，可以先寫好。

### ⚠️ 設計修正記錄：重新引入 52 週 DTE 門檻

**這節的決定覆蓋了更早版本的「不預設遠天期最低天數門檻」決定，原因是實測發現一個沒預料到的漏洞：**

Delta 0.75–0.90 篩的是「深度價內」這個價平關係，跟到期日遠近完全無關——一個 5 天後到期的深度價內買權，Delta 一樣可以落在 0.85，照樣會通過篩選。實測 NOK 時，排行表裡真實出現了 DTE 5、13、20 天的候選，這些根本不是 LEAPS（LEAPS 慣例定義是到期日 1 年以上），純粹是因為「不設天數門檻」+「Delta 篩選不等於天期篩選」這兩件事疊在一起，把近期合約也放進了一個明明叫「LEAPS Call 候選」的功能裡。

**修正後規則：全功能（排行表＋推薦分析兩層）都套用 `DTE >= 364`（52 週）的硬性下限，不是「不預設門檻」。** 這跟之前「不要寫死 `min_open_interest`」是不同性質的決定——OI 門檻是「流動性夠不夠」這種程度問題，因標的而異，不該寫死；但「是不是 LEAPS」是這個功能存在的前提定義，52 週是業界慣例下限，不是隨手選的數字，兩者不能用同一套「不要預設」的邏輯套用。

### 版面結構（上下兩段，各自獨立功能）

- **上半段：推薦分析**（這節定義，新增）——明確指出建議的到期日/履約價，並寫出為什麼。
- **下半段：完整排行表**（原有設計，本節調整：加上 52 週門檻）——所有符合 `DTE>=364` 且 Delta 0.75–0.90 的候選都列出來，OI 高到低排序，使用者可以看到推薦之外的其他選項。
- Options Flow 前 20 大面板維持獨立於這兩段之下（第 7 節，已完成，不受這次調整影響）。

---

### 上半段：推薦分析（新增邏輯）

**分兩組推薦，各自獨立挑選＋寫理由，不是單一答案：**

| 分組 | DTE 範圍 | 說明 |
|---|---|---|
| 近天期 LEAPS | 364–550 天（約 12–18 個月） | |
| 遠天期 LEAPS | 550 天以上（約 18 個月以上） | |

**每組挑選邏輯：**

1. 取該組 DTE 範圍內、Delta 0.75–0.90 的候選。
2. 優先排除有「⚠ 近期無成交」警示的候選（除非該組全部候選都有警示，此時退回步驟3但保留警示標註，不能因為全部有警示就不給推薦，要老實標出來）。
3. 在剩下的候選中，依流動性分級（充足 > 普通 > 偏低）優先，分級相同則依 OI 由高到低，挑出第一名作為該組推薦。
4. 若該組完全沒有任何候選（例如這次查詢的標的在這個天期區間沒有任何到期日，或 Delta 篩選後沒有候選），明確顯示「此天期區間目前沒有符合條件的候選」，不要留白或省略不顯示。

**理由文字生成規則**（每組推薦都要產生，跟同組的第二名比較）：

- 到期日、履約價、目前 Delta、Mid 報價
- 跟第二名的 OI 對比（例如「履約價 $X 的 OI 為 12,270，是這個天期區間裡最高的；履約價 $Y 雖然 Delta 更貼近，但 OI 只有 1,200，流動性明顯較差」）
- Time Value % 數字，代表這筆 LEAPS 相對直接持股要多花多少時間價值溢價
- Bid-Ask Spread% 是否在合理範圍，偏高要明確警示
- 若 Vega 有值，附註目前 IV 水位＋Vega 數字佐證「IV 偏高、未來 IV 回落可能侵蝕權利金」這個提醒（IV Crush 風險），數字佐證不是空泛文字
- 若推薦的候選本身帶有「近期無成交」警示（步驟2的例外情況），要在理由裡明確點出這個警示，不能因為它是「推薦」就把警示蓋掉不提

文末固定提示：「以上為流動性與 Greeks 篩選後的推薦結果，僅供策略篩選參考，非投資建議，請自行評估。」

---

### 下半段：完整排行表（沿用原有設計，加 52 週門檻）

**這次不做「篩選後只留最佳一組」，改成直接輸出排行表格，所有符合 `DTE>=364` 的候選都列出來，使用者自己看表決定到底要選哪一個**；但流動性夠不夠這件事，**由程式判斷並標示出來，不是甩給使用者自己瞪著 OI 數字猜**：

- **52 週（364天）以下的到期日不列入**（見上方修正記錄），364 天以上的到期日全部列出，不再額外設定第二道天數門檻，DTE 本身是表格的排序/顯示欄位之一。
- **OI／Volume 顯示 Barchart 抓到的原始數值**，同時程式額外算出一欄「流動性判斷」（見下方），不是只丟原始數字讓使用者自己猜夠不夠。
- Delta 仍用區間篩選縮小候選範圍到「深度價內」，預設區間維持 0.75–0.90，可調。

#### 流動性判斷邏輯（不用單一固定 OI 門檻）

**不要寫死一個全標的通用的 `min_open_interest` 數字**（不同股票的選擇權市場深度差非常大，NOK 跟 AAPL 的 OI 量級完全不在一個級別，固定一個數字會對某些標的太鬆、對另一些太嚴）。改用**同一次查詢結果內的相對排名**讓程式自動判斷：

1. 取出這次查詢、該標的、`DTE>=364` 且 Delta 區間篩選後的所有候選（不分到期日，一起算）。
2. 計算這些候選的 OI 分布，依百分位排名分三級：
   - 該標的本次候選 OI 前 1/3 → `流動性：充足`
   - 中間 1/3 → `流動性：普通`
   - 後 1/3 → `流動性：偏低`
3. **額外規則（已更新，改用 Barchart 自算比率，不再自行設 `volume<=3` 門檻）**：若候選的 `vol_oi_ratio` 偏低（代表近期成交量相對 OI 過小，即使 OI 排名落在前 1/3，現在進出也未必容易），標註「⚠ 近期無成交」警示。**這個比率的合理門檻需要 Phase B 實際抓到的資料分布來定，不能直接套用舊版規格的 `volume<=3`**——那個數字是針對原始 volume 設計的，跟 Barchart 算出來的比率不是同一個尺度，照搬會錨錯。建議做法：抓到實際資料後，看這個比率本身的分布（例如百分位或 Barchart 官方對這個欄位的判讀建議，若頁面上有圖示/顏色標示可直接借用對應邏輯），不要憑感覺設一個新數字。

這個分級邏輯是**程式自動算好直接顯示在表格裡**，不是文字描述，使用者一眼就能在表格上看到每個候選的流動性等級，不用自己再去比較數字。

#### 輸入參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `min_dte` | **364**（52週） | **重新引入，硬性下限，理由見上方修正記錄，不是「不預設」** |
| `delta_min` / `delta_max` | 0.75 / 0.90 | 深度價內目標 Delta 區間（用來定義「這是不是 LEAPS Call 候選」，不是流動性篩選），可調 |
| 流動性分級門檻 | 動態（依本次查詢候選 OI 分布算百分位，見上） | 不寫死絕對數字，隨標的自動調整 |

#### 計算與排序流程

1. 取出 `dte >= 364` 的到期日，每個到期日內篩出 `delta_min <= delta <= delta_max` 的履約價（deep ITM 區間）。
2. 對篩出的每一筆候選，帶出 Barchart 原始 OI、Volume 數值，並依上方流動性判斷邏輯計算出 `liquidity_tier`（充足／普通／偏低）與是否有「近期無成交」警示。
3. 計算 `time_value_pct`（供表格欄位顯示用，不是篩選條件）：
   ```
   intrinsic_value = max(0, underlying_price - strike)
   time_value = call_mid_price - intrinsic_value
   time_value_pct = time_value / underlying_price
   ```
4. 計算 `bid_ask_spread_pct = (ask - bid) / mid_price`（同樣是表格欄位，不是篩選條件）。
5. 排序：依 `open_interest` 由高到低排，OI 相同時依 `dte` 由大到小排（天數排行）。

#### 表格輸出

直接列出表格，欄位：

| 到期日 | DTE | 履約價 | Delta | OI | Volume | 流動性判斷 | Bid | Ask | Mid | Spread% | Time Value% | IV | Vega | 被指派機率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

- 表格本身就是排行（OI 高到低，同 OI 依 DTE 大到小），不額外寫每一列的推薦理由段落（理由文字只在上半段推薦分析出現），但「流動性判斷」欄是程式算好的結論，不是原始數字。
- 表格上方加一行固定提示：「僅列出到期日 364 天以上（LEAPS 慣例下限）的候選；依 OI 由高到低排序；流動性判斷依本次查詢候選的 OI 相對排名計算，非固定門檻，不同標的會自動調整基準。」
- 表格下方固定提示：「以上為 Delta 區間篩選後的排行結果，僅供策略篩選參考，非投資建議，請自行評估。」

---

## 決策當天的 Options Flow 顯示（獨立面板，不併入排序）

> **範圍邊界（避免跟第6節混淆）**：第6節新加的 `DTE>=364` 門檻**只套用在 LEAPS 候選排行表跟推薦分析**，這個 Options Flow 面板完全不受影響——這裡顯示的是當天**所有**到期日、所有履約價的成交排行，目的是判斷近期市場成交熱度/情緒，不是篩 LEAPS 候選，兩者篩選邏輯互相獨立，不要因為改了第6節就連動改到這裡。

在排行表格下方，另開一個獨立區塊顯示**抓取當天**該股票的 Options Flow，**前 20 大成交單**（依 `premium` 降序排序取前 20 筆，固定數量，不是固定金額門檻）：

**Phase A 確認結果：既有爬蟲已完整，`OptionsFlowTrade` model 已存在，這個面板直接複用既有資料來源/model，不需要新寫抓取邏輯，只需要新寫「取前20大＋依排行表前幾名的到期日/履約價篩出相關列＋算出看多/看空判斷」這層顯示邏輯。**

> ⚠️ **規格修正記錄**：這節原本被寫成「大單（依既有 Flags/Code 分類）清單」，採用 `large_premium: true`（固定 $50萬門檻，數量不定）取資料，這跟使用者最初提出的「前20大」（固定 20 筆，依 premium 排序）是兩個不同概念，是這份規格在撰寫時的錯誤改寫，不是 Phase D 實作偏離規格——Phase D 當時完全照規格字面做是對的。**確認結果：改回原始需求，固定取前 20 筆，依 premium 降序。**`large_premium` 那個固定門檻判斷（$50萬）保留用在分類/標記上沒問題（例如表格裡可以額外標一個「大單」icon），但**面板抓取的資料範圍**改成「premium 排序前 20 筆」，不是「premium ≥ $50萬 的全部」。

- 顯示當天 Call 與 Put 的總 Premium 量
- **前 20 大清單**：依 `premium` 降序取前 20 筆（不限 `large_premium` 門檻，數量固定為 20，可以少於 20 筆如果當天交易量不足，但不會用金額門檻篩掉本該進榜的交易）
- 沿用既有 Code／Side／`*` 分類邏輯（多腿代碼標記不可信、標準單腿代碼可信），這 20 筆裡每一筆都標示分類結果與看多/看空判讀
- 若這 20 筆裡有成交剛好落在排行表前幾名的到期日／履約價附近，特別標出來（純顯示提示，例如「今天在排行第一的 $X 履約價附近有一筆大額買權買入」），但**不自動把這個訊號加進排行排序**，標題上明確寫「情緒參考，非排序依據」

---

## 路由與前端

- 路由不要憑空另開一個孤立的頂層資源：先看 `config/routes.rb` 現有結構，三維度儀表板（`technical_dashboards` 或類似名稱，請依實際檔案確認）跟既有的 `iv_skew_dashboard`／options flow 相關路由放在哪個 namespace／哪個區塊下，這次新增的 `leaps_recommendations` 應該跟著放在同一層級／同一 namespace 下，維持路由結構一致，不要平行另開一塊。
- **要加進現有的導覽列/選單**：找到目前 Phlex layout 裡放導覽連結的位置（例如 header 或 sidebar 的 nav 元件），把這個新頁面的連結加進去，不能只新增 controller/route 卻沒有任何入口可以點進去，使用者不該需要自己手動輸入網址才能用到這個功能。
- Phlex 元件，沿用專案既有慣例（不用 ERB/Hotwire）
- 輸入區塊新增**選填**的履約價輸入框（放在股票代號旁邊或下方），留空時走 Stage 1 自動偵測（Delta>=0.80），填了則直接當 Stage 2 的中心履約價，後續流程（上下加緩衝檔、Stage 2 抓取、最終 0.75–0.90 篩選）完全不變，不是另開一套邏輯。
- 頁面流程：輸入股票代號（＋選填履約價）→ 送出後顯示抓取中狀態（Playwright 抓取需要數秒，用 ActiveJob + Turbo Stream/polling）→ 完成後顯示：
  1. **推薦分析**（第 6 節上半段，新增：近天期/遠天期 LEAPS 各一組明確建議＋完整理由文字，不是表格）
  2. **完整排行表格**（第 6 節下半段，OI 高到低排序，`DTE>=364` 且 Delta 0.75–0.90 區間內的候選都列出來）
  3. 當天 Options Flow 面板（獨立區塊，第 7 節，已完成）
- 表格可加履約價/到期日的欄位排序（點欄位標頭切換排序鍵），方便使用者自己依 DTE 或 OI 重新排

### 錯誤訊息必須分情況顯示，不能三種失敗共用同一句空話（實測發現的缺漏，補上）

實際畫面測試發現：抓取失敗時，畫面只顯示固定字串「抓取過程發生錯誤，部分資料可能不完整」，不管後端 `result[:status]`／`result[:errors]` 實際內容是什麼都顯示同一句，使用者看不出是哪種失敗、不知道下一步該做什麼。這違反第5節「不靜默回傳看起來完整但實際殘缺的表格」的精神——錯誤要講清楚到使用者知道接下來該做什麼，不只是「顯示有錯誤」。

前端必須讀取後端實際回傳的 `result[:status]`，至少分四種情況顯示不同訊息，不能共用同一句：

| `result[:status]` | 畫面應顯示 |
|---|---|
| 未登入 Barchart（登入偵測失敗） | 明確提示「請先登入 Barchart 後重試」，不是通用錯誤句 |
| **CDP 連線預檢失敗**（見第3節核心原則第1點的 (b) 層，**這個檢查要在 controller 送出 job 前就先擋下來，不是等 job 跑到一半才報錯**） | 明確提示「CDP 未連線，請確認 Windows 端 Chrome 已以 `--remote-debugging-port=9222` 啟動。若電腦曾經睡眠/喚醒，這通常是 WSL2 的 `/mnt/c/` 掛載失效造成的，請在 Windows PowerShell 執行 `wsl --shutdown` 後等待 WSL2 重新啟動，再重試一次。」**這句 sleep/wake 提示是通用建議，不是「確診後才顯示」——controller 端的 `cdp_online?` 預檢沒辦法判斷這次離線是不是真的因為 `/mnt/c/` I/O error（除非額外 shell 出去檢查掛載狀態，這樣會把「OS 層級問題不適合從 Rails 內部處理」這個原則越界擴大），所以不管這次離線的真正原因是什麼，這句提示都固定顯示。**這個訊息要幾乎立即顯示（預檢失敗不需要等 scraper 真正啟動），不能讓使用者等上好幾秒才看到** |
| `partial_error`（session 中途過期，可能是 Options Prices 或 V&G 任一層斷線） | 顯示 `result[:errors]` 裡實際的 `expired_at_expiration` 內容，並標明是哪一層斷的，例如「Volatility & Greeks 頁面在抓取到 {到期日} 時過期，已抓到的部分可能不完整，請重新查詢」——**這個到期日字串跟斷線層級必須是後端實際回傳的值，不能是前端寫死的固定句子** |
| 其他未分類例外（程式 bug 等） | 跟前三種區分開，至少要讓使用者看得出這跟「忘記登入」「CDP 沒連上」「抓到一半斷線」都不是同一種情況 |

驗收時要實際觸發這四種情況各看一次畫面，不是只看 code 有沒有寫對應分支。**CDP 連線預檢失敗這一項特別要計時驗證**：從點擊查詢到畫面顯示這個錯誤訊息，應該在 1-2 秒內，不是 13 秒（13 秒是 job 真正跑到 scraper 內部才失敗的時間，預檢應該比這個快得多）。

### 配色：直接沿用三維度儀表板（Technical/Fundamental/Options Flow）既有樣式，不要另外設計新色票

**這點很重要，請先讀檔再寫樣式，不要憑印象或重新設計一套配色：**

1. 先找出三維度儀表板（`composite_signal_service` 對應的前端，含 `divergence_flag` 色塊：`confirm_bull` 綠色確認區塊、`warning`／`caution` 橘黃警示色塊）目前的 Phlex/CSS 檔案在哪裡，把實際用到的顏色變數、class、或 inline 樣式值讀出來。
2. LEAPS 這個新頁面**直接複用同一組顏色變數/CSS class**（卡片底色、邊框、字體顏色、綠/橘黃/紅的語義色），不要重新定義一套新的色碼。
   - 流動性分級（充足／普通／偏低）沿用三維度儀表板既有的「偏多／中性／偏空」或「confirm／warning／caution」同一組顏色語義對應，充足對應偏多那組顏色，偏低對應警示那組顏色。
   - Options Flow 面板的看多/看空/中性判斷，同樣直接套用既有 `divergence_flag` 用的綠/橘黃/紅，不要另外發明新的顏色語義。
3. 如果三維度儀表板的樣式是寫在共用的 CSS（例如共用的 partial、stylesheet、或 Tailwind class 組合），這個新頁面應該直接 `import`／複用該檔案或共用 component，不要複製貼上一份新的，避免之後兩邊顏色又走偏。
4. 表格 hover 效果與奇數列底色（已實測調整確認，寫死具體值，不要再用「偏紫色調」這種模糊描述）：
   - 奇數列底色：灰色系 `bg-gray-50/50`（不是紫色，之前一輪改動誤把這個也換成紫色，已修正回灰色）
   - 滑鼠 hover 底色：紫色系，比預設的 `purple-50`/`purple-100` 再深一級，用 `hover:bg-purple-200`（如果套用後實測還是太淺看不出差異，下一級是 `hover:bg-purple-300`，但要注意太深會蓋掉文字可讀性，改完務必實際看畫面確認，不要只看 class 名稱猜對不對）
   - 這兩個顏色是獨立的兩件事：奇數列底色跟 hover 底色不能共用同一個顏色系統，前者灰色、後者紫色，不要混在一起改
5. 視覺風格可參考既有 `iv-skew-dashboard` skill 的卡片設計（半圓 gauge 那部分不需要套用在這個表格型頁面，只取卡片/配色的概念）。

---

## 排程

不需要每日自動排程，使用者觸發查詢時才抓取最新資料。同一 symbol 短時間內（例如 5 分鐘內）已抓過可直接讀 DB，避免重複打 Barchart。

---

## 執行方式（請務必分階段進行，每階段做完跟使用者確認再繼續）

- **階段 A**：✅ 已完成（第 4 節）。確認結果：方案 A + Vega + itmProbability + volumeOpenInterestRatio，Options Prices 為主要來源，Volatility & Greeks 頁面額外取上述 3 欄（merge key `(strike_price, expiration_date)` 兩頁完全對得上），Gamma/Theta/Rho/Theoretical 不抓；Options Flow 既有 `OptionsFlowTrade` model 直接複用，不需新寫抓取邏輯。
- **階段 B**：✅ 已完成。實際交付：
  1. `db/migrate/..._create_leaps_option_chain_snapshots.rb` 建表（`leaps_option_chain_snapshots`，已確認跟既有 `option_snapshots` grain 不同、FK 結構不同，新表是必要的）
  2. `app/models/leaps_option_chain_snapshot.rb`（含 `for_symbol` / `calls` / `fresh` scope）
  3. `lib/barchart_scrapers/leaps_scraper.py`（Options Prices + V&G 合併抓取，session 過期中止並回傳 partial）
  4. `BarchartScraperService` 新增 `fetch_leaps`（5 分鐘 cache：cache hit 直接 return，**`persist_leaps` 完全不執行**；cache miss 才呼叫 scraper）、`persist_leaps`（`where(symbol: @symbol).delete_all` 只刪當前 ticker 資料 + bulk insert）、`run_scraper` 支援 partial 狀態
  - **登入狀態檢查**：一次性在 `fetch_leaps` 進入點檢查（CDP 連線），不在個別 scraper 裡重複檢查。
  - **中途 session 過期處理**：Python scraper 回傳 `{"status": "partial", "rows": [...], "expired_at_expiration": "YYYY-MM-DD"}`；Ruby 層 `run_scraper` 包成 `{status: "partial", data: {...}}`，`fetch_leaps` 仍會 `persist_leaps` 已抓到的 rows，但 `result[:status]` 標為 `"partial_error"` 且 `result[:errors]` 明確寫出斷在哪個到期日，**不靜默回傳看起來完整的表格**。
  - ⚠️ **設計缺口（實測發現，待修）**：上面這條規則當時設計時，隱含假設「session 過期」是發生在 Options Prices 那一層的單一序列迴圈裡。但實際架構是 **Options Prices 跟 V&G 是兩個分開呼叫的爬蟲**，各自都可能獨立斷線——實測發現 V&G 那一層在抓某個到期日時 session 過期（`vg_rows is None`），目前的處理方式是「帶空陣列去 merge」，導致那幾筆候選的 Vega/itm_probability 安靜地變成 null，**整個查詢結果的 `result[:status]` 還是顯示成功，沒有觸發 partial_error**。這違反「不靜默回傳看起來完整但實際殘缺」的原則——只是這次殘缺的不是缺了幾個到期日的列，是同一列裡缺了幾個欄位，但本質是一樣的「使用者看不出資料不完整」。**修正方向**：V&G 那層的 session 過期偵測，要跟 Options Prices 那層用同一套機制往上回報（同樣標 `partial_error`、同樣在 `result[:errors]` 寫出是哪個到期日的 V&G 抓取斷線），不能讓它安靜地降級成 null 欄位後就當作正常結果。
  - **已知缺漏（待補）**：migration 漏了 `vega` 欄位（第 5 節已批准但建表時漏寫），需要補一個小 migration 加這個欄位，不需重建整張表；gamma/theta/rho 維持不加。
- **階段 C**：✅ 已完成，兩項待補**已收到修復回報**：
  1. ✅ `DTE>=364` 已補：`fetch_candidates` 加 `.where("dte >= ?", 364)`，3 個新測試覆蓋排除邊界（DTE=363）、納入邊界（DTE=364）、明確排除 DTE=20（對應 NOK 實測案例）。
  2. ✅ **V&G merge bug 根因已確認，不是 code bug**：`_merge_vg` 的 key 比對邏輯本身正確（July 2/10 兩筆有值可佐證）。July 17 那兩筆 Vega=null 是因為**抓 V&G 頁面時 session 過期**，不是型態/格式不一致——這把問題從「merge 邏輯」改判定為「session 耐久性」，對應到上面階段 B 補的那個設計缺口，兩者是同一根因，已合併一起修。
- **階段 D**：⚠️ 已交付，但有一處需要修正後才算完成。`LeapsOptionsFlowPanelService`：
  - ✅ `aggregate` 原封不動轉交 `OptionsFlowClassifierService.aggregate`（只做 AR→hash 格式配接，無語義轉換）——符合「不重新發明分類邏輯」原則。
  - ✅ `highlighted_trades`／不影響排行排序（non-ranking guarantee 有測試覆蓋）——符合規格。
  - ❌ **需修正**：原規格這節被誤寫成「大單（`large_premium: true`，固定 $50萬門檎，數量不定）」，跟使用者最初提出的「前20大」（固定 20 筆，依 premium 降序）是兩個不同概念——**這是規格撰寫階段的錯誤改寫，不是 Phase D 實作偏離規格**，Phase D 當時完全照規格字面做是對的。已確認改回原始需求：`large_orders` 邏輯需從「filter by `large_premium` flag」換成「sort by premium desc, take 20」。`large_premium` 門檻可以保留做標記/icon 用，但不能用來決定面板抓取的資料範圍。**這個改動是局部的，不影響已驗收的 `aggregate`、`highlighted_trades`、non-ranking guarantee。**（這項已修正完畢，38/38 通過）
- **階段 C.5**：✅ 完全關閉。原始要求：V&G 抓取那一層偵測到 session 過期時，要往上回報成 `partial_error`，跟 Options Prices 那層用同一套機制，不能讓它降級成 null 欄位後被當成正常結果；`result[:errors]` 要明確區分是哪一層斷的，不能兩種都顯示同一句「Session 過期」。修法：`is None` 改成 `not vg_rows`／`not opts_rows`（同時涵蓋空陣列與 `None` 兩種失敗模式，不需要先確診當初真實情況是哪一種），spec comment 補上真實失敗模式說明（曾經懷疑當初真實情況是空陣列、不是 `None`，這個寫法直接涵蓋兩種，不用先確診）。4條新測試全過，commit 373d758。
- **階段 C.5b（新增）**：Controller CDP 連線預檢——✅ **完全關閉**。實測 port 9222 REJECT 時 `cdp_online?` 耗時 484ms（遠低於 1-2 秒要求）；錯誤訊息符合第8節措辭（含 wsl --shutdown 提示）；request spec 覆蓋「CDP 離線時擋下不送 job」情境（leaps_recommendations_spec.rb）。2026-06-30 驗收完畢。
- **階段 G（新增，不阻擋階段 F，可並行）**：實作第 4 節「鎖履約價、Stacked 檢視」抓取策略 → 確認
  - 驗證 V&G 頁面是否也支援同樣的 `?view=stacked&strike=X` 模式（待確認項，見第 4 節）
  - 重寫 `leaps_scraper.py` 的抓取邏輯：兩階段（Stage 1 用 Near the Money 檢視 + `Delta>=0.80` 估候選履約價 → Stage 2 鎖履約價拿全到期日資料），取代原本逐到期日序列爬，**也取代曾經考慮過的價格反推公式（已確認放棄，不要實作）**
  - 確認候選履約價數量覆蓋足夠範圍（上下各留緩衝），不能只鎖估計值剛好命中的那一檔
  - 新增：前端加選填的履約價輸入框，有值時直接當 Stage 1 輸出的中心履約價（跳過 Delta>=0.80 自動偵測），其餘流程（緩衝檔、Stage 2、最終 0.75–0.90 篩選）不變；單元測試覆蓋「手動輸入履約價但篩不出任何候選」時，畫面顯示明確原因，不留白、不誤判為查詢失敗
  - ⚠️ **已知缺陷，連續三次「回報已修復」但症狀完全沒變，這次必須附證據才能算修好**：履約價 `<input type="number">` 的 `step`/`min` 屬性設定錯誤，導致瀏覽器原生驗證跳出「請輸入有效值，最接近的兩個有效值分別是 6.51 和 7.01」，輸入合法值（例如 7）在**按下查詢送出表單時**被瀏覽器擋下，請求根本沒送到 Rails 後端。三次回報修復，重新測試都是同一句一字不差的警告文字——**這個模式本身值得懷疑：改動可能根本沒有真正生效到瀏覽器實際載入的版本**（Rails assets pipeline 快取、瀏覽器快取，或改動套用到沒被實際渲染路徑使用的檔案），不要再猜第四種 `step` 數值，先排除「改動有沒有真的送到瀏覽器」這個更上游的可能性。修復後**必須**附：(1) 該 input 目前 render 出來的完整 HTML（含 `type`/`step`/`min`/`max` 實際數值）；(2) 實際按下查詢按鈕後，Rails log 或 console 印出的請求參數，證明 `strike` 真的送達後端，不是只看「打字沒跳錯誤」就回報完成。
  - 確認 Stage 1 的 `0.80` 跟 Stage 2 的 `0.75–0.90` 沒有被合併成同一條規則（見驗收標準對應項）
  - 單元測試：驗證即使縮減了頁面導航次數，最終篩出的 Delta 0.75–0.90 候選跟舊版逐到期日序列爬的結果一致（用假資料模擬，確認兩種抓取策略產出同一份候選清單，不會因為換了抓取方式漏掉本該存在的候選）
  - 效能驗證：實測同一個 symbol，新策略的總頁面導航次數跟總耗時，跟舊策略對比，確認真的有縮短（這是這次修改的核心目的，要實際量出來，不是只看邏輯對不對）
- **階段 F（新增）**：實作第 6 節上半段「推薦分析」邏輯（新服務，暫名 `LeapsRecommendationService`）→ 確認
  - 輸入：`LeapsRankingService` 算好的候選清單（含 `DTE>=364` 篩選後的結果，依賴階段 C 的待補項目 1 先做完）
  - 輸出：近天期／遠天期兩組推薦，每組含挑選結果＋理由文字（第 6 節「理由文字生成規則」）
  - 這是新的呈現/分析層，不需要動到抓取層或 DB schema
  - 單元測試至少覆蓋：兩組挑選邏輯各自正確、「全部候選都有警示」的退回邏輯、「該組沒有任何候選」時明確顯示而非留白
- **階段 E**：⚠️ 三項已逐一確認，**兩項通過、一項未通過**：
  - ✅ 路由 namespace：`config/routes.rb` L116–124，LEAPS 路由（`leaps`、`leaps/analyze`、`leaps/status`）跟三維度儀表板（`technical_dashboard`）放在同一個 flat 區塊，符合「跟著既有路由同一層級」。
  - ✅ 導覽列：`app/components/fair_value/app_switcher_component.rb` 的 `APP_LINKS` 陣列有對應條目（href `/leaps`），掛在三維度判斷入口正下方。
  - ✅ **配色已補**：新增 `ApplicationComponent::SIGNAL_COLORS` 作為 5 個語義色階的單一定義來源；`LIQUIDITY_STYLE` 直接引用、`DIR_STYLE`／`DIV_META` 用 `.merge` 加各自專屬欄位，兩邊不再各自維護。Boot check + 29 條 spec 全通過，commit 7cba8b4。
  - ✅ D 的標題文字逐字核對：`page_component.rb` 確認顯示「Options Flow — 情緒參考，非排序依據」，跟規格要求的字串完全一致。
  - 錢誤訊息分情況顯示（第8節）、推薦分析區塊放置順序，已隨 Phase F/C.5b 落地，視為已完成。

每一步都要以實際讀到的 DOM／資料為準，不要假設或猜測欄位名稱與資料格式。

---

## 驗收標準 Checklist

- [x] 未登入 Barchart 時，系統正確中止並提示手動登入，沒有任何自動登入嘗試。
- [x] 三個頁面（Options Prices、Volatility & Greeks、Options Flow）的資料抓取全部走 DOM 解析或合法匯出，沒有呼叫任何內部 API 端點。
- [x] Volatility & Greeks 頁面的抓取範圍只限 Vega／itmProbability／volumeOpenInterestRatio 三欄，沒有額外抓 Gamma/Theta/Rho/Theoretical 或多餘欄位。
- [x] `vega` 欄位已補進 `leaps_option_chain_snapshots`（不需重建整張表），且排行表能正確顯示這個值；gamma/theta/rho 仍維持不加。
- [x] 5 分鐘 cache hit 時 `persist_leaps` 完全不會被呼叫；只有 cache miss 並成功（或 partial）抓取後才會刪除該 ticker 舊資料並寫入新資料，不會誤刪其他 ticker。
- [x] 登入狀態檢查只在 `fetch_leaps` 進入點做一次，沒有在個別 per-expiration scraper 裡重複檢查。
- [x] 中途 session 過期時，回傳結果包含已抓到的 rows、明確的 `expired_at_expiration`（斷在哪個到期日），且最終狀態標示為 partial/不完整，不會讓使用者誤以為表格是完整抓完的。
- [x] **（已修正方向）** 排行表格與推薦分析都套用 `DTE>=364`（52週）硬性下限——這是這次新加的修正，不是「不設天數門檻」；表格不會再出現 5、13、20 天這種明顯不是 LEAPS 的近期合約。排序仍只用 OI（主）+ DTE（次），沒有把 Options Flow 數字混進排序。
- [x] 流動性判斷（充足／普通／偏低）是程式依本次查詢候選的 OI 相對排名動態算出，不是寫死一個固定 OI 數字套用在所有標的上。
- [x] 「近期無成交」警示用 Barchart 算好的 `vol_oi_ratio` 判斷，沒有沿用舊版規格的 `volume<=3` 門檻（尺度不同，不能直接搬）。
- [x] OI／Volume 欄位同時顯示 Barchart 原始數值與程式算出的流動性判斷結果，兩者都看得到。
- [x] **（新增）** 頁面最上方有獨立的「推薦分析」區塊，近天期／遠天期各一組明確建議＋完整理由文字（到期日、履約價、Delta、跟次選的 OI/流動性對比、Time Value%、Spread%、Vega/IV 佐證），不是又一張表格；下半段完整排行表維持表格形式，不寫每列理由。
- [x] **（新增）** 某個天期區間沒有任何符合條件的候選時，畫面明確顯示「此天期區間目前沒有符合條件的候選」，不是留白或整段消失。
- [x] **（新增）** 若某組推薦本身帶有「近期無成交」警示（因為該組全部候選都有警示），理由文字裡有明確點出這個警示，沒有因為它是「推薦」就把警示蓋掉不提。
- [x] Options Flow 面板直接複用既有 `OptionsFlowTrade` model，獨立顯示，標題清楚標示「情緒參考，非排序依據」。
- [x] 面板顯示的是**真正的前 20 大**：依 `premium` 降序排序取前 20 筆，固定數量（可少於20筆但不會更多），**不是**用 `large_premium` 固定金額門檻篩出來的不定數量清單；有單元測試覆蓋「當天 large_premium=true 的交易數超過20筆」與「當天 0 筆 large_premium=true」這兩種邊界情況，驗證兩種情況下都還是回傳依 premium 排序的前 20 筆（或不足20筆時的全部），不會因為金額門檻而漏掉或多顯示。
- [x] V&G session 過期已正確傳播為 `partial_error`：模擬 V&G 單獨斷線（Options Prices 正常）的情境，`result[:status]` 確實變成 `partial_error`，不會安靜降級成 Vega/itm_probability 為 null 但整體狀態顯示成功；`result[:errors]` 訊息能區分是 Options Prices 斷線還是 V&G 斷線。**已完成，4條測試全過，commit 373d758。**
- [x] **（新增）** 抓取改用「鎖履約價、Stacked 檢視」兩階段策略：第一階段用 Near the Money 檢視的 Delta 欄位（不是價格反推公式）篩 `Delta>=0.80` 估候選履約價、第二階段針對這些履約價（含上下緩衝）各拿全到期日資料，取代逐到期日序列爬；同一 symbol 的總頁面導航次數有實測下降，且最終候選清單跟舊版逐到期日序列爬的結果一致（沒有因為換抓取方式漏掉本該存在的候選）。
- [x] **（新增）** `0.80` 跟 `0.75–0.90` 是兩條不同用途的規則，沒有被誤合併成同一個門檻：Stage 1 用 `Delta>=0.80`（無上限）挑要鎖定的履約價，Stage 2 拿到完整資料後仍套用 `0.75–0.90` 區間做最終篩選——有測試覆蓋「Stage 1 選中的履約價，在某個到期日 Delta 實際落在 0.80–0.90 之間」跟「同一履約價在另一個到期日 Delta 超過 0.90 或低於 0.75」這兩種情況，驗證 Stage 2 篩選確實會把後者排除，不會因為 Stage 1 篩過就直接收進最終候選。
- [x] **（待修）** 奇數列底色實際 class 是 `bg-gray-50/50`（含透明度），目前回報的是 `bg-gray-50`（缺 `/50`），需要補上透明度後再驗收一次畫面。
- [x] **（新增，⚠️已連續三次「回報已修復」但症狀未變，不接受第四次空話）** 履約價輸入框為選填：留空時走 Stage 1 自動偵測（Delta>=0.80），填了則直接取代 Stage 1 輸出、當 Stage 2 的中心履約價，上下緩衝檔/最終 0.75–0.90 篩選邏輯不變；手動輸入但完全篩不出候選時，畫面明確顯示原因（輸入值不適合做 LEAPS），不是空白或誤判成查詢失敗。**`step`/`min` 驗證 bug 必須附完整 HTML 屬性數值＋按下查詢後的 Rails log/console 請求參數證據才算修復，且要先排除「改動沒真正生效到瀏覽器」這個可能性。**
- [x] 同一 symbol 5 分鐘內重複查詢會讀快取，不重複打 Barchart。
- [x] 表格下方有「僅供策略篩選參考，非投資建議」提示文字。
- [x] **（新增）** Controller 在送出抓取 job 前先做 CDP 連線預檢，連不上時在 1-2 秒內回報明確訊息（提示檢查 Windows Chrome 的 remote-debugging port），不是等 job 跑到 scraper 內部才在 13 秒後報錯；有測試覆蓋「CDP 離線時 controller 直接擋下不送 job」這個情境。
- [x] 抓取失敗時的畫面訊息依 `result[:status]` 分情況顯示（未登入／CDP預檢失敗／partial_error 帶出實際斷點到期日與斷線層級／其他例外），不是共用同一句固定字串；驗收時實際觸發過這四種情況各看一次畫面。
- [x] 配色（卡片底色、邊框、綠/橘黃/紅語義色、hover 效果）直接讀取並複用三維度儀表板既有的 CSS/變數，沒有另外設計一套新色票；流動性分級與 Options Flow 看多/看空判斷的顏色語義跟 `divergence_flag` 的 confirm/warning/caution 對應一致。**已完成：`ApplicationComponent::SIGNAL_COLORS` 單一定義來源，`LIQUIDITY_STYLE` 直接引用、`DIR_STYLE`/`DIV_META` 用 `.merge` 加專屬欄位，commit 7cba8b4。**
- [x] 新路由跟既有三維度儀表板/IV Skew 相關路由放在同一 namespace／層級下，不是憑空另開一個不相關的頂層路由。
- [x] 導覽列/選單裡有連結可以直接點進 LEAPS 頁面，不需要手動輸入網址。

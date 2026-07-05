# LEAPS Call 規格歷史記錄

> 本檔為 `leaps-call-recommendation-spec.md` 的歷史歸檔（2026-07-05 搬移），內容為逐字剪貼、不作改寫或濃縮。**現行有效規範一律以主文件為準**；本檔僅在追查歷史問題時讀取。

## 第 1 節：接手前必讀原文與事件記錄（原主文件標頭、-1／0／0.1／0.2／2／3／4 節）

## ✅ 接手前必讀：功能已結案（2026-07-02）。⚙️ **2026-07-03 補充修復**：`leaps_scraper.py` 抓取誤判 bug（固定 sleep 導致 `bc-data-grid._data` 未載入即誤判 session 過期）已修復，見第3節與第4節補充記錄。🆕 **2026-07-04 新增 Phase H（未開始；檔頭原標「進行中」，經程式碼核對 schema 尚無新欄位、實為零進度，已更正）**：`leaps_option_chain_snapshots` 加入 `intrinsic_value`／`extrinsic_value` 兩個衍生欄位（以 Mid 計算），排行表新增外在價值/外在佔比顯示欄，見「Phase H」一節。🆕 **2026-07-04 新增 Phase I（未開始）**：LEAPS 頁面右上角加「匯出 PNG／匯出 PDF」按鈕（純前端 client-side，整頁完整匯出），見「Phase I」一節。原結案範圍不受影響；Phase H/I 是使用者明確決定附加在本規格的小型增量（跟本功能頁面緊密耦合，不值得另開文件），不是推翻「新功能另開規格」的原則。

**這份規格記錄了 LEAPS 功能從 Phase A 到目前的完整開發脈絡。2026-06-30 曾一度標記「結案」，後續發現多個新問題，結案標記一度撤回。✅ **2026-07-02 全部未解問題已確認並結案**（見第3、4節）。新 session 若有新功能需求，請另開新規格文件。**

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

### 0.2 CDP 連不上時的標準診斷流程（30秒以內）

每次遇到 CDP 連不上，不要猜，先跑這三行：

```bash
curl -s http://localhost:9222/json/version | head -3
pm2 status cdp-relay
ls /mnt/c/ 2>&1 | head -3
```

根據結果判斷：

| 症狀 | 根因 | 對策 |
|---|---|---|
| `curl` 失敗 + `ls /mnt/c/` 出現 I/O error | 電腦睡眠/喚醒後 `/mnt/c/` 掛載失效 | Windows PowerShell 執行 `wsl --shutdown`，等 WSL2 重啟後重試 |
| `curl` 失敗 + `ls /mnt/c/` 正常 + `pm2 status` 顯示 cdp-relay `stopped` | `cdp-relay` process 死掉 | WSL2 執行 `pm2 restart cdp-relay` |
| `curl` 失敗 + `ls /mnt/c/` 正常 + `pm2 status` 顯示 cdp-relay `online` | Chrome 沒有帶 `--remote-debugging-port=9222` 啟動 | Windows 端關掉 Chrome，用正確參數重新啟動 |
| `curl` 成功 + `pm2 status` 顯示 cdp-relay `online` 但工具還是連不上 | `playwright-mcp` 本身的問題（見第0節） | 先呼叫一次 `mcp__playwright-chrome__browser_navigate` 確認工具狀態 |
| `browser_navigate` 逾時 30 秒以上，`curl` 跟 `cdp-relay` 都正常 | 多個 session 的 `playwright-mcp` process 殘留，搶同一條 Chrome CDP 連線互相干擾（session crash 或強制中斷時 cleanup 沒有正確執行） | 先查：`ps aux \| grep playwright-mcp \| grep -v grep`，如果超過一行代表有殘留，執行 `pkill -f playwright-mcp` 全部清掉，讓 Claude Code 自動啟動乾淨的新 process |

> **2026-07-02 已自動化**：`~/.claude/hooks/stop-playwright-cleanup.sh` 已加入全域 Stop hook，每次任何 Claude Code session 結束時自動執行 `pkill -f playwright-mcp`，清掉殘留 process，不再需要手動介入。注意：這是全域 hook，不限 FairPrice 專案；若同時開兩個 Claude Code session，其中一個結束時會連帶清掉另一個 session 正在用的 playwright-mcp process。

**長期對策（還沒設定的話，這個才是真正能讓 CDP 不再每次手動修的方法）**：設定 Windows 工作排程器，在電腦喚醒時自動執行：
1. `wsl --shutdown`
2. 等待幾秒
3. 重新啟動 Chrome（帶 `--remote-debugging-port=9222`）

這樣睡眠/喚醒後不需要手動介入。設定方式參考專案根目錄的 `cdp-precheck-global-rule.md`。



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
| Phase A–F、C.5、C.5b、E 配色共用 | ✅ 已驗證完成 |
| Phase G（Stacked 抓取策略） | ✅ 已驗證完成 |
| 履約價輸入框 step bug | ✅ 已關閉（三項證據齊全） |
| `mcp__playwright-chrome__*` 工具連線 | ✅ 2026-06-30 實際呼叫確認可用；⚠️ **已知反覆發生問題**：多個 session 的 `playwright-mcp` process 殘留會互相搶 CDP 連線導致逾時，解法是 `pkill -f playwright-mcp` 清掉殘留，Claude Code 會自動啟動乾淨的新 process；詳見第0.2節第五種情況；✅ **2026-07-02 已自動化**：`~/.claude/hooks/stop-playwright-cleanup.sh` 加入全域 Stop hook |
| `bg-gray-50/50` 奇數列透明度 | ✅ 2026-06-30 親眼確認 |
| Checklist 同步 | ✅ 2026-06-30 完成 |
| CDP 連線異常 | ✅ 根因查出（cdp-relay 死亡），已重啟，C.5b 484ms 達標；⚠️ **2026-07-02 二度發生**：cdp-relay 再次停止（SIGINT 根因未明）＋ 3 個 playwright-mcp 殘留 process 搶 CDP 連線，`browser_navigate` 逾時 30 秒；已 pm2 restart cdp-relay + kill -9 殘留 process，工具恢復正常 ✅ |
| 錯誤訊息分四種情況顯示 | ✅ 2026-06-30 修完，23/23 spec 通過 |
| `FetchLog`/`log_fetch` bug | ✅ 2026-06-30 修完 |
| partial_error UX（expire strike vs 推薦 strike 重疊判斷） | ✅ 2026-07-01 修完，23/23 spec 通過 |
| partial_error + fresh data 空白頁 | ✅ 2026-07-01 修完，60/60 spec 通過 |
| Delta 篩選範圍放寬（0.75–0.90 → 0.60–0.90） | ✅ 程式碼+測試完成（60 通過）；✅ **2026-07-02 Rails runner 驗證**：DEFAULT_DELTA_MIN=0.60 確認，NOK DTE≥364 候選 delta 均在 0.83–0.87（市場本身無 0.60–0.75 深度價內候選，屬正常市場現象） |
| KLAC 空白頁（partial + fresh data）截圖驗收 | ✅ **2026-07-02 snapshot 驗證**：模擬 partial_error + fresh data，banner 顯示「⚠️ 抓取中途發生未預期錯誤，部分資料可能不完整，請重新查詢」，非「CDP 未連線」，顯示邏輯正確 |
| NOK 0.60–0.75 段候選實際出現在排行表 | ✅ **2026-07-02 確認**：市場資料特性，NOK DTE≥364 選擇權 delta 均在 0.83–0.87，此天期無 0.60–0.75 深度價內候選屬正常現象；程式碼邏輯（DEFAULT_DELTA_MIN=0.60）確認正確，不是 bug |
| asyncio traceback 根因 | ⚠️ **未知**：`/tmp/nok_stderr.txt` 已被清除，需重現才能查 |
| `bc-data-grid._data` 未載入即誤判 session 過期（固定 sleep 問題） | ✅ **2026-07-03 修復**：`_wait_for_grid()` 輪詢取代固定 sleep，Stage 1 NTM 頁同步改輪詢；三分類（None/[]/data）+ `_confirm_empty()` 穩定性確認；`reason` 字段區分 `session_expired` vs `page_load_timeout`；17/17 unit tests 通過；E2E 無 user_strike NOK 完整跑完（104 rows）；commit `4012075` |

### 4. 目前進行中——未完成項目與接手順序

✅ **2026-07-02 全部項目完成，結案**：

~~1. **先解決 CDP 連線問題**~~ ✅ **2026-07-02 完成**：cdp-relay 重啟 + playwright-mcp 殘留清理 + Stop hook 自動化，CDP 已正常。
~~2. **NOK 不帶履約價完整查詢**：確認 Delta 0.60–0.75 段候選有正確出現在排行表，附截圖。~~ ✅ **2026-07-02 完成**：Rails runner 驗證 DEFAULT_DELTA_MIN=0.60；NOK DTE≥364 候選 delta 0.83–0.87，無 0.60–0.75 段候選屬市場現象非 bug。
~~3. **KLAC 空白頁截圖驗收**：模擬 partial_error + fresh data 情境，截圖確認 banner 文字正確（不是「CDP未連線」）。~~ ✅ **2026-07-02 完成**：snapshot 確認 partial_error banner 顯示正確（非「CDP 未連線」）。
4. 以上三項全部完成 ✅ → 結案標記恢復。

如果之後有新功能需求（例如 PMCC 短腿選擇），應另開新規格文件，不要在這份繼續累加。



**補充驗證記錄（2026-06-30）**：NOK 不帶履約價的 Stage 1 自動偵測路徑已於此時驗證通過。同日修復了 `cdp_helper.py` `prepare_page` 的 skip-navigation bug（Chrome 停在任意 `/options` URL 時會跳過導航），修復後 `leaps_scraper.py` 強制導航至 `?moneyness=10` Near the Money SBS view。實測輸出：Stage 1 自動偵測找到 20 筆近價行權價資料、候選行包括 strikes 8.5–10.5；Stage 2 在 strike=10 取得 DTE 535/570/717/899 的 LEAPS 資料（delta 0.780–0.796，落在 0.60–0.90 篩選範圍內）。`persist_leaps` 在 `when "partial"` 分支同樣執行，已抓到的資料會入庫，不因 strike 11 的 partial 而遺失。

⚠️ **結案後仍有三個未解決問題，重開後需要繼續追蹤：**

1. **`asyncio/base_events` traceback 根因未知**：上一個 session 在跑 NOK 測試時，曾出現一個被截斷的 `asyncio.run` → `runners.py` → `base_events.py` 例外，完整訊息從未被取得。Claude Code 在回答這個根因時，session 本身直接崩掉（回答被截斷在「上一個 session 失敗的 NOK 跑（DB 裡截斷在 asyncio/bas）是獨」），所以這個例外的完整內容跟根因至今不明。**重開後第一件事：先去找 `/tmp/nok_stderr.txt`，把完整內容貼出來確認根因。如果檔案不存在，告知後再討論怎麼重現。確認是不是已被 `prepare_page` 的 skip-navigation bug 修復所連帶解決，還是獨立問題。**

   📋 **2026-07-01 調查結果**：`/tmp/nok_stderr.txt` 不存在（系統重開後 `/tmp` 已清除）。這個 traceback 無法從暫存檔取回，需要重新觸發 NOK 無履約價查詢才能重現。在重現之前，這條根因仍屬未知。

   📋 **2026-07-03 後續推斷**：最可能的根因是 `bc-data-grid._data` 在固定 sleep 結束後仍為 null，scraper 誤判為 session 過期後以異常路徑退出，asyncio event loop 在不乾淨的狀態下被強制終止，產生 traceback。2026-07-03 改用 `_wait_for_grid()` 輪詢後，Stage 1 和 Stage 2 的 None 路徑都改走正常 `json.dumps()` → `return` 退出，不再觸發 event loop 的邊緣情況。**NOK 無 user_strike E2E 實測（104 rows，全程無 exception）支持此推斷。視為連帶解決，不需要再重現。**

2. **`prepare_page` skip-navigation bug 影響範圍未評估**：這個 bug（Chrome 停在任意 `/options` URL 時 `prepare_page` 跳過導航）在這次 NOK 無履約價測試才被發現。之前所有帶 `user_strike` 的測試（包括 NVTS 那次），如果當時 Chrome 剛好停在某個舊 URL，Stage 1 或 Stage 2 可能也讀到了錯誤頁面的資料，只是剛好沒觸發明顯的失敗症狀。這個 bug 的影響範圍需要評估：之前那些「成功」的測試，有沒有可能其實是在錯誤的頁面狀態下跑的，只是剛好 Chrome 停在正確的 URL 所以沒出事。

   ✅ **2026-07-01 評估完成，影響範圍確認為：無**。根因是 `leaps_scraper.py` 在 `prepare_page` 之後立刻強制導航（`L263–264`：`cdp_navigate(ntm_url, settle_ms=OPTIONS_SETTLE)`），Stage 2 每個 strike 同樣各自有 `cdp_navigate`（Options L299、V&G L322）。所有資料讀取都發生在各自的強制導航之後，`prepare_page` 的 skip-navigation 步驟只是「找到 tab + 等 500ms」，即使跳過，後續的強制導航仍會把頁面帶到正確 URL。因此 NVTS 等帶 `user_strike` 的歷次測試資料可信度不受這個 bug 影響，可關閉此疑慮。

3. **`partial_error` 警示與推薦分析同時顯示的 UX 問題**：截圖現象：「Session 在抓取 Strike 12 的 V&G 時過期」黃色 banner 跟下方推薦分析（推薦 Strike 10）同時出現，使用者看不出這個警示是否影響推薦結果的可信度。修法：判斷 `expired_at_strike` 是否跟推薦候選 strike 重疊：
   - **不重疊**（本次：strike 12 過期，但推薦是 strike 10）→ 改顯示「Strike 12 的 V&G 資料不完整，但不影響本次推薦（推薦候選為 Strike 10）」
   - **重疊**（過期的 strike 剛好是推薦候選）→ 在推薦卡片上直接標示「⚠️ 此推薦的 Vega/被指派機率資料可能不完整」

   `partial_error` 時推薦分析仍顯示這件事本身是對的，不要因為有一個 strike 缺 V&G 就整頁空白，但要讓使用者看得出哪些資料是完整的、哪些是缺的。

   ✅ **2026-07-01 修復完成**。`page_component.rb` 新增：
   - `partial_error_strike`：從 `@scrape_errors.first` 用 regex 解出 `Strike N` 數值（memoized）
   - `recommendation_strikes`：取近/遠天期推薦的 strike 清單
   - `fmt_strike_short`：整數顯示整數（10），小數保留小數（10.5）
   - `:partial_error` banner：不重疊時顯示「Strike N 的 V&G 資料不完整，但不影響本次推薦（推薦候選為 Strike M）」；重疊或無法解析時沿用原始錯誤訊息
   - `render_recommendation_group`：重疊時在推薦 badge 旁加「⚠️ 此推薦的 Vega/被指派機率資料可能不完整」
   - 23/23 spec 通過

**補充驗證記錄（2026-07-01）— Delta 篩選範圍放寬**：Stage 1 候選門檻由 `Delta>=0.80` 放寬至 `Delta>=0.60`，Stage 2 最終篩選由 `0.75–0.90` 放寬至 `0.60–0.90`。涉及 `leaps_scraper.py`（`_pick_candidates` 條件 + 相關 comment）、`LeapsRankingService`（`DEFAULT_DELTA_MIN 0.75 → 0.60`）、`leaps_ranking_service_spec`（邊界測試 `0.74/0.75 → 0.59/0.60`、`be_between(0.60, 0.90)`）。全部 60 examples 通過，Stage 1/Stage 2 分離規則測試隨新數值一起更新，邏輯不變。⚠️ CDP 修改當日離線，NOK 實際抓取驗證（確認 0.60–0.75 段候選有正確出現）待 Chrome 連線後補跑。

**補充驗證記錄（2026-07-01）— `partial_error` + fresh data 空白頁修復**：當 Barchart 未登入時 scraper 回傳 `partial`（非 `session_expired`），`persist_leaps` 仍將資料寫入 DB（5 分鐘 fresh window 有效）。首次點擊 `?job_status=partial_error` 顯示 banner 正常，但後續點擊（5 分鐘內）controller 走 `fresh_data_exists? = true` → `LeapsRankingService` 因 delta/DTE 條件回傳 `[]` → `@scrape_status = :cached` → 空白頁無任何提示。修復：`LeapsRecommendationsController#index` 在 `fresh_data_exists? && @candidates.empty? && @scrape_status == :cached` 時讀 `Rails.cache.read("leaps_last_errors_#{@symbol}")`：有 errors → 設 `:partial_error`（復用現有 banner 邏輯）；無 errors → 設 `:no_candidates`。同步更新 `barchart_scraper_service.rb` partial_error 訊息末尾加「請重新登入 Barchart 後點查詢重試」。補兩個 RSpec request spec 驗證 fallback 路徑，60/60 examples 通過。

**補充驗證記錄（2026-07-03）— `bc-data-grid._data` 誤判修復（輪詢取代固定 sleep）**：
問題：Stage 2（Options Prices / V&G）和 Stage 1（NTM 頁）的 `cdp_navigate` 後固定 sleep，`bc-data-grid._data` 從其他 URL 切換過來時不一定能在 sleep 結束前載入，導致 null 被誤判為 session 過期，`status=barchart_session_expired` 提前中止。實測：NOK user_strike=7 CLI 跑通但 E2E（無 user_strike）固定失敗，根因鎖定在 Stage 1 NTM 頁 STAGE1_SETTLE=5000ms 不夠。
修復：(1) `_wait_for_grid(ws_url, js, max_wait_s=30, poll_s=0.5)` — 每 500ms 輪詢，第一個非 None 立即返回，取代所有固定 sleep；(2) `_confirm_empty(ws_url, js, delay_s=1.5)` — `[]` 結果 1.5s 二次確認；(3) Stage 1 NTM 改用 `_wait_for_grid`（原先 `STAGE1_SETTLE=5000ms` 固定 sleep）；(4) `SESSION_EXPIRED_JS` 在 None 路徑提供真正的 session 過期偵測；(5) `reason` 字段區分 `session_expired` vs `page_load_timeout`；(6) `skipped_strikes` 字段記錄跳過的 strike/layer。
驗收：17/17 unit tests（三分類 + SESSION_EXPIRED_JS false-positive）；CLI `python3 leaps_scraper.py NOK 7` itm_probability/vega/delta 全有值；E2E 無 user_strike NOK 104 rows 入庫，推薦分析正常顯示；commit `4012075`，push `8092340`。

---

## 第 2 節：執行方式各階段交付記錄（階段 A／B／C／D／C.5／C.5b／G／F／E）

- **階段 A**：✅ 已完成（第 4 節）。確認結果：方案 A + Vega + itmProbability + volumeOpenInterestRatio，Options Prices 為主要來源，Volatility & Greeks 頁面額外取上述 3 欄（merge key `(strike_price, expiration_date)` 兩頁完全對得上），Gamma/Theta/Rho/Theoretical 不抓；Options Flow 既有 `OptionsFlowTrade` model 直接複用，不需新寫抓取邏輯。
- **階段 B**：✅ 已完成。實際交付：
  1. `db/migrate/..._create_leaps_option_chain_snapshots.rb` 建表（`leaps_option_chain_snapshots`，已確認跟既有 `option_snapshots` grain 不同、FK 結構不同，新表是必要的）
  2. `app/models/leaps_option_chain_snapshot.rb`（含 `for_symbol` / `calls` / `fresh` scope）
  3. `lib/barchart_scrapers/leaps_scraper.py`（Options Prices + V&G 合併抓取，session 過期中止並回傳 partial）
  4. `BarchartScraperService` 新增 `fetch_leaps`（5 分鐘 cache：cache hit 直接 return，**`persist_leaps` 完全不執行**；cache miss 才呼叫 scraper）、`persist_leaps`（`where(symbol: @symbol).delete_all` 只刪當前 ticker 資料 + bulk insert）、`run_scraper` 支援 partial 狀態（🆕 **2026-07-04 註記**：cache 時長「5 分鐘」已被「排程」一節的設計修正記錄覆蓋為 **30 分鐘**，cache hit/miss 的行為邏輯不變，只有時長數值改變）
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
  - 重寫 `leaps_scraper.py` 的抓取邏輯：兩階段（Stage 1 用 Near the Money 檢視 + `Delta>=0.60` 估候選履約價 → Stage 2 鎖履約價拿全到期日資料），取代原本逐到期日序列爬，**也取代曾經考慮過的價格反推公式（已確認放棄，不要實作）**
  - 確認候選履約價數量覆蓋足夠範圍（上下各留緩衝），不能只鎖估計值剛好命中的那一檔
  - 新增：前端加選填的履約價輸入框，有值時直接當 Stage 1 輸出的中心履約價（跳過 Delta>=0.60 自動偵測），其餘流程（緩衝檔、Stage 2、最終 0.60–0.90 篩選）不變；單元測試覆蓋「手動輸入履約價但篩不出任何候選」時，畫面顯示明確原因，不留白、不誤判為查詢失敗
  - ⚠️ **已知缺陷，連續三次「回報已修復」但症狀完全沒變，這次必須附證據才能算修好**：履約價 `<input type="number">` 的 `step`/`min` 屬性設定錯誤，導致瀏覽器原生驗證跳出「請輸入有效值，最接近的兩個有效值分別是 6.51 和 7.01」，輸入合法值（例如 7）在**按下查詢送出表單時**被瀏覽器擋下，請求根本沒送到 Rails 後端。三次回報修復，重新測試都是同一句一字不差的警告文字——**這個模式本身值得懷疑：改動可能根本沒有真正生效到瀏覽器實際載入的版本**（Rails assets pipeline 快取、瀏覽器快取，或改動套用到沒被實際渲染路徑使用的檔案），不要再猜第四種 `step` 數值，先排除「改動有沒有真的送到瀏覽器」這個更上游的可能性。修復後**必須**附：(1) 該 input 目前 render 出來的完整 HTML（含 `type`/`step`/`min`/`max` 實際數值）；(2) 實際按下查詢按鈕後，Rails log 或 console 印出的請求參數，證明 `strike` 真的送達後端，不是只看「打字沒跳錯誤」就回報完成。
  - 確認 Stage 1 的 `0.60` 跟 Stage 2 的 `0.60–0.90` 沒有被合併成同一條規則（見驗收標準對應項）
  - 單元測試：驗證即使縮減了頁面導航次數，最終篩出的 Delta 0.60–0.90 候選跟舊版逐到期日序列爬的結果一致（用假資料模擬，確認兩種抓取策略產出同一份候選清單，不會因為換了抓取方式漏掉本該存在的候選）
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

## 第 3 節：驗收標準 Checklist（已完成項目與證據，含 fresh window／Phase H／Phase I）

## 驗收標準 Checklist

- [x] 未登入 Barchart 時，系統正確中止並提示手動登入，沒有任何自動登入嘗試。
- [x] 三個頁面（Options Prices、Volatility & Greeks、Options Flow）的資料抓取全部走 DOM 解析或合法匯出，沒有呼叫任何內部 API 端點。
- [x] Volatility & Greeks 頁面的抓取範圍只限 Vega／itmProbability／volumeOpenInterestRatio 三欄，沒有額外抓 Gamma/Theta/Rho/Theoretical 或多餘欄位。
- [x] `vega` 欄位已補進 `leaps_option_chain_snapshots`（不需重建整張表），且排行表能正確顯示這個值；gamma/theta/rho 仍維持不加。
- [x] ~~5 分鐘~~ cache hit 時 `persist_leaps` 完全不會被呼叫；只有 cache miss 並成功（或 partial）抓取後才會刪除該 ticker 舊資料並寫入新資料，不會誤刪其他 ticker。（🆕 2026-07-04：時長改為 30 分鐘，見下方 fresh window 區塊；hit/miss 行為本身已驗收，不需重驗）
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
- [x] **（新增）** 抓取改用「鎖履約價、Stacked 檢視」兩階段策略：第一階段用 Near the Money 檢視的 Delta 欄位（不是價格反推公式）篩 `Delta>=0.60` 估候選履約價、第二階段針對這些履約價（含上下緩衝）各拿全到期日資料，取代逐到期日序列爬；同一 symbol 的總頁面導航次數有實測下降，且最終候選清單跟舊版逐到期日序列爬的結果一致（沒有因為換抓取方式漏掉本該存在的候選）。
- [x] **（新增）** `0.60` 跟 `0.60–0.90` 是兩條不同用途的規則，沒有被誤合併成同一個門檻：Stage 1 用 `Delta>=0.60`（無上限）挑要鎖定的履約價，Stage 2 拿到完整資料後仍套用 `0.60–0.90` 區間做最終篩選——有測試覆蓋「Stage 1 選中的履約價，在某個到期日 Delta 實際落在 0.60–0.90 之間」跟「同一履約價在另一個到期日 Delta 超過 0.90 或低於 0.60」這兩種情況，驗證 Stage 2 篩選確實會把後者排除，不會因為 Stage 1 篩過就直接收進最終候選。
- [x] **（待修）** 奇數列底色實際 class 是 `bg-gray-50/50`（含透明度），目前回報的是 `bg-gray-50`（缺 `/50`），需要補上透明度後再驗收一次畫面。
- [x] **（新增，⚠️已連續三次「回報已修復」但症狀未變，不接受第四次空話）** 履約價輸入框為選填：留空時走 Stage 1 自動偵測（Delta>=0.60），填了則直接取代 Stage 1 輸出、當 Stage 2 的中心履約價，上下緩衝檔/最終 0.60–0.90 篩選邏輯不變；手動輸入但完全篩不出候選時，畫面明確顯示原因（輸入值不適合做 LEAPS），不是空白或誤判成查詢失敗。**`step`/`min` 驗證 bug 必須附完整 HTML 屬性數值＋按下查詢後的 Rails log/console 請求參數證據才算修復，且要先排除「改動沒真正生效到瀏覽器」這個可能性。**
- [x] 同一 symbol ~~5 分鐘~~ 內重複查詢會讀快取，不重複打 Barchart。（🆕 2026-07-04：時長改為 30 分鐘，需依下方 fresh window 區塊重新驗收時長）

### 🆕 fresh window 5 → 30 分鐘（2026-07-04 新增；✅ 2026-07-04 全部驗收完成 commit `2e46139`，證據如下。⚠️ 2026-07-04 晚間曾因規格從舊版覆蓋被誤還原為未驗收，已恢復——本段狀態以 commit `2e46139` 為準）

- [x] 建立單一常數 `LeapsOptionChainSnapshot::FRESH_WINDOW = 30.minutes`：model `fresh` scope 引用它；`fetch_leaps` 與 `fresh_data_exists?` 都透過 `fresh` scope 判斷（單一路徑）；`ScrapeLeapsJob` 的 4 處 `Rails.cache` `expires_in` 與 controller 的 `leaps_job_*` pending 快取全部改引用常數。
- [x] grep 證據（`5\.minutes|expires_in.*300` 掃 `app/ lib/`）：LEAPS 相關檔案零殘留。僅存 4 筆命中全屬無關功能（`technical_dashboards_controller` 的 `td_job_*` pending ×2、`api/v1/options_controller` 的 `CACHE_TTL`/`options_price` 快取 ×2），各有自己的 TTL 語義，不在本節範圍。
- [x] 邊界測試（`travel_to` + `FRESH_WINDOW ± 1.minute`，無寫死分鐘數）：`spec/models/leaps_option_chain_snapshot_spec.rb`（scope 邊界 + 常數值釘住 30.minutes）＋ `spec/requests/leaps_recommendations_spec.rb` 第 9 區塊（真實 DB rows 不 stub：窗內 → `ready` 不排 job；窗外 → 排 job）。全套 337 examples, 0 failures。
- [x] 核心情境實測（2026-07-04）：NOK 第一次查詢 22:20:20 (+0800) → `Enqueued ScrapeLeapsJob`，22:21:51 入庫；**間隔 5 分 54 秒**（>5 分 <30 分鑑別區間）後 22:27:45 重查 → Rails log 僅一條 `LeapsOptionChainSnapshot Exists?` 查詢即 `Completed 200`，**無 `Enqueued ScrapeLeapsJob`**，analyze 回 `ready` 直接渲染頁面。舊 5 分鐘行為在此區間必定重爬，證明新行為生效。
- [x] 表格下方有「僅供策略篩選參考，非投資建議」提示文字。
- [x] **（新增）** Controller 在送出抓取 job 前先做 CDP 連線預檢，連不上時在 1-2 秒內回報明確訊息（提示檢查 Windows Chrome 的 remote-debugging port），不是等 job 跑到 scraper 內部才在 13 秒後報錯；有測試覆蓋「CDP 離線時 controller 直接擋下不送 job」這個情境。
- [x] 抓取失敗時的畫面訊息依 `result[:status]` 分情況顯示（未登入／CDP預檢失敗／partial_error 帶出實際斷點到期日與斷線層級／其他例外），不是共用同一句固定字串；驗收時實際觸發過這四種情況各看一次畫面。
- [x] 配色（卡片底色、邊框、綠/橘黃/紅語義色、hover 效果）直接讀取並複用三維度儀表板既有的 CSS/變數，沒有另外設計一套新色票；流動性分級與 Options Flow 看多/看空判斷的顏色語義跟 `divergence_flag` 的 confirm/warning/caution 對應一致。**已完成：`ApplicationComponent::SIGNAL_COLORS` 單一定義來源，`LIQUIDITY_STYLE` 直接引用、`DIR_STYLE`/`DIV_META` 用 `.merge` 加專屬欄位，commit 7cba8b4。**
- [x] 新路由跟既有三維度儀表板/IV Skew 相關路由放在同一 namespace／層級下，不是憑空另開一個不相關的頂層路由。
- [x] 導覽列/選單裡有連結可以直接點進 LEAPS 頁面，不需要手動輸入網址。

### 🆕 Phase H（2026-07-04 新增；✅ 2026-07-04 全部驗收完成，證據如下）

- [x] Migration `20260704151000` 只加 `intrinsic_value`、`extrinsic_value` 兩欄（decimal 10,4 對齊 bid/ask，允許 null）；「外在佔比」未落地（display 層 `calc_extrinsic_pct` 計算）。
- [x] 計算在 Ruby persist 層：`LeapsOptionChainSnapshot.derived_values`（公式唯一定義處）由 `persist_leaps` 每筆呼叫；`git diff` 證明 `leaps_scraper.py` 零改動（0 changed files）。
- [x] 權利金基準 `mid = (bid + ask) / 2`；`derived_values` 公式內無 `last_price`。
- [x] 公式依 `option_type` 分支（`casecmp("put")`）；put ITM/OTM 兩條單元測試釘住。
- [x] bid/ask/underlying_price 任一 null → 兩欄皆 null（三條單元測試）；display 層 mid ≤ 0 或缺值 → 佔比 nil → 畫面「—」（ranking spec + request spec 驗證，無 NaN）。
- [x] 舊 rows backfill：migration `up_only` SQL（同公式含 Put 分支與 null 規則）；實測 NOK 舊 row（strike 7, bid 4.7/ask 5.65, spot 12.07）backfill 值 5.07/0.105 與 `derived_values` 輸出一致。
- [x] `time_value_pct` 改讀已存 `extrinsic_value`；排行層重複公式已移除。單一來源測試：故意存入與公式不符的值（9.99/0.88），enrich 回傳存值非重算值，證明排行層無第二份公式。
- [x] 排行表 18 欄：「內在價值／外在價值／外在佔比」在 Spread% 之後、Time Value% 之前；外在佔比（分母 mid）與 Time Value%（分母 spot）兩欄並存。NVTS live 驗證：strike 10 佔比 52.2% vs TV% 33.6%，兩欄數值不同、未合併。
- [x] request spec（真實 DB rows 走完整 HTTP 路徑）：新欄位標題與數值（3.08/0.12/3.8%）出現在回應；bid/ask 缺值情境顯示「—」無 NaN。
- [x] **核心情境 E2E（2026-07-04）**：NVTS 不帶 user_strike 完整查詢 → `job_status=success`，76/76 rows 內在/外在價值全數有值。（首跑曾因 pm2 server 為 migration 前啟動、schema cache 過期導致 `insert_all` 失敗 ROLLBACK——transaction 設計正確保住舊資料；`pm2 restart fairprice-rails` 後重跑通過。）
- [x] **人工已知值對照（fixture 層）**：`leaps_option_chain_snapshot_spec.rb` 以 2026-07-02 NVTS 數值釘公式：strike 5 → 9.46/1.54/14%、strike 10 → 4.46/4.865/52%，通過。
- [x] **人工已知值對照（live 層）**：當次（2026-07-04）抓到的 NVTS 2028-01-21 鏈手算兩筆 vs 頁面：strike 10（bid 8.70/ask 9.95, spot 14.46）→ Mid 9.325、內在 4.46、外在 4.865、佔比 52.17%，頁面 9.32/4.46/4.86/52.2% ✓；strike 7（bid 9.65/ask 10.40）→ Mid 10.025、內在 7.46、外在 2.565、佔比 25.59%，頁面 10.02/7.46/2.56/25.6% ✓。備註：live 報價與 7/2 fixture 相同是因 7/3 國慶補假＋週末休市、報價自 7/2 收盤後凍結，手算全程使用當次抓取值，未對歷史數值。

### 🆕 Phase I：頁面匯出 PNG／PDF（2026-07-04 新增；✅ 2026-07-05 全部驗收完成，證據如下）

- [x] 兩顆按鈕在頁面右上角（與標題同行右對齊），沿用本頁既有淺色主題按鈕樣式（規格原文「深色主題」沿自舊模板，本頁實際為淺色，E2E 背景檢查點對應為「背景有畫進輸出、非透明底」）；事件綁定為 document 層事件委派，無 inline onclick。
- [x] 純前端零後端：git status 僅 layout erb、page_component.rb、vendor JS、tailwind.css，routes/controllers/services/jobs/models 變動數 0。
- [x] 函式庫 vendor 本地檔：`vendor/assets/javascripts/html-to-image-1.11.11.js`（UMD，選 html-to-image 而非 html2canvas 的理由：本專案 Tailwind v4 用 oklch 色彩，html2canvas 不支援 oklch，html-to-image 走瀏覽器引擎渲染原生支援——實測頁面 bg `oklch(0.985 0.002 247.839)` 正確輸出）＋ `jspdf-2.5.2.umd.min.js`。layout 原有的 html-to-image CDN 標籤一併改為本地檔（daily_momentum 匯出共用受惠）；LEAPS 頁面上兩個匯出函式庫均走 `/assets` digest 路徑，零 CDN。
- [x] PDF 由 PNG 嵌入產生（`addImage` + `FAST` flate 壓縮，48MB→550KB），自訂單頁尺寸依圖片長寬比（2850×3160），不切 A4；PNG 與 PDF 畫面一致（同一 dataUrl）。
- [x] 匯出為完整頁面：root `#leaps-export-root` 含推薦分析＋18 欄排行表＋Options Flow 20 列全部；按鈕以 `data-export-exclude` + html-to-image filter 排除；導覽列在 root 之外天然排除。**修正記錄**：首版輸出被 clone 內的捲軸蓋住排行表末列——html-to-image 的 SVG foreignObject clone 字體度量略寬，live DOM 無溢出的 overflow-auto 容器在 clone 內會溢出幾 px 而畫出捲軸；修法是匯出前**無條件**把所有 overflow:auto/scroll 容器暫改 visible（不能只看 live 量測），完成後還原（驗證還原後無殘留 inline style）。
- [x] 檔名實測 `leaps_NVTS_20260705_1246.png/.pdf` 符合格式；無資料時兩鈕 disabled（實測含樣式）；`exporting` 旗標＋雙鈕 disabled 防重複點擊，匯出中顯示「匯出中…」。
- [x] **E2E 開檔驗收（2026-07-05）**：真實點擊兩顆按鈕各觸發下載事件（Playwright 回報 `Downloading file leaps_NVTS_20260705_1246.png/.pdf`）；輸出位元組（同管線取回）逐一開檔檢查：排行表 3 列與 Options Flow 20 列完整未腰斬、末列乾淨收尾、背景正確非透明、中文全部正常無豆腐字、按鈕不在輸出中。輸出檔存於驗收 scratchpad 並附截圖於回報。

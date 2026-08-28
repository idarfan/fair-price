# FairPrice / Daily Momentum — Rails 程式碼審計報告

- **審計日期**：2026-08-28
- **審計基準 commit**：`39ac654`（main，工作區乾淨）
- **Rails 版本**：8.1.3.1 ／ **Ruby**：4.0.1
- **審計依據**：thoughtbot《Ruby Science》《Testing Rails》最佳實務
- **規模**：34 controllers、33 models、41 services、75 components、202 個受測 Ruby 檔

## 實測數據（本次實跑，非估算）

| 工具 | 結果 |
|------|------|
| RSpec | **627 examples, 0 failures**（3 分 13 秒） |
| SimpleCov 行覆蓋率 | **43.59%**（3819 / 8760） |
| SimpleCov 分支覆蓋率 | **34.59%**（977 / 2824） |
| RubyCritic 總分 | **66.3 / 100**（A 78、B 35、C 47、D 29、**F 13**） |
| Brakeman | **0 warnings** |
| bundler-audit | **1 個 Medium 漏洞**（mail 2.9.0） |
| npm audit | 0 vulnerabilities |

> 測試全綠、Brakeman 全清、外部 API 全部設有 timeout、DB 索引與外鍵齊備、機密檔案管理正確。
> 這個專案的**基礎工程紀律相當好**。問題集中在兩件事：**API 認證缺口**，以及**把數千行 JavaScript 塞進 Phlex 元件**。

---

## Critical（必須立即處理）

### C-1. 整個 `/api/*` 命名空間完全不需要登入，且關閉 CSRF —— 含破壞性寫入端點

**位置**：`app/controllers/application_controller.rb:4`

```ruby
GATE_EXEMPT_PREFIXES = %w[/login /logout /auth /up /api /track].freeze
```

`enforce_auth_gate` 對任何 `request.path.start_with?("/api")` 直接 `return`，
而 `Api::V1::BaseController` 又加上 `protect_from_forgery with: :null_session`。
結果是：**全站有 Google OAuth + 強制 TOTP 二階段驗證 + 閒置逾時 + 每日強制登出的完整防護，
但這一整套在 `/api/*` 上完全不生效。**

**已實測驗證**（本機 production process，未帶任何 cookie）：

```
GET /                                → HTTP 302 → /login      （UI 有擋）
GET /api/v1/margin_positions         → HTTP 200 {"positions":[],"closed_positions":[]}
GET /api/v1/tracked_tickers          → HTTP 200 [{"id":105,"symbol":"F",...}]   ← 真實資料外洩
GET /api/iv_analysis/watchlist       → HTTP 200 {"watchlist":[{"ticker":"SHOP",...}]}  ← 真實資料外洩
```

**未受保護的破壞性端點**（全部無認證、無 CSRF）：

| 方法 | 路徑 | 後果 |
|------|------|------|
| `DELETE` | `/api/v1/margin_positions/:id` | 刪除融資部位（財務資料，`destroy!` 無確認） |
| `POST` | `/api/v1/margin_positions/:id/close` | 竄改部位狀態為已平倉 |
| `POST/PATCH` | `/api/v1/margin_positions` | 新增／竄改買入價、股數 |
| `DELETE` | `/api/v1/tracked_tickers/:id` | 連鎖 `dependent: :destroy` 刪光該代號所有 option_snapshots 歷史 |
| `DELETE` | `/api/iv_analysis/watchlist/:ticker` | 刪除 IV 觀察清單 |
| `POST` | `/api/v1/tracked_tickers/:id/collect` | 任意人可觸發 Python 爬蟲（見 H-1） |

**風險放大因素**：`config/environments/production.rb:14` 設定 `config.hosts << "fairprice-ohmy.com"`，
代表這是**對外網域的正式站台**，不是純內網工具。

**這是一個被測試「鎖定」的刻意設計**——`spec/requests/auth_gate_spec.rb:16` 明確斷言
`it "leaves /api/* accessible"`。修復時必須同步改這支測試，否則會誤以為是回歸。

**建議修法**：

```ruby
# application_controller.rb — /api 移出白名單
GATE_EXEMPT_PREFIXES = %w[/login /logout /auth /up /track].freeze

# api/v1/base_controller.rb — 改為明確的 API 認證
module Api
  module V1
    class BaseController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :require_api_session   # session cookie 或 token 擇一

      private

      def require_api_session
        head :unauthorized unless current_user&.enabled?
      end
    end
  end
end
```

前端是同源的 Vite/React（`app/frontend/margin/MarginApp.tsx` 用 `fetch` 打同網域），
所以**沿用既有 session cookie 即可**，不需要另做 token 機制；
只要在寫入請求帶上 `X-CSRF-Token` 就能把 `null_session` 換回 `:exception`。

---

### C-2. `MarginPosition` 財務資料無任何使用者歸屬

**位置**：`app/models/margin_position.rb`、`db/schema.rb`

`margin_positions` 表**沒有 `user_id` 欄位**，controller 也是全表操作
（`MarginPosition.open_positions`、`MarginPosition.find(params[:id])`）。
`portfolios`、`price_alerts`、`watchlist_items`、`iv_watchlists`、`tracked_tickers` 同樣沒有 user 歸屬。

目前 `users` 表有 pending／enabled／disabled 狀態與 admin 核准流程，
代表這是**多使用者系統**。一旦第二個帳號被核准，所有人共用同一份融資部位與投資組合，
彼此可讀可改可刪，且無審計軌跡。搭配 C-1 更是任何匿名者都能刪。

**建議**：為財務性資料表加上 `user_id`（`null: false` + index + FK），
model 加 `belongs_to :user`，controller 一律用 `current_user.margin_positions` 取代 `MarginPosition`。
這是 schema 變更，需先確認既有資料要歸給哪個帳號（migration 內 backfill 成 admin 的 id）。

---

## High（近期必須修）

### H-1. `tracked_tickers#collect` 在 web request 內同步跑 Python 子行程，無認證、無 timeout

**位置**：`app/controllers/api/v1/tracked_tickers_controller.rb:46`

```ruby
_output, status = Open3.capture2e(python, script, "--symbols", ticker.symbol, "--force")
```

參數是陣列形式，**沒有 shell injection**（這點是對的）。問題在別處：

1. **無 timeout** —— Python 爬蟲卡住，這條 Puma thread 就永久卡住。
   `RAILS_MAX_THREADS` 預設 5，**5 個請求就能讓整站無回應**。
2. **無認證**（C-1）——任何人可以無限次觸發外部爬蟲，等於免費的 DoS + 對 Barchart 的濫用來源。
3. **同步阻塞** ——`thoughtbot` 稱之為 sluggish service：外部呼叫應該進背景 job。

專案已經有 `app/jobs/`（10 支 job，用 `Rails.cache` 回報狀態的模式已成熟），
應改成 `enqueue` 後回 `202 Accepted` + job_id，前端輪詢 status，與 `ScrapeLeapsJob` 一致。

### H-2. `config.force_ssl` 未啟用（正式站有對外網域）

**位置**：`config/environments/production.rb:25-31`（`assume_ssl`、`force_ssl`、`ssl_options` 三行都被註解）

沒有 `force_ssl` 就沒有 HSTS，session cookie 也不會帶 `Secure` 旗標。
考量到這個 session 背後是 Google OAuth + TOTP，cookie 被明文傳輸的代價很高。
若已由反向代理終結 TLS，至少要開 `config.assume_ssl = true` + `config.force_ssl = true`。

### H-3. 數千行 JavaScript 內嵌在 Phlex 元件的 heredoc 裡

這是本專案 **RubyCritic 13 個 F 級檔案的共同成因**，也是覆蓋率上不去的主因。

| 方法 | 行數 |
|------|------|
| `IvAnalysis::PageComponent#render_script` | **725** |
| `BullPutSpreads::PageComponent#script_js` | **510** |
| `BullCallSpreads::PageComponent#script_js` | **428** |
| `TechnicalDashboard::PageComponent#render_options_charts` | **399** |
| `IvAnalysis::EducationComponent#render_chain_tooltip_script` | **273** |
| `DailyMomentum::AnalysisPanelComponent#render_script` | 232 |
| `IvWatchlists::IndexView#render_scripts` | 221 |

連帶後果：

- 這些 JS **不經 ESLint、不經 TypeScript、無法測試、無 source map、無 Vite 打包**，
  等於專案有一半前端邏輯躲在型別檢查之外——而 `CLAUDE.md` 的技術棧規範明確要求
  「互動圖表、複雜 UI 狀態」走 Vite + React。
- 強迫 CSP 開啟 `script_src :unsafe_inline`（`config/initializers/content_security_policy.rb:4`），
  使 CSP 幾乎失去防 XSS 的作用。
- `app/components/technical_dashboard/page_component.rb` 複雜度 **1501.5**、
  重複度 855、140 個 smell、churn 38（改動最頻繁的檔案之一）——高改動 × 高複雜度是最危險的象限。

**建議**：把這些 heredoc JS 逐一搬進 `app/frontend/` 成為真正的 Vite 模組，
Phlex 只負責輸出 `div(data: { controller: "...", payload: data.to_json })` 掛載點。
優先順序照 churn × complexity 排：`technical_dashboard/page_component.rb` →
`bull_put_spreads` / `bull_call_spreads` → `iv_analysis`。

### H-4. `TrackedTicker#last_snapshot_date` 造成 N+1

**位置**：`app/models/tracked_ticker.rb:17`

```ruby
def last_snapshot_date
  option_snapshots.maximum(:snapshot_date)   # 每筆 record 一次 SQL
end
```

`Api::V1::TrackedTickersController#index` 對每一筆都呼叫 `serialize_ticker`，
所以 N 個代號 = N + 1 次查詢。實測 index 回傳的清單已有數十筆。

**建議**：改成一次 group query 預先算好

```ruby
maxes = OptionSnapshot.where(tracked_ticker_id: tickers.map(&:id))
                      .group(:tracked_ticker_id).maximum(:snapshot_date)
```

（整體而言本專案關聯很少、N+1 風險低，這是唯一確認的一處。）

### H-5. `Api::V1::TrackedTickersController#watchlist` 無上限地開 thread

**位置**：`app/controllers/api/iv_analysis_controller.rb:96-118`

每個 watchlist 項目開 **3 個 `Thread.new`**，數量隨資料筆數線性成長且無上限。
註解正確地說明了「HTTP only — no AR inside threads」（這點做得對），
但 100 個代號就是 300 條同時對外的 HTTP 連線。
應改用固定大小的 thread pool（如 `Concurrent::FixedThreadPool`）或分批處理——
`MomentumReportService:55` 已經有 `batch.map { Thread.new ... }` 的分批寫法可以參照。

### H-6. `mail` gem 已知漏洞

`mail 2.9.0` — GHSA-mvxr-6m87-mv2q（Medium，透過畸形 RFC 2047 encoded-word 偽造寄件者）。
`bundle update mail`（需 `>= 2.9.1`）。

---

## Medium

### M-1. `public/tech_prototype.html` 繞過登入閘門對外公開

實測 `GET /tech_prototype.html → HTTP 200`（未登入）。
它在 `.gitignore` 裡，代表是開發殘留物，卻實際存在於 production 的 `public/`。
`public/` 下的檔案由 web server 直接送出，**完全繞過 `enforce_auth_gate` 與瀏覽軌跡記錄**
（這正是專案筆記中 2026-08-05 `public/csp/` 事件的同一個模式）。
建議直接刪除，或比照 CSP lessons 搬進 `private/` 加 controller。

### M-2. 例外訊息直接回傳給客戶端

- `app/controllers/api/v1/valuations_controller.rb:25` → `render json: { error: "查詢失敗：#{e.message}" }`
- `app/controllers/api/v1/options_controller.rb:43` → `render json: { error: e.message }`
- `app/services/telegram_bot_handler_service.rb:72` → `"😿 歐歐分析時發生錯誤：#{e.message}"`

`e.message` 可能含檔案路徑、SQL 片段、上游 API key 錯誤訊息。
其他地方（如 `margin_positions_controller.rb:59`）做法就是對的：log 詳細、回傳籠統訊息。
應統一成後者。

### M-3. `barchart_scraper_service.rb:422` 裸 `rescue` 無任何記錄

全專案 45 處寬鬆 rescue 中，**只有這一處**完全沒有 log，直接 `false`。
其餘 44 處都有 `Rails.logger` 記錄——整體錯誤處理紀律其實很好，補上這一處即可。

### M-4. `TrackController#page_view` 忽略 `save` 回傳值

**位置**：`app/controllers/track_controller.rb:20` —— `activity.save`（非 `save!`，也未檢查回傳值）。
瀏覽軌跡是 admin 後台「累積停留時間」的資料來源，靜默失敗會讓統計無聲失真。
至少改成 `Rails.logger.warn unless activity.save`。

### M-5. `iv_watchlists.ticker` 有 uniqueness validation 但缺 unique index

**位置**：`app/models/iv_watchlist.rb:8` vs `db/schema.rb`

其他 12 個 uniqueness validation **全部**都有對應的 unique index（做得很好），
只有這一個漏掉，並發時會寫入重複列。`iv_queries` 表則是完全沒有任何索引。

### M-6. 兩個大型元件的重複程式碼

`bull_call_spreads/page_component.rb`（重複度 791）與
`bull_put_spreads/page_component.rb`（重複度 649）明顯是複製貼上的一對；
`daily_momentum/watchlist_row_component.rb` 與 `watchlist_manager_row_component.rb`
被 flay 判定為「Identical code found in 2 nodes」。
Call/Put spread 的差異只在方向與履約價比較，適合抽共用 base component + 策略物件。

---

## Low

### L-1. 測試覆蓋率 43.59%（低於團隊標準 80%）

**90 / 202 個檔案完全沒被任何測試載入過**（約 8,155 行從未執行）：

| 目錄 | 零覆蓋檔案 | 約略行數 |
|------|-----------|---------|
| `app/components` | 40 / 75 | ~5,159 |
| `app/services` | 20 / 41 | ~1,803 |
| `app/controllers` | 17 / 36 | ~939 |
| `app/models` | 12 / 38 | ~245 |

最大的零覆蓋檔：`iv_analysis/education_component.rb`（1230 行）、
`iv_analysis/page_component.rb`（673）、`composite_signal_service.rb`（388）。

低覆蓋（有測試但不足）：

| 覆蓋率 | 檔案 |
|--------|------|
| 13.6% | `api/v1/charts_controller.rb` |
| 13.9% | `technical_dashboard/page_component.rb` |
| 25.6% | `stock_data_service.rb` |
| 34.6% | `reports_controller.rb` |
| 49.7% | `barchart_scraper_service.rb` |

**建議優先序**：不要追求全面補測。先補**風險最高的**——
`composite_signal_service.rb`（388 行純計算邏輯、F 級、churn 10，是投資訊號的核心，
最適合寫單元測試且投報率最高）、以及所有 `/api/*` 的 request spec（同時可以鎖住 C-1 的修復）。
元件那 5,000 行零覆蓋主要是內嵌 JS，做完 H-3 之後才有意義測。

### L-2. Service Object 命名（thoughtbot PORO 觀點）

41 個 `*Service` 中約半數是「只有一個 `.call` / `.fetch` 的類別方法容器」。
thoughtbot 立場是這類物件應該用領域名詞命名並 `include ActiveModel::Model`。

**實務評估**：本專案的 Service 絕大多數是**外部 API adapter**
（`FinnhubService`、`YahooFinanceService`、`SecEdgarService`、`VixService`、`TelegramService`…），
這種用途下 `*Service` 命名是恰當的，不建議為改名而改名。
真正值得改的只有承載領域邏輯的那幾個：
`ValuationService` → `Valuation::Analysis`、`CompositeSignalService` → `CompositeSignal`、
`PmccRankingService` → `PmccRanking`。這是 Low，優先度排在功能與安全之後。

### L-3. RubyCritic smell 統計

| 類型 | 次數 |
|------|------|
| DuplicateMethodCall | 673 |
| TooManyStatements | 431 |
| UncommunicativeVariableName | 286 |
| DuplicateCode | 198 |
| HighComplexity | 166 |
| IrresponsibleModule（無說明註解） | 163 |
| UtilityFunction | 150 |
| FeatureEnvy | 98 |

其中 673 個 `DuplicateMethodCall` 與 431 個 `TooManyStatements` 高度集中在
內嵌 JS 的大型 Phlex 元件——**做完 H-3 會一次消掉大半**，不必逐項處理。

### L-4. `GATE_EXEMPT_PREFIXES` 用 `start_with?` 做前綴比對

`/logout_backdoor`、`/upgrade`、`/authentication_bypass` 這類路徑都會意外命中白名單。
目前 `config/routes.rb` 沒有這種路由所以無實害，但屬於容易踩到的地雷。
改成完整 path 集合或 `%r{\A/api(/|\z)}` 這類明確 anchor 較安全。

---

## 做得好的部分（不要動）

這些在稽核中被明確驗證，值得記錄下來避免日後「重構」時弄壞：

- **外部 API timeout 100% 覆蓋** —— 20 個對外服務全部設有 timeout（4s ～ 120s，依用途分級），
  這是多數 Rails 專案最常漏的一項。
- **DB schema 紀律優良** —— 29 張表，所有 `*_id` 欄位都有 FK 或索引，
  13 個 uniqueness validation 有 12 個有對應 unique index。
- **零 SQL injection、零 mass assignment** —— 全專案沒有任何字串插值進 `where`／`order`，
  沒有 `permit!`、沒有 `to_unsafe_h`，Brakeman 0 warnings。
- **`html_safe` 使用安全** —— 逐一檢查所有插值點，只有 `to_json`、內部 uid、CSRF token，
  沒有未轉義的使用者輸入。
- **機密管理正確** —— `.gitignore` 涵蓋 `.env*`、`master.key`、`client_secret_*.json`，
  git 追蹤中無任何明文機密。
- **認證流程設計紮實** —— Google OAuth + 強制 TOTP + `session_version` 撤銷機制 +
  閒置 2 小時 + 絕對 24 小時逾時，且有 `auth_gate_spec` / `idle_timeout_spec` /
  `absolute_timeout_spec` 三支測試覆蓋。可惜 `/api` 缺口讓這一切在 API 上失效（C-1）。
- **錯誤處理紀律** —— 45 處 rescue 中 44 處有記錄，無 `rescue nil`，無靜默吞例外。
- **`Admin::UsersController`** —— A 級評分，`require_admin!` 回 `404` 而非 `403`（不洩漏端點存在），
  統計用 `group`/`pluck` 在 SQL 層做完，是全專案寫得最好的 controller。

---

## 建議執行順序

| 順位 | 項目 | 預估 | 為什麼是這個順序 |
|------|------|------|-----------------|
| 1 | **C-1** `/api` 認證 + 同步改 `auth_gate_spec` | 半天 | 對外網域上的匿名資料外洩與匿名刪除，其餘都可以等 |
| 2 | **H-1** `collect` 改背景 job | 半天 | 5 個請求打垮整站，且被 C-1 放大 |
| 3 | **H-2** `force_ssl` + **H-6** `bundle update mail` | 30 分 | 改設定即可，成本極低 |
| 4 | **M-1** 刪除 `public/tech_prototype.html` | 5 分 | 一行的事 |
| 5 | **C-2** 財務資料加 `user_id` | 1–2 天 | 需要 migration + backfill，趁使用者還少時做最便宜 |
| 6 | **H-4 / H-5 / M-2～M-5** | 1 天 | 獨立小修，可一次批掉 |
| 7 | **L-1** 補 `composite_signal_service` + `/api` request spec | 1–2 天 | 保護核心投資邏輯與剛修好的認證 |
| 8 | **H-3** 內嵌 JS 遷移到 Vite（照 churn 排序分批） | 持續進行 | 最大工程量，但一做就同時解掉 F 級評分、CSP `unsafe_inline`、以及元件那 5000 行零覆蓋 |

---

*本報告所有數據來自實際執行：RSpec + SimpleCov、RubyCritic、Brakeman、bundler-audit、npm audit，
以及對執行中 production process（port 3003）的實際 HTTP 探測。
稽核期間新增的 SimpleCov / RubyCritic 相依已全數還原，工作區維持乾淨。*

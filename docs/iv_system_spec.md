在現有的 Rails 專案中新增「期權 IV 分析系統」，包含即時查詢、歷史 IV 自建數據庫、
Watchlist 管理三個子功能，整合成同一套系統。

════════════════════════════════════════
█ 一、系統架構概覽
════════════════════════════════════════

Rails (主後端)
  ├── Phlex 前端頁面（/iv_analysis）
  ├── JSON API（/api/iv_analysis/...）
  ├── PostgreSQL 資料庫
  ├── Rake task（每日定時抓 IV）
  └── HTTP 呼叫 → Python sidecar（port 5050）

Python sidecar（iv_sidecar.py）
  ├── Flask HTTP server
  ├── yfinance 抓 option chain
  └── Black-Scholes delta 計算（備援）

════════════════════════════════════════
█ 二、資料庫設計
════════════════════════════════════════

── watched_tickers ──────────────────────
ticker          string,   not null, unique
added_at        datetime, not null
last_fetched_at datetime
active          boolean,  default true

── iv_daily_snapshots ───────────────────
ticker          string,   not null
snapshot_date   date,     not null
atm_iv          decimal(8,4)   # 當日 ATM IV，作為全股代表 IV
atm_strike      decimal(10,2)
current_price   decimal(10,2)
created_at      datetime
index: [ticker, snapshot_date], unique

── iv_queries ────────────────────────────
ticker          string
strike          decimal(10,2)
expiry_date     date
option_type     string          # call / put
current_price   decimal(10,2)
delta           decimal(6,4)
iv              decimal(8,4)
ivr_1y          decimal(6,2)   # null 若資料不足
ivp_1y          decimal(6,2)
ivr_2y          decimal(6,2)
ivp_2y          decimal(6,2)
available_days  integer         # 實際用了幾天資料
data_quality    string          # insufficient/limited/good/excellent
low_iv_signal   boolean
queried_at      datetime

════════════════════════════════════════
█ 三、Python Sidecar（iv_sidecar.py）
════════════════════════════════════════

Flask app，port 5050
啟動前需確認：pip install yfinance flask scipy numpy

開始寫程式前先執行以下驗證，確認 yfinance 欄位正確：
  python3 -c "
    import yfinance as yf
    tk = yf.Ticker('AAPL')
    exp = tk.options[0]
    chain = tk.option_chain(exp)
    print(chain.calls.columns.tolist())
    print(chain.calls[['strike','impliedVolatility']].head())
  "

── POST /fetch_atm_iv ───────────────────
input:  { ticker }
output: { ticker, current_price, atm_strike, atm_iv, snapshot_date }

邏輯：
1. yfinance 取得當前股價
2. 取最近到期日的 option chain（calls）
3. 找最接近股價的 strike（ATM）
4. 回傳該 call 的 impliedVolatility 作為 atm_iv

── POST /fetch_option_detail ────────────
input:  { ticker, strike, expiry_date, option_type }
output: { ticker, strike, expiry_date, current_price, iv, delta }

邏輯：
1. 抓指定 strike + expiry 的 option
2. 取 impliedVolatility
3. delta 優先取 yfinance 回傳值；若無則用 Black-Scholes 計算
   Black-Scholes delta 自行實作（r = 0.045）
4. 若 strike / expiry 找不到，回傳 HTTP 422 + error message

════════════════════════════════════════
█ 四、Rails 服務層
════════════════════════════════════════

── IvSidecarService ─────────────────────
封裝對 Python sidecar 的 HTTP 呼叫
.fetch_atm_iv(ticker)
.fetch_option_detail(ticker:, strike:, expiry_date:, option_type:)
timeout: 15 秒；sidecar 無回應時 raise IvSidecarService::UnavailableError

── IvStatsService ───────────────────────
基於 iv_daily_snapshots 計算統計
.calculate(ticker, current_iv)

  查詢該 ticker 所有歷史快照，按 snapshot_date 排序
  計算 IVR 與 IVP：
    1Y = 最近 252 筆（交易日）
    2Y = 最近 504 筆
  公式：
    IVR = (current_iv - period_min) / (period_max - period_min) * 100
    IVP = (period 中 iv < current_iv 的天數 / 總天數) * 100

  data_quality 判斷：
    available_days < 30   → :insufficient
    30..179               → :limited
    180..364              → :good
    >= 365                → :excellent

  回傳：
    { ivr_1y, ivp_1y, ivr_2y, ivp_2y,
      available_days, data_quality }
  若資料不足 30 天，ivr/ivp 全部回傳 nil

── WatchedTickersService ────────────────
.add(ticker)
  加入 watchlist（idempotent，已存在則只確保 active: true）

.remove(ticker)
  soft delete（active: false）

.daily_fetch_all
  對所有 active: true 的 ticker：
    1. 呼叫 IvSidecarService.fetch_atm_iv
    2. 若當日 snapshot 已存在則跳過（idempotent）
    3. 否則寫入 iv_daily_snapshots
    4. 更新 watched_tickers.last_fetched_at
  單一 ticker 失敗不中斷其他 ticker
  印出每筆結果 log

════════════════════════════════════════
█ 五、API Endpoints
════════════════════════════════════════

── POST /api/iv_analysis ────────────────
params: { ticker, strike, expiry_date, option_type }
流程：
  1. IvSidecarService.fetch_option_detail → 取得 iv, delta
  2. WatchedTickersService.add(ticker)    → 自動加入 watchlist
  3. IvStatsService.calculate(ticker, iv) → 取得 IVR/IVP
  4. 寫入 iv_queries
  5. 回傳 JSON（含 low_iv_signal 判斷）

low_iv_signal 規則：
  ivr_1y < 20 或 ivr_2y < 20 → true，否則 false
  資料不足時 → false，並附 notice 說明

response 範例：
  {
    ticker, strike, expiry_date, option_type,
    current_price, delta, iv,
    ivr_1y, ivp_1y, ivr_2y, ivp_2y,
    available_days, data_quality,
    low_iv_signal,
    notice,      # 選填，如「資料累積不足，IVR 僅供參考」
    queried_at
  }

── GET /api/iv_analysis/watchlist ───────
回傳所有 active ticker 的清單，含：
  ticker, added_at, last_fetched_at,
  available_days（從 iv_daily_snapshots count）,
  latest_atm_iv（最新一筆 atm_iv）,
  data_quality

── DELETE /api/iv_analysis/watchlist/:ticker
soft delete（active: false）
回傳 { success: true }

════════════════════════════════════════
█ 六、Rake Task + 排程
════════════════════════════════════════

── rake iv:daily_snapshot ───────────────
呼叫 WatchedTickersService.daily_fetch_all
執行完印出摘要：成功幾筆 / 跳過幾筆 / 失敗幾筆

── rake iv:backfill[ticker] ─────────────
對單一 ticker 補抓當日 IV（手動補救用）

── config/schedule.rb（whenever gem）────
每天 04:30 台灣時間（= 美東 16:30 收盤後）：
  rake iv:daily_snapshot

════════════════════════════════════════
█ 七、Phlex 前端
════════════════════════════════════════

目錄：app/components/iv_analysis/

── GET /iv_analysis ─────────────────────
渲染 IvAnalysis::PageComponent，包含：

  IvAnalysis::QueryFormComponent（查詢表單）
    - Ticker 文字輸入框
    - Strike 數字輸入框
    - Expiry Date datepicker
    - Call / Put 切換按鈕
    - 送出按鈕（原生 JS fetch → POST /api/iv_analysis）

  IvAnalysis::ResultComponent（查詢結果，初始隱藏）
    數字卡片區：
      - 當前股價
      - Delta（含色碼：> 0.5 藍、0.3-0.5 綠、< 0.3 灰）
      - IV 百分比

    IVR / IVP 統計區（1Y / 2Y 各一欄）：
      - 數值顯示
      - IVR < 20% → 綠色標記「低點」
      - IVR > 80% → 紅色標記「高點」
      - 資料不足 → 灰色顯示「-」並附說明

    data_quality 提示橫幅：
      :insufficient → 黃色「⚠️ 資料累積不足 30 天，IVR/IVP 尚不可靠」
      :limited      → 灰色「📊 資料累積中（N 天），建議等待更多歷史資料」
      :good         → 藍色「✅ 資料品質良好（N 天）」
      :excellent    → 綠色「✅ 資料充足（N 天），統計結果可信」

    結論卡片：
      IVR 1Y < 20% → 「✅ IV 處於一年低點，買入期權勝算較高」
      IVR 2Y < 20% → 「✅ IV 同時處於兩年低點，信號更強」
      IVR > 80%    → 「⚠️ IV 偏高，Vega 風險大，考慮賣方策略」
      其他         → 「IV 處於中性區間」

  IvAnalysis::WatchlistComponent（下方 watchlist 表格）
    欄位：Ticker / 最新 ATM IV / 累積天數 /
          資料品質 badge / 最後更新 / 移除按鈕
    移除：原生 JS fetch → DELETE /api/iv_analysis/watchlist/:ticker
    移除後該列淡出消失（CSS transition）

════════════════════════════════════════
█ 八、前端互動規範
════════════════════════════════════════

- 不使用 ERB、Hotwire、Stimulus
- 所有互動用原生 JS + event delegation
- 表單送出：
    document.querySelector('#iv-analysis-form')
      .addEventListener('submit', handler)
    handler 內用 fetch() 打 API，結果更新 DOM
- Watchlist 移除同上模式
- Loading 狀態：送出期間按鈕 disabled + 顯示「查詢中...」
- 錯誤處理：API 回傳非 200 時，顯示錯誤訊息區塊

════════════════════════════════════════
█ 九、路由
════════════════════════════════════════

GET    /iv_analysis
POST   /api/iv_analysis
GET    /api/iv_analysis/watchlist
DELETE /api/iv_analysis/watchlist/:ticker

════════════════════════════════════════
█ 十、執行順序提醒（給 Claude Code）
════════════════════════════════════════

請依照以下順序實作，每步完成後確認再繼續：

1. 先執行 yfinance 驗證指令，確認欄位名稱
2. 建立三張資料表的 migration 並 migrate
3. 實作 Python sidecar（iv_sidecar.py），用 curl 測試兩個 endpoint
4. 實作 Rails 三個 Service class，各自寫單元測試
5. 實作 API Controller 與路由
6. 實作 Phlex components 與頁面路由
7. 加入 Rake task，手動執行一次確認
8. 加入 whenever 排程設定
9. 整合測試：查詢 AAPL，確認 watchlist 自動新增、資料庫有寫入

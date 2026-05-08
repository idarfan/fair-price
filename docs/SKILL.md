---
name: iv-skew-dashboard
description: >
  每日期權分析儀表板，整合 IV Rank（ATM 隱含波動率相對水位）與
  Put/Call Skew Rank（方向性偏向）兩個維度，從 PostgreSQL 讀取數據並渲染
  多個儀表圖（gauge）。當使用者提到 IV Rank 儀表板、Skew 儀表板、
  期權波動率跨標的比較、或要更新/重繪儀表板圖表時觸發。
---

# IV Rank × Put/Call Skew 雙維度儀表板

## 目標

1. **IV Rank Dashboard** - 指標：ATM IV 對照過去一年最高/最低做 0-100 排名
   - 顏色語義：紅 >= 60（高波動）、橘 30-60（中性）、綠 < 30（低波動）

2. **Put/Call Skew Dashboard** - 指標：avg(0.25-delta Put IV) - avg(0.25-delta Call IV)，DTE 0-15 天
   - 顏色語義：紅 >= 60（市場偏空）、灰 30-60（中性）、綠 < 30（市場偏多）

---

## 視覺設計規格

每個標的對應一個半圓形 gauge：

```
┌─────────────────────┐
│  TICKER             │
│  Skew Rank / IV Rank│
│   ╭──────────╮      │
│  /  ▓▓░░░░  \     │
│ /     │      \    │
│/      ↓       \   │
│  0          100 │
│  [大字數值]     │
│  [小字 raw data]│
└─────────────────────┘
```

- 背景 #0d0d0d；弧形三色：綠（0-30）橘（30-60）紅（60-100）
- 數值字體 24-28px bold；raw data 小字 9-10px
- 卡片圓角深色邊框，hover 時邊框發亮

### 頁面頂部 Summary Bar

```
┌─────────────────┬──────────────────┬────────────────┐
│  High Vol Zone  │   Neutral Zone   │  Low Vol Zone  │
│  IV Rank >= 60  │  30 <= IV < 60   │  IV Rank < 30  │
│       16        │        17        │       2        │
└─────────────────┴──────────────────┴────────────────┘
```

---

## 實際資料庫 Schema（已驗證 2026-05-08）

### `iv_daily_snapshots`（每日 ATM IV 快照）

```sql
id             bigint PRIMARY KEY
ticker         varchar
snapshot_date  date
atm_iv         numeric(8,4)    -- ATM 隱含波動率（當日快照）
atm_strike     numeric(10,2)
current_price  numeric(10,2)
created_at / updated_at  timestamp
```

> 警告：無 `iv_rank` 欄位。IV Rank 必須在 API 層用 Window Function 從 atm_iv 歷史動態計算。

### `iv_queries`（使用者查詢紀錄）

```sql
id            bigint PRIMARY KEY
ticker        varchar
strike        numeric(10,2)
expiry_date   date
option_type   varchar          -- 'call' / 'put'
current_price numeric(10,2)
delta         numeric(6,4)
iv            numeric(8,4)     -- 該合約 IV
ivr_1y        numeric(6,2)     -- IV Rank（1年視窗）
ivp_1y        numeric(6,2)     -- IV Percentile（1年視窗）
ivr_2y        numeric(6,2)     -- IV Rank（2年視窗）
ivp_2y        numeric(6,2)     -- IV Percentile（2年視窗）
available_days integer
data_quality  varchar
low_iv_signal boolean
queried_at    timestamp
```

> 每次用戶在 IV 分析頁查詢時寫入一筆；取最新一筆的 ivr_1y 可作當前 IV Rank 備用來源。

### `options_snapshots`（跨標的快取）

```sql
id              bigint PRIMARY KEY
symbol          varchar          -- 注意：欄位是 symbol，不是 ticker
cached_at       timestamp
current_price   numeric(10,4)
expiration_date varchar
iv_rank         numeric(5,2)     -- IV Rank（預計算）
iv_skew         numeric(6,4)     -- Put IV - Call IV 差值（預計算）
pc_ratio        numeric(6,4)
raw_data        jsonb
```

> 警告：無 `skew_rank` 欄位。Skew Rank 需從 iv_skew 歷史動態計算。

### `option_snapshots`（逐合約原始資料，options_collector.py 寫入）

```sql
id                bigint PRIMARY KEY
tracked_ticker_id bigint           -- FK -> tracked_tickers.id
contract_symbol   varchar
option_type       varchar          -- 'call' / 'put'
expiration        date
strike            numeric(10,4)
implied_volatility numeric(8,6)
in_the_money      boolean
underlying_price  numeric(10,4)
bid / ask / last_price  numeric(10,4)
volume / open_interest  integer
snapshot_date     date
snapped_at        timestamp
```

> 注意：option_snapshots（無複數 s）= 逐合約表；options_snapshots（有複數 s）= 快取表，兩者不同。

---

## API 端點設計（Rails）

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    get 'dashboard/combined', to: 'dashboard#combined'
  end
end
```

```ruby
# app/controllers/api/v1/dashboard_controller.rb
class Api::V1::DashboardController < ApplicationController
  def combined
    target_date = params[:date] || Date.today.to_s
    quoted_date = ActiveRecord::Base.connection.quote(target_date)

    # IV Rank：從 iv_daily_snapshots.atm_iv 動態計算（表內無 iv_rank 欄位）
    iv_rows = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT
        ticker,
        snapshot_date,
        atm_iv,
        current_price,
        ROUND(
          (atm_iv - MIN(atm_iv) OVER w)
          / NULLIF(MAX(atm_iv) OVER w - MIN(atm_iv) OVER w, 0)
          * 100
        , 1) AS iv_rank,
        COUNT(*) OVER w AS data_days
      FROM iv_daily_snapshots
      WINDOW w AS (
        PARTITION BY ticker
        ORDER BY snapshot_date
        ROWS BETWEEN 364 PRECEDING AND CURRENT ROW
      )
      WHERE snapshot_date = #{quoted_date}
    SQL

    # Skew：options_snapshots 取最新一筆（欄位是 symbol，不是 ticker）
    skew_rows = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT DISTINCT ON (symbol)
        symbol, iv_rank AS cached_iv_rank, iv_skew, pc_ratio, cached_at
      FROM options_snapshots
      ORDER BY symbol, cached_at DESC
    SQL

    # Skew Rank：從 options_snapshots.iv_skew 歷史動態計算
    skew_rank_rows = ActiveRecord::Base.connection.execute(<<~SQL)
      SELECT
        symbol,
        ROUND(
          (iv_skew - MIN(iv_skew) OVER w)
          / NULLIF(MAX(iv_skew) OVER w - MIN(iv_skew) OVER w, 0)
          * 100
        , 1) AS skew_rank
      FROM options_snapshots
      WINDOW w AS (
        PARTITION BY symbol
        ORDER BY cached_at
        ROWS BETWEEN 364 PRECEDING AND CURRENT ROW
      )
      WHERE cached_at::date = #{quoted_date}
    SQL

    merged = iv_rows.each_with_object({}) do |row, h|
      h[row['ticker']] = {
        ticker:    row['ticker'],
        iv_rank:   row['iv_rank'].to_f,
        atm_iv:    row['atm_iv'].to_f,
        data_days: row['data_days'].to_i
      }
    end

    skew_rank_lookup = skew_rank_rows.each_with_object({}) do |r, h|
      h[r['symbol']] = r['skew_rank'].to_f
    end

    skew_rows.each do |row|
      sym = row['symbol']
      merged[sym] ||= { ticker: sym }
      merged[sym].merge!(
        skew_rank: skew_rank_lookup[sym] || 0,
        iv_skew:   row['iv_skew'].to_f,
        pc_ratio:  row['pc_ratio'].to_f
      )
    end

    render json: {
      date: target_date,
      data: merged.values,
      summary: {
        iv: {
          high: merged.values.count { |d| d[:iv_rank].to_f >= 60 },
          mid:  merged.values.count { |d| (30...60).cover?(d[:iv_rank].to_f) },
          low:  merged.values.count { |d| d[:iv_rank].to_f < 30 }
        },
        skew: {
          high: merged.values.count { |d| d[:skew_rank].to_f >= 60 },
          mid:  merged.values.count { |d| (30...60).cover?(d[:skew_rank].to_f) },
          low:  merged.values.count { |d| d[:skew_rank].to_f < 30 }
        }
      }
    }
  end
end
```

---

## React 元件架構

```
IvSkewDashboard/
├── index.jsx
├── components/
│   ├── SummaryBar.jsx
│   ├── GaugeCard.jsx        # SVG 半圓 gauge
│   ├── DualGaugeCard.jsx    # 雙指針（IV + Skew）
│   └── MatrixView.jsx       # 3x3 象限矩陣
└── hooks/
    └── useDashboardData.js
```

```js
// hooks/useDashboardData.js
import { useState, useEffect } from 'react';

export function useDashboardData(date) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    setLoading(true);
    fetch(`/api/v1/dashboard/combined?date=${date}`)
      .then(r => r.json())
      .then(json => { setData(json); setLoading(false); })
      .catch(e => { setError(e); setLoading(false); });
  }, [date]);

  return { data, loading, error };
}
```

---

## Gauge SVG 規格

```
半圓中心：cx = width/2, cy = height * 0.75
半徑：r = width * 0.38
弧形範圍：Math.PI -> 2*Math.PI

顏色分段：0-30 -> #2ecc8e、30-60 -> #e6952a、60-100 -> #e05252

指針角度：Math.PI + (rank / 100) * Math.PI
指針長度：r * 0.85

Raw data 小字：
  IV Rank 模式: "ATM IV: 34.2%"（來自 iv_daily_snapshots.atm_iv）
  Skew 模式:   "Skew: +2.3 pts"（來自 options_snapshots.iv_skew）
```

---

## 四個 Tab 模式

| Tab | 說明 | Summary Bar |
|-----|------|-------------|
| 雙維度 | 每格兩根指針（實線 IV、虛線 Skew） | IV Rank 統計 |
| IV Rank | 單指針，波動率水位 | IV Rank 統計 |
| Skew Rank | 單指針，方向偏向 | Skew 統計 |
| 象限矩陣 | 3x3 格，自動分類 + 策略標籤 | 兩者統計 |

---

## 象限矩陣策略對應

```
           偏空(Skew>=60)   中性(30-60)      偏多(Skew<30)
高IV(>=60)  賣Call/BearSprd  賣跨式Straddle   賣Put/BullSprd
中IV(30-60) 謹慎方向交易    觀望             買Call
低IV(<30)  買Put（便宜）   等待             買Call（便宜）
```

---

## 每日資料更新流程

### 重要限制：yfinance 無法提供歷史 IV

yfinance impliedVolatility 只有即時值，無法回溯歷史。
唯一可行做法：每天執行腳本把當天 IV 存入 PostgreSQL，靠資料庫累積歷史再計算 Rank。

```
每日美股收盤後（台灣時間約 05:00-06:00）：
1. options_collector.py 抓取期權鏈 -> option_snapshots
2. 計算今日 ATM IV -> iv_daily_snapshots (ticker, snapshot_date, atm_iv, atm_strike, current_price)
3. 計算今日 iv_skew（0.25-delta Put IV - Call IV）-> options_snapshots (symbol, iv_skew, iv_rank, pc_ratio)
4. API 層用 Window Function 動態計算 Rank（無需預存）
```

### Python 計算腳本（對應真實欄位）

```python
import yfinance as yf
import pandas as pd

def calc_atm_iv(ticker: str, dte_max: int = 14):
    """回傳 (atm_iv, atm_strike, current_price)，寫入 iv_daily_snapshots"""
    tk = yf.Ticker(ticker)
    spot = tk.fast_info['last_price']
    ivs, atm_strike = [], None
    for exp in tk.options:
        dte = (pd.to_datetime(exp) - pd.Timestamp.today()).days
        if dte < 0 or dte > dte_max:
            continue
        calls = tk.option_chain(exp).calls.copy()
        calls['dist'] = abs(calls['strike'] - spot)
        atm = calls.nsmallest(2, 'dist')
        if atm_strike is None:
            atm_strike = float(atm['strike'].iloc[0])
        ivs.extend(atm['impliedVolatility'].dropna().tolist())
    atm_iv = sum(ivs) / len(ivs) if ivs else None
    return atm_iv, atm_strike, spot


def calc_iv_skew(ticker: str, dte_max: int = 15, delta_pct: float = 0.20):
    """回傳 iv_skew = avg(put_iv) - avg(call_iv)，寫入 options_snapshots.iv_skew"""
    tk = yf.Ticker(ticker)
    spot = tk.fast_info['last_price']
    results = []
    for exp in tk.options:
        dte = (pd.to_datetime(exp) - pd.Timestamp.today()).days
        if dte < 0 or dte > dte_max:
            continue
        chain = tk.option_chain(exp)
        puts  = chain.puts[chain.puts['strike'] < spot].copy()
        calls = chain.calls[chain.calls['strike'] > spot].copy()
        puts['dist']  = abs(puts['strike']  - spot * (1 - delta_pct))
        calls['dist'] = abs(calls['strike'] - spot * (1 + delta_pct))
        put_iv  = puts.nsmallest(2, 'dist')['impliedVolatility'].mean()
        call_iv = calls.nsmallest(2, 'dist')['impliedVolatility'].mean()
        if pd.notna(put_iv) and pd.notna(call_iv):
            results.append((put_iv, call_iv))
    if not results:
        return None
    avg_put  = sum(r[0] for r in results) / len(results)
    avg_call = sum(r[1] for r in results) / len(results)
    return avg_put - avg_call   # -> options_snapshots.iv_skew
```

---

## 注意事項

1. **欄位名稱常見混淆**：
   - options_snapshots.symbol ≠ iv_daily_snapshots.ticker（兩表主鍵欄位名不同）
   - option_snapshots（無複數 s）= 逐合約原始資料表
   - options_snapshots（有複數 s）= 跨標的快取表，兩者不同

2. **無預存 Rank 欄位**：
   - iv_daily_snapshots 無 iv_rank，需動態算
   - options_snapshots 無 skew_rank，需動態算

3. 顏色主題：背景 #0d0d0d，卡片 #111，邊框 #2a2a2a，hover #3a3a3a

4. 每格大小：約 120x130px，`grid repeat(auto-fill, minmax(115px, 1fr))`

5. 點擊卡片導向 /iv_analysis?ticker=XXX

6. 頁面頂部日期選擇器，預設今日，可回溯歷史

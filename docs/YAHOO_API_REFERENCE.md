# Yahoo Finance API 參考文件

> **性質：非官方 API，無公開文件，Yahoo 隨時可能異動，使用需自行承擔風險。**
> 本文件依據 2026-03-12 實際呼叫結果整理，以實際回傳為準。

---

## 驗證流程（裸用 HTTP，必讀）

Yahoo Finance v10 系列 endpoint 需要 **crumb + session cookie** 才能成功回傳資料。

### 兩步驟取 crumb

```
Step 1  GET https://finance.yahoo.com
        Header: Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
        Header: User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ...
        → Response Header: set-cookie: A1=d=...&S=...  ← 取這個

Step 2  GET https://query2.finance.yahoo.com/v1/test/getcrumb
        Header: Cookie: A1=<上一步取到的值>
        → Response Body: <crumb 字串，如 /sW0q42JKTe>
```

**關鍵注意事項**：
- Step 1 的 `Accept` 標頭必須是 `text/html`（若用 `application/json` 或 `*/*` 將不回傳 cookie，crumb endpoint 會回傳 HTTP 406）
- Step 2 的 crumb endpoint 本身用 `follow_redirects: false` 呼叫較穩定
- Crumb 和 Cookie 的有效期約數小時，建議每次請求時重新取得（成本低，約 2 個 HTTP 請求）

### 後續請求格式

```
GET https://query2.finance.yahoo.com/v10/finance/quoteSummary/{SYMBOL}
    ?modules=<module1>,<module2>
    &crumb=<crumb>
Header: Cookie: A1=<cookie>
```

---

## Endpoint 1：K 線 / 報價（**不需驗證**）

```
GET https://query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}
    ?interval=1d&range=1y
```

### 回傳結構（實測 AAPL）

```json
{
  "chart": {
    "result": [
      {
        "meta": {
          "symbol": "AAPL",
          "currency": "USD",
          "exchangeName": "NMS",
          "fullExchangeName": "NasdaqGS",
          "instrumentType": "EQUITY",
          "regularMarketPrice": 254.76,
          "fiftyTwoWeekHigh": 288.62,
          "fiftyTwoWeekLow": 169.21,
          "regularMarketVolume": 7527172,
          "regularMarketDayHigh": 258.95,
          "regularMarketDayLow": 254.50,
          "chartPreviousClose": 260.29,
          "gmtoffset": -14400,
          "timezone": "EDT",
          "exchangeTimezoneName": "America/New_York",
          "longName": "Apple Inc.",
          "shortName": "Apple Inc.",
          "regularMarketTime": 1773325940,
          "firstTradeDate": 345479400,
          "hasPrePostMarketData": true,
          "priceHint": 2,
          "dataGranularity": "1d",
          "range": "5d",
          "validRanges": ["1d","5d","1mo","3mo","6mo","1y","2y","5y","10y","ytd","max"],
          "currentTradingPeriod": {
            "pre":     { "start": 1773302400, "end": 1773322200, "timezone": "EDT", "gmtoffset": -14400 },
            "regular": { "start": 1773322200, "end": 1773345600, "timezone": "EDT", "gmtoffset": -14400 },
            "post":    { "start": 1773345600, "end": 1773360000, "timezone": "EDT", "gmtoffset": -14400 }
          }
        },
        "indicators": {
          "quote": [
            {
              "open":   [Float, ...],
              "high":   [Float, ...],
              "low":    [Float, ...],
              "close":  [Float, ...],
              "volume": [Integer, ...]
            }
          ],
          "adjclose": [{ "adjclose": [Float, ...] }]
        },
        "timestamp": [Integer, ...]
      }
    ],
    "error": null
  }
}
```

**本專案使用方式**（`YahooFinanceService#chart`）：
- `meta.fiftyTwoWeekHigh` / `meta.fiftyTwoWeekLow`
- `meta.regularMarketVolume`
- `meta.regularMarketChangePercent`（或用 `regularMarketPrice` / `chartPreviousClose` 計算）
- `indicators.quote[0].close[]`（K 線收盤價陣列）

---

## Endpoint 2：quoteSummary（**需要驗證**）

```
GET https://query2.finance.yahoo.com/v10/finance/quoteSummary/{SYMBOL}
    ?modules=<modules>&crumb=<crumb>
```

### 數值欄位格式規律

所有數值欄位皆包含三個子欄位：

| 子欄位 | 類型 | 說明 |
|--------|------|------|
| `raw`  | Number | 原始數值，供程式計算 |
| `fmt`  | String | 格式化字串，如 `"65.21%"`、`"3.74T"` |
| `longFmt` | String | 完整格式，如 `"3,744,590,462,976.00"`（部分欄位才有） |

**本專案一律取 `raw`。**

---

### Module: `price`

```json
{
  "quoteSummary": {
    "result": [{
      "price": {
        "symbol": "AAPL",
        "longName": "Apple Inc.",
        "currency": "USD",
        "exchangeName": "NasdaqGS",
        "marketCap":                    { "raw": 3744590462976, "fmt": "3.74T", "longFmt": "..." },
        "regularMarketPrice":           { "raw": 254.77,        "fmt": "254.77" },
        "regularMarketChange":          { "raw": -6.0399933,    "fmt": "-6.04" },
        "regularMarketChangePercent":   { "raw": -0.023158595,  "fmt": "-2.32%" },
        "regularMarketVolume":          { "raw": 7527379,       "fmt": "7.53M", "longFmt": "7,527,379.00" },
        "regularMarketDayHigh":         { "raw": ..., "fmt": "..." },
        "regularMarketDayLow":          { "raw": ..., "fmt": "..." },
        "regularMarketOpen":            { "raw": ..., "fmt": "..." },
        "regularMarketPreviousClose":   { "raw": ..., "fmt": "..." }
      }
    }],
    "error": null
  }
}
```

---

### Module: `majorHoldersBreakdown`（實測 AAPL 2026-03-12）

```json
{
  "majorHoldersBreakdown": {
    "maxAge": 1,
    "insidersPercentHeld":        { "raw": 0.01637,      "fmt": "1.64%" },
    "institutionsPercentHeld":    { "raw": 0.65213996,   "fmt": "65.21%" },
    "institutionsFloatPercentHeld": { "raw": 0.66300005, "fmt": "66.30%" },
    "institutionsCount":          { "raw": 7521, "fmt": "7.52k", "longFmt": "7,521" }
  }
}
```

---

### Module: `institutionOwnership`（實測 AAPL 前 10 筆，2026-03-12）

```json
{
  "institutionOwnership": {
    "maxAge": 1,
    "ownershipList": [
      {
        "maxAge": 1,
        "reportDate": { "raw": 1767139200, "fmt": "2025-12-31" },
        "organization": "Vanguard Group Inc",
        "pctHeld":   { "raw": 0.097200006, "fmt": "9.72%" },
        "position":  { "raw": 1426283914,  "fmt": "1.43B",    "longFmt": "1,426,283,914" },
        "value":     { "raw": 363374358863,"fmt": "363.37B",   "longFmt": "363,374,358,863" },
        "pctChange": { "raw": 0.019199999, "fmt": "1.92%" }
      },
      {
        "organization": "Blackrock Inc.",
        "pctHeld":   { "raw": 0.078600004, "fmt": "7.86%" },
        "value":     { "raw": 294174193220,"fmt": "294.17B" },
        "pctChange": { "raw": 0.0073, "fmt": "0.73%" }
      }
      // ... 最多回傳 10 筆
    ]
  }
}
```

**欄位說明**：

| 欄位 | 說明 |
|------|------|
| `organization` | 機構名稱 |
| `pctHeld.raw` | 持股佔總股本比例（0~1 之間，×100 = %） |
| `position.raw` | 持有股數 |
| `value.raw` | 持股市值（USD） |
| `pctChange.raw` | 較上一季持股變動（正 = 增持，負 = 減持） |
| `reportDate.fmt` | 申報季末日期，格式 YYYY-MM-DD |

---

## 完整 quoteSummary Modules 清單

以下模組已確認存在（來源：社群文件 + 2026 實測）：

| 類別 | Module 名稱 |
|------|-------------|
| 基本資訊 | `assetProfile`, `summaryProfile`, `summaryDetail`, `quoteType`, `price` |
| 持股結構 | `majorHoldersBreakdown`, `institutionOwnership`, `fundOwnership`, `insiderHolders`, `insiderTransactions`, `majorDirectHolders` |
| 財務報表 | `financialData`, `defaultKeyStatistics`, `incomeStatementHistory`, `incomeStatementHistoryQuarterly`, `balanceSheetHistory`, `balanceSheetHistoryQuarterly`, `cashflowStatementHistory`, `cashflowStatementHistoryQuarterly` |
| 分析師評級 | `recommendationTrend`, `upgradeDowngradeHistory`, `earningsTrend` |
| 收益 | `earnings`, `earningsHistory`, `calendarEvents` |
| 基金專用 | `fundProfile`, `fundPerformance`, `topHoldings` |
| 其他 | `secFilings`, `netSharePurchaseActivity`, `indexTrend`, `sectorTrend` |

---

## 本專案使用方式摘要

| Service 方法 | Endpoint | 認證 | 使用 Modules |
|---|---|---|---|
| `YahooFinanceService#chart` | `/v8/finance/chart` | 不需要 | — |
| `YahooFinanceService#holders` | `/v10/finance/quoteSummary` | 需要 crumb | `majorHoldersBreakdown`, `institutionOwnership` |

### Ruby 呼叫範例

```ruby
svc = YahooFinanceService.new

# K 線（不需驗證）
chart = svc.chart("AAPL", range: "1y", interval: "1d")
# => { high_52w:, low_52w:, volume:, change_pct:, closes: [], volumes: [] }

# 持股結構（需驗證，自動取 crumb）
data = svc.holders("AAPL")
# => {
#      summary: { institutions_pct:, insiders_pct:, institutions_float_pct:, institutions_count: },
#      top_holders: [ { name:, pct_held:, value:, report_date: }, ... ],
#      source: "Yahoo Finance"
#    }
# 若失敗回傳 nil（觸發 SecEdgarService fallback）
```

---

## 已知限制與注意事項

1. **Cookie 有效期**：A1 cookie 約數小時過期，每次呼叫前重新取得（成本：2 HTTP request）
2. **crumb 綁定 cookie**：crumb 與 cookie 必須配對使用，不可混用
3. **Accept header 關鍵**：取 cookie 時必須用 `Accept: text/html`，否則不回傳 cookie
4. **institutionOwnership 最多 10 筆**：API 固定只回傳前 10 大機構
5. **數據更新頻率**：`maxAge: 1` 表示每日更新；持股資料為季報，每季更新一次
6. **Host 負載均衡**：`query1` 與 `query2` 皆可使用，本專案統一使用 `query2`

---

*最後更新：2026-03-12 | 實測股票：AAPL*

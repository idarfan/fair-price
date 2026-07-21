# 公允價值偏離診斷（案例：NOK）

問題：一般股適用模型算出 NOK 公允價 $2.37–$3.94，市場共識 $8.5–$15，偏離過大。懷疑資料層錯誤（ADR/原股混用、幣別、trailing EPS 污染），其次才是模型倍數假設。

規則：依階段順序執行；每階段驗證未過，禁止進入下一階段。狀態表每過一階段即 patch 更新。

## 執行狀態表

| 階段 | 狀態 | 驗證結果 |
|---|---|---|
| S1 輸入數據 dump | ✅ 完成 | `tmp/fv_diag_nok.json` 已產出，見下 |
| S2 幣別/listing 判定 | ✅ 完成 | `mismatch:price_currency_vs_metric_currency`，見下 |
| S3 EPS 正規化檢查 | ✅ 完成 | `ttm_normalized`（excl extra items），非一次性減損污染 |
| S4 模型公式檢查 | ✅ 完成 | 手算重現 $2.37 / $3.94 誤差 < $0.01 |
| S5 修正與回歸 | ⚠️ 部分完成 | 幣別 bug 已修正，但公允價仍未達 $7–$16，見下方「S5 缺口」 |

## S1 結果

`tmp/fv_diag_nok.json`：source=Finnhub、exchange="NASDAQ OMX HELSINKI LTD."、eps_ttm=0.1406、eps_fwd=null、revenue=20,063,960,784、growth=0.1687、currency=EUR、price=10.08。

`eps_fwd` 為 null：非 bug，Finnhub `/stock/metric`（免費層）完全不提供前瞻 EPS 欄位（已列出全部 eps* 欄位確認），此限制記錄於下方待辦。

## S2 結果：currency_verdict = `mismatch:price_currency_vs_metric_currency`

**verdict_basis**：以 stockanalysis.com（NYSE: NOK 即時報價）交叉驗證：
- `current_price` 10.08 與外部 USD ADR 報價完全吻合（quote 端點正確）。
- 但 `eps_ttm`（0.1406）、`total_revenue`（20.06B）、`book_value`（3.7873）、52週高低（3.419/14.995）與外部 USD 數字（EPS $0.16、營收 $23.06B、52週 4.00–17.45）不符，換算成 EUR（÷ FX 0.8758）後幾乎完全吻合。

**根因**：Finnhub 對雙掛牌 ADR（如 NOK）：`/quote` 端點回傳掛牌交易所價格（美股 ticker 恆為 USD），但 `/stock/profile2`、`/stock/metric` 回傳公司財報原始幣別（Nokia 為 EUR，因主要上市地為 Helsinki OMX）。`StockDataService` 原本把兩者未經換算直接混用，造成「USD 股價 ÷ EUR 每股盈餘」的貨幣錯位，是 $2.37–$3.94 偏低的**主因**。

## S3 結果：eps_basis = `ttm_normalized`

`epsBasicExclExtraItemsTTM` = `epsExclExtraItemsTTM` = `epsTTM` = 0.1406（三者相同），已排除一次性項目，非減損污染問題。

## S4 結果：公式重現

一般股模型：`[DCF, P/E, PEG]`。DCF 因 `free_cashflow` 為 nil（Finnhub 未提供 NOK 的 FCF/股）被 `compact` 跳過，僅剩：
- P/E：`EPS(EUR) 0.1406 × Communication Services 平均 P/E 28x = $3.94`
- PEG：`PEG=1 時公允P/E=17x → 0.1406 × 17 = $2.37`

手算重現誤差 < $0.01，確認理解正確。

## S5：已修正 + 剩餘缺口

**已修正**（`app/services/stock_data_service.rb`、`app/services/exchange_rate_service.rb`）：新增 `ExchangeRateService.rate_to_usd(currency)`，`StockDataService#parse` 於 `financial_currency != "USD"` 時，將 EPS/淨值/股利/營收/EBITDA/52週高低換算為 USD 後再回傳，並在 `currency_note` 標註換算依據。修正後 NOK 數字與外部驗證幾乎完全吻合（EPS $0.1605 vs 外部 $0.16、營收 $22.91B vs $23.06B）。

**修正後結果**：`fair_value_low: 2.71, fair_value_high: 4.50` — **仍未達驗收標準 $7–$16**。

**剩餘缺口為模型方法論限制，非資料 bug**：
1. DCF 因 Finnhub 無 NOK 的 FCF/股資料而完全跳過，一般股模型少了核心估值法。
2. P/E 法用「產業平均 28x」，但市場實際給 NOK 的本益比是 62x（因 AI 網通建設題材的前瞻成長溢價），PEG 法用 TTM 歷史成長率（16.87%）亦偏保守。這類「本益比遠高於產業均值、市場賭未來成長」的個股，用現行方法論會系統性低估。

**待決策**（需使用者選擇方向，超出本次資料層 bug 修正範圍）：
- (a) DCF 無 FCF 資料時的 fallback（例如用 EBITDA 或淨利估算現金流）？
- (b) P/E 法是否納入前瞻成長溢價調整，或改用 forward P/E（但 Finnhub 免費層無 forward EPS）？
- (c) 或接受此為模型已知限制，僅修資料層 bug，不擴大範圍？

## 回歸測試：待辦（需先決定上述方向再執行，避免重工）

## S1 輸入數據 dump

對 NOK 執行公允價值計算，log 模型實際使用的全部輸入：資料源名稱、掛牌交易所欄位、EPS（trailing/forward 各是多少）、營收、成長率、幣別欄位、股價。輸出到 `tmp/fv_diag_nok.json`。

驗證（機器可判定）：`tmp/fv_diag_nok.json` 存在且含 keys：`source, exchange, eps_ttm, eps_fwd, revenue, growth, currency, price`，值皆非 null。

## S2 幣別/listing 判定

比對基準（USD ADR，Nokia 2025 年報换算）：EPS TTM 約 $0.36–0.42、營收約 $21–23B。若 dump 值明顯落在 EUR 原股區間或量級不符，判定為 listing/幣別錯誤。

驗證：在 `tmp/fv_diag_nok.json` 追加 `currency_verdict` 欄位，值為 `ok` 或 `mismatch:<原因>`；判定依據寫入 `verdict_basis`（引用的基準值與來源）。

## S3 EPS 正規化檢查

檢查模型是否使用含一次性減損的 trailing EPS。列出所用 EPS 的來源期間與是否為 normalized。

驗證：json 追加 `eps_basis`（`ttm_raw` / `ttm_normalized` / `forward`）與該值。

## S4 模型公式檢查

Dump 一般股適用模型的完整公式與參數（倍數、折現率、成長率如何進入計算），以 S1 的輸入手算重現 $2.37 與 $3.94，證明理解正確。

驗證：json 追加 `formula`, `params`, `reproduced_low`, `reproduced_high`；reproduced 值與 UI 顯示誤差 < $0.01。

## S5 修正與回歸

依 S2–S4 判定結果修正（資料源選 USD ADR listing / 改用 normalized 或 forward EPS / 調整公式）。修正範圍僅限判定出的錯誤，不得順手改其他邏輯。

驗證：
1. 重跑 NOK：公允價區間落在 $7–$16 內。
2. 回歸至少 3 檔既有正常標的（自 DB 挑近期算過且無偏離爭議者），修正前後公允價變動 < 5%，證明修正未污染非 ADR 標的。
3. 三檔回歸結果（ticker、前後值）寫入 `tmp/fv_diag_regression.json`。

## 驗收

核心用例（無任何 override 參數、預設路徑）對 NOK 端到端跑過一次，附 UI 截圖與 DOM 顯示值。

# 公允價值偏離診斷（案例：NOK）

問題：一般股適用模型算出 NOK 公允價 $2.37–$3.94，市場共識 $8.5–$15，偏離過大。懷疑資料層錯誤（ADR/原股混用、幣別、trailing EPS 污染），其次才是模型倍數假設。

規則：依階段順序執行；每階段驗證未過，禁止進入下一階段。狀態表每過一階段即 patch 更新。

## 執行狀態表

| 階段 | 狀態 | 驗證結果 |
|---|---|---|
| S1 輸入數據 dump | 未開始 | |
| S2 幣別/listing 判定 | 未開始 | |
| S3 EPS 正規化檢查 | 未開始 | |
| S4 模型公式檢查 | 未開始 | |
| S5 修正與回歸 | 未開始 | |

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

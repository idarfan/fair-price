# 一般股公允價值模型升級：P/E 成長溢價 + DCF FCF fallback

背景：NOK 診斷（`fairvalue-nok-diagnosis.md`）結案結論——資料層修正後仍偏低（$2.71–$4.50 vs 共識 $8.5–$15），根因為模型結構：P/E 法用產業均值 28x 忽略成長溢價、DCF 因 Finnhub 無 FCF/股而缺法。本規格補此二項。

規則：依階段順序執行；每階段驗證未過，禁止進入下一階段。狀態表每過一階段即 patch 更新。不得改動本規格範圍外的估值邏輯。

## 執行狀態表

| 階段 | 狀態 | 驗證結果 |
|---|---|---|
| S1 回歸基準集建立 | 未開始 | |
| S2 P/E 前瞻溢價調整 | 未開始 | |
| S3 DCF FCF fallback | 未開始 | |
| S4 三法合成與權重 | 未開始 | |
| S5 回歸與驗收 | 未開始 | |

## S1 回歸基準集建立

從 DB 挑 8 檔既有標的，改動前先固定基準：

- 高成長股 3 檔（TTM 盈餘成長 > 15%）
- 價值股 3 檔（成長 < 5%、P/E < 產業均值）
- ADR 1 檔（NOK 以外）＋ NOK

對每檔記錄：目前模型公允價低/高估、輸入數據、外部參考區間（分析師目標價低/高，來源 Finnhub price target endpoint；取不到者記 null 並註明）。寫入 `tmp/fv_upgrade_baseline.json`。

驗證：檔案存在，8 檔各含 keys `ticker, fv_low_before, fv_high_before, growth_ttm, analyst_low, analyst_high`，前三值非 null。

## S2 P/E 前瞻溢價調整

公式：`adjusted_pe = industry_pe × (1 + min(growth_ttm, growth_cap))`，`growth_cap = 0.5`（防止異常成長率炸倍數）。growth_ttm 為負時不調整（用原 industry_pe，不下修——下修屬另案）。參數集中於估值設定檔，不得散落硬編碼。

驗證：單元測試 3 例通過——(a) growth 0.169、industry_pe 28 → adjusted_pe = 32.73±0.01；(b) growth 0.8 → cap 生效 = 42.0；(c) growth −0.1 → 28.0。

## S3 DCF FCF fallback

FCF/股缺值時的估算鏈，依序 fallback：

1. Finnhub 有 FCF/股 → 直接用（現行為）。
2. 無 → `FCF ≈ 淨利 × fcf_conversion`，`fcf_conversion = 0.9`（設定檔參數）。
3. 淨利 ≤ 0 或缺 → `FCF ≈ EBITDA × 0.5`（設定檔參數）。
4. 皆缺 → DCF 缺法，維持現行兩法，並在輸出 json 標記 `dcf_status: "unavailable"`。

每次計算輸出 `dcf_status`: `native` / `ni_proxy` / `ebitda_proxy` / `unavailable`。

驗證：單元測試 4 例，各 mock 對應資料缺口，斷言 dcf_status 與 FCF 估算值正確。

## S4 三法合成與權重

Dump 現行兩法合成公允價低/高估的規則，將 DCF 併入為第三法。合成規則沿用現行架構（若現行為取法間 min/max 或加權，DCF 同等地位加入，不新設權重邏輯）。proxy 來源（ni_proxy/ebitda_proxy）的 DCF 結果在 UI 分析方法欄註記「DCF（估算）」。

驗證：對任一 dcf_status=native 的標的，手算三法合成結果與程式輸出誤差 < $0.01，過程記入 `tmp/fv_upgrade_s4_check.json`。

## S5 回歸與驗收

重跑 S1 全部 8 檔，寫入 `tmp/fv_upgrade_regression.json`（前後值、dcf_status）：

1. NOK：公允價區間與分析師區間（$8.5–$15）有交集。
2. 高成長 3 檔：新公允價 ≥ 舊值（溢價調整只會上調）。
3. 價值股 3 檔：|新−舊| / 舊 < 15%（低成長股不應被大幅擾動）。
4. 全 8 檔：新區間與各自分析師區間（有值者）有交集或距離較舊值縮小。
5. 任一檔不過 → 回 S2/S3 調參數（僅限設定檔內參數），重跑全集。

驗收：核心用例無 override、預設路徑，UI 對 NOK 端到端跑一次，截圖含估值判斷卡與「分析方法」欄新註記。

## 附註

- growth_cap、fcf_conversion、ebitda_ratio 三參數與其現值須寫入估值設定檔並附註釋，日後調參不動程式碼。
- 本規格不處理：負成長下修、金融股/REIT 特殊模型、產業均值 P/E 資料源更換。

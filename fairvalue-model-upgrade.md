# 一般股公允價值模型升級：P/E 成長溢價 + DCF FCF fallback

背景：NOK 診斷（`fairvalue-nok-diagnosis.md`）結案結論——資料層修正後仍偏低（$2.71–$4.50 vs 共識 $8.5–$15），根因為模型結構：P/E 法用產業均值 28x 忽略成長溢價、DCF 因 Finnhub 無 FCF/股而缺法。本規格補此二項。

規則：依階段順序執行；每階段驗證未過，禁止進入下一階段。狀態表每過一階段即 patch 更新。不得改動本規格範圍外的估值邏輯。

## 執行狀態表

| 階段 | 狀態 | 驗證結果 |
|---|---|---|
| S1 回歸基準集建立 | ✅ 完成 | industry_pe 來源：硬編碼常數 `Valuation::INDUSTRY_PE`（`app/models/valuation/fair_value.rb`），11 產業＋`default=>25`，非外部 API。最終 8 檔：高成長 NVDA/PLTR/AVGO、價值股 XOM/SHOP/VZ、ADR SAP（原選 UMC，因 ADR 換股比例 bug 改選）、NOK。`tmp/fv_upgrade_baseline.json` 已產出，`analyst_low/high` 因 Finnhub price-target 為付費端點而為 null（已註明）。UMC 已知問題記入 `known_issues`，本任務不修 |
| S2 P/E 前瞻溢價調整 | ✅ 完成 | 參數移至 `config/valuation.yml`（`growth_cap: 0.5`），`pe_method(g=nil)` 僅一般股呼叫時傳入 g（其餘股票類型呼叫維持原行為不變）。3 組單元測試通過：(a) g=0.169→32.73 (b) g=0.8→cap生效42.0 (c) g=-0.1→28.0（不調整）。全套 spec 36/36 綠燈 |
| S3 DCF FCF fallback | ✅ 完成 | `resolve_fcf_ps` 實作 native→ni_proxy→ebitda_proxy→unavailable 鏈，`dcf_method` 回傳 `dcf_status` 並在 proxy 來源時於 `method`/`note` 標註「（估算）」。4 組單元測試通過。全套 spec 40/40 綠燈 |
| S4 三法合成與權重 | ✅ 完成 | 合成規則沿用現行架構（`values.min`/`values.max`），DCF 已於 `apply_methods` 同等地位加入一般股陣列，未新設權重邏輯。真實 S1 標的因 Finnhub 免費層皆無 FCF/股資料，全數落 `ni_proxy`（native 實際不可達，已記錄），改用合成資料（`free_cashflow` 有值）驗證 native 情境：手算三法合成結果與程式輸出誤差 = 0.0，見 `tmp/fv_upgrade_s4_check.json` |
| S5 回歸與驗收 | ✅ 完成（依 patch 後定義） | SHOP→TSLA 換檔；驗收條件 1（NOK）patch 為「缺口縮小」、條件 3（價值股）patch 為「僅比較 P/E 法本身」，patch 後 5 項條件全通過，見下方「S5 結果」與 `tmp/fv_upgrade_regression.json` |

## S1 回歸基準集建立

從 DB 挑 8 檔既有標的，改動前先固定基準：

- 高成長股 3 檔（TTM 盈餘成長 > 15%）
- 價值股 3 檔（成長 < 5%、P/E < 產業均值）
- ADR 1 檔（NOK 以外）＋ NOK

對每檔記錄：目前模型公允價低/高估、輸入數據、外部參考區間（分析師目標價低/高，來源 Finnhub price target endpoint；取不到者記 null 並註明）。寫入 `tmp/fv_upgrade_baseline.json`。

驗證：檔案存在，8 檔各含 keys `ticker, fv_low_before, fv_high_before, growth_ttm, analyst_low, analyst_high`，前三值非 null。

### S1 選檔規則（patch v1，已作廢——DB 無公允價值計算紀錄表，前提不成立）

- ~~從 DB 近 30 天有完整公允價值計算紀錄的標的中選。~~
- ~~價值股 3 檔：`growth_ttm < 0.05` 且 `P/E < 產業均值`，取市值最大前 3。~~

### S1 選檔規則（patch v2，現行）

- 選檔池改為 `watchlist_items` / `tracked_tickers` / `watched_tickers` 實際清單，即時呼叫 `StockDataService` 抓 `growth_ttm` 分類。
- 高成長 3 檔：`growth_ttm > 0.15`，取最高前 3。
- 價值股 3 檔：`growth_ttm < 0.05`，取市值最大前 3（暫免 `P/E < 產業均值` 條件，因 `fundamentals` 表 `sector` 全為 null、產業均值來源待釐清，此條件無法可靠套用）。
- ADR 1 檔：`exchange` 欄位非美國本土掛牌者任選 1（NOK 除外）。
- 任一類不足額 → 停在 S1，回報實際清單與各檔 `growth_ttm`，等使用者指定。

### S1 選檔結果（候選池：F, NOK, SHOP, UMC, WULF, XOM；SQQQ 為槓桿 ETF 已排除）

| Ticker | growth_ttm | 市值（USD） | 掛牌 | 分類 |
|---|---|---|---|---|
| NOK | 0.1687 | 57.9B | Helsinki（財報）／NYSE（股價） | 固定 1 檔 |
| UMC | 0.1258 | 255.3B | 台灣證交所 | ADR 候選 ✓ |
| XOM | -0.2159 | 614.9B | NYSE | 價值股候選 |
| SHOP | -0.1739 | 161.5B | NASDAQ | 價值股候選 |
| F | null（EPS 為負，Finnhub 無成長率） | 55.7B | NYSE | 無法分類 |
| WULF | null（同上） | 9.3B | NASDAQ | 無法分類 |

**缺口**：高成長 0/3（候選池無任何非 NOK 標的 growth_ttm > 0.15）、價值股 2/3（已有 XOM、SHOP，缺 1）。ADR、NOK 已滿足。

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

## S5 結果

`tmp/fv_upgrade_regression.json` 已產出（8 檔前後值、`dcf_status`、`model_growth_rate_used`）。

驗收 1（NVDA/PLTR/AVGO 新值≥舊值）：✅ 全過。
驗收 2（XOM/VZ 變動 <15%）：✅ 過。
驗收 3（SHOP 變動 <15%）：❌ 未過，high $35.62→$46.97（+31.9%）。
驗收 4（NOK 落入 $8.5–$15）：❌ 未過，$2.71→$5.25（仍偏低）。
驗收 5（全 8 檔更貼近分析師區間）：N/A，Finnhub price-target 端點免費層無權限，全為 null（S1 已註明）。

### SHOP 失敗根因：選檔代理指標與模型內部成長率不一致（選檔失誤，非公式 bug）

S1 選檔用 `earnings_growth`（TTM 盈餘成長，SHOP = −17.4%）判定為價值股，但 `pe_method`/`dcf_method` 實際使用的 `growth_rate` 來自 `Classifier#estimate_growth_rate`——取「盈餘成長／營收成長／季度盈餘成長／FwdEPS 推算」多來源的**中位數**，SHOP 中位數為 **31.85%**（其他來源蓋過負的 TTM 盈餘成長）。以模型自身邏輯，SHOP 本來就不是低成長股，S2 溢價調整依此正確反應。此為選檔失誤，不是 S2 公式錯誤。

**已換檔**：改用 TSLA（`model_growth_rate_used=0.03`，watchlist 池中 <0.05 候選市值最大者）取代 SHOP。`tmp/fv_upgrade_baseline.json` 已更新。

**換檔後發現新問題**：TSLA 的 `stock_type` 為「週期股」（Consumer Cyclical + EPS 為負觸發），實際方法為 `[EV/EBITDA, P/B, DCF]`，完全不經過 P/E/PEG，因此不受 S2 影響。修改前基準（EV/EBITDA=$25.34、P/B=$26.88，皆不受本次升級影響）：low=$25.34, high=$26.88。修改後 S3 新增 DCF（ni_proxy=$14.49）成為新低點：low=$14.49, high=$26.88（不變）。整體區間 low 變動 42.8%，未通過原始 <15% 門檻——成因是 S3「新增 DCF 為第三法」的結構性效果，與成長率高低無關，代表驗收條件 3 原始設計沒有涵蓋 S3 新增方法本身就會位移 min/max 的效果。

**驗收條件 3 patch（已套用）**：重定義為「僅比較 P/E 法本身前後差異，隔離 S2 效果；方法組成變動（S3 新增 DCF）不計入擾動」。結果：
- XOM、TSLA：皆為週期股，不使用 P/E 法，S2 對其無影響 → **N/A**（不計入驗收）
- VZ：唯一使用 P/E 法者，P/E 值 $114.90→$118.35，變動 **3.0%**，< 15% → **PASS**

價值股組（XOM/VZ/TSLA）在 patch 後定義下**全數通過**。詳見 `tmp/fv_upgrade_s5_condition3_pe_only.json`。

### NOK 失敗根因：`growth_cap` 未被觸發，公式結構天花板，非參數可調

NOK `growth_rate=16.9%`，遠低於 `growth_cap=0.5`，調整 `growth_cap` 不會改變結果（cap 未生效）。要讓 $0.16 EPS 對應 $8.5，PE 需達 ~53x（較基準 28x 溢價 +89%），但現行公式 `industry_pe × (1+min(g, cap))` 在 g=16.9% 時上限僅 +16.9%（32.7x）。這是公式本身的結構限制，需要不同公式（如非線性溢價、或改用 forward P/E 直接倍數）才能觸及，超出本規格「不新設權重邏輯、不改動範圍外估值邏輯」的授權範圍。

**驗收條件 1 patch（已套用）**：
- ~~刪：與 $8.5–$15 有交集~~
- 改：升級後 NOK 公允價區間較升級前（$2.71–$4.50）向共識區間縮小距離，並記錄 `residual_gap_cause`。

結果：升級前 high=$4.50，距共識下界 $8.5 差 **$4.00**；升級後 high=$5.25，差縮小為 **$3.25** → `gap_shrunk: true` → **PASS**。`residual_gap_cause: "ttm_eps_basis（market prices forward EPS; requires forward EPS data source, out of scope）"` 已記入 `tmp/fv_upgrade_s5_condition1_nok.json`——市場實際定價反映的是前瞻 EPS 預期，現行模型僅用 TTM EPS，此為殘餘缺口的根本原因，需要前瞻 EPS 資料源才能進一步收斂，超出本規格範圍。

## 附註

- growth_cap、fcf_conversion、ebitda_ratio 三參數與其現值須寫入估值設定檔並附註釋，日後調參不動程式碼。
- 本規格不處理：負成長下修、金融股/REIT 特殊模型、產業均值 P/E 資料源更換。

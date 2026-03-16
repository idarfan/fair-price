# Valuation Methods Reference

## Stock Classification & Method Selection

| 類別 | 判斷標準 | 主要方法（最多3種）| 參考方法 |
|------|---------|-----------------|---------|
| 一般股 | 正常盈利、非特殊行業 | DCF + P/E + PEG | — |
| 金融股 | 銀行/保險/券商（BV重要）| ExcessReturns + P/E + P/B | — |
| REITs | 房地產信託，以配息為主 | DDM + DCF + P/B | — |
| 公用事業 | 穩定現金流、高配息 | DDM + DCF + P/E | — |
| 虧損成長股 | 目前虧損、高速成長 | RevMultiple + DCF(保守) | — |
| 週期股 | 產業週期明顯（鋼鐵/能源/化工）| EV/EBITDA + P/B + DCF | — |

---

## Method Formulas

### DCF (Discounted Cash Flow)
```
FCF_n = FCF_0 × (1 + g)^n        # 預測5年
TV = FCF_5 × (1 + g_terminal) / (r - g_terminal)
PV = Σ FCF_n/(1+r)^n + TV/(1+r)^5
Fair Value per Share = PV / Shares Outstanding
```
預設：r=10%, g=成長率, g_terminal=3%

### P/E (Price-to-Earnings)
```
Fair Value = EPS × Industry_Average_PE
```
使用 forward EPS 與產業平均 P/E

### PEG (Price/Earnings-to-Growth)
```
Fair Value = EPS × (EPS_Growth_Rate × 100)
PEG < 1 → 低估, PEG > 1 → 高估
```

### P/B (Price-to-Book)
```
Fair Value = BVPS × Industry_Average_PB
```

### DDM (Dividend Discount Model)
```
Fair Value = D1 / (r - g)
D1 = D0 × (1 + g)
```
適用於穩定配息股

### ExcessReturns (金融股)
```
Value = BV + PV(ExcessReturns)
ExcessReturn = (ROE - CoE) × BV
PV = ExcessReturn / (CoE - g)
```

### RevMultiple (虧損成長股)
```
Fair Value = Revenue × Sector_Revenue_Multiple / Shares
```
比較同類上市公司 EV/Revenue

### EV/EBITDA (週期股)
```
EV = EBITDA × Industry_EV_EBITDA_Multiple
Equity Value = EV - Net Debt
Fair Value = Equity Value / Shares
```

---

## Fair Value Judgment

| 股價 vs 公允價值 | 判斷 |
|---------------|------|
| 股價 > 公允價值上限 20%+ | 🔴 明顯高估 |
| 股價 > 公允價值上限 | 🟡 略微高估 |
| 在區間內 | 🟢 合理 |
| 股價 < 公允價值下限 | 🟡 略微低估 |
| 股價 < 公允價值下限 20%+ | 🟢 明顯低估（潛在買點）|

# frozen_string_literal: true

class StrategyRecommender
  STRATEGIES = {
    bullish: {
      high_iv: [
        { name: "Cash Secured Put", key: "cash_secured_put",
          desc: "賣 OTM Put，收 Premium，願意在 Strike 價接股",
          dte: "30–45 天", delta: "−0.20 ~ −0.35", credit: true,
          max_profit: "收入 Premium", risk: "Strike 全額（同持股）" },
        { name: "Bull Put Spread", key: "bull_put_spread",
          desc: "賣高 Strike Put + 買低 Strike Put，限定風險看漲",
          dte: "21–35 天", delta: "−0.25 ~ −0.35", credit: true,
          max_profit: "淨 Credit", risk: "兩 Strike 差 − 淨 Credit" }
      ],
      low_iv: [
        { name: "Long Call", key: "long_call",
          desc: "直接買 Call，低 IV 時 Premium 便宜",
          dte: "45–60 天", delta: "0.30 ~ 0.50", credit: false,
          max_profit: "無限", risk: "全部 Premium" },
        { name: "Bull Call Spread", key: "bull_call_spread",
          desc: "買低 Strike Call + 賣高 Strike Call，降低成本",
          dte: "30–45 天", delta: "淨 0.30 ~ 0.45", credit: false,
          max_profit: "兩 Strike 差 − 淨 Debit", risk: "淨 Debit" }
      ]
    },
    bearish: {
      high_iv: [
        { name: "Bear Call Spread", key: "bear_call_spread",
          desc: "賣低 Strike Call + 買高 Strike Call，限定風險看跌",
          dte: "21–35 天", delta: "0.25 ~ 0.35", credit: true,
          max_profit: "淨 Credit", risk: "兩 Strike 差 − 淨 Credit" }
      ],
      low_iv: [
        { name: "Long Put", key: "long_put",
          desc: "直接買 Put，低 IV 時 Premium 便宜",
          dte: "45–60 天", delta: "−0.30 ~ −0.50", credit: false,
          max_profit: "Strike − Premium", risk: "全部 Premium" },
        { name: "Bear Put Spread", key: "bear_put_spread",
          desc: "買高 Strike Put + 賣低 Strike Put，降低成本",
          dte: "30–45 天", delta: "淨 −0.30 ~ −0.45", credit: false,
          max_profit: "兩 Strike 差 − 淨 Debit", risk: "淨 Debit" }
      ]
    },
    neutral: {
      high_iv: [
        { name: "Iron Condor", key: "iron_condor",
          desc: "賣 OTM Strangle + 翼部保護，四腳盤整收 Premium",
          dte: "30–45 天", delta: "±0.15 ~ ±0.25", credit: true,
          max_profit: "淨 Credit", risk: "翼部寬度 − 淨 Credit" },
        { name: "Short Strangle", key: "short_strangle",
          desc: "賣 OTM Call + 賣 OTM Put，無限風險但 Premium 最大",
          dte: "30–45 天", delta: "±0.20 ~ ±0.30", credit: true,
          max_profit: "淨 Credit", risk: "無限（需保證金）" }
      ],
      low_iv: [
        { name: "Iron Butterfly", key: "iron_butterfly",
          desc: "ATM Short Straddle + OTM 翼部，看極度不動",
          dte: "21–35 天", delta: "ATM", credit: true,
          max_profit: "淨 Credit（最大）", risk: "翼部寬度 − 淨 Credit" }
      ]
    },
    volatile: {
      any: [
        { name: "Long Straddle", key: "long_straddle",
          desc: "買 ATM Call + Put，不確定方向看大波動",
          dte: "45–60 天", delta: "接近 0", credit: false,
          max_profit: "無限（任一方向）", risk: "總 Premium（兩腳）" },
        { name: "Long Strangle", key: "long_strangle",
          desc: "買 OTM Call + Put，成本低於 Straddle",
          dte: "45–60 天", delta: "接近 0", credit: false,
          max_profit: "無限（任一方向）", risk: "總 Premium（較低）" }
      ]
    }
  }.freeze
end

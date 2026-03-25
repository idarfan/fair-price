import type { MarketOutlook, IvEnv, StrategyTemplate } from './types'

type StrategyMap = {
  [K in MarketOutlook]: Partial<Record<IvEnv | 'any', StrategyTemplate[]>>
}

export const STRATEGIES: StrategyMap = {
  bullish: {
    high_iv: [
      {
        key: 'cash_secured_put', name: 'Cash Secured Put',
        desc: '賣 OTM Put，收 Premium，願意在 Strike 價接股',
        dte: '30–45 天', delta: '−0.20 ~ −0.35', credit: true,
        maxProfit: '收入 Premium', risk: 'Strike 全額（同持股）',
        defaultLegs: [{ type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.60, dte: 35 }],
      },
      {
        key: 'bull_put_spread', name: 'Bull Put Spread',
        desc: '賣高 Strike Put + 買低 Strike Put，限定風險看漲',
        dte: '21–35 天', delta: '−0.25 ~ −0.35', credit: true,
        maxProfit: '淨 Credit', risk: '兩 Strike 差 − 淨 Credit',
        defaultLegs: [
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.60, dte: 30 },
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.65, dte: 30 },
        ],
      },
    ],
    low_iv: [
      {
        key: 'long_call', name: 'Long Call',
        desc: '直接買 Call，低 IV 時 Premium 便宜',
        dte: '45–60 天', delta: '0.30 ~ 0.50', credit: false,
        maxProfit: '無限', risk: '全部 Premium',
        defaultLegs: [{ type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.35, dte: 50 }],
      },
      {
        key: 'bull_call_spread', name: 'Bull Call Spread',
        desc: '買低 Strike Call + 賣高 Strike Call，降低成本',
        dte: '30–45 天', delta: '淨 0.30 ~ 0.45', credit: false,
        maxProfit: '兩 Strike 差 − 淨 Debit', risk: '淨 Debit',
        defaultLegs: [
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.35, dte: 40 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.33, dte: 40 },
        ],
      },
    ],
  },
  bearish: {
    high_iv: [
      {
        key: 'bear_call_spread', name: 'Bear Call Spread',
        desc: '賣低 Strike Call + 買高 Strike Call，限定風險看跌',
        dte: '21–35 天', delta: '0.25 ~ 0.35', credit: true,
        maxProfit: '淨 Credit', risk: '兩 Strike 差 − 淨 Credit',
        defaultLegs: [
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.55, dte: 30 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 30 },
        ],
      },
    ],
    low_iv: [
      {
        key: 'long_put', name: 'Long Put',
        desc: '直接買 Put，低 IV 時 Premium 便宜',
        dte: '45–60 天', delta: '−0.30 ~ −0.50', credit: false,
        maxProfit: 'Strike − Premium', risk: '全部 Premium',
        defaultLegs: [{ type: 'long_put', strike: 0, premium: 0, quantity: 1, iv: 0.38, dte: 50 }],
      },
      {
        key: 'bear_put_spread', name: 'Bear Put Spread',
        desc: '買高 Strike Put + 賣低 Strike Put，降低成本',
        dte: '30–45 天', delta: '淨 −0.30 ~ −0.45', credit: false,
        maxProfit: '兩 Strike 差 − 淨 Debit', risk: '淨 Debit',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 40 },
          { type: 'short_put', strike: 0, premium: 0, quantity: 1, iv: 0.40, dte: 40 },
        ],
      },
    ],
  },
  neutral: {
    high_iv: [
      {
        key: 'iron_condor', name: 'Iron Condor',
        desc: '賣 OTM Strangle + 翼部保護，四腳盤整收 Premium',
        dte: '30–45 天', delta: '±0.15 ~ ±0.25', credit: true,
        maxProfit: '淨 Credit', risk: '翼部寬度 − 淨 Credit',
        defaultLegs: [
          { type: 'long_put',   strike: 0, premium: 0, quantity: 1, iv: 0.68, dte: 35 },
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.62, dte: 35 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.55, dte: 35 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 35 },
        ],
      },
      {
        key: 'short_strangle', name: 'Short Strangle',
        desc: '賣 OTM Call + 賣 OTM Put，無限風險但 Premium 最大',
        dte: '30–45 天', delta: '±0.20 ~ ±0.30', credit: true,
        maxProfit: '淨 Credit', risk: '無限（需保證金）',
        defaultLegs: [
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.58, dte: 35 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.53, dte: 35 },
        ],
      },
    ],
    low_iv: [
      {
        key: 'iron_butterfly', name: 'Iron Butterfly',
        desc: 'ATM Short Straddle + OTM 翼部，看極度不動',
        dte: '21–35 天', delta: 'ATM', credit: true,
        maxProfit: '淨 Credit（最大）', risk: '翼部寬度 − 淨 Credit',
        defaultLegs: [
          { type: 'long_put',   strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 28 },
          { type: 'short_put',  strike: 0, premium: 0, quantity: 1, iv: 0.44, dte: 28 },
          { type: 'short_call', strike: 0, premium: 0, quantity: 1, iv: 0.44, dte: 28 },
          { type: 'long_call',  strike: 0, premium: 0, quantity: 1, iv: 0.42, dte: 28 },
        ],
      },
    ],
  },
  volatile: {
    any: [
      {
        key: 'long_straddle', name: 'Long Straddle',
        desc: '買 ATM Call + Put，不確定方向看大波動',
        dte: '45–60 天', delta: '接近 0', credit: false,
        maxProfit: '無限（任一方向）', risk: '總 Premium（兩腳）',
        defaultLegs: [
          { type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.50, dte: 50 },
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 50 },
        ],
      },
      {
        key: 'long_strangle', name: 'Long Strangle',
        desc: '買 OTM Call + Put，成本低於 Straddle',
        dte: '45–60 天', delta: '接近 0', credit: false,
        maxProfit: '無限（任一方向）', risk: '總 Premium（較低）',
        defaultLegs: [
          { type: 'long_put',  strike: 0, premium: 0, quantity: 1, iv: 0.52, dte: 50 },
          { type: 'long_call', strike: 0, premium: 0, quantity: 1, iv: 0.50, dte: 50 },
        ],
      },
    ],
  },
}

export function getStrategies(outlook: MarketOutlook, ivRank: number): StrategyTemplate[] {
  const env: IvEnv = ivRank >= 50 ? 'high_iv' : 'low_iv'
  return (
    STRATEGIES[outlook][env] ??
    STRATEGIES[outlook].any ??
    []
  )
}

export function buildLegsForPrice(
  template: StrategyTemplate,
  price: number
): StrategyTemplate['defaultLegs'] {
  const step = price < 50 ? 2.5 : price < 200 ? 5 : price < 500 ? 10 : 25

  return template.defaultLegs.map((leg, i) => {
    let strike: number
    if (template.key === 'iron_condor') {
      const offsets = [-2, -1, 1, 2]
      strike = Math.round((price + offsets[i] * step * 1.5) / step) * step
    } else if (template.key === 'iron_butterfly') {
      const offsets = [-2, 0, 0, 2]
      strike = Math.round((price + offsets[i] * step * 2) / step) * step
    } else if (template.defaultLegs.length === 2 && i === 0) {
      strike = leg.type.includes('put')
        ? Math.round((price * 0.95) / step) * step
        : Math.round((price * 1.05) / step) * step
    } else if (template.defaultLegs.length === 2 && i === 1) {
      strike = leg.type.includes('put')
        ? Math.round((price * 0.90) / step) * step
        : Math.round((price * 1.10) / step) * step
    } else {
      strike = leg.type.includes('put')
        ? Math.round((price * 0.95) / step) * step
        : Math.round((price * 1.05) / step) * step
    }

    const iv = leg.iv ?? 0.45
    const dte = leg.dte ?? 35
    const T = dte / 365
    const intrinsicApprox = leg.type.includes('call')
      ? Math.max(price - strike, 0)
      : Math.max(strike - price, 0)
    const timeValue = iv * price * Math.sqrt(T) * 0.4
    const premium = Math.max(Math.round((intrinsicApprox + timeValue) * 20) / 20, 0.05)

    return { ...leg, strike, premium }
  })
}

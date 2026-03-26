import type { PayoffLeg, PayoffPoint, PayoffSummary } from './types'

function normCDF(x: number): number {
  const a = [0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429]
  const p = 0.3275911
  const sign = x < 0 ? -1 : 1
  const ax = Math.abs(x)
  const t = 1 / (1 + p * ax)
  const y = 1 - (((((a[4] * t + a[3]) * t + a[2]) * t + a[1]) * t + a[0]) * t) * Math.exp(-ax * ax)
  return 0.5 * (1 + sign * y)
}

function bsCall(S: number, K: number, T: number, sig: number): number {
  if (T <= 0) return Math.max(S - K, 0)
  const d1 = (Math.log(S / K) + (0.043 + sig * sig / 2) * T) / (sig * Math.sqrt(T))
  const d2 = d1 - sig * Math.sqrt(T)
  return S * normCDF(d1) - K * Math.exp(-0.043 * T) * normCDF(d2)
}

function bsPut(S: number, K: number, T: number, sig: number): number {
  if (T <= 0) return Math.max(K - S, 0)
  return bsCall(S, K, T, sig) - S + K * Math.exp(-0.043 * T)
}

function legPnl(leg: PayoffLeg, S: number, mode: 'expiry' | 'theory'): number {
  const MULT = leg.type.includes('stock') ? 1 : 100
  let pnl: number

  if (mode === 'theory' && leg.iv && leg.dte && leg.dte > 0 && !leg.type.includes('stock')) {
    const T = leg.dte / 365
    const bs = leg.type.includes('call')
      ? bsCall(S, leg.strike, T, leg.iv)
      : bsPut(S, leg.strike, T, leg.iv)
    pnl = leg.type.startsWith('long') ? bs - leg.premium : leg.premium - bs
  } else {
    const intr = leg.type.includes('call')
      ? Math.max(S - leg.strike, 0)
      : Math.max(leg.strike - S, 0)
    pnl = leg.type.startsWith('long') ? intr - leg.premium : leg.premium - intr
  }
  return Math.round(pnl * leg.quantity * MULT * 100) / 100
}

// ─── Greeks 計算 ──────────────────────────────────────────────────────────────

export interface LegGreeks {
  delta: number
  theta: number   // 每日 Theta（負值 = 時間衰減）
  iv:    number   // 年化 IV（小數）
}

/** 計算單條腿的 Delta 和 Theta（Black-Scholes） */
export function calcLegGreeks(leg: PayoffLeg, price: number): LegGreeks | null {
  const iv  = leg.iv
  const dte = leg.dte
  if (!iv || !dte || dte <= 0 || leg.type.includes('stock') || price <= 0) return null

  const T   = dte / 365
  const r   = 0.043  // 無風險利率
  const d1  = (Math.log(price / leg.strike) + (r + iv * iv / 2) * T) / (iv * Math.sqrt(T))

  const sign = leg.type.startsWith('long') ? 1 : -1
  const isCall = leg.type.includes('call')

  // Delta
  const rawDelta = isCall ? normCDF(d1) : normCDF(d1) - 1
  const delta = rawDelta * sign * leg.quantity

  // Theta（每日）
  const nd1 = Math.exp(-d1 * d1 / 2) / Math.sqrt(2 * Math.PI) // N'(d1)
  const d2 = d1 - iv * Math.sqrt(T)
  let rawTheta: number
  if (isCall) {
    rawTheta = -(price * nd1 * iv) / (2 * Math.sqrt(T)) - r * leg.strike * Math.exp(-r * T) * normCDF(d2)
  } else {
    rawTheta = -(price * nd1 * iv) / (2 * Math.sqrt(T)) + r * leg.strike * Math.exp(-r * T) * normCDF(-d2)
  }
  const theta = (rawTheta / 365) * sign * leg.quantity * 100  // per contract per day

  return { delta: Math.round(delta * 1000) / 1000, theta: Math.round(theta * 100) / 100, iv }
}

/** 計算整組策略的 Greeks 彙總 */
export function calcPositionGreeks(legs: PayoffLeg[], price: number): { netDelta: number; netTheta: number } {
  let netDelta = 0
  let netTheta = 0
  for (const leg of legs) {
    const g = calcLegGreeks(leg, price)
    if (g) {
      netDelta += g.delta
      netTheta += g.theta
    }
  }
  return {
    netDelta: Math.round(netDelta * 1000) / 1000,
    netTheta: Math.round(netTheta * 100) / 100,
  }
}

export function buildChartData(legs: PayoffLeg[], price: number): PayoffPoint[] {
  const strikes = legs.map(l => l.strike).filter(s => s > 0)
  const center = strikes.length ? strikes.reduce((a, b) => a + b, 0) / strikes.length : price
  const spread = Math.max(strikes.length >= 2 ? Math.max(...strikes) - Math.min(...strikes) : 0, center * 0.2)
  const lo = Math.floor(center - spread * 1.5)
  const hi = Math.ceil(center + spread * 1.5)
  const step = Math.max((hi - lo) / 150, 1)

  const pts: PayoffPoint[] = []
  for (let s = lo; s <= hi; s += step) {
    const exp = legs.reduce((sum, l) => sum + legPnl(l, s, 'expiry'), 0)
    const thy = legs.reduce((sum, l) => sum + legPnl(l, s, 'theory'), 0)
    pts.push({
      price:      Math.round(s * 100) / 100,
      expiryPnl:  Math.round(exp * 100) / 100,
      theoryPnl:  Math.round(thy * 100) / 100,
      profitArea: exp >= 0 ? exp : 0,
      lossArea:   exp < 0  ? exp : 0,
    })
  }
  return pts
}

export function calcSummary(pts: PayoffPoint[]): PayoffSummary {
  const maxProfit = Math.max(...pts.map(p => p.expiryPnl))
  const maxLoss   = Math.min(...pts.map(p => p.expiryPnl))
  const breakevens: number[] = []
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1]
    if ((a.expiryPnl >= 0 && b.expiryPnl < 0) || (a.expiryPnl <= 0 && b.expiryPnl > 0)) {
      const r = Math.abs(a.expiryPnl) / (Math.abs(a.expiryPnl) + Math.abs(b.expiryPnl))
      breakevens.push(Math.round((a.price + r * (b.price - a.price)) * 100) / 100)
    }
  }
  return { maxProfit, maxLoss, breakevens }
}

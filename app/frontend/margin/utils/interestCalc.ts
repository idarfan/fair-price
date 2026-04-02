// Pure interest calculation functions for Tab 1 (immediate UI feedback).
// IMPORTANT: RATE_TIERS must stay in sync with
//   app/services/margin_interest_service.rb → RATE_TIERS
// Tab 2 numbers always come from server-computed fields in the API response.

import type { RateTier, ScheduleRow } from '../types'

export const RATE_TIERS: RateTier[] = [
  { min: 1_000_000, rate: 0.08 },
  { min:   500_000, rate: 0.086 },
  { min:   250_000, rate: 0.105 },
  { min:   100_000, rate: 0.1075 },
  { min:    25_000, rate: 0.1125 },
  { min:    10_000, rate: 0.1175 },
  { min:         0, rate: 0.12 },
]

export function getAnnualRate(balance: number): number {
  const tier = RATE_TIERS.find(t => balance >= t.min)
  return tier ? tier.rate : 0.12
}

export function calcMarginInterest(
  balance: number,
  annualRate: number,
  days: number
): number {
  return balance * annualRate * days / 360
}

export function calcNetProfit(
  buyPrice: number,
  sellPrice: number,
  shares: number,
  marginInterest: number
): number {
  return (sellPrice - buyPrice) * shares - marginInterest
}

export function calcBreakEven(
  buyPrice: number,
  shares: number,
  marginInterest: number
): number {
  if (shares <= 0) return 0
  return buyPrice + marginInterest / shares
}

// Builds interest charge schedule:
// Row 1: day 15 (periodDays=15), Row 2+: every 30 days
export function buildInterestSchedule(
  balance: number,
  annualRate: number,
  totalDays: number
): ScheduleRow[] {
  const rows: ScheduleRow[] = []
  let daysCounted = 0
  let cumulative = 0
  let chargeNumber = 1

  while (daysCounted < totalDays) {
    const periodDays = chargeNumber === 1 ? 15 : 30
    const remaining = totalDays - daysCounted
    const actualDays = Math.min(periodDays, remaining)
    const periodInterest = balance * annualRate * actualDays / 360

    daysCounted += actualDays
    cumulative += periodInterest

    rows.push({
      chargeNumber,
      dayOfCharge: daysCounted,
      periodDays: actualDays,
      periodInterest,
      cumulativeInterest: cumulative,
    })

    chargeNumber++
  }

  return rows
}

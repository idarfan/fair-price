// Margin Trade Calculator — TypeScript interfaces
// Mirrors app/models/margin_position.rb and app/services/margin_interest_service.rb

export interface RateTier {
  min: number
  rate: number
}

export interface ScheduleRow {
  chargeNumber: number
  dayOfCharge: number      // days from opened_on
  periodDays: number       // 15 for first charge, 30 thereafter
  periodInterest: number
  cumulativeInterest: number
}

// Tab 1 — calculator inputs (pure frontend, no DB)
export interface CalcInputs {
  ticker: string
  buyPrice: number | null
  shares: number | null
  sellPrice: number | null
  days: number
}

export interface CalcResults {
  balance: number
  annualRate: number
  marginInterest: number
  spreadProfit: number
  netProfit: number
  breakEven: number
  schedule: ScheduleRow[]
}

// Tab 2 — persisted position (matches API response shape)
export interface MarginPosition {
  id: number
  symbol: string
  buy_price: string        // decimal string from Rails
  shares: string
  sell_price: string | null
  opened_on: string        // ISO date "YYYY-MM-DD"
  closed_on: string | null
  status: 'open' | 'closed'
  // server-computed fields
  balance: number
  annual_rate: number
  days_held: number
  accrued_interest: number
  next_charge_date: string
  current_period_interest: number
}

export interface PriceLookupResult {
  symbol:          string
  company_name:    string
  price:           number
  day_low:         number | null
  day_high:        number | null
  week52_low:      number | null
  week52_high:     number | null
  fair_value_low:  number | null
  fair_value_high: number | null
  stock_type:      string | null
}

export interface AddPositionPayload {
  symbol: string
  buy_price: number
  shares: number
  sell_price: number | null
  opened_on: string        // ISO date "YYYY-MM-DD"
}

export type MarketOutlook = 'bullish' | 'bearish' | 'neutral' | 'volatile'
export type IvEnv = 'high_iv' | 'low_iv'
export type LegType =
  | 'long_call' | 'short_call'
  | 'long_put'  | 'short_put'
  | 'long_stock' | 'short_stock'

export interface PayoffLeg {
  type:     LegType
  strike:   number
  premium:  number
  quantity: number
  iv?:      number
  dte?:     number
}

export interface PayoffPoint {
  price:     number
  expiryPnl: number
  theoryPnl: number
  profitArea: number
  lossArea:   number
}

export interface PayoffSummary {
  maxProfit: number
  maxLoss:   number
  breakevens: number[]
}

export interface StrategyTemplate {
  key:       string
  name:      string
  desc:      string
  dte:       string
  delta:     string
  credit:    boolean
  maxProfit: string
  risk:      string
  defaultLegs: PayoffLeg[]
}

export interface OIPoint {
  strike:  number
  call_oi: number
  put_oi:  number
}

export interface SentimentData {
  symbol:             string
  price:              number
  pc_ratio:           number | null
  pc_ratio_sentiment: string
  call_volume:        number
  put_volume:         number
  iv_skew:            number | null
  otm_put_iv:         number | null
  otm_call_iv:        number | null
  skew_comment:       string
  oi_distribution:    OIPoint[]
}

export interface IvRankData {
  symbol:     string
  iv_rank:    number
  iv_comment: string
  peers: Array<{ symbol: string; iv: number; iv_rank: number }>
}

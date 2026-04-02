import { useState } from 'react'
import { PriceInput } from './PriceInput'
import { DaysSelector } from './DaysSelector'
import { ResultSummary } from './ResultSummary'
import { InterestScheduleTable } from './InterestScheduleTable'
import {
  getAnnualRate, calcMarginInterest, calcNetProfit, calcBreakEven, buildInterestSchedule,
} from '../utils/interestCalc'
import type { CalcResults } from '../types'

export function CalculatorTab() {
  const [ticker, setTicker] = useState('')
  const [buyPrice, setBuyPrice] = useState<number | null>(null)
  const [shares, setShares] = useState<number | null>(100)
  const [sellPrice, setSellPrice] = useState<number | null>(null)
  const [days, setDays] = useState(30)
  const [lookupLoading, setLookupLoading] = useState(false)
  const [lookupError, setLookupError] = useState<string | null>(null)

  const handlePriceLookup = async () => {
    if (!ticker) return
    setLookupLoading(true)
    setLookupError(null)
    try {
      const res = await fetch(
        `/api/v1/margin_positions/price_lookup?symbol=${encodeURIComponent(ticker)}`
      )
      const data = await res.json() as { price?: number; error?: string }
      if (!res.ok || !data.price) {
        setLookupError(data.error ?? `無法取得 ${ticker} 報價`)
      } else {
        setBuyPrice(data.price)
      }
    } catch {
      setLookupError('網路錯誤，請稍後再試')
    } finally {
      setLookupLoading(false)
    }
  }

  const results: CalcResults | null = (() => {
    if (!buyPrice || !shares || !sellPrice || buyPrice <= 0 || shares <= 0) return null

    const balance = buyPrice * shares
    const annualRate = getAnnualRate(balance)
    const marginInterest = calcMarginInterest(balance, annualRate, days)
    const spreadProfit = (sellPrice - buyPrice) * shares
    const netProfit = calcNetProfit(buyPrice, sellPrice, shares, marginInterest)
    const breakEven = calcBreakEven(buyPrice, shares, marginInterest)
    const schedule = buildInterestSchedule(balance, annualRate, days)

    return { balance, annualRate, marginInterest, spreadProfit, netProfit, breakEven, schedule }
  })()

  return (
    <div className="space-y-5">
      <PriceInput
        ticker={ticker}
        buyPrice={buyPrice}
        shares={shares}
        sellPrice={sellPrice}
        lookupLoading={lookupLoading}
        lookupError={lookupError}
        onTickerChange={setTicker}
        onBuyPriceChange={setBuyPrice}
        onSharesChange={setShares}
        onSellPriceChange={setSellPrice}
        onPriceLookup={handlePriceLookup}
      />
      <DaysSelector days={days} onDaysChange={setDays} />
      <hr className="border-gray-700" />
      <ResultSummary results={results} />
      {results && <InterestScheduleTable schedule={results.schedule} />}
    </div>
  )
}

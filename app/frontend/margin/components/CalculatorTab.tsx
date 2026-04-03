import { useState, useEffect, useRef } from 'react'
import { PriceInput } from './PriceInput'
import { PriceInfoBar } from './PriceInfoBar'
import { DaysSelector } from './DaysSelector'
import { ResultSummary } from './ResultSummary'
import { InterestScheduleTable } from './InterestScheduleTable'
import {
  getAnnualRate, calcMarginInterest, calcNetProfit, calcBreakEven, buildInterestSchedule,
} from '../utils/interestCalc'
import type { CalcResults, PriceLookupResult } from '../types'

export function CalculatorTab() {
  const [ticker, setTicker] = useState('')
  const [buyPrice, setBuyPrice] = useState<number | null>(null)
  const [shares, setShares] = useState<number | null>(100)
  const [sellPrice, setSellPrice] = useState<number | null>(null)
  const [days, setDays] = useState(30)
  const [customRate, setCustomRate] = useState<number | null>(null)
  const [priceInfo, setPriceInfo] = useState<PriceLookupResult | null>(null)
  const [lookupLoading, setLookupLoading] = useState(false)
  const [lookupError, setLookupError] = useState<string | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    setPriceInfo(null)
    setLookupError(null)

    if (!ticker) return

    if (debounceRef.current) clearTimeout(debounceRef.current)

    debounceRef.current = setTimeout(async () => {
      setLookupLoading(true)
      try {
        const res = await fetch(
          `/api/v1/margin_positions/price_lookup?symbol=${encodeURIComponent(ticker)}`
        )
        const data = await res.json() as PriceLookupResult & { error?: string }
        if (!res.ok || !data.price) {
          setLookupError(data.error ?? '找不到此代號')
          setPriceInfo(null)
        } else {
          setPriceInfo(data)
          setBuyPrice(data.price)
          setLookupError(null)
        }
      } catch {
        setLookupError('網路錯誤')
        setPriceInfo(null)
      } finally {
        setLookupLoading(false)
      }
    }, 600)

    return () => { if (debounceRef.current) clearTimeout(debounceRef.current) }
  }, [ticker])

  const results: CalcResults | null = (() => {
    if (!buyPrice || !shares || !sellPrice || buyPrice <= 0 || shares <= 0) return null
    const balance = buyPrice * shares
    const annualRate = customRate != null ? customRate / 100 : getAnnualRate(balance)
    const marginInterest = calcMarginInterest(balance, annualRate, days)
    const spreadProfit = (sellPrice - buyPrice) * shares
    const netProfit = calcNetProfit(buyPrice, sellPrice, shares, marginInterest)
    const breakEven = calcBreakEven(buyPrice, shares, marginInterest)
    const schedule = buildInterestSchedule(balance, annualRate, days)
    return { balance, annualRate, marginInterest, spreadProfit, netProfit, breakEven, schedule }
  })()

  return (
    <div className="space-y-5">
      <div>
        <PriceInput
          ticker={ticker}
          buyPrice={buyPrice}
          shares={shares}
          sellPrice={sellPrice}
          livePrice={priceInfo?.price ?? null}
          lookupLoading={lookupLoading}
          lookupError={lookupError}
          onTickerChange={setTicker}
          onBuyPriceChange={setBuyPrice}
          onSharesChange={setShares}
          onSellPriceChange={setSellPrice}
        />
        {priceInfo && <PriceInfoBar info={priceInfo} />}
      </div>
      <DaysSelector days={days} onDaysChange={setDays} customRate={customRate} onCustomRateChange={setCustomRate} />
      <hr className="border-gray-700" />
      <ResultSummary results={results} />
      {results && <InterestScheduleTable schedule={results.schedule} />}
    </div>
  )
}

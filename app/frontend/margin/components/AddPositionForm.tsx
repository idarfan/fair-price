import { useState, useEffect, useRef } from 'react'
import { todayISO, fmtUSD, parseFlexDate } from '../utils/format'
import { PriceInfoBar } from './PriceInfoBar'
import type { AddPositionPayload, PriceLookupResult } from '../types'

interface Props {
  onSubmit: (payload: AddPositionPayload) => Promise<void>
}

const API_LOOKUP = '/api/v1/margin_positions/price_lookup'

export function AddPositionForm({ onSubmit }: Props) {
  const [symbol, setSymbol] = useState('')
  const [buyPrice, setBuyPrice] = useState('')
  const [shares, setShares] = useState('')
  const [sellPrice, setSellPrice] = useState('')
  const [openedOnText, setOpenedOnText] = useState(todayISO())
  const [openedOn, setOpenedOn] = useState(todayISO())
  const [loading, setLoading] = useState(false)
  const [priceInfo, setPriceInfo] = useState<PriceLookupResult | null>(null)
  const [lookupLoading, setLookupLoading] = useState(false)
  const [lookupError, setLookupError] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Auto-fetch price on symbol change (600ms debounce, same as Tab 1)
  useEffect(() => {
    setPriceInfo(null)
    setLookupError(null)

    if (!symbol) return

    if (debounceRef.current) clearTimeout(debounceRef.current)

    debounceRef.current = setTimeout(async () => {
      setLookupLoading(true)
      try {
        const res = await fetch(`${API_LOOKUP}?symbol=${encodeURIComponent(symbol)}`)
        const data = await res.json() as PriceLookupResult & { error?: string }
        if (!res.ok || !data.price) {
          setLookupError(data.error ?? '找不到此代號')
          setPriceInfo(null)
        } else {
          setPriceInfo(data)
          setBuyPrice(data.price.toFixed(2))
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
  }, [symbol])

  const handleSubmit = async (e: React.SyntheticEvent<HTMLFormElement>) => {
    e.preventDefault()
    setError(null)

    const bp = parseFloat(buyPrice)
    const sh = parseFloat(shares)
    if (!symbol || isNaN(bp) || bp <= 0 || isNaN(sh) || sh <= 0) {
      setError('請填入股票代號、建倉價與股數')
      return
    }

    const sp = sellPrice ? parseFloat(sellPrice) : null
    if (sp !== null && sp <= 0) {
      setError('平倉價必須大於 0')
      return
    }

    setLoading(true)
    await onSubmit({
      symbol: symbol.toUpperCase(),
      buy_price: bp,
      shares: sh,
      sell_price: sp,
      opened_on: openedOn,
    })
    setLoading(false)

    setSymbol('')
    setBuyPrice('')
    setShares('')
    setSellPrice('')
    setOpenedOn(todayISO())
    setOpenedOnText(todayISO())
    setPriceInfo(null)
  }

  const inputClass =
    'bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm ' +
    'placeholder-gray-500 focus:outline-none focus:border-blue-500'

  return (
    <form onSubmit={handleSubmit} className="bg-gray-800 rounded-xl p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-200">新增融資持倉</h3>
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="grid grid-cols-2 gap-2">
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="text-xs text-gray-400">股票代號</label>
            {lookupLoading && (
              <span className="text-xs text-gray-500 animate-pulse">查詢中…</span>
            )}
            {!lookupLoading && priceInfo !== null && (
              <span className="text-xs font-semibold text-green-400">
                現價 {fmtUSD(priceInfo.price)}
              </span>
            )}
            {!lookupLoading && lookupError && (
              <span className="text-xs text-red-400">{lookupError}</span>
            )}
          </div>
          <input
            type="text"
            value={symbol}
            onChange={e => setSymbol(e.target.value.toUpperCase())}
            placeholder="TQQQ"
            maxLength={10}
            className={`${inputClass} w-full uppercase`}
          />
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="text-xs text-gray-400">建倉日期</label>
            {openedOnText && !parseFlexDate(openedOnText) && openedOnText !== todayISO() && (
              <span className="text-xs text-red-400">格式錯誤</span>
            )}
          </div>
          <input
            type="text"
            value={openedOnText}
            placeholder="20260401"
            maxLength={10}
            onChange={e => {
              setOpenedOnText(e.target.value)
              const parsed = parseFlexDate(e.target.value)
              if (parsed) setOpenedOn(parsed)
            }}
            className={`${inputClass} w-full`}
          />
        </div>
        <div>
          <label className="block text-xs text-gray-400 mb-1">建倉價 ($)</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={buyPrice}
            onChange={e => setBuyPrice(e.target.value)}
            placeholder="0.00"
            className={`${inputClass} w-full`}
          />
        </div>
        <div>
          <label className="block text-xs text-gray-400 mb-1">股數</label>
          <input
            type="number"
            min="1"
            step="1"
            value={shares}
            onChange={e => setShares(e.target.value)}
            placeholder="100"
            className={`${inputClass} w-full`}
          />
        </div>
        <div>
          <label className="block text-xs text-gray-400 mb-1">平倉價 ($)（選填）</label>
          <input
            type="number"
            min="0"
            step="0.01"
            value={sellPrice}
            onChange={e => setSellPrice(e.target.value)}
            placeholder="0.00"
            className={`${inputClass} w-full`}
          />
        </div>
      </div>
      {priceInfo && <PriceInfoBar info={priceInfo} />}
      <button
        type="submit"
        disabled={loading}
        className="w-full py-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-50
                   rounded-lg text-sm font-medium text-white"
      >
        {loading ? '新增中…' : '新增持倉'}
      </button>
    </form>
  )
}

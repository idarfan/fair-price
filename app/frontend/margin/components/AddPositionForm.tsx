import { useState } from 'react'
import { todayISO } from '../utils/format'
import type { AddPositionPayload } from '../types'

interface Props {
  onSubmit: (payload: AddPositionPayload) => Promise<void>
  onPriceLookup: (symbol: string) => Promise<number | null>
}

export function AddPositionForm({ onSubmit, onPriceLookup }: Props) {
  const [symbol, setSymbol] = useState('')
  const [buyPrice, setBuyPrice] = useState('')
  const [shares, setShares] = useState('')
  const [sellPrice, setSellPrice] = useState('')
  const [openedOn, setOpenedOn] = useState(todayISO())
  const [loading, setLoading] = useState(false)
  const [lookupLoading, setLookupLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleLookup = async () => {
    if (!symbol) return
    setLookupLoading(true)
    const price = await onPriceLookup(symbol)
    setLookupLoading(false)
    if (price !== null) setBuyPrice(price.toFixed(2))
  }

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

    // Reset form
    setSymbol('')
    setBuyPrice('')
    setShares('')
    setSellPrice('')
    setOpenedOn(todayISO())
  }

  const inputClass =
    'bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm ' +
    'placeholder-gray-500 focus:outline-none focus:border-blue-500'

  return (
    <form onSubmit={handleSubmit} className="bg-gray-800 rounded-xl p-4 space-y-3">
      <h3 className="text-sm font-semibold text-gray-200">新增融資持倉</h3>
      {error && (
        <p className="text-xs text-red-400">{error}</p>
      )}
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="block text-xs text-gray-400 mb-1">股票代號</label>
          <div className="flex gap-1">
            <input
              type="text"
              value={symbol}
              onChange={e => setSymbol(e.target.value.toUpperCase())}
              placeholder="TQQQ"
              maxLength={10}
              className={`${inputClass} flex-1 uppercase`}
            />
            <button
              type="button"
              onClick={handleLookup}
              disabled={lookupLoading || !symbol}
              className="px-2 py-1 text-xs bg-gray-700 hover:bg-gray-600 rounded-lg text-gray-300 disabled:opacity-50"
            >
              {lookupLoading ? '…' : '查價'}
            </button>
          </div>
        </div>
        <div>
          <label className="block text-xs text-gray-400 mb-1">建倉日期</label>
          <input
            type="date"
            value={openedOn}
            onChange={e => setOpenedOn(e.target.value)}
            className={inputClass + ' w-full'}
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

interface Props {
  ticker: string
  buyPrice: number | null
  shares: number | null
  sellPrice: number | null
  lookupLoading?: boolean
  lookupError?: string | null
  onTickerChange: (v: string) => void
  onBuyPriceChange: (v: number | null) => void
  onSharesChange: (v: number | null) => void
  onSellPriceChange: (v: number | null) => void
  onPriceLookup?: () => void
}

function numInput(
  value: number | null,
  onChange: (v: number | null) => void,
  placeholder: string,
  step = '0.01'
) {
  return (
    <input
      type="number"
      min="0"
      step={step}
      value={value ?? ''}
      placeholder={placeholder}
      onChange={e => {
        const v = e.target.value
        onChange(v === '' ? null : parseFloat(v))
      }}
      className="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm
                 placeholder-gray-500 focus:outline-none focus:border-blue-500"
    />
  )
}

export function PriceInput({
  ticker, buyPrice, shares, sellPrice,
  lookupLoading = false, lookupError = null,
  onTickerChange, onBuyPriceChange, onSharesChange, onSellPriceChange,
  onPriceLookup,
}: Props) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <div>
        <label className="block text-xs text-gray-400 mb-1">股票代號</label>
        <div className="flex gap-1">
          <input
            type="text"
            value={ticker}
            placeholder="TQQQ"
            onChange={e => onTickerChange(e.target.value.toUpperCase())}
            onKeyDown={e => { if (e.key === 'Enter' && onPriceLookup) onPriceLookup() }}
            maxLength={10}
            className="flex-1 bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm
                       placeholder-gray-500 focus:outline-none focus:border-blue-500 uppercase"
          />
          {onPriceLookup && (
            <button
              type="button"
              onClick={onPriceLookup}
              disabled={lookupLoading || !ticker}
              className="px-2 py-1 text-xs bg-gray-700 hover:bg-gray-600 rounded-lg
                         text-gray-300 disabled:opacity-50 whitespace-nowrap"
            >
              {lookupLoading ? '…' : '查價'}
            </button>
          )}
        </div>
        {lookupError && (
          <p className="text-xs text-red-400 mt-1">{lookupError}</p>
        )}
      </div>
      <div>
        <label className="block text-xs text-gray-400 mb-1">股數</label>
        {numInput(shares, onSharesChange, '100', '1')}
      </div>
      <div>
        <label className="block text-xs text-gray-400 mb-1">建倉價 ($)</label>
        {numInput(buyPrice, onBuyPriceChange, '0.00')}
      </div>
      <div>
        <label className="block text-xs text-gray-400 mb-1">平倉價 ($)</label>
        {numInput(sellPrice, onSellPriceChange, '0.00')}
      </div>
    </div>
  )
}

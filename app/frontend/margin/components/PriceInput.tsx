interface Props {
  ticker: string
  buyPrice: number | null
  shares: number | null
  sellPrice: number | null
  onTickerChange: (v: string) => void
  onBuyPriceChange: (v: number | null) => void
  onSharesChange: (v: number | null) => void
  onSellPriceChange: (v: number | null) => void
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
  onTickerChange, onBuyPriceChange, onSharesChange, onSellPriceChange,
}: Props) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <div>
        <label className="block text-xs text-gray-400 mb-1">股票代號</label>
        <input
          type="text"
          value={ticker}
          placeholder="TQQQ"
          onChange={e => onTickerChange(e.target.value.toUpperCase())}
          maxLength={10}
          className="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm
                     placeholder-gray-500 focus:outline-none focus:border-blue-500 uppercase"
        />
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

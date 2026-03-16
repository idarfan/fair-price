import React, { useState } from 'react'

interface Props {
  symbols:  string[]
  selected: string | null
  loading:  boolean
  onFetch:  (symbol: string) => void
}

function StockLogo({ symbol }: { symbol: string }) {
  const [src, setSrc] = useState(
    `https://assets.parqet.com/logos/symbol/${symbol}?format=jpg`
  )
  const [failed, setFailed] = useState(false)

  function handleError() {
    if (!src.includes('finnhub')) {
      setSrc(`https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/${symbol}.png`)
    } else {
      setFailed(true)
    }
  }

  if (failed) {
    return (
      <span
        className="w-7 h-7 rounded-full bg-gray-600 text-white font-bold flex items-center justify-center flex-shrink-0"
        style={{ fontSize: '8px' }}
      >
        {symbol.slice(0, 2)}
      </span>
    )
  }

  return (
    <img
      src={src}
      alt={symbol}
      onError={handleError}
      className="w-7 h-7 rounded-full object-contain border border-gray-600 bg-white flex-shrink-0"
    />
  )
}

export default function SymbolList({ symbols, selected, loading, onFetch }: Props) {
  if (symbols.length === 0) {
    return (
      <div className="p-4 text-gray-400 text-xs">
        Watchlist 無股票，請先至 Watchlist 頁面新增。
      </div>
    )
  }

  return (
    <ul className="divide-y divide-gray-700">
      {symbols.map(sym => {
        const isActive   = sym === selected
        const isFetching = isActive && loading

        return (
          <li key={sym}>
            <button
              onClick={() => onFetch(sym)}
              disabled={isFetching}
              className={[
                'w-full text-left px-3 py-2.5 flex items-center gap-2.5 transition-colors',
                isActive   ? 'bg-blue-600 text-white' : 'text-gray-200 hover:bg-gray-700',
                isFetching ? 'opacity-70' : '',
              ].join(' ')}
            >
              <StockLogo symbol={sym} />
              <span className="font-mono text-sm flex-1">{sym}</span>
              {isFetching && (
                <span className="text-xs text-blue-200 flex-shrink-0">抓取中…</span>
              )}
            </button>
          </li>
        )
      })}
    </ul>
  )
}

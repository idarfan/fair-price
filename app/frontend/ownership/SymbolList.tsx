import React from 'react'

interface Props {
  symbols:  string[]
  selected: string | null
  onSelect: (symbol: string) => void
}

export default function SymbolList({ symbols, selected, onSelect }: Props) {
  if (symbols.length === 0) {
    return (
      <div className="p-4 text-gray-400 text-sm">
        Watchlist 無股票，請先至 Watchlist 頁面新增。
      </div>
    )
  }

  return (
    <ul className="divide-y divide-gray-700">
      {symbols.map(sym => (
        <li key={sym}>
          <button
            onClick={() => onSelect(sym)}
            className={[
              'w-full text-left px-4 py-3 text-sm font-mono transition-colors',
              sym === selected
                ? 'bg-blue-600 text-white font-semibold'
                : 'text-gray-200 hover:bg-gray-700',
            ].join(' ')}
          >
            {sym}
          </button>
        </li>
      ))}
    </ul>
  )
}

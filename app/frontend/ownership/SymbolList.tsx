import StockLogo from '../components/StockLogo'

interface Props {
  symbols:  string[]
  selected: string | null
  loading:  boolean
  onFetch:  (symbol: string) => void
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

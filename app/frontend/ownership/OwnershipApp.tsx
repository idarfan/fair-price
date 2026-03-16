import React, { useCallback, useEffect, useState } from 'react'
import SymbolList from './SymbolList'
import OwnershipPanel from './OwnershipPanel'
import type { Snapshot } from './types'

interface Props {
  symbols: string[]
}

export default function OwnershipApp({ symbols }: Props) {
  const [selected,  setSelected]  = useState<string | null>(symbols[0] ?? null)
  const [snapshots, setSnapshots] = useState<Snapshot[]>([])
  const [loading,   setLoading]   = useState(false)
  const [error,     setError]     = useState<string | null>(null)

  const loadHistory = useCallback(async (sym: string) => {
    setLoading(true)
    setError(null)
    try {
      const res  = await fetch(`/ownership/history?symbol=${encodeURIComponent(sym)}`)
      const json = await res.json()
      setSnapshots(json.snapshots ?? [])
    } catch {
      setError('無法載入歷史資料')
      setSnapshots([])
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (selected) loadHistory(selected)
  }, [selected, loadHistory])

  function handleSelect(sym: string) {
    setSelected(sym)
    setSnapshots([])
  }

  return (
    <div className="flex h-full min-h-screen bg-gray-900 text-white">
      {/* 左側：Watchlist 清單 */}
      <aside className="w-36 shrink-0 border-r border-gray-700 overflow-y-auto">
        <div className="px-4 py-3 text-xs text-gray-400 font-semibold uppercase tracking-wider border-b border-gray-700">
          Watchlist
        </div>
        <SymbolList
          symbols={symbols}
          selected={selected}
          onSelect={handleSelect}
        />
      </aside>

      {/* 右側：圖表面板 */}
      <main className="flex-1 overflow-y-auto">
        {!selected ? (
          <div className="flex items-center justify-center h-full text-gray-400 text-sm">
            請從左側選擇股票
          </div>
        ) : loading ? (
          <div className="flex items-center justify-center h-full text-gray-400 text-sm">
            載入中…
          </div>
        ) : error ? (
          <div className="flex items-center justify-center h-full text-red-400 text-sm">
            {error}
          </div>
        ) : (
          <OwnershipPanel
            symbol={selected}
            snapshots={snapshots}
            onRefresh={() => loadHistory(selected)}
          />
        )}
      </main>
    </div>
  )
}

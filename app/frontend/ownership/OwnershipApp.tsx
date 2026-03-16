import React, { useCallback, useEffect, useState } from 'react'
import SymbolList from './SymbolList'
import MetricCards from './components/MetricCards'
import TimeRangeSelector from './components/TimeRangeSelector'
import OwnershipTrendChart from './components/OwnershipTrendChart'
import HoldersTable from './components/HoldersTable'
import type { ApiSnapshot } from './types'
import type { RangeKey } from './components/TimeRangeSelector'

interface Props {
  symbols: string[]
}

export default function OwnershipApp({ symbols }: Props) {
  const [selected,   setSelected]   = useState<string | null>(symbols[0] ?? null)
  const [range,      setRange]      = useState<RangeKey>('90d')
  const [snapshots,  setSnapshots]  = useState<ApiSnapshot[]>([])
  const [previous,   setPrevious]   = useState<ApiSnapshot | null>(null)
  const [fetching,   setFetching]   = useState(false)
  const [error,      setError]      = useState<string | null>(null)

  const loadHistory = useCallback(async (sym: string, r: RangeKey) => {
    try {
      const res  = await fetch(`/api/v1/ownership_snapshots/${encodeURIComponent(sym)}?range=${r}`)
      const json = await res.json()
      setSnapshots(json.snapshots ?? [])
      setPrevious(json.previous ?? null)
      setError(null)
    } catch {
      setError('無法載入資料')
      setSnapshots([])
      setPrevious(null)
    }
  }, [])

  // 切換股票：只讀取現有歷史
  function handleSelect(sym: string) {
    if (sym === selected) return
    setSelected(sym)
    setSnapshots([])
    setPrevious(null)
    loadHistory(sym, range)
  }

  // 切換時間範圍
  function handleRangeChange(key: RangeKey) {
    setRange(key)
    if (selected) loadHistory(selected, key)
  }

  // 手動抓取快照（更新鍵）
  async function handleFetch() {
    if (!selected) return
    setFetching(true)
    setError(null)
    try {
      const res = await fetch(`/api/v1/ownership_snapshots/${encodeURIComponent(selected)}`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
      })
      if (!res.ok) {
        const json = await res.json().catch(() => ({}))
        setError(json.error || '抓取失敗')
      } else {
        await loadHistory(selected, range)
      }
    } catch {
      setError('網路錯誤，請稍後再試')
    } finally {
      setFetching(false)
    }
  }

  // 初次載入
  useEffect(() => {
    if (selected) loadHistory(selected, range)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const latest = snapshots.at(-1) ?? null

  return (
    <div className="flex h-full min-h-screen bg-gray-900 text-white">
      {/* 左側：股票清單（只切換，不抓取） */}
      <aside className="w-40 shrink-0 border-r border-gray-700 overflow-y-auto">
        <div className="px-4 py-3 text-xs text-gray-400 font-semibold uppercase tracking-wider border-b border-gray-700">
          Watchlist
        </div>
        <SymbolList
          symbols={symbols}
          selected={selected}
          loading={false}
          onFetch={handleSelect}
        />
      </aside>

      {/* 右側 */}
      <main className="flex-1 overflow-y-auto p-4">
        {!selected ? (
          <div className="flex items-center justify-center h-full text-gray-400 text-sm">
            請從左側選擇股票
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            {/* 標題 + 更新按鈕 */}
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold text-white font-mono">{selected} 持股結構</h2>
              <button
                onClick={handleFetch}
                disabled={fetching}
                className="px-3 py-1.5 text-xs rounded bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-medium transition-colors"
              >
                {fetching ? '更新中…' : '更新快照'}
              </button>
            </div>

            {error && (
              <div className="text-xs text-red-400 bg-red-900/30 rounded px-3 py-2">{error}</div>
            )}

            {snapshots.length === 0 && !fetching ? (
              <div className="text-sm text-gray-400 py-8 text-center">
                尚無快照資料，點擊「更新快照」開始抓取。
              </div>
            ) : (
              <>
                {/* Metric Cards */}
                <MetricCards latest={latest} previous={previous} />

                {/* 時間範圍 + 趨勢圖 */}
                <div className="bg-gray-800 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-4">
                    <p className="text-xs text-gray-400">歷史趨勢（共 {snapshots.length} 筆）</p>
                    <TimeRangeSelector range={range} onRangeChange={handleRangeChange} />
                  </div>
                  <OwnershipTrendChart snapshots={snapshots} range={range} />
                </div>

                {/* 機構持有人表格 */}
                <div className="bg-gray-800 rounded-lg p-4">
                  <p className="text-xs text-gray-400 mb-3">
                    主要機構持有人
                    {latest && <span className="ml-2 text-gray-500">（{latest.date}）</span>}
                  </p>
                  <HoldersTable latest={latest} previous={previous} />
                </div>
              </>
            )}
          </div>
        )}
      </main>
    </div>
  )
}

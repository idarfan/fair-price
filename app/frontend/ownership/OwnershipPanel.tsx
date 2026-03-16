import React, { useState } from 'react'
import OwnershipChart from './OwnershipChart'
import type { Snapshot } from './types'

interface Props {
  symbol:    string
  snapshots: Snapshot[]
  onRefresh: () => void
}

function fmtPct(val: number | null) {
  if (val == null) return '—'
  return `${val.toFixed(2)}%`
}

function fmtLarge(val: number | null) {
  if (val == null) return '—'
  if (val >= 1_000_000_000) return `$${(val / 1_000_000_000).toFixed(1)}B`
  if (val >= 1_000_000)     return `$${(val / 1_000_000).toFixed(0)}M`
  return val.toLocaleString()
}

export default function OwnershipPanel({ symbol, snapshots, onRefresh }: Props) {
  const [fetching, setFetching] = useState(false)
  const [error, setError]       = useState<string | null>(null)

  const latest = snapshots.at(-1) ?? null

  async function handleFetch() {
    setFetching(true)
    setError(null)
    try {
      const res = await fetch('/ownership/fetch', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        body:    JSON.stringify({ symbol }),
      })
      const json = await res.json()
      if (!res.ok) {
        setError(json.error || '抓取失敗')
      } else {
        onRefresh()
      }
    } catch {
      setError('網路錯誤，請稍後再試')
    } finally {
      setFetching(false)
    }
  }

  return (
    <div className="flex flex-col gap-4 p-4 min-h-0 overflow-y-auto">
      {/* 標題列 */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-white font-mono">{symbol} 持股結構</h2>
        <button
          onClick={handleFetch}
          disabled={fetching}
          className="px-3 py-1.5 text-xs rounded bg-blue-600 hover:bg-blue-500 disabled:opacity-50
                     text-white font-medium transition-colors"
        >
          {fetching ? '抓取中…' : '抓取快照'}
        </button>
      </div>

      {error && (
        <div className="text-xs text-red-400 bg-red-900/30 rounded px-3 py-2">{error}</div>
      )}

      {/* 摘要卡片 */}
      <div className="grid grid-cols-3 gap-3">
        <StatCard label="機構持股" value={fmtPct(latest?.institutions_pct ?? null)} />
        <StatCard label="內部人持股" value={fmtPct(latest?.insiders_pct ?? null)} />
        <StatCard label="機構數量" value={latest?.institutions_count?.toLocaleString() ?? '—'} />
      </div>

      {/* 折線圖 */}
      <div className="bg-gray-800 rounded-lg p-4">
        <p className="text-xs text-gray-400 mb-3">
          歷史趨勢（共 {snapshots.length} 筆快照）
          {latest?.source && <span className="ml-2 text-gray-500">來源：{latest.source}</span>}
        </p>
        <OwnershipChart snapshots={snapshots} />
      </div>

      {/* 主要機構持有人表格 */}
      {latest && latest.top_holders.length > 0 && (
        <div className="bg-gray-800 rounded-lg p-4">
          <p className="text-xs text-gray-400 mb-3">
            主要機構持有人（最新快照：{latest.fetched_at.slice(0, 10)}）
          </p>
          <table className="w-full text-xs">
            <thead>
              <tr className="text-gray-400 border-b border-gray-700">
                <th className="text-left pb-2">機構名稱</th>
                <th className="text-right pb-2">持股%</th>
                <th className="text-right pb-2">市值</th>
                <th className="text-right pb-2">申報日</th>
              </tr>
            </thead>
            <tbody>
              {latest.top_holders.map((h, i) => (
                <tr key={i} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="py-1.5 text-gray-200">{h.name}</td>
                  <td className="py-1.5 text-right text-blue-300">{fmtPct(h.pct_held)}</td>
                  <td className="py-1.5 text-right text-gray-300">{fmtLarge(h.value)}</td>
                  <td className="py-1.5 text-right text-gray-400">{h.report_date ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-gray-800 rounded-lg px-4 py-3">
      <p className="text-xs text-gray-400">{label}</p>
      <p className="text-lg font-semibold text-white mt-1">{value}</p>
    </div>
  )
}

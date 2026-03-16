import React from 'react'
import type { Holder, ApiSnapshot } from '../types'
import { fmtPct, fmtLarge } from '../utils/format'

interface Props {
  latest:   ApiSnapshot | null
  previous: ApiSnapshot | null
}

interface HolderRow extends Holder {
  delta:  number | null   // 季度變化（優先用 API pct_change，退用 DB delta）
  isNew:  boolean
}

function buildRows(holders: Holder[], prevSnap: ApiSnapshot | null): HolderRow[] {
  return holders.map(h => {
    // 優先使用 Yahoo Finance 提供的 pct_change（vs 上季股份增減比例）
    if (h.pct_change != null) {
      return { ...h, delta: h.pct_change, isNew: false }
    }
    // 退用 DB 前一筆快照計算
    const prev = prevSnap?.holders.find(p => p.name === h.name)
    if (!prev) return { ...h, delta: null, isNew: !!prevSnap }
    return { ...h, delta: (h.pct ?? 0) - (prev.pct ?? 0), isNew: false }
  })
}

function findExited(holders: Holder[], prevSnap: ApiSnapshot | null): Holder[] {
  if (!prevSnap) return []
  const currentNames = new Set(holders.map(h => h.name))
  return prevSnap.holders.filter(h => !currentNames.has(h.name))
}

function DeltaCell({ row }: { row: HolderRow }) {
  if (row.delta == null) {
    return <td className="py-1.5 text-right text-gray-500">—</td>
  }
  const isPositive = row.delta > 0
  const isNegative = row.delta < 0
  const colorCls   = isPositive ? 'text-green-400' : isNegative ? 'text-red-400' : 'text-gray-400'
  const sign       = isPositive ? '+' : ''
  // pct_change 來自 API（0.019 = 1.9%），是股份數量的相對變化
  const display = `${sign}${Math.abs(row.delta).toFixed(2)}%`

  return <td className={`py-1.5 text-right ${colorCls}`}>{display}</td>
}

export default function HoldersTable({ latest, previous }: Props) {
  if (!latest || latest.holders.length === 0) {
    return (
      <div className="text-xs text-gray-400 py-4 text-center">
        尚無機構持有人資料
      </div>
    )
  }

  const rows   = buildRows(latest.holders, previous ?? null)
  const exited = findExited(latest.holders, previous ?? null)

  return (
    <div>
      <table className="w-full text-xs">
        <thead>
          <tr className="text-gray-400 border-b border-gray-700">
            <th className="text-left pb-2">機構名稱</th>
            <th className="text-right pb-2">持股%</th>
            <th className="text-right pb-2">季度變化</th>
            <th className="text-right pb-2">市值</th>
            <th className="text-right pb-2">申報日</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((h, i) => (
            <tr key={i} className="border-b border-gray-700/50 hover:bg-gray-700/30">
              <td className="py-1.5 text-gray-200">
                {h.name}
                {h.isNew && (
                  <span className="ml-2 px-1 py-0.5 bg-blue-700 text-blue-100 text-[10px] rounded font-medium">
                    NEW
                  </span>
                )}
              </td>
              <td className="py-1.5 text-right text-blue-300">{fmtPct(h.pct)}</td>
              <DeltaCell row={h} />
              <td className="py-1.5 text-right text-gray-300">{fmtLarge(h.value)}</td>
              <td className="py-1.5 text-right text-gray-400">{h.filing_date ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {exited.length > 0 && (
        <div className="mt-4">
          <p className="text-xs text-gray-500 mb-2">已退出機構</p>
          <table className="w-full text-xs opacity-60">
            <tbody>
              {exited.map((h, i) => (
                <tr key={i} className="border-b border-gray-700/30">
                  <td className="py-1 text-gray-400 line-through">{h.name}</td>
                  <td className="py-1 text-right text-gray-500">{fmtPct(h.pct)}</td>
                  <td className="py-1 text-right text-red-500">退出</td>
                  <td className="py-1 text-right text-gray-500">{fmtLarge(h.value)}</td>
                  <td className="py-1 text-right text-gray-500">{h.filing_date ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

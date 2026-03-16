import React from 'react'
import type { ApiSnapshot } from '../types'
import { fmtPct, fmtDelta, fmtCount } from '../utils/format'

interface Props {
  latest:   ApiSnapshot | null
  previous: ApiSnapshot | null
}

interface CardProps {
  label:    string
  value:    string
  delta:    number | null
  isCount?: boolean
}

function MetricCard({ label, value, delta, isCount = false }: CardProps) {
  const hasData  = delta != null
  const positive = hasData && delta! > 0
  const negative = hasData && delta! < 0

  const deltaText = isCount
    ? (hasData ? `${delta! > 0 ? '+' : ''}${delta} vs 上季` : '—')
    : (hasData ? `${fmtDelta(delta)} vs 上季` : '—')

  return (
    <div className="bg-gray-800 rounded-lg px-4 py-3">
      <p className="text-xs text-gray-400">{label}</p>
      <p className="text-lg font-semibold text-white mt-1">{value}</p>
      <p className={[
        'text-xs mt-1',
        positive ? 'text-green-400' : negative ? 'text-red-400' : 'text-gray-500',
      ].join(' ')}>
        {deltaText}
      </p>
    </div>
  )
}

export default function MetricCards({ latest, previous }: Props) {
  const instDelta = (latest && previous)
    ? (latest.institutional_pct ?? 0) - (previous.institutional_pct ?? 0)
    : null

  const insidDelta = (latest && previous)
    ? (latest.insider_pct ?? 0) - (previous.insider_pct ?? 0)
    : null

  const countDelta = (latest && previous)
    ? (latest.institution_count ?? 0) - (previous.institution_count ?? 0)
    : null

  return (
    <div className="grid grid-cols-3 gap-3">
      <MetricCard
        label="機構持股"
        value={fmtPct(latest?.institutional_pct)}
        delta={instDelta}
      />
      <MetricCard
        label="內部人持股"
        value={fmtPct(latest?.insider_pct)}
        delta={insidDelta}
      />
      <MetricCard
        label="機構數量"
        value={fmtCount(latest?.institution_count)}
        delta={countDelta}
        isCount
      />
    </div>
  )
}

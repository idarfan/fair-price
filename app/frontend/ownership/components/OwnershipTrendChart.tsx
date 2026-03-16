import React from 'react'
import {
  ComposedChart, Area, XAxis, YAxis, Tooltip,
  ResponsiveContainer, TooltipProps,
} from 'recharts'
import type { ApiSnapshot } from '../types'
import type { RangeKey } from './TimeRangeSelector'

interface Props {
  snapshots: ApiSnapshot[]
  range:     RangeKey
}

interface ChartPoint {
  label:         string
  institutional: number | null
  insider:       number | null
  prevInst:      number | null
  prevInsider:   number | null
}

function xLabel(snapshot: ApiSnapshot, range: RangeKey): string {
  if (range === '90d') {
    const d = new Date(snapshot.date)
    return `${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`
  }
  return snapshot.quarter
}

function buildChartData(snapshots: ApiSnapshot[], range: RangeKey): ChartPoint[] {
  return snapshots.map((s, i) => {
    const prev = i > 0 ? snapshots[i - 1] : null
    return {
      label:         xLabel(s, range),
      institutional: s.institutional_pct,
      insider:       s.insider_pct,
      prevInst:      prev?.institutional_pct ?? null,
      prevInsider:   prev?.insider_pct ?? null,
    }
  })
}

function CustomTooltip({ active, payload, label }: TooltipProps<number, string>) {
  if (!active || !payload?.length) return null

  const instEntry    = payload.find(p => p.dataKey === 'institutional')
  const insiderEntry = payload.find(p => p.dataKey === 'insider')

  function deltaStr(current: number | undefined, prev: number | null | undefined) {
    if (current == null || prev == null) return ''
    const d = current - prev
    const sign = d >= 0 ? '+' : ''
    return ` (${sign}${d.toFixed(2)}%)`
  }

  const instVal    = instEntry?.value   as number | undefined
  const insiderVal = insiderEntry?.value as number | undefined
  const instPrev   = instEntry?.payload?.prevInst   as number | null | undefined
  const insiderPrev = instEntry?.payload?.prevInsider as number | null | undefined

  return (
    <div className="bg-gray-800 border border-gray-600 rounded px-3 py-2 text-xs">
      <p className="text-gray-300 mb-1 font-medium">{label}</p>
      {instVal != null && (
        <p className="text-blue-300">
          機構持股：{instVal.toFixed(2)}%{deltaStr(instVal, instPrev)}
        </p>
      )}
      {insiderVal != null && (
        <p className="text-amber-300">
          內部人持股：{insiderVal.toFixed(2)}%{deltaStr(insiderVal, insiderPrev)}
        </p>
      )}
    </div>
  )
}

export default function OwnershipTrendChart({ snapshots, range }: Props) {
  if (snapshots.length <= 1) {
    return (
      <div className="flex items-center justify-center h-48 text-gray-400 text-sm text-center px-4">
        目前僅有一筆快照，累積更多資料後將顯示趨勢圖
      </div>
    )
  }

  const data = buildChartData(snapshots, range)

  return (
    <div>
      {/* 自建 legend */}
      <div className="flex gap-4 mb-3 text-xs text-gray-400">
        <span className="flex items-center gap-1">
          <span className="w-3 h-0.5 bg-blue-400 inline-block" />
          機構持股
        </span>
        <span className="flex items-center gap-1">
          <span className="w-3 h-0.5 bg-amber-400 inline-block" />
          內部人持股
        </span>
      </div>

      <ResponsiveContainer width="100%" height={260}>
        <ComposedChart data={data} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
          <XAxis
            dataKey="label"
            tick={{ fill: '#9ca3af', fontSize: 11 }}
            tickLine={false}
          />
          <YAxis
            tickFormatter={v => `${v}%`}
            tick={{ fill: '#9ca3af', fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            width={48}
          />
          <Tooltip content={<CustomTooltip />} />
          <Area
            type="monotone"
            dataKey="institutional"
            name="機構持股"
            fill="rgba(55,138,221,0.08)"
            stroke="#378ADD"
            strokeWidth={2}
            dot={{ r: 3, fill: '#378ADD' }}
            activeDot={{ r: 5 }}
            connectNulls
          />
          <Area
            type="monotone"
            dataKey="insider"
            name="內部人持股"
            fill="rgba(239,159,39,0.08)"
            stroke="#EF9F27"
            strokeWidth={2}
            dot={{ r: 3, fill: '#EF9F27' }}
            activeDot={{ r: 5 }}
            connectNulls
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}

import React from 'react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ResponsiveContainer,
} from 'recharts'
import type { Snapshot } from './types'

interface Props {
  snapshots: Snapshot[]
}

function fmtDate(iso: string) {
  return iso.slice(0, 10)
}

function fmtPct(val: number | null) {
  if (val == null) return '—'
  return `${val.toFixed(2)}%`
}

export default function OwnershipChart({ snapshots }: Props) {
  if (snapshots.length === 0) {
    return (
      <div className="flex items-center justify-center h-48 text-gray-400 text-sm">
        尚無快照資料，請點擊「抓取快照」開始記錄。
      </div>
    )
  }

  const data = snapshots.map(s => ({
    date:             fmtDate(s.fetched_at),
    institutions_pct: s.institutions_pct,
    insiders_pct:     s.insiders_pct,
  }))

  return (
    <ResponsiveContainer width="100%" height={260}>
      <LineChart data={data} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis
          dataKey="date"
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
        <Tooltip
          contentStyle={{ background: '#1f2937', border: '1px solid #374151', borderRadius: 6 }}
          labelStyle={{ color: '#e5e7eb', marginBottom: 4 }}
          formatter={(value: number | null, name: string) => [
            fmtPct(value),
            name === 'institutions_pct' ? '機構持股' : '內部人持股',
          ]}
        />
        <Legend
          formatter={name => name === 'institutions_pct' ? '機構持股' : '內部人持股'}
          wrapperStyle={{ color: '#d1d5db', fontSize: 12 }}
        />
        <Line
          type="monotone"
          dataKey="institutions_pct"
          name="institutions_pct"
          stroke="#3b82f6"
          strokeWidth={2}
          dot={{ r: 3, fill: '#3b82f6' }}
          activeDot={{ r: 5 }}
          connectNulls
        />
        <Line
          type="monotone"
          dataKey="insiders_pct"
          name="insiders_pct"
          stroke="#f59e0b"
          strokeWidth={2}
          dot={{ r: 3, fill: '#f59e0b' }}
          activeDot={{ r: 5 }}
          connectNulls
        />
      </LineChart>
    </ResponsiveContainer>
  )
}

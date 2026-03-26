import React from 'react'
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ReferenceLine, ResponsiveContainer, Legend
} from 'recharts'
import type { PayoffPoint, PayoffSummary } from '../types'

interface Props {
  data:    PayoffPoint[]
  summary: PayoffSummary | null
  price:   number
}

function SummaryRow({ summary }: { summary: PayoffSummary }) {
  const fmt = (n: number) =>
    n === Infinity || n > 999999 ? '∞'
    : n === -Infinity || n < -999999 ? '−∞'
    : `$${Math.abs(n).toFixed(0)}`

  return (
    <div className="flex gap-4 text-xs flex-wrap">
      <span className="text-green-600">
        最大獲利：<strong>{fmt(summary.maxProfit)}</strong>
      </span>
      <span className="text-red-500">
        最大虧損：<strong>{fmt(summary.maxLoss)}</strong>
      </span>
      {summary.breakevens.length > 0 && (
        <span className="text-gray-500">
          損益兩平：<strong>{summary.breakevens.map(b => `$${b}`).join(' / ')}</strong>
        </span>
      )}
    </div>
  )
}

const CustomTooltip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-2 shadow text-xs">
      <p className="font-semibold text-gray-700 mb-1">價格 ${(label as number).toFixed(1)}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} style={{ color: p.color }}>
          {p.name}：${(p.value as number).toFixed(2)}
        </p>
      ))}
    </div>
  )
}

export default function PayoffChart({ data, summary, price }: Props) {
  if (!data.length) {
    return (
      <div className="flex items-center justify-center h-48 text-sm text-gray-400">
        選擇策略後顯示損益圖
      </div>
    )
  }

  const maxAbs = Math.max(...data.map(d => Math.max(Math.abs(d.expiryPnl), Math.abs(d.theoryPnl))))
  const yDomain: [number, number] = [-maxAbs * 1.1, maxAbs * 1.1]

  return (
    <div className="flex flex-col gap-3">
      {summary && <SummaryRow summary={summary} />}
      <div style={{ width: '100%', height: 220 }}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: 8 }}>
          <defs>
            <linearGradient id="profitGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor="#22c55e" stopOpacity={0.3} />
              <stop offset="95%" stopColor="#22c55e" stopOpacity={0}   />
            </linearGradient>
            <linearGradient id="lossGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor="#ef4444" stopOpacity={0}   />
              <stop offset="95%" stopColor="#ef4444" stopOpacity={0.3} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
          <XAxis
            dataKey="price"
            tick={{ fontSize: 10 }}
            tickFormatter={(v: number) => `$${v.toFixed(0)}`}
            interval="preserveStartEnd"
          />
          <YAxis
            domain={yDomain}
            tick={{ fontSize: 10 }}
            tickFormatter={(v: number) => `$${v.toFixed(0)}`}
            width={52}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend
            wrapperStyle={{ fontSize: 11 }}
            formatter={(value: string) =>
              value === 'expiryPnl' ? '到期損益' : '理論現值'
            }
          />
          <ReferenceLine y={0}     stroke="#94a3b8" strokeWidth={1.5} />
          <ReferenceLine x={price} stroke="#6366f1" strokeDasharray="4 3" strokeWidth={1.5}
            label={{ value: '現價', position: 'insideTopRight', fontSize: 10, fill: '#6366f1' }}
          />
          <Area
            type="monotone"
            dataKey="profitArea"
            fill="url(#profitGrad)"
            stroke="none"
            legendType="none"
          />
          <Area
            type="monotone"
            dataKey="lossArea"
            fill="url(#lossGrad)"
            stroke="none"
            legendType="none"
          />
          <Area
            type="monotone"
            dataKey="expiryPnl"
            stroke="#1d4ed8"
            strokeWidth={2}
            fill="none"
            dot={false}
            activeDot={{ r: 4 }}
            name="expiryPnl"
          />
          <Area
            type="monotone"
            dataKey="theoryPnl"
            stroke="#f59e0b"
            strokeWidth={1.5}
            strokeDasharray="5 3"
            fill="none"
            dot={false}
            activeDot={{ r: 3 }}
            name="theoryPnl"
          />
        </AreaChart>
      </ResponsiveContainer>
      </div>
    </div>
  )
}

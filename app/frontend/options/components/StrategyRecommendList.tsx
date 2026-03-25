import React from 'react'
import type { StrategyTemplate } from '../types'

interface Props {
  strategies:  StrategyTemplate[]
  selectedIdx: number
  onSelect:    (i: number) => void
}

export default function StrategyRecommendList({ strategies, selectedIdx, onSelect }: Props) {
  if (!strategies.length) {
    return <p className="text-sm text-gray-400 py-4 text-center">無推薦策略</p>
  }

  return (
    <div className="flex flex-col gap-2">
      {strategies.map((s, i) => (
        <button
          key={s.key}
          onClick={() => onSelect(i)}
          className="w-full text-left p-3 rounded-xl border-2 transition-all"
          style={{
            borderColor: i === selectedIdx ? '#3b82f6' : '#e5e7eb',
            background:  i === selectedIdx ? '#eff6ff' : '#f9fafb',
          }}
        >
          <div className="flex items-center justify-between mb-1">
            <span className="font-semibold text-sm text-gray-800">{s.name}</span>
            <span
              className="text-xs px-2 py-0.5 rounded-full font-medium"
              style={{
                background: s.credit ? '#dcfce7' : '#fef3c7',
                color:       s.credit ? '#166534' : '#92400e',
              }}
            >
              {s.credit ? 'Credit' : 'Debit'}
            </span>
          </div>
          <p className="text-xs text-gray-500 mb-2">{s.desc}</p>
          <div className="flex gap-3 text-xs">
            <span className="text-gray-400">DTE：<span className="text-gray-600">{s.dte}</span></span>
            <span className="text-gray-400">Delta：<span className="text-gray-600">{s.delta}</span></span>
          </div>
          <div className="flex gap-3 text-xs mt-1">
            <span className="text-green-600">獲利：{s.maxProfit}</span>
            <span className="text-red-500">風險：{s.risk}</span>
          </div>
        </button>
      ))}
    </div>
  )
}

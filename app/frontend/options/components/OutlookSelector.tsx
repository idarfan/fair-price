import React from 'react'
import type { MarketOutlook } from '../types'

interface Props {
  value:    MarketOutlook
  onChange: (v: MarketOutlook) => void
}

const OUTLOOKS: { key: MarketOutlook; label: string; color: string; bg: string }[] = [
  { key: 'bullish',  label: '看多',  color: '#16a34a', bg: '#dcfce7' },
  { key: 'bearish',  label: '看空',  color: '#dc2626', bg: '#fee2e2' },
  { key: 'neutral',  label: '中性',  color: '#7c3aed', bg: '#ede9fe' },
  { key: 'volatile', label: '大波動', color: '#d97706', bg: '#fef3c7' },
]

export default function OutlookSelector({ value, onChange }: Props) {
  return (
    <div>
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">市場方向</p>
      <div className="grid grid-cols-2 gap-2">
        {OUTLOOKS.map(o => (
          <button
            key={o.key}
            onClick={() => onChange(o.key)}
            className="py-2 px-3 rounded-lg border-2 text-sm font-medium transition-all"
            style={{
              borderColor: value === o.key ? o.color : '#e5e7eb',
              background:  value === o.key ? o.bg : '#fff',
              color:        value === o.key ? o.color : '#6b7280',
            }}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  )
}

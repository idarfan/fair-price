import React from 'react'

export type RangeKey = '1w' | '1m' | '90d'

const RANGES: { key: RangeKey; label: string }[] = [
  { key: '1w',  label: '週' },
  { key: '1m',  label: '月' },
  { key: '90d', label: '90天' },
]

interface Props {
  range:         RangeKey
  onRangeChange: (key: RangeKey) => void
}

export default function TimeRangeSelector({ range, onRangeChange }: Props) {
  return (
    <div className="flex gap-1">
      {RANGES.map(({ key, label }) => (
        <button
          key={key}
          onClick={() => onRangeChange(key)}
          className={[
            'px-3 py-1 text-xs rounded transition-colors',
            range === key
              ? 'bg-blue-600 text-white'
              : 'bg-gray-700 text-gray-300 hover:bg-gray-600',
          ].join(' ')}
        >
          {label}
        </button>
      ))}
    </div>
  )
}

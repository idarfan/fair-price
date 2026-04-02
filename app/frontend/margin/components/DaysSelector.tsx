import { daysToDate, dateToDays } from '../utils/format'

const QUICK_DAYS = [7, 30, 90, 180, 365] as const

interface Props {
  days: number
  onDaysChange: (days: number) => void
}

export function DaysSelector({ days, onDaysChange }: Props) {
  const clamp = (v: number) => Math.min(730, Math.max(1, v))

  return (
    <div className="space-y-3">
      <label className="block text-xs text-gray-400">持有天數</label>

      {/* Quick buttons */}
      <div className="flex gap-2 flex-wrap">
        {QUICK_DAYS.map(d => (
          <button
            key={d}
            type="button"
            onClick={() => onDaysChange(d)}
            className={`px-3 py-1 text-xs rounded-full border transition-colors
              ${days === d
                ? 'bg-blue-600 border-blue-500 text-white'
                : 'bg-gray-800 border-gray-600 text-gray-300 hover:border-blue-500'}`}
          >
            {d}d
          </button>
        ))}
      </div>

      {/* Slider */}
      <input
        type="range"
        min={1}
        max={730}
        step={1}
        value={days}
        onChange={e => onDaysChange(clamp(parseInt(e.target.value, 10)))}
        className="w-full accent-blue-500"
      />

      {/* Number input + Date picker */}
      <div className="flex gap-3">
        <div className="flex-1">
          <label className="block text-xs text-gray-500 mb-1">天數</label>
          <input
            type="number"
            min={1}
            max={730}
            value={days}
            onChange={e => {
              const v = parseInt(e.target.value, 10)
              if (!isNaN(v)) onDaysChange(clamp(v))
            }}
            className="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2
                       text-white text-sm focus:outline-none focus:border-blue-500"
          />
        </div>
        <div className="flex-1">
          <label className="block text-xs text-gray-500 mb-1">平倉日期</label>
          <input
            type="date"
            value={daysToDate(days)}
            onChange={e => {
              if (e.target.value) onDaysChange(dateToDays(e.target.value))
            }}
            className="w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2
                       text-white text-sm focus:outline-none focus:border-blue-500"
          />
        </div>
      </div>
    </div>
  )
}

import { fmtUSD } from '../utils/format'
import type { PriceLookupResult } from '../types'

interface Props {
  info: PriceLookupResult
}

function pctInRange(price: number, low: number, high: number): number {
  if (high <= low) return 50
  return Math.min(100, Math.max(0, ((price - low) / (high - low)) * 100))
}

interface RangeBarProps {
  label: string
  low: number
  high: number
  current: number
  /** true = fill from left to current (Day's Range); false = marker only (52W) */
  filled?: boolean
  /** override track background color */
  trackColor?: string
}

function RangeBar({ label, low, high, current, filled = false, trackColor }: RangeBarProps) {
  const pct = pctInRange(current, low, high)

  return (
    <div>
      {/* Values + label row */}
      <div className="flex items-baseline justify-between mb-1.5">
        <span className="text-gray-200 text-xs font-medium tabular-nums">{fmtUSD(low)}</span>
        <span className="text-gray-400 text-[10px] tracking-widest uppercase">{label}</span>
        <span className="text-gray-200 text-xs font-medium tabular-nums">{fmtUSD(high)}</span>
      </div>

      {/* Bar + triangle container */}
      <div className="relative pb-3">
        {/* Track */}
        <div
          className="relative h-3 rounded-full bg-gray-500"
          style={trackColor ? { backgroundColor: trackColor } : undefined}
        >
          {filled ? (
            /* Day range: red fill from left to current price */
            <div
              className="absolute top-0 left-0 h-full rounded-full"
              style={{ width: `${pct}%`, backgroundColor: '#f87171' }}
            />
          ) : (
            /* 52W range: small red square at current price */
            <div
              className="absolute top-0 h-full w-3 rounded-sm"
              style={{ left: `calc(${pct}% - 6px)`, backgroundColor: '#f87171' }}
            />
          )}
        </div>

        {/* Triangle marker (▲) below bar */}
        <div
          className="absolute"
          style={{
            left:        `${pct}%`,
            bottom:      0,
            transform:   'translateX(-50%)',
            width:        0,
            height:       0,
            borderLeft:  '5px solid transparent',
            borderRight: '5px solid transparent',
            borderBottom: '6px solid #9ca3af',
          }}
        />
      </div>
    </div>
  )
}

export function PriceInfoBar({ info }: Props) {
  const {
    price, day_low, day_high,
    week52_low, week52_high,
    fair_value_low, fair_value_high, stock_type,
  } = info

  const hasDayRange = day_low != null && day_high != null && day_high > day_low
  const has52w      = week52_low != null && week52_high != null
  const hasFairV    = fair_value_low != null && fair_value_high != null

  if (!hasDayRange && !has52w) return null

  return (
    <div className="mt-2 space-y-3 bg-gray-700 rounded-lg px-3 pt-2.5 pb-2">
      {hasDayRange && (
        <RangeBar
          label="Day's Range"
          low={day_low!}
          high={day_high!}
          current={price}
          filled
          trackColor="#4ade80"
        />
      )}

      {has52w && (
        <RangeBar
          label="52Wk Range"
          low={week52_low!}
          high={week52_high!}
          current={price}
          trackColor="#4ade80"
        />
      )}

      {hasFairV && (
        <div className="flex items-center gap-1.5 text-gray-400 text-xs pb-0.5">
          <span className="w-2 h-2 rounded-sm bg-blue-400 opacity-70 inline-block flex-shrink-0" />
          <span>
            公允估值
            {stock_type && (
              <span className="ml-1 text-[10px]">({stock_type})</span>
            )}
            ：
            <span className="text-blue-300 font-semibold ml-1">{fmtUSD(fair_value_low!)}</span>
            <span className="mx-1">~</span>
            <span className="text-blue-300 font-semibold">{fmtUSD(fair_value_high!)}</span>
          </span>
        </div>
      )}
    </div>
  )
}

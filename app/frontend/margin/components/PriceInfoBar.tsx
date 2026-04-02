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
  filled?: boolean   // true = fill from left to current (day range); false = marker only (52W)
}

function RangeBar({ label, low, high, current, filled = false }: RangeBarProps) {
  const pct = pctInRange(current, low, high)

  return (
    <div>
      <div className="flex items-baseline justify-between mb-1.5">
        <span className="text-gray-200 text-xs font-medium tabular-nums">{fmtUSD(low)}</span>
        <span className="text-gray-400 text-[10px] tracking-widest uppercase">{label}</span>
        <span className="text-gray-200 text-xs font-medium tabular-nums">{fmtUSD(high)}</span>
      </div>

      {/* Bar + triangle marker */}
      <div className="relative pb-2.5">
        {/* Track */}
        <div className="h-1.5 bg-gray-600 rounded-full overflow-hidden">
          {filled ? (
            /* Day range: fill from left edge to current price */
            <div
              className="h-full bg-red-400 rounded-full"
              style={{ width: `${pct}%` }}
            />
          ) : (
            /* 52W range: small square marker at current price */
            <div
              className="absolute top-0 h-1.5 w-2 bg-red-400 rounded-sm -translate-x-1/2"
              style={{ left: `${pct}%` }}
            />
          )}
        </div>

        {/* Triangle (▲) below bar at current price position */}
        <div
          className="absolute bottom-0 w-0 h-0 -translate-x-1/2"
          style={{
            left: `${pct}%`,
            borderLeft:   '4px solid transparent',
            borderRight:  '4px solid transparent',
            borderBottom: '6px solid #9ca3af',   // gray-400
          }}
        />
      </div>
    </div>
  )
}

export function PriceInfoBar({ info }: Props) {
  const { price, day_low, day_high, week52_low, week52_high, fair_value_low, fair_value_high, stock_type } = info

  const hasDayRange = day_low != null && day_high != null && day_high > day_low
  const has52w      = week52_low != null && week52_high != null
  const hasFairV    = fair_value_low != null && fair_value_high != null

  if (!hasDayRange && !has52w) return null

  return (
    <div className="mt-2 space-y-3 text-xs bg-gray-700 rounded-lg px-3 pt-2.5 pb-1.5">
      {hasDayRange && (
        <RangeBar
          label="Day's Range"
          low={day_low!}
          high={day_high!}
          current={price}
          filled
        />
      )}

      {has52w && (
        <RangeBar
          label="52Wk Range"
          low={week52_low!}
          high={week52_high!}
          current={price}
          filled={false}
        />
      )}

      {hasFairV && (
        <div className="flex items-center gap-1.5 text-gray-400 pb-0.5">
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

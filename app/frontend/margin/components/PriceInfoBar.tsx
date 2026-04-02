import { fmtUSD } from '../utils/format'
import type { PriceLookupResult } from '../types'

interface Props {
  info: PriceLookupResult
}

// Returns position % (0–100) of price within [low, high]
function pctInRange(price: number, low: number, high: number): number {
  if (high <= low) return 50
  return Math.min(100, Math.max(0, ((price - low) / (high - low)) * 100))
}

export function PriceInfoBar({ info }: Props) {
  const { price, week52_low, week52_high, fair_value_low, fair_value_high, stock_type } = info

  const has52w   = week52_low != null && week52_high != null
  const hasFairV = fair_value_low != null && fair_value_high != null

  return (
    <div className="mt-2 space-y-2 text-xs">
      {/* 52-week range bar */}
      {has52w && (
        <div>
          <div className="flex justify-between text-gray-500 mb-0.5">
            <span>52週低 {fmtUSD(week52_low!)}</span>
            <span className="text-gray-400">現價 {fmtUSD(price)}</span>
            <span>52週高 {fmtUSD(week52_high!)}</span>
          </div>
          <div className="relative h-1.5 bg-gray-700 rounded-full">
            {/* Fair value band overlay */}
            {hasFairV && (() => {
              const fvLeft = pctInRange(fair_value_low!, week52_low!, week52_high!)
              const fvRight = pctInRange(fair_value_high!, week52_low!, week52_high!)
              return (
                <div
                  className="absolute top-0 h-full bg-blue-900 rounded-full opacity-70"
                  style={{ left: `${fvLeft}%`, width: `${fvRight - fvLeft}%` }}
                />
              )
            })()}
            {/* Current price dot */}
            <div
              className="absolute top-1/2 -translate-y-1/2 w-2.5 h-2.5 bg-green-400
                         rounded-full border-2 border-gray-900 shadow"
              style={{ left: `calc(${pctInRange(price, week52_low!, week52_high!)}% - 5px)` }}
            />
          </div>
        </div>
      )}

      {/* Fair value range */}
      {hasFairV && (
        <div className="flex items-center gap-1 text-gray-400">
          <span className="w-1.5 h-1.5 rounded-sm bg-blue-700 inline-block" />
          <span>
            公允估值
            {stock_type ? <span className="text-gray-600 ml-1">({stock_type})</span> : null}
            ：
            <span className="text-blue-300 font-medium ml-1">
              {fmtUSD(fair_value_low!)} ~ {fmtUSD(fair_value_high!)}
            </span>
          </span>
        </div>
      )}
    </div>
  )
}

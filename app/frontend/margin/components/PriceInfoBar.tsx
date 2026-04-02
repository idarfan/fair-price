import { fmtUSD } from '../utils/format'
import type { PriceLookupResult } from '../types'

interface Props {
  info: PriceLookupResult
}

function pctInRange(price: number, low: number, high: number): number {
  if (high <= low) return 50
  return Math.min(100, Math.max(0, ((price - low) / (high - low)) * 100))
}

export function PriceInfoBar({ info }: Props) {
  const { price, week52_low, week52_high, fair_value_low, fair_value_high, stock_type } = info

  const has52w   = week52_low != null && week52_high != null
  const hasFairV = fair_value_low != null && fair_value_high != null

  return (
    <div className="mt-2 space-y-2.5 text-xs bg-gray-700 rounded-lg px-3 py-2.5">
      {/* 52-week range bar */}
      {has52w && (
        <div>
          <div className="flex justify-between text-gray-200 mb-1.5">
            <span>📉 52W低 <span className="text-red-300 font-medium">{fmtUSD(week52_low!)}</span></span>
            <span className="text-white font-semibold">現價 {fmtUSD(price)}</span>
            <span>📈 52W高 <span className="text-green-300 font-medium">{fmtUSD(week52_high!)}</span></span>
          </div>
          {/* Progress bar track */}
          <div className="relative h-2 bg-gray-600 rounded-full">
            {/* Fair value band */}
            {hasFairV && (() => {
              const fvLeft  = pctInRange(fair_value_low!,  week52_low!, week52_high!)
              const fvRight = pctInRange(fair_value_high!, week52_low!, week52_high!)
              return (
                <div
                  className="absolute top-0 h-full bg-blue-400 rounded-full opacity-40"
                  style={{ left: `${fvLeft}%`, width: `${Math.max(2, fvRight - fvLeft)}%` }}
                />
              )
            })()}
            {/* Current price dot */}
            <div
              className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-yellow-300
                         rounded-full border-2 border-gray-700 shadow-lg"
              style={{ left: `calc(${pctInRange(price, week52_low!, week52_high!)}% - 6px)` }}
            />
          </div>
        </div>
      )}

      {/* Fair value range */}
      {hasFairV && (
        <div className="flex items-center gap-1.5 text-gray-200">
          <span className="w-2 h-2 rounded-sm bg-blue-400 opacity-70 inline-block flex-shrink-0" />
          <span>
            公允估值
            {stock_type
              ? <span className="text-gray-400 ml-1 text-xs">({stock_type})</span>
              : null}
            ：
            <span className="text-blue-200 font-semibold ml-1">
              {fmtUSD(fair_value_low!)}
            </span>
            <span className="text-gray-400 mx-1">~</span>
            <span className="text-blue-200 font-semibold">
              {fmtUSD(fair_value_high!)}
            </span>
          </span>
        </div>
      )}
    </div>
  )
}

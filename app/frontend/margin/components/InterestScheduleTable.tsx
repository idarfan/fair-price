import { fmtUSD } from '../utils/format'
import type { ScheduleRow } from '../types'

interface Props {
  schedule: ScheduleRow[]
}

export function InterestScheduleTable({ schedule }: Props) {
  if (schedule.length === 0) return null

  return (
    <div>
      <h3 className="text-xs text-gray-400 mb-2">融資利息收取時程</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="text-gray-400 border-b border-gray-700">
              <th className="text-left py-1 pr-3">次數</th>
              <th className="text-right py-1 pr-3">收息日（天）</th>
              <th className="text-right py-1 pr-3">計息天數</th>
              <th className="text-right py-1 pr-3">本期利息</th>
              <th className="text-right py-1">累計利息</th>
            </tr>
          </thead>
          <tbody>
            {schedule.map(row => (
              <tr key={row.chargeNumber} className="border-b border-gray-800 text-gray-300">
                <td className="py-1 pr-3">{row.chargeNumber}</td>
                <td className="text-right py-1 pr-3">第 {row.dayOfCharge} 天</td>
                <td className="text-right py-1 pr-3">{row.periodDays} 天</td>
                <td className="text-right py-1 pr-3">{fmtUSD(row.periodInterest)}</td>
                <td className="text-right py-1">{fmtUSD(row.cumulativeInterest)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

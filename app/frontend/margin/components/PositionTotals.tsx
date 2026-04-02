import { fmtUSD } from '../utils/format'
import type { MarginPosition } from '../types'

interface Props {
  positions: MarginPosition[]
}

export function PositionTotals({ positions }: Props) {
  const open = positions.filter(p => p.status === 'open')

  const totalInterest = open.reduce((sum, p) => sum + p.accrued_interest, 0)
  const totalCurrentPeriod = open.reduce((sum, p) => sum + p.current_period_interest, 0)
  const totalBalance = open.reduce((sum, p) => sum + p.balance, 0)

  const totalNetProfit = open.reduce((sum, p) => {
    if (!p.sell_price) return sum
    const spread = (parseFloat(p.sell_price) - parseFloat(p.buy_price)) * parseFloat(p.shares)
    return sum + spread - p.accrued_interest
  }, 0)

  if (open.length === 0) return null

  return (
    <tfoot>
      <tr className="border-t border-gray-600 font-semibold text-sm">
        <td className="py-2 pr-3 text-gray-400" colSpan={3}>
          合計（{open.length} 筆持倉）
        </td>
        <td className="py-2 pr-3 text-gray-400">—</td>
        <td className="py-2 pr-3 text-yellow-400">{fmtUSD(totalInterest)}</td>
        <td className="py-2 pr-3 text-gray-400">—</td>
        <td className="py-2 pr-3 text-gray-400">{fmtUSD(totalCurrentPeriod)}</td>
        <td className={`py-2 pr-3 ${totalNetProfit >= 0 ? 'text-green-400' : 'text-red-400'}`}>
          {fmtUSD(totalNetProfit)}
        </td>
        <td className="py-2 text-gray-400 text-xs">
          融資總額 {fmtUSD(totalBalance)}
        </td>
      </tr>
    </tfoot>
  )
}

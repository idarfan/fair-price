import { fmtUSD, fmtDate } from '../utils/format'
import type { MarginPosition } from '../types'

interface Props {
  position: MarginPosition
  onClose: (id: number) => void
  onDelete: (id: number) => void
}

export function PositionRow({ position, onClose, onDelete }: Props) {
  const isClosed = position.status === 'closed'
  const rowClass = isClosed ? 'opacity-50' : ''

  const netProfit = position.sell_price
    ? (parseFloat(position.sell_price) - parseFloat(position.buy_price))
        * parseFloat(position.shares) - position.accrued_interest
    : null

  return (
    <tr className={`border-b border-gray-800 text-sm ${rowClass}`}>
      <td className="py-2 pr-3 font-semibold text-white">{position.symbol}</td>
      <td className="py-2 pr-3 text-gray-300">{fmtUSD(parseFloat(position.buy_price))}</td>
      <td className="py-2 pr-3 text-gray-300">{parseFloat(position.shares).toLocaleString()}</td>
      <td className="py-2 pr-3 text-gray-400">{position.days_held} 天</td>
      <td className="py-2 pr-3 text-yellow-400">{fmtUSD(position.accrued_interest)}</td>
      <td className="py-2 pr-3 text-gray-400">{fmtDate(position.next_charge_date)}</td>
      <td className="py-2 pr-3 text-gray-400">{fmtUSD(position.current_period_interest)}</td>
      <td className={`py-2 pr-3 font-medium ${
        netProfit === null ? 'text-gray-500' :
        netProfit >= 0 ? 'text-green-400' : 'text-red-400'
      }`}>
        {netProfit !== null ? fmtUSD(netProfit) : '—'}
      </td>
      <td className="py-2">
        {!isClosed && (
          <div className="flex gap-1">
            <button
              onClick={() => onClose(position.id)}
              className="px-2 py-1 text-xs bg-blue-700 hover:bg-blue-600 rounded text-white"
            >
              平倉
            </button>
            <button
              onClick={() => onDelete(position.id)}
              className="px-2 py-1 text-xs bg-gray-700 hover:bg-red-700 rounded text-gray-300"
            >
              刪除
            </button>
          </div>
        )}
      </td>
    </tr>
  )
}

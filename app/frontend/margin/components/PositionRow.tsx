import { useState } from 'react'
import { fmtUSD, fmtDate } from '../utils/format'
import type { MarginPosition } from '../types'

interface Props {
  position: MarginPosition
  onClose: (id: number) => void
  onDelete: (id: number) => void
  onUpdateDate: (id: number, field: 'opened_on' | 'closed_on', value: string) => void
}

function EditableDate({
  value,
  onSave,
}: {
  value: string
  onSave: (v: string) => void
}) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)

  const commit = () => {
    setEditing(false)
    if (draft && draft !== value) onSave(draft)
  }

  if (editing) {
    return (
      <input
        type="date"
        value={draft}
        autoFocus
        onChange={e => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={e => {
          if (e.key === 'Enter') commit()
          if (e.key === 'Escape') { setDraft(value); setEditing(false) }
        }}
        className="bg-gray-700 border border-blue-500 rounded px-1 py-0.5 text-white text-xs w-28"
      />
    )
  }

  return (
    <button
      type="button"
      title="點擊編輯日期"
      onClick={() => { setDraft(value); setEditing(true) }}
      className="text-gray-400 hover:text-blue-400 hover:underline underline-offset-2
                 decoration-dashed cursor-pointer text-left"
    >
      {fmtDate(value)}
    </button>
  )
}

export function PositionRow({ position, onClose, onDelete, onUpdateDate }: Props) {
  const isClosed = position.status === 'closed'

  const netProfit = position.sell_price
    ? (parseFloat(position.sell_price) - parseFloat(position.buy_price))
        * parseFloat(position.shares) - position.accrued_interest
    : null

  return (
    <tr className={`border-b border-gray-800 text-sm ${isClosed ? 'opacity-50' : ''}`}>
      <td className="py-2 pr-3 font-semibold text-white">{position.symbol}</td>
      <td className="py-2 pr-3 text-gray-300">{fmtUSD(parseFloat(position.buy_price))}</td>
      <td className="py-2 pr-3 text-gray-300">{parseFloat(position.shares).toLocaleString()}</td>

      {/* 建倉日 — 可編輯 */}
      <td className="py-2 pr-3">
        <EditableDate
          value={position.opened_on}
          onSave={v => onUpdateDate(position.id, 'opened_on', v)}
        />
      </td>

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
        <div className="flex gap-1 flex-wrap">
          {!isClosed && (
            <>
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
            </>
          )}
          {/* 已平倉：可修改平倉日 */}
          {isClosed && position.closed_on && (
            <div className="flex items-center gap-1 text-xs text-gray-500">
              <span>平倉日：</span>
              <EditableDate
                value={position.closed_on}
                onSave={v => onUpdateDate(position.id, 'closed_on', v)}
              />
            </div>
          )}
        </div>
      </td>
    </tr>
  )
}

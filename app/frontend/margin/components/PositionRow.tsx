import { useState } from 'react'
import { fmtUSD, fmtDate } from '../utils/format'
import type { MarginPosition } from '../types'

interface Props {
  position: MarginPosition
  onClose: (id: number) => void
  onDelete: (id: number) => void
  onUpdateField: (id: number, field: string, value: string) => void
}

type CellType = 'date' | 'price'

function EditableCell({
  value,
  type,
  display,
  onSave,
}: {
  value: string
  type: CellType
  display: string
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
        type={type === 'date' ? 'date' : 'number'}
        value={draft}
        step={type === 'price' ? '0.01' : undefined}
        min={type === 'price' ? '0' : undefined}
        autoFocus
        onChange={e => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={e => {
          if (e.key === 'Enter') commit()
          if (e.key === 'Escape') { setDraft(value); setEditing(false) }
        }}
        className="bg-gray-700 border border-blue-500 rounded px-1 py-0.5 text-white text-xs w-24"
      />
    )
  }

  return (
    <button
      type="button"
      title="點擊編輯"
      onClick={() => { setDraft(value); setEditing(true) }}
      className="hover:text-blue-400 hover:underline underline-offset-2
                 decoration-dashed cursor-pointer text-left"
    >
      {display}
    </button>
  )
}

export function PositionRow({ position, onClose, onDelete, onUpdateField }: Props) {
  const isClosed = position.status === 'closed'

  const netProfit = position.sell_price
    ? (parseFloat(position.sell_price) - parseFloat(position.buy_price))
        * parseFloat(position.shares) - position.accrued_interest
    : null

  return (
    <tr className={`border-b border-gray-800 text-sm ${isClosed ? 'opacity-50' : ''}`}>
      <td className="py-2 pr-3 font-semibold text-white">{position.symbol}</td>

      {/* 建倉價 — 可編輯 */}
      <td className="py-2 pr-3 text-gray-300">
        <EditableCell
          value={position.buy_price}
          type="price"
          display={fmtUSD(parseFloat(position.buy_price))}
          onSave={v => onUpdateField(position.id, 'buy_price', v)}
        />
      </td>

      <td className="py-2 pr-3 text-gray-300">{parseFloat(position.shares).toLocaleString()}</td>

      {/* 建倉日 — 可編輯 */}
      <td className="py-2 pr-3 text-gray-400">
        <EditableCell
          value={position.opened_on}
          type="date"
          display={fmtDate(position.opened_on)}
          onSave={v => onUpdateField(position.id, 'opened_on', v)}
        />
      </td>

      <td className="py-2 pr-3 text-gray-400">{position.days_held} 天</td>
      <td className="py-2 pr-3 text-yellow-400">{fmtUSD(position.accrued_interest)}</td>
      <td className="py-2 pr-3 text-gray-400">{fmtDate(position.next_charge_date)}</td>
      <td className="py-2 pr-3 text-gray-400">{fmtUSD(position.current_period_interest)}</td>

      {/* 平倉價 — 可編輯 */}
      <td className={`py-2 pr-3 font-medium ${
        netProfit === null ? 'text-gray-500' :
        netProfit >= 0 ? 'text-green-400' : 'text-red-400'
      }`}>
        <EditableCell
          value={position.sell_price ?? ''}
          type="price"
          display={netProfit !== null ? fmtUSD(netProfit) : '— 填平倉價'}
          onSave={v => onUpdateField(position.id, 'sell_price', v)}
        />
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
          {isClosed && position.closed_on && (
            <div className="flex items-center gap-1 text-xs text-gray-500">
              <span>平倉日：</span>
              <EditableCell
                value={position.closed_on}
                type="date"
                display={fmtDate(position.closed_on)}
                onSave={v => onUpdateField(position.id, 'closed_on', v)}
              />
            </div>
          )}
        </div>
      </td>
    </tr>
  )
}

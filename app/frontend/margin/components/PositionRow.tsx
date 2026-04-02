import { useRef, useState } from 'react'
import { fmtUSD, fmtDate, parseFlexDate } from '../utils/format'
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
  const [textDraft, setTextDraft] = useState(value) // for date: text side
  const pickerRef = useRef<HTMLInputElement>(null)

  const commit = (val = draft) => {
    setEditing(false)
    if (val && val !== value) onSave(val)
  }

  const commitText = () => {
    const parsed = parseFlexDate(textDraft)
    if (parsed) {
      setDraft(parsed)
      commit(parsed)
    } else {
      commit(draft)  // fall back to last known good value
    }
  }

  if (editing && type === 'date') {
    return (
      <div className="flex items-center gap-1">
        {/* Text input — direct typing */}
        <input
          type="text"
          value={textDraft}
          placeholder="20260401"
          autoFocus
          maxLength={10}
          onChange={e => {
            setTextDraft(e.target.value)
            const parsed = parseFlexDate(e.target.value)
            if (parsed) setDraft(parsed)
          }}
          onBlur={commitText}
          onKeyDown={e => {
            if (e.key === 'Enter') commitText()
            if (e.key === 'Escape') { setEditing(false); setDraft(value); setTextDraft(value) }
          }}
          className="bg-gray-700 border border-blue-500 rounded px-1 py-0.5 text-white text-xs w-28"
        />
        {/* Hidden date picker — triggered by calendar icon */}
        <input
          ref={pickerRef}
          type="date"
          value={draft}
          tabIndex={-1}
          onChange={e => {
            if (e.target.value) {
              setDraft(e.target.value)
              setTextDraft(e.target.value)
              commit(e.target.value)
            }
          }}
          className="sr-only"
        />
        <button
          type="button"
          tabIndex={-1}
          title="開啟日曆"
          onMouseDown={e => { e.preventDefault(); pickerRef.current?.showPicker?.() }}
          className="text-gray-400 hover:text-blue-400 text-sm leading-none"
        >
          📅
        </button>
      </div>
    )
  }

  if (editing && type === 'price') {
    return (
      <input
        type="number"
        value={draft}
        step="0.01"
        min="0"
        autoFocus
        onChange={e => setDraft(e.target.value)}
        onBlur={() => commit()}
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
      onClick={() => { setDraft(value); setTextDraft(value); setEditing(true) }}
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
      <td className="py-2 pr-3 text-gray-300">
        <EditableCell
          value={position.sell_price ?? ''}
          type="price"
          display={position.sell_price ? fmtUSD(parseFloat(position.sell_price)) : '—'}
          onSave={v => onUpdateField(position.id, 'sell_price', v)}
        />
      </td>

      {/* 淨獲利（唯讀，由 sell_price 與 accrued_interest 計算） */}
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

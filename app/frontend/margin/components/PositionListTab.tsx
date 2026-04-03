import { useState, useEffect, useCallback } from 'react'
import { AddPositionForm } from './AddPositionForm'
import { PositionRow } from './PositionRow'
import { PositionTotals } from './PositionTotals'
import { fmtUSD, fmtDate } from '../utils/format'
import type { MarginPosition, AddPositionPayload } from '../types'

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

const API_BASE = '/api/v1/margin_positions'

const OPEN_HEADERS = [
  '代號', '建倉價', '股數', '建倉日', '持有天數',
  '累計利息', '下次收息日', '本期備金', '平倉價', '淨獲利', '操作',
]

export function PositionListTab() {
  const [positions, setPositions] = useState<MarginPosition[]>([])
  const [closedPositions, setClosedPositions] = useState<MarginPosition[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPositions = useCallback(async () => {
    try {
      const res = await fetch(API_BASE)
      if (!res.ok) throw new Error('無法載入持倉資料')
      const data = await res.json()
      setPositions(data.positions ?? [])
      setClosedPositions(data.closed_positions ?? [])
    } catch (err) {
      setError(err instanceof Error ? err.message : '未知錯誤')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchPositions() }, [fetchPositions])

  const handleAdd = async (payload: AddPositionPayload) => {
    const res = await fetch(API_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ margin_position: payload }),
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.errors?.join(', ') || '新增失敗')
    }
    await fetchPositions()
  }

  const handleClose = async (id: number) => {
    const res = await fetch(`${API_BASE}/${id}/close`, {
      method: 'POST',
      headers: { 'X-CSRF-Token': csrfToken() },
    })
    if (res.ok) await fetchPositions()
  }

  const handleDelete = async (id: number) => {
    if (!confirm('確認刪除此持倉？')) return
    const res = await fetch(`${API_BASE}/${id}`, {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': csrfToken() },
    })
    if (res.ok) await fetchPositions()
  }

  const handleUpdateField = async (id: number, field: string, value: string) => {
    await fetch(`${API_BASE}/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ margin_position: { [field]: value } }),
    })
    await fetchPositions()
  }

  return (
    <div className="space-y-6">
      <AddPositionForm onSubmit={handleAdd} />

      <div className="flex items-center gap-3">
        <h2 className="text-sm font-semibold text-gray-300">實際融資持股清單</h2>
        <hr className="flex-1 border-gray-700" />
      </div>

      {loading && <p className="text-gray-500 text-sm text-center py-4">載入中…</p>}
      {error   && <p className="text-red-400 text-sm text-center py-4">{error}</p>}

      {/* ── 持倉中 ── */}
      {!loading && !error && (
        <>
          {positions.length === 0 ? (
            <p className="text-gray-500 text-sm text-center py-8">尚無持倉，請新增第一筆</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs min-w-[900px]">
                <thead>
                  <tr className="text-gray-400 border-b border-gray-700 text-left">
                    {OPEN_HEADERS.map(h => (
                      <th key={h} className="py-2 pr-3 last:pr-0">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {positions.map(p => (
                    <PositionRow
                      key={p.id}
                      position={p}
                      onClose={handleClose}
                      onDelete={handleDelete}
                      onUpdateField={handleUpdateField}
                    />
                  ))}
                </tbody>
                <PositionTotals positions={positions} />
              </table>
            </div>
          )}

          {/* ── 已平倉記錄 ── */}
          {closedPositions.length > 0 && (
            <ClosedPositionsSection
              positions={closedPositions}
              onUpdateField={handleUpdateField}
              onDelete={handleDelete}
            />
          )}
        </>
      )}
    </div>
  )
}

// ── 已平倉記錄區塊 ──────────────────────────────────────────────────
function ClosedPositionsSection({
  positions,
  onUpdateField,
  onDelete,
}: {
  positions: MarginPosition[]
  onUpdateField: (id: number, field: string, value: string) => void
  onDelete: (id: number) => void
}) {
  const [collapsed, setCollapsed] = useState(false)

  const totalInterest = positions.reduce((s, p) => s + p.accrued_interest, 0)
  const totalNetProfit = positions.reduce((s, p) => {
    if (!p.sell_price) return s
    return s + (parseFloat(p.sell_price) - parseFloat(p.buy_price)) * parseFloat(p.shares) - p.accrued_interest
  }, 0)

  return (
    <div>
      <button
        type="button"
        onClick={() => setCollapsed(c => !c)}
        className="flex items-center gap-2 text-sm font-semibold text-gray-400
                   hover:text-gray-200 mb-2"
      >
        <span>{collapsed ? '▶' : '▼'}</span>
        <span>已平倉記錄（{positions.length} 筆）</span>
        <span className="text-xs font-normal text-gray-500 ml-2">
          共支付利息 {fmtUSD(totalInterest)}，
          淨損益 <span className={totalNetProfit >= 0 ? 'text-green-400' : 'text-red-400'}>
            {fmtUSD(totalNetProfit)}
          </span>
        </span>
      </button>

      {!collapsed && (
        <div className="overflow-x-auto">
          <table className="w-full text-xs min-w-[780px]">
            <thead>
              <tr className="text-gray-500 border-b border-gray-800 text-left">
                <th className="py-1 pr-3">代號</th>
                <th className="py-1 pr-3">建倉價</th>
                <th className="py-1 pr-3">平倉價</th>
                <th className="py-1 pr-3">股數</th>
                <th className="py-1 pr-3">建倉日</th>
                <th className="py-1 pr-3">平倉日</th>
                <th className="py-1 pr-3">持有天數</th>
                <th className="py-1 pr-3">支付利息</th>
                <th className="py-1 pr-3">淨損益</th>
                <th className="py-1">操作</th>
              </tr>
            </thead>
            <tbody>
              {positions.map(p => <ClosedRow key={p.id} position={p} onUpdateField={onUpdateField} onDelete={onDelete} />)}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function ClosedRow({
  position: p,
  onUpdateField,
  onDelete,
}: {
  position: MarginPosition
  onUpdateField: (id: number, field: string, value: string) => void
  onDelete: (id: number) => void
}) {
  const netProfit = p.sell_price
    ? (parseFloat(p.sell_price) - parseFloat(p.buy_price)) * parseFloat(p.shares) - p.accrued_interest
    : null

  return (
    <tr className="border-b border-gray-800 text-gray-400 opacity-70">
      <td className="py-1.5 pr-3 font-semibold text-gray-300">{p.symbol}</td>
      <td className="py-1.5 pr-3">{fmtUSD(parseFloat(p.buy_price))}</td>
      <td className="py-1.5 pr-3">
        {p.sell_price ? fmtUSD(parseFloat(p.sell_price)) : '—'}
      </td>
      <td className="py-1.5 pr-3">{parseFloat(p.shares).toLocaleString()}</td>
      <td className="py-1.5 pr-3">{fmtDate(p.opened_on)}</td>
      <td className="py-1.5 pr-3">
        {p.closed_on
          ? <ClosedDateEdit value={p.closed_on} onSave={v => onUpdateField(p.id, 'closed_on', v)} />
          : '—'}
      </td>
      <td className="py-1.5 pr-3">{p.days_held} 天</td>
      <td className="py-1.5 pr-3 text-yellow-400">{fmtUSD(p.accrued_interest)}</td>
      <td className={`py-1.5 pr-3 font-medium ${
        netProfit === null ? 'text-gray-500' :
        netProfit >= 0 ? 'text-green-400' : 'text-red-400'
      }`}>
        {netProfit !== null ? fmtUSD(netProfit) : '—'}
      </td>
      <td className="py-1.5">
        <button
          onClick={() => onDelete(p.id)}
          className="px-2 py-0.5 text-xs bg-gray-800 hover:bg-red-900 rounded text-gray-500"
        >
          刪除
        </button>
      </td>
    </tr>
  )
}

// Simple inline date editor for closed_on in the closed section
function ClosedDateEdit({ value, onSave }: { value: string; onSave: (v: string) => void }) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)

  const commit = () => {
    setEditing(false)
    const clean = draft.replace(/-/g, '')
    if (/^\d{8}$/.test(clean)) {
      const iso = `${clean.slice(0,4)}-${clean.slice(4,6)}-${clean.slice(6,8)}`
      if (!isNaN(Date.parse(iso)) && iso !== value) onSave(iso)
    }
  }

  if (editing) {
    return (
      <input
        type="text"
        value={draft}
        placeholder="20260401"
        maxLength={10}
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
      onClick={() => { setDraft(value); setEditing(true) }}
      className="hover:text-blue-400 hover:underline underline-offset-2 decoration-dashed"
    >
      {fmtDate(value)}
    </button>
  )
}

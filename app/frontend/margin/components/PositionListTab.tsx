import { useState, useEffect, useCallback } from 'react'
import { AddPositionForm } from './AddPositionForm'
import { PositionRow } from './PositionRow'
import { PositionTotals } from './PositionTotals'
import type { MarginPosition, AddPositionPayload } from '../types'

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

const API_BASE = '/api/v1/margin_positions'

export function PositionListTab() {
  const [positions, setPositions] = useState<MarginPosition[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPositions = useCallback(async () => {
    try {
      const res = await fetch(API_BASE)
      if (!res.ok) throw new Error('無法載入持倉資料')
      const data = await res.json()
      setPositions(data.positions)
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
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
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
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      body: JSON.stringify({ margin_position: { [field]: value } }),
    })
    await fetchPositions()
  }

  const handlePriceLookup = async (symbol: string): Promise<number | null> => {
    const res = await fetch(`${API_BASE}/price_lookup?symbol=${encodeURIComponent(symbol)}`)
    if (!res.ok) return null
    const data = await res.json()
    return data.price ?? null
  }

  return (
    <div className="space-y-4">
      <AddPositionForm onSubmit={handleAdd} onPriceLookup={handlePriceLookup} />

      {loading && (
        <p className="text-gray-500 text-sm text-center py-4">載入中…</p>
      )}
      {error && (
        <p className="text-red-400 text-sm text-center py-4">{error}</p>
      )}
      {!loading && !error && positions.length === 0 && (
        <p className="text-gray-500 text-sm text-center py-8">尚無持倉，請新增第一筆</p>
      )}
      {!loading && positions.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full text-xs min-w-[800px]">
            <thead>
              <tr className="text-gray-400 border-b border-gray-700 text-left">
                <th className="py-2 pr-3">代號</th>
                <th className="py-2 pr-3">建倉價</th>
                <th className="py-2 pr-3">股數</th>
                <th className="py-2 pr-3">建倉日</th>
                <th className="py-2 pr-3">持有天數</th>
                <th className="py-2 pr-3">累計利息</th>
                <th className="py-2 pr-3">下次收息日</th>
                <th className="py-2 pr-3">本期備金</th>
                <th className="py-2 pr-3">淨獲利</th>
                <th className="py-2">操作</th>
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
    </div>
  )
}

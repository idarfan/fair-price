import React, { useState, useEffect, useCallback } from 'react'
import type {
  MarketOutlook, SentimentData, IvRankData, PayoffLeg
} from './types'
import { getStrategies, buildLegsForPrice } from './strategies'
import { buildChartData, calcSummary }       from './payoff'
import OutlookSelector        from './components/OutlookSelector'
import StrategyRecommendList  from './components/StrategyRecommendList'
import StrategyDetailPanel    from './components/StrategyDetailPanel'
import PayoffChart             from './components/PayoffChart'
import SentimentPanel          from './components/SentimentPanel'
import ImageUploadZone, { OcrResult } from './components/ImageUploadZone'

// ─── Types ────────────────────────────────────────────────────────────────────

interface LegRow extends PayoffLeg {
  id: number
}

// ─── Custom Leg Editor ────────────────────────────────────────────────────────

const LEG_TYPES: PayoffLeg['type'][] = [
  'long_call', 'short_call', 'long_put', 'short_put'
]
const LEG_LABELS: Record<PayoffLeg['type'], string> = {
  long_call:  'Long Call',
  short_call: 'Short Call',
  long_put:   'Long Put',
  short_put:  'Short Put',
  long_stock:  'Long Stock',
  short_stock: 'Short Stock',
}

function LegEditor({
  legs,
  onAdd,
  onRemove,
  onChange,
}: {
  legs:     LegRow[]
  onAdd:    () => void
  onRemove: (id: number) => void
  onChange: (id: number, field: keyof PayoffLeg, value: number | string) => void
}) {
  return (
    <div className="flex flex-col gap-2">
      {legs.map(leg => (
        <div key={leg.id} className="flex gap-1 items-center flex-wrap">
          <select
            value={leg.type}
            onChange={e => onChange(leg.id, 'type', e.target.value)}
            className="text-xs border border-gray-200 rounded px-1 py-0.5 bg-white"
          >
            {LEG_TYPES.map(t => (
              <option key={t} value={t}>{LEG_LABELS[t]}</option>
            ))}
          </select>
          <input
            type="number" placeholder="Strike"
            value={leg.strike || ''}
            onChange={e => onChange(leg.id, 'strike', parseFloat(e.target.value) || 0)}
            className="w-20 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <input
            type="number" placeholder="Premium"
            step="0.01"
            value={leg.premium || ''}
            onChange={e => onChange(leg.id, 'premium', parseFloat(e.target.value) || 0)}
            className="w-20 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <input
            type="number" placeholder="Qty"
            value={leg.quantity}
            onChange={e => onChange(leg.id, 'quantity', parseInt(e.target.value) || 1)}
            className="w-12 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <button
            onClick={() => onRemove(leg.id)}
            className="text-red-400 hover:text-red-600 text-xs px-1"
          >✕</button>
        </div>
      ))}
      <button
        onClick={onAdd}
        className="text-xs text-blue-500 hover:text-blue-700 text-left"
      >
        + 新增腳
      </button>
    </div>
  )
}

// ─── Symbol Search Bar ────────────────────────────────────────────────────────

function SymbolBar({
  symbol, price, loading, onSearch
}: {
  symbol:   string
  price:    number
  loading:  boolean
  onSearch: (sym: string) => void
}) {
  const [input, setInput] = useState(symbol)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const sym = input.trim().toUpperCase()
    if (sym) onSearch(sym)
  }

  return (
    <form onSubmit={handleSubmit} className="flex items-center gap-2">
      <input
        value={input}
        onChange={e => setInput(e.target.value.toUpperCase())}
        placeholder="輸入代號，如 AAPL"
        className="flex-1 border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
      />
      <button
        type="submit"
        disabled={loading}
        className="bg-blue-600 text-white text-sm px-4 py-1.5 rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {loading ? '載入…' : '分析'}
      </button>
      {price > 0 && (
        <span className="text-sm text-gray-600 font-medium">${price.toFixed(2)}</span>
      )}
    </form>
  )
}

// ─── Main App ─────────────────────────────────────────────────────────────────

let nextLegId = 1

export default function OptionsAnalyzerApp({ initialSymbol }: { initialSymbol: string }) {
  const [symbol,      setSymbol]      = useState(initialSymbol || 'AAPL')
  const [price,       setPrice]       = useState(0)
  const [loading,     setLoading]     = useState(false)
  const [error,       setError]       = useState('')
  const [outlook,     setOutlook]     = useState<MarketOutlook>('bullish')
  const [ivRank,      setIvRank]      = useState<IvRankData | null>(null)
  const [sentiment,   setSentiment]   = useState<SentimentData | null>(null)
  const [selectedIdx, setSelectedIdx] = useState(0)
  const [legs,        setLegs]        = useState<LegRow[]>([])
  const [activeTab,   setActiveTab]   = useState<'recommend' | 'custom'>('recommend')

  const fetchData = useCallback(async (sym: string) => {
    setLoading(true)
    setError('')
    try {
      const [sentRes, ivRes] = await Promise.all([
        fetch(`/api/v1/options/${encodeURIComponent(sym)}/sentiment`),
        fetch(`/api/v1/options/${encodeURIComponent(sym)}/iv_rank`),
      ])
      if (!sentRes.ok || !ivRes.ok) throw new Error('API 錯誤')
      const sentData: SentimentData = await sentRes.json()
      const ivData:   IvRankData    = await ivRes.json()
      setSentiment(sentData)
      setIvRank(ivData)
      setPrice(sentData.price)
    } catch (e) {
      setError(e instanceof Error ? e.message : '載入失敗')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchData(symbol) }, [symbol, fetchData])

  const strategies = React.useMemo(
    () => getStrategies(outlook, ivRank?.iv_rank ?? 50),
    [outlook, ivRank]
  )

  // Reset legs when strategy list changes (new outlook/symbol)
  useEffect(() => {
    setSelectedIdx(0)
    if (strategies.length > 0 && price > 0) {
      const builtLegs = buildLegsForPrice(strategies[0], price)
      setLegs(builtLegs.map(l => ({ ...l, id: nextLegId++ })))
    }
  }, [strategies, price])

  // Rebuild legs when selected strategy changes
  const handleSelectStrategy = (i: number) => {
    setSelectedIdx(i)
    const tpl = strategies[i]
    if (!tpl || price <= 0) return
    const builtLegs = buildLegsForPrice(tpl, price)
    setLegs(builtLegs.map(l => ({ ...l, id: nextLegId++ })))
  }

  const handleAddLeg = () => {
    setLegs(prev => [...prev, {
      id: nextLegId++, type: 'long_call',
      strike: price > 0 ? Math.round(price / 5) * 5 : 100,
      premium: 1.0, quantity: 1,
    }])
    setActiveTab('custom')
  }

  const handleRemoveLeg = (id: number) =>
    setLegs(prev => prev.filter(l => l.id !== id))

  const handleChangeLeg = (id: number, field: keyof PayoffLeg, value: number | string) =>
    setLegs(prev => prev.map(l => l.id === id ? { ...l, [field]: value } : l))

  const chartData = React.useMemo(
    () => (legs.length > 0 && price > 0 ? buildChartData(legs as PayoffLeg[], price) : []),
    [legs, price]
  )
  const summary = React.useMemo(
    () => (chartData.length > 0 ? calcSummary(chartData) : null),
    [chartData]
  )

  const handleSearch = async (sym: string) => {
    setSymbol(sym)
  }

  const handleOcrResult = useCallback((result: OcrResult) => {
    // 自動填入 symbol
    if (result.symbol) setSymbol(result.symbol)
    // 自動設定 outlook
    if (result.outlook) setOutlook(result.outlook as MarketOutlook)
    // 若識別到腳位，直接覆蓋 legs
    if (result.legs.length > 0) {
      setLegs(result.legs.map(l => ({
        ...l,
        id:       nextLegId++,
        iv:       l.iv ?? undefined,
        dte:      l.dte ?? undefined,
        quantity: l.quantity,
      } as LegRow)))
      setActiveTab('custom')
    }
  }, [])

  return (
    <div className="flex flex-col h-full min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-4 py-3 flex flex-col gap-2">
        <h1 className="text-base font-bold text-gray-800">美股期權分析</h1>
        <SymbolBar symbol={symbol} price={price} loading={loading} onSearch={handleSearch} />
        {error && <p className="text-xs text-red-500">{error}</p>}
      </div>

      {/* Body：5 欄 */}
      <div className="flex flex-1 overflow-hidden">

        {/* Col 1：Outlook + Sentiment */}
        <div className="w-64 flex-shrink-0 border-r border-gray-200 overflow-y-auto p-3 flex flex-col gap-3 bg-white">
          <OutlookSelector value={outlook} onChange={setOutlook} />
          <SentimentPanel sentiment={sentiment} ivRank={ivRank} />
        </div>

        {/* Col 2：策略列表 */}
        <div className="w-52 flex-shrink-0 border-r border-gray-100 overflow-y-auto bg-white flex flex-col">
          <div className="flex border-b border-gray-100">
            <button
              onClick={() => setActiveTab('recommend')}
              className={`flex-1 py-2 text-xs font-medium transition-colors ${
                activeTab === 'recommend'
                  ? 'bg-blue-50 text-blue-700 border-b-2 border-blue-600'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              推薦策略
            </button>
            <button
              onClick={() => setActiveTab('custom')}
              className={`flex-1 py-2 text-xs font-medium transition-colors ${
                activeTab === 'custom'
                  ? 'bg-blue-50 text-blue-700 border-b-2 border-blue-600'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              自訂腳位
            </button>
          </div>
          <div className="p-2 flex-1 overflow-y-auto">
            {activeTab === 'recommend' ? (
              <StrategyRecommendList
                strategies={strategies}
                selectedIdx={selectedIdx}
                onSelect={handleSelectStrategy}
              />
            ) : (
              <LegEditor
                legs={legs}
                onAdd={handleAddLeg}
                onRemove={handleRemoveLeg}
                onChange={handleChangeLeg}
              />
            )}
          </div>
        </div>

        {/* Col 3：策略解說（7 個區塊）*/}
        <div className="w-72 flex-shrink-0 border-r border-gray-100 overflow-y-auto p-4 bg-white">
          <StrategyDetailPanel
            template={strategies[selectedIdx] ?? null}
            legs={legs as import('./types').PayoffLeg[]}
            price={price}
            summary={summary}
          />
        </div>

        {/* Col 4：損益圖 */}
        <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-3 min-w-0">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">損益圖</p>
          <PayoffChart data={chartData} summary={summary} price={price} />
        </div>

        {/* Col 5：截圖上傳（右側常駐，大型拖曳區）*/}
        <div className="w-56 flex-shrink-0 border-l border-gray-200 bg-gray-50 flex flex-col">
          <div className="px-3 pt-3 pb-1">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">截圖分析</p>
          </div>
          <div className="flex-1 overflow-hidden">
            <ImageUploadZone onResult={handleOcrResult} />
          </div>
        </div>

      </div>
    </div>
  )
}

import React, { useRef, useState, useCallback } from 'react'

export interface OcrResult {
  symbol:         string
  price:          number | null
  iv_rank:        number | null
  outlook:        'bullish' | 'bearish' | 'neutral' | 'volatile'
  outlook_reason: string
  legs: Array<{
    type:     string
    strike:   number
    premium:  number
    quantity: number
    dte:      number | null
    iv:       number | null
  }>
  strategy_hint:  string
  recommendation: string
  confidence:     'high' | 'medium' | 'low'
  notes:          string
}

interface Props {
  onResult: (result: OcrResult) => void
}

const CONF_COLOR: Record<string, string> = {
  high:   '#16a34a',
  medium: '#d97706',
  low:    '#dc2626',
}
const CONF_LABEL: Record<string, string> = {
  high: '高信心', medium: '中信心', low: '低信心',
}

function ResultCard({ result, onClose }: { result: OcrResult; onClose: () => void }) {
  return (
    <div className="mt-3 bg-white rounded-xl border border-blue-200 shadow-sm p-3 text-sm relative">
      <button
        onClick={onClose}
        className="absolute top-2 right-2 text-gray-300 hover:text-gray-500 text-lg leading-none"
      >
        ×
      </button>

      {/* Header */}
      <div className="flex items-center gap-2 mb-2 flex-wrap">
        {result.symbol && (
          <span className="font-bold text-base text-gray-800">{result.symbol}</span>
        )}
        {result.price != null && (
          <span className="text-gray-500">${result.price.toFixed(2)}</span>
        )}
        <span
          className="text-xs px-2 py-0.5 rounded-full font-medium"
          style={{ background: '#eff6ff', color: '#1d4ed8' }}
        >
          {result.outlook === 'bullish' ? '看多'
            : result.outlook === 'bearish' ? '看空'
            : result.outlook === 'volatile' ? '大波動'
            : '中性'}
        </span>
        <span
          className="text-xs px-2 py-0.5 rounded-full font-medium"
          style={{ background: '#f9fafb', color: CONF_COLOR[result.confidence] }}
        >
          {CONF_LABEL[result.confidence]}
        </span>
        {result.strategy_hint && (
          <span className="text-xs px-2 py-0.5 rounded-full bg-purple-50 text-purple-700 font-medium">
            {result.strategy_hint}
          </span>
        )}
      </div>

      {/* Outlook reason */}
      {result.outlook_reason && (
        <p className="text-xs text-gray-500 mb-2">{result.outlook_reason}</p>
      )}

      {/* Identified legs */}
      {result.legs.length > 0 && (
        <div className="mb-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-1">識別到的期權腳位</p>
          <div className="flex flex-wrap gap-1">
            {result.legs.map((l, i) => (
              <span
                key={i}
                className="text-xs px-2 py-0.5 rounded-full border font-mono"
                style={{
                  color: l.type.startsWith('short') ? '#dc2626' : '#16a34a',
                  borderColor: l.type.startsWith('short') ? '#fca5a5' : '#86efac',
                  background: '#f9fafb',
                }}
              >
                {l.quantity > 1 ? `${l.quantity}x ` : ''}
                {l.type.replace('_', ' ')} ${l.strike} @ ${l.premium.toFixed(2)}
                {l.dte ? ` (${l.dte}天)` : ''}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Recommendation */}
      {result.recommendation && (
        <div className="bg-blue-50 rounded-lg p-2 mb-2">
          <p className="text-xs font-semibold text-blue-600 mb-0.5">操作建議</p>
          <p className="text-xs text-blue-800 leading-relaxed">{result.recommendation}</p>
        </div>
      )}

      {/* Notes */}
      {result.notes && (
        <p className="text-xs text-gray-400">{result.notes}</p>
      )}
    </div>
  )
}

export default function ImageUploadZone({ onResult }: Props) {
  const inputRef  = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)
  const [loading,  setLoading]  = useState(false)
  const [error,    setError]    = useState('')
  const [preview,  setPreview]  = useState<string | null>(null)
  const [result,   setResult]   = useState<OcrResult | null>(null)

  const handleFile = useCallback(async (file: File) => {
    if (!file.type.startsWith('image/')) {
      setError('請上傳圖片（JPG / PNG / WebP）')
      return
    }

    setError('')
    setResult(null)
    setPreview(URL.createObjectURL(file))
    setLoading(true)

    const form = new FormData()
    form.append('image', file)

    try {
      const res  = await fetch('/api/v1/options/analyze_image', { method: 'POST', body: form })
      const data = await res.json() as OcrResult & { error?: string }
      if (!res.ok) throw new Error(data.error ?? '分析失敗')
      setResult(data)
      onResult(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : '分析失敗，請重試')
    } finally {
      setLoading(false)
    }
  }, [onResult])

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files[0]
    if (file) handleFile(file)
  }

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) handleFile(file)
    e.target.value = ''
  }

  return (
    <div className="w-full">
      {/* Drop zone / button */}
      <div
        onDragOver={e => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => inputRef.current?.click()}
        className="flex items-center gap-2 cursor-pointer select-none"
        title="點擊或拖曳圖片至此"
      >
        <div
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg border-2 border-dashed text-xs font-medium transition-all ${
            dragging
              ? 'border-blue-400 bg-blue-50 text-blue-600'
              : loading
              ? 'border-gray-200 bg-gray-50 text-gray-400'
              : 'border-gray-300 bg-white text-gray-500 hover:border-blue-300 hover:text-blue-500'
          }`}
        >
          {loading ? (
            <>
              <span className="animate-spin">⟳</span>
              <span>AI 分析中…</span>
            </>
          ) : preview ? (
            <>
              <img src={preview} className="w-5 h-5 rounded object-cover" alt="preview" />
              <span>重新上傳</span>
            </>
          ) : (
            <>
              <span>📸</span>
              <span>{dragging ? '放開以分析' : '上傳截圖'}</span>
            </>
          )}
        </div>
      </div>

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={onInputChange}
      />

      {error && (
        <p className="text-xs text-red-500 mt-1">{error}</p>
      )}

      {result && (
        <ResultCard result={result} onClose={() => { setResult(null); setPreview(null) }} />
      )}
    </div>
  )
}

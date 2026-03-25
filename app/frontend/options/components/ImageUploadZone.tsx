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
const OUTLOOK_LABEL: Record<string, string> = {
  bullish: '看多 📈', bearish: '看空 📉',
  volatile: '大波動 ⚡', neutral: '中性 ↔',
}

function ResultCard({ result, onReset }: { result: OcrResult; onReset: () => void }) {
  return (
    <div className="flex flex-col gap-3 animate-fade-in">
      {/* 標題列 */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 flex-wrap">
          {result.symbol && (
            <span className="font-bold text-lg text-gray-800">{result.symbol}</span>
          )}
          {result.price != null && (
            <span className="text-gray-500 text-sm">${result.price.toFixed(2)}</span>
          )}
          <span className="text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 font-medium">
            {OUTLOOK_LABEL[result.outlook] ?? result.outlook}
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
        <button
          onClick={onReset}
          className="text-xs text-gray-400 hover:text-gray-600 px-2 py-1 rounded hover:bg-gray-100 transition-colors flex-shrink-0"
        >
          重新上傳
        </button>
      </div>

      {/* Outlook reason */}
      {result.outlook_reason && (
        <p className="text-xs text-gray-500 leading-relaxed">{result.outlook_reason}</p>
      )}

      {/* 識別到的腳位 */}
      {result.legs.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-1.5">
            識別到的期權腳位
          </p>
          <div className="flex flex-col gap-1">
            {result.legs.map((l, i) => (
              <div
                key={i}
                className="flex items-center gap-2 text-xs px-2 py-1 rounded-lg border"
                style={{
                  borderColor: l.type.startsWith('short') ? '#fca5a5' : '#86efac',
                  background:  l.type.startsWith('short') ? '#fff5f5' : '#f0fdf4',
                }}
              >
                <span
                  className="font-semibold"
                  style={{ color: l.type.startsWith('short') ? '#dc2626' : '#16a34a' }}
                >
                  {l.type.replace('_', ' ').replace(/\b\w/g, c => c.toUpperCase())}
                </span>
                <span className="text-gray-600">Strike ${l.strike}</span>
                <span className="text-gray-400">@</span>
                <span className="font-mono text-gray-700">${l.premium.toFixed(2)}</span>
                {l.dte   != null && <span className="text-gray-400">{l.dte}天</span>}
                {l.iv    != null && <span className="text-gray-400">IV {(l.iv * 100).toFixed(0)}%</span>}
                {l.quantity > 1  && <span className="text-gray-400">×{l.quantity}</span>}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* 操作建議 */}
      {result.recommendation && (
        <div className="bg-gradient-to-br from-blue-50 to-indigo-50 rounded-xl p-3 border border-blue-100">
          <p className="text-xs font-semibold text-blue-600 mb-1">💡 AI 操作建議</p>
          <p className="text-sm text-blue-900 leading-relaxed">{result.recommendation}</p>
        </div>
      )}

      {/* 補充說明 */}
      {result.notes && (
        <p className="text-xs text-gray-400 leading-relaxed">{result.notes}</p>
      )}
    </div>
  )
}

export default function ImageUploadZone({ onResult }: Props) {
  const inputRef   = useRef<HTMLInputElement>(null)
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
      setPreview(null)
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

  const reset = () => {
    setResult(null)
    setPreview(null)
    setError('')
  }

  // ── 有結果時顯示結果卡片 ────────────────────────────────────────────────────
  if (result) {
    return (
      <div className="flex flex-col h-full overflow-y-auto p-4">
        <ResultCard result={result} onReset={reset} />
      </div>
    )
  }

  // ── 分析中 ──────────────────────────────────────────────────────────────────
  if (loading && preview) {
    return (
      <div className="flex flex-col h-full items-center justify-center gap-4 p-4">
        <img src={preview} className="max-h-40 rounded-xl shadow object-contain" alt="preview" />
        <div className="flex flex-col items-center gap-2">
          <div className="w-8 h-8 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-gray-500 font-medium">EasyOCR 識別中…</p>
          <p className="text-xs text-gray-400">接著由 Groq 解讀，約需 10–20 秒</p>
        </div>
      </div>
    )
  }

  // ── 預設：大型拖曳區 ────────────────────────────────────────────────────────
  return (
    <div
      className="flex flex-col h-full"
      onDragOver={e => { e.preventDefault(); setDragging(true) }}
      onDragLeave={e => {
        // 只在真正離開整個區域時重置（避免子元素觸發）
        if (!e.currentTarget.contains(e.relatedTarget as Node)) setDragging(false)
      }}
      onDrop={onDrop}
    >
      <div
        onClick={() => inputRef.current?.click()}
        className={`
          flex-1 flex flex-col items-center justify-center gap-5 m-3 rounded-2xl
          border-2 border-dashed cursor-pointer transition-all duration-200
          ${dragging
            ? 'border-blue-400 bg-blue-50 scale-[0.99]'
            : 'border-gray-300 bg-gray-50 hover:border-blue-300 hover:bg-blue-50/40'
          }
        `}
      >
        {/* Icon */}
        <div
          className={`
            w-20 h-20 rounded-2xl flex items-center justify-center text-4xl
            transition-all duration-200 shadow-sm
            ${dragging ? 'bg-blue-100 scale-110' : 'bg-white'}
          `}
        >
          {dragging ? '📂' : '📸'}
        </div>

        {/* 文字說明 */}
        <div className="text-center px-4">
          <p className={`text-base font-semibold mb-1 transition-colors ${dragging ? 'text-blue-600' : 'text-gray-600'}`}>
            {dragging ? '放開以分析圖片' : '拖曳截圖至此'}
          </p>
          <p className="text-sm text-gray-400">
            或點擊選擇檔案
          </p>
          <p className="text-xs text-gray-300 mt-2">
            支援 JPG · PNG · WebP
          </p>
        </div>

        {/* 適用場景提示 */}
        {!dragging && (
          <div className="flex flex-wrap justify-center gap-2 px-4">
            {['券商期權鏈', '股價圖表', 'K 線圖', 'P&L 截圖'].map(tag => (
              <span
                key={tag}
                className="text-xs px-2.5 py-1 bg-white rounded-full border border-gray-200 text-gray-400 shadow-sm"
              >
                {tag}
              </span>
            ))}
          </div>
        )}
      </div>

      {error && (
        <p className="text-xs text-red-500 text-center pb-2">{error}</p>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={e => {
          const file = e.target.files?.[0]
          if (file) handleFile(file)
          e.target.value = ''
        }}
      />
    </div>
  )
}

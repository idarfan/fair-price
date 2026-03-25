import React from 'react'
import type { StrategyTemplate, PayoffSummary, PayoffLeg } from '../types'

interface Props {
  template: StrategyTemplate | null
  legs:     PayoffLeg[]
  price:    number
  summary:  PayoffSummary | null
}

// ─── 格式化工具 ───────────────────────────────────────────────────────────────

function fmt(n: number, decimals = 2): string {
  if (!isFinite(n) || Math.abs(n) > 999_999) return n > 0 ? '無限' : '−無限'
  const sign = n >= 0 ? '+' : ''
  return `${sign}$${Math.abs(n).toFixed(decimals)}`
}

function fmtMoney(n: number): string {
  if (!isFinite(n) || Math.abs(n) > 999_999) return n > 0 ? '無限' : '−無限'
  return `$${Math.abs(n).toFixed(2)}`
}

// ─── 區塊元件 ─────────────────────────────────────────────────────────────────

function Block({
  icon, title, children, accent,
}: {
  icon: string; title: string; children: React.ReactNode; accent?: string
}) {
  return (
    <div className="flex gap-3">
      <div
        className="flex-shrink-0 w-8 h-8 rounded-lg flex items-center justify-center text-base"
        style={{ background: accent ?? '#f1f5f9' }}
      >
        {icon}
      </div>
      <div className="flex-1 min-w-0 overflow-hidden">
        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-0.5">{title}</p>
        <div className="text-sm text-gray-700 leading-relaxed break-words">{children}</div>
      </div>
    </div>
  )
}

// ─── 損益腿位摘要 ─────────────────────────────────────────────────────────────

const LEG_LABELS: Record<string, string> = {
  long_call: 'Long Call', short_call: 'Short Call',
  long_put: 'Long Put',   short_put: 'Short Put',
  long_stock: '買股',     short_stock: '賣股',
}
const TYPE_COLOR: Record<string, string> = {
  long_call: '#16a34a', short_call: '#dc2626',
  long_put:  '#dc2626', short_put:  '#16a34a',
}

function LegsRow({ legs }: { legs: PayoffLeg[] }) {
  if (!legs.length) return null
  return (
    <div className="flex flex-wrap gap-2">
      {legs.map((l, i) => (
        <span
          key={i}
          className="text-xs px-2 py-0.5 rounded-full border font-mono"
          style={{
            color:       TYPE_COLOR[l.type] ?? '#374151',
            borderColor: TYPE_COLOR[l.type] ?? '#d1d5db',
            background:  '#f9fafb',
          }}
        >
          {l.quantity > 1 ? `${l.quantity}x ` : ''}
          {LEG_LABELS[l.type] ?? l.type} ${l.strike.toFixed(l.strike < 20 ? 2 : 0)}
          {' '}@ ${l.premium.toFixed(2)}
        </span>
      ))}
    </div>
  )
}

// ─── 主元件 ───────────────────────────────────────────────────────────────────

export default function StrategyDetailPanel({ template, legs, price, summary }: Props) {
  if (!template) {
    return (
      <p className="text-sm text-gray-400 py-6 text-center">選擇策略後查看詳細解說</p>
    )
  }

  const detail = template.detail

  // 動態計算損益數字
  const netPremium = legs.reduce((sum, l) => {
    const sign = l.type.startsWith('short') ? 1 : -1
    return sum + sign * l.premium * l.quantity
  }, 0)
  const netPremiumPer100 = netPremium * 100

  const maxProfitVal = summary?.maxProfit ?? 0
  const maxLossVal   = summary?.maxLoss   ?? 0
  const bes          = summary?.breakevens ?? []

  return (
    <div className="flex flex-col gap-4 min-w-0">
      {/* Header */}
      <div className="min-w-0">
        <div className="flex items-center gap-2 mb-1 flex-wrap">
          <h2 className="text-sm font-bold text-gray-800 break-words">{template.name}</h2>
          <span
            className="text-xs px-2 py-0.5 rounded-full font-medium"
            style={{
              background: template.credit ? '#dcfce7' : '#fef3c7',
              color:       template.credit ? '#166534' : '#92400e',
            }}
          >
            {template.credit ? 'Credit（收 Premium）' : 'Debit（付 Premium）'}
          </span>
        </div>
        <LegsRow legs={legs} />
      </div>

      <div className="border-t border-gray-100" />

      {/* Block 1: 這是什麼 */}
      <Block icon="📘" title="這是什麼" accent="#eff6ff">
        {detail?.what ?? template.desc}
      </Block>

      {/* Block 2: 什麼時候用 */}
      <Block icon="🎯" title="什麼時候用" accent="#f0fdf4">
        {detail?.when ?? `DTE ${template.dte}，Delta ${template.delta}`}
      </Block>

      {/* Block 3: 最大獲利 */}
      <Block icon="💰" title="最大獲利" accent="#dcfce7">
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className="text-xl font-bold text-green-600">
            {fmtMoney(maxProfitVal)}
          </span>
          <span className="text-gray-400 text-xs">/ 組（現價 ${price.toFixed(2)}，{legs[0]?.dte ?? 35} 天到期）</span>
        </div>
        <p className="text-xs text-gray-500 mt-0.5">{template.maxProfit}</p>
        {template.credit && netPremiumPer100 !== 0 && (
          <p className="text-xs text-green-600 mt-0.5">
            淨收入 Premium：{fmt(netPremium, 2)} = ${Math.abs(netPremiumPer100).toFixed(0)} / contract
          </p>
        )}
      </Block>

      {/* Block 4: 最大虧損 */}
      <Block icon="⚠️" title="最大虧損" accent="#fee2e2">
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className="text-xl font-bold text-red-600">
            {isFinite(maxLossVal) && Math.abs(maxLossVal) < 999999
              ? fmtMoney(Math.abs(maxLossVal))
              : '無限（需主動管理）'}
          </span>
          <span className="text-gray-400 text-xs">/ 組</span>
        </div>
        <p className="text-xs text-gray-500 mt-0.5">{template.risk}</p>
      </Block>

      {/* Block 5: Break-even */}
      <Block icon="⚖️" title="損益兩平價（Break-even）" accent="#fef3c7">
        {bes.length > 0 ? (
          <div className="flex gap-3 flex-wrap">
            {bes.map((b, i) => (
              <span key={i} className="font-bold text-amber-700">${b.toFixed(2)}</span>
            ))}
            {bes.length === 1 && (
              <span className="text-xs text-gray-500 self-end">
                （距現價 {((bes[0] - price) / price * 100).toFixed(1)}%）
              </span>
            )}
            {bes.length === 2 && (
              <span className="text-xs text-gray-500 self-end">
                （盈利走廊寬 {(bes[1] - bes[0]).toFixed(2)}）
              </span>
            )}
          </div>
        ) : (
          <span className="text-gray-400 text-sm">計算中…</span>
        )}
      </Block>

      {/* Block 6: 主要風險 */}
      <Block icon="🛡️" title="主要風險" accent="#fdf4ff">
        {detail?.risks ?? '注意 Theta 衰減與 IV 變化'}
      </Block>

      {/* Block 7: 實戰應用場景 */}
      <Block icon="🏋️" title="實戰應用場景" accent="#f0f9ff">
        {detail?.scenario ?? `適合 ${template.dte} 的市場環境`}
      </Block>
    </div>
  )
}

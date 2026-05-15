import React from 'react'
import type { StrategyTemplate, PayoffSummary, PayoffLeg } from '../types'
import { calcLegGreeks, calcPositionGreeks } from '../payoff'

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

// ─── 段落元件（以句號分段）───────────────────────────────────────────────────

function Paragraphs({ text }: { text: string }) {
  const parts = text.split(/(?<=。)/).filter(s => s.trim())
  if (parts.length <= 1) {
    return <p className="break-words">{text}</p>
  }
  return (
    <>
      {parts.map((p, i) => (
        <p key={i} className="mb-2 last:mb-0 break-words">{p.trim()}</p>
      ))}
    </>
  )
}

// ─── 區塊元件 ─────────────────────────────────────────────────────────────────

function Block({
  icon, title, children, accent,
}: {
  icon: string; title: string; children: React.ReactNode; accent?: string
}) {
  return (
    <div
      className="border-l-4 pl-3 rounded-sm"
      style={{ borderLeftColor: accent ?? '#e2e8f0' }}
    >
      <p className="text-sm font-semibold text-gray-500 uppercase tracking-wider mb-1">
        <span className="mr-1.5">{icon}</span>{title}
      </p>
      <div className="text-sm text-gray-700 leading-relaxed break-words">{children}</div>
    </div>
  )
}

// ─── Tooltip ─────────────────────────────────────────────────────────────────

function Tooltip({ content }: { content: string }) {
  return (
    <span className="group relative inline-block align-middle">
      <span className="ml-1 cursor-help inline-flex items-center justify-center w-4 h-4 rounded-full border border-gray-300 text-gray-400 text-xs hover:border-gray-500 hover:text-gray-600 select-none">?</span>
      <span className="pointer-events-none absolute bottom-full left-1/2 -translate-x-1/2 mb-2 w-64 rounded-xl bg-gray-900 text-white text-xs px-3 py-2.5 leading-relaxed shadow-xl opacity-0 group-hover:opacity-100 transition-opacity z-50 whitespace-normal">
        {content}
        <span className="absolute top-full left-1/2 -translate-x-1/2 border-4 border-transparent border-t-gray-900" />
      </span>
    </span>
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

function LegsRow({ legs, price }: { legs: PayoffLeg[]; price: number }) {
  if (!legs.length) return null
  return (
    <div className="flex flex-col gap-1.5">
      {legs.map((l, i) => {
        const greeks = calcLegGreeks(l, price)
        return (
          <div
            key={i}
            className="flex items-center gap-2 text-xs font-mono px-2 py-1 rounded-lg border"
            style={{
              color:       TYPE_COLOR[l.type] ?? '#374151',
              borderColor: TYPE_COLOR[l.type] ?? '#d1d5db',
              background:  '#f9fafb',
            }}
          >
            <span className="font-semibold">
              {l.quantity > 1 ? `${l.quantity}x ` : ''}
              {LEG_LABELS[l.type] ?? l.type} ${l.strike.toFixed(l.strike < 20 ? 2 : 0)}
              {' '}@ ${l.premium.toFixed(2)}
            </span>
            {greeks && (
              <span className="text-gray-500 font-normal">
                Delta {greeks.delta > 0 ? '+' : ''}{greeks.delta.toFixed(2)}
                {' · '}IV {(greeks.iv * 100).toFixed(0)}%
                {' · '}Theta {greeks.theta > 0 ? '+' : ''}{greeks.theta.toFixed(1)}/日
              </span>
            )}
          </div>
        )
      })}
    </div>
  )
}

// ─── 主元件 ───────────────────────────────────────────────────────────────────

export default function StrategyDetailPanel({ template, legs, price, summary }: Props) {
  if (!template) {
    return (
      <p className="text-base text-gray-400 py-6 text-center">選擇策略後查看詳細解說</p>
    )
  }

  const detail = template.detail

  const netPremium = legs.reduce((sum, l) => {
    const sign = l.type.startsWith('short') ? 1 : -1
    return sum + sign * l.premium * l.quantity
  }, 0)
  const netPremiumPer100 = netPremium * 100

  const maxProfitVal = summary?.maxProfit ?? 0
  const maxLossVal   = summary?.maxLoss   ?? 0
  const bes          = summary?.breakevens ?? []

  return (
    <div className="flex flex-col gap-6 min-w-0">
      {/* Header */}
      <div className="min-w-0">
        <div className="flex items-center gap-2 mb-2 flex-wrap">
          <h2 className="text-lg font-bold text-gray-800 break-words">{template.name}</h2>
          <span
            className="text-xs px-2.5 py-1 rounded-full font-medium"
            style={{
              background: template.credit ? '#dcfce7' : '#fef3c7',
              color:       template.credit ? '#166534' : '#92400e',
            }}
          >
            {template.credit ? 'Credit（收 Premium）' : 'Debit（付 Premium）'}
          </span>
        </div>
        <LegsRow legs={legs} price={price} />
      </div>

      <div className="border-t border-gray-200" />

      {/* Block 1: 這是什麼 */}
      <Block icon="📘" title="這是什麼" accent="#93c5fd">
        <Paragraphs text={detail?.what ?? template.desc} />
      </Block>

      {/* Block 2: 什麼時候用 */}
      <Block icon="🎯" title="什麼時候用" accent="#86efac">
        <Paragraphs text={detail?.when ?? `DTE ${template.dte}，Delta ${template.delta}`} />
      </Block>

      {/* Block 3: 最大獲利 */}
      <Block icon="💰" title="最大獲利" accent="#4ade80">
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className="text-2xl font-bold text-green-600">
            {fmtMoney(maxProfitVal)}
          </span>
          <span className="text-gray-400 text-sm">/ 組（現價 ${price.toFixed(2)}，{legs[0]?.dte ?? 35} 天到期）</span>
        </div>
        <p className="text-sm text-gray-500 mt-1">{template.maxProfit}</p>
        {template.credit && netPremiumPer100 !== 0 && (
          <p className="text-sm text-green-600 mt-1">
            淨收入 Premium：{fmt(netPremium, 2)} = ${Math.abs(netPremiumPer100).toFixed(0)} / contract
          </p>
        )}
      </Block>

      {/* Block 4: 最大虧損 */}
      <Block icon="⚠️" title="最大虧損" accent="#f87171">
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className="text-2xl font-bold text-red-600">
            {isFinite(maxLossVal) && Math.abs(maxLossVal) < 999999
              ? fmtMoney(Math.abs(maxLossVal))
              : '無限（需主動管理）'}
          </span>
          <span className="text-gray-400 text-sm">/ 組</span>
        </div>
        <p className="text-sm text-gray-500 mt-1">{template.risk}</p>
      </Block>

      {/* Block 5: Break-even */}
      <Block icon="⚖️" title="損益兩平價（Break-even）" accent="#fbbf24">
        {bes.length > 0 ? (
          <div className="flex gap-3 flex-wrap items-baseline">
            {bes.map((b, i) => (
              <span key={i} className="text-xl font-bold text-amber-700">${b.toFixed(2)}</span>
            ))}
            {bes.length === 1 && (
              <span className="text-sm text-gray-500">
                （距現價 {((bes[0] - price) / price * 100).toFixed(1)}%）
              </span>
            )}
            {bes.length === 2 && (
              <span className="text-sm text-gray-500">
                （盈利走廊寬 {(bes[1] - bes[0]).toFixed(2)}）
              </span>
            )}
          </div>
        ) : (
          <span className="text-gray-400 text-base">計算中…</span>
        )}
      </Block>

      {/* Block 5.5: Greeks 摘要 */}
      {(() => {
        const greeks = calcPositionGreeks(legs, price)
        if (greeks.netDelta === 0 && greeks.netTheta === 0) return null
        const deltaPerPoint = Math.abs(greeks.netDelta * 100).toFixed(2)
        const theta7d  = (greeks.netTheta * 7).toFixed(2)
        const theta30d = (greeks.netTheta * 30).toFixed(2)
        return (
          <Block icon="📊" title="Greeks 摘要" accent="#a78bfa">
            <div className="flex gap-3 flex-wrap mb-3">

              {/* Delta card */}
              <div className="flex-1 min-w-36 bg-gray-50 rounded-lg px-3 py-2.5 border border-gray-100">
                <div className="flex items-center gap-0.5 mb-1">
                  <span className="text-xs text-gray-500 font-medium">淨 Delta</span>
                  <Tooltip content="股價每變動 $1，整組倉位的理論損益變化。正值 = 偏多頭（股票漲你賺）；負值 = 偏空頭（股票跌你賺）。絕對值越大方向風險越高；接近 0 為 Delta 中性。還需考慮 Gamma：Delta 本身也會隨股價移動而改變。" />
                </div>
                <div className={`text-xl font-bold leading-none mb-1.5 ${greeks.netDelta > 0 ? 'text-green-600' : greeks.netDelta < 0 ? 'text-red-600' : 'text-gray-600'}`}>
                  {greeks.netDelta > 0 ? '+' : ''}{greeks.netDelta.toFixed(2)}
                </div>
                <p className="text-xs text-gray-600">
                  股票每 ±$1 → 組合 {greeks.netDelta >= 0 ? '+' : '−'}${deltaPerPoint}
                </p>
                <p className="text-xs text-gray-400 mt-0.5">
                  {greeks.netDelta > 0.2 ? '↑ 明顯偏多頭，方向風險高' :
                   greeks.netDelta > 0.05 ? '↑ 輕微偏多頭' :
                   greeks.netDelta < -0.2 ? '↓ 明顯偏空頭，方向風險高' :
                   greeks.netDelta < -0.05 ? '↓ 輕微偏空頭' :
                   '≈ 接近 Delta 中性'}
                </p>
              </div>

              {/* Theta card */}
              <div className="flex-1 min-w-36 bg-gray-50 rounded-lg px-3 py-2.5 border border-gray-100">
                <div className="flex items-center gap-0.5 mb-1">
                  <span className="text-xs text-gray-500 font-medium">每日 Theta</span>
                  <Tooltip content="每過一天，整組倉位因時間價值耗損產生的損益（按 1 張 contract 計）。正值 = 時間是你的朋友（賣方收租）；負值 = 每天付出時間成本（買方）。越接近到期日耗損加速，OTM 期權在最後一週可能一夜變廢紙。" />
                </div>
                <div className={`text-xl font-bold leading-none mb-1.5 ${greeks.netTheta > 0 ? 'text-green-600' : 'text-red-600'}`}>
                  {greeks.netTheta > 0 ? '+' : ''}${greeks.netTheta.toFixed(2)}
                </div>
                <p className="text-xs text-gray-600">
                  7 天累積 {greeks.netTheta >= 0 ? '+' : ''}${theta7d} ／ 30 天 {greeks.netTheta >= 0 ? '+' : ''}${theta30d}
                </p>
                <p className="text-xs text-gray-400 mt-0.5">
                  {greeks.netTheta > 0 ? '⏱ 時間流逝對你有利（賣方收租）' : '⏱ 時間流逝對你不利（買方付費）'}
                </p>
              </div>
            </div>

            {/* 策略影響說明 */}
            <div className="text-xs text-gray-700 leading-relaxed bg-purple-50 rounded-lg px-3 py-2.5 border border-purple-100">
              <span className="font-medium text-purple-800">影響說明：</span>
              {greeks.netDelta > 0.1
                ? `股票每漲 $1，組合理論獲利 $${deltaPerPoint}（Delta ${'+'}${greeks.netDelta.toFixed(2)}）；若股票下跌則反向虧損。`
                : greeks.netDelta < -0.1
                ? `股票每跌 $1，組合理論獲利 $${deltaPerPoint}（Delta ${greeks.netDelta.toFixed(2)}）；若股票上漲則反向虧損。`
                : `部位接近 Delta 中性（${greeks.netDelta > 0 ? '+' : ''}${greeks.netDelta.toFixed(2)}），方向風險低，股價小幅波動影響有限。`
              }
              {greeks.netTheta > 0
                ? ` Theta 每日為你產生 $${greeks.netTheta.toFixed(2)} 時間租金，7 天可積累 $${theta7d}，即使股票不動也有收益。`
                : ` Theta 每日耗損 $${Math.abs(greeks.netTheta).toFixed(2)}，7 天損耗 $${Math.abs(parseFloat(theta7d)).toFixed(2)}，須讓標的在到期前到位。`
              }
            </div>
          </Block>
        )
      })()}

      {/* Block 6: 主要風險 */}
      <Block icon="🛡️" title="主要風險" accent="#c084fc">
        <Paragraphs text={detail?.risks ?? '注意 Theta 衰減與 IV 變化'} />
      </Block>

      {/* Block 7: 實戰應用場景 */}
      <Block icon="🏋️" title="實戰應用場景" accent="#38bdf8">
        <Paragraphs text={detail?.scenario ?? `適合 ${template.dte} 的市場環境`} />
      </Block>
    </div>
  )
}

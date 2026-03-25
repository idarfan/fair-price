import React from 'react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell
} from 'recharts'
import type { SentimentData, IvRankData } from '../types'

interface Props {
  sentiment: SentimentData | null
  ivRank:    IvRankData | null
}

function IvRankBar({ rank }: { rank: number }) {
  const pct   = Math.min(Math.max(rank, 0), 100)
  const color = pct >= 50 ? '#ef4444' : '#22c55e'
  const label = pct >= 75 ? 'IV 偏高（賣方有利）'
              : pct >= 50 ? 'IV 中高'
              : pct >= 25 ? 'IV 中低'
              : 'IV 偏低（買方有利）'

  return (
    <div>
      <div className="flex justify-between text-xs mb-1">
        <span className="text-gray-400">IV Rank</span>
        <span className="font-semibold" style={{ color }}>{pct.toFixed(0)}</span>
      </div>
      <div className="relative h-3 rounded-full bg-gray-200">
        <div
          className="absolute h-3 rounded-full transition-all"
          style={{ width: `${pct}%`, background: color }}
        />
      </div>
      <p className="text-xs mt-1" style={{ color }}>{label}</p>
    </div>
  )
}

function PcRatioGauge({ ratio, sentiment }: { ratio: number | null; sentiment: string }) {
  if (ratio === null) return <p className="text-xs text-gray-400">P/C Ratio 無資料</p>
  const color = ratio > 1.2 ? '#ef4444' : ratio < 0.8 ? '#22c55e' : '#6b7280'
  return (
    <div>
      <div className="flex justify-between text-xs mb-0.5">
        <span className="text-gray-400">P/C Ratio</span>
        <span className="font-semibold" style={{ color }}>{ratio.toFixed(2)}</span>
      </div>
      <p className="text-xs" style={{ color }}>{sentiment}</p>
    </div>
  )
}

function IvSkewRow({
  skew, otmPut, otmCall, comment
}: { skew: number | null; otmPut: number | null; otmCall: number | null; comment: string }) {
  // skew is in decimal form (e.g. 0.14 = 14 pp difference)
  const pct   = skew !== null ? skew * 100 : null
  const color = (pct ?? 0) > 5 ? '#ef4444' : (pct ?? 0) < -5 ? '#22c55e' : '#6b7280'
  return (
    <div>
      <div className="flex justify-between text-xs mb-0.5">
        <span className="text-gray-400">IV Skew（Put − Call）</span>
        <span className="font-semibold" style={{ color }}>
          {pct !== null ? `${pct > 0 ? '+' : ''}${pct.toFixed(1)}%` : 'N/A'}
        </span>
      </div>
      <div className="flex gap-3 text-xs text-gray-400">
        {otmPut  !== null && <span>OTM Put IV: <span className="text-gray-600">{(otmPut * 100).toFixed(1)}%</span></span>}
        {otmCall !== null && <span>OTM Call IV: <span className="text-gray-600">{(otmCall * 100).toFixed(1)}%</span></span>}
      </div>
      <p className="text-xs mt-0.5" style={{ color }}>{comment}</p>
    </div>
  )
}

function OiChart({ data }: { data: { strike: number; call_oi: number; put_oi: number }[] }) {
  if (!data.length) return null
  const maxOI = Math.max(...data.flatMap(d => [d.call_oi, d.put_oi]))
  const callWall = data.reduce((m, d) => d.call_oi > m.call_oi ? d : m, data[0])
  const putWall  = data.reduce((m, d) => d.put_oi  > m.put_oi  ? d : m, data[0])

  return (
    <div>
      <div className="flex gap-4 text-xs mb-2">
        <span className="flex items-center gap-1">
          <span className="w-2 h-2 rounded-sm inline-block bg-blue-400" />
          Call Wall: <strong>{callWall.strike}</strong>
        </span>
        <span className="flex items-center gap-1">
          <span className="w-2 h-2 rounded-sm inline-block bg-red-400" />
          Put Wall: <strong>{putWall.strike}</strong>
        </span>
      </div>
      <ResponsiveContainer width="100%" height={120}>
        <BarChart data={data} margin={{ top: 0, right: 0, bottom: 0, left: 0 }}>
          <XAxis dataKey="strike" tick={{ fontSize: 9 }} interval="preserveStartEnd" />
          <YAxis hide domain={[0, maxOI * 1.1]} />
          <Tooltip
            content={({ active, payload, label }) => {
              if (!active || !payload?.length) return null
              return (
                <div className="bg-white border border-gray-200 rounded p-2 text-xs shadow">
                  <p className="font-semibold mb-1">Strike {label}</p>
                  {payload.map((p, i) => (
                    <p key={i} style={{ color: p.color }}>
                      {p.dataKey === 'call_oi' ? 'Call OI' : 'Put OI'}：
                      {typeof p.value === 'number' ? p.value.toLocaleString() : p.value}
                    </p>
                  ))}
                </div>
              )
            }}
          />
          <Bar dataKey="call_oi" name="call_oi" fill="#93c5fd" radius={[2, 2, 0, 0]}>
            {data.map((d, i) => (
              <Cell key={i} fill={d.strike === callWall.strike ? '#3b82f6' : '#93c5fd'} />
            ))}
          </Bar>
          <Bar dataKey="put_oi" name="put_oi" fill="#fca5a5" radius={[2, 2, 0, 0]}>
            {data.map((d, i) => (
              <Cell key={i} fill={d.strike === putWall.strike ? '#ef4444' : '#fca5a5'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

function PeerIvTable({ peers }: { peers: IvRankData['peers'] }) {
  if (!peers.length) return null
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-xs">
        <thead>
          <tr className="text-gray-400 border-b border-gray-100">
            <th className="text-left pb-1">同類股</th>
            <th className="text-right pb-1">IV</th>
            <th className="text-right pb-1">IV Rank</th>
          </tr>
        </thead>
        <tbody>
          {peers.map(p => (
            <tr key={p.symbol} className="border-b border-gray-50">
              <td className="py-0.5 font-medium text-gray-700">{p.symbol}</td>
              <td className="text-right text-gray-600">{(p.iv * 100).toFixed(1)}%</td>
              <td className="text-right">
                <span
                  className="px-1.5 py-0.5 rounded text-xs font-medium"
                  style={{
                    background: p.iv_rank >= 50 ? '#fee2e2' : '#dcfce7',
                    color:       p.iv_rank >= 50 ? '#991b1b' : '#166534',
                  }}
                >
                  {p.iv_rank}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default function SentimentPanel({ sentiment, ivRank }: Props) {
  return (
    <div className="flex flex-col gap-4">
      {/* IV Rank */}
      {ivRank && (
        <div className="bg-white rounded-xl p-3 border border-gray-100 shadow-sm flex flex-col gap-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">IV Rank</p>
          <IvRankBar rank={ivRank.iv_rank} />
          <p className="text-xs text-gray-500">{ivRank.iv_comment}</p>
          {ivRank.peers.length > 0 && (
            <>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mt-1">同類股比較</p>
              <PeerIvTable peers={ivRank.peers} />
            </>
          )}
        </div>
      )}

      {/* Sentiment */}
      {sentiment && (
        <div className="bg-white rounded-xl p-3 border border-gray-100 shadow-sm flex flex-col gap-3">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">市場情緒</p>

          <div className="flex justify-between text-xs">
            <span className="text-gray-400">Call 量</span>
            <span className="text-blue-600 font-medium">{sentiment.call_volume.toLocaleString()}</span>
          </div>
          <div className="flex justify-between text-xs -mt-2">
            <span className="text-gray-400">Put 量</span>
            <span className="text-red-500 font-medium">{sentiment.put_volume.toLocaleString()}</span>
          </div>

          <PcRatioGauge ratio={sentiment.pc_ratio} sentiment={sentiment.pc_ratio_sentiment} />
          <IvSkewRow
            skew={sentiment.iv_skew}
            otmPut={sentiment.otm_put_iv}
            otmCall={sentiment.otm_call_iv}
            comment={sentiment.skew_comment}
          />
        </div>
      )}

      {/* OI Distribution */}
      {sentiment && sentiment.oi_distribution.length > 0 && (
        <div className="bg-white rounded-xl p-3 border border-gray-100 shadow-sm">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">OI 分佈（Call vs Put）</p>
          <OiChart data={sentiment.oi_distribution} />
        </div>
      )}
    </div>
  )
}

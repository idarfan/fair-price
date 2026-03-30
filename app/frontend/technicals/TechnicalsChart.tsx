import { useEffect, useState } from 'react'
import {
  ComposedChart, Line, Bar, XAxis, YAxis, Tooltip,
  ResponsiveContainer, ReferenceLine, Cell,
} from 'recharts'

interface DataPoint {
  date: string
  close: number
  volume: number
  ma20: number | null
  ma50: number | null
  rsi14: number | null
  rsi7: number | null
  avg_vol: number
}

interface Stats {
  rsi14: number | null
  rsi7: number | null
  rsi14_label: string
  rsi7_label: string
  ma20_price: number | null
  ma20_dist_pct: number | null
  pos_52w_pct: number
  high_range: number
  low_range: number
  today_vol: number
  avg_vol: number
  vol_ratio_pct: number
  vol_label: string
}

interface SupportResistance {
  support: number[]
  resistance: number[]
}

type Range = '1m' | '3m' | '6m' | '1y'

const RANGES: { key: Range; label: string }[] = [
  { key: '1m', label: '1M' },
  { key: '3m', label: '3M' },
  { key: '6m', label: '6M' },
  { key: '1y', label: '1Y' },
]

function rsiColor(v: number | null): string {
  if (v === null) return '#94a3b8'
  if (v >= 70) return '#f87171'
  if (v <= 30) return '#4ade80'
  if (v >= 50) return '#fbbf24'
  return '#94a3b8'
}

function distColor(v: number | null): string {
  if (v === null) return '#94a3b8'
  return v >= 0 ? '#4ade80' : '#f87171'
}

function fmtVol(v: number): string {
  if (v >= 1e9) return (v / 1e9).toFixed(1) + 'B'
  if (v >= 1e6) return (v / 1e6).toFixed(0) + 'M'
  return (v / 1e3).toFixed(0) + 'K'
}

function StatCard({ label, value, sub, valueColor }: {
  label: string
  value: string
  sub: string
  valueColor?: string
}) {
  return (
    <div style={{ background: '#0f172a', borderRadius: 8, padding: '10px 12px' }}>
      <div style={{ fontSize: 11, color: '#94a3b8', marginBottom: 3 }}>{label}</div>
      <div style={{ fontSize: 15, fontWeight: 500, color: valueColor ?? '#e2e8f0' }}>{value}</div>
      <div style={{ fontSize: 11, color: '#64748b', marginTop: 2 }}>{sub}</div>
    </div>
  )
}

const TICK = { fill: '#64748b', fontSize: 11 }

export default function TechnicalsChart({ symbol }: { symbol: string }) {
  const [range, setRange] = useState<Range>('1m')
  const [data, setData] = useState<DataPoint[]>([])
  const [stats, setStats] = useState<Stats | null>(null)
  const [sr, setSr] = useState<SupportResistance>({ support: [], resistance: [] })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)

  useEffect(() => {
    setLoading(true)
    setError(false)
    fetch(`/api/v1/charts/${encodeURIComponent(symbol)}?range=${range}`)
      .then(r => {
        if (!r.ok) throw new Error('fetch failed')
        return r.json() as Promise<{ data: DataPoint[]; stats: Stats; support_resistance: SupportResistance }>
      })
      .then(json => {
        setData(json.data)
        setStats(json.stats)
        setSr(json.support_resistance ?? { support: [], resistance: [] })
        setLoading(false)
      })
      .catch(() => {
        setError(true)
        setLoading(false)
      })
  }, [symbol, range])

  const volLabel = stats?.vol_label ?? ''
  const volBadgeColor =
    volLabel === '爆量' || volLabel === '放量' ? '#4ade80'
    : volLabel === '縮量' ? '#f87171'
    : '#94a3b8'

  return (
    <div style={{ background: '#1e293b', borderRadius: 12, padding: 16, fontFamily: 'system-ui, sans-serif' }}>

      {/* Range tabs */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 14 }}>
        {RANGES.map(r => (
          <button
            key={r.key}
            onClick={() => setRange(r.key)}
            style={{
              padding: '4px 14px', borderRadius: 6, fontSize: 12, border: 'none', cursor: 'pointer',
              background: range === r.key ? '#3b82f6' : '#0f172a',
              color: range === r.key ? '#fff' : '#94a3b8',
            }}
          >
            {r.label}
          </button>
        ))}
      </div>

      {/* Stat cards */}
      {stats && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 10, marginBottom: 14 }}>
          <StatCard
            label="RSI (14) / (7)"
            value={`${stats.rsi14 ?? '—'} / ${stats.rsi7 ?? '—'}`}
            sub={`${stats.rsi14_label} / ${stats.rsi7_label}`}
            valueColor={rsiColor(stats.rsi14)}
          />
          <StatCard
            label="MA20 距離"
            value={stats.ma20_dist_pct != null ? `${stats.ma20_dist_pct > 0 ? '+' : ''}${stats.ma20_dist_pct}%` : '—'}
            sub={stats.ma20_price != null ? `MA20 = $${stats.ma20_price}` : '—'}
            valueColor={distColor(stats.ma20_dist_pct)}
          />
          <StatCard
            label="52W 位置"
            value={`${stats.pos_52w_pct}%`}
            sub={`$${stats.low_range} — $${stats.high_range}`}
          />
          <StatCard
            label="成交量"
            value={fmtVol(stats.today_vol)}
            sub={`均量 ${fmtVol(stats.avg_vol)}，今日 ${stats.vol_ratio_pct}%`}
            valueColor={stats.vol_ratio_pct >= 130 ? '#4ade80' : stats.vol_ratio_pct <= 60 ? '#f87171' : '#e2e8f0'}
          />
        </div>
      )}

      {loading && (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 380, color: '#64748b', fontSize: 13 }}>
          載入中...
        </div>
      )}

      {error && (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 380, color: '#f87171', fontSize: 13 }}>
          資料載入失敗，請稍後重試
        </div>
      )}

      {!loading && !error && data.length > 0 && (
        <>
          {/* Price chart */}
          <div style={{ fontSize: 11, color: '#94a3b8', marginBottom: 4 }}>收盤價 + MA20 + MA50</div>
          <ResponsiveContainer width="100%" height={220}>
            <ComposedChart data={data} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
              <XAxis dataKey="date" tick={TICK} tickLine={false} minTickGap={40} />
              <YAxis tick={TICK} tickLine={false} axisLine={false} width={52}
                tickFormatter={v => `$${Math.round(v as number)}`} />
              <Tooltip
                contentStyle={{ background: '#1e293b', border: '1px solid #334155', borderRadius: 6, fontSize: 12 }}
                labelStyle={{ color: '#94a3b8' }}
                itemStyle={{ color: '#e2e8f0' }}
                formatter={(v: unknown) => [`$${(v as number).toFixed(2)}`]}
              />
              {sr.support.map(lvl => (
                <ReferenceLine key={`s${lvl}`} y={lvl} stroke="#4ade80" strokeWidth={1}
                  strokeDasharray="6 3"
                  label={{ value: `支 $${lvl}`, position: 'insideTopRight', fill: '#4ade80', fontSize: 10 }} />
              ))}
              {sr.resistance.map(lvl => (
                <ReferenceLine key={`r${lvl}`} y={lvl} stroke="#f87171" strokeWidth={1}
                  strokeDasharray="6 3"
                  label={{ value: `阻 $${lvl}`, position: 'insideBottomRight', fill: '#f87171', fontSize: 10 }} />
              ))}
              <Line dataKey="close" stroke="#60a5fa" strokeWidth={2} dot={false} name="收盤價" />
              <Line dataKey="ma20"  stroke="#fbbf24" strokeWidth={1.5} dot={false} name="MA20" connectNulls />
              <Line dataKey="ma50"  stroke="#f87171" strokeWidth={1.5} dot={false} name="MA50" connectNulls />
            </ComposedChart>
          </ResponsiveContainer>
          <div style={{ display: 'flex', gap: 14, marginTop: 6, marginBottom: 14, fontSize: 11, color: '#94a3b8' }}>
            {[['#60a5fa', '收盤價'], ['#fbbf24', 'MA20'], ['#f87171', 'MA50']].map(([c, l]) => (
              <span key={l} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ width: 18, height: 2, background: c, borderRadius: 1, display: 'inline-block' }} />
                {l}
              </span>
            ))}
          </div>

          {/* Volume chart */}
          <div style={{ fontSize: 11, color: '#94a3b8', marginBottom: 4, display: 'flex', alignItems: 'center', gap: 8 }}>
            成交量
            <span style={{ fontSize: 10, padding: '1px 6px', borderRadius: 4, fontWeight: 500,
              background: volLabel === '爆量' || volLabel === '放量' ? 'rgba(74,222,128,0.15)' : volLabel === '縮量' ? 'rgba(248,113,113,0.15)' : 'rgba(148,163,184,0.15)',
              color: volBadgeColor }}>
              {volLabel}
            </span>
            {stats && <span style={{ fontSize: 11, color: '#64748b' }}>今日 {stats.vol_ratio_pct}% 均量</span>}
          </div>
          <ResponsiveContainer width="100%" height={80}>
            <ComposedChart data={data} margin={{ top: 0, right: 8, left: 0, bottom: 0 }}>
              <XAxis dataKey="date" tick={false} tickLine={false} />
              <YAxis tick={{ ...TICK, fontSize: 10 }} tickLine={false} axisLine={false} width={44}
                tickFormatter={v => fmtVol(v as number)} />
              <Tooltip
                contentStyle={{ background: '#1e293b', border: '1px solid #334155', borderRadius: 6, fontSize: 12 }}
                labelStyle={{ color: '#94a3b8' }}
                formatter={(v: unknown) => [fmtVol(v as number)]}
              />
              <Bar dataKey="volume" name="成交量" maxBarSize={12}>
                {data.map((d, i) => (
                  <Cell key={i} fill={i === 0 || d.close >= (data[i - 1]?.close ?? d.close)
                    ? 'rgba(74,222,128,0.7)' : 'rgba(248,113,113,0.7)'} />
                ))}
              </Bar>
              <Line dataKey="avg_vol" stroke="#f59e0b" strokeWidth={1.5} strokeDasharray="5 4"
                dot={false} name="20日均量" />
            </ComposedChart>
          </ResponsiveContainer>
          <div style={{ display: 'flex', gap: 14, marginTop: 6, marginBottom: 14, fontSize: 11, color: '#94a3b8' }}>
            {[['rgba(74,222,128,0.7)', '漲日'], ['rgba(248,113,113,0.7)', '跌日'], ['#f59e0b', '均量']].map(([c, l]) => (
              <span key={l} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ width: 18, height: 2, background: c, borderRadius: 1, display: 'inline-block' }} />
                {l}
              </span>
            ))}
          </div>

          {/* RSI chart */}
          <div style={{ fontSize: 11, color: '#94a3b8', marginBottom: 4 }}>
            RSI (14) / RSI (7) — 超買 &gt;70 / 超賣 &lt;30
          </div>
          <ResponsiveContainer width="100%" height={80}>
            <ComposedChart data={data} margin={{ top: 0, right: 8, left: 0, bottom: 0 }}>
              <XAxis dataKey="date" tick={false} tickLine={false} />
              <YAxis domain={[0, 100]} tick={{ ...TICK, fontSize: 10 }} tickLine={false}
                axisLine={false} width={28} ticks={[0, 30, 70, 100]} />
              <Tooltip
                contentStyle={{ background: '#1e293b', border: '1px solid #334155', borderRadius: 6, fontSize: 12 }}
                labelStyle={{ color: '#94a3b8' }}
              />
              <ReferenceLine y={70} stroke="#f87171" strokeWidth={1} strokeDasharray="4 4" />
              <ReferenceLine y={30} stroke="#4ade80" strokeWidth={1} strokeDasharray="4 4" />
              <Line dataKey="rsi14" stroke="#a78bfa" strokeWidth={2} dot={false} name="RSI14" connectNulls />
              <Line dataKey="rsi7"  stroke="#38bdf8" strokeWidth={1.5} dot={false} name="RSI7"  connectNulls />
            </ComposedChart>
          </ResponsiveContainer>
          <div style={{ display: 'flex', gap: 14, marginTop: 6, fontSize: 11, color: '#94a3b8' }}>
            {[['#a78bfa', 'RSI (14) 慢線'], ['#38bdf8', 'RSI (7) 快線']].map(([c, l]) => (
              <span key={l} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ width: 18, height: 2, background: c, borderRadius: 1, display: 'inline-block' }} />
                {l}
              </span>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

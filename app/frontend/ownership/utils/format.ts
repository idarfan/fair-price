export function fmtPct(val: number | null | undefined): string {
  if (val == null) return '—'
  return `${val.toFixed(2)}%`
}

export function fmtDelta(val: number | null | undefined): string {
  if (val == null) return '—'
  const sign = val >= 0 ? '+' : ''
  return `${sign}${val.toFixed(2)}%`
}

export function fmtLarge(val: number | null | undefined): string {
  if (val == null) return '—'
  if (val >= 1_000_000_000) return `$${(val / 1_000_000_000).toFixed(1)}B`
  if (val >= 1_000_000)     return `$${(val / 1_000_000).toFixed(0)}M`
  if (val >= 1_000)         return `$${(val / 1_000).toFixed(0)}K`
  return `$${val.toLocaleString()}`
}

export function fmtCount(val: number | null | undefined): string {
  if (val == null) return '—'
  return val.toLocaleString()
}

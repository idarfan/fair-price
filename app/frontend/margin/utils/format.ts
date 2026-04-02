export function fmtUSD(value: number, decimals = 2): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value)
}

export function fmtPct(rate: number): string {
  return (rate * 100).toFixed(2) + '%'
}

export function fmtDays(days: number): string {
  return `${days} 天`
}

export function fmtDate(isoDate: string): string {
  if (!isoDate) return '—'
  const d = new Date(isoDate + 'T00:00:00')
  return d.toLocaleDateString('zh-TW', { year: 'numeric', month: '2-digit', day: '2-digit' })
}

export function todayISO(): string {
  return new Date().toISOString().split('T')[0]
}

// Convert a date string (YYYY-MM-DD) to days from today (min 1)
export function dateToDays(isoDate: string): number {
  const target = new Date(isoDate + 'T00:00:00')
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const diff = Math.round((target.getTime() - today.getTime()) / 86_400_000)
  return Math.max(1, diff)
}

// Convert days from today to ISO date string
export function daysToDate(days: number): string {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() + days)
  return d.toISOString().split('T')[0]
}

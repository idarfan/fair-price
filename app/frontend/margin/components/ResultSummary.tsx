import { fmtUSD, fmtPct } from '../utils/format'
import type { CalcResults } from '../types'

interface Props {
  results: CalcResults | null
}

function MetricCard({
  label, value, positive, neutral,
}: {
  label: string
  value: string
  positive?: boolean
  neutral?: boolean
}) {
  const color = neutral
    ? 'text-gray-300'
    : positive
      ? 'text-green-400'
      : 'text-red-400'

  return (
    <div className="bg-gray-800 rounded-lg p-3">
      <p className="text-xs text-gray-400 mb-1">{label}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}

export function ResultSummary({ results }: Props) {
  if (!results) {
    return (
      <div className="bg-gray-800 rounded-lg p-4 text-center text-gray-500 text-sm">
        請填入建倉價、股數與平倉價以查看試算結果
      </div>
    )
  }

  const { balance, annualRate, marginInterest, spreadProfit, netProfit, breakEven } = results

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <MetricCard label="融資餘額" value={fmtUSD(balance)} neutral />
        <MetricCard label="融資年利率" value={fmtPct(annualRate)} neutral />
        <MetricCard label="融資利息" value={fmtUSD(marginInterest)} neutral />
        <MetricCard label="損益兩平價" value={fmtUSD(breakEven)} neutral />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <MetricCard
          label="價差獲利"
          value={fmtUSD(spreadProfit)}
          positive={spreadProfit >= 0}
        />
        <MetricCard
          label="淨獲利（扣息後）"
          value={fmtUSD(netProfit)}
          positive={netProfit >= 0}
        />
      </div>
    </div>
  )
}

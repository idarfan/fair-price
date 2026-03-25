import type { Meta, StoryObj } from '@storybook/react'
import PayoffChart from './PayoffChart'
import { buildChartData, calcSummary } from '../payoff'
import { STRATEGIES, buildLegsForPrice } from '../strategies'

const meta: Meta<typeof PayoffChart> = {
  title: 'Options/PayoffChart',
  component: PayoffChart,
  parameters: { layout: 'padded' },
}
export default meta
type Story = StoryObj<typeof PayoffChart>

const price = 5.0

function makeData(key: string) {
  const all = [
    ...Object.values(STRATEGIES.bullish).flat(),
    ...Object.values(STRATEGIES.neutral).flat(),
    ...Object.values(STRATEGIES.volatile).flat(),
  ]
  const tpl = all.find(s => s.key === key)
  if (!tpl) return { data: [], summary: null }
  const legs = buildLegsForPrice(tpl, price)
  const data = buildChartData(legs, price)
  return { data, summary: calcSummary(data) }
}

export const CashSecuredPut: Story = {
  render: () => { const { data, summary } = makeData('cash_secured_put'); return <PayoffChart data={data} summary={summary} price={price} /> }
}
export const IronCondor: Story = {
  render: () => { const { data, summary } = makeData('iron_condor'); return <PayoffChart data={data} summary={summary} price={price} /> }
}
export const LongStraddle: Story = {
  render: () => { const { data, summary } = makeData('long_straddle'); return <PayoffChart data={data} summary={summary} price={price} /> }
}
export const LongCallButterfly: Story = {
  render: () => { const { data, summary } = makeData('long_call_butterfly'); return <PayoffChart data={data} summary={summary} price={price} /> }
}
export const Empty: Story = {
  render: () => <PayoffChart data={[]} summary={null} price={0} />
}

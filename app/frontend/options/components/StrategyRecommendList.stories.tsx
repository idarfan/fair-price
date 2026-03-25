import type { Meta, StoryObj } from '@storybook/react'
import { useState } from 'react'
import StrategyRecommendList from './StrategyRecommendList'
import { STRATEGIES } from '../strategies'

const meta: Meta<typeof StrategyRecommendList> = {
  title: 'Options/StrategyRecommendList',
  component: StrategyRecommendList,
  parameters: { layout: 'padded' },
}
export default meta
type Story = StoryObj<typeof StrategyRecommendList>

const bullishHighIv = STRATEGIES.bullish.high_iv ?? []
const neutralHighIv = STRATEGIES.neutral.high_iv ?? []

const Controlled = ({ strategies }: { strategies: typeof bullishHighIv }) => {
  const [idx, setIdx] = useState(0)
  return <div style={{ width: 220 }}><StrategyRecommendList strategies={strategies} selectedIdx={idx} onSelect={setIdx} /></div>
}

export const BullishHighIV: Story  = { render: () => <Controlled strategies={bullishHighIv} /> }
export const NeutralHighIV: Story  = { render: () => <Controlled strategies={neutralHighIv} /> }
export const Empty: Story          = { render: () => <Controlled strategies={[]} /> }

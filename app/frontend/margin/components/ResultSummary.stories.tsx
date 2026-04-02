import type { Meta, StoryObj } from '@storybook/react'
import { ResultSummary } from './ResultSummary'
import { buildInterestSchedule } from '../utils/interestCalc'

const meta: Meta<typeof ResultSummary> = {
  title: 'Margin/ResultSummary',
  component: ResultSummary,
  parameters: { backgrounds: { default: 'dark' } },
  decorators: [
    Story => (
      <div className="bg-gray-900 p-6 rounded-lg w-80">
        <Story />
      </div>
    ),
  ],
}
export default meta
type Story = StoryObj<typeof ResultSummary>

// TQQQ 100 shares, 60 days: balance=3000, rate=12%
// interest = 3000 * 0.12 * 60 / 360 = 60
// spread = (35 - 30) * 100 = 500
// net = 500 - 60 = 440
// breakEven = 30 + 60/100 = 30.60
export const ProfitablePosition: Story = {
  args: {
    results: {
      balance: 3000,
      annualRate: 0.12,
      marginInterest: 60,
      spreadProfit: 500,
      netProfit: 440,
      breakEven: 30.60,
      schedule: buildInterestSchedule(3000, 0.12, 60),
    },
  },
}

export const LosingPosition: Story = {
  args: {
    results: {
      balance: 3000,
      annualRate: 0.12,
      marginInterest: 60,
      spreadProfit: -200,
      netProfit: -260,
      breakEven: 30.60,
      schedule: buildInterestSchedule(3000, 0.12, 60),
    },
  },
}

export const BreakEvenPosition: Story = {
  args: {
    results: {
      balance: 3000,
      annualRate: 0.12,
      marginInterest: 60,
      spreadProfit: 60,
      netProfit: 0,
      breakEven: 30.60,
      schedule: buildInterestSchedule(3000, 0.12, 15),
    },
  },
}

export const NoInput: Story = {
  args: { results: null },
}

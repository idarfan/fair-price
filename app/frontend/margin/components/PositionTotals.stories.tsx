import type { Meta, StoryObj } from '@storybook/react'
import { PositionTotals } from './PositionTotals'

const meta: Meta<typeof PositionTotals> = {
  title: 'Margin/PositionTotals',
  component: PositionTotals,
  parameters: { backgrounds: { default: 'dark' } },
  decorators: [
    Story => (
      <div className="bg-gray-900 p-4 rounded-lg">
        <table className="w-full">
          <tbody />
          <Story />
        </table>
      </div>
    ),
  ],
}
export default meta
type Story = StoryObj<typeof PositionTotals>

const makePosition = (overrides: object) => ({
  id: 1,
  symbol: 'AAPL',
  buy_price: '180.00',
  shares: '100.0',
  sell_price: '200.00',
  opened_on: '2026-02-01',
  closed_on: null,
  status: 'open' as const,
  balance: 18000,
  annual_rate: 0.1175,
  days_held: 60,
  accrued_interest: 352.5,
  next_charge_date: '2026-04-17',
  current_period_interest: 58.75,
  ...overrides,
})

export const WithPositions: Story = {
  args: {
    positions: [
      makePosition({ id: 1, symbol: 'AAPL' }),
      makePosition({ id: 2, symbol: 'NVDA', buy_price: '900.00', balance: 9000 }),
    ],
  },
}

export const AllNegative: Story = {
  args: {
    positions: [
      makePosition({ sell_price: '150.00' }),
    ],
  },
}

export const Empty: Story = {
  args: { positions: [] },
}

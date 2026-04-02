import type { Meta, StoryObj } from '@storybook/react'
import { PositionRow } from './PositionRow'

const meta: Meta<typeof PositionRow> = {
  title: 'Margin/PositionRow',
  component: PositionRow,
  parameters: { backgrounds: { default: 'dark' } },
  decorators: [
    Story => (
      <div className="bg-gray-900 p-4 rounded-lg">
        <table className="w-full">
          <thead>
            <tr className="text-gray-400 border-b border-gray-700 text-left text-xs">
              <th className="py-2 pr-3">代號</th>
              <th className="py-2 pr-3">建倉價</th>
              <th className="py-2 pr-3">股數</th>
              <th className="py-2 pr-3">持有天數</th>
              <th className="py-2 pr-3">累計利息</th>
              <th className="py-2 pr-3">下次收息日</th>
              <th className="py-2 pr-3">本期備金</th>
              <th className="py-2 pr-3">淨獲利</th>
              <th className="py-2">操作</th>
            </tr>
          </thead>
          <tbody>
            <Story />
          </tbody>
        </table>
      </div>
    ),
  ],
}
export default meta
type Story = StoryObj<typeof PositionRow>

const basePosition = {
  id: 1,
  symbol: 'NVDA',
  buy_price: '900.00',
  shares: '10.0',
  sell_price: null,
  opened_on: '2026-03-11',
  closed_on: null,
  status: 'open' as const,
  balance: 9000,
  annual_rate: 0.12,
  days_held: 22,
  accrued_interest: 66.0,
  next_charge_date: '2026-04-10',
  current_period_interest: 22.0,
}

export const OpenPosition: Story = {
  args: {
    position: basePosition,
    onClose: (id) => console.log('close', id),
    onDelete: (id) => console.log('delete', id),
  },
}

export const OpenWithSellPrice: Story = {
  args: {
    position: { ...basePosition, sell_price: '950.00' },
    onClose: (id) => console.log('close', id),
    onDelete: (id) => console.log('delete', id),
  },
}

export const ClosedPosition: Story = {
  args: {
    position: {
      ...basePosition,
      status: 'closed' as const,
      sell_price: '850.00',
      closed_on: '2026-04-01',
    },
    onClose: (id) => console.log('close', id),
    onDelete: (id) => console.log('delete', id),
  },
}

import type { Meta, StoryObj } from '@storybook/react'
import { InterestScheduleTable } from './InterestScheduleTable'
import { buildInterestSchedule } from '../utils/interestCalc'

const meta: Meta<typeof InterestScheduleTable> = {
  title: 'Margin/InterestScheduleTable',
  component: InterestScheduleTable,
  parameters: { backgrounds: { default: 'dark' } },
  decorators: [
    Story => (
      <div className="bg-gray-900 p-6 rounded-lg">
        <Story />
      </div>
    ),
  ],
}
export default meta
type Story = StoryObj<typeof InterestScheduleTable>

export const ShortHold15Days: Story = {
  args: { schedule: buildInterestSchedule(3000, 0.12, 15) },
}

export const MediumHold45Days: Story = {
  args: { schedule: buildInterestSchedule(3000, 0.12, 45) },
}

export const LongHold365Days: Story = {
  args: { schedule: buildInterestSchedule(18250, 0.1175, 365) },
}

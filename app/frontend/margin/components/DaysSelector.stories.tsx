import type { Meta, StoryObj } from '@storybook/react'
import { useState } from 'react'
import { DaysSelector } from './DaysSelector'

const meta: Meta<typeof DaysSelector> = {
  title: 'Margin/DaysSelector',
  component: DaysSelector,
  parameters: { backgrounds: { default: 'dark' } },
  decorators: [
    Story => (
      <div className="bg-gray-900 p-6 rounded-lg w-96">
        <Story />
      </div>
    ),
  ],
}
export default meta
type Story = StoryObj<typeof DaysSelector>

function Controlled({ initialDays }: { initialDays: number }) {
  const [days, setDays] = useState(initialDays)
  return <DaysSelector days={days} onDaysChange={setDays} />
}

export const Default: Story = {
  render: () => <Controlled initialDays={30} />,
}

export const MaxDays: Story = {
  render: () => <Controlled initialDays={730} />,
}

export const SevenDays: Story = {
  render: () => <Controlled initialDays={7} />,
}

export const NinetyDays: Story = {
  render: () => <Controlled initialDays={90} />,
}

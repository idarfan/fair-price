import type { Meta, StoryObj } from '@storybook/react'
import { useState } from 'react'
import OutlookSelector from './OutlookSelector'

const meta: Meta<typeof OutlookSelector> = {
  title: 'Options/OutlookSelector',
  component: OutlookSelector,
  parameters: { layout: 'padded' },
}
export default meta
type Story = StoryObj<typeof OutlookSelector>

const Controlled = ({ initial }: { initial: Parameters<typeof OutlookSelector>[0]['value'] }) => {
  const [v, setV] = useState(initial)
  return <OutlookSelector value={v} onChange={setV} />
}

export const Bullish: Story  = { render: () => <Controlled initial="bullish"  /> }
export const Bearish: Story  = { render: () => <Controlled initial="bearish"  /> }
export const Neutral: Story  = { render: () => <Controlled initial="neutral"  /> }
export const Volatile: Story = { render: () => <Controlled initial="volatile" /> }

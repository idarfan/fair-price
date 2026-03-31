import type { Meta, StoryObj } from '@storybook/react'
import TechnicalsChart from '../app/frontend/technicals/TechnicalsChart'

const meta: Meta<typeof TechnicalsChart> = {
  title: 'Charts/TechnicalsChart',
  component: TechnicalsChart,
  parameters: {
    layout: 'fullscreen',
    // Chromatic: capture at multiple widths to catch responsive sizing bugs (教訓 2026-03-30 教訓 3)
    chromatic: { viewports: [1280, 768, 375] },
  },
}

export default meta
type Story = StoryObj<typeof TechnicalsChart>

// Default story: loads live data — Chromatic uses this for visual regression
export const AAPL: Story = {
  args: { symbol: 'AAPL' },
}

export const TSM: Story = {
  args: { symbol: 'TSM' },
}

import type { Meta, StoryObj } from '@storybook/react'
import ImageUploadZone from './ImageUploadZone'

const meta: Meta<typeof ImageUploadZone> = {
  title: 'Options/ImageUploadZone',
  component: ImageUploadZone,
  parameters: { layout: 'fullscreen' },
}
export default meta
type Story = StoryObj<typeof ImageUploadZone>

export const Default: Story = {
  render: () => (
    <div style={{ width: 240, height: 600, border: '1px solid #e5e7eb' }}>
      <ImageUploadZone onResult={r => console.log('OCR result', r)} />
    </div>
  ),
}

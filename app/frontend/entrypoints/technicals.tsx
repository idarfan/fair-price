import React from 'react'
import { createRoot, Root } from 'react-dom/client'
import TechnicalsChart from '../technicals/TechnicalsChart'

declare global {
  interface Window {
    mountTechChart: (el: Element, symbol: string) => void
  }
}

const roots = new Map<Element, Root>()

function mountTechChart(el: Element, symbol: string): void {
  const existing = roots.get(el)
  if (existing) existing.unmount()
  const root = createRoot(el)
  root.render(<TechnicalsChart symbol={symbol} />)
  roots.set(el, root)
}

window.mountTechChart = mountTechChart

import React from 'react'
import { createRoot } from 'react-dom/client'
import OptionsAnalyzerApp from '../options/OptionsAnalyzerApp'

const el = document.getElementById('options-root')
if (el) {
  const symbol: string = JSON.parse(el.dataset.symbol || '""')
  createRoot(el).render(<OptionsAnalyzerApp initialSymbol={symbol} />)
}

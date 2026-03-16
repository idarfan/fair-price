import React from 'react'
import { createRoot } from 'react-dom/client'
import OwnershipApp from '../ownership/OwnershipApp'

const el = document.getElementById('ownership-root')
if (el) {
  const symbols: string[] = JSON.parse(el.dataset.symbols || '[]')
  createRoot(el).render(<OwnershipApp symbols={symbols} />)
}

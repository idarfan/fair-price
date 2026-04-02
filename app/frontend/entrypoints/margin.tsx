import { createRoot } from 'react-dom/client'
import { MarginApp } from '../margin/MarginApp'

const el = document.getElementById('margin-root')
if (el) {
  createRoot(el).render(<MarginApp />)
}

import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Storybook 專用 Vite config（不使用 vite-plugin-ruby，強制 base='/' 避免繼承 /vite/ 路徑）
export default defineConfig({
  base: '/',
  plugins: [react()],
})

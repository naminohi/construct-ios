import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    fs: {
      // Allow serving WASM files
      allow: ['..']
    }
  },
  optimizeDeps: {
    exclude: ['construct_core']
  }
})

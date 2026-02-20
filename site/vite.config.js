import { defineConfig } from 'vite'

export default defineConfig({
  root: '.',
  base: '/AssemblyClaw/',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})

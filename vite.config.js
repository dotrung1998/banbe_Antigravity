import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // maplibre-gl loads its own tile-decoding Web Worker via a `new
  // Worker(new URL(...))` relative import; Vite's dep pre-bundling rewrites
  // that into `.vite/deps/maplibre-gl-worker.mjs`, which then 404s/fails to
  // load at runtime (net::ERR_FAILED) — the map's canvas and base style
  // still initialize, but every vector tile silently never decodes, so the
  // basemap area stays blank. Excluding it from pre-bundling keeps its own
  // worker file intact. See .claude/notes/11-realtime-map.md.
  optimizeDeps: { exclude: ['maplibre-gl'] },
})

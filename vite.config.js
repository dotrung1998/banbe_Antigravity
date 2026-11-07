import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { existsSync, mkdirSync, copyFileSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const MAPLIBRE_WORKER_DIR = 'maplibre-gl-worker' // served/emitted at /maplibre-gl-worker/*
const MAPLIBRE_WORKER_FILES = ['maplibre-gl-worker.mjs', 'maplibre-gl-shared.mjs']

// maplibre-gl locates its tile-decoding Web Worker at runtime via
// `new URL('./maplibre-gl-worker.mjs', import.meta.url)`, computed from a
// *variable*, not a static string literal — Vite/Rollup's special
// `new Worker(new URL(...))` bundling only recognizes a literal string, so
// it can't detect or bundle this one at all. Left alone, the production
// build never emits `maplibre-gl-worker.mjs`, so the URL maplibre-gl
// requests 404s (a static host's SPA fallback can mask this as an HTTP 200
// of index.html) and the worker is created then immediately torn down —
// the map style/sprite/tile-source *metadata* still loads fine over plain
// fetch from the main thread, so only the vector tile layer itself never
// paints: markers (plain DOM elements) still show, the basemap stays
// blank. See .claude/notes/11-realtime-map.md.
//
// The worker file also does its own `import ... from './maplibre-gl-shared.mjs'`
// — a plain `?url` asset copy of just the worker file breaks that relative
// import once it's alone in a hashed output directory, so both files need
// to be served/copied together, verbatim, at their original relative
// names. This plugin does that identically in dev (a server middleware)
// and in a production build (a post-build file copy), so
// `src/screens/MapExplore.jsx` can call
// `maplibregl.setWorkerUrl('/maplibre-gl-worker/maplibre-gl-worker.mjs')`
// unconditionally in both modes.
function maplibreWorkerFiles() {
  const workerSrcDir = join(process.cwd(), 'node_modules', 'maplibre-gl', 'dist')
  return {
    name: 'maplibre-gl-worker-files',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const name = MAPLIBRE_WORKER_FILES.find(f => req.url === `/${MAPLIBRE_WORKER_DIR}/${f}`)
        if (!name) return next()
        res.setHeader('Content-Type', 'text/javascript')
        res.end(readFileSync(join(workerSrcDir, name)))
      })
    },
    closeBundle() {
      const outDir = join(process.cwd(), 'dist', MAPLIBRE_WORKER_DIR)
      if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true })
      for (const f of MAPLIBRE_WORKER_FILES) copyFileSync(join(workerSrcDir, f), join(outDir, f))
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), maplibreWorkerFiles()],
  // maplibre-gl loads its own tile-decoding Web Worker via a `new
  // Worker(new URL(...))` relative import; Vite's dep pre-bundling rewrites
  // that into `.vite/deps/maplibre-gl-worker.mjs`, which then 404s/fails to
  // load at runtime (net::ERR_FAILED) — the map's canvas and base style
  // still initialize, but every vector tile silently never decodes, so the
  // basemap area stays blank. Excluding it from pre-bundling keeps its own
  // worker file intact. See .claude/notes/11-realtime-map.md.
  optimizeDeps: { exclude: ['maplibre-gl'] },
})

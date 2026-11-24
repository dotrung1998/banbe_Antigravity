import { applyMapSurface } from './lib/mapSurface.js'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
// Note 101: dynaura's stylesheet without its Google Fonts import (the island uses the app's own face).
import 'dynaura/styles-no-font.css'
import './index.css'
import { applyGlassOpacity } from './lib/glassOpacity.js'
import { installZoomOrigin } from './lib/zoomOrigin.js'
import { applyFont } from './lib/fontPref.js'
import App from './App.jsx'
import { PublicPolicy } from './screens/Policy.jsx'
import PublicDataDeletion from './screens/PublicDataDeletion.jsx'

// Public, logged-out pages for app-store/OAuth review (Meta needs a privacy
// policy URL and a data-deletion URL). Rendered without BanBeProvider, so no
// login wall, splash or session is involved.
const publicPath = window.location.pathname.replace(/\/+$/, '')
const Root = publicPath === '/privacy' ? PublicPolicy
  : publicPath === '/data-deletion' ? PublicDataDeletion
  : App

// After a new deploy, an open tab may ask for a lazy chunk an older build named; the catch-all rewrite answers
// with index.html and the import fails. Reload once to pick up the new build (ChunkErrorBoundary in App.jsx is
// the fallback). The sessionStorage stamp stops a reload loop if the fresh page fails the same way.
window.addEventListener('vite:preloadError', (event) => {
  const KEY = 'bb-preload-reload-at'
  let last = 0
  try { last = Number(sessionStorage.getItem(KEY)) || 0 } catch { /* storage unavailable */ }
  if (Date.now() - last < 10000) return
  try { sessionStorage.setItem(KEY, String(Date.now())) } catch { /* storage unavailable */ }
  event.preventDefault()
  window.location.reload()
})

applyGlassOpacity()
applyMapSurface()
applyFont()
installZoomOrigin()

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Root />
  </StrictMode>,
)

// Local cache for Supabase Storage images (see public/sw.js). Production only,
// so dev hot-reload is never served stale.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {})
  })
}

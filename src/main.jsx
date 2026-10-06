import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
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

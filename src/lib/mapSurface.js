// Map controls come in two looks (iOS MapSurface.swift): "glass" (blurred pills) or "solid" (static colour surface:
// palette surface1 + 1px ink/8% stroke + small shadow). Stored per browser; applied as a data attribute on <html>,
// which index.css turns into CSS variables for every element carrying the `bb-mapsurf` class (no per-component forks).
export const MAP_SURFACE_KEY = 'banbe.mapSurface.v1';

export function getMapSurface() {
  try { return localStorage.getItem(MAP_SURFACE_KEY) === 'solid' ? 'solid' : 'glass'; } catch { return 'glass'; }
}

export function setMapSurface(v) {
  const value = v === 'solid' ? 'solid' : 'glass';
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-map-surface', value);
  try { localStorage.setItem(MAP_SURFACE_KEY, value); } catch { /* ignore */ }
  return value;
}

export function applyMapSurface() {
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-map-surface', getMapSurface());
}

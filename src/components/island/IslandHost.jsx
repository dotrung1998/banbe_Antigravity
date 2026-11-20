import { useEffect } from 'react';
import { Toaster } from 'dynaura';
import { useIslandPrefs } from '../../lib/useIslandPrefs.js';
import { islandTheme } from '../../lib/islandPrefs.js';

// The one dynaura Toaster for the whole page (dynaura keeps a single global island; a second one warns and breaks
// transitions). Mounted only while the `island_toasts` switch is on. Its props are live: picking another style in
// Settings re-themes the same island without a reload (dynaura's adapter re-applies Toaster options on each render).
export default function IslandHost() {
  const prefs = useIslandPrefs();
  useEffect(() => {
    const root = document.documentElement;
    root.setAttribute('data-island-theme', prefs.theme);
    root.setAttribute('data-island-motion', prefs.motion);
  }, [prefs.theme, prefs.motion]);

  return (
    <Toaster
      position={prefs.position}
      offset={10}
      theme={islandTheme(prefs.theme).theme}
      // Swipe is the fast way off an island; some people turn it off after an accidental dismiss.
      swipe={prefs.swipe ? 'edge' : 'none'}
      haptics={prefs.haptics}
      timer
      queue={false}
      dedupe="id"
    />
  );
}

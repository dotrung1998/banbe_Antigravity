import { useSyncExternalStore } from 'react';
import { readIslandPrefs, subscribeIslandPrefs } from './islandPrefs.js';

/** The saved island style, live: changing it from Settings re-themes the mounted Toaster without a reload. */
export function useIslandPrefs() {
  return useSyncExternalStore(subscribeIslandPrefs, readIslandPrefs, readIslandPrefs);
}

import { useEffect } from 'react';

// Note 64: the first Home after a sign-in reveals its regions top to bottom (CSS in index.css, regions marked with
// data-reveal="0..3"). One shot: `justSignedIn` is set by completeSignInHandoff() and cleared here when the
// sequence ends, so ordinary navigation and restored sessions never replay it.
const TOTAL_MS = 240 + 420 + 60; // last delay + duration + a frame of slack
const REDUCED_MS = 220;

export default function useSignInReveal(justSignedIn, screen, clear, onDone) {
  useEffect(() => {
    if (!justSignedIn) return undefined;
    if (screen !== 'home') { clear(); return undefined; }
    const root = document.documentElement;
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    root.dataset.reveal = '1';
    const t = setTimeout(() => {
      delete root.dataset.reveal;
      clear();
      onDone?.();
    }, reduce ? REDUCED_MS : TOTAL_MS);
    return () => { clearTimeout(t); delete root.dataset.reveal; };
  }, [justSignedIn, screen]); // eslint-disable-line react-hooks/exhaustive-deps
}

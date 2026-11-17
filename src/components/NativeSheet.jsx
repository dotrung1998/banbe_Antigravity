// Native modal sheet on <dialog> (Modern Web Guidance pass, note 90). The browser already provides what every
// hand-rolled sheet in this app rebuilt: top-layer rendering above everything, focus containment, page inertness,
// Esc / back-gesture dismissal, and focus return to the control that opened it.
//
// Two things this app adds on top of the platform:
//   1. The desktop phone frame. A top-layer box is laid out against the VIEWPORT, so on a MacBook it would centre in
//      the whole window instead of the 415px phone. The frame's rectangle (src/lib/viewport.js) is written as a
//      clip-path inset before showModal(), so the scrim and the sheet paint and hit-test only inside the phone.
//      On a real phone the insets are 0 and this is a no-op.
//   2. `role="dialog"` / `aria-modal` are kept DELIBERATELY, although the native element already implies both: this
//      repo's Playwright specs assert those attributes, and dropping them would be a contract change unrelated to
//      the modernization. They are redundant, not wrong.
//
// Do NOT add a focus trap, an Escape listener or `inert` toggling around this component: showModal() supplies all
// three, and stacking a second trap on top fights the native one (see the dialog guide).
import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { getFrameBox } from '../lib/viewport.js';

const FRAME_RADIUS = 55; // .bb-screen's border-radius in the desktop frame

/**
 * `open` false unmounts the dialog (the app's sheets are conditionally mounted, so this is usually always true).
 * `onClose` is called for Esc, the back gesture, and a press on the scrim — never for a press inside the panel.
 * `returnFocusTo` is the element that should get focus back; native dialogs restore focus to the previously focused
 * element, but Safari does not focus a button on click, so callers pass the clicked element explicitly.
 */
export default function NativeSheet({
  open = true, onClose, labelledBy, label, testId, zIndex = 2300, returnFocusTo,
  children, style, className = '',
}) {
  const dialogRef = useRef(null);
  const bodyRef = useRef(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  const returnRef = useRef(returnFocusTo);
  returnRef.current = returnFocusTo;

  useEffect(() => {
    if (!open) return undefined;
    const el = dialogRef.current;
    if (!el || typeof el.showModal !== 'function' || el.open) return undefined;

    // The phone frame, as insets from the four viewport edges.
    const box = getFrameBox();
    const vw = window.innerWidth || 0;
    const vh = window.innerHeight || 0;
    const framed = box.width > 0
      && (box.left > 0.5 || box.top > 0.5 || box.width < vw - 0.5 || box.height < vh - 0.5);
    const set = (k, v) => el.style.setProperty(k, v);
    set('--bb-dlg-t', `${framed ? Math.max(0, box.top) : 0}px`);
    set('--bb-dlg-r', `${framed ? Math.max(0, vw - box.left - box.width) : 0}px`);
    set('--bb-dlg-b', `${framed ? Math.max(0, vh - box.top - box.height) : 0}px`);
    set('--bb-dlg-l', `${framed ? Math.max(0, box.left) : 0}px`);
    set('--bb-dlg-radius', `${framed ? FRAME_RADIUS : 0}px`);

    el.showModal();
    return () => {
      const d = dialogRef.current;
      if (d?.open) d.close();
      const back = returnRef.current;
      if (back?.focus) { try { back.focus({ preventScroll: true }); } catch { /* element gone */ } }
    };
  }, [open]);

  if (!open) return null;
  const target = (typeof document !== 'undefined' && (document.querySelector('.bb-screen') || document.body)) || null;
  if (!target) return null;

  return createPortal(
    <dialog
      ref={dialogRef}
      className={`bb-native-sheet ${className}`.trim()}
      data-testid={testId}
      aria-labelledby={labelledBy}
      aria-label={labelledBy ? undefined : label}
      // Deliberate redundancy, see the header comment: the app's specs assert these.
      role="dialog"
      aria-modal="true"
      style={{ zIndex, ...style }}
      // Esc and the mobile back gesture: keep React's state in charge of unmounting, with its own close animation.
      onCancel={(e) => { e.preventDefault(); closeRef.current?.(); }}
      // A press on the scrim (the dialog itself, or the full-size body wrapper) dismisses. `closedby` would do this
      // natively but is Chrome/Firefox only; on Safari this is the portable path.
      onClick={(e) => { if (e.target === dialogRef.current || e.target === bodyRef.current) closeRef.current?.(); }}
    >
      <div ref={bodyRef} className="bb-native-sheet-body">{children}</div>
    </dialog>,
    target,
  );
}

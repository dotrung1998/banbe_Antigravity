import { useEffect } from 'react';
import { dynaura } from 'dynaura';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { useIslandPrefs } from '../../lib/useIslandPrefs.js';
import { islandPresentation } from '../../lib/islandNotifications.js';

// The island's real job (note 101): proactive in-app notifications (state.toasts, polled by BanBeContext) show on the
// island instead of the card stack, while the switch is on. One at a time: the first non-leaving toast owns the
// island, its 8-second clock only starts when it is actually shown (markToastVisible, same rule as ToastStack), and
// when it leaves the next one rises. Tapping the island opens the notification exactly as tapping the card did.
//
// duration is null on purpose: BanBeContext's own timer is the single clock, so hover/pin inside dynaura can never
// leave a toast behind after the queue says it is gone.
export default function IslandToasts() {
  const { state: s, T, openNotification, dismissToast, markToastVisible } = useBanBe();
  const prefs = useIslandPrefs();
  const active = (s.toasts || []).find(t => !t.leaving);
  const activeId = active?.id || null;

  useEffect(() => {
    if (!active) return undefined;
    const id = active.id;
    const n = active.notification || {};
    markToastVisible(id);

    const open = () => {
      dismissToast(id);
      if (active.notification) openNotification(active.notification);
    };
    const presentation = islandPresentation(n);
    const description = prefs.detail === 'title' ? undefined : (n.body || undefined);

    dynaura[presentation.type]({
      id,
      title: n.title || T('Thông báo mới', 'New notification'),
      description,
      duration: null,
      onClick: open,
      // A swipe, Escape or the button is the person acting on it; 'api' is our own cleanup and must not re-dismiss.
      onDismiss: (reason) => { if (reason !== 'api') dismissToast(id); },
      ...(presentation.action ? { button: { title: T('Mở', 'Open'), onClick: open } } : {}),
    });

    return () => { dynaura.dismiss(id, 'api'); };
  }, [activeId]); // eslint-disable-line react-hooks/exhaustive-deps

  return null;
}

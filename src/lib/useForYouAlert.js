// React glue for src/lib/forYouAlert.js. Persists per account; tracks which
// pending set the one-shot animation already ran for (in memory only), so a
// re-render, poll or remount-free update never replays it.
import { useCallback, useEffect, useRef, useState } from 'react';
import { observe, acknowledge, hasPending, pendingIds, loadAlertState, saveAlertState, emptyAlertState } from './forYouAlert.js';

export function useForYouAlert({ userId, matches, prefsVersion, loading }) {
  const [st, setSt] = useState(() => loadAlertState(userId));
  const userRef = useRef(userId);
  const animated = useRef(new Set());
  const [animateNow, setAnimateNow] = useState(false);
  const timer = useRef(null);

  // Account switch: load that account's own state.
  useEffect(() => {
    if (userRef.current === userId) return;
    userRef.current = userId;
    animated.current = new Set();
    setAnimateNow(false);
    setSt(userId ? loadAlertState(userId) : emptyAlertState());
  }, [userId]);

  useEffect(() => {
    if (!userId) return;
    setSt(prev => {
      const next = observe(prev, matches, { prefsVersion, loading });
      if (next !== prev) saveAlertState(userId, next);
      return next;
    });
  }, [userId, matches, prefsVersion, loading]);

  // Animate only when the pending set gains an id not yet animated for.
  useEffect(() => {
    const fresh = pendingIds(st).filter(id => !animated.current.has(id));
    if (!fresh.length) return;
    fresh.forEach(id => animated.current.add(id));
    setAnimateNow(true);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setAnimateNow(false), 3000);
  }, [st]);
  useEffect(() => () => clearTimeout(timer.current), []);

  const ack = useCallback((loadedIds) => {
    setSt(prev => {
      const next = acknowledge(prev, loadedIds);
      if (next !== prev) saveAlertState(userRef.current, next);
      return next;
    });
  }, []);

  return { pending: hasPending(st), animate: animateNow, acknowledge: ack };
}

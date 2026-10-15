import { useCallback, useEffect, useMemo, useRef } from 'react';
import { ensureOrganizerRpc, shouldEnsureOrganizer } from './ensureOrganizer.js';

// Calls ensure_my_organizer exactly when Organizer Mode is on and the
// confirmed owned-organizer lookup is empty. Covers: toggle on, sign-in /
// session restore (loadMyEvents -> 'loaded'), and the Host card finding none.
// A failure stops at status 'error' (no auto loop); retryEnsureOrganizer is the
// explicit user action. Does not touch roles or publish anything.
export function useEnsureOrganizer({ s, set, supabase, loadMyEvents }) {
  const run = useMemo(() => ensureOrganizerRpc(supabase), [supabase]);
  const userId = s.user?.id || null;
  const lastUserRef = useRef(null);

  const attempt = useCallback(async () => {
    set({ ensureOrganizerStatus: 'loading', ensureOrganizerError: '' });
    const r = await run();
    if (!r.ok) {
      set({ ensureOrganizerStatus: 'error', ensureOrganizerError: r.error });
      return r;
    }
    set(prev => ({
      ensureOrganizerStatus: 'idle', ensureOrganizerError: '',
      myOrganizerId: prev.myOrganizerId || r.organizerId,
      myOrganizerIds: prev.myOrganizerIds.includes(r.organizerId) ? prev.myOrganizerIds : [...prev.myOrganizerIds, r.organizerId],
      orgRegName: prev.orgRegName || r.name,
    }));
    if (userId) loadMyEvents(userId);
    return r;
  }, [run, set, userId, loadMyEvents]);

  useEffect(() => {
    if (lastUserRef.current !== userId) {
      lastUserRef.current = userId;
      if (s.ensureOrganizerStatus === 'error') set({ ensureOrganizerStatus: 'idle', ensureOrganizerError: '' });
    }
    // While the setup sheet is open the user has not agreed to create a host profile yet; only the
    // sheet's own Create button (`now`) may create it.
    if (!s.hostSetupOpen && shouldEnsureOrganizer({
      userId, organizerMode: s.organizerMode, idsStatus: s.myOrganizerIdsStatus,
      ownedCount: s.myOrganizerIds.length, ensureStatus: s.ensureOrganizerStatus,
      modeBusy: !!s.organizerModeBusy,
    })) attempt();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, s.organizerMode, s.myOrganizerIdsStatus, s.myOrganizerIds.length, s.ensureOrganizerStatus, s.organizerModeBusy, s.hostSetupOpen]);

  // Explicit user Retry; ignored while a call is in flight (no double submit).
  const retry = useCallback(() => {
    if (s.ensureOrganizerStatus === 'loading') return;
    attempt();
  }, [attempt, s.ensureOrganizerStatus]);
  // `now` runs ensure immediately and resolves with {ok, organizerId, error}. It bypasses the
  // automatic-run gating above, for callers (the host setup sheet) that need the organizer right now.
  return { retry, now: attempt };
}

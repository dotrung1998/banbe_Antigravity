// Ensure an Organizer-Mode user OWNS an organizer row (migration 163,
// ensure_my_organizer). Root cause this fixes: the organizer row used to be
// created only lazily inside create_event_draft, so a user with Organizer
// Mode on but no event yet had no organizer and the Host card had nothing
// to render. Pure helpers here; the React wiring is in useEnsureOrganizer.js.

const EMAIL_LIKE = /@/;
const PHONE_LIKE = /^[0-9+()\s.-]+$/;

/** Default editable organizer name. Mirrors the SQL. Never email/phone/handle. */
export function deriveDefaultOrganizerName(displayName, lang = 'en') {
  const vi = lang === 'vi';
  const raw = typeof displayName === 'string' ? displayName.trim() : '';
  if (!raw || EMAIL_LIKE.test(raw) || PHONE_LIKE.test(raw)) {
    return vi ? 'Sự kiện của tôi' : 'My events';
  }
  return `${raw.slice(0, 60)}${vi ? ' Sự kiện' : ' Events'}`;
}

/**
 * Should the client call ensure_my_organizer now?
 * Only when organizer mode is on, the owned-organizer lookup has CONFIRMED
 * zero (status 'loaded', never 'idle'/'loading'/'error'), and no ensure is
 * in flight or already failed (a failed attempt waits for an explicit Retry,
 * so there is no automatic retry loop).
 */
export function shouldEnsureOrganizer({ userId, organizerMode, idsStatus, ownedCount, ensureStatus = 'idle' }) {
  if (!userId || !organizerMode) return false;
  if (idsStatus !== 'loaded') return false;
  if ((ownedCount || 0) > 0) return false;
  if (ensureStatus === 'loading' || ensureStatus === 'error') return false;
  return true;
}

/** Normalise the RPC response into {ok, organizerId, created, name, error}. */
export function normalizeEnsureResult({ data, error }) {
  if (error) return { ok: false, error: error.code || error.message || 'RPC_ERROR' };
  if (!data || data.success === false || !data.organizerId) {
    return { ok: false, error: (data && data.error) || 'EMPTY_RESULT' };
  }
  return { ok: true, organizerId: data.organizerId, created: !!data.created, name: data.name || '' };
}

/** Wrap an async fn so concurrent callers share one in-flight promise. */
export function createSingleFlight(fn) {
  let inflight = null;
  return (...args) => {
    if (inflight) return inflight;
    inflight = Promise.resolve().then(() => fn(...args)).finally(() => { inflight = null; });
    return inflight;
  };
}

/** Retry state machine: idle -> loading -> (done | error); error -> loading only via retry. */
export function nextEnsureStatus(status, event) {
  switch (event) {
    case 'start': return status === 'loading' ? 'loading' : 'loading';
    case 'success': return 'idle';
    case 'failure': return 'error';
    case 'retry': return status === 'error' ? 'loading' : status;
    case 'reset': return 'idle';
    default: return status;
  }
}

export function ensureOrganizerRpc(supabase) {
  return createSingleFlight(async () => normalizeEnsureResult(await supabase.rpc('ensure_my_organizer')));
}

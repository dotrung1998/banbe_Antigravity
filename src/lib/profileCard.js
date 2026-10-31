// The personal profile identity card (note 68): one role line, de-duplicated chips, the stats strip, the Upcoming list
// and the card surface. Pure logic, mirrored by apps/ios/BanbeApp/Lib/ProfileCard.swift through the shared
// tests/fixtures/profile-card.json (tests: tests/unit/profileCard.test.mjs and apps/ios/BanbeAppTests/ProfileCardTests.swift)
// — change both together.
//
// The admin role is never shown here: this page is public (get_public_profile has an anon grant, migration 079).

/** "Host · Founder of Bếp Nhỏ" while this profile owns an organizer AND organizer mode is on, else "Member". */
export function roleLabel({ organizerName = null, organizerMode = false } = {}, vi = false) {
  if (organizerName && organizerMode) return vi ? `Host · Founder tổ chức ${organizerName}` : `Host · Founder of ${organizerName}`;
  return vi ? 'Thành viên' : 'Member';
}

const norm = (x) => String(x ?? '').trim().toLocaleLowerCase();

/**
 * Interest chips with repeats and anything already said on the card removed (regression: banbetestadmin's interests
 * are ["Admin", "Admin"], shown as two identical chips). Case- and space-insensitive; keeps the first of any repeat.
 */
export function dedupeChips(chips = [], alreadyShown = []) {
  const seen = new Set(alreadyShown.map(norm).filter(Boolean));
  const out = [];
  for (const c of chips) {
    const k = norm(c);
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push(c);
  }
  return out;
}

/**
 * The stats strip inside the card: [{ id, value }] (labels are the caller's, by id), or [] when fewer than two would
 * show. Public numbers only for visitors: a host's events and followers (get_public_profile). The owner also sees
 * their own badges (only while the Rewards switch is on) and upcoming count. Never a made-up zero for unknown data.
 */
export function profileStats({ organizer = null, organizerMode = false, isOwner = false, rewardsOn = false, badgeCount = null, upcomingCount = null } = {}) {
  const out = [];
  const host = organizer && organizerMode;
  if (host) {
    out.push({ id: 'hosted', value: organizer.event_count ?? 0 });
    out.push({ id: 'followers', value: organizer.follower_count ?? 0 });
  }
  if (isOwner && upcomingCount != null && !host) out.push({ id: 'upcoming', value: upcomingCount });
  if (isOwner && rewardsOn && badgeCount != null) out.push({ id: 'badges', value: badgeCount });
  else if (host && organizer.hosting_since_year) out.push({ id: 'since', value: organizer.hosting_since_year });
  return out.length >= 2 ? out.slice(0, 3) : [];
}

/**
 * The Upcoming list under the card, from data the app already has: this profile's own hosted events that are still
 * ahead (public), plus — for the owner only — the events they are going to. Never another person's bookings.
 * `events` = [{ key, name, organizerId, start (ms|null), ended, cancelled }]. Sorted by start, at most `limit`.
 */
export function upcomingEvents({ events = [], organizerId = null, organizerMode = false, isOwner = false, goingKeys = [], limit = 5 } = {}) {
  const going = new Set(isOwner ? goingKeys : []);
  const out = [];
  for (const e of events) {
    if (!e || e.ended || e.cancelled) continue;
    const hosting = !!(organizerId && organizerMode && e.organizerId === organizerId);
    if (hosting) out.push({ ...e, role: 'hosting' });
    else if (going.has(e.key)) out.push({ ...e, role: 'going' });
  }
  out.sort((a, b) => (a.start ?? Infinity) - (b.start ?? Infinity));
  return out.slice(0, limit);
}

// The card surface: the theme's raised surface, the person's own palette colour as a light tint (their choice stays
// visible, text contrast stays guaranteed), and a soft clay glow in the charm's corner.
export const CARD_TINT = 0.18;
export const CARD_GLOW = 0.1;

const hex = (h) => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const toHex = (rgb) => '#' + rgb.map(v => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
const mix = (top, bottom, a) => top.map((v, i) => v * a + bottom[i] * (1 - a));

/** Flat colours of the card for one theme: `base` (surface2), `tinted` (palette over it), `glow` (clay over that). */
export function cardSurface(paletteHex, theme) {
  const base = hex(theme.surface2);
  const tinted = mix(hex(paletteHex), base, CARD_TINT);
  const glow = mix(hex(theme.clay), tinted, CARD_GLOW);
  return { base: theme.surface2, tinted: toHex(tinted), glow: toHex(glow) };
}

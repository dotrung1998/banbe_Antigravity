// Event Project Hub, team channels (note 76): up to 5 external links (Zoom, Meet, Zalo…) the Host adds so the team
// can talk outside banbe. iOS twin: apps/ios/BanbeApp/Lib/ProjectChannels.swift. Shared vectors:
// tests/fixtures/project-channel-links.json (also run against sanitize_project_channels in SQL, migration 210).
//
// Same URL rule as sanitize_social_links (migration 102:43): https only, a real host name, nothing else in the host
// part (no port, no user@). Stricter than 102 on platforms: the host must BE the platform domain or a subdomain of
// it, so "evilzoom.us" is not Zoom. One bad entry rejects the whole list, like the server.
import LIMITS from '../data/projectLimits.json' with { type: 'json' };

/** Platform -> accepted domains, in the order the picker lists them. `link` takes any https host. */
export const CHANNEL_PLATFORMS = {
  zoom: ['zoom.us'],
  meet: ['meet.google.com'],
  zalo: ['zalo.me'],
  messenger: ['m.me', 'messenger.com'],
  whatsapp: ['chat.whatsapp.com', 'wa.me'],
  telegram: ['t.me'],
  discord: ['discord.gg', 'discord.com'],
  teams: ['teams.microsoft.com', 'teams.live.com'],
  slack: ['slack.com'],
  link: [],
};

/** Display names (product names, shown as text; never logos). `link` is translated by the caller. */
export const CHANNEL_NAMES = {
  zoom: 'Zoom', meet: 'Google Meet', zalo: 'Zalo', messenger: 'Messenger', whatsapp: 'WhatsApp',
  telegram: 'Telegram', discord: 'Discord', teams: 'Microsoft Teams', slack: 'Slack', link: null,
};

const URL_RE = /^https:\/\/[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(\/.*)?(\?.*)?$/i;

/** Lower-cased host of an https URL that passes the URL rule, else null. */
export function channelHost(url) {
  const u = String(url ?? '').trim();
  if (!u || u.length > LIMITS.channelUrlMax || /[\s\u0000-\u001f\u007f]/.test(u) || !URL_RE.test(u)) return null;
  return u.slice('https://'.length).split(/[/?#]/)[0].toLowerCase();
}

const hostMatches = (host, domain) => host === domain || host.endsWith(`.${domain}`);

/** The platform a pasted URL belongs to ('link' for any other valid https URL), or null when the URL is invalid. */
export function detectChannelPlatform(url) {
  const host = channelHost(url);
  if (!host) return null;
  for (const [p, domains] of Object.entries(CHANNEL_PLATFORMS)) if (domains.some(d => hostMatches(host, d))) return p;
  return 'link';
}

/**
 * One channel -> { ok: true, channel } or { ok: false, error }.
 * Errors: 'url' (not a valid https link), 'platform' (unknown platform or host not on it), 'label' (too long).
 * An empty label becomes the platform name (or '' for `link`; the caller shows its translated "Link").
 */
export function validateChannel(raw) {
  const url = String(raw?.url ?? '').trim();
  const host = channelHost(url);
  if (!host) return { ok: false, error: 'url' };
  const platform = String(raw?.platform ?? '').trim().toLowerCase() || detectChannelPlatform(url);
  if (!(platform in CHANNEL_PLATFORMS)) return { ok: false, error: 'platform' };
  const domains = CHANNEL_PLATFORMS[platform];
  if (domains.length && !domains.some(d => hostMatches(host, d))) return { ok: false, error: 'platform' };
  const label = String(raw?.label ?? '').trim() || CHANNEL_NAMES[platform] || '';
  if ([...label].length > LIMITS.channelLabelMax) return { ok: false, error: 'label' };
  return { ok: true, channel: { platform, label, url, primary: raw?.primary === true } };
}

/**
 * The whole list -> { ok: true, channels } or { ok: false, error, index }.
 * List errors: 'list' (not an array), 'count' (more than 5), 'primary' (more than one starred), 'duplicate' (same URL
 * twice). Same verdict as the server's sanitize_project_channels.
 */
export function sanitizeChannels(list) {
  if (!Array.isArray(list)) return { ok: false, error: 'list', index: -1 };
  if (list.length > LIMITS.channelsMax) return { ok: false, error: 'count', index: -1 };
  const channels = [];
  for (let i = 0; i < list.length; i++) {
    const r = validateChannel(list[i]);
    if (!r.ok) return { ok: false, error: r.error, index: i };
    if (channels.some(c => c.url.toLowerCase() === r.channel.url.toLowerCase())) return { ok: false, error: 'duplicate', index: i };
    channels.push(r.channel);
  }
  if (channels.filter(c => c.primary).length > 1) return { ok: false, error: 'primary', index: -1 };
  return { ok: true, channels };
}

/** Display order: the starred channel first, the rest as the Host ordered them. */
export function orderedChannels(channels) {
  const list = channels || [];
  return [...list.filter(c => c.primary), ...list.filter(c => !c.primary)];
}

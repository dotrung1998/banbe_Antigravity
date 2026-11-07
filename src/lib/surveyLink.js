// ONE canonical survey-link builder, reused by every surface that needs a
// shareable /surveys/<publicId> URL — Copy Link/Share Link (SurveysHosting),
// Share-to-Story, and anywhere else a survey link is ever generated. Before
// this, iOS hardcoded `https://banbe.app` (a domain this deployment does not
// own — DNS/Vercel domain lookup confirmed 403/unattached) while web used
// `window.location.origin` directly at each call site (correct, but
// duplicated, and with no single place to point at a future custom domain).
//
// `PUBLIC_WEB_ORIGIN` defaults to `window.location.origin` — on web this is
// always the real, currently-served origin (so it auto-follows a future
// custom-domain migration with zero code change), with `VITE_PUBLIC_WEB_
// ORIGIN` as an explicit override for the rare case that's wrong (e.g. a
// build ever needs to generate links to a DIFFERENT deployed origin than the
// one currently serving it). iOS has no origin of its own, so its own
// AppConfig.publicWebOrigin constant (AppConfig.swift) is the equivalent
// override point there — see that file's own comment.
export const PUBLIC_WEB_ORIGIN = (
  import.meta.env?.VITE_PUBLIC_WEB_ORIGIN
  || (typeof window !== 'undefined' ? window.location.origin : '')
).replace(/\/+$/, '');

export function surveyPublicUrl(publicId) {
  return `${PUBLIC_WEB_ORIGIN}/surveys/${publicId}`;
}

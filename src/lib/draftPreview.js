// Create-event "Public preview" (owner, 2026-10-21): the unsaved draft shaped like `shapeRealEventAsCurEvent`
// (BanBeContext.jsx) so the REAL Event Detail renders it. Differences from a published event: the key is
// DRAFT_PREVIEW_KEY, nothing is booked (every offered seat is free), and `where` has no distance segment (a draft
// has no "km from you" worth showing — the screenshot that prompted this read "9665,7 km away").
// iOS twin: CatalogEvent.fromDraft (apps/ios/BanbeApp/Models/CatalogEvent.swift).
import { formatVnEventDate } from './countdown.js';
import { formatMoney, parsePriceInput } from './eventMarket.js';

export const DRAFT_PREVIEW_KEY = 'draft-preview';

/** Same parsing createSubmit uses, so the preview price matches what gets saved (minor units of `currency`). */
export function draftPriceVnd(raw, currency = 'VND') {
  if (currency === 'USD') return parsePriceInput(raw, 'USD') ?? 0;
  return parseInt(((raw || '').match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
}

/** { name, catKey, catLabel, area, lat, lng, startsAt (Date|null), priceVnd, seats (number|null), description,
 *  intro, includedItems, inviteOnly, organizerName, coverUrl, timeZone?, currency?, details? } → a curEvent-shaped object.
 *  `timeZone`/`currency` are the form's venue market (migration 195); without them the browser zone and VND. */
export function shapeDraftAsCurEvent(d) {
  const startsAt = d.startsAt && !Number.isNaN(d.startsAt.getTime()) ? d.startsAt : null;
  const currency = d.currency === 'USD' ? 'USD' : 'VND';
  const { weekdayShort, dayMonth, dayLong, time } = startsAt ? formatVnEventDate(startsAt, d.timeZone || undefined) : {};
  const items = (d.includedItems || [])
    .map(it => ({ label: (it.label || '').trim(), detail: (it.detail || '').trim() }))
    .filter(it => it.label);
  const seats = Number.isFinite(d.seats) && d.seats > 0 ? d.seats : null;
  return {
    key: DRAFT_PREVIEW_KEY, catKey: d.catKey || 'all', cat: d.catLabel || '', cat2Key: null, catDisplay: d.catLabel || '',
    name: d.name, img: d.coverUrl || '', lat: d.lat ?? null, lng: d.lng ?? null,
    meta: [d.catLabel, d.area].filter(Boolean).join(' ▪︎ '),
    where: [d.area, dayLong, time].filter(Boolean).join(' ▪︎ '),
    when: startsAt ? `${weekdayShort}, ${dayMonth} ▪︎ ${time}` : '',
    price: d.priceVnd > 0 ? formatMoney(d.priceVnd, currency) : 'Miễn phí',
    priceAmount: d.priceVnd > 0 ? d.priceVnd : 0, currency, tz: d.timeZone || null,
    seats: seats != null ? String(seats) : '',
    seatsLong: seats != null ? `${seats} chỗ trống` : '',
    urgent: false,
    desc: d.description || '', included: items.map(it => it.label).join(' ▪︎ '), includedItems: items, intro: d.intro || '',
    details: d.details || {}, capacity: seats,
    host: d.organizerName || '', hostShort: d.organizerName || '', greeting: '',
    gallery: [], orgGallery: [], orgName: d.organizerName || '', orgIg: '', orgDesc: '',
    orgSince: '', orgCount: 0, orgTrusted: false,
    cancelled: false, cancelledHoursAgo: null, endedHoursAgo: null,
    soldOut: false, inviteOnly: !!d.inviteOnly,
    until: null, untilLabel: '', startDate: startsAt,
    palette: 'concrete', isRealFallback: true,
  };
}

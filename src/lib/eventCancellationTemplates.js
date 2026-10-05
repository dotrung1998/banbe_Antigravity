// Apology templates for the host's "Cancel event" flow. Mirrors
// apps/ios/BanbeApp/Lib/EventCancellationTemplates.swift — keep the two in step.
//
// Placeholders (filled by fillCancellationTemplate):
//   {{guest_name}}      the person's own name in an individual email; in the optional
//                       one-email-to-everyone draft it is "An, Bình and Chi" (long lists shortened)
//   {{event_name}}      {{event_date}}   {{event_place}}   {{organizer_name}}
//
// The host sends from their OWN mailbox, one email per guest, so each guest is
// greeted by name and sees only their own address.

export const CANCELLATION_TEMPLATES = [
  {
    key: 'unforeseen',
    title: { vi: 'Lý do bất khả kháng', en: 'Unforeseen circumstances' },
    reason: { vi: 'Sự kiện bị huỷ do hoàn cảnh bất khả kháng', en: 'Cancelled due to unforeseen circumstances' },
    subject: { vi: 'Thông báo huỷ sự kiện {{event_name}}', en: 'Cancellation of {{event_name}}' },
    body: {
      vi: `Kính gửi {{guest_name}},

Chúng tôi vô cùng tiếc phải thông báo rằng sự kiện "{{event_name}}" dự kiến diễn ra vào {{event_date}} tại {{event_place}} đã phải huỷ do những hoàn cảnh bất khả kháng ngoài khả năng kiểm soát của chúng tôi.

Chúng tôi chân thành xin lỗi vì sự bất tiện này và biết ơn sự quan tâm của bạn. Toàn bộ số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ. Vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền để chúng tôi chuyển khoản cho bạn.

Một lần nữa, thành thật xin lỗi. Hy vọng sớm được gặp bạn ở một sự kiện khác.

Trân trọng,
{{organizer_name}}`,
      en: `Dear {{guest_name}},

We are very sorry to let you know that "{{event_name}}", planned for {{event_date}} at {{event_place}}, has had to be cancelled because of circumstances beyond our control.

Please accept our sincere apologies for the disruption, and our thanks for your support. Every ticket you paid for will be refunded in full. Please open the banbe app and add the account you'd like your refund sent to, and we will transfer it to you.

Once again, we are truly sorry, and we hope to welcome you at a future event.

Kind regards,
{{organizer_name}}`,
    },
  },
  {
    key: 'venue',
    title: { vi: 'Địa điểm không còn khả dụng', en: 'Venue no longer available' },
    reason: { vi: 'Sự kiện bị huỷ vì địa điểm không còn khả dụng', en: 'Cancelled because the venue is no longer available' },
    subject: { vi: 'Về sự kiện {{event_name}}: địa điểm không còn khả dụng', en: 'About {{event_name}}: venue unavailable' },
    body: {
      vi: `Kính gửi {{guest_name}},

Rất tiếc, địa điểm của sự kiện "{{event_name}}" ({{event_place}}) không còn khả dụng vào {{event_date}} và chúng tôi chưa tìm được địa điểm thay thế phù hợp, nên buổi gặp mặt buộc phải huỷ.

Chúng tôi thành thật xin lỗi vì đã làm thay đổi kế hoạch của bạn. Số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ; vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

Nếu sau này có địa điểm mới, chúng tôi sẽ báo cho bạn đầu tiên.

Trân trọng,
{{organizer_name}}`,
      en: `Dear {{guest_name}},

Unfortunately the venue for "{{event_name}}" ({{event_place}}) is no longer available on {{event_date}}, and we have not been able to secure a suitable alternative, so we have to cancel the event.

We are sincerely sorry for upsetting your plans. Every ticket you paid for will be refunded in full; please open the banbe app and add the account you'd like your refund sent to.

If we find a new venue, you will be the first to hear about it.

Kind regards,
{{organizer_name}}`,
    },
  },
  {
    key: 'low_turnout',
    title: { vi: 'Chưa đủ số lượng đăng ký', en: 'Not enough sign-ups' },
    reason: { vi: 'Sự kiện bị huỷ vì chưa đủ số lượng đăng ký', en: 'Cancelled because there were not enough sign-ups' },
    subject: { vi: 'Thông báo huỷ {{event_name}}', en: 'Update on {{event_name}}' },
    body: {
      vi: `Kính gửi {{guest_name}},

Cảm ơn bạn đã đăng ký tham gia "{{event_name}}" vào {{event_date}}. Rất tiếc, số lượng đăng ký chưa đủ để chúng tôi tổ chức sự kiện với chất lượng như đã hứa, nên chúng tôi quyết định huỷ.

Chúng tôi xin lỗi vì quyết định này đến muộn hơn mong muốn và vì sự bất tiện bạn gặp phải. Toàn bộ số tiền vé sẽ được hoàn lại; vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

Chúng tôi rất trân trọng sự ủng hộ của bạn và hy vọng sẽ sớm tổ chức lại.

Trân trọng,
{{organizer_name}}`,
      en: `Dear {{guest_name}},

Thank you for signing up for "{{event_name}}" on {{event_date}}. Unfortunately, not enough people have registered for us to run the event to the standard we promised, so we have decided to cancel it.

We apologise that this decision comes later than we would have liked, and for the inconvenience. All ticket payments will be refunded in full; please open the banbe app and add the account you'd like your refund sent to.

We truly appreciate your support and hope to run this again soon.

Kind regards,
{{organizer_name}}`,
    },
  },
  {
    key: 'safety',
    title: { vi: 'An toàn hoặc thời tiết', en: 'Safety or weather' },
    reason: { vi: 'Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết', en: 'Cancelled for safety or weather reasons' },
    subject: { vi: '{{event_name}} bị huỷ vì lý do an toàn', en: '{{event_name}} cancelled for safety reasons' },
    body: {
      vi: `Kính gửi {{guest_name}},

Vì sự an toàn của tất cả mọi người, chúng tôi buộc phải huỷ sự kiện "{{event_name}}" dự kiến vào {{event_date}} tại {{event_place}} do điều kiện thời tiết hoặc an toàn không đảm bảo.

Chúng tôi rất tiếc và xin lỗi vì sự thay đổi này. Số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ. Vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

Cảm ơn bạn đã thông cảm. Chúc bạn bình an.

Trân trọng,
{{organizer_name}}`,
      en: `Dear {{guest_name}},

For everyone's safety, we have had to cancel "{{event_name}}", planned for {{event_date}} at {{event_place}}, because of unsafe weather or conditions.

We are very sorry for the change. Every ticket you paid for will be refunded in full. Please open the banbe app and add the account you'd like your refund sent to.

Thank you for your understanding. Please stay safe.

Kind regards,
{{organizer_name}}`,
    },
  },
];

const MAX_NAMES = 6;

/** "An, Bình and Chi"; past MAX_NAMES it names the first few and counts the rest. */
export function joinNames(names, lang) {
  const list = names.map((n) => (n || '').trim()).filter(Boolean);
  if (!list.length) return lang === 'en' ? 'everyone' : 'các bạn';
  const and = lang === 'en' ? 'and' : 'và';
  if (list.length === 1) return list[0];
  if (list.length <= MAX_NAMES) return `${list.slice(0, -1).join(', ')} ${and} ${list[list.length - 1]}`;
  const rest = list.length - MAX_NAMES;
  return `${list.slice(0, MAX_NAMES).join(', ')} ${and} ${rest} ${lang === 'en' ? 'others' : 'bạn khác'}`;
}

/** Replaces {{placeholders}}; an unknown one is left visible rather than silently dropped. */
export function fillCancellationTemplate(text, values) {
  return text.replace(/\{\{(\w+)\}\}/g, (m, k) => (values[k] !== undefined && values[k] !== '' ? values[k] : m));
}

/**
 * `guestName` set → an individual email to that person. Omitted → the group
 * draft, greeted with everyone's names (used for the single BCC draft).
 */
export function buildCancellationDraft(template, lang, { guestName, guestNames = [], eventName, eventDate, eventPlace, organizerName }) {
  const single = (guestName || '').trim();
  const greeting = guestName !== undefined
    ? (single || (lang === 'en' ? 'there' : 'bạn'))
    : joinNames(guestNames, lang);
  const values = {
    guest_name: greeting,
    event_name: eventName,
    event_date: eventDate,
    event_place: eventPlace || (lang === 'en' ? 'the venue' : 'địa điểm đã thông báo'),
    organizer_name: organizerName,
  };
  return {
    subject: fillCancellationTemplate(template.subject[lang], values),
    body: fillCancellationTemplate(template.body[lang], values),
    reason: template.reason[lang],
  };
}

/** mailto: draft. `to` addresses one person; `bcc` is for the single group draft so nobody sees anyone else's address. */
export function buildMailtoUrl({ to = [], bcc = [] }, subject, body) {
  const q = [
    bcc.length ? `bcc=${bcc.map(encodeURIComponent).join(',')}` : '',
    `subject=${encodeURIComponent(subject)}`,
    `body=${encodeURIComponent(body)}`,
  ].filter(Boolean).join('&');
  return `mailto:${to.map(encodeURIComponent).join(',')}?${q}`;
}

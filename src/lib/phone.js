// Phone helpers for the account gate (web parity with iOS Lib/AccountEnrollment.swift
// `PhoneCountry`). Output is E.164: "+" and 8-15 digits.

export const PHONE_COUNTRIES = [
  { iso: 'VN', dial: '84', vi: 'Việt Nam', en: 'Vietnam', trunkZero: true },
  { iso: 'US', dial: '1', vi: 'Hoa Kỳ', en: 'United States', trunkZero: false },
  { iso: 'CA', dial: '1', vi: 'Canada', en: 'Canada', trunkZero: false },
  { iso: 'GB', dial: '44', vi: 'Vương quốc Anh', en: 'United Kingdom', trunkZero: true },
  { iso: 'AU', dial: '61', vi: 'Úc', en: 'Australia', trunkZero: true },
  { iso: 'SG', dial: '65', vi: 'Singapore', en: 'Singapore', trunkZero: false },
  { iso: 'JP', dial: '81', vi: 'Nhật Bản', en: 'Japan', trunkZero: true },
  { iso: 'KR', dial: '82', vi: 'Hàn Quốc', en: 'South Korea', trunkZero: true },
  { iso: 'FR', dial: '33', vi: 'Pháp', en: 'France', trunkZero: true },
  { iso: 'DE', dial: '49', vi: 'Đức', en: 'Germany', trunkZero: true },
  { iso: 'TH', dial: '66', vi: 'Thái Lan', en: 'Thailand', trunkZero: true },
  { iso: 'MY', dial: '60', vi: 'Malaysia', en: 'Malaysia', trunkZero: true },
  { iso: 'PH', dial: '63', vi: 'Philippines', en: 'Philippines', trunkZero: true },
  { iso: 'TW', dial: '886', vi: 'Đài Loan', en: 'Taiwan', trunkZero: true },
  { iso: 'CN', dial: '86', vi: 'Trung Quốc', en: 'China', trunkZero: false },
  { iso: 'IN', dial: '91', vi: 'Ấn Độ', en: 'India', trunkZero: false },
];

export const DEFAULT_PHONE_COUNTRY = PHONE_COUNTRIES[0];

export function flagOf(iso) {
  return String.fromCodePoint(...[...iso].map(c => 127397 + c.charCodeAt(0)));
}

/** E.164 from a country and what the user typed, or null when it can't be valid. */
export function toE164(country, raw) {
  const trimmed = String(raw || '').trim();
  let digits = trimmed.replace(/\D/g, '');
  if (!digits) return null;
  if (trimmed.startsWith('+')) return digits.length >= 8 && digits.length <= 15 ? `+${digits}` : null;
  if (country.trunkZero && digits.startsWith('0')) digits = digits.slice(1);
  const total = country.dial.length + digits.length;
  if (digits.length < 6 || total > 15 || total < 8) return null;
  return `+${country.dial}${digits}`;
}

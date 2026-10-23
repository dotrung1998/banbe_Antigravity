// Day / Month / Year -> validated ISO date ("YYYY-MM-DD"). Mirrors iOS
// DateOfBirthInput: real calendar dates only, not in the future, year >= 1900
// (the server rejects the same). Additionally rejects an implausible age
// (> 120 years). The value is only ever sent to the account-gate RPCs.
// `minAge` (migration 197: 16) is passed only where a NEW date of birth is saved; confirming or deleting an
// existing account never re-checks age.

export const digitsOnly = (s, max) => String(s || '').replace(/\D/g, '').slice(0, max);

function isRealDate(y, m, d) {
  if (m < 1 || m > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return d <= days[m - 1];
}

export const MIN_AGE = 16;

/** The latest date of birth that is at least `minAge` years old today (local calendar), as { y, m, d }. */
export function latestDobFor(minAge, now = new Date()) {
  const y = now.getFullYear() - minAge, m = now.getMonth() + 1;
  // 29 February today -> 28 February `minAge` years ago when that year has no 29th.
  const d = Math.min(now.getDate(), isRealDate(y, m, now.getDate()) ? now.getDate() : 28);
  return { y, m, d };
}

/** Returns { iso } or { problem: 'incomplete'|'tooOld'|'invalidDate'|'future'|'implausible'|'tooYoung' }. */
export function validateDob({ day, month, year }, now = new Date(), { minAge } = {}) {
  if (!day || !month || String(year).length !== 4) return { problem: 'incomplete' };
  const d = Number(day), m = Number(month), y = Number(year);
  if (y < 1900) return { problem: 'tooOld' };
  if (!isRealDate(y, m, d)) return { problem: 'invalidDate' };
  const ty = now.getFullYear(), tm = now.getMonth() + 1, td = now.getDate();
  if (y > ty || (y === ty && (m > tm || (m === tm && d > td)))) return { problem: 'future' };
  if (ty - y > 120) return { problem: 'implausible' };
  if (minAge) {
    const l = latestDobFor(minAge, now);
    if (y > l.y || (y === l.y && (m > l.m || (m === l.m && d > l.d)))) return { problem: 'tooYoung' };
  }
  const pad = (n, w) => String(n).padStart(w, '0');
  return { iso: `${pad(y, 4)}-${pad(m, 2)}-${pad(d, 2)}` };
}

export function dobProblemText(problem, T) {
  switch (problem) {
    case 'incomplete': return T('Nhập đủ ngày, tháng và năm (4 chữ số).', 'Enter the day, month and a 4-digit year.');
    case 'invalidDate': return T('Ngày này không có trong lịch.', "That date doesn't exist.");
    case 'future': return T('Ngày sinh không thể ở tương lai.', "Date of birth can't be in the future.");
    case 'tooOld': return T('Hãy nhập năm sinh từ 1900 trở đi.', 'Enter a year from 1900 onward.');
    case 'tooYoung': return T('banbe dành cho người từ 16 tuổi trở lên.', 'banbe is for people aged 16 and over.');
    default: return T('Ngày sinh này chưa hợp lý. Hãy kiểm tra lại năm sinh.', "That date of birth doesn't look right. Check the year.");
  }
}

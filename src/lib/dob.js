// Day / Month / Year -> validated ISO date ("YYYY-MM-DD"). Mirrors iOS
// DateOfBirthInput: real calendar dates only, not in the future, year >= 1900
// (the server rejects the same). Additionally rejects an implausible age
// (> 120 years). The value is only ever sent to the account-gate RPCs.

export const digitsOnly = (s, max) => String(s || '').replace(/\D/g, '').slice(0, max);

function isRealDate(y, m, d) {
  if (m < 1 || m > 12 || d < 1) return false;
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return d <= days[m - 1];
}

/** Returns { iso } or { problem: 'incomplete'|'tooOld'|'invalidDate'|'future'|'implausible' }. */
export function validateDob({ day, month, year }, now = new Date()) {
  if (!day || !month || String(year).length !== 4) return { problem: 'incomplete' };
  const d = Number(day), m = Number(month), y = Number(year);
  if (y < 1900) return { problem: 'tooOld' };
  if (!isRealDate(y, m, d)) return { problem: 'invalidDate' };
  const ty = now.getFullYear(), tm = now.getMonth() + 1, td = now.getDate();
  if (y > ty || (y === ty && (m > tm || (m === tm && d > td)))) return { problem: 'future' };
  if (ty - y > 120) return { problem: 'implausible' };
  const pad = (n, w) => String(n).padStart(w, '0');
  return { iso: `${pad(y, 4)}-${pad(m, 2)}-${pad(d, 2)}` };
}

export function dobProblemText(problem, T) {
  switch (problem) {
    case 'incomplete': return T('Nhập đủ ngày, tháng và năm (4 chữ số).', 'Enter the day, month and a 4-digit year.');
    case 'invalidDate': return T('Ngày này không có trong lịch.', "That date doesn't exist.");
    case 'future': return T('Ngày sinh không thể ở tương lai.', "Date of birth can't be in the future.");
    case 'tooOld': return T('Hãy nhập năm sinh từ 1900 trở đi.', 'Enter a year from 1900 onward.');
    default: return T('Ngày sinh này chưa hợp lý. Hãy kiểm tra lại năm sinh.', "That date of birth doesn't look right. Check the year.");
  }
}

// Note 69: which Account tabs exist. The tabs come back after note 67, but they follow Hosting mode instead of being
// fixed:
//   Hosting off, not admin  -> no tabs (one page)
//   Hosting off, admin      -> Personal · Admin
//   Hosting on              -> Host · Personal (Host first and selected when hosting turns on), then Admin for admins
// iOS twin: apps/ios/BanbeApp/Lib/AccountTabs.swift.

export function accountTabs({ isAdmin, hostMode }) {
  const out = hostMode ? ['host', 'personal'] : (isAdmin ? ['personal'] : []);
  if (isAdmin) out.push('admin');
  return out;
}

/** The tab to show: the stored one while it still exists, otherwise the first tab (Personal when there are none). */
export function resolveAccountTab(selected, tabs) {
  return tabs.includes(selected) ? selected : (tabs[0] || 'personal');
}

// Read-only guest browsing — web mirror of iOS `State/AppState+GuestAccess.swift` (note 48). Pure: no React, no
// network; tests/unit/guestAccess.test.mjs.
//
// A signed-out visitor may browse Home, Map and an event (public data only — see note 48's audit and this pass's
// web audit in note 49). Anything personal asks first with a contextual prompt ("Continue" = create an account,
// "Log in", "Not now"); signing in resumes what they were doing.

/** The screens a guest can browse (on top of the pre-login screens). */
// 'search' (note 50): the Search screen only reads public events, same as Home/Map.
export const GUEST_BROWSE_SCREENS = new Set(['home', 'mapExplore', 'event', 'search']);

// 'host' / 'schedule' / 'invite': the Simple Shell (switch simple_shell) mode switch and centre "+" rows (note 66).
export const PROMPT_CONTEXTS = ['save', 'follow', 'reserve', 'message', 'like', 'host', 'schedule', 'invite'];

export function promptCopy(context, T) {
  switch (context) {
    case 'save': return { title: T('Lưu sự kiện này', 'Save this event'), body: T('Đăng nhập để lưu sự kiện và xem lại trên mọi thiết bị.', 'Log in to keep your saved events on every device.') };
    case 'follow': return { title: T('Theo dõi host này', 'Follow this host'), body: T('Đăng nhập để nhận sự kiện mới của host bạn theo dõi.', 'Log in to hear about new events from hosts you follow.') };
    case 'reserve': return { title: T('Giữ chỗ của bạn', 'Hold your seat'), body: T('Đăng nhập để giữ chỗ. Bạn sẽ quay lại đúng sự kiện này.', "Log in to hold your seat. You'll come right back to this event.") };
    case 'message': return { title: T('Nhắn tin cho host', 'Message the host'), body: T('Đăng nhập để nhắn tin. Bạn sẽ quay lại đúng cuộc trò chuyện này.', "Log in to send a message. You'll come right back to this chat.") };
    case 'like': return { title: T('Thích ảnh này', 'Like this photo'), body: T('Đăng nhập để thích ảnh và ủng hộ host.', 'Log in to like photos and support the host.') };
    case 'host': return { title: T('Tổ chức sự kiện', 'Host an event'), body: T('Đăng nhập để tổ chức. Miễn phí, tắt lúc nào cũng được.', 'Log in to host. It is free and you can turn it off any time.') };
    case 'schedule': return { title: T('Lịch của bạn', 'Your schedule'), body: T('Đăng nhập để lưu kế hoạch vào lịch và xem trên mọi thiết bị.', 'Log in to keep plans in your schedule on every device.') };
    case 'invite': return { title: T('Mời bạn bè', 'Invite friends'), body: T('Đăng nhập để nhận link mời của riêng bạn.', 'Log in to get your own invite link.') };
    default: return { title: T('Đăng nhập để tiếp tục', 'Log in to continue'), body: '' };
  }
}

/** Three benefit rows, the one matching the guest's action first (iOS order). */
export function promptBenefits(context, T) {
  const rows = [
    { id: 'save', icon: '♡', text: T('Lưu sự kiện, xem lại trên mọi thiết bị', 'Save events and see them on every device') },
    { id: 'reserve', icon: '🎟', text: T('Giữ chỗ trong vài giây, nhận vé QR', 'Hold a seat in seconds, get a QR ticket') },
    { id: 'message', icon: '💬', text: T('Nhắn trực tiếp cho host', 'Message hosts directly') },
  ];
  const i = rows.findIndex(r => r.id === context);
  if (i > 0) rows.unshift(...rows.splice(i, 1));
  if (context === 'follow') rows[2] = { id: 'follow', icon: '🔔', text: T('Biết ngay khi host bạn theo dõi có sự kiện mới', 'Hear first when hosts you follow post events') };
  return rows;
}

/**
 * A guest prompt: { context, returnTo, resume } where resume is null | { type: 'reserve', eventKey } |
 * { type: 'chat', eventKey, back } | { type: 'host' }. `returnTo` is where sign-in comes back to.
 */
export function makePrompt(context, { screen, eventKey } = {}) {
  const resume = context === 'reserve' && eventKey ? { type: 'reserve', eventKey }
    : context === 'message' && eventKey ? { type: 'chat', eventKey, back: screen === 'event' ? 'event' : 'home' }
      // Simple Shell follow-up (note 66): after sign-in, Start hosting carries on (invitation or Home > Hosting).
      : context === 'host' ? { type: 'host' }
        : null;
  return { context, returnTo: GUEST_BROWSE_SCREENS.has(screen) ? screen : 'home', resume };
}

/** Where Login's Back goes for a signed-out visitor: back to the browse screen they came from, else Welcome. */
export function loginBackTarget(fromScreen) {
  return GUEST_BROWSE_SCREENS.has(fromScreen) ? fromScreen : 'welcome';
}

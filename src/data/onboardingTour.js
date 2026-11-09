// The guided tour over the real app (note 64), forward-only chapters since onboarding v5 (note 80). iOS twin: Models/OnboardingTourContent.swift —
// tests/unit/onboardingTour.test.mjs checks both have the same step ids, targets, screens and order.
//
// Each step points at a REAL control by a stable target id. Web resolves the id to an existing data-testid (the
// tour never adds a copy of the control); iOS publishes the same ids with `.tourTarget(_:)`.
// `requires`: a step that only makes sense in some states ('organizerMode'). A step whose target is not on screen
// after a short wait (no events yet, no For You matches) is skipped instead of pointing at nothing.

export const TOUR_STEPS = [
  {
    id: 'home.search', target: 'tour.home.search', screen: 'home', placement: 'below',
    vi: ['Tìm kiếm và khu vực', 'Tìm sự kiện, host hay địa điểm. Mọi danh sách trên Trang chính đều theo khu vực bạn chọn.'],
    en: ['Search and area', 'Search events, hosts or places. Every list on Home follows the area you pick.'],
    short: ['Tìm kiếm', 'Search'],
  },
  {
    id: 'home.forYou', target: 'tour.home.forYou', screen: 'home', placement: 'below',
    vi: ['Gợi ý Dành cho bạn', 'Làm từ câu trả lời bạn vừa chọn. Chấm vàng nghĩa là có gợi ý mới.'],
    en: ['Your For You picks', 'Built from the answers you just gave. A gold dot means there are new picks.'],
    short: ['Dành cho bạn', 'For You'],
  },
  {
    id: 'home.eventCard', target: 'tour.home.eventCard', screen: 'home', placement: 'below',
    vi: ['Mở một sự kiện', 'Chạm vào thẻ để xem chi tiết, giữ chỗ hoặc nhắn host. Giữ chỗ miễn phí trong 30 phút.'],
    en: ['Open an event', 'Tap a card to see details, hold a seat or message the host. A hold is free for 30 minutes.'],
    short: ['Sự kiện', 'Event'],
  },
  {
    id: 'dock.map', target: 'tour.dock.map', screen: 'home', placement: 'above',
    vi: ['Bản đồ', 'Xem sự kiện quanh bạn, theo khu phố và theo giờ.'],
    en: ['Map', "See what's on around you, by neighbourhood and by time."],
    short: ['Bản đồ', 'Map'],
  },
  {
    id: 'dock.schedule', target: 'tour.dock.schedule', screen: 'home', placement: 'above',
    vi: ['Lịch', 'Mọi vé và buổi bạn đã lưu, xếp theo ngày.'],
    en: ['Schedule', 'Every ticket and saved plan, day by day.'],
    short: ['Lịch', 'Schedule'],
  },
  {
    id: 'dock.inbox', target: 'tour.dock.inbox', screen: 'home', placement: 'above',
    vi: ['Tin nhắn', 'Trò chuyện với host và đội sự kiện, cùng cập nhật về vé của bạn. Huy hiệu đếm tin chưa đọc.'],
    en: ['Messages', "Conversations with hosts and event teams, and updates about your tickets. The badge counts what's unread."],
    short: ['Tin nhắn', 'Messages'],
  },
  {
    id: 'account.organizerMode', target: 'tour.account.organizerMode', screen: 'profile', placement: 'below',
    vi: ['Chế độ tổ chức', 'Đang tắt, như bạn đã chọn. Bật lúc nào bạn muốn tổ chức một sự kiện.'],
    en: ['Hosting mode', 'Off, as you chose. Turn it on any time you want to run an event.'],
    short: ['Tổ chức', 'Host'],
  },
  {
    id: 'dock.create', target: 'tour.dock.create', screen: 'profile', placement: 'above', requires: 'organizerMode',
    vi: ['Tạo sự kiện', 'Nút + này mở trình tạo sự kiện 5 bước. Mất khoảng 5 phút.'],
    en: ['Create an event', 'This + opens the 5-step event builder. It takes about 5 minutes.'],
    short: ['Tạo', 'Create'],
  },
];

/** Web: semantic target id → the existing control's data-testid (first match in DOM order). */
export const WEB_TARGETS = {
  'tour.home.search': '[data-testid="home-search-bar"]',
  'tour.home.forYou': '[data-testid="home-filter-foryou"]',
  'tour.home.eventCard': '[data-testid^="home-event-"]',
  'tour.dock.map': '[data-testid="tab-map"]',
  'tour.dock.schedule': '[data-testid="tab-schedule"]',
  'tour.dock.inbox': '[data-testid="tab-inbox"]',
  'tour.account.organizerMode': '[data-testid="organizer-mode-toggle"]',
  'tour.dock.create': '[data-testid="dock-create-button"]',
  // Simple Shell (switch simple_shell, note 66): Map is a Home view and the mode switch sits in Home's header.
  'tour.home.mapView': '[data-testid="home-layout-map"]',
  'tour.home.modeSwitch': '[data-testid="home-mode-switch"]',
};

// Simple Shell retargets (same ids, same order, still 8 steps): the Map step points at Home's map view toggle, the
// organizer-mode step at Home's "Going out | Hosting" switch, and the "+" step is for everyone (the "+" always shows).
const SIMPLE_SHELL_OVERRIDES = {
  'dock.map': {
    target: 'tour.home.mapView', screen: 'home', placement: 'above',
    vi: ['Bản đồ', 'Xem các sự kiện này trên bản đồ, ngay từ Trang chính.'],
    en: ['Map', 'See these events on a map, right from Home.'],
  },
  'account.organizerMode': {
    target: 'tour.home.modeSwitch', screen: 'home', placement: 'below',
    vi: ['Muốn tổ chức?', 'Chạm Tổ chức để tạo sự kiện của riêng bạn. Chuyển lại Đi chơi lúc nào cũng được.'],
    en: ['Want to host?', 'Tap Hosting to create your own events. Switch back to Going out any time.'],
  },
  'dock.create': {
    requires: undefined,
    vi: ['Nút +', 'Thêm kế hoạch, mời bạn bè hoặc tạo sự kiện khi bạn đang tổ chức.'],
    en: ['The + button', 'Add plans, invite friends, or create an event while you are hosting.'],
  },
};

/** The steps this account can see, in order. */
export function eligibleSteps(ctx) {
  const steps = ctx?.simpleShell ? TOUR_STEPS.map(st => (SIMPLE_SHELL_OVERRIDES[st.id] ? { ...st, ...SIMPLE_SHELL_OVERRIDES[st.id] } : st)) : TOUR_STEPS;
  return steps.filter(st => !st.requires || !!ctx?.[st.requires]);
}

export const tourDoneKey = uid => `banbe.tour.v3.done.${uid}`;

/** Three short chapters (note 80, iOS twin `OnboardingTourContent.chapters`). A chapter with no eligible step is dropped. */
export const TOUR_CHAPTERS = [
  { id: 'discover', name: ['Khám phá', 'Discover'], stepIds: ['home.search', 'home.forYou', 'home.eventCard', 'dock.map'] },
  { id: 'plans', name: ['Lịch và tin nhắn', 'Plans and messages'], stepIds: ['dock.schedule', 'dock.inbox'] },
  { id: 'you', name: ['Tài khoản của bạn', 'Your account'], stepIds: ['account.organizerMode', 'dock.create'] },
];

/**
 * "Do it" steps only move on when the highlighted control is clicked. The overlay then runs that control's own
 * action itself; the real control underneath is never pressed.
 */
export const TOUR_DO_IT = {
  'home.forYou': ['Chạm Dành cho bạn', 'Tap For You'],
};

/** The hosting step speaks to what the person chose during setup. */
export const HOSTING_ON_COPY = {
  vi: ['Chế độ tổ chức', 'Bạn đã bật lúc thiết lập. Nó thêm công cụ tổ chức: tạo sự kiện, check-in khách và nhận tiền.'],
  en: ['Hosting mode', 'You turned this on during setup. It adds the hosting tools: create events, check guests in and get paid.'],
};

/** The eligible steps grouped into their chapters, in tour order: [{ chapter, steps }]. */
export function tourPlan(ctx) {
  const byId = new Map(eligibleSteps(ctx).map(st => [st.id, st]));
  return TOUR_CHAPTERS.map(chapter => ({ chapter, steps: chapter.stepIds.map(id => byId.get(id)).filter(Boolean) }))
    .filter(c => c.steps.length);
}

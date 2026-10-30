// Onboarding Version 3: the guided tour over the real app (note 64). iOS twin: Models/OnboardingTourContent.swift —
// tests/unit/onboardingTour.test.mjs checks both have the same step ids, targets, screens and order.
//
// Each step points at a REAL control by a stable target id. Web resolves the id to an existing data-testid (the
// tour never adds a copy of the control); iOS publishes the same ids with `.tourTarget(_:)`.
// `requires`: a step that only makes sense in some states ('organizerMode'). A step whose target is not on screen
// after a short wait (no events yet, no For You matches) is skipped instead of pointing at nothing.

export const TOUR_STEPS = [
  {
    id: 'home.search', target: 'tour.home.search', screen: 'home', placement: 'below',
    vi: ['Tìm mọi thứ ở đây', 'Gõ tên sự kiện, host hay khu vực. Kết quả hiện ngay khi bạn gõ.'],
    en: ['Find anything here', 'Type an event, a host or an area. Results show up as you type.'],
    short: ['Tìm kiếm', 'Search'],
  },
  {
    id: 'home.forYou', target: 'tour.home.forYou', screen: 'home', placement: 'below',
    vi: ['Dành cho bạn', 'Lọc theo câu trả lời của bạn lúc bắt đầu. Chấm vàng nghĩa là có gợi ý mới.'],
    en: ['For You', 'Filters by the answers you gave at the start. A gold dot means there are new picks.'],
    short: ['Dành cho bạn', 'For You'],
  },
  {
    id: 'home.eventCard', target: 'tour.home.eventCard', screen: 'home', placement: 'below',
    vi: ['Một sự kiện', 'Chạm vào thẻ để xem chi tiết, giữ chỗ hoặc nhắn host. Giữ chỗ miễn phí trong 30 phút.'],
    en: ['An event', 'Tap a card to see details, hold a seat or message the host. A hold is free for 30 minutes.'],
    short: ['Sự kiện', 'Event'],
  },
  {
    id: 'dock.map', target: 'tour.dock.map', screen: 'home', placement: 'above',
    vi: ['Bản đồ', 'Xem sự kiện quanh bạn trên bản đồ.'],
    en: ['Map', 'See what is on around you on a map.'],
    short: ['Bản đồ', 'Map'],
  },
  {
    id: 'dock.schedule', target: 'tour.dock.schedule', screen: 'home', placement: 'above',
    vi: ['Lịch', 'Vé và những buổi bạn đã lưu, xếp theo ngày.'],
    en: ['Schedule', 'Your tickets and saved plans, day by day.'],
    short: ['Lịch', 'Schedule'],
  },
  {
    id: 'dock.inbox', target: 'tour.dock.inbox', screen: 'home', placement: 'above',
    vi: ['Tin nhắn', 'Trò chuyện với host và nhận cập nhật về vé của bạn.'],
    en: ['Messages', 'Chat with hosts and get updates about your tickets.'],
    short: ['Tin nhắn', 'Messages'],
  },
  {
    id: 'account.organizerMode', target: 'tour.account.organizerMode', screen: 'profile', placement: 'below',
    vi: ['Muốn tổ chức?', 'Bật chế độ tổ chức ở đây để tạo sự kiện của riêng bạn. Tắt lúc nào cũng được.'],
    en: ['Want to host?', 'Turn on organizer mode here to create your own events. Turn it off any time.'],
    short: ['Tổ chức', 'Host'],
  },
  {
    id: 'dock.create', target: 'tour.dock.create', screen: 'profile', placement: 'above', requires: 'organizerMode',
    vi: ['Tạo sự kiện', 'Nút + này mở trình tạo sự kiện 5 bước.'],
    en: ['Create an event', 'This + opens the 5-step event builder.'],
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

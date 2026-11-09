// The guided tour over the real app (note 64), forward-only chapters since onboarding v5 (note 80). iOS twin: Models/OnboardingTourContent.swift —
// tests/unit/onboardingTour.test.mjs checks both have the same step ids, targets, screens and order.
//
// Each step points at a REAL control by a stable target id. Web resolves the id to an existing data-testid (the
// tour never adds a copy of the control); iOS publishes the same ids with `.tourTarget(_:)`.
// `requires`: a step that only makes sense in some states ('organizerMode'). A step whose target is not on screen
// after a short wait (no events yet, no For You matches) is skipped instead of pointing at nothing.

export const TOUR_STEPS = [
  { id: 'home.forYou', target: 'tour.home.forYou', screen: 'home', placement: 'below',
    vi: ['Gợi ý Dành cho bạn', 'Làm từ câu trả lời bạn vừa chọn. Vuốt ngang để xem thêm, chạm vào thẻ để mở sự kiện.'],
    en: ['Your For You picks', 'Built from the answers you just gave. Swipe sideways for more, and tap a card to open the event.'] },
  { id: 'home.tonight', target: 'tour.home.tonight', screen: 'home', placement: 'below',
    vi: ['Ba cách vào xem', 'Dành cho bạn là của riêng bạn. Tối nay là mọi thứ diễn ra hôm nay. Cuối tuần gồm thứ Bảy và Chủ nhật.'],
    en: ['Three ways in', 'For You is yours. Tonight is everything on today. Weekend covers Saturday and Sunday.'] },
  { id: 'home.tabPicks', target: 'tour.home.rail', screen: 'home', placement: 'below',
    vi: ['Danh sách theo tab', 'Các gợi ý bên dưới đổi theo tab bạn chọn. Hôm nay chưa có gì thì tab sẽ báo trống.'],
    en: ['Picks follow the tab', 'The picks below change with the tab you choose. If nothing is on, the tab says so.'] },
  { id: 'home.search', target: 'tour.home.search', screen: 'home', placement: 'below',
    vi: ['Tìm kiếm và khu vực', 'Tìm sự kiện, host hay địa điểm. Chấm ghim đặt khu vực, và mọi danh sách trên Trang chính đều theo khu vực đó.'],
    en: ['Search and area', 'Search events, hosts or places. The pin sets your area, and every list on Home follows it.'] },
  { id: 'home.browse', target: 'tour.home.browse', screen: 'home', placement: 'below',
    vi: ['Duyệt theo loại', 'Năm loại phổ biến, cùng Tìm một loại để tìm theo tên, như rượu vang hay phim.'],
    en: ['Browse by type', 'Five popular types, plus Find a type to search all of them by name, like wine or film.'] },
  { id: 'home.filters', target: 'tour.home.filters', screen: 'home', placement: 'above',
    vi: ['Bộ lọc, đặt một lần', 'Dòng này cho biết bộ lọc của bạn. Chạm để đổi ngày, giá, chỗ hoặc khu vực. Bộ lọc áp dụng cho mọi danh sách.'],
    en: ['Filters, set once', 'This line shows your filters. Tap it to change date, price, seats or area. The same filters apply on every list.'] },
  { id: 'dock.schedule', target: 'tour.dock.schedule', screen: 'home', placement: 'above',
    vi: ['Lịch', 'Mọi vé và buổi bạn đã lưu, xếp theo ngày.'],
    en: ['Schedule', 'Every ticket and saved plan, day by day.'] },
  { id: 'dock.activity', target: 'tour.dock.inbox', screen: 'home', placement: 'above',
    vi: ['Hoạt động', 'Tin nhắn với host và cập nhật về vé, thanh toán của bạn, gom một chỗ. Huy hiệu đếm những gì chưa đọc.'],
    en: ['Activity', "Messages with hosts and updates about your tickets and payments, in one place. The badge counts what's unread."] },
  { id: 'activity.tabs', target: 'tour.activity.tabs', screen: 'inbox', placement: 'below',
    vi: ['Tin nhắn và Thông báo', 'Tin nhắn là các cuộc trò chuyện: host, đội sự kiện, tranh chấp. Thông báo là cập nhật: vé, thanh toán, sự kiện. Không có gì hiện hai lần.'],
    en: ['Messages and Notifications', 'Messages are conversations: hosts, event teams, disputes. Notifications are updates: tickets, payments, events. Nothing shows up twice.'] },
  { id: 'dock.account', target: 'tour.dock.account', screen: 'inbox', placement: 'above',
    vi: ['Tài khoản', 'Hồ sơ, vé, ví và cài đặt của bạn.'],
    en: ['Account', 'Your profile, tickets, wallet and settings.'] },
  { id: 'account.shortcuts', target: 'tour.account.shortcuts', screen: 'profile', placement: 'below',
    vi: ['Bốn lối tắt hay dùng', 'Vé kèm mã QR, Ví cho thông tin thanh toán, sự kiện Đã lưu và Phần thưởng.'],
    en: ['The four you’ll use most', 'Tickets with their QR codes, Wallet for payment details, Saved events, and Rewards.'] },
  { id: 'account.organizerMode', target: 'tour.account.organizerMode', screen: 'profile', placement: 'below',
    vi: ['Chế độ tổ chức', 'Đang tắt, như bạn đã chọn. Bật lúc nào bạn muốn tổ chức một sự kiện. Nó thêm Hosting ở Trang chính và tab Host ở đây.'],
    en: ['Hosting mode', 'Off, as you chose. Turn it on any time you want to run an event. It adds Hosting on Home and the Host tab here.'] },
  { id: 'account.settings', target: 'tour.account.settings', screen: 'profile', placement: 'above',
    vi: ['Cài đặt', 'Thông báo, gợi ý Dành cho bạn, giao diện và ngôn ngữ đều ở đây. Xem lại hướng dẫn này trong Trợ giúp.'],
    en: ['Settings', 'Notifications, For You preferences, appearance and language are all here. Replay this tour from Help.'] },
  { id: 'host.tab', target: 'tour.home.hosting', screen: 'home', placement: 'below', requires: 'organizerMode',
    vi: ['Trang Hosting của bạn', 'Chế độ tổ chức đã thêm tab này. Nó chứa mọi thứ về các sự kiện bạn tổ chức.'],
    en: ['Your Hosting home', 'Hosting mode added this tab. It holds everything about the events you run.'] },
  { id: 'host.hero', target: 'tour.host.hero', screen: 'home', placement: 'below', requires: 'organizerMode',
    vi: ['Lên kế hoạch sự kiện tiếp theo', 'Tạo sự kiện mở trình tạo 5 bước. Mất khoảng 5 phút và lần sau sẽ sao chép sự kiện gần nhất.'],
    en: ['Plan your next event', 'Create opens a 5-step builder. It takes about 5 minutes and copies your last event next time.'] },
  { id: 'host.quick', target: 'tour.host.quick', screen: 'home', placement: 'below', requires: 'organizerMode',
    vi: ['Công cụ tổ chức', 'Khách và check-in, hoàn tiền, story, khảo sát, hồ sơ host và báo cáo.'],
    en: ['Host tools', 'Guests and check-in, refunds, stories, surveys, your host profile and reports.'] },
];

/** Web: semantic target id → the existing control's selector (first match in DOM order). */
export const WEB_TARGETS = {
  'tour.home.forYou': '[data-testid^="home-hero-card-"]',
  'tour.home.tonight': '[data-testid="home-hero-tabs"]',
  'tour.home.rail': '[data-testid="home-hero-rail"],[data-testid="home-hero-empty"]',
  'tour.home.hosting': '[data-testid="home-hero-tab-hosting"]',
  'tour.home.search': '[data-testid="home-search-row"]',
  'tour.home.browse': '[data-testid="home-browse"]',
  'tour.home.filters': '[data-testid="home-filter-summary"]',
  'tour.dock.schedule': '[data-testid="tab-schedule"]',
  'tour.dock.inbox': '[data-testid="tab-inbox"]',
  'tour.dock.account': '[data-testid="tab-profile"]',
  'tour.activity.tabs': '[data-testid="activity-tabs"]',
  'tour.account.shortcuts': '[data-testid="account-tiles"]',
  'tour.account.organizerMode': '[data-testid="organizer-mode-toggle"]',
  'tour.account.settings': '[data-testid="account-group-preferences"]',
  'tour.host.hero': '[data-testid="home-host-hero"],[data-testid="home-host-plan"]',
  'tour.host.quick': '[data-testid="home-host-quick"]',
};

/** The steps this account can see, in order. */
export function eligibleSteps(ctx) {
  return TOUR_STEPS.filter(st => !st.requires || !!ctx?.[st.requires]);
}

export const tourDoneKey = uid => `banbe.tour.v3.done.${uid}`;

/** Three short chapters (note 80, iOS twin `OnboardingTourContent.chapters`). A chapter with no eligible step is dropped. */
export const TOUR_CHAPTERS = [
  { id: 'discover', name: ['Khám phá', 'Discover'], stepIds: ['home.forYou', 'home.tonight', 'home.tabPicks', 'home.search', 'home.browse', 'home.filters'] },
  { id: 'plans', name: ['Lịch và tin nhắn', 'Plans and messages'], stepIds: ['dock.schedule', 'dock.activity', 'activity.tabs'] },
  { id: 'you', name: ['Tài khoản của bạn', 'Your account'], stepIds: ['dock.account', 'account.shortcuts', 'account.organizerMode', 'account.settings'] },
  { id: 'host', name: ['Tổ chức', 'Hosting'], stepIds: ['host.tab', 'host.hero', 'host.quick'] },
];

/** "Do it" steps only move on when the highlighted control is used; the overlay performs it (see OnboardingTour). */
export const TOUR_DO_IT = {
  'home.tonight': ['Chạm Tối nay hoặc Cuối tuần', 'Tap Tonight or Weekend'],
  'dock.activity': ['Chạm Hoạt động', 'Tap Activity'],
  'dock.account': ['Chạm Tài khoản', 'Tap Account'],
  'host.tab': ['Chạm Hosting', 'Tap Hosting'],
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

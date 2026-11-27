/* Cụm onboarding · Ngày 1/8 · 2026-11-27
   The eight screens share one state object, stored in sessionStorage under
   `bb:onboarding:state` so the stage's Làm lại can clear every choice.

   Data: the seven production events below were checked on 2026-11-27 through
   https://www.banbe.app/api/photo-share?eid=<id> (og:description gives the
   venue day and time) and the v2.3 test-data seed (prices, type, cover).
   Covers are the real event photos from app/public/photos. */
(() => {
  const CLUSTER = 'onboarding';
  const STORE = `bb:${CLUSTER}:state`;
  const MAX_PRICE = 650000;

  const EVENTS = [
    { id: 'chophien', name: 'Chợ Phiên Sân Thượng', type: 'popup', area: 'Quận 1', dayName: 'Thứ Bảy', short: 'T7', day: 28, month: 'T11', monthNum: 11, time: '16:00', minutes: 960, price: 0, iso: '2026-11-28', weekday: 6, photo: 'photos/DSCF7597.jpg' },
    { id: 'bunchay', name: 'Bữa Chay Sân Gạch', type: 'supper', area: 'Quận 10', dayName: 'Thứ Bảy', short: 'T7', day: 28, month: 'T11', monthNum: 11, time: '18:30', minutes: 1110, price: 380000, iso: '2026-11-28', weekday: 6, photo: 'photos/DSCF6107.jpg' },
    { id: 'saxsang', name: 'Sax Buổi Sáng', type: 'music', area: 'Thảo Điền', dayName: 'Chủ Nhật', short: 'CN', day: 29, month: 'T11', monthNum: 11, time: '10:00', minutes: 600, price: 150000, iso: '2026-11-29', weekday: 0, photo: 'photos/DSCF4282.jpg' },
    { id: 'tranhtoi', name: 'Trăng Tối Acoustic', type: 'music', area: 'Quận 1', dayName: 'Thứ Hai', short: 'T2', day: 30, month: 'T11', monthNum: 11, time: '20:00', minutes: 1200, price: 220000, iso: '2026-11-30', weekday: 1, photo: 'photos/DSCF4212.jpg' },
    { id: 'gomxanh', name: 'Gốm Xanh Biên Hoà', type: 'gallery', area: 'Quận 1', dayName: 'Thứ Ba', short: 'T3', day: 1, month: 'T12', monthNum: 12, time: '18:00', minutes: 1080, price: 120000, iso: '2026-12-01', weekday: 2, photo: 'photos/DSCF2539.jpg' },
    { id: 'phimcu', name: 'Phim Cũ, Ảnh Mới', type: 'gallery', area: 'Quận 5', dayName: 'Thứ Tư', short: 'T4', day: 2, month: 'T12', monthNum: 12, time: '17:00', minutes: 1020, price: 90000, iso: '2026-12-02', weekday: 3, photo: 'photos/DSCF2023.jpg' },
    { id: 'maydo', name: 'Một Buổi May Đo', type: 'fashion', area: 'Bình Thạnh', dayName: 'Thứ Năm', short: 'T5', day: 3, month: 'T12', monthNum: 12, time: '15:00', minutes: 900, price: 650000, iso: '2026-12-03', weekday: 4, photo: 'photos/DSCF4254.jpg' },
  ].sort((a, b) => a.iso.localeCompare(b.iso) || a.minutes - b.minutes);

  const TYPES = [
    ['supper', 'Supper club'],
    ['music', 'Nhạc'],
    ['gallery', 'Phòng tranh'],
    ['fashion', 'Thời trang'],
    ['popup', 'Pop-up'],
  ];
  const TYPE_LABEL = Object.fromEntries(TYPES);
  const AVAILABILITY = [
    ['weekdays', 'Ngày thường'],
    ['weekends', 'Cuối tuần'],
    ['daytime', 'Ban ngày'],
    ['evening', 'Buổi tối'],
  ];
  const AVAILABILITY_LABEL = Object.fromEntries(AVAILABILITY);
  const BUDGET = [
    { key: 'free', cap: 0, label: 'Chỉ sự kiện miễn phí', short: 'Miễn phí' },
    { key: 'low', cap: 200000, label: 'Thấp · đến 200.000₫', short: 'Đến 200.000₫' },
    { key: 'medium', cap: 600000, label: 'Trung bình · 200.000₫ – 600.000₫', short: 'Đến 600.000₫' },
    { key: 'flexible', cap: Infinity, label: 'Linh hoạt · không giới hạn', short: 'Không giới hạn' },
  ];
  const STEPS = ['Chào', 'Sở thích', 'Thời gian', 'Ngân sách', 'Dành cho bạn', 'Bản tin', 'Tổ chức', 'Đăng nhập'];

  const blank = () => ({
    interests: [],
    availability: [],
    budget: null,
    digest: false,
    hosting: false,
    login: { email: '', password: '', method: 'code', submitted: false },
  });

  function load() {
    try {
      const raw = sessionStorage.getItem(STORE);
      if (!raw) return blank();
      const parsed = JSON.parse(raw);
      const base = blank();
      return {
        ...base,
        ...parsed,
        interests: Array.isArray(parsed.interests) ? parsed.interests.filter((k) => TYPE_LABEL[k]) : [],
        availability: Array.isArray(parsed.availability) ? parsed.availability.filter((k) => AVAILABILITY_LABEL[k]) : [],
        budget: BUDGET.some((b) => b.key === parsed.budget) ? parsed.budget : null,
        digest: parsed.digest === true,
        hosting: parsed.hosting === true,
        login: { ...base.login, ...(parsed.login || {}) },
      };
    } catch {
      return blank();
    }
  }

  let state = load();
  let current = 1;
  let firstRender = true;
  let demoOpen = false;
  let demoTrigger = null;
  let demoScrollTop = 0;

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const pad = (n) => String(n).padStart(2, '0');
  const money = (value) => (value === 0 ? 'Miễn phí' : `${new Intl.NumberFormat('vi-VN').format(value)}₫`);
  const save = () => {
    try { sessionStorage.setItem(STORE, JSON.stringify(state)); } catch { /* private mode */ }
  };

  function sectionFor(step) {
    return $(`[data-step="${step}"]`);
  }

  function setText(sel, text) {
    const node = $(sel);
    if (node) node.textContent = text;
  }

  /* ── event helpers ─────────────────────────────────────────────── */
  const matchesAvailability = (ev, key) => {
    if (key === 'weekdays') return ev.weekday >= 1 && ev.weekday <= 5;
    if (key === 'weekends') return ev.weekday === 0 || ev.weekday === 6;
    if (key === 'daytime') return ev.minutes < 17 * 60;
    if (key === 'evening') return ev.minutes >= 17 * 60;
    return false;
  };
  const budgetCap = (key) => (BUDGET.find((b) => b.key === key) || {}).cap ?? Infinity;

  function matchesAll(ev, s = state) {
    if (s.interests.length && !s.interests.includes(ev.type)) return false;
    if (s.availability.length && !s.availability.some((k) => matchesAvailability(ev, k))) return false;
    if (s.budget && ev.price > budgetCap(s.budget)) return false;
    return true;
  }
  const hasAnswers = (s = state) => s.interests.length > 0 || s.availability.length > 0 || !!s.budget;

  function typeCounts() {
    const m = {};
    EVENTS.forEach((ev) => { m[ev.type] = (m[ev.type] || 0) + 1; });
    return m;
  }
  const TYPE_COUNTS = typeCounts();

  function eventHref(ev) {
    return `https://www.banbe.app/event/${ev.id}`;
  }

  function openEvent(a, ev) {
    a.href = eventHref(ev);
    a.target = '_blank';
    a.rel = 'noreferrer';
    a.title = `${ev.name} · màn demo trong prototype`;
    a.setAttribute('aria-haspopup', 'dialog');
    a.dataset.eventId = ev.id;
  }

  function openDemo(ev, trigger) {
    const panel = $('[data-event-demo]');
    const screen = $('.bb-screen');
    if (!panel || !screen) return;
    demoTrigger = trigger || null;
    demoScrollTop = screen.scrollTop;
    screen.dataset.demo = '1';
    screen.scrollTop = 0;

    setText('[data-demo-step]', `Bước ${current}/${STEPS.length} · ${STEPS[current - 1]}`);
    setText('[data-demo-note]', `Bạn vẫn đang trong onboarding, bước ${current}/${STEPS.length}. Đây là màn sự kiện demo: chưa giữ ghế, chưa nhận vé.`);
    setText('[data-demo-kicker]', `${TYPE_LABEL[ev.type]} · ${dateLine(ev)}`);
    setText('[data-demo-title]', ev.name);
    setText('[data-demo-meta]', `${ev.time} · ${ev.area}, Sài Gòn`);
    setText('[data-demo-price]', money(ev.price));
    setText('[data-demo-copy]', 'Ngày, giờ, khu vực và giá lấy từ sự kiện thật trên banbe. Màn demo chưa có mô tả của host hay số chỗ còn lại.');

    const photo = $('[data-demo-photo]', panel);
    if (photo) {
      photo.src = ev.photo;
      photo.alt = `Ảnh bìa ${ev.name}`;
    }
    const real = $('[data-demo-real]', panel);
    if (real) real.href = eventHref(ev);

    demoOpen = true;
    $$('[data-step]').forEach((section) => { section.inert = true; });
    panel.hidden = false;
    $('[data-demo-title]', panel)?.focus({ preventScroll: true });
  }

  function closeDemo({ restoreFocus = true } = {}) {
    if (!demoOpen) return;
    const panel = $('[data-event-demo]');
    const screen = $('.bb-screen');
    demoOpen = false;
    if (panel) panel.hidden = true;
    $$('[data-step]').forEach((section) => { section.inert = false; });
    if (screen) {
      delete screen.dataset.demo;
      screen.scrollTop = demoScrollTop;
    }
    const trigger = demoTrigger;
    demoTrigger = null;
    if (restoreFocus && trigger) trigger.focus({ preventScroll: true });
  }

  function dateLine(ev) {
    return `${ev.dayName}, ${ev.day}.${ev.monthNum}`;
  }

  function welcomeRow(ev) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    openEvent(a, ev);
    a.innerHTML = `<span class="w-date"><b>${ev.day}</b><small>${ev.month}</small></span>
      <span><span class="w-name">${ev.name}</span><span class="w-meta-line">${TYPE_LABEL[ev.type]} · ${ev.area} · ${ev.time}</span></span>
      <span class="w-price">${money(ev.price)}</span>`;
    li.append(a);
    return li;
  }

  function evidenceCard(ev, badge = false) {
    const a = document.createElement('a');
    a.className = 'ev-row';
    openEvent(a, ev);
    a.innerHTML = `<img src="${ev.photo}" alt="" loading="lazy">
      <span><b>${ev.name}${badge ? '<span class="ev-badge" aria-label="Khớp với lựa chọn"></span>' : ''}</b>
      <small>${TYPE_LABEL[ev.type]} · ${ev.area} · ${ev.short} ${ev.day}.${ev.monthNum}, ${ev.time}</small></span>
      <span class="ev-price">${money(ev.price)}</span>`;
    return a;
  }

  function fillCards(container, list, badgeFn = () => false) {
    if (!container) return;
    container.replaceChildren();
    list.forEach((ev) => container.append(evidenceCard(ev, badgeFn(ev))));
  }

  function weekCells(target, activeFor) {
    if (!target) return;
    const days = [];
    EVENTS.forEach((ev) => {
      let day = days.find((d) => d.iso === ev.iso);
      if (!day) {
        day = { iso: ev.iso, day: ev.day, month: ev.month, short: ev.short, count: 0, events: [] };
        days.push(day);
      }
      day.count += 1;
      day.events.push(ev);
    });
    target.replaceChildren();
    days.forEach((day) => {
      const on = activeFor ? day.events.some(activeFor) : true;
      const cell = document.createElement('div');
      cell.className = 'ev-day';
      cell.dataset.on = String(on);
      cell.innerHTML = `<em>${day.short}</em><b>${day.day}</b><small>${day.count} buổi</small>`;
      target.append(cell);
    });
  }

  /* ── welcome ───────────────────────────────────────────────────── */
  function renderWelcome() {
    const list = $('[data-welcome-list]');
    if (!list) return;
    list.replaceChildren(...EVENTS.map(welcomeRow));
  }

  /* ── question 1 · interests ────────────────────────────────────── */
  function renderInterests() {
    const picked = state.interests;
    const list = picked.length ? EVENTS.filter((ev) => picked.includes(ev.type)) : EVENTS;
    const title = !picked.length
      ? 'Bảy buổi, năm loại'
      : picked.length === 1
        ? `${TYPE_LABEL[picked[0]]}: ${list.length} buổi`
        : `${picked.length} loại, ${list.length} buổi`;
    setText('[data-evidence="interests"] [data-ev-title]', title);
    setText('[data-evidence="interests"] [data-ev-copy]',
      picked.length
        ? 'Đây là những buổi thuộc loại bạn chọn. Bỏ chọn để xem lại tất cả.'
        : 'Chọn loại bạn thích, danh sách bên dưới đổi theo. Không chọn gì thì vẫn xem được tất cả.');
    fillCards($('[data-evidence="interests"] [data-ev-cards]'), list.slice(0, 3));
    setText('[data-evidence="interests"] [data-ev-note]',
      TYPES.map(([key, label]) => `${TYPE_COUNTS[key] || 0} ${label}`).join(' · '));
  }

  /* ── question 2 · availability ─────────────────────────────────── */
  function renderAvailability() {
    const picked = state.availability;
    const list = picked.length
      ? EVENTS.filter((ev) => picked.some((k) => matchesAvailability(ev, k)))
      : EVENTS;
    const title = picked.length
      ? `${list.length} buổi khớp giờ bạn chọn`
      : `${EVENTS.filter((ev) => matchesAvailability(ev, 'weekends')).length} buổi cuối tuần, ${EVENTS.filter((ev) => matchesAvailability(ev, 'evening')).length} buổi tối`;
    setText('[data-evidence="availability"] [data-ev-title]', title);
    setText('[data-evidence="availability"] [data-ev-copy]',
      picked.length
        ? 'Đây là những buổi rơi vào giờ bạn chọn. Bỏ chọn để xem lại cả tuần.'
        : 'Đây là những buổi thật trong tuần này. Chọn giờ bạn hay rảnh, chúng tôi xếp chúng lên trước.');
    weekCells($('[data-evidence="availability"] [data-ev-week]'),
      picked.length ? (ev) => picked.some((k) => matchesAvailability(ev, k)) : null);
    fillCards($('[data-evidence="availability"] [data-ev-cards]'), list.slice(0, 3));
  }

  /* ── question 3 · budget ───────────────────────────────────────── */
  function buildRuler() {
    const ruler = $('[data-ruler]');
    if (!ruler) return;
    const dots = EVENTS.map((ev) => {
      const left = (ev.price / MAX_PRICE) * 100;
      return `<i class="ruler-dot" data-price="${ev.price}" style="left:${left.toFixed(2)}%" title="${ev.name}: ${money(ev.price)}"></i>`;
    }).join('');
    ruler.innerHTML = `<div class="ruler-track"><div class="ruler-line"></div><div class="ruler-band"></div>${dots}</div>
      <div class="ruler-scale"><span>0₫</span><span>650.000₫</span></div>
      <p class="ruler-note">Bảy mức giá thật. Cao nhất 650.000₫.</p>`;
  }

  function renderBudget() {
    const picked = BUDGET.find((b) => b.key === state.budget) || null;
    const cap = picked ? picked.cap : Infinity;
    const list = EVENTS.filter((ev) => ev.price <= cap);
    const title = !picked
      ? 'Từ miễn phí đến 650.000₫'
      : picked.key === 'flexible'
        ? 'Cả bảy buổi'
        : picked.key === 'free'
          ? `${list.length} buổi miễn phí`
          : `${list.length} buổi đến ${money(picked.cap)}`;
    setText('[data-evidence="budget"] [data-ev-title]', title);
    setText('[data-evidence="budget"] [data-ev-copy]',
      picked
        ? 'Mức bạn chọn chỉ đổi Dành cho bạn. Mọi sự kiện vẫn tìm thấy ở Browse.'
        : 'Mức bạn chọn chỉ đổi Dành cho bạn. Mọi sự kiện vẫn tìm thấy ở Browse.');
    fillCards($('[data-evidence="budget"] [data-ev-cards]'), list.slice(0, 4));

    const ruler = $('[data-ruler]');
    if (!ruler) return;
    const pct = !picked ? 0 : picked.key === 'flexible' ? 100 : Math.min(100, (picked.cap / MAX_PRICE) * 100);
    ruler.style.setProperty('--cap', `${pct}%`);
    $$('.ruler-dot', ruler).forEach((dot) => {
      dot.dataset.over = String(Number(dot.dataset.price) > cap);
    });
  }

  /* ── 5 · reveal ────────────────────────────────────────────────── */
  function renderReveal() {
    const answered = hasAnswers();
    const matches = EVENTS.filter((ev) => matchesAll(ev));
    const fallback = answered && matches.length === 0;
    const showBadges = answered && !fallback;
    const ordered = [...EVENTS].sort((a, b) => {
      if (showBadges) {
        const am = matchesAll(a) ? 1 : 0;
        const bm = matchesAll(b) ? 1 : 0;
        if (am !== bm) return bm - am;
      }
      return a.iso.localeCompare(b.iso) || a.minutes - b.minutes;
    });

    const sub = !answered
      ? 'Bạn bỏ qua ba câu, đây là bảy buổi gần nhất.'
      : fallback
        ? 'Không có buổi nào khớp cả ba lựa chọn. Đây là bảy buổi gần nhất.'
        : `${matches.length} buổi khớp với lựa chọn của bạn. Tất cả bảy buổi vẫn ở đây, khớp trước.`;
    setText('[data-reveal-sub]', sub);

    const chips = [
      { go: 2, label: 'Sở thích', value: state.interests.map((k) => TYPE_LABEL[k]).join(', ') },
      { go: 3, label: 'Thời gian', value: state.availability.map((k) => AVAILABILITY_LABEL[k]).join(', ') },
      { go: 4, label: 'Ngân sách', value: (BUDGET.find((b) => b.key === state.budget) || {}).short || '' },
    ];
    const answers = $('[data-reveal-answers]');
    if (answers) {
      answers.innerHTML = chips.map((c) => {
        const action = c.value ? 'Sửa' : 'Chọn';
        return `<span class="chip"><span class="chip-copy"><span>${c.label}:</span><b>${c.value || 'Chưa chọn'}</b></span><a href="#b${c.go}" aria-label="${action} ${c.label}">${action}</a></span>`;
      }).join('');
    }

    const lead = ordered[0];
    const leadEl = $('[data-reveal-lead]');
    if (leadEl && lead) {
      const isMatch = showBadges && matchesAll(lead);
      leadEl.replaceChildren();
      const a = document.createElement('a');
      a.className = 'r-lead';
      openEvent(a, lead);
      a.innerHTML = `<img src="${lead.photo}" alt="">
        <div class="r-lead-body">
          <div class="r-lead-top"><span>${isMatch ? 'Khớp · ' : ''}${TYPE_LABEL[lead.type]} · ${dateLine(lead)}</span><span>${money(lead.price)}</span></div>
          <h3>${lead.name}</h3>
          <div class="r-lead-meta"><span><b>${lead.time}</b></span><span>${lead.area}</span><span>Giữ ghế 30 phút</span></div>
          <span class="r-lead-cta">Xem sự kiện <span aria-hidden="true">→</span></span>
        </div>`;
      leadEl.append(a);
    }

    const list = $('[data-reveal-list]');
    if (list) {
      list.replaceChildren();
      ordered.slice(1).forEach((ev) => {
        const li = document.createElement('li');
        const a = document.createElement('a');
        a.className = 'r-row';
        openEvent(a, ev);
        const isMatch = showBadges && matchesAll(ev);
        a.innerHTML = `<span class="r-day"><b>${ev.day}</b><small>${ev.month}</small></span>
          <span><span class="r-row-name">${ev.name}</span><small class="r-row-meta">${TYPE_LABEL[ev.type]} · ${ev.area} · ${ev.short} ${ev.day}.${ev.monthNum}, ${ev.time}</small></span>
          <span class="r-row-price">${money(ev.price)}${isMatch ? '<em>Khớp</em>' : ''}</span>`;
        li.append(a);
        list.append(li);
      });
    }

    weekCells($('[data-reveal-week]'), null);
  }

  /* ── 6 · digest ────────────────────────────────────────────────── */
  function renderDigest() {
    const list = $('[data-digest-list]');
    if (!list) return;
    list.innerHTML = EVENTS.slice(0, 3).map((ev) => `<li><b>${ev.day}</b><div><b>${ev.name}</b><small>${ev.short} ${ev.day}.${ev.monthNum} · ${ev.time} · ${ev.area}</small></div></li>`).join('');
  }

  /* ── 8 · login ─────────────────────────────────────────────────── */
  const emailOk = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());

  function loginValid() {
    const l = state.login;
    return l.method === 'password' ? emailOk(l.email) && l.password.length > 0 : emailOk(l.email);
  }

  function updateLoginSubmit() {
    const btn = $('[data-login-submit]');
    if (btn) btn.disabled = !loginValid();
    const label = $('[data-login-label]');
    if (label) label.textContent = state.login.method === 'password' ? 'Đăng nhập' : 'Gửi mã 8 số';
  }

  function showLoginNote(text) {
    const note = $('[data-login-note]');
    if (!note) return;
    note.hidden = false;
    note.textContent = text;
  }

  function renderLogin() {
    const email = $('[data-login-email]');
    const password = $('[data-login-password]');
    if (email && email.value !== state.login.email) email.value = state.login.email;
    if (password && password.value !== state.login.password) password.value = state.login.password;
    $$('[data-method]').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(btn.dataset.method === state.login.method));
    });
    const passwordField = $('[data-password-field]');
    if (passwordField) passwordField.hidden = state.login.method !== 'password';
    updateLoginSubmit();
    const error = $('[data-email-error]');
    if (error) error.hidden = true;
    if (state.login.submitted) {
      showLoginNote(state.login.method === 'password'
        ? 'Trong app thật, bạn sẽ vào Home với vé của mình. Bản xem trước không tạo phiên đăng nhập.'
        : `Trong app thật, một mã 8 số sẽ được gửi tới ${state.login.email}. Bản xem trước không gửi gì và không tạo phiên.`);
    } else {
      const note = $('[data-login-note]');
      if (note) note.hidden = true;
    }
  }

  function renderChoiceSummary() {
    const el = $('[data-choice-summary]');
    if (!el) return;
    el.innerHTML = `
      <div><span>Bản tin thứ Năm</span><span>${state.digest ? 'Bật' : 'Tắt'} · <a href="#b6">Sửa</a></span></div>
      <div><span>Chế độ tổ chức</span><span>${state.hosting ? 'Bật' : 'Tắt'} · <a href="#b7">Sửa</a></span></div>`;
  }

  /* ── state → controls ──────────────────────────────────────────── */
  function syncToggles() {
    $$('[data-toggle]').forEach((btn) => {
      const on = state[btn.dataset.toggle] === true;
      btn.setAttribute('aria-checked', String(on));
      const label = $('[data-toggle-label]', btn);
      if (label) label.textContent = on ? 'Đang bật' : 'Đang tắt';
    });
  }

  function syncPressed() {
    $$('[data-group="interests"] .tile').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(state.interests.includes(btn.dataset.value)));
    });
    $$('[data-group="availability"] .tile').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(state.availability.includes(btn.dataset.value)));
    });
    $$('[data-group="budget"] .budget-row').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(state.budget === btn.dataset.value));
    });
  }

  function syncChoiceCounts() {
    $$('[data-count]').forEach((node) => {
      const key = node.dataset.count;
      if (TYPE_COUNTS[key] != null) {
        node.textContent = `${TYPE_COUNTS[key]} buổi`;
        return;
      }
      if (AVAILABILITY_LABEL[key]) {
        node.textContent = `${EVENTS.filter((ev) => matchesAvailability(ev, key)).length} buổi`;
        return;
      }
      const tier = BUDGET.find((b) => b.key === key);
      if (tier) node.textContent = tier.cap === Infinity ? '7 buổi' : `${EVENTS.filter((ev) => ev.price <= tier.cap).length} buổi`;
    });
  }

  /* ── render ────────────────────────────────────────────────────── */
  function render(step) {
    if (demoOpen) closeDemo({ restoreFocus: false });
    const sections = $$('[data-step]');
    current = Math.max(1, Math.min(sections.length, Number(step) || 1));
    sections.forEach((section) => {
      section.hidden = Number(section.dataset.step) !== current;
      section.setAttribute('aria-current', Number(section.dataset.step) === current ? 'step' : 'false');
    });

    $$('[data-step-label]').forEach((node) => { node.textContent = `${current}/${sections.length}`; });
    $$('[data-progressdots]').forEach((dots) => {
      [...dots.children].forEach((dot, i) => dot.toggleAttribute('data-on', i < current));
    });
    $$('.rail-step').forEach((btn) => {
      if (Number(btn.dataset.go) === current) btn.setAttribute('aria-current', 'step');
      else btn.removeAttribute('aria-current');
    });

    if (current === 1) renderWelcome();
    if (current === 2) renderInterests();
    if (current === 3) renderAvailability();
    if (current === 4) renderBudget();
    if (current === 5) renderReveal();
    if (current === 6) renderDigest();
    if (current === 8) { renderLogin(); renderChoiceSummary(); }

    const live = $('[data-live]');
    if (live) live.textContent = `Bước ${current}/${sections.length}, ${STEPS[current - 1]}`;

    if (!firstRender) {
      const heading = sectionFor(current)?.querySelector('[data-focus]');
      heading?.focus({ preventScroll: true });
    }
    firstRender = false;
  }

  function reset() {
    state = blank();
    try { sessionStorage.removeItem(STORE); } catch { /* ignore */ }
    const email = $('[data-login-email]');
    const password = $('[data-login-password]');
    if (email) email.value = '';
    if (password) password.value = '';
    const error = $('[data-email-error]');
    if (error) error.hidden = true;
    const note = $('[data-login-note]');
    if (note) { note.hidden = true; note.textContent = ''; }
    syncToggles();
    syncPressed();
    syncChoiceCounts();
    renderChoiceSummary();
    // Step 8 is hidden now, but its DOM must be clean before the next visit.
    renderLogin();
  }

  /* ── static shell (rails, progress dots, ruler) ────────────────── */
  function buildShell() {
    $$('[data-rail]').forEach((rail) => {
      rail.innerHTML = '<p class="rail-head">Onboarding · 8 bước</p>';
      STEPS.forEach((label, i) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'rail-step';
        btn.dataset.go = String(i + 1);
        btn.innerHTML = `<b>${pad(i + 1)}</b><span>${label}</span>`;
        rail.append(btn);
      });
      const foot = document.createElement('p');
      foot.className = 'rail-foot';
      foot.textContent = 'Bản xem trước. Làm lại xoá mọi lựa chọn.';
      rail.append(foot);
    });

    $$('[data-progressdots]').forEach((dots) => {
      for (let i = 0; i < STEPS.length; i += 1) dots.append(document.createElement('i'));
    });

    buildRuler();
    syncToggles();
    syncPressed();
    syncChoiceCounts();
    renderChoiceSummary();
  }

  /* ── events ────────────────────────────────────────────────────── */
  document.addEventListener('click', (event) => {
    const eventLink = event.target.closest('[data-event-id]');
    if (eventLink) {
      const ev = EVENTS.find((item) => item.id === eventLink.dataset.eventId);
      if (ev) {
        event.preventDefault();
        openDemo(ev, eventLink);
      }
      return;
    }

    if (event.target.closest('[data-demo-close]')) {
      closeDemo();
      return;
    }

    const go = event.target.closest('[data-go]');
    if (go && window.BBStage) {
      window.BBStage.go(Number(go.dataset.go));
      return;
    }

    const tile = event.target.closest('.tile');
    if (tile) {
      const group = tile.closest('[data-group]')?.dataset.group;
      const value = tile.dataset.value;
      if (group === 'interests' || group === 'availability') {
        const list = state[group];
        const at = list.indexOf(value);
        if (at >= 0) list.splice(at, 1);
        else list.push(value);
        save();
        syncPressed();
        if (group === 'interests') renderInterests();
        else renderAvailability();
      }
      return;
    }

    const budget = event.target.closest('.budget-row');
    if (budget) {
      const value = budget.dataset.value;
      state.budget = state.budget === value ? null : value;
      save();
      syncPressed();
      renderBudget();
      return;
    }

    const toggle = event.target.closest('[data-toggle]');
    if (toggle) {
      const key = toggle.dataset.toggle;
      state[key] = !state[key];
      save();
      syncToggles();
      renderChoiceSummary();
      return;
    }

    const method = event.target.closest('[data-method]');
    if (method) {
      state.login.method = method.dataset.method;
      state.login.submitted = false;
      save();
      renderLogin();
      return;
    }

    if (event.target.closest('[data-login-submit]')) {
      if (!loginValid()) {
        const error = $('[data-email-error]');
        if (error) error.hidden = false;
        return;
      }
      const error = $('[data-email-error]');
      if (error) error.hidden = true;
      state.login.submitted = true;
      save();
      showLoginNote(state.login.method === 'password'
        ? 'Trong app thật, bạn sẽ vào Home với vé của mình. Bản xem trước không tạo phiên đăng nhập.'
        : `Trong app thật, một mã 8 số sẽ được gửi tới ${state.login.email}. Bản xem trước không gửi gì và không tạo phiên.`);
      return;
    }

    if (event.target.closest('[data-testid="login-google"]')) {
      state.login.submitted = false;
      save();
      showLoginNote('Google mở cửa sổ đăng nhập trong app thật. Bản xem trước không mở.');
    }
  });

  document.addEventListener('input', (event) => {
    const email = event.target.closest('[data-login-email]');
    if (email) {
      state.login.email = email.value;
      state.login.submitted = false;
      save();
      updateLoginSubmit();
      const note = $('[data-login-note]');
      if (note) note.hidden = true;
      const error = $('[data-email-error]');
      if (error && emailOk(email.value)) error.hidden = true;
      return;
    }
    const password = event.target.closest('[data-login-password]');
    if (password) {
      state.login.password = password.value;
      state.login.submitted = false;
      save();
      updateLoginSubmit();
    }
  });

  document.addEventListener('focusout', (event) => {
    const email = event.target.closest('[data-login-email]');
    if (!email) return;
    const error = $('[data-email-error]');
    if (error) error.hidden = email.value.trim().length === 0 || emailOk(email.value);
  });

  document.addEventListener('keydown', (event) => {
    if (demoOpen && event.key === 'Escape') {
      event.preventDefault();
      closeDemo();
      return;
    }
    const field = event.target.closest('[data-login-email], [data-login-password]');
    if (field && event.key === 'Enter' && !event.isComposing && event.keyCode !== 229) {
      if (loginValid()) $('[data-login-submit]')?.click();
      return;
    }
    if (event.key === 'Escape') {
      if (event.target.matches('input')) { event.target.blur(); return; }
      if (current > 1 && window.BBStage) window.BBStage.go(current - 1);
    }
  });

  buildShell();

  window.bbScreen = { steps: STEPS.length, render, reset, closeDemo };
})();

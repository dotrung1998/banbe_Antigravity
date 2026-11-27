/* banbe prototype stage controller.
 *
 * Contract with the cluster screen (screen.js):
 *   window.bbScreen = {
 *     steps: 5,                 // optional if data-steps is set
 *     render(step) { ... },     // required
 *     reset() { ... }           // optional: clear choices; stage re-renders 1
 *   };
 *
 * The stage owns: device rail, fit scaling, #bN deep links, the reset button,
 * the 4-up overview, and the "app thật" fallback for a cluster that does not
 * exist yet. State that must reset belongs in sessionStorage under `bb:<cluster>:*`.
 */
(() => {
  const SIZES = [
    { id: '390', w: 390, h: 844, label: 'iPhone · 390×844' },
    { id: '834', w: 834, h: 1194, label: 'iPad dọc · 834×1194' },
    { id: '1194', w: 1194, h: 834, label: 'iPad ngang · 1194×834' },
    { id: '1440', w: 1440, h: 900, label: 'Browser · 1440×900' },
  ];
  const BY_ID = Object.fromEntries(SIZES.map((s) => [s.id, s]));
  const root = document.documentElement;
  const params = new URLSearchParams(location.search);
  const embed = params.get('embed') === '1';
  const capture = params.get('capture') === '1';
  if (embed) root.dataset.embed = '1';
  if (capture) root.dataset.capture = '1';

  const stage = document.querySelector('[data-stage]');
  if (!stage) return;

  const cluster = stage.dataset.cluster || 'cluster';
  const bar = document.querySelector('.bb-bar');
  const device = stage.querySelector('[data-device]');
  const fit = stage.querySelector('[data-fit]');
  const overview = stage.querySelector('[data-overview]');
  const sizeLabel = stage.querySelector('[data-size-label]');
  const caption = stage.querySelector('.bb-stage-caption');
  const resetButton = document.querySelector('[data-reset]');
  const sizeButtons = [...document.querySelectorAll('[data-size]')];

  let steps = Math.max(1, Number(stage.dataset.steps || window.bbScreen?.steps || 1));
  let current = 1;
  let currentSize = '390';
  let overviewOpen = false;

  const clamp = (n) => Math.max(1, Math.min(steps, Math.floor(Number(n) || 1)));
  const pad2 = (n) => String(n).padStart(2, '0');

  function readStep() {
    const fromQuery = Number(params.get('step'));
    if (Number.isFinite(fromQuery) && fromQuery >= 1) return clamp(fromQuery);
    const match = location.hash.match(/^#b(\d+)$/);
    if (match) return clamp(Number(match[1]));
    return 1;
  }

  function defaultSize() {
    if (window.innerWidth >= 1100) return '1440';
    if (window.innerWidth >= 700) return '834';
    return '390';
  }

  function readSize() {
    try {
      const saved = localStorage.getItem('bb:size');
      if (saved && BY_ID[saved]) return saved;
    } catch {}
    return defaultSize();
  }

  function saveSize(id) {
    try { localStorage.setItem('bb:size', id); } catch {}
  }

  function setPressed(id) {
    sizeButtons.forEach((button) => {
      const on = button.dataset.size === id;
      button.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }

  function render(step, { replace = false } = {}) {
    current = clamp(step);
    if (typeof window.bbScreen?.render === 'function') {
      window.bbScreen.render(current);
    } else {
      console.error('[BBStage] window.bbScreen.render(step) is missing');
    }
    stage.dataset.currentStep = String(current);
    if (!embed) {
      const hash = `#b${current}`;
      if (location.hash !== hash) {
        if (replace) history.replaceState(null, '', hash);
        else history.pushState(null, '', hash);
      }
    }
    document.querySelectorAll('[data-step-dot]').forEach((dot) => {
      dot.toggleAttribute('data-on', Number(dot.dataset.stepDot) === current);
    });
  }

  function go(step) {
    if (overviewOpen) closeOverview();
    render(step);
  }

  function applySize(id, { save = true } = {}) {
    if (id === 'all') {
      openOverview();
      return;
    }
    const size = BY_ID[id] || BY_ID['390'];
    closeOverview();
    currentSize = size.id;
    device.dataset.device = size.id;
    if (sizeLabel) sizeLabel.textContent = size.label;
    setPressed(size.id);
    if (save) saveSize(size.id);
    fitDevice();
  }

  function fitDevice() {
    if (embed) return;
    if (overviewOpen) return;
    const size = BY_ID[currentSize] || BY_ID['390'];
    const barH = bar ? bar.getBoundingClientRect().height : 57;
    const capH = caption ? caption.getBoundingClientRect().height : 20;
    const availW = window.innerWidth - 48;
    const availH = window.innerHeight - barH - capH - 56;
    const scale = Math.max(0.18, Math.min(1, availW / size.w, availH / size.h));
    fit.style.width = `${Math.round(size.w * scale)}px`;
    fit.style.height = `${Math.round(size.h * scale)}px`;
    device.style.setProperty('--bb-scale', String(scale));
  }

  function urlFor(sizeId) {
    const url = new URL(location.href);
    url.searchParams.set('embed', '1');
    url.searchParams.set('step', String(current));
    url.searchParams.delete('capture');
    url.hash = '';
    return url.toString();
  }

  function openOverview() {
    if (embed) return;
    overviewOpen = true;
    setPressed('all');
    fit.hidden = true;
    overview.hidden = false;
    overview.replaceChildren();
    const fragment = document.createDocumentFragment();
    SIZES.forEach((size) => {
      const thumb = document.createElement('div');
      thumb.className = 'bb-thumb';
      thumb.dataset.thumb = size.id;
      const label = document.createElement('span');
      label.className = 'bb-thumb-label';
      label.textContent = size.label;
      const frame = document.createElement('div');
      frame.className = 'bb-thumb-frame';
      const iframe = document.createElement('iframe');
      iframe.title = size.label;
      iframe.loading = 'eager';
      iframe.src = urlFor(size.id);
      iframe.style.width = `${size.w}px`;
      iframe.style.height = `${size.h}px`;
      frame.append(iframe);
      const open = document.createElement('button');
      open.type = 'button';
      open.className = 'bb-thumb-open';
      open.dataset.open = size.id;
      open.setAttribute('aria-label', `Mở ${size.label}`);
      const hint = document.createElement('span');
      hint.className = 'bb-thumb-hint';
      hint.textContent = 'Mở khung này';
      thumb.append(label, frame, open, hint);
      fragment.append(thumb);
    });
    overview.append(fragment);
    layoutOverview();
  }

  function layoutOverview() {
    if (!overviewOpen) return;
    const gap = 14;
    const width = overview.clientWidth;
    const height = overview.clientHeight;
    const cellW = (width - gap) / 2;
    const cellH = (height - gap) / 2;
    overview.querySelectorAll('.bb-thumb').forEach((thumb) => {
      const size = BY_ID[thumb.dataset.thumb];
      const frame = thumb.querySelector('.bb-thumb-frame');
      const iframe = thumb.querySelector('iframe');
      if (!size || !frame || !iframe) return;
      const labelH = 18;
      const scale = Math.max(0.05, Math.min((cellW - 2) / size.w, (cellH - labelH - 8) / size.h));
      frame.style.width = `${Math.round(size.w * scale)}px`;
      frame.style.height = `${Math.round(size.h * scale)}px`;
      frame.style.margin = '0 auto';
      iframe.style.transform = `scale(${scale})`;
    });
  }

  function closeOverview() {
    if (!overviewOpen) return;
    overviewOpen = false;
    overview.hidden = true;
    overview.replaceChildren();
    fit.hidden = false;
    setPressed(currentSize);
    fitDevice();
  }

  function reset() {
    try {
      Object.keys(sessionStorage)
        .filter((key) => key.startsWith(`bb:${cluster}:`))
        .forEach((key) => sessionStorage.removeItem(key));
    } catch {}
    if (typeof window.bbScreen?.reset === 'function') window.bbScreen.reset();
    render(1, { replace: true });
    if (resetButton) {
      const label = resetButton.textContent;
      resetButton.textContent = 'Đã làm lại';
      resetButton.disabled = true;
      window.setTimeout(() => {
        resetButton.textContent = label;
        resetButton.disabled = false;
      }, 1100);
    }
  }

  function checkLinks() {
    if (embed || location.protocol === 'file:') return;
    document.querySelectorAll('.bb-clusters a[data-cluster], .bb-screen a[data-app]').forEach((link) => {
      if (link.dataset.cluster === cluster) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
      if (link.dataset.app === undefined) return;
      fetch(link.getAttribute('href'), { method: 'HEAD' })
        .then((response) => {
          if (response.ok) return;
          fallback(link);
        })
        .catch(() => {
          /* A missing file or a server without HEAD support: fall back too. */
          fallback(link);
        });
    });
  }

  function fallback(link) {
    if (!link.dataset.app) return;
    link.href = link.dataset.app;
    link.target = '_blank';
    link.rel = 'noreferrer';
    if (!link.querySelector('.bb-fallback')) {
      const badge = document.createElement('span');
      badge.className = 'bb-fallback';
      badge.textContent = 'app thật';
      link.append(badge);
    }
  }

  function wire() {
    sizeButtons.forEach((button) => {
      button.addEventListener('click', () => {
        if (button.dataset.size === 'all') {
          if (overviewOpen) closeOverview();
          else openOverview();
        } else {
          applySize(button.dataset.size);
        }
      });
    });
    resetButton?.addEventListener('click', reset);
    window.addEventListener('resize', () => {
      fitDevice();
      layoutOverview();
    });
    window.addEventListener('popstate', () => render(readStep(), { replace: true }));
    window.addEventListener('hashchange', () => render(readStep(), { replace: true }));
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && overviewOpen) closeOverview();
    });
    overview?.addEventListener('click', (event) => {
      const open = event.target.closest('[data-open]');
      if (open) applySize(open.dataset.open);
    });
  }

  function init() {
    steps = Math.max(1, Number(window.bbScreen?.steps || stage.dataset.steps || steps));
    stage.dataset.steps = String(steps);
    if (typeof window.bbScreen?.render !== 'function') {
      console.error('[BBStage] window.bbScreen.render(step) is missing — did screen.js load?');
      return;
    }
    if (!embed) {
      applySize(readSize());
      checkLinks();
      wire();
    }
    render(readStep(), { replace: true });
    if (!embed) fitDevice();
    document.documentElement.dataset.stageReady = '1';
  }

  window.BBStage = {
    go,
    reset,
    render,
    get step() { return current; },
    get size() { return currentSize; },
    get steps() { return steps; },
  };

  /* stage.js is a deferred script that runs before screen.js; wait for
     DOMContentLoaded so window.bbScreen is defined before init(). */
  if (document.readyState === 'complete') {
    init();
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();

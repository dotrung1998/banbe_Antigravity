/* Cluster screen logic. Replace the sections and the render body with the
   real cluster; keep the window.bbScreen contract so the stage can drive it. */
(() => {
  const sections = [...document.querySelectorAll('[data-step]')];
  const progress = document.querySelector('[data-progress]');
  let current = 1;

  function render(step) {
    current = Math.max(1, Math.min(sections.length, Number(step) || 1));
    sections.forEach((section) => {
      section.hidden = Number(section.dataset.step) !== current;
    });
    if (progress) progress.textContent = `Bước ${current}/${sections.length}`;
  }

  function reset() {
    /* Clear any choice held in sessionStorage under `bb:template:*`.
       The stage clears those keys before calling this, then renders step 1. */
    current = 1;
  }

  document.addEventListener('click', (event) => {
    const go = event.target.closest('[data-go]');
    if (go && window.BBStage) window.BBStage.go(Number(go.dataset.go));
  });

  window.bbScreen = { steps: sections.length, render, reset };
})();

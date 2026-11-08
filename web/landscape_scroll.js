// Give the browser a real document scroll when entering mobile landscape.
// Toolbar visibility itself remains controlled by the browser.
(() => {
  const host = document.getElementById('app-host');
  const landscape = matchMedia('(orientation: landscape) and (pointer: coarse)');
  let handled = false;
  let queued = false;
  let generation = 0;
  const ready = () => !document.body.hasAttribute('data-map-loading') && host.querySelector('flutter-view');

  function collapse() {
    if (!landscape.matches || handled || queued || !ready()) return;
    queued = true;
    const current = generation;
    // Read the scroll range after the rotated layout and sticky host settle.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (current !== generation) return;
      queued = false;
      if (!landscape.matches || !ready()) return;
      const root = document.scrollingElement;
      const bottom = Math.max(0, root.scrollHeight - root.clientHeight);
      if (bottom === 0) return;
      handled = true;
      window.scrollTo({left: 0, top: bottom, behavior: 'instant'});
    }));
  }

  landscape.addEventListener('change', () => {
    generation++;
    queued = false;
    handled = false;
    if (landscape.matches) collapse();
    else window.scrollTo({left: 0, top: 0, behavior: 'instant'});
  });
  window.addEventListener('resize', collapse, {passive: true});
  new MutationObserver(collapse).observe(host, {childList: true});
  new MutationObserver(collapse).observe(document.body, {attributes: true, attributeFilter: ['data-map-loading']});
  collapse();
})();

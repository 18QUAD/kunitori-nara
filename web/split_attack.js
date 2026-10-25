// Separate native targets let two fingers tap independently on iOS.
(() => {
  const host = document.getElementById('app-host');
  const portrait = window.matchMedia('(orientation: portrait)');
  const pairs = new Map();
  const forwardedClicks = new WeakSet();
  const effects = new WeakMap();
  let pending = false;

  function feedback(target) {
    effects.get(target)?.cancel();
    // Animations belong to this DOM target, so style synchronization cannot
    // copy a left-side press effect onto the right-side button (or vice versa).
    effects.set(target, target.animate(
      [{filter: 'brightness(0.84)'}, {filter: 'brightness(1)'}],
      {duration: 160, easing: 'ease-out'}));
  }

  function activate(button, target) {
    if (button.disabled) return;
    feedback(target);
    forwardedClicks.add(button);
    try { button.click(); }
    finally { forwardedClicks.delete(button); }
  }

  function pointerTap(button, event, target = button) {
    if (!portrait.matches || event.button !== 0 || button.disabled) return;
    // Use the existing game callback, including its route and enabled checks.
    // Each pointer counts once on press; its later compatibility click is ignored.
    activate(button, target);
  }

  function attach(button) {
    const right = document.createElement('button');
    right.type = 'button';
    right.className = 'attack-tap-half';
    right.setAttribute('aria-description', '右半分');
    button.dataset.splitReady = '';
    button.addEventListener('pointerdown', event => {
      if (!portrait.matches) return;
      // Older builds count clicks; newer builds already count pointerdown.
      // Own this event before either implementation can count it again.
      event.stopImmediatePropagation();
      pointerTap(button, event);
    }, true);
    button.addEventListener('click', event => {
      if (portrait.matches && event.detail === 0 && !event.pointerType && !button.disabled && !forwardedClicks.has(button)) feedback(button);
      if (portrait.matches && (event.detail > 0 || event.pointerType)) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }, true);
    right.addEventListener('pointerdown', event => {
      event.stopPropagation();
      pointerTap(button, event, right);
    });
    for (const type of ['pointerup', 'pointermove', 'pointercancel', 'keydown', 'keyup']) {
      right.addEventListener(type, event => event.stopPropagation());
    }
    right.addEventListener('click', event => {
      event.stopPropagation();
      if (event.detail === 0 && !event.pointerType && portrait.matches) activate(button, right);
      else event.preventDefault();
    });
    right.addEventListener('contextmenu', event => event.preventDefault());
    host.append(right);
    pairs.set(button, right);
  }

  function update() {
    pending = false;
    for (const [button, right] of pairs) {
      if (!button.isConnected) {
        right.remove();
        pairs.delete(button);
      }
    }
    for (const button of host.querySelectorAll('button.attack-tap-native')) {
      if (!pairs.has(button)) attach(button);
      const right = pairs.get(button);
      button.setAttribute('aria-description', portrait.matches ? '左半分' : '');
      // Read Flutter's full layout width, not the CSS half-width on screen.
      const width = parseFloat(button.style.width) || 0;
      const left = parseFloat(button.style.left) || 0;
      const half = Math.max(0, width / 2 - 4);
      const value = `${half}px`;
      if (button.style.getPropertyValue('--attack-half-width') !== value) {
        button.style.setProperty('--attack-half-width', value);
      }
      right.style.cssText = button.style.cssText;
      right.style.left = `${left + width / 2 + 4}px`;
      right.style.width = value;
      right.disabled = button.disabled;
      right.setAttribute('aria-label', `${button.getAttribute('aria-label') || 'タップで進軍'}（右）`);
    }
  }

  function schedule() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(update);
  }
  new MutationObserver(records => {
    if (records.some(record => record.type === 'childList' || record.target.matches('button.attack-tap-native'))) schedule();
  }).observe(host, {subtree: true, childList: true, attributes: true, attributeFilter: ['style', 'disabled', 'aria-label']});
  portrait.addEventListener('change', schedule);
  schedule();
})();

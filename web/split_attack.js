// Separate display targets from the existing game callback and its style updates.
(() => {
  const host = document.getElementById('app-host');
  const portrait = window.matchMedia('(orientation: portrait)');
  const pairs = new Map();
  const effects = new WeakMap();
  let pending = false;

  // iOS may recognize a cross-button pinch or double tap even when individual
  // targets declare touch-action:none. Cancel native touch defaults only for
  // contacts that started on attack buttons; pointerdown still counts them.
  const attackTouches = new Set();
  const attackTarget = node => node instanceof Element &&
    node.closest('button.attack-tap-native, button.attack-tap-half');
  const cancelDefault = event => {if (event.cancelable) event.preventDefault();};
  document.addEventListener('touchstart', event => {
    let attack = false;
    for (const touch of event.changedTouches) {
      if (attackTarget(touch.target)) {
        attackTouches.add(touch.identifier);
        attack = true;
      }
    }
    if (attack) cancelDefault(event);
  }, {capture: true, passive: false});
  document.addEventListener('touchmove', event => {
    if ([...event.changedTouches].some(touch => attackTouches.has(touch.identifier))) cancelDefault(event);
  }, {capture: true, passive: false});
  for (const type of ['touchend', 'touchcancel']) {
    document.addEventListener(type, event => {
      if ([...event.changedTouches].some(touch => attackTouches.has(touch.identifier))) cancelDefault(event);
      for (const touch of event.changedTouches) attackTouches.delete(touch.identifier);
    }, {capture: true, passive: false});
  }
  for (const type of ['gesturestart', 'gesturechange']) {
    document.addEventListener(type, event => {
      if (attackTouches.size || attackTarget(event.target)) cancelDefault(event);
    }, {capture: true, passive: false});
  }
  window.addEventListener('blur', () => attackTouches.clear());
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) attackTouches.clear();
  });

  function feedback(target) {
    effects.get(target)?.cancel();
    effects.set(target, target.animate(
      [{filter: 'brightness(0.84)'}, {filter: 'brightness(1)'}],
      {duration: 160, easing: 'ease-out'}));
  }

  function activate(bridge, target) {
    if (!portrait.matches || bridge.disabled) return;
    feedback(target);
    // The bridge is invisible in portrait. Its native click response and
    // Flutter's synchronous full-width style resets cannot flash either half.
    bridge.click();
  }

  function targetFor(bridge, side) {
    const target = document.createElement('button');
    target.type = 'button';
    target.className = 'attack-tap-half';
    target.dataset.side = side;
    target.setAttribute('aria-description', side === 'left' ? '左半分' : '右半分');
    target.addEventListener('pointerdown', event => {
      event.stopPropagation();
      if (event.button === 0) activate(bridge, target);
    });
    for (const type of ['pointerup', 'pointermove', 'pointercancel', 'keydown', 'keyup']) {
      target.addEventListener(type, event => event.stopPropagation());
    }
    target.addEventListener('click', event => {
      event.stopPropagation();
      // Pointer taps already counted on press. Only keyboard/programmatic
      // activation needs the native click fallback.
      if (event.detail === 0 && !event.pointerType) activate(bridge, target);
      else event.preventDefault();
    });
    target.addEventListener('contextmenu', event => event.preventDefault());
    host.append(target);
    return target;
  }

  function attach(bridge) {
    const pair = {
      left: targetFor(bridge, 'left'),
      right: targetFor(bridge, 'right'),
      styles: {},
      tabIndex: bridge.tabIndex,
      ariaHidden: bridge.getAttribute('aria-hidden'),
    };
    bridge.addEventListener('pointerdown', event => {
      if (portrait.matches || event.button !== 0) return;
      // The legacy contact tracker can reject a second finger or retain a
      // canceled contact. Count each landscape target directly on press.
      event.stopImmediatePropagation();
      if (bridge.disabled) return;
      feedback(bridge);
      bridge.click();
    }, true);
    bridge.addEventListener('click', event => {
      if (!portrait.matches && (event.detail > 0 || event.pointerType)) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }, true);
    bridge.dataset.splitReady = '';
    pairs.set(bridge, pair);
  }

  function update() {
    pending = false;
    for (const [bridge, pair] of pairs) {
      if (!bridge.isConnected) {
        pair.left.remove();
        pair.right.remove();
        pairs.delete(bridge);
      }
    }
    for (const bridge of host.querySelectorAll('button.attack-tap-native')) {
      if (!pairs.has(bridge)) attach(bridge);
      const pair = pairs.get(bridge);
      bridge.tabIndex = portrait.matches ? -1 : pair.tabIndex;
      if (portrait.matches) bridge.setAttribute('aria-hidden', 'true');
      else if (pair.ariaHidden === null) bridge.removeAttribute('aria-hidden');
      else bridge.setAttribute('aria-hidden', pair.ariaHidden);
      const width = parseFloat(bridge.style.width) || 0;
      const left = parseFloat(bridge.style.left) || 0;
      const half = Math.max(0, width / 2 - 4);
      for (const side of ['left', 'right']) {
        const target = pair[side];
        const x = left + (side === 'right' ? width / 2 + 4 : 0);
        const style = `${bridge.style.cssText};left:${x}px;width:${half}px`;
        // A progress update usually changes no button styling. Do not reset
        // the untouched display target's background on every game callback.
        if (pair.styles[side] !== style) {
          target.style.cssText = style;
          pair.styles[side] = style;
        }
        if (target.disabled !== bridge.disabled) target.disabled = bridge.disabled;
        const suffix = side === 'left' ? '' : '（右）';
        target.setAttribute('aria-label', `${bridge.getAttribute('aria-label') || 'タップで進軍'}${suffix}`);
      }
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

// Мобильное управление: джойстик слева, свайп камеры справа, круглые кнопки способностей с перезарядкой.
// Клавиатура тоже работает (для проверки на ПК): WASD/стрелки — ход, мышь с зажатой ПКМ — камера.
//
// const ctl = createControls({ buttons: [{ id:'m1', label:'👊', x:-90, y:-90, size:80, key:'KeyF' }, ...] });
// В цикле: ctl.move -> {x,y} (-1..1, y вверх = вперёд), ctl.consumeLook() -> {dx,dy} пикселей,
// ctl.down(id) — зажата ли кнопка, ctl.onPress(id, fn), ctl.setCooldown(id, 0..1), ctl.setLabel(id, txt), ctl.show(id, bool)
// x/y кнопки: отрицательные = от правого/нижнего края.
const CSS = `
.tc-stick{position:fixed;width:120px;height:120px;margin:-60px 0 0 -60px;border-radius:50%;background:rgba(255,255,255,.12);border:2px solid rgba(255,255,255,.35);z-index:40;pointer-events:none;display:none}
.tc-knob{position:absolute;left:35px;top:35px;width:50px;height:50px;border-radius:50%;background:rgba(255,255,255,.55)}
.tc-btn{position:fixed;z-index:41;border-radius:50%;border:3px solid rgba(255,255,255,.75);background:rgba(20,20,30,.45);color:#fff;
 font:800 14px system-ui,sans-serif;display:flex;align-items:center;justify-content:center;text-align:center;user-select:none;touch-action:none;overflow:hidden;text-shadow:0 1px 2px #000}
.tc-btn.on{background:rgba(255,255,255,.35);transform:scale(.94)}
.tc-btn .cd{position:absolute;inset:0;background:conic-gradient(rgba(0,0,0,.6) var(--a,0deg),transparent 0);pointer-events:none}
.tc-btn .k{position:absolute;bottom:3px;font-size:9px;opacity:.6}
.tc-btn span{position:relative;line-height:1.05;padding:2px}
`;

export function createControls({ buttons = [], lookArea = 'right', keyMap = {} } = {}) {
  if (!document.getElementById('tc-css')) {
    const st = document.createElement('style'); st.id = 'tc-css'; st.textContent = CSS; document.head.appendChild(st);
  }
  const stick = document.createElement('div'); stick.className = 'tc-stick';
  stick.innerHTML = '<div class="tc-knob"></div>';
  document.body.appendChild(stick);
  const knob = stick.firstChild;

  const state = { move: { x: 0, y: 0 }, look: { dx: 0, dy: 0 }, held: new Set(), press: {}, release: {}, keys: new Set() };
  const btnEls = {};
  let stickId = null, sx = 0, sy = 0, lookId = null, lx = 0, ly = 0;

  function place(el, b) {
    const s = b.size || 70;
    el.style.width = el.style.height = s + 'px';
    el.style.left = b.x < 0 ? `calc(100vw + ${b.x}px - ${s / 2}px)` : `${b.x - s / 2}px`;
    el.style.top = b.y < 0 ? `calc(100vh + ${b.y}px - ${s / 2}px)` : `${b.y - s / 2}px`;
  }

  for (const b of buttons) {
    const el = document.createElement('div');
    el.className = 'tc-btn';
    el.innerHTML = `<div class="cd"></div><span>${b.label}</span>${b.key ? `<i class="k">${b.key.replace('Key', '').replace('Digit', '')}</i>` : ''}`;
    if (b.color) el.style.borderColor = b.color;
    place(el, b);
    el.addEventListener('pointerdown', (e) => {
      e.preventDefault(); e.stopPropagation();
      el.setPointerCapture(e.pointerId);
      fire(b.id, true);
    });
    const up = (e) => { e.preventDefault(); fire(b.id, false); };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    document.body.appendChild(el);
    btnEls[b.id] = el;
    if (b.key) keyMap[b.key] = b.id;
  }

  function fire(id, down) {
    if (down) {
      if (state.held.has(id)) return;
      state.held.add(id);
      btnEls[id]?.classList.add('on');
      (state.press[id] || []).forEach((f) => f());
    } else {
      if (!state.held.has(id)) return;
      state.held.delete(id);
      btnEls[id]?.classList.remove('on');
      (state.release[id] || []).forEach((f) => f());
    }
  }

  const onDown = (e) => {
    if (e.target.closest('.bc-wrap,.bc-btn,.ui-top,button,input')) return;
    const left = e.clientX < innerWidth * 0.42;
    if (left && stickId === null && e.pointerType !== 'mouse') {
      stickId = e.pointerId; sx = e.clientX; sy = e.clientY;
      stick.style.display = 'block'; stick.style.left = sx + 'px'; stick.style.top = sy + 'px';
    } else if (lookId === null && (e.pointerType !== 'mouse' || e.button === 2 || e.button === 0)) {
      lookId = e.pointerId; lx = e.clientX; ly = e.clientY;
    }
  };
  const onMove = (e) => {
    if (e.pointerId === stickId) {
      let dx = e.clientX - sx, dy = e.clientY - sy;
      const d = Math.hypot(dx, dy), m = 50;
      if (d > m) { dx = (dx / d) * m; dy = (dy / d) * m; }
      knob.style.transform = `translate(${dx}px,${dy}px)`;
      state.move.x = dx / m; state.move.y = -dy / m;
    } else if (e.pointerId === lookId) {
      state.look.dx += e.clientX - lx; state.look.dy += e.clientY - ly;
      lx = e.clientX; ly = e.clientY;
    }
  };
  const onUp = (e) => {
    if (e.pointerId === stickId) {
      stickId = null; stick.style.display = 'none'; knob.style.transform = '';
      state.move.x = state.move.y = 0;
    }
    if (e.pointerId === lookId) lookId = null;
  };
  addEventListener('pointerdown', onDown);
  addEventListener('pointermove', onMove);
  addEventListener('pointerup', onUp);
  addEventListener('pointercancel', onUp);
  addEventListener('contextmenu', (e) => e.preventDefault());

  const keyMove = () => {
    if (stickId !== null) return;
    const k = state.keys;
    state.move.x = (k.has('KeyD') || k.has('ArrowRight') ? 1 : 0) - (k.has('KeyA') || k.has('ArrowLeft') ? 1 : 0);
    state.move.y = (k.has('KeyW') || k.has('ArrowUp') ? 1 : 0) - (k.has('KeyS') || k.has('ArrowDown') ? 1 : 0);
  };
  addEventListener('keydown', (e) => {
    if (e.repeat) return;
    state.keys.add(e.code); keyMove();
    if (keyMap[e.code]) fire(keyMap[e.code], true);
  });
  addEventListener('keyup', (e) => {
    state.keys.delete(e.code); keyMove();
    if (keyMap[e.code]) fire(keyMap[e.code], false);
  });

  return {
    move: state.move,
    consumeLook() { const l = { dx: state.look.dx, dy: state.look.dy }; state.look.dx = state.look.dy = 0; return l; },
    down: (id) => state.held.has(id),
    key: (code) => state.keys.has(code),
    onPress(id, fn) { (state.press[id] ||= []).push(fn); },
    onRelease(id, fn) { (state.release[id] ||= []).push(fn); },
    setCooldown(id, frac) {
      const el = btnEls[id]; if (!el) return;
      el.firstChild.style.setProperty('--a', Math.max(0, Math.min(1, frac)) * 360 + 'deg');
    },
    setLabel(id, html) { const el = btnEls[id]; if (el) el.querySelector('span').innerHTML = html; },
    show(id, v) { const el = btnEls[id]; if (el) el.style.display = v ? 'flex' : 'none'; },
    el: (id) => btnEls[id],
  };
}

'use strict';
// Ввод: одна клавиатура на двоих, до двух геймпадов, сенсорные джойстики на планшете.

const KEYMAP = [
  { up: ['KeyW'], down: ['KeyS'], left: ['KeyA'], right: ['KeyD'], jump: ['Space'], action: ['KeyF', 'KeyG'], camL: ['KeyQ'], camR: ['KeyE'] },
  { up: ['ArrowUp'], down: ['ArrowDown'], left: ['ArrowLeft'], right: ['ArrowRight'], jump: ['Enter', 'NumpadEnter', 'ShiftRight', 'Numpad0'], action: ['Slash', 'ControlRight', 'NumpadDecimal', 'Period'], camL: ['BracketLeft', 'Numpad4'], camR: ['BracketRight', 'Numpad6'] },
];

const GAME_KEYS = new Set(KEYMAP.flatMap((m) => Object.values(m).flat()).concat(['Escape']));

const Input = {
  down: new Set(),
  pressed: new Set(),
  padPrev: [{}, {}],
  touch: [null, null],
  touchBtn: [{ jump: false, action: false, jumpP: false, actionP: false }, { jump: false, action: false, jumpP: false, actionP: false }],
  states: [null, null],
  enabled: true,

  init() {
    window.addEventListener('keydown', (e) => {
      if (isTyping(e)) return;
      if (GAME_KEYS.has(e.code)) e.preventDefault();
      if (!e.repeat) this.pressed.add(e.code);
      this.down.add(e.code);
      Sound.init();
    });
    window.addEventListener('keyup', (e) => {
      this.down.delete(e.code);
    });
    window.addEventListener('blur', () => this.down.clear());
    this.initTouch();
  },

  isDown(codes) { return codes.some((c) => this.down.has(c)); },
  wasPressed(codes) { return codes.some((c) => this.pressed.has(c)); },
  anyPressed(list) { return list.some((c) => this.pressed.has(c)); },

  pads() {
    const raw = navigator.getGamepads ? Array.from(navigator.getGamepads()).filter((p) => p && p.connected) : [];
    const swap = Store.data.settings.pad === 1;
    if (raw.length === 1) return swap ? [null, raw[0]] : [raw[0], null];
    return [raw[0] || null, raw[1] || null];
  },

  // Состояние управления игрока i за этот кадр.
  poll() {
    let pads = [];
    try { pads = this.pads(); } catch (e) { pads = [null, null]; }
    for (let i = 0; i < 2; i++) {
      const km = KEYMAP[i];
      let mx = (this.isDown(km.right) ? 1 : 0) - (this.isDown(km.left) ? 1 : 0);
      let mz = (this.isDown(km.up) ? 1 : 0) - (this.isDown(km.down) ? 1 : 0);
      let cam = (this.isDown(km.camR) ? 1 : 0) - (this.isDown(km.camL) ? 1 : 0);
      let camY = 0;
      let jump = this.isDown(km.jump);
      let jumpP = this.wasPressed(km.jump);
      let action = this.isDown(km.action);
      let actionP = this.wasPressed(km.action);
      let pause = false;
      let menuUp = this.wasPressed(km.up);
      let menuDown = this.wasPressed(km.down);
      let menuLeft = this.wasPressed(km.left);
      let menuRight = this.wasPressed(km.right);
      const pad = pads[i];
      if (pad) {
        const prev = this.padPrev[i];
        const ax = (n) => { const v = pad.axes[n] || 0; return Math.abs(v) > 0.2 ? v : 0; };
        const btn = (n) => !!(pad.buttons[n] && pad.buttons[n].pressed);
        const edge = (n) => btn(n) && !prev[n];
        if (ax(0) || ax(1)) { mx = ax(0); mz = -ax(1); }
        if (btn(14)) mx = -1;
        if (btn(15)) mx = 1;
        if (btn(12)) mz = 1;
        if (btn(13)) mz = -1;
        if (ax(2)) cam = ax(2);
        if (ax(3)) camY = ax(3);
        if (btn(4)) cam = -1;
        if (btn(5)) cam = 1;
        jump = jump || btn(0);
        jumpP = jumpP || edge(0);
        action = action || btn(1) || btn(2);
        actionP = actionP || edge(1) || edge(2);
        pause = edge(9);
        const stickEdge = (cond, key) => { const was = prev[key]; prev[key] = cond; return cond && !was; };
        menuUp = menuUp || edge(12) || stickEdge(pad.axes[1] < -0.6, 'sU');
        menuDown = menuDown || edge(13) || stickEdge(pad.axes[1] > 0.6, 'sD');
        menuLeft = menuLeft || edge(14) || stickEdge(pad.axes[0] < -0.6, 'sL');
        menuRight = menuRight || edge(15) || stickEdge(pad.axes[0] > 0.6, 'sR');
        for (let b = 0; b < pad.buttons.length; b++) prev[b] = btn(b);
      }
      const t = this.touch[i];
      const tb = this.touchBtn[i];
      if (t && t.active) { mx = t.dx; mz = -t.dy; }
      jump = jump || tb.jump;
      jumpP = jumpP || tb.jumpP;
      action = action || tb.action;
      actionP = actionP || tb.actionP;
      tb.jumpP = false;
      tb.actionP = false;
      const len = Math.hypot(mx, mz);
      if (len > 1) { mx /= len; mz /= len; }
      this.states[i] = { mx, mz, cam, camY, jump, jumpP, action, actionP, pause, menuUp, menuDown, menuLeft, menuRight };
    }
    return this.states;
  },

  endFrame() { this.pressed.clear(); },

  // Сенсорное управление: каждая половина экрана — свой джойстик и кнопки.
  initTouch() {
    this.touchUI = [];
    const ids = new Map();
    const layer = (i) => this.touchUI[i];
    const btnHit = (i, x, y) => {
      const L = layer(i);
      if (!L) return null;
      for (const b of ['jump', 'action']) {
        const r = L[b].getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        if (Math.hypot(x - cx, y - cy) < r.width * 0.75) return b;
      }
      return null;
    };
    const onStart = (e) => {
      if (!Game.touchMode || !Game.playing()) return;
      let used = false;
      for (const t of e.changedTouches) {
        if (t.target.closest && t.target.closest('button, input, .editor, .card')) continue;
        used = true;
        const i = Game.split ? (t.clientX < window.innerWidth / 2 ? 0 : 1) : 0;
        const b = btnHit(i, t.clientX, t.clientY);
        if (b) {
          this.touchBtn[i][b] = true;
          this.touchBtn[i][b + 'P'] = true;
          ids.set(t.identifier, { i, b });
          layer(i)[b].style.background = 'rgba(255,255,255,0.45)';
        } else if (!this.touch[i] || !this.touch[i].active) {
          this.touch[i] = { active: true, ox: t.clientX, oy: t.clientY, dx: 0, dy: 0 };
          ids.set(t.identifier, { i, stick: true });
          const L = layer(i);
          if (L) { L.stick.hidden = false; L.stick.style.left = t.clientX - L.half.getBoundingClientRect().left + 'px'; L.stick.style.top = t.clientY + 'px'; L.knob.style.transform = 'translate(-50%,-50%)'; }
        }
      }
      if (used) e.preventDefault();
    };
    const onMove = (e) => {
      for (const t of e.changedTouches) {
        const info = ids.get(t.identifier);
        if (!info || !info.stick) continue;
        const s = this.touch[info.i];
        let dx = (t.clientX - s.ox) / 50;
        let dy = (t.clientY - s.oy) / 50;
        const l = Math.hypot(dx, dy);
        if (l > 1) { dx /= l; dy /= l; }
        s.dx = dx;
        s.dy = dy;
        const L = layer(info.i);
        if (L) L.knob.style.transform = `translate(calc(-50% + ${dx * 40}px), calc(-50% + ${dy * 40}px))`;
      }
    };
    const onEnd = (e) => {
      for (const t of e.changedTouches) {
        const info = ids.get(t.identifier);
        if (!info) continue;
        ids.delete(t.identifier);
        if (info.stick) {
          this.touch[info.i] = null;
          const L = layer(info.i);
          if (L) L.stick.hidden = true;
        } else {
          this.touchBtn[info.i][info.b] = false;
          layer(info.i)[info.b].style.background = '';
        }
      }
    };
    window.addEventListener('touchstart', (e) => { Sound.init(); if (!Game.touchMode) { Game.enableTouch(); } onStart(e); }, { passive: false });
    window.addEventListener('touchmove', onMove, { passive: false });
    window.addEventListener('touchend', onEnd);
    window.addEventListener('touchcancel', onEnd);
  },
};

function isTyping(e) {
  const t = e.target;
  return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA') && t.type === 'text';
}

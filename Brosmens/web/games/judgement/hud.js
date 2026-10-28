// HUD как в UJD — минимальный: таймер (целые секунды, чёрные пиксельные цифры со светлой обводкой, без плашки),
// у игрока-Судьи — строка «УКЛОНЕНИЯ: N», над головами — «билборды» постоянного экранного размера
// (Судья: голубая полоска «1/1»; люди: жёлтая полоска HP, светящееся сердце-душа и имя; карма — розовый кусок и
// пурпурные цифры; святое зелье — золотая заливка и второй сегмент-щит), пиксельные баннеры, полоска наблюдения
// «< Наблюдение: Имя >» и диалоговое окно в духе Undertale (интро и смерть Судьи, печатная машинка 30 букв/с).
import * as THREE from 'three';
import { heartTex } from './fx.js';
import { pixCanvas, measurePixText, PIX } from './pixfont.js';
import { TYPE_CPS, LINE_HOLD } from './data.js';

const h = (tag, cls, html = '') => { const e = document.createElement(tag); if (cls) e.className = cls; if (html) e.innerHTML = html; return e; };
const P = new THREE.Vector3();
const KR_STYLE = { ...PIX.bar, fill: '#FF00FF' };
const TIMER_STYLE = { ...PIX.timer, spacing: 1.65, rows: 7 };
const DODGE_STYLE = { ...PIX.timer, outlineK: 0.45, rows: 7 };

// Пиксельная надпись в DOM: перерисовывается только когда меняется текст/размер/цвет
export function pixLabel(cls) {
  const c = document.createElement('canvas'); c.className = cls;
  let key = '';
  c.set = (str, px, style) => {
    const k = str + '|' + px + '|' + style.fill + '|' + (style.outline || '');
    if (k === key) return;
    key = k; pixCanvas(str, px, style, c);
  };
  return c;
}

// ---------- «билборд» над бойцом ----------
const BAR = { monster: { w: 112, h: 24, tpx: 2 }, human: { w: 78, h: 16, tpx: 1.55 } };
function makeBillboard(f, layer) {
  const isM = f.team === 'monster', S = BAR[isM ? 'monster' : 'human'];
  const el = h('div', 'bb ' + (isM ? 'bbm' : 'bbh'));
  el.style.setProperty('--w', S.w + 'px'); el.style.setProperty('--h', S.h + 'px');
  let heart = null;
  if (!isM) { heart = h('canvas', 'hrt'); heart.width = heart.height = 64; el.appendChild(heart); }
  const trk = h('div', 'trk'), kr = h('i', 'kr'), fill = h('i', 'fill');
  const txt = pixLabel('txt');
  trk.append(kr, fill, txt); el.appendChild(trk);
  // щит святого зелья — второй сегмент под полоской HP
  const shTrk = h('div', 'shtrk'), sh = h('i', 'sh'); shTrk.appendChild(sh); el.appendChild(shTrk);
  const nm = pixLabel('nm');
  el.appendChild(nm);
  nm.set(f.name.length > 16 ? f.name.slice(0, 15) + '…' : f.name, 1.25, { fill: '#C9CDD2', outline: '#1E1E1E', outlinePx: 1 });
  layer.appendChild(el);
  return { f, el, heart, kr, fill, sh, shTrk, txt, S, isM, c: {} };
}
function heartDraw(b, color) {
  if (b.c.heart === color) return;
  b.c.heart = color;
  const g = b.heart.getContext('2d'); g.clearRect(0, 0, 64, 64);
  g.drawImage(heartTex(color).image, 0, 0, 64, 64);
}

// ---------- диалоговое окно (Undertale): чёрное, белая рамка 3 px, 70% ширины, строчный пиксельный текст ----------
// lines: [{ text, hold?, pre?, eyes?, event? }]. Печать TYPE_CPS букв/с, «бип» на букву (кроме пробелов),
// после строки — пауза hold (LINE_HOLD). Тап по окну: допечатать строку / дальше. «Пропустить» — сразу в конец.
function createDialogue(root) {
  const box = h('div', 'jd-dlg');
  const r1 = pixLabel('dr'), r2 = pixLabel('dr');
  const skipB = h('button', 'dskip'); const skipL = pixLabel('ds'); skipB.appendChild(skipL);
  box.append(r1, r2, skipB);
  root.appendChild(box);
  let L = null, i = 0, n = 0, acc = 0, t = 0, phase = 'off', rows = [''], cb = {}, shown = '';
  const px = () => Math.max(1.7, Math.min(3.2, innerHeight * 0.0062));
  // перенос по словам, чтобы буквы не «прыгали» между строками во время печати
  const wrap = (str) => {
    const maxW = box.clientWidth - 34, P2 = px(), out = [''];
    for (const w of str.split(' ')) {
      const cur = out[out.length - 1], cand = cur ? cur + ' ' + w : w;
      if (measurePixText('* ' + cand, P2) <= maxW || !cur) out[out.length - 1] = cand; else out.push(w);
    }
    return out.slice(0, 2);
  };
  const render = () => {
    let left = n, a = '', b = '';
    if (phase !== 'pre' && L) {
      a = rows[0].slice(0, left); left -= rows[0].length + 1;
      if (rows[1] && left > 0) b = rows[1].slice(0, left);
    }
    const s = a + '|' + b;
    if (s === shown) return;
    shown = s;
    const p = px(), st = { fill: '#FFFFFF' };
    r1.set(a || phase === 'pre' ? '* ' + a : ' ', p, st);
    r2.set(b ? '  ' + b : ' ', p, st);
    r1.style.visibility = a ? 'visible' : 'hidden';
  };
  const begin = () => {
    const ln = L[i];
    rows = wrap(ln.text); n = 0; acc = 0;
    phase = ln.pre > 0 ? 'pre' : 'type'; t = ln.pre || 0;
    if (phase === 'type') cb.onLine?.(i, ln);
    render();
  };
  const next = () => {
    const ln = L[i];
    if (ln.event) cb.onEvent?.(ln.event, i);
    i++;
    if (i >= L.length) { phase = 'off'; box.classList.remove('show'); const d = cb.onDone; cb = {}; d?.(); return; }
    begin();
  };
  const total = () => rows.join(' ').length;
  box.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); api.tap(); });
  skipB.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); api.skip(); });
  const api = {
    get active() { return phase !== 'off'; },
    // поднять окно над панелью предметов (в интро ей можно пользоваться)
    setRaised(v) { box.classList.toggle('hi', !!v); },
    start(lines, callbacks = {}) {
      L = lines; i = 0; cb = callbacks; shown = '';
      box.classList.add('show');
      skipL.set('Пропустить', Math.max(1.3, px() * 0.55), { fill: '#bdbdbd' });
      begin();
    },
    update(dt) {
      if (phase === 'off') return;
      if (phase === 'pre') { t -= dt; if (t <= 0) { phase = 'type'; cb.onLine?.(i, L[i]); } else return; }
      if (phase === 'type') {
        acc += dt * TYPE_CPS;
        const all = rows.join(' ');
        while (acc >= 1 && n < all.length) { n++; acc--; if (all[n - 1] !== ' ') cb.onChar?.(all[n - 1]); }
        render();
        if (n >= all.length) { phase = 'hold'; t = L[i].hold ?? LINE_HOLD; }
        return;
      }
      if (phase === 'hold') { t -= dt; if (t <= 0) next(); }
    },
    // тап: допечатать строку, а если уже напечатана — следующая
    tap() {
      if (phase === 'type') { n = total(); render(); phase = 'hold'; t = Math.min(L[i].hold ?? LINE_HOLD, 0.7); }
      else if (phase === 'hold') next();
    },
    skip() { if (phase === 'off') return; const s = cb.onSkip; if (s) s(); else this.close(true); },
    // закрыть; fire — выполнить оставшиеся события и onDone
    close(fire = false) {
      if (phase === 'off') return;
      const lines = L, from = i, c = cb;
      phase = 'off'; cb = {}; box.classList.remove('show');
      if (fire) { for (let k = from; k < lines.length; k++) if (lines[k].event) c.onEvent?.(lines[k].event, k, true); c.onDone?.(); }
    },
  };
  return api;
}

export function createHUD() {
  const root = h('div', 'jd-hud');
  root.innerHTML = `<div class="bbs"></div><div class="banner"></div>
  <div class="spec"><button class="sprev"></button><span class="stxt"></span><button class="snext"></button><button class="sleave"></button></div>`;
  document.body.appendChild(root);
  const q = (s) => root.querySelector(s);
  const bbs = q('.bbs'), bannerEl = q('.banner'), spec = q('.spec'), stxtWrap = q('.stxt');
  const timer = pixLabel('timer'); root.appendChild(timer);
  const dodgeL = pixLabel('dodges'); root.appendChild(dodgeL);
  const bTitle = pixLabel('b1'), bSub = pixLabel('b2'); bannerEl.append(bTitle, bSub);
  const sTxt = pixLabel('st'); stxtWrap.appendChild(sTxt);
  const sPrev = pixLabel('sa'), sNext = pixLabel('sa'), sLeave = pixLabel('sl'); q('.sprev').appendChild(sPrev); q('.snext').appendChild(sNext); q('.sleave').appendChild(sLeave);
  for (const b of [q('.sprev'), q('.snext'), q('.sleave')]) { b.addEventListener('pointerdown', (e) => e.stopPropagation()); b.addEventListener('pointerup', (e) => e.stopPropagation()); }
  let specFn = null, leaveFn = null, leaveOn = null;
  q('.sprev').onclick = () => specFn?.(-1);
  q('.snext').onclick = () => specFn?.(1);
  q('.sleave').onclick = () => leaveFn?.();
  let boards = [], mode = 'human', bannerT = 0, specName = '', specOn = false;
  const uiK = () => Math.max(0.8, Math.min(1.6, innerHeight / 412));
  const dlg = createDialogue(document.body);

  return {
    root, dlg,
    show(v) { root.style.display = v ? 'block' : 'none'; },
    setup(G) {
      bbs.innerHTML = ''; boards = [];
      for (const f of [G.monster, ...G.humans]) boards.push(makeBillboard(f, bbs));
      mode = G.player ? G.player.team : 'spectator';
      dodgeL.style.display = mode === 'monster' ? 'block' : 'none';
      this.sec = this.dg = -1;
      spec.style.display = 'none'; specOn = false; specName = '';
    },
    showTimer(v) { timer.style.display = v ? 'block' : 'none'; if (mode === 'monster') dodgeL.style.display = v ? 'block' : 'none'; },
    update(G, dt) {
      const m = G.monster, cam = G.camera;
      if (bannerT > 0) { bannerT -= dt; if (bannerT <= 0) bannerEl.classList.remove('show'); }
      if (!m) return;
      const H = innerHeight, W = innerWidth, k = uiK();
      // таймер: цифры ≈5% высоты экрана, шаг ≈0.95 высоты, центр на 14% сверху
      const dh = Math.max(16, Math.round(H * 0.053));
      const sec = Math.max(0, Math.ceil(G.roundLeft));
      if (sec !== this.sec || H !== this.H) { this.sec = sec; this.H = H; timer.set(String(sec), dh / 7, TIMER_STYLE); this.dg = -1; }
      if (mode === 'monster' && m.dodges !== this.dg) { this.dg = m.dodges; dodgeL.set('УКЛОНЕНИЯ: ' + m.dodges, Math.max(1.4, H * 0.0042), DODGE_STYLE); }
      // билборды
      for (const b of boards) {
        const f = b.f, el = b.el;
        let vis = !(f.dead && (!b.isM || !f.model.root.visible)) && G.state !== 'lobby' && !(b.isM && G.cutIntro);
        if (vis) {
          P.set(f.pos.x, f.pos.y + f.model.barY, f.pos.z);
          const dist = P.distanceTo(cam.position);
          P.project(cam);
          if (P.z > 1 || P.x < -1.3 || P.x > 1.3 || P.y < -1.3 || P.y > 1.4 || dist < 2.5) vis = false;
          else {
            const x = Math.round((P.x * 0.5 + 0.5) * W * 2) / 2, y = Math.round((-P.y * 0.5 + 0.5) * H * 2) / 2;
            const s = Math.round(k * Math.max(0.6, Math.min(1, 15 / Math.max(1, dist))) * 50) / 50;
            const tr = `translate3d(${x}px,${y}px,0) scale(${s})`;
            if (b.c.tr !== tr) { b.c.tr = tr; el.style.transform = tr; }
            const z = String(Math.max(1, 900 - Math.round(dist * 4)));
            if (b.c.z !== z) { b.c.z = z; el.style.zIndex = z; }
          }
        }
        if (b.c.vis !== vis) { b.c.vis = vis; el.style.display = vis ? 'block' : 'none'; }
        if (!vis) continue;
        if (b.isM) {
          const kk = f.hp > 0 ? f.hp / f.maxHp : 2 / b.S.w; // при убийстве — тонкая голубая полоска у края, «0/1» на чёрном
          if (b.c.k !== kk) { b.c.k = kk; b.fill.style.transform = `scaleX(${kk})`; }
          const hpi = Math.max(0, Math.ceil(f.hp));
          if (b.c.hp !== hpi) { b.c.hp = hpi; b.txt.set(hpi + '/' + f.maxHp, b.S.tpx, PIX.bar); }
        } else {
          const hp = Math.max(0, f.hp), kr = f.karma > 0 ? Math.min(hp - 1, f.karma * Math.max(1, f.maxHp * 0.01)) : 0; // сколько съест карма
          const kf = Math.round(Math.max(0, hp - Math.max(0, kr)) / f.maxHp * 500) / 500;
          const kk = Math.round(hp / f.maxHp * 500) / 500;
          if (b.c.k !== kf) { b.c.k = kf; b.fill.style.transform = `scaleX(${kf})`; }
          if (b.c.kr !== kk) { b.c.kr = kk; b.kr.style.transform = `scaleX(${kk})`; }
          // пирог/зелье: полоска на миг вспыхивает; святое зелье — золотая заливка
          const flash = G.time - (f.barFlashAt ?? -9) < 0.3, holy = f.holyUntil > G.time;
          const col = flash ? '#FFFFFF' : holy ? '#FFE040' : '';
          if (b.c.col !== col) { b.c.col = col; b.fill.style.background = col; }
          const shk = Math.round(Math.min(1, (f.shield || 0) / f.maxHp) * 100) / 100;
          if (b.c.sh !== shk) { b.c.sh = shk; b.sh.style.transform = `scaleX(${shk})`; b.shTrk.style.display = shk > 0 ? 'block' : 'none'; }
          const hpi = Math.ceil(hp), krOn = f.karma > 0.05;
          if (b.c.hp !== hpi || b.c.krOn !== krOn) { b.c.hp = hpi; b.c.krOn = krOn; b.txt.set(hpi + '/' + f.maxHp, b.S.tpx, krOn ? KR_STYLE : PIX.bar); }
          heartDraw(b, f.color);
          // сердце-душа пульсирует (вторая жизнь Решимости, пирог)
          const pk = G.time - (f.pulseAt ?? -9), ps = pk < 0.7 ? 1 + Math.sin((pk / 0.7) * Math.PI) * (f.dtUntil > G.time ? 1.4 : 0.5) : 1;
          const pss = Math.round(ps * 20) / 20;
          if (b.c.ps !== pss) { b.c.ps = pss; b.heart.style.transform = pss === 1 ? '' : `scale(${pss})`; b.heart.style.animationPlayState = pss === 1 ? '' : 'paused'; }
        }
      }
    },
    // баннер пиксельным шрифтом (end — конец раунда: на тёмной полосе)
    banner(big, sub = '', ms = 2200, color = '#ffffff', end = false) {
      const H = innerHeight, W = innerWidth;
      const px = Math.min(Math.max(3, H * 0.085 / 7), (W * 0.9) / Math.max(1, measurePixText(big, 1)));
      bTitle.set(big, px, { fill: color, outline: '#141414', outlineW: Math.max(2, H * 0.006) });
      bSub.style.display = sub ? 'block' : 'none';
      if (sub) bSub.set(sub, Math.max(1.6, H * 0.032 / 7), { fill: '#ffffff', outline: '#141414', outlineW: Math.max(1, H * 0.0035) });
      bannerEl.classList.toggle('end', end);
      bannerEl.classList.add('show'); bannerT = ms / 1000;
    },
    hideBanner() { bannerEl.classList.remove('show'); bannerT = 0; },
    // полоска наблюдения «< Наблюдение: Имя >»
    // canLeave — кнопка «Лобби» (режим «Наблюдать» из лобби: в раунде только боты)
    spectate(on, name, canLeave = false) {
      if (on !== specOn) { specOn = on; spec.style.display = on ? 'flex' : 'none'; }
      if (!on) return;
      const px = Math.max(1.7, innerHeight * 0.0055);
      if (name !== specName) { specName = name; sTxt.set('Наблюдение: ' + (name.length > 16 ? name.slice(0, 15) + '…' : name), px, PIX.panel); sPrev.set('<', px * 1.4, PIX.panel); sNext.set('>', px * 1.4, PIX.panel); }
      if (canLeave !== leaveOn) { leaveOn = canLeave; q('.sleave').style.display = canLeave ? 'flex' : 'none'; if (canLeave) sLeave.set('Лобби', px * 0.85, PIX.panel); }
    },
    onSpecNext(fn) { specFn = fn; },
    onSpecLeave(fn) { leaveFn = fn; },
  };
}

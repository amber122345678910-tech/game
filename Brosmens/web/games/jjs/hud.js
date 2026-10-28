// Интерфейс боя: HP/пробуждение, таблица, кил-фид, цифры урона, ники над головами, экраны выбора/смерти/итогов.
import * as THREE from 'three';
import { CHARS, CHAR_IDS } from './skills.js';
import { drawPortrait, LOOKS } from './rig.js';
import { AW_DUR } from './fighter.js';

const CSS = `
.jh{position:fixed;z-index:30;pointer-events:none;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff}
:root{--hand:"Patrick Hand","Comic Sans MS","Chalkboard SE","Comic Neue",casual,"Coming Soon",system-ui,sans-serif}
#jh-over{position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:29;pointer-events:none}
.jh-bot{left:50%;bottom:6px;transform:translateX(-50%);width:300px;display:flex;flex-direction:column;align-items:center}
.jh-awl{font:16px/1.05 var(--hand);color:#fff;letter-spacing:.3px;white-space:nowrap;margin-bottom:3px;text-shadow:1.5px 0 0 #1b1b1b,-1.5px 0 0 #1b1b1b,0 1.5px 0 #1b1b1b,0 -1.5px 0 #1b1b1b,1px 1px 0 #1b1b1b,-1px 1px 0 #1b1b1b,1px -1px 0 #1b1b1b,-1px -1px 0 #1b1b1b}
.jh-aw{position:relative;width:300px;height:18px;box-sizing:border-box;border:2px solid #2B2B2B;border-radius:2px;background:linear-gradient(#9C9C9C,#8E8E8E);overflow:hidden;pointer-events:auto;touch-action:none;cursor:pointer}
.jh-aw .fill{position:absolute;left:0;top:0;bottom:0;width:100%;transform-origin:left;transform:scaleX(0);background:linear-gradient(#ffffff,#d2d2d2)}
.jh-aw::after{content:'';position:absolute;left:0;right:0;top:0;height:2px;background:rgba(255,255,255,.78);pointer-events:none}
.jh-aw .fl{position:absolute;inset:0;background:#fff;opacity:0;pointer-events:none}
.jh-aw.flash .fl{animation:jhfl .3s ease-out}
.jh-aw b{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font:800 11px/1 system-ui,sans-serif;color:#fff;letter-spacing:.2px;white-space:nowrap;text-shadow:1px 0 0 #234,-1px 0 0 #234,0 1px 0 #234,0 -1px 0 #234}
.jh-aw.on{filter:brightness(1.12)}
.jh-subs{display:flex;justify-content:space-between;width:300px;margin-top:3px}
.jh-sub{position:relative;width:49%;height:5px;box-sizing:border-box;border:1px solid rgba(25,25,25,.9);background:#d4d4d4;overflow:hidden}
.jh-sub i{position:absolute;left:0;top:0;bottom:0;width:100%;transform-origin:left;transform:scaleX(0)}
.jh-sub.ev i{background:#1c1c1c}
.jh-sub.ev.burst{box-shadow:0 0 6px #fff;border-color:#fff}
.jh-sub.sp i{background:#7f8c9e}
.jh-sub.sp.rdy i{background:#3E86F0}
.jh-sub.off{opacity:.35}
.jh-hot{display:flex;gap:6px;margin-top:6px;pointer-events:auto}
.jh-slot{position:relative;width:58px;height:58px;border-radius:3px;background:rgba(40,40,40,.5);overflow:hidden;touch-action:none}
.jh-slot .cd{position:absolute;left:0;right:0;bottom:0;height:0;background:#8C8C8C;opacity:.85}
.jh-slot .fl{position:absolute;inset:0;background:#fff;opacity:0}
.jh-slot.rdy .fl{animation:jhfl .12s linear}
.jh-slot.on{background:rgba(150,150,150,.6)}
.jh-slot .n{position:absolute;left:0;right:0;top:1px;text-align:center;font:22px/1 var(--hand);color:#fff;text-shadow:1.5px 0 0 #000,-1.5px 0 0 #000,0 1.5px 0 #000,0 -1.5px 0 #000,1px 1px 0 #000,-1px 1px 0 #000,1px -1px 0 #000,-1px -1px 0 #000}
.jh-slot .l{position:absolute;left:2px;right:2px;top:26px;bottom:2px;display:flex;align-items:flex-start;justify-content:center;text-align:center;font:600 11.5px/1.05 "Source Sans Pro","Segoe UI",system-ui,sans-serif;color:#fff;overflow:hidden;text-shadow:0 1px 1px rgba(0,0,0,.45);overflow-wrap:anywhere}
.jh-slot.tp .l{top:24px}
.jh-slot .tip{position:absolute;left:0;right:0;bottom:2px;text-align:center;font:800 8px/1 system-ui,sans-serif;letter-spacing:.4px;color:rgba(255,255,255,.88);text-transform:uppercase}
@keyframes jhfl{0%{opacity:1}100%{opacity:0}}
.jh-hpb{top:121px;right:8px;width:150px;height:8px;border-radius:4px;background:rgba(20,20,20,.6);border:1px solid rgba(0,0,0,.55);overflow:hidden;opacity:0;transition:opacity .3s}
.jh-hpb i{position:absolute;left:0;top:0;bottom:0;width:100%;transform-origin:left;background:#3cd23c;transition:transform .12s}
.jh-chant{position:fixed;left:0;top:0;z-index:45;pointer-events:none;background:#fff;border:2.5px solid #141414;border-radius:48% 52% 46% 54%/55% 45% 58% 42%;padding:7px 13px 8px;font:900 15px/1 var(--hand);color:#111;text-transform:uppercase;letter-spacing:.3px;white-space:nowrap;box-shadow:1.5px 1.5px 0 #141414,3px 3px 0 rgba(0,0,0,.18);will-change:transform,opacity}
.jh-chant::after{content:'';position:absolute;left:9px;bottom:-10px;width:13px;height:13px;background:#fff;border-left:2.5px solid #141414;border-bottom:2.5px solid #141414;transform:skewX(-28deg) rotate(-16deg)}
.jh-manga{position:fixed;left:0;top:0;z-index:45;pointer-events:none;background:#fff;border:3px solid #000;padding:7px 8px 8px;width:min-content;min-width:88px;max-width:160px;box-sizing:border-box;font:italic 900 16px/1.02 "Arial Black","Impact",system-ui,sans-serif;color:#000;text-transform:uppercase;letter-spacing:.2px;box-shadow:4px 4px 0 rgba(0,0,0,.4);will-change:transform,opacity}
#jh-shatter{position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:28;pointer-events:none;display:none}
/* список игроков как в роблоксе: «Игроки | Убийства», своя строка подсвечена */
.jh-sb{top:6px;right:8px;width:168px;background:rgba(28,28,30,.62);border-radius:8px;overflow:hidden;font:600 11px/1 "Builder Sans","Gotham SSm","Montserrat",system-ui,sans-serif}
.jh-sb .hd{display:flex;align-items:center;height:20px;padding:0 8px;background:rgba(0,0,0,.32);color:#d2d2d2;font-weight:800;font-size:10px;letter-spacing:.2px}
.jh-sb .r{display:flex;align-items:center;height:15px;padding:0 8px;white-space:nowrap;color:#fff}
.jh-sb .r:nth-child(even){background:rgba(255,255,255,.04)}
.jh-sb .r span:first-child,.jh-sb .hd span:first-child{flex:1;overflow:hidden;text-overflow:ellipsis}
.jh-sb .r span:last-child,.jh-sb .hd span:last-child{width:56px;text-align:center}
.jh-sb .r.me{background:rgba(255,255,255,.22)}
.jh-top{left:50%;top:6px;transform:translateX(-50%);text-align:center}
.jh-timer{font:800 12px/1 system-ui;background:rgba(20,20,20,.6);border-radius:11px;padding:5px 10px;display:inline-block;letter-spacing:.3px}
/* кил-фид справа под списком: белые строки «убийца → жертва» */
.jh-kf{top:142px;right:108px;display:flex;flex-direction:column;align-items:flex-end;gap:2px}
.jh-kf div{font:700 11px/1 system-ui;color:#fff;background:rgba(20,20,20,.5);border-radius:5px;padding:3px 7px;transition:opacity .6s;white-space:nowrap;text-shadow:0 1px 1px rgba(0,0,0,.6)}
.jh-kf div.me{background:rgba(60,60,60,.7)}
/* счётчик урона JJS: красный «N DMG», над ним урон последнего удара */
.jh-dmg{right:22%;top:24%;text-align:right;opacity:0;transition:opacity .35s;transform-origin:right center}
.jh-dmg i{display:block;font:italic 800 13px/1 system-ui;color:#ffd9d9;text-shadow:1px 1px 0 #000,-1px -1px 0 #000,1px -1px 0 #000,-1px 1px 0 #000;margin-bottom:1px}
.jh-dmg b{display:block;font:900 26px/1 system-ui;color:#ff2b2b;letter-spacing:.5px;text-shadow:2px 2px 0 #000,-1px -1px 0 #000,1px -1px 0 #000,-1px 1px 0 #000,0 0 8px rgba(255,0,0,.35)}
.jh-dmg.pop b{animation:jhpop .16s}
@keyframes jhpop{0%{transform:scale(1.6)}100%{transform:scale(1)}}
.jh-flash{inset:0;opacity:0;z-index:28}
.jh-inv{inset:0;z-index:28;backdrop-filter:invert(1) contrast(1.6);-webkit-backdrop-filter:invert(1) contrast(1.6);display:none}
.jh-vig{inset:0;z-index:27;opacity:0;background:radial-gradient(ellipse at center,rgba(0,0,0,0) 55%,rgba(200,0,0,.65) 100%);transition:opacity .3s}
.jh-tint{inset:0;z-index:26;opacity:0;transition:opacity .5s}
.jh-call{left:50%;top:17%;transform:translateX(-50%);text-align:center;opacity:0;transition:opacity .3s;white-space:nowrap}
.jh-call b{display:block;font:900 min(4.2vw,26px)/1.1 system-ui;letter-spacing:1px;text-shadow:0 3px 0 #000,0 0 18px var(--c)}
.jh-call span{font:800 12px system-ui;opacity:.85;text-shadow:0 1px 2px #000}
.jh-scr{position:fixed;inset:0;z-index:58;display:flex;flex-direction:column;align-items:center;justify-content:center;background:radial-gradient(ellipse at 50% 30%,#2a1840,#07060c 75%);pointer-events:auto;font-family:system-ui,sans-serif;color:#fff;padding:8px}
.jh-scr h1{margin:0;font:900 min(6vw,30px)/1 system-ui;letter-spacing:1px;text-shadow:0 3px 0 #000,0 0 18px rgba(200,120,255,.5)}
.jh-scr h1 em{font-style:normal;color:#c77dff}
.jh-scr .sub{font:700 12px system-ui;opacity:.75;margin:4px 0 8px}
.jh-cards{display:flex;gap:min(1.6vw,12px);justify-content:center;max-width:100%}
.jh-card{width:min(22.5vw,200px);background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.18);border-radius:12px;overflow:hidden;cursor:pointer;transition:transform .15s,border-color .15s,box-shadow .15s;display:flex;flex-direction:column}
.jh-card canvas{width:100%;height:auto;display:block;aspect-ratio:16/10}
.jh-card .tx{padding:5px 7px 7px}
.jh-card h3{margin:0;font:900 min(1.75vw,13px)/1.15 system-ui}
.jh-card .ru{font:800 10px system-ui;margin:1px 0 3px}
.jh-card p{margin:0;font:600 min(1.45vw,10.5px)/1.25 system-ui;opacity:.85}
.jh-card .aw{margin-top:4px;font:700 min(1.35vw,9.5px)/1.2 system-ui;opacity:.9}
.jh-card.sel{transform:translateY(-3px);border-color:var(--c);box-shadow:0 0 16px var(--c)}
.jh-go{margin-top:10px;border:0;border-radius:12px;padding:10px 34px;font:900 17px system-ui;color:#fff;background:linear-gradient(#a259ff,#6b2bd9);box-shadow:0 4px 0 #3d1680;cursor:pointer}
.jh-go:active{transform:translateY(2px);box-shadow:0 2px 0 #3d1680}
.jh-death{position:fixed;inset:0;z-index:55;display:flex;flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,.35);pointer-events:none;font-family:system-ui;color:#fff}
.jh-death h2{margin:0;font:900 26px system-ui;text-shadow:0 3px 0 #000}
.jh-death>*{transform:translateY(-22px)}
.jh-death .k{font:700 13px system-ui;opacity:.9;margin:4px 0 2px}
.jh-death .t{font:800 14px system-ui;margin-bottom:10px}
.jh-mini{display:flex;gap:8px;pointer-events:auto}
.jh-mini div{width:96px;border-radius:9px;border:2px solid rgba(255,255,255,.25);background:rgba(0,0,0,.4);overflow:hidden;cursor:pointer;text-align:center;font:800 9.5px/1.2 system-ui;padding-bottom:3px}
.jh-mini canvas{width:100%;display:block}
.jh-mini div.sel{border-color:var(--c);box-shadow:0 0 12px var(--c)}
.jh-res table{border-collapse:collapse;margin:8px 0;font:700 13px system-ui;min-width:min(80vw,380px)}
.jh-res td,.jh-res th{padding:3px 10px;text-align:left}
.jh-res th{opacity:.6;font-size:11px}
.jh-res tr.me{background:rgba(255,255,255,.12)}
.jh-res .btns{display:flex;gap:10px}
.jh-res .btns button{border:0;border-radius:10px;padding:9px 20px;font:900 15px system-ui;color:#fff;background:#6b2bd9;cursor:pointer}
.jh-res .btns button.gray{background:#444a58}
`;

const _v = new THREE.Vector3();
// Размер шрифта названия навыка: не больше 2 строк в ячейке 54 px, слова не рвутся (меряем настоящую ширину текста)
const _mc = document.createElement('canvas').getContext('2d');
function fitLabel(text) {
  const words = text.split(' ');
  for (let fs = 11.5; fs >= 7.5; fs -= 0.5) {
    _mc.font = `600 ${fs}px "Source Sans Pro","Segoe UI",system-ui,sans-serif`;
    const sp = _mc.measureText(' ').width;
    let lines = 1, cur = 0, ok = true;
    for (const w of words) {
      const ww = _mc.measureText(w).width;
      if (ww > 53) { ok = false; break; }
      if (cur === 0) cur = ww;
      else if (cur + sp + ww <= 53) cur += sp + ww;
      else { lines++; cur = ww; }
    }
    if (ok && lines <= 2) return fs;
  }
  return 7.5;
}

export function createHUD() {
  const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
  const el = (cls, html = '', parent = document.body) => { const d = document.createElement('div'); d.className = cls; d.innerHTML = html; parent.appendChild(d); return d; };

  const over = document.createElement('canvas'); over.id = 'jh-over'; document.body.appendChild(over);
  const g = over.getContext('2d');
  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 1.5);
    W = innerWidth; H = innerHeight;
    over.width = Math.round(W * DPR); over.height = Math.round(H * DPR);
  }
  resize(); addEventListener('resize', resize);

  // ---------- нижняя боевая панель (как в JJS): название пробуждения, шкала, 2 подшкалы, 4 ячейки ----------
  const bot = el('jh jh-bot', `<div class="jh-awl"></div>
    <div class="jh-aw"><i class="fill"></i><i class="fl"></i><b></b></div>
    <div class="jh-subs"><div class="jh-sub ev"><i></i></div><div class="jh-sub sp"><i></i></div></div>
    <div class="jh-hot"></div>`);
  const hot = bot.querySelector('.jh-hot');
  const slots = [];
  let skillPress = null, skillRelease = null, awakenTap = null;
  for (let i = 0; i < 4; i++) {
    const d = document.createElement('div'); d.className = 'jh-slot';
    d.innerHTML = `<i class="cd"></i><i class="fl"></i><span class="n">${i + 1}</span><span class="l"></span><span class="tip"></span>`;
    const up = (e) => { e.preventDefault(); e.stopPropagation(); if (!d.classList.contains('on')) return; d.classList.remove('on'); skillRelease?.(i); };
    d.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); try { d.setPointerCapture(e.pointerId); } catch {} d.classList.add('on'); skillPress?.(i); });
    d.addEventListener('pointerup', up); d.addEventListener('pointercancel', up);
    hot.appendChild(d);
    slots.push({ d, cd: d.querySelector('.cd'), l: d.querySelector('.l'), tip: d.querySelector('.tip'), key: '', frac: -1, wasCd: false });
  }
  const awLabel = bot.querySelector('.jh-awl');
  const awBar = bot.querySelector('.jh-aw'), awFill = awBar.querySelector('.fill'), awB = awBar.querySelector('b');
  const evBar = bot.querySelector('.jh-sub.ev'), evI = evBar.querySelector('i');
  const spBar = bot.querySelector('.jh-sub.sp'), spI = spBar.querySelector('i');
  awBar.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); awBar.classList.add('on'); awakenTap?.(); });
  const awUp = () => awBar.classList.remove('on');
  awBar.addEventListener('pointerup', awUp); awBar.addEventListener('pointercancel', awUp); awBar.addEventListener('pointerleave', awUp);
  const coarse = matchMedia('(pointer:coarse)').matches;
  const C = { mode: '', fill: -1, ev: -1, sp: -1, spOn: null, burst: null, hide: null, label: '' };
  // здоровье — как в роблоксе: справа сверху, только когда не полное
  const hpb = el('jh jh-hpb', '<i></i>');
  const hpI = hpb.querySelector('i');
  let hpK = -1;
  // манга-реплики пробуждения и стеклянный экран (Limitless)
  const mangas = [];
  const shCv = document.createElement('canvas'); shCv.id = 'jh-shatter'; document.body.appendChild(shCv);
  const shG = shCv.getContext('2d');
  const capCv = document.createElement('canvas'), capG = capCv.getContext('2d');
  let capWant = false, capOk = false, shards = null, shT = 0, glCanvas = null;
  const sb = el('jh jh-sb');
  const top = el('jh jh-top', '<div class="jh-timer">4:00</div>');
  const timerEl = top.querySelector('.jh-timer');
  const kfEl = el('jh jh-kf');
  const dmgEl = el('jh jh-dmg', '<i></i><b></b>');
  const dmgLast = dmgEl.querySelector('i'), dmgTot = dmgEl.querySelector('b');
  const chants = [];
  const flashEl = el('jh jh-flash');
  const invEl = el('jh jh-inv');
  const vig = el('jh jh-vig');
  const tintEl = el('jh jh-tint');
  const callEl = el('jh jh-call', '<b></b><span></span>');

  const pops = [];
  let dmgSum = 0, dmgT = 0, callT = 0, flashA = 0, flashDecay = 3, hurtA = 0;
  const fmtD = (n) => String(Math.round(n * 100) / 100);
  const tags = [], placed = [];
  let lastSb = '';

  const api = {
    get W() { return W; }, get H() { return H; },
    setChar(f) {
      C.mode = ''; C.label = '';
      for (const S of slots) S.key = '';
    },
    onSkill(press, release) { skillPress = press; skillRelease = release; },
    onAwakenTap(fn) { awakenTap = fn; },
    // Ячейки навыков: defs[i] = {id, label, tip}
    setSkills(defs) {
      defs.forEach((sk, i) => {
        const S = slots[i];
        const id = sk ? sk.id : '-';
        if (S.key === id) return;
        S.key = id;
        S.l.textContent = sk ? sk.label : '';
        S.l.style.fontSize = fitLabel(sk ? sk.label : '') + 'px';
        S.tip.textContent = sk && sk.tip ? sk.tip : '';
        S.d.classList.toggle('tp', !!(sk && sk.tip));
      });
    },
    // Перезарядка: ячейка становится плоско-серой, серое сжимается сверху вниз; готово — белая вспышка
    setCooldowns(rems, maxs) {
      for (let i = 0; i < 4; i++) {
        const S = slots[i];
        const r = rems[i], f = r > 0 ? Math.min(1, r / maxs[i]) : 0;
        const fq = Math.round(f * 200);
        if (fq !== S.frac) { S.frac = fq; S.cd.style.height = (f * 100).toFixed(1) + '%'; }
        const on = r > 0;
        if (S.wasCd && !on) { S.d.classList.remove('rdy'); void S.d.offsetWidth; S.d.classList.add('rdy'); }
        S.wasCd = on;
      }
    },
    setBoxesHidden(h) { if (C.hide !== h) { C.hide = h; hot.style.visibility = h ? 'hidden' : ''; } },
    // Шкала пробуждения + подшкалы (уклонение / перезарядка особого навыка)
    updateCombat(p) {
      const aw = p.ch.awaken;
      if (C.label !== aw.label) { C.label = aw.label; awLabel.textContent = aw.label; }
      let mode, fill;
      if (p.awakened > 0) { mode = 'aw'; fill = Math.min(1, p.awakened / AW_DUR); }
      else if (p.meter >= 100) { mode = 'full'; fill = 1; }
      else { mode = 'fill'; fill = p.meter / 100; }
      if (mode !== C.mode) {
        if (mode === 'full') { awBar.classList.remove('flash'); void awBar.offsetWidth; awBar.classList.add('flash'); }
        C.mode = mode;
        awBar.classList.toggle('full', mode === 'full');
        awFill.style.background = mode === 'aw' ? `linear-gradient(${aw.grad[0]},${aw.grad[1]})` : mode === 'full' ? 'linear-gradient(#F2F2F2,#9FC9E8)' : '';
        awB.textContent = mode === 'full' ? (coarse ? 'Нажми, чтобы пробудиться' : 'Нажми G, чтобы пробудиться') : '';
      }
      const fq = Math.round(fill * 600);
      if (fq !== C.fill) { C.fill = fq; awFill.style.transform = `scaleX(${fill.toFixed(4)})`; }
      const ev = Math.round(p.evasive);
      if (ev !== C.ev) { C.ev = ev; evI.style.transform = `scaleX(${(ev / 100).toFixed(3)})`; }
      const burst = p.burst > 0;
      if (burst !== C.burst) { C.burst = burst; evBar.classList.toggle('burst', burst); }
      const sp = p.specialDef();
      const spOn = !!sp;
      if (spOn !== C.spOn) { C.spOn = spOn; spBar.classList.toggle('off', !spOn); }
      const k = !spOn ? 0 : p.specCd > 0 ? 1 - p.specCd / p.specCdMax : 1;
      const kq = Math.round(k * 300);
      if (kq !== C.sp) { C.sp = kq; spI.style.transform = `scaleX(${k.toFixed(3)})`; spBar.classList.toggle('rdy', k >= 1); }
    },
    // Манга-панель реплики рядом с персонажем (пробуждение)
    manga(f, text, idx = 0) {
      const d = document.createElement('div'); d.className = 'jh-manga'; d.textContent = text;
      d.style.opacity = 0;
      document.body.appendChild(d);
      mangas.push({ d, f, idx, t: 0, w: 0, h: 0 });
    },
    // Limitless: кадр «до» снимается после рендера, затем экран раскалывается на осколки
    setGL(c) { glCanvas = c; },
    captureShatter() { capWant = true; },
    afterRender(c) {
      if (!capWant) return;
      capWant = false;
      const w = Math.max(2, Math.round(W * 0.6)), h = Math.max(2, Math.round(H * 0.6));
      if (capCv.width !== w || capCv.height !== h) { capCv.width = w; capCv.height = h; }
      try { capG.drawImage(c, 0, 0, w, h); capOk = true; } catch { capOk = false; }
      if (glCanvas) glCanvas.style.filter = 'saturate(0.2) contrast(1.1)';
    },
    shatter() {
      shCv.width = Math.round(W * DPR); shCv.height = Math.round(H * DPR);
      const cx = W * (0.46 + Math.random() * 0.08), cy = H * (0.44 + Math.random() * 0.1), D = Math.hypot(W, H);
      const N = 8, angs = [];
      for (let i = 0; i < N; i++) angs.push(((i + 0.2 + Math.random() * 0.6) / N) * Math.PI * 2);
      const inner = angs.map((a) => { const r = D * (0.1 + Math.random() * 0.12); return [cx + Math.cos(a) * r, cy + Math.sin(a) * r]; });
      const outer = angs.map((a) => [cx + Math.cos(a) * D, cy + Math.sin(a) * D]);
      shards = [];
      const mk = (pts) => {
        let mx = 0, my = 0; for (const [x, y] of pts) { mx += x; my += y; } mx /= pts.length; my /= pts.length;
        let dx = mx - cx, dy = my - cy; const l = Math.hypot(dx, dy) || 1; dx /= l; dy /= l;
        const sp = 520 + Math.random() * 520;
        shards.push({ pts, mx, my, vx: dx * sp, vy: dy * sp - 120, rot: 0, w: (Math.random() - 0.5) * 7 });
      };
      for (let i = 0; i < N; i++) {
        const j = (i + 1) % N;
        mk([[cx, cy], inner[i], inner[j]]);
        mk([inner[i], outer[i], outer[j], inner[j]]);
      }
      shT = 0; shCv.style.display = 'block';
    },
    pop(pos, text, color = '#fff', scale = 1) {
      if (pops.length > 40) pops.shift();
      pops.push({ x: pos.x, y: pos.y, z: pos.z, text, color, scale, t: 0, life: text.length > 4 ? 1.1 : 0.8, dx: (Math.random() - 0.5) * 30 });
    },
    // Счётчик урона (как в JJS): сумма комбо + урон последнего удара; держится 3 с, затем сброс
    dmg(n) {
      dmgSum += n; dmgT = 3;
      dmgLast.textContent = fmtD(n);
      dmgTot.textContent = fmtD(dmgSum) + ' DMG';
      dmgEl.classList.remove('pop'); void dmgEl.offsetWidth; dmgEl.classList.add('pop');
      dmgEl.style.opacity = 1;
    },
    // Заклинание (Incantation): белый «рукописный» пузырь у головы, каждый следующий заменяет предыдущий
    chant(f, text) {
      for (let i = chants.length - 1; i >= 0; i--) if (chants[i].f === f) { chants[i].d.remove(); chants.splice(i, 1); }
      const d = document.createElement('div'); d.className = 'jh-chant'; d.textContent = text; d.style.opacity = 0;
      document.body.appendChild(d);
      chants.push({ d, f, t: 0, w: 0, h: 0, rot: (Math.random() - 0.5) * 6 });
    },
    hurt(dmg) { hurtA = Math.min(1, hurtA + dmg / 25); },
    flash(color, alpha = 0.5, decay = 3) { flashEl.style.background = color; flashA = Math.max(flashA, alpha); flashDecay = decay; },
    blackFlash() {
      invEl.style.display = 'block';
      setTimeout(() => { invEl.style.display = 'none'; api.flash('#ff1030', 0.35, 4); }, 90);
    },
    tint(css) { if (css) { tintEl.style.background = css; tintEl.style.opacity = 1; } else tintEl.style.opacity = 0; },
    callout(text, sub, color) {
      callEl.querySelector('b').textContent = text;
      callEl.querySelector('span').textContent = sub || '';
      callEl.style.setProperty('--c', color);
      callEl.querySelector('b').style.color = color;
      callEl.style.opacity = 1; callT = 2.0;
    },
    killfeed(killer, victim, kc, vc) {
      const d = document.createElement('div');
      const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
      d.innerHTML = killer ? `${esc(killer)} → ${esc(victim)}` : `${esc(victim)} погиб`;
      if (kc === 'me') d.className = 'me';
      kfEl.prepend(d);
      while (kfEl.children.length > 3) kfEl.lastChild.remove();
      setTimeout(() => (d.style.opacity = 0), 5000);
      setTimeout(() => d.remove(), 5700);
    },
    setTimer(sec) {
      const s = Math.max(0, Math.ceil(sec));
      timerEl.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      timerEl.style.color = s <= 20 ? '#ff6060' : '#fff';
    },
    showHUD(on) {
      for (const e of [bot, sb, top, hpb, kfEl, dmgEl]) e.style.display = on ? '' : 'none';
      if (!on) { for (const m of mangas) m.d.remove(); mangas.length = 0; for (const c of chants) c.d.remove(); chants.length = 0; dmgSum = 0; dmgT = 0; dmgEl.style.opacity = 0; }
    },

    update(dt, camera, fighters, player) {
      // нижняя панель
      if (player) {
        api.updateCombat(player);
        const k = Math.max(0, player.hp) / player.maxHp;
        const kq = Math.round(k * 400);
        if (kq !== hpK) {
          hpK = kq;
          hpI.style.transform = `scaleX(${k.toFixed(3)})`;
          hpI.style.background = k > 0.5 ? '#3cd23c' : k > 0.25 ? '#f2c52a' : '#e83a3a';
          hpb.style.opacity = k < 0.999 && !player.dead ? 1 : 0;
        }
        const lowHp = !player.dead && k < 0.3 ? 0.35 + Math.sin(performance.now() / 180) * 0.15 : 0;
        vig.style.opacity = Math.max(hurtA, lowHp);
      }
      hurtA = Math.max(0, hurtA - dt * 1.8);
      if (dmgT > 0) { dmgT -= dt; if (dmgT <= 0) { dmgSum = 0; dmgEl.style.opacity = 0; } }
      if (callT > 0) { callT -= dt; if (callT <= 0) callEl.style.opacity = 0; }
      if (flashA > 0) { flashA = Math.max(0, flashA - dt * flashDecay); flashEl.style.opacity = flashA; }

      // таблица
      const rows = fighters.slice().sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
      let html = '<div class="hd"><span>Игроки</span><span>Убийства</span></div>';
      const meIdx = rows.indexOf(player);
      const shown = rows.slice(0, 6);
      if (meIdx >= 6) shown[5] = player;
      for (const f of shown) {
        html += `<div class="r${f === player ? ' me' : ''}"><span>${f.name.replace(/</g, '')}${f.isClaude ? ' ✦' : ''}</span><span>${f.kills}</span></div>`;
      }
      if (html !== lastSb) { sb.innerHTML = html; lastSb = html; }

      // оверлей
      g.setTransform(DPR, 0, 0, DPR, 0, 0);
      g.clearRect(0, 0, W, H);
      g.textAlign = 'center';
      g.lineJoin = 'round';
      const cp = camera.position;
      // ники как в роблоксе: светло-серые 12px с тёмной обводкой, тонкая полоска HP — только при уроне;
      // дальше ~45 стадов и перекрытые более близкими — скрыты
      tags.length = 0;
      for (const f of fighters) {
        if (f.dead || f === player || f.vanish > 0) continue;
        _v.set(f.pos.x, f.pos.y + 5.9 * f.scale + 1.1, f.pos.z);
        const dist = _v.distanceTo(cp);
        if (dist > 45) continue;
        _v.project(camera);
        if (_v.z > 1 || _v.x < -1.05 || _v.x > 1.05 || _v.y < -1.05 || _v.y > 1.05) continue;
        tags.push({ f, dist, x: (_v.x + 1) * 0.5 * W, y: (1 - _v.y) * 0.5 * H });
      }
      tags.sort((a, b) => a.dist - b.dist);
      placed.length = 0;
      g.font = '700 12px "Builder Sans","Gotham SSm",system-ui,sans-serif';
      g.lineWidth = 2.5; g.strokeStyle = 'rgba(20,20,20,.9)';
      for (const tg of tags) {
        const f = tg.f;
        const nm = f.isClaude ? `${f.name} ✦` : f.name;
        const w = g.measureText(nm).width, hurt = f.hp < f.maxHp - 0.05;
        const x0 = tg.x - w / 2 - 2, x1 = tg.x + w / 2 + 2, y0 = tg.y - 12, y1 = tg.y + (hurt ? 8 : 2);
        let clash = false;
        for (let i = 0; i < placed.length; i += 4) if (x0 < placed[i + 2] && x1 > placed[i] && y0 < placed[i + 3] && y1 > placed[i + 1]) { clash = true; break; }
        if (clash) continue;
        placed.push(x0, y0, x1, y1);
        g.globalAlpha = tg.dist > 35 ? (45 - tg.dist) / 10 : 1;
        g.strokeText(nm, tg.x, tg.y); g.fillStyle = f.isClaude ? '#fff4e6' : '#ececec'; g.fillText(nm, tg.x, tg.y);
        if (hurt) {
          const bw = 40, k = Math.max(0, f.hp / f.maxHp);
          g.fillStyle = 'rgba(15,15,15,.7)'; g.fillRect(tg.x - bw / 2 - 1, tg.y + 3, bw + 2, 6);
          g.fillStyle = k > 0.5 ? '#3ccf3c' : k > 0.25 ? '#f2c52a' : '#e83a3a';
          g.fillRect(tg.x - bw / 2, tg.y + 4, bw * k, 4);
        }
      }
      // Outburst: 3-сегментная розовая шкала заряда справа от игрока
      if (player && player.charge && !player.dead) {
        player.chestPos(_v); _v.project(camera);
        if (_v.z < 1) {
          const x = (_v.x + 1) * 0.5 * W + 34, y = (1 - _v.y) * 0.5 * H + 22, st = player.charge.stage, k = player.charge.k;
          g.globalAlpha = 1;
          for (let i = 0; i < 3; i++) {
            const yy = y - (i + 1) * 19;
            g.fillStyle = 'rgba(20,10,22,.72)'; g.fillRect(x - 1.5, yy - 1.5, 15, 18);
            const fill = i < st ? 1 : i === st ? k : 0;
            if (fill > 0) { g.fillStyle = i < st ? '#ff5fd8' : '#ffb3ef'; g.fillRect(x, yy + 15 * (1 - fill), 12, 15 * fill); }
            g.strokeStyle = '#ffffff'; g.lineWidth = 1.5; g.strokeRect(x - 0.75, yy - 0.75, 13.5, 16.5);
          }
          g.lineWidth = 2.5; g.strokeStyle = 'rgba(20,20,20,.9)';
        }
      }
      g.globalAlpha = 1;
      for (let i = pops.length - 1; i >= 0; i--) {
        const p = pops[i];
        p.t += dt;
        if (p.t >= p.life) { pops.splice(i, 1); continue; }
        _v.set(p.x, p.y, p.z).project(camera);
        if (_v.z > 1) continue;
        const k = p.t / p.life;
        const x = (_v.x + 1) * 0.5 * W + p.dx * k, y = (1 - _v.y) * 0.5 * H - 26 * k - 8;
        const pop = k < 0.15 ? 1 + (0.15 - k) * 4 : 1;
        const size = Math.round(15 * p.scale * pop);
        g.globalAlpha = k > 0.7 ? (1 - k) / 0.3 : 1;
        g.font = `900 ${size}px system-ui,sans-serif`;
        g.lineWidth = Math.max(3, size / 4); g.strokeStyle = '#000';
        g.strokeText(p.text, x, y); g.fillStyle = p.color; g.fillText(p.text, x, y);
      }
      g.globalAlpha = 1;
      // пузыри заклинаний
      for (let i = chants.length - 1; i >= 0; i--) {
        const c = chants[i];
        c.t += dt;
        const f = c.f;
        if (c.t > 1.35 || f.dead) { c.d.remove(); chants.splice(i, 1); continue; }
        _v.set(f.pos.x, f.pos.y + 6.2 * f.scale, f.pos.z);
        const dist = _v.distanceTo(cp);
        _v.project(camera);
        if (_v.z > 1 || dist > 60) { c.d.style.opacity = 0; continue; }
        if (!c.w) { c.w = c.d.offsetWidth; c.h = c.d.offsetHeight; }
        const sc = f === player ? 1 : Math.max(0.6, Math.min(0.95, 20 / dist));
        let x = (_v.x + 1) * 0.5 * W + 26 * sc, y = (1 - _v.y) * 0.5 * H - c.h * sc - 6;
        x = Math.max(6, Math.min(W - c.w * sc - 6, x)); y = Math.max(44, Math.min(H - 140, y));
        const pop = c.t < 0.1 ? 1.2 - c.t * 2 : 1;
        c.d.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) scale(${(sc * pop).toFixed(3)}) rotate(${c.rot.toFixed(1)}deg)`;
        c.d.style.transformOrigin = '0 100%';
        c.d.style.opacity = c.t < 0.06 ? c.t / 0.06 : c.t > 1.1 ? Math.max(0, (1.35 - c.t) / 0.25) : 1;
      }
      // манга-панели
      for (let i = mangas.length - 1; i >= 0; i--) {
        const m = mangas[i];
        m.t += dt;
        const f = m.f;
        if (m.t > 2.3 || f.dead) { m.d.remove(); mangas.splice(i, 1); continue; }
        _v.set(f.pos.x, f.pos.y + 4.6 * f.scale, f.pos.z);
        const dist = _v.distanceTo(cp);
        _v.project(camera);
        if (_v.z > 1 || dist > 50) { m.d.style.opacity = 0; continue; }
        if (!m.w) { m.w = m.d.offsetWidth; m.h = m.d.offsetHeight; }
        const sc = f === player ? 1 : Math.max(0.55, Math.min(0.85, 18 / dist));
        const side = m.idx % 2 ? 1 : -1;
        let x = (_v.x + 1) * 0.5 * W + side * (Math.min(125, W * 0.14) + m.w * 0.1), y = (1 - _v.y) * 0.5 * H + (m.idx % 2 ? 26 : -34);
        x = Math.max(m.w * sc / 2 + 6, Math.min(W - m.w * sc / 2 - 6, x)); y = Math.max(m.h * sc / 2 + 46, Math.min(H - m.h * sc / 2 - 130, y));
        const pop = m.t < 0.12 ? 1.25 - m.t / 0.12 * 0.25 : 1;
        m.d.style.transform = `translate(${(x - m.w / 2).toFixed(1)}px,${(y - m.h / 2).toFixed(1)}px) scale(${(sc * pop).toFixed(3)}) rotate(${side * -2}deg)`;
        m.d.style.opacity = m.t < 0.08 ? m.t / 0.08 : m.t > 2.0 ? Math.max(0, (2.3 - m.t) / 0.3) : 1;
      }
      // стеклянные осколки
      if (shards) {
        shT += dt;
        const T = 0.6;
        shG.setTransform(DPR, 0, 0, DPR, 0, 0);
        shG.clearRect(0, 0, W, H);
        if (shT >= T) {
          shards = null; shCv.style.display = 'none';
          if (glCanvas) glCanvas.style.filter = '';
        } else {
          if (shT > 0.22 && glCanvas && glCanvas.style.filter) glCanvas.style.filter = '';
          const k = shT / T;
          shG.globalAlpha = k > 0.55 ? Math.max(0, (1 - k) / 0.45) : 1;
          shG.filter = shT < 0.22 ? 'saturate(0.25) contrast(1.1)' : 'none';
          // сначала трещины (0.07 с), потом осколки разлетаются
          const tt = Math.max(0, shT - 0.07);
          for (const sd of shards) {
            const ox = sd.vx * tt, oy = sd.vy * tt + 900 * tt * tt;
            const rot = sd.w * tt, sc = 1 + tt * 0.6;
            shG.save();
            shG.translate(sd.mx + ox, sd.my + oy); shG.rotate(rot); shG.scale(sc, sc); shG.translate(-sd.mx, -sd.my);
            shG.beginPath(); shG.moveTo(sd.pts[0][0], sd.pts[0][1]);
            for (let j = 1; j < sd.pts.length; j++) shG.lineTo(sd.pts[j][0], sd.pts[j][1]);
            shG.closePath();
            shG.save(); shG.clip();
            if (capOk) shG.drawImage(capCv, 0, 0, W, H); else { shG.fillStyle = 'rgba(210,235,255,.55)'; shG.fill(); }
            shG.fillStyle = `rgba(215,240,255,${(0.1 + Math.max(0, 0.25 - shT) * 1.2).toFixed(3)})`; shG.fill();
            shG.restore();
            shG.lineWidth = 3; shG.strokeStyle = 'rgba(20,30,40,.35)'; shG.stroke();
            shG.lineWidth = 1.6; shG.strokeStyle = 'rgba(255,255,255,.95)'; shG.stroke();
            shG.restore();
          }
          shG.filter = 'none'; shG.globalAlpha = 1;
        }
      }
    },

    // ---------- экраны ----------
    showSelect(cur, skin, onGo) {
      const scr = el('jh-scr');
      scr.innerHTML = `<h1>Jujutsu <em>Brosmens</em></h1><div class="sub">Арена FFA • выбери бойца</div><div class="jh-cards"></div><button class="jh-go">В бой!</button>`;
      const cards = scr.querySelector('.jh-cards');
      let sel = cur;
      const els = {};
      for (const id of CHAR_IDS) {
        const ch = CHARS[id], L = LOOKS[id];
        const c = document.createElement('div');
        c.className = 'jh-card' + (id === sel ? ' sel' : '');
        c.style.setProperty('--c', L.color);
        const cv = document.createElement('canvas'); cv.width = 320; cv.height = 200;
        drawPortrait(cv, id, skin);
        const tx = document.createElement('div'); tx.className = 'tx';
        tx.innerHTML = `<h3>${ch.name}</h3><div class="ru" style="color:${L.color}">${ch.ru}</div><p>${ch.desc}</p><div class="aw">⚡ ${ch.awakenDesc}</div>`;
        c.append(cv, tx);
        c.onclick = () => { sel = id; for (const k in els) els[k].classList.toggle('sel', k === id); };
        c.ondblclick = () => go();
        els[id] = c;
        cards.appendChild(c);
      }
      const go = () => { scr.remove(); onGo(sel); };
      scr.querySelector('.jh-go').onclick = go;
      scr.addEventListener('pointerdown', (e) => e.stopPropagation());
      return scr;
    },
    showDeath(killerName, cur, skin, onPick) {
      api.hideDeath();
      const d = el('jh-death');
      d.id = 'jh-death';
      d.innerHTML = `<h2>Ты погиб</h2><div class="k">${killerName ? 'Тебя победил ' + killerName.replace(/</g, '') : ''}</div><div class="t">Возрождение через 4… • можно сменить бойца</div><div class="jh-mini"></div>`;
      const mini = d.querySelector('.jh-mini');
      const els = {};
      for (const id of CHAR_IDS) {
        const c = document.createElement('div');
        c.style.setProperty('--c', LOOKS[id].color);
        if (id === cur) c.classList.add('sel');
        const cv = document.createElement('canvas'); cv.width = 192; cv.height = 120;
        drawPortrait(cv, id, skin);
        c.appendChild(cv);
        c.appendChild(document.createTextNode(CHARS[id].name));
        c.onclick = () => { for (const k in els) els[k].classList.toggle('sel', k === id); onPick(id); };
        els[id] = c;
        mini.appendChild(c);
      }
      mini.addEventListener('pointerdown', (e) => e.stopPropagation());
      return d;
    },
    setDeathTimer(s) { const t = document.querySelector('#jh-death .t'); if (t) t.textContent = `Возрождение через ${Math.max(1, Math.ceil(s))}… • можно сменить бойца`; },
    hideDeath() { document.getElementById('jh-death')?.remove(); },
    showResults(rows, me, coins, onAgain, onHome) {
      const scr = el('jh-scr jh-res');
      const esc = (s) => String(s).replace(/</g, '');
      const place = rows.indexOf(me) + 1;
      scr.innerHTML = `<h1>${place === 1 ? 'ПОБЕДА!' : 'Матч окончен'}</h1><div class="sub">Твоё место: ${place} • +${coins} монет</div>
        <table><tr><th>#</th><th>Игрок</th><th>Боец</th><th>Убийства</th><th>Смерти</th></tr>
        ${rows.map((f, i) => `<tr class="${f === me ? 'me' : ''}"><td>${i + 1}</td><td style="color:${f.color}">${esc(f.name)}</td><td style="color:${f.look.color}">${CHARS[f.charId].name}</td><td>${f.kills}</td><td>${f.deaths}</td></tr>`).join('')}</table>
        <div class="btns"><button class="gray">В меню</button><button>Ещё матч</button></div>`;
      const [home, again] = scr.querySelectorAll('button');
      home.onclick = onHome; again.onclick = () => { scr.remove(); onAgain(); };
      scr.addEventListener('pointerdown', (e) => e.stopPropagation());
    },
  };
  return api;
}

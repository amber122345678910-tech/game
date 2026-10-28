// Интерфейс боя: HP/пробуждение, таблица, кил-фид, цифры урона, ники над головами, экраны выбора/смерти/итогов.
import * as THREE from 'three';
import { CHARS, CHAR_IDS } from './skills.js';
import { drawPortrait, LOOKS } from './rig.js';

const CSS = `
.jh{position:fixed;z-index:30;pointer-events:none;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#fff}
#jh-over{position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:29;pointer-events:none}
.jh-bot{left:50%;bottom:5px;transform:translateX(-50%);width:min(246px,36vw);text-align:center}
.jh-hot{display:flex;gap:5px;margin-top:5px;pointer-events:auto}
.jh-slot{position:relative;flex:1;aspect-ratio:1;max-height:58px;border-radius:7px;background:rgba(18,19,26,.62);border:2px solid rgba(255,255,255,.55);overflow:hidden;touch-action:none;display:flex;align-items:center;justify-content:center;text-align:center}
.jh-slot.on{background:rgba(255,255,255,.3);transform:scale(.95)}
.jh-slot .n{position:absolute;left:4px;top:2px;font:900 10px system-ui;opacity:.75}
.jh-slot .l{position:relative;font:900 10.5px/1.05 system-ui;text-shadow:0 1px 2px #000;padding:0 2px}
.jh-slot .cd{position:absolute;left:0;right:0;bottom:0;background:rgba(0,0,0,.62);height:0}
.jh-slot .s{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font:900 17px system-ui;text-shadow:0 2px 2px #000}
.jh-slot .bar{position:absolute;left:0;right:0;bottom:0;height:3px}
.jh-name{font:900 12px system-ui;letter-spacing:.5px;text-shadow:0 1px 2px #000,0 0 6px rgba(0,0,0,.6);margin-bottom:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.jh-bar{position:relative;height:15px;background:rgba(0,0,0,.55);border:2px solid rgba(255,255,255,.85);border-radius:5px;overflow:hidden;margin-top:3px}
.jh-bar i{position:absolute;left:0;top:0;bottom:0;width:100%;transform-origin:left;transition:transform .12s}
.jh-bar b{position:absolute;inset:0;font:800 10.5px/11px system-ui;text-shadow:0 1px 2px #000;display:flex;align-items:center;justify-content:center}
.jh-hp i{background:linear-gradient(#5be35b,#2bb02b)}
.jh-hp .lag{background:#ff4040;transition:transform .5s .25s}
.jh-aw{height:11px}
.jh-aw b{font-size:9px}
.jh-aw.full{border-color:#fff;box-shadow:0 0 10px var(--c),0 0 3px var(--c)}
.jh-guard{height:4px;border-width:1px;margin-top:2px;opacity:0;transition:opacity .2s}
.jh-guard i{background:#8fd0ff}
.jh-sb{top:6px;right:6px;width:158px;background:rgba(10,12,20,.55);border-radius:8px;padding:4px 6px;font:700 10.5px/1.25 system-ui}
.jh-sb .hd{display:flex;opacity:.7;font-size:9.5px;border-bottom:1px solid rgba(255,255,255,.2);margin-bottom:2px;padding-bottom:1px}
.jh-sb .r{display:flex;gap:4px;white-space:nowrap}
.jh-sb .r span:first-child{flex:1;overflow:hidden;text-overflow:ellipsis}
.jh-sb .r span:nth-child(2),.jh-sb .hd span:nth-child(2){width:22px;text-align:right}
.jh-sb .r span:nth-child(3),.jh-sb .hd span:nth-child(3){width:20px;text-align:right;opacity:.6}
.jh-sb .hd span:first-child{flex:1}
.jh-sb .me{background:rgba(255,255,255,.14);border-radius:3px}
.jh-top{left:50%;top:5px;transform:translateX(-50%);text-align:center}
.jh-timer{font:900 15px system-ui;background:rgba(0,0,0,.45);border-radius:7px;padding:2px 10px;display:inline-block;text-shadow:0 1px 2px #000}
.jh-kf{margin-top:4px;display:flex;flex-direction:column;align-items:center;gap:2px}
.jh-kf div{font:800 11px system-ui;background:rgba(0,0,0,.45);border-radius:6px;padding:2px 8px;transition:opacity .6s;white-space:nowrap}
.jh-combo{right:14%;top:36%;text-align:center;opacity:0;transition:opacity .3s}
.jh-combo b{display:block;font:900 34px/1 system-ui;color:#ffd23f;text-shadow:0 3px 0 #000,0 0 10px rgba(255,160,0,.6)}
.jh-combo span{font:900 12px system-ui;letter-spacing:2px;text-shadow:0 2px 0 #000}
.jh-combo.pop b{animation:jhpop .18s}
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

  const bot = el('jh jh-bot', `<div class="jh-name"></div>
    <div class="jh-bar jh-hp"><i class="lag"></i><i class="hp"></i><b></b></div>
    <div class="jh-bar jh-aw"><i></i><b></b></div>
    <div class="jh-bar jh-guard"><i></i></div><div class="jh-hot"></div>`);
  const hot = bot.querySelector('.jh-hot');
  const slots = [];
  let skillPress = null, skillRelease = null;
  for (let i = 0; i < 4; i++) {
    const d = document.createElement('div'); d.className = 'jh-slot';
    d.innerHTML = `<i class="cd"></i><span class="n">${i + 1}</span><span class="l"></span><span class="s"></span><i class="bar"></i>`;
    const up = (e) => { e.preventDefault(); e.stopPropagation(); if (!d.classList.contains('on')) return; d.classList.remove('on'); skillRelease?.(i); };
    d.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); try { d.setPointerCapture(e.pointerId); } catch {} d.classList.add('on'); skillPress?.(i); });
    d.addEventListener('pointerup', up); d.addEventListener('pointercancel', up);
    hot.appendChild(d);
    slots.push({ d, cd: d.querySelector('.cd'), l: d.querySelector('.l'), s: d.querySelector('.s'), bar: d.querySelector('.bar'), key: '', sec: -1, frac: -1 });
  }
  const nameEl = bot.querySelector('.jh-name');
  const hpI = bot.querySelector('.jh-hp i.hp'), hpLag = bot.querySelector('.jh-hp .lag'), hpB = bot.querySelector('.jh-hp b');
  const awBar = bot.querySelector('.jh-aw'), awI = awBar.querySelector('i'), awB = awBar.querySelector('b');
  const guardBar = bot.querySelector('.jh-guard'), guardI = guardBar.querySelector('i');
  const sb = el('jh jh-sb');
  const top = el('jh jh-top', '<div class="jh-timer">4:00</div><div class="jh-kf"></div>');
  const timerEl = top.querySelector('.jh-timer'), kfEl = top.querySelector('.jh-kf');
  const comboEl = el('jh jh-combo', '<b>0</b><span>HITS</span>');
  const flashEl = el('jh jh-flash');
  const invEl = el('jh jh-inv');
  const vig = el('jh jh-vig');
  const tintEl = el('jh jh-tint');
  const callEl = el('jh jh-call', '<b></b><span></span>');

  const pops = [];
  let comboN = 0, comboT = 0, callT = 0, flashA = 0, flashDecay = 3, hurtA = 0;
  let lastSb = '';

  const api = {
    get W() { return W; }, get H() { return H; },
    setChar(f) {
      const ch = CHARS[f.charId];
      nameEl.textContent = `${ch.name}`;
      nameEl.style.color = LOOKS[f.charId].color;
      awBar.style.setProperty('--c', LOOKS[f.charId].color);
      awI.style.background = `linear-gradient(90deg, ${LOOKS[f.charId].color}, #ffffff)`;
    },
    onSkill(press, release) { skillPress = press; skillRelease = release; },
    // Хотбар навыков: defs[i] = {label, color}, cds[i] = {rem, max}
    setSkills(defs) {
      defs.forEach((sk, i) => {
        const S = slots[i];
        if (S.key === sk.id) return;
        S.key = sk.id;
        S.l.textContent = sk.label;
        const longest = Math.max(...sk.label.split(' ').map((w) => w.length));
        S.l.style.fontSize = Math.min(11.5, 54 / (longest * 0.62)).toFixed(1) + 'px';
        S.bar.style.background = sk.color;
        S.d.style.borderColor = sk.color + 'cc';
      });
    },
    setCooldowns(rems, maxs) {
      for (let i = 0; i < 4; i++) {
        const S = slots[i];
        const r = rems[i], f = r > 0 ? Math.min(1, r / maxs[i]) : 0;
        const fq = Math.round(f * 60);
        if (fq !== S.frac) { S.frac = fq; S.cd.style.height = (f * 100).toFixed(1) + '%'; }
        const sec = r > 0 ? Math.ceil(r) : 0;
        if (sec !== S.sec) { S.sec = sec; S.s.textContent = sec ? sec : ''; S.l.style.opacity = sec ? 0.12 : 1; }
      }
    },
    pop(pos, text, color = '#fff', scale = 1) {
      if (pops.length > 40) pops.shift();
      pops.push({ x: pos.x, y: pos.y, z: pos.z, text, color, scale, t: 0, life: text.length > 4 ? 1.1 : 0.8, dx: (Math.random() - 0.5) * 30 });
    },
    combo() {
      comboN++; comboT = 1.4;
      comboEl.querySelector('b').textContent = comboN;
      comboEl.classList.remove('pop'); void comboEl.offsetWidth; comboEl.classList.add('pop');
      if (comboN >= 2) comboEl.style.opacity = 1;
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
      d.innerHTML = killer ? `<span style="color:${kc}">${esc(killer)}</span> ⚔ <span style="color:${vc}">${esc(victim)}</span>` : `<span style="color:${vc}">${esc(victim)}</span> погиб`;
      kfEl.prepend(d);
      while (kfEl.children.length > 4) kfEl.lastChild.remove();
      setTimeout(() => (d.style.opacity = 0), 5000);
      setTimeout(() => d.remove(), 5700);
    },
    setTimer(sec) {
      const s = Math.max(0, Math.ceil(sec));
      timerEl.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      timerEl.style.color = s <= 20 ? '#ff6060' : '#fff';
    },
    showHUD(on) { for (const e of [bot, sb, top]) e.style.display = on ? '' : 'none'; },

    update(dt, camera, fighters, player) {
      // нижняя панель
      if (player) {
        const k = Math.max(0, player.hp) / player.maxHp;
        hpI.style.transform = `scaleX(${k})`; hpLag.style.transform = `scaleX(${k})`;
        hpI.style.background = k > 0.5 ? 'linear-gradient(#5be35b,#2bb02b)' : k > 0.25 ? 'linear-gradient(#ffd23f,#e0a800)' : 'linear-gradient(#ff5a5a,#d02020)';
        hpB.textContent = `${Math.ceil(Math.max(0, player.hp))} / ${player.maxHp}`;
        if (player.awakened > 0) {
          awI.style.transform = `scaleX(${player.awakened / player.ch.awaken.dur})`;
          awB.textContent = `ПРОБУЖДЕНИЕ ${Math.ceil(player.awakened)}с`;
          awBar.classList.add('full');
        } else {
          awI.style.transform = `scaleX(${player.meter / 100})`;
          const full = player.meter >= 100;
          awBar.classList.toggle('full', full);
          awB.textContent = full ? 'ПРОБУЖДЕНИЕ ГОТОВО [G]' : `Пробуждение ${Math.floor(player.meter)}%`;
        }
        guardBar.style.opacity = player.guard < 99 || player.blocking ? 1 : 0;
        guardI.style.transform = `scaleX(${player.guard / 100})`;
        const lowHp = !player.dead && k < 0.3 ? 0.35 + Math.sin(performance.now() / 180) * 0.15 : 0;
        vig.style.opacity = Math.max(hurtA, lowHp);
      }
      hurtA = Math.max(0, hurtA - dt * 1.8);
      if (comboT > 0) { comboT -= dt; if (comboT <= 0) { comboN = 0; comboEl.style.opacity = 0; } }
      if (callT > 0) { callT -= dt; if (callT <= 0) callEl.style.opacity = 0; }
      if (flashA > 0) { flashA = Math.max(0, flashA - dt * flashDecay); flashEl.style.opacity = flashA; }

      // таблица
      const rows = fighters.slice().sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
      let html = '<div class="hd"><span>Игроки</span><span>У</span><span>С</span></div>';
      const meIdx = rows.indexOf(player);
      const shown = rows.slice(0, 6);
      if (meIdx >= 6) shown[5] = player;
      for (const f of shown) {
        html += `<div class="r${f === player ? ' me' : ''}"><span style="color:${f.color}">${f.name.replace(/</g, '')}</span><span>${f.kills}</span><span>${f.deaths}</span></div>`;
      }
      if (html !== lastSb) { sb.innerHTML = html; lastSb = html; }

      // оверлей
      g.setTransform(DPR, 0, 0, DPR, 0, 0);
      g.clearRect(0, 0, W, H);
      g.textAlign = 'center';
      g.lineJoin = 'round';
      const cp = camera.position;
      for (const f of fighters) {
        if (f.dead || f === player) continue;
        _v.set(f.pos.x, f.pos.y + 6.9, f.pos.z);
        const dist = _v.distanceTo(cp);
        if (dist > 90) continue;
        _v.project(camera);
        if (_v.z > 1 || _v.x < -1.1 || _v.x > 1.1 || _v.y < -1.1 || _v.y > 1.1) continue;
        const x = (_v.x + 1) * 0.5 * W, y = (1 - _v.y) * 0.5 * H;
        const a = dist > 60 ? (90 - dist) / 30 : 1;
        g.globalAlpha = a;
        g.font = '800 11.5px system-ui,sans-serif';
        g.lineWidth = 3; g.strokeStyle = 'rgba(0,0,0,.85)';
        const nm = f.isClaude ? `${f.name} ✦` : f.name;
        g.strokeText(nm, x, y); g.fillStyle = f.color; g.fillText(nm, x, y);
        const bw = 46, bh = 5;
        g.fillStyle = 'rgba(0,0,0,.6)'; g.fillRect(x - bw / 2 - 1, y + 4, bw + 2, bh + 2);
        const k = Math.max(0, f.hp / f.maxHp);
        g.fillStyle = k > 0.5 ? '#4cd94c' : k > 0.25 ? '#ffc93c' : '#ff4a4a';
        g.fillRect(x - bw / 2, y + 5, bw * k, bh);
        if (f.awakened > 0) { g.fillStyle = f.look.color; g.fillRect(x - bw / 2, y + 11, bw * (f.awakened / f.ch.awaken.dur), 2); }
        if (f.stun > 0.5 && !f.rag) {
          const tt = performance.now() / 160;
          g.fillStyle = '#ffe14a';
          for (let i = 0; i < 3; i++) { const an = tt + (i * Math.PI * 2) / 3; g.font = '900 11px system-ui'; g.fillText('★', x + Math.cos(an) * 13, y - 12 + Math.sin(an) * 4); }
        }
        if (f.blocking) { g.font = '900 11px system-ui'; g.fillStyle = '#9fd8ff'; g.fillText('⛨', x + bw / 2 + 9, y + 10); }
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

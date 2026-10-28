// HUD (HP Судьи, таймер, команда, своя полоска HP/кармы/щита или уклонения/ульты), экран выбора и итоги.
import { ROLES, ROLE_IDS, MONSTER } from './data.js';
import { heartDataURL } from './fx.js';

const h = (tag, cls, html = '') => { const e = document.createElement(tag); if (cls) e.className = cls; if (html) e.innerHTML = html; return e; };
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const fmt = (s) => { s = Math.max(0, Math.ceil(s)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); };
const SKULL_ICON = '💀';

export function createHUD() {
  const root = h('div', 'jd-hud');
  root.innerHTML = `
  <div class="boss">
    <div class="brow"><span class="bname"></span><span class="timer">3:00</span></div>
    <div class="bar big"><i class="lag"></i><i class="fill"></i><b class="txt"></b></div>
    <div class="sub">
      <span class="lbl dl">УКЛОН. ×7</span><div class="bar dodge"><i class="fill"></i></div>
      <span class="lbl ul">УЛЬТА</span><div class="bar ult"><i class="fill"></i></div>
    </div>
  </div>
  <div class="team"></div>
  <div class="feed"></div>
  <div class="mepanel">
    <div class="mrow"><img class="mheart"><span class="mname"></span><span class="mlv">LV 1</span><span class="mlbl">HP</span><div class="bar mbar"><i class="kr"></i><i class="fill"></i><i class="sh"></i></div><span class="mkrl">KR</span><span class="mhp"></span></div>
    <div class="mrow2"></div>
  </div>
  <div class="alert"></div>
  <div class="spec"><span class="stxt"></span><button class="snext">Следующий ▶</button></div>`;
  document.body.appendChild(root);
  const q = (s) => root.querySelector(s);
  const E = {
    boss: q('.boss'), bname: q('.bname'), timer: q('.timer'), bfill: q('.big .fill'), blag: q('.big .lag'), btxt: q('.big .txt'),
    dfill: q('.dodge .fill'), dl: q('.lbl.dl'), dodge: q('.dodge'), ufill: q('.ult .fill'), ult: q('.ult'), ulbl: q('.lbl.ul'),
    team: q('.team'), feed: q('.feed'), me: q('.mepanel'), mheart: q('.mheart'), mname: q('.mname'), mhp: q('.mhp'),
    mfill: q('.mbar .fill'), mlbl: q('.mlbl'), mkrl: q('.mkrl'), mlv: q('.mlv'), mkr: q('.mbar .kr'), msh: q('.mbar .sh'), mrow2: q('.mrow2'), alert: q('.alert'),
    spec: q('.spec'), stxt: q('.stxt'), snext: q('.snext'),
  };
  E.snext.addEventListener('pointerdown', (e) => e.stopPropagation());
  const cache = new Map();
  const setW = (el, k) => { const v = Math.round(Math.max(0, Math.min(1, k)) * 1000) / 10; if (cache.get(el) !== v) { cache.set(el, v); el.style.width = v + '%'; } };
  const setT = (el, t) => { if (cache.get(el) !== t) { cache.set(el, t); el.textContent = t; } };
  const ccache = new Map();
  const setC = (el, c, on) => { const v = !!on; let o = ccache.get(el); if (!o) ccache.set(el, (o = {})); if (o[c] === v) return; o[c] = v; el.classList.toggle(c, v); };
  let rows = [], lag = 1, alertT = 0, mode = 'human';

  return {
    root,
    show(v) { root.style.display = v ? 'block' : 'none'; },
    setup(G) {
      cache.clear(); ccache.clear(); lag = 1;
      const m = G.monster;
      E.bname.innerHTML = `⚖ СУДЬЯ <small>${esc(m.name)}</small>`;
      E.team.innerHTML = ''; rows = [];
      for (const f of G.humans) {
        const r = h('div', 'trow' + (f.isPlayer ? ' me' : ''), `<img src="${heartDataURL(f.color, 20)}"><span>${esc(f.name)}</span><div class="bar tb"><i class="fill"></i></div>`);
        E.team.appendChild(r); rows.push({ r, f, fill: r.querySelector('.fill') });
      }
      E.feed.innerHTML = '';
      const p = G.player;
      mode = p.team;
      E.me.className = 'mepanel ' + mode;
      if (mode === 'human') {
        E.mheart.src = heartDataURL(p.color, 28); E.mheart.style.display = '';
        E.mname.textContent = p.name.toUpperCase().slice(0, 12); E.mlbl.textContent = 'HP'; E.mkrl.style.display = ''; E.mlv.style.display = '';
      } else { E.mheart.style.display = 'none'; E.mname.textContent = '⚖ СУДЬЯ'; E.mlbl.textContent = 'УКЛ'; E.mkrl.style.display = 'none'; E.mlv.style.display = 'none'; }
      E.spec.style.display = 'none'; E.me.style.visibility = 'visible';
      E.alert.style.opacity = 0;
    },
    update(G, dt) {
      const m = G.monster, p = G.player;
      if (!m) return;
      setT(E.timer, fmt(G.roundLeft));
      setC(E.timer, 'warn', G.roundLeft < 30);
      const k = m.hp / m.maxHp;
      lag = Math.max(k, lag - dt * 0.35);
      setW(E.bfill, k); setW(E.blag, lag);
      setT(E.btxt, `${Math.ceil(m.hp)} / ${m.maxHp}`);
      setW(E.dfill, m.dodge / m.dodgeMax);
      setT(E.dl, G.time < m.brokenUntil ? 'СЛОМАНО' : 'УКЛОН. ×' + Math.floor(m.dodge / 14));
      setC(E.dodge, 'broken', G.time < m.brokenUntil);
      setW(E.ufill, m.ult / 100);
      setC(E.ult, 'full', m.ult >= 100);
      setC(E.ulbl, 'full', m.ult >= 100);
      for (const r of rows) { setW(r.fill, r.f.hp / r.f.maxHp); setC(r.r, 'dead', r.f.dead); }
      if (mode === 'human') {
        setW(E.mkr, Math.min(p.maxHp, p.hp) / p.maxHp);
        E.mkr.style.opacity = p.karma > 0.5 ? 1 : 0;
        setW(E.mfill, Math.max(0, p.hp - p.karma) / p.maxHp);
        setW(E.msh, Math.min(1, p.shield / p.maxHp));
        setT(E.mhp, `${Math.ceil(p.hp)} / ${p.maxHp}`);
        setC(E.mkrl, 'on', p.karma > 0.5);
        setC(E.me, 'low', p.hp / p.maxHp < 0.3 && !p.dead);
        const t = [];
        if (p.shield > 0) t.push('🛡 ' + Math.ceil(p.shield));
        if (G.time < p.tauntUntil) t.push('😤 провокация');
        t.unshift(`${p.role.name} (${p.role.soul} душа)`);
        if (p.roleId === 'pat') t.push(p.reviveCharges > 0 ? '✨ воскрешение: 1' : '✨ использовано');
        setT(E.mrow2, t.join('  ·  '));
      } else {
        setW(E.mfill, m.dodge / m.dodgeMax); setW(E.mkr, 0); setW(E.msh, 0);
        setT(E.mhp, G.time < m.brokenUntil ? 'СЛОМАНО' : '×' + Math.floor(m.dodge / 14));
        setT(E.mrow2, m.ult >= 100 ? '☠ ПОСЛЕДНЯЯ АТАКА ГОТОВА — жми 4' : `HP ${Math.ceil(m.hp)} · ульта ${Math.floor(m.ult)}%`);
        setC(E.me, 'low', G.time < m.brokenUntil);
      }
      if (alertT > 0) { alertT -= dt; if (alertT <= 0) E.alert.style.opacity = 0; }
    },
    feed(html) {
      const d = h('div', 'fl', html); E.feed.prepend(d);
      while (E.feed.children.length > 4) E.feed.lastChild.remove();
      setTimeout(() => d.classList.add('old'), 5000);
    },
    alert(text, ms = 1400, cls = '') { E.alert.textContent = text; E.alert.className = 'alert ' + cls; E.alert.style.opacity = 1; alertT = ms / 1000; },
    spectate(on, name) { E.spec.style.display = on ? 'flex' : 'none'; E.me.style.visibility = on ? 'hidden' : 'visible'; if (on) E.stxt.textContent = '👁 Наблюдение: ' + name; },
    onSpecNext(fn) { E.snext.onclick = fn; },
  };
}

// ---------- экран выбора ----------
export function showSelect({ coins = 0, stats = {}, sel, onPlay }) {
  const ov = h('div', 'jd-select');
  const sides = [
    ['human', '🧍', 'Человек', 'Команда против Судьи'],
    ['monster', SKULL_ICON, 'Монстр', 'Ты — Судья'],
    ['random', '🎲', 'Случайно', 'Как повезёт'],
  ];
  ov.innerHTML = `
  <div class="sl">
    <div class="logo"><h1>СУДНЫЙ ДЕНЬ</h1><p>Стань сильнейшим!</p></div>
    <div class="sides">${sides.map(([id, ic, n, d]) => `<button class="side" data-side="${id}"><i>${ic}</i><b>${n}</b><small>${d}</small></button>`).join('')}</div>
    <div class="stat">🪙 ${coins} · Побед: ${stats.wins || 0} · Раундов: ${stats.games || 0}</div>
    <button class="play">В БОЙ ▶</button>
  </div>
  <div class="sr">
    <div class="rtitle">Роль человека</div>
    <div class="roles">${ROLE_IDS.map((id) => { const r = ROLES[id]; return `<button class="role" data-role="${id}" style="--c:${r.color}"><img src="${heartDataURL(r.color, 30)}"><b>${r.name}</b><small>❤ ${r.hp} · ${r.weapon}</small></button>`; }).join('')}</div>
    <div class="info"></div>
  </div>`;
  document.body.appendChild(ov);
  ov.addEventListener('pointerdown', (e) => e.stopPropagation());
  const info = ov.querySelector('.info');
  const render = () => {
    ov.querySelectorAll('.side').forEach((b) => b.classList.toggle('on', b.dataset.side === sel.side));
    ov.querySelectorAll('.role').forEach((b) => b.classList.toggle('on', b.dataset.role === sel.role));
    ov.querySelector('.sr').classList.toggle('dim', sel.side === 'monster');
    if (sel.side === 'monster') {
      info.innerHTML = `<div class="ih" style="color:${MONSTER.color}">⚖ Судья — ${MONSTER.desc}</div>
        <div class="ab"><i>🦴</i><b>M1</b> Удар костью (комбо)</div>
        ${MONSTER.skills.map((s, i) => `<div class="ab"><i>${s.icon}</i><b>${i + 1}</b> ${s.name} — ${s.desc}</div>`).join('')}
        <div class="ab"><i>👻</i><b>Q</b> Телепорт · <b>пассив</b> автоуклонение и карма</div>`;
    } else {
      const r = ROLES[sel.role];
      info.innerHTML = `<div class="ih" style="color:${r.color}">${r.name} (${r.soul} душа) — ${r.desc}</div>
        <div class="ab"><i>${r.m1.icon}</i><b>M1</b> ${r.m1.name}</div>
        ${r.skills.map((s, i) => `<div class="ab"><i>${s.icon}</i><b>${i + 1}</b> ${s.name} — ${s.desc} <em>${s.cd > 1 ? s.cd + 'с' : ''}</em></div>`).join('')}
        <div class="ab"><i>💨</i><b>Q</b> Рывок (неуязвимость) · <b>Space</b> прыжок</div>
        ${sel.side === 'random' ? '<div class="ab note">🎲 Сторона выпадет случайно (роль — эта)</div>' : ''}`;
    }
  };
  ov.querySelectorAll('.side').forEach((b) => (b.onclick = () => { sel.side = b.dataset.side; render(); }));
  ov.querySelectorAll('.role').forEach((b) => (b.onclick = () => { sel.role = b.dataset.role; if (sel.side === 'monster') sel.side = 'human'; render(); }));
  ov.querySelector('.play').onclick = () => { ov.remove(); onPlay(sel); };
  render();
  return ov;
}

// ---------- итоги ----------
export function showResults({ win, title, sub, rows, coins, onAgain, onChange, onHome }) {
  const ov = h('div', 'jd-results');
  ov.innerHTML = `<div class="card">
    <h1 class="${win ? 'win' : 'lose'}">${win ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ'}</h1>
    <div class="rt">${esc(title)}</div><div class="rs">${esc(sub)}</div>
    <table><tr><th></th><th>Игрок</th><th>Урон</th><th>Леч.</th><th>Убийств</th><th></th></tr>
    ${rows.map((r) => `<tr class="${r.me ? 'me' : ''}"><td>${r.icon}</td><td>${esc(r.name)}<small> ${esc(r.role)}</small></td><td>${r.dmg}</td><td>${r.heal || '–'}</td><td>${r.kills || '–'}</td><td>${r.status}</td></tr>`).join('')}
    </table>
    <div class="reward">+${coins} 🪙</div>
    <div class="btns"><button class="again">Ещё раунд</button><button class="change gray">Сменить роль</button><button class="home gray">В меню</button></div>
  </div>`;
  document.body.appendChild(ov);
  ov.addEventListener('pointerdown', (e) => e.stopPropagation());
  ov.querySelector('.again').onclick = () => { ov.remove(); onAgain(); };
  ov.querySelector('.change').onclick = () => { ov.remove(); onChange(); };
  ov.querySelector('.home').onclick = () => onHome();
  return ov;
}

// Общий интерфейс игр: базовые стили, меню как в роблоксе (☰: Игроки / Настройки / Управление,
// слайдеры графики, громкости и чувствительности, «Сбросить персонажа», «Выйти»), надписи, загрузка.
//
// const ui = initGameUI({ title, players: () => [{name, skin, team?, score?}], onReset: () => {...}, controlsHelp: 'html' });
// ui.toast('текст')  ui.banner('ПОБЕДА', 'подзаголовок', 3000)  ui.loading(false)  ui.goHome()  ui.modal(html, buttons)
// ui.setPlayers(fn)  ui.onReset(fn)  ui.onSettings(fn) — fn(settings) при изменении настроек  ui.openMenu()
// pixelRatio(), graphicsLevel() (1..10), shakeEnabled() — учитывают настройки из меню.
import { getProfile, getSettings, updateProfile } from './profile.js';
import { drawAvatar } from './avatar.js';
import { sfx } from './sfx.js';

const CSS = `
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;height:100%;overflow:hidden;background:#000;color:#fff;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;user-select:none;-webkit-user-select:none;touch-action:none;overscroll-behavior:none}
canvas{display:block}
.ui-top{position:fixed;top:6px;left:8px;z-index:60;display:flex;gap:6px}
.ui-top button{height:34px;min-width:36px;border:0;border-radius:9px;background:rgba(20,22,28,.6);color:#fff;font:800 16px system-ui;padding:0 9px;position:static}
.ui-top .ui-menu-btn{font-size:19px}
.ui-toast{position:fixed;left:50%;top:18%;transform:translateX(-50%);z-index:70;background:rgba(0,0,0,.65);padding:8px 16px;border-radius:10px;font-weight:800;font-size:15px;pointer-events:none;transition:opacity .4s;text-align:center}
.ui-banner{position:fixed;inset:0;z-index:69;display:flex;flex-direction:column;align-items:center;justify-content:center;pointer-events:none;opacity:0;transition:opacity .35s;text-shadow:0 3px 0 #000,0 0 12px rgba(0,0,0,.8)}
.ui-banner.show{opacity:1}
.ui-banner h1{margin:0;font-size:min(11vw,64px);font-weight:900;letter-spacing:1px}
.ui-banner p{margin:6px 0 0;font-size:min(5vw,22px);font-weight:800;opacity:.92}
.ui-load{position:fixed;inset:0;z-index:100;background:#111;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;font-weight:900;font-size:22px}
.ui-load i{width:44px;height:44px;border:5px solid #fff3;border-top-color:#fff;border-radius:50%;animation:uispin 1s linear infinite}
@keyframes uispin{to{transform:rotate(360deg)}}
.ui-panel{position:fixed;z-index:90;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center}
.ui-card{background:#fff;color:#111;border-radius:14px;padding:18px;max-width:min(92vw,520px);max-height:90vh;overflow:auto;box-shadow:0 10px 40px rgba(0,0,0,.5)}
.ui-card h2{margin:0 0 10px}
.ui-card button{border:0;border-radius:10px;padding:10px 16px;font:800 15px system-ui;background:#2f6fed;color:#fff;margin:4px}
.ui-card button.gray{background:#e3e5ea;color:#111}

.rm{position:fixed;inset:0;z-index:85;background:rgba(10,12,16,.62);backdrop-filter:blur(7px);-webkit-backdrop-filter:blur(7px);display:none;flex-direction:column;align-items:center;padding:10px 12px 12px;gap:8px}
.rm.open{display:flex}
.rm-tabs{display:flex;gap:6px;background:rgba(255,255,255,.08);padding:4px;border-radius:12px}
.rm-tabs button{border:0;background:none;color:#cfd3dc;font:800 14px system-ui;padding:8px 14px;border-radius:9px}
.rm-tabs button.on{background:#fff;color:#111}
.rm-body{flex:1;min-height:0;width:min(94vw,680px);overflow-y:auto;background:rgba(25,27,33,.92);border-radius:12px;padding:6px 14px;border:1px solid rgba(255,255,255,.08)}
.rm-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 0;border-bottom:1px solid rgba(255,255,255,.07);font-weight:700;font-size:14px}
.rm-row:last-child{border-bottom:0}
.rm-seg{display:flex;align-items:center;gap:6px}
.rm-seg button{width:30px;height:30px;border-radius:8px;border:0;background:rgba(255,255,255,.12);color:#fff;font:900 18px system-ui}
.rm-bars{display:flex;gap:3px}
.rm-bars i{width:16px;height:22px;border-radius:3px;background:rgba(255,255,255,.18);display:block}
.rm-bars i.on{background:#fff}
.rm-sw{width:52px;height:28px;border-radius:14px;border:0;background:rgba(255,255,255,.2);position:relative}
.rm-sw::after{content:'';position:absolute;top:3px;left:3px;width:22px;height:22px;border-radius:50%;background:#fff;transition:left .15s}
.rm-sw.on{background:#2f9e5b}.rm-sw.on::after{left:27px}
.rm-player{display:flex;align-items:center;gap:10px;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.07);font-weight:800}
.rm-player canvas{width:34px;height:34px;border-radius:8px;background:#2a2d35}
.rm-player small{margin-left:auto;color:#aab;font-weight:700}
.rm-help{font-size:14px;line-height:1.5;color:#dde;padding:8px 0}
.rm-help b{color:#fff}
.rm-foot{display:flex;gap:8px;flex-wrap:wrap;justify-content:center}
.rm-foot button{border:0;border-radius:10px;background:#fff;color:#111;font:800 14px system-ui;padding:10px 14px;display:flex;align-items:center;gap:8px}
.rm-foot button kbd{font:800 11px system-ui;border:1.5px solid #111;border-radius:5px;padding:1px 5px}
.rm-foot button.dark{background:rgba(255,255,255,.14);color:#fff}
.rm-foot button.dark kbd{border-color:#fff}
`;

export function graphicsLevel() {
  return Math.max(1, Math.min(10, getSettings().graphics ?? 6));
}

// Разрешение рендера по уровню графики (как «Качество графики» в роблоксе)
export function pixelRatio() {
  const dpr = window.devicePixelRatio || 1;
  const g = graphicsLevel();
  if (g <= 2) return Math.min(dpr, 0.6);
  if (g <= 4) return Math.min(dpr, 0.85);
  if (g <= 6) return Math.min(dpr, 1.15);
  if (g <= 8) return Math.min(dpr, 1.5);
  return Math.min(dpr, 2);
}

export function shakeEnabled() {
  return getSettings().shake !== false;
}

export function initGameUI({ title = '', home = '../../index.html', players = null, onReset = null, controlsHelp = '' } = {}) {
  if (!document.getElementById('ui-css')) {
    const st = document.createElement('style'); st.id = 'ui-css'; st.textContent = CSS; document.head.appendChild(st);
  }
  document.title = title;
  const top = document.createElement('div'); top.className = 'ui-top';
  const menuBtn = document.createElement('button'); menuBtn.className = 'ui-menu-btn'; menuBtn.textContent = '☰'; menuBtn.title = 'Меню';
  top.appendChild(menuBtn);
  document.body.appendChild(top);

  const toastEl = document.createElement('div'); toastEl.className = 'ui-toast'; toastEl.style.opacity = 0;
  const bannerEl = document.createElement('div'); bannerEl.className = 'ui-banner';
  const loadEl = document.createElement('div'); loadEl.className = 'ui-load';
  loadEl.innerHTML = `<i></i><div>${title}</div>`;
  document.body.append(toastEl, bannerEl, loadEl);

  let toastT = 0, bannerT = 0;
  let playersFn = players, resetFn = onReset;
  const settingsFns = [];
  const goHome = () => { location.href = home; };

  // ---------- меню ☰ ----------
  const menu = document.createElement('div'); menu.className = 'rm';
  menu.innerHTML = `<div class="rm-tabs"><button data-t="players">👥 Игроки</button><button data-t="settings">⚙ Настройки</button><button data-t="help">🎮 Управление</button></div>
    <div class="rm-body"></div>
    <div class="rm-foot"><button class="dark" data-a="reset"><kbd>R</kbd>Сбросить персонажа</button><button class="dark" data-a="leave"><kbd>L</kbd>Выйти</button><button data-a="resume"><kbd>Esc</kbd>Продолжить</button></div>`;
  document.body.appendChild(menu);
  const body = menu.querySelector('.rm-body');
  let tab = 'settings';
  menu.addEventListener('pointerdown', (e) => e.stopPropagation());
  menu.addEventListener('pointerup', (e) => e.stopPropagation());

  const setTab = (t) => {
    tab = t;
    menu.querySelectorAll('.rm-tabs button').forEach((b) => b.classList.toggle('on', b.dataset.t === t));
    body.innerHTML = '';
    if (t === 'players') renderPlayers(); else if (t === 'settings') renderSettings(); else renderHelp();
  };

  function renderPlayers() {
    const me = getProfile();
    const list = playersFn ? playersFn() : [{ name: me.name, skin: me.skin }];
    for (const p of list) {
      const row = document.createElement('div'); row.className = 'rm-player';
      const c = document.createElement('canvas'); c.width = c.height = 68;
      if (p.skin) drawAvatar(c, p.skin, { headOnly: true });
      const nm = document.createElement('span'); nm.textContent = p.name + (p.name === me.name ? ' (ты)' : '');
      if (p.team) nm.style.color = p.teamColor || '#fff';
      const sc = document.createElement('small'); sc.textContent = p.score ?? p.team ?? '';
      row.append(c, nm, sc); body.appendChild(row);
    }
  }

  function save(key, v) {
    updateProfile((p) => { p.settings[key] = v; });
    const s = getSettings();
    settingsFns.forEach((f) => f(s));
    window.dispatchEvent(new Event('resize'));
  }

  function segRow(label, key, min, max) {
    const row = document.createElement('div'); row.className = 'rm-row';
    row.innerHTML = `<span>${label}</span><div class="rm-seg"><button>−</button><div class="rm-bars"></div><button>+</button></div>`;
    const bars = row.querySelector('.rm-bars');
    for (let i = 1; i <= 10; i++) {
      const b = document.createElement('i');
      b.onclick = () => set(min + Math.round(((max - min) * i) / 10));
      bars.appendChild(b);
    }
    const draw = () => {
      const v = getSettings()[key];
      [...bars.children].forEach((b, i) => b.classList.toggle('on', i < Math.round(((v - min) / (max - min)) * 10)));
    };
    const set = (v) => { save(key, Math.max(min, Math.min(max, v))); draw(); sfx.play('ui', { vol: 0.5 }); };
    const [minus, plus] = row.querySelectorAll('.rm-seg > button');
    minus.onclick = () => set(getSettings()[key] - 1);
    plus.onclick = () => set(getSettings()[key] + 1);
    draw();
    body.appendChild(row);
  }

  function switchRow(label, key) {
    const row = document.createElement('div'); row.className = 'rm-row';
    row.innerHTML = `<span>${label}</span><button class="rm-sw"></button>`;
    const sw = row.querySelector('.rm-sw');
    const draw = () => sw.classList.toggle('on', getSettings()[key] !== false);
    sw.onclick = () => { save(key, getSettings()[key] === false); draw(); sfx.play('ui', { vol: 0.5 }); };
    draw();
    body.appendChild(row);
  }

  function renderSettings() {
    segRow('Качество графики', 'graphics', 1, 10);
    segRow('Громкость', 'volume', 0, 10);
    segRow('Чувствительность камеры', 'sensitivity', 1, 10);
    switchRow('Звук', 'sound');
    switchRow('Тряска камеры', 'shake');
  }

  function renderHelp() {
    const d = document.createElement('div'); d.className = 'rm-help';
    d.innerHTML = controlsHelp || '<b>Телефон:</b> левая половина экрана — джойстик, свайп справа — камера, кнопки справа — действия.<br><b>ПК:</b> WASD — ход, мышь — камера.';
    body.appendChild(d);
  }

  const openMenu = () => { menu.classList.add('open'); setTab(tab); sfx.play('ui', { vol: 0.6 }); };
  const closeMenu = () => menu.classList.remove('open');
  menuBtn.onclick = () => (menu.classList.contains('open') ? closeMenu() : openMenu());
  menu.querySelectorAll('.rm-tabs button').forEach((b) => (b.onclick = () => setTab(b.dataset.t)));

  const confirmLeave = () => api.modal('<h2>Выйти из игры?</h2><p>Ты вернёшься в меню «Бросменс».</p>', [{ label: 'Отмена', gray: true }, { label: 'Выйти', onClick: goHome }]);
  const confirmReset = () => api.modal('<h2>Сбросить персонажа?</h2>', [{ label: 'Нет', gray: true }, { label: 'Да', onClick: () => { closeMenu(); resetFn?.(); } }]);
  menu.querySelector('[data-a=resume]').onclick = closeMenu;
  menu.querySelector('[data-a=leave]').onclick = confirmLeave;
  menu.querySelector('[data-a=reset]').onclick = confirmReset;
  const resetBtn = menu.querySelector('[data-a=reset]');
  resetBtn.style.display = resetFn ? '' : 'none';

  addEventListener('keydown', (e) => {
    if (e.target.closest?.('input,textarea')) return;
    if (e.code === 'Escape') { menu.classList.contains('open') ? closeMenu() : openMenu(); }
    else if (menu.classList.contains('open') && e.code === 'KeyL') confirmLeave();
    else if (menu.classList.contains('open') && e.code === 'KeyR' && resetFn) confirmReset();
  });

  const api = {
    top,
    goHome,
    openMenu,
    closeMenu,
    menuOpen: () => menu.classList.contains('open'),
    setPlayers(fn) { playersFn = fn; },
    onReset(fn) { resetFn = fn; resetBtn.style.display = fn ? '' : 'none'; },
    onSettings(fn) { settingsFns.push(fn); },
    addTopButton(label, onClick) {
      const b = document.createElement('button'); b.innerHTML = label; b.onclick = onClick; top.appendChild(b); return b;
    },
    toast(msg, ms = 1800) {
      toastEl.textContent = msg; toastEl.style.opacity = 1;
      clearTimeout(toastT); toastT = setTimeout(() => (toastEl.style.opacity = 0), ms);
    },
    banner(big, sub = '', ms = 2500, color = '#fff') {
      bannerEl.innerHTML = `<h1 style="color:${color}">${big}</h1>${sub ? `<p>${sub}</p>` : ''}`;
      bannerEl.classList.add('show');
      clearTimeout(bannerT); if (ms) bannerT = setTimeout(() => bannerEl.classList.remove('show'), ms);
    },
    hideBanner() { bannerEl.classList.remove('show'); },
    loading(on, text) { loadEl.style.display = on ? 'flex' : 'none'; if (text) loadEl.lastChild.textContent = text; },
    // Модальное окно: buttons = [{label, gray?, onClick}] — закрывается после нажатия
    modal(html, buttons = [{ label: 'OK' }]) {
      const p = document.createElement('div'); p.className = 'ui-panel';
      const c = document.createElement('div'); c.className = 'ui-card'; c.innerHTML = html;
      const row = document.createElement('div'); row.style.textAlign = 'right';
      for (const b of buttons) {
        const el = document.createElement('button'); el.textContent = b.label; if (b.gray) el.className = 'gray';
        el.onclick = () => { p.remove(); b.onClick?.(); };
        row.appendChild(el);
      }
      c.appendChild(row); p.appendChild(c); document.body.appendChild(p);
      p.addEventListener('pointerdown', (e) => e.stopPropagation());
      return p;
    },
  };
  return api;
}

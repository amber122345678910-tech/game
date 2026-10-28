// Общий интерфейс игр: базовые стили, кнопка «домой», всплывающие надписи, экран загрузки.
// const ui = initGameUI({ title: 'JJ Bros' });  ui.toast('текст')  ui.banner('ПОБЕДА', 'подзаголовок', 3000)
// ui.loading(false) — убрать экран загрузки.  ui.goHome() — вернуться в меню.
const CSS = `
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;height:100%;overflow:hidden;background:#000;color:#fff;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;user-select:none;-webkit-user-select:none;touch-action:none;overscroll-behavior:none}
canvas{display:block}
.ui-top{position:fixed;top:6px;left:48px;z-index:60;display:flex;gap:6px}
.ui-top button{height:32px;min-width:34px;border:0;border-radius:8px;background:rgba(0,0,0,.5);color:#fff;font:800 15px system-ui;padding:0 9px}
.ui-toast{position:fixed;left:50%;top:18%;transform:translateX(-50%);z-index:70;background:rgba(0,0,0,.65);padding:8px 16px;border-radius:10px;font-weight:800;font-size:15px;pointer-events:none;transition:opacity .4s;text-align:center}
.ui-banner{position:fixed;inset:0;z-index:69;display:flex;flex-direction:column;align-items:center;justify-content:center;pointer-events:none;opacity:0;transition:opacity .35s;text-shadow:0 3px 0 #000,0 0 12px rgba(0,0,0,.8)}
.ui-banner.show{opacity:1}
.ui-banner h1{margin:0;font-size:min(11vw,64px);font-weight:900;letter-spacing:1px}
.ui-banner p{margin:6px 0 0;font-size:min(5vw,22px);font-weight:800;opacity:.92}
.ui-load{position:fixed;inset:0;z-index:100;background:#111;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;font-weight:900;font-size:22px}
.ui-load i{width:44px;height:44px;border:5px solid #fff3;border-top-color:#fff;border-radius:50%;animation:uispin 1s linear infinite}
@keyframes uispin{to{transform:rotate(360deg)}}
.ui-panel{position:fixed;z-index:80;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center}
.ui-card{background:#fff;color:#111;border-radius:14px;padding:18px;max-width:min(92vw,520px);max-height:90vh;overflow:auto;box-shadow:0 10px 40px rgba(0,0,0,.5)}
.ui-card h2{margin:0 0 10px}
.ui-card button{border:0;border-radius:10px;padding:10px 16px;font:800 15px system-ui;background:#2f6fed;color:#fff;margin:4px}
.ui-card button.gray{background:#e3e5ea;color:#111}
`;

export function initGameUI({ title = '', home = '../../index.html' } = {}) {
  if (!document.getElementById('ui-css')) {
    const st = document.createElement('style'); st.id = 'ui-css'; st.textContent = CSS; document.head.appendChild(st);
  }
  document.title = title;
  const top = document.createElement('div'); top.className = 'ui-top';
  const homeBtn = document.createElement('button'); homeBtn.textContent = '⌂'; homeBtn.title = 'В меню';
  top.appendChild(homeBtn);
  document.body.appendChild(top);

  const toastEl = document.createElement('div'); toastEl.className = 'ui-toast'; toastEl.style.opacity = 0;
  const bannerEl = document.createElement('div'); bannerEl.className = 'ui-banner';
  const loadEl = document.createElement('div'); loadEl.className = 'ui-load';
  loadEl.innerHTML = `<i></i><div>${title}</div>`;
  document.body.append(toastEl, bannerEl, loadEl);

  let toastT = 0, bannerT = 0;
  const goHome = () => { location.href = home; };

  const api = {
    top,
    goHome,
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
  homeBtn.onclick = () => api.modal('<h2>Выйти в меню?</h2>', [{ label: 'Остаться', gray: true }, { label: 'Выйти', onClick: goHome }]);
  return api;
}

// Размер рендера с учётом качества (для телефонов не больше 1.5x)
export function pixelRatio() {
  return Math.min(window.devicePixelRatio || 1, 1.5);
}

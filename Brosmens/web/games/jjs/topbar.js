// Верхняя панель как в JJS: после общих ☰ и 💬 — «таблетки» [👤 Персонажи ▾] [🏪 $N] [🕺],
// выпадающий список бойцов и колесо эмоций (тёмное кольцо #3A3A3A, 4 слота на страницу, «‹ 1/2 ›»).
const CSS = `
.ui-top .jt-pill{height:34px;min-width:34px;border:0;border-radius:17px;background:rgba(20,20,20,.6);color:#fff;font:700 13px/1 "Builder Sans","Gotham SSm","Montserrat",system-ui,sans-serif;padding:0 12px;display:flex;align-items:center;justify-content:center;gap:6px;letter-spacing:.2px;white-space:nowrap;cursor:pointer}
.ui-top .jt-pill.ico{padding:0;width:34px}
.ui-top .jt-pill.on{background:rgba(70,70,70,.82)}
.ui-top .jt-pill svg{width:17px;height:17px;flex:none;display:block}
.ui-top .jt-pill .car{width:9px;height:9px;opacity:.8}
.jt-wrap{position:relative;display:flex}
.jt-dd{position:absolute;left:0;top:40px;width:224px;background:rgba(20,20,20,.84);border-radius:10px;padding:5px;display:none;flex-direction:column;gap:2px;box-shadow:0 6px 18px rgba(0,0,0,.35);z-index:62}
.jt-dd.open{display:flex}
.jt-dd .hd{font:800 10px/1 system-ui,sans-serif;color:#bdbdbd;letter-spacing:.4px;text-transform:uppercase;padding:5px 7px 4px}
.ui-top .jt-dd button{height:36px;min-width:0;width:100%;border:0;border-radius:7px;background:transparent;display:flex;align-items:center;gap:8px;text-align:left;font:700 13px/1.1 "Builder Sans","Gotham SSm",system-ui,sans-serif;color:#fff;padding:0 8px;cursor:pointer}
.ui-top .jt-dd button:active,.ui-top .jt-dd button.cur{background:rgba(255,255,255,.14)}
.jt-dd button i{width:9px;height:9px;border-radius:50%;background:var(--c);box-shadow:0 0 6px var(--c);flex:none}
.jt-dd button span{display:flex;flex-direction:column;gap:2px;flex:1;min-width:0}
.jt-dd button small{font:600 10.5px system-ui,sans-serif;color:#a9a9a9}
.jt-dd button b{font:900 12px system-ui;color:#fff;opacity:0}
.jt-dd button.cur b{opacity:1}
.jt-pop{position:fixed;z-index:61;font:900 15px/1 system-ui,sans-serif;color:#47e04a;pointer-events:none;text-shadow:1px 1px 0 #0b2a0b,-1px -1px 0 #0b2a0b,1px -1px 0 #0b2a0b,-1px 1px 0 #0b2a0b;transition:transform .9s ease-out,opacity .9s ease-in}
.jt-ew{position:fixed;inset:0;z-index:57;display:none;pointer-events:auto;touch-action:none}
.jt-ew.open{display:block}
.jt-ring{position:absolute;left:50%;top:46%;width:236px;height:236px;margin:-118px 0 0 -118px;border-radius:50%;box-sizing:border-box;border:56px solid rgba(58,58,58,.93);box-shadow:0 0 0 2px rgba(0,0,0,.35),inset 0 0 0 2px rgba(0,0,0,.35)}
.jt-slot{position:absolute;width:60px;height:60px;margin:-30px 0 0 -30px;border-radius:50%;background:radial-gradient(circle at 50% 38%,#4a4a4a,#262626);border:2px solid #6a6a6a;display:flex;align-items:center;justify-content:center;font:30px/1 system-ui,"Noto Color Emoji",sans-serif;cursor:pointer;box-sizing:border-box}
.jt-slot:active{transform:scale(.94);border-color:#fff}
.jt-slot em{position:absolute;top:60px;left:50%;transform:translateX(-50%);font:400 14px/1 "JJSHand","Comic Sans MS","Chalkboard SE",system-ui,sans-serif;font-style:normal;color:#fff;white-space:nowrap;text-shadow:1.5px 0 0 #111,-1.5px 0 0 #111,0 1.5px 0 #111,0 -1.5px 0 #111}
.jt-pg{position:absolute;left:50%;top:46%;transform:translate(-50%,-50%);display:flex;align-items:center;gap:4px;font:400 17px/1 "JJSHand","Comic Sans MS","Chalkboard SE",system-ui,sans-serif;color:#fff;text-shadow:1px 1px 0 #000}
.jt-pg button{width:26px;height:30px;border:0;border-radius:6px;background:rgba(255,255,255,.08);color:#fff;font:900 17px system-ui;padding:0;cursor:pointer}
.jt-hint{position:absolute;left:50%;top:max(46px,calc(46% - 146px));transform:translateX(-50%);font:700 11px system-ui,sans-serif;color:#e8e8e8;background:rgba(20,20,20,.6);border-radius:12px;padding:5px 11px;white-space:nowrap}
`;
const ICON = {
  person: '<svg viewBox="0 0 20 20"><circle cx="10" cy="6.2" r="3.6" fill="#fff"/><path d="M3 18c0-4.2 3.2-6.6 7-6.6s7 2.4 7 6.6z" fill="#fff"/></svg>',
  shop: '<svg viewBox="0 0 20 20"><path d="M2.5 3h15l1 4.2c0 1.4-1.1 2.3-2.4 2.3-1.2 0-2.2-.9-2.3-2.1-.1 1.2-1.1 2.1-2.4 2.1S9.1 8.6 9 7.4C8.9 8.6 7.9 9.5 6.6 9.5S4.3 8.6 4.2 7.4c-.1 1.2-1 2.1-2.2 2.1C.9 9.5.5 8.4.5 7.6z" fill="#fff"/><path d="M3.2 10.6V17h13.6v-6.4" fill="none" stroke="#fff" stroke-width="1.8"/><rect x="8" y="12.4" width="4" height="4.6" fill="#fff"/></svg>',
  dance: '<svg viewBox="0 0 20 20"><circle cx="11.5" cy="3.2" r="2.1" fill="#fff"/><path d="M11 6.2 9.4 11.4M9.4 11.4l3.4 2.4-.8 4.6M9.4 11.4 6.6 15l-3 .6M10.6 7.2l4.6-3.6M10.6 7.4 6 8.4 4 5.8" stroke="#fff" stroke-width="2.1" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  caret: '<svg class="car" viewBox="0 0 10 10"><path d="M1.5 3.2 5 6.8l3.5-3.6" stroke="#fff" stroke-width="1.8" fill="none" stroke-linecap="round"/></svg>',
};

export function createTopBar({ ui, chars, emotes, onChar, onEmote }) {
  const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
  const top = ui.top;
  const mk = (tag, cls, html = '', parent = null) => { const e = document.createElement(tag); e.className = cls; e.innerHTML = html; if (parent) parent.appendChild(e); return e; };

  // [👤 Персонажи ▾] + выпадающий список
  const wrap = mk('div', 'jt-wrap', '', top);
  const charBtn = mk('button', 'jt-pill', `${ICON.person}<span>Персонажи</span>${ICON.caret}`, wrap);
  const dd = mk('div', 'jt-dd', '<div class="hd">Выбор бойца</div>', wrap);
  const rows = {};
  for (const c of chars) {
    const b = mk('button', '', `<i style="--c:${c.color}"></i><span>${c.name}<small>${c.ru}</small></span><b>✓</b>`, dd);
    b.onclick = (e) => { e.stopPropagation(); close(); onChar(c.id); };
    rows[c.id] = b;
  }
  // [🏪 $N]
  const cashBtn = mk('button', 'jt-pill', `${ICON.shop}<span>$0</span>`, top);
  const cashTxt = cashBtn.querySelector('span');
  // [🕺]
  const emoBtn = mk('button', 'jt-pill ico', ICON.dance, top);

  // колесо эмоций
  const ew = mk('div', 'jt-ew', '', document.body);
  mk('div', 'jt-hint', 'Выбери эмоцию • прыжок, M1, блок или удар отменяют', ew);
  const ring = mk('div', 'jt-ring', '', ew);
  const slots = [];
  const POS = [[0, -90], [90, 0], [0, 90], [-90, 0]];
  for (let i = 0; i < 4; i++) {
    const s = mk('div', 'jt-slot', '', ew);
    s.style.left = `calc(50% + ${POS[i][0]}px)`; s.style.top = `calc(46% + ${POS[i][1]}px)`;
    s.addEventListener('pointerdown', (e) => { e.stopPropagation(); const d = s._def; if (d) { closeWheel(); onEmote(d); } });
    slots.push(s);
  }
  const pg = mk('div', 'jt-pg', '<button>‹</button><span></span><button>›</button>', ew);
  const [prevB, nextB] = pg.querySelectorAll('button');
  const pgTxt = pg.querySelector('span');
  const pages = Math.max(1, Math.ceil(emotes.length / 4));
  let page = 0;
  const drawPage = () => {
    for (let i = 0; i < 4; i++) {
      const d = emotes[page * 4 + i];
      slots[i]._def = d || null;
      slots[i].innerHTML = d ? `${d.icon}<em>${d.name}</em>` : '';
      slots[i].style.visibility = d ? '' : 'hidden';
    }
    pgTxt.textContent = `${page + 1}/${pages}`;
  };
  prevB.addEventListener('pointerdown', (e) => { e.stopPropagation(); page = (page + pages - 1) % pages; drawPage(); });
  nextB.addEventListener('pointerdown', (e) => { e.stopPropagation(); page = (page + 1) % pages; drawPage(); });
  ring.addEventListener('pointerdown', (e) => e.stopPropagation());
  ew.addEventListener('pointerdown', (e) => { e.stopPropagation(); closeWheel(); });
  drawPage();

  const close = () => { dd.classList.remove('open'); charBtn.classList.remove('on'); };
  const closeWheel = () => { ew.classList.remove('open'); emoBtn.classList.remove('on'); };
  const openWheel = () => { close(); drawPage(); ew.classList.add('open'); emoBtn.classList.add('on'); };
  charBtn.onclick = (e) => { e.stopPropagation(); closeWheel(); const o = !dd.classList.contains('open'); dd.classList.toggle('open', o); charBtn.classList.toggle('on', o); };
  emoBtn.onclick = (e) => { e.stopPropagation(); if (ew.classList.contains('open')) closeWheel(); else openWheel(); };
  cashBtn.onclick = (e) => { e.stopPropagation(); ui.toast(`Монеты: ${cashTxt.textContent} • +$5 за каждое убийство`, 1600); };
  // тап мимо выпадающего списка закрывает его
  addEventListener('pointerdown', (e) => { if (dd.classList.contains('open') && !wrap.contains(e.target)) close(); }, true);

  const items = [wrap, cashBtn, emoBtn];
  return {
    setVisible(v) { for (const e of items) e.style.display = v ? '' : 'none'; if (!v) { close(); closeWheel(); } },
    setChar(id) { for (const k in rows) rows[k].classList.toggle('cur', k === id); },
    setCoins(n) { cashTxt.textContent = '$' + Math.max(0, Math.floor(n)); },
    coinPop(text) {
      const r = cashBtn.getBoundingClientRect();
      const d = mk('div', 'jt-pop', text, document.body);
      d.style.left = (r.left + 10) + 'px'; d.style.top = (r.bottom + 2) + 'px';
      requestAnimationFrame(() => requestAnimationFrame(() => { d.style.transform = 'translateY(16px)'; d.style.opacity = 0; }));
      setTimeout(() => d.remove(), 1000);
      cashBtn.animate?.([{ transform: 'scale(1.12)' }, { transform: 'scale(1)' }], { duration: 260 });
    },
    toggleWheel() { if (ew.classList.contains('open')) closeWheel(); else openWheel(); },
    isOpen: () => ew.classList.contains('open') || dd.classList.contains('open'),
    closeAll() { close(); closeWheel(); },
  };
}

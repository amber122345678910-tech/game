// Интерфейс лобби (F2/F3/U6/U7/U12): «Раунд через 27» сверху по центру, доска очереди Судьи справа
// (выбор стороны «Человек / Судья / Случайно»), снизу «Магазин душ» и «Играть сейчас»,
// слева — вкладка «<» с панелью статистики (#343434: Победы / Убийства / Монеты, кнопки #1A1A1A
// «Наблюдать», «Низкая графика», «Не АФК»), Магазин душ — чёрное окно с белой сеткой 2 px,
// «Выбор персонажа» — чёрная комната со светящимися белыми силуэтами монстров (+ «Случайный монстр»).
import { ROLES, ROLE_IDS, POTIONS, POTION_IDS, MONSTERS, MONSTER_IDS } from './data.js';
import { drawHeart } from './fx.js';
import { pixCanvas, PIX } from './pixfont.js';
import { pixLabel } from './hud.js';

const el = (tag, cls, parent, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html) e.innerHTML = html; if (parent) parent.appendChild(e); return e; };
const SOULS = ['#F80000', '#F86800', '#F0F800', '#00F820', '#00F8F8', '#0010F8', '#B000F8', '#F840E0'];
const K = () => Math.max(0.85, Math.min(1.5, innerHeight / 412));

function heartCanvas(color, size) {
  const dpr = Math.min(3, devicePixelRatio || 1), c = document.createElement('canvas');
  c.width = c.height = Math.round(size * dpr); c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'); g.imageSmoothingEnabled = false;
  drawHeart(g, c.width / 2, c.height / 2 + 1, Math.floor(c.width / 10), color);
  return c;
}
// пиксельная склянка цвета зелья
const FLASK = ['..##..', '..##..', '.####.', '#XXXX#', '#XXXX#', '#XXXX#', '.####.'];
function flaskCanvas(color, size) {
  const dpr = Math.min(3, devicePixelRatio || 1), c = document.createElement('canvas');
  c.width = c.height = Math.round(size * dpr); c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'), px = Math.floor(c.width / 8), x0 = (c.width - px * 6) / 2, y0 = (c.height - px * 7) / 2;
  FLASK.forEach((row, r) => [...row].forEach((ch, k) => { if (ch === '.') return; g.fillStyle = ch === '#' ? '#202020' : color; g.fillRect(x0 + k * px, y0 + r * px, px, px); }));
  g.fillStyle = 'rgba(255,255,255,.7)'; g.fillRect(x0 + px, y0 + 3 * px, px, px);
  return c;
}
function rainbow(text, px) {
  const wrap = el('span', 'rb');
  let k = 0;
  for (const ch of text) {
    if (ch === ' ') { el('i', 'sp', wrap); continue; }
    wrap.appendChild(pixCanvas(ch, px, { fill: SOULS[k++ % SOULS.length], outline: '#000', outlineW: Math.max(1, px * 0.5) }));
  }
  return wrap;
}

// светящийся белый силуэт монстра (большой круглый череп, толстовка, шорты, тапки) или «?» для случайного
function silhouette(size, random = false) {
  const dpr = Math.min(3, devicePixelRatio || 1), c = document.createElement('canvas');
  c.width = c.height = Math.round(size * dpr); c.style.width = c.style.height = size + 'px';
  const g = c.getContext('2d'), S = c.width;
  g.shadowColor = '#ffffff'; g.shadowBlur = S * 0.08; g.fillStyle = '#ffffff';
  if (random) {
    g.font = `900 ${Math.round(S * 0.62)}px system-ui,sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText('?', S / 2, S * 0.54);
    return c;
  }
  g.beginPath(); g.ellipse(S * 0.5, S * 0.27, S * 0.2, S * 0.18, 0, 0, 7); g.fill();            // череп
  g.beginPath(); g.ellipse(S * 0.5, S * 0.56, S * 0.25, S * 0.17, 0, 0, 7); g.fill();          // толстовка
  g.fillRect(S * 0.25, S * 0.46, S * 0.08, S * 0.22); g.fillRect(S * 0.67, S * 0.46, S * 0.08, S * 0.22); // рукава
  g.fillRect(S * 0.33, S * 0.66, S * 0.34, S * 0.1);                                             // шорты
  g.fillRect(S * 0.37, S * 0.75, S * 0.07, S * 0.1); g.fillRect(S * 0.56, S * 0.75, S * 0.07, S * 0.1); // ноги
  g.beginPath(); g.ellipse(S * 0.39, S * 0.87, S * 0.07, S * 0.035, 0, 0, 7); g.ellipse(S * 0.61, S * 0.87, S * 0.07, S * 0.035, 0, 0, 7); g.fill();
  g.shadowBlur = 0; g.fillStyle = '#000';
  g.beginPath(); g.ellipse(S * 0.43, S * 0.26, S * 0.035, S * 0.04, 0, 0, 7); g.ellipse(S * 0.57, S * 0.26, S * 0.035, S * 0.04, 0, 0, 7); g.fill();
  g.fillStyle = '#3fe0ff'; g.beginPath(); g.arc(S * 0.57, S * 0.26, S * 0.014, 0, 7); g.fill();
  return c;
}

export function createLobbyUI({ onPlay, onSide, onSoul, onPotion, onFlag, onChar }) {
  const root = el('div', 'jd-lobby', document.body);
  root.style.display = 'none';
  root.addEventListener('pointerdown', (e) => { if (e.target !== root) e.stopPropagation(); });

  // ---------- сверху: отсчёт ----------
  const top = el('div', 'lb-top', root);
  const cd = pixLabel('lb-cd'), next = pixLabel('lb-next');
  top.append(cd, next);

  // ---------- справа: очередь Судьи ----------
  const qp = el('div', 'lb-queue', root);
  const qh = el('div', 'qh', qp); const qrows = el('div', 'qrows', qp);
  const sides = el('div', 'lb-sides', qp);
  const SIDES = [['human', 'Человек'], ['monster', 'Судья'], ['random', 'Случайно']];
  const sideBtns = SIDES.map(([id, nm]) => { const b = el('button', '', sides, nm); b.dataset.side = id; b.onclick = () => onSide?.(id); return b; });
  const hint = el('div', 'qhint', qp);

  // ---------- снизу: магазин и «играть» ----------
  const bot = el('div', 'lb-bottom', root);
  const shopB = el('button', 'lb-shop', bot);
  const shopHeart = el('span', 'sh-h', shopB); const shopTxt = el('span', 'sh-t', shopB); const shopSub = el('small', 'sh-s', shopB);
  const playB = el('button', 'lb-play', bot);
  const charB = el('button', 'lb-char', bot);
  const charIco = el('span', 'ch-i', charB); const charTxt = el('span', 'ch-t', charB);
  shopB.onclick = () => openShop(true);
  playB.onclick = () => onPlay?.();
  charB.onclick = () => openChars(true);

  // ---------- слева: вкладка «<» и панель статистики ----------
  const stats = el('div', 'lb-stats', root);
  const sp = el('div', 'sp', stats);
  const tab = el('button', 'tab', stats);
  const tabL = pixLabel('tl'); tab.appendChild(tabL);
  const rows = {};
  for (const [id, nm] of [['wins', 'Победы:'], ['kills', 'Убийства:'], ['coins', 'Монеты:']]) {
    const r = el('div', 'st', sp); r.appendChild(pixCanvas(nm, 1.7 * K(), PIX.panel));
    const v = pixLabel('sv'); r.appendChild(v); rows[id] = { v, val: 0, shown: -1 };
  }
  const bSpec = el('button', 'sb tall', sp), bLow = el('button', 'sb', sp), bAfk = el('button', 'sb', sp);
  const lSpec = pixLabel('bl'), lLow = pixLabel('bl'), lAfk = pixLabel('bl');
  bSpec.appendChild(lSpec); bLow.appendChild(lLow); bAfk.appendChild(lAfk);
  bSpec.onclick = () => onFlag?.('spectate'); bLow.onclick = () => onFlag?.('lowGfx'); bAfk.onclick = () => onFlag?.('afk');
  let statsOpen = false, autoClose = 0;
  const setStatsOpen = (v) => { statsOpen = v; stats.classList.toggle('open', v); tabL.set(v ? '<' : '>', 2.6 * K(), PIX.panel); autoClose = 0; };
  tab.onclick = () => setStatsOpen(!statsOpen);

  // ---------- Магазин душ ----------
  const shop = el('div', 'lb-shopwin', document.body);
  shop.style.display = 'none';
  shop.addEventListener('pointerdown', (e) => e.stopPropagation());
  shop.addEventListener('click', (e) => { if (e.target === shop) openShop(false); });
  const sw = el('div', 'sw', shop);
  let sel = { role: 'det', potion: 'heal', side: 'human' };
  function renderShop() {
    const k = K();
    sw.innerHTML = '';
    const head = el('div', 'hd', sw);
    const cur = el('div', 'cur', head); cur.appendChild(pixCanvas('Текущая душа: ' + ROLES[sel.role].name, 1.35 * k, { fill: ROLES[sel.role].color }));
    const tt = el('div', 'tt', head); tt.appendChild(pixCanvas('Магазин душ', 3 * k, PIX.panel));
    const x = el('button', 'x', head); x.appendChild(pixCanvas('X', 3 * k, { fill: '#ff2a2a' })); x.onclick = () => openShop(false);
    for (const id of ROLE_IDS) {
      const r = ROLES[id], on = sel.role === id;
      const row = el('div', 'row' + (on ? ' on' : ''), sw);
      const c1 = el('div', 'c nm', row); c1.appendChild(pixCanvas(r.name, 2 * k, { fill: r.color })); el('small', '', c1).textContent = `${r.hp} HP · ${r.weapon}`;
      const c2 = el('div', 'c tile', row); el('div', 'wt', c2).appendChild(heartCanvas(r.color, Math.round(30 * k)));
      const c3 = el('div', 'c ds', row); c3.style.color = r.color;
      c3.innerHTML = `<span>${r.desc}${r.ability ? ` <b>Перезарядка R — ${r.ability.cd} с.</b>` : ''}</span>`;
      const c4 = el('div', 'c bt', row);
      const b = el('button', 'eq' + (on ? ' on' : ''), c4); b.appendChild(pixCanvas(on ? 'Надета' : 'Надеть душу', 1.45 * k, { fill: on ? '#9a9a9a' : '#ffffff' }));
      b.onclick = () => { onSoul?.(id); };
    }
    const ph = el('div', 'phd', sw); ph.appendChild(pixCanvas('Зелье на раунд: ' + POTIONS[sel.potion].short, 1.6 * k, { fill: POTIONS[sel.potion].color }));
    const pr = el('div', 'prow', sw);
    for (const id of POTION_IDS) {
      const p = POTIONS[id], on = sel.potion === id;
      const c = el('div', 'pc' + (on ? ' on' : ''), pr);
      const top = el('div', 'ptop', c);
      el('div', 'wt', top).appendChild(flaskCanvas(p.color, Math.round(22 * k)));
      top.appendChild(pixCanvas(p.short, 1.5 * k, { fill: p.color }));
      el('small', 'pd', c).textContent = p.desc;
      const b = el('button', 'eq' + (on ? ' on' : ''), c); b.appendChild(pixCanvas(on ? 'Взято' : 'Взять', 1.35 * k, { fill: on ? '#9a9a9a' : '#ffffff' }));
      b.onclick = () => { onPotion?.(id); };
    }
  }
  function openShop(v) {
    if (v) { openChars(false); renderShop(); }
    shop.style.display = v ? 'flex' : 'none';
  }

  // ---------- Выбор персонажа (монстра) ----------
  const chars = el('div', 'lb-charwin', document.body);
  chars.style.display = 'none';
  chars.addEventListener('pointerdown', (e) => e.stopPropagation());
  chars.addEventListener('click', (e) => { if (e.target === chars) openChars(false); });
  const cw = el('div', 'cw', chars);
  function renderChars() {
    const k = K();
    cw.innerHTML = '';
    const head = el('div', 'hd', cw);
    el('div', 'tt', head).appendChild(pixCanvas('Выбор персонажа', 2.6 * k, PIX.panel));
    const x = el('button', 'x', head); x.appendChild(pixCanvas('X', 3 * k, { fill: '#ff2a2a' })); x.onclick = () => openChars(false);
    const grid = el('div', 'cards', cw);
    for (const id of [...MONSTER_IDS, 'random']) {
      const M = MONSTERS[id], on = (sel.monster || 'judge') === id;
      const c = el('div', 'card' + (on ? ' on' : ''), grid);
      el('div', 'sil', c).appendChild(silhouette(Math.round(78 * k), id === 'random'));
      el('div', 'nm', c).appendChild(pixCanvas(M ? M.name : 'Случайный монстр', 1.7 * k, PIX.panel));
      el('small', '', c).textContent = M ? `таймер ${M.timer} · уклонений ${M.dodges} · ${M.hp} HP` : 'любой из открытых';
      const b = el('button', 'eq' + (on ? ' on' : ''), c); b.appendChild(pixCanvas(on ? 'Выбран' : 'Выбрать', 1.45 * k, { fill: on ? '#9a9a9a' : '#ffffff' }));
      b.onclick = () => onChar?.(id);
    }
    el('div', 'note', cw).textContent = 'Персонаж нужен, когда твоя очередь быть монстром (или выбери в очереди «Судья»).';
  }
  function openChars(v) {
    if (v) { shop.style.display = 'none'; renderChars(); }
    chars.style.display = v ? 'flex' : 'none';
  }

  let lastCd = '', lastNext = '';
  const api = {
    root,
    get shopOpen() { return shop.style.display !== 'none'; },
    get charsOpen() { return chars.style.display !== 'none'; },
    show(v) {
      root.style.display = v ? 'block' : 'none';
      if (!v) { openShop(false); openChars(false); }
      else { setStatsOpen(statsOpen); playB.innerHTML = ''; playB.appendChild(pixCanvas('Играть сейчас', 2 * K(), { fill: '#ffffff', outline: '#0b4f2c', outlineW: 1.5 * K() })); }
    },
    openShop, openChars,
    setSel(s) {
      sel = { ...s };
      sideBtns.forEach((b) => b.classList.toggle('on', b.dataset.side === sel.side));
      const r = ROLES[sel.role], p = POTIONS[sel.potion], k = K();
      shopHeart.innerHTML = ''; shopHeart.appendChild(heartCanvas(r.color, Math.round(22 * k)));
      shopTxt.innerHTML = ''; shopTxt.appendChild(rainbow('Магазин душ', 1.75 * k));
      shopSub.innerHTML = `<b style="color:${r.color}">${r.name}</b> · <b style="color:${p.color}">${p.name}</b>`;
      const M = MONSTERS[sel.monster];
      charIco.innerHTML = ''; charIco.appendChild(silhouette(Math.round(26 * k), !M));
      charTxt.innerHTML = ''; charTxt.appendChild(pixCanvas('Персонаж', 1.45 * k, PIX.panel));
      el('small', '', charTxt).textContent = M ? M.name : 'Случайный';
      if (api.shopOpen) renderShop();
      if (api.charsOpen) renderChars();
    },
    // rows: [{ name, me, judge }], text — подсказка под кнопками
    setQueue(list, hintText) {
      const k = K();
      qh.innerHTML = ''; qh.appendChild(pixCanvas('Очередь Судьи', 1.75 * k, PIX.panel));
      qrows.innerHTML = '';
      list.slice(0, 5).forEach((r, i) => {
        const row = el('div', 'qr' + (r.me ? ' me' : '') + (i === 0 ? ' first' : ''), qrows);
        el('b', '', row).textContent = i + 1;
        el('span', '', row).textContent = r.name + (r.me ? ' (ты)' : '');
        if (i === 0) el('em', '', row).textContent = 'Судья';
      });
      hint.textContent = hintText || '';
    },
    setCountdown(sec, afk) {
      const s = afk ? 'АФК' : 'Раунд через ' + Math.max(0, Math.ceil(sec));
      if (s === lastCd) return; lastCd = s;
      cd.set(s, Math.max(2, innerHeight * 0.0068), { ...PIX.timer, outlineK: 0.42 });
    },
    setNext(text) { if (text === lastNext) return; lastNext = text; next.set(text, Math.max(1.4, innerHeight * 0.0042), { fill: '#ffffff', outline: '#1a1206', outlineW: 1.6 }); },
    setFlags(f) {
      const k = K();
      lSpec.set(f.spectate ? 'Наблюдаю' : 'Наблюдать', 1.5 * k, { fill: f.spectate ? '#3fe08a' : '#ffffff' });
      lLow.set('Низкая графика', 1.25 * k, { fill: f.lowGfx ? '#3fe08a' : '#ffffff' });
      lAfk.set(f.afk ? 'АФК' : 'Не АФК', 1.5 * k, { fill: f.afk ? '#ff5050' : '#ffffff' });
      bSpec.classList.toggle('on', !!f.spectate); bLow.classList.toggle('on', !!f.lowGfx); bAfk.classList.toggle('on', !!f.afk);
    },
    // числа статистики; count — плавно досчитать от прошлых значений (после раунда)
    setStats(v, count = false) {
      for (const id of ['wins', 'kills', 'coins']) {
        const r = rows[id];
        r.val = v[id] || 0;
        if (!count || r.shown < 0) { r.shown = r.val; r.from = r.val; r.v.set(String(r.val), 2.4 * K(), PIX.panel); }
        else { r.from = r.shown; r.t = 0; }
      }
      if (count) { setStatsOpen(true); autoClose = 6; }
    },
    openStats: setStatsOpen,
    // анимация счётчиков; возвращает true, если что-то досчиталось (для «тиков»)
    update(dt) {
      let ticked = false;
      for (const id of ['wins', 'kills', 'coins']) {
        const r = rows[id];
        if (r.shown === r.val) continue;
        r.t = (r.t || 0) + dt;
        const k = Math.min(1, Math.max(0, (r.t - 0.4) / 1.4));
        const n = Math.round(r.from + (r.val - r.from) * k);
        if (n !== r.shown) { r.shown = n; r.v.set(String(n), 2.4 * K(), { fill: k < 1 ? '#ffe040' : '#ffffff' }); ticked = true; }
        if (k >= 1) r.v.set(String(n), 2.4 * K(), PIX.panel);
      }
      if (autoClose > 0) { autoClose -= dt; if (autoClose <= 0) setStatsOpen(false); }
      return ticked;
    },
  };
  return api;
}

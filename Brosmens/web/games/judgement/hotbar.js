// Мобильные элементы в стиле роблокса:
//  • панель предметов (hotbar) снизу по центру: квадратные слоты #1F1F1F 50%, номер слева сверху, название —
//    обычным шрифтом в нижней половине, у выбранного — синяя рамка #5A8EE9 (10% слота), перезарядка —
//    тёмный сектор по часовой + целые секунды, белая вспышка, когда готово. Тап = выбрать, двойной тап = сразу применить;
//  • кнопка души слева (пиксельное сердце цвета души, сектор перезарядки);
//  • счётчик «ПУЛИ» над панелью (Справедливость); прицел по центру экрана (Судья).
import { drawHeart } from './fx.js';
import { pixCanvas } from './pixfont.js';

const div = (cls, parent) => { const e = document.createElement('div'); e.className = cls; if (parent) parent.appendChild(e); return e; };
const DBL = +new URLSearchParams(location.search).get('dblms') || 320; // мс между тапами для «двойного»

export function createHotbar({ onTap, onDouble }) {
  const root = div('jd-hotbar', document.body);
  root.style.display = 'none';
  let slots = [], equipped = null, last = { id: null, t: 0 };
  const press = (id) => {
    const t = performance.now();
    if (last.id === id && t - last.t < DBL) { last.id = null; onDouble?.(id); }
    else { last = { id, t }; onTap?.(id); }
  };
  return {
    root,
    // tools: [{ id, num, name }]
    setTools(tools) {
      root.innerHTML = ''; slots = []; equipped = null;
      for (const tl of tools) {
        const el = div('jd-slot', root);
        el.innerHTML = `<i class="sw"></i><i class="rg"></i><b class="num">${tl.num}</b><span class="nm"></span><em class="sec"></em>`;
        el.querySelector('.nm').textContent = tl.name;
        const lw = Math.max(...tl.name.replace(/\u00ad/g, ' ').split(' ').map((w) => w.length));
        if (tl.name.length > 12 || lw >= 8) el.classList.add(lw >= 11 ? 'xlong' : 'long');
        el.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); press(tl.id); });
        el.addEventListener('pointerup', (e) => e.stopPropagation());
        slots.push({ ...tl, el, sw: el.querySelector('.sw'), rg: el.querySelector('.rg'), sec: el.querySelector('.sec'), c: { a: -1, s: '', ready: true, r: '' } });
      }
    },
    has: (id) => slots.some((s) => s.id === id),
    byNum: (n) => slots.find((s) => s.num === n)?.id ?? null,
    name: (id) => slots.find((s) => s.id === id)?.name ?? '',
    press,
    setEquipped(id) {
      equipped = id;
      for (const s of slots) s.el.classList.toggle('on', s.id === id);
    },
    remove(id) {
      const i = slots.findIndex((s) => s.id === id);
      if (i < 0) return;
      slots[i].el.remove(); slots.splice(i, 1);
    },
    // cd(id) → [доля 0..1, секунд осталось, кольцо 0..1 (действующее зелье), цвет кольца]
    update(cd) {
      for (const s of slots) {
        const [frac, left, ring = 0, rc = '#fff'] = cd(s.id);
        const rk = ring > 0 ? rc + Math.round(ring * 180) : '';
        if (rk !== s.c.r) {
          s.c.r = rk;
          s.rg.style.display = rk ? 'block' : 'none';
          if (rk) s.rg.style.background = `conic-gradient(${rc} ${Math.round(ring * 360)}deg, rgba(255,255,255,.12) 0)`;
          s.el.classList.toggle('active', !!rk);
        }
        const a = frac > 0.001 ? Math.round((1 - frac) * 360) : 360;
        if (a !== s.c.a) { s.c.a = a; s.sw.style.background = a >= 360 ? 'none' : `conic-gradient(transparent ${a}deg, rgba(0,0,0,.62) 0)`; }
        const txt = frac > 0.001 && left >= 0.95 ? String(Math.ceil(left)) : '';
        if (txt !== s.c.s) { s.c.s = txt; s.sec.textContent = txt; }
        const ready = frac <= 0.001;
        if (ready !== s.c.ready) {
          s.c.ready = ready;
          s.el.classList.toggle('cool', !ready);
          if (ready) { s.el.classList.remove('flash'); void s.el.offsetWidth; s.el.classList.add('flash'); }
        }
      }
    },
    show(v) { root.style.display = v ? 'flex' : 'none'; },
  };
}

// Кнопка способности души: пиксельное сердце цвета души
export function createSoulButton({ onPress }) {
  const el = div('jd-soul', document.body);
  el.style.display = 'none';
  const cv = document.createElement('canvas'); el.appendChild(cv);
  const sw = div('sw', el), sec = div('sec', el);
  let key = '', c = { a: -1, s: '' };
  el.addEventListener('pointerdown', (e) => {
    e.preventDefault(); e.stopPropagation();
    el.classList.add('on'); onPress?.();
  });
  const up = (e) => { e.stopPropagation(); el.classList.remove('on'); };
  el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
  return {
    el,
    setHeart(color, broken = false, dim = false) {
      const k = color + broken + dim;
      if (k === key) return; key = k;
      const dpr = Math.min(3, devicePixelRatio || 1), S = 46;
      cv.width = cv.height = Math.round(S * dpr); cv.style.width = cv.style.height = S + 'px';
      const g = cv.getContext('2d'); g.imageSmoothingEnabled = false;
      g.clearRect(0, 0, cv.width, cv.height);
      const px = Math.floor((S * dpr) / 10);
      g.shadowColor = color; g.shadowBlur = 10 * dpr;
      drawHeart(g, cv.width / 2, cv.height / 2 + px * 0.3, px, color, broken);
      el.classList.toggle('dim', dim);
    },
    setCooldown(frac, left) {
      const a = frac > 0.001 ? Math.round((1 - frac) * 360) : 360;
      if (a !== c.a) { c.a = a; sw.style.background = a >= 360 ? 'none' : `conic-gradient(transparent ${a}deg, rgba(0,0,0,.6) 0)`; if (a >= 360) { el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); } }
      const s = frac > 0.001 ? String(Math.ceil(left)) : '';
      if (s !== c.s) { c.s = s; sec.textContent = s; }
    },
    show(v) { el.style.display = v ? 'flex' : 'none'; },
  };
}

// «ПУЛИ»: подпись пиксельным шрифтом и 6 патронов над панелью предметов
export function createAmmo() {
  const el = div('jd-ammo', document.body);
  el.style.display = 'none';
  el.appendChild(pixCanvas('ПУЛИ', 1.6, { fill: '#ffffff', outline: '#141414', outlineW: 1.2 }));
  const pips = []; const row = div('pips', el);
  for (let i = 0; i < 6; i++) pips.push(div('pip', row));
  let k = '';
  return {
    set(n, color = '#F0F800') {
      const key = n + color; if (key === k) return; k = key;
      pips.forEach((p, i) => { p.classList.toggle('on', i < n); p.style.background = i < n ? color : ''; });
    },
    show(v) { el.style.display = v ? 'flex' : 'none'; },
  };
}

// Прицел Судьи: белый кружок с точкой по центру экрана
export function createReticle() {
  const el = div('jd-ret', document.body);
  el.innerHTML = '<i></i>';
  el.style.display = 'none';
  return { show(v) { el.style.display = v ? 'block' : 'none'; } };
}

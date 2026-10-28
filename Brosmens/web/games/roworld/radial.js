// BroWorld — радиальное меню как в оригинале: полупрозрачное серое кольцо, тёмно-синий диск, разделённый
// на равные секторы (иконка над подписью), круглая «✕» в центре, табличка с именем цели сверху и
// подсказка снизу. Наведение/ведение пальцем подсвечивает сектор янтарным, отпускание на секторе — выбор.
// openRadial(x, y, { title, color, items: [{ id, icon, label, hint, off, red }], onPick })
const NS = 'http://www.w3.org/2000/svg';
let el = null, st = null;

function sector(cx, cy, r0, r1, a0, a1) {
  const p = (r, a) => `${(cx + Math.cos(a) * r).toFixed(1)} ${(cy + Math.sin(a) * r).toFixed(1)}`;
  const big = a1 - a0 > Math.PI ? 1 : 0;
  return `M${p(r0, a0)} L${p(r1, a0)} A${r1} ${r1} 0 ${big} 1 ${p(r1, a1)} L${p(r0, a1)} A${r0} ${r0} 0 ${big} 0 ${p(r0, a0)}Z`;
}

export function radialOpen() { return !!st; }
export function closeRadial() {
  if (!el) return;
  st = null;
  el.classList.remove('show');
  el.innerHTML = '';
  el.style.display = 'none';
}

export function openRadial(x, y, opts) {
  if (!el) {
    el = document.createElement('div');
    el.id = 'radial';
    document.body.appendChild(el);
    el.addEventListener('pointerdown', (e) => { e.stopPropagation(); if (st) { st.down = true; hover(e.clientX, e.clientY); } });
    el.addEventListener('pointermove', (e) => { if (st) hover(e.clientX, e.clientY); });
    el.addEventListener('pointerup', (e) => { e.stopPropagation(); if (st && st.down) release(e.clientX, e.clientY); });
  }
  const vw = innerWidth, vh = innerHeight;
  const Ro = Math.min(108, vh * 0.27), Rd = Ro - 15, Rc = 25;
  const cx = Math.max(Ro + 8, Math.min(vw - Ro - 8, x)), cy = Math.max(Ro + 34, Math.min(vh - Ro - 30, y));
  const n = opts.items.length, da = (2 * Math.PI) / n;
  st = { ...opts, cx, cy, Ro, Rd, Rc, n, da, hov: -1, t0: performance.now(), down: false };
  el.style.display = 'block';
  el.style.setProperty('--ox', cx + 'px'); el.style.setProperty('--oy', cy + 'px');
  el.innerHTML = '';
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('width', vw); svg.setAttribute('height', vh);
  let h = `<circle cx="${cx}" cy="${cy}" r="${Ro}" fill="rgba(107,114,128,.35)"/><circle cx="${cx}" cy="${cy}" r="${Rd}" fill="#0E1528" fill-opacity=".96"/>`;
  opts.items.forEach((it, i) => {
    const a0 = -Math.PI / 2 - da / 2 + i * da, a1 = a0 + da, am = (a0 + a1) / 2;
    h += `<path class="wg" data-i="${i}" d="${sector(cx, cy, Rc + 3, Rd, a0, a1)}" fill="transparent"/>`;
    if (n > 1) h += `<line x1="${cx + Math.cos(a0) * (Rc + 3)}" y1="${cy + Math.sin(a0) * (Rc + 3)}" x2="${cx + Math.cos(a0) * Rd}" y2="${cy + Math.sin(a0) * Rd}" stroke="rgba(255,255,255,.14)" stroke-width="1"/>`;
    const rm = (Rc + Rd) / 2 + 2, ix = cx + Math.cos(am) * rm, iy = cy + Math.sin(am) * rm;
    h += `<g class="wi${it.off ? ' off' : ''}" data-i="${i}" transform="translate(${ix.toFixed(1)} ${(iy - 7).toFixed(1)})"><g transform="translate(-10 -10)">${it.icon}</g><text y="19" text-anchor="middle">${it.label}</text></g>`;
  });
  h += `<circle class="rx" cx="${cx}" cy="${cy}" r="${Rc}" fill="#141c30" stroke="rgba(255,255,255,.28)" stroke-width="2"/><path d="M${cx - 6} ${cy - 6}L${cx + 6} ${cy + 6}M${cx + 6} ${cy - 6}L${cx - 6} ${cy + 6}" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/>`;
  svg.innerHTML = h;
  el.appendChild(svg);
  const name = document.createElement('div');
  name.className = 'rname';
  name.textContent = opts.title;
  name.style.color = opts.color || '#fff';
  name.style.left = cx + 'px'; name.style.top = (cy - Ro - 30) + 'px';
  const hint = document.createElement('div');
  hint.className = 'rhint';
  hint.style.left = cx + 'px'; hint.style.top = (cy + Ro + 6) + 'px';
  el.append(name, hint);
  st.hintEl = hint;
  setHint(opts.hint || '');
  requestAnimationFrame(() => el.classList.add('show'));
}

function setHint(t) { if (st) { st.hintEl.textContent = t; st.hintEl.style.display = t ? '' : 'none'; } }

function which(x, y) {
  const dx = x - st.cx, dy = y - st.cy, r = Math.hypot(dx, dy);
  if (r < st.Rc) return -2; // центр
  if (r > st.Ro + 14) return -3; // мимо
  let a = Math.atan2(dy, dx) + Math.PI / 2 + st.da / 2;
  a = ((a % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
  return Math.min(st.n - 1, Math.floor(a / st.da));
}

// ведение пальцем (в том числе продолжение долгого нажатия на карте)
export function hover(x, y) {
  if (!st) return;
  const i = which(x, y);
  const k = i >= 0 && !st.items[i].off ? i : -1;
  if (k === st.hov && i >= 0) return;
  st.hov = k;
  el.querySelectorAll('.wg').forEach((p) => p.setAttribute('fill', +p.dataset.i === k ? (st.items[k].red ? '#EE4062' : st.items[k].salmon ? '#F2727F' : '#F3B647') : 'transparent'));
  el.querySelectorAll('.wi').forEach((g) => g.classList.toggle('on', +g.dataset.i === k));
  setHint(i >= 0 ? st.items[i].hint || st.items[i].label : st.hint || '');
}

// отпускание: на секторе — выбор, в центре — закрыть (если давно открыто), мимо — закрыть
export function release(x, y, fromHold = false) {
  if (!st) return;
  const i = which(x, y);
  if (i >= 0) {
    const it = st.items[i];
    if (it.off) { setHint(it.hint || ''); return; }
    const fn = st.onPick;
    closeRadial();
    fn(it.id);
    return;
  }
  if (fromHold && i === -2) return; // долгое нажатие отпустили в центре — меню остаётся открытым
  if (i === -2 || i === -3) closeRadial();
}

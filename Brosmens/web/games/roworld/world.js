// BroWorld — процедурный мир: материки и острова (шум), провинции (геодезический Вороной по суше),
// местность, гладкие границы (общие участки границ считаются один раз — без щелей), морские пути.
// Модуль чистый (без DOM), всё в мировых единицах. Карта WW×WH, сетка GW×GH клеток по CELL.
export const CELL = 5;
export const GW = 360, GH = 208;
export const WW = GW * CELL, WH = GH * CELL;
const CW = GW + 1; // ширина сетки углов
const SF = 2; // морская сетка грубее в 2 раза
export const SW = GW / SF, SH = GH / SF, SEA_CELL = CELL * SF;
export const SEA_RANGE = 36; // шагов морской сетки (~360 ед.) — дальность высадки из порта

export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makePerlin(rand) {
  const base = new Uint8Array(256);
  for (let i = 0; i < 256; i++) base[i] = i;
  for (let i = 255; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = base[i]; base[i] = base[j]; base[j] = t; }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = base[i & 255];
  const GX = [1, -1, 0, 0, 0.7071, -0.7071, 0.7071, -0.7071];
  const GY = [0, 0, 1, -1, 0.7071, 0.7071, -0.7071, -0.7071];
  function noise(x, y) {
    const X = Math.floor(x), Y = Math.floor(y);
    const xf = x - X, yf = y - Y, xi = X & 255, yi = Y & 255;
    const u = xf * xf * xf * (xf * (xf * 6 - 15) + 10), v = yf * yf * yf * (yf * (yf * 6 - 15) + 10);
    const h00 = perm[perm[xi] + yi] & 7, h10 = perm[perm[xi + 1] + yi] & 7;
    const h01 = perm[perm[xi] + yi + 1] & 7, h11 = perm[perm[xi + 1] + yi + 1] & 7;
    const n00 = GX[h00] * xf + GY[h00] * yf, n10 = GX[h10] * (xf - 1) + GY[h10] * yf;
    const n01 = GX[h01] * xf + GY[h01] * (yf - 1), n11 = GX[h11] * (xf - 1) + GY[h11] * (yf - 1);
    const a = n00 + u * (n10 - n00), b = n01 + u * (n11 - n01);
    return (a + v * (b - a)) * 1.4;
  }
  function fbm(x, y, oct = 4) {
    let s = 0, amp = 1, f = 1, norm = 0;
    for (let o = 0; o < oct; o++) { s += amp * noise(x * f, y * f); norm += amp; amp *= 0.5; f *= 2.03; }
    return s / norm;
  }
  return { noise, fbm };
}

class Heap {
  constructor(cap) { this.k = new Float64Array(cap); this.v = new Int32Array(cap); this.n = 0; this.topK = 0; }
  push(k, v) {
    let i = this.n++;
    while (i > 0) { const p = (i - 1) >> 1; if (this.k[p] <= k) break; this.k[i] = this.k[p]; this.v[i] = this.v[p]; i = p; }
    this.k[i] = k; this.v[i] = v;
  }
  pop() {
    const top = this.v[0]; this.topK = this.k[0];
    const k = this.k[--this.n], v = this.v[this.n];
    let i = 0;
    for (;;) {
      let c = 2 * i + 1; if (c >= this.n) break;
      if (c + 1 < this.n && this.k[c + 1] < this.k[c]) c++;
      if (this.k[c] >= k) break;
      this.k[i] = this.k[c]; this.v[i] = this.v[c]; i = c;
    }
    this.k[i] = k; this.v[i] = v;
    return top;
  }
}

// Связные компоненты маски (4-связность)
function components(mask, val) {
  const N = GW * GH, label = new Int32Array(N).fill(-1), sizes = [], border = [];
  const stack = new Int32Array(N);
  for (let s = 0; s < N; s++) {
    if (mask[s] !== val || label[s] >= 0) continue;
    const c = sizes.length; let sp = 0, size = 0, touch = false;
    stack[sp++] = s; label[s] = c;
    while (sp) {
      const i = stack[--sp]; size++;
      const x = i % GW, y = (i / GW) | 0;
      if (x === 0 || y === 0 || x === GW - 1 || y === GH - 1) touch = true;
      if (x > 0 && mask[i - 1] === val && label[i - 1] < 0) { label[i - 1] = c; stack[sp++] = i - 1; }
      if (x < GW - 1 && mask[i + 1] === val && label[i + 1] < 0) { label[i + 1] = c; stack[sp++] = i + 1; }
      if (y > 0 && mask[i - GW] === val && label[i - GW] < 0) { label[i - GW] = c; stack[sp++] = i - GW; }
      if (y < GH - 1 && mask[i + GW] === val && label[i + GW] < 0) { label[i + GW] = c; stack[sp++] = i + GW; }
    }
    sizes.push(size); border.push(touch);
  }
  return { label, sizes, border };
}

// ---- сглаживание линий ----
function chaikin(pts, closed, iters) {
  let p = pts;
  for (let it = 0; it < iters; it++) {
    const n = p.length / 2, out = [];
    if (closed) {
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n, ax = p[i * 2], ay = p[i * 2 + 1], bx = p[j * 2], by = p[j * 2 + 1];
        out.push(ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25, ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75);
      }
    } else {
      out.push(p[0], p[1]);
      for (let i = 0; i < n - 1; i++) {
        const ax = p[i * 2], ay = p[i * 2 + 1], bx = p[i * 2 + 2], by = p[i * 2 + 3];
        out.push(ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25, ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75);
      }
      out.push(p[p.length - 2], p[p.length - 1]);
    }
    p = out;
  }
  return p;
}

function simplify(pts, tol) { // Дуглас-Пекер для открытой ломаной (концы сохраняются)
  const n = pts.length / 2;
  if (n <= 2) return pts.slice();
  const keep = new Uint8Array(n); keep[0] = keep[n - 1] = 1;
  const st = [0, n - 1], t2 = tol * tol;
  while (st.length) {
    const b = st.pop(), a = st.pop();
    const ax = pts[a * 2], ay = pts[a * 2 + 1], bx = pts[b * 2], by = pts[b * 2 + 1];
    const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy || 1e-9;
    let best = -1, bd = t2;
    for (let i = a + 1; i < b; i++) {
      const px = pts[i * 2] - ax, py = pts[i * 2 + 1] - ay;
      const t = Math.max(0, Math.min(1, (px * dx + py * dy) / L));
      const ex = px - t * dx, ey = py - t * dy, d = ex * ex + ey * ey;
      if (d > bd) { bd = d; best = i; }
    }
    if (best > 0) { keep[best] = 1; st.push(a, best, best, b); }
  }
  const out = [];
  for (let i = 0; i < n; i++) if (keep[i]) out.push(pts[i * 2], pts[i * 2 + 1]);
  return out;
}

function reversePts(p) {
  const out = new Array(p.length);
  for (let i = 0, n = p.length / 2; i < n; i++) { out[i * 2] = p[(n - 1 - i) * 2]; out[i * 2 + 1] = p[(n - 1 - i) * 2 + 1]; }
  return out;
}

// смещение ломаной вправо (внутрь провинции) на d
export function offsetPts(p, closed, d) {
  const n = p.length / 2, out = new Float32Array(p.length);
  for (let i = 0; i < n; i++) {
    const a = i > 0 ? i - 1 : closed ? n - 1 : 0, b = i < n - 1 ? i + 1 : closed ? 0 : n - 1;
    let tx = p[b * 2] - p[a * 2], ty = p[b * 2 + 1] - p[a * 2 + 1];
    const L = Math.hypot(tx, ty) || 1; tx /= L; ty /= L;
    out[i * 2] = p[i * 2] - ty * d; out[i * 2 + 1] = p[i * 2 + 1] + tx * d;
  }
  return out;
}

const NAME_A = ['Красно', 'Бело', 'Черно', 'Злато', 'Сине', 'Ново', 'Старо', 'Тихо', 'Ясно', 'Светло', 'Высоко', 'Долго', 'Камне', 'Лесо', 'Медве', 'Соле', 'Яро', 'Вольно', 'Мирно', 'Ледо', 'Песко', 'Горно', 'Озеро', 'Звёздо', 'Ветро', 'Громо', 'Дубо', 'Кедро', 'Сокол', 'Волко', 'Лисо', 'Орло', 'Снеже', 'Тёпло', 'Зелено', 'Бронзо', 'Серебро', 'Рыбо', 'Хлебо', 'Мохо'];
const NAME_B = ['горск', 'град', 'поль', 'мир', 'дар', 'вск', 'бор', 'дол', 'ярск', 'морье', 'поле', 'гора', 'брод', 'устье', 'речье', 'полье', 'вежье', 'холм', 'стан', 'ск'];

export function generateWorld(seed, { provinces: target = 185, land: landFrac = 0.41 } = {}) {
  const rand = mulberry32(seed);
  const P = makePerlin(rand);
  const N = GW * GH;
  const elev = new Float32Array(N), mtn = new Float32Array(N), moist = new Float32Array(N);

  // --- рельеф: несколько «материковых» пятен + шум + искажение координат ---
  const blobs = [];
  const nb = 5 + Math.floor(rand() * 3);
  for (let k = 0; k < nb; k++) {
    blobs.push({ x: WW * (0.1 + rand() * 0.8), y: WH * (0.15 + rand() * 0.7), r: WW * (0.08 + rand() * 0.12), w: 0.7 + rand() * 0.4 });
  }
  for (let gy = 0, i = 0; gy < GH; gy++) {
    for (let gx = 0; gx < GW; gx++, i++) {
      const x = (gx + 0.5) * CELL, y = (gy + 0.5) * CELL;
      const wx = x + 150 * P.fbm(x / 430 + 3.1, y / 430 + 1.7, 3);
      const wy = y + 150 * P.fbm(x / 430 + 8.3, y / 430 + 4.2, 3);
      let b = 0;
      for (const B of blobs) {
        const dx = wx - B.x, dy = wy - B.y;
        const v = B.w * Math.exp(-(dx * dx + dy * dy) / (B.r * B.r));
        if (v > b) b = v;
      }
      let e = b + 0.5 * P.fbm(x / 250, y / 250, 5) + 0.1 * P.fbm(x / 50, y / 50, 3);
      const edge = Math.min(x, WW - x, (y) * 1.3, (WH - y) * 1.3) / (WW * 0.07);
      if (edge < 1) e -= (1 - edge) * (1 - edge) * 1.2;
      elev[i] = e;
      mtn[i] = 1 - Math.abs(P.fbm(x / 160 + 20, y / 160 - 9, 4)) * 2.4;
      moist[i] = P.fbm(x / 290 - 13, y / 290 + 21, 4);
    }
  }
  const sorted = Float32Array.from(elev).sort();
  const thr = sorted[Math.floor(N * (1 - landFrac))];
  const land = new Uint8Array(N);
  for (let gy = 2; gy < GH - 2; gy++) for (let gx = 2; gx < GW - 2; gx++) { const i = gy * GW + gx; land[i] = elev[i] > thr ? 1 : 0; }
  // убрать мелкие острова, засыпать мелкие озёра
  {
    const c = components(land, 1);
    for (let i = 0; i < N; i++) if (land[i] && c.sizes[c.label[i]] < 30) land[i] = 0;
    const w = components(land, 0);
    for (let i = 0; i < N; i++) if (!land[i] && !w.border[w.label[i]] && w.sizes[w.label[i]] < 70) land[i] = 1;
  }
  const comp = components(land, 1);
  const landCells = [];
  for (let i = 0; i < N; i++) if (land[i]) landCells.push(i);
  const L = landCells.length;

  // --- семена провинций (Пуассон) ---
  const order = landCells.slice();
  for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = order[i]; order[i] = order[j]; order[j] = t; }
  let fac = 1.0, seeds = [];
  for (let attempt = 0; attempt < 8; attempt++) {
    const r = Math.sqrt(L / target) * fac, r2 = r * r;
    const bw = Math.ceil(GW / r), bh = Math.ceil(GH / r);
    const buckets = Array.from({ length: bw * bh }, () => []);
    seeds = [];
    for (const c of order) {
      const x = c % GW, y = (c / GW) | 0, bx = Math.floor(x / r), by = Math.floor(y / r);
      let ok = true;
      for (let yy = Math.max(0, by - 1); yy <= Math.min(bh - 1, by + 1) && ok; yy++) {
        for (let xx = Math.max(0, bx - 1); xx <= Math.min(bw - 1, bx + 1) && ok; xx++) {
          for (const s of buckets[yy * bw + xx]) { const dx = (s % GW) - x, dy = ((s / GW) | 0) - y; if (dx * dx + dy * dy < r2) { ok = false; break; } }
        }
      }
      if (ok) { seeds.push(c); buckets[by * bw + bx].push(c); }
    }
    if (seeds.length < target * 0.93) fac *= 0.95;
    else if (seeds.length > target * 1.07) fac *= 1.04;
    else break;
  }
  // у каждого острова — хотя бы одно семя
  {
    const has = new Uint8Array(comp.sizes.length);
    for (const s of seeds) has[comp.label[s]] = 1;
    const sx = new Float64Array(comp.sizes.length), sy = new Float64Array(comp.sizes.length);
    for (const c of landCells) { const k = comp.label[c]; sx[k] += c % GW; sy[k] += (c / GW) | 0; }
    const best = new Int32Array(comp.sizes.length).fill(-1), bd = new Float64Array(comp.sizes.length).fill(1e18);
    for (const c of landCells) {
      const k = comp.label[c]; if (has[k]) continue;
      const dx = (c % GW) - sx[k] / comp.sizes[k], dy = ((c / GW) | 0) - sy[k] / comp.sizes[k], d = dx * dx + dy * dy;
      if (d < bd[k]) { bd[k] = d; best[k] = c; }
    }
    for (let k = 0; k < best.length; k++) if (!has[k] && best[k] >= 0) seeds.push(best[k]);
  }

  // --- рост провинций (Дейкстра с шумной стоимостью → живые границы) ---
  const id = new Int16Array(N).fill(-1);
  {
    const dist = new Float64Array(N).fill(Infinity);
    const jit = new Float32Array(N);
    for (const c of landCells) { const x = (c % GW) * CELL, y = ((c / GW) | 0) * CELL; jit[c] = 0.5 + 0.5 * (P.fbm(x / 40 + 50, y / 40 - 30, 3) + 1); }
    const heap = new Heap(N * 8);
    seeds.forEach((c, k) => { dist[c] = 0; id[c] = k; heap.push(0, c); });
    const DX = [1, -1, 0, 0, 1, 1, -1, -1], DY = [0, 0, 1, -1, 1, -1, 1, -1];
    while (heap.n) {
      const c = heap.pop(), d = heap.topK;
      if (d > dist[c]) continue;
      const x = c % GW, y = (c / GW) | 0;
      for (let k = 0; k < 8; k++) {
        const nx = x + DX[k], ny = y + DY[k];
        if (nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue;
        const n = ny * GW + nx;
        if (!land[n]) continue;
        if (k >= 4 && !land[y * GW + nx] && !land[ny * GW + x]) continue;
        const nd = d + (k >= 4 ? 1.414 : 1) * (jit[c] + jit[n]) * 0.5;
        if (nd < dist[n]) { dist[n] = nd; id[n] = id[c]; heap.push(nd, n); }
      }
    }
  }
  // слить крошечные провинции с соседом, затем перенумеровать
  {
    let np = seeds.length;
    for (let pass = 0; pass < 2; pass++) {
      const cnt = new Int32Array(np);
      for (const c of landCells) cnt[id[c]]++;
      const nbBest = new Int32Array(np).fill(-1), nbCnt = new Int32Array(np);
      for (const c of landCells) {
        const p = id[c]; if (cnt[p] >= 14) continue;
        const x = c % GW;
        for (const n of [c - 1, c + 1, c - GW, c + GW]) {
          if (n < 0 || n >= N || (n === c - 1 && x === 0) || (n === c + 1 && x === GW - 1)) continue;
          const q = id[n]; if (q >= 0 && q !== p && cnt[q] > nbCnt[p]) { nbCnt[p] = cnt[q]; nbBest[p] = q; }
        }
      }
      for (const c of landCells) { const p = id[c]; if (cnt[p] < 14 && nbBest[p] >= 0) id[c] = nbBest[p]; }
    }
    const remap = new Int32Array(np).fill(-1); let k = 0;
    for (const c of landCells) if (remap[id[c]] < 0) remap[id[c]] = k++;
    for (const c of landCells) id[c] = remap[id[c]];
  }
  let np = 0;
  for (const c of landCells) if (id[c] + 1 > np) np = id[c] + 1;

  // --- данные провинций ---
  const provinces = [];
  const cnt = new Int32Array(np);
  for (const c of landCells) cnt[id[c]]++;
  for (let p = 0; p < np; p++) {
    provinces.push({ id: p, cells: new Int32Array(cnt[p]), area: cnt[p], sx: 0, sy: 0, e: 0, m: 0, w: 0, coastal: false, nb: new Set(), x0: 1e9, y0: 1e9, x1: -1e9, y1: -1e9 });
  }
  const fill = new Int32Array(np);
  for (const c of landCells) {
    const p = id[c], pr = provinces[p];
    pr.cells[fill[p]++] = c;
    const x = c % GW, y = (c / GW) | 0;
    pr.sx += x; pr.sy += y; pr.e += elev[c]; pr.m += mtn[c]; pr.w += moist[c];
    if (x < pr.x0) pr.x0 = x; if (x > pr.x1) pr.x1 = x; if (y < pr.y0) pr.y0 = y; if (y > pr.y1) pr.y1 = y;
    const ns = [x > 0 ? id[c - 1] : -1, x < GW - 1 ? id[c + 1] : -1, y > 0 ? id[c - GW] : -1, y < GH - 1 ? id[c + GW] : -1];
    for (const q of ns) { if (q < 0) pr.coastal = true; else if (q !== p) pr.nb.add(q); }
  }
  // дистанция до границы (для подписей и значков)
  const dt = new Uint8Array(N);
  {
    const q = new Int32Array(N); let h = 0, t = 0;
    for (const c of landCells) {
      const x = c % GW, y = (c / GW) | 0, p = id[c];
      if (x === 0 || y === 0 || x === GW - 1 || y === GH - 1 || id[c - 1] !== p || id[c + 1] !== p || id[c - GW] !== p || id[c + GW] !== p) { dt[c] = 1; q[t++] = c; }
    }
    while (h < t) {
      const c = q[h++], p = id[c];
      for (const n of [c - 1, c + 1, c - GW, c + GW]) if (id[n] === p && !dt[n]) { dt[n] = dt[c] + 1; q[t++] = n; }
    }
  }
  const names = [];
  for (const a of NAME_A) for (const b of NAME_B) names.push(a + b);
  for (let i = names.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = names[i]; names[i] = names[j]; names[j] = t; }

  for (const pr of provinces) {
    const n = pr.area;
    pr.cx = (pr.sx / n + 0.5) * CELL; pr.cy = (pr.sy / n + 0.5) * CELL;
    pr.e = (pr.e / n - thr); pr.m /= n; pr.w /= n;
    let best = -1, bs = -1e9;
    for (const c of pr.cells) {
      const x = (c % GW + 0.5) * CELL, y = (((c / GW) | 0) + 0.5) * CELL;
      const s = Math.min(dt[c], 7) * 10 - Math.hypot(x - pr.cx, y - pr.cy) / CELL;
      if (s > bs) { bs = s; best = c; }
    }
    pr.lx = (best % GW + 0.5) * CELL; pr.ly = (((best / GW) | 0) + 0.5) * CELL;
    pr.neighbors = [...pr.nb]; delete pr.nb;
    pr.bx0 = pr.x0 * CELL; pr.by0 = pr.y0 * CELL; pr.bx1 = (pr.x1 + 1) * CELL; pr.by1 = (pr.y1 + 1) * CELL;
    pr.name = names[pr.id % names.length];
    pr.lat = Math.abs(pr.cy / WH - 0.5) * 2; // 0 экватор … 1 полюс
  }

  // --- местность ---
  {
    const lat = (p) => p.lat + P.fbm(p.cx / 300 + 77, p.cy / 300, 2) * 0.12;
    const rest = new Set(provinces);
    for (const p of provinces) if (lat(p) > 0.74) { p.terrain = 'snow'; rest.delete(p); }
    const byM = [...rest].sort((a, b) => (b.m * 0.6 + b.e * 1.6) - (a.m * 0.6 + a.e * 1.6));
    for (let i = 0; i < Math.round(np * 0.14); i++) { byM[i].terrain = 'mountains'; rest.delete(byM[i]); }
    const hot = [...rest].filter((p) => lat(p) < 0.42).sort((a, b) => a.w - b.w);
    for (let i = 0; i < Math.min(hot.length, Math.round(np * 0.13)); i++) { if (hot[i].w > 0.08) break; hot[i].terrain = 'desert'; rest.delete(hot[i]); }
    const wet = [...rest].sort((a, b) => b.w - a.w);
    for (let i = 0; i < Math.round(wet.length * 0.42); i++) { wet[i].terrain = 'forest'; rest.delete(wet[i]); }
    for (const p of rest) p.terrain = 'plains';
  }

  // --- контуры: рёбра клеток → кольца → участки по соседу → сглаживание (общие участки — из кэша) ---
  const runCache = new Map();
  const cx = (k) => (k % CW) * CELL, cy = (k) => Math.floor(k / CW) * CELL;
  const coastLines = [], innerBorders = [];
  function makeRun(p, other, corners, closed) {
    // убрать точки на прямых участках
    const m = corners.length, keep = [];
    for (let i = 0; i < m; i++) {
      if (!closed && (i === 0 || i === m - 1)) { keep.push(corners[i]); continue; }
      const a = corners[(i - 1 + m) % m], b = corners[i], c = corners[(i + 1) % m];
      const d1x = cx(b) - cx(a), d1y = cy(b) - cy(a), d2x = cx(c) - cx(b), d2y = cy(c) - cy(b);
      if (d1x * d2y - d1y * d2x !== 0) keep.push(b);
    }
    let key = null, pts = null;
    if (other >= 0) {
      const lo = Math.min(p, other), hi = Math.max(p, other);
      if (closed) key = `c${lo}_${hi}_${Math.min(...corners)}`;
      else key = `o${lo}_${hi}_${Math.min(corners[0], corners[m - 1])}_${Math.max(corners[0], corners[m - 1])}`;
      const hit = runCache.get(key);
      if (hit) pts = (!closed && hit.start === corners[0]) ? hit.pts : reversePts(hit.pts);
    }
    if (!pts) {
      let raw = [];
      for (const k of keep) raw.push(cx(k), cy(k));
      if (closed && raw.length < 6) { raw = []; for (const k of corners) raw.push(cx(k), cy(k)); }
      // ступеньки → прямые диагонали → плавные кривые
      let pre = raw;
      if (closed) { const t = simplify(raw.concat([raw[0], raw[1]]), CELL * 0.62); t.length -= 2; if (t.length >= 8) pre = t; }
      else pre = simplify(raw, CELL * 0.62);
      let sm = chaikin(pre, closed, 3);
      if (closed) { sm.push(sm[0], sm[1]); sm = simplify(sm, 0.3); sm.length -= 2; }
      else sm = simplify(sm, 0.3);
      pts = sm;
      if (key) runCache.set(key, { start: corners[0], pts });
      if (other < 0) coastLines.push({ pts, closed });
      else innerBorders.push({ pts, closed });
    }
    return { other, closed, pts: Float32Array.from(pts) };
  }

  for (const pr of provinces) {
    const p = pr.id;
    const ea = [], eb = [], eo = [];
    const outMap = new Map();
    const add = (a, b, o) => {
      const k = ea.length; ea.push(a); eb.push(b); eo.push(o);
      const l = outMap.get(a); if (l) l.push(k); else outMap.set(a, [k]);
    };
    for (const c of pr.cells) {
      const gx = c % GW, gy = (c / GW) | 0;
      const t = gy > 0 ? id[c - GW] : -1, r = gx < GW - 1 ? id[c + 1] : -1;
      const bo = gy < GH - 1 ? id[c + GW] : -1, l = gx > 0 ? id[c - 1] : -1;
      if (t !== p) add(gy * CW + gx, gy * CW + gx + 1, t);
      if (r !== p) add(gy * CW + gx + 1, (gy + 1) * CW + gx + 1, r);
      if (bo !== p) add((gy + 1) * CW + gx + 1, (gy + 1) * CW + gx, bo);
      if (l !== p) add((gy + 1) * CW + gx, gy * CW + gx, l);
    }
    const used = new Uint8Array(ea.length);
    const rings = [];
    for (let s = 0; s < ea.length; s++) {
      if (used[s]) continue;
      const ring = []; let e = s;
      for (;;) {
        used[e] = 1; ring.push(e);
        const cand = outMap.get(eb[e]);
        let nx = -1;
        for (const c of cand) {
          if (used[c]) continue;
          if (nx < 0) nx = c;
          else {
            const d1x = cx(eb[e]) - cx(ea[e]), d1y = cy(eb[e]) - cy(ea[e]);
            const d2x = cx(eb[c]) - cx(ea[c]), d2y = cy(eb[c]) - cy(ea[c]);
            if (d1x * d2y - d1y * d2x > 0) nx = c;
          }
        }
        if (nx < 0) break;
        e = nx;
      }
      rings.push(ring);
    }
    pr.rings = [];
    pr.runs = [];
    for (const ring of rings) {
      const m = ring.length;
      let start = -1;
      for (let i = 0; i < m; i++) if (eo[ring[i]] !== eo[ring[(i - 1 + m) % m]]) { start = i; break; }
      const rr = [];
      if (start < 0) {
        rr.push(makeRun(p, eo[ring[0]], ring.map((e) => ea[e]), true));
      } else {
        let o = eo[ring[start]], cur = [ea[ring[start]]];
        for (let k = 0; k < m; k++) {
          const e = ring[(start + k) % m];
          if (eo[e] !== o) { rr.push(makeRun(p, o, cur, false)); cur = [ea[e]]; o = eo[e]; }
          cur.push(eb[e]);
        }
        rr.push(makeRun(p, o, cur, false));
      }
      // кольцо целиком
      const ringPts = [];
      rr.forEach((run, i) => { const a = run.pts; for (let j = i === 0 ? 0 : 2; j < a.length; j += 2) ringPts.push(a[j], a[j + 1]); });
      pr.rings.push(Float32Array.from(ringPts));
      for (const run of rr) { run.inner = offsetPts(run.pts, run.closed, 1.7); pr.runs.push(run); }
    }
  }

  // --- море: грубая сетка, расстояние до берега, прибрежные морские клетки провинций ---
  const sea = new Uint8Array(SW * SH);
  for (let sy = 0; sy < SH; sy++) for (let sx = 0; sx < SW; sx++) {
    let w = 0;
    for (let dy = 0; dy < SF; dy++) for (let dx = 0; dx < SF; dx++) if (!land[(sy * SF + dy) * GW + sx * SF + dx]) w++;
    sea[sy * SW + sx] = w >= 2 ? 1 : 0;
  }
  for (const pr of provinces) {
    const set = new Set();
    if (pr.coastal) {
      for (const c of pr.cells) {
        const x = c % GW, y = (c / GW) | 0;
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= GW || ny >= GH || land[ny * GW + nx]) continue;
          const s = ((ny / SF) | 0) * SW + ((nx / SF) | 0);
          if (sea[s]) set.add(s);
        }
      }
    }
    pr.sea = [...set];
    if (!pr.sea.length) pr.coastal = false;
  }
  // расстояние до суши (фаска 1/√2, два прохода) — плавный градиент глубины
  const oceanDist = new Float32Array(N);
  {
    const INF = 1e9, D = Math.SQRT2;
    for (let i = 0; i < N; i++) oceanDist[i] = land[i] ? 0 : INF;
    for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
      const i = y * GW + x; let v = oceanDist[i];
      if (x > 0) v = Math.min(v, oceanDist[i - 1] + 1);
      if (y > 0) { v = Math.min(v, oceanDist[i - GW] + 1); if (x > 0) v = Math.min(v, oceanDist[i - GW - 1] + D); if (x < GW - 1) v = Math.min(v, oceanDist[i - GW + 1] + D); }
      oceanDist[i] = v;
    }
    for (let y = GH - 1; y >= 0; y--) for (let x = GW - 1; x >= 0; x--) {
      const i = y * GW + x; let v = oceanDist[i];
      if (x < GW - 1) v = Math.min(v, oceanDist[i + 1] + 1);
      if (y < GH - 1) { v = Math.min(v, oceanDist[i + GW] + 1); if (x < GW - 1) v = Math.min(v, oceanDist[i + GW + 1] + D); if (x > 0) v = Math.min(v, oceanDist[i + GW - 1] + D); }
      oceanDist[i] = Math.min(v, 80);
    }
  }

  // --- морские пути ---
  const sDist = new Int16Array(SW * SH), sPar = new Int32Array(SW * SH), sQ = new Int32Array(SW * SH);
  function seaBFS(pid, maxSteps) {
    sDist.fill(-1);
    let h = 0, t = 0;
    for (const s of provinces[pid].sea) { sDist[s] = 0; sPar[s] = -1; sQ[t++] = s; }
    while (h < t) {
      const c = sQ[h++], d = sDist[c];
      if (d >= maxSteps) continue;
      const x = c % SW, y = (c / SW) | 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= SW || ny >= SH) continue;
        const n = ny * SW + nx;
        if (!sea[n] || sDist[n] >= 0) continue;
        sDist[n] = d + 1; sPar[n] = c; sQ[t++] = n;
      }
    }
  }
  const reachCache = new Map();
  const coastalList = provinces.filter((p) => p.coastal);
  function seaReach(pid) {
    if (reachCache.has(pid)) return reachCache.get(pid);
    const out = [];
    if (provinces[pid].coastal) {
      seaBFS(pid, SEA_RANGE);
      for (const q of coastalList) {
        if (q.id === pid) continue;
        let best = -1;
        for (const s of q.sea) { const d = sDist[s]; if (d >= 0 && (best < 0 || d < best)) best = d; }
        if (best >= 0) out.push({ id: q.id, d: best * SEA_CELL });
      }
    }
    reachCache.set(pid, out);
    return out;
  }
  function seaPath(a, b) {
    const A = provinces[a], B = provinces[b];
    seaBFS(a, SEA_RANGE + 4);
    let best = -1, bd = 1e9;
    for (const s of B.sea) { const d = sDist[s]; if (d >= 0 && d < bd) { bd = d; best = s; } }
    if (best < 0) return [A.lx, A.ly, B.lx, B.ly];
    const cells = [];
    for (let c = best; c >= 0; c = sPar[c]) cells.push(c);
    cells.reverse();
    let pts = [A.lx, A.ly];
    for (const c of cells) pts.push(((c % SW) + 0.5) * SEA_CELL, (((c / SW) | 0) + 0.5) * SEA_CELL);
    pts.push(B.lx, B.ly);
    pts = simplify(pts, 7);
    return chaikin(pts, false, 2);
  }

  // волны — точки в открытом море
  const waves = [];
  for (let tries = 0; tries < 4000 && waves.length < 170; tries++) {
    const i = Math.floor(rand() * N);
    if (!land[i] && oceanDist[i] >= 5) waves.push({ x: ((i % GW) + 0.5) * CELL, y: (((i / GW) | 0) + 0.5) * CELL, ph: rand() * 6.28, s: 0.7 + rand() * 0.6 });
  }

  return {
    seed, thr, id, land, elev, mtn, moist, dt, oceanDist, provinces, landCount: L, sea,
    coastLines, innerBorders, waves, seaReach, seaPath,
    pick(wx, wy) {
      const gx = Math.floor(wx / CELL), gy = Math.floor(wy / CELL);
      if (gx < 0 || gy < 0 || gx >= GW || gy >= GH) return -1;
      const v = id[gy * GW + gx];
      if (v >= 0) return v;
      // промах по берегу — ближайшая суша в радиусе 2 клеток
      let best = -1, bd = 99;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
        const x = gx + dx, y = gy + dy;
        if (x < 0 || y < 0 || x >= GW || y >= GH) continue;
        const q = id[y * GW + x]; const d = dx * dx + dy * dy;
        if (q >= 0 && d < bd) { bd = d; best = q; }
      }
      return best;
    },
  };
}

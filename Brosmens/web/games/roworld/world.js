// BroWorld — карта мира в клетках (тайлах): реальная Земля 1000×500 из earthmap.js.
// Модуль чистый (без DOM). Клетка t = y * W + x. Соседство — 4 клетки (как в оригинале).
import { MAP_W, MAP_H, LON0, LAT0, DLON, DLAT, decodeEarth } from './earthmap.js';

export const W = MAP_W, H = MAP_H, N_TILES = W * H;
// классы местности (значения из earthmap.js; 5 — непроходимо, на «Мире» не используется)
export const T_OCEAN = 0, T_LAKE = 1, T_PLAINS = 2, T_HIGH = 3, T_MTN = 4, T_IMPASS = 5;
export const TERRAIN_NAME = ['Океан', 'Озеро', 'Равнина', 'Возвышенность', 'Горы', 'Ледник'];

export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

let cached = null;
export function buildWorld() {
  if (cached) return cached;
  const { cls, shade } = decodeEarth();
  const n = N_TILES;
  const terr = cls;
  const shore = new Uint8Array(n); // суша, у которой есть сосед-вода
  const wdist = new Uint8Array(n); // для воды: расстояние до суши (1..), 255 — далеко; для суши 0
  let landCount = 0;
  const q = new Int32Array(n);
  let qh = 0, qt = 0;
  wdist.fill(255);
  for (let t = 0; t < n; t++) {
    if (terr[t] < T_PLAINS) continue;
    landCount++;
    wdist[t] = 0;
    const x = t % W;
    if ((x > 0 && terr[t - 1] < T_PLAINS) || (x < W - 1 && terr[t + 1] < T_PLAINS) || (t >= W && terr[t - W] < T_PLAINS) || (t < n - W && terr[t + W] < T_PLAINS)) {
      shore[t] = 1; q[qt++] = t;
    }
  }
  // BFS по воде от берега, затем точное (евклидово) расстояние вблизи берега — мелководье без «ромбиков»
  while (qh < qt) {
    const t = q[qh++], d = wdist[t];
    if (d >= 12) continue;
    const x = t % W;
    if (x > 0 && wdist[t - 1] === 255) { wdist[t - 1] = d + 1; q[qt++] = t - 1; }
    if (x < W - 1 && wdist[t + 1] === 255) { wdist[t + 1] = d + 1; q[qt++] = t + 1; }
    if (t >= W && wdist[t - W] === 255) { wdist[t - W] = d + 1; q[qt++] = t - W; }
    if (t < n - W && wdist[t + W] === 255) { wdist[t + W] = d + 1; q[qt++] = t + W; }
  }
  const wfine = new Float32Array(n).fill(99); // евклидово расстояние до суши (только у берега, до 5)
  for (let t = 0; t < n; t++) {
    if (terr[t] >= T_PLAINS || wdist[t] > 6) continue;
    const x0 = t % W, y0 = (t / W) | 0;
    let best = 99;
    for (let dy = -5; dy <= 5; dy++) {
      const y = y0 + dy; if (y < 0 || y >= H) continue;
      for (let dx = -5; dx <= 5; dx++) {
        const x = x0 + dx; if (x < 0 || x >= W) continue;
        if (terr[y * W + x] >= T_PLAINS) { const d = dx * dx + dy * dy; if (d < best) best = d; }
      }
    }
    wfine[t] = Math.sqrt(best);
  }

  const isLand = (t) => terr[t] >= T_PLAINS && terr[t] !== T_IMPASS;
  const tileOf = (lon, lat) => {
    let x = Math.floor((((lon - LON0) % 360) + 360) % 360 / DLON);
    let y = Math.floor((LAT0 - lat) / DLAT);
    x = Math.max(0, Math.min(W - 1, x)); y = Math.max(0, Math.min(H - 1, y));
    return y * W + x;
  };
  // ближайшая клетка суши, удовлетворяющая ok(t), по спирали квадратов до maxR
  const nearest = (t0, maxR, ok) => {
    const x0 = t0 % W, y0 = (t0 / W) | 0;
    if (ok(t0)) return t0;
    for (let r = 1; r <= maxR; r++) {
      let best = -1, bd = 1e9;
      for (let dy = -r; dy <= r; dy++) {
        const y = y0 + dy; if (y < 0 || y >= H) continue;
        const step = dy === -r || dy === r ? 1 : 2 * r;
        for (let dx = -r; dx <= r; dx += step) {
          const x = x0 + dx; if (x < 0 || x >= W) continue;
          const t = y * W + x;
          if (!ok(t)) continue;
          const d = dx * dx + dy * dy;
          if (d < bd) { bd = d; best = t; }
        }
      }
      if (best >= 0) return best;
    }
    return -1;
  };
  cached = { W, H, n, terr, shade, shore, wdist, wfine, landCount, isLand, tileOf, nearest };
  return cached;
}

// BroWorld — отрисовка как в оригинале: два offscreen-холста по 1 пикселю на клетку (рельеф и территории),
// рисуются без сглаживания — вблизи границы ступенчатые. Территория: пастель владельца с прозрачностью 0.588
// и полоса границы в 1 клетку (темнее и насыщеннее). Подписи наций — в самом «толстом» месте территории
// (максимум карты расстояний), тёмный текст с обводкой цветом владельца, войска под именем, аватар у игроков.
import { W, H, N_TILES, T_LAKE, T_PLAINS, T_HIGH, T_MTN } from './world.js';
import { KIND, fmt, fmtT, fmtC, SPAWN_R, STRUCTS, SHIP, NUKES } from './game.js';
import { drawAvatar } from '../../shared/avatar.js';
import { graphicsLevel } from '../../shared/ui.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const CH = 50, CWN = Math.ceil(W / CH), CHN = Math.ceil(H / CH);
const hex = (h) => { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
const C = {
  ocean: hex('#4785B5'), shallow: hex('#5B9BC0'), shore: hex('#CCCB9E'),
  plains: hex('#BEDC8A'), high: hex('#DCCB9E'), mtn: hex('#E6E6E6'), imp: hex('#3C3C3C'),
};
const u32 = (rgb, a) => ((a << 24) | (rgb[2] << 16) | (rgb[1] << 8) | rgb[0]) >>> 0;
const mix = (a, b, k) => [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
const FILL_A = 150, BORDER_A = 235; // 0.588 и почти непрозрачная граница
// радиация как в оригинале: круглое ярко-зелёное пятно #1DDE0D с пиксельным «дизерингом» по краю (#1CAC1C);
// свежая воронка раскалена и мерцает (#0D660D…#33FF33), остывая — медленно «кипит» двухоктавным шумом и
// со временем оседает к #0D8C12; внутри чужой земли — оливковая #2E9A2E
const F_BRIGHT = hex('#1DDE0D'), F_DARK = hex('#0D8C12'), F_EDGE = hex('#1CAC1C'), F_OLIVE = hex('#2E9A2E');
const F_FL0 = hex('#0D660D'), F_FL1 = hex('#33FF33'), F_HOT = hex('#B9FF9C');
// гладкий шум по клеткам (значения в узлах решётки — хэш), для «кипения» радиации
const hash2 = (x, y) => (((Math.imul(x, 374761393) + Math.imul(y, 668265263)) ^ 0x5bd1e995) >>> 0);
function vnoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi;
  const h = (a, b) => { let v = hash2(a, b); v = Math.imul(v ^ (v >>> 13), 1274126177); return ((v ^ (v >>> 16)) >>> 0) / 4294967296; };
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
// пул частиц (обломки взрыва, искры радиации, дым перехвата): массивы фиксированного размера, без аллокаций в кадре
const PMAX = 1400;
const PCOL = ['#2b2118', '#4a3a2c', '#6b5a48', '#8d8d8d', '#ff9a3c', '#ffd27a', '#0D660D', '#1E9E1E', '#26CC26', '#33FF33', '#d9dde6'];

export class Renderer {
  constructor(canvas, dprFn) {
    this.cv = canvas; this.ctx = canvas.getContext('2d', { alpha: false });
    this.dprFn = dprFn;
    this.cam = { x: W / 2, y: H / 2, z: 1 };
    this.fly = null;
    this.fx = { rings: [], texts: [], booms: [] };
    this.blasts = [];   // недавние взрывы: зелёное свечение и искры, пока воронка горячая
    this.fronts = []; this.frontT = -9; // метки войск на фронтах атак (пересчёт раз в 200 мс, плавный переезд)
    this.broilT = 0; this.hotT = 0; this.hotI = 0;
    const F = Float32Array;
    this.pt = { x: new F(PMAX), y: new F(PMAX), vx: new F(PMAX), vy: new F(PMAX), life: new F(PMAX), max: new F(PMAX), size: new F(PMAX), drag: new F(PMAX), col: new Uint8Array(PMAX), n: 0 };
    this.shk = 0; this.shakeOn = true; this.sub = 0; // тряска камеры от взрывов; доля тика для плавного полёта ракет
    this.hl = 0; // подсвеченный игрок (цель)
    this.labels = []; this.labelT = -9;
    this.avatars = new Map();
    this.spawnMark = -1;
    this.pickMode = false; // этап выбора столицы: метки-квадратики вместо территорий
    this.ghost = null;     // призрак постройки при размещении
    this.alt = false;      // альтернативный вид: цвета по отношению к игроку
    this.me = null;
    this.dirty = new Uint8Array(CWN * CHN);
    this.resize();
  }

  resize() {
    this.dpr = this.dprFn();
    this.w = innerWidth; this.h = innerHeight;
    this.cv.width = Math.round(this.w * this.dpr); this.cv.height = Math.round(this.h * this.dpr);
    this.cv.style.width = this.w + 'px'; this.cv.style.height = this.h + 'px';
    this.minZ = Math.min(this.w / W, this.h / H) * 0.98;
    this.maxZ = 24;
    this.clampCam();
  }

  setWorld(world) {
    if (this.world === world) return;
    this.world = world;
    this.buildTerrain();
    const c = this.polCv = document.createElement('canvas'); c.width = W; c.height = H;
    this.polCtx = c.getContext('2d');
    this.polImg = this.polCtx.createImageData(W, H);
    this.pol32 = new Uint32Array(this.polImg.data.buffer);
  }
  setGame(game) {
    this.game = game;
    const n = game.P.length;
    this.cFill = new Uint32Array(n); this.cBorder = new Uint32Array(n); this.cFillHi = new Uint32Array(n); this.cBorderHi = new Uint32Array(n);
    this.cFillDef = new Uint32Array(n); this.cBorderDef = new Uint32Array(n);
    this.aFill = new Uint32Array(n); this.aBorder = new Uint32Array(n); this.aFillHi = new Uint32Array(n);
    this.sDark2 = [];
    for (let i = 1; i < n; i++) {
      const c = game.P[i].col;
      this.cFill[i] = u32(c.fill, FILL_A); this.cBorder[i] = u32(c.border, BORDER_A);
      this.cFillHi[i] = u32(c.fillHi, FILL_A + 18); this.cBorderHi[i] = u32(c.borderHi, 255);
      // под защитой оборонного поста: заливка темнее ×0.85, граница — «шахматка» ×0.7
      this.cFillDef[i] = u32(c.fill.map((v) => v * 0.85), FILL_A + 10); this.cBorderDef[i] = u32(c.border.map((v) => v * 0.7), BORDER_A);
      this.sDark2[i] = '#' + c.rgb.map((v) => Math.round(v * 0.55).toString(16).padStart(2, '0')).join('');
    }
    this.alt = false;
    this.hl = 0;
    this.fx = { rings: [], texts: [], booms: [] };
    this.blasts = []; this.fronts = []; this.pt.n = 0;
    this.fallBorn = new Float32Array(N_TILES);
    this.labels = []; this.labelT = -9;
    this.avatars.clear();
    this.paintAll();
  }

  // ---------- рельеф ----------
  buildTerrain() {
    const { terr, shade, shore, wfine } = this.world;
    const c = document.createElement('canvas'); c.width = W; c.height = H;
    const g = c.getContext('2d'), img = g.createImageData(W, H), d = img.data;
    for (let t = 0; t < N_TILES; t++) {
      const v = terr[t];
      let col;
      const nz = (((Math.imul(t, 2654435761) >>> 8) & 255) / 255 - 0.5);
      if (v < T_PLAINS) {
        if (v === T_LAKE) col = C.shallow;
        else {
          const e = wfine[t];
          const k = e < 99 ? clamp((4.2 - e) / 3.2, 0, 1) : 0;
          col = k ? mix(C.ocean, C.shallow, k * k * 0.95) : C.ocean;
        }
        const f = 1 + nz * 0.012;
        d[t * 4] = col[0] * f; d[t * 4 + 1] = col[1] * f; d[t * 4 + 2] = col[2] * f;
      } else {
        col = v === T_PLAINS ? C.plains : v === T_HIGH ? C.high : v === T_MTN ? C.mtn : C.imp;
        if (shore[t] && v !== T_MTN) col = mix(col, C.shore, 0.75);
        const f = 1 + shade[t] * 0.045 + nz * 0.035;
        d[t * 4] = clamp(col[0] * f, 0, 255); d[t * 4 + 1] = clamp(col[1] * f, 0, 255); d[t * 4 + 2] = clamp(col[2] * f, 0, 255);
      }
      d[t * 4 + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    this.terrCv = c;
  }

  // ---------- территории ----------
  paint(t) {
    const G = this.game, id = G.owner[t];
    let v = 0;
    if (id) {
      const hl = id === this.hl, edge = G.isBorderTile(t, id);
      if (this.alt) v = edge ? this.aBorder[id] : hl ? this.aFillHi[id] : this.aFill[id];
      else if (hl) v = edge ? this.cBorderHi[id] : this.cFillHi[id];
      else if (G.P[id].posts.length && G.defended(id, t)) v = edge ? ((((t % W) + ((t / W) | 0)) & 1) ? this.cBorderDef[id] : this.cBorder[id]) : this.cFillDef[id];
      else v = edge ? this.cBorder[id] : this.cFill[id];
    }
    if (!id && G.fall[t]) {
      if (!this.fallBorn[t]) this.fallBorn[t] = G.tickN * 0.1 + 0.01;
      v = this.falloutColor(t, G.fall[t]);
    } else if (this.fallBorn[t]) this.fallBorn[t] = 0;
    this.pol32[t] = v;
    this.dirty[(((t / W) | 0) / CH | 0) * CWN + ((t % W) / CH | 0)] = 1;
  }
  falloutColor(t, heat) {
    const G = this.game, f = G.fall, o = G.owner, x = t % W, y = (t / W) | 0;
    // край пятна: рядом чистая ничья земля или вода; «внутри чужой земли»: рядом ≥2 занятых клетки
    let edge = false, owned = 0;
    for (let dy = -1; dy <= 1; dy++) {
      const yy = y + dy; if (yy < 0 || yy >= H) continue;
      for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const xx = x + dx; if (xx < 0 || xx >= W) continue;
        const nb = yy * W + xx;
        if (o[nb]) owned++;
        else if (!f[nb] && (!dx || !dy)) edge = true;
      }
    }
    let base, a = 228;
    if (owned >= 2) { base = F_OLIVE; a = 215; }
    else if (edge) { const on = ((x + y) & 1) === 0; base = F_EDGE; a = on ? 235 : 105; }
    else {
      // «кипение»: два слоя шума медленно плывут; через ~1.5 мин пятно оседает к #0D8C12
      const tm = G.tickN * 0.1, born = this.fallBorn[t] || tm;
      const n = 0.62 * vnoise(x * 0.118 + tm * 0.035, y * 0.118 - tm * 0.02) + 0.38 * vnoise(x * 0.342 - tm * 0.06, y * 0.342 + tm * 0.045);
      const settle = clamp((tm - born - 12) / 80, 0, 1);
      base = mix(F_BRIGHT, F_DARK, clamp(settle * 0.62 + (n - 0.38) * 0.75, 0, 1));
    }
    if (heat > 1) { // раскалённая воронка мерцает и светится
      const k = Math.pow(heat / 255, 1.3);
      const fl = mix(F_FL0, F_FL1, Math.random());
      base = mix(mix(base, fl, 0.62 * k), F_HOT, 0.3 * k * k);
      a = Math.max(a, Math.round(200 + 55 * k));
    }
    return u32(base, a);
  }
  // мерцание горячих клеток (не больше ~9000 за проход) и медленное «кипение» видимой радиации
  animFallout(time, x0, x1, y0, y1, z) {
    const G = this.game;
    if (G.hot.length && time - this.hotT > 0.1) {
      this.hotT = time;
      const L = G.hot, n = Math.min(L.length, 9000);
      for (let k = 0; k < n; k++) { this.hotI = (this.hotI + 1) % L.length; const t = L[this.hotI]; if (G.fall[t] && !G.owner[t]) this.paint(t); }
    }
    if (G.fallout && z >= 1.1 && time - this.broilT > 0.25) {
      this.broilT = time;
      const f = G.fall, o = G.owner;
      for (let y = y0; y < y1; y++) for (let t = y * W + x0, e = y * W + x1; t < e; t++) if (f[t] === 1 && !o[t]) this.paint(t);
    }
  }
  // остывание воронок: перекрасить только эти клетки
  onHeat(list) { for (const t of list) this.paint(t); }
  paintAll() {
    for (let t = 0; t < N_TILES; t++) this.paint(t);
  }
  onTiles(buf, n) {
    for (let i = 0; i < n; i++) {
      const t = buf[i], x = t % W;
      this.paint(t);
      if (x > 0) this.paint(t - 1);
      if (x < W - 1) this.paint(t + 1);
      if (t >= W) this.paint(t - W);
      if (t < N_TILES - W) this.paint(t + W);
    }
  }
  // перерисовать квадрат вокруг клетки (зона оборонного поста появилась/пропала)
  repaintArea(t0, r) {
    const x0 = t0 % W, y0 = (t0 / W) | 0;
    for (let y = Math.max(0, y0 - r); y <= Math.min(H - 1, y0 + r); y++) for (let x = Math.max(0, x0 - r); x <= Math.min(W - 1, x0 + r); x++) this.paint(y * W + x);
  }
  // альтернативный вид (🌐): свои #00FF00, союзники #FFFF00, нейтральные #808080, враги #FF0000
  setAlt(on, aff) {
    this.alt = on;
    if (on && aff) {
      const C = { self: [0, 255, 0], ally: [255, 255, 0], neutral: [128, 128, 128], enemy: [255, 0, 0] };
      for (let i = 1; i < this.game.P.length; i++) {
        const c = C[aff(this.game.P[i])] || C.neutral;
        this.aFill[i] = u32(c, 120); this.aFillHi[i] = u32(c, 160); this.aBorder[i] = u32(c.map((v) => v * 0.6), 245);
      }
    }
    this.paintAll();
  }
  setHighlight(id) {
    if (id === this.hl) return;
    const old = this.hl;
    this.hl = id;
    const o = this.game.owner;
    for (let t = 0; t < N_TILES; t++) { const v = o[t]; if (v && (v === old || v === id)) this.paint(t); }
  }
  flushTiles() {
    const d = this.dirty;
    for (let i = 0; i < d.length; i++) {
      if (!d[i]) continue;
      d[i] = 0;
      const x = (i % CWN) * CH, y = ((i / CWN) | 0) * CH;
      this.polCtx.putImageData(this.polImg, 0, 0, x, y, Math.min(CH, W - x), Math.min(CH, H - y));
    }
  }

  // ---------- подписи: центр самой «толстой» части территории (раз в секунду, на сетке 2×) ----------
  computeLabels() {
    const G = this.game, o = G.owner, GW = W >> 1, GH = H >> 1, n = GW * GH;
    if (!this.dtOwn) { this.dtOwn = new Uint16Array(n); this.dtD = new Uint16Array(n); }
    const own = this.dtOwn, d = this.dtD;
    for (let gy = 0; gy < GH; gy++) for (let gx = 0; gx < GW; gx++) own[gy * GW + gx] = o[(gy * 2) * W + gx * 2];
    for (let c = 0; c < n; c++) {
      const id = own[c];
      if (!id) { d[c] = 0; continue; }
      const x = c % GW;
      d[c] = (x === 0 || x === GW - 1 || c < GW || c >= n - GW || own[c - 1] !== id || own[c + 1] !== id || own[c - GW] !== id || own[c + GW] !== id) ? 10 : 65000;
    }
    for (let c = GW; c < n; c++) {
      const id = own[c]; if (!id || d[c] <= 10) continue;
      const x = c % GW; let v = d[c];
      if (x > 0 && own[c - 1] === id && d[c - 1] + 10 < v) v = d[c - 1] + 10;
      if (own[c - GW] === id && d[c - GW] + 10 < v) v = d[c - GW] + 10;
      if (x > 0 && own[c - GW - 1] === id && d[c - GW - 1] + 14 < v) v = d[c - GW - 1] + 14;
      if (x < GW - 1 && own[c - GW + 1] === id && d[c - GW + 1] + 14 < v) v = d[c - GW + 1] + 14;
      d[c] = v;
    }
    const np = G.P.length;
    const bestD = new Uint16Array(np), bestC = new Int32Array(np).fill(-1);
    for (let c = n - GW - 1; c >= 0; c--) {
      const id = own[c]; if (!id) continue;
      let v = d[c];
      if (v > 10) {
        const x = c % GW;
        if (x < GW - 1 && own[c + 1] === id && d[c + 1] + 10 < v) v = d[c + 1] + 10;
        if (c + GW < n && own[c + GW] === id && d[c + GW] + 10 < v) v = d[c + GW] + 10;
        if (x < GW - 1 && c + GW + 1 < n && own[c + GW + 1] === id && d[c + GW + 1] + 14 < v) v = d[c + GW + 1] + 14;
        if (x > 0 && c + GW - 1 < n && own[c + GW - 1] === id && d[c + GW - 1] + 14 < v) v = d[c + GW - 1] + 14;
        d[c] = v;
      }
      if (v > bestD[id]) { bestD[id] = v; bestC[id] = c; }
    }
    const out = [];
    for (let i = 1; i < np; i++) {
      const p = G.P[i];
      if (!p.alive || !p.tiles) continue;
      let x, y, r;
      if (bestC[i] >= 0) { const c = bestC[i]; x = (c % GW) * 2 + 1; y = ((c / GW) | 0) * 2 + 1; r = bestD[i] / 10 * 2; }
      else if (p.spawn >= 0 && o[p.spawn] === i) { x = p.spawn % W + 0.5; y = ((p.spawn / W) | 0) + 0.5; r = 1.5; }
      else continue;
      const old = this.labels.find((L) => L.p === p);
      out.push({ p, x, y, r, sx: old ? old.sx : x, sy: old ? old.sy : y, sr: old ? old.sr : r });
    }
    this.labels = out;
  }

  avatarOf(p) {
    if (!p.skin) return null;
    let c = this.avatars.get(p.id);
    if (c) return c;
    const a = document.createElement('canvas'); a.width = a.height = 64;
    drawAvatar(a, p.skin, { headOnly: true, bg: '#d8dce4' });
    c = document.createElement('canvas'); c.width = c.height = 64;
    const g = c.getContext('2d');
    g.save(); g.beginPath(); g.arc(32, 32, 29, 0, 7); g.clip(); g.drawImage(a, 0, 0); g.restore();
    g.lineWidth = 4; g.strokeStyle = p.col.borderCss; g.beginPath(); g.arc(32, 32, 29, 0, 7); g.stroke();
    this.avatars.set(p.id, c);
    return c;
  }

  // ---------- камера ----------
  clampCam() {
    const c = this.cam;
    c.z = clamp(c.z, this.minZ, this.maxZ);
    const hw = this.w / 2 / c.z, hh = this.h / 2 / c.z, mx = (this.w * 0.35) / c.z, my = (this.h * 0.35) / c.z;
    c.x = 2 * hw >= W ? W / 2 : clamp(c.x, Math.min(W / 2, hw - mx), Math.max(W / 2, W - hw + mx));
    c.y = 2 * hh >= H ? H / 2 : clamp(c.y, Math.min(H / 2, hh - my), Math.max(H / 2, H - hh + my));
  }
  s2w(sx, sy) { const c = this.cam; return [c.x + (sx - this.w / 2) / c.z, c.y + (sy - this.h / 2) / c.z]; }
  w2s(wx, wy) { const c = this.cam; return [(wx - c.x) * c.z + this.w / 2, (wy - c.y) * c.z + this.h / 2]; }
  tileAt(sx, sy) {
    const [x, y] = this.s2w(sx, sy);
    const tx = Math.floor(x), ty = Math.floor(y);
    if (tx < 0 || ty < 0 || tx >= W || ty >= H) return -1;
    return ty * W + tx;
  }
  tileCenter(t) { return [(t % W) + 0.5, ((t / W) | 0) + 0.5]; }
  zoomAt(sx, sy, f) {
    const [wx, wy] = this.s2w(sx, sy);
    this.cam.z = clamp(this.cam.z * f, this.minZ, this.maxZ);
    this.cam.x = wx - (sx - this.w / 2) / this.cam.z;
    this.cam.y = wy - (sy - this.h / 2) / this.cam.z;
    this.fly = null;
    this.clampCam();
  }
  pan(dx, dy) { this.cam.x -= dx / this.cam.z; this.cam.y -= dy / this.cam.z; this.fly = null; this.clampCam(); }
  flyTo(x, y, z, dur = 0.6) { this.fly = { x0: this.cam.x, y0: this.cam.y, z0: this.cam.z, x, y, z: clamp(z, this.minZ, this.maxZ), t: 0, dur }; }
  fitAll() { this.cam.z = this.minZ; this.cam.x = W / 2; this.cam.y = H / 2; this.clampCam(); }

  // ---------- эффекты ----------
  ring(x, y, color = '#fff', r1 = 30, dur = 0.5) { if (this.fx.rings.length < 40) this.fx.rings.push({ x, y, color, r1, dur, t: 0 }); }
  text(x, y, s, color = '#fff', size = 14, dur = 1.4) { if (this.fx.texts.length < 30) this.fx.texts.push({ x, y, s, color, size, dur, t: 0 }); }
  // ядерный взрыв: белая вспышка ~120 мс, раскалённое ядро, ударная волна до 1.5× радиуса за 1.5 с (толщина 4% радиуса),
  // обломки ~6 с (из пула), зелёное свечение и искры над свежей воронкой, пока она горячая
  boom(x, y, r, big = true, vis = true) {
    if (this.fx.booms.length < 70) this.fx.booms.push({ x, y, r, big, t: 0, dur: big ? 1.5 : 0.9 });
    this.blasts.push({ x, y, r, t: 0, dur: big ? 10.5 : 7, big, acc: 0 });
    if (this.blasts.length > 40) this.blasts.shift();
    if (!vis) return;
    const g = graphicsLevel(), q = g <= 3 ? 0.35 : g <= 7 ? 0.7 : 1;
    const n = Math.round((big ? 150 : 7) * q);
    for (let i = 0; i < n; i++) {
      const a = Math.random() * 6.283, d = Math.random() * r * 0.35, sp = r * (0.35 + Math.random() * 1.15);
      const ember = Math.random() < 0.35;
      this.spawnP(x + Math.cos(a) * d, y + Math.sin(a) * d, Math.cos(a) * sp, Math.sin(a) * sp, 2 + Math.random() * 4, 1.4 + Math.random() * 2.2, 1.1 + Math.random() * 0.8, ember ? 4 + (Math.random() * 2 | 0) : Math.random() * 4 | 0);
    }
  }
  // перехват ПВО: маленькая ударная волна 40 px за 0.8 с и клубок дыма
  intercept(x, y) {
    this.ring(x, y, '#ffffff', 40, 0.8);
    for (let i = 0; i < 10; i++) { const a = Math.random() * 6.283, sp = 1.5 + Math.random() * 3; this.spawnP(x, y, Math.cos(a) * sp, Math.sin(a) * sp, 0.6 + Math.random() * 0.6, 2 + Math.random() * 2, 2.2, Math.random() < 0.3 ? 5 : 10); }
  }
  spawnP(x, y, vx, vy, life, size, drag, col) {
    const P = this.pt;
    if (P.n >= PMAX) return;
    const i = P.n++;
    P.x[i] = x; P.y[i] = y; P.vx[i] = vx; P.vy[i] = vy; P.life[i] = life; P.max[i] = life; P.size[i] = size; P.drag[i] = drag; P.col[i] = col;
  }
  drawParticles(toS, z, dt) {
    const P = this.pt, ctx = this.ctx, w = this.w, h = this.h;
    let cur = -1;
    for (let i = 0; i < P.n;) {
      P.life[i] -= dt;
      if (P.life[i] <= 0) { // удалить: поменять с последней
        const j = --P.n;
        P.x[i] = P.x[j]; P.y[i] = P.y[j]; P.vx[i] = P.vx[j]; P.vy[i] = P.vy[j]; P.life[i] = P.life[j]; P.max[i] = P.max[j]; P.size[i] = P.size[j]; P.drag[i] = P.drag[j]; P.col[i] = P.col[j];
        continue;
      }
      const k = Math.exp(-P.drag[i] * dt);
      P.vx[i] *= k; P.vy[i] *= k;
      P.x[i] += P.vx[i] * dt; P.y[i] += P.vy[i] * dt;
      const sx = (P.x[i] - this.cam.x) * z + w / 2, sy = (P.y[i] - this.cam.y) * z + h / 2;
      if (sx > -10 && sy > -10 && sx < w + 10 && sy < h + 10) {
        const f = P.life[i] / P.max[i], c = P.col[i];
        // угольки остывают: оранжевые → тёмные
        const ci = c === 4 && f < 0.5 ? 1 : c === 5 && f < 0.6 ? 4 : c;
        if (ci !== cur) { cur = ci; ctx.fillStyle = PCOL[ci]; }
        ctx.globalAlpha = Math.min(1, f * 1.6) * (c >= 6 && c <= 9 ? 0.9 : 0.85);
        const s = P.size[i];
        ctx.fillRect(sx - s / 2, sy - s / 2, s, s);
      }
      i++;
    }
    ctx.globalAlpha = 1;
  }
  // свечение свежих воронок (#26F226) и мерцающие искры над радиацией
  drawBlasts(toS, z, dt) {
    const ctx = this.ctx, G = this.game, f = G.fall, gl = graphicsLevel();
    ctx.globalCompositeOperation = 'lighter';
    for (let i = this.blasts.length - 1; i >= 0; i--) {
      const b = this.blasts[i]; b.t += dt;
      if (b.t >= b.dur) { this.blasts.splice(i, 1); continue; }
      const k = Math.pow(1 - b.t / b.dur, 1.4), [x, y] = toS(b.x, b.y), R = Math.max(5, b.r * z * 1.25);
      if (x < -R || y < -R || x > this.w + R || y > this.h + R) continue;
      const gr = ctx.createRadialGradient(x, y, 0, x, y, R);
      gr.addColorStop(0, `rgba(38,242,38,${(0.42 * k).toFixed(3)})`); gr.addColorStop(0.7, `rgba(38,242,38,${(0.16 * k).toFixed(3)})`); gr.addColorStop(1, 'rgba(38,242,38,0)');
      ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(x, y, R, 0, 7); ctx.fill();
      // искры: тем чаще, чем горячее воронка
      b.acc += dt * (b.big ? 70 : 6) * k * (gl <= 3 ? 0.3 : gl <= 7 ? 0.65 : 1);
      while (b.acc >= 1) {
        b.acc--;
        const a = Math.random() * 6.283, d = Math.sqrt(Math.random()) * b.r * 0.95, px = b.x + Math.cos(a) * d, py = b.y + Math.sin(a) * d;
        const t = Math.floor(py) * W + Math.floor(px);
        if (t < 0 || t >= N_TILES || !f[t]) continue;
        this.spawnP(px, py, (Math.random() - 0.5) * 0.6, -0.4 - Math.random() * 1.2, 0.5 + Math.random() * 0.8, 1.5 + Math.random() * 1.6, 0.5, 6 + (Math.random() * 4 | 0));
      }
    }
    ctx.globalCompositeOperation = 'source-over';
  }
  shake(a) { if (this.shakeOn) this.shk = Math.max(this.shk, a); }

  // ---------- кадр ----------
  draw(time, dt) {
    if (!this.world) return;
    if (this.fly) {
      const f = this.fly; f.t += dt / f.dur;
      const k = f.t >= 1 ? 1 : 1 - Math.pow(1 - f.t, 3);
      const lz = Math.log(f.z0) + (Math.log(f.z) - Math.log(f.z0)) * k;
      this.cam.z = Math.exp(lz);
      this.cam.x = f.x0 + (f.x - f.x0) * k; this.cam.y = f.y0 + (f.y - f.y0) * k;
      this.clampCam();
      if (f.t >= 1) this.fly = null;
    }
    const G = this.game;
    const { ctx, cam, dpr, w, h } = this, z = cam.z;
    const x0 = Math.max(0, Math.floor(cam.x - w / 2 / z)), x1 = Math.min(W, Math.ceil(cam.x + w / 2 / z) + 1);
    const y0 = Math.max(0, Math.floor(cam.y - h / 2 / z)), y1 = Math.min(H, Math.ceil(cam.y + h / 2 / z) + 1);
    if (G) {
      if (G.fallout) this.animFallout(time, x0, x1, y0, y1, z);
      this.flushTiles();
      if (time - this.labelT > 1) { this.labelT = time; this.computeLabels(); }
      if (time - this.frontT > 0.2) { this.frontT = time; this.computeFronts(); }
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#3C3C3C'; ctx.fillRect(0, 0, this.cv.width, this.cv.height);
    const k = z * dpr;
    let ox = 0, oy = 0;
    if (this.shk > 0.3) { ox = (Math.random() - 0.5) * this.shk; oy = (Math.random() - 0.5) * this.shk; this.shk *= Math.exp(-dt * 7); } else this.shk = 0;
    ctx.setTransform(k, 0, 0, k, (w / 2 - cam.x * z + ox) * dpr, (h / 2 - cam.y * z + oy) * dpr);
    ctx.imageSmoothingEnabled = z < 1.5;
    ctx.imageSmoothingQuality = 'low';
    if (x1 > x0 && y1 > y0) {
      ctx.drawImage(this.terrCv, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
      if (G) ctx.drawImage(this.polCv, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
    }
    ctx.imageSmoothingEnabled = true;

    // ---------- экранные слои ----------
    ctx.setTransform(dpr, 0, 0, dpr, ox * dpr, oy * dpr);
    const toS = (x, y) => [(x - cam.x) * z + w / 2, (y - cam.y) * z + h / 2];
    if (G) {
      if (this.blasts.length) this.drawBlasts(toS, z, dt);
      if (this.pickMode) this.drawSpawnMarks(toS, z, time);
      this.drawLabels(toS, z, time, dt);
      this.drawStructs(toS, z, time); // значки построек поверх подписей — иначе столицу закрывает имя
      this.drawUnits(toS, z, time);
      if (this.fronts.length) this.drawFronts(toS, z, dt);
      if (G.nukes.length || G.samShots.length) this.drawNukes(toS, z, time);
      if (this.fx.booms.length) this.drawBooms(toS, z, dt);
      if (this.pt.n) this.drawParticles(toS, z, dt);
      if (this.ghost) this.drawGhost(toS, z, time);
    }
    // кольца
    for (let i = this.fx.rings.length - 1; i >= 0; i--) {
      const r = this.fx.rings[i]; r.t += dt;
      if (r.t >= r.dur) { this.fx.rings.splice(i, 1); continue; }
      const q = r.t / r.dur, [x, y] = toS(r.x, r.y);
      ctx.lineWidth = 2.5; ctx.strokeStyle = r.color; ctx.globalAlpha = 1 - q;
      ctx.beginPath(); ctx.arc(x, y, 4 + r.r1 * q, 0, 7); ctx.stroke();
    }
    ctx.globalAlpha = 1;
    // всплывающий текст
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
    for (let i = this.fx.texts.length - 1; i >= 0; i--) {
      const t = this.fx.texts[i]; t.t += dt;
      if (t.t >= t.dur) { this.fx.texts.splice(i, 1); continue; }
      const q = t.t / t.dur, [x, y] = toS(t.x, t.y);
      ctx.globalAlpha = q < 0.1 ? q / 0.1 : q > 0.6 ? 1 - (q - 0.6) / 0.4 : 1;
      ctx.font = `800 ${t.size}px system-ui,sans-serif`;
      ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(20,20,30,.85)';
      const yy = y - 10 - q * 20;
      ctx.strokeText(t.s, x, yy); ctx.fillStyle = t.color; ctx.fillText(t.s, x, yy);
    }
    ctx.globalAlpha = 1;
  }

  // ---------- метки войск на фронтах атак (как в оригинале: «107K» на границе, синие — твои, красные — по тебе) ----------
  // раз в 200 мс: клетки фронта каждой атаки с твоим участием → кластеры на сетке 6×6 → метка в центре кластера
  computeFronts() {
    const G = this.game, me = this.me, o = G.owner, CELL = 6, GW = Math.ceil(W / CELL);
    const old = this.fronts, out = [];
    if (me) for (const a of G.attacks) {
      if (a.dead || a.retreatAt >= 0 || a.troops < 1) continue;
      const inc = a.target === me;
      if (a.owner !== me && !inc) continue;
      const tid = a.target ? a.target.id : 0;
      const cells = new Map();
      for (const t of a.front) {
        if (o[t] !== tid) continue;
        const x = t % W, y = (t / W) | 0, key = ((y / CELL) | 0) * GW + ((x / CELL) | 0);
        let c = cells.get(key);
        if (!c) { c = { n: 0, sx: 0, sy: 0, comp: -1 }; cells.set(key, c); }
        c.n++; c.sx += x; c.sy += y;
      }
      if (!cells.size) continue;
      const comps = [];
      for (const [key, c] of cells) {
        if (c.comp >= 0) continue;
        const cm = { n: 0, sx: 0, sy: 0, list: [] }, st = [key];
        c.comp = comps.length;
        while (st.length) {
          const kk = st.pop(), cc = cells.get(kk);
          cm.n += cc.n; cm.sx += cc.sx; cm.sy += cc.sy; cm.list.push(cc);
          const cx = kk % GW;
          for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
            if ((!dx && !dy) || cx + dx < 0 || cx + dx >= GW) continue;
            const nk = kk + dy * GW + dx, nc = cells.get(nk);
            if (nc && nc.comp < 0) { nc.comp = comps.length; st.push(nk); }
          }
        }
        comps.push(cm);
      }
      comps.sort((p, q) => q.n - p.n);
      for (let i = 0; i < comps.length && i < 3; i++) {
        const cm = comps[i];
        if (i && cm.n < 4) break;
        // метка — на клетках фронта: центр той ячейки кластера, что ближе всего к его центру
        const mx = cm.sx / cm.n, my = cm.sy / cm.n;
        let bx = mx, by = my, bd = 1e18;
        for (const cc of cm.list) { const x = cc.sx / cc.n, y = cc.sy / cc.n, d = (x - mx) ** 2 + (y - my) ** 2; if (d < bd) { bd = d; bx = x; by = y; } }
        out.push({ a, inc, owner: a.owner, x: bx + 0.5, y: by + 0.5, dx: bx + 0.5, dy: by + 0.5, al: 0, gone: false });
      }
    }
    // плавный переезд: каждая новая метка забирает ближайшую старую той же атаки
    const used = new Set();
    for (const L of out) {
      let best = null, bd = 30 * 30;
      for (const P of old) {
        if (P.gone || P.a !== L.a || used.has(P)) continue;
        const d = (P.dx - L.x) ** 2 + (P.dy - L.y) ** 2;
        if (d < bd) { bd = d; best = P; }
      }
      if (best) { used.add(best); L.dx = best.dx; L.dy = best.dy; L.al = best.al; }
    }
    for (const P of old) if (!used.has(P) && P.al > 0.05) { P.gone = true; out.push(P); }
    this.fronts = out;
  }
  drawFronts(toS, z, dt) {
    const ctx = this.ctx, w = this.w, h = this.h, fs = h > 600 ? 17 : 15;
    ctx.font = `800 ${fs}px "Rubik","Segoe UI",system-ui,sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
    const k = Math.min(1, dt * 7);
    for (let i = this.fronts.length - 1; i >= 0; i--) {
      const L = this.fronts[i];
      if (L.gone) { L.al -= dt * 4; if (L.al <= 0) { this.fronts.splice(i, 1); continue; } }
      else { L.al = Math.min(1, L.al + dt * 4); L.dx += (L.x - L.dx) * k; L.dy += (L.y - L.dy) * k; }
      const [x, y] = toS(L.dx, L.dy);
      if (x < -40 || y < -20 || x > w + 40 || y > h + 20) continue;
      const s = fmtT(L.a.troops);
      ctx.globalAlpha = L.al;
      ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(12,16,28,.92)'; ctx.strokeText(s, x, y);
      ctx.fillStyle = L.inc ? '#F87171' : '#3FA9F5'; ctx.fillText(s, x, y);
    }
    ctx.globalAlpha = 1;
  }

  // ---------- этап выбора: метки столиц (скруглённые квадратики) ----------
  drawSpawnMarks(toS, z, time) {
    const G = this.game, ctx = this.ctx, w = this.w, h = this.h;
    const s = clamp(2 * SPAWN_R * z, 7, 46), rr = s * 0.28;
    const me = this.me;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
    for (let i = 1; i < G.P.length; i++) {
      const p = G.P[i];
      if (!p.alive || p.spawn < 0 || p === me) continue;
      const [x, y] = toS((p.spawn % W) + 0.5, ((p.spawn / W) | 0) + 0.5);
      if (x < -s || y < -s || x > w + s || y > h + s) continue;
      ctx.beginPath(); ctx.roundRect(x - s / 2, y - s / 2, s, s, rr);
      if (p.kind === KIND.TRIBE) { ctx.fillStyle = 'rgba(201,198,191,.42)'; ctx.fill(); ctx.lineWidth = 1.3; ctx.strokeStyle = '#8E8B84'; ctx.stroke(); }
      else { ctx.fillStyle = p.color; ctx.fill(); ctx.lineWidth = 1.6; ctx.strokeStyle = p.col.borderCss; ctx.stroke(); }
      if (z >= 2.6 && p.kind !== KIND.TRIBE) {
        const fs = clamp(z * 2.2, 9, 15);
        ctx.font = `800 ${fs}px "Rubik","Segoe UI",system-ui,sans-serif`;
        ctx.lineWidth = 3; ctx.strokeStyle = p.col.css; ctx.strokeText(p.name, x, y - s / 2 - fs * 0.7);
        ctx.fillStyle = '#3A3A3A'; ctx.fillText(p.name, x, y - s / 2 - fs * 0.7);
      }
    }
    if (me && me.spawn >= 0) {
      const [x, y] = toS((me.spawn % W) + 0.5, ((me.spawn / W) | 0) + 0.5);
      // пульсирующее кольцо вокруг своей столицы (10→30 клеток оригинала)
      const ph = (time * 0.7) % 1, R = Math.max((5 + 10 * ph) * z, 12 + 26 * ph);
      const gr = ctx.createRadialGradient(x, y, R * 0.55, x, y, R);
      gr.addColorStop(0, 'rgba(215,38,61,0)'); gr.addColorStop(0.8, `rgba(215,38,61,${0.32 * (1 - ph)})`); gr.addColorStop(1, 'rgba(215,38,61,0)');
      ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(x, y, R, 0, 7); ctx.fill();
      ctx.lineWidth = 1.5; ctx.strokeStyle = `rgba(215,38,61,${0.85 * (1 - ph)})`; ctx.beginPath(); ctx.arc(x, y, R, 0, 7); ctx.stroke();
      const s2 = s * 1.15;
      ctx.beginPath(); ctx.roundRect(x - s2 / 2, y - s2 / 2, s2, s2, s2 * 0.28);
      ctx.fillStyle = '#F9B6C3'; ctx.fill(); ctx.lineWidth = 2.2; ctx.strokeStyle = '#D7263D'; ctx.stroke();
    }
  }

  // ---------- постройки: значки-фигуры (город — круг, порт — пятиугольник, завод — шестиугольник,
  // оборона — щит, ПВО — квадрат, шахта — треугольник); при отдалении — только фигуры-точки ----------
  shape(type, x, y, r) {
    const ctx = this.ctx;
    ctx.beginPath();
    if (type === 'city') { ctx.arc(x, y, r, 0, 7); return; }
    if (type === 'port' || type === 'factory') {
      const n = type === 'port' ? 5 : 6, a0 = type === 'port' ? -Math.PI / 2 : 0;
      for (let i = 0; i < n; i++) { const a = a0 + (i * 2 * Math.PI) / n; ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); }
      ctx.closePath(); return;
    }
    if (type === 'post') {
      ctx.moveTo(x, y - r); ctx.lineTo(x + r * 0.92, y - r * 0.62); ctx.lineTo(x + r * 0.86, y + r * 0.1);
      ctx.quadraticCurveTo(x + r * 0.62, y + r * 0.78, x, y + r * 1.02); ctx.quadraticCurveTo(x - r * 0.62, y + r * 0.78, x - r * 0.86, y + r * 0.1);
      ctx.lineTo(x - r * 0.92, y - r * 0.62); ctx.closePath(); return;
    }
    if (type === 'sam') { ctx.roundRect(x - r * 0.78, y - r * 0.78, r * 1.56, r * 1.56, r * 0.22); return; }
    if (type === 'silo') { ctx.moveTo(x, y - r * 0.95); ctx.lineTo(x + r * 0.95, y + r * 0.68); ctx.lineTo(x - r * 0.95, y + r * 0.68); ctx.closePath(); return; }
    ctx.arc(x, y, r, 0, 7);
  }
  glyph(type, x, y, r) {
    const ctx = this.ctx, u = r / 8;
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#fff';
    if (type === 'city') { ctx.fillRect(x - 4.8 * u, y - 0.8 * u, 2.8 * u, 5 * u); ctx.fillRect(x - 1.4 * u, y - 4.6 * u, 2.8 * u, 8.8 * u); ctx.fillRect(x + 2 * u, y - 2.4 * u, 2.8 * u, 6.6 * u); return; }
    if (type === 'port') {
      ctx.lineWidth = 1.5 * u; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.arc(x, y - 3.4 * u, 1.3 * u, 0, 7); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x, y - 2 * u); ctx.lineTo(x, y + 4 * u); ctx.moveTo(x - 2.4 * u, y - 0.6 * u); ctx.lineTo(x + 2.4 * u, y - 0.6 * u); ctx.stroke();
      ctx.beginPath(); ctx.arc(x, y + 0.6 * u, 3.6 * u, 0.25, Math.PI - 0.25); ctx.stroke(); return;
    }
    if (type === 'factory') {
      ctx.beginPath(); ctx.moveTo(x - 4.6 * u, y + 3.8 * u); ctx.lineTo(x - 4.6 * u, y - 0.4 * u); ctx.lineTo(x - 1.8 * u, y - 2.2 * u); ctx.lineTo(x - 1.8 * u, y - 0.4 * u);
      ctx.lineTo(x + 1 * u, y - 2.2 * u); ctx.lineTo(x + 1 * u, y - 0.4 * u); ctx.lineTo(x + 2.4 * u, y - 0.4 * u); ctx.lineTo(x + 2.4 * u, y - 4.4 * u); ctx.lineTo(x + 4.6 * u, y - 4.4 * u); ctx.lineTo(x + 4.6 * u, y + 3.8 * u); ctx.closePath(); ctx.fill(); return;
    }
    if (type === 'post') { // башня с зубцами
      ctx.fillRect(x - 2.6 * u, y - 1.6 * u, 5.2 * u, 5.6 * u);
      for (let i = 0; i < 3; i++) ctx.fillRect(x - 3.4 * u + i * 2.6 * u, y - 3.6 * u, 1.6 * u, 2.2 * u);
      return;
    }
    if (type === 'sam') { ctx.beginPath(); ctx.moveTo(x - 4.6 * u, y - 4 * u); ctx.lineTo(x + 4.6 * u, y - 4 * u); ctx.lineTo(x + 2.6 * u, y - 1.4 * u); ctx.lineTo(x - 2.6 * u, y - 1.4 * u); ctx.closePath(); ctx.fill(); ctx.fillRect(x - 0.8 * u, y - 1.4 * u, 1.6 * u, 4.4 * u); ctx.fillRect(x - 3 * u, y + 3 * u, 6 * u, 1.6 * u); return; }
    if (type === 'silo') {
      ctx.beginPath(); ctx.moveTo(x, y - 3.6 * u); ctx.quadraticCurveTo(x + 1.8 * u, y - 1.6 * u, x + 1.6 * u, y + 2.6 * u); ctx.lineTo(x - 1.6 * u, y + 2.6 * u); ctx.quadraticCurveTo(x - 1.8 * u, y - 1.6 * u, x, y - 3.6 * u); ctx.fill();
      ctx.beginPath(); ctx.moveTo(x - 1.6 * u, y + 1 * u); ctx.lineTo(x - 3 * u, y + 3.4 * u); ctx.lineTo(x - 1.6 * u, y + 3 * u); ctx.moveTo(x + 1.6 * u, y + 1 * u); ctx.lineTo(x + 3 * u, y + 3.4 * u); ctx.lineTo(x + 1.6 * u, y + 3 * u); ctx.fill();
    }
  }
  icon(type, x, y, r, fill, line, dots, alpha = 1) {
    const ctx = this.ctx;
    ctx.globalAlpha = alpha;
    this.shape(type, x, y, r);
    ctx.fillStyle = fill; ctx.fill();
    ctx.lineWidth = dots ? 1 : 1.4; ctx.strokeStyle = line; ctx.stroke();
    if (!dots) { ctx.globalAlpha = alpha * 0.98; this.glyph(type, type === 'silo' ? x : x, type === 'silo' ? y + r * 0.12 : y, r * (type === 'sam' ? 1 : type === 'post' ? 0.8 : 0.85)); }
    ctx.globalAlpha = 1;
  }
  levelPill(x, y, lv) {
    const ctx = this.ctx, s = String(lv), wd = 7 + s.length * 5;
    ctx.fillStyle = '#111'; ctx.beginPath(); ctx.roundRect(x - wd / 2, y - 6, wd, 12, 6); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = '800 9px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(s, x, y + 0.5);
  }
  progBar(x, y, f, z) {
    const ctx = this.ctx, bw = Math.max(16, 7 * z), bh = Math.max(3, 1.5 * z);
    ctx.fillStyle = '#000'; ctx.fillRect(x - bw / 2 - 1, y - 1, bw + 2, bh + 2);
    ctx.fillStyle = f < 0.25 ? '#E81919' : f < 0.5 ? '#F07A19' : f < 0.75 ? '#CAE70F' : '#2CEF12';
    ctx.fillRect(x - bw / 2, y, bw * f, bh);
  }
  drawStructs(toS, z, time) {
    const G = this.game, ctx = this.ctx, w = this.w, h = this.h;
    const dots = z < 2.4; // оригинал: ниже зума 1.2 (у нас клетка вдвое крупнее) — только фигуры
    const K = { city: 1, port: 1.08, factory: 1.08, post: 1, sam: 1.25, silo: 1.35 };
    const base = dots ? clamp(z * 1.5, 2.6, 4.2) : clamp(z * 1.45, 7, 13);
    for (const s of G.structs) {
      const [x, y] = toS((s.tile % W) + 0.5, ((s.tile / W) | 0) + 0.5);
      if (x < -20 || y < -20 || x > w + 20 || y > h + 20) continue;
      const own = G.P[s.owner];
      const r = base * K[s.type];
      const busy = !s.built || s.pending;
      this.icon(s.type, x, y, r, own.col.dark, dots ? this.sDark2[s.owner] : 'rgba(255,255,255,.9)', dots, !s.built ? 0.55 : 1);
      if (s.level > 1 && z >= 1.4) this.levelPill(x, y - r - 6, s.level);
      if (busy && z >= 1.6) {
        const T = Math.max(1, s.doneAt - (s.startAt ?? s.born));
        this.progBar(x, y + r + 3, clamp(1 - (s.doneAt - G.tickN) / T, 0, 1), z);
      }
    }
  }
  // десант и военные корабли
  drawUnits(toS, z, time) {
    const G = this.game, ctx = this.ctx, w = this.w, h = this.h, me = this.me;
    for (const b of G.boats) {
      const [bx, by] = G.boatPos(b), [x, y] = toS(bx, by);
      const mine = b.owner === me, vsMe = b.target === me, P = b.pts;
      if ((mine || vsMe) && b.n > 1) { // точечная линия пути (вперёд — до берега высадки, при возврате — домой)
        ctx.setLineDash([2, 5]); ctx.lineWidth = 1.6; ctx.lineCap = 'round'; ctx.strokeStyle = mine ? 'rgba(255,255,255,.85)' : 'rgba(255,110,130,.9)';
        ctx.beginPath(); ctx.moveTo(x, y);
        const step = Math.max(1, Math.round(4 / Math.max(0.4, z)));
        if (b.back) for (let i = Math.floor(b.i); i >= 0; i -= step) { const [px, py] = toS(P[i * 2], P[i * 2 + 1]); ctx.lineTo(px, py); }
        else {
          for (let i = Math.ceil(b.i); i < b.n; i += step) { const [px, py] = toS(P[i * 2], P[i * 2 + 1]); ctx.lineTo(px, py); }
          const [ex, ey] = toS(P[b.n * 2 - 2], P[b.n * 2 - 1]); ctx.lineTo(ex, ey);
          const [lx, ly] = toS((b.land % W) + 0.5, ((b.land / W) | 0) + 0.5); ctx.lineTo(lx, ly);
        }
        ctx.stroke(); ctx.setLineDash([]); ctx.lineCap = 'butt';
        if (!b.back) { const [lx, ly] = toS((b.land % W) + 0.5, ((b.land / W) | 0) + 0.5); ctx.fillStyle = mine ? 'rgba(255,255,255,.9)' : 'rgba(255,110,130,.95)'; ctx.beginPath(); ctx.arc(lx, ly, 3, 0, 7); ctx.fill(); }
      }
      if (x < -20 || y < -20 || x > w + 20 || y > h + 20) continue;
      // корпус транспорта по курсу: острый нос, палуба, белая обводка и пенный след
      const i0 = Math.max(0, Math.min(b.n - 2, Math.floor(b.i)));
      let ang = Math.atan2(P[i0 * 2 + 3] - P[i0 * 2 + 1], P[i0 * 2 + 2] - P[i0 * 2]);
      if (b.back) ang += Math.PI;
      const s = clamp(z * 1.9, 6, 10.5);
      ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
      ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(-s * 1.1, -s * 0.35); ctx.lineTo(-s * 2.3, -s * 0.9); ctx.moveTo(-s * 1.1, s * 0.35); ctx.lineTo(-s * 2.3, s * 0.9); ctx.stroke();
      ctx.fillStyle = b.owner.col.dark; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.3;
      ctx.beginPath(); ctx.moveTo(s * 1.25, 0); ctx.lineTo(s * 0.45, -s * 0.55); ctx.lineTo(-s * 1.1, -s * 0.55); ctx.lineTo(-s * 1.1, s * 0.55); ctx.lineTo(s * 0.45, s * 0.55); ctx.closePath();
      ctx.fill(); ctx.stroke();
      ctx.fillStyle = 'rgba(255,255,255,.85)'; ctx.fillRect(-s * 0.7, -s * 0.22, s * 1.1, s * 0.44);
      ctx.restore();
      if (z >= 2.2) {
        ctx.font = '800 10px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.lineWidth = 2.6; ctx.strokeStyle = 'rgba(15,20,35,.85)'; ctx.strokeText(fmtT(b.troops), x, y + s + 8);
        ctx.fillStyle = mine ? '#3FA9F5' : vsMe ? '#F87171' : '#fff'; ctx.fillText(fmtT(b.troops), x, y + s + 8);
      }
    }
    for (const s of G.ships) {
      const [sx0, sy0] = G.shipXY(s);
      s.rx = s.rx === undefined ? sx0 : s.rx + (sx0 - s.rx) * 0.15; s.ry = s.ry === undefined ? sy0 : s.ry + (sy0 - s.ry) * 0.15;
      const [x, y] = toS(s.rx, s.ry);
      if (G.tickN - s.shotAt < 4 && s.shot) { // выстрел
        const [tx, ty] = toS(s.shot[0], s.shot[1]);
        ctx.strokeStyle = 'rgba(255,230,140,.9)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(tx, ty); ctx.stroke();
        ctx.fillStyle = 'rgba(255,240,200,.8)'; ctx.beginPath(); ctx.arc(tx, ty, 4, 0, 7); ctx.fill();
      }
      if (x < -20 || y < -20 || x > w + 20 || y > h + 20) continue;
      const r = clamp(z * 1.6, 5.5, 11), hostile = me && s.owner !== me && !G.allied(me, s.owner);
      ctx.beginPath();
      for (let i = 0; i < 8; i++) { const a = Math.PI / 8 + (i * Math.PI) / 4; ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); }
      ctx.closePath();
      ctx.fillStyle = hostile && Math.sin(time * 6) > 0.4 ? '#8a2b2b' : '#5d6472'; ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = s.owner.col.css; ctx.stroke();
      const u = r / 8; ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.moveTo(x - 5 * u, y + 0.8 * u); ctx.lineTo(x + 5 * u, y + 0.8 * u); ctx.lineTo(x + 3.4 * u, y + 3.4 * u); ctx.lineTo(x - 3.4 * u, y + 3.4 * u); ctx.closePath(); ctx.fill();
      ctx.fillRect(x - 2 * u, y - 1.8 * u, 4 * u, 2.2 * u); ctx.fillRect(x - 0.5 * u, y - 4.2 * u, 1 * u, 2.6 * u);
      if (z >= 1.6) { // полоска здоровья
        const bw = Math.max(18, 5.5 * z), f = clamp(s.hp / SHIP.hp, 0, 1);
        ctx.fillStyle = '#000'; ctx.fillRect(x - bw / 2 - 1, y - r - 7, bw + 2, 5);
        ctx.fillStyle = f > 0.5 ? '#2CEF12' : f > 0.25 ? '#CAE70F' : '#E81919'; ctx.fillRect(x - bw / 2, y - r - 6, bw * f, 3);
      }
    }
  }
  // призрак постройки: следует за пальцем, «прилипает» к допустимой клетке; красный — нельзя
  drawGhost(toS, z, time) {
    const g = this.ghost, ctx = this.ctx;
    if (g.tile < 0) return;
    if (g.nuke) { this.drawNukeGhost(g, toS, z, time); return; }
    const [x, y] = toS((g.tile % W) + 0.5, ((g.tile / W) | 0) + 0.5);
    const rng = g.type === 'post' || g.type === 'sam' ? STRUCTS[g.type].range : 0;
    if (rng) {
      ctx.save(); ctx.translate(x, y); ctx.rotate(time * 0.24);
      ctx.setLineDash([12, 6]); ctx.lineWidth = 1.5; ctx.strokeStyle = g.ok ? 'rgba(255,255,255,.8)' : 'rgba(255,90,90,.8)';
      ctx.beginPath(); ctx.arc(0, 0, rng * z, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }
    const r = clamp(z * 1.6, 12, 17) * (g.type === 'sam' ? 1.2 : g.type === 'silo' ? 1.3 : 1);
    if (g.type === 'warship') {
      ctx.globalAlpha = 0.85; ctx.fillStyle = g.ok ? '#5d6472' : '#c0392b'; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.globalAlpha = 1;
    } else this.icon(g.type, x, y, r, g.ok ? (this.me ? this.me.col.dark : '#555') : '#D93A3A', g.ok ? 'rgba(255,255,255,.95)' : '#ffb3b3', false, g.ok ? 0.92 : 0.55);
    if (g.up && g.ok) this.levelPill(x, y - r - 7, g.up.level + 1);
    ctx.font = '800 11px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const label = g.ok ? (g.up ? `↑ ${fmtC(g.cost)}` : fmtC(g.cost)) : g.why || '✕';
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(15,20,35,.9)'; ctx.strokeText(label, x, y + r + 10);
    ctx.fillStyle = g.ok ? (g.afford ? '#FBE99F' : '#E06A8C') : '#ff9a9a'; ctx.fillText(label, x, y + r + 10);
  }

  // ---------- ядерные ракеты: траектория, метка цели, перехват ПВО ----------
  drawNukes(toS, z, time) {
    const G = this.game, ctx = this.ctx, me = this.me, w = this.w, h = this.h, sub = this.sub;
    // ракеты ПВО: белый след от ПВО к точке встречи
    for (const s of G.samShots) {
      const f = clamp((G.tickN + sub - s.at) / Math.max(1, s.hit - s.at), 0, 1);
      const [ax, ay] = toS(s.fx, s.fy), [bx, by] = toS(s.x, s.y);
      const hx = ax + (bx - ax) * f, hy = ay + (by - ay) * f, f0 = Math.max(0, f - 0.35);
      ctx.strokeStyle = 'rgba(255,255,255,.9)'; ctx.lineWidth = 1.8; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(ax + (bx - ax) * f0, ay + (by - ay) * f0); ctx.lineTo(hx, hy); ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(hx, hy, 2.4, 0, 7); ctx.fill();
    }
    ctx.lineCap = 'butt';
    for (const n of G.nukes) {
      if (n.dead) continue;
      const own = n.owner === me, ally = !own && me && G.allied(me, n.owner);
      const col = own ? '#00FF00' : ally ? '#FFFF00' : '#FF0000';
      const big = n.type === 'atom' || n.type === 'hydro';
      if (big) {
        // метка цели: заливка 25% и пунктирное кольцо радиуса взрыва, вращается 20°/с
        const [tx, ty] = toS(n.tx, n.ty), R = NUKES[n.type].outer * z;
        if (tx > -R && ty > -R && tx < w + R && ty < h + R) {
          ctx.globalAlpha = 0.25; ctx.fillStyle = col; ctx.beginPath(); ctx.arc(tx, ty, R, 0, 7); ctx.fill();
          ctx.globalAlpha = 0.85 + 0.1 * Math.sin(time * 6);
          ctx.save(); ctx.translate(tx, ty); ctx.rotate(time * 0.349);
          ctx.setLineDash([12, 6]); ctx.lineWidth = 1.5; ctx.strokeStyle = col; ctx.beginPath(); ctx.arc(0, 0, Math.max(4, R), 0, 7); ctx.stroke();
          ctx.restore(); ctx.setLineDash([]); ctx.globalAlpha = 1;
        }
      }
      if (n.type !== 'warhead' && !n.wait) this.nukeTrail(n, toS, z);
    }
    for (const n of G.nukes) {
      if (n.dead || n.wait > 0) continue;
      const d = Math.min(n.len, n.d + n.speed * sub);
      const [px, py] = G.pathAt(n, d), [qx, qy] = G.pathAt(n, Math.min(n.len, d + 2));
      const [x, y] = toS(px, py);
      if (x < -30 || y < -30 || x > w + 30 || y > h + 30) continue;
      const a = Math.atan2(qy - py, qx - px), tgt = G.targetable(n, px, py);
      if (n.type === 'warhead' && z < 2.5) { // издалека боеголовки — огненные чёрточки с хвостом
        const L = 9, ex = x - Math.cos(a) * L, ey = y - Math.sin(a) * L;
        const gr = ctx.createLinearGradient(ex, ey, x, y);
        gr.addColorStop(0, 'rgba(255,120,40,0)'); gr.addColorStop(1, 'rgba(255,220,120,.95)');
        ctx.strokeStyle = gr; ctx.lineWidth = 2.2; ctx.beginPath(); ctx.moveTo(ex, ey); ctx.lineTo(x, y); ctx.stroke();
        ctx.fillStyle = '#fff4c8'; ctx.beginPath(); ctx.arc(x, y, 1.6, 0, 7); ctx.fill();
        continue;
      }
      const s = n.type === 'warhead' ? 5 : n.type === 'mirv' ? 9 : 7.5;
      ctx.globalAlpha = tgt ? 1 : 0.6;
      if (n.type === 'hydro' || n.type === 'mirv') { // оранжевое свечение 2.2× размера
        const gr = ctx.createRadialGradient(x, y, 0, x, y, s * 2.2);
        gr.addColorStop(0, 'rgba(255,184,38,.85)'); gr.addColorStop(1, 'rgba(255,184,38,0)');
        ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(x, y, s * 2.2, 0, 7); ctx.fill();
      }
      ctx.save(); ctx.translate(x, y); ctx.rotate(a);
      ctx.fillStyle = n.owner.col.dark; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(s, 0); ctx.lineTo(s * 0.35, -s * 0.38); ctx.lineTo(-s * 0.8, -s * 0.38); ctx.lineTo(-s, -s * 0.75); ctx.lineTo(-s, s * 0.75); ctx.lineTo(-s * 0.8, s * 0.38); ctx.lineTo(s * 0.35, s * 0.38); ctx.closePath();
      ctx.fill(); ctx.stroke();
      if (n.type !== 'warhead') { ctx.fillStyle = 'rgba(255,190,90,.9)'; ctx.beginPath(); ctx.moveTo(-s, -s * 0.3); ctx.lineTo(-s * (1.6 + 0.3 * Math.random()), 0); ctx.lineTo(-s, s * 0.3); ctx.fill(); }
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }
  // оставшаяся часть пути: штрих 8/4, где ракету может сбить ПВО, точки 2/6 — где не может; белая линия 2.5 px
  // с серой обводкой #8C8C8C; после точки, где её собьёт ПВО, — красная #FF5050 (обводка #965A5A)
  nukeTrail(n, toS, z) {
    const G = this.game, ctx = this.ctx, step = Math.max(3, 9 / Math.max(0.5, z));
    const segs = [], hit = n.dHit ?? 1e9;
    let cur = null;
    for (let d = n.d; ; d += step) {
      const dd = Math.min(n.len, d), [x, y] = G.pathAt(n, dd), tg = G.targetable(n, x, y), red = dd > hit, [sx, sy] = toS(x, y);
      if (!cur || cur.tg !== tg || cur.red !== red) { const c = { tg, red, pts: cur ? [cur.pts[cur.pts.length - 1]] : [] }; segs.push(c); cur = c; }
      cur.pts.push([sx, sy]);
      if (dd >= n.len) break;
    }
    for (const pass of [0, 1]) {
      ctx.lineWidth = pass ? 2.5 : 4;
      for (const c of segs) {
        if (c.pts.length < 2) continue;
        ctx.strokeStyle = pass ? (c.red ? '#FF5050' : 'rgba(255,255,255,.95)') : c.red ? 'rgba(150,90,90,.85)' : 'rgba(140,140,140,.75)';
        ctx.setLineDash(c.tg ? [8, 4] : [2, 6]);
        ctx.beginPath(); ctx.moveTo(c.pts[0][0], c.pts[0][1]);
        for (let i = 1; i < c.pts.length; i++) ctx.lineTo(c.pts[i][0], c.pts[i][1]);
        ctx.stroke();
      }
    }
    ctx.setLineDash([]);
  }
  drawBooms(toS, z, dt) {
    const ctx = this.ctx;
    for (let i = this.fx.booms.length - 1; i >= 0; i--) {
      const b = this.fx.booms[i]; b.t += dt;
      if (b.t >= b.dur) { this.fx.booms.splice(i, 1); continue; }
      const [x, y] = toS(b.x, b.y), R = Math.max(6, b.r * z);
      if (b.t < 0.12) { ctx.globalAlpha = 1 - b.t / 0.12; ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(x, y, R * 1.05, 0, 7); ctx.fill(); }
      const q = b.t / b.dur;
      if (b.t < 0.5) { // раскалённое ядро
        const gr = ctx.createRadialGradient(x, y, 0, x, y, R * 0.8);
        gr.addColorStop(0, 'rgba(255,250,210,.95)'); gr.addColorStop(0.45, 'rgba(255,170,60,.7)'); gr.addColorStop(1, 'rgba(255,90,30,0)');
        ctx.globalAlpha = 1 - b.t / 0.5; ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(x, y, R * 0.8, 0, 7); ctx.fill();
      }
      ctx.globalAlpha = (1 - q) * 0.9; ctx.strokeStyle = '#ffffff'; ctx.lineWidth = Math.max(2, R * 0.04);
      ctx.beginPath(); ctx.arc(x, y, R * 1.5 * (1 - Math.pow(1 - q, 2)), 0, 7); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
  // прицел ядерного удара: два полупрозрачных красных круга (радиус взрыва и полного уничтожения)
  drawNukeGhost(g, toS, z, time) {
    const ctx = this.ctx, N = NUKES[g.type === 'mirv' ? 'warhead' : g.type];
    const [x, y] = toS((g.tile % W) + 0.5, ((g.tile / W) | 0) + 0.5);
    const Ro = Math.max(5, N.outer * z), Ri = Math.max(3, N.inner * z);
    ctx.globalAlpha = g.ok ? 0.3 : 0.18;
    ctx.fillStyle = '#E05050'; ctx.beginPath(); ctx.arc(x, y, Ro, 0, 7); ctx.fill();
    ctx.fillStyle = '#B81E2E'; ctx.beginPath(); ctx.arc(x, y, Ri, 0, 7); ctx.fill();
    ctx.globalAlpha = g.ok ? 0.95 : 0.5; ctx.lineWidth = 1; ctx.strokeStyle = '#FF3B3B';
    ctx.beginPath(); ctx.arc(x, y, Ro, 0, 7); ctx.stroke(); ctx.beginPath(); ctx.arc(x, y, Ri, 0, 7); ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.6; // перекрестие
    ctx.beginPath(); ctx.moveTo(x - 7, y); ctx.lineTo(x + 7, y); ctx.moveTo(x, y - 7); ctx.lineTo(x, y + 7); ctx.stroke();
    ctx.font = '800 11px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const label = g.ok ? fmtC(g.cost) + (g.self ? ' ⚠' : '') : g.why || '✕', ly = y + Math.min(Ro + 12, 22);
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(15,20,35,.9)'; ctx.strokeText(label, x, ly);
    ctx.fillStyle = g.ok ? (g.self ? '#FFB347' : g.afford ? '#FBE99F' : '#E06A8C') : '#ff9a9a'; ctx.fillText(label, x, ly);
  }

  drawLabels(toS, z, time, dt) {
    const G = this.game, ctx = this.ctx, w = this.w, h = this.h;
    const minPx = 0.008 * Math.max(w, h);
    const lead = G.leader();
    const pulse = 0.5 + 0.5 * Math.sin(time * 5);
    ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
    const k = Math.min(1, dt * 4);
    for (const L of this.labels) {
      const p = L.p;
      if (!p.alive) continue;
      L.sx += (L.x - L.sx) * k; L.sy += (L.y - L.sy) * k; L.sr += (L.r - L.sr) * k;
      const name = p.name, len = Math.max(3, name.length);
      const av = p.skin ? 1.25 : 0;
      let fsT = Math.min(L.sr * 0.95, (2.5 * L.sr) / (0.56 * len + av + 0.2));
      let fs = fsT * z;
      const tiny = p.isPlayer && p.tiles < 2000; // маленького себя легко найти: всегда видно + красное свечение
      if (fs < minPx && !p.isPlayer) continue;
      fs = clamp(fs, p.isPlayer ? 12 : 10, 120);
      const [x, y] = toS(L.sx, L.sy);
      if (x < -fs * 8 || x > w + fs * 8 || y < -fs * 2 || y > h + fs * 2) continue;
      ctx.font = `800 ${fs.toFixed(1)}px "Rubik","Segoe UI",system-ui,sans-serif`;
      const tw = ctx.measureText(name).width;
      const aw = av ? fs * 1.15 : 0, gap = av ? fs * 0.22 : 0;
      const x0 = x - (aw + gap + tw) / 2, ty = y - fs * 0.18;
      const small = fs < 15;
      if (av) {
        const img = this.avatarOf(p);
        if (img) ctx.drawImage(img, x0, ty - aw / 2, aw, aw);
      }
      ctx.textAlign = 'left';
      if (tiny) { ctx.shadowColor = '#FF1F1A'; ctx.shadowBlur = 10 + 14 * pulse; }
      ctx.lineWidth = Math.max(2.2, fs * 0.2);
      ctx.strokeStyle = small || tiny ? '#ffffff' : p.col.css;
      ctx.strokeText(name, x0 + aw + gap, ty);
      if (tiny) { ctx.strokeStyle = `rgba(255,31,26,${0.35 + 0.55 * pulse})`; ctx.lineWidth = Math.max(1.5, fs * 0.1); ctx.strokeText(name, x0 + aw + gap, ty); ctx.shadowBlur = 0; ctx.shadowColor = 'transparent'; }
      ctx.fillStyle = p.kind === KIND.TRIBE ? '#4A4A4A' : '#3A3A3A';
      ctx.fillText(name, x0 + aw + gap, ty);
      // войска под именем
      const fs2 = fs * 0.6, cx = x0 + aw + gap + tw / 2;
      ctx.font = `800 ${fs2.toFixed(1)}px "Rubik","Segoe UI",system-ui,sans-serif`;
      ctx.textAlign = 'center';
      const tr = fmtT(p.troops), yy = ty + fs * 0.78;
      ctx.lineWidth = Math.max(2, fs2 * 0.2); ctx.strokeStyle = small ? '#ffffff' : p.col.css;
      ctx.strokeText(tr, cx, yy); ctx.fillStyle = '#3A3A3A'; ctx.fillText(tr, cx, yy);
      // корона лидера
      const crown = p === lead && p.tiles > 300;
      if (crown) this.crown(cx, ty - fs * 0.95, Math.max(10, fs * 0.75));
      // красная плашка «ПРЕДАТЕЛЬ» над именем (30 с после разрыва союза)
      if (G.isTraitor(p)) {
        const ts = clamp(fs * 0.42, 8.5, 15), py = ty - fs * (crown ? 1.55 : 0.92);
        ctx.font = `900 ${ts.toFixed(1)}px "Rubik","Segoe UI",system-ui,sans-serif`;
        const pw = ctx.measureText('ПРЕДАТЕЛЬ').width + ts * 1.1;
        ctx.fillStyle = '#EE4062'; ctx.beginPath(); ctx.roundRect(cx - pw / 2, py - ts * 0.75, pw, ts * 1.5, ts * 0.5); ctx.fill();
        ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(255,255,255,.7)'; ctx.stroke();
        ctx.fillStyle = '#fff'; ctx.fillText('ПРЕДАТЕЛЬ', cx, py + 0.5);
      }
    }
    ctx.textAlign = 'center';
  }

  crown(x, y, s) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.moveTo(x - s * 0.5, y + s * 0.3); ctx.lineTo(x - s * 0.55, y - s * 0.25); ctx.lineTo(x - s * 0.25, y + s * 0.02);
    ctx.lineTo(x, y - s * 0.38); ctx.lineTo(x + s * 0.25, y + s * 0.02); ctx.lineTo(x + s * 0.55, y - s * 0.25); ctx.lineTo(x + s * 0.5, y + s * 0.3);
    ctx.closePath();
    ctx.fillStyle = '#F5C542'; ctx.strokeStyle = '#7A5A0A'; ctx.lineWidth = Math.max(1.2, s * 0.08);
    ctx.fill(); ctx.stroke();
  }
}

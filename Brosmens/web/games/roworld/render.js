// BroWorld — отрисовка как в оригинале: два offscreen-холста по 1 пикселю на клетку (рельеф и территории),
// рисуются без сглаживания — вблизи границы ступенчатые. Территория: пастель владельца с прозрачностью 0.588
// и полоса границы в 1 клетку (темнее и насыщеннее). Подписи наций — в самом «толстом» месте территории
// (максимум карты расстояний), тёмный текст с обводкой цветом владельца, войска под именем, аватар у игроков.
import { W, H, N_TILES, T_LAKE, T_PLAINS, T_HIGH, T_MTN } from './world.js';
import { KIND, fmt, fmtT, SPAWN_R, STRUCTS, SHIP } from './game.js';
import { drawAvatar } from '../../shared/avatar.js';

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

export class Renderer {
  constructor(canvas, dprFn) {
    this.cv = canvas; this.ctx = canvas.getContext('2d', { alpha: false });
    this.dprFn = dprFn;
    this.cam = { x: W / 2, y: H / 2, z: 1 };
    this.fly = null;
    this.fx = { rings: [], texts: [] };
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
    this.fx = { rings: [], texts: [] };
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
    this.pol32[t] = v;
    this.dirty[(((t / W) | 0) / CH | 0) * CWN + ((t % W) / CH | 0)] = 1;
  }
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
    if (G) {
      this.flushTiles();
      if (time - this.labelT > 1) { this.labelT = time; this.computeLabels(); }
    }
    const { ctx, cam, dpr, w, h } = this, z = cam.z;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#3C3C3C'; ctx.fillRect(0, 0, this.cv.width, this.cv.height);
    const k = z * dpr;
    ctx.setTransform(k, 0, 0, k, (w / 2 - cam.x * z) * dpr, (h / 2 - cam.y * z) * dpr);
    ctx.imageSmoothingEnabled = z < 1.5;
    ctx.imageSmoothingQuality = 'low';
    const x0 = Math.max(0, Math.floor(cam.x - w / 2 / z)), x1 = Math.min(W, Math.ceil(cam.x + w / 2 / z) + 1);
    const y0 = Math.max(0, Math.floor(cam.y - h / 2 / z)), y1 = Math.min(H, Math.ceil(cam.y + h / 2 / z) + 1);
    if (x1 > x0 && y1 > y0) {
      ctx.drawImage(this.terrCv, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
      if (G) ctx.drawImage(this.polCv, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
    }
    ctx.imageSmoothingEnabled = true;

    // ---------- экранные слои ----------
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const toS = (x, y) => [(x - cam.x) * z + w / 2, (y - cam.y) * z + h / 2];
    if (G) {
      if (this.pickMode) this.drawSpawnMarks(toS, z, time);
      this.drawStructs(toS, z, time);
      this.drawUnits(toS, z, time);
      this.drawLabels(toS, z, time, dt);
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
      const mine = b.owner === me, vsMe = b.target === me;
      if ((mine || vsMe) && b.path.length > 1) { // пунктир пути
        ctx.setLineDash([2, 5]); ctx.lineWidth = 1.6; ctx.strokeStyle = mine ? 'rgba(255,255,255,.85)' : 'rgba(255,110,130,.9)';
        ctx.beginPath(); ctx.moveTo(x, y);
        const P = b.path, step = Math.max(1, Math.round(3 / Math.max(0.4, z)));
        if (b.back) for (let i = Math.floor(b.i); i >= 0; i -= step) { const [px, py] = toS((P[i] % W) + 0.5, ((P[i] / W) | 0) + 0.5); ctx.lineTo(px, py); }
        else {
          for (let i = Math.ceil(b.i); i < P.length; i += step) { const [px, py] = toS((P[i] % W) + 0.5, ((P[i] / W) | 0) + 0.5); ctx.lineTo(px, py); }
          const [lx, ly] = toS((b.land % W) + 0.5, ((b.land / W) | 0) + 0.5); ctx.lineTo(lx, ly);
        }
        ctx.stroke(); ctx.setLineDash([]);
      }
      if (x < -20 || y < -20 || x > w + 20 || y > h + 20) continue;
      const s = clamp(z * 1.7, 4.5, 10);
      ctx.fillStyle = b.owner.col.dark; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(x - s, y - s * 0.15); ctx.lineTo(x + s, y - s * 0.15); ctx.lineTo(x + s * 0.6, y + s * 0.55); ctx.lineTo(x - s * 0.6, y + s * 0.55); ctx.closePath(); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.fillRect(x - s * 0.1, y - s * 0.95, s * 0.2, s * 0.8);
      ctx.beginPath(); ctx.moveTo(x + s * 0.1, y - s * 0.95); ctx.lineTo(x + s * 0.65, y - s * 0.35); ctx.lineTo(x + s * 0.1, y - s * 0.35); ctx.fill();
      if (z >= 2.2) {
        ctx.font = '800 10px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.lineWidth = 2.6; ctx.strokeStyle = 'rgba(15,20,35,.85)'; ctx.strokeText(fmtT(b.troops), x, y + s + 7);
        ctx.fillStyle = mine ? '#3FA9F5' : vsMe ? '#F87171' : '#fff'; ctx.fillText(fmtT(b.troops), x, y + s + 7);
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
    const [x, y] = toS((g.tile % W) + 0.5, ((g.tile / W) | 0) + 0.5);
    const rng = g.type === 'post' || g.type === 'sam' ? STRUCTS[g.type].range : 0;
    if (rng) {
      ctx.save(); ctx.translate(x, y); ctx.rotate(time * 0.24);
      ctx.setLineDash([12, 6]); ctx.lineWidth = 1.5; ctx.strokeStyle = g.ok ? 'rgba(255,255,255,.8)' : 'rgba(255,90,90,.8)';
      ctx.beginPath(); ctx.arc(0, 0, rng * z, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }
    const r = clamp(z * 1.45, 9, 14) * (g.type === 'sam' ? 1.25 : g.type === 'silo' ? 1.35 : 1);
    if (g.type === 'warship') {
      ctx.globalAlpha = 0.85; ctx.fillStyle = g.ok ? '#5d6472' : '#c0392b'; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.globalAlpha = 1;
    } else this.icon(g.type, x, y, r, g.ok ? (this.me ? this.me.col.dark : '#555') : '#D93A3A', g.ok ? 'rgba(255,255,255,.95)' : '#ffb3b3', false, g.ok ? 0.92 : 0.55);
    if (g.up && g.ok) this.levelPill(x, y - r - 7, g.up.level + 1);
    ctx.font = '800 11px "Rubik",system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const label = g.ok ? (g.up ? `↑ ${fmt(g.cost)}` : fmt(g.cost)) : g.why || '✕';
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(15,20,35,.9)'; ctx.strokeText(label, x, y + r + 10);
    ctx.fillStyle = g.ok ? (g.afford ? '#FBE99F' : '#E06A8C') : '#ff9a9a'; ctx.fillText(label, x, y + r + 10);
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
      if (p === lead && p.tiles > 300) this.crown(cx, ty - fs * 0.95, Math.max(10, fs * 0.75));
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

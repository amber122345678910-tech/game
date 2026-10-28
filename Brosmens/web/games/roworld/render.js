// BroWorld — отрисовка Canvas 2D: кэш карты (океан, суша с текстурой, рельеф, значки местности) в offscreen canvas,
// поверх — политическая заливка/границы наций (Path2D по нациям, пересобираются только при смене владельцев),
// армии, эффекты, подписи. Камера: перетаскивание, зум.
import { WW, WH, GW, GH, CELL, mulberry32 } from './world.js';
import { TERRAIN } from './game.js';
import { star } from './nations.js';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

function pathFrom(pts, closed) {
  const p = new Path2D();
  p.moveTo(pts[0], pts[1]);
  for (let i = 2; i < pts.length; i += 2) p.lineTo(pts[i], pts[i + 1]);
  if (closed) p.closePath();
  return p;
}
function hexMix(h, k, j = 0) { // слегка варьировать цвет
  const n = parseInt(h.slice(1), 16);
  const f = (c) => clamp(Math.round(c * (1 + k) + j), 0, 255);
  return `rgb(${f((n >> 16) & 255)},${f((n >> 8) & 255)},${f(n & 255)})`;
}

// ---------- значки построек (спрайты) ----------
function sprite(draw) {
  const c = document.createElement('canvas'); c.width = c.height = 40;
  const g = c.getContext('2d');
  g.translate(20, 20);
  g.fillStyle = '#fff'; g.strokeStyle = 'rgba(0,0,0,.55)'; g.lineWidth = 2.5;
  g.beginPath(); g.arc(0, 0, 17, 0, 7); g.fill(); g.stroke();
  draw(g);
  return c;
}
function makeSprites() {
  return {
    capital: (() => {
      const c = document.createElement('canvas'); c.width = c.height = 40;
      const g = c.getContext('2d'); g.translate(20, 21);
      g.fillStyle = '#3b2a00'; star(g, 0, 0, 19, 8.5); g.fillStyle = '#ffc928'; star(g, 0, -0.5, 15.5, 6.8);
      g.fillStyle = 'rgba(255,255,255,.55)'; g.beginPath(); g.arc(-3, -5, 2.6, 0, 7); g.fill();
      return c;
    })(),
    city: sprite((g) => {
      g.fillStyle = '#3d4a5c';
      g.fillRect(-11, -2, 7, 12); g.fillRect(-3, -10, 7, 20); g.fillRect(5, -5, 7, 15);
      g.fillStyle = '#ffe082';
      for (const [x, y] of [[-9, 1], [-9, 5], [-1, -7], [-1, -3], [-1, 1], [-1, 5], [7, -2], [7, 2], [7, 6]]) g.fillRect(x, y, 2.4, 2.4);
    }),
    port: sprite((g) => {
      g.strokeStyle = '#1d4f91'; g.lineWidth = 2.6; g.lineCap = 'round';
      g.beginPath(); g.arc(0, -9, 3, 0, 7); g.stroke();
      g.beginPath(); g.moveTo(0, -6); g.lineTo(0, 11); g.moveTo(-6, -3); g.lineTo(6, -3); g.stroke();
      g.beginPath(); g.arc(0, 2, 10, 0.25, Math.PI - 0.25); g.stroke();
      g.fillStyle = '#1d4f91';
      g.beginPath(); g.moveTo(-12, 3); g.lineTo(-7, 2); g.lineTo(-10, 7); g.fill();
      g.beginPath(); g.moveTo(12, 3); g.lineTo(7, 2); g.lineTo(10, 7); g.fill();
    }),
    factory: sprite((g) => {
      g.fillStyle = '#5d4037';
      g.beginPath(); g.moveTo(-12, 10); g.lineTo(-12, -1); g.lineTo(-6, -5); g.lineTo(-6, -1); g.lineTo(0, -5); g.lineTo(0, -1); g.lineTo(6, -5); g.lineTo(6, 10); g.closePath(); g.fill();
      g.fillRect(7, -12, 5, 22);
      g.fillStyle = '#9e9e9e'; g.beginPath(); g.arc(10, -14, 3, 0, 7); g.arc(6, -16, 2.4, 0, 7); g.fill();
      g.fillStyle = '#ffcc80'; g.fillRect(-9, 3, 3, 3); g.fillRect(-3, 3, 3, 3); g.fillRect(2, 3, 3, 3);
    }),
    fort: sprite((g) => {
      g.fillStyle = '#795548';
      g.fillRect(-10, -4, 20, 15);
      for (let i = 0; i < 4; i++) g.fillRect(-10 + i * 5.6, -10, 3.4, 7);
      g.fillStyle = '#3e2723'; g.beginPath(); g.arc(0, 11, 4, Math.PI, 0); g.fill(); g.fillRect(-4, 7, 8, 4);
    }),
    anchor: (() => {
      const c = document.createElement('canvas'); c.width = c.height = 40;
      const g = c.getContext('2d'); g.translate(20, 20);
      g.strokeStyle = '#fff'; g.lineWidth = 3.4; g.lineCap = 'round';
      g.beginPath(); g.arc(0, -9, 3, 0, 7); g.moveTo(0, -6); g.lineTo(0, 11); g.moveTo(-6, -3); g.lineTo(6, -3); g.stroke();
      g.beginPath(); g.arc(0, 2, 10, 0.25, Math.PI - 0.25); g.stroke();
      return c;
    })(),
  };
}

export class Renderer {
  constructor(canvas, dprFn) {
    this.cv = canvas; this.ctx = canvas.getContext('2d', { alpha: false });
    this.dprFn = dprFn;
    this.cam = { x: WW / 2, y: WH / 2, z: 0.4 };
    this.fly = null;
    this.sprites = makeSprites();
    this.fx = { rings: [], parts: [], texts: [], flashes: [] };
    this.sel = -1; this.targets = null; this.pickMode = false; this.hover = -1;
    this.dirty = true;
    this.resize();
  }

  resize() {
    this.dpr = this.dprFn();
    this.w = innerWidth; this.h = innerHeight;
    this.cv.width = Math.round(this.w * this.dpr); this.cv.height = Math.round(this.h * this.dpr);
    this.cv.style.width = this.w + 'px'; this.cv.style.height = this.h + 'px';
    this.minZ = Math.min(this.w / WW, this.h / WH) * 0.98;
    this.vign = null;
    this.clampCam();
  }

  setWorld(world, game, nations) {
    this.world = world; this.game = game; this.N = nations;
    for (const p of world.provinces) {
      const path = new Path2D();
      for (const r of p.rings) path.addPath(pathFrom(r, true));
      p.path = path;
      for (const run of p.runs) { run.line = pathFrom(run.pts, run.closed); run.innerPath = pathFrom(run.inner, run.closed); }
    }
    this.coastPath = new Path2D();
    for (const c of world.coastLines) this.coastPath.addPath(pathFrom(c.pts, c.closed));
    this.innerPath = new Path2D();
    for (const c of world.innerBorders) this.innerPath.addPath(pathFrom(c.pts, c.closed));
    this.buildBase();
    this.fx = { rings: [], parts: [], texts: [], flashes: [] };
    this.dirty = true;
    this.sel = -1; this.targets = null;
  }

  // ---------- кэш карты ----------
  buildBase() {
    const world = this.world, rand = mulberry32(world.seed ^ 0x5bd1e995);
    const det = this.detail ?? 6;
    const BS = this.bs = det <= 3 ? 1.0 : det <= 7 ? 1.5 : 1.8;
    const W = Math.round(WW * BS), H = Math.round(WH * BS);
    const base = this.base || document.createElement('canvas');
    base.width = W; base.height = H;
    const g = base.getContext('2d');
    // океан: глубина от расстояния до берега
    const oc = document.createElement('canvas'); oc.width = GW; oc.height = GH;
    const og = oc.getContext('2d'), img = og.createImageData(GW, GH), d = img.data;
    for (let i = 0; i < GW * GH; i++) {
      const y = (i / GW) | 0, lat = Math.abs(y / GH - 0.5) * 2;
      const t = Math.pow(clamp((world.oceanDist[i] - 1) / 26, 0, 1), 0.75);
      const nz = (world.moist[i] * 10) | 0;
      d[i * 4] = (78 + (19 - 78) * t) * (1 - lat * 0.12) + nz;
      d[i * 4 + 1] = (176 + (64 - 176) * t) * (1 - lat * 0.1) + nz;
      d[i * 4 + 2] = (205 + (122 - 205) * t) + nz;
      d[i * 4 + 3] = 255;
    }
    og.putImageData(img, 0, 0);
    g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
    g.drawImage(oc, 0, 0, W, H);
    // зерно
    const grain = document.createElement('canvas'); grain.width = grain.height = 128;
    {
      const gg = grain.getContext('2d'), gi = gg.createImageData(128, 128);
      for (let i = 0; i < 128 * 128; i++) { const v = rand() < 0.5 ? 0 : 255; gi.data[i * 4] = gi.data[i * 4 + 1] = gi.data[i * 4 + 2] = v; gi.data[i * 4 + 3] = (rand() * 26) | 0; }
      gg.putImageData(gi, 0, 0);
    }
    g.fillStyle = g.createPattern(grain, 'repeat'); g.globalAlpha = 0.5; g.fillRect(0, 0, W, H); g.globalAlpha = 1;
    // мелководье у берега
    g.setTransform(BS, 0, 0, BS, 0, 0);
    g.lineJoin = g.lineCap = 'round';
    g.strokeStyle = 'rgba(190,240,255,0.10)'; g.lineWidth = 22; g.stroke(this.coastPath);
    g.strokeStyle = 'rgba(200,245,255,0.16)'; g.lineWidth = 11; g.stroke(this.coastPath);
    g.strokeStyle = 'rgba(235,252,255,0.35)'; g.lineWidth = 4.5; g.stroke(this.coastPath);

    // суша
    const L = document.createElement('canvas'); L.width = W; L.height = H;
    const lg = L.getContext('2d');
    lg.setTransform(BS, 0, 0, BS, 0, 0);
    lg.lineJoin = 'round';
    for (const p of world.provinces) {
      const col = hexMix(TERRAIN[p.terrain].color, (rand() - 0.5) * 0.08, (rand() - 0.5) * 8);
      lg.fillStyle = col; lg.strokeStyle = col; lg.lineWidth = 1.2;
      lg.fill(p.path); lg.stroke(p.path);
    }
    // рельеф (освещение с северо-запада)
    {
      const rc = document.createElement('canvas'); rc.width = GW; rc.height = GH;
      const rg = rc.getContext('2d'), ri = rg.createImageData(GW, GH), rd = ri.data;
      const E = world.elev, M = world.mtn;
      for (let y = 1; y < GH - 1; y++) for (let x = 1; x < GW - 1; x++) {
        const i = y * GW + x;
        if (!world.land[i]) continue;
        const pid = world.id[i], mt = world.provinces[pid].terrain === 'mountains' ? 1.9 : 0.8;
        const hgt = (k) => E[k] + Math.max(0, M[k]) * 0.25 * mt;
        let s = (hgt(i - GW - 1) - hgt(i + GW + 1)) * 5 * mt;
        s = clamp(s, -1, 1);
        if (s > 0) { rd[i * 4] = 255; rd[i * 4 + 1] = 250; rd[i * 4 + 2] = 225; rd[i * 4 + 3] = s * 90; }
        else { rd[i * 4] = 40; rd[i * 4 + 1] = 30; rd[i * 4 + 2] = 15; rd[i * 4 + 3] = -s * 100; }
      }
      rg.putImageData(ri, 0, 0);
      lg.setTransform(1, 0, 0, 1, 0, 0);
      lg.globalCompositeOperation = 'source-atop';
      lg.imageSmoothingEnabled = true; lg.imageSmoothingQuality = 'high';
      lg.drawImage(rc, 0, 0, W, H);
      lg.fillStyle = lg.createPattern(grain, 'repeat'); lg.fillRect(0, 0, W, H);
      lg.globalCompositeOperation = 'source-over';
    }
    // значки местности
    lg.setTransform(BS, 0, 0, BS, 0, 0);
    for (const p of world.provinces) this.drawGlyphs(lg, p, rand);
    // тонкие границы провинций
    lg.strokeStyle = 'rgba(60,45,25,0.28)'; lg.lineWidth = 1.1; lg.stroke(this.innerPath);
    // суша с тенью → на океан
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.save();
    if (det > 3) { g.shadowColor = 'rgba(0,25,50,0.5)'; g.shadowBlur = 12 * BS / 1.5; g.shadowOffsetY = 4; }
    g.drawImage(L, 0, 0);
    g.restore();
    g.setTransform(BS, 0, 0, BS, 0, 0);
    g.strokeStyle = 'rgba(25,45,40,0.55)'; g.lineWidth = 1.3; g.stroke(this.coastPath);
    L.width = L.height = 1;
    this.base = base;
  }

  drawGlyphs(g, p, rand) {
    const world = this.world, t = p.terrain;
    const n = Math.round(p.area / (t === 'forest' ? 16 : t === 'mountains' ? 22 : 34));
    const pts = [];
    for (let tries = 0; tries < n * 6 && pts.length < n; tries++) {
      const c = p.cells[Math.floor(rand() * p.cells.length)];
      if (world.dt[c] < 2) continue;
      const x = (c % GW + rand()) * CELL, y = (((c / GW) | 0) + rand()) * CELL;
      if (Math.hypot(x - p.lx, y - p.ly) < 16) continue;
      if (pts.some((q) => Math.abs(q[0] - x) < 6 && Math.abs(q[1] - y) < 5)) continue;
      pts.push([x, y]);
    }
    pts.sort((a, b) => a[1] - b[1]);
    for (const [x, y] of pts) {
      const s = 0.8 + rand() * 0.5;
      if (t === 'mountains') {
        g.fillStyle = '#857a68'; g.beginPath(); g.moveTo(x - 7 * s, y + 4 * s); g.lineTo(x, y - 6 * s); g.lineTo(x + 7 * s, y + 4 * s); g.fill();
        g.fillStyle = '#665c4d'; g.beginPath(); g.moveTo(x, y - 6 * s); g.lineTo(x + 7 * s, y + 4 * s); g.lineTo(x + 1 * s, y + 4 * s); g.fill();
        g.fillStyle = '#f4f6f8'; g.beginPath(); g.moveTo(x - 2.3 * s, y - 2.6 * s); g.lineTo(x, y - 6 * s); g.lineTo(x + 2.3 * s, y - 2.6 * s); g.lineTo(x + 0.6 * s, y - 3.2 * s); g.lineTo(x - 0.6 * s, y - 2.2 * s); g.fill();
      } else if (t === 'forest') {
        g.fillStyle = 'rgba(30,60,25,0.35)'; g.beginPath(); g.ellipse(x + 0.8, y + 2.6 * s, 3.2 * s, 1.3 * s, 0, 0, 7); g.fill();
        g.fillStyle = '#2f6b2c'; g.beginPath(); g.arc(x, y, 3.1 * s, 0, 7); g.fill();
        g.fillStyle = '#4f9440'; g.beginPath(); g.arc(x - 0.9 * s, y - 0.9 * s, 1.6 * s, 0, 7); g.fill();
      } else if (t === 'desert') {
        g.strokeStyle = 'rgba(150,110,50,0.55)'; g.lineWidth = 1.1;
        g.beginPath(); g.moveTo(x - 6 * s, y + 1); g.quadraticCurveTo(x - 1 * s, y - 3.5 * s, x + 5 * s, y + 1); g.stroke();
        g.strokeStyle = 'rgba(255,240,200,0.5)'; g.beginPath(); g.moveTo(x - 4 * s, y - 0.2); g.quadraticCurveTo(x - 1 * s, y - 2.6 * s, x + 2 * s, y - 1); g.stroke();
      } else if (t === 'snow') {
        if (rand() < 0.55) {
          g.fillStyle = '#3f6650'; g.beginPath(); g.moveTo(x - 2.8 * s, y + 3 * s); g.lineTo(x, y - 4 * s); g.lineTo(x + 2.8 * s, y + 3 * s); g.fill();
          g.fillStyle = '#ffffff'; g.beginPath(); g.moveTo(x - 1.4 * s, y - 0.6 * s); g.lineTo(x, y - 4 * s); g.lineTo(x + 1.4 * s, y - 0.6 * s); g.fill();
        } else { g.fillStyle = 'rgba(150,190,215,0.55)'; g.beginPath(); g.ellipse(x, y, 3.5 * s, 1.4 * s, 0, 0, 7); g.fill(); }
      } else {
        if (rand() < 0.35) { // поле
          g.save(); g.translate(x, y); g.rotate((rand() - 0.5) * 0.8);
          g.fillStyle = rand() < 0.5 ? 'rgba(230,205,110,0.55)' : 'rgba(120,160,60,0.45)'; g.fillRect(-4 * s, -2.5 * s, 8 * s, 5 * s);
          g.strokeStyle = 'rgba(90,110,40,0.35)'; g.lineWidth = 0.6; for (let k = -3; k <= 3; k += 2) { g.beginPath(); g.moveTo(k * s, -2.5 * s); g.lineTo(k * s, 2.5 * s); g.stroke(); }
          g.restore();
        } else {
          g.strokeStyle = 'rgba(70,110,40,0.6)'; g.lineWidth = 0.9;
          g.beginPath(); g.moveTo(x - 1.6, y + 1.5); g.lineTo(x - 2.4, y - 1.5); g.moveTo(x, y + 1.5); g.lineTo(x, y - 2.2); g.moveTo(x + 1.6, y + 1.5); g.lineTo(x + 2.4, y - 1.5); g.stroke();
        }
      }
    }
  }

  // ---------- политика (по нациям) ----------
  rebuildPolitical() {
    const P = this.world.provinces, N = this.N;
    this.pol = N.map(() => ({ fill: new Path2D(), border: new Path2D(), any: false }));
    this.sep = new Path2D();
    for (const p of P) {
      if (p.owner < 0) continue;
      const pol = this.pol[p.owner]; pol.any = true;
      pol.fill.addPath(p.path);
      for (const run of p.runs) {
        const oo = run.other >= 0 ? P[run.other].owner : -1;
        if (oo === p.owner) continue;
        pol.border.addPath(run.innerPath);
        if (run.other >= 0 && (oo < 0 || p.id < run.other)) this.sep.addPath(run.line);
      }
    }
    // подписи наций: центр самого большого куска территории
    for (const n of N) {
      n.label = null;
      if (!n.alive) continue;
      const seen = new Set();
      let best = null;
      for (const p of P) {
        if (p.owner !== n.id || seen.has(p.id)) continue;
        const comp = []; const st = [p.id]; seen.add(p.id);
        while (st.length) { const q = st.pop(); comp.push(q); for (const x of P[q].neighbors) if (!seen.has(x) && P[x].owner === n.id) { seen.add(x); st.push(x); } }
        let area = 0; for (const q of comp) area += P[q].area;
        if (!best || area > best.area) best = { comp, area };
      }
      if (!best) continue;
      let sx = 0, sy = 0;
      for (const q of best.comp) { sx += P[q].cx * P[q].area; sy += P[q].cy * P[q].area; }
      let x = sx / best.area, y = sy / best.area;
      const pid = this.world.pick(x, y);
      if (pid < 0 || P[pid].owner !== n.id) {
        let bd = 1e18;
        for (const q of best.comp) { const d = (P[q].cx - x) ** 2 + (P[q].cy - y) ** 2; if (d < bd) { bd = d; x = P[q].cx; y = P[q].cy; } }
      }
      n.label = { x, y, size: clamp(Math.sqrt(best.area) * CELL * 0.12, 13, 64), comp: best.comp.length };
    }
    this.dirty = false;
  }

  // ---------- камера ----------
  clampCam() {
    const c = this.cam;
    c.z = clamp(c.z, this.minZ, 3.6);
    const hw = this.w / 2 / c.z, hh = this.h / 2 / c.z, mx = (this.w * 0.3) / c.z, my = (this.h * 0.38) / c.z;
    c.x = 2 * hw >= WW ? WW / 2 : clamp(c.x, Math.min(WW / 2, hw - mx), Math.max(WW / 2, WW - hw + mx));
    c.y = 2 * hh >= WH ? WH / 2 : clamp(c.y, Math.min(WH / 2, hh - my), Math.max(WH / 2, WH - hh + my));
  }
  s2w(sx, sy) { const c = this.cam; return [c.x + (sx - this.w / 2) / c.z, c.y + (sy - this.h / 2) / c.z]; }
  w2s(wx, wy) { const c = this.cam; return [(wx - c.x) * c.z + this.w / 2, (wy - c.y) * c.z + this.h / 2]; }
  zoomAt(sx, sy, f) {
    const [wx, wy] = this.s2w(sx, sy);
    this.cam.z = clamp(this.cam.z * f, this.minZ, 3.6);
    this.cam.x = wx - (sx - this.w / 2) / this.cam.z;
    this.cam.y = wy - (sy - this.h / 2) / this.cam.z;
    this.fly = null;
    this.clampCam();
  }
  pan(dx, dy) { this.cam.x -= dx / this.cam.z; this.cam.y -= dy / this.cam.z; this.fly = null; this.clampCam(); }
  flyTo(x, y, z, dur = 1) { this.fly = { x0: this.cam.x, y0: this.cam.y, z0: this.cam.z, x, y, z: clamp(z, this.minZ, 3.6), t: 0, dur }; }
  fitAll() { this.cam.z = this.minZ; this.cam.x = WW / 2; this.cam.y = WH / 2; this.clampCam(); }

  // ---------- эффекты ----------
  ring(x, y, color, r1 = 40, dur = 0.6) { if (this.fx.rings.length < 60) this.fx.rings.push({ x, y, color, r1, dur, t: 0 }); }
  sparks(x, y, color, n = 10) {
    const det = this.detail ?? 6;
    n = Math.round(n * (det <= 3 ? 0.4 : det <= 7 ? 1 : 1.4));
    for (let i = 0; i < n && this.fx.parts.length < 240; i++) {
      const a = Math.random() * 6.28, v = 40 + Math.random() * 110;
      this.fx.parts.push({ x, y, ox: 0, oy: 0, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 30, t: 0, dur: 0.45 + Math.random() * 0.4, color });
    }
  }
  text(x, y, s, color = '#fff', size = 15, dur = 1.4) {
    if (this.fx.texts.length >= 40) return;
    let k = 0; // не накладывать надписи друг на друга
    for (const t of this.fx.texts) if (t.t < 0.6 && Math.abs(t.x - x) < 30 && Math.abs(t.y0 - y) < 30) k++;
    this.fx.texts.push({ x, y: y - (k * 16) / this.cam.z, y0: y, s, color, size, dur, t: 0 });
  }
  flash(pid, color = '255,255,255') { this.fx.flashes.push({ pid, color, t: 0, dur: 0.7 }); }

  // ---------- кадр ----------
  draw(time, dt) {
    if (!this.world) return;
    if (this.fly) {
      const f = this.fly; f.t += dt / f.dur;
      const k = f.t >= 1 ? 1 : 1 - Math.pow(1 - f.t, 3);
      this.cam.x = f.x0 + (f.x - f.x0) * k; this.cam.y = f.y0 + (f.y - f.y0) * k; this.cam.z = f.z0 + (f.z - f.z0) * k;
      this.clampCam();
      if (f.t >= 1) this.fly = null;
    }
    if (this.dirty) this.rebuildPolitical();
    const SK = this.skip || {}, BS = this.bs, det = this.detail ?? 6;
    const { ctx, cam, dpr, w, h } = this, z = cam.z, P = this.world.provinces, N = this.N, G = this.game;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#133d79'; ctx.fillRect(0, 0, this.cv.width, this.cv.height);
    const k = z * dpr;
    ctx.setTransform(k, 0, 0, k, (w / 2 - cam.x * z) * dpr, (h / 2 - cam.y * z) * dpr);
    const vx0 = cam.x - w / 2 / z, vx1 = cam.x + w / 2 / z, vy0 = cam.y - h / 2 / z, vy1 = cam.y + h / 2 / z;
    const sx0 = Math.max(0, vx0), sy0 = Math.max(0, vy0), sx1 = Math.min(WW, vx1), sy1 = Math.min(WH, vy1);
    if (!SK.base && sx1 > sx0 && sy1 > sy0) ctx.drawImage(this.base, sx0 * BS, sy0 * BS, (sx1 - sx0) * BS, (sy1 - sy0) * BS, sx0, sy0, sx1 - sx0, sy1 - sy0);

    // волны
    if (!SK.waves && det > 2) {
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.strokeStyle = 'rgba(220,245,255,0.35)'; ctx.lineWidth = Math.max(0.8, 1.3 / z);
    ctx.beginPath();
    for (const wv of this.world.waves) {
      if (wv.x < vx0 - 10 || wv.x > vx1 + 10 || wv.y < vy0 - 10 || wv.y > vy1 + 10) continue;
      const ph = time * 0.9 + wv.ph, a = Math.sin(ph);
      if (a < 0) continue;
      const s = wv.s * (0.6 + a * 0.5) * 1.4, x = wv.x + Math.sin(time * 0.3 + wv.ph) * 4, y = wv.y;
      ctx.moveTo(x - 6 * s, y); ctx.quadraticCurveTo(x - 3 * s, y - 3 * s, x, y); ctx.quadraticCurveTo(x + 3 * s, y - 3 * s, x + 6 * s, y);
    }
    ctx.stroke();
    }

    // заливка наций
    if (!SK.pol) for (const n of N) { const pol = this.pol[n.id]; if (pol && pol.any) { ctx.fillStyle = n.fill; ctx.fill(pol.fill); } }
    // вспышки захвата
    for (let i = this.fx.flashes.length - 1; i >= 0; i--) {
      const f = this.fx.flashes[i]; f.t += dt;
      if (f.t >= f.dur) { this.fx.flashes.splice(i, 1); continue; }
      ctx.fillStyle = `rgba(${f.color},${0.55 * (1 - f.t / f.dur)})`; ctx.fill(P[f.pid].path);
    }
    // выделение/наведение
    if (this.hover >= 0 && this.hover !== this.sel) { ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.fill(P[this.hover].path); }
    // границы
    const sw = clamp(z * 3.4, 1.6, 4.6);
    ctx.lineWidth = sw / z;
    if (!SK.border) { for (const n of N) { const pol = this.pol[n.id]; if (pol && pol.any) { ctx.strokeStyle = n.color; ctx.stroke(pol.border); } }
    ctx.strokeStyle = 'rgba(15,15,25,0.6)'; ctx.lineWidth = 1.1 / z; ctx.stroke(this.sep); }

    // цели и выбор
    const pulse = 0.5 + 0.5 * Math.sin(time * 6);
    if (this.targets) {
      for (const [id, info] of this.targets) {
        ctx.fillStyle = info.color.replace('A', (0.08 + 0.12 * pulse).toFixed(2));
        ctx.fill(P[id].path);
      }
      ctx.lineWidth = 4.2 / z; ctx.strokeStyle = 'rgba(0,0,0,0.25)';
      for (const [id] of this.targets) ctx.stroke(P[id].path);
      ctx.lineWidth = 2.4 / z;
      for (const [id, info] of this.targets) {
        ctx.strokeStyle = info.color.replace('A', (0.55 + 0.45 * pulse).toFixed(2));
        ctx.stroke(P[id].path);
      }
    }
    if (this.sel >= 0) {
      const p = P[this.sel];
      ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fill(p.path);
      ctx.setLineDash([6 / z, 4 / z]); ctx.lineDashOffset = -time * 20 / z;
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 3 / z; ctx.stroke(p.path);
      ctx.setLineDash([]);
    }

    // следы армий (мир)
    const G_ = G;
    ctx.lineWidth = 2.2 / z;
    for (const a of G_.armies) {
      const pos = armyPos(a);
      a._x = pos[0]; a._y = pos[1]; a._ang = pos[2];
      const col = N[a.owner].color;
      ctx.strokeStyle = col; ctx.globalAlpha = 0.85;
      ctx.setLineDash([5 / z, 4 / z]); ctx.lineDashOffset = -time * 30 / z;
      ctx.beginPath(); ctx.moveTo(pos[0], pos[1]);
      for (let i = pos[3] + 1; i < a.path.length / 2; i++) ctx.lineTo(a.path[i * 2], a.path[i * 2 + 1]);
      ctx.stroke(); ctx.setLineDash([]);
      // стрелка у цели
      const n2 = a.path.length;
      const ex = a.path[n2 - 2], ey = a.path[n2 - 1], px = a.path[n2 - 4], py = a.path[n2 - 3];
      const an = Math.atan2(ey - py, ex - px), r = 7 / z;
      const tx = ex - Math.cos(an) * 9 / z, ty = ey - Math.sin(an) * 9 / z;
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.moveTo(tx + Math.cos(an) * r, ty + Math.sin(an) * r);
      ctx.lineTo(tx + Math.cos(an + 2.5) * r, ty + Math.sin(an + 2.5) * r); ctx.lineTo(tx + Math.cos(an - 2.5) * r, ty + Math.sin(an - 2.5) * r); ctx.fill();
      ctx.globalAlpha = 1;
    }

    // ---------- экранные слои ----------
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const toS = (x, y) => [(x - cam.x) * z + w / 2, (y - cam.y) * z + h / 2];
    // кольца
    ctx.lineWidth = 3;
    for (let i = this.fx.rings.length - 1; i >= 0; i--) {
      const r = this.fx.rings[i]; r.t += dt;
      if (r.t >= r.dur) { this.fx.rings.splice(i, 1); continue; }
      const k2 = r.t / r.dur, [x, y] = toS(r.x, r.y);
      ctx.strokeStyle = r.color; ctx.globalAlpha = 1 - k2;
      ctx.beginPath(); ctx.arc(x, y, 6 + r.r1 * k2, 0, 7); ctx.stroke();
    }
    ctx.globalAlpha = 1;
    // названия наций
    if (!SK.names && z < 1.65) {
      const alpha = clamp((1.55 - z) / 0.8, 0.22, 0.92);
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.lineJoin = 'round';
      for (const n of N) {
        const L = n.label; if (!L) continue;
        const fs = clamp(L.size * z, 11, 34);
        if (L.comp < 2 && z < 0.9 && !n.isPlayer) continue;
        const [x, y] = toS(L.x, L.y);
        if (x < -200 || x > w + 200 || y < -50 || y > h + 50) continue;
        ctx.font = `900 ${fs.toFixed(0)}px system-ui,sans-serif`;
        ctx.letterSpacing = (fs * 0.06).toFixed(1) + 'px';
        ctx.globalAlpha = alpha;
        ctx.lineWidth = Math.max(2.5, fs * 0.16); ctx.strokeStyle = 'rgba(10,15,30,0.75)';
        const t = n.name.toUpperCase();
        const yy = y + (z >= 0.5 ? 13 + fs * 0.55 : 0);
        ctx.strokeText(t, x, yy);
        ctx.fillStyle = n.light; ctx.fillText(t, x, yy);
      }
      ctx.letterSpacing = '0px';
      ctx.globalAlpha = 1;
    }
    // войска на провинциях + постройки
    const showNum = z >= 0.5;
    const showIcons = z >= 0.62;
    ctx.font = '800 11px system-ui,sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    if (!SK.pills) for (const p of P) {
      const [x, y] = toS(p.lx, p.ly);
      if (x < -30 || x > w + 30 || y < -30 || y > h + 30) continue;
      const own = p.owner >= 0 ? N[p.owner] : null;
      const important = p.id === this.sel || (this.targets && this.targets.has(p.id));
      if (!showNum && !important && !p.capital) continue;
      if (!showNum && !important) { // только столица
        ctx.drawImage(this.sprites.capital, x - 8, y - 8, 16, 16); continue;
      }
      if (z >= 1.65) { // подписи провинций вблизи
        ctx.font = '700 10px system-ui,sans-serif'; ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(0,0,0,0.55)'; ctx.fillStyle = 'rgba(255,255,255,0.9)';
        ctx.strokeText(p.name, x, y + 17); ctx.fillText(p.name, x, y + 17);
        ctx.font = '800 11px system-ui,sans-serif';
      }
      const v = Math.floor(p.troops), str = v >= 10000 ? (v / 1000).toFixed(0) + 'k' : String(v);
      const bw = 10 + str.length * 6.6, bh = 16;
      const recent = G.time - p.hit < 0.4;
      ctx.fillStyle = own ? own.dark : 'rgba(35,35,40,0.62)';
      rr(ctx, x - bw / 2, y - bh / 2, bw, bh, 8); ctx.fill();
      ctx.lineWidth = p.capital ? 2 : 1.2; ctx.strokeStyle = recent ? '#ff5252' : p.capital ? '#ffd54a' : 'rgba(255,255,255,0.75)'; ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.fillText(str, x, y + 0.5);
      let ix = x - bw / 2 - 9;
      if (p.capital) { ctx.drawImage(this.sprites.capital, ix - 8, y - 9, 18, 18); ix -= 16; }
      if (showIcons || important) {
        const icons = [];
        if (p.b.city) icons.push(this.sprites.city);
        if (p.b.port) icons.push(this.sprites.port);
        if (p.b.factory) icons.push(this.sprites.factory);
        if (p.b.fort) icons.push(this.sprites.fort);
        const s = 15, tw = icons.length * (s - 1);
        icons.forEach((im, i) => ctx.drawImage(im, x - tw / 2 + i * (s - 1), y - bh / 2 - s - 1, s, s));
      }
    }
    // морские цели — якорь
    if (this.targets) for (const [id, info] of this.targets) {
      if (!info.naval) continue;
      const p = P[id], [x, y] = toS(p.lx, p.ly);
      if (x < -20 || x > w + 20 || y < -20 || y > h + 20) continue;
      ctx.fillStyle = '#1d6fd6'; ctx.beginPath(); ctx.arc(x, y + 17, 9, 0, 7); ctx.fill();
      ctx.lineWidth = 1.5; ctx.strokeStyle = '#fff'; ctx.stroke();
      ctx.drawImage(this.sprites.anchor, x - 7, y + 10, 14, 14);
    }
    // армии
    for (const a of G.armies) {
      if (a._x === undefined) continue;
      const [x, y] = toS(a._x, a._y);
      if (x < -30 || x > w + 30 || y < -30 || y > h + 30) continue;
      const n = N[a.owner], ang = a._ang;
      const cs = Math.cos(ang), sn = Math.sin(ang);
      if (a.naval) { // кораблик
        ctx.save(); ctx.translate(x, y + 6);
        ctx.fillStyle = '#6d4c41'; ctx.beginPath(); ctx.moveTo(-13, -2); ctx.lineTo(13, -2); ctx.lineTo(8, 5); ctx.lineTo(-8, 5); ctx.closePath(); ctx.fill();
        ctx.fillStyle = '#fafafa'; ctx.beginPath(); ctx.moveTo(1, -18); ctx.lineTo(1, -3); ctx.lineTo(11, -4); ctx.closePath(); ctx.fill();
        ctx.fillStyle = n.color; ctx.fillRect(-1, -20, 2, 18);
        ctx.restore();
      } else { // колонна солдат
        const m = Math.min(4, 1 + Math.floor(a.n / 12));
        for (let i = 1; i <= m; i++) {
          const bob = Math.sin(time * 14 + i * 1.7) * 1.4;
          const sx = x - cs * (9 + i * 7), sy = y - sn * (9 + i * 7) + bob;
          ctx.fillStyle = n.dark; ctx.fillRect(sx - 3.5, sy - 3.5, 7, 7);
          ctx.fillStyle = n.color; ctx.fillRect(sx - 2.5, sy - 2.5, 5, 5);
        }
      }
      const str = String(Math.floor(a.n)), r = 8 + str.length * 2;
      ctx.fillStyle = n.color; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.stroke();
      ctx.fillStyle = '#fff'; ctx.font = '900 11px system-ui,sans-serif';
      ctx.fillText(str, x, y + 0.5);
    }
    // искры
    for (let i = this.fx.parts.length - 1; i >= 0; i--) {
      const s = this.fx.parts[i]; s.t += dt;
      if (s.t >= s.dur) { this.fx.parts.splice(i, 1); continue; }
      s.ox += s.vx * dt; s.oy += s.vy * dt; s.vy += 160 * dt;
      const [x, y] = toS(s.x, s.y);
      ctx.globalAlpha = 1 - s.t / s.dur; ctx.fillStyle = s.color;
      ctx.fillRect(x + s.ox - 2, y + s.oy - 2, 4, 4);
    }
    ctx.globalAlpha = 1;
    // всплывающий текст
    for (let i = this.fx.texts.length - 1; i >= 0; i--) {
      const t = this.fx.texts[i]; t.t += dt;
      if (t.t >= t.dur) { this.fx.texts.splice(i, 1); continue; }
      const k2 = t.t / t.dur, [x, y] = toS(t.x, t.y);
      ctx.globalAlpha = k2 < 0.7 ? 1 : 1 - (k2 - 0.7) / 0.3;
      ctx.font = `900 ${t.size}px system-ui,sans-serif`;
      ctx.lineWidth = 3.5; ctx.strokeStyle = 'rgba(0,0,0,.75)';
      const yy = y - 14 - k2 * 30;
      ctx.strokeText(t.s, x, yy); ctx.fillStyle = t.color; ctx.fillText(t.s, x, yy);
    }
    ctx.globalAlpha = 1;
    // виньетка
    if (!this.vign) {
      this.vign = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.45, w / 2, h / 2, Math.max(w, h) * 0.75);
      this.vign.addColorStop(0, 'rgba(0,0,0,0)'); this.vign.addColorStop(1, 'rgba(0,10,30,0.35)');
    }
    if (!SK.vign && det > 3) { ctx.fillStyle = this.vign; ctx.fillRect(0, 0, w, h); }
  }
}

function rr(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

export function armyPos(a) {
  const d = Math.min(a.d, a.len), c = a.cum;
  let i = 0;
  while (i < c.length - 2 && c[i + 1] < d) i++;
  const seg = (c[i + 1] - c[i]) || 1, t = (d - c[i]) / seg;
  const x0 = a.path[i * 2], y0 = a.path[i * 2 + 1], x1 = a.path[i * 2 + 2], y1 = a.path[i * 2 + 3];
  return [x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, Math.atan2(y1 - y0, x1 - x0), i];
}

// Эффекты: процедурные текстуры, частицы (один draw call), разрезы, кольца-ударные волны,
// послеобразы, лучи лечения, всплывающие цифры (DOM), вспышки экрана и тряска камеры.
import * as THREE from 'three';
import { shakeEnabled } from '../../shared/ui.js';
import { pixTexture, PIX } from './pixfont.js';

export function canvasTex(w, h, draw, srgb = true) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

const texCache = new Map();
function cached(key, fn) { if (!texCache.has(key)) texCache.set(key, fn()); return texCache.get(key); }

export const glowTex = () => cached('glow', () => canvasTex(64, 64, (g) => {
  const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,.75)');
  gr.addColorStop(0.6, 'rgba(255,255,255,.18)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
}));

// Вертикальный «послеобраз»
const afterTex = () => cached('after', () => canvasTex(32, 128, (g) => {
  const gr = g.createLinearGradient(0, 0, 32, 0);
  gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(0.5, 'rgba(255,255,255,.9)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 32, 128);
  const v = g.createLinearGradient(0, 0, 0, 128);
  v.addColorStop(0, 'rgba(0,0,0,1)'); v.addColorStop(0.15, 'rgba(0,0,0,0)'); v.addColorStop(0.85, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,1)');
  g.globalCompositeOperation = 'destination-out'; g.fillStyle = v; g.fillRect(0, 0, 32, 128);
}));

// Полоса-телеграф на полу: яркие края, тусклая середина (u — поперёк)
export const stripTex = () => cached('strip', () => canvasTex(64, 8, (g) => {
  const gr = g.createLinearGradient(0, 0, 64, 0);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.08, 'rgba(255,255,255,.55)');
  gr.addColorStop(0.3, 'rgba(255,255,255,.18)'); gr.addColorStop(0.5, 'rgba(255,255,255,.12)');
  gr.addColorStop(0.7, 'rgba(255,255,255,.18)'); gr.addColorStop(0.92, 'rgba(255,255,255,.55)'); gr.addColorStop(1, 'rgba(255,255,255,1)');
  g.fillStyle = gr; g.fillRect(0, 0, 64, 8);
}));

// Разрез: яркий передний край (u=1), мягкие края по v
const slashTex = () => cached('slash', () => canvasTex(128, 32, (g) => {
  const img = g.createImageData(128, 32);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 128; x++) {
    const u = x / 127, v = y / 31;
    const a = Math.pow(u, 1.6) * Math.pow(Math.sin(v * Math.PI), 0.7) * (v > 0.55 ? 1 : 0.55 + v * 0.8);
    const i = (y * 128 + x) * 4;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = 255; img.data[i + 3] = Math.min(255, a * 300);
  }
  g.putImageData(img, 0, 0);
}));

// Пиксельное сердце-душа
const HEART = ['.XX...XX.', 'XXXX.XXXX', 'XXXXXXXXX', 'XXXXXXXXX', '.XXXXXXX.', '..XXXXX..', '...XXX...', '....X....'];
export function drawHeart(g, cx, cy, px, color, broken = false) {
  const w = 9 * px, h = 8 * px, x0 = cx - w / 2, y0 = cy - h / 2;
  for (let r = 0; r < 8; r++) for (let c = 0; c < 9; c++) {
    if (HEART[r][c] !== 'X') continue;
    let ox = 0;
    if (broken) { if (c < 4 || (c === 4 && r % 2 === 0)) ox = -px * 0.8; else ox = px * 0.8; }
    g.fillStyle = color; g.fillRect(x0 + c * px + ox, y0 + r * px, px + 0.5, px + 0.5);
  }
  if (!broken) { g.fillStyle = 'rgba(255,255,255,.75)'; g.fillRect(x0 + 1 * px, y0 + 1 * px, px, px); }
}
export const heartTex = (color, broken = false) => cached('heart' + color + broken, () => canvasTex(64, 64, (g) => {
  const gr = g.createRadialGradient(32, 32, 4, 32, 32, 32);
  gr.addColorStop(0, color + 'aa'); gr.addColorStop(1, color + '00');
  g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
  drawHeart(g, 32, 33, 4.4, color, broken);
}));
export function heartDataURL(color, size = 36) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  drawHeart(c.getContext('2d'), size / 2, size / 2 + 1, size / 10, color);
  return c.toDataURL();
}

export function textSprite(text, color = '#fff', { font = 30, w = 256, h = 48 } = {}) {
  const tex = canvasTex(w, h, (g) => {
    g.font = `900 ${font}px system-ui,sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.lineWidth = 6; g.strokeStyle = 'rgba(0,0,0,.85)'; g.strokeText(text, w / 2, h / 2);
    g.fillStyle = color; g.fillText(text, w / 2, h / 2);
  });
  tex.userData.own = true; // уничтожается вместе с персонажем
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, fog: false }));
  s.scale.set(w / 64, h / 64, 1);
  s.renderOrder = 5;
  return s;
}

// ---------- Частицы ----------
const PVS = `attribute float aSize; attribute float aAlpha; attribute vec3 aColor;
varying float vA; varying vec3 vC; uniform float uScale;
void main(){ vA=aAlpha; vC=aColor; vec4 mv=modelViewMatrix*vec4(position,1.0);
gl_PointSize=aSize*uScale/max(0.5,-mv.z); gl_Position=projectionMatrix*mv; }`;
const PFS = `varying float vA; varying vec3 vC; uniform float uHard;
void main(){ vec2 c=gl_PointCoord-0.5; float d=length(c)*2.0; float a=clamp(1.0-d,0.0,1.0); a=mix(a*a, smoothstep(0.0,0.35,a), uHard);
gl_FragColor=vec4(vC, a*vA); }`;

class Particles {
  constructor(scene, max, additive, hard = 0) {
    this.max = max; this.n = 0;
    this.p = new Float32Array(max * 3); this.v = new Float32Array(max * 3);
    this.c = new Float32Array(max * 3); this.s = new Float32Array(max); this.a = new Float32Array(max);
    this.life = new Float32Array(max); this.ml = new Float32Array(max); this.s0 = new Float32Array(max);
    this.g = new Float32Array(max); this.drag = new Float32Array(max); this.grow = new Float32Array(max);
    const geo = new THREE.BufferGeometry();
    this.aP = new THREE.BufferAttribute(this.p, 3).setUsage(THREE.DynamicDrawUsage);
    this.aC = new THREE.BufferAttribute(this.c, 3).setUsage(THREE.DynamicDrawUsage);
    this.aS = new THREE.BufferAttribute(this.s, 1).setUsage(THREE.DynamicDrawUsage);
    this.aA = new THREE.BufferAttribute(this.a, 1).setUsage(THREE.DynamicDrawUsage);
    geo.setAttribute('position', this.aP); geo.setAttribute('aColor', this.aC);
    geo.setAttribute('aSize', this.aS); geo.setAttribute('aAlpha', this.aA);
    this.mat = new THREE.ShaderMaterial({
      uniforms: { uScale: { value: 400 }, uHard: { value: hard } }, vertexShader: PVS, fragmentShader: PFS,
      transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.pts = new THREE.Points(geo, this.mat);
    this.pts.frustumCulled = false; this.pts.renderOrder = 3;
    geo.setDrawRange(0, 0);
    scene.add(this.pts);
  }
  emit(x, y, z, vx, vy, vz, life, size, col, g = 0, drag = 0, grow = 0) {
    let i = this.n < this.max ? this.n++ : Math.floor(Math.random() * this.max);
    const i3 = i * 3;
    this.p[i3] = x; this.p[i3 + 1] = y; this.p[i3 + 2] = z;
    this.v[i3] = vx; this.v[i3 + 1] = vy; this.v[i3 + 2] = vz;
    this.c[i3] = col.r; this.c[i3 + 1] = col.g; this.c[i3 + 2] = col.b;
    this.life[i] = life; this.ml[i] = life; this.s0[i] = size; this.s[i] = size;
    this.g[i] = g; this.drag[i] = drag; this.grow[i] = grow; this.a[i] = 1;
  }
  update(dt) {
    let n = this.n;
    for (let i = 0; i < n; i++) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) { n--; if (i !== n) this.copy(n, i); i--; continue; }
      const i3 = i * 3, k = this.life[i] / this.ml[i];
      const dr = Math.max(0, 1 - this.drag[i] * dt);
      this.v[i3] *= dr; this.v[i3 + 2] *= dr; this.v[i3 + 1] = this.v[i3 + 1] * dr - this.g[i] * dt;
      this.p[i3] += this.v[i3] * dt; this.p[i3 + 1] += this.v[i3 + 1] * dt; this.p[i3 + 2] += this.v[i3 + 2] * dt;
      if (this.p[i3 + 1] < 0.05 && this.g[i] > 0) { this.p[i3 + 1] = 0.05; this.v[i3 + 1] *= -0.3; }
      this.a[i] = Math.min(1, k * 1.6);
      this.s[i] = this.s0[i] * (1 + this.grow[i] * (1 - k));
    }
    this.n = n;
    this.pts.geometry.setDrawRange(0, n);
    this.aP.needsUpdate = this.aC.needsUpdate = this.aS.needsUpdate = this.aA.needsUpdate = true;
  }
  copy(from, to) {
    const f3 = from * 3, t3 = to * 3;
    for (let k = 0; k < 3; k++) { this.p[t3 + k] = this.p[f3 + k]; this.v[t3 + k] = this.v[f3 + k]; this.c[t3 + k] = this.c[f3 + k]; }
    this.life[to] = this.life[from]; this.ml[to] = this.ml[from]; this.s0[to] = this.s0[from]; this.s[to] = this.s[from];
    this.g[to] = this.g[from]; this.drag[to] = this.drag[from]; this.grow[to] = this.grow[from]; this.a[to] = this.a[from];
  }
  clear() { this.n = 0; this.pts.geometry.setDrawRange(0, 0); }
}

function arcGeometry(r0, r1, ang, seg = 18) {
  const pos = [], uv = [], idx = [];
  for (let i = 0; i <= seg; i++) {
    const t = i / seg, a = -ang / 2 + ang * t;
    pos.push(Math.sin(a) * r0, 0, Math.cos(a) * r0, Math.sin(a) * r1, 0, Math.cos(a) * r1);
    uv.push(t, 0, t, 1);
    if (i < seg) { const b = i * 2; idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  return g;
}

const tmpC = new THREE.Color();
const V1 = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3();

export class FX {
  constructor(scene, camera) {
    this.scene = scene; this.camera = camera;
    this.glow = new Particles(scene, 900, true);
    this.dust = new Particles(scene, 300, false);
    this.trauma = 0; this.shakeOff = new THREE.Vector3(); this.q = 1; this.shakeOn = shakeEnabled();
    // разрезы
    const arc = arcGeometry(2.0, 3.3, 2.4);
    this.slashes = [];
    for (let i = 0; i < 12; i++) {
      const m = new THREE.Mesh(arc, new THREE.MeshBasicMaterial({ map: slashTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
      m.visible = false; m.renderOrder = 4; scene.add(m);
      this.slashes.push({ m, t: 0, life: 0 });
    }
    // кольца на полу
    const ring = new THREE.RingGeometry(0.86, 1, 48); ring.rotateX(-Math.PI / 2);
    this.rings = [];
    for (let i = 0; i < 12; i++) {
      const m = new THREE.Mesh(ring, new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
      m.visible = false; m.renderOrder = 2; scene.add(m);
      this.rings.push({ m, t: 0, life: 0, r0: 1, r1: 2, y: 0.08 });
    }
    // послеобразы
    this.afters = [];
    for (let i = 0; i < 6; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: afterTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
      s.visible = false; scene.add(s); this.afters.push({ s, t: 0, life: 0 });
    }
    // лучи (лечение / трассеры)
    const cyl = new THREE.CylinderGeometry(1, 1, 1, 8, 1, true); cyl.translate(0, 0.5, 0);
    this.lines = [];
    for (let i = 0; i < 10; i++) {
      const m = new THREE.Mesh(cyl, new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
      m.visible = false; scene.add(m); this.lines.push({ m, t: 0, life: 0, w: 0.2 });
    }
    // вспышки-спрайты
    this.flares = [];
    for (let i = 0; i < 10; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
      s.visible = false; s.renderOrder = 6; scene.add(s); this.flares.push({ s, t: 0, life: 0, size: 1 });
    }
    // «MISS» — спрайты пиксельным шрифтом (чёрные буквы на толстой светлой обводке), без дрейфа
    const missTex = pixTexture('MISS', 10, PIX.miss);
    this.misses = [];
    for (let i = 0; i < 5; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: missTex, transparent: true, depthTest: false, depthWrite: false, fog: false }));
      const h = 1.9; s.scale.set(h * missTex.userData.aspect, h, 1);
      s.visible = false; s.renderOrder = 9; scene.add(s); this.misses.push({ s, t: 0, life: 0 });
    }
    // DOM
    this.layer = document.createElement('div'); this.layer.className = 'jd-ftext';
    document.body.appendChild(this.layer);
    this.texts = [];
    for (let i = 0; i < 26; i++) {
      const el = document.createElement('div'); el.style.display = 'none'; this.layer.appendChild(el);
      this.texts.push({ el, pos: new THREE.Vector3(), t: 0, life: 0 });
    }
    this.flashEl = document.createElement('div'); this.flashEl.className = 'jd-flash'; document.body.appendChild(this.flashEl);
    this.vigEl = document.createElement('div'); this.vigEl.className = 'jd-vig'; document.body.appendChild(this.vigEl);
    this.darkEl = document.createElement('div'); this.darkEl.className = 'jd-dark'; document.body.appendChild(this.darkEl);
    this.flashA = 0; this.vigA = 0; this.darkA = 0; this.darkTarget = 0;
    this.W = innerWidth; this.H = innerHeight;
  }
  setScale(h, fov) {
    const s = h / (2 * Math.tan((fov * Math.PI) / 360));
    this.glow.mat.uniforms.uScale.value = s; this.dust.mat.uniforms.uScale.value = s;
    this.W = innerWidth; this.H = innerHeight;
  }

  // Россыпь искр
  burst(p, color, n = 12, speed = 10, size = 0.5, life = 0.5, { up = 2, g = 12, drag = 2, spread = 1, grow = 0 } = {}) {
    tmpC.set(color); n = Math.max(1, Math.round(n * this.q));
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, e = (Math.random() * 2 - 1) * spread;
      const sp = speed * (0.4 + Math.random() * 0.6);
      this.glow.emit(p.x, p.y, p.z, Math.cos(a) * sp, e * sp + up, Math.sin(a) * sp, life * (0.6 + Math.random() * 0.6), size * (0.6 + Math.random() * 0.7), tmpC, g, drag, grow);
    }
  }
  puff(p, n = 8, color = 0x8890b0, size = 1.6, life = 0.7, speed = 4) {
    tmpC.set(color); n = Math.max(1, Math.round(n * this.q));
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, sp = speed * (0.3 + Math.random() * 0.7);
      this.dust.emit(p.x + Math.cos(a) * 0.5, p.y + Math.random() * 0.4, p.z + Math.sin(a) * 0.5, Math.cos(a) * sp, Math.random() * 2, Math.sin(a) * sp, life * (0.7 + Math.random() * 0.5), size * (0.6 + Math.random() * 0.6), tmpC, -1, 2.5, 1.2);
    }
  }
  // Пыль, которая сыплется вниз (Судья рассыпается): обычное смешивание, падает под тяжестью
  fall(p, color = 0x9a9aa4, size = 0.6, life = 1.2) {
    tmpC.set(color);
    this.dust.emit(p.x, p.y, p.z, (Math.random() - 0.5) * 0.8, -0.5 - Math.random(), (Math.random() - 0.5) * 0.8, life * (0.7 + Math.random() * 0.5), size, tmpC, 7, 1.5, 0.3);
  }
  spark(x, y, z, vx, vy, vz, life, size, color, g = 0, drag = 0, grow = 0) {
    if (this.q < 1 && Math.random() > this.q) return;
    tmpC.set(color); this.glow.emit(x, y, z, vx, vy, vz, life, size, tmpC, g, drag, grow);
  }
  slash(pos, yaw, color, { tilt = 0, flip = false, scale = 1, life = 0.18, y = 2.6, spin = 3 } = {}) {
    const s = this.slashes.find((o) => o.life <= 0) || this.slashes[0];
    s.m.visible = true; s.t = 0; s.life = life; s.spin = spin * (flip ? -1 : 1); s.yaw = yaw;
    s.m.position.set(pos.x, pos.y + y, pos.z);
    s.m.rotation.set(0, yaw, 0); s.m.rotateZ(tilt);
    s.m.scale.set(flip ? -scale : scale, scale, scale);
    s.m.material.color.set(color); s.m.material.opacity = 1;
  }
  ring(pos, color, r0, r1, life = 0.5, y = 0.1) {
    const r = this.rings.find((o) => o.life <= 0) || this.rings[0];
    r.m.visible = true; r.t = 0; r.life = life; r.r0 = r0; r.r1 = r1;
    r.m.position.set(pos.x, (pos.y || 0) + y, pos.z); r.m.material.color.set(color); r.m.scale.setScalar(r0);
  }
  after(pos, color, h = 6.5, life = 0.35) {
    const a = this.afters.find((o) => o.life <= 0) || this.afters[0];
    a.s.visible = true; a.t = 0; a.life = life; a.h = h;
    a.s.position.set(pos.x, pos.y + h / 2, pos.z); a.s.material.color.set(color);
    a.s.scale.set(h * 0.42, h, 1);
  }
  line(a, b, color, width = 0.18, life = 0.3) {
    const l = this.lines.find((o) => o.life <= 0) || this.lines[0];
    V1.subVectors(b, a); const len = V1.length(); if (len < 0.01) return;
    l.m.visible = true; l.t = 0; l.life = life; l.w = width;
    l.m.position.copy(a);
    l.m.quaternion.setFromUnitVectors(THREE.Object3D.DEFAULT_UP, V1.divideScalar(len));
    l.m.scale.set(width, len, width); l.m.material.color.set(color); l.m.material.opacity = 1;
  }
  flare(pos, color, size = 3, life = 0.25) {
    const f = this.flares.find((o) => o.life <= 0) || this.flares[0];
    f.s.visible = true; f.t = 0; f.life = life; f.size = size;
    f.s.position.copy(pos); f.s.material.color.set(color); f.s.scale.setScalar(size);
  }
  text(pos, str, cls = 'dmg', life = 0.9) {
    const t = this.texts.find((o) => o.life <= 0) || this.texts[0];
    t.pos.set(pos.x + (Math.random() - 0.5) * 1.2, pos.y, pos.z + (Math.random() - 0.5) * 1.2);
    t.t = 0; t.life = life; t.el.className = 'ft ' + cls; t.el.textContent = str; t.el.style.display = 'block';
  }
  // «MISS» сбоку от Судьи на уровне головы/плеч, со стороны камеры; несколько подряд — стопкой
  miss(m, camera) {
    const alive = this.misses.filter((o) => o.life > 0);
    const o = this.misses.find((x) => x.life <= 0) || this.misses[0];
    V2.setFromMatrixColumn(camera.matrixWorld, 0).setY(0).normalize();             // вправо на экране
    V3.set(camera.position.x - m.pos.x, 0, camera.position.z - m.pos.z).normalize(); // к камере
    const side = (m.sideDir.x * V2.x + m.sideDir.z * V2.z) > 0 ? -1 : 1;             // с противоположной шагу стороны
    o.s.position.set(m.pos.x + V2.x * side * 2.9 + V3.x * 1.2, m.pos.y + 5.3 + alive.length * 1.15, m.pos.z + V2.z * side * 2.9 + V3.z * 1.2);
    o.s.visible = true; o.t = 0; o.life = 0.9;
  }
  flash(color = '#fff', a = 0.5) { this.flashEl.style.background = color; this.flashA = Math.max(this.flashA, a); }
  hurt(a = 0.5) { this.vigA = Math.max(this.vigA, a); }
  shake(a) { if (this.shakeOn) this.trauma = Math.min(1, this.trauma + a); }
  setQuality(level) { this.q = level <= 3 ? 0.45 : level <= 7 ? 0.8 + (level - 4) * 0.07 : 1.2; this.shakeOn = shakeEnabled(); if (!this.shakeOn) this.trauma = 0; }
  setDark(k) { this.darkTarget = k; }

  clear() {
    this.glow.clear(); this.dust.clear();
    for (const arr of [this.slashes, this.rings, this.afters, this.lines, this.flares, this.texts, this.misses]) for (const o of arr) { o.life = 0; if (o.m) o.m.visible = false; if (o.s) o.s.visible = false; if (o.el) o.el.style.display = 'none'; }
    this.trauma = 0; this.darkTarget = 0;
  }

  update(dt, camera) {
    this.glow.update(dt); this.dust.update(dt);
    for (const s of this.slashes) if (s.life > 0) {
      s.t += dt; const k = s.t / s.life;
      if (k >= 1) { s.life = 0; s.m.visible = false; continue; }
      s.m.rotateY(s.spin * dt); s.m.material.opacity = 1 - k * k;
    }
    for (const r of this.rings) if (r.life > 0) {
      r.t += dt; const k = r.t / r.life;
      if (k >= 1) { r.life = 0; r.m.visible = false; continue; }
      const e = 1 - Math.pow(1 - k, 3);
      r.m.scale.setScalar(r.r0 + (r.r1 - r.r0) * e); r.m.material.opacity = 1 - k;
    }
    for (const a of this.afters) if (a.life > 0) {
      a.t += dt; const k = a.t / a.life;
      if (k >= 1) { a.life = 0; a.s.visible = false; continue; }
      a.s.material.opacity = 0.85 * (1 - k); a.s.scale.set(a.h * 0.42 * (1 - k * 0.6), a.h * (1 + k * 0.15), 1);
    }
    for (const l of this.lines) if (l.life > 0) {
      l.t += dt; const k = l.t / l.life;
      if (k >= 1) { l.life = 0; l.m.visible = false; continue; }
      l.m.material.opacity = 1 - k; const w = l.w * (1 - k * 0.7); l.m.scale.x = l.m.scale.z = w;
    }
    for (const o of this.misses) if (o.life > 0) { o.t += dt; if (o.t >= o.life) { o.life = 0; o.s.visible = false; } }
    for (const f of this.flares) if (f.life > 0) {
      f.t += dt; const k = f.t / f.life;
      if (k >= 1) { f.life = 0; f.s.visible = false; continue; }
      f.s.material.opacity = 1 - k; f.s.scale.setScalar(f.size * (1 + k * 0.6));
    }
    // всплывающий текст
    for (const t of this.texts) if (t.life > 0) {
      t.t += dt; const k = t.t / t.life;
      if (k >= 1) { t.life = 0; t.el.style.display = 'none'; continue; }
      V1.copy(t.pos); V1.y += k * 2.2; V1.project(camera);
      if (V1.z > 1) { t.el.style.display = 'none'; continue; }
      t.el.style.display = 'block';
      const x = (V1.x * 0.5 + 0.5) * this.W, y = (-V1.y * 0.5 + 0.5) * this.H;
      const sc = k < 0.15 ? 0.6 + (k / 0.15) * 0.6 : 1.2 - Math.min(0.2, (k - 0.15));
      t.el.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) translate(-50%,-50%) scale(${sc.toFixed(2)})`;
      t.el.style.opacity = k > 0.7 ? (1 - k) / 0.3 : 1;
    }
    // экран
    if (this.flashA > 0.01) { this.flashA *= Math.exp(-dt * 9); this.flashEl.style.opacity = this.flashA.toFixed(3); } else if (this.flashA) { this.flashA = 0; this.flashEl.style.opacity = 0; }
    if (this.vigA > 0.01) { this.vigA *= Math.exp(-dt * 3); this.vigEl.style.opacity = this.vigA.toFixed(3); } else if (this.vigA) { this.vigA = 0; this.vigEl.style.opacity = 0; }
    if (Math.abs(this.darkA - this.darkTarget) > 0.005) { this.darkA += (this.darkTarget - this.darkA) * Math.min(1, dt * 3); this.darkEl.style.opacity = this.darkA.toFixed(3); }
    // тряска
    this.trauma = Math.max(0, this.trauma - dt * 1.8);
    const s = this.trauma * this.trauma * 1.1;
    this.shakeOff.set((Math.random() - 0.5) * s, (Math.random() - 0.5) * s, (Math.random() - 0.5) * s);
  }
}

import * as THREE from 'three';

export const rand = (a, b) => a + Math.random() * (b - a);
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const damp = (a, b, k, dt) => a + (b - a) * (1 - Math.exp(-k * dt));
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
export function wrapAngle(a) {
  a = (a + Math.PI) % (Math.PI * 2);
  if (a < 0) a += Math.PI * 2;
  return a - Math.PI;
}
export function angleDamp(a, b, k, dt) {
  return a + wrapAngle(b - a) * (1 - Math.exp(-k * dt));
}
export function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export const ease = {
  out: (t) => 1 - (1 - t) * (1 - t),
  out3: (t) => 1 - Math.pow(1 - t, 3),
  in: (t) => t * t,
  smooth: (t) => t * t * (3 - 2 * t),
};

// ---------- Склейка блоков в одну геометрию (вершинные цвета, опционально UV) ----------
const FACES = [
  { n: [1, 0, 0], c: [[0.5, -0.5, 0.5], [0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [0.5, 0.5, 0.5]] },
  { n: [-1, 0, 0], c: [[-0.5, -0.5, -0.5], [-0.5, -0.5, 0.5], [-0.5, 0.5, 0.5], [-0.5, 0.5, -0.5]] },
  { n: [0, 1, 0], c: [[-0.5, 0.5, 0.5], [0.5, 0.5, 0.5], [0.5, 0.5, -0.5], [-0.5, 0.5, -0.5]] },
  { n: [0, -1, 0], c: [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5]] },
  { n: [0, 0, 1], c: [[-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5]] },
  { n: [0, 0, -1], c: [[0.5, -0.5, -0.5], [-0.5, -0.5, -0.5], [-0.5, 0.5, -0.5], [0.5, 0.5, -0.5]] },
];
export const WHITE_UV = [0.25, 0.1];
export const SKIN_UV = [0.75, 0.1];
export const FACE_UV = [0, 0.2, 1, 1];

const _e = new THREE.Euler(), _q = new THREE.Quaternion(), _m = new THREE.Matrix4();
const _p = new THREE.Vector3(), _s = new THREE.Vector3(), _v = new THREE.Vector3();
const _c = new THREE.Color(), _nm = new THREE.Matrix3();

export class Merger {
  constructor(uv = false) { this.uv = uv; this.p = []; this.n = []; this.c = []; this.t = []; this.i = []; this.vc = 0; }
  // Блок: центр, размер, цвет; o: {rx,ry,rz, uvFront, uvAll, shade}
  box(x, y, z, w, h, d, color, o) {
    _e.set(o?.rx || 0, o?.ry || 0, o?.rz || 0);
    _q.setFromEuler(_e);
    _m.compose(_p.set(x, y, z), _q, _s.set(w, h, d));
    if (o?.m) _m.premultiply(o.m);
    _nm.getNormalMatrix(_m);
    _c.set(color);
    const sh = o?.shade ?? 1;
    for (let f = 0; f < 6; f++) {
      const F = FACES[f];
      const base = this.vc;
      _v.set(F.n[0], F.n[1], F.n[2]).applyMatrix3(_nm).normalize();
      const nx = _v.x, ny = _v.y, nz = _v.z;
      const k = f === 3 ? 0.8 * sh : sh;
      for (let j = 0; j < 4; j++) {
        const c = F.c[j];
        _v.set(c[0], c[1], c[2]).applyMatrix4(_m);
        this.p.push(_v.x, _v.y, _v.z);
        this.n.push(nx, ny, nz);
        this.c.push(_c.r * k, _c.g * k, _c.b * k);
        if (this.uv) {
          if (f === 4 && o?.uvFront) {
            const U = o.uvFront;
            this.t.push(U[0] + (c[0] + 0.5) * (U[2] - U[0]), U[1] + (c[1] + 0.5) * (U[3] - U[1]));
          } else {
            const W = o?.uvAll || WHITE_UV;
            this.t.push(W[0], W[1]);
          }
        }
      }
      this.i.push(base, base + 1, base + 2, base, base + 2, base + 3);
      this.vc += 4;
    }
  }
  // Произвольная геометрия (цилиндры и т.п.)
  geo(geometry, matrix, color) {
    const pa = geometry.attributes.position, na = geometry.attributes.normal;
    _nm.getNormalMatrix(matrix);
    _c.set(color);
    const base = this.vc;
    for (let k = 0; k < pa.count; k++) {
      _v.fromBufferAttribute(pa, k).applyMatrix4(matrix);
      this.p.push(_v.x, _v.y, _v.z);
      _v.fromBufferAttribute(na, k).applyMatrix3(_nm).normalize();
      this.n.push(_v.x, _v.y, _v.z);
      this.c.push(_c.r, _c.g, _c.b);
      if (this.uv) this.t.push(WHITE_UV[0], WHITE_UV[1]);
    }
    if (geometry.index) for (const ix of geometry.index.array) this.i.push(base + ix);
    else for (let k = 0; k < pa.count; k++) this.i.push(base + k);
    this.vc += pa.count;
  }
  cyl(x, y, z, r, h, color, seg = 12, rTop = r) {
    const g = new THREE.CylinderGeometry(rTop, r, h, seg);
    _m.makeTranslation(x, y, z);
    this.geo(g, _m, color);
    g.dispose();
  }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.p, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.n, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.c, 3));
    if (this.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(this.t, 2));
    g.setIndex(this.vc > 65535 ? new THREE.Uint32BufferAttribute(this.i, 1) : new THREE.Uint16BufferAttribute(this.i, 1));
    g.computeBoundingSphere();
    return g;
  }
}

// ---------- Канвас-текстуры ----------
export function canvasTex(w, h, draw, { srgb = true, repeat = false, mip = true } = {}) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  if (!mip) { t.generateMipmaps = false; t.minFilter = THREE.LinearFilter; }
  return t;
}

const texCache = {};
export function tex(name) {
  if (texCache[name]) return texCache[name];
  let t;
  if (name === 'glow') {
    t = canvasTex(64, 64, (g) => {
      const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
      gr.addColorStop(0, 'rgba(255,255,255,1)');
      gr.addColorStop(0.25, 'rgba(255,255,255,.7)');
      gr.addColorStop(0.6, 'rgba(255,255,255,.18)');
      gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
    });
  } else if (name === 'burst') {
    t = canvasTex(128, 128, (g) => {
      g.translate(64, 64);
      const gr = g.createRadialGradient(0, 0, 0, 0, 0, 40);
      gr.addColorStop(0, 'rgba(255,255,255,1)');
      gr.addColorStop(0.35, 'rgba(255,255,255,.75)');
      gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.beginPath(); g.arc(0, 0, 40, 0, 7); g.fill();
      g.fillStyle = '#fff';
      for (let i = 0; i < 14; i++) {
        const a = (i / 14) * Math.PI * 2 + Math.random() * 0.2;
        const L = 34 + Math.random() * 30, w = 2.2 + Math.random() * 2.5;
        g.save(); g.rotate(a);
        g.beginPath(); g.moveTo(0, -w); g.lineTo(L, 0); g.lineTo(0, w); g.closePath(); g.fill();
        g.restore();
      }
    });
  } else if (name === 'slash') {
    t = canvasTex(256, 32, (g, w, h) => {
      const img = g.createImageData(w, h);
      for (let x = 0; x < w; x++) {
        const u = x / (w - 1);
        const tip = Math.min(1, Math.sin(u * Math.PI) * 1.6) * (0.35 + 0.65 * u);
        for (let y = 0; y < h; y++) {
          const v = Math.abs(y / (h - 1) - 0.5) * 2;
          const core = Math.max(0, 1 - v * 3.2);
          const soft = Math.max(0, 1 - v) * 0.5;
          const a = Math.min(1, (core + soft) * tip);
          const i = (y * w + x) * 4;
          img.data[i] = img.data[i + 1] = img.data[i + 2] = 255;
          img.data[i + 3] = a * 255;
        }
      }
      g.putImageData(img, 0, 0);
    });
  } else if (name === 'beam') {
    t = canvasTex(128, 64, (g, w, h) => {
      g.fillStyle = 'rgba(255,255,255,.55)'; g.fillRect(0, 0, w, h);
      for (let i = 0; i < 70; i++) {
        g.fillStyle = `rgba(255,255,255,${0.3 + Math.random() * 0.7})`;
        g.fillRect(Math.random() * w, Math.random() * h, 1 + Math.random() * 4, 8 + Math.random() * 30);
      }
    }, { repeat: true });
  } else if (name === 'void') {
    t = canvasTex(1024, 512, (g, w, h) => {
      g.fillStyle = '#04030c'; g.fillRect(0, 0, w, h);
      const blobs = [['#3b1d7a', 0.45], ['#123a8a', 0.4], ['#6a2a9a', 0.3], ['#0a5a8a', 0.3]];
      for (let i = 0; i < 26; i++) {
        const [col, a] = blobs[i % blobs.length];
        const x = Math.random() * w, y = h * 0.2 + Math.random() * h * 0.6, r = 60 + Math.random() * 160;
        const gr = g.createRadialGradient(x, y, 0, x, y, r);
        gr.addColorStop(0, col); gr.addColorStop(1, 'rgba(0,0,0,0)');
        g.globalAlpha = a; g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
      }
      g.globalAlpha = 1;
      for (let i = 0; i < 1400; i++) {
        const s = Math.random() < 0.06 ? 2.5 : Math.random() < 0.3 ? 1.5 : 1;
        g.fillStyle = `rgba(255,255,255,${0.4 + Math.random() * 0.6})`;
        g.fillRect(Math.random() * w, Math.random() * h, s, s);
      }
      // светящаяся «река информации» по экватору
      const gr = g.createLinearGradient(0, h * 0.44, 0, h * 0.56);
      gr.addColorStop(0, 'rgba(160,200,255,0)'); gr.addColorStop(0.5, 'rgba(210,230,255,.55)'); gr.addColorStop(1, 'rgba(160,200,255,0)');
      g.fillStyle = gr; g.fillRect(0, h * 0.44, w, h * 0.12);
    });
  } else if (name === 'shrine') {
    t = canvasTex(256, 256, (g, w) => {
      const c = w / 2;
      const gr = g.createRadialGradient(c, c, 0, c, c, c);
      gr.addColorStop(0, 'rgba(120,0,10,.85)');
      gr.addColorStop(0.75, 'rgba(90,0,8,.6)');
      gr.addColorStop(0.97, 'rgba(255,40,40,.9)');
      gr.addColorStop(1, 'rgba(255,40,40,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, w);
      g.strokeStyle = 'rgba(255,90,90,.5)'; g.lineWidth = 2;
      for (let i = 0; i < 40; i++) {
        const a = Math.random() * 7, r0 = Math.random() * c * 0.8, L = 20 + Math.random() * 50;
        g.beginPath();
        g.moveTo(c + Math.cos(a) * r0, c + Math.sin(a) * r0);
        g.lineTo(c + Math.cos(a + 0.5) * (r0 + L), c + Math.sin(a + 0.5) * (r0 + L));
        g.stroke();
      }
    });
  } else if (name === 'crack') {
    t = canvasTex(256, 256, (g, w) => {
      const c = w / 2;
      const gr = g.createRadialGradient(c, c, 0, c, c, c);
      gr.addColorStop(0, 'rgba(30,24,20,.75)'); gr.addColorStop(0.35, 'rgba(45,38,30,.45)'); gr.addColorStop(1, 'rgba(40,35,30,0)');
      g.fillStyle = gr; g.fillRect(0, 0, w, w);
      g.strokeStyle = 'rgba(20,16,12,.85)'; g.lineCap = 'round';
      for (let i = 0; i < 13; i++) {
        let a = (i / 13) * Math.PI * 2 + Math.random() * 0.3, r = 10, x = c, y = c;
        g.lineWidth = 2.5 + Math.random() * 2.5;
        g.beginPath(); g.moveTo(x, y);
        while (r < c * (0.6 + Math.random() * 0.35)) {
          r += 10 + Math.random() * 14; a += (Math.random() - 0.5) * 0.5;
          x = c + Math.cos(a) * r; y = c + Math.sin(a) * r; g.lineTo(x, y);
        }
        g.stroke();
      }
    });
  } else if (name === 'grass') {
    t = canvasTex(128, 128, (g, w, h) => {
      g.fillStyle = '#5ea548'; g.fillRect(0, 0, w, h);
      for (let i = 0; i < 900; i++) {
        const v = Math.random();
        g.fillStyle = v < 0.5 ? 'rgba(40,90,30,.16)' : 'rgba(170,220,120,.14)';
        const s = 2 + Math.floor(Math.random() * 4);
        g.fillRect(Math.floor(Math.random() * w), Math.floor(Math.random() * h), s, s);
      }
    }, { repeat: true });
  }
  texCache[name] = t;
  return t;
}

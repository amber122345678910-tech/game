// Эффекты: пулы частиц (Points), искры-полосы и молнии (InstancedMesh), обломки, вспышки, кольца, сферы, разрезы.
import * as THREE from 'three';
import { tex, rand } from './util.js';

const _c = new THREE.Color();
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _p = new THREE.Vector3(), _s = new THREE.Vector3(), _d = new THREE.Vector3();
const Z = new THREE.Vector3(0, 0, 1);
const _e = new THREE.Euler();

function lin(hex) { _c.set(hex); return _c; }
function srgb(hex) { _c.set(hex).convertLinearToSRGB(); return _c; }

// ---------- Частицы-точки ----------
class PSys {
  constructor(scene, max, additive, soft) {
    this.max = max;
    this.pos = new Float32Array(max * 3); this.vel = new Float32Array(max * 3);
    this.rgba = new Float32Array(max * 4); this.col = new Float32Array(max * 3);
    this.size = new Float32Array(max); this.s0 = new Float32Array(max); this.s1 = new Float32Array(max);
    this.life = new Float32Array(max); this.maxLife = new Float32Array(max);
    this.grav = new Float32Array(max); this.drag = new Float32Array(max); this.a0 = new Float32Array(max);
    this.next = 0; this.alive = 0;
    const g = new THREE.BufferGeometry();
    this.aPos = new THREE.BufferAttribute(this.pos, 3); this.aPos.setUsage(THREE.DynamicDrawUsage);
    this.aCol = new THREE.BufferAttribute(this.rgba, 4); this.aCol.setUsage(THREE.DynamicDrawUsage);
    this.aSize = new THREE.BufferAttribute(this.size, 1); this.aSize.setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.aPos); g.setAttribute('rgba', this.aCol); g.setAttribute('size', this.aSize);
    this.uni = { uScale: { value: 400 }, uSoft: { value: soft ? 1 : 0 } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uni, transparent: true, depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      vertexShader: `attribute float size; attribute vec4 rgba; varying vec4 vC; uniform float uScale;
        void main(){ vC = rgba; vec4 mv = modelViewMatrix * vec4(position,1.0);
        gl_PointSize = size > 0.0 ? min(size * uScale / max(0.3,-mv.z), 180.0) : 0.0; gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `varying vec4 vC; uniform float uSoft;
        void main(){ vec2 d = gl_PointCoord - 0.5; float r = length(d) * 2.0;
        float a = uSoft > 0.5 ? (1.0 - smoothstep(0.15, 1.0, r)) : (1.0 - smoothstep(0.85, 1.0, r));
        if (a < 0.01) discard; gl_FragColor = vec4(vC.rgb, vC.a * a); }`,
    });
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = additive ? 5 : 4;
    scene.add(this.points);
  }
  spawn(x, y, z, vx, vy, vz, color, a, s0, s1, life, grav = 0, drag = 0) {
    const i = this.next; this.next = (i + 1) % this.max;
    const i3 = i * 3;
    this.pos[i3] = x; this.pos[i3 + 1] = y; this.pos[i3 + 2] = z;
    this.vel[i3] = vx; this.vel[i3 + 1] = vy; this.vel[i3 + 2] = vz;
    const c = srgb(color);
    this.col[i3] = c.r; this.col[i3 + 1] = c.g; this.col[i3 + 2] = c.b;
    this.a0[i] = a; this.s0[i] = s0; this.s1[i] = s1;
    this.life[i] = this.maxLife[i] = life; this.grav[i] = grav; this.drag[i] = drag;
  }
  update(dt) {
    let alive = 0;
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) { if (this.size[i] !== 0) this.size[i] = 0; continue; }
      alive++;
      const l = (this.life[i] -= dt);
      if (l <= 0) { this.size[i] = 0; continue; }
      const i3 = i * 3;
      const dr = Math.exp(-this.drag[i] * dt);
      this.vel[i3] *= dr; this.vel[i3 + 1] = this.vel[i3 + 1] * dr - this.grav[i] * dt; this.vel[i3 + 2] *= dr;
      this.pos[i3] += this.vel[i3] * dt; this.pos[i3 + 1] += this.vel[i3 + 1] * dt; this.pos[i3 + 2] += this.vel[i3 + 2] * dt;
      const k = 1 - l / this.maxLife[i];
      this.size[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * k;
      const i4 = i * 4;
      this.rgba[i4] = this.col[i3]; this.rgba[i4 + 1] = this.col[i3 + 1]; this.rgba[i4 + 2] = this.col[i3 + 2];
      this.rgba[i4 + 3] = this.a0[i] * (1 - k * k);
    }
    this.alive = alive;
    this.aPos.needsUpdate = this.aCol.needsUpdate = this.aSize.needsUpdate = true;
  }
}

// ---------- Полосы (искры, молнии, следы) ----------
class Streaks {
  constructor(scene, max, additive) {
    this.max = max;
    const mat = additive
      ? new THREE.MeshBasicMaterial({ color: 0xffffff, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, fog: false })
      : new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false });
    this.mesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), mat, max);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 6;
    this.additive = additive;
    for (let i = 0; i < max; i++) { this.mesh.setMatrixAt(i, _m.makeScale(0, 0, 0)); this.mesh.setColorAt(i, _c.setRGB(0, 0, 0)); }
    scene.add(this.mesh);
    this.d = [];
    for (let i = 0; i < max; i++) this.d.push({ life: 0, max: 1, p: new THREE.Vector3(), v: new THREE.Vector3(), dir: new THREE.Vector3(0, 0, 1), w: 0.1, len: 1, r: 1, g: 1, b: 1, drag: 0, grav: 0, stat: false });
    this.next = 0;
  }
  add(p, v, color, life, w, len, { stat = false, dir = null, drag = 3, grav = 0 } = {}) {
    const s = this.d[this.next]; this.next = (this.next + 1) % this.max;
    s.p.copy(p); s.v.copy(v); s.life = s.max = life; s.w = w; s.len = len; s.drag = drag; s.grav = grav; s.stat = stat;
    if (dir) s.dir.copy(dir).normalize(); else if (v.lengthSq() > 1e-6) s.dir.copy(v).normalize();
    const c = lin(color); s.r = c.r; s.g = c.g; s.b = c.b;
    return s;
  }
  update(dt) {
    const mesh = this.mesh;
    let any = false;
    for (let i = 0; i < this.max; i++) {
      const s = this.d[i];
      if (s.life <= 0) { if (s.max > 0) { s.max = 0; mesh.setMatrixAt(i, _m.makeScale(0, 0, 0)); any = true; } continue; }
      s.life -= dt; any = true;
      if (s.life <= 0) { mesh.setMatrixAt(i, _m.makeScale(0, 0, 0)); continue; }
      const k = s.life / s.max;
      if (!s.stat) {
        const dr = Math.exp(-s.drag * dt);
        s.v.multiplyScalar(dr); s.v.y -= s.grav * dt;
        s.p.addScaledVector(s.v, dt);
        if (s.v.lengthSq() > 1e-4) s.dir.copy(s.v).normalize();
      }
      _q.setFromUnitVectors(Z, s.dir);
      const w = this.additive ? s.w : s.w * k;
      _m.compose(s.p, _q, _s.set(w, w, s.len * (this.additive ? (0.4 + 0.6 * k) : 1)));
      mesh.setMatrixAt(i, _m);
      if (this.additive) mesh.setColorAt(i, _c.setRGB(s.r * k, s.g * k, s.b * k));
      else mesh.setColorAt(i, _c.setRGB(s.r, s.g, s.b));
    }
    if (any) { mesh.instanceMatrix.needsUpdate = true; if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true; }
  }
}

// ---------- Обломки ----------
class Debris {
  constructor(scene, max) {
    this.max = max;
    this.mesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshLambertMaterial({ color: 0xffffff }), max);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    for (let i = 0; i < max; i++) { this.mesh.setMatrixAt(i, _m.makeScale(0, 0, 0)); this.mesh.setColorAt(i, _c.set(0x888888)); }
    scene.add(this.mesh);
    this.d = [];
    for (let i = 0; i < max; i++) this.d.push({ life: 0, p: new THREE.Vector3(), v: new THREE.Vector3(), r: new THREE.Vector3(), w: new THREE.Vector3(), s: 1 });
    this.next = 0;
  }
  add(p, v, color, size, life) {
    const i = this.next; this.next = (i + 1) % this.max;
    const d = this.d[i];
    d.p.copy(p); d.v.copy(v); d.life = life; d.s = size;
    d.r.set(rand(0, 6), rand(0, 6), rand(0, 6)); d.w.set(rand(-9, 9), rand(-9, 9), rand(-9, 9));
    this.mesh.setColorAt(i, _c.set(color));
    this.mesh.instanceColor.needsUpdate = true;
  }
  update(dt) {
    let any = false;
    for (let i = 0; i < this.max; i++) {
      const d = this.d[i];
      if (d.life <= 0) continue;
      any = true;
      d.life -= dt;
      if (d.life <= 0) { this.mesh.setMatrixAt(i, _m.makeScale(0, 0, 0)); continue; }
      d.v.y -= 70 * dt;
      d.p.addScaledVector(d.v, dt);
      const half = d.s * 0.5;
      if (d.p.y < half) { d.p.y = half; d.v.y *= -0.35; d.v.x *= 0.6; d.v.z *= 0.6; d.w.multiplyScalar(0.6); }
      d.r.addScaledVector(d.w, dt);
      const sc = d.s * Math.min(1, d.life / 0.4);
      _q.setFromEuler(_e.set(d.r.x, d.r.y, d.r.z));
      _m.compose(d.p, _q, _s.set(sc, sc, sc));
      this.mesh.setMatrixAt(i, _m);
    }
    if (any) this.mesh.instanceMatrix.needsUpdate = true;
  }
}

// ---------- Геометрия «полумесяц» для разрезов ----------
function crescentGeo(arc = 2.4, segs = 20, rin = 0.82, rout = 1.12) {
  const pos = [], uv = [], idx = [];
  for (let i = 0; i <= segs; i++) {
    const u = i / segs, th = -arc / 2 + arc * u;
    const w = Math.sin(u * Math.PI);
    const r0 = 1 - (1 - rin) * w, r1 = 1 + (rout - 1) * w;
    pos.push(Math.sin(th) * r0, 0, Math.cos(th) * r0 - 1, Math.sin(th) * r1, 0, Math.cos(th) * r1 - 1);
    uv.push(u, 0, u, 1);
    if (i < segs) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  return g;
}

export class FX {
  constructor(scene, camera) {
    this.scene = scene; this.camera = camera;
    this.add = new PSys(scene, 1600, true, true);
    this.norm = new PSys(scene, 700, false, true);
    this.str = new Streaks(scene, 260, true);
    this.dark = new Streaks(scene, 160, false);
    this.deb = new Debris(scene, 110);
    this.anims = [];
    this.pools = {};
    this.k = 1; // множитель количества частиц (качество графики)
    this.geo = {
      ring: new THREE.RingGeometry(0.82, 1, 48),
      hex: new THREE.RingGeometry(0.7, 1, 6),
      disc: new THREE.CircleGeometry(1, 40),
      sphere: new THREE.SphereGeometry(1, 24, 16),
      cres: crescentGeo(),
      cyl: new THREE.CylinderGeometry(1, 1, 1, 20, 1, true),
      plane: new THREE.PlaneGeometry(2, 2),
    };
  }
  setScale(h, fov) {
    const s = h / (2 * Math.tan((fov * Math.PI) / 360));
    this.add.uni.uScale.value = s; this.norm.uni.uScale.value = s;
  }
  // --- пулы мешей ---
  pool(kind) {
    const list = (this.pools[kind] ||= []);
    let it = list.find((i) => !i.active);
    if (!it) {
      let obj, mat;
      const add = { blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, fog: false };
      if (kind === 'glow' || kind === 'burst') {
        mat = new THREE.SpriteMaterial({ map: tex(kind), ...add });
        obj = new THREE.Sprite(mat);
      } else if (kind === 'ring' || kind === 'hex') {
        mat = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide, ...add });
        obj = new THREE.Mesh(this.geo[kind], mat);
      } else if (kind === 'disc') {
        // плоский непрозрачный «стёртый» круг на земле (Lapse Blue MAX)
        mat = new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 });
        obj = new THREE.Mesh(this.geo.disc, mat);
      } else if (kind === 'sphere') {
        mat = new THREE.MeshBasicMaterial(add);
        obj = new THREE.Mesh(this.geo.sphere, mat);
      } else if (kind === 'sphereN') {
        mat = new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, fog: false });
        obj = new THREE.Mesh(this.geo.sphere, mat);
      } else if (kind === 'cres') {
        mat = new THREE.MeshBasicMaterial({ map: tex('slash'), side: THREE.DoubleSide, ...add });
        obj = new THREE.Mesh(this.geo.cres, mat);
      } else if (kind === 'cresN') {
        mat = new THREE.MeshBasicMaterial({ map: tex('slash'), side: THREE.DoubleSide, transparent: true, depthWrite: false, fog: false });
        obj = new THREE.Mesh(this.geo.cres, mat);
      } else if (kind === 'crater') {
        mat = new THREE.MeshBasicMaterial({ map: tex('crack'), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
        obj = new THREE.Mesh(this.geo.plane, mat);
      } else if (kind === 'beam') {
        mat = new THREE.MeshBasicMaterial({ map: tex('beam'), side: THREE.DoubleSide, ...add });
        mat.map = mat.map.clone(); mat.map.needsUpdate = true;
        obj = new THREE.Mesh(this.geo.cyl, mat);
      }
      obj.frustumCulled = false;
      obj.renderOrder = kind === 'crater' || kind === 'disc' ? 1 : 7;
      this.scene.add(obj);
      it = { obj, mat, active: false };
      list.push(it);
    }
    it.active = true;
    it.obj.visible = true;
    it.obj.scale.setScalar(1);
    it.obj.rotation.set(0, 0, 0);
    it.mat.opacity = 1;
    if (kind !== 'crater' && it.mat.color) it.mat.color.set(0xffffff);
    if (kind === 'disc') it.obj.rotation.set(-Math.PI / 2, 0, 0);
    return it;
  }
  release(it) { it.active = false; it.obj.visible = false; }

  // Анимированный пул-объект: s0→s1, a0→a1 за life
  animate(kind, pos, color, s0, s1, life, o = {}) {
    const it = this.pool(kind);
    it.obj.position.copy(pos);
    it.mat.color.set(color);
    if (kind === 'burst' || kind === 'glow') it.mat.rotation = o.rot ?? rand(0, 6.28);
    const a = { it, t: 0, life, s0, s1, a0: o.a0 ?? 1, a1: o.a1 ?? 0, follow: o.follow || null, off: o.off ? o.off.clone() : null, axis: o.axis || null, spin: o.spin || 0, easeK: o.ease ?? 3, delay: o.delay || 0, sx: o.sx || null };
    if (o.quat) it.obj.quaternion.copy(o.quat);
    else if (a.axis === 'y') it.obj.rotation.set(-Math.PI / 2, 0, 0);
    else if (a.axis && a.axis.isVector3) { it.obj.quaternion.setFromUnitVectors(Z, _d.copy(a.axis).normalize()); }
    this.setAnim(a, 0);
    if (a.delay > 0) it.obj.visible = false;
    this.anims.push(a);
    return a;
  }
  setAnim(a, k) {
    const e = 1 - Math.pow(1 - k, a.easeK);
    const s = a.s0 + (a.s1 - a.s0) * e;
    if (a.sx) a.it.obj.scale.set(s * a.sx[0], s * a.sx[1], s * a.sx[2]);
    else a.it.obj.scale.setScalar(s);
    a.it.mat.opacity = a.fadeTail ? Math.min(1, (1 - k) * a.life / a.fadeTail) : a.a0 + (a.a1 - a.a0) * k;
  }

  // --- удобные функции ---
  glow(pos, color, size, life, o = {}) { return this.animate('glow', pos, color, o.s0 ?? size * 0.6, size, life, o); }
  burst(pos, color, size, life = 0.18, o = {}) { return this.animate('burst', pos, color, size * 0.35, size, life, { ease: 4, ...o }); }
  ring(pos, color, r0, r1, life, o = {}) { return this.animate('ring', pos, color, r0, r1, life, { axis: o.axis ?? 'cam', ...o }); }
  hex(pos, color, r0, r1, life, o = {}) { return this.animate('hex', pos, color, r0, r1, life, { axis: o.axis ?? 'cam', spin: 6, ...o }); }
  sphere(pos, color, r0, r1, life, o = {}) { return this.animate(o.normal ? 'sphereN' : 'sphere', pos, color, r0, r1, life, o); }
  crescent(pos, quat, color, s0, s1, life, o = {}) { return this.animate(o.normal ? 'cresN' : 'cres', pos, color, s0, s1, life, { quat, ...o }); }

  // Кратер-трещины на земле
  crater(pos, size = 6, life = 4) {
    const a = this.animate('crater', pos, '#ffffff', size, size, life, { a0: 1, a1: 1, axis: 'y' });
    a.it.obj.position.y = Math.max(0.12, pos.y);
    a.it.obj.rotation.z = rand(0, 6.28);
    a.fadeTail = 1;
    return a;
  }
  sparks(pos, dir, color, n = 8, speed = 40, o = {}) {
    n = Math.max(1, Math.round(n * this.k));
    for (let i = 0; i < n; i++) {
      _d.set(rand(-1, 1), rand(-0.6, 1), rand(-1, 1)).normalize();
      if (dir) _d.multiplyScalar(o.spread ?? 0.7).add(dir).normalize();
      _p.copy(_d).multiplyScalar(speed * rand(0.5, 1.2));
      this.str.add(pos, _p, color, rand(0.12, 0.28) * (o.lifeK ?? 1), o.w ?? 0.12, o.len ?? rand(1.2, 2.4), { drag: 6, grav: o.grav ?? 20 });
    }
  }
  particles(pos, o) {
    const n = Math.max(1, Math.round((o.n ?? 10) * this.k)), sys = o.normal ? this.norm : this.add;
    const sp = o.speed ?? 10, up = o.up ?? 0, sz = o.size ?? 1;
    for (let i = 0; i < n; i++) {
      let vx = rand(-1, 1), vy = rand(-1, 1), vz = rand(-1, 1);
      const l = Math.hypot(vx, vy, vz) || 1;
      const s = sp * rand(0.4, 1) / l;
      vx *= s; vy = vy * s + up; vz *= s;
      if (o.dir) { vx += o.dir.x * (o.dirSpeed ?? sp); vy += o.dir.y * (o.dirSpeed ?? sp); vz += o.dir.z * (o.dirSpeed ?? sp); }
      const r = o.radius ?? 0;
      const ox = r ? rand(-r, r) : 0, oy = r ? rand(-r, r) * (o.flatY ? 0 : 1) : 0, oz = r ? rand(-r, r) : 0;
      const col = Array.isArray(o.color) ? o.color[i % o.color.length] : o.color;
      sys.spawn(pos.x + ox, pos.y + oy, pos.z + oz, vx, vy, vz, col, o.alpha ?? 1, sz * rand(0.7, 1.2), (o.size1 ?? sz * 0.2) * rand(0.7, 1.2), (o.life ?? 0.5) * rand(0.7, 1.2), o.grav ?? 0, o.drag ?? 2);
    }
  }
  dust(pos, n = 8, size = 2.5, color = '#d8cfbf') {
    this.particles(pos, { n, normal: true, color, speed: 8, up: 3, size: size * 0.6, size1: size * 1.6, life: 0.8, drag: 4, alpha: 0.55, radius: 0.8, flatY: true });
  }
  debris(pos, n = 8, colors = ['#7d7468', '#5ea548', '#9a8f80'], speed = 22, size = null) {
    n = Math.max(1, Math.round(n * this.k));
    const s0 = size ? size[0] : 0.35, s1 = size ? size[1] : 0.9;
    for (let i = 0; i < n; i++) {
      _d.set(rand(-1, 1), rand(0.6, 1.6), rand(-1, 1)).normalize().multiplyScalar(speed * rand(0.5, 1.1));
      this.deb.add(pos, _d, colors[i % colors.length], rand(s0, s1), rand(1.0, 1.8));
    }
  }
  bolt(a, b, color, o = {}) {
    const segs = o.segs ?? 7, jag = o.jag ?? 1.2;
    const sys = o.dark ? this.dark : this.str;
    let px = a.x, py = a.y, pz = a.z;
    for (let i = 1; i <= segs; i++) {
      const t = i / segs;
      let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t;
      if (i < segs) { x += rand(-jag, jag); y += rand(-jag, jag); z += rand(-jag, jag); }
      _d.set(x - px, y - py, z - pz);
      const len = _d.length();
      _p.set((x + px) / 2, (y + py) / 2, (z + pz) / 2);
      sys.add(_p, _s.set(0, 0, 0), color, o.life ?? 0.22, o.w ?? 0.22, len, { stat: true, dir: _d });
      px = x; py = y; pz = z;
    }
  }
  line(a, b, color, life, w, dark = false) {
    _d.subVectors(b, a); const len = _d.length();
    _p.addVectors(a, b).multiplyScalar(0.5);
    (dark ? this.dark : this.str).add(_p, _s.set(0, 0, 0), color, life, w, len, { stat: true, dir: _d });
  }
  // Сброс всех эффектов (новый матч)
  clear() {
    for (const k in this.pools) for (const it of this.pools[k]) this.release(it);
    this.anims.length = 0;
    for (const sys of [this.add, this.norm]) sys.life.fill(0);
    for (const st of [this.str, this.dark]) for (const d of st.d) d.life = 0;
    for (const d of this.deb.d) d.life = 0;
  }
  update(dt, camera) {
    this.add.update(dt); this.norm.update(dt); this.str.update(dt); this.dark.update(dt); this.deb.update(dt);
    for (let i = this.anims.length - 1; i >= 0; i--) {
      const a = this.anims[i];
      if (a.delay > 0) { a.delay -= dt; if (a.delay <= 0) a.it.obj.visible = true; else continue; }
      a.t += dt;
      const k = Math.min(1, a.t / a.life);
      if (a.follow) { a.it.obj.position.copy(a.follow); if (a.off) a.it.obj.position.add(a.off); }
      if (a.axis === 'cam') a.it.obj.quaternion.copy(camera.quaternion);
      if (a.spin) { if (a.it.mat.rotation !== undefined && a.it.obj.isSprite) a.it.mat.rotation += a.spin * dt; else a.it.obj.rotateZ(a.spin * dt); }
      this.setAnim(a, k);
      if (k >= 1) { this.release(a.it); this.anims[i] = this.anims[this.anims.length - 1]; this.anims.pop(); }
    }
  }
}

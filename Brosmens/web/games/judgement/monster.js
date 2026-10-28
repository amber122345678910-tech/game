// Атаки Судьи: черепа-бластеры, волны и кольца костей, гравитация, «Последняя атака», удар костью, телепорт.
import * as THREE from 'three';
import { buildSkull, boneGeometry, BONE_H } from './models.js';
import { stripTex, glowTex } from './fx.js';
import { damageHuman, dist2, clamp, lerp, easeOut, easeIn, angleTo } from './combat.js';
import { ARENA_HALF } from './data.js';

const V = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);
const rand = (a, b) => a + Math.random() * (b - a);

// ---------- общие ресурсы (пулы) ----------
export function initMonsterAssets(G) {
  const scene = G.scene;
  const A = {};
  // кости (инстансы)
  const geo = boneGeometry();
  A.meshes = [
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xf6f8ff, emissive: 0x4a5a90, emissiveIntensity: 0.7 }), 900),
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0x2f8cff, emissive: 0x1a5cff, emissiveIntensity: 1.1 }), 500),
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xff9a2a, emissive: 0xff6a00, emissiveIntensity: 0.9 }), 400),
  ];
  A.caps = [900, 500, 400]; A.n = [0, 0, 0];
  for (const m of A.meshes) { m.instanceMatrix.setUsage(THREE.DynamicDrawUsage); m.frustumCulled = false; m.count = 0; scene.add(m); }
  // полосы-телеграфы на полу
  const sg = new THREE.PlaneGeometry(1, 1); sg.rotateX(-Math.PI / 2);
  A.strips = [];
  for (let i = 0; i < 34; i++) {
    const m = new THREE.Mesh(sg, new THREE.MeshBasicMaterial({ map: stripTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    m.visible = false; m.renderOrder = 2; scene.add(m); A.strips.push({ m, used: false });
  }
  // бластеры
  const beamGeo = new THREE.CylinderGeometry(1, 1, 1, 16, 1, true); beamGeo.rotateX(Math.PI / 2); beamGeo.translate(0, 0, 0.5);
  A.blasters = [];
  for (let i = 0; i < 22; i++) {
    const sk = buildSkull(); sk.group.visible = false; scene.add(sk.group);
    const beam = new THREE.Group(); beam.visible = false; scene.add(beam);
    const mk = (c, op) => { const m = new THREE.Mesh(beamGeo, new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: op, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide })); beam.add(m); return m; };
    const core = mk(0xffffff, 0.95), mid = mk(0x8fe8ff, 0.32), haze = mk(0x2f8bff, 0.1);
    const flare = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xcff8ff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
    flare.visible = false; flare.renderOrder = 7; scene.add(flare);
    A.blasters.push({ sk, beam, core, mid, haze, flare, used: false });
  }
  // кольца гравитации
  const rg = new THREE.RingGeometry(0.82, 1, 40); rg.rotateX(-Math.PI / 2);
  A.gRings = [];
  for (let i = 0; i < 5; i++) {
    const m = new THREE.Mesh(rg, new THREE.MeshBasicMaterial({ color: 0x3f7bff, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    const inner = new THREE.Mesh(new THREE.CircleGeometry(1, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x2050ff, transparent: true, opacity: 0.18, depthWrite: false, blending: THREE.AdditiveBlending }));
    m.add(inner); m.visible = false; m.renderOrder = 2; scene.add(m); A.gRings.push({ m, inner, used: false });
  }
  G.ma = A;
}
const take = (arr) => { const o = arr.find((x) => !x.used); if (o) o.used = true; return o; };

export function bonesBegin(G) { G.ma.n[0] = G.ma.n[1] = G.ma.n[2] = 0; }
// type: 0 — белая (перепрыгнуть), 1 — синяя (стой), 2 — оранжевая (двигайся)
function boneAdd(G, x, y, z, type, c, s) {
  const A = G.ma, i = A.n[type];
  if (i >= A.caps[type]) return;
  const a = A.meshes[type].instanceMatrix.array, o = i * 16;
  a[o] = c; a[o + 1] = 0; a[o + 2] = -s; a[o + 3] = 0; a[o + 4] = 0; a[o + 5] = 1; a[o + 6] = 0; a[o + 7] = 0;
  a[o + 8] = s; a[o + 9] = 0; a[o + 10] = c; a[o + 11] = 0; a[o + 12] = x; a[o + 13] = y; a[o + 14] = z; a[o + 15] = 1;
  A.n[type]++;
}
export function bonesEnd(G) {
  const A = G.ma;
  A.meshes.forEach((m, t) => {
    const n = A.n[t]; m.count = n;
    m.instanceMatrix.clearUpdateRanges(); m.instanceMatrix.addUpdateRange(0, Math.max(16, n * 16)); m.instanceMatrix.needsUpdate = true;
  });
}
export const BONE_COL = [0xdfe8ff, 0x3f8bff, 0xff9a2a];
const BONE_CAUSE = ['кости', 'синие кости', 'оранжевые кости'];
// синие бьют только движущихся, оранжевые — только стоящих
function boneSafe(h, type) {
  const moving = h.hspeed() >= 2.5 || h.dashT > 0;
  return (type === 1 && !moving) || (type === 2 && moving);
}

function humansAlive(G) { return G.humans.filter((h) => !h.dead); }
export function nearestHuman(G, p, maxD = 999, exclude = null) {
  let best = null, bd = maxD;
  for (const h of G.humans) { if (h.dead || h === exclude) continue; const d = dist2(p, h.pos); if (d < bd) { bd = d; best = h; } }
  return best;
}

// ---------- Череп-бластер ----------
const APPEAR = 0.32, FIRE = 0.5, FADE = 0.32;
export class Blaster {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'blaster';
    this.from = o.from.clone(); this.pos = o.pos.clone(); this.pos.y = o.y ?? 3.3;
    this.dir = new THREE.Vector3(o.aim.x - this.pos.x, 0, o.aim.z - this.pos.z).normalize();
    this.yaw = Math.atan2(this.dir.x, this.dir.z);
    this.tele = o.tele ?? 0.85; this.R = o.R ?? 1.75; this.dmg = o.dmg ?? 28; this.len = o.len ?? 110;
    this.t = -(o.delay || 0); this.hit = new Set(); this.vis = null; this.strip = null; this.fired = false;
    this.origin = new THREE.Vector3().copy(this.pos).addScaledVector(this.dir, 2.6);
  }
  get phase() { const t = this.t; return t < 0 ? 'wait' : t < APPEAR ? 'appear' : t < APPEAR + this.tele ? 'tele' : t < APPEAR + this.tele + FIRE ? 'fire' : 'fade'; }
  timeToFire() { return APPEAR + this.tele - this.t; }
  dangerous() { const t = this.t; return t > -0.1 && t < APPEAR + this.tele + FIRE; }
  update(dt) {
    const G = this.G; this.t += dt;
    const t = this.t; if (t < 0) return true;
    if (!this.vis) {
      this.vis = take(G.ma.blasters); this.strip = take(G.ma.strips);
      if (!this.vis) return false;
      this.vis.sk.group.visible = true;
      G.sfx('charge', 0.35, null, 0.12);
    }
    const v = this.vis, sk = v.sk, end = APPEAR + this.tele + FIRE + FADE;
    if (t >= end) { this.dispose(); return false; }
    const ph = this.phase;
    // череп
    if (ph === 'appear') {
      const k = easeOut(t / APPEAR);
      sk.group.position.lerpVectors(this.from, this.pos, k);
      sk.group.rotation.set(0, this.yaw + (1 - k) * Math.PI * 2, 0);
      sk.inner.scale.setScalar(1.55 * k);
      sk.jaw.rotation.x = 0;
    } else {
      sk.group.position.copy(this.pos);
      sk.group.rotation.set(0, this.yaw, 0);
      sk.inner.scale.setScalar(1.55);
    }
    let eye = 0.1;
    if (ph === 'tele') {
      const k = (t - APPEAR) / this.tele;
      sk.jaw.rotation.x = 0.45 * easeIn(k);
      eye = 0.4 + k * 1.1;
      if (k > 0.7) sk.group.position.x += (Math.random() - 0.5) * 0.15;
      if (Math.random() < 0.6) { // частицы втягиваются в пасть
        const a = Math.random() * Math.PI * 2, r = 2.5 + Math.random() * 1.5;
        V.set(this.origin.x + Math.cos(a) * r, this.origin.y + Math.sin(a) * r, this.origin.z);
        G.fx.spark(V.x, V.y, V.z, (this.origin.x - V.x) * 3, (this.origin.y - V.y) * 3, (this.origin.z - V.z) * 3, 0.3, 0.6, 0x9fefff);
      }
    } else if (ph === 'fire' || ph === 'fade') {
      const kf = ph === 'fire' ? (t - APPEAR - this.tele) / FIRE : 1;
      sk.jaw.rotation.x = 0.85;
      eye = 1.6;
      sk.group.position.addScaledVector(this.dir, -Math.min(1, kf * 4) * 1.3);
      if (ph === 'fade') { const kd = (t - APPEAR - this.tele - FIRE) / FADE; sk.inner.scale.setScalar(1.55 * (1 - kd * 0.9)); sk.group.position.y += kd * 2; eye = 1.6 * (1 - kd); }
    }
    for (const e of sk.eyes) e.scale.setScalar(eye * (0.9 + Math.random() * 0.2));
    // полоса-телеграф
    const st = this.strip?.m;
    if (st) {
      if (ph === 'appear' || ph === 'tele') {
        const k = ph === 'appear' ? t / APPEAR * 0.3 : 0.3 + ((t - APPEAR) / this.tele) * 0.7;
        st.visible = true;
        st.position.set(this.origin.x + this.dir.x * this.len / 2, 0.07, this.origin.z + this.dir.z * this.len / 2);
        st.rotation.y = this.yaw;
        st.scale.set(this.R * 2 + 0.6, 1, this.len);
        const flick = 0.75 + 0.25 * Math.sin(t * (20 + k * 30));
        st.material.opacity = (0.2 + k * 0.45) * flick;
        st.material.color.setHex(k > 0.85 ? 0xcff4ff : 0x5fc8ff);
      } else st.visible = false;
    }
    // луч
    if (ph === 'fire' || ph === 'fade') {
      if (!this.fired) {
        this.fired = true;
        G.sfx('beam', 0.45, null, 0.09);
        V.copy(this.origin);
        const cf = G.camFocus;
        if (cf && !cf.dead) { const d = this.lineDist(cf.pos); if (d < 14) { G.fx.shake(0.3); if (d < 5) G.fx.flash('#cfefff', 0.25); } }
      }
      const b = v.beam; b.visible = true;
      b.position.copy(sk.group.position).addScaledVector(this.dir, 2.4); b.position.y = this.origin.y - 0.1;
      b.rotation.set(0, this.yaw, 0);
      let r;
      if (ph === 'fire') { const kf = (t - APPEAR - this.tele) / FIRE; r = this.R * Math.min(1, 0.3 + kf * 10) * (0.94 + Math.random() * 0.12); }
      else { const kd = (t - APPEAR - this.tele - FIRE) / FADE; r = this.R * (1 - kd) * (0.9 + Math.random() * 0.1); }
      b.scale.set(1, 1, this.len);
      v.core.scale.set(r * 0.42, r * 0.42, 1); v.mid.scale.set(r * 0.78, r * 0.78, 1); v.haze.scale.set(r * 1.15, r * 1.15, 1);
      v.flare.visible = true; v.flare.position.copy(b.position); v.flare.scale.setScalar(r * 3.2);
      // искры вдоль луча по полу
      for (let i = 0; i < 3; i++) {
        const d = Math.random() * 60;
        V.copy(b.position).addScaledVector(this.dir, d);
        G.fx.spark(V.x + (Math.random() - 0.5) * r * 2, 0.2, V.z + (Math.random() - 0.5) * r * 2, 0, 3 + Math.random() * 5, 0, 0.4, 0.5, 0xbff4ff);
      }
      if (ph === 'fire') this.checkHits();
    }
    return true;
  }
  lineDist(p) {
    const rx = p.x - this.origin.x, rz = p.z - this.origin.z;
    const along = rx * this.dir.x + rz * this.dir.z;
    if (along < -1.5 || along > this.len) return 999;
    return Math.abs(rx * this.dir.z - rz * this.dir.x);
  }
  checkHits() {
    const G = this.G;
    for (const h of G.humans) {
      if (h.dead || this.hit.has(h) || h.pos.y > 7) continue;
      if (this.lineDist(h.pos) < this.R + h.radius * 0.6) {
        const side = Math.sign((h.pos.x - this.origin.x) * this.dir.z - (h.pos.z - this.origin.z) * this.dir.x) || 1;
        V2.set(this.dir.z * side * 9 + this.dir.x * 6, 0, -this.dir.x * side * 9 + this.dir.z * 6);
        if (damageHuman(G, h, this.dmg, this.owner, { kb: V2, color: 0xbff4ff, cause: 'бластер' })) this.hit.add(h);
      }
    }
  }
  dispose() {
    if (this.vis) { const v = this.vis; v.used = false; v.sk.group.visible = false; v.beam.visible = false; v.flare.visible = false; this.vis = null; }
    if (this.strip) { this.strip.used = false; this.strip.m.visible = false; this.strip = null; }
  }
}

// ---------- Ряд костей ----------
export class BoneRow {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'row';
    this.origin = o.origin.clone(); this.origin.y = 0;
    this.dir = o.dir.clone().setY(0).normalize();
    this.perp = new THREE.Vector3(-this.dir.z, 0, this.dir.x);
    this.halfW = o.halfW ?? 18; this.speed = o.speed ?? 16; this.type = o.type ?? (o.blue ? 1 : 0);
    this.travel = o.travel ?? 75; this.rise = o.rise ?? 0.55; this.dmg = o.dmg ?? 10;
    this.t = -(o.delay || 0); this.s = 0; this.riseK = 0; this.sinkT = 0; this.strip = null; this.sounded = false;
  }
  get moving() { return this.t >= this.rise && this.sinkT === 0; }
  get blue() { return this.type === 1; }
  update(dt) {
    const G = this.G; this.t += dt;
    if (this.t < 0) return true;
    if (!this.sounded) { this.sounded = true; G.sfx('bone', 0.5, null, 0.06); this.strip = take(G.ma.strips); }
    if (this.t < this.rise) this.riseK = easeOut(this.t / this.rise);
    else if (this.s < this.travel) { this.riseK = 1; this.s += this.speed * dt; }
    else { this.sinkT += dt; this.riseK = Math.max(0, 1 - this.sinkT / 0.3); if (this.sinkT > 0.3) { this.dispose(); return false; } }
    // полоса на полу под рядом
    const cx = this.origin.x + this.dir.x * this.s, cz = this.origin.z + this.dir.z * this.s;
    if (this.strip) {
      const m = this.strip.m; m.visible = true;
      m.position.set(cx, 0.08, cz); m.rotation.y = Math.atan2(this.perp.x, this.perp.z);
      m.scale.set(1.7, 1, this.halfW * 2 + 1);
      m.material.color.setHex(BONE_COL[this.type]);
      m.material.opacity = (this.t < this.rise ? 0.4 + 0.5 * Math.abs(Math.sin(this.t * 25)) : 0.55) * this.riseK + (this.t < this.rise ? 0.3 : 0);
    }
    // след
    if (this.riseK > 0.5 && Math.random() < 0.9) {
      const w = (Math.random() * 2 - 1) * this.halfW;
      G.fx.spark(cx + this.perp.x * w - this.dir.x * 0.6, 0.3, cz + this.perp.z * w - this.dir.z * 0.6, -this.dir.x * 2, 2 + Math.random() * 3, -this.dir.z * 2, 0.45, 0.55, BONE_COL[this.type]);
      if (Math.random() < 0.3) { V.set(cx + this.perp.x * w, 0, cz + this.perp.z * w); G.fx.puff(V, 1, 0x5a6690, 1.2, 0.5, 1.5); }
    }
    if (this.riseK > 0.55) this.checkHits(cx, cz);
    return true;
  }
  checkHits(cx, cz) {
    const G = this.G, now = G.time;
    for (const h of G.humans) {
      if (h.dead || now < h.boneImmuneUntil || h.grab) continue;
      const rx = h.pos.x - cx, rz = h.pos.z - cz;
      const along = rx * this.dir.x + rz * this.dir.z, across = rx * this.perp.x + rz * this.perp.z;
      if (Math.abs(along) > 0.3 + h.radius * 0.8 || Math.abs(across) > this.halfW + 0.4) continue;
      if (h.pos.y > BONE_H * this.riseK - 0.25) continue;
      if (boneSafe(h, this.type)) continue;
      V2.copy(this.dir).multiplyScalar(8);
      if (damageHuman(G, h, this.dmg, this.owner, { kb: V2, lift: 9, color: BONE_COL[this.type], cause: BONE_CAUSE[this.type] })) h.boneImmuneUntil = now + 0.7;
    }
  }
  draw(G) {
    if (this.t < 0 || this.riseK <= 0) return;
    const n = Math.floor((this.halfW * 2) / 1.2) + 1, y = -BONE_H * (1 - this.riseK);
    const bx = this.origin.x + this.dir.x * this.s, bz = this.origin.z + this.dir.z * this.s;
    const c = this.perp.x, s = -this.perp.z;
    for (let i = 0; i < n; i++) {
      const w = -this.halfW + i * 1.2, wob = Math.sin(i * 1.7) * 0.12;
      boneAdd(G, bx + this.perp.x * w + this.dir.x * wob, y + Math.sin(i * 2.3) * 0.08, bz + this.perp.z * w + this.dir.z * wob, this.type, c, s);
    }
  }
  dispose() { if (this.strip) { this.strip.used = false; this.strip.m.visible = false; this.strip = null; } }
}

// ---------- Кольцо костей ----------
export class BoneRing {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'ring';
    this.c = o.center.clone(); this.c.y = 0; this.r = o.r0 ?? 4.4; this.rMax = o.rMax ?? 40;
    this.speed = o.speed ?? 13; this.type = o.type ?? (o.blue ? 1 : 0); this.rise = o.rise ?? 0.6; this.dmg = o.dmg ?? 10;
    this.t = -(o.delay || 0); this.riseK = 0; this.sinkT = 0; this.off = Math.random() * 6; this.sounded = false;
  }
  get blue() { return this.type === 1; }
  update(dt) {
    const G = this.G; this.t += dt;
    if (this.t < 0) return true;
    if (!this.sounded) { this.sounded = true; G.sfx('bone', 0.6, null, 0.06); G.fx.ring(this.c, BONE_COL[this.type], this.r, this.r + 1.5, 0.5); }
    if (this.t < this.rise) this.riseK = easeOut(this.t / this.rise);
    else if (this.r < this.rMax) { this.riseK = 1; this.r += this.speed * dt; }
    else { this.sinkT += dt; this.riseK = Math.max(0, 1 - this.sinkT / 0.3); if (this.sinkT > 0.3) return false; }
    if (this.riseK > 0.5) {
      for (let i = 0; i < 2; i++) {
        const a = Math.random() * Math.PI * 2;
        G.fx.spark(this.c.x + Math.cos(a) * this.r, 0.3, this.c.z + Math.sin(a) * this.r, Math.cos(a) * 2, 2 + Math.random() * 3, Math.sin(a) * 2, 0.4, 0.55, BONE_COL[this.type]);
      }
    }
    if (this.riseK > 0.55 && this.dmg > 0) {
      const now = G.time;
      for (const h of G.humans) {
        if (h.dead || now < h.boneImmuneUntil || h.grab) continue;
        const d = dist2(h.pos, this.c);
        if (Math.abs(d - this.r) > 0.3 + h.radius * 0.8) continue;
        if (h.pos.y > BONE_H * this.riseK - 0.25) continue;
        if (boneSafe(h, this.type)) continue;
        V2.set(h.pos.x - this.c.x, 0, h.pos.z - this.c.z).normalize().multiplyScalar(8);
        if (damageHuman(G, h, this.dmg, this.owner, { kb: V2, lift: 9, color: BONE_COL[this.type], cause: BONE_CAUSE[this.type] })) h.boneImmuneUntil = now + 0.7;
      }
    }
    return true;
  }
  draw(G) {
    if (this.t < 0 || this.riseK <= 0) return;
    const n = clamp(Math.floor((Math.PI * 2 * this.r) / 1.3), 8, 200), y = -BONE_H * (1 - this.riseK);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + this.off;
      boneAdd(G, this.c.x + Math.cos(a) * this.r, y, this.c.z + Math.sin(a) * this.r, this.type, -Math.sin(a), -Math.cos(a));
    }
  }
  dispose() {}
}

// ---------- Гравитация (синяя душа) ----------
const MARK = 0.7, FOLLOW = 0.32, LIFT = 0.5, HOLD = 0.16, SLAM = 0.16;
export class Gravity {
  constructor(G, owner, target) {
    this.G = G; this.owner = owner; this.target = target; this.kind = 'gravity';
    this.t = 0; this.phase = 'mark'; this.ringPos = target.pos.clone(); this.ringPos.y = 0;
    this.ring = take(G.ma.gRings); this.R = 3.3;
    this.liftFrom = new THREE.Vector3(); this.slamTo = new THREE.Vector3(); this.done = false;
  }
  timeToLock() { return MARK - this.t; }
  update(dt) {
    const G = this.G, tg = this.target; this.t += dt;
    if (this.phase === 'mark') {
      if (this.t < FOLLOW && !tg.dead) { this.ringPos.x = lerp(this.ringPos.x, tg.pos.x, 1 - Math.exp(-14 * dt)); this.ringPos.z = lerp(this.ringPos.z, tg.pos.z, 1 - Math.exp(-14 * dt)); }
      if (this.ring) {
        const k = this.t / MARK, m = this.ring.m; m.visible = true;
        m.position.set(this.ringPos.x, 0.09, this.ringPos.z);
        m.scale.setScalar(this.R * (1.5 - 0.5 * easeOut(Math.min(1, k * 1.6))));
        m.material.opacity = 0.6 + 0.4 * Math.abs(Math.sin(this.t * (10 + k * 25)));
        m.material.color.setHex(this.t > FOLLOW ? 0x6fa0ff : 0x3f7bff);
        this.ring.inner.material.opacity = 0.12 + k * 0.25;
        if (Math.random() < 0.5) { const a = Math.random() * 7; G.fx.spark(this.ringPos.x + Math.cos(a) * this.R, 0.2, this.ringPos.z + Math.sin(a) * this.R, 0, 6, 0, 0.4, 0.5, 0x4f8bff); }
      }
      if (this.t >= MARK) {
        if (!tg.dead && !tg.grab && G.time >= tg.iframeUntil && dist2(tg.pos, this.ringPos) < this.R + 0.4 && G.state === 'fight') {
          this.phase = 'lift'; this.t = 0; tg.grab = this; tg.cancelAction(); tg.dashT = 0; tg.hv.set(0, 0, 0); tg.kb.set(0, 0, 0);
          this.liftFrom.copy(tg.pos);
          // куда швырнуть: к Судье или от него — в пределах арены
          V.subVectors(this.owner.pos, tg.pos).setY(0); const d = V.length();
          if (d > 0.1) V.divideScalar(d); else V.set(1, 0, 0);
          const L = ARENA_HALF - 2;
          this.slamTo.set(clamp(tg.pos.x + V.x * Math.min(8, d * 0.5), -L, L), 0, clamp(tg.pos.z + V.z * Math.min(8, d * 0.5), -L, L));
          G.sfx('charge', 0.5, tg); G.fx.ring(tg.pos, 0x3f7bff, 1, 5, 0.4);
          G.onEvent('grabbed', { h: tg, m: this.owner });
        } else {
          if (!tg.dead) G.fx.text(V.set(tg.pos.x, tg.pos.y + 5.5, tg.pos.z), 'УВЕРНУЛСЯ', 'miss', 0.7);
          this.dispose(); return false;
        }
      }
      return true;
    }
    if (this.ring) this.ring.m.visible = false;
    if (tg.dead || tg.grab !== this) { this.release(); return false; }
    if (this.phase === 'lift' && this.t >= LIFT + HOLD) { this.phase = 'slam'; this.t = 0; G.sfx('swing', 0.7, tg); }
    if (this.phase === 'slam' && this.t >= SLAM) {
      tg.pos.copy(this.slamTo);
      this.release();
      tg.stunUntil = G.time + 0.4;
      G.fx.ring(tg.pos, 0x3f7bff, 1, 9, 0.5); G.fx.ring(tg.pos, 0xffffff, 0.5, 5, 0.35);
      G.fx.puff(tg.pos, 14, 0x6070a0, 2.2, 0.8, 8);
      G.fx.burst(V.set(tg.pos.x, 0.5, tg.pos.z), 0xdfe8ff, 18, 14, 0.6, 0.5, { up: 10 });
      G.sfx('heavy', 0.9, tg);
      if (tg === G.camFocus) G.fx.shake(0.7);
      damageHuman(G, tg, 24, this.owner, { color: 0x3f7bff, cause: 'гравитация', unblockable: true });
      // шипы костей на месте удара
      G.hazards.push(new BoneRing(G, this.owner, { center: tg.pos, r0: 1.5, rMax: 5, speed: 18, rise: 0.12, dmg: 0 }));
      return false;
    }
    return true;
  }
  drive(h, dt) {
    if (this.phase === 'lift') {
      const k = easeOut(Math.min(1, this.t / LIFT));
      h.pos.set(this.liftFrom.x, this.liftFrom.y + k * 10, this.liftFrom.z);
      h.pos.x += Math.sin(this.t * 40) * 0.08;
      if (Math.random() < 0.6) this.G.fx.spark(h.pos.x, h.pos.y + 2, h.pos.z, (Math.random() - 0.5) * 3, -4, (Math.random() - 0.5) * 3, 0.4, 0.8, 0x3f7bff);
    } else if (this.phase === 'slam') {
      const k = easeIn(Math.min(1, this.t / SLAM));
      V.copy(this.liftFrom); V.y += 10;
      h.pos.lerpVectors(V, this.slamTo, k);
    }
    h.vy = 0; h.onGround = false;
  }
  release() { const tg = this.target; if (tg.grab === this) { tg.grab = null; tg.vy = 0; } this.dispose(); }
  dispose() { if (this.ring) { this.ring.used = false; this.ring.m.visible = false; this.ring = null; } }
}

// ---------- Последняя атака (ульта) ----------
export class LastAttack {
  constructor(G, owner) {
    this.G = G; this.owner = owner; this.kind = 'ult'; this.t = 0; this.step = 0;
    const m = owner;
    G.fx.after(m.pos, 0xffe040, 8, 0.5);
    m.pos.set(0, 0, 0); m.hv.set(0, 0, 0); m.kb.set(0, 0, 0);
    G.fx.ring(m.pos, 0xffe040, 2, 30, 1.2); G.fx.ring(m.pos, 0x3fe0ff, 1, 20, 0.9);
    m.startAction({ name: 'ult', dur: 9.8, lock: true, moveMul: 0, float: 3, pose: ultPose });
    G.fx.setDark(0.55); G.world.setDark(1); G.fx.flash('#ffffff', 0.6); G.fx.shake(0.5);
    G.sfx('boom', 0.9); G.sfx('charge', 0.6);
    this.events = [
      [0.7, () => this.ringBlasters(10, 38)],
      [3.0, () => this.crossRows()],
      [5.0, () => this.huntBlasters()],
      [7.0, () => G.hazards.push(new BoneRing(G, m, { center: V3.set(0, 0, 0), r0: 4.5, rMax: 46, speed: 14 }))],
      [7.7, () => G.hazards.push(new BoneRing(G, m, { center: V3.set(0, 0, 0), r0: 4.5, rMax: 46, speed: 14, type: 2 }))],
      [8.4, () => G.hazards.push(new BoneRing(G, m, { center: V3.set(0, 0, 0), r0: 4.5, rMax: 46, speed: 14 }))],
    ];
  }
  ringBlasters(n, R) {
    const G = this.G, hs = humansAlive(G), off = Math.random() * 6;
    for (let i = 0; i < n; i++) {
      const a = off + (i / n) * Math.PI * 2;
      V.set(Math.cos(a) * R, 0, Math.sin(a) * R);
      let aim;
      if (hs.length && i % 2 === 0) { const h = hs[(i / 2) % hs.length]; aim = V2.copy(h.pos).addScaledVector(h.hv, 0.35); }
      else aim = V2.set((Math.random() - 0.5) * 24, 0, (Math.random() - 0.5) * 24);
      G.hazards.push(new Blaster(G, this.owner, { from: V3.set(0, 8, 0), pos: V, aim, delay: i * 0.13, tele: 0.95 }));
    }
  }
  crossRows() {
    const G = this.G, a = Math.random() * Math.PI * 2;
    const d1 = new THREE.Vector3(Math.cos(a), 0, Math.sin(a)), d2 = new THREE.Vector3(-d1.z, 0, d1.x);
    const o1 = d1.clone().multiplyScalar(-(ARENA_HALF - 1)), o2 = d2.clone().multiplyScalar(-(ARENA_HALF - 1));
    G.hazards.push(new BoneRow(G, this.owner, { origin: o1, dir: d1, halfW: ARENA_HALF + 6, speed: 15, travel: 90 }));
    G.hazards.push(new BoneRow(G, this.owner, { origin: o1, dir: d1, halfW: ARENA_HALF + 6, speed: 15, travel: 90, blue: true, delay: 0.9 }));
    G.hazards.push(new BoneRow(G, this.owner, { origin: o2, dir: d2, halfW: ARENA_HALF + 6, speed: 15, travel: 90, delay: 0.45 }));
  }
  huntBlasters() {
    const G = this.G, hs = humansAlive(G);
    hs.forEach((h, i) => {
      for (let k = 0; k < 2; k++) {
        const a = Math.random() * Math.PI * 2;
        V.set(h.pos.x + Math.cos(a) * 18, 0, h.pos.z + Math.sin(a) * 18);
        V2.copy(h.pos).addScaledVector(h.hv, 0.3);
        if (k) V2.addScaledVector(V3.set(-Math.sin(a), 0, Math.cos(a)), (Math.random() < 0.5 ? -1 : 1) * 3.5);
        G.hazards.push(new Blaster(G, this.owner, { from: V3.set(0, 8, 0), pos: V, aim: V2, delay: i * 0.18 + k * 0.3, tele: 0.85 }));
      }
    });
  }
  update(dt) {
    const G = this.G; this.t += dt;
    while (this.step < this.events.length && this.t >= this.events[this.step][0]) { if (!this.owner.dead) this.events[this.step][1](); this.step++; }
    this.owner.glow = 1;
    if (this.t > 9.8 || this.owner.dead || G.state !== 'fight') { this.dispose(); return false; }
    return true;
  }
  dispose() { this.G.fx.setDark(0); this.G.world.setDark(0); }
}

// ---------- позы Судьи ----------
function ultPose(p, k, a, f) {
  p.armL.rotation.set(-2.7, 0, -0.5); p.armR.rotation.set(-2.7, 0, 0.5);
  p.legL.rotation.x = 0.3; p.legR.rotation.x = 0.1; p.neck.rotation.x = -0.2;
  p.hips.position.y = 2 + Math.sin(f.animT * 3) * 0.15;
}
function summonPose(p, k) {
  const e = easeOut(Math.min(1, k * 2));
  p.armR.rotation.set(-2.6 * e, 0, 0.3 * e); p.armL.rotation.set(-0.6 * e, 0, -0.4 * e); p.neck.rotation.x = -0.15 * e;
}
function bonesPose(p, k) {
  const e = k < 0.4 ? k / 0.4 : 1;
  p.armL.rotation.set(lerp(0.7, -2.0, easeOut(e)), 0, -0.4); p.armR.rotation.set(lerp(0.7, -2.0, easeOut(e)), 0, 0.4);
  p.hips.rotation.x = lerp(0.35, -0.1, e);
}
function gravPose(p, k) {
  p.armR.rotation.set(-1.55, 0, 0); p.armL.rotation.set(-0.3, 0, -0.3); p.neck.rotation.y = 0.2;
  if (k > 0.6) p.armR.rotation.x = lerp(-1.55, -2.8, (k - 0.6) / 0.4);
}

// ---------- способности Судьи (для игрока и бота) ----------
export function monsterM1(G, m) {
  if (!m.canAct() || !m.ready('m1')) return false;
  const combo = G.time < m.comboUntil ? (m.combo + 1) % 3 : 0; m.combo = combo;
  const last = combo === 2, dur = last ? 0.52 : 0.42;
  m.use('m1', dur + (last ? 0.7 : 0.05)); m.comboUntil = G.time + dur + 0.55;
  const t = nearestHuman(G, m.pos, 9);
  if (t && angleTo(m, t.pos) < 1.6) m.faceTo(t.pos, true);
  m.model.club.visible = true;
  m.startAction({
    name: 'm1', dur, lock: true, moveMul: 0.45,
    pose(p, k) {
      const e = easeOut(k);
      if (combo === 1) { p.armR.rotation.set(-1.4, 0, lerp(-1.0, 1.4, e)); p.hips.rotation.y = lerp(-0.5, 0.5, e); }
      else if (combo === 0) { p.armR.rotation.set(-1.4, 0, lerp(1.4, -1.0, e)); p.hips.rotation.y = lerp(0.5, -0.5, e); }
      else { p.armR.rotation.set(lerp(-3.0, -0.5, easeIn(k)), 0, 0.2); p.hips.rotation.x = lerp(-0.2, 0.35, k); }
    },
    update(f, t) {
      if (!this.hit && t > dur * 0.45) {
        this.hit = true;
        G.fx.slash(f.pos, f.yaw, 0xdfeaff, { tilt: last ? Math.PI / 2 : combo ? 0.3 : -0.3, flip: combo === 1, scale: 1.5, y: 3.4 });
        G.sfx('swing', 0.6, f);
        f.fwd(V);
        for (const h of G.humans) {
          if (h.dead) continue;
          if (dist2(h.pos, f.pos) - h.radius > 5.3 || angleTo(f, h.pos) > 0.95 || Math.abs(h.pos.y - f.pos.y) > 5) continue;
          V2.copy(V).multiplyScalar(last ? 26 : 6);
          damageHuman(G, h, last ? 12 : 7, f, { kb: V2, lift: last ? 12 : 0, cause: 'кость' });
        }
      }
    },
    end(f) { f.model.club.visible = false; },
  });
  return true;
}

export function monsterTeleport(G, m, dir) {
  if (m.dead || !m.ready('dash') || m.grab || m.stunned || m.busy || G.state !== 'fight') return false;
  m.use('dash', 3.5);
  G.fx.after(m.pos, 0x5fb4ff, 7.5, 0.4);
  G.fx.burst(V.set(m.pos.x, 3, m.pos.z), 0x8fd0ff, 12, 8, 0.6, 0.35);
  V.copy(dir).setY(0); if (V.lengthSq() < 0.01) m.fwd(V); V.normalize();
  const L = ARENA_HALF - m.radius;
  m.pos.x = clamp(m.pos.x + V.x * 13, -L, L); m.pos.z = clamp(m.pos.z + V.z * 13, -L, L);
  m.yaw = m.targetYaw = Math.atan2(V.x, V.z);
  G.fx.burst(V.set(m.pos.x, 3, m.pos.z), 0x8fd0ff, 12, 8, 0.6, 0.35);
  G.sfx('tp', 0.7, m);
  return true;
}

// targets — люди по приоритету
export function castBlasters(G, m, targets) {
  if (!m.canAct() || !m.ready('s1')) return false;
  targets = (targets || humansAlive(G).sort((a, b) => dist2(a.pos, m.pos) - dist2(b.pos, m.pos))).filter((h) => !h.dead && dist2(h.pos, m.pos) < 80);
  if (!targets.length) return false;
  const n = clamp(targets.length + 1, 2, 6);
  m.use('s1', 8); m.glow = 1;
  m.startAction({ name: 'summon', dur: 0.45, lock: true, moveMul: 0.3, pose: summonPose });
  const L = ARENA_HALF + 3;
  for (let i = 0; i < n; i++) {
    const tg = targets[i % targets.length];
    const aim = V2.copy(tg.pos).addScaledVector(tg.hv, 0.3);
    const base = Math.atan2(m.pos.z - tg.pos.z, m.pos.x - tg.pos.x);
    const a = base + (Math.random() < 0.5 ? -1 : 1) * rand(0.35, 1.5) + (i >= targets.length ? Math.PI * 0.5 : 0);
    const r = rand(15, 19);
    V.set(clamp(aim.x + Math.cos(a) * r, -L, L), 0, clamp(aim.z + Math.sin(a) * r, -L, L));
    // не вешаем череп прямо перед камерой — уводим на другую сторону цели
    const cp = G.camera.position;
    if (Math.hypot(V.x - cp.x, V.z - cp.z) < 10) V.set(clamp(aim.x - Math.cos(a) * r, -L, L), 0, clamp(aim.z - Math.sin(a) * r, -L, L));
    if (i >= targets.length) { // дополнительный череп отрезает путь отхода
      const px = -(aim.z - V.z), pz = aim.x - V.x, pl = Math.hypot(px, pz) || 1, s = (Math.random() < 0.5 ? -1 : 1) * 4;
      aim.x += (px / pl) * s; aim.z += (pz / pl) * s;
    }
    G.hazards.push(new Blaster(G, m, { from: V3.set(m.pos.x, m.pos.y + 6, m.pos.z), pos: V, aim, delay: i * 0.14 }));
  }
  G.onEvent('mcast', { m, what: 'blasters' });
  return true;
}

export function castBones(G, m, dir, forceRing = false) {
  if (!m.canAct() || !m.ready('s2')) return false;
  m.use('s2', 6); m.glow = 1;
  m.startAction({ name: 'bones', dur: 0.5, lock: true, moveMul: 0.15, pose: bonesPose });
  G.fx.ring(m.pos, 0xffffff, 1, 7, 0.45); G.fx.puff(m.pos, 10, 0x6070a0, 2, 0.6, 7);
  const close = G.humans.filter((h) => !h.dead && dist2(h.pos, m.pos) < 9).length;
  if (forceRing || close >= 2) {
    G.hazards.push(new BoneRing(G, m, { center: m.pos, delay: 0.15 }));
    G.hazards.push(new BoneRing(G, m, { center: m.pos, delay: 0.95, type: Math.random() < 0.5 ? 1 : 2 }));
  } else {
    const d = V.copy(dir).setY(0).normalize();
    m.yaw = m.targetYaw = Math.atan2(d.x, d.z);
    const o = V2.copy(m.pos).addScaledVector(d, 2.2);
    const special = Math.floor(Math.random() * 4), sType = Math.random() < 0.55 ? 1 : 2; // один ряд синий/оранжевый (иногда нет)
    for (let i = 0; i < 3; i++) G.hazards.push(new BoneRow(G, m, { origin: o, dir: d, halfW: 17, delay: 0.12 + i * 0.6, type: i === special ? sType : 0, speed: 16 }));
  }
  G.onEvent('mcast', { m, what: 'bones' });
  return true;
}

export function castGravity(G, m, target) {
  if (!m.canAct() || !m.ready('s3') || !target || target.dead) return false;
  m.use('s3', 10); m.glow = 1;
  m.faceTo(target.pos, true);
  m.startAction({ name: 'grav', dur: 0.7, lock: true, moveMul: 0.3, pose: gravPose, face: target });
  G.hazards.push(new Gravity(G, m, target));
  G.onEvent('gravity', { m, h: target });
  return true;
}

export function castUlt(G, m) {
  if (m.ult < 100 || !m.canAct()) return false;
  m.ult = 0; m.glow = 1;
  G.hazards.push(new LastAttack(G, m));
  G.onEvent('ult', { m });
  return true;
}

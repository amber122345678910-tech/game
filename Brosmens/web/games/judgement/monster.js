// Атаки Судьи (как у классического Санса в UJD): Бластер (череп рядом, луч через зал), Крест бластеров (4 черепа сверху),
// Зона костей (красный квадрат → частокол), Бросок костей (веер), Синяя атака (≈20 с стены костей едут поперёк зала),
// Отталкивание (все люди отлетают, без урона). Только у бота: Стена костей и Круг бластеров (один раз на ≤3 уклонениях).
// Ни удара в ближнем бою, ни телепорта, ни ульты — как у оригинала. Урон — тиками 10 Гц + карма.
import * as THREE from 'three';
import { buildSkull, boneGeometry, BONE_H } from './models.js';
import { stripTex, glowTex } from './fx.js';
import { damageHuman, dist2, clamp, lerp, easeOut, easeIn, angleTo, arenaCollide, clampToHall, clearance } from './combat.js';
import { HALL_X, HALL_Z, HALL_H, FORCE_H, FORCE_V } from './data.js';

const V = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3(), V4 = new THREE.Vector3();
const rand = (a, b) => a + Math.random() * (b - a);
const TICK = 0.1; // интервал тикового урона по одной цели, с

// ---------- общие ресурсы (пулы) ----------
export function initMonsterAssets(G) {
  const scene = G.scene;
  const A = {};
  // кости (инстансы): белые / голубые («стой») / оранжевые («двигайся»)
  const geo = boneGeometry();
  A.meshes = [
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xf4f4f8, emissive: 0x8a8a98, emissiveIntensity: 0.55 }), 900),
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0x5ff6ff, emissive: 0x00c8e8, emissiveIntensity: 1.0 }), 500),
    new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xffb030, emissive: 0xff7a00, emissiveIntensity: 0.9 }), 400),
  ];
  A.caps = [900, 500, 400]; A.n = [0, 0, 0];
  for (const m of A.meshes) { m.instanceMatrix.setUsage(THREE.DynamicDrawUsage); m.frustumCulled = false; m.count = 0; scene.add(m); }
  // красные рельсы-телеграфы «Зоны костей»
  A.rails = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshLambertMaterial({ color: 0xff0000, emissive: 0xc00000, emissiveIntensity: 0.8 }), 96);
  A.rails.instanceMatrix.setUsage(THREE.DynamicDrawUsage); A.rails.frustumCulled = false; A.rails.count = 0; A.railN = 0; scene.add(A.rails);
  // полосы-телеграфы на полу
  const sg = new THREE.PlaneGeometry(1, 1); sg.rotateX(-Math.PI / 2);
  A.strips = [];
  for (let i = 0; i < 34; i++) {
    const m = new THREE.Mesh(sg, new THREE.MeshBasicMaterial({ map: stripTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    m.visible = false; m.renderOrder = 2; scene.add(m); A.strips.push({ m, used: false });
  }
  // бластеры: череп + луч (ядро/середина/ореол) + вспышка у пасти + вспышка в точке попадания
  const beamGeo = new THREE.CylinderGeometry(1, 1, 1, 16, 1, true); beamGeo.rotateX(Math.PI / 2); beamGeo.translate(0, 0, 0.5);
  A.blasters = [];
  for (let i = 0; i < 22; i++) {
    const sk = buildSkull(); sk.group.visible = false; scene.add(sk.group);
    const beam = new THREE.Group(); beam.visible = false; beam.rotation.order = 'YXZ'; scene.add(beam);
    const mk = (c, op) => { const m = new THREE.Mesh(beamGeo, new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: op, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide })); beam.add(m); return m; };
    const core = mk(0xffffff, 1), mid = mk(0xf2fbff, 0.45), haze = mk(0xbfeaff, 0.16);
    const spr = (c) => { const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: c, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false })); s.visible = false; s.renderOrder = 7; scene.add(s); return s; };
    A.blasters.push({ sk, beam, core, mid, haze, flare: spr(0xeafcff), hitF: spr(0xffffff), used: false });
  }
  G.ma = A;
}
const take = (arr) => { const o = arr.find((x) => !x.used); if (o) o.used = true; return o; };

// ---------- инстансы костей и рельс (заполняются заново каждый кадр) ----------
export function bonesBegin(G) { G.ma.n[0] = G.ma.n[1] = G.ma.n[2] = 0; G.ma.railN = 0; }
// Вертикальная кость: поворот вокруг Y (c = cos, s = sin), sy — масштаб длины, sw — толщины.
// type: 0 — белая (перепрыгнуть/уйти), 1 — голубая (стой), 2 — оранжевая (двигайся)
function boneAdd(G, x, y, z, type, c, s, sy = 1, sw = 1) {
  const A = G.ma, i = A.n[type];
  if (i >= A.caps[type]) return;
  const a = A.meshes[type].instanceMatrix.array, o = i * 16;
  a[o] = c * sw; a[o + 1] = 0; a[o + 2] = -s * sw; a[o + 3] = 0; a[o + 4] = 0; a[o + 5] = sy; a[o + 6] = 0; a[o + 7] = 0;
  a[o + 8] = s * sw; a[o + 9] = 0; a[o + 10] = c * sw; a[o + 11] = 0; a[o + 12] = x; a[o + 13] = y; a[o + 14] = z; a[o + 15] = 1;
  A.n[type]++;
}
// Брусок рельсы (оси совпадают с осями мира)
function railAdd(G, x, y, z, sx, sy, sz) {
  const A = G.ma, i = A.railN;
  if (i >= 96) return;
  const a = A.rails.instanceMatrix.array, o = i * 16;
  a[o] = sx; a[o + 1] = 0; a[o + 2] = 0; a[o + 3] = 0; a[o + 4] = 0; a[o + 5] = sy; a[o + 6] = 0; a[o + 7] = 0;
  a[o + 8] = 0; a[o + 9] = 0; a[o + 10] = sz; a[o + 11] = 0; a[o + 12] = x; a[o + 13] = y; a[o + 14] = z; a[o + 15] = 1;
  A.railN++;
}
export function bonesEnd(G) {
  const A = G.ma;
  const fin = (m, n) => { m.count = n; m.visible = n > 0; m.instanceMatrix.clearUpdateRanges(); m.instanceMatrix.addUpdateRange(0, Math.max(16, n * 16)); m.instanceMatrix.needsUpdate = true; };
  A.meshes.forEach((m, t) => fin(m, A.n[t]));
  fin(A.rails, A.railN);
}
export const BONE_COL = [0xeef0ff, 0x3ff2ff, 0xffa020];
const BONE_CAUSE = ['кости', 'синие кости', 'оранжевые кости'];
// синие бьют только движущихся, оранжевые — только стоящих
export function boneSafe(h, type) {
  const moving = h.hspeed() >= 2.5 || h.flung || !h.onGround;
  return (type === 1 && !moving) || (type === 2 && moving);
}

function humansAlive(G) { return G.humans.filter((h) => !h.dead); }
export function nearestHuman(G, p, maxD = 999, exclude = null) {
  let best = null, bd = maxD;
  for (const h of G.humans) { if (h.dead || h === exclude) continue; const d = dist2(p, h.pos); if (d < bd) { bd = d; best = h; } }
  return best;
}

// Длина луча от точки o по направлению d до стены/пола/потолка зала
function rayToHall(o, d) {
  let t = 400;
  if (d.x > 1e-4) t = Math.min(t, (HALL_X - o.x) / d.x); else if (d.x < -1e-4) t = Math.min(t, (-HALL_X - o.x) / d.x);
  if (d.z > 1e-4) t = Math.min(t, (HALL_Z - o.z) / d.z); else if (d.z < -1e-4) t = Math.min(t, (-HALL_Z - o.z) / d.z);
  if (d.y < -1e-4) t = Math.min(t, -o.y / d.y); else if (d.y > 1e-4) t = Math.min(t, (HALL_H - o.y) / d.y);
  return Math.max(1, t);
}

// ---------- Череп-бластер ----------
// o: from (откуда вылетает), pos (где висит), aim (точка прицела), flat (луч горизонтальный),
//    appear (вылет), tele (время до выстрела от появления), fire (длит. луча), w0→w1 (ширина луча),
//    dmg (за тик), quad (часть «Креста»), strip (бледная полоса на полу)
export class Blaster {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'blaster';
    this.from = o.from.clone(); this.pos = o.pos.clone();
    this.dir = new THREE.Vector3().subVectors(o.aim, this.pos);
    if (o.flat) this.dir.y = 0;
    if (this.dir.lengthSq() < 0.01) this.dir.set(0, 0, 1);
    this.dir.normalize();
    this.yaw = Math.atan2(this.dir.x, this.dir.z);
    this.pitch = Math.asin(clamp(-this.dir.y, -1, 1));
    this.appear = o.appear ?? 0.3; this.tele = Math.max(this.appear + 0.05, o.tele ?? 0.8);
    this.fireT = o.fire ?? 2.4; this.fadeT = 0.3;
    this.w0 = o.w0 ?? 5; this.w1 = o.w1 ?? 1.5; this.R = this.w0 / 2;
    this.dmg = o.dmg ?? 2; this.cause = o.cause || 'бластер'; this.quad = !!o.quad; this.useStrip = !!o.strip;
    this.t = -(o.delay || 0); this.vis = null; this.strip = null; this.fired = false; this.hitT = new Map(); this.r = 0; this.near = null;
    this.origin = new THREE.Vector3().copy(this.pos).addScaledVector(this.dir, 2.6 * (o.scale ?? 1));
    this.len = rayToHall(this.origin, this.dir) + 0.6;
    this.end = new THREE.Vector3().copy(this.origin).addScaledVector(this.dir, this.len - 0.6);
    // проекция луча на пол: единичное направление и участок (по горизонтали), где луч на высоте тела
    const hx = Math.hypot(this.dir.x, this.dir.z) || 1e-3;
    this.dir2 = new THREE.Vector3(this.dir.x / hx, 0, this.dir.z / hx);
    const lowT = this.dir.y < -1e-3 ? Math.max(0, (this.origin.y - 6.5 - this.R) / -this.dir.y) : 0;
    this.a0 = lowT * hx; this.a1 = this.len * hx;
    this.scale = o.scale ?? 1;
  }
  get phase() { const t = this.t; return t < 0 ? 'wait' : t < this.appear ? 'appear' : t < this.tele ? 'tele' : t < this.tele + this.fireT ? 'fire' : 'fade'; }
  timeToFire() { return this.tele - this.t; }
  dangerous() { const t = this.t; return t > -0.1 && t < this.tele + this.fireT; }
  update(dt) {
    const G = this.G; this.t += dt;
    const t = this.t; if (t < 0) return true;
    if (!this.vis) {
      this.vis = take(G.ma.blasters);
      if (!this.vis) return false;
      if (this.useStrip) this.strip = take(G.ma.strips);
      this.vis.sk.group.visible = true; this.vis.sk.group.rotation.order = 'YXZ';
      // «зарядка»: нарастающий вой от появления черепа до выстрела
      G.jd('whine', this, this.quad ? 0.55 : 0.85, { dur: this.tele }, 0.12);
    }
    const v = this.vis, sk = v.sk, end = this.tele + this.fireT + this.fadeT, S = 1.55 * this.scale;
    if (t >= end) { this.dispose(); return false; }
    const ph = this.phase;
    // череп: вылетает к месту, разворачиваясь к цели
    if (ph === 'appear') {
      const k = easeOut(t / this.appear);
      sk.group.position.lerpVectors(this.from, this.pos, k);
      sk.group.rotation.set(this.pitch * k, this.yaw + (1 - k) * Math.PI * 1.5, 0);
      sk.inner.scale.setScalar(S * (0.25 + 0.75 * k));
      sk.jaw.rotation.x = 0;
    } else {
      sk.group.position.copy(this.pos);
      sk.group.rotation.set(this.pitch, this.yaw, 0);
      sk.inner.scale.setScalar(S);
    }
    let eye = 0.1;
    if (ph === 'tele') {
      const k = (t - this.appear) / (this.tele - this.appear);
      sk.jaw.rotation.x = 0.5 * easeIn(k);
      eye = 0.4 + k * 1.2;
      if (k > 0.6) sk.group.position.x += (Math.random() - 0.5) * 0.12;
      if (Math.random() < 0.6) { // частицы втягиваются в пасть
        const a = Math.random() * Math.PI * 2, r = 2.2 + Math.random() * 1.5;
        V.set(this.origin.x + Math.cos(a) * r * this.dir2.z, this.origin.y + Math.sin(a) * r, this.origin.z - Math.cos(a) * r * this.dir2.x);
        G.fx.spark(V.x, V.y, V.z, (this.origin.x - V.x) * 3, (this.origin.y - V.y) * 3, (this.origin.z - V.z) * 3, 0.3, 0.55, 0xeafcff);
      }
    } else if (ph === 'fire' || ph === 'fade') {
      sk.jaw.rotation.x = 0.9;
      eye = 1.7;
      const kf = ph === 'fire' ? (t - this.tele) / this.fireT : 1;
      sk.group.position.addScaledVector(this.dir, -Math.min(1, kf * 12) * 1.2 * this.scale);
      if (ph === 'fire') sk.group.position.x += (Math.random() - 0.5) * 0.08;
      if (ph === 'fade') { const kd = (t - this.tele - this.fireT) / this.fadeT; sk.inner.scale.setScalar(S * (1 - kd * 0.85)); sk.group.position.y += kd * 2; eye = 1.7 * (1 - kd); }
    }
    for (const e of sk.eyes) e.scale.setScalar(eye * (0.9 + Math.random() * 0.2));
    // бледная полоса на полу (подсказка для телефона, в оригинале её нет)
    const st = this.strip?.m;
    if (st) {
      if (ph === 'appear' || ph === 'tele') {
        const k = Math.min(1, t / this.tele);
        st.visible = true;
        st.position.set(this.origin.x + this.dir2.x * this.a1 / 2, 0.07, this.origin.z + this.dir2.z * this.a1 / 2);
        st.rotation.y = this.yaw;
        st.scale.set(this.w0 * 0.8, 1, this.a1);
        st.material.opacity = 0.06 + k * 0.16;
        st.material.color.setHex(0xfff4d0);
      } else st.visible = false;
    }
    // луч: сначала широкий (~w0), за время выстрела сужается до w1, потом гаснет
    if (ph === 'fire' || ph === 'fade') {
      const tf = t - this.tele;
      if (!this.fired) {
        this.fired = true;
        // выстрел: широкий шумный рёв, гаснет вместе с лучом
        G.jd('roar', this, this.quad ? 0.6 : 1, { dur: this.fireT + this.fadeT }, 0.09);
        const cf = G.camFocus;
        if (cf && !cf.dead) { const d = this.lineDist(cf.pos); if (d < 14) { G.fx.shake(0.12); if (d < 4) G.fx.flash('#fffbe8', 0.18); } }
      }
      let r;
      if (ph === 'fire') {
        const kf = tf / this.fireT;
        r = (lerp(this.w0, this.w1, kf) / 2) * Math.min(1, 0.35 + tf * 10) * (0.95 + Math.random() * 0.1);
      } else { const kd = (t - this.tele - this.fireT) / this.fadeT; r = (this.w1 / 2) * (1 - kd) * (0.9 + Math.random() * 0.1); }
      this.r = r;
      const b = v.beam; b.visible = true;
      b.position.copy(this.origin).addScaledVector(this.dir, -0.6);
      b.rotation.set(this.pitch, this.yaw, 0);
      b.scale.set(1, 1, this.len);
      v.core.scale.set(r * 0.55, r * 0.55, 1); v.mid.scale.set(r * 0.85, r * 0.85, 1); v.haze.scale.set(r * 1.3, r * 1.3, 1);
      v.flare.visible = true; v.flare.position.copy(this.origin); v.flare.scale.setScalar(r * 3.6 + 1);
      v.hitF.visible = true; v.hitF.position.copy(this.end); v.hitF.scale.setScalar(r * 4 + 1.5);
      // искры на месте удара луча и пыль вдоль него
      if (Math.random() < 0.8) G.fx.spark(this.end.x, this.end.y + 0.2, this.end.z, (Math.random() - 0.5) * 8, 3 + Math.random() * 6, (Math.random() - 0.5) * 8, 0.4, 0.6, 0xfff8e0, 14);
      if (Math.random() < 0.5) {
        const d = this.a0 + Math.random() * (this.a1 - this.a0);
        G.fx.spark(this.origin.x + this.dir2.x * d + (Math.random() - 0.5) * r * 2, 0.2, this.origin.z + this.dir2.z * d + (Math.random() - 0.5) * r * 2, 0, 2 + Math.random() * 4, 0, 0.45, 0.45, 0xfff2c0);
      }
      if (ph === 'fire') this.checkHits(r);
    }
    return true;
  }
  // расстояние от точки до проекции луча на пол (для ботов и камеры)
  lineDist(p) {
    const rx = p.x - this.origin.x, rz = p.z - this.origin.z;
    const along = rx * this.dir2.x + rz * this.dir2.z;
    if (along < this.a0 - 1.5 || along > this.a1) return 999;
    return Math.abs(rx * this.dir2.z - rz * this.dir2.x);
  }
  checkHits(r) {
    const G = this.G, now = G.time, hx = Math.hypot(this.dir.x, this.dir.z) || 1e-3;
    for (const h of G.humans) {
      if (h.dead) continue;
      const rx = h.pos.x - this.origin.x, rz = h.pos.z - this.origin.z;
      const along = rx * this.dir2.x + rz * this.dir2.z;
      if (along < -1 || along > this.a1) continue;
      const cross = Math.abs(rx * this.dir2.z - rz * this.dir2.x);
      if (cross > r + h.radius * 0.55) {
        // луч прошёл совсем рядом, но не задел — повод для реплики в чате
        if (cross < r + 3.2 && !this.quad && !(this.near ||= new Set()).has(h) && !this.hitT.has(h)) { this.near.add(h); G.onEvent('nearmiss', { h, hz: this }); }
        continue;
      }
      // высота центра луча над этой точкой пола; ноги выше центра — луч проходит под человеком
      const yc = this.origin.y + this.dir.y * (along / hx);
      const half = r / Math.max(0.3, hx);
      if (h.pos.y > yc || yc - half > h.pos.y + 5.3 || yc + half < h.pos.y + 0.2) continue;
      if (now < (this.hitT.get(h) || 0)) continue;
      this.hitT.set(h, now + TICK);
      damageHuman(G, h, this.dmg, this.owner, { tick: true, color: 0xfffbe8, cause: this.cause });
    }
  }
  dispose() {
    if (this.vis) { const v = this.vis; v.used = false; v.sk.group.visible = false; v.beam.visible = false; v.flare.visible = false; v.hitF.visible = false; this.vis = null; }
    if (this.strip) { this.strip.used = false; this.strip.m.visible = false; this.strip = null; }
  }
}

// ---------- Зона костей ----------
// Красный квадрат из рельс (≈11 стадов) → через 0.75 с частокол 6×6 костей до колена (≤0.1 с),
// держится 2 с и уходит в пол; рельсы исчезают вместе с костями. 3 урона за тик + карма; перепрыгнуть можно.
export class BoneZone {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'zone';
    this.hs = o.half ?? 5.5;
    this.c = clampToHall(o.center.clone().setY(0), this.hs + 0.8);
    this.tele = 0.75; this.pop = 0.1; this.stay = 2.0; this.sink = 0.3; this.bh = o.boneH ?? 1.8;
    this.dmg = o.dmg ?? 3; this.t = -(o.delay || 0); this.up = 0; this.hitT = new Map(); this.popped = false; this.started = false;
    this.jit = [];
    for (let i = 0; i < 36; i++) this.jit.push([(Math.random() - 0.5) * 0.35, (Math.random() - 0.5) * 0.35, Math.random() * Math.PI, 0.9 + Math.random() * 0.2]);
  }
  get bonesUp() { return this.t >= this.tele && this.up > 0.4; }
  timeToPop() { return this.tele - this.t; }
  inside(p, pad = 0) { return Math.abs(p.x - this.c.x) < this.hs + pad && Math.abs(p.z - this.c.z) < this.hs + pad; }
  update(dt) {
    const G = this.G; this.t += dt;
    const t = this.t; if (t < 0) return true;
    if (!this.started) { this.started = true; G.jd('ting', { pos: this.c }, 0.9, null, 0.05); }
    const t1 = this.tele, t2 = t1 + this.pop, t3 = t2 + this.stay, t4 = t3 + this.sink;
    if (t >= t4) return false;
    if (t < t1) this.up = 0;
    else if (t < t2) this.up = easeOut((t - t1) / this.pop);
    else if (t < t3) this.up = 1;
    else this.up = 1 - (t - t3) / this.sink;
    if (t >= t1 && !this.popped) {
      this.popped = true;
      G.jd('shhk', { pos: this.c }, 1, null, 0.04);
      G.fx.ring(this.c, 0xfff0d0, this.hs * 0.6, this.hs * 1.5, 0.35);
      G.fx.puff(this.c, 10, 0xc8a050, 2.2, 0.6, 7);
    }
    if (this.up > 0.4) this.checkHits();
    return true;
  }
  checkHits() {
    const G = this.G, now = G.time, top = this.bh * this.up;
    for (const h of G.humans) {
      if (h.dead || !this.inside(h.pos, h.radius * 0.6) || h.pos.y > top - 0.15) continue;
      if (now < (this.hitT.get(h) || 0)) continue;
      this.hitT.set(h, now + TICK);
      damageHuman(G, h, this.dmg, this.owner, { tick: true, color: 0xffffff, cause: 'зона костей' });
    }
  }
  draw(G) {
    if (this.t < 0) return;
    const c = this.c, hs = this.hs, k = Math.min(1, this.t / 0.12), y = 0.25 * k, th = 0.6, ht = 0.5 * k;
    railAdd(G, c.x, y, c.z - hs, hs * 2 + th, ht, th); railAdd(G, c.x, y, c.z + hs, hs * 2 + th, ht, th);
    railAdd(G, c.x - hs, y, c.z, th, ht, hs * 2 - th); railAdd(G, c.x + hs, y, c.z, th, ht, hs * 2 - th);
    if (this.up <= 0) return;
    const n = 6, sp = (hs * 2 - 0.9) / n, sy = this.bh / BONE_H, yb = -this.bh * (1 - this.up);
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
      const q = this.jit[i * n + j];
      boneAdd(G, c.x - hs + 0.45 + sp * (i + 0.5) + q[0], yb, c.z - hs + 0.45 + sp * (j + 0.5) + q[1], 0, Math.cos(q[2]), Math.sin(q[2]), sy * q[3], 1.05);
    }
  }
  dispose() {}
}

// ---------- Бросок костей ----------
// 8 маленьких костей возникают веером перед Судьёй, висят 0.35 с и летят (60 ст/с, разброс ±10°, до 60 ст).
// Часть — голубые (бьют только движущихся). 3 урона за касание + карма.
export class BoneThrow {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'throw';
    this.hover = o.hover ?? 0.35; this.speed = o.speed ?? 60; this.range = o.range ?? 60; this.dmg = o.dmg ?? 3;
    this.t = -(o.delay || 0); this.launched = false;
    const m = owner, n = o.n ?? 8;
    const d = V.set(o.aim.x - m.pos.x, 0, o.aim.z - m.pos.z);
    if (d.lengthSq() < 0.01) m.fwd(d);
    d.normalize();
    const px = -d.z, pz = d.x, base = Math.atan2(d.x, d.z);
    const blueSet = new Set();
    while (blueSet.size < (o.blue ?? 3)) blueSet.add(Math.floor(Math.random() * n));
    this.bones = [];
    for (let i = 0; i < n; i++) {
      const u = n > 1 ? i / (n - 1) - 0.5 : 0;
      const w = u * 7.5, fwd = 2.6 - Math.abs(u) * 1.6;
      const a = base + u * 2 * (10 * Math.PI / 180) + (Math.random() - 0.5) * 0.05;
      this.bones.push({
        pos: new THREE.Vector3(m.pos.x + d.x * fwd + px * w, 1.7 + (i % 3) * 0.75 + Math.random() * 0.2, m.pos.z + d.z * fwd + pz * w),
        dir: new THREE.Vector3(Math.sin(a), 0, Math.cos(a)), yaw: a + Math.PI / 2, s: 0, alive: true,
        type: blueSet.has(i) ? 1 : 0, ph: Math.random() * 6,
      });
    }
  }
  get flying() { return this.launched; }
  update(dt) {
    const G = this.G; this.t += dt;
    if (this.t < 0) return true;
    if (!this.started) { this.started = true; G.sfx('bone', 0.3, this.owner, 0.04); for (const b of this.bones) G.fx.spark(b.pos.x, b.pos.y, b.pos.z, 0, 1, 0, 0.25, 0.9, BONE_COL[b.type]); }
    if (!this.launched && this.t >= this.hover) {
      this.launched = true;
      // по свисту на каждую кость, чуть расстроенные и вразнобой
      this.bones.forEach((b, i) => G.jd('whoosh', this.owner, 0.5, { det: (Math.random() - 0.5) * 0.35, delay: i * 0.022 + Math.random() * 0.01 }, 0));
    }
    let any = false;
    for (const b of this.bones) {
      if (!b.alive) continue;
      any = true;
      if (!this.launched) continue;
      const step = this.speed * dt;
      b.pos.addScaledVector(b.dir, step); b.s += step;
      V.copy(b.pos);
      if (b.s > this.range || arenaCollide(V, 0.3)) { b.alive = false; G.fx.puff(b.pos, 2, 0xd8d0b0, 0.8, 0.3, 2); continue; }
      if (Math.random() < 0.7) G.fx.spark(b.pos.x - b.dir.x * 0.6, b.pos.y + (Math.random() - 0.3) * 0.8, b.pos.z - b.dir.z * 0.6, -b.dir.x * 4, 0, -b.dir.z * 4, 0.18, b.type ? 0.9 : 0.6, BONE_COL[b.type]);
      for (const h of G.humans) {
        if (h.dead) continue;
        if (Math.hypot(h.pos.x - b.pos.x, h.pos.z - b.pos.z) > h.radius + 0.45) continue;
        if (b.pos.y + 0.7 < h.pos.y + 0.2 || b.pos.y - 0.7 > h.pos.y + 5.3) continue;
        if (boneSafe(h, b.type)) continue;
        V2.copy(b.dir).multiplyScalar(5);
        if (damageHuman(G, h, this.dmg, this.owner, { kb: V2, color: BONE_COL[b.type], cause: b.type ? 'синие кости' : 'кости' })) {
          b.alive = false; G.fx.burst(b.pos, BONE_COL[b.type], 6, 6, 0.4, 0.3); break;
        }
      }
    }
    return any;
  }
  draw(G) {
    if (this.t < 0) return;
    const k = Math.min(1, this.t / 0.12), L = 1.35 / BONE_H;
    for (const b of this.bones) {
      if (!b.alive) continue;
      const bob = this.launched ? 0 : Math.sin(this.t * 9 + b.ph) * 0.08;
      boneAdd(G, b.pos.x, b.pos.y - 0.68 + bob, b.pos.z, b.type, Math.cos(b.yaw), Math.sin(b.yaw), L * k, 0.9 * k);
    }
  }
  dispose() {}
}

// ---------- Ряд костей (волны «Последней атаки»; также «Стена костей» для бота) ----------
export class BoneRow {
  constructor(G, owner, o) {
    this.G = G; this.owner = owner; this.kind = 'row';
    this.origin = o.origin.clone(); this.origin.y = 0;
    this.dir = o.dir.clone().setY(0).normalize();
    this.perp = new THREE.Vector3(-this.dir.z, 0, this.dir.x);
    this.halfW = o.halfW ?? 18; this.speed = o.speed ?? 16; this.type = o.type ?? (o.blue ? 1 : 0);
    this.travel = o.travel ?? 75; this.rise = o.rise ?? 0.55; this.dmg = o.dmg ?? 10;
    this.hgt = o.hgt ?? BONE_H; this.gap = o.gap ?? 1.2; this.useStrip = o.strip !== false; this.cause = o.cause; this.sw = o.sw ?? 1; this.y0 = o.y0 ?? 0; this.blueAtk = !!o.blueAtk;
    this.t = -(o.delay || 0); this.s = 0; this.riseK = 0; this.sinkT = 0; this.strip = null; this.sounded = false;
  }
  get moving() { return this.t >= this.rise && this.sinkT === 0; }
  get blue() { return this.type === 1; }
  update(dt) {
    const G = this.G; this.t += dt;
    if (this.t < 0) return true;
    if (!this.sounded) { this.sounded = true; if (!this.blueAtk) G.sfx('bone', 0.4, null, 0.06); if (this.useStrip) this.strip = take(G.ma.strips); }
    if (this.t < this.rise) this.riseK = easeOut(this.t / this.rise);
    else if (this.s < this.travel) {
      // стена тронулась: «вжух» (стены Синей атаки — пониже и подольше)
      if (this.riseK < 1) G.jd(this.blueAtk ? 'wall' : 'whoosh', { pos: this.origin }, this.blueAtk ? 0.8 : 0.6, null, 0.05);
      this.riseK = 1; this.s += this.speed * dt;
    }
    else { this.sinkT += dt; this.riseK = Math.max(0, 1 - this.sinkT / 0.3); if (this.sinkT > 0.3) { this.dispose(); return false; } }
    const cx = this.origin.x + this.dir.x * this.s, cz = this.origin.z + this.dir.z * this.s;
    if (this.strip) {
      const m = this.strip.m; m.visible = true;
      m.position.set(cx, 0.08, cz); m.rotation.y = Math.atan2(this.perp.x, this.perp.z);
      m.scale.set(1.7, 1, this.halfW * 2 + 1);
      m.material.color.setHex(BONE_COL[this.type]);
      m.material.opacity = (this.t < this.rise ? 0.4 + 0.5 * Math.abs(Math.sin(this.t * 25)) : 0.55) * this.riseK + (this.t < this.rise ? 0.3 : 0);
    }
    if (this.riseK > 0.5 && Math.random() < 0.9) {
      const w = (Math.random() * 2 - 1) * this.halfW;
      G.fx.spark(cx + this.perp.x * w - this.dir.x * 0.6, 0.3, cz + this.perp.z * w - this.dir.z * 0.6, -this.dir.x * 2, 2 + Math.random() * 3, -this.dir.z * 2, 0.45, 0.55, BONE_COL[this.type]);
      if (Math.random() < 0.3) { V.set(cx + this.perp.x * w, 0, cz + this.perp.z * w); G.fx.puff(V, 1, 0xb89a50, 1.2, 0.5, 1.5); }
    }
    if (this.riseK > 0.55) this.checkHits(cx, cz);
    return true;
  }
  checkHits(cx, cz) {
    const G = this.G, now = G.time;
    for (const h of G.humans) {
      if (h.dead || now < h.boneImmuneUntil) continue;
      const rx = h.pos.x - cx, rz = h.pos.z - cz;
      const along = rx * this.dir.x + rz * this.dir.z, across = rx * this.perp.x + rz * this.perp.z;
      if (Math.abs(along) > 0.3 + h.radius * 0.8 || Math.abs(across) > this.halfW + 0.4) continue;
      if (h.pos.y > this.y0 + this.hgt * this.riseK - 0.25 || h.pos.y + 5 < this.y0) continue;
      if (boneSafe(h, this.type)) continue;
      V2.copy(this.dir).multiplyScalar(8);
      if (damageHuman(G, h, this.dmg, this.owner, { kb: V2, color: BONE_COL[this.type], cause: this.cause || BONE_CAUSE[this.type] })) h.boneImmuneUntil = now + 0.7;
    }
  }
  draw(G) {
    if (this.t < 0 || this.riseK <= 0) return;
    const n = Math.floor((this.halfW * 2) / this.gap) + 1, y = this.y0 - this.hgt * (1 - this.riseK), sy = this.hgt / BONE_H;
    const bx = this.origin.x + this.dir.x * this.s, bz = this.origin.z + this.dir.z * this.s;
    const c = this.perp.x, s = -this.perp.z;
    for (let i = 0; i < n; i++) {
      const w = -this.halfW + i * this.gap, wob = Math.sin(i * 1.7) * 0.12;
      boneAdd(G, bx + this.perp.x * w + this.dir.x * wob, y + Math.sin(i * 2.3) * 0.08, bz + this.perp.z * w + this.dir.z * wob, this.type, c, s, sy, this.sw);
    }
  }
  dispose() { if (this.strip) { this.strip.used = false; this.strip.m.visible = false; this.strip = null; } }
}

// ---------- позы Судьи ----------
// вторая рука остаётся в кармане (поза задаётся в combat.animateJudge)
function summonPose(p, k) {
  const e = easeOut(Math.min(1, k * 2.5)), r = k > 0.7 ? 1 - (k - 0.7) / 0.3 : 1;
  p.armR.rotation.set(lerp(-0.4, -1.9, e * r), 0, lerp(-0.3, 0.5, e * r)); p.neck.rotation.x = -0.1 * e;
}
function pointPose(p, k) {
  const e = easeOut(Math.min(1, k * 3)), r = k > 0.75 ? 1 - (k - 0.75) / 0.25 : 1;
  p.armR.rotation.set(lerp(-0.4, -1.5, e * r), 0, lerp(-0.3, -0.1, e * r));
}
// ---------- способности Судьи (для игрока и бота) ----------
// Бластер (CD 5): один череп сбоку от Судьи (4–6 ст. вбок, 3–5 вверх), поворачивается к точке и через ~0.8 с
// стреляет широким белым лучом (~2.4 с, сужается с 5 до 1.5) до стены. 3 урона за тик (как в вики) + карма.
export function castBlaster(G, m, aim) {
  if (!m.canAct() || !m.ready('blast') || !aim) return false;
  m.use('blast', 5); m.glow = 1;
  V.set(aim.x - m.pos.x, 0, aim.z - m.pos.z);
  if (V.lengthSq() < 1) m.fwd(V);
  V.normalize();
  m.faceTo(V2.copy(m.pos).add(V), true);
  m.startAction({ name: 'summon', dur: 0.4, lock: true, moveMul: 0.45, pose: summonPose });
  const px = -V.z, pz = V.x, off = rand(4.5, 5.8);
  const sc = (s) => clearance(m.pos.x + px * s * off, m.pos.z + pz * s * off, 6) + Math.random() * 1.5;
  const s = sc(1) >= sc(-1) ? 1 : -1;
  const pos = V3.set(m.pos.x + px * s * off + V.x * 0.6, rand(3.4, 4.2), m.pos.z + pz * s * off + V.z * 0.6);
  arenaCollide(pos, 2.2);
  const a = V4.set(aim.x, pos.y, aim.z);
  if (Math.hypot(a.x - pos.x, a.z - pos.z) < 3) a.set(pos.x + V.x * 10, pos.y, pos.z + V.z * 10);
  G.hazards.push(new Blaster(G, m, { from: V2.set(m.pos.x, m.pos.y + 6, m.pos.z), pos, aim: a, flat: true, tele: 0.8, fire: 2.4, w0: 5, w1: 1.5, dmg: 3, strip: true, cause: 'бластер' }));
  G.onEvent('mcast', { m, what: 'blaster' });
  return true;
}

// Крест бластеров (CD 8): 4 черепа крестом вокруг точки (12–20 ст., 8–15 вверх), смотрят вниз,
// через 0.5 с бьют вместе — лучи пересекаются в точке. 2 урона за тик + карма.
export function castQuad(G, m, aim) {
  if (!m.canAct() || !m.ready('quad') || !aim) return false;
  m.use('quad', 8); m.glow = 1;
  m.faceTo(aim, true);
  m.startAction({ name: 'summon', dur: 0.4, lock: true, moveMul: 0.45, pose: summonPose });
  const c = clampToHall(V.set(aim.x, 0, aim.z), 2);
  const R = rand(13, 17), H = rand(9.5, 12.5), rot = Math.random() < 0.5 ? 0 : Math.PI / 4;
  for (let i = 0; i < 4; i++) {
    const a = rot + (i * Math.PI) / 2, dx = Math.sin(a), dz = Math.cos(a);
    // радиус по этому лучу — не дальше стены
    let r = R;
    if (Math.abs(dx) > 1e-3) r = Math.min(r, (HALL_X - 2 - Math.sign(dx) * c.x) / Math.abs(dx));
    if (Math.abs(dz) > 1e-3) r = Math.min(r, (HALL_Z - 2 - Math.sign(dz) * c.z) / Math.abs(dz));
    r = Math.max(6, r);
    const pos = V2.set(c.x + dx * r, H, c.z + dz * r);
    G.hazards.push(new Blaster(G, m, { from: V3.set(m.pos.x, m.pos.y + 7, m.pos.z), pos, aim: V4.set(c.x, 1.4, c.z), appear: 0.25, tele: 0.55, fire: 1.3, w0: 3.4, w1: 1.1, dmg: 2, quad: true, cause: 'крест бластеров' }));
  }
  G.onEvent('mcast', { m, what: 'quad' });
  return true;
}

// Зона костей (CD 5) в точке (не дальше 55 ст. от Судьи)
export function castBoneZone(G, m, at) {
  if (!m.canAct() || !m.ready('zone') || !at) return false;
  m.use('zone', 5); m.glow = 1;
  V.set(at.x - m.pos.x, 0, at.z - m.pos.z);
  const d = V.length(); if (d > 55) V.multiplyScalar(55 / d);
  m.faceTo(V2.copy(m.pos).add(V), true);
  m.startAction({ name: 'zone', dur: 0.35, lock: true, moveMul: 0.45, pose: pointPose });
  G.hazards.push(new BoneZone(G, m, { center: V2.set(m.pos.x + V.x, 0, m.pos.z + V.z) }));
  G.onEvent('mcast', { m, what: 'zone' });
  return true;
}

// Бросок костей (CD 5) в сторону точки
export function castBoneThrow(G, m, aim) {
  if (!m.canAct() || !m.ready('throw') || !aim) return false;
  m.use('throw', 5); m.glow = 1;
  m.faceTo(aim, true);
  m.startAction({ name: 'throw', dur: 0.45, lock: true, moveMul: 0.3, pose: pointPose });
  G.hazards.push(new BoneThrow(G, m, { aim }));
  G.onEvent('mcast', { m, what: 'throw' });
  return true;
}

// Стена костей (только у бота, CD 5): 8 ст. в ширину и 2 в высоту, пауза 0.4 с, рывок 45 ст/с на 50 ст. Перепрыгивается.
export function castBoneWall(G, m, aim) {
  if (!m.canAct() || !m.ready('wall') || !aim) return false;
  m.use('wall', 5); m.glow = 1;
  V.set(aim.x - m.pos.x, 0, aim.z - m.pos.z); if (V.lengthSq() < 0.01) m.fwd(V); V.normalize();
  m.faceTo(V2.copy(m.pos).add(V), true);
  m.startAction({ name: 'wall', dur: 0.4, lock: true, moveMul: 0.2, pose: pointPose });
  G.hazards.push(new BoneRow(G, m, { origin: V2.set(m.pos.x + V.x * 2.6, 0, m.pos.z + V.z * 2.6), dir: V, halfW: 4, gap: 0.8, hgt: 2.0, rise: 0.4, speed: 45, travel: 50, dmg: 4, strip: false, cause: 'стена костей' }));
  G.onEvent('mcast', { m, what: 'wall' });
  return true;
}


// Отталкивание (CD 15, без урона): каждый живой человек отлетает от Судьи — ≈50 ст/с вбок и 65 вверх
// (≈0.66 с полёта, ≈33 стада), без управления; стены и колонны останавливают полёт. На Судье — никаких эффектов,
// только глухое «бум» и ветер.
export function castForce(G, m) {
  if (!m.canAct() || !m.ready('force')) return false;
  m.use('force', 15);
  let n = 0;
  for (const h of G.humans) {
    if (h.dead) continue;
    V.set(h.pos.x - m.pos.x, 0, h.pos.z - m.pos.z);
    if (V.lengthSq() < 0.01) m.fwd(V);
    V.normalize();
    h.fling(V.x * FORCE_H, V.z * FORCE_H, FORCE_V); n++;
    G.fx.puff(h.pos, 5, 0xc8a050, 1.6, 0.5, 6);
  }
  G.jd('thoom', m, 1, null, 0.2);
  const cf = G.camFocus;
  if (cf && cf.team === 'human' && !cf.dead) G.fx.shake(0.14);
  G.onEvent('force', { m, n });
  return true;
}

// ---------- Синяя атака ----------
// CD 215 (≈раз за раунд). ≈20 с: каждые 0.8–1.2 с из левой или правой стены выезжает стена костей и
// пересекает зал на 35–45 ст/с в разных местах коридора (рядом с людьми). Два вида:
//  • голубой «гребень» — 5–8 высоких (6–8 ст.) светящихся костей #00FFFF: бьёт, только если двигаешься (5 урона);
//  • низкий белый ряд — перепрыгни (3 урона).
export class BlueAttack {
  constructor(G, owner) {
    this.G = G; this.owner = owner; this.kind = 'blueatk'; this.t = 0; this.dur = 20; this.next = 0.5; this.walls = 0;
    G.audio?.('humOn'); this.hum = true;
  }
  get active() { return this.t < this.dur; }
  update(dt) {
    const G = this.G; this.t += dt;
    if (this.t >= this.dur || this.owner.dead || G.state !== 'fight') { this.dispose(); return false; }
    this.next -= dt;
    if (this.next <= 0 && this.t < this.dur - 1.5) { this.next = rand(0.8, 1.2); this.spawn(); }
    return true;
  }
  spawn() {
    const G = this.G, hs = humansAlive(G);
    const ref = hs.length ? hs[Math.floor(Math.random() * hs.length)].pos : this.owner.pos;
    const cyan = this.walls === 0 || Math.random() < 0.55;
    const side = Math.random() < 0.5 ? 1 : -1; // 1 — из левой стены (−x) направо
    const speed = rand(35, 45);
    let halfW, o;
    if (cyan) {
      const nb = 5 + Math.floor(Math.random() * 4), gap = 1.75;
      halfW = ((nb - 1) * gap) / 2;
      o = { type: 1, hgt: rand(6, 8), gap, sw: 1.7, dmg: 5 };
    } else {
      halfW = rand(5, 10);
      o = { type: 0, hgt: 1.9, gap: 0.72, sw: 1.05, dmg: 3 };
    }
    const z = clamp(ref.z + rand(-7, 7), -HALL_Z + halfW + 1, HALL_Z - halfW - 1);
    G.hazards.push(new BoneRow(G, this.owner, {
      ...o, origin: V.set(-side * (HALL_X + 0.4), 0, z), dir: V2.set(side, 0, 0), halfW, speed, travel: HALL_X * 2 + 1, rise: 0.12,
      cause: cyan ? 'синяя атака' : 'синяя атака (белые)', blueAtk: true,
    }));
    this.walls++;
  }
  dispose() { if (!this.done) { this.done = true; this.G.audio?.('humOff'); } }
}
export function castBlue(G, m) {
  if (!m.canAct() || !m.ready('blue')) return false;
  m.use('blue', 215); m.glow = 1;
  m.startAction({ name: 'summon', dur: 0.5, lock: true, moveMul: 0.3, pose: summonPose });
  G.hazards.push(new BlueAttack(G, m));
  G.onEvent('blue', { m });
  return true;
}

// Круг бластеров (только у бота, один раз на ≤3 уклонениях): 8 черепов кольцом 14 ст. вокруг человека,
// появляются с шагом 0.1 с, бьют через 0.9 с, лучи 1.5 с. 2 урона за тик + карма.
export function castCircle(G, m, target) {
  if (!m.canAct() || !m.ready('circle') || !target || target.dead) return false;
  m.use('circle', 999); m.glow = 1;
  m.faceTo(target.pos, true);
  m.startAction({ name: 'summon', dur: 0.5, lock: true, moveMul: 0.3, pose: summonPose });
  const c = clampToHall(V3.copy(target.pos).setY(0), 3);
  const off = Math.random() * Math.PI * 2;
  for (let i = 0; i < 8; i++) {
    const a = off + (i * Math.PI) / 4;
    const pos = clampToHall(V.set(c.x + Math.cos(a) * 14, 3.4, c.z + Math.sin(a) * 14), 2.2);
    G.hazards.push(new Blaster(G, m, { from: V2.set(c.x, 12, c.z), pos, aim: V4.set(c.x, 2.4, c.z), delay: i * 0.1, appear: 0.3, tele: 0.9, fire: 1.5, w0: 3.2, w1: 1.2, dmg: 2, strip: true, cause: 'круг бластеров' }));
  }
  G.jd('ring', m, 0.8);
  G.onEvent('mcast', { m, what: 'circle' });
  return true;
}

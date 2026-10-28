// Наборы приёмов по спеке JJS (§4.2–4.4):
//  • «Святилище» — King of Curses (пробуждение Сосуда) и Strongest of History: Cleave (40 % текущего HP),
//    Dismantle (шквал разрезов ≤30 стадов, в воздухе — длинный разрез), Open (огонь → стрела → столб пламени),
//    Rush (рывок 60 стадов → колено в небо → удар вниз); Heian Form: Incantation (заклинания-пузыри),
//    варианты Strong Dismantle по числу заклинаний, Open FURNACE; пассив Shrine M1 (серые полумесяцы на 24 стада).
//  • Проклятый напарник: Рика (R: призрак у плеча → её приёмы с общей перезарядкой), Severing Path / Veilstep,
//    Resolute Slash (+ Чёрная вспышка), Outburst (заряд 3 ступени + парирование), Second Wind.
//  • True Love: Рика-гигант у правого плеча, Стальная рука, Rika Downslam (R), Elbow Rush, Копия «Не двигайся!»,
//    Energy Ripple, True Love Beam.
import * as THREE from 'three';
import { G } from './ctx.js';
import { PX, POSE, M1ANIM, K } from './anim.js';
import { rand, clamp, ease, angleDamp, wrapAngle } from './util.js';
import { projectile, beamFX, beamHits, aimFrom, lungeTo, getRika, getRikaArm } from './skills.js';

const V3 = THREE.Vector3;
const _a = new V3(), _b = new V3(), _c = new V3(), _d = new V3(), _e = new V3();
const _s0 = new V3(), _s1 = new V3(), _sd = new V3();
const _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();
const ZV = new V3(0, 0, 1), YV = new V3(0, 1, 0), NY = new V3(0, -1, 0);
const M1D = [3, 3, 4, 4];

// ======================= помощники =======================
const rightOf = (f, out) => out.set(-Math.cos(f.yaw), 0, Math.sin(f.yaw));
// Летящая «волна» разреза: дуга развёрнута поперёк полёта (иначе сзади её видно только ребром)
const _qx = new THREE.Quaternion();
export function waveQuat(dir, roll, out = new THREE.Quaternion(), tilt = 1.15) {
  out.setFromUnitVectors(ZV, dir).multiply(_q2.setFromAxisAngle(ZV, roll)).multiply(_qx.setFromAxisAngle(new V3(1, 0, 0), tilt));
  return out;
}
const groundY = (x, z, y) => G.world.groundAt(x, z, y);
const hitOk = (r) => r === 'hit' || r === 'break';
// держать цель в точке p (захваты): без гравитации, без блока
function holdAt(v, p, dt, k = 14) { v.pos.lerp(p, 1 - Math.exp(-k * dt)); v.vel.set(0, 0, 0); v.suspend = 0.15; v.blocking = false; }
function holdFront(f, v, dist, h, dt, k = 14) {
  f.fwd(_e);
  _d.set(f.pos.x + _e.x * dist, f.pos.y + h, f.pos.z + _e.z * dist);
  holdAt(v, _d, dt, k);
}
// Направление прицела: у игрока — луч камеры (с наклоном), у бота — на цель или вперёд
function aimDirOf(f, origin, tgt, out, maxPitch = 0.35) {
  if (tgt && !tgt.dead) aimFrom(f, origin, tgt, out);
  else if (f.isPlayer) f.aimDir(origin, out);
  else f.fwd(out);
  const l = Math.hypot(out.x, out.z) || 1;
  out.y = clamp(out.y, -l * maxPitch, l * maxPitch);
  return out.normalize();
}
function smokePuff(p, n = 16, size = 2.2, speed = 7) {
  G.fx.particles(p, { n, normal: true, color: ['#0c0a0e', '#1a161e', '#2a2430'], speed, up: 2, size, size1: size * 2.4, life: 0.75, alpha: 0.85, drag: 3, radius: 0.6 });
}
// Тонкая белая линия разреза с чёрной обводкой через точку c
function slashMark(c, len = 5.5, col = '#ffffff', life = 0.16, w = 0.1) {
  _sd.set(rand(-1, 1), rand(-0.8, 0.8), rand(-1, 1)).normalize();
  _s0.copy(c).addScaledVector(_sd, -len / 2); _s1.copy(c).addScaledVector(_sd, len / 2);
  G.fx.line(_s0, _s1, '#0b0b0b', life + 0.03, w * 2.6, true);
  G.fx.line(_s0, _s1, col, life, w);
}
function redSpecks(c, n = 4) { G.fx.particles(c, { n, normal: true, color: ['#7a0610', '#b0101c'], speed: 9, up: 3, size: 0.45, size1: 0.3, life: 0.45, grav: 40 }); }
function hexSpark(p, col = '#ff7bf0') {
  G.fx.hex(p, col, 0.4, 2.4, 0.22, { a0: 0.95 });
  G.fx.hex(p, '#ffffff', 0.2, 1.4, 0.16, { a0: 0.8 });
  G.fx.particles(p, { n: 5, color: [col, '#ffffff'], speed: 9, size: 0.5, life: 0.25 });
}
// Розово-белая дуга катаны перед бойцом
function kataArc(f, roll, s = 4.6, dist = 2.5, c1 = '#ffd9f7', c2 = '#ff7be8') {
  f.chestPos(_a); f.fwd(_b); _a.addScaledVector(_b, dist);
  _q.setFromUnitVectors(ZV, _b).multiply(_q2.setFromAxisAngle(ZV, roll));
  G.fx.crescent(_a, _q, c1, s * 0.55, s, 0.2, { a0: 0.95 });
  G.fx.crescent(_a, _q, c2, s * 0.5, s * 0.85, 0.16, { a0: 0.6 });
}
// Чёрная вспышка: чёрно-красные молнии, белое ядро, инверсия экрана рядом с игроком
function bfFX(f, v) {
  v.chestPos(_c);
  const c = _c.clone();
  for (let i = 0; i < 9; i++) {
    _b.set(rand(-1, 1), rand(-0.7, 1), rand(-1, 1)).normalize().multiplyScalar(rand(4, 9)).add(c);
    G.fx.bolt(c, _b, '#0a0003', { dark: true, segs: 5, jag: 0.9, life: rand(0.25, 0.45), w: rand(0.18, 0.32) });
    if (i % 2) G.fx.bolt(c, _b, '#ff1030', { segs: 5, jag: 0.9, life: 0.3, w: 0.35 });
  }
  G.fx.sphere(c, '#14000a', 0.5, 5, 0.25, { normal: true, a0: 0.9 });
  G.fx.burst(c, '#ff2040', 14, 0.25);
  G.fx.ring(c, '#ff2040', 1, 10, 0.35);
  G.hud.pop(_a.set(c.x, c.y + 3, c.z), 'BLACK FLASH!', '#ff2040', 1.7);
  G.sound('heavy', v.pos, 1); G.sound('block', v.pos, 0.8);
  if (f.isPlayer || v.isPlayer || (G.player && f.dist(G.player) < 40)) G.hud.blackFlash();
}
function craterAt(p, size = 6, cols = ['#2b2b2b', '#3a3a40', '#d8d8d8']) {
  G.fx.crater(p, size); G.fx.dust(p, 10, 3); G.fx.debris(p, 8, cols);
}

// Рика не должна закрывать обзор: если она между камерой и игроком — почти прозрачная (как в роблоксе)
function occlusionFade(R, base, dt) {
  const cam = G.camera, p = G.player;
  let want = base;
  if (cam && p && !p.dead) {
    const s = R.root.scale.x;
    R.root.getWorldPosition(_s0); _s0.y += 7 * s;
    _s1.set(p.pos.x, p.pos.y + 3, p.pos.z).sub(cam.position);
    const L = _s1.length() || 1;
    _s1.multiplyScalar(1 / L);
    _sd.copy(_s0).sub(cam.position);
    const t = clamp(_sd.dot(_s1), 0, L);
    const d = _sd.addScaledVector(_s1, -t).length();
    if (d < 5.5 * s && t < L - 1) want = Math.min(base, 0.14 + 0.36 * (d / (5.5 * s)));
  }
  R.mat.opacity += (want - R.mat.opacity) * Math.min(1, dt * 8);
}

// ======================= позы =======================
const FS = POSE.idle.fist, KT = POSE.idle.katana, KH = POSE.idle.katanaH;
const SWIPE = M1ANIM.sukuna[3];
const CLEAVE_WIND = PX(FS, { rax: 0.6, raz: -0.4, twist: -0.7, hy: -0.3, cx: 0.1, lax: -0.9, laz: 0.4 });
const CLEAVE_GRAB = PX(FS, { rax: -1.65, raz: 0.1, twist: 0.6, cx: 0.25, hy: -0.35, lax: -0.4, laz: 0.4, llx: -0.45, rlx: 0.45 });
const FLURRY_L = PX(FS, { lax: -1.5, laz: 1.2, lay: -1.6, twist: -0.6, cx: 0.25, hy: -0.35, rax: -1.65, raz: 0.1 });
const FLURRY_R = PX(FS, { lax: -1.6, laz: -0.3, twist: 0.7, cx: 0.25, hy: -0.35, rax: -1.4, raz: -1.2, ray: 1.6 });
const CLEAVE_LAUNCH = PX(FS, { rax: -2.85, raz: 0.2, twist: 0.4, cx: -0.2, hy: 0.05, lax: -0.6, laz: 0.5 });
const CLAP_OPEN = PX(FS, { rax: -1.45, raz: -0.45, lax: -1.45, laz: 0.45, hy: -0.15, cx: 0.05, twist: 0 });
const CLAP = PX(FS, { rax: -1.5, raz: 0.6, lax: -1.5, laz: -0.6, hy: -0.15, cx: 0.12, twist: 0 });
const BOW = PX(FS, { twist: -0.35, lax: -1.6, laz: -0.05, rax: -1.45, raz: 0.8, cx: 0.0, hy: -0.2, hx: 0.05, llx: -0.3, rlx: 0.35 });
const BOW_FIRE = PX(BOW, { cx: -0.15, rax: -0.9, raz: 0.3 });
const RUSH_POSE = PX(POSE.dashF, { rax: -1.2, raz: 0.2, lax: -1.2, laz: -0.2 });
const KNEE = PX(FS, { rlx: -2.3, llx: 0.35, lean: -0.15, cx: 0.15, hy: 0.15, rax: -2.4, raz: 0.25, lax: -2.4, laz: -0.25 });
const AIR_UP = PX(POSE.air, { rax: -2.9, raz: 0.1, lax: -2.9, laz: -0.1, llx: -0.5, rlx: 0.6 });
const SLAM_WIND = PX(POSE.air, { rax: -2.95, raz: -0.2, lax: -2.95, laz: 0.2, cx: -0.35, llx: -0.6, rlx: -0.6 });
const SLAM_HIT = PX(POSE.air, { rax: -0.4, raz: 0.3, lax: -0.4, laz: -0.3, cx: 0.75, hy: -0.2, llx: -1.0, rlx: 0.3 });
const CROSS = PX(FS, { rax: -1.45, raz: 0.95, lax: -1.45, laz: -0.95, hy: -0.08, hx: -0.25, cx: -0.05, twist: 0 });
const WIDE_WIND = PX(FS, { twist: 0.9, lax: -1.5, laz: 1.3, lay: 0.8, rax: -1.5, raz: -0.2, hy: -0.2 });
const WIDE_SLASH = PX(FS, { twist: -1.0, lax: -1.5, laz: 0.2, lay: -2.4, rax: -1.4, raz: -1.3, ray: -0.4, cx: 0.25, hy: -0.4, llx: -0.4, rlx: 0.4 });
// Проклятый напарник (катана)
const POINT = PX(KH, { rax: -1.65, raz: 0.05, twist: 0.3, cx: 0.05, hx: -0.05 });
const SEV_SWEEP = PX(KT, { hy: -1.0, cx: 0.5, lean: 0.2, twist: -0.6, rax: -0.5, raz: -1.1, ray: 0.9, kat: 1.2, lax: -0.4, laz: 0.6, llx: -1.1, rlx: 1.0 });
const VEIL = PX(KT, { hy: -1.2, cx: 0.9, hx: 0.4, lax: -1.5, laz: -0.3, rax: -1.2, raz: 0.3, llx: -1.6, rlx: -1.5, kat: 1.0 });
const RES_WIND = PX(KT, { rax: 0.4, raz: -0.6, ray: -0.4, kat: 1.4, twist: -0.8, hy: -0.4, cx: 0.2, lax: -0.6, laz: 0.4 });
const RES_SLASH = PX(KT, { rax: -1.4, raz: 1.0, ray: -1.2, kat: 1.3, twist: 0.9, hy: -0.45, cx: 0.3, lax: -0.3, laz: -0.6, llx: -0.5, rlx: 0.5 });
const BF_HIT = PX(KT, { rax: -1.7, raz: 0.05, twist: 0.85, cx: 0.3, hy: -0.35, kat: 1.4, lax: -0.4, laz: 0.4, llx: -0.45, rlx: 0.5 });
const OUT_HOLD = PX(KH, { rax: -0.9, raz: 0.95, ray: 0.3, twist: -0.65, cx: 0.25, hy: -0.5, lax: -0.5, laz: -0.55, llx: -0.4, rlx: 0.45, llz: 0.2, rlz: -0.2 });
const OUT_SWING = PX(KT, { rax: -1.5, raz: -1.2, ray: 1.6, kat: 1.4, twist: 0.9, cx: 0.25, hy: -0.4, lax: -0.6, laz: 0.4, llx: -0.4, rlx: 0.4 });
const SW_RUSH = PX(POSE.dashF, { rax: -1.45, raz: 0.15, lax: 0.9, laz: 0.3 });
const SW_GRAB = PX(KH, { rax: -1.7, raz: 0.1, twist: 0.4, cx: 0.3, hy: -0.35, lax: -0.6, laz: 0.4 });
const SW_LIFT = PX(KH, { rax: -2.8, raz: 0.1, twist: 0.2, cx: -0.2, hy: 0, lax: -0.4, laz: 0.4 });
const SW_SLAM = PX(KH, { rax: -0.6, raz: 0.1, cx: 0.65, hy: -0.75, llx: -0.6, rlx: 0.6, twist: 0.1, lax: -0.3, laz: 0.4 });
const STAB_UP = PX(KT, { rax: -2.7, raz: 0.2, kat: 4.27, lax: -2.7, laz: -0.2, hy: 0.05, cx: -0.15, twist: 0 });
const STAB_DN = PX(KT, { rax: -0.9, raz: 0.25, kat: 2.47, lax: -0.9, laz: -0.25, hy: -0.95, cx: 0.5, twist: 0, llx: -0.7, rlx: 0.6 });
const ELBOW = PX(POSE.dashF, { rax: -1.3, raz: 1.0, ray: -0.8, twist: 0.9, lax: 0.6, laz: 0.3 });
const SPEECH = PX(KT, { lax: -2.3, laz: -0.75, hx: 0.1, cx: 0.15, hy: -0.15 });
const BEAM_POSE = PX(KT, { rax: -1.6, raz: 0.1, kat: 1.45, twist: 0.4, cx: 0.15, hy: -0.3, lax: -0.6, laz: 0.4, llx: -0.4, rlx: 0.4 });
const PL = PX(FS, { lax: -1.65, laz: -0.05, rax: -0.5, twist: -0.55, cx: 0.22, hy: -0.3 });
const PR = PX(FS, { rax: -1.65, raz: 0.05, lax: -0.5, twist: 0.55, cx: 0.22, hy: -0.3 });

// ======================= Пассив Shrine (KoC / Heian): M1 — серые полумесяцы до 24 стадов, блок со всех сторон =======================
export function shrineM1(f, n) {
  const last = n === 4;
  f.chestPos(_c); _c.y += 0.3;
  const origin = _c.clone();
  const dir = new V3();
  const t = f.lastTarget;
  if (t && f.isEnemy(t) && f.dist(t) < 27) { t.chestPos(dir).sub(origin); const l = dir.length(); dir.y = clamp(dir.y, -l * 0.35, l * 0.35); }
  else f.fwd(dir);
  dir.normalize();
  f.fwd(_b);
  if (dir.x * _b.x + dir.z * _b.z < 0.5) f.fwd(dir);
  const roll = last ? Math.PI / 2 + 0.25 : (n % 2 ? 0.32 : -0.32);
  const q = waveQuat(dir, roll);
  const it = G.fx.pool('cresN'); it.mat.color.set('#e2e2e2');
  const S = last ? 4.8 : 3.5;
  projectile({
    owner: f, pos: origin.addScaledVector(dir, 1.4), dir, speed: 130, range: 24, radius: 1.5,
    onHit: (o, p) => {
      const opt = last ? { rag: 0.9, kb: { f: 42, up: 12 }, hitstop: 0.08, shake: 0.4, sfx: 'heavy' } : { stun: 0.75, push: 2.5, hitstop: 0.05, shake: 0.15, sfx: 'slash' };
      G.hit(f, o, { dmg: M1D[n - 1], melee: true, m1: true, block360: true, fx: 'slash', color: '#d8d8d8', from: p, ...opt });
    },
    onStep: (p, dt, tt) => {
      const s = S * Math.min(1, 0.4 + tt / 0.05);
      it.obj.position.copy(p); it.obj.quaternion.copy(q); it.obj.scale.set(s, s, s * 0.8);
      it.mat.opacity = Math.max(0.3, 0.95 - tt * 2);
    },
    onWorld: (p) => G.fx.sparks(p, null, '#ffffff', 5, 22),
    onEnd: () => G.fx.release(it),
  });
}

// ======================= Стальная рука (True Love): к каждому из первых 3 M1 — быстрый джеб =======================
export function steelJab(f, o) {
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    if (t < 0.09) return true;
    if (o.dead || f.dead || f.dist(o) > 7) return false;
    G.hit(f, o, { dmg: 0.5, melee: true, stun: 0.6, push: 1.5, hitstop: 0.03, fx: 'none', shake: 0.08, sfx: 'hit', vol: 0.45 });
    o.chestPos(_c); f.fwd(_b); _c.addScaledVector(_b, -0.9);
    hexSpark(_c);
    return false;
  });
}

// ======================= Cleave: захват, пауза, шквал разрезов, подброс — 40 % текущего HP (мин. 10) =======================
export const sCleave = {
  id: 'cleave', label: 'Cleave', cd: 12, windup: 0.25, color: '#ff2d4a', ai: { kind: 'melee', min: 0, max: 8 },
  cast(f) {
    const tgt = f.autoTarget(12, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = lungeTo(f, tgt, 12, 2.6) / 0.16;
    G.sound('swing', f.pos, 0.6);
    f.startAction({
      name: 'cleave', dur: 0.6, keepVel: true, windup: 0.25,
      frames: [[0, f.idlePose], [0.3, CLEAVE_WIND], [0.46, CLEAVE_GRAB], [1, CLEAVE_GRAB]],
      update: (ff, dt, t) => {
        if (t > 0.12 && t < 0.28) { ff.fwd(_b); const sp = Math.max(8, lunge); ff.vel.x = _b.x * sp; ff.vel.z = _b.z * sp; }
        else ff.friction(dt, 16);
      },
      events: [[0.28, (ff, a) => {
        const v = ff.meleeTargets(5.6, 0.3)[0];
        if (!v) { a.dur = 0.8; a.locked = true; return; }
        const hp0 = v.hp;
        const r = G.hit(ff, v, { dmg: 1, melee: true, unblockable: true, stun: 2.2, push: 0, hitstop: 0.08, fx: 'hit', color: '#ff2d4a', shake: 0.3, sfx: 'hit' });
        if (!hitOk(r)) { if (ff.action === a) { a.dur = 0.8; a.locked = true; } return; }
        cleaveHold(ff, v, Math.max(10, hp0 * 0.4));
      }]],
    });
  },
};
function cleaveHold(f, v, total) {
  const k = 1 / f.dmgMult(); // ровно 40 % — без множителя урона пробуждения
  const rest = Math.max(0, total - 1);
  const per = (rest * 0.6) / 6, fin = rest * 0.4;
  const evs = [];
  for (let i = 0; i < 6; i++) {
    evs.push([0.5 + i * 0.07, (ff) => {
      if (v.dead) return;
      G.hit(ff, v, { dmg: per * k, melee: true, unblockable: true, ignoreIframes: true, stun: 1.2, hitstop: 0.02, fx: 'none', shake: 0.12, sfx: 'slash', vol: 0.4 });
      v.chestPos(_c);
      slashMark(_c, 7); slashMark(_c, 6);
      redSpecks(_c, 3);
    }]);
  }
  evs.push([0.98, (ff) => {
    if (v.dead) return;
    G.hit(ff, v, { dmg: fin * k, melee: true, unblockable: true, ignoreIframes: true, rag: 1.2, kb: { f: 38, up: 34 }, hitstop: 0.13, fx: 'slash', color: '#ff2d4a', shake: 0.6, sfx: 'heavy' });
    v.chestPos(_c); ff.fwd(_b);
    _q.setFromUnitVectors(ZV, _b).multiply(_q2.setFromAxisAngle(ZV, 1.2));
    G.fx.crescent(_c, _q, '#ffffff', 3, 9, 0.25, { a0: 1 });
    G.fx.ring(_c, '#ff3050', 1, 8, 0.3, { a0: 0.9 });
    redSpecks(_c, 8);
  }]);
  f.startAction({
    name: 'cleaveHold', dur: 1.3, events: evs, poseSpeed: 32,
    pose: (ff, a, out) => out.set(a.t < 0.45 ? CLEAVE_GRAB : a.t < 0.95 ? (Math.floor(a.t / 0.05) % 2 ? FLURRY_L : FLURRY_R) : CLEAVE_LAUNCH),
    update: (ff, dt, t) => {
      if (v.dead || t >= 0.98) return;
      holdFront(ff, v, 3, 0.6, dt);
      v.stun = Math.max(v.stun, 0.4);
      if (t < 0.45 && Math.random() < 0.4) { v.chestPos(_c); G.fx.add.spawn(_c.x + rand(-1, 1), _c.y + rand(-1, 1), _c.z + rand(-1, 1), 0, 1, 0, '#ff3050', 0.6, 0.5, 0.1, 0.25); }
    },
  });
}

// ======================= Dismantle: взмах → шквал тонких разрезов по всем ≤30 стадов впереди (17.5 / 10 в блоке) =======================
export const sDismantle = {
  id: 'dismantle', label: 'Dismantle', cd: 13, windup: 0.26, color: '#ffffff', ai: { kind: 'ranged', min: 2, max: 28 },
  cast(f) {
    if (f.airborne()) return dismantleAir(f);
    const tgt = f.autoTarget(30, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    f.startAction({ name: 'dismantle', dur: 0.6, frames: SWIPE, events: [[0.26, (ff) => dismantleWave(ff)]] });
    G.sound('swing', f.pos, 0.5);
  },
};
function dismantleWave(f) {
  const fx = Math.sin(f.yaw), fz = Math.cos(f.yaw);
  f.chestPos(_c);
  const origin = _c.clone();
  // видимая волна: три тонких белых полумесяца веером на 30 стадов
  for (const ang of [-0.4, 0, 0.4]) {
    const dir = new V3(fx, 0, fz).applyAxisAngle(YV, ang);
    const it = G.fx.pool('cresN'); it.mat.color.set('#f4f4f4');
    const q = waveQuat(dir, rand(-0.5, 0.5));
    const p = origin.clone();
    let t = 0;
    G.addTask((dt) => {
      t += dt;
      p.addScaledVector(dir, 120 * dt);
      const k = t / 0.25;
      it.obj.position.copy(p); it.obj.quaternion.copy(q); it.obj.scale.set(4, 4, 3.2); it.mat.opacity = Math.max(0, 0.9 - k * 0.8);
      if (k >= 1 || G.world.pointBlocked(p)) { G.fx.release(it); return false; }
      return true;
    });
  }
  G.sound('slash', f.pos, 0.9);
  for (const o of G.fighters) {
    if (!f.isEnemy(o)) continue;
    const dx = o.pos.x - f.pos.x, dz = o.pos.z - f.pos.z, d = Math.hypot(dx, dz);
    if (d > 30 || Math.abs(o.pos.y - f.pos.y) > 10) continue;
    if (d > 3 && (dx * fx + dz * fz) / d < 0.42) continue;
    const delay = d / 120;
    let n = 0, t = 0;
    G.addTask((dt) => {
      t += dt;
      while (n < 5 && t >= delay + n * 0.065) {
        n++;
        G.hit(f, o, { dmg: 3.5, bullet: true, block360: true, bypassRag: true, chip: 10 / 17.5, chipKill: false, stun: 0.55, push: 1.2, hitstop: 0.02, fx: 'none', shake: 0.12, sfx: 'slash', vol: 0.4, from: f.pos });
        o.chestPos(_c);
        slashMark(_c, 7.5, '#ffffff', 0.2, 0.15); slashMark(_c, 6, '#ffffff', 0.18, 0.13);
        G.fx.burst(_c, '#ffffff', 2.6, 0.08);
        if (n % 2) redSpecks(_c, 3);
      }
      return n < 5 && !o.dead && !G.matchOver;
    });
  }
}
// В воздухе: подскок, сальто, один длинный разрез (25, неблокируемый), борозда из чёрных кубиков дороги
function dismantleAir(f) {
  const tgt = f.autoTarget(50, 0.5);
  if (tgt) f.faceTo(tgt.pos);
  f.vel.y = 16; f.onGround = false;
  f.startAction({
    name: 'dismantleAir', dur: 0.72, noGrav: true, keepVel: true, windup: 0.3, poseSpeed: 40,
    pose: (ff, a, out) => { out.set(a.t < 0.42 ? POSE.air : SWIPE[2][1]); out[K.lean] = -ease.smooth(Math.min(1, a.t / 0.42)) * Math.PI * 2; },
    update: (ff, dt, t) => { ff.vel.x *= 0.9; ff.vel.z *= 0.9; ff.vel.y = t < 0.2 ? 12 : 0; },
    events: [[0.42, (ff) => {
      ff.chestPos(_c);
      const origin = _c.clone();
      const dir = aimDirOf(ff, origin, tgt, new V3(), 0.6);
      const it = G.fx.pool('cresN'); it.mat.color.set('#ffffff');
      const q = waveQuat(dir, 0.15);
      G.sound('slash', ff.pos, 1); G.shake(0.35, ff.pos);
      projectile({
        owner: ff, pos: origin.addScaledVector(dir, 1.5), dir, speed: 115, range: 60, radius: 2.4, pierce: true,
        onHit: (o, p) => G.hit(ff, o, { dmg: 25, unblockable: true, bypassRag: true, rag: 1.1, kb: { f: 30, up: 22 }, hitstop: 0.1, fx: 'slash', color: '#ffffff', shake: 0.55, sfx: 'heavy', from: p }),
        onStep: (p, dt, tt) => {
          const s = Math.min(1, tt / 0.06) * 9;
          it.obj.position.copy(p); it.obj.quaternion.copy(q); it.obj.scale.set(s, s, s * 0.7); it.mat.opacity = 1;
          _a.copy(p).addScaledVector(dir, -7); G.fx.line(_a, p, '#ffffff', 0.12, 0.12);
          const gy = groundY(p.x, p.z, p.y);
          if (p.y - gy < 7 && Math.random() < 0.7) { _a.set(p.x + rand(-0.8, 0.8), gy + 0.3, p.z + rand(-0.8, 0.8)); G.fx.debris(_a, 1, ['#1e1e22', '#2b2b2b', '#d8d8d8'], 20, [0.6, 1.3]); }
        },
        onWorld: (p) => { G.fx.sparks(p, null, '#ffffff', 8, 30); G.fx.debris(p, 6, ['#2b2b2b', '#9a9ea6']); },
        onEnd: () => G.fx.release(it),
      });
    }]],
    onEnd: (ff) => { ff.pose[K.lean] = wrapAngle(ff.pose[K.lean]); },
    onCancel: (ff) => { ff.pose[K.lean] = wrapAngle(ff.pose[K.lean]); },
  });
  G.sound('jump', f.pos, 0.4);
  return true;
}

// ======================= Open: охват пламенем → лук (неуязвимость) → светящаяся стрела → столб огня (30) =======================
function fireArrow(f, origin, dir, speed, onImpact) {
  const g = G.fx.pool('glow'); g.mat.color.set('#ffe7a0');
  projectile({
    owner: f, pos: origin, dir, speed, range: 120, radius: 1.6,
    onHit: () => {},
    onStep: (p) => {
      g.obj.position.copy(p); g.obj.scale.setScalar(7);
      _a.copy(p).addScaledVector(dir, -10);
      G.fx.line(_a, p, '#fff4c8', 0.07, 0.55);
      G.fx.line(_a, p, '#ff9a30', 0.1, 1.1);
      G.fx.add.spawn(p.x + rand(-0.6, 0.6), p.y + rand(-0.6, 0.6), p.z + rand(-0.6, 0.6), rand(-3, 3), rand(1, 4), rand(-3, 3), Math.random() < 0.5 ? '#ff7a1a' : '#ffd040', 1, 1.4, 0.2, 0.3);
    },
    onEnd: (p) => { G.fx.release(g); onImpact(p); },
  });
}
function fireEngulf(f, k) {
  for (let i = 0; i < 3; i++) {
    _a.set(f.pos.x + rand(-1.4, 1.4), f.pos.y + rand(0, 5.5) * f.scale, f.pos.z + rand(-1.4, 1.4));
    G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-1, 1), rand(4, 9), rand(-1, 1), i ? '#ff7a1a' : '#ffd040', 0.9 * k, rand(1.4, 2.4), 0.2, 0.45);
  }
}
function firePillar(f, p, dmg, R) {
  const gy = groundY(p.x, p.z, p.y + 2);
  const base = new V3(p.x, gy + 0.2, p.z);
  beamFX(base, YV, 30, R * 0.75, '#ff6a10', '#fff2b0', 1.1);
  G.fx.ring(base, '#ff6a10', 1, R * 2, 0.5, { axis: 'y', a0: 0.9 });
  G.fx.ring(base, '#ffffff', 1, R * 1.3, 0.35, { axis: 'y', a0: 0.8 });
  G.fx.burst(_a.set(p.x, gy + 4, p.z), '#ffd070', R * 2.6, 0.3);
  G.fx.crater(base, R * 1.1, 5);
  G.fx.debris(base, 10, ['#2b2b2b', '#3a3a40', '#ff7a1a']);
  _a.set(p.x, gy + 3, p.z);
  for (const o of f.enemiesNear(_a, R, 22)) {
    G.hit(f, o, { dmg, unblockable: true, bypassRag: true, noCounter: true, rag: 1.4, kb: { f: 8, up: 62 }, from: base, hitstop: 0.12, fx: 'fire', shake: 0.8, sfx: 'boom' });
  }
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    for (let i = 0; i < 3; i++) G.fx.add.spawn(p.x + rand(-R, R) * 0.6, gy + rand(0, 3), p.z + rand(-R, R) * 0.6, rand(-2, 2), rand(8, 18), rand(-2, 2), Math.random() < 0.5 ? '#ff5a10' : '#ffc040', 1, 1.8, 0.2, 0.7);
    return t < 1.6 && !G.matchOver;
  });
  G.shake(0.8, p); G.sound('boom', p, 1); G.sound('heavy', p, 0.6);
  G.flashNear(p, '#ff8a2a', 0.45, 60);
}
export const sOpen = {
  id: 'open', label: 'Open', cd: 40, windup: 0.9, color: '#ff8a2a', ai: { kind: 'ranged', min: 8, max: 90 },
  cast(f) {
    let tgt = f.camTarget(110);
    G.callout(f, '開 — OPEN', '#ff8a2a', true);
    G.sound('charge', f.pos, 0.6);
    const ag = G.fx.pool('glow'); ag.mat.color.set('#ffb040'); ag.obj.visible = false;
    let freed = false;
    const free = () => { if (!freed) { freed = true; G.fx.release(ag); } };
    f.startAction({
      name: 'open', dur: 1.95, armor: true, iframes: 1.55,
      frames: [[0, f.idlePose], [0.1, CLAP], [0.42, CLAP], [0.52, BOW], [0.79, BOW], [0.83, BOW_FIRE], [1, BOW_FIRE]],
      update: (ff, dt, t) => {
        if (tgt && tgt.dead) tgt = null;
        if (t < 0.95) fireEngulf(ff, 1 - t * 0.5);
        else if (t < 1.55 && !freed) {
          if (tgt) ff.faceTo(tgt.pos); else if (ff.isPlayer) ff.yaw = Math.atan2(ff.aim.x, ff.aim.z);
          ff.handPos('L', _a); ff.handPos('R', _c);
          G.fx.line(_c, _a, '#ffe08a', 0.05, 0.25);
          ag.obj.visible = true; ag.obj.position.copy(_a); ag.obj.scale.setScalar(3 + (t - 0.95) * 9);
          if (Math.random() < 0.6) G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-1, 1), rand(1, 4), rand(-1, 1), '#ffd040', 1, 1.2, 0.2, 0.3);
        }
      },
      events: [[1.55, (ff) => {
        free();
        ff.handPos('L', _a);
        const origin = _a.clone();
        const dir = aimDirOf(ff, origin, tgt, new V3(), 0.5);
        ff.vel.addScaledVector(dir, -12);
        G.fx.burst(origin, '#fff0b0', 12, 0.2);
        G.sound('beam', ff.pos, 0.9);
        if (ff.isPlayer) G.hud.flash('#ff9a30', 0.22, 2.5);
        fireArrow(ff, origin, dir, 200, (p) => firePillar(ff, p, 30, 8));
      }]],
      onCancel: free, onEnd: free,
    });
  },
};
// Heian: Open FURNACE — два хлопка, стрела, вспышка, взрыв (45) и ударная волна (10–20, сильнее вдали)
export const sFurnace = {
  id: 'furnace', label: 'Open FURNACE', cd: 20, windup: 0.6, color: '#ffb040', ai: { kind: 'ranged', min: 8, max: 85 },
  cast(f) {
    let tgt = f.camTarget(110);
    G.callout(f, 'FUGA', '#ffb040', true);
    const clap = (ff) => { ff.handPos('R', _a); G.fx.burst(_a, '#ffd070', 6, 0.15); G.fx.ring(_a, '#ffb040', 0.4, 4, 0.22, { a0: 0.9 }); G.sound('hit', ff.pos, 0.7); fireEngulf(ff, 1); };
    f.startAction({
      name: 'furnace', dur: 1.45, armor: true, iframes: 0.75,
      frames: [[0, f.idlePose], [0.08, CLAP_OPEN], [0.16, CLAP], [0.27, CLAP_OPEN], [0.35, CLAP], [0.48, BOW], [0.7, BOW], [0.76, BOW_FIRE], [1, BOW_FIRE]],
      update: (ff, dt, t) => {
        if (tgt && tgt.dead) tgt = null;
        if (t > 0.6 && t < 1.05) {
          if (tgt) ff.faceTo(tgt.pos); else if (ff.isPlayer) ff.yaw = Math.atan2(ff.aim.x, ff.aim.z);
          ff.handPos('L', _a); ff.handPos('R', _c); G.fx.line(_c, _a, '#fff0a0', 0.05, 0.3);
        }
        if (Math.random() < 0.5) fireEngulf(ff, 0.5);
      },
      events: [[0.22, clap], [0.48, clap], [1.05, (ff) => {
        ff.handPos('L', _a);
        const origin = _a.clone();
        const dir = aimDirOf(ff, origin, tgt, new V3(), 0.5);
        ff.vel.addScaledVector(dir, -14);
        G.sound('beam', ff.pos, 1);
        if (ff.isPlayer) G.hud.flash('#ffb040', 0.25, 2.5);
        fireArrow(ff, origin, dir, 200, (p) => furnaceBlast(ff, p));
      }]],
    });
  },
};
function furnaceBlast(f, p) {
  const c = p.clone();
  const flare = G.fx.glow(c, '#fff4c0', 12, 0.3, { s0: 2, a0: 1 });
  void flare;
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    if (t < 0.28) return !G.matchOver;
    const gy = groundY(c.x, c.z, c.y + 2);
    const base = _a.set(c.x, gy + 0.3, c.z).clone();
    firePillar(f, c, 45, 10);
    G.fx.sphere(base, '#ffb040', 2, 14, 0.4, { a0: 0.8 });
    for (let i = 0; i < 3; i++) G.fx.ring(base, i ? '#ffd070' : '#ffffff', 2, 34, 0.6 + i * 0.12, { axis: 'y', a0: 0.85, delay: i * 0.05 });
    // ударная волна: вдали сильнее (10 → 20)
    _c.set(c.x, gy + 2, c.z);
    for (const o of f.enemiesNear(_c, 32, 14)) {
      const d = Math.hypot(o.pos.x - c.x, o.pos.z - c.z);
      if (d < 10) continue;
      G.hit(f, o, { dmg: 10 + 10 * clamp((d - 10) / 22, 0, 1), unblockable: true, bypassRag: true, rag: 0.9, kb: { f: 50, up: 18 }, from: base, hitstop: 0.06, fx: 'fire', shake: 0.4, sfx: 'boom', vol: 0.6 });
    }
    G.flashNear(c, '#ffb040', 0.75, 90);
    return false;
  });
}

// ======================= Rush: 60 стадов на ≈120 ст/с → толчок, колено в небо (линии скорости), удар вниз (5+15+5) =======================
export const sRush = {
  id: 'rush', label: 'Rush', cd: 15, windup: 0.14, color: '#ff6a8a', ai: { kind: 'gap', min: 5, max: 50 },
  cast(f) {
    const tgt = f.autoTarget(60, 0.6);
    if (tgt) f.faceTo(tgt.pos);
    f.fwd(_b);
    const dx = _b.x, dz = _b.z;
    G.sound('dash', f.pos, 0.8);
    f.startAction({
      name: 'rush', dur: 0.64, keepVel: true, windup: 0.14, poseSpeed: 26,
      pose: (ff, a, out) => out.set(a.t < 0.14 ? PX(ff.idlePose, { hy: -0.4, cx: 0.3 }) : RUSH_POSE),
      update: (ff, dt, t) => {
        if (t < 0.14) { ff.friction(dt, 20); return; }
        ff.vel.x = dx * 120; ff.vel.z = dz * 120;
        if (Math.random() < 0.9) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.5, 5), ff.pos.z + rand(-1, 1)); _c.set(-dx * 50, 0, -dz * 50); G.fx.str.add(_a, _c, '#ffe0e8', 0.15, 0.09, 4, { drag: 6 }); }
        if (Math.random() < 0.5) { ff.chestPos(_a); G.fx.add.spawn(_a.x, _a.y, _a.z, 0, 0, 0, '#ff8aa0', 0.5, 4, 1, 0.15); }
        const v = ff.meleeTargets(3.8, 0.4)[0];
        if (!v) return;
        const r = G.hit(ff, v, { dmg: 5, melee: true, unblockable: true, stun: 2.5, push: 0, hitstop: 0.1, fx: 'heavy', color: '#ff8aa0', shake: 0.5, sfx: 'heavy' });
        ff.vel.x *= 0.1; ff.vel.z *= 0.1;
        if (hitOk(r)) rushCombo(ff, v, dx, dz);
        else if (r !== 'counter') ff.endlag(0.5);
      },
      onEnd: (ff) => { ff.vel.x *= 0.2; ff.vel.z *= 0.2; ff.endlag(0.45); },
    });
  },
};
function rushCombo(f, v, dx, dz) {
  const dst = new V3(v.pos.x + dx * 11, v.pos.y, v.pos.z + dz * 11);
  G.world.collide(dst, 1.2, 5);
  const gy = groundY(dst.x, dst.z, v.pos.y + 3);
  dst.y = gy;
  f.vel.set(0, 0, 0);
  const SLAM = 0.95;
  f.startAction({
    name: 'rushCombo', dur: 1.5, noGrav: true, keepVel: true, armor: true, poseSpeed: 30,
    pose: (ff, a, out) => out.set(a.t < 0.3 ? RUSH_POSE : a.t < 0.5 ? KNEE : a.t < 0.82 ? AIR_UP : a.t < SLAM ? SLAM_WIND : SLAM_HIT),
    update: (ff, dt, t, a) => {
      if (t < SLAM && !v.dead) {
        v.stun = Math.max(v.stun, 0.5); v.blocking = false;
        if (t < 0.32) {
          // цель отлетает вперёд, Сукуна догоняет
          const k = ease.out(Math.min(1, t / 0.25));
          _a.set(dst.x, gy + Math.sin(k * Math.PI) * 2, dst.z);
          holdAt(v, _a, dt, 16);
          _c.set(dst.x - dx * 2.6, gy, dst.z - dz * 2.6);
          ff.pos.lerp(_c, 1 - Math.exp(-11 * dt));
          ff.faceTo(v.pos);
        } else {
          // колено → цель уходит в небо, затем прыжок следом
          const k = ease.out3(Math.min(1, (t - 0.32) / 0.42));
          _a.set(dst.x, gy + 1 + 17 * k, dst.z);
          holdAt(v, _a, dt, 22);
          if (Math.random() < 0.9) { _c.set(v.pos.x + rand(-2.5, 2.5), v.pos.y + rand(-3, 3), v.pos.z + rand(-2.5, 2.5)); G.fx.str.add(_c, _b.set(0, -70, 0), '#ffffff', 0.18, 0.07, rand(4, 8), { drag: 3 }); }
          if (t > 0.48) {
            const j = ease.out(Math.min(1, (t - 0.48) / 0.36));
            _c.set(dst.x - dx * 1.8, gy + 21 * j, dst.z - dz * 1.8);
            ff.pos.lerp(_c, 1 - Math.exp(-14 * dt));
          }
        }
      } else if (t >= SLAM) {
        ff.vel.x = 0; ff.vel.z = 0; ff.vel.y = Math.max(ff.vel.y - 140 * dt, -70);
        if (ff.onGround && !a.landed) { a.landed = true; _a.set(ff.pos.x, ff.pos.y + 0.2, ff.pos.z); G.fx.dust(_a, 10, 3); G.sound('hit', ff.pos, 0.6); }
      }
    },
    events: [
      [0.32, (ff) => {
        if (v.dead) return;
        G.hit(ff, v, { dmg: 15, melee: true, unblockable: true, ignoreIframes: true, stun: 1.6, hitstop: 0.14, fx: 'heavy', color: '#ffffff', shake: 0.65, sfx: 'heavy' });
        v.chestPos(_a); G.fx.ring(_a, '#ffffff', 1, 9, 0.3, { axis: 'y', a0: 1 }); G.fx.sparks(_a, YV, '#ffffff', 14, 60, { spread: 0.5 });
        if (ff.isPlayer || v.isPlayer) G.hud.flash('#ffffff', 0.25, 4);
      }],
      [SLAM, (ff) => {
        if (v.dead) return;
        G.hit(ff, v, { dmg: 5, melee: true, unblockable: true, downslam: true, bypassRag: true, ignoreIframes: true, rag: 1.2, kb: { f: 4, up: -75 }, hitstop: 0.13, fx: 'heavy', color: '#ff8aa0', shake: 0.75, sfx: 'boom' });
        let lt = 0;
        G.addTask((dt) => {
          lt += dt;
          if (!(v.onGround || lt > 0.6) || v.dead) return lt < 0.8;
          _a.set(v.pos.x, v.pos.y + 0.2, v.pos.z);
          craterAt(_a, 9); G.fx.ring(_a, '#ffffff', 1, 13, 0.4, { axis: 'y', a0: 0.9 });
          G.shake(0.6, v.pos); G.sound('boom', v.pos, 0.8);
          return false;
        });
      }],
    ],
  });
}

// ======================= Heian Form: Incantation (R) — 5 % пробуждения за заклинание, пузыри-реплики =======================
const CHANTS = ['SCALE OF THE DRAGON…', 'RECOIL…', 'TWIN METEORS'];
export const sIncant = {
  id: 'incant', label: 'Incantation', cd: 0.6, color: '#ff9578', ai: { kind: 'chant' },
  cast(f) {
    if (f.chant >= 3) return false;
    if (f.awakenPct() < 5) return false;
    f.spendAwaken(5);
    f.chant++;
    G.hud.chant(f, CHANTS[f.chant - 1]);
    f.startAction({ name: 'chant', dur: 0.85, move: 0.55, noFeint: true, frames: [[0, f.idlePose], [0.22, CROSS], [0.55, POSE.sign], [1, f.idlePose]] });
    f.chestPos(_a);
    G.fx.ring(_a, '#ff5a20', 1, 6 + f.chant * 2, 0.4, { a0: 0.7 });
    G.fx.particles(_a, { n: 10, color: ['#ff9578', '#ffffff'], speed: 6, up: 3, size: 0.7, life: 0.5 });
    G.sound('charge', f.pos, 0.3 + f.chant * 0.12);
  },
};
// 1 после 1 заклинания: «Kai!» — шесть Dismantle по области у цели (6 × 5)
export const sKai = {
  id: 'kai', label: 'Dismantle Barrage', tip: 'CHANT ×1', cd: 8, windup: 0.2, color: '#ffffff', ai: { kind: 'ranged', min: 2, max: 40 },
  cast(f) {
    const tgt = f.camTarget(45);
    const pt = new V3();
    if (tgt) { pt.copy(tgt.pos); f.faceTo(tgt.pos); } else { f.fwd(_b); pt.copy(f.pos).addScaledVector(_b, 14); }
    f.chant = 0;
    G.callout(f, '解 — KAI!', '#ffffff', true);
    const evs = [];
    for (let i = 0; i < 6; i++) {
      evs.push([0.22 + i * 0.08, (ff) => {
        if (tgt && !tgt.dead) pt.lerp(tgt.pos, 0.6);
        _c.set(pt.x + rand(-3.5, 3.5), pt.y + rand(1.5, 4.5), pt.z + rand(-3.5, 3.5));
        slashMark(_c, 12, '#ffffff', 0.22, 0.16); slashMark(_c, 9, '#ffffff', 0.18, 0.12);
        G.fx.burst(_c, '#ffffff', 4, 0.12);
        for (const o of ff.enemiesNear(_c, 5)) G.hit(ff, o, { dmg: 5, bullet: true, block360: true, bypassRag: true, chip: 0.4, stun: 0.6, push: 2, hitstop: 0.03, fx: 'none', from: _c, shake: 0.2, sfx: 'slash', vol: 0.6 });
        if (i % 2 === 0) { _a.set(_c.x, groundY(_c.x, _c.z, _c.y) + 0.3, _c.z); G.fx.debris(_a, 3, ['#1e1e22', '#2b2b2b', '#d8d8d8'], 16); }
        G.sound('slash', _c, 0.7);
      }]);
    }
    f.startAction({ name: 'kai', dur: 0.85, frames: [[0, f.idlePose], [0.18, PX(FS, { lax: -1.7, laz: 0.1, twist: -0.4, hy: -0.2 })], [0.3, PX(FS, { lax: -1.75, laz: -0.5, twist: 0.3, cx: 0.15, hy: -0.25 })], [1, f.idlePose]], events: evs });
  },
};
// 1 после 2 заклинаний: Disgraced Sovereign — левитация, разрезы на 25 стадов, затем «рост», стирающий всё в 27.5 (19)
export const sSovereign = {
  id: 'sovereign', label: 'Disgraced Sovereign', tip: 'CHANT ×2', cd: 8, windup: 0.3, color: '#ff9578', ai: { kind: 'aoe', min: 0, max: 24 },
  cast(f) {
    f.chant = 0;
    G.callout(f, 'Disgraced Sovereign', '#ff9578', true);
    G.sound('charge', f.pos, 0.8);
    let tick = 0;
    f.startAction({
      name: 'sovereign', dur: 2.2, armor: true, noGrav: true, keepVel: true,
      frames: [[0, f.idlePose], [0.12, POSE.spread], [0.8, POSE.spread], [0.86, POSE.roar], [1, f.idlePose]],
      update: (ff, dt, t) => {
        ff.vel.set(0, t < 0.45 ? 9 : t > 1.95 ? -16 : 0, 0);
        if (t > 0.45 && t < 1.65) {
          tick -= dt;
          for (let i = 0; i < 2; i++) {
            const an = rand(0, Math.PI * 2), rr = Math.sqrt(Math.random()) * 25;
            _c.set(ff.pos.x + Math.cos(an) * rr, groundY(ff.pos.x, ff.pos.z, ff.pos.y) + rand(1, 7), ff.pos.z + Math.sin(an) * rr);
            slashMark(_c, rand(5, 10), Math.random() < 0.2 ? '#ff6070' : '#ffffff', 0.15, 0.1);
          }
          if (tick <= 0) {
            tick = 0.24;
            _c.set(ff.pos.x, ff.pos.y, ff.pos.z);
            for (const o of ff.enemiesNear(_c, 25, 14)) {
              G.hit(ff, o, { dmg: 2.8, bullet: true, block360: true, chip: 0.25, bypassRag: true, stun: 0.4, hitstop: 0.02, fx: 'none', shake: 0.08, sfx: 'slash', vol: 0.3 });
              o.chestPos(_a); slashMark(_a, 5);
            }
          }
        }
      },
      events: [[1.7, (ff) => {
        ff.chestPos(_c);
        G.fx.sphere(_c, '#ffffff', 2, 27.5, 0.45, { a0: 0.8 });
        G.fx.ring(_c, '#ff9578', 2, 30, 0.5, { axis: 'y', a0: 0.9 });
        G.fx.burst(_c, '#ffffff', 30, 0.3);
        for (const o of ff.enemiesNear(_c, 27.5, 18)) G.hit(ff, o, { dmg: 5, unblockable: true, bypassRag: true, rag: 1.0, kb: { f: 45, up: 22 }, from: ff.pos, hitstop: 0.08, fx: 'slash', color: '#ffffff', shake: 0.5, sfx: 'boom' });
        G.flashNear(ff.pos, '#ffffff', 0.5, 50);
        G.shake(0.6, ff.pos);
      }]],
    });
  },
};
// 1 после 3 заклинаний: World Cutting Slash — огромный горизонтальный разрез (80, меньше при нескольких целях)
export const sWCS = {
  id: 'wcs', label: 'World Cutting Slash', tip: 'CHANT ×3', cd: 8, windup: 0.95, color: '#ffffff', ai: { kind: 'ranged', min: 3, max: 90 },
  cast(f) {
    f.chant = 0;
    let tgt = f.camTarget(130);
    G.callout(f, 'WORLD CUTTING SLASH', '#ffffff');
    G.sound('charge', f.pos, 1);
    f.startAction({
      name: 'wcs', dur: 1.55, armor: true, iframes: 1.6,
      frames: [[0, f.idlePose], [0.2, POSE.sign], [0.55, POSE.sign], [0.62, WIDE_WIND], [0.7, WIDE_SLASH], [1, WIDE_SLASH]],
      update: (ff, dt, t) => {
        if (tgt && tgt.dead) tgt = null;
        if (t < 0.95) { if (tgt) ff.faceTo(tgt.pos); else if (ff.isPlayer) ff.yaw = Math.atan2(ff.aim.x, ff.aim.z); }
        if (t < 0.95 && Math.random() < 0.7) { ff.chestPos(_a); _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize().multiplyScalar(5).add(_a); G.fx.line(_a, _b, '#ffffff', 0.08, 0.06); }
      },
      events: [[0.95, (ff) => worldCut(ff)]],
    });
  },
};
function worldCut(f) {
  const fx = Math.sin(f.yaw), fz = Math.cos(f.yaw), rx = -fz, rz = fx;
  const y0 = f.pos.y + 3.2;
  const L = 140, SP = 170, HW = 32;
  const list = [];
  for (const o of G.fighters) {
    if (!f.isEnemy(o)) continue;
    const dx = o.pos.x - f.pos.x, dz = o.pos.z - f.pos.z;
    const fwd = dx * fx + dz * fz, lat = dx * rx + dz * rz, dy = o.pos.y - f.pos.y;
    if (fwd > -1 && fwd < L && Math.abs(lat) < HW && dy > -8 && dy < 14) list.push({ o, fwd });
  }
  const dmg = 80 / (1 + 0.3 * Math.max(0, list.length - 1));
  const it = G.fx.pool('cresN'); it.mat.color.set('#ffffff');
  const q = waveQuat(_d.set(fx, 0, fz), 0.12, new THREE.Quaternion(), 1.3);
  const p = new V3(f.pos.x, y0, f.pos.z);
  let trav = 0;
  G.shake(0.9, f.pos); G.sound('slash', f.pos, 1); G.sound('boom', f.pos, 0.8);
  G.flashNear(f.pos, '#ffffff', 0.6, 70);
  G.addTask((dt) => {
    trav += SP * dt;
    p.set(f.pos.x + fx * trav, y0, f.pos.z + fz * trav);
    it.obj.position.copy(p); it.obj.quaternion.copy(q); it.obj.scale.set(HW * 1.05, HW, HW * 0.3); it.mat.opacity = Math.max(0, 1 - trav / L);
    _a.set(p.x - rx * HW, y0, p.z - rz * HW); _b.set(p.x + rx * HW, y0, p.z + rz * HW);
    G.fx.line(_a, _b, '#0b0b0b', 0.14, 1.1, true); G.fx.line(_a, _b, '#ffffff', 0.12, 0.55);
    if (Math.random() < 0.5) { _c.set(p.x + rx * rand(-HW, HW), y0 + rand(-1.5, 1.5), p.z + rz * rand(-HW, HW)); G.fx.str.add(_c, _e.set(fx * 60, 0, fz * 60), '#ffffff', 0.25, 0.12, 6, { drag: 2 }); }
    if (Math.random() < 0.8) { _c.set(p.x + rx * rand(-HW, HW), 0.4, p.z + rz * rand(-HW, HW)); G.fx.debris(_c, 2, ['#1e1e22', '#2b2b2b', '#d8d8d8'], 18, [0.6, 1.4]); }
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].fwd > trav) continue;
      const o = list[i].o; list.splice(i, 1);
      G.hit(f, o, { dmg, unblockable: true, noCounter: true, pierce: true, bypassRag: true, rag: 1.6, kb: { f: 60, up: 24 }, from: f.pos, hitstop: 0.15, fx: 'slash', color: '#ffffff', shake: 0.9, sfx: 'boom' });
      o.chestPos(_c); slashMark(_c, 14, '#ffffff', 0.3, 0.25); redSpecks(_c, 10);
    }
    if (trav >= L || G.matchOver) { G.fx.release(it); return false; }
    return true;
  });
}

// ======================= Проклятый напарник: Рика (R) =======================
function rikaGhost(f) {
  const R = getRika();
  f.rikaGhost = R;
  R.root.scale.setScalar(0.01);
  R.armL.rotation.set(0, 0, 0); R.armR.rotation.set(0, 0, 0);
  R.mat.opacity = 0.34;
  rightOf(f, _c); f.fwd(_b);
  R.root.position.copy(f.pos).addScaledVector(_c, 2.4).addScaledVector(_b, -0.8);
  R.root.rotation.y = f.yaw;
  const glow = G.fx.pool('glow'); glow.mat.color.set('#ff8cf0'); glow.obj.visible = false;
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    if (f.rikaGhost !== R || f.dead || f.rikaMode === 0 || G.matchOver) {
      if (f.rikaGhost === R) f.rikaGhost = null;
      G.fx.release(glow);
      R.busy = false; R.root.visible = false;
      return false;
    }
    const hide = f.awakened > 0;
    R.root.visible = !hide;
    if (hide) { glow.obj.visible = false; return true; }
    const s = 0.42 * ease.out3(Math.min(1, t / 0.45));
    R.root.scale.setScalar(Math.max(0.01, s));
    rightOf(f, _c); f.fwd(_b);
    _a.copy(f.pos).addScaledVector(_c, 2.3).addScaledVector(_b, -0.9);
    _a.y = f.pos.y + 1.6 + Math.sin(t * 2.4) * 0.25;
    R.root.position.lerp(_a, 1 - Math.exp(-9 * dt));
    R.root.rotation.y = angleDamp(R.root.rotation.y, f.yaw, 7, dt);
    R.armL.rotation.x = -0.35 + Math.sin(t * 2) * 0.12; R.armR.rotation.x = -0.35 - Math.sin(t * 2) * 0.12;
    // режим приёмов Рики: кольцо на шее светится, призрак плотнее
    const on = f.rikaMode === 2;
    occlusionFade(R, on ? 0.62 : 0.44, dt);
    glow.obj.visible = on;
    if (on) { f.chestPos(_a); f.fwd(_b); _a.addScaledVector(_b, 0.6); _a.y += 0.35 * f.scale; glow.obj.position.copy(_a); glow.obj.scale.setScalar(1.4 + Math.sin(t * 9) * 0.25); }
    if (Math.random() < 0.15) { R.root.getWorldPosition(_a); _a.y += rand(0, 3); G.fx.norm.spawn(_a.x + rand(-1, 1), _a.y, _a.z + rand(-1, 1), 0, rand(0.5, 1.5), 0, '#1a1020', 0.35, 0.9, 1.8, 0.8); }
    return true;
  });
}
const rikaDone = (f) => { if (f.rikaMode === 2) f.setRikaMode(1); };
const rikaCmd = (f) => { if (f.canAct()) f.startAction({ name: 'rikaCmd', dur: 0.32, frames: [[0, f.idlePose], [0.35, POINT], [1, POINT]] }); };
export const yRika = {
  id: 'rika', label: 'Rika', cd: 0.35, instant: true, color: '#efe6f5', ai: { kind: 'rika' },
  cast(f) {
    if (f.rikaMode === 0) {
      f.setRikaMode(1);
      rikaGhost(f);
      rightOf(f, _c); f.chestPos(_a).addScaledVector(_c, 2.4);
      smokePuff(_a, 24, 2.6, 9);
      G.sound('tp', f.pos, 0.5);
      return;
    }
    if (f.rikaMode === 1) {
      if (!f.rikaGhost) rikaGhost(f);
      f.setRikaMode(2);
      f.chestPos(_a); G.fx.ring(_a, '#ff9cf2', 0.4, 3, 0.25, { a0: 0.9 });
      G.sound('charge', f.pos, 0.35);
      return;
    }
    f.setRikaMode(1);
    G.sound('swing', f.pos, 0.25);
  },
};
// Рика: кулак из чёрного дыма поднимается над целью и обрушивается (10, отскок)
export const yRSmash = {
  id: 'rkSmash', label: 'Rika Smash', tip: 'TARGET', cd: 10, shared: true, color: '#efe6f5', ai: { kind: 'ranged', min: 0, max: 30 },
  cast(f) {
    const tgt = f.camTarget(32);
    if (!tgt) return false;
    rikaDone(f); rikaCmd(f);
    const air = tgt.airborne();
    const arm = getRikaArm();
    arm.root.rotation.set(0, f.yaw, 0); arm.root.scale.setScalar(0.01);
    const pt = tgt.pos.clone();
    let t = 0, hit = false;
    G.sound('charge', pt, 0.5);
    G.addTask((dt) => {
      t += dt;
      if (!tgt.dead && t < 0.5) pt.lerp(tgt.pos, 1 - Math.exp(-12 * dt));
      const gy = air ? pt.y : groundY(pt.x, pt.z, pt.y + 2);
      // дымное облако над целью, кулак выходит, приподнимается и бьёт вниз
      if (t < 0.5 && Math.random() < 0.9) { _a.set(pt.x + rand(-2.5, 2.5), gy + 15 + rand(-1, 1.5), pt.z + rand(-2.5, 2.5)); G.fx.norm.spawn(_a.x, _a.y, _a.z, rand(-1, 1), rand(-0.5, 0.5), rand(-1, 1), Math.random() < 0.5 ? '#100c12' : '#241e28', 0.9, 3, 5, 0.6); }
      let y;
      if (t < 0.3) y = 18 - 6 * ease.out(t / 0.3);
      else if (t < 0.46) y = 12 + 2.5 * ease.out((t - 0.3) / 0.16);
      else if (t < 0.58) y = 14.5 - 12.3 * ease.in((t - 0.46) / 0.12);
      else y = 2.2 + Math.max(0, t - 0.85) * 40;
      arm.root.position.set(pt.x, gy + y, pt.z);
      arm.root.scale.setScalar(Math.min(0.8, 0.2 + t * 2.2) * (t > 0.95 ? Math.max(0.01, 1 - (t - 0.95) / 0.25) : 1));
      if (!hit && t >= 0.58) {
        hit = true;
        _a.set(pt.x, gy + 1.5, pt.z);
        for (const o of f.enemiesNear(_a, 6.5)) {
          G.hit(f, o, { dmg: air ? 8 : 10, bullet: true, block360: true, bypassRag: true, rag: air ? 1.4 : 1.0, kb: air ? { f: 4, up: -55 } : { f: 6, up: 34 }, from: pt, hitstop: 0.1, fx: 'heavy', color: '#e8e0f0', shake: 0.55, sfx: 'heavy' });
        }
        _a.y = gy + 0.3;
        G.fx.ring(_a, '#e8e0f0', 1, 12, 0.4, { axis: 'y' });
        craterAt(_a, 8, ['#1b1b1b', '#2b2b2b', '#d8d8d8']);
        smokePuff(_a, 14, 2.4, 12);
        G.shake(0.5, pt); G.sound('boom', pt, 0.8);
      }
      if (t >= 1.2 || G.matchOver) { arm.busy = false; arm.root.visible = false; return false; }
      return true;
    });
  },
};
// Рика подталкивает вперёд (в воздухе — вверх); посреди своего приёма — финт этого приёма
export const yRLaunch = {
  id: 'rkLaunch', label: 'Rika Launch', cd: 10, shared: true, instant: true, color: '#efe6f5', ai: { kind: 'gap', min: 9, max: 30 },
  cast(f) {
    const a = f.action;
    let feint = false;
    if (a && a.name !== 'emote' && a.name !== 'land' && a.name !== 'rikaCmd') {
      if (a.noFeint || a.armor || !(a.slot != null || a.name === 'm1')) return false;
      a.onCancel?.(f, a);
      f.action = null; feint = true;
      if (a.slot != null && a.cdArr) a.cdArr[a.slot] = Math.min(a.cdArr[a.slot], 4);
      if (a.name === 'm1') f.combo = Math.max(0, f.combo - 1);
    } else if (a) f.action = null;
    rikaDone(f);
    const air = !f.onGround;
    let dx = f.input.mx, dz = f.input.mz;
    const l = Math.hypot(dx, dz);
    if (l > 0.3) { dx /= l; dz /= l; } else { dx = f.aim.x; dz = f.aim.z; const k = Math.hypot(dx, dz) || 1; dx /= k; dz /= k; }
    _a.set(f.pos.x - dx * 2.5, f.pos.y + 2.5, f.pos.z - dz * 2.5);
    smokePuff(_a, 18, 2.4, 8);
    if (air) { f.vel.y = 48; f.onGround = false; }
    f.startAction({
      name: 'rkLaunch', dur: 0.36, keepVel: true, poseSpeed: 24, noFeint: true,
      pose: (ff, a2, out) => out.set(air ? POSE.air : POSE.dashF),
      update: (ff, dt, t) => {
        const sp = (air ? 26 : 78) * Math.sqrt(Math.max(0, 1 - t / 0.36));
        ff.vel.x = dx * sp; ff.vel.z = dz * sp;
        if (Math.random() < 0.8) { ff.chestPos(_a); _a.x += rand(-1, 1); _a.z += rand(-1, 1); G.fx.str.add(_a, _c.set(-dx * 30, 0, -dz * 30), Math.random() < 0.5 ? '#ff9cf2' : '#ffffff', 0.2, 0.1, 2.6, { drag: 6 }); }
      },
    });
    if (feint) { f.chestPos(_a); G.fx.ring(_a, '#ffffff', 2.6, 3.4, 0.25, { a0: 0.6 }); }
    G.sound('dash', f.pos, 0.7);
    return feint ? 6 : undefined;
  },
};
// Рика: медленный замах из дыма у цели (≤10 стадов) и тяжёлый удар — 12, в блок 18 (без рэгдолла, но с отбросом)
export const yRHaymaker = {
  id: 'rkHay', label: 'Rika Haymaker', tip: 'TARGET', cd: 10, shared: true, color: '#efe6f5', ai: { kind: 'melee', min: 0, max: 10 },
  cast(f) {
    const tgt = f.camTarget(11);
    if (!tgt) return false;
    rikaDone(f); rikaCmd(f);
    const arm = getRikaArm();
    arm.root.scale.setScalar(0.01);
    const dir = new V3(), src = new V3();
    let t = 0, hit = false;
    G.sound('charge', tgt.pos, 0.6);
    G.addTask((dt) => {
      t += dt;
      if (!hit) {
        if (tgt.dead) { arm.busy = false; arm.root.visible = false; return false; }
        dir.set(tgt.pos.x - f.pos.x, 0, tgt.pos.z - f.pos.z);
        if (dir.lengthSq() < 0.01) f.fwd(dir);
        dir.normalize();
      }
      tgt.chestPos(_c);
      // облако дыма сбоку-сзади цели (со стороны Юты), рука медленно отводится и выстреливает
      const back = t < 0.75 ? 6 + 4 * ease.out(t / 0.75) : t < 0.84 ? 10 - 8.3 * ease.in((t - 0.75) / 0.09) : 1.7;
      src.copy(_c).addScaledVector(dir, -11);
      if (t < 0.8 && Math.random() < 0.9) G.fx.norm.spawn(src.x + rand(-2, 2), src.y + rand(-1.5, 2), src.z + rand(-2, 2), rand(-1, 1), rand(0, 1), rand(-1, 1), Math.random() < 0.5 ? '#100c12' : '#241e28', 0.9, 3, 5.5, 0.6);
      arm.root.position.copy(_c).addScaledVector(dir, -back);
      arm.root.quaternion.setFromUnitVectors(NY, dir);
      arm.root.scale.setScalar(Math.min(0.62, 0.15 + t * 1.5) * (t > 1.05 ? Math.max(0.01, 1 - (t - 1.05) / 0.2) : 1));
      if (!hit && t >= 0.84) {
        hit = true;
        const vf = Math.sin(tgt.yaw) * -dir.x + Math.cos(tgt.yaw) * -dir.z;
        if (tgt.blocking && vf > 0.05) G.hit(f, tgt, { dmg: 18, unblockable: true, stun: 0.9, kb: { f: 58, up: 8 }, from: src, hitstop: 0.14, fx: 'heavy', color: '#e8e0f0', shake: 0.7, sfx: 'boom' });
        else G.hit(f, tgt, { dmg: 12, bullet: true, block360: true, bypassRag: true, rag: 1.3, kb: { f: 92, up: 20 }, from: src, hitstop: 0.14, fx: 'heavy', color: '#e8e0f0', shake: 0.7, sfx: 'boom' });
        tgt.chestPos(_a);
        G.fx.debris(_a, 10, ['#111114', '#2b2b2b', '#3a3a40'], 30);
        G.fx.ring(_a, '#ffffff', 1, 8, 0.3, { axis: dir.clone(), a0: 0.9 });
      }
      if (t >= 1.25 || G.matchOver) { arm.busy = false; arm.root.visible = false; return false; }
      return true;
    });
  },
};

// ======================= 1: Severing Path — скольжение 16 стадов с подсечкой, 3 взмаха (4 + 3×2.3); назад — Veilstep =======================
export const ySevering = {
  id: 'severing', label: 'Severing Path', tip: 'DIRECTION', cd: 15, windup: 0.22, color: '#ff7be8', ai: { kind: 'gap', min: 0, max: 14 },
  cast(f) {
    const mx = f.input.mx, mz = f.input.mz, l = Math.hypot(mx, mz);
    if (l > 0.3 && (mx * f.aim.x + mz * f.aim.z) / l < -0.5) return veilstep(f);
    f.drawKatana();
    const tgt = f.autoTarget(18, 0.45);
    if (tgt) f.faceTo(tgt.pos);
    const D = 0.36, v0 = (16 * 1.5) / D;
    f.startAction({
      name: 'severing', dur: D, keepVel: true, windup: 0.22, poseSpeed: 26,
      pose: (ff, a, out) => out.set(SEV_SWEEP),
      update: (ff, dt, t) => {
        if (tgt && !tgt.dead && ff.dist(tgt) > 2) ff.yaw = angleDamp(ff.yaw, Math.atan2(tgt.pos.x - ff.pos.x, tgt.pos.z - ff.pos.z), 8, dt);
        ff.fwd(_b);
        const sp = v0 * Math.sqrt(Math.max(0, 1 - t / D));
        ff.vel.x = _b.x * sp; ff.vel.z = _b.z * sp;
        if (Math.random() < 0.8) { ff.handPos('R', _a); _a.y = ff.pos.y + 0.25; G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-3, 3), rand(2, 5), rand(-3, 3), Math.random() < 0.5 ? '#ff9cf2' : '#ffffff', 1, 0.7, 0.1, 0.25); }
        const v = ff.meleeTargets(3.4, 0.5)[0];
        if (!v) return;
        const r = G.hit(ff, v, { dmg: 4, melee: true, bypassRag: true, stun: 1.2, push: 0, hitstop: 0.07, fx: 'slash', color: '#ff7be8', shake: 0.3, sfx: 'slash' });
        ff.vel.x *= 0.1; ff.vel.z *= 0.1;
        if (hitOk(r)) severingSwings(ff, v);
        else if (r !== 'counter') ff.endlag(r === 'blocked' ? 1.2 : 0.5);
      },
      onEnd: (ff) => ff.endlag(0.5),
    });
    G.sound('dash', f.pos, 0.55);
  },
};
function severingSwings(f, v) {
  const KF = M1ANIM.katana;
  const evs = [0.12, 0.3, 0.5].map((tt, i) => [tt, (ff) => {
    if (v.dead) return;
    const last = i === 2;
    G.hit(ff, v, { dmg: 2.3, melee: true, bypassRag: true, ...(last ? { rag: 1.1, kb: { f: 10, up: 42 } } : { stun: 0.9 }), hitstop: last ? 0.1 : 0.05, fx: 'slash', color: '#ff7be8', shake: last ? 0.45 : 0.18, sfx: last ? 'heavy' : 'slash' });
    kataArc(ff, [0.45, -0.5, Math.PI / 2][i], last ? 6 : 4.8);
  }]);
  f.startAction({
    name: 'severingSw', dur: 0.82, events: evs, poseSpeed: 34,
    frames: [[0, SEV_SWEEP], [0.08, KF[1][1][1]], [0.16, KF[1][2][1]], [0.28, KF[2][1][1]], [0.38, KF[2][2][1]], [0.5, KF[3][1][1]], [0.64, KF[3][2][1]], [1, KT]],
    update: (ff, dt, t) => { if (!v.dead && t < 0.55 && v.stun > 0 && !v.rag) holdFront(ff, v, 3.2, 0, dt, 10); },
  });
}
// Veilstep: перекат назад на 27 стадов с неуязвимостью; всех на пути подбрасывает (9)
function veilstep(f) {
  f.drawKatana();
  let dx = -f.aim.x, dz = -f.aim.z;
  const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
  f.yaw = Math.atan2(-dx, -dz);
  const D = 0.45, v0 = (27 * 1.5) / D;
  const seen = new Set();
  f.startAction({
    name: 'veilstep', dur: D, keepVel: true, iframes: D, windup: 0.1, poseSpeed: 40,
    pose: (ff, a, out) => { out.set(VEIL); out[K.lean] = -ease.smooth(Math.min(1, a.t / D)) * Math.PI * 2; },
    update: (ff, dt, t) => {
      const sp = v0 * Math.sqrt(Math.max(0, 1 - t / D));
      ff.vel.x = dx * sp; ff.vel.z = dz * sp;
      for (const o of G.fighters) {
        if (!ff.isEnemy(o) || seen.has(o) || ff.dist(o) > 3.2 || Math.abs(o.pos.y - ff.pos.y) > 4) continue;
        seen.add(o);
        G.hit(ff, o, { dmg: 9, melee: true, block360: true, bypassRag: true, rag: 1.0, kb: { f: 6, up: 44 }, hitstop: 0.08, fx: 'slash', color: '#ff7be8', shake: 0.4, sfx: 'slash' });
      }
      if (Math.random() < 0.7) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.3, 2.5), ff.pos.z + rand(-1, 1)); G.fx.str.add(_a, _c.set(-dx * 26, 0, -dz * 26), Math.random() < 0.5 ? '#ff9cf2' : '#ffffff', 0.2, 0.09, 2.2, { drag: 6 }); }
    },
    onEnd: (ff) => { ff.pose[K.lean] = wrapAngle(ff.pose[K.lean]); },
    onCancel: (ff) => { ff.pose[K.lean] = wrapAngle(ff.pose[K.lean]); },
  });
  G.sound('dash', f.pos, 0.6);
  return true;
}

// ======================= 2: Resolute Slash — исчезнуть в дыму, появиться у цели (≤25) с разрезом 12; ещё раз — Чёрная вспышка =======================
function vanishFX(f) {
  _a.set(f.pos.x, f.pos.y + 0.8, f.pos.z);
  smokePuff(_a, 22, 2.4, 6);
  G.fx.ring(_a, '#1a1420', 1, 5, 0.35, { axis: 'y', a0: 0.6 });
}
export const yResolute = {
  id: 'resolute', label: 'Resolute Slash', tip: 'USE AGAIN', cd: 15, windup: 0.4, color: '#ff4fd8', ai: { kind: 'gap', min: 4, max: 25 },
  cast(f) {
    const tgt = f.camTarget(25);
    if (!tgt) return false;
    f.drawKatana();
    f.faceTo(tgt.pos);
    vanishFX(f);
    f.vanish = 0.42;
    const start = f.pos.clone();
    f.vel.x = 0; f.vel.z = 0;
    f.startAction({
      name: 'resolute', dur: 0.4, windup: 0.4, iframes: 0.42, frames: [[0, f.idlePose], [0.3, RES_WIND], [1, RES_WIND]],
      onEnd: (ff, a) => resoluteAppear(ff, tgt, start, a),
      onCancel: (ff) => { ff.vanish = 0; },
    });
    G.sound('tp', f.pos, 0.45);
  },
};
function resoluteAppear(f, tgt, start, a) {
  f.vanish = 0;
  if (tgt.dead || f.dist(tgt) > 34) { f.endlag(0.3); return; }
  _d.set(tgt.pos.x - start.x, 0, tgt.pos.z - start.z);
  if (_d.lengthSq() < 0.01) f.fwd(_d);
  _d.normalize();
  const from = new V3(tgt.pos.x - _d.x * 3.4, tgt.pos.y + 3, tgt.pos.z - _d.z * 3.4);
  const to = new V3(tgt.pos.x + _d.x * 3.2, tgt.pos.y, tgt.pos.z + _d.z * 3.2);
  G.world.collide(to, 1.2, 5);
  to.y = Math.max(to.y, groundY(to.x, to.z, to.y + 3));
  f.pos.copy(to); f.vel.set(0, 0, 0);
  f.yaw = Math.atan2(_d.x, _d.z);
  _b.set(to.x + _d.x * 3, to.y + 3, to.z + _d.z * 3);
  G.fx.line(from, _b, '#ff3fd0', 0.4, 0.95);
  G.fx.line(from, _b, '#ffffff', 0.32, 0.32);
  tgt.chestPos(_c);
  _q.setFromUnitVectors(ZV, _d).multiply(_q2.setFromAxisAngle(ZV, 0.3));
  G.fx.crescent(_c, _q, '#ffd9f7', 3, 7, 0.22, { a0: 1 });
  smokePuff(_a.set(to.x, to.y + 1, to.z), 12, 2, 5);
  const r = G.hit(f, tgt, { dmg: 12, melee: true, unblockable: true, stun: 1.15, push: 2, hitstop: 0.12, fx: 'slash', color: '#ff4fd8', shake: 0.5, sfx: 'slash', from: _e.copy(from) });
  f.startAction({
    name: 'resoluteEnd', dur: 0.62, frames: [[0, RES_SLASH], [0.7, RES_SLASH], [1, f.idlePose]],
    onRepress: (ff, a2) => { if (!a2.bf && a2.t < 0.5) { a2.bf = true; resoluteBF(ff, tgt); } },
    update: (ff, dt, t, a2) => {
      if (ff.brain && !a2.bfTry && t > 0.12) { a2.bfTry = true; if (hitOk(r) && Math.random() < ff.brain.skill * 0.7) { a2.bf = true; resoluteBF(ff, tgt); } }
    },
  });
  f.action.slot = a.slot; f.action.cdArr = a.cdArr;
}
function resoluteBF(f, tgt) {
  vanishFX(f);
  f.vanish = 0.3;
  f.iframes = Math.max(f.iframes, 0.36);
  f.startAction({
    name: 'resoluteBF', dur: 0.66, armor: true, frames: [[0, RES_WIND], [0.46, RES_WIND], [0.56, BF_HIT], [1, BF_HIT]],
    update: (ff, dt, t) => { if (t < 0.3) { ff.handPos('R', _a); G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-2, 2), rand(0, 3), rand(-2, 2), '#ff2040', 1, 1, 0.2, 0.25); } },
    events: [
      [0.3, (ff) => {
        ff.vanish = 0;
        if (tgt.dead) return;
        _d.set(ff.pos.x - tgt.pos.x, 0, ff.pos.z - tgt.pos.z);
        if (_d.lengthSq() < 0.01) tgt.fwd(_d);
        _d.normalize();
        ff.pos.set(tgt.pos.x + _d.x * 2.6, tgt.pos.y, tgt.pos.z + _d.z * 2.6);
        G.world.collide(ff.pos, 1.2, 5);
        ff.faceTo(tgt.pos);
        smokePuff(_a.set(ff.pos.x, ff.pos.y + 1, ff.pos.z), 10, 2, 5);
      }],
      [0.37, (ff) => {
        if (tgt.dead || ff.dist(tgt) > 6) return;
        const r = G.hit(ff, tgt, { dmg: 12, melee: true, unblockable: true, bypassRag: true, pierce: true, rag: 1.3, kb: { f: 105, up: 20 }, hitstop: 0.2, fx: 'heavy', color: '#ff2040', shake: 1.0, sfx: 'boom' });
        if (r) bfFX(ff, tgt);
      }],
    ],
  });
}

// ======================= 3: Outburst — держать: 3 ступени заряда; выброс 13×13 стадов, 4 (+2 за ступень); 0.25 с парирования =======================
export const yOutburst = {
  id: 'outburst', label: 'Outburst', tip: 'HOLD', cd: 16, windup: 0.25, color: '#ff6ad5', ai: { kind: 'aoe', min: 0, max: 8 },
  cast(f) {
    const hold = f.bot ? rand(0.15, 1.8) : 99;
    f.counter = 0.25;
    f.charge = { stage: 0, k: 0 };
    G.sound('charge', f.pos, 0.4);
    f.startAction({
      name: 'outburst', dur: 99, windup: 0.25, poseSpeed: 20,
      pose: (ff, a, out) => out.set(a.swung ? OUT_SWING : OUT_HOLD),
      update: (ff, dt, t, a) => {
        if (a.swung) return;
        const c = Math.min(t, 1.65);
        const stage = Math.min(3, Math.floor(c / 0.55));
        if (ff.charge) { ff.charge.stage = stage; ff.charge.k = stage >= 3 ? 1 : (c - stage * 0.55) / 0.55; }
        if (Math.random() < 0.3 + stage * 0.2) {
          const an = rand(0, Math.PI * 2), rr = 1.8 + stage * 0.3;
          _a.set(ff.pos.x + Math.cos(an) * rr, ff.pos.y + rand(0.3, 5), ff.pos.z + Math.sin(an) * rr);
          G.fx.add.spawn(_a.x, _a.y, _a.z, -Math.cos(an) * 3, rand(2, 5), -Math.sin(an) * 3, Math.random() < 0.6 ? '#ff6ad5' : '#ffffff', 0.9, 0.9, 0.15, 0.35);
        }
        if (stage !== (a.st ?? 0)) {
          a.st = stage;
          ff.chestPos(_a); G.fx.ring(_a, '#ff6ad5', 1, 3 + stage * 1.5, 0.25, { a0: 0.85 });
          G.sound('charge', ff.pos, 0.25 + stage * 0.1);
        }
        if ((a.released && t > 0.12) || t >= hold || t >= 2.4) outburstSwing(ff, a, stage);
      },
      onCancel: (ff) => { ff.charge = null; ff.counter = 0; },
      onEnd: (ff) => { ff.charge = null; },
    });
  },
};
function outburstSwing(f, a, stage) {
  a.swung = true; f.charge = null; f.counter = 0;
  f.drawKatana();
  a.dur = a.t + 0.5;
  const R = 6.5 + stage, dmg = 4 + 2 * stage, full = stage >= 3;
  f.chestPos(_c);
  const c = _c.clone();
  for (const o of f.meleeTargets(5.5, 0.3)) G.hit(f, o, { dmg: 2, melee: true, stun: 0.4, hitstop: 0.04, fx: 'slash', color: '#ff7be8', sfx: 'slash' });
  for (const o of f.enemiesNear(c, R, R)) {
    G.hit(f, o, { dmg, bypassRag: true, chip: full ? 0 : 1, chipKill: false, unblockable: full, rag: 1.0, kb: { f: 18 + stage * 6, up: 38 + stage * 4 }, from: f.pos, hitstop: 0.1, fx: 'energy', color: '#ff6ad5', shake: 0.5, sfx: 'boom' });
  }
  G.fx.sphere(c, '#ff6ad5', 1, R, 0.32, { a0: 0.7 });
  G.fx.sphere(c, '#ffffff', 0.5, R * 0.55, 0.2, { a0: 0.8 });
  _a.set(f.pos.x, f.pos.y + 0.2, f.pos.z);
  G.fx.ring(_a, '#ff6ad5', 1, R * 1.4, 0.4, { axis: 'y', a0: 0.9 });
  G.fx.particles(c, { n: 22, color: ['#ff6ad5', '#ffb3ef', '#ffffff'], speed: R * 3, size: 1.4, life: 0.5 });
  G.fx.particles(c, { n: 10, normal: true, color: ['#d040b0', '#ff9ce8'], speed: 8, up: 4, size: 2.4, size1: 5, life: 0.8, alpha: 0.45 });
  kataArc(f, -0.25, 6 + stage);
  G.shake(0.3 + stage * 0.12, f.pos);
  G.sound('boom', f.pos, 0.5 + stage * 0.12);
  if (full) G.flashNear(f.pos, '#ff6ad5', 0.25, 30);
}
// Парирование Outburst (≤0.25 с): ближний бой — отброс и оглушение, неуязвимость, −2 с к перезарядкам Рики
export function outburstParry(f, att, bullet) {
  const a = f.action;
  f.counter = 0;
  if (!a || a.name !== 'outburst' || a.swung) return;
  f.charge = null;
  f.action = null;
  f.iframes = Math.max(f.iframes, 0.6);
  for (let i = 0; i < 4; i++) f.cdRk[i] = Math.max(0, f.cdRk[i] - 2);
  if (a.cdArr && a.slot != null) {
    const c = bullet ? 0 : 4;
    a.cdArr[a.slot] = c;
    if (f.cd === a.cdArr) f.cdMax[a.slot] = Math.max(c, 0.01);
  }
  f.drawKatana();
  f.chestPos(_c);
  G.fx.ring(_c, '#ff9cf2', 1, 7, 0.25, { a0: 1 });
  G.fx.burst(_c, '#ffffff', 9, 0.18);
  G.fx.sparks(_c, null, '#ffd0f4', 12, 40, { spread: 1 });
  G.hud.pop(f.headPos(_a), 'PARRY!', '#ff9cf2', 1.4);
  G.sound('block', f.pos, 0.9);
  if (!bullet && !att.dead) {
    _d.set(att.pos.x - f.pos.x, 0, att.pos.z - f.pos.z);
    if (_d.lengthSq() < 0.01) f.fwd(_d);
    _d.normalize();
    att.interrupt();
    att.stun = Math.max(att.stun, 1.0); att.broken = Math.max(att.broken, 0.8);
    att.vel.x = _d.x * 30; att.vel.z = _d.z * 30;
  }
  f.startAction({ name: 'parry', dur: 0.35, frames: [[0, OUT_HOLD], [0.4, OUT_SWING], [1, OUT_SWING]] });
}

// ======================= 4: Second Wind — рывок 20 стадов (фиолетовое пламя у ног), захват за лицо и удар об пол (2+8) =======================
export const ySecondWind = {
  id: 'secondwind', label: 'Second Wind', tip: 'USE AGAIN', cd: 16, windup: 0.15, color: '#b060ff', ai: { kind: 'gap', min: 2, max: 18 },
  cast(f) {
    const second = G.time < (f.swRetry || 0);
    f.swRetry = 0;
    const tgt = f.autoTarget(22, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    const D = 0.32, v0 = (20 * 1.5) / D;
    f.startAction({
      name: 'secondwind', dur: D, keepVel: true, iframes: D, windup: 0.15, poseSpeed: 26,
      pose: (ff, a, out) => out.set(SW_RUSH),
      update: (ff, dt, t) => {
        if (tgt && !tgt.dead && ff.dist(tgt) > 2) ff.yaw = angleDamp(ff.yaw, Math.atan2(tgt.pos.x - ff.pos.x, tgt.pos.z - ff.pos.z), 8, dt);
        ff.fwd(_b);
        const sp = v0 * Math.sqrt(Math.max(0, 1 - t / D));
        ff.vel.x = _b.x * sp; ff.vel.z = _b.z * sp;
        // тёмно-фиолетовое пламя с розово-белыми искрами у ног
        for (let i = 0; i < 2; i++) G.fx.norm.spawn(ff.pos.x + rand(-0.9, 0.9), ff.pos.y + rand(0, 0.8), ff.pos.z + rand(-0.9, 0.9), -_b.x * 6, rand(3, 6), -_b.z * 6, Math.random() < 0.5 ? '#3a0a5a' : '#5a1880', 0.8, 1.3, 0.4, 0.4);
        if (Math.random() < 0.6) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0, 1.2), ff.pos.z + rand(-1, 1)); G.fx.bolt(_a, _c.set(_a.x + rand(-1, 1), _a.y + rand(0.3, 1.2), _a.z + rand(-1, 1)), Math.random() < 0.5 ? '#ffb0f0' : '#ffffff', { segs: 2, jag: 0.3, life: 0.08, w: 0.07 }); }
        const v = ff.meleeTargets(3.4, 0.5)[0];
        if (!v) return;
        const r = G.hit(ff, v, { dmg: 2, melee: true, block360: true, stun: 1.6, push: 0, hitstop: 0.08, fx: 'hit', color: '#c070ff', shake: 0.3, sfx: 'hit' });
        ff.vel.x *= 0.1; ff.vel.z *= 0.1;
        if (hitOk(r)) secondWindSlam(ff, v, second);
        else if (r === 'blocked') ff.endlag(1.2);
        else if (r !== 'counter') ff.endlag(0.4);
      },
      onEnd: (ff, a) => {
        // промах первой попытки: перезарядки нет, можно повторить (подсказка USE AGAIN)
        if (!second && a.cdArr && a.slot != null) { a.cdArr[a.slot] = 0; ff.swRetry = G.time + 5; ff.endlag(0.35); }
        else ff.endlag(1.2);
      },
    });
    G.sound('dash', f.pos, 0.6);
  },
};
function secondWindSlam(f, v, second) {
  f.startAction({
    name: 'secondwindSlam', dur: 0.95, armor: true, poseSpeed: 26,
    frames: [[0, SW_GRAB], [0.3, SW_LIFT], [0.48, SW_SLAM], [1, SW_SLAM]],
    update: (ff, dt, t) => {
      if (v.dead || t > 0.47) return;
      const k = t < 0.28 ? t / 0.28 : Math.max(0, 1 - (t - 0.28) / 0.18);
      holdFront(ff, v, 2.8, Math.sin(k * Math.PI / 2) * 2.6, dt, 18);
      v.stun = Math.max(v.stun, 0.5);
    },
    events: [[0.46, (ff) => {
      if (v.dead) return;
      ff.fwd(_b);
      const gx = ff.pos.x + _b.x * 2.8, gz = ff.pos.z + _b.z * 2.8, gy = groundY(gx, gz, ff.pos.y + 2);
      v.pos.set(gx, gy, gz);
      G.hit(ff, v, { dmg: 8, melee: true, unblockable: true, bypassRag: true, downslam: true, ignoreIframes: true, rag: 1.2, kb: { f: 4, up: -30 }, hitstop: 0.12, fx: 'heavy', color: '#c070ff', shake: 0.6, sfx: 'boom' });
      _a.set(gx, gy + 0.2, gz);
      craterAt(_a, 7);
      G.fx.ring(_a, '#b060ff', 1, 9, 0.35, { axis: 'y', a0: 0.9 });
      if (second) { G.fx.burst(_a.set(gx, gy + 2, gz), '#ffd0f6', 18, 0.3); G.fx.ring(_a, '#ffffff', 1, 12, 0.35, { a0: 1 }); }
    }]],
  });
}

// ======================= True Love: Рика-гигант у правого плеча =======================
// Бледно-серо-белая полупрозрачная (≈2.5 роста владельца), плечо справа (+3) и чуть позади (−1.5).
// Приёмы пробуждения задают ей «действие» R.act(R, dt) → true, пока управляют ею.
export function yutaRika(f) {
  if (f.rika) return;
  const R = getRika();
  f.rika = R;
  R.act = null; R.sinkT = 0;
  R.mat.opacity = 0.5;
  R.root.scale.setScalar(0.01);
  R.root.position.copy(f.pos); R.root.rotation.y = f.yaw;
  R.armL.rotation.set(0, 0, 0); R.armR.rotation.set(0, 0, 0);
  f.chestPos(_a);
  smokePuff(_a, 30, 3, 14);
  G.callout(f, 'Rika: Full Manifestation', '#F76BFF', true);
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    const alive = !f.dead && f.awakened > 0 && !G.matchOver && f.rika === R;
    let s = 1.15 * ease.out3(Math.min(1, t / 0.7));
    if (!alive) { R.sinkT += dt; s *= Math.max(0, 1 - R.sinkT / 0.6); }
    if (!(alive && R.act)) R.root.scale.setScalar(Math.max(0.01, s));
    if (!alive && R.act) { R.act.cancel?.(); R.act = null; }
    if (alive && R.act) { if (!R.act(R, dt)) R.act = null; }
    else {
      f.fwd(_b); rightOf(f, _c);
      _a.copy(f.pos).addScaledVector(_b, -1.5).addScaledVector(_c, 3);
      _a.y = f.pos.y + 0.9 + Math.sin(t * 2) * 0.35;
      R.root.position.lerp(_a, 1 - Math.exp(-8 * dt));
      R.root.rotation.y = angleDamp(R.root.rotation.y, f.yaw, 6, dt);
      const k = Math.min(1, dt * 6);
      R.armR.rotation.x += (-0.45 + Math.sin(t * 2.2) * 0.15 - R.armR.rotation.x) * k;
      R.armL.rotation.x += (-0.45 - Math.sin(t * 2.2) * 0.15 - R.armL.rotation.x) * k;
      R.armR.rotation.z *= 1 - k; R.armL.rotation.z *= 1 - k;
    }
    if (alive) occlusionFade(R, 0.5, dt); else R.mat.opacity = 0.5 * Math.max(0, 1 - R.sinkT / 0.6);
    if (Math.random() < 0.3) { R.root.getWorldPosition(_a); G.fx.norm.spawn(_a.x + rand(-3, 3), _a.y + rand(0, 4), _a.z + rand(-3, 3), 0, rand(1, 3), 0, '#1a1020', 0.45, 1.5, 3, 0.8); }
    if (!alive && R.sinkT > 0.6) {
      if (f.rika === R) f.rika = null;
      R.act = null; R.busy = false; R.root.visible = false;
      return false;
    }
    return true;
  });
}
// Приём берёт Рику под управление; прежний приём (если был) завершается через cancel
function setAct(R, fn, cancel = null) {
  if (R.act && R.act.cancel) R.act.cancel();
  fn.cancel = cancel;
  R.act = fn;
}
// Рика ведёт себя как «тело» приёма: летит к точке, смотрит в направлении
function rikaGoto(R, p, yaw, dt, k = 10) {
  R.root.position.lerp(p, 1 - Math.exp(-k * dt));
  R.root.rotation.y = angleDamp(R.root.rotation.y, yaw, 10, dt);
}
// R (True Love): Rika Downslam — молот обеими руками сверху по цели (8 + 4), цель сплющивается
export const yTLDownslam = {
  id: 'rkDown', label: 'Rika Downslam', tip: 'TARGET', cd: 13, color: '#e8e0f0', ai: { kind: 'gap', min: 0, max: 26 },
  cast(f) {
    const tgt = f.camTarget(28);
    if (!tgt) return false;
    if (!f.rika) yutaRika(f);
    rikaCmd(f);
    const p = tgt.pos.clone();
    let t = 0, hits = 0;
    G.sound('charge', tgt.pos, 0.5);
    setAct(f.rika, (R, dt) => {
      t += dt;
      if (!tgt.dead && t < 0.5) p.copy(tgt.pos);
      _d.set(p.x - f.pos.x, 0, p.z - f.pos.z);
      if (_d.lengthSq() < 0.01) f.fwd(_d);
      _d.normalize();
      // сбоку от цели (справа от линии Юта → цель), чтобы не заслонять обзор
      _a.set(p.x - _d.z * 4.6 - _d.x * 1.2, p.y + 0.5, p.z + _d.x * 4.6 - _d.z * 1.2);
      rikaGoto(R, _a, Math.atan2(p.x - _a.x, p.z - _a.z), dt, 9);
      const up = t < 0.45 ? ease.out(t / 0.45) : Math.max(0, 1 - (t - 0.45) / 0.1);
      R.armL.rotation.x = R.armR.rotation.x = -0.9 - 2.1 * up;
      R.armL.rotation.z = 0.25 * up; R.armR.rotation.z = -0.25 * up;
      if (hits === 0 && t >= 0.55) {
        hits = 1;
        const gy = groundY(p.x, p.z, p.y + 2);
        _c.set(p.x, gy + 0.3, p.z);
        if (!tgt.dead && Math.hypot(tgt.pos.x - p.x, tgt.pos.z - p.z) < 7) {
          G.hit(f, tgt, { dmg: 8, bypassRag: true, block360: true, stun: 0.9, hitstop: 0.12, fx: 'heavy', color: '#e8e0f0', shake: 0.7, sfx: 'boom', from: R.root.position });
          squash(tgt);
        }
        craterAt(_c, 10); G.fx.ring(_c, '#ffffff', 1, 13, 0.35, { axis: 'y', a0: 0.9 });
        G.shake(0.5, p);
      }
      if (hits === 1 && t >= 0.8) {
        hits = 2;
        if (!tgt.dead && Math.hypot(tgt.pos.x - p.x, tgt.pos.z - p.z) < 8) G.hit(f, tgt, { dmg: 4, bypassRag: true, rag: 1.2, kb: { f: 10, up: 30 }, hitstop: 0.06, fx: 'heavy', color: '#e8e0f0', shake: 0.3, sfx: 'heavy', from: R.root.position });
      }
      return t < 1.15;
    });
  },
};
function squash(v) {
  let t = 0;
  const root = v.model.root;
  G.addTask((dt) => {
    t += dt;
    const base = root.scale.x;
    if (t >= 0.45 || v.dead) { root.scale.y = base; return false; }
    root.scale.y = base * (0.35 + 0.65 * ease.out(t / 0.45));
    return true;
  });
}
// 1: Elbow Rush — рывок 38.5 стадов локтем; цель кружится, Юта появляется за ней, Рика — спереди, шквал вдвоём, финал
export const yElbowRush = {
  id: 'elbow', label: 'Elbow Rush', cd: 15, windup: 0.15, color: '#ff9cf2', ai: { kind: 'gap', min: 3, max: 36 },
  cast(f) {
    const tgt = f.autoTarget(40, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    const D = 0.42, v0 = (38.5 * 1.5) / D;
    f.startAction({
      name: 'elbow', dur: D, keepVel: true, windup: 0.15, poseSpeed: 28,
      pose: (ff, a, out) => out.set(ELBOW),
      update: (ff, dt, t) => {
        if (tgt && !tgt.dead && ff.dist(tgt) > 2) ff.yaw = angleDamp(ff.yaw, Math.atan2(tgt.pos.x - ff.pos.x, tgt.pos.z - ff.pos.z), 9, dt);
        ff.fwd(_b);
        const sp = v0 * Math.sqrt(Math.max(0, 1 - t / D));
        ff.vel.x = _b.x * sp; ff.vel.z = _b.z * sp;
        if (Math.random() < 0.9) { ff.handPos('R', _a); G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-2, 2), rand(0, 2), rand(-2, 2), Math.random() < 0.5 ? '#ff7bf0' : '#ffffff', 1, 0.9, 0.1, 0.22); }
        if (Math.random() < 0.7) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.5, 4.5), ff.pos.z + rand(-1, 1)); G.fx.str.add(_a, _c.set(-_b.x * 34, 0, -_b.z * 34), '#ffffff', 0.18, 0.08, 2.6, { drag: 8 }); }
        const v = ff.meleeTargets(3.6, 0.5)[0];
        if (!v) return;
        const r = G.hit(ff, v, { dmg: 4, melee: true, unblockable: true, stun: 2.6, push: 0, hitstop: 0.1, fx: 'heavy', color: '#ff9cf2', shake: 0.45, sfx: 'heavy' });
        ff.vel.x *= 0.1; ff.vel.z *= 0.1;
        if (hitOk(r)) elbowBarrage(ff, v);
        else if (r !== 'counter') ff.endlag(0.6);
      },
      onEnd: (ff) => ff.endlag(1.0),
    });
    G.sound('dash', f.pos, 0.75);
  },
};
function elbowBarrage(f, v) {
  f.fwd(_b);
  const bx = _b.x, bz = _b.z;
  _a.set(f.pos.x, f.pos.y + 1, f.pos.z); smokePuff(_a, 12, 2, 5);
  f.pos.set(v.pos.x + bx * 2.8, v.pos.y, v.pos.z + bz * 2.8);
  G.world.collide(f.pos, 1.2, 5);
  f.faceTo(v.pos);
  smokePuff(_a.set(f.pos.x, f.pos.y + 1, f.pos.z), 12, 2, 5);
  const R = f.rika;
  if (R) {
    let t = 0;
    setAct(R, (R2, dt) => {
      t += dt;
      // с той стороны цели, что дальше от камеры: цель зажата между Ютой и Рикой и видна
      const cam = G.camera.position;
      _d.set(v.pos.x - cam.x, 0, v.pos.z - cam.z);
      if (_d.lengthSq() < 0.01) f.fwd(_d);
      _d.normalize();
      _a.set(v.pos.x + _d.x * 5.5, v.pos.y - 3.2, v.pos.z + _d.z * 5.5);
      rikaGoto(R2, _a, Math.atan2(-_d.x, -_d.z), dt, 14);
      if (t < 0.95) { R2.armR.rotation.x = -1.5 + Math.sin(t * 34) * 0.55; R2.armL.rotation.x = -1.5 - Math.sin(t * 34) * 0.55; }
      else { R2.armR.rotation.x = -2.6; R2.armL.rotation.x = -0.6; }
      return t < 1.25 && !v.dead;
    });
  }
  const evs = [];
  for (let i = 0; i < 5; i++) {
    evs.push([0.12 + i * 0.14, (ff) => {
      if (v.dead) return;
      G.hit(ff, v, { dmg: 1, melee: true, ignoreIframes: true, stun: 0.9, hitstop: 0.025, fx: 'hit', shake: 0.1, sfx: 'hit', vol: 0.45 });
      v.chestPos(_c);
      for (let j = 0; j < 2; j++) G.fx.burst(_a.set(_c.x + rand(-1.2, 1.2), _c.y + rand(-1, 1.2), _c.z + rand(-1.2, 1.2)), j ? '#ffffff' : '#ffd0f4', 3, 0.1);
      if (i % 2) hexSpark(_c);
    }]);
  }
  evs.push([0.98, (ff) => {
    if (v.dead) return;
    G.hit(ff, v, { dmg: 6, melee: true, unblockable: true, ignoreIframes: true, rag: 1.3, kb: { f: 72, up: 30 }, hitstop: 0.13, fx: 'heavy', color: '#ff9cf2', shake: 0.7, sfx: 'boom' });
    v.chestPos(_c);
    G.fx.particles(_c, { n: 26, normal: true, color: ['#ffffff', '#f2f2f2', '#dcdcdc'], speed: 16, up: 4, size: 3, size1: 7, life: 0.9, alpha: 0.85, drag: 3 });
    G.fx.burst(_c, '#ffffff', 16, 0.25);
  }]);
  f.startAction({
    name: 'elbowBarrage', dur: 1.3, armor: true, events: evs, poseSpeed: 40,
    pose: (ff, a, out) => out.set(a.t > 0.92 ? PX(FS, { rax: -2.8, raz: 0.1, twist: 0.5, cx: -0.2, hy: 0.1 }) : Math.floor(a.t / 0.07) % 2 ? PL : PR),
    update: (ff, dt, t) => {
      if (v.dead || t >= 0.98) return;
      v.stun = Math.max(v.stun, 0.5); v.vel.set(0, 0, 0); v.suspend = 0.1; v.blocking = false;
      v.yaw += dt * (t < 0.3 ? 16 : 3);
      ff.faceTo(v.pos);
    },
  });
}
// 2: Копия — Cursed Speech «Не двигайся!»: оглушение 2.5 с всем в 35 стадах
export const yCopySpeech = {
  id: 'copy', label: 'Copy: Speech', tip: 'COPY', cd: 15, windup: 0.22, color: '#c77dff', ai: { kind: 'aoe', min: 0, max: 30 },
  cast(f) {
    f.startAction({
      name: 'speech', dur: 0.65, frames: [[0, f.idlePose], [0.25, SPEECH], [0.8, SPEECH], [1, f.idlePose]],
      events: [[0.22, (ff) => {
        ff.headPos(_a);
        G.hud.pop(_a.set(_a.x, _a.y + 1, _a.z), 'НЕ ДВИГАЙСЯ!', '#d9a0ff', 2);
        ff.chestPos(_c);
        for (let i = 0; i < 3; i++) {
          G.fx.ring(_c, '#c77dff', 1, 35, 0.55, { axis: 'y', delay: i * 0.08, a0: 0.9 });
          G.fx.ring(_c, '#ffffff', 1, 14, 0.35, { delay: i * 0.1, a0: 0.6 });
        }
        G.fx.particles(_c, { n: 20, color: ['#c77dff', '#ffffff'], speed: 18, size: 1, life: 0.5 });
        for (const o of ff.enemiesNear(_c, 35, 12)) {
          G.hit(ff, o, { dmg: 2, stun: 2.5, pierce: true, noCounter: true, unblockable: true, hitstop: 0.05, fx: 'energy', color: '#c77dff', shake: 0.3, sfx: 'hit' });
          if (!o.dead && !o.rag && o.prot <= 0 && o.iframes <= 0) { o.stun = Math.max(o.stun, 2.5); o.broken = Math.max(o.broken, 2.5); o.interrupt(true); }
        }
        G.sound('tp', ff.pos, 0.8); G.sound('heavy', ff.pos, 0.5);
        G.shake(0.3, ff.pos);
      }]],
    });
  },
};
// 3: Energy Ripple — удар катаной в землю, белая вспышка и расходящееся пурпурное кольцо (19, отброс на 27 стадов)
export const yEnergyRipple = {
  id: 'ripple', label: 'Energy Ripple', cd: 18, windup: 0.52, color: '#ff6ad5', ai: { kind: 'aoe', min: 0, max: 22 },
  cast(f) {
    f.drawKatana();
    G.sound('charge', f.pos, 0.55);
    f.startAction({
      name: 'ripple', dur: 1.05, armor: true,
      frames: [[0, f.idlePose], [0.3, STAB_UP], [0.45, STAB_UP], [0.52, STAB_DN], [1, STAB_DN]],
      update: (ff, dt, t) => { if (t < 0.52) { ff.handPos('R', _a); G.fx.add.spawn(_a.x + rand(-0.5, 0.5), _a.y + rand(-1.5, 0.5), _a.z + rand(-0.5, 0.5), 0, rand(1, 3), 0, Math.random() < 0.5 ? '#ff6ad5' : '#ffffff', 1, 0.9, 0.1, 0.3); } },
      events: [[0.52, (ff) => {
        const gy = groundY(ff.pos.x, ff.pos.z, ff.pos.y + 1);
        const c = new V3(ff.pos.x, gy + 0.25, ff.pos.z);
        G.flashNear(c, '#ffffff', 0.8, 45);
        for (let i = 0; i < 3; i++) G.fx.ring(c, i === 1 ? '#ffffff' : '#ff3fc8', 1 + i, 27 + i * 1.2, 0.5 + i * 0.06, { axis: 'y', a0: 0.95, delay: i * 0.03 });
        G.fx.ring(_a.set(c.x, c.y + 2.5, c.z), '#ff6ad5', 1, 22, 0.45, { axis: 'y', a0: 0.6 });
        G.fx.sphere(_a.set(c.x, c.y + 1, c.z), '#ff6ad5', 1, 9, 0.3, { a0: 0.6 });
        craterAt(c, 9, ['#2b2b2b', '#3a3a40', '#ffb3ef']);
        G.fx.dust(c, 16, 4);
        _a.set(c.x, c.y + 2, c.z);
        for (const o of ff.enemiesNear(_a, 27, 10)) G.hit(ff, o, { dmg: 19, unblockable: true, bypassRag: true, noCounter: true, rag: 1.2, kb: { f: 75, up: 24 }, from: c, hitstop: 0.1, fx: 'energy', color: '#ff6ad5', shake: 0.6, sfx: 'boom' });
        G.shake(0.7, ff.pos); G.sound('boom', ff.pos, 1);
      }]],
    });
  },
};
// 4: True Love Beam — Рика собирает розовые молнии (1.2 с), растёт и бьёт огромным пурпурным лучом (тики, меньше при толпе и вдали)
export const yTLBeam = {
  id: 'tlbeam', label: 'True Love Beam', cd: 40, windup: 1.2, color: '#ff6ad5', ai: { kind: 'ranged', min: 5, max: 60 },
  cast(f) {
    if (!f.rika) yutaRika(f);
    const R = f.rika;
    let tgt = f.camTarget(80);
    if (tgt) f.faceTo(tgt.pos);
    G.callout(f, 'True Love Beam', '#ff6ad5', true);
    G.sound('charge', f.pos, 0.8);
    const mouth = new V3(), dir = new V3();
    const glow = G.fx.pool('glow'); glow.mat.color.set('#ff8ae0');
    let t = 0, fired = false, tick = 0;
    const LEN = 80, RAD = 4.5, FIRE = 1.2, END = 3.4;
    const yaw0 = f.yaw;
    setAct(R, (R2, dt) => {
      t += dt;
      if (tgt && tgt.dead) tgt = null;
      if (!fired && (!f.action || f.action.name !== 'love')) { G.fx.release(glow); return false; }
      f.fwd(_b); rightOf(f, _c);
      // Рика поднимается за правым плечом и растёт
      const g = ease.out3(Math.min(1, t / 0.6));
      _a.copy(f.pos).addScaledVector(_b, -2.5).addScaledVector(_c, 2.4); _a.y = f.pos.y + 2.5 * g;
      const yawB = fired ? Math.atan2(dir.x, dir.z) : tgt ? Math.atan2(tgt.pos.x - R2.root.position.x, tgt.pos.z - R2.root.position.z) : f.yaw;
      rikaGoto(R2, _a, yawB, dt, 8);
      R2.root.scale.setScalar(1.15 + 0.3 * g);
      R2.armL.rotation.x = R2.armR.rotation.x = -1.1;
      const k = R2.root.scale.x;
      mouth.set(0, 9.3 * k, 3.8 * k).applyAxisAngle(YV, R2.root.rotation.y).add(R2.root.position);
      if (!fired) {
        const c = Math.min(1, t / FIRE);
        glow.obj.position.copy(mouth); glow.obj.scale.setScalar(2 + c * 9);
        for (let i = 0; i < 2; i++) {
          _d.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
          _e.copy(mouth).addScaledVector(_d, rand(3, 6));
          G.fx.bolt(_e, mouth, Math.random() < 0.5 ? '#ff6ad5' : '#ffffff', { segs: 3, jag: 0.5, life: 0.08, w: 0.1 });
        }
        if (t >= FIRE) {
          fired = true;
          G.fx.release(glow);
          if (tgt) tgt.chestPos(dir).sub(mouth);
          else if (f.isPlayer && G.camRay) { dir.copy(G.camRay.dir); }
          else { f.fwd(dir); dir.y = -0.12; }
          if (dir.y > 0.3) dir.y = 0.3;
          dir.normalize();
          beamFX(mouth.clone(), dir, LEN, RAD, '#ff3fc8', '#ffffff', END - FIRE);
          G.fx.burst(mouth, '#ffb0ee', 18, 0.25);
          G.fx.ring(mouth, '#ff6ad5', 1, 12, 0.35, { axis: dir.clone() });
          G.sound('beam', f.pos, 1); G.shake(0.6, f.pos);
          G.flashNear(f.pos, '#ff6ad5', 0.35, 60);
          for (let d = 6; d < LEN; d += 9) { _a.copy(mouth).addScaledVector(dir, d); if (_a.y < 6) { _a.y = 0.4; G.fx.debris(_a, 2, ['#5a4a6a', '#2b2b2b'], 16); G.fx.dust(_a, 2, 3); } }
        }
      } else {
        tick -= dt;
        if (tick <= 0 && t < END) {
          tick = 0.2;
          const hits = beamHits(f, mouth, dir, LEN, RAD);
          const n = hits.length;
          for (const o of hits) {
            o.chestPos(_a);
            const dk = 1 - 0.4 * clamp(_a.distanceTo(mouth) / LEN, 0, 1);
            const last = t + 0.2 >= END;
            G.hit(f, o, { dmg: (3.8 * dk) / Math.sqrt(n), chip: 0.5, pierce: true, bypassRag: true, ...(last ? { rag: 1.4, kb: { f: 70, up: 22 } } : { stun: 0.35, push: 6 }), hitstop: 0.02, fx: 'energy', color: '#ff6ad5', shake: 0.25, sfx: 'hit', vol: 0.4, from: mouth });
          }
        }
      }
      return t < END + 0.4;
    }, () => { if (!fired) G.fx.release(glow); });
    f.startAction({
      name: 'love', dur: END + 0.2, armor: true, windup: 1.2,
      frames: [[0, KT], [0.08, BEAM_POSE], [1, BEAM_POSE]],
      update: (ff) => { if (!fired) { if (tgt) ff.faceTo(tgt.pos); else if (ff.isPlayer) ff.yaw = Math.atan2(ff.aim.x, ff.aim.z); else ff.yaw = yaw0; } },
    });
  },
};

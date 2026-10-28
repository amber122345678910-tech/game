// Персонажи и их навыки. Каждый навык: { id, label, cd, color, ai:{kind,min,max}, cast(f) }.
import * as THREE from 'three';
import { G } from './ctx.js';
import { P, PX, POSE, M1ANIM } from './anim.js';
import { buildRika, buildRikaArm, buildShrine } from './rig.js';
import { rand, clamp, tex, ease } from './util.js';

const V3 = THREE.Vector3;
const _a = new V3(), _b = new V3(), _c = new V3(), _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();
const ZV = new V3(0, 0, 1), YV = new V3(0, 1, 0);

// ---------- общие помощники ----------
function aimFrom(f, origin, tgt, out, flat = false) {
  if (tgt) { tgt.chestPos(out).sub(origin); if (flat) out.y = 0; }
  else { f.fwd(out); }
  if (out.lengthSq() < 1e-4) f.fwd(out);
  return out.normalize();
}

// Снаряд: o = {owner, pos, dir, speed, range, radius, pierce, onHit(f,p), onWorld(p), onStep(p,dt,t), onEnd(p)}
function projectile(o) {
  const p = o.pos.clone(), d = o.dir.clone().normalize();
  const hitSet = new Set();
  let trav = 0, t = 0, done = false;
  const finish = () => { if (!done) { done = true; o.onEnd?.(p); } return false; };
  G.addTask((dt) => {
    if (G.matchOver) return finish();
    t += dt;
    const step = o.speed * dt;
    const n = Math.max(1, Math.ceil(step / 1.4));
    for (let s = 0; s < n; s++) {
      p.addScaledVector(d, step / n); trav += step / n;
      for (const f of G.fighters) {
        if (!o.owner.isEnemy(f) || hitSet.has(f)) continue;
        const dx = f.pos.x - p.x, dz = f.pos.z - p.z, R = o.radius + 1.2;
        if (dx * dx + dz * dz > R * R || p.y < f.pos.y - o.radius || p.y > f.pos.y + 5.4 + o.radius) continue;
        hitSet.add(f);
        o.onHit(f, p);
        if (!o.pierce) return finish();
      }
      if (G.world.pointBlocked(p)) { o.onWorld?.(p); return finish(); }
      if (trav >= o.range) return finish();
    }
    o.onStep?.(p, dt, t, d);
    return true;
  });
}

function beamHits(owner, origin, dir, len, radius) {
  const out = [];
  for (const f of G.fighters) {
    if (!owner.isEnemy(f)) continue;
    f.chestPos(_c).sub(origin);
    const t = _c.dot(dir);
    if (t < -2 || t > len) continue;
    if (_c.lengthSq() - t * t <= (radius + 1.5) * (radius + 1.5)) out.push(f);
  }
  return out;
}

function beamFX(origin, dir, len, radius, outer, core, life) {
  const A = G.fx.pool('beam'), B = G.fx.pool('beam');
  A.mat.color.set(outer); B.mat.color.set(core);
  _q.setFromUnitVectors(YV, dir);
  const mid = origin.clone().addScaledVector(dir, len / 2);
  for (const it of [A, B]) { it.obj.position.copy(mid); it.obj.quaternion.copy(_q); it.mat.map.repeat.set(2, len / 14); it.mat.opacity = 1; }
  let t = 0;
  G.addTask((dt) => {
    t += dt;
    const k = t / life;
    const g = k < 0.12 ? ease.out(k / 0.12) : k > 0.7 ? Math.max(0, (1 - k) / 0.3) : 1;
    const wob = 1 + Math.sin(t * 70) * 0.06;
    A.obj.scale.set(radius * g * wob, len, radius * g * wob);
    B.obj.scale.set(radius * 0.42 * g, len, radius * 0.42 * g);
    A.mat.map.offset.y -= dt * 5; B.mat.map.offset.y -= dt * 9;
    if (k >= 1) { G.fx.release(A); G.fx.release(B); return false; }
    return true;
  });
}

function explosion(owner, p, R, color, o) {
  for (const f of owner.enemiesNear(p, R, R + 2)) {
    G.hit(owner, f, { from: p, ...o });
  }
  G.fx.burst(p, '#ffffff', R * 1.6, 0.2);
  G.fx.sphere(p, color, 1, R, 0.35, { a0: 0.8 });
  G.fx.ring(p, color, 1, R * 1.8, 0.4, { axis: 'y', a0: 0.9 });
  G.fx.ring(p, '#ffffff', 1, R * 1.4, 0.3, { a0: 0.7 });
  G.fx.sparks(p, null, color, 16, 55, { spread: 1 });
  G.fx.particles(p, { n: 22, color: [color, '#ffffff'], speed: R * 3.2, size: 1.4, life: 0.5 });
  G.fx.particles(p, { n: 10, normal: true, color: '#3a3a40', speed: 7, up: 5, size: 2.2, size1: 5, life: 1.1, alpha: 0.5 });
  const gy = G.world.groundAt(p.x, p.z, p.y);
  if (p.y - gy < 5) { _a.set(p.x, gy + 0.3, p.z); G.fx.debris(_a, 10); G.fx.dust(_a, 10, 3.5); G.fx.crater(_a, R * 0.9, 5); }
  G.shake(0.6, p);
  G.sound('boom', p, 0.8);
  G.flashNear(p, color, 0.25, 30);
}

function lungeTo(f, tgt, maxD, stop = 3) {
  if (!tgt) return 0;
  const d = f.dist(tgt);
  return d < maxD ? Math.max(0, d - stop) : 0;
}

// Аура пробуждения
function aura(colors, dark) {
  return (f, dt) => {
    if (Math.random() < dt * 22) {
      _a.set(f.pos.x + rand(-1.3, 1.3), f.pos.y + rand(0.3, 5), f.pos.z + rand(-1.3, 1.3));
      G.fx.particles(_a, { n: 1, color: colors, speed: 1, up: 6, size: 1.1, size1: 0.2, life: 0.6, normal: !!dark });
    }
  };
}

// ======================= GOJO =======================
const P_POINT = PX(POSE.idle.gojo, { rax: -1.6, raz: 0.05, twist: 0.35, cx: 0.05, hx: -0.05 });
const P_POINT2 = PX(POSE.idle.gojo, { rax: -1.75, raz: 0.1, twist: 0.5, cx: 0.12, hy: -0.15 });

const gBlue = {
  id: 'blue', label: 'Blue', cd: 9, color: '#3f8cff', ai: { kind: 'ranged', min: 3, max: 24 },
  cast(f) {
    const tgt = f.autoTarget(28, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const center = new V3();
    if (tgt) tgt.chestPos(center); else { f.chestPos(center); f.fwd(_a); center.addScaledVector(_a, 11); }
    f.startAction({
      name: 'blue', dur: 0.55, frames: [[0, POSE.idle.gojo], [0.25, P_POINT], [1, P_POINT]],
      events: [[0.16, () => spawnBlue(f, center, tgt)]],
    });
    G.sound('charge', f.pos, 0.4);
  },
};
function spawnBlue(f, center, tgt) {
  const core = G.fx.pool('sphere'), glow = G.fx.pool('glow'), r1 = G.fx.pool('ring'), r2 = G.fx.pool('ring');
  core.mat.color.set('#2d6dff'); glow.mat.color.set('#5fb8ff'); r1.mat.color.set('#8fd0ff'); r2.mat.color.set('#3f8cff');
  let t = 0, tick = 0;
  const L = 1.5;
  G.addTask((dt) => {
    t += dt; tick -= dt;
    if (tgt && !tgt.dead) { tgt.chestPos(_a); _a.sub(center); const d = _a.length(); if (d > 0.5) center.addScaledVector(_a, Math.min(1, (7 * dt) / d)); }
    const grow = Math.min(1, t / 0.2);
    const pulse = 1 + Math.sin(t * 30) * 0.08;
    core.obj.position.copy(center); core.obj.scale.setScalar(1.5 * grow * pulse); core.mat.opacity = 0.9;
    glow.obj.position.copy(center); glow.obj.scale.setScalar(11 * grow); glow.mat.opacity = 0.8;
    r1.obj.position.copy(center); r1.obj.scale.setScalar(3.6 * grow); r1.obj.rotation.set(t * 4, t * 3, 0); r1.mat.opacity = 0.7;
    r2.obj.position.copy(center); r2.obj.scale.setScalar(4.6 * grow); r2.obj.rotation.set(-t * 3, 0, t * 5); r2.mat.opacity = 0.5;
    for (let i = 0; i < 3; i++) {
      _a.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
      _b.copy(center).addScaledVector(_a, rand(6, 9));
      _a.multiplyScalar(-rand(18, 26));
      G.fx.add.spawn(_b.x, _b.y, _b.z, _a.x, _a.y, _a.z, i ? '#7cc8ff' : '#ffffff', 1, 0.7, 0.1, 0.35, 0, 0);
    }
    // притяжение
    for (const o of f.enemiesNear(center, 14, 12)) {
      o.chestPos(_a); _b.subVectors(center, _a); const d = _b.length();
      if (d > 0.8) {
        _b.multiplyScalar(1 / d);
        const k = (o.rag ? 30 : 75) * dt;
        o.vel.x += _b.x * k; o.vel.z += _b.z * k; o.vel.y += _b.y * k * 0.5;
        if (d < 3) { o.vel.x *= 0.85; o.vel.z *= 0.85; }
      }
      if (d < 7 && !o.rag) { o.stun = Math.max(o.stun, 0.3); o.interrupt(); }
    }
    if (tick <= 0) {
      tick = 0.25;
      for (const o of f.enemiesNear(center, 5.5, 6)) G.hit(f, o, { dmg: 1.1, stun: 0.4, hitstop: 0.02, fx: 'energy', color: '#5fb8ff', shake: 0.08, sfx: 'hit', vol: 0.35, from: center, guardDmg: 10 });
    }
    if (t >= L) {
      G.fx.release(core); G.fx.release(glow); G.fx.release(r1); G.fx.release(r2);
      explosion(f, center, 6, '#3f8cff', { dmg: 6, rag: 0.7, kb: { f: 22, up: 20 }, fx: 'energy', color: '#5fb8ff', hitstop: 0.07, shake: 0.4, sfx: 'heavy', guardDmg: 40 });
      return false;
    }
    return true;
  });
}

const gRed = {
  id: 'red', label: 'Red', cd: 11, color: '#ff3b3b', ai: { kind: 'ranged', min: 4, max: 40 },
  cast(f) {
    const tgt = f.autoTarget(45, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    const orb = G.fx.pool('glow'), core = G.fx.pool('sphere');
    orb.mat.color.set('#ff3030'); core.mat.color.set('#ff5040');
    const cleanup = () => { G.fx.release(orb); G.fx.release(core); };
    f.startAction({
      name: 'red', dur: 0.78, frames: [[0, POSE.idle.gojo], [0.3, P_POINT2], [0.62, P_POINT2], [0.72, PX(P_POINT2, { cx: -0.1, rax: -1.9 })], [1, POSE.idle.gojo]],
      update: (ff, dt, t) => {
        if (t < 0.5) {
          ff.handPos('R', _a);
          const g = t / 0.5;
          orb.obj.position.copy(_a); orb.obj.scale.setScalar(2 + g * 5); orb.mat.opacity = 0.9;
          core.obj.position.copy(_a); core.obj.scale.setScalar(0.3 + g * 0.6);
          if (Math.random() < 0.7) { _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize(); _c.copy(_a).addScaledVector(_b, 3); _b.multiplyScalar(-10); G.fx.add.spawn(_c.x, _c.y, _c.z, _b.x, _b.y, _b.z, '#ff6040', 1, 0.6, 0.1, 0.3); }
          if (tgt && !tgt.dead) ff.faceTo(tgt.pos);
        }
      },
      events: [[0.5, (ff) => {
        cleanup();
        ff.handPos('R', _a);
        const origin = _a.clone();
        const dir = aimFrom(ff, origin, tgt && !tgt.dead ? tgt : null, new V3());
        if (!tgt) dir.y = 0, dir.normalize();
        const ball = G.fx.pool('sphere'), bg = G.fx.pool('glow');
        ball.mat.color.set('#ff2a2a'); bg.mat.color.set('#ff5a3a');
        ff.vel.addScaledVector(dir, -14);
        G.sound('beam', ff.pos, 0.35);
        G.fx.burst(origin, '#ff6040', 6, 0.15);
        projectile({
          owner: ff, pos: origin, dir, speed: 95, range: 52, radius: 1.3,
          onHit: () => {},
          onStep: (p) => {
            ball.obj.position.copy(p); ball.obj.scale.setScalar(1.1);
            bg.obj.position.copy(p); bg.obj.scale.setScalar(6);
            G.fx.add.spawn(p.x, p.y, p.z, rand(-3, 3), rand(-3, 3), rand(-3, 3), '#ff4030', 0.9, 1.4, 0.2, 0.25);
          },
          onEnd: (p) => {
            G.fx.release(ball); G.fx.release(bg);
            explosion(ff, p, 7.5, '#ff3030', { dmg: 12, rag: 1.25, kb: { f: 62, up: 22 }, fx: 'heavy', color: '#ff5050', hitstop: 0.1, shake: 0.6, sfx: 'heavy', guardDmg: 70 });
          },
        });
      }]],
      onCancel: cleanup,
    });
    G.sound('charge', f.pos, 0.35);
  },
};

const gInfinity = {
  id: 'inf', label: 'Infinity', cd: 15, color: '#bfe6ff', ai: { kind: 'buff' },
  cast(f) {
    f.infinity = 3.0;
    f.startAction({ name: 'inf', dur: 0.3, frames: [[0, POSE.idle.gojo], [0.4, POSE.sign2], [1, POSE.sign2]] });
    const shell = G.fx.pool('sphere'), ring = G.fx.pool('ring');
    shell.mat.color.set('#7fc8ff'); ring.mat.color.set('#dff3ff');
    G.sound('tp', f.pos, 0.5);
    f.chestPos(_a); G.fx.ring(_a, '#bfe6ff', 1, 6, 0.4, { a0: 0.8 });
    let t = 0;
    G.addTask((dt) => {
      t += dt;
      if (f.dead || f.infinity <= 0) { G.fx.release(shell); G.fx.release(ring); return false; }
      f.chestPos(_a);
      shell.obj.position.copy(_a); shell.obj.scale.setScalar(3.4 + Math.sin(t * 9) * 0.12); shell.mat.opacity = 0.1 + Math.sin(t * 7) * 0.03;
      ring.obj.position.copy(_a); ring.obj.scale.setScalar(3.6); ring.obj.rotation.set(Math.PI / 2 + Math.sin(t * 2) * 0.3, t * 2, 0); ring.mat.opacity = 0.35;
      if (Math.random() < 0.4) { _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize().multiplyScalar(3.4); _b.add(_a); G.fx.add.spawn(_b.x, _b.y, _b.z, 0, 0.5, 0, '#dff3ff', 0.8, 0.5, 0.1, 0.5); }
      return true;
    });
  },
};

const gTeleport = {
  id: 'tp', label: 'Teleport', cd: 8, color: '#9fd8ff', ai: { kind: 'gap', min: 6, max: 36 },
  cast(f) {
    const tgt = f.autoTarget(38, 0.2);
    f.chestPos(_a);
    G.fx.glow(_a, '#bfe6ff', 9, 0.3); G.fx.ring(_a, '#9fd8ff', 1, 5, 0.3);
    G.fx.particles(_a, { n: 14, color: ['#ffffff', '#9fd8ff'], speed: 10, size: 0.8, life: 0.4 });
    G.sound('tp', f.pos, 0.7);
    if (!tgt) {
      f.fwd(_b);
      f.pos.addScaledVector(_b, 16);
      G.world.collide(f.pos, 1.2, 5);
      f.pos.y = Math.max(f.pos.y, G.world.groundAt(f.pos.x, f.pos.z, f.pos.y + 3));
      f.iframes = Math.max(f.iframes, 0.2);
      f.chestPos(_a); G.fx.glow(_a, '#bfe6ff', 9, 0.3);
      f.startAction({ name: 'tpw', dur: 0.2, pose: (ff, a, out) => out.set(POSE.sign2) });
      return;
    }
    // за спину цели
    tgt.fwd(_b);
    f.pos.set(tgt.pos.x - _b.x * 2.8, tgt.pos.y, tgt.pos.z - _b.z * 2.8);
    G.world.collide(f.pos, 1.2, 5);
    f.vel.set(0, 0, 0);
    f.faceTo(tgt.pos);
    f.iframes = Math.max(f.iframes, 0.25);
    f.chestPos(_a); G.fx.glow(_a, '#bfe6ff', 10, 0.3); G.fx.ring(_a, '#ffffff', 1, 6, 0.25);
    const kick = M1ANIM.fist[3];
    f.startAction({
      name: 'tpStrike', dur: 0.5, frames: kick, noGrav: true,
      update: (ff) => { ff.vel.y = 0; },
      events: [[0.2, (ff) => {
        if (!tgt.dead && ff.dist(tgt) < 7) {
          G.hit(ff, tgt, { dmg: 9, melee: true, rag: 1.0, kb: { f: 52, up: 18 }, hitstop: 0.11, fx: 'heavy', color: '#9fd8ff', shake: 0.55, sfx: 'heavy', guardDmg: 55 });
        }
      }]],
    });
  },
};

const gPurple = {
  id: 'purple', label: 'Purple', cd: 9, color: '#b04dff', ai: { kind: 'ranged', min: 5, max: 55 },
  cast(f) {
    let tgt = f.autoTarget(60, 0.55);
    if (tgt) f.faceTo(tgt.pos);
    const bl = G.fx.pool('glow'), rd = G.fx.pool('glow'), pu = G.fx.pool('sphere'), pg = G.fx.pool('glow');
    bl.mat.color.set('#3f8cff'); rd.mat.color.set('#ff3030'); pu.mat.color.set('#a040ff'); pg.mat.color.set('#c070ff');
    pu.obj.visible = pg.obj.visible = false;
    const cleanup = () => { G.fx.release(bl); G.fx.release(rd); G.fx.release(pu); G.fx.release(pg); };
    const SPREAD = PX(POSE.idle.gojo, { lax: -1.3, laz: 1.1, rax: -1.3, raz: -1.1, hy: -0.2, hx: -0.1 });
    const JOIN = PX(POSE.idle.gojo, { lax: -1.6, laz: -0.35, rax: -1.6, raz: 0.35, hy: -0.3, cx: 0.15 });
    const FIRE = PX(POSE.idle.gojo, { rax: -1.7, raz: 0.1, lax: 0.2, laz: 0.3, twist: 0.55, cx: 0.25, hy: -0.35, llx: -0.4, rlx: 0.4 });
    const front = new V3();
    G.sound('charge', f.pos, 0.7);
    G.callout(f, 'Hollow Purple', '#c070ff', true);
    f.startAction({
      name: 'purple', dur: 2.0, armor: true,
      frames: [[0, POSE.idle.gojo], [0.15, SPREAD], [0.45, SPREAD], [0.58, JOIN], [0.62, FIRE], [0.9, FIRE], [1, POSE.idle.gojo]],
      update: (ff, dt, t) => {
        if (tgt && (tgt.dead || ff.dist(tgt) > 70)) tgt = null;
        if (t < 1.2 && tgt) { _a.set(tgt.pos.x - ff.pos.x, 0, tgt.pos.z - ff.pos.z); ff.yaw += Math.atan2(Math.sin(Math.atan2(_a.x, _a.z) - ff.yaw), Math.cos(Math.atan2(_a.x, _a.z) - ff.yaw)) * Math.min(1, dt * 4); }
        ff.chestPos(front); ff.fwd(_b); front.addScaledVector(_b, 3); front.y += 0.6;
        if (t < 1.0) {
          const k = Math.min(1, t / 0.9);
          ff.handPos('L', _a); bl.obj.position.copy(_a); bl.obj.scale.setScalar(2 + k * 5);
          ff.handPos('R', _c); rd.obj.position.copy(_c); rd.obj.scale.setScalar(2 + k * 5);
          if (t > 0.75) { const m = (t - 0.75) / 0.25; bl.obj.position.lerp(front, m); rd.obj.position.lerp(front, m); }
          for (const [p, col] of [[_a, '#7cc8ff'], [_c, '#ff6a5a']]) {
            _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
            const sx = p.x + _b.x * 3, sy = p.y + _b.y * 3, sz = p.z + _b.z * 3;
            G.fx.add.spawn(sx, sy, sz, -_b.x * 12, -_b.y * 12, -_b.z * 12, col, 1, 0.6, 0.1, 0.25);
          }
        } else if (t < 1.25) {
          bl.obj.visible = rd.obj.visible = false;
          pu.obj.visible = pg.obj.visible = true;
          const k = (t - 1.0) / 0.25;
          pu.obj.position.copy(front); pu.obj.scale.setScalar(0.5 + k * 2.6); pu.mat.opacity = 0.9;
          pg.obj.position.copy(front); pg.obj.scale.setScalar(4 + k * 10);
          G.fx.particles(front, { n: 3, color: ['#c070ff', '#ffffff'], speed: 14, size: 0.8, life: 0.3 });
        }
      },
      events: [[1.25, (ff) => {
        G.fx.release(pu); G.fx.release(pg); G.fx.release(bl); G.fx.release(rd);
        const dir = new V3();
        if (tgt && !tgt.dead) { tgt.chestPos(dir).sub(front); dir.y = clamp(dir.y, -dir.length() * 0.3, dir.length() * 0.3); dir.normalize(); }
        else { ff.fwd(dir); }
        const len = 85, R = 5;
        beamFX(front, dir, len, R, '#9a3cff', '#ffe8ff', 0.75);
        G.fx.burst(front, '#e0b0ff', 22, 0.3);
        G.fx.ring(front, '#c070ff', 2, 16, 0.4, { axis: dir.clone() });
        G.fx.ring(front, '#ffffff', 1, 10, 0.3, { axis: dir.clone() });
        for (let i = 0; i < 20; i++) {
          _a.copy(front).addScaledVector(dir, rand(4, len));
          G.fx.add.spawn(_a.x + rand(-4, 4), _a.y + rand(-4, 4), _a.z + rand(-4, 4), dir.x * 30, dir.y * 30, dir.z * 30, i % 2 ? '#c070ff' : '#ffffff', 1, 2, 0.3, 0.5);
        }
        for (const o of beamHits(ff, front, dir, len, R)) {
          G.hit(ff, o, { dmg: 28, rag: 1.6, kb: { f: 80, up: 26 }, pierce: true, unblockable: true, noCounter: true, hitstop: 0.12, fx: 'energy', color: '#c070ff', shake: 0.9, sfx: 'boom', from: ff.pos });
        }
        // борозда по земле
        for (let d = 6; d < len; d += 9) { _a.copy(front).addScaledVector(dir, d); if (_a.y < 6) { _a.y = 0.4; G.fx.debris(_a, 2, ['#5a4a6a', '#7d7468'], 16); } }
        G.shake(0.8, ff.pos);
        G.sound('beam', ff.pos, 1.0); G.sound('boom', ff.pos, 0.6);
        G.flashNear(ff.pos, '#b060ff', 0.45, 60);
        ff.vel.addScaledVector(dir, -18);
      }]],
      onCancel: cleanup,
    });
  },
};

// ---------- Unlimited Void ----------
let voidMeshes = [];
function getVoid() {
  let v = voidMeshes.find((x) => !x.busy);
  if (!v) {
    const mat = new THREE.MeshBasicMaterial({ map: tex('void'), side: THREE.DoubleSide, fog: false, transparent: true, depthWrite: true });
    const dome = new THREE.Mesh(new THREE.SphereGeometry(1, 40, 24), mat);
    const fmat = new THREE.MeshBasicMaterial({ map: tex('void'), fog: false, transparent: true });
    const floor = new THREE.Mesh(new THREE.CircleGeometry(1, 48), fmat);
    floor.rotation.x = -Math.PI / 2;
    dome.renderOrder = 3; floor.renderOrder = 2;
    G.scene.add(dome, floor);
    v = { dome, floor, mat, fmat, busy: false };
    voidMeshes.push(v);
  }
  v.busy = true; v.dome.visible = v.floor.visible = true;
  return v;
}
function unlimitedVoid(f) {
  f.startAction({
    name: 'void', dur: 1.3, armor: true, iframes: 1.3,
    frames: [[0, POSE.idle.gojo], [0.25, POSE.sign2], [1, POSE.sign2]],
    events: [[0.55, (ff) => {
      const center = ff.pos.clone(); center.y += 1;
      const R = 26, v = getVoid();
      const caught = new Set();
      G.sound('boom', ff.pos, 0.8); G.sound('tp', ff.pos, 1);
      G.flashNear(ff.pos, '#ffffff', 0.7, 40);
      G.shake(0.6, ff.pos);
      const catchAll = (stun) => {
        for (const o of ff.enemiesNear(center, R, R)) {
          if (caught.has(o)) continue;
          caught.add(o);
          o.interrupt(true); o.rag = false; o.down = 0;
          o.stun = Math.max(o.stun, stun); o.broken = Math.max(o.broken, stun); o.blocking = false;
          G.hit(ff, o, { dmg: 6, pierce: true, unblockable: true, noCounter: true, hitstop: 0.05, fx: 'energy', color: '#bfe6ff', shake: 0.3, sfx: 'hit' });
          o.stun = Math.max(o.stun, stun);
          o.chestPos(_a); G.hud.pop(_a, '∞', '#bfe6ff', 1.6);
        }
      };
      let t = 0;
      const L = 5.5;
      G.addTask((dt) => {
        t += dt;
        const grow = ease.out3(Math.min(1, t / 0.5));
        const fade = t > L - 0.6 ? Math.max(0, (L - t) / 0.6) : 1;
        v.dome.position.copy(center); v.dome.scale.setScalar(R * grow);
        v.floor.position.set(center.x, 0.25, center.z); v.floor.scale.setScalar(R * grow);
        v.mat.opacity = fade; v.fmat.opacity = fade * 0.95;
        v.dome.rotation.y += dt * 0.08;
        if (t > 0.3 && t < 0.4) catchAll(4.2);
        else if (t > 0.4 && t < L - 1) catchAll(2.2);
        if (Math.random() < 0.8) {
          _a.set(center.x + rand(-R, R) * 0.7, center.y + rand(0, R * 0.6), center.z + rand(-R, R) * 0.7);
          G.fx.add.spawn(_a.x, _a.y, _a.z, 0, rand(-1, 1), 0, Math.random() < 0.5 ? '#ffffff' : '#9fd8ff', 1, 0.6, 0.1, 1.2);
        }
        G.voidZone = t < L ? { center, r: R * grow } : null;
        if (t >= L) { v.busy = false; v.dome.visible = v.floor.visible = false; G.voidZone = null; return false; }
        return true;
      });
    }]],
  });
  G.callout(f, 'Domain Expansion: Unlimited Void', '#9fd8ff');
}

// ======================= SUKUNA =======================
const SWIPE = M1ANIM.sukuna[3];
const sDismantle = {
  id: 'dismantle', label: 'Dismantle', cd: 6, color: '#ff4d6a', ai: { kind: 'ranged', min: 3, max: 34 },
  cast(f) {
    const tgt = f.autoTarget(45, 0.45);
    if (tgt) f.faceTo(tgt.pos);
    f.startAction({
      name: 'dismantle', dur: 0.48, frames: SWIPE,
      events: [[0.18, (ff) => {
        ff.chestPos(_a); _a.y += 0.4;
        const origin = _a.clone();
        const base = aimFrom(ff, origin, tgt && !tgt.dead ? tgt : null, new V3());
        base.y = clamp(base.y, -0.25, 0.25); base.normalize();
        G.sound('slash', ff.pos, 0.8);
        for (const ang of [-0.24, 0, 0.24]) {
          const dir = base.clone().applyAxisAngle(YV, ang);
          const roll = rand(-0.45, 0.45);
          const it = G.fx.pool('cres');
          it.mat.color.set('#ffd6dc');
          const q = new THREE.Quaternion().setFromUnitVectors(ZV, dir).multiply(_q2.setFromAxisAngle(ZV, roll));
          projectile({
            owner: ff, pos: origin.clone().addScaledVector(dir, 1.5), dir, speed: 82, range: 48, radius: 1.6, pierce: true,
            onHit: (o, p) => G.hit(ff, o, { dmg: 4.5, stun: 0.45, push: 7, hitstop: 0.04, fx: 'slash', color: '#ff4d6a', shake: 0.15, sfx: 'slash', vol: 0.5, from: p, guardDmg: 25 }),
            onStep: (p, dt, t) => {
              it.obj.position.copy(p); it.obj.quaternion.copy(q);
              const s = Math.min(1, t / 0.08) * 4.2;
              it.obj.scale.set(s, s, s * 0.8); it.mat.opacity = 1;
              if (Math.random() < 0.5) G.fx.add.spawn(p.x + rand(-1.5, 1.5), p.y, p.z + rand(-1.5, 1.5), 0, 0, 0, '#ff4d6a', 0.8, 0.7, 0.1, 0.2);
            },
            onWorld: (p) => { G.fx.sparks(p, null, '#ffd0d0', 6, 25); },
            onEnd: () => G.fx.release(it),
          });
        }
      }]],
    });
  },
};

const CLEAVE_HOLD = PX(POSE.idle.fist, { rax: -1.6, raz: 0.1, twist: 0.6, cx: 0.25, hy: -0.3, lax: -0.4, laz: 0.4, llx: -0.4, rlx: 0.4 });
const sCleave = {
  id: 'cleave', label: 'Cleave', cd: 10, color: '#ff2d4a', ai: { kind: 'melee', min: 0, max: 8 },
  cast(f) {
    const tgt = f.autoTarget(12, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = lungeTo(f, tgt, 12, 2.6) / 0.18;
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    f.startAction({
      name: 'cleave', dur: 0.82, keepVel: true,
      frames: [[0, POSE.idle.fist], [0.15, PX(CLEAVE_HOLD, { rax: -0.6, twist: -0.4 })], [0.25, CLEAVE_HOLD], [1, CLEAVE_HOLD]],
      update: (ff, dt, t, a) => {
        if (t < 0.18) { ff.vel.x = dx * Math.max(10, lunge); ff.vel.z = dz * Math.max(10, lunge); }
        else ff.friction(dt, 16);
        if (a.victim && !a.victim.dead) { a.victim.stun = Math.max(a.victim.stun, 0.3); }
      },
      events: [
        [0.2, (ff, a) => {
          const v = ff.meleeTargets(5.6, 0.3)[0];
          if (!v) { a.dur = 0.5; return; }
          a.victim = v;
          const r = G.hit(ff, v, { dmg: 2, melee: true, stun: 1.0, guardBreak: true, hitstop: 0.06, fx: 'slash', color: '#ff2d4a', shake: 0.25, sfx: 'slash' });
          if (r !== 'hit' && r !== 'break') { a.victim = null; a.dur = 0.5; }
        }],
        ...[0.28, 0.35, 0.42, 0.49, 0.56].map((tt) => [tt, (ff, a) => {
          const v = a.victim; if (!v || v.dead) return;
          G.hit(ff, v, { dmg: 2, melee: true, stun: 0.6, hitstop: 0.025, fx: 'slash', color: '#ff2d4a', shake: 0.12, sfx: 'slash', vol: 0.45, guardBreak: true });
          v.chestPos(_a);
          _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
          _c.copy(_a).addScaledVector(_b, 3); _a.addScaledVector(_b, -3);
          G.fx.line(_a, _c, '#ffffff', 0.15, 0.12);
        }]),
        [0.66, (ff, a) => {
          const v = a.victim; if (!v || v.dead) return;
          G.hit(ff, v, { dmg: 6, melee: true, rag: 0.9, kb: { f: 34, up: 14 }, hitstop: 0.1, fx: 'slash', color: '#ff2d4a', shake: 0.5, sfx: 'heavy', guardBreak: true });
          v.chestPos(_a);
          _q.setFromUnitVectors(ZV, _b.set(Math.sin(ff.yaw), 0, Math.cos(ff.yaw)));
          G.fx.crescent(_a, _q, '#ff3050', 3, 8, 0.25);
        }],
      ],
    });
    G.sound('swing', f.pos, 0.6);
  },
};

const BOW = PX(POSE.idle.fist, { twist: -0.35, lax: -1.6, laz: -0.05, rax: -1.45, raz: 0.8, cx: 0.0, hy: -0.2, hx: 0.05, llx: -0.3, rlx: 0.35 });
const sFuga = {
  id: 'fuga', label: 'Fire Arrow', cd: 14, color: '#ff8a2a', ai: { kind: 'charge', min: 6, max: 50 },
  cast(f) {
    let tgt = f.autoTarget(55, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    const arrowGlow = G.fx.pool('glow');
    arrowGlow.mat.color.set('#ff8a2a');
    const chargeTime = f.bot ? rand(0.55, 1.3) : 99;
    G.sound('charge', f.pos, 0.5);
    G.callout(f, 'Fuga', '#ff8a2a', true);
    const fire = (ff, a) => {
      if (a.fired) return;
      a.fired = true;
      G.fx.release(arrowGlow);
      const c = clamp((a.t - 0.1) / 1.2, 0, 1);
      ff.handPos('L', _a); const origin = _a.clone();
      if (tgt && tgt.dead) tgt = null;
      const dir = aimFrom(ff, origin, tgt, new V3());
      if (!tgt) dir.y = 0, dir.normalize();
      const g = G.fx.pool('glow'); g.mat.color.set('#ffb040');
      G.sound('beam', ff.pos, 0.6);
      G.fx.burst(origin, '#ffb040', 8, 0.18);
      ff.vel.addScaledVector(dir, -10);
      projectile({
        owner: ff, pos: origin, dir, speed: 105, range: 75, radius: 1.4,
        onHit: () => {},
        onStep: (p, dt) => {
          g.obj.position.copy(p); g.obj.scale.setScalar(5 + c * 3);
          _b.copy(p).addScaledVector(dir, -3.5);
          G.fx.line(_b, p, '#ffcf6a', 0.05, 0.45 + c * 0.3);
          for (let i = 0; i < 3; i++) G.fx.add.spawn(p.x + rand(-0.6, 0.6), p.y + rand(-0.6, 0.6), p.z + rand(-0.6, 0.6), rand(-3, 3), rand(1, 5), rand(-3, 3), i ? '#ff6a1a' : '#ffd040', 1, 1.6, 0.2, 0.35);
        },
        onEnd: (p) => {
          G.fx.release(g);
          const R = 6 + c * 5;
          explosion(ff, p, R, '#ff7a1a', { dmg: 9 + 13 * c, rag: 1.2, kb: { f: 45 + 20 * c, up: 22 }, fx: 'fire', hitstop: 0.1, shake: 0.7, sfx: 'heavy', guardDmg: 80 });
          // остаточное пламя
          let ft = 0;
          G.addTask((dt) => {
            ft += dt;
            if (Math.random() < 0.9) G.fx.add.spawn(p.x + rand(-R, R) * 0.5, Math.max(0.3, p.y - 1) + rand(0, 1), p.z + rand(-R, R) * 0.5, 0, rand(4, 9), 0, Math.random() < 0.5 ? '#ff6a1a' : '#ffc040', 1, 1.8, 0.2, 0.6);
            return ft < 1.4;
          });
        },
      });
      a.dur = a.t + 0.35;
    };
    f.startAction({
      name: 'fuga', slot: 2, dur: 99, move: 0.15,
      frames: [[0, POSE.idle.fist], [1, BOW]],
      pose: null,
      update: (ff, dt, t, a) => {
        if (!a.fired) {
          if (tgt && !tgt.dead) ff.faceTo(tgt.pos);
          else if (ff.isPlayer) { ff.yaw = Math.atan2(ff.aim.x, ff.aim.z); }
          const c = clamp(t / 1.2, 0, 1);
          ff.handPos('L', _a); ff.handPos('R', _c);
          G.fx.line(_c, _a, '#ffd070', 0.05, 0.2 + c * 0.3);
          arrowGlow.obj.position.copy(_a); arrowGlow.obj.scale.setScalar(3 + c * 6);
          for (let i = 0; i < 2; i++) {
            const ang = rand(-1.3, 1.3);
            _b.set(_a.x + Math.cos(ang) * 0.3, _a.y + Math.sin(ang) * 2.4, _a.z);
            G.fx.add.spawn(_b.x, _b.y, _b.z, rand(-1, 1), rand(1, 4), rand(-1, 1), i ? '#ff6a1a' : '#ffd040', 1, 1.1 + c, 0.2, 0.3);
          }
          const minOk = t > 0.35;
          if (minOk && (a.released || t >= chargeTime || t >= 1.6)) fire(ff, a);
        }
      },
      onCancel: () => G.fx.release(arrowGlow),
    });
    // для анимации используем позу лука
    f.action.frames = null;
    f.action.pose = (ff, a, out) => out.set(a.fired ? PX(BOW, { cx: -0.15, rax: -0.9, raz: 0.3 }) : BOW);
  },
};

const RUSH_POSE = PX(POSE.dashF, { rax: -1.2, raz: 0.2, lax: -1.2, laz: -0.2 });
const sRush = {
  id: 'rush', label: 'Rush', cd: 12, color: '#ff6a8a', ai: { kind: 'gap', min: 4, max: 26 },
  cast(f) {
    const tgt = f.autoTarget(30, 0.4);
    if (tgt) f.faceTo(tgt.pos);
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    G.sound('dash', f.pos, 0.8);
    f.startAction({
      name: 'rush', dur: 0.45, keepVel: true, poseSpeed: 26,
      pose: (ff, a, out) => out.set(RUSH_POSE),
      update: (ff, dt, t) => {
        if (tgt && !tgt.dead) ff.faceTo(tgt.pos);
        ff.fwd(_b);
        ff.vel.x = _b.x * 72; ff.vel.z = _b.z * 72;
        if (Math.random() < 0.8) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.5, 5), ff.pos.z + rand(-1, 1)); _c.set(-_b.x * 40, 0, -_b.z * 40); G.fx.str.add(_a, _c, '#ffd0dc', 0.15, 0.09, 3, { drag: 6 }); }
        const v = ff.meleeTargets(3.4, 0.5)[0];
        if (v) {
          ff.vel.set(0, ff.vel.y, 0);
          rushBarrage(ff, v);
        }
      },
    });
    void dx; void dz;
  },
};
function rushBarrage(f, v) {
  f.action = null;
  const L = PX(POSE.idle.fist, { lax: -1.65, laz: -0.1, rax: -0.6, twist: -0.6, cx: 0.25, hy: -0.3 });
  const R = PX(POSE.idle.fist, { rax: -1.65, raz: 0.1, lax: -0.6, twist: 0.6, cx: 0.25, hy: -0.3 });
  const UP = PX(POSE.idle.fist, { rax: -2.8, raz: 0.1, twist: 0.5, cx: -0.2, hy: 0.1, rlx: 0.3, llx: -0.3 });
  const evs = [];
  for (let i = 0; i < 7; i++) {
    evs.push([0.05 + i * 0.085, (ff) => {
      if (v.dead) return;
      G.hit(ff, v, { dmg: 1.4, melee: true, stun: 0.5, push: 1.5, hitstop: 0.025, fx: 'hit', shake: 0.1, sfx: 'hit', vol: 0.4, guardDmg: 14 });
      ff.chestPos(_a); ff.fwd(_b); _a.addScaledVector(_b, 2.6); _a.x += rand(-1, 1); _a.y += rand(-1, 1.2); _a.z += rand(-1, 1);
      G.fx.burst(_a, '#ffffff', 2.8, 0.1);
    }]);
  }
  evs.push([0.72, (ff) => {
    if (v.dead) return;
    G.hit(ff, v, { dmg: 5, melee: true, rag: 1.0, kb: { f: 28, up: 34 }, hitstop: 0.1, fx: 'heavy', color: '#ff8aa0', shake: 0.5, sfx: 'heavy', guardDmg: 50 });
  }]);
  f.startAction({
    name: 'barrage', dur: 0.95, keepVel: false, poseSpeed: 40, events: evs,
    pose: (ff, a, out) => out.set(a.t > 0.68 ? UP : Math.floor(a.t / 0.0425) % 2 ? L : R),
    update: (ff) => { if (!v.dead && v.stun > 0) { ff.faceTo(v.pos); const d = ff.dist(v); if (d > 3.2) { ff.fwd(_b); ff.vel.x = _b.x * 12; ff.vel.z = _b.z * 12; } } },
  });
}

// ---------- Malevolent Shrine ----------
const shrines = [];
function getShrine() {
  let s = shrines.find((x) => !x.busy);
  if (!s) {
    const m = buildShrine();
    const disc = new THREE.Mesh(new THREE.CircleGeometry(1, 48), new THREE.MeshBasicMaterial({ map: tex('shrine'), transparent: true, depthWrite: false, fog: false }));
    disc.rotation.x = -Math.PI / 2; disc.renderOrder = 2;
    G.scene.add(m.root, disc);
    s = { m, disc, busy: false };
    shrines.push(s);
  }
  s.busy = true; s.m.root.visible = s.disc.visible = true;
  return s;
}
function malevolentShrine(f) {
  f.startAction({
    name: 'shrine', dur: 1.5, armor: true, iframes: 1.5,
    frames: [[0, POSE.idle.sukuna], [0.25, POSE.sign], [1, POSE.sign]],
    events: [[0.6, (ff) => {
      const s = getShrine();
      const center = ff.pos.clone();
      ff.fwd(_b);
      const base = center.clone().addScaledVector(_b, -9);
      s.m.root.position.copy(base); s.m.root.rotation.y = ff.yaw;
      const R = 30, L = 11;
      G.sound('boom', ff.pos, 0.9);
      G.flashNear(ff.pos, '#ff1030', 0.5, 50);
      G.shake(0.7, ff.pos);
      let t = 0, tick = 0;
      G.addTask((dt) => {
        t += dt; tick -= dt;
        const rise = ease.out3(Math.min(1, t / 0.7));
        const sink = t > L - 0.8 ? Math.max(0, (L - t) / 0.8) : 1;
        s.m.root.position.y = base.y - 20 * (1 - rise) - 20 * (1 - sink);
        const r = R * ease.out(Math.min(1, t / 0.6));
        s.disc.position.set(center.x, 0.2, center.z); s.disc.scale.setScalar(r); s.disc.material.opacity = sink * 0.85;
        if (t < 0.7 && Math.random() < 0.8) { _a.set(base.x + rand(-8, 8), 0.5, base.z + rand(-8, 8)); G.fx.debris(_a, 1, ['#2b2524', '#6a1818']); }
        // визуальные разрезы по зоне
        for (let i = 0; i < 2; i++) {
          const ang = rand(0, Math.PI * 2), rr = Math.sqrt(Math.random()) * r;
          _a.set(center.x + Math.cos(ang) * rr, rand(0.5, 7), center.z + Math.sin(ang) * rr);
          _b.set(rand(-1, 1), rand(-0.6, 0.6), rand(-1, 1)).normalize();
          _c.copy(_a).addScaledVector(_b, rand(3, 7));
          G.fx.line(_a, _c, Math.random() < 0.3 ? '#ff5060' : '#ffffff', 0.12, 0.1);
        }
        if (tick <= 0 && t > 0.5 && !ff.dead) {
          tick = 0.22;
          let any = false;
          for (const o of ff.enemiesNear(center, r, 12)) {
            any = true;
            G.hit(ff, o, { dmg: 1.2, pierce: true, unblockable: true, noCounter: true, hitstop: 0.0, fx: 'slash', color: '#ff2040', shake: 0.06, sfx: 'slash', vol: 0.25 });
          }
          if (any) G.sound('slash', center, 0.3);
        }
        G.shrineZone = { center, r, owner: ff };
        if (t >= L || (ff.dead && t < L - 0.8)) {
          if (ff.dead && t < L - 0.8) { t = L - 0.8; return true; }
          s.busy = false; s.m.root.visible = s.disc.visible = false; G.shrineZone = null;
          return false;
        }
        return true;
      });
    }]],
  });
  G.callout(f, 'Domain Expansion: Malevolent Shrine', '#ff3050');
}

// ======================= YUJI =======================
const PUNCH_WIND = PX(POSE.idle.fist, { rax: 0.5, raz: -0.3, twist: -0.6, hy: -0.3, cx: 0.1, lax: -1.2 });
const PUNCH_HIT = PX(POSE.idle.fist, { rax: -1.7, raz: 0.05, twist: 0.75, cx: 0.3, hy: -0.35, lax: -0.4, laz: 0.4, llx: -0.45, rlx: 0.5 });

const yDivergent = {
  id: 'divergent', label: 'Divergent', cd: 7, color: '#4fb8ff', ai: { kind: 'gap', min: 0, max: 15 },
  cast(f) {
    const tgt = f.autoTarget(17, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(85, lungeTo(f, tgt, 17, 2.6) / 0.12);
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    f.startAction({
      name: 'divergent', dur: 0.6, keepVel: true,
      frames: [[0, POSE.idle.fist], [0.25, PUNCH_WIND], [0.4, PUNCH_HIT], [0.8, PUNCH_HIT], [1, POSE.idle.fist]],
      update: (ff, dt, t) => {
        if (t > 0.12 && t < 0.24) { ff.vel.x = dx * Math.max(8, lunge); ff.vel.z = dz * Math.max(8, lunge); } else ff.friction(dt, 14);
        if (t < 0.24) { ff.handPos('R', _a); G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-2, 2), rand(0, 3), rand(-2, 2), '#4fb8ff', 1, 1, 0.2, 0.25); }
      },
      events: [[0.24, (ff) => {
        for (const v of ff.meleeTargets(5.6, 0.35)) {
          const r = G.hit(ff, v, { dmg: 5, melee: true, stun: 1.0, push: 3, hitstop: 0.07, fx: 'hit', shake: 0.3, sfx: 'hit' });
          if (r === 'hit') {
            let t = 0;
            G.addTask((dt) => {
              t += dt;
              if (v.dead) return false;
              if (t < 0.38) { v.chestPos(_a); if (Math.random() < 0.6) G.fx.add.spawn(_a.x + rand(-1, 1), _a.y + rand(-1, 1), _a.z + rand(-1, 1), 0, 2, 0, '#4fb8ff', 1, 0.9, 0.1, 0.25); return true; }
              G.hit(ff, v, { dmg: 7, rag: 0.8, kb: { f: 34, up: 14 }, pierce: true, noCounter: true, ignoreIframes: true, hitstop: 0.09, fx: 'energy', color: '#4fb8ff', shake: 0.45, sfx: 'heavy', guardDmg: 50 });
              v.chestPos(_a);
              G.fx.ring(_a, '#4fb8ff', 1, 7, 0.3, { a0: 0.9 });
              G.fx.ring(_a, '#ffffff', 0.5, 4, 0.2);
              return false;
            });
          }
        }
      }]],
    });
    G.sound('swing', f.pos, 0.6);
  },
};

const KICK_HIGH = PX(POSE.idle.fist, { rlx: -2.3, llx: 0.3, lean: -0.35, cx: -0.1, hy: 0.15, rax: 0.5, raz: -0.9, lax: 0.4, laz: 0.9, twist: 0.3 });
const MANJI_STANCE = PX(POSE.idle.fist, { hy: -0.45, cx: 0.2, rax: -1.0, raz: 0.3, lax: -1.3, laz: -0.2, llx: -0.5, rlx: 0.5, twist: 0.4 });
const yManji = {
  id: 'manji', label: 'Manji Kick', cd: 10, color: '#ffc040', ai: { kind: 'counter', min: 0, max: 7 },
  cast(f) {
    f.counter = 0.85;
    f.chestPos(_a); G.fx.ring(_a, '#ffc040', 1, 4, 0.3, { a0: 0.8 });
    G.sound('block', f.pos, 0.5);
    f.startAction({
      name: 'manji', dur: 0.85, frames: [[0, POSE.idle.fist], [0.2, MANJI_STANCE], [1, MANJI_STANCE]],
      onEnd: (ff) => {
        ff.counter = 0;
        // не поймал — простой лоу-кик
        ff.startAction({
          name: 'lowkick', dur: 0.4, frames: [[0, MANJI_STANCE], [0.4, PX(POSE.idle.fist, { rlx: -1.2, lean: -0.15, hy: -0.2 })], [1, POSE.idle.fist]],
          events: [[0.16, (f2) => { for (const v of f2.meleeTargets(5, 0.4)) G.hit(f2, v, { dmg: 4, melee: true, stun: 0.5, push: 5, fx: 'hit', sfx: 'hit' }); }]],
        });
      },
    });
  },
};
function manjiCounter(f, att) {
  f.interrupt(true);
  f.counter = 0;
  f.faceTo(att.pos);
  const d = f.dist(att);
  if (d > 3.5 && d < 14) { f.fwd(_b); f.pos.addScaledVector(_b, d - 2.8); G.world.collide(f.pos, 1.2, 5); }
  f.iframes = Math.max(f.iframes, 0.45);
  att.interrupt(); att.stun = Math.max(att.stun, 0.4);
  f.chestPos(_a);
  G.hud.pop(_a, 'COUNTER!', '#ffc040', 1.5);
  G.fx.burst(_a, '#ffd060', 8, 0.2);
  G.sound('block', f.pos, 0.9);
  f.startAction({
    name: 'manjiKick', dur: 0.55, frames: [[0, MANJI_STANCE], [0.25, KICK_HIGH], [0.7, KICK_HIGH], [1, POSE.idle.fist]],
    events: [[0.12, (ff) => {
      if (att.dead || ff.dist(att) > 7.5) return;
      G.hit(ff, att, { dmg: 10, melee: true, rag: 1.2, kb: { f: 22, up: 40 }, noCounter: true, pierce: true, hitstop: 0.12, fx: 'heavy', color: '#ffc040', shake: 0.6, sfx: 'heavy', guardBreak: true });
    }]],
  });
}

const yStrikes = {
  id: 'strikes', label: 'Cursed Strikes', cd: 11, color: '#ff9a4a', ai: { kind: 'melee', min: 0, max: 7 },
  cast(f) {
    const tgt = f.autoTarget(10, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const L = PX(POSE.idle.fist, { lax: -1.65, laz: -0.05, rax: -0.5, twist: -0.55, cx: 0.22, hy: -0.3 });
    const R = PX(POSE.idle.fist, { rax: -1.65, raz: 0.05, lax: -0.5, twist: 0.55, cx: 0.22, hy: -0.3 });
    const evs = [];
    for (let i = 0; i < 7; i++) evs.push([0.08 + i * 0.1, (ff) => {
      for (const v of ff.meleeTargets(5.4, 0.3)) G.hit(ff, v, { dmg: 1.6, melee: true, stun: 0.5, push: 3, hitstop: 0.025, fx: 'hit', color: '#ffb070', shake: 0.1, sfx: 'hit', vol: 0.45, guardDmg: 16 });
      ff.chestPos(_a); ff.fwd(_b); _a.addScaledVector(_b, 2.8); _a.x += rand(-1, 1); _a.y += rand(-0.8, 1); _a.z += rand(-1, 1);
      G.fx.burst(_a, '#ffb070', 3, 0.1);
      G.sound('swing', ff.pos, 0.3);
    }]);
    evs.push([0.86, (ff) => {
      for (const v of ff.meleeTargets(5.6, 0.3)) G.hit(ff, v, { dmg: 5, melee: true, rag: 0.9, kb: { f: 42, up: 14 }, hitstop: 0.09, fx: 'heavy', color: '#ff9a4a', shake: 0.45, sfx: 'heavy', guardDmg: 45 });
    }]);
    f.startAction({
      name: 'strikes', dur: 1.05, keepVel: true, poseSpeed: 40, events: evs,
      pose: (ff, a, out) => out.set(a.t > 0.82 ? PUNCH_HIT : Math.floor(a.t / 0.05) % 2 ? L : R),
      update: (ff, dt, t) => {
        if (tgt && !tgt.dead && ff.dist(tgt) > 3.2) { ff.faceTo(tgt.pos); ff.fwd(_b); ff.vel.x = _b.x * 9; ff.vel.z = _b.z * 9; } else ff.friction(dt, 12);
      },
    });
  },
};

const yBlackFlash = {
  id: 'bf', label: 'Black Flash', cd: 9, color: '#e0203a', ai: { kind: 'gap', min: 0, max: 13 },
  cast(f) {
    const tgt = f.autoTarget(15, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(90, lungeTo(f, tgt, 15, 2.6) / 0.09);
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    f.startAction({
      name: 'bf', dur: 0.78, keepVel: true,
      frames: [[0, POSE.idle.fist], [0.35, PUNCH_WIND], [0.48, PUNCH_HIT], [0.85, PUNCH_HIT], [1, POSE.idle.fist]],
      update: (ff, dt, t) => {
        if (t < 0.28) {
          ff.handPos('R', _a);
          if (Math.random() < 0.5) { _b.set(_a.x + rand(-1.5, 1.5), _a.y + rand(-1.5, 1.5), _a.z + rand(-1.5, 1.5)); G.fx.bolt(_a, _b, '#120006', { dark: true, segs: 3, jag: 0.4, life: 0.1, w: 0.12 }); }
          ff.friction(dt, 12);
        } else if (t < 0.37) { ff.vel.x = dx * Math.max(8, lunge); ff.vel.z = dz * Math.max(8, lunge); }
        else ff.friction(dt, 14);
      },
      events: [[0.37, (ff) => {
        const v = ff.meleeTargets(5.8, 0.35)[0];
        if (!v) return;
        if (Math.random() < (ff.awakened > 0 ? 1 : 0.45)) blackFlash(ff, v, false);
        else G.hit(ff, v, { dmg: 8, melee: true, rag: 0.9, kb: { f: 44, up: 14 }, hitstop: 0.1, fx: 'heavy', shake: 0.5, sfx: 'heavy', guardDmg: 60 });
      }]],
    });
    G.sound('charge', f.pos, 0.3);
  },
};
function blackFlash(f, v, fromM1) {
  const r = G.hit(f, v, { dmg: fromM1 ? 11 : 15, melee: true, rag: 1.3, kb: { f: 72, up: 24 }, pierce: true, hitstop: 0.22, fx: 'heavy', color: '#ff2040', shake: 1.0, sfx: 'boom', guardBreak: true, numColor: '#ff3050' });
  if (!r) return;
  v.chestPos(_a);
  const c = _a.clone();
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
  if (f.isPlayer || v.isPlayer || f.dist(G.player) < 40) G.hud.blackFlash();
  if (f.awakened <= 0) f.meter = Math.min(100, f.meter + 25);
  f.cd[3] *= 0.5;
}

function yujiAwaken(f) {
  f.startAction({
    name: 'yawaken', dur: 1.0, armor: true, iframes: 1.0,
    frames: [[0, POSE.idle.fist], [0.3, POSE.roar], [0.8, POSE.roar], [1, POSE.idle.fist]],
    events: [[0.3, (ff) => {
      ff.chestPos(_a);
      G.fx.ring(_a, '#ff2040', 1, 16, 0.5, { axis: 'y' });
      G.fx.ring(_a, '#111111', 1, 12, 0.4);
      G.fx.particles(_a, { n: 30, color: ['#ff2040', '#ffffff', '#ff8040'], speed: 20, size: 1.2, life: 0.6 });
      for (let i = 0; i < 6; i++) { _b.set(rand(-1, 1), rand(-0.3, 1), rand(-1, 1)).normalize().multiplyScalar(7).add(_a); G.fx.bolt(_a, _b, '#0a0003', { dark: true, life: 0.35 }); }
      for (const o of ff.enemiesNear(_a, 11)) G.hit(ff, o, { dmg: 3, rag: 0.6, kb: { f: 30, up: 12 }, fx: 'energy', color: '#ff2040', from: ff.pos, unblockable: true });
      G.sound('boom', ff.pos, 0.7);
      G.shake(0.6, ff.pos);
    }]],
  });
  G.callout(f, 'Awakening: Black Flash Mastery', '#ff2040');
}

// ======================= YUTA =======================
const KT = POSE.idle.katana;
const POINT_UP = PX(KT, { rax: -2.7, raz: 0.1, kat: 0.2, lax: -0.4, laz: 0.4, hx: -0.15, hy: -0.1 });
const rikaArms = [];
function getRikaArm() {
  let a = rikaArms.find((x) => !x.busy);
  if (!a) { a = buildRikaArm(); a.busy = false; G.scene.add(a.root); rikaArms.push(a); }
  a.busy = true; a.root.visible = true;
  return a;
}
const rikas = [];
function getRika() {
  let r = rikas.find((x) => !x.busy);
  if (!r) { r = buildRika(); r.busy = false; G.scene.add(r.root); rikas.push(r); }
  r.busy = true; r.root.visible = true;
  return r;
}

const ySmash = {
  id: 'rsmash', label: 'Rika Smash', cd: 10, color: '#8a5cff', ai: { kind: 'ranged', min: 3, max: 18 },
  cast(f) {
    const tgt = f.autoTarget(20, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const pt = new V3();
    if (tgt) pt.copy(tgt.pos); else { f.fwd(_b); pt.copy(f.pos).addScaledVector(_b, 10); }
    pt.y = G.world.groundAt(pt.x, pt.z, pt.y + 2);
    G.sound('charge', f.pos, 0.4);
    f.startAction({
      name: 'rsmash', dur: 0.75, frames: [[0, KT], [0.25, POINT_UP], [0.5, PX(KT, { rax: -1.2, kat: 0.9, cx: 0.2, hy: -0.3 })], [1, KT]],
      events: [[0.1, (ff) => {
        const arm = getRikaArm();
        const yaw = ff.yaw;
        let t = 0, hit = false;
        G.fx.particles(_a.set(pt.x, pt.y + 14, pt.z), { n: 20, normal: true, color: '#1a1020', speed: 8, size: 2, size1: 4, life: 0.6, alpha: 0.7 });
        G.addTask((dt) => {
          t += dt;
          if (tgt && !tgt.dead && t < 0.15) { pt.x += (tgt.pos.x - pt.x) * 0.2; pt.z += (tgt.pos.z - pt.z) * 0.2; }
          const fall = ease.in(Math.min(1, t / 0.3));
          arm.root.position.set(pt.x, pt.y + 2.2 + 16 * (1 - fall), pt.z);
          arm.root.rotation.set(-0.7 * (1 - fall), yaw, 0);
          const sink = t > 0.85 ? Math.min(1, (t - 0.85) / 0.3) : 0;
          arm.root.position.y -= sink * 14;
          arm.root.scale.setScalar(1 - sink * 0.3);
          if (!hit && t >= 0.3) {
            hit = true;
            _a.set(pt.x, pt.y + 1.5, pt.z);
            for (const o of ff.enemiesNear(_a, 7.5)) G.hit(ff, o, { dmg: 11, rag: 1.0, kb: { f: 22, up: 28 }, from: pt, hitstop: 0.1, fx: 'heavy', color: '#b080ff', shake: 0.6, sfx: 'heavy', guardDmg: 70 });
            _a.y = pt.y + 0.3;
            G.fx.ring(_a, '#c0a0ff', 1, 13, 0.45, { axis: 'y' });
            G.fx.ring(_a, '#ffffff', 1, 8, 0.3, { axis: 'y' });
            G.fx.debris(_a, 14, ['#7d7468', '#5ea548', '#3a3c42'], 26);
            G.fx.crater(_a, 8, 5);
            G.fx.dust(_a, 16, 4);
            G.fx.particles(_a, { n: 14, normal: true, color: '#1a1020', speed: 12, up: 6, size: 2, size1: 5, life: 0.8, alpha: 0.6 });
            G.shake(0.55, pt);
            G.sound('boom', pt, 0.8);
          }
          if (t >= 1.15) { arm.busy = false; arm.root.visible = false; return false; }
          return true;
        });
      }]],
    });
  },
};

const DASH_SLASH = PX(KT, { lean: 0.45, rax: 0.7, raz: -0.3, kat: 1.4, lax: 0.6, laz: 0.3, hy: -0.35, llx: -0.6, rlx: 0.7 });
const SHEATH = PX(KT, { rax: -0.3, raz: 0.6, kat: 1.5, twist: 0.6, cx: 0.25, hy: -0.4, lax: -0.6, laz: -0.6 });
const yKDash = {
  id: 'kdash', label: 'Katana Dash', cd: 7, color: '#e8f0ff', ai: { kind: 'gap', min: 4, max: 22 },
  cast(f) {
    const tgt = f.autoTarget(26, 0.4);
    if (tgt) f.faceTo(tgt.pos);
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    const start = f.pos.clone();
    const victims = new Set();
    G.sound('dash', f.pos, 0.8);
    f.startAction({
      name: 'kdash', dur: 0.3, keepVel: true, iframes: 0.32, poseSpeed: 30,
      pose: (ff, a, out) => out.set(DASH_SLASH),
      update: (ff) => {
        ff.vel.x = dx * 78; ff.vel.z = dz * 78;
        for (const o of G.fighters) if (ff.isEnemy(o) && ff.dist(o) < 3.6 && Math.abs(o.pos.y - ff.pos.y) < 5) victims.add(o);
      },
      onEnd: (ff) => {
        ff.vel.x *= 0.15; ff.vel.z *= 0.15;
        const end = ff.pos.clone();
        _a.copy(start); _a.y += 3; _c.copy(end); _c.y += 3;
        G.fx.line(_a, _c, '#ffffff', 0.45, 0.35);
        G.fx.line(_a, _c, '#c7a0ff', 0.6, 0.7);
        ff.startAction({ name: 'sheath', dur: 0.35, frames: [[0, DASH_SLASH], [0.4, SHEATH], [1, SHEATH]] });
        let t = 0;
        G.addTask((dt) => {
          t += dt;
          if (t < 0.18) return true;
          for (const v of victims) {
            if (v.dead) continue;
            G.hit(ff, v, { dmg: 9, stun: 0.7, kb: { f: 10, up: 8 }, from: start, hitstop: 0.08, fx: 'slash', color: '#e8f0ff', shake: 0.4, sfx: 'slash', guardDmg: 45, ignoreIframes: true });
            v.chestPos(_a);
            for (let i = 0; i < 2; i++) {
              _q.setFromUnitVectors(ZV, _b.set(dx, 0, dz)); _q.multiply(_q2.setFromAxisAngle(ZV, rand(0, 3.14)));
              G.fx.crescent(_a, _q, '#ffffff', 2, 5, 0.22);
            }
          }
          if (victims.size) G.sound('slash', end, 0.8);
          return false;
        });
      },
    });
  },
};

const SPEECH = PX(KT, { lax: -2.3, laz: -0.75, hx: 0.1, cx: 0.15, hy: -0.15 });
const ySpeech = {
  id: 'speech', label: '«Стой!»', cd: 15, color: '#c77dff', ai: { kind: 'aoe', min: 0, max: 14 },
  cast(f) {
    f.startAction({
      name: 'speech', dur: 0.65, frames: [[0, KT], [0.25, SPEECH], [0.8, SPEECH], [1, KT]],
      events: [[0.22, (ff) => {
        ff.headPos(_a);
        G.hud.pop(_a.set(_a.x, _a.y + 1, _a.z), 'СТОЙ!', '#d9a0ff', 2.2);
        ff.chestPos(_a);
        for (let i = 0; i < 3; i++) {
          G.fx.ring(_a, '#c77dff', 1, 18, 0.5, { axis: 'y', delay: i * 0.08, a0: 0.9 });
          G.fx.ring(_a, '#ffffff', 1, 12, 0.35, { delay: i * 0.1, a0: 0.6 });
        }
        G.fx.particles(_a, { n: 20, color: ['#c77dff', '#ffffff'], speed: 18, size: 1, life: 0.5 });
        for (const o of ff.enemiesNear(_a, 15)) {
          G.hit(ff, o, { dmg: 3, stun: 1.4, pierce: true, noCounter: true, unblockable: true, hitstop: 0.05, fx: 'energy', color: '#c77dff', shake: 0.3, sfx: 'hit' });
          if (!o.dead && !o.rag && o.prot <= 0) { o.stun = Math.max(o.stun, 1.4); o.broken = Math.max(o.broken, 1.4); o.interrupt(true); }
        }
        G.sound('tp', ff.pos, 0.8); G.sound('heavy', ff.pos, 0.5);
        G.shake(0.3, ff.pos);
      }]],
    });
  },
};

const BEAM_POSE = PX(KT, { rax: -1.6, raz: 0.1, kat: 1.45, twist: 0.4, cx: 0.15, hy: -0.3, lax: -0.6, laz: 0.4, llx: -0.4, rlx: 0.4 });
const yLoveBeam = {
  id: 'love', label: 'Love Beam', cd: 16, color: '#ff6ad5', ai: { kind: 'ranged', min: 5, max: 48 },
  cast(f) {
    let tgt = f.autoTarget(55, 0.5);
    if (tgt) f.faceTo(tgt.pos);
    const rika = getRika();
    rika.root.scale.setScalar(0.85);
    const glow = G.fx.pool('glow'); glow.mat.color.set('#ff8ae0');
    const mouth = new V3();
    const cleanup = () => { G.fx.release(glow); };
    G.sound('charge', f.pos, 0.6);
    G.callout(f, 'Pure Love Beam', '#ff6ad5', true);
    let gone = false;
    const R = rika;
    const placeRika = (ff, t) => {
      ff.fwd(_b);
      const rise = ease.out3(Math.min(1, t / 0.4));
      const sink = t > 1.6 ? Math.min(1, (t - 1.6) / 0.4) : 0;
      R.root.position.set(ff.pos.x - _b.x * 4.5, ff.pos.y - 12 * (1 - rise) - 14 * sink, ff.pos.z - _b.z * 4.5);
      R.root.rotation.y = ff.yaw;
      R.armL.rotation.x = -1.2; R.armR.rotation.x = -1.2;
      mouth.set(0, 9.3 * 0.85, 3.8 * 0.85).applyAxisAngle(YV, ff.yaw).add(R.root.position);
    };
    let rt = 0;
    G.addTask((dt) => {
      rt += dt;
      placeRika(f, rt);
      if (rt > 2.0 || (f.dead && rt > 0.1)) { R.busy = false; R.root.visible = false; gone = true; return false; }
      return true;
    });
    f.startAction({
      name: 'love', dur: 1.55, armor: true,
      frames: [[0, KT], [0.2, BEAM_POSE], [1, BEAM_POSE]],
      update: (ff, dt, t) => {
        if (tgt && tgt.dead) tgt = null;
        if (t < 0.85) {
          if (tgt) ff.faceTo(tgt.pos);
          const k = t / 0.85;
          glow.obj.position.copy(mouth); glow.obj.scale.setScalar(2 + k * 8);
          _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
          G.fx.add.spawn(mouth.x + _b.x * 5, mouth.y + _b.y * 5, mouth.z + _b.z * 5, -_b.x * 18, -_b.y * 18, -_b.z * 18, Math.random() < 0.5 ? '#ff8ae0' : '#ffffff', 1, 0.9, 0.1, 0.28);
        }
      },
      events: [[0.85, (ff) => {
        cleanup();
        const origin = mouth.clone();
        const dir = new V3();
        if (tgt) { tgt.chestPos(dir).sub(origin).normalize(); } else { ff.fwd(dir); dir.y = -0.12; dir.normalize(); }
        const len = 62, Rr = 3.4;
        beamFX(origin, dir, len, Rr, '#ff4fc8', '#ffffff', 0.65);
        G.fx.burst(origin, '#ffb0ee', 16, 0.25);
        G.fx.ring(origin, '#ff6ad5', 1, 10, 0.35, { axis: dir.clone() });
        for (const o of beamHits(ff, origin, dir, len, Rr)) G.hit(ff, o, { dmg: 20, rag: 1.4, kb: { f: 66, up: 22 }, pierce: true, hitstop: 0.12, fx: 'energy', color: '#ff6ad5', shake: 0.75, sfx: 'boom', from: ff.pos, guardDmg: 120 });
        for (let d = 6; d < len; d += 10) { _a.copy(origin).addScaledVector(dir, d); if (_a.y < 5) { _a.y = 0.4; G.fx.debris(_a, 2, ['#5a4a6a', '#7d7468'], 16); G.fx.dust(_a, 2, 3); } }
        G.sound('beam', ff.pos, 1);
        G.shake(0.6, ff.pos);
        G.flashNear(ff.pos, '#ff6ad5', 0.35, 50);
      }]],
      onCancel: cleanup,
    });
  },
};

// Пробуждение Юты: Рика сражается рядом
function yutaAwaken(f) {
  const R = getRika();
  R.root.scale.setScalar(1);
  f.rika = R;
  f.startAction({
    name: 'rawaken', dur: 1.2, armor: true, iframes: 1.2,
    frames: [[0, KT], [0.25, POINT_UP], [1, POINT_UP]],
    events: [[0.4, (ff) => {
      ff.chestPos(_a);
      G.fx.ring(_a, '#8a5cff', 1, 18, 0.5, { axis: 'y' });
      G.fx.particles(_a, { n: 30, normal: true, color: '#1a1020', speed: 16, up: 4, size: 2, size1: 5, life: 0.9, alpha: 0.7 });
      for (const o of ff.enemiesNear(_a, 10)) G.hit(ff, o, { dmg: 4, rag: 0.6, kb: { f: 32, up: 14 }, from: ff.pos, fx: 'energy', color: '#8a5cff', unblockable: true });
      G.sound('boom', ff.pos, 0.8);
      G.shake(0.6, ff.pos);
    }]],
  });
  G.callout(f, 'Rika: Full Manifestation', '#c77dff');
  const pos = f.pos.clone(); pos.y -= 14;
  let t = 0, atk = 1.0, swing = 0, target = null, yaw = f.yaw;
  G.addTask((dt) => {
    t += dt; atk -= dt;
    const alive = !f.dead && f.awakened > 0 && !G.matchOver;
    // точка: за плечом у Юты, или у цели при атаке
    f.fwd(_b);
    const side = new V3(-_b.z, 0, _b.x);
    _a.copy(f.pos).addScaledVector(_b, -4.5).addScaledVector(side, -3.5);
    if (swing > 0 && target && !target.dead) { _a.copy(target.pos); _c.set(f.pos.x - target.pos.x, 0, f.pos.z - target.pos.z).normalize(); _a.addScaledVector(_c, 5.5); }
    _a.y = (alive ? f.pos.y : f.pos.y - 16) + Math.sin(t * 2) * 0.5;
    if (t < 0.6) _a.y -= 14 * (1 - ease.out3(t / 0.6));
    pos.lerp(_a, 1 - Math.exp(-(swing > 0 ? 12 : 5) * dt));
    R.root.position.copy(pos);
    if (target && !target.dead && swing > 0) yaw = Math.atan2(target.pos.x - pos.x, target.pos.z - pos.z);
    else yaw = f.yaw;
    R.root.rotation.y += Math.atan2(Math.sin(yaw - R.root.rotation.y), Math.cos(yaw - R.root.rotation.y)) * Math.min(1, dt * 6);
    // руки
    if (swing > 0) {
      swing -= dt;
      const k = 1 - swing / 0.55;
      R.armR.rotation.x = k < 0.5 ? -2.8 * (k / 0.5) : -2.8 + 2.6 * ((k - 0.5) / 0.5);
      R.armL.rotation.x = -0.6;
      if (k >= 0.6 && !R.didHit) {
        R.didHit = true;
        if (target && !target.dead) {
          target.chestPos(_c);
          for (const o of f.enemiesNear(_c, 5.5)) G.hit(f, o, { dmg: 6, rag: 0.8, kb: { f: 32, up: 16 }, from: pos, hitstop: 0.08, fx: 'heavy', color: '#b080ff', shake: 0.4, sfx: 'heavy', guardDmg: 50 });
          _c.y = target.pos.y + 0.3;
          G.fx.ring(_c, '#c0a0ff', 1, 8, 0.3, { axis: 'y' });
          G.fx.dust(_c, 6, 3);
        }
      }
    } else {
      R.armR.rotation.x = -0.5 + Math.sin(t * 2.2) * 0.2; R.armL.rotation.x = -0.5 - Math.sin(t * 2.2) * 0.2;
      if (alive && atk <= 0) {
        target = null; let bd = 17;
        for (const o of G.fighters) if (f.isEnemy(o)) { const d = f.dist(o); if (d < bd) { bd = d; target = o; } }
        if (target) { swing = 0.55; R.didHit = false; atk = 1.7; G.sound('swing', pos, 0.6); } else atk = 0.3;
      }
    }
    if (Math.random() < 0.3) { _c.set(pos.x + rand(-3, 3), pos.y + rand(0, 4), pos.z + rand(-3, 3)); G.fx.norm.spawn(_c.x, _c.y, _c.z, 0, rand(1, 3), 0, '#1a1020', 0.5, 1.5, 3, 0.8); }
    if (!alive) {
      if (!R.sinkT) R.sinkT = 0;
      R.sinkT += dt;
      if (R.sinkT > 0.8) { R.busy = false; R.root.visible = false; R.sinkT = 0; f.rika = null; return false; }
    }
    return true;
  });
}

// Сброс доменов/Рики между матчами
export function resetSkills() {
  for (const list of [voidMeshes, shrines, rikas, rikaArms]) for (const o of list) {
    o.busy = false;
    if (o.dome) o.dome.visible = o.floor.visible = false;
    if (o.m) o.m.root.visible = o.disc.visible = false;
    if (o.root) o.root.visible = false;
  }
  G.shrineZone = G.voidZone = null;
}

// ======================= Таблица персонажей =======================
export const CHARS = {
  gojo: {
    id: 'gojo', name: 'The Strongest of Today', ru: 'Сильнейший сегодня', stance: 'gojo', m1: 'gojo',
    desc: 'Синий притягивает, Красный отбрасывает, Бесконечность гасит урон, телепорт за спину.',
    awakenDesc: 'Безграничная Пустота + Полый Фиолетовый',
    skills: [gBlue, gRed, gInfinity, gTeleport],
    awakenSkills: [null, null, null, gPurple],
    awaken: { label: 'Void', dur: 22, mods: { dmg: 1.1, cd: 0.7 }, aiRange: 18, cast: unlimitedVoid, tick: aura(['#bfe6ff', '#ffffff', '#5fb8ff']) },
  },
  sukuna: {
    id: 'sukuna', name: 'Strongest of History', ru: 'Сильнейший в истории', stance: 'sukuna', m1: 'sukuna',
    desc: 'Режущие волны, рассечение в упор, огненная стрела Фуга и натиск кулаками.',
    awakenDesc: 'Гробница Зла режет всех в зоне',
    skills: [sDismantle, sCleave, sFuga, sRush],
    awaken: { label: 'Shrine', dur: 18, mods: { dmg: 1.15, cd: 0.5 }, aiRange: 20, cast: malevolentShrine, tick: aura(['#ff3050', '#ffffff', '#ff8aa0']) },
  },
  yuji: {
    id: 'yuji', name: 'Vessel', ru: 'Сосуд', stance: 'fist', m1: 'fist',
    desc: 'Кулак с отложенным ударом, контр-кик, серия ударов и Чёрная Вспышка.',
    awakenDesc: 'Скорость + Чёрная Вспышка всегда',
    skills: [yDivergent, yManji, yStrikes, yBlackFlash],
    awaken: { label: 'Awaken', dur: 20, mods: { dmg: 1.2, cd: 0.6, speed: 1.35 }, aiRange: 14, cast: yujiAwaken, tick: aura(['#ff2040', '#1a0006', '#ff6040']) },
    speed: 1.08,
    bfChance: 0.15,
    m1Mult: 1.15,
    dmgTaken: 0.85,
    aiRush: true,
    onCounter: manjiCounter,
    blackFlashM1: true,
    blackFlash,
  },
  yuta: {
    id: 'yuta', name: 'Cursed Partner', ru: 'Проклятый напарник', stance: 'katana', m1: 'katana',
    desc: 'Катана и Рика: удар лапой, рывок с разрезом, «Стой!» и луч Чистой Любви.',
    awakenDesc: 'Рика полностью появляется и дерётся рядом',
    skills: [ySmash, yKDash, ySpeech, yLoveBeam],
    awaken: { label: 'Rika', dur: 20, mods: { dmg: 1.1, cd: 0.6 }, aiRange: 16, cast: yutaAwaken, tick: aura(['#c77dff', '#ffffff']) },
  },
};
export const CHAR_IDS = ['gojo', 'sukuna', 'yuji', 'yuta'];

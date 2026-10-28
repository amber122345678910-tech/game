// Персонажи и их навыки. Каждый навык: { id, label, tip?, cd, windup?, color, ai:{kind,min,max}, cast(f) }.
// У персонажа: special (кнопка R / звезда), skills[4], пробуждение awaken{…} с набором awakenSkills[4] и awakenSpecial.
import * as THREE from 'three';
import { G } from './ctx.js';
import { PX, POSE } from './anim.js';
import { buildRika, buildRikaArm, buildShrine } from './rig.js';
import { rand, clamp, tex, ease, angleDamp } from './util.js';
import {
  shrineM1, steelJab, sCleave, sDismantle, sOpen, sRush, sFurnace, sIncant, sKai, sSovereign, sWCS,
  yRika, yRSmash, yRLaunch, yRHaymaker, ySevering, yResolute, yOutburst, ySecondWind, outburstParry,
  yutaRika, yTLDownslam, yElbowRush, yCopySpeech, yEnergyRipple, yTLBeam, waveQuat,
} from './kits.js';

const V3 = THREE.Vector3;
const _a = new V3(), _b = new V3(), _c = new V3(), _d = new V3(), _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();
const ZV = new V3(0, 0, 1), YV = new V3(0, 1, 0);

// ---------- общие помощники ----------
export function aimFrom(f, origin, tgt, out, flat = false) {
  if (tgt) { tgt.chestPos(out).sub(origin); if (flat) out.y = 0; }
  else { f.fwd(out); }
  if (out.lengthSq() < 1e-4) f.fwd(out);
  return out.normalize();
}

// Снаряд: o = {owner, pos, dir, speed, range, radius, pierce, ghost (сквозь препятствия), onHit(f,p), onWorld(p), onStep(p,dt,t), onEnd(p)}
export function projectile(o) {
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
      if (!o.ghost && G.world.pointBlocked(p)) { o.onWorld?.(p); return finish(); }
      if (trav >= o.range) return finish();
    }
    o.onStep?.(p, dt, t, d);
    return true;
  });
}

export function beamHits(owner, origin, dir, len, radius) {
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

export function beamFX(origin, dir, len, radius, outer, core, life) {
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

export function lungeTo(f, tgt, maxD, stop = 3) {
  if (!tgt) return 0;
  const d = f.dist(tgt);
  return d < maxD ? Math.max(0, d - stop) : 0;
}

// ======================= GOJO (The Strongest of Today) =======================
const GJ = POSE.idle.gojo;
const P_POINT = PX(GJ, { rax: -1.6, raz: 0.05, twist: 0.35, cx: 0.05, hx: -0.05 });
const P_POINT2 = PX(GJ, { rax: -1.75, raz: 0.1, twist: 0.5, cx: 0.12, hy: -0.15 });
const P_RAISE = PX(GJ, { rax: -2.55, raz: 0.35, ray: 0.35, hx: -0.12, twist: -0.15, lax: 0.15, laz: 0.2 });
const KICK_WIND = PX(GJ, { rlx: 0.7, llx: -0.15, lean: 0.15, hy: -0.2, rax: -0.4, raz: -0.5, lax: -0.4, laz: 0.5, twist: -0.4 });
const KICK_UP = PX(GJ, { rlx: -2.6, llx: 0.3, lean: -0.4, cx: -0.15, hy: 0.15, rax: 0.5, raz: -0.9, lax: 0.4, laz: 0.9, twist: 0.25 });
const KICK_SIDE = PX(GJ, { rlx: -1.6, rlz: -0.9, llx: 0.2, lean: -0.2, twist: 0.9, cx: -0.1, rax: 0.5, raz: -1.0, lax: -0.6, laz: 0.8 });
const AXE_KICK = PX(POSE.air, { rlx: 0.9, llx: -1.2, cx: 0.45, hy: 0.1, rax: -2.4, raz: -0.3, lax: -2.4, laz: 0.3 });

// Осколки стекла в мире (Limitless)
function glassBurst(p, n = 16) {
  G.fx.particles(p, { n, color: ['#ffffff', '#cdefff', '#9fd8ff'], speed: 16, size: 0.55, size1: 0.15, life: 0.45, grav: 18 });
  for (let i = 0; i < 8; i++) {
    _b.set(rand(-1, 1), rand(-0.5, 1), rand(-1, 1)).normalize().multiplyScalar(rand(14, 26));
    G.fx.str.add(p, _b, '#e8f8ff', rand(0.18, 0.32), 0.07, rand(0.6, 1.4), { drag: 4, grav: 20 });
  }
}

// ---------- R: Limitless — телепорт к цели (−6 % пробуждения) ----------
const gLimitless = {
  id: 'limitless', label: 'Limitless', tip: 'TARGET', cd: 15, color: '#9fd8ff', ai: { kind: 'gap', min: 8, max: 40 },
  cast(f) {
    if (f.awakenPct() < 6) { if (f.isPlayer) G.hud.pop(f.headPos(_a), 'НУЖНО 6% ПРОБУЖДЕНИЯ', '#9fd8ff', 0.9); return false; }
    const tgt = f.camTarget(40);
    if (!tgt) return false;
    f.spendAwaken(6);
    f.faceTo(tgt.pos);
    const airAtCast = tgt.pos.y - G.world.groundAt(tgt.pos.x, tgt.pos.z, tgt.pos.y) > 3;
    G.sound('charge', f.pos, 0.25);
    f.startAction({
      name: 'limitless', dur: 0.45, windup: 0.45, frames: [[0, GJ], [0.45, P_RAISE], [1, P_RAISE]],
      update: (ff, dt, t, a) => {
        if (!tgt.dead && !ff.isPlayer) ff.faceTo(tgt.pos);
        ff.handPos('R', _a);
        if (Math.random() < 0.6) G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-1, 1), rand(1, 3), rand(-1, 1), '#bfe6ff', 0.9, 0.7, 0.1, 0.3);
        // кадр «до» для стеклянного экрана
        if (ff.isPlayer && t > 0.36 && !a.cap) { a.cap = true; G.hud.captureShatter(); }
      },
      onEnd: (ff) => {
        if (tgt.dead) return;
        ff.chestPos(_a); glassBurst(_a);
        if (ff.isPlayer) G.hud.shatter();
        G.sound('tp', ff.pos, 0.8); G.sound('block', ff.pos, 0.5);
        const gy = G.world.groundAt(tgt.pos.x, tgt.pos.z, tgt.pos.y);
        if (airAtCast || tgt.pos.y - gy > 3) {
          // цель в воздухе: появиться над ней и вбить в землю (8, истинный рэгдолл)
          ff.pos.set(tgt.pos.x, tgt.pos.y + 4.6, tgt.pos.z);
          ff.vel.set(0, 0, 0);
          ff.chestPos(_a); glassBurst(_a, 10);
          ff.startAction({
            name: 'limitlessKick', dur: 0.5, noGrav: true, frames: [[0, PX(AXE_KICK, { rlx: -1.8, llx: 0.4, cx: -0.2 })], [0.3, AXE_KICK], [1, AXE_KICK]],
            update: (f2) => { f2.vel.y = f2.action.t < 0.15 ? 0 : -30; },
            events: [[0.14, (f2) => {
              if (tgt.dead) return;
              G.hit(f2, tgt, { dmg: 8, melee: true, unblockable: true, bypassRag: true, trueRag: true, downslam: true, rag: 1.2, kb: { f: 4, up: -60 }, hitstop: 0.12, fx: 'heavy', color: '#9fd8ff', shake: 0.6, sfx: 'heavy' });
            }]],
          });
          return;
        }
        // сторона появления: у игрока — по повороту камеры к моменту «раскола» (развернул камеру — окажешься сзади)
        let sx = ff.aim.x, sz = ff.aim.z;
        if (!ff.isPlayer && Math.random() < 0.4 * (ff.brain?.skill ?? 0.5)) { sx = -sx; sz = -sz; }
        const l = Math.hypot(sx, sz) || 1;
        ff.pos.set(tgt.pos.x - (sx / l) * 3.2, tgt.pos.y, tgt.pos.z - (sz / l) * 3.2);
        G.world.collide(ff.pos, 1.2, 5);
        ff.pos.y = Math.max(ff.pos.y, G.world.groundAt(ff.pos.x, ff.pos.z, ff.pos.y + 3));
        ff.vel.set(0, 0, 0);
        ff.faceTo(tgt.pos);
        ff.iframes = Math.max(ff.iframes, 0.15);
        ff.chestPos(_a); glassBurst(_a, 10); G.fx.ring(_a, '#ffffff', 1, 5, 0.22, { a0: 0.8 });
        ff.startAction({ name: 'land', dur: 0.16, pose: (f2, a, out) => out.set(P_RAISE) });
      },
    });
  },
};

// ---------- 1: Lapse Blue — вихрь притягивает цель и неблокируемый пинок вверх ----------
function blueVortex(color = '#5fb8ff') {
  const core = G.fx.pool('sphere'), glow = G.fx.pool('glow'), r1 = G.fx.pool('ring'), r2 = G.fx.pool('ring');
  core.mat.color.set('#2d8dff'); glow.mat.color.set(color); r1.mat.color.set('#bff0ff'); r2.mat.color.set('#3f9cff');
  return {
    t: 0,
    set(p, s, dt) {
      this.t += dt;
      const t = this.t, pulse = 1 + Math.sin(t * 30) * 0.08;
      core.obj.position.copy(p); core.obj.scale.setScalar(1.2 * s * pulse); core.mat.opacity = 0.85;
      glow.obj.position.copy(p); glow.obj.scale.setScalar(9 * s);
      r1.obj.position.copy(p); r1.obj.scale.setScalar(3.2 * s); r1.obj.rotation.set(t * 4, t * 3, 0); r1.mat.opacity = 0.7;
      r2.obj.position.copy(p); r2.obj.scale.setScalar(4.4 * s); r2.obj.rotation.set(-t * 3, 0, t * 5); r2.mat.opacity = 0.5;
      for (let i = 0; i < 2; i++) {
        _c.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
        _b.copy(p).addScaledVector(_c, rand(5, 8) * s);
        _c.multiplyScalar(-rand(16, 24) * s);
        G.fx.add.spawn(_b.x, _b.y, _b.z, _c.x, _c.y, _c.z, i ? '#7cd8ff' : '#ffffff', 1, 0.6, 0.1, 0.32);
      }
    },
    free() { G.fx.release(core); G.fx.release(glow); G.fx.release(r1); G.fx.release(r2); },
  };
}
const gLapseBlue = {
  id: 'lblue', label: 'Lapse Blue', tip: 'TARGET', cd: 13, windup: 0.3, color: '#3f8cff', ai: { kind: 'ranged', min: 3, max: 33 },
  cast(f) {
    const tgt = f.camTarget(35);
    if (!tgt) return false;
    f.faceTo(tgt.pos);
    const vx = blueVortex();
    const vp = new V3();
    let freed = false;
    const free = () => { if (!freed) { freed = true; vx.free(); } };
    G.sound('charge', f.pos, 0.45);
    f.startAction({
      name: 'lblue', dur: 1.35, windup: 0.3, keepVel: false,
      frames: [[0, GJ], [0.12, P_POINT], [0.6, P_POINT], [0.68, KICK_WIND], [0.76, KICK_UP], [0.92, KICK_UP], [1, GJ]],
      update: (ff, dt, t, a) => {
        if (a.caught && !tgt.dead) {
          ff.fwd(_b);
          _a.set(ff.pos.x + _b.x * 3.6, ff.pos.y + 1.3, ff.pos.z + _b.z * 3.6);
          if (t < 1.02) {
            tgt.pos.lerp(_a, 1 - Math.exp(-(t < 0.8 ? 7 : 20) * dt));
            tgt.vel.set(0, 0, 0); tgt.suspend = 0.25; tgt.stun = Math.max(tgt.stun, 0.4);
          }
          tgt.chestPos(vp);
        } else if (!tgt.dead && t < 0.3) { tgt.chestPos(vp); ff.faceTo(tgt.pos); }
        if (!freed) {
          const grow = Math.min(1, t / 0.2);
          vx.set(vp, (a.caught ? 0.8 : 0.6) * grow * (t > 1.0 ? Math.max(0, 1 - (t - 1.0) / 0.12) : 1), dt);
          if (t > 1.12) free();
        }
      },
      events: [
        [0.3, (ff, a) => {
          if (tgt.dead || ff.dist(tgt) > 40) { free(); a.dur = 0.6; return; }
          const r = G.hit(ff, tgt, { dmg: 5, block360: true, bypassRag: true, noPush: true, stun: 1.2, hitstop: 0.05, fx: 'energy', color: '#5fb8ff', shake: 0.2, sfx: 'hit', noCounter: true });
          if (r === 'hit' || r === 'break') {
            a.caught = true;
            tgt.rag = false; tgt.ragTrue = false; tgt.down = 0; tgt.interrupt(true);
            G.sound('tp', tgt.pos, 0.5);
          } else { free(); a.dur = r === 'blocked' ? 0.9 : 0.6; a.locked = true; tgt.chestPos(_a); G.fx.burst(_a, '#9fd8ff', 6, 0.2); }
        }],
        [1.0, (ff, a) => {
          if (!a.caught || tgt.dead || ff.dist(tgt) > 7) return;
          ff.iframes = Math.max(ff.iframes, 0.3);
          G.hit(ff, tgt, { dmg: 7.5, melee: true, unblockable: true, bypassRag: true, rag: 1.2, kb: { f: 16, up: 38 }, hitstop: 0.1, fx: 'heavy', color: '#7cc8ff', shake: 0.5, sfx: 'heavy' });
          tgt.chestPos(_a); G.fx.ring(_a, '#9fd8ff', 1, 7, 0.3, { a0: 0.9 });
        }],
      ],
      onCancel: free,
      onEnd: free,
    });
  },
};

// ---------- 2: Reversal Red — красная сфера 40 стадов, взрыв 15 стадов ----------
function redBlast(owner, p, R, o) {
  for (const e of owner.enemiesNear(p, R, R + 2)) {
    G.hit(owner, e, { from: p, noPush: true, bypassRag: true, ...o });
  }
  G.fx.burst(p, '#ffffff', R * 1.3, 0.2);
  G.fx.sphere(p, '#ff2020', R * 0.25, R * 0.85, 0.32, { a0: 0.85 });
  G.fx.sphere(p, '#ff6a50', 1, R * 0.5, 0.2, { a0: 0.9 });
  G.fx.ring(p, '#ffffff', R * 0.4, R * 1.1, 0.35, { a0: 1 });
  G.fx.ring(p, '#ff2a2a', 1, R * 1.4, 0.45, { axis: 'y', a0: 0.9 });
  // «блочный» взрыв: красные кубы
  G.fx.debris(p, 14, ['#ff2020', '#c00818', '#ff6040', '#ffffff'], R * 3.2, [0.8, 1.9]);
  G.fx.sparks(p, null, '#ff5040', 16, 60, { spread: 1 });
  G.fx.particles(p, { n: 22, color: ['#ff3020', '#ffffff', '#ff8060'], speed: R * 3, size: 1.5, life: 0.5 });
  G.fx.particles(p, { n: 10, normal: true, color: '#2a2024', speed: 8, up: 5, size: 2.2, size1: 5, life: 1.1, alpha: 0.5 });
  const gy = G.world.groundAt(p.x, p.z, p.y);
  if (p.y - gy < 6) { _a.set(p.x, gy + 0.3, p.z); G.fx.debris(_a, 10, ['#2b2b2b', '#3a3a40', '#d8d8d8']); G.fx.dust(_a, 10, 3.5); G.fx.crater(_a, R * 0.8, 5); }
  G.shake(0.65, p);
  G.sound('boom', p, 0.9);
  G.flashNear(p, '#ff3030', 0.3, 34);
}
const gRed = {
  id: 'red', label: 'Reversal Red', cd: 20, windup: 0.35, color: '#ff3b3b', ai: { kind: 'ranged', min: 4, max: 38 },
  cast(f) {
    const tgt = f.camTarget(45);
    if (tgt) f.faceTo(tgt.pos);
    const orb = G.fx.pool('glow'), core = G.fx.pool('sphere'), light = G.fx.pool('glow'), floor = G.fx.pool('ring');
    orb.mat.color.set('#ff3030'); core.mat.color.set('#ff5040'); light.mat.color.set('#ff2a1a'); floor.mat.color.set('#ff2020');
    floor.obj.rotation.set(-Math.PI / 2, 0, 0);
    let freed = false;
    const cleanup = () => { if (!freed) { freed = true; G.fx.release(orb); G.fx.release(core); G.fx.release(light); G.fx.release(floor); } };
    f.startAction({
      name: 'red', dur: 0.62, windup: 0.35,
      frames: [[0, GJ], [0.3, P_POINT2], [0.56, P_POINT2], [0.66, PX(P_POINT2, { cx: -0.1, rax: -1.9 })], [1, GJ]],
      update: (ff, dt, t) => {
        if (t < 0.35 && !freed) {
          const g = t / 0.35;
          ff.handPos('R', _a);
          orb.obj.position.copy(_a); orb.obj.scale.setScalar(1.5 + g * 4); orb.mat.opacity = 0.95;
          core.obj.position.copy(_a); core.obj.scale.setScalar(0.25 + g * 0.45);
          ff.chestPos(_b); light.obj.position.copy(_b); light.obj.scale.setScalar(10 + g * 12); light.mat.opacity = 0.35 * g;
          // красный оттенок земли вокруг
          floor.obj.position.set(ff.pos.x, ff.pos.y + 0.15, ff.pos.z); floor.obj.scale.setScalar(2 + g * 7); floor.mat.opacity = 0.55 * g;
          if (Math.random() < 0.7) { _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize(); _c.copy(_a).addScaledVector(_b, 2.6); _b.multiplyScalar(-9); G.fx.add.spawn(_c.x, _c.y, _c.z, _b.x, _b.y, _b.z, '#ff6040', 1, 0.6, 0.1, 0.28); }
          if (tgt && !tgt.dead) ff.faceTo(tgt.pos);
        }
      },
      events: [[0.35, (ff) => {
        cleanup();
        ff.handPos('R', _a);
        const origin = _a.clone();
        const dir = aimFrom(ff, origin, tgt && !tgt.dead ? tgt : null, new V3());
        if (!tgt) { if (ff.isPlayer) ff.aimDir(origin, dir); else { dir.y = 0; dir.normalize(); } }
        const ball = G.fx.pool('sphere'), bg = G.fx.pool('glow');
        ball.mat.color.set('#ff2a2a'); bg.mat.color.set('#ff5a3a');
        ff.vel.addScaledVector(dir, -10);
        G.sound('beam', ff.pos, 0.4);
        G.fx.burst(origin, '#ff6040', 6, 0.15);
        projectile({
          owner: ff, pos: origin, dir, speed: 57, range: 40, radius: 1.3,
          onHit: () => {},
          onStep: (p) => {
            ball.obj.position.copy(p); ball.obj.scale.setScalar(0.9 + Math.sin(G.time * 40) * 0.1);
            bg.obj.position.copy(p); bg.obj.scale.setScalar(6);
            G.fx.add.spawn(p.x, p.y, p.z, rand(-3, 3), rand(-3, 3), rand(-3, 3), '#ff4030', 0.9, 1.4, 0.2, 0.25);
          },
          onEnd: (p) => {
            G.fx.release(ball); G.fx.release(bg);
            redBlast(ff, p, 15, { dmg: 12.5, chip: 0.5, rag: 1.25, kb: { f: 66, up: 20 }, fx: 'heavy', color: '#ff5050', hitstop: 0.1, shake: 0.6, sfx: 'heavy' });
          },
        });
      }]],
      onCancel: cleanup,
    });
    G.sound('charge', f.pos, 0.35);
  },
};

// ---------- 3: Rapid Punches — захват вертушкой, шквал 15 ударов, 3 тяжёлых, финал ----------
const SPIN_KICK = PX(GJ, { rlx: -1.5, rlz: -0.6, llx: 0.2, lean: -0.15, twist: 1.2, cx: -0.1, rax: 0.3, raz: -1.2, lax: -0.3, laz: 1.0, hy: 0.05 });
const GOJO_BARRAGE = { n: 15, gap: 0.042, dmg: 0.5, heavies: 3, heavyGap: 0.17, heavyDmg: 1.5, finalGap: 0.24, finalDmg: 4, finalRag: 1.1, finalKb: { f: 48, up: 16 }, arcs: '#fff4b0', color: '#fff4b0' };
const gRapid = {
  id: 'rapid', label: 'Rapid Punches', cd: 15, windup: 0.32, color: '#fff4b0', ai: { kind: 'melee', min: 0, max: 6 },
  cast(f) {
    const tgt = f.autoTarget(9, 0.4);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(4, lungeTo(f, tgt, 9, 3)) / 0.28;
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    const y0 = f.yaw;
    f.startAction({
      name: 'rapid', dur: 0.7, keepVel: true, windup: 0.32, poseSpeed: 28,
      pose: (ff, a, out) => out.set(a.t < 0.12 ? KICK_WIND : SPIN_KICK),
      update: (ff, dt, t) => {
        if (t < 0.28) { ff.vel.x = dx * lunge; ff.vel.z = dz * lunge; } else ff.friction(dt, 14);
        // вертушка
        if (t > 0.08 && t < 0.36) ff.yaw = y0 + ((t - 0.08) / 0.28) * Math.PI * 2;
        else if (t >= 0.36) ff.yaw = y0;
      },
      events: [[0.32, (ff, a) => {
        ff.yaw = y0;
        const v = ff.meleeTargets(5.6, 0.3)[0];
        G.sound('swing', ff.pos, 0.6);
        if (!v) return;
        const r = G.hit(ff, v, { dmg: 1.25, melee: true, unblockable: true, stun: 1.5, push: 1, hitstop: 0.07, fx: 'hit', shake: 0.25, sfx: 'hit' });
        if (r === 'hit' || r === 'break') rushBarrage(ff, v, GOJO_BARRAGE);
      }]],
    });
  },
};

// ---------- 4: Twofold Kick — пинок вверх (6) подвешивает, через ≈1.1 с неблокируемый второй (4) ----------
const gTwofold = {
  id: 'twofold', label: 'Twofold Kick', cd: 18, windup: 0.34, color: '#bfe6ff', ai: { kind: 'melee', min: 0, max: 6 },
  cast(f) {
    const tgt = f.autoTarget(8, 0.4);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(3, lungeTo(f, tgt, 8, 3)) / 0.3;
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    f.startAction({
      name: 'twofold', dur: 1.45, keepVel: true, windup: 0.34,
      frames: [[0, GJ], [0.18, KICK_WIND], [0.25, KICK_UP], [0.5, PX(KICK_UP, { rlx: -1.2 })], [0.66, KICK_WIND], [0.76, KICK_SIDE], [0.9, KICK_SIDE], [1, GJ]],
      update: (ff, dt, t, a) => {
        if (t < 0.34) { ff.vel.x = dx * lunge; ff.vel.z = dz * lunge; } else ff.friction(dt, 12);
        const v = a.v;
        if (v && !v.dead && t < 1.1) {
          ff.fwd(_b);
          const h = 3.2 + Math.min(1, (t - 0.36) / 0.3) * 3.2;
          _a.set(ff.pos.x + _b.x * 3.2, ff.pos.y + h, ff.pos.z + _b.z * 3.2);
          v.pos.lerp(_a, 1 - Math.exp(-10 * dt)); v.vel.set(0, 0, 0); v.suspend = 0.2; v.stun = Math.max(v.stun, 0.4);
          if (Math.random() < 0.3) { v.chestPos(_c); G.fx.add.spawn(_c.x + rand(-1, 1), _c.y + rand(-1, 1), _c.z + rand(-1, 1), 0, 1, 0, '#bfe6ff', 0.8, 0.6, 0.1, 0.3); }
        }
      },
      events: [
        [0.36, (ff, a) => {
          const v = ff.meleeTargets(5.6, 0.35, 6)[0];
          G.sound('swing', ff.pos, 0.6);
          if (!v) { a.dur = 0.8; return; }
          const r = G.hit(ff, v, { dmg: 6, melee: true, bypassRag: true, stun: 1.3, push: 0, hitstop: 0.09, fx: 'heavy', color: '#bfe6ff', shake: 0.4, sfx: 'heavy' });
          if (r === 'hit' || r === 'break') { a.v = v; v.rag = false; v.ragTrue = false; v.down = 0; ff.iframes = Math.max(ff.iframes, 0.3); }
          else if (r === 'blocked') { a.dur = 1.0; a.locked = true; }
          else a.dur = 0.8;
        }],
        [1.1, (ff, a) => {
          const v = a.v;
          if (!v || v.dead || ff.dist(v) > 8) return;
          ff.iframes = Math.max(ff.iframes, 0.25);
          G.hit(ff, v, { dmg: 4, melee: true, unblockable: true, bypassRag: true, rag: 1.3, kb: { f: 12, up: 44 }, hitstop: 0.12, fx: 'heavy', color: '#9fd8ff', shake: 0.55, sfx: 'heavy' });
          v.chestPos(_a); G.fx.ring(_a, '#ffffff', 1, 7, 0.3, { a0: 0.9 }); G.fx.sparks(_a, null, '#fff6d0', 10, 44, { spread: 1 });
        }],
      ],
    });
  },
};

// ======================= Six Eyes (пробуждение Сильнейшего) =======================
// 1: Lapse Blue MAX — тёмно-синий шар под управлением (идёшь/поворачиваешь камеру — шар следует), 20 тиков по 2.2;
// под шаром — белый круг «стёртой» земли. В воздухе заклинатель зависает, пока шар жив.
const gBlueMax = {
  id: 'bluemax', label: 'Lapse Blue MAX', cd: 17, windup: 0.2, color: '#2d3dff', ai: { kind: 'ranged', min: 2, max: 28 },
  cast(f) {
    const tgt = f.camTarget(30);
    if (tgt) f.faceTo(tgt.pos);
    const air = f.airborne();
    f.startAction({
      name: 'bluemax', dur: 0.45, noGrav: air, frames: [[0, GJ], [0.4, P_POINT], [1, P_POINT]],
      update: (ff) => { if (air) ff.vel.y *= 0.8; },
      events: [[0.2, (ff) => spawnBlueMax(ff, tgt, air)]],
    });
    G.sound('charge', f.pos, 0.5);
  },
};
function navyOrb() {
  const core = G.fx.pool('sphereN'), shell = G.fx.pool('sphere'), glow = G.fx.pool('glow'), r1 = G.fx.pool('ring'), r2 = G.fx.pool('ring');
  core.mat.color.set('#0c1458'); shell.mat.color.set('#2a46ff'); glow.mat.color.set('#2f45ff'); r1.mat.color.set('#a8b8ff'); r2.mat.color.set('#3a56ff');
  return {
    t: 0,
    set(p, s, dt) {
      this.t += dt;
      const t = this.t, pulse = 1 + Math.sin(t * 26) * 0.06;
      core.obj.position.copy(p); core.obj.scale.setScalar(2.4 * s * pulse); core.mat.opacity = 0.93;
      shell.obj.position.copy(p); shell.obj.scale.setScalar(3.1 * s * pulse); shell.mat.opacity = 0.35;
      glow.obj.position.copy(p); glow.obj.scale.setScalar(13 * s);
      r1.obj.position.copy(p); r1.obj.scale.setScalar(4.6 * s); r1.obj.rotation.set(t * 4, t * 3, 0); r1.mat.opacity = 0.65;
      r2.obj.position.copy(p); r2.obj.scale.setScalar(6 * s); r2.obj.rotation.set(-t * 3, 0, t * 5); r2.mat.opacity = 0.45;
      // искры, тёмно-синие «щупальца» и ветер, засасываемый к центру
      for (let i = 0; i < 2; i++) {
        _c.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
        _b.copy(p).addScaledVector(_c, rand(6, 10) * s);
        _c.multiplyScalar(-rand(18, 28) * s);
        G.fx.add.spawn(_b.x, _b.y, _b.z, _c.x, _c.y, _c.z, i ? '#9fd8ff' : '#ffffff', 1, 0.7, 0.1, 0.32);
      }
      if (Math.random() < 0.35) { _c.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize(); _b.copy(p).addScaledVector(_c, rand(4, 7) * s); G.fx.bolt(p, _b, '#0a1250', { dark: true, segs: 3, jag: 0.6, life: 0.12, w: 0.18 }); }
      if (Math.random() < 0.5) { _c.set(rand(-1, 1), rand(-0.3, 0.6), rand(-1, 1)).normalize(); _b.copy(p).addScaledVector(_c, rand(8, 12) * s); G.fx.str.add(_b, _c.multiplyScalar(-40 * s), '#dff4ff', 0.25, 0.08, 3, { drag: 2 }); }
    },
    free() { for (const it of [core, shell, glow, r1, r2]) G.fx.release(it); },
  };
}
function spawnBlueMax(f, tgt, air) {
  const orb = navyOrb();
  const disc = G.fx.pool('disc'); disc.mat.color.set('#f2f4fa');
  const center = new V3();
  let dist = 12;
  if (tgt && !tgt.dead) { tgt.chestPos(center); dist = clamp(f.dist(tgt), 6, 26); }
  else { f.chestPos(center); f.fwd(_a); center.addScaledVector(_a, dist); }
  let t = 0, tick = 0, ticks = 0;
  const L = 3.4;
  G.addTask((dt) => {
    t += dt; tick -= dt;
    if (G.matchOver || f.dead) { orb.free(); G.fx.release(disc); return false; }
    // управление: у игрока — точка по лучу камеры на прежней дистанции, у бота — его цель
    if (!f.isPlayer && tgt && !tgt.dead && f.dist(tgt) < 40) tgt.chestPos(_a);
    else {
      f.chestPos(_a); f.aimDir(_a, _b); _a.addScaledVector(_b, dist);
      const g = G.world.groundAt(_a.x, _a.z, _a.y);
      if (_a.y < g + 2.5) _a.y = g + 2.5;
    }
    center.lerp(_a, 1 - Math.exp(-3.5 * dt));
    if (air && !f.rag && t < L) f.suspend = Math.max(f.suspend, 0.1);
    const grow = Math.min(1, t / 0.25), fade = t > L - 0.25 ? Math.max(0, (L - t) / 0.25) : 1;
    orb.set(center, grow * fade, dt);
    const gy = G.world.groundAt(center.x, center.z, center.y);
    const near = 1 - clamp((center.y - gy - 3) / 10, 0, 1);
    disc.obj.position.set(center.x, gy + 0.14, center.z); disc.obj.scale.setScalar(6.5 * grow * fade * (0.5 + 0.5 * near)); disc.mat.opacity = 0.9 * near;
    if (near > 0.3 && Math.random() < 0.4) { const an = rand(0, 6.28), rr = rand(5, 9); _a.set(center.x + Math.cos(an) * rr, gy + 0.4, center.z + Math.sin(an) * rr); G.fx.norm.spawn(_a.x, _a.y, _a.z, -Math.cos(an) * 10, 6, -Math.sin(an) * 10, Math.random() < 0.5 ? '#2b2b2b' : '#d8d8d8', 1, 0.7, 0.4, 0.5, 0, 0); }
    for (const o of f.enemiesNear(center, 15, 12)) {
      o.chestPos(_a); _b.subVectors(center, _a); const d = _b.length();
      if (d > 0.8) { _b.multiplyScalar(1 / d); const k = (o.rag ? 34 : 80) * dt; o.vel.x += _b.x * k; o.vel.z += _b.z * k; o.vel.y += _b.y * k * 0.6; if (d < 3) { o.vel.multiplyScalar(0.85); } }
    }
    if (tick <= 0 && ticks < 20 && t > 0.2) {
      tick = 0.14; ticks++;
      for (const o of f.enemiesNear(center, 6.5, 7)) G.hit(f, o, { dmg: 2.2, unblockable: true, bypassRag: true, stun: 0.4, hitstop: 0.015, fx: 'energy', color: '#4a64ff', shake: 0.06, sfx: 'hit', vol: 0.3, from: center, noPush: true });
    }
    if (t >= L) { orb.free(); G.fx.release(disc); return false; }
    return true;
  });
}
// 2: Reversal Red MAX — заряд 1.1 с, пробивающая сфера до 100 стадов, 30→7 по дальности
const gRedMax = {
  id: 'redmax', label: 'Reversal Red MAX', cd: 10, windup: 1.1, color: '#ff2050', ai: { kind: 'ranged', min: 5, max: 75 },
  cast(f) {
    let tgt = f.camTarget(100);
    if (tgt) f.faceTo(tgt.pos);
    const orb = G.fx.pool('glow'); orb.mat.color.set('#ff3060');
    let freed = false;
    const cleanup = () => { if (!freed) { freed = true; G.fx.release(orb); } };
    G.sound('charge', f.pos, 0.7);
    f.startAction({
      name: 'redmax', dur: 1.35, windup: 1.1,
      frames: [[0, GJ], [0.2, P_POINT2], [0.8, P_POINT2], [0.86, PX(P_POINT2, { cx: -0.15, rax: -1.95 })], [1, GJ]],
      update: (ff, dt, t) => {
        if (tgt && tgt.dead) tgt = null;
        if (t < 1.1) {
          if (tgt) ff.faceTo(tgt.pos);
          ff.handPos('R', _a);
          orb.obj.position.copy(_a); orb.obj.scale.setScalar(2 + (t / 1.1) * 6);
          // красно-розовые молнии по телу
          if (Math.random() < 0.8) {
            _b.set(ff.pos.x + rand(-1.4, 1.4), ff.pos.y + rand(0.5, 5.5), ff.pos.z + rand(-1.4, 1.4));
            _c.copy(_b).add(_a.set(rand(-1.5, 1.5), rand(-1.5, 1.5), rand(-1.5, 1.5)));
            G.fx.bolt(_b, _c, Math.random() < 0.5 ? '#ff4080' : '#ffd0e0', { segs: 3, jag: 0.5, life: 0.09, w: 0.1 });
          }
        }
      },
      events: [[1.1, (ff) => {
        cleanup();
        ff.handPos('R', _a);
        const origin = _a.clone();
        const dir = aimFrom(ff, origin, tgt, new V3());
        if (!tgt) { if (ff.isPlayer) ff.aimDir(origin, dir); else { dir.y = 0; dir.normalize(); } }
        const ball = G.fx.pool('sphere'), bg = G.fx.pool('glow');
        ball.mat.color.set('#ff2050'); bg.mat.color.set('#ff6a8a');
        ff.vel.addScaledVector(dir, -16);
        G.sound('beam', ff.pos, 0.9); G.sound('boom', ff.pos, 0.4);
        G.fx.burst(origin, '#ff90b0', 12, 0.2);
        G.fx.ring(origin, '#ff4070', 1, 9, 0.3, { axis: dir.clone() });
        G.shake(0.4, ff.pos);
        let trav = 0;
        projectile({
          owner: ff, pos: origin, dir, speed: 140, range: 100, radius: 2.2, pierce: true, ghost: true,
          onHit: (o, p) => {
            const k = clamp(p.distanceTo(origin) / 100, 0, 1);
            G.hit(ff, o, { dmg: 30 - 23 * k, unblockable: true, bypassRag: true, rag: 1.3, kb: { f: 80 - 30 * k, up: 18 }, hitstop: 0.12, fx: 'heavy', color: '#ff4070', shake: 0.7, sfx: 'boom', from: p });
          },
          onStep: (p, dt) => {
            trav += 140 * dt;
            ball.obj.position.copy(p); ball.obj.scale.setScalar(1.6);
            bg.obj.position.copy(p); bg.obj.scale.setScalar(9);
            if (Math.random() < 0.5) G.fx.ring(p, '#ff6080', 1, 4, 0.25, { axis: dir.clone(), a0: 0.5 });
            G.fx.add.spawn(p.x + rand(-1, 1), p.y + rand(-1, 1), p.z + rand(-1, 1), rand(-4, 4), rand(-4, 4), rand(-4, 4), Math.random() < 0.5 ? '#ff4070' : '#ffe0ea', 1, 1.8, 0.2, 0.3);
            if (p.y < 7 && Math.random() < 0.4) { _a.set(p.x, 0.4, p.z); G.fx.debris(_a, 1, ['#2b2b2b', '#3a3a40']); }
          },
          onWorld: (p) => { G.fx.burst(p, '#ff6080', 10, 0.2); G.fx.debris(p, 8, ['#2b2b2b', '#ff4060']); },
          onEnd: () => { G.fx.release(ball); G.fx.release(bg); },
        });
      }]],
      onCancel: cleanup,
    });
  },
};

// 3: Hollow Purple — ≈3 с подготовки: синий и красный в руках, слияние (≈0.7 с видно), затем огромная
// пурпурная масса несётся вперёд, стирая всё (неблокируемо; 45 для баланса FFA, в JJS — 70)
const gPurple = {
  id: 'purple', label: 'Hollow Purple', cd: 40, windup: 3.0, color: '#b04dff', ai: { kind: 'ranged', min: 6, max: 70 },
  cast(f) {
    let tgt = f.camTarget(80);
    if (tgt) f.faceTo(tgt.pos);
    const bl = G.fx.pool('glow'), rd = G.fx.pool('glow'), blc = G.fx.pool('sphere'), rdc = G.fx.pool('sphere'), pu = G.fx.pool('sphere'), pg = G.fx.pool('glow');
    bl.mat.color.set('#3f8cff'); rd.mat.color.set('#ff3030'); blc.mat.color.set('#5aa8ff'); rdc.mat.color.set('#ff4a3a'); pu.mat.color.set('#a040ff'); pg.mat.color.set('#c070ff');
    pu.obj.visible = pg.obj.visible = false;
    let freed = false;
    const cleanup = () => { if (!freed) { freed = true; for (const it of [bl, rd, blc, rdc, pu, pg]) G.fx.release(it); } };
    const SPREAD = PX(GJ, { lax: -1.3, laz: 1.1, rax: -1.3, raz: -1.1, hy: -0.2, hx: -0.1 });
    const JOIN = PX(GJ, { lax: -1.6, laz: -0.35, rax: -1.6, raz: 0.35, hy: -0.3, cx: 0.15 });
    const FIRE = PX(GJ, { rax: -1.7, raz: 0.1, lax: 0.2, laz: 0.3, twist: 0.55, cx: 0.25, hy: -0.35, llx: -0.4, rlx: 0.4 });
    const front = new V3();
    const T1 = 1.4, T2 = 2.1, T3 = 3.0, D = 3.55;
    G.sound('charge', f.pos, 0.7);
    G.callout(f, 'Hollow Purple', '#c070ff');
    f.startAction({
      name: 'purple', dur: D, armor: true, windup: T3,
      frames: [[0, POSE.idle.gojo], [0.08, SPREAD], [0.38, SPREAD], [0.5, JOIN], [0.8, JOIN], [0.85, FIRE], [1, FIRE]],
      update: (ff, dt, t) => {
        if (tgt && (tgt.dead || ff.dist(tgt) > 90)) tgt = null;
        if (t < T3) {
          if (tgt) ff.yaw = angleDamp(ff.yaw, Math.atan2(tgt.pos.x - ff.pos.x, tgt.pos.z - ff.pos.z), 4, dt);
          else if (ff.isPlayer) ff.yaw = angleDamp(ff.yaw, Math.atan2(ff.aim.x, ff.aim.z), 8, dt);
        }
        ff.chestPos(front); ff.fwd(_b); front.addScaledVector(_b, 3.2); front.y += 0.8;
        if (t < T2) {
          const k = Math.min(1, t / T1);
          ff.handPos('L', _a); ff.handPos('R', _c);
          if (t > T1) { const m = ease.smooth((t - T1) / (T2 - T1)); _a.lerp(front, m); _c.lerp(front, m); }
          bl.obj.position.copy(_a); bl.obj.scale.setScalar(2 + k * 5); blc.obj.position.copy(_a); blc.obj.scale.setScalar(0.3 + k * 0.5);
          rd.obj.position.copy(_c); rd.obj.scale.setScalar(2 + k * 5); rdc.obj.position.copy(_c); rdc.obj.scale.setScalar(0.3 + k * 0.5);
          for (const [p, col] of [[_a, '#7cc8ff'], [_c, '#ff6a5a']]) {
            _d.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
            G.fx.add.spawn(p.x + _d.x * 3, p.y + _d.y * 3, p.z + _d.z * 3, -_d.x * 12, -_d.y * 12, -_d.z * 12, col, 1, 0.6, 0.1, 0.25);
          }
        } else if (t < T3) {
          if (bl.obj.visible) { bl.obj.visible = rd.obj.visible = blc.obj.visible = rdc.obj.visible = false; pu.obj.visible = pg.obj.visible = true; G.fx.burst(front, '#e0b0ff', 12, 0.25); G.sound('tp', ff.pos, 0.6); }
          const k = (t - T2) / (T3 - T2);
          pu.obj.position.copy(front); pu.obj.scale.setScalar(0.6 + k * 2.4 + Math.sin(t * 40) * 0.08); pu.mat.opacity = 0.9;
          pg.obj.position.copy(front); pg.obj.scale.setScalar(5 + k * 12);
          if (Math.random() < 0.6) { _d.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize(); _a.copy(front).addScaledVector(_d, rand(2.5, 5)); G.fx.bolt(front, _a, Math.random() < 0.5 ? '#c070ff' : '#ffffff', { segs: 3, jag: 0.5, life: 0.08, w: 0.12 }); }
          G.fx.particles(front, { n: 2, color: ['#c070ff', '#ffffff'], speed: 12, size: 0.8, life: 0.3 });
        }
      },
      events: [[T3, (ff) => {
        cleanup();
        const dir = new V3();
        if (tgt && !tgt.dead) tgt.chestPos(dir).sub(front);
        else if (ff.isPlayer) ff.aimDir(front, dir);
        else ff.fwd(dir);
        const hl = Math.hypot(dir.x, dir.z) || 1;
        dir.y = clamp(dir.y, -hl * 0.3, hl * 0.3);
        dir.normalize();
        const ball = G.fx.pool('sphere'), core = G.fx.pool('sphere'), halo = G.fx.pool('glow');
        ball.mat.color.set('#9a2cff'); core.mat.color.set('#ffe8ff'); halo.mat.color.set('#c070ff');
        G.fx.burst(front, '#e0b0ff', 26, 0.3);
        G.fx.ring(front, '#c070ff', 2, 18, 0.45, { axis: dir.clone() });
        G.fx.ring(front, '#ffffff', 1, 11, 0.32, { axis: dir.clone() });
        G.shake(0.8, ff.pos);
        G.sound('beam', ff.pos, 1.0); G.sound('boom', ff.pos, 0.6);
        G.flashNear(ff.pos, '#b060ff', 0.45, 60);
        ff.vel.addScaledVector(dir, -18);
        projectile({
          owner: ff, pos: front.clone().addScaledVector(dir, 2), dir, speed: 78, range: 90, radius: 6, pierce: true, ghost: true,
          onHit: (o) => G.hit(ff, o, { dmg: 45, rag: 1.6, kb: { f: 80, up: 26 }, pierce: true, unblockable: true, bypassRag: true, noCounter: true, hitstop: 0.12, fx: 'energy', color: '#c070ff', shake: 0.9, sfx: 'boom', from: ff.pos }),
          onStep: (p, dt2, tt) => {
            const g = Math.min(1, tt / 0.15);
            ball.obj.position.copy(p); ball.obj.scale.setScalar(5.5 * g + Math.sin(tt * 50) * 0.2); ball.mat.opacity = 0.75;
            core.obj.position.copy(p); core.obj.scale.setScalar(2.6 * g); core.mat.opacity = 0.9;
            halo.obj.position.copy(p); halo.obj.scale.setScalar(26 * g);
            for (let i = 0; i < 2; i++) { _d.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize(); _a.copy(p).addScaledVector(_d, rand(5, 9)); G.fx.bolt(p, _a, i ? '#ffffff' : '#c070ff', { segs: 4, jag: 0.8, life: 0.1, w: 0.2 }); }
            G.fx.add.spawn(p.x + rand(-5, 5), p.y + rand(-5, 5), p.z + rand(-5, 5), -dir.x * 20, -dir.y * 20, -dir.z * 20, Math.random() < 0.5 ? '#c070ff' : '#ffffff', 1, 2.2, 0.3, 0.4);
            const gy = G.world.groundAt(p.x, p.z, p.y);
            if (p.y - gy < 8 && Math.random() < 0.6) { _a.set(p.x + rand(-4, 4), gy + 0.4, p.z + rand(-4, 4)); G.fx.debris(_a, 2, ['#5a4a6a', '#2b2b2b', '#d8d8d8'], 22); }
          },
          onEnd: (p) => { G.fx.release(ball); G.fx.release(core); G.fx.release(halo); G.fx.burst(p, '#e0b0ff', 22, 0.3); G.fx.sphere(p, '#c070ff', 3, 12, 0.35, { a0: 0.6 }); },
        });
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

// 4: Infinite Void — домен (слот 4 пробуждения, перезарядка 120 с)
const gVoid = { id: 'void', label: 'Infinite Void', tip: 'DOMAIN', cd: 120, windup: 0.55, color: '#bfe6ff', ai: { kind: 'domain', min: 0, max: 22 }, cast: unlimitedVoid };

// ======================= SUKUNA =======================
// Cleave / Dismantle / Open / Rush / FURNACE / Incantation — в kits.js (общие для Strongest of History и King of Curses)

// Шквал ударов по захваченной цели (Rush Сукуны, Rapid Punches Годжо)
export function rushBarrage(f, v, o) {
  f.action = null;
  const base = f.idlePose;
  const L = PX(base, { lax: -1.65, laz: -0.1, rax: -0.6, twist: -0.6, cx: 0.25, hy: -0.3 });
  const R = PX(base, { rax: -1.65, raz: 0.1, lax: -0.6, twist: 0.6, cx: 0.25, hy: -0.3 });
  const HL = PX(base, { lax: -1.75, laz: 0.1, rax: 0.4, raz: -0.4, twist: -0.95, cx: 0.35, hy: -0.4, llx: -0.4, rlx: 0.45 });
  const HR = PX(base, { rax: -1.75, raz: -0.1, lax: 0.4, laz: 0.4, twist: 0.95, cx: 0.35, hy: -0.4, llx: 0.45, rlx: -0.4 });
  const UP = PX(base, { rax: -2.8, raz: 0.1, twist: 0.5, cx: -0.2, hy: 0.1, rlx: 0.3, llx: -0.3 });
  const evs = [];
  let t = 0.05;
  for (let i = 0; i < o.n; i++, t += o.gap) {
    evs.push([t, (ff) => {
      if (v.dead) return;
      G.hit(ff, v, { dmg: o.dmg, melee: true, stun: 0.5, push: 1.2, hitstop: 0.02, fx: 'hit', shake: 0.08, sfx: 'hit', vol: 0.35 });
      ff.chestPos(_a); ff.fwd(_b); _a.addScaledVector(_b, 2.6); _a.x += rand(-1, 1); _a.y += rand(-1, 1.2); _a.z += rand(-1, 1);
      G.fx.burst(_a, '#ffffff', 2.6, 0.09);
      if (o.arcs) { _q.setFromUnitVectors(ZV, _b); _q.multiply(_q2.setFromAxisAngle(ZV, rand(0, Math.PI * 2))); G.fx.crescent(_a, _q, o.arcs, 1.2, 2.6, 0.12, { a0: 0.9 }); }
    }]);
  }
  const hStart = t;
  for (let i = 0; i < o.heavies; i++) {
    t += o.heavyGap;
    evs.push([t, (ff) => {
      if (v.dead) return;
      G.hit(ff, v, { dmg: o.heavyDmg, melee: true, stun: 0.7, push: 2.5, hitstop: 0.06, fx: 'heavy', color: o.color, shake: 0.25, sfx: 'heavy', vol: 0.6 });
    }]);
  }
  const hEnd = t;
  t += o.finalGap;
  evs.push([t, (ff) => {
    if (v.dead) return;
    G.hit(ff, v, { dmg: o.finalDmg, melee: true, rag: o.finalRag, kb: o.finalKb, hitstop: 0.11, fx: 'heavy', color: o.color, shake: 0.55, sfx: 'heavy' });
  }]);
  const fin = t;
  f.startAction({
    name: 'barrage', dur: fin + 0.25, keepVel: false, poseSpeed: 40, events: evs,
    pose: (ff, a, out) => {
      if (a.t > fin - 0.06) out.set(UP);
      else if (a.t > hStart - 0.02 && o.heavies) out.set(Math.floor((a.t - hStart) / o.heavyGap) % 2 ? HL : HR);
      else out.set(Math.floor(a.t / (o.gap / 2)) % 2 ? L : R);
    },
    update: (ff) => { if (!v.dead && v.stun > 0) { ff.faceTo(v.pos); const d = ff.dist(v); if (d > 3.2) { ff.fwd(_b); ff.vel.x = _b.x * 12; ff.vel.z = _b.z * 12; } } },
  });
  void hEnd;
}

// 4 (база) / 1 (Хэйан): Strong Dismantle — два длинных разреза, срывающих дорогу
const SWIPE_L = [[0, POSE.idle.fist], [0.2, PX(POSE.idle.fist, { twist: 0.7, lax: -0.1, laz: 1.4, lay: 0.4, hy: -0.15 })], [0.38, PX(POSE.idle.fist, { twist: -0.8, lax: -0.1, laz: 1.4, lay: -2.4, cx: 0.25, hy: -0.3, rax: -0.3, raz: -0.6 })], [0.55, PX(POSE.idle.fist, { twist: 0.6, lax: -0.1, laz: 1.4, lay: 0.6, hy: -0.15 })], [0.72, PX(POSE.idle.fist, { twist: -0.8, lax: -0.1, laz: 1.4, lay: -2.4, cx: 0.25, hy: -0.3 })], [1, POSE.idle.fist]];
export const sStrongDismantle = {
  id: 'sdismantle', label: 'Strong Dismantle', tip: 'TARGET', cd: 10, windup: 0.22, color: '#ffffff', ai: { kind: 'ranged', min: 3, max: 45 },
  cast(f) {
    const tgt = f.camTarget(60);
    if (tgt) f.faceTo(tgt.pos);
    const slash = (ff, roll) => {
      ff.chestPos(_a); _a.y += 0.2;
      const origin = _a.clone();
      const dir = aimFrom(ff, origin, tgt && !tgt.dead ? tgt : null, new V3());
      if (!(tgt && !tgt.dead) && ff.isPlayer) ff.aimDir(origin, dir);
      dir.y = clamp(dir.y, -0.2, 0.2); dir.normalize();
      const it = G.fx.pool('cres'); it.mat.color.set('#ffffff');
      const q = waveQuat(dir, roll);
      G.sound('slash', ff.pos, 0.9);
      projectile({
        owner: ff, pos: origin.addScaledVector(dir, 1.5), dir, speed: 95, range: 60, radius: 2.2, pierce: true,
        onHit: (o, p) => G.hit(ff, o, { dmg: 10, unblockable: true, bullet: true, bypassRag: true, stun: 0.8, push: 10, hitstop: 0.07, fx: 'slash', color: '#ffffff', shake: 0.35, sfx: 'slash', from: p }),
        onStep: (p, dt, t) => {
          it.obj.position.copy(p); it.obj.quaternion.copy(q);
          const s = Math.min(1, t / 0.06) * 7.5;
          it.obj.scale.set(s, s, s * 0.8); it.mat.opacity = 1;
          _a.copy(p).addScaledVector(dir, -6); G.fx.line(_a, p, '#ffffff', 0.12, 0.1);
          if (p.y < 6 && Math.random() < 0.6) { _a.set(p.x + rand(-1.2, 1.2), 0.4, p.z + rand(-1.2, 1.2)); G.fx.debris(_a, 1, ['#1e1e22', '#2b2b2b', '#d8d8d8'], 18); G.fx.dust(_a, 1, 2.5, '#f0f0f0'); }
        },
        onWorld: (p) => { G.fx.sparks(p, null, '#ffffff', 8, 30); G.fx.debris(p, 6, ['#2b2b2b', '#9a9ea6']); },
        onEnd: () => G.fx.release(it),
      });
    };
    f.startAction({ name: 'sdismantle', dur: 0.75, frames: SWIPE_L, events: [[0.22, (ff) => slash(ff, 0.25)], [0.5, (ff) => slash(ff, -0.3)]] });
  },
};

// 3 (Хэйан): Kamutoke — ваджра вверх, молнии бьют по области вокруг
const VAJRA = PX(POSE.idle.fist, { rax: -2.95, raz: 0.15, hx: -0.3, lax: -0.4, laz: 0.5, cx: -0.1 });
export const sKamutoke = {
  id: 'kamutoke', label: 'Kamutoke', cd: 12, windup: 0.4, color: '#ffe680', ai: { kind: 'aoe', min: 0, max: 16 },
  cast(f) {
    G.sound('charge', f.pos, 0.6);
    f.startAction({
      name: 'kamutoke', dur: 1.7, frames: [[0, POSE.idle.fist], [0.15, VAJRA], [0.9, VAJRA], [1, POSE.idle.fist]],
      update: (ff) => { if (Math.random() < 0.5) { ff.handPos('R', _a); _b.set(_a.x + rand(-1.5, 1.5), _a.y + rand(0, 2.5), _a.z + rand(-1.5, 1.5)); G.fx.bolt(_a, _b, '#fff6a0', { segs: 3, jag: 0.4, life: 0.08, w: 0.1 }); } },
      events: [0.4, 0.6, 0.8, 1.0, 1.2, 1.4].map((tt, i) => [tt, (ff) => {
        // точка удара: враги рядом в приоритете
        const near = ff.enemiesNear(ff.pos, 17, 10);
        const o = near.length && Math.random() < 0.7 ? near[i % near.length] : null;
        const an = rand(0, Math.PI * 2), rr = rand(4, 15);
        const x = o ? o.pos.x + rand(-1.5, 1.5) : ff.pos.x + Math.cos(an) * rr, z = o ? o.pos.z + rand(-1.5, 1.5) : ff.pos.z + Math.sin(an) * rr;
        const gy = G.world.groundAt(x, z, ff.pos.y + 4);
        _a.set(x + rand(-3, 3), gy + 42, z + rand(-3, 3)); _b.set(x, gy + 0.2, z);
        G.fx.bolt(_a, _b, '#fff8c0', { segs: 9, jag: 2.2, life: 0.22, w: 0.55 });
        G.fx.bolt(_a, _b, '#ffffff', { segs: 7, jag: 1.4, life: 0.16, w: 0.25 });
        G.fx.ring(_b, '#ff3030', 1, 9, 0.35, { axis: 'y', a0: 0.9 });
        G.fx.ring(_b, '#ffffff', 1, 6, 0.25, { axis: 'y', a0: 0.9 });
        G.fx.burst(_b, '#fff2a0', 9, 0.2);
        G.fx.debris(_b, 9, ['#1e1e22', '#2b2b2b', '#d8d8d8'], 26, [0.6, 1.4]);
        G.fx.crater(_b, 5);
        _b.y += 2;
        for (const e of ff.enemiesNear(_b, 5.5, 8)) G.hit(ff, e, { dmg: 8, bypassRag: true, rag: 0.8, kb: { f: 22, up: 26 }, from: _b, hitstop: 0.08, fx: 'energy', color: '#fff2a0', shake: 0.4, sfx: 'boom' });
        G.sound('boom', _b, 0.6);
        G.shake(0.3, _b);
        G.flashNear(_b, '#fff2a0', 0.22, 30);
      }]),
    });
  },
};

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

// ======================= YUJI (Vessel) =======================
const FS = POSE.idle.fist;
const PUNCH_WIND = PX(FS, { rax: 0.5, raz: -0.3, twist: -0.6, hy: -0.3, cx: 0.1, lax: -1.2 });
const PUNCH_HIT = PX(FS, { rax: -1.7, raz: 0.05, twist: 0.75, cx: 0.3, hy: -0.35, lax: -0.4, laz: 0.4, llx: -0.45, rlx: 0.5 });
const SLIDE = PX(POSE.dashF, { rax: 0.5, raz: -0.3, lax: -1.3, laz: 0.2, twist: -0.4, hy: -0.45, lean: 0.35 });
const FL_L = PX(FS, { lax: -1.65, laz: -0.05, rax: -0.5, twist: -0.55, cx: 0.22, hy: -0.3 });
const FL_R = PX(FS, { rax: -1.65, raz: 0.05, lax: -0.5, twist: 0.55, cx: 0.22, hy: -0.3 });
const CALF = PX(FS, { rlx: -0.7, rlz: -0.5, twist: -0.6, llx: 0.25, hy: -0.35, cx: 0.1, rax: 0.4, raz: -0.6, lax: -0.8, laz: 0.6 });
const CHARGE = PX(FS, { rax: 0.7, raz: -0.45, twist: -0.75, cx: 0.15, hy: -0.4, lax: -1.3, laz: 0.3, llx: -0.3, rlx: 0.4 });
const GRAB = PX(FS, { rax: -1.6, raz: 0.15, twist: 0.4, cx: 0.25, hy: -0.3, lax: -1.4, laz: -0.2 });
const SLAM_UP = PX(FS, { rax: -2.9, raz: 0.1, lax: -2.9, laz: -0.1, cx: -0.25, hy: 0.05, twist: 0 });
const SLAM_DN = PX(FS, { rax: -0.7, raz: 0.15, lax: -0.7, laz: -0.15, cx: 0.6, hy: -0.6, llx: -0.5, rlx: 0.5 });
const DROPKICK = PX(POSE.air, { rlx: -1.5, llx: -1.2, lean: -0.6, cx: -0.2, rax: -2.6, lax: -2.6, laz: 0.4, raz: -0.4 });

// R: Combat Instincts — финт: мгновенно отменяет свой M1 или замах навыка, навык не уходит на перезарядку
function feintFX(f) {
  f.chestPos(_a);
  const cam = G.camera;
  _b.setFromMatrixColumn(cam.matrixWorld, 0); _c.setFromMatrixColumn(cam.matrixWorld, 1);
  const R = 3.4 * f.scale, N = 16;
  const p0 = new V3(), p1 = new V3();
  for (let i = 0; i < N; i++) {
    const a0 = (i / N) * Math.PI * 2, a1 = ((i + 1) / N) * Math.PI * 2;
    p0.copy(_a).addScaledVector(_b, Math.cos(a0) * R * 0.62).addScaledVector(_c, Math.sin(a0) * R);
    p1.copy(_a).addScaledVector(_b, Math.cos(a1) * R * 0.62).addScaledVector(_c, Math.sin(a1) * R);
    G.fx.bolt(p0, p1, '#ffffff', { segs: 2, jag: 0.3, life: 0.25, w: 0.07 });
  }
  G.fx.ring(_a, '#dff3ff', R * 0.9, R, 0.25, { a0: 0.55, sx: [0.62, 1, 1] });
  G.fx.particles(_a, { n: 8, color: ['#ffffff', '#cfe8ff'], speed: 9, size: 0.45, life: 0.25 });
}
const yInstincts = {
  id: 'instinct', label: 'Combat Instincts', cd: 2, instant: true, color: '#ffffff', ai: { kind: 'feint' },
  cast(f) {
    const a = f.action;
    if (!a || a.noFeint) return false;
    const m1 = a.name === 'm1' && a.t < a.hitAt;
    const sk = a.slot != null && a.t < (a.windup ?? 0.25);
    if (!m1 && !sk) return false;
    a.onCancel?.(f, a);
    f.action = null;
    if (sk) f.cd[a.slot] = 0;
    if (m1) { f.combo = Math.max(0, f.combo - 1); if (a.n === 4) f.m1Cd = 0; }
    if (f.awakenPct() >= 3) f.spendAwaken(3);
    feintFX(f);
    G.sound('tp', f.pos, 0.3);
    return true;
  },
};

// 1: Cursed Strikes — скольжение 18 стадов с красными глазами, захват: 6×1.75 и подсечка (3, оглушение 1 с)
function redEyes() {
  const L = G.fx.pool('glow'), R = G.fx.pool('glow');
  L.mat.color.set('#ff1a2a'); R.mat.color.set('#ff1a2a');
  return {
    set(f) {
      f.headPos(_a); _a.y -= 0.75 * f.scale; f.fwd(_b);
      _c.set(-_b.z, 0, _b.x);
      L.obj.position.copy(_a).addScaledVector(_b, 0.7).addScaledVector(_c, 0.27); L.obj.scale.setScalar(0.9);
      R.obj.position.copy(_a).addScaledVector(_b, 0.7).addScaledVector(_c, -0.27); R.obj.scale.setScalar(0.9);
    },
    free() { G.fx.release(L); G.fx.release(R); },
  };
}
const yCursedStrikes = {
  id: 'cstrikes', label: 'Cursed Strikes', cd: 14, windup: 0.3, color: '#ff3040', ai: { kind: 'gap', min: 0, max: 16 },
  cast(f) {
    if (f.airborne()) return airDropkick(f);
    const tgt = f.autoTarget(20, 0.45);
    if (tgt) f.faceTo(tgt.pos);
    const saved = f.combo;
    const eyes = redEyes();
    let freed = false;
    const free = () => { if (!freed) { freed = true; eyes.free(); } };
    const D = 0.45, v0 = (18 * 1.5) / D;
    const flurry = (ff, v) => {
      const evs = [];
      for (let i = 0; i < 6; i++) evs.push([0.08 + i * 0.13, (f2) => {
        if (v.dead) return;
        G.hit(f2, v, { dmg: 1.75, melee: true, stun: 0.7, push: 0.8, hitstop: 0.03, fx: 'hit', color: '#ff4050', shake: 0.12, sfx: 'hit', vol: 0.5 });
        v.chestPos(_a); _b.set(rand(-1, 1), rand(-1, 1), rand(-1, 1)).normalize();
        _c.copy(_a).addScaledVector(_b, 2.2); _a.addScaledVector(_b, -2.2);
        G.fx.line(_a, _c, '#ff3040', 0.14, 0.12);
      }]);
      evs.push([1.02, (f2) => {
        if (v.dead) return;
        const r = G.hit(f2, v, { dmg: 3, melee: true, stun: 1.0, push: 2, hitstop: 0.08, fx: 'heavy', color: '#ff6060', shake: 0.35, sfx: 'heavy' });
        if (r === 'hit') v.broken = Math.max(v.broken, 1.0);
      }]);
      ff.startAction({
        name: 'cstrikesF', dur: 1.3, poseSpeed: 40, events: evs,
        pose: (f2, a, out) => out.set(a.t > 0.95 ? CALF : Math.floor(a.t / 0.065) % 2 ? FL_L : FL_R),
        update: (f2, dt) => {
          if (!v.dead && v.stun > 0) { f2.faceTo(v.pos); f2.fwd(_b); _a.set(f2.pos.x + _b.x * 3, v.pos.y, f2.pos.z + _b.z * 3); v.pos.lerp(_a, 1 - Math.exp(-8 * dt)); }
          if (!freed) eyes.set(f2);
        },
        onEnd: (f2) => { free(); f2.combo = saved; f2.comboT = 1.2; },
        onCancel: free,
      });
    };
    f.startAction({
      name: 'cstrikes', dur: D, keepVel: true, windup: 0.3, poseSpeed: 24,
      pose: (ff, a, out) => out.set(SLIDE),
      update: (ff, dt, t, a) => {
        if (tgt && !tgt.dead && ff.dist(tgt) > 2) ff.yaw = angleDamp(ff.yaw, Math.atan2(tgt.pos.x - ff.pos.x, tgt.pos.z - ff.pos.z), 8, dt);
        ff.fwd(_b);
        const sp = v0 * Math.sqrt(Math.max(0, 1 - t / D));
        ff.vel.x = _b.x * sp; ff.vel.z = _b.z * sp;
        eyes.set(ff);
        if (Math.random() < 0.6) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.3, 1.2), ff.pos.z + rand(-1, 1)); G.fx.dust(_a, 1, 2); }
        const v = ff.meleeTargets(3.3, 0.5)[0];
        if (!v) return;
        // захват (блокируется со всех сторон)
        const r = G.hit(ff, v, { dmg: 4, melee: true, block360: true, stun: 1.6, push: 0, hitstop: 0.07, fx: 'hit', color: '#ff4050', shake: 0.25, sfx: 'hit' });
        ff.vel.x *= 0.1; ff.vel.z *= 0.1;
        if (r === 'hit' || r === 'break') { ff.fdashCd = Math.max(ff.fdashCd, 1.2); flurry(ff, v); }
        else { free(); ff.endlag(r === 'blocked' ? 0.6 : 0.3); }
      },
      onEnd: (ff) => { free(); ff.endlag(0.3); },
      onCancel: free,
    });
    G.sound('dash', f.pos, 0.6);
  },
};
// Воздушный вариант: подскок и ныряющий дропкик, прижимает к земле (14)
function airDropkick(f) {
  const tgt = f.autoTarget(26, 0.3);
  if (tgt) f.faceTo(tgt.pos);
  const aimP = new V3();
  if (tgt) aimP.copy(tgt.pos); else { f.fwd(_b); aimP.copy(f.pos).addScaledVector(_b, 12); aimP.y = G.world.groundAt(aimP.x, aimP.z, f.pos.y); }
  G.sound('charge', f.pos, 0.4);
  f.startAction({
    name: 'cstrikesAir', dur: 1.4, keepVel: true, noGrav: true, windup: 0.18, poseSpeed: 20,
    pose: (ff, a, out) => out.set(a.t < 0.18 ? POSE.air : DROPKICK),
    update: (ff, dt, t, a) => {
      if (t < 0.18) {
        ff.vel.set(0, 10, 0);
        if (Math.random() < 0.8) { const gy = G.world.groundAt(ff.pos.x, ff.pos.z, ff.pos.y); _a.set(ff.pos.x + rand(-2, 2), gy + 0.3, ff.pos.z + rand(-2, 2)); G.fx.particles(_a, { n: 1, normal: true, color: '#e8e8e8', speed: 3, up: 2, size: 1.2, size1: 2.4, life: 0.4, alpha: 0.5 }); }
        return;
      }
      if (!a.dir) {
        if (tgt && !tgt.dead) aimP.copy(tgt.pos);
        a.dir = new V3().subVectors(aimP, ff.pos);
        const h = Math.hypot(a.dir.x, a.dir.z);
        // нельзя нырнуть строго вниз
        if (h < Math.abs(a.dir.y) * 0.55) { ff.fwd(_b); a.dir.x = _b.x * Math.abs(a.dir.y) * 0.55; a.dir.z = _b.z * Math.abs(a.dir.y) * 0.55; }
        a.dir.normalize();
        if (a.dir.y > -0.25) { a.dir.y = -0.25; a.dir.normalize(); }
        ff.yaw = Math.atan2(a.dir.x, a.dir.z);
      }
      ff.vel.copy(a.dir).multiplyScalar(72);
      if (Math.random() < 0.7) { _a.set(ff.pos.x + rand(-1, 1), ff.pos.y + rand(0.5, 4), ff.pos.z + rand(-1, 1)); G.fx.str.add(_a, _b.copy(a.dir).multiplyScalar(-30), '#ff6070', 0.15, 0.09, 2.4, { drag: 6 }); }
      if (ff.onGround || t > 1.3) {
        _a.set(ff.pos.x, ff.pos.y + 2, ff.pos.z);
        for (const o of ff.enemiesNear(_a, 6)) G.hit(ff, o, { dmg: 14, melee: true, unblockable: true, bypassRag: true, downslam: true, rag: 1.1, kb: { f: 14, up: -45 }, hitstop: 0.12, fx: 'heavy', color: '#ff4050', shake: 0.6, sfx: 'heavy' });
        _a.set(ff.pos.x, ff.pos.y + 0.2, ff.pos.z);
        G.fx.ring(_a, '#3a3236', 1, 11, 0.45, { axis: 'y', a0: 0.9 });
        G.fx.ring(_a, '#ffffff', 1, 8, 0.3, { axis: 'y', a0: 0.8 });
        G.fx.crater(_a, 7); G.fx.dust(_a, 16, 3.5, '#8a8078'); G.fx.debris(_a, 10, ['#2b2b2b', '#3a3a40', '#d8d8d8']);
        G.shake(0.45, ff.pos); G.sound('boom', ff.pos, 0.7);
        ff.vel.set(0, 0, 0);
        ff.startAction({ name: 'land', dur: 0.4, pose: (f2, a2, out) => out.set(PX(f2.idlePose, { hy: -0.7, cx: 0.45 })) });
      }
    },
  });
  return true;
}

// 2: Crushing Blow — голубая энергия в руке, захват ≤5 стадов, два удара о землю (6+6), подброс
const yCrushing = {
  id: 'crushing', label: 'Crushing Blow', cd: 15, windup: 0.4, color: '#4fe0ff', ai: { kind: 'melee', min: 0, max: 6 },
  cast(f) {
    const tgt = f.autoTarget(8, 0.4);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(3, lungeTo(f, tgt, 8, 3)) / 0.36;
    const flame = G.fx.pool('glow'); flame.mat.color.set('#40d8ff');
    let freed = false;
    const free = () => { if (!freed) { freed = true; G.fx.release(flame); } };
    const slam = (ff, a) => {
      const v = a.v;
      if (!v || v.dead) return;
      ff.fwd(_b);
      const gx = ff.pos.x + _b.x * 3, gz = ff.pos.z + _b.z * 3, gy = G.world.groundAt(gx, gz, ff.pos.y + 2);
      v.pos.set(gx, gy, gz);
      G.hit(ff, v, { dmg: 6, melee: true, unblockable: true, bypassRag: true, stun: 1.2, ignoreIframes: true, hitstop: 0.09, fx: 'heavy', color: '#4fe0ff', shake: 0.5, sfx: 'heavy' });
      _a.set(gx, gy + 0.2, gz);
      beamFX(_a, YV, 11, 1.5, '#3fd8ff', '#e8ffff', 0.35);
      G.fx.ring(_a, '#4fe0ff', 1, 9, 0.35, { axis: 'y', a0: 0.9 });
      G.fx.crater(_a, 6); G.fx.dust(_a, 10, 3); G.fx.debris(_a, 8, ['#2b2b2b', '#3a3a40', '#d8d8d8']);
      G.sound('boom', _a, 0.5);
    };
    f.startAction({
      name: 'crushing', dur: 1.75, keepVel: true, windup: 0.4,
      frames: [[0, FS], [0.12, CHARGE], [0.22, CHARGE], [0.27, GRAB], [0.36, SLAM_UP], [0.43, SLAM_DN], [0.55, SLAM_UP], [0.65, SLAM_DN], [0.78, SLAM_DN], [0.86, SLAM_UP], [1, FS]],
      update: (ff, dt, t, a) => {
        if (t < 0.38) { ff.vel.x = Math.sin(ff.yaw) * lunge; ff.vel.z = Math.cos(ff.yaw) * lunge; } else ff.friction(dt, 14);
        if (!freed) {
          ff.handPos('R', _a);
          flame.obj.position.copy(_a); flame.obj.scale.setScalar(2.4 + Math.sin(t * 40) * 0.3);
          if (Math.random() < 0.8) G.fx.add.spawn(_a.x + rand(-0.4, 0.4), _a.y, _a.z + rand(-0.4, 0.4), rand(-1, 1), rand(3, 6), rand(-1, 1), Math.random() < 0.5 ? '#40d8ff' : '#e0ffff', 1, 0.9, 0.1, 0.3);
        }
        const v = a.v;
        if (v && !v.dead && t < 1.5) {
          // держит цель перед собой: поднимает между ударами
          ff.fwd(_b);
          const up = t < 0.76 ? (t - 0.4) / 0.36 : t < 1.14 ? (t - 0.76) / 0.38 : (t - 1.14) / 0.36;
          const gy = G.world.groundAt(v.pos.x, v.pos.z, ff.pos.y + 2);
          _a.set(ff.pos.x + _b.x * 3, gy + Math.sin(Math.min(1, up) * Math.PI) * 3.2, ff.pos.z + _b.z * 3);
          v.pos.lerp(_a, 1 - Math.exp(-14 * dt)); v.vel.set(0, 0, 0); v.suspend = 0.1; v.stun = Math.max(v.stun, 0.5); v.blocking = false;
        }
      },
      events: [
        [0.4, (ff, a) => {
          const v = ff.meleeTargets(5, 0.35)[0];
          if (!v || v.prot > 0 || v.iframes > 0) {
            // промах — слабая ударная волна
            ff.fwd(_b); _a.set(ff.pos.x + _b.x * 4, ff.pos.y + 1.5, ff.pos.z + _b.z * 4);
            for (const o of ff.enemiesNear(_a, 6)) G.hit(ff, o, { dmg: 3, stun: 0.5, push: 12, from: ff.pos, fx: 'energy', color: '#4fe0ff', sfx: 'hit' });
            _a.y = ff.pos.y + 0.2; G.fx.ring(_a, '#4fe0ff', 1, 8, 0.35, { axis: 'y' }); G.fx.dust(_a, 8, 2.5);
            free(); a.dur = 1.0; a.locked = true;
            return;
          }
          a.v = v;
          v.interrupt(true); v.rag = false; v.ragTrue = false; v.down = 0; v.blocking = false; v.stun = Math.max(v.stun, 1.2);
          v.lastHitBy = ff; v.lastHitT = G.time;
          v.chestPos(_a); G.fx.burst(_a, '#4fe0ff', 5, 0.15);
          G.sound('hit', v.pos, 0.6);
        }],
        [0.76, slam],
        [1.14, slam],
        [1.5, (ff, a) => {
          free();
          const v = a.v;
          if (!v || v.dead || v.iframes > 0) return;
          v.launch(Math.sin(ff.yaw) * 6, 46, Math.cos(ff.yaw) * 6, 1.2);
          v.chestPos(_a); G.fx.ring(_a, '#4fe0ff', 1, 7, 0.3, { a0: 0.9 }); G.fx.particles(_a, { n: 12, color: ['#4fe0ff', '#ffffff'], speed: 14, up: 10, size: 0.9, life: 0.4 });
          G.sound('heavy', v.pos, 0.6);
        }],
      ],
      onCancel: free,
      onEnd: free,
    });
    G.sound('charge', f.pos, 0.4);
  },
};

// 3: Divergent Fist — удар (5) и отложенный удар энергией (5); повтор в белой вспышке = Чёрная вспышка
const yDivergent = {
  id: 'divergent', label: 'Divergent Fist', tip: 'USE TWICE', cd: 18, windup: 0.42, color: '#4fb8ff', ai: { kind: 'melee', min: 0, max: 8 },
  cast(f) {
    const tgt = f.autoTarget(11, 0.35);
    if (tgt) f.faceTo(tgt.pos);
    const lunge = Math.min(3, lungeTo(f, tgt, 11, 2.8)) / 0.3;
    f.fwd(_b); const dx = _b.x, dz = _b.z;
    f.startAction({
      name: 'divergent', dur: 0.85, keepVel: true, windup: 0.42,
      frames: [[0, FS], [0.3, PUNCH_WIND], [0.48, PUNCH_WIND], [0.56, PUNCH_HIT], [0.85, PUNCH_HIT], [1, FS]],
      update: (ff, dt, t, a) => {
        if (t > 0.12 && t < 0.42) { ff.vel.x = dx * lunge; ff.vel.z = dz * lunge; } else ff.friction(dt, 14);
        // окно Чёрной вспышки: тело вспыхивает белым
        if (t >= 0.2 && t < 0.4) ff.whiteT = 0.03;
        if (t < 0.42) {
          ff.handPos('R', _a);
          G.fx.add.spawn(_a.x, _a.y, _a.z, rand(-2, 2), rand(0, 3), rand(-2, 2), a.bf ? '#ff2040' : '#4fb8ff', 1, 1, 0.2, 0.25);
          if (a.bf && Math.random() < 0.7) { _b.set(_a.x + rand(-1.5, 1.5), _a.y + rand(-1.5, 1.5), _a.z + rand(-1.5, 1.5)); G.fx.bolt(_a, _b, '#120006', { dark: true, segs: 3, jag: 0.4, life: 0.1, w: 0.12 }); }
        }
        // боты: попадание в окно зависит от умения
        if (ff.brain && !a.bfTry && t >= 0.24) { a.bfTry = true; if (Math.random() < ff.brain.skill * 0.6) a.bf = true; }
      },
      onRepress: (ff, a) => { if (a.t >= 0.2 && a.t < 0.42 && !a.bfMiss) { if (!a.bf) { a.bf = true; G.sound('charge', ff.pos, 0.4); } } else if (a.t < 0.2) a.bfMiss = true; },
      events: [[0.42, (ff, a) => {
        const v = ff.meleeTargets(5.6, 0.35)[0];
        G.sound('swing', ff.pos, 0.6);
        if (!v) return;
        if (a.bf) { blackFlash(ff, v, a); return; }
        const r = G.hit(ff, v, { dmg: 5, melee: true, stun: 1.0, push: 3, hitstop: 0.07, fx: 'hit', sfx: 'hit' });
        if (r === 'blocked') { a.dur = 1.0; a.locked = true; return; }
        if (r !== 'hit' && r !== 'break') return;
        let t = 0;
        G.addTask((dt) => {
          t += dt;
          if (v.dead || G.matchOver) return false;
          if (t < 0.38) { v.chestPos(_a); if (Math.random() < 0.6) G.fx.add.spawn(_a.x + rand(-1, 1), _a.y + rand(-1, 1), _a.z + rand(-1, 1), 0, 2, 0, '#4fb8ff', 1, 0.9, 0.1, 0.25); return true; }
          const acting = !!(v.action && v.action.name !== 'endlag') && v.stun <= 0;
          G.hit(ff, v, { dmg: 5, unblockable: true, pierce: true, noCounter: true, ignoreIframes: true, ...(acting ? { stun: 1.0 } : { rag: 1.2, kb: { f: 70, up: 16 } }), hitstop: 0.09, fx: 'energy', color: '#4fb8ff', shake: 0.45, sfx: 'heavy', from: ff.pos });
          v.chestPos(_a);
          G.fx.ring(_a, '#4fb8ff', 1, 7, 0.3, { a0: 0.9 });
          G.fx.ring(_a, '#ffffff', 0.5, 4, 0.2);
          return false;
        });
      }]],
    });
    G.sound('swing', f.pos, 0.4);
  },
};
// Чёрная вспышка: 10 (20 если прерывает действие); со спины — оглушение и цепочка до 4 (4-я — «KOKUSEN!» 15)
function blackFlash(f, v, a) {
  const interrupting = !!(v.action && v.action.name !== 'endlag' && v.action.name !== 'land') && v.stun <= 0 && !v.rag;
  v.fwd(_b); _c.set(f.pos.x - v.pos.x, 0, f.pos.z - v.pos.z).normalize();
  const back = _b.dot(_c) < -0.3;
  let dmg, opts;
  let n = 0;
  if (back) {
    n = f.bfChain = Math.min(4, f.bfChain + 1); f.bfChainT = 3.5;
    if (n >= 4) { dmg = 15; opts = { rag: 1.4, trueRag: true, kb: { f: 110, up: 22 } }; f.bfChain = 0; }
    else { dmg = interrupting ? 14 : 7; opts = { stun: 1.0 }; }
  } else {
    f.bfChain = 0;
    dmg = interrupting ? 20 : 10; opts = { rag: 1.3, kb: { f: 110, up: 20 } };
  }
  const r = G.hit(f, v, { dmg, melee: true, unblockable: true, pierce: true, hitstop: 0.22, fx: 'heavy', color: '#ff2040', shake: 1.0, sfx: 'boom', numColor: '#ff3050', ...opts });
  if (!r) return;
  if (back && n < 4) {
    // цепочка: навык не уходит на перезарядку, боковой рывок обновляется
    if (a.slot != null) f.cd[a.slot] = 0;
    f.sdashCd = 0;
    v.broken = Math.max(v.broken, 1.0);
  }
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
  if (n >= 4) {
    // «KOKUSEN!» — радужные лучи
    const RB = ['#ff3030', '#ff9a20', '#ffe030', '#40e060', '#30b0ff', '#6a50ff', '#d040ff'];
    for (let i = 0; i < 21; i++) {
      _b.set(rand(-1, 1), rand(-0.6, 1), rand(-1, 1)).normalize();
      _a.copy(c).addScaledVector(_b, 1.5); _c.copy(c).addScaledVector(_b, rand(12, 20));
      G.fx.line(_a, _c, RB[i % 7], 0.5, 0.35);
    }
    G.fx.ring(c, '#ffffff', 2, 18, 0.5, { a0: 1 });
    G.hud.pop(_a.set(c.x, c.y + 3.5, c.z), 'KOKUSEN!', '#ffe14a', 2.1);
    G.callout(f, 'KOKUSEN!', '#ffe14a');
  } else G.hud.pop(_a.set(c.x, c.y + 3, c.z), back ? `BLACK FLASH ×${n}` : 'BLACK FLASH!', '#ff2040', 1.7);
  G.sound('heavy', v.pos, 1); G.sound('block', v.pos, 0.8);
  if (f.isPlayer || v.isPlayer || f.dist(G.player) < 40) G.hud.blackFlash();
}

// 4: Manji Kick — стойка-контратака 0.6 с против ближнего боя и «пуль», круговой удар вверх 8.5
const KICK_HIGH = PX(FS, { rlx: -2.3, llx: 0.3, lean: -0.35, cx: -0.1, hy: 0.15, rax: 0.5, raz: -0.9, lax: 0.4, laz: 0.9, twist: 0.3 });
const MANJI_STANCE = PX(FS, { hy: -0.1, cx: 0.05, rax: -2.4, raz: 0.3, lax: -0.9, laz: 0.4, llx: -1.4, rlx: 0.1, twist: 0.4 });
const yManji = {
  id: 'manji', label: 'Manji Kick', tip: 'COUNTER', cd: 20, color: '#ffc040', ai: { kind: 'counter', min: 0, max: 7 },
  cast(f) {
    f.counter = 0.6;
    f.chestPos(_a); G.fx.ring(_a, '#ffe0a0', 1, 4, 0.3, { a0: 0.8 });
    G.sound('block', f.pos, 0.5);
    f.startAction({
      name: 'manji', dur: 0.6, noFeint: true, windup: 0, frames: [[0, FS], [0.25, MANJI_STANCE], [1, MANJI_STANCE]],
      onEnd: (ff) => { ff.counter = 0; ff.endlag(0.35, MANJI_STANCE); },
    });
  },
};
function manjiCounter(f, att, bullet) {
  f.interrupt(true);
  f.counter = 0;
  f.faceTo(att.pos);
  const d = f.dist(att);
  if (bullet && d > 3.5 && d < 60) {
    // «пуля»: уклон и налёт на стрелка
    f.chestPos(_a); G.fx.burst(_a, '#ffffff', 10, 0.2);
    f.fwd(_b); f.pos.set(att.pos.x - _b.x * 2.8, att.pos.y, att.pos.z - _b.z * 2.8);
    G.world.collide(f.pos, 1.2, 5);
    f.chestPos(_a); G.fx.burst(_a, '#ffffff', 16, 0.3); G.fx.ring(_a, '#ffffff', 1, 9, 0.3, { a0: 1 });
  } else if (d > 3.5 && d < 10) { f.fwd(_b); f.pos.addScaledVector(_b, d - 2.8); G.world.collide(f.pos, 1.2, 5); }
  f.iframes = Math.max(f.iframes, 0.5);
  att.interrupt(); att.stun = Math.max(att.stun, 0.4);
  f.chestPos(_a);
  G.hud.pop(_a, 'COUNTER!', '#ffc040', 1.5);
  G.fx.burst(_a, '#ffd060', 8, 0.2);
  G.sound('block', f.pos, 0.9);
  f.startAction({
    name: 'manjiKick', dur: 0.55, noFeint: true, frames: [[0, MANJI_STANCE], [0.25, KICK_HIGH], [0.7, KICK_HIGH], [1, FS]],
    events: [[0.12, (ff) => {
      if (att.dead || ff.dist(att) > 7.5) return;
      // удар с разворота: отбрасывает вбок и вверх
      ff.fwd(_b); _c.set(-_b.z, 0, _b.x);
      const from = _a.set(att.pos.x - _c.x * 3 - _b.x * 1.5, att.pos.y, att.pos.z - _c.z * 3 - _b.z * 1.5);
      G.hit(ff, att, { dmg: 8.5, melee: true, unblockable: true, bypassRag: true, trueRag: true, noCounter: true, pierce: true, rag: 1.2, kb: { f: 34, up: 34 }, from: from.clone(), hitstop: 0.12, fx: 'heavy', color: '#ffc040', shake: 0.6, sfx: 'heavy' });
      _a.set(att.pos.x, G.world.groundAt(att.pos.x, att.pos.z, att.pos.y) + 0.2, att.pos.z);
      G.fx.crater(_a, 6); G.fx.debris(_a, 8, ['#2b2b2b', '#3a3a40']);
    }]],
  });
}

// ======================= YUTA =======================
const KT = POSE.idle.katana;
const POINT_UP = PX(KT, { rax: -2.7, raz: 0.1, kat: 0.2, lax: -0.4, laz: 0.4, hx: -0.15, hy: -0.1 });
const rikaArms = [];
export function getRikaArm() {
  let a = rikaArms.find((x) => !x.busy);
  if (!a) { a = buildRikaArm(); a.busy = false; G.scene.add(a.root); rikaArms.push(a); }
  a.busy = true; a.root.visible = true;
  return a;
}
const rikas = [];
export function getRika() {
  let r = rikas.find((x) => !x.busy);
  if (!r) { r = buildRika(); r.busy = false; G.scene.add(r.root); rikas.push(r); }
  r.busy = true; r.root.visible = true;
  return r;
}

// Приёмы Проклятого напарника и True Love — в kits.js

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

// ======================= Пробуждения =======================
// Общая кинематика (≈3 с, неуязвимость): чёрный дым, манга-реплики (рисует HUD), постоянный облик до конца 60 с.
function awakenSmoke(f, red) {
  f.chestPos(_a);
  G.fx.particles(_a, { n: 34, normal: true, color: ['#0c0c0e', '#1c1a1e', '#2a2628'], speed: 18, up: 3, size: 3, size1: 7, life: 1.1, alpha: 0.85, drag: 3 });
  G.fx.particles(_a, { n: 14, normal: true, color: '#141214', speed: 6, up: 6, size: 4, size1: 8, life: 1.4, alpha: 0.7, radius: 1.5 });
  if (red) for (let i = 0; i < 8; i++) {
    _b.set(rand(-1, 1), rand(-0.2, 1), rand(-1, 1)).normalize().multiplyScalar(rand(5, 9)).add(_a);
    G.fx.bolt(_a, _b, '#c0101c', { segs: 4, jag: 0.6, life: 0.35, w: 0.3 });
    G.fx.bolt(_a, _b, '#0a0003', { dark: true, segs: 4, jag: 0.6, life: 0.4, w: 0.18 });
  }
  G.fx.burst(_a, '#ffffff', 10, 0.2);
  _b.set(f.pos.x, f.pos.y + 0.2, f.pos.z);
  G.fx.ring(_b, '#ffffff', 1, 12, 0.45, { axis: 'y', a0: 0.7 });
  G.fx.dust(_b, 12, 3.5, '#9a9490');
  G.sound('boom', f.pos, 0.6);
  G.shake(0.45, f.pos);
}
const GJ_PALM = PX(POSE.palm, { rax: -1.65, raz: 0.15, twist: 0.25, cx: 0.18 });
const AW_GOJO = {
  label: 'Six Eyes', heal: 25, color: '#2EB6F0', grad: ['#9BE6FF', '#2EB6F0'], rim: '#5fd8ff', cine: 3.0,
  lines: [[0.3, 'LET’S GET…'], [1.45, '…A LITTLE CRAZY.']],
  frames: [[0, POSE.idle.gojo], [0.1, POSE.unveil], [0.3, POSE.unveil], [0.37, PX(POSE.unveil, { rax: -2.1, raz: 0.95, ray: 0.1, hx: 0.05 })], [0.48, POSE.palm], [0.55, GJ_PALM], [0.85, GJ_PALM], [1, POSE.idle.gojo]],
  events: [
    [0.2, (f) => awakenSmoke(f, false)],
    [1.05, (f) => {
      // повязка снята: светящиеся глаза
      f.setAwakenLook(true);
      f.headPos(_a); _a.y -= 0.6;
      G.fx.burst(_a, '#9BE6FF', 7, 0.25); G.fx.ring(_a, '#bff4ff', 0.5, 4, 0.3, { a0: 0.9 });
      G.fx.particles(_a, { n: 6, normal: true, color: '#101116', speed: 6, up: 4, size: 0.5, size1: 0.3, life: 0.8, grav: 20 });
      G.sound('tp', f.pos, 0.5);
    }],
    [1.62, (f) => { f.handPos('L', _a); G.fx.burst(_a, '#ffffff', 6, 0.15); G.fx.ring(_a, '#9BE6FF', 0.4, 4, 0.25, { a0: 0.9 }); G.sound('hit', f.pos, 0.7); G.shake(0.25, f.pos); }],
  ],
  tick: (f, dt) => {
    if (Math.random() < dt * 9) { _a.set(f.pos.x + rand(-1.3, 1.3), f.pos.y + rand(0.3, 5), f.pos.z + rand(-1.3, 1.3)); G.fx.particles(_a, { n: 1, color: ['#bfe6ff', '#ffffff'], speed: 1, up: 5, size: 0.8, size1: 0.2, life: 0.6 }); }
  },
};
const AW_YUJI = {
  label: 'King Of Curses', heal: 45, color: '#D61E1E', grad: ['#ff6a6a', '#D61E1E'], rim: '#ff1818', cine: 3.1,
  lines: [[1.35, 'YOU’RE SUCH AN ANNOYING BRAT']],
  frames: [[0, POSE.idle.fist], [0.12, POSE.faint], [0.3, POSE.faint], [0.37, PX(POSE.roar, { hy: -0.15 })], [0.75, POSE.roar], [0.86, PX(POSE.idle.fist, { twist: 0.05, hx: -0.15, lax: -0.25, laz: 0.25, rax: -0.25, raz: -0.25 })], [1, POSE.idle.fist]],
  events: [[1.0, (f) => { awakenSmoke(f, true); f.setAwakenLook(true); }]],
  shrineM1,
  // тёмно-красный дым-аура вокруг силуэта
  tick: (f, dt) => {
    if (Math.random() < dt * 26) {
      _a.set(f.pos.x + rand(-1.4, 1.4), f.pos.y + rand(0.2, 5.4), f.pos.z + rand(-1.4, 1.4));
      G.fx.norm.spawn(_a.x, _a.y, _a.z, rand(-0.5, 0.5), rand(2, 4), rand(-0.5, 0.5), Math.random() < 0.5 ? '#2a0306' : '#6a0a12', 0.65, 1.1, 2.2, 0.6);
    }
    if (Math.random() < dt * 8) { _a.set(f.pos.x + rand(-1.2, 1.2), f.pos.y + rand(0.5, 5), f.pos.z + rand(-1.2, 1.2)); G.fx.add.spawn(_a.x, _a.y, _a.z, 0, rand(2, 4), 0, '#ff2020', 0.7, 0.6, 0.1, 0.5); }
  },
};
const AW_SUKUNA = {
  label: 'Heian Form', heal: 35, color: '#FF5500', grad: ['#ffb070', '#FF5500'], rim: '#ff5a10', cine: 3.2, mods: { dmg: 1.15 },
  lines: [[0.4, 'KNOW YOUR PLACE,'], [1.5, 'FOOL.']],
  frames: [[0, POSE.idle.sukuna], [0.12, POSE.sign], [0.3, POSE.sign], [0.4, POSE.spread], [0.85, POSE.spread], [1, POSE.idle.sukuna]],
  events: [[1.0, (f) => {
    awakenSmoke(f, true);
    f.setAwakenLook(true);
    // рост до 1.4× и вторая пара рук
    let t = 0;
    G.addTask((dt) => {
      t += dt;
      if (f.dead || f.awakened <= 0) return false;
      f.model.root.scale.setScalar(1 + 0.4 * ease.out3(Math.min(1, t / 0.5)));
      return t < 0.5;
    });
  }]],
  shrineM1,
  tick: (f, dt) => {
    if (Math.random() < dt * 14) { _a.set(f.pos.x + rand(-1.6, 1.6), f.pos.y + rand(0.3, 7), f.pos.z + rand(-1.6, 1.6)); G.fx.add.spawn(_a.x, _a.y, _a.z, 0, rand(2, 5), 0, Math.random() < 0.5 ? '#ff6a20' : '#ffc080', 0.8, 0.7, 0.1, 0.6); }
  },
  end: (f) => { f.chant = 0; },
};
const RING_POSE = PX(POSE.idle.katana, { lax: -1.9, laz: -0.95, hx: 0.3, cx: 0.1, rax: -0.4 });
const AW_YUTA = {
  label: 'True Love', heal: 25, color: '#F76BFF', grad: ['#ffc8ff', '#F76BFF'], rim: '#ff6bff', cine: 3.3, mods: { dmg: 1.15 },
  lines: [[0.35, 'COME, RIKA.'], [1.7, 'GIVE ME EVERYTHING.']],
  frames: [[0, POSE.idle.katana], [0.1, RING_POSE], [0.32, RING_POSE], [0.42, POINT_UP], [0.85, POINT_UP], [1, POSE.idle.katana]],
  events: [[1.0, (f) => { awakenSmoke(f, false); f.setAwakenLook(true); yutaRika(f); }]],
  steelJab,
  tick: (f, dt) => {
    if (Math.random() < dt * 10) { _a.set(f.pos.x + rand(-1.3, 1.3), f.pos.y + rand(0.3, 5), f.pos.z + rand(-1.3, 1.3)); G.fx.add.spawn(_a.x, _a.y, _a.z, 0, rand(2, 4), 0, Math.random() < 0.5 ? '#ff8aff' : '#ffffff', 0.8, 0.6, 0.1, 0.6); }
  },
};

// Домен Сукуны как навык (слот 4 пробуждения)
const sShrine = { id: 'shrine', label: 'Malevolent Shrine', tip: 'DOMAIN', cd: 120, windup: 0.6, color: '#ff3050', ai: { kind: 'domain', min: 0, max: 24 }, cast: malevolentShrine };
const aw = (sk, o) => ({ ...sk, ...o });

// Heian, слот 1: Strong Dismantle; после 1/2/3 заклинаний — Dismantle Barrage / Disgraced Sovereign / World Cutting Slash
const heianOne = aw(sStrongDismantle, { id: 'sdismantleH', cd: 8 });
heianOne.pick = (f) => (f.chant >= 3 ? sWCS : f.chant === 2 ? sSovereign : f.chant === 1 ? sKai : heianOne);

// ======================= Таблица персонажей =======================
export const CHARS = {
  gojo: {
    id: 'gojo', name: 'The Strongest of Today', ru: 'Сильнейший сегодня', stance: 'gojo', m1: 'gojo', hp: 100,
    desc: 'Limitless — телепорт к цели, Lapse Blue притягивает, Reversal Red взрывает, шквал ударов и двойной пинок.',
    awakenDesc: 'Six Eyes: Blue MAX, Red MAX, Hollow Purple, Infinite Void',
    special: gLimitless,
    skills: [gLapseBlue, gRed, gRapid, gTwofold],
    awakenSpecial: gLimitless,
    awakenSkills: [gBlueMax, gRedMax, gPurple, gVoid],
    awaken: AW_GOJO,
  },
  sukuna: {
    id: 'sukuna', name: 'Strongest of History', ru: 'Сильнейший в истории', stance: 'sukuna', m1: 'fist', hp: 100,
    desc: 'R Cleave — захват и шквал (40 % HP цели), Dismantle — разрезы на 30 стадов, Open — огненная стрела, Rush — натиск с коленом, Strong Dismantle.',
    awakenDesc: 'Heian Form: 4 руки и рост 1.4×, заклинания (R), Open FURNACE, Kamutoke, Гробница Зла',
    special: sCleave,
    skills: [sDismantle, sOpen, sRush, sStrongDismantle],
    awakenSpecial: sIncant,
    awakenSkills: [heianOne, sFurnace, sKamutoke, sShrine],
    awaken: AW_SUKUNA,
  },
  yuji: {
    id: 'yuji', name: 'Vessel', ru: 'Сосуд', stance: 'fist', m1: 'fist', hp: 85,
    desc: 'Финт Combat Instincts, Cursed Strikes, Crushing Blow, Divergent Fist с Чёрной вспышкой и контр-кик Manji.',
    awakenDesc: 'King Of Curses: разрезы Shrine, Cleave, Dismantle, Open, Rush, Гробница Зла',
    special: yInstincts,
    skills: [yCursedStrikes, yCrushing, yDivergent, yManji],
    awakenSpecial: sCleave,
    awakenSkills: [sDismantle, sOpen, sRush, sShrine],
    awaken: AW_YUJI,
    aiRush: true,
    onCounter: manjiCounter,
  },
  yuta: {
    id: 'yuta', name: 'Cursed Partner', ru: 'Проклятый напарник', stance: 'katana', m1: 'katana', hp: 90,
    desc: 'R — Рика у плеча, ещё раз — её удары. Severing Path (назад — Veilstep), Resolute Slash с Чёрной вспышкой, Outburst с парированием, Second Wind.',
    awakenDesc: 'True Love: Рика-гигант, стальная рука, Elbow Rush, «Не двигайся!», Energy Ripple, луч',
    special: yRika,
    skills: [ySevering, yResolute, yOutburst, ySecondWind],
    rikaSkills: [yRSmash, yRLaunch, yRHaymaker, null],
    awakenSpecial: yTLDownslam,
    awakenSkills: [yElbowRush, yCopySpeech, yEnergyRipple, yTLBeam],
    awaken: AW_YUTA,
    onCounter: outburstParry,
    reset: (f) => { f.rikaGhost = null; f.swRetry = 0; },
  },
};
export const CHAR_IDS = ['gojo', 'sukuna', 'yuji', 'yuta'];

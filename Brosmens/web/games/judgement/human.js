// Люди как в UJD: оружие (M1) + одна способность души (R) + пассивка + предметы раунда (3 пирога и 1 зелье).
// Никаких рывков, выносливости, командного лечения, щитов, воскрешений и провокаций.
//  • Решимость — быстрый нож; пассивка «вторая жизнь» (combat.secondLife). Способности на R нет.
//  • Терпение — игрушечный нож; R «Нити»: 7–9 голубых нитей веером 45° на 18 стадов, висят 3–4 с,
//    каждая может снять 1 уклонение, всего не больше 2. Пассивка: стоишь — урон −10% и лечение.
//  • Храбрость — перчатка, удар снимает 2 уклонения; +25% скорости, +10% урона; R «Кулак» — снаряд.
//  • Справедливость — револьвер на 6 пуль (каждая — 1 уклонение), без пуль или вплотную — удар рукоятью;
//    R — перезарядка до 6 (CD 15, ≈1 с).
// Снаряды и способности не снимают последнее уклонение Судьи — добивать нужно в ближнем бою.
import * as THREE from 'three';
import { damageMonster, dist2, angleTo, clamp, lerp, easeOut, arenaCollide } from './combat.js';
import { MELEE, POTIONS, POTION_TIME, pieHeal } from './data.js';
import { glowTex } from './fx.js';

const V = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3(), V4 = new THREE.Vector3();
const rand = (a, b) => a + Math.random() * (b - a);
const STRING_COL = 0x00f8f8, FIST_COL = 0xf86800, BULLET_COL = 0xf0f800;
const POTION_TINT = { speed: 0x6a7bff, might: 0xff3030, heal: 0x30f050, holy: 0xffe040 };

// ---------- пулы: пули, кулаки, нити ----------
export function initHumanAssets(G) {
  const scene = G.scene;
  const geo = new THREE.BoxGeometry(1, 1, 1); geo.translate(0, 0, -0.5);
  const bullets = [];
  for (let i = 0; i < 24; i++) {
    const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: BULLET_COL, transparent: true, opacity: 0.95, depthWrite: false, blending: THREE.AdditiveBlending }));
    m.visible = false; scene.add(m); bullets.push({ m, used: false });
  }
  // кулак: блок с костяшками и большим пальцем + оранжевое свечение
  const fistMat = new THREE.MeshLambertMaterial({ color: 0xff8a2a, emissive: 0xf86800, emissiveIntensity: 0.75 });
  const fistParts = [new THREE.BoxGeometry(1.7, 1.45, 1.45).translate(0, 0, -0.1)];
  for (let i = 0; i < 4; i++) fistParts.push(new THREE.BoxGeometry(0.38, 0.4, 0.5).translate(-0.6 + i * 0.4, 0.5 - (i === 0 || i === 3 ? 0.06 : 0), 0.72));
  fistParts.push(new THREE.BoxGeometry(0.42, 0.9, 0.6).translate(0.95, -0.15, 0.2));
  const fistGeo = mergeGeos(fistParts);
  const fists = [];
  for (let i = 0; i < 4; i++) {
    const g = new THREE.Group();
    g.add(new THREE.Mesh(fistGeo, fistMat));
    const gl = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color: 0xff7a20, transparent: true, opacity: 0.8, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
    gl.scale.setScalar(4.2); g.add(gl);
    g.visible = false; scene.add(g); fists.push({ m: g, used: false });
  }
  // нити Терпения: тонкие светящиеся бруски
  const sgeo = new THREE.BoxGeometry(0.1, 0.1, 1); sgeo.translate(0, 0, 0.5);
  const strings = [];
  for (let i = 0; i < 27; i++) {
    const m = new THREE.Mesh(sgeo, new THREE.MeshBasicMaterial({ color: STRING_COL, transparent: true, opacity: 0.9, depthWrite: false, blending: THREE.AdditiveBlending }));
    m.visible = false; m.renderOrder = 4; scene.add(m); strings.push({ m, used: false });
  }
  G.ha = { bullets, fists, strings };
  G.fans = [];
}
function mergeGeos(list) {
  const pos = [], nor = [];
  for (const g0 of list) { const g = g0.index ? g0.toNonIndexed() : g0; pos.push(...g.attributes.position.array); nor.push(...g.attributes.normal.array); }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  return out;
}
const take = (arr) => { const o = arr.find((x) => !x.used); if (o) o.used = true; return o; };

function muzzle(f, out) {
  if (f.model.tip) { f.model.root.updateMatrixWorld(true); f.model.tip.getWorldPosition(out); }
  else out.set(f.pos.x, f.pos.y + 3.2, f.pos.z);
  return out;
}

// Направление выстрела/способности: на Судью (если он перед камерой/ботом), в точку тапа или по камере.
export function aimDir(G, f, from, out, aimPt = null) {
  const m = G.monster;
  const alive = m && !m.dead;
  if (aimPt) {
    if (alive && dist2(aimPt, m.pos) < 6) out.set(m.pos.x - from.x, m.pos.y + 3 - from.y, m.pos.z - from.z);
    else out.set(aimPt.x - from.x, 0, aimPt.z - from.z);
    if (out.lengthSq() < 0.01) f.fwd(out);
    return out.normalize();
  }
  let auto = alive && dist2(f.pos, m.pos) < 90;
  if (auto && f.isPlayer && G.camFwd) {
    V3.set(m.pos.x - f.pos.x, 0, m.pos.z - f.pos.z).normalize();
    if (V3.dot(G.camFwd) < 0.25 && dist2(f.pos, m.pos) > 9) auto = false;
  }
  if (auto) {
    out.set(m.pos.x - from.x, m.pos.y + 3 - from.y, m.pos.z - from.z);
    if (!f.isPlayer) { const sp = 0.09 + (1 - (f.bot?.skill ?? 0.7)) * 0.22; out.normalize(); out.x += (Math.random() - 0.5) * sp; out.z += (Math.random() - 0.5) * sp; }
  } else if (f.isPlayer && G.camFwd) out.set(G.camFwd.x, 0, G.camFwd.z);
  else f.fwd(out);
  return out.normalize();
}

function shoot(G, f, kind, from, dir, o) {
  const pool = kind === 'fist' ? G.ha.fists : G.ha.bullets;
  const p = take(pool);
  if (!p) return null;
  p.m.visible = true;
  if (kind === 'bullet') { p.m.material.color.setHex(o.color); p.m.scale.set(o.size, o.size, o.len ?? 1.6); }
  const b = { kind, p, pos: from.clone(), vel: dir.clone().multiplyScalar(o.speed), life: o.range / o.speed, owner: f, dmg: o.dmg, size: o.size, color: o.color, noLast: true, spin: 0 };
  G.projectiles.push(b);
  G.fx.flare(from, o.color, kind === 'fist' ? 3.5 : 1.6, 0.12);
  return b;
}

export function updateProjectiles(G, dt) {
  const m = G.monster;
  for (let i = G.projectiles.length - 1; i >= 0; i--) {
    const b = G.projectiles[i];
    b.life -= dt;
    b.pos.addScaledVector(b.vel, dt);
    const fist = b.kind === 'fist';
    let done = b.life <= 0 || b.pos.y < 0.2, hit = false;
    if (!done) { V.copy(b.pos); if (arenaCollide(V, fist ? 0.9 : 0.1)) { done = true; hit = true; } }
    if (!done && m && !m.dead && dist2(b.pos, m.pos) < m.radius * 0.85 + b.size * 0.5 && b.pos.y > m.pos.y - 0.5 && b.pos.y < m.pos.y + 6.5) {
      damageMonster(G, m, b.dmg, b.owner, { noLast: true, color: b.color });
      done = true; hit = true;
    }
    if (fist) {
      if (Math.random() < 0.9) G.fx.spark(b.pos.x - b.vel.x * 0.012, b.pos.y + (Math.random() - 0.5), b.pos.z - b.vel.z * 0.012, 0, 0.5, 0, 0.3, 1.3, 0xff8a2a);
    } else if (Math.random() < 0.4) G.fx.spark(b.pos.x, b.pos.y, b.pos.z, 0, 0, 0, 0.15, 0.45, b.color);
    if (done) {
      if (hit) {
        if (fist) { // маленький оранжевый взрыв без урона по площади
          G.fx.burst(b.pos, FIST_COL, 22, 11, 0.7, 0.45); G.fx.burst(b.pos, 0xffd080, 10, 6, 0.5, 0.3);
          G.fx.flare(b.pos, 0xff8a2a, 5, 0.3); G.fx.ring(V.set(b.pos.x, 0, b.pos.z), FIST_COL, 0.5, 4, 0.3);
          G.sfx('heavy', 0.55, b.owner, 0.05);
        } else G.fx.burst(b.pos, b.color, 5, 5, 0.3, 0.2);
      }
      b.p.used = false; b.p.m.visible = false; G.projectiles.splice(i, 1); continue;
    }
    b.p.m.position.copy(b.pos);
    b.p.m.lookAt(V.copy(b.pos).add(b.vel));
    if (fist) b.p.m.rotateZ((b.spin += dt * 4));
  }
  updateFans(G, dt);
}
export function clearProjectiles(G) {
  for (const b of G.projectiles) { b.p.used = false; b.p.m.visible = false; }
  G.projectiles.length = 0;
  for (const fan of G.fans) for (const s of fan.s) { s.p.used = false; s.p.m.visible = false; }
  G.fans.length = 0;
}

// ---------- нити Терпения ----------
function updateFans(G, dt) {
  const m = G.monster;
  for (let i = G.fans.length - 1; i >= 0; i--) {
    const fan = G.fans[i];
    fan.t += dt;
    const k = fan.t / fan.life;
    if (k >= 1 || G.state === 'results' || G.state === 'menu') { for (const s of fan.s) { s.p.used = false; s.p.m.visible = false; } G.fans.splice(i, 1); continue; }
    const grow = Math.min(1, fan.t / 0.12), fade = k > 0.85 ? (1 - k) / 0.15 : 1;
    for (let j = 0; j < fan.s.length; j++) {
      const s = fan.s[j], mm = s.p.m;
      mm.scale.set(1, 1, fan.len * grow);
      mm.material.opacity = (s.hit ? 0.45 : 0.9) * fade * (0.85 + Math.sin(fan.t * 20 + j) * 0.15);
      if (Math.random() < 0.08) { const d = Math.random() * fan.len * grow; G.fx.spark(fan.o.x + s.d.x * d, fan.o.y + s.d.y * d, fan.o.z + s.d.z * d, 0, 0.6, 0, 0.35, 0.35, 0x8ff8f8); }
    }
    // каждая нить может снять одно уклонение, весь веер — не больше двух
    if (grow < 1 || fan.hits >= 2 || !m || m.dead || G.state !== 'fight') continue;
    if (Math.abs(m.pos.y + 3 - fan.o.y) > 4) continue;
    for (const s of fan.s) {
      if (s.hit) continue;
      const rx = m.pos.x - fan.o.x, rz = m.pos.z - fan.o.z;
      const along = rx * s.d.x + rz * s.d.z;
      if (along < 0 || along > fan.len + m.radius) continue;
      if (Math.abs(rx * s.d.z - rz * s.d.x) > m.radius + 0.25) continue;
      if (damageMonster(G, m, fan.dmg, fan.owner, { noLast: true, color: STRING_COL })) {
        s.hit = true; fan.hits++;
        V.copy(fan.o).addScaledVector(s.d, along); V.y = m.pos.y + 3;
        G.fx.burst(V, STRING_COL, 12, 7, 0.45, 0.35);
        G.sfx('block', 0.45, fan.owner, 0.05);
      }
      break;
    }
  }
}
function spawnFan(G, f, dir) {
  const n = 7 + Math.floor(Math.random() * 3), spread = (45 * Math.PI) / 180;
  const fan = { owner: f, o: new THREE.Vector3(f.pos.x, f.pos.y + 3, f.pos.z), len: 18, t: 0, life: rand(3, 4), hits: 0, dmg: 30, s: [] };
  const base = Math.atan2(dir.x, dir.z);
  for (let i = 0; i < n; i++) {
    const p = take(G.ha.strings);
    if (!p) break;
    const a = base + (i / (n - 1) - 0.5) * spread;
    const d = new THREE.Vector3(Math.sin(a), (Math.random() - 0.5) * 0.06, Math.cos(a));
    p.m.visible = true; p.m.position.copy(fan.o); p.m.lookAt(V.copy(fan.o).add(d)); p.m.scale.set(1, 1, 0.01);
    fan.s.push({ p, d, hit: false });
  }
  G.fans.push(fan);
  G.fx.flare(fan.o, STRING_COL, 3, 0.25);
}

// ---------- позы (R6: руки жёсткие, вращаются в плечах) ----------
const poseSlash = (p, k, side) => {
  const e = easeOut(k);
  p.armR.rotation.set(-1.45, 0, side > 0 ? lerp(1.3, -0.9, e) : lerp(-0.9, 1.3, e));
  p.hips.rotation.y = side > 0 ? lerp(0.45, -0.45, e) : lerp(-0.45, 0.45, e);
};
const poseChop = (p, k) => { const e = easeOut(k); p.armR.rotation.set(lerp(-2.9, -0.9, e), 0, 0.15); p.hips.rotation.x = 0.15 * e; };
const posePunch = (p, k, right) => {
  const e = Math.sin(Math.min(1, k * 1.3) * Math.PI);
  const a = right ? p.armR : p.armL, b = right ? p.armL : p.armR;
  a.rotation.set(-0.4 - e * 1.25, 0, 0); b.rotation.set(-1.2, 0, right ? 0.3 : -0.3);
  p.hips.rotation.y = (right ? -0.45 : 0.45) * e; p.hips.rotation.x = 0.12 * e;
};
const poseAim = (p, k, recoil = 0.3) => {
  const r = recoil * Math.max(0, 1 - k * 3);
  p.armR.rotation.set(-1.57 - r, 0, 0); p.armL.rotation.set(-1.0, 0, 0.5); p.hips.rotation.y = 0.2;
};
const poseCast = (p, k) => { const e = easeOut(Math.min(1, k * 2.5)); p.armR.rotation.set(-1.6 * e, 0, -0.25 * e); p.armL.rotation.set(-1.6 * e, 0, 0.25 * e); };
const poseItem = (p, k) => { const e = Math.sin(Math.min(1, k) * Math.PI); p.armR.rotation.set(-2.3 * e, 0, -0.35 * e); p.neck.rotation.x = -0.2 * e; };
const poseReload = (p, k) => { p.armR.rotation.set(-0.9, 0, -0.5); p.armL.rotation.set(-1.1, 0, 0.6); p.neck.rotation.x = 0.25; p.armR.rotation.x += Math.sin(k * Math.PI * 6) * 0.12; };

// ---------- M1 ----------
const dmgMul = (G, f) => (f.roleId === 'brv' ? 1.1 : 1) * (G.time < f.mightUntil ? 1.35 : 1);
// Ближний бой (§4.4): досягаемость 5 стадов от тела, дуга 100°, удар засчитывается через 0.12 с
function meleeHit(G, f, dmg, o) {
  const m = G.monster;
  if (!m || m.dead) return false;
  const d = dist2(f.pos, m.pos);
  if (d > MELEE.reach + m.radius * 0.6 || Math.abs(m.pos.y - f.pos.y) > 6) return false;
  if (angleTo(f, m.pos) > MELEE.arc + (d < 2.5 ? 0.6 : 0.1)) return false;
  return damageMonster(G, m, dmg, f, o);
}
function melee(G, f, aimPt, o) {
  f.use('m1', o.cd);
  const m = G.monster;
  if (m && !m.dead && dist2(f.pos, m.pos) < MELEE.reach + m.radius + 3) f.faceTo(m.pos, true);
  else if (aimPt) f.faceTo(aimPt, true);
  f.startAction({
    name: 'm1', dur: o.dur, lock: true, moveMul: 0.85, pose: (p, k) => o.pose(p, k),
    update(ff, t) {
      if (!this.hit && t >= MELEE.hitAt) {
        this.hit = true;
        o.fx(ff);
        G.sfx(o.sfx, 0.45, ff, 0.04);
        meleeHit(G, ff, o.dmg * dmgMul(G, ff), { dodges: o.dodges || 1, color: o.color });
      }
    },
  });
  return true;
}

export function humanM1(G, f, aimPt = null) {
  if (!f.canAct() || !f.ready('m1')) return false;
  const col = f.color;
  if (f.roleId === 'det') {
    f.combo = (f.combo + 1) % 2;
    const side = f.combo ? -1 : 1;
    return melee(G, f, aimPt, { cd: f.role.m1.cd, dur: 0.26, dmg: 30, sfx: 'slash', pose: (p, k) => poseSlash(p, k, side),
      fx: (ff) => G.fx.slash(ff.pos, ff.yaw, col, { tilt: side > 0 ? -0.35 : 0.35, flip: side < 0, scale: 1.1 }) });
  }
  if (f.roleId === 'pat') {
    f.combo = (f.combo + 1) % 2;
    const side = f.combo ? -1 : 1;
    return melee(G, f, aimPt, { cd: f.role.m1.cd, dur: 0.3, dmg: 30, sfx: 'swing', pose: (p, k) => poseSlash(p, k, side),
      fx: (ff) => G.fx.slash(ff.pos, ff.yaw, 0xbff8ff, { tilt: side > 0 ? -0.3 : 0.3, flip: side < 0, scale: 1.0 }) });
  }
  if (f.roleId === 'brv') {
    f.combo = (f.combo + 1) % 2;
    const right = f.combo === 1;
    return melee(G, f, aimPt, { cd: f.role.m1.cd, dur: 0.32, dmg: 40, dodges: 2, sfx: 'swing', color: 0xf86800, pose: (p, k) => posePunch(p, k, right),
      fx: (ff) => { ff.fwd(V); V3.copy(ff.pos).addScaledVector(V, 2.6); V3.y += 3; G.fx.flare(V3, col, 2.4, 0.15); } });
  }
  if (f.roleId === 'jus') {
    const m = G.monster;
    const close = m && !m.dead && dist2(f.pos, m.pos) < MELEE.reach + m.radius * 0.5 && (f.bot || angleTo(f, m.pos) < 1.2 || !aimPt);
    // без пуль или вплотную — удар рукоятью
    if (f.ammo <= 0 || close) {
      return melee(G, f, aimPt, { cd: 0.7, dur: 0.3, dmg: f.role.m1.whip, sfx: 'swing', pose: poseChop,
        fx: (ff) => G.fx.slash(ff.pos, ff.yaw, 0xfff8a0, { tilt: 1.4, scale: 0.9 }) });
    }
    f.use('m1', f.role.m1.cd);
    f.ammo--;
    if (aimPt) f.faceTo(aimPt, true);
    const tint = G.time < f.potionUntil ? POTION_TINT[f.potionId] : null;
    f.startAction({
      name: 'm1', dur: 0.2, lock: true, moveMul: 0.85, pose: (p, k) => poseAim(p, k), face: m && !m.dead && !f.isPlayer ? m : null,
      update(ff, t) {
        if (!this.hit && t >= 0.03) {
          this.hit = true;
          muzzle(ff, V); aimDir(G, ff, V, V2, aimPt);
          ff.faceTo(V3.copy(ff.pos).add(V2), true);
          muzzle(ff, V);
          shoot(G, ff, 'bullet', V, V2, { dmg: f.role.m1.dmg * dmgMul(G, ff), speed: 120, range: 80, size: 0.36, len: 1.5, color: tint ?? BULLET_COL });
          G.sfx('block', 0.4, ff, 0.05); G.sfx('hit', 0.25, ff, 0.05);
        }
      },
    });
    G.onEvent('ammo', { f });
    return true;
  }
  return false;
}

// ---------- способность души (R) ----------
export function abilityCd(G, f) { return (f.role.ability?.cd || 0) * (G.time < f.speedUntil ? 0.5 : 1); }
export function humanAbility(G, f, aimPt = null) {
  const ab = f.role.ability;
  if (!ab || !f.canAct() || !f.ready('R')) return false;
  if (f.roleId === 'pat') {
    f.use('R', abilityCd(G, f));
    V.set(f.pos.x, f.pos.y + 3, f.pos.z); aimDir(G, f, V, V2, aimPt); V2.y = 0; V2.normalize();
    f.faceTo(V3.copy(f.pos).add(V2), true);
    spawnFan(G, f, V2);
    f.startAction({ name: 'R', dur: 0.35, lock: true, moveMul: 0.6, pose: poseCast });
    G.sfx('slash', 0.5, f); G.sfx('charge', 0.25, f, 0.1);
    G.onEvent('ability', { f });
    return true;
  }
  if (f.roleId === 'brv') {
    f.use('R', abilityCd(G, f));
    f.fwd(V4); V.set(f.pos.x, f.pos.y + 3, f.pos.z).addScaledVector(V4, 1.2);
    aimDir(G, f, V, V2, aimPt);
    f.faceTo(V3.copy(f.pos).add(V2), true);
    V.set(f.pos.x + V2.x * 1.8, f.pos.y + 3, f.pos.z + V2.z * 1.8);
    shoot(G, f, 'fist', V, V2, { dmg: 40 * dmgMul(G, f), speed: 70, range: 60, size: 2, color: FIST_COL });
    f.startAction({ name: 'R', dur: 0.35, lock: true, moveMul: 0.5, pose: (p, k) => posePunch(p, k, true) });
    G.sfx('dash', 0.6, f); G.sfx('swing', 0.6, f);
    G.onEvent('ability', { f });
    return true;
  }
  if (f.roleId === 'jus') {
    if (f.ammo >= 6) { if (f.isPlayer) G.toast('Барабан и так полный'); return false; }
    f.use('R', abilityCd(G, f));
    const dur = G.time < f.speedUntil ? 0.5 : 1.0;
    f.startAction({
      name: 'R', dur, lock: true, moveMul: 0.75, pose: poseReload,
      update(ff, t) { if (!this.c1 && t > dur * 0.35) { this.c1 = true; G.jd?.('reload', ff, 0.9); } },
      end(ff, cancelled) { if (!cancelled) { ff.ammo = 6; G.sfx('block', 0.35, ff); G.onEvent('ammo', { f: ff }); } },
    });
    G.onEvent('ability', { f });
    return true;
  }
  return false;
}

// ---------- предметы ----------
// Пользоваться можно и в интро (пока Судья говорит) — как в UJD: «пейте зелья до конца катсцены»
const itemTime = (G) => G.state === 'fight' || G.state === 'intro';
// Пирог: +15% макс. HP (не меньше 100). До 3 за раунд. Укус, рука вверх 0.3 с, вспышка полоски HP — без «+N».
export function usePie(G, f) {
  if (f.dead || f.pies <= 0 || f.busy || f.flung || !itemTime(G)) return false;
  f.pies--;
  f.heal(pieHeal(f.maxHp));
  f.startAction({ name: 'item', dur: 0.3, lock: true, moveMul: 1, pose: poseItem });
  V.set(f.pos.x, f.pos.y + 4, f.pos.z);
  G.fx.burst(V, 0xffd090, 8, 4, 0.35, 0.45, { up: 3, g: 6 });
  f.pulseAt = G.time; f.barFlashAt = G.time;
  G.jd?.('bite', f, 1);
  G.onEvent('pie', { f, left: f.pies });
  return true;
}
// Зелье (одно за раунд, 45 с): скорость / сила / лечение / святое
export function usePotion(G, f) {
  if (f.dead || !f.potion || f.busy || f.flung || !itemTime(G)) return false;
  const id = f.potion, P = POTIONS[id], now = G.time, until = now + POTION_TIME;
  f.potion = null; f.potionId = id; f.potionUntil = until;
  if (id === 'speed') f.speedUntil = until;
  else if (id === 'might') f.mightUntil = until;
  else if (id === 'heal') { f.heal(150); f.healUntil = until; f.healRate = (0.56 * f.maxHp) / POTION_TIME; f.krClearT = 0; f.karma = 0; }
  else if (id === 'holy') { f.holyUntil = until; f.shield = f.maxHp; f.shieldUntil = until; f.karma = 0; }
  if (f.model.aura) f.model.aura.material.color.set(P.color);
  f.startAction({ name: 'item', dur: 0.4, lock: true, moveMul: 1, pose: poseItem });
  // искры цвета зелья поднимаются вверх
  for (let i = 0; i < 14; i++) G.fx.spark(f.pos.x + (Math.random() - 0.5) * 2, f.pos.y + Math.random() * 2, f.pos.z + (Math.random() - 0.5) * 2, 0, 3 + Math.random() * 4, 0, 0.8, 0.6, P.color);
  G.fx.ring(f.pos, P.color, 0.5, 5, 0.45);
  f.barFlashAt = G.time;
  G.jd?.('glug', f, 1);
  G.onEvent('potion', { f, id });
  return true;
}

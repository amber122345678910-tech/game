// Способности людей: Решимость (нож), Терпение (лента, лечение, щит, воскрешение),
// Храбрость (перчатки, таран, провокация, сокрушение), Справедливость (пистолет, заряд, дробь, отскок).
import * as THREE from 'three';
import { damageMonster, reviveHuman, dist2, angleTo, clamp, lerp, easeOut, easeIn } from './combat.js';
import { COST } from './data.js';

const V = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3();

// ---------- пули ----------
export function initHumanAssets(G) {
  const geo = new THREE.BoxGeometry(1, 1, 1); geo.translate(0, 0, -0.5);
  const pool = [];
  for (let i = 0; i < 30; i++) {
    const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: 0xffe23a, transparent: true, opacity: 0.95, depthWrite: false, blending: THREE.AdditiveBlending }));
    m.visible = false; G.scene.add(m); pool.push({ m, used: false });
  }
  G.ha = { bullets: pool };
}

function muzzle(f, out) {
  if (f.model.tip) { f.model.root.updateMatrixWorld(true); f.model.tip.getWorldPosition(out); }
  else out.set(f.pos.x, f.pos.y + 3.5, f.pos.z);
  return out;
}

// Направление прицела человека: на Судью (автонаводка) или куда смотрит камера
export function aimDir(G, f, from, out) {
  const m = G.monster;
  let auto = m && !m.dead && dist2(f.pos, m.pos) < 90;
  if (auto && f.isPlayer && G.camFwd) {
    V3.set(m.pos.x - f.pos.x, 0, m.pos.z - f.pos.z).normalize();
    if (V3.dot(G.camFwd) < 0.2 && dist2(f.pos, m.pos) > 12) auto = false;
  }
  if (auto) out.set(m.pos.x - from.x, m.pos.y + 3.3 - from.y, m.pos.z - from.z);
  else if (f.isPlayer && G.camFwd) out.set(G.camFwd.x, 0, G.camFwd.z);
  else f.fwd(out);
  return out.normalize();
}

function fireBullet(G, f, from, dir, o) {
  const p = G.ha.bullets.find((b) => !b.used);
  if (!p) return;
  p.used = true; p.m.visible = true;
  p.m.material.color.setHex(o.color ?? 0xffe23a);
  const s = o.size ?? 0.22;
  p.m.scale.set(s, s, o.len ?? 2.2);
  G.projectiles.push({ p, pos: from.clone(), vel: dir.clone().multiplyScalar(o.speed ?? 120), life: o.life ?? 0.8, owner: f, dmg: o.dmg, cost: o.cost ?? COST.normal, size: s, heavy: !!o.heavy, color: o.color ?? 0xffe23a });
  G.fx.flare(from, o.color ?? 0xffe23a, o.heavy ? 3 : 1.5, 0.12);
}

export function updateProjectiles(G, dt) {
  const m = G.monster;
  for (let i = G.projectiles.length - 1; i >= 0; i--) {
    const b = G.projectiles[i];
    b.life -= dt;
    b.pos.addScaledVector(b.vel, dt);
    let done = b.life <= 0 || b.pos.y < 0;
    if (!done && m && !m.dead && dist2(b.pos, m.pos) < m.radius + b.size + 0.3 && b.pos.y > m.pos.y - 0.5 && b.pos.y < m.pos.y + 8) {
      damageMonster(G, m, b.dmg, b.owner, { cost: b.cost, heavy: b.heavy, color: b.color });
      done = true;
    }
    if (Math.random() < (b.heavy ? 1 : 0.4)) G.fx.spark(b.pos.x, b.pos.y, b.pos.z, 0, 0, 0, b.heavy ? 0.3 : 0.15, b.heavy ? 1.2 : 0.4, b.color);
    if (done) { b.p.used = false; b.p.m.visible = false; G.projectiles.splice(i, 1); continue; }
    b.p.m.position.copy(b.pos);
    b.p.m.lookAt(V.copy(b.pos).add(b.vel));
  }
}
export function clearProjectiles(G) { for (const b of G.projectiles) { b.p.used = false; b.p.m.visible = false; } G.projectiles.length = 0; }

// ---------- общее ----------
function softLock(G, f, maxD = 11) {
  const m = G.monster;
  if (m && !m.dead && dist2(f.pos, m.pos) < maxD) { f.faceTo(m.pos, true); return m; }
  return null;
}
function meleeHit(G, f, range, arc, dmg, o) {
  const m = G.monster;
  if (!m || m.dead) return false;
  if (dist2(f.pos, m.pos) - m.radius > range || angleTo(f, m.pos) > arc || Math.abs(m.pos.y - f.pos.y) > 6) return false;
  damageMonster(G, m, dmg, f, o);
  return true;
}
function chase(f, tgt, range, dt, speed = 14) {
  if (!tgt) return;
  const d = dist2(f.pos, tgt.pos) - tgt.radius;
  if (d > range * 0.7 && d < range + 4) { V.subVectors(tgt.pos, f.pos).setY(0).normalize(); f.pos.addScaledVector(V, Math.min(d - range * 0.6, speed * dt)); }
}

function comboMelee(G, f, o) {
  const n = o.dmgs.length;
  const i = G.time < f.comboUntil ? (f.combo + 1) % n : 0; f.combo = i;
  const dur = o.durs[i], last = i === n - 1;
  f.use('m1', dur + (last ? o.endLag : 0)); f.comboUntil = G.time + dur + 0.5;
  const tgt = softLock(G, f, o.range + 7);
  f.startAction({
    name: 'm1', dur, lock: true, moveMul: 0.35,
    pose: (p, k) => o.pose(p, k, i, f),
    update(ff, t, dt) {
      if (t < dur * 0.45) chase(ff, tgt, o.range, dt);
      if (!this.hit && t >= dur * (o.hitAt ?? 0.4)) {
        this.hit = true;
        o.fx(ff, i, last);
        G.sfx(o.sfx, 0.45, ff, 0.04);
        f.fwd(V2).multiplyScalar(last ? 4 : 0);
        meleeHit(G, ff, o.range, o.arc, o.dmgs[i], { cost: last ? o.costLast : o.cost, kb: V2 });
      }
    },
  });
  return true;
}

// ---------- позы ----------
const poseSlash = (p, k, side) => {
  const e = easeOut(k);
  p.armR.rotation.set(-1.45, 0, side > 0 ? lerp(1.3, -0.9, e) : lerp(-0.9, 1.3, e));
  p.hips.rotation.y = side > 0 ? lerp(0.5, -0.5, e) : lerp(-0.5, 0.5, e);
};
const poseStab = (p, k) => {
  const e = Math.sin(Math.min(1, k * 1.4) * Math.PI);
  p.armR.rotation.set(-1.3 - e * 0.35, 0, -0.2); p.hips.rotation.x = 0.15 * e; p.hips.rotation.y = -0.3 * e;
};
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
const poseCast = (p, k) => { const e = easeOut(Math.min(1, k * 2.5)); p.armR.rotation.set(-2.5 * e, 0, 0.2); p.armL.rotation.set(-2.5 * e, 0, -0.2); };

// ---------- M1 ----------
export function humanM1(G, f) {
  if (!f.canAct() || !f.ready('m1')) return false;
  const col = f.color;
  if (f.roleId === 'det') return comboMelee(G, f, {
    dmgs: [8, 8, 9, 15], durs: [0.24, 0.24, 0.26, 0.36], endLag: 0.3, range: 4.4, arc: 1.15, cost: COST.normal, costLast: 18, sfx: 'slash',
    pose: (p, k, i) => (i === 3 ? poseStab(p, k) : poseSlash(p, k, i % 2 ? -1 : 1)),
    fx: (ff, i, last) => G.fx.slash(ff.pos, ff.yaw, col, { tilt: last ? 1.4 : i % 2 ? 0.35 : -0.35, flip: i % 2 === 1, scale: last ? 1.2 : 1 }),
  });
  if (f.roleId === 'pat') return comboMelee(G, f, {
    dmgs: [7, 7, 11], durs: [0.34, 0.34, 0.42], endLag: 0.3, range: 7.2, arc: 0.95, cost: 12, costLast: 16, sfx: 'swing', hitAt: 0.45,
    pose: (p, k, i) => { const e = easeOut(k); p.armR.rotation.set(lerp(-2.7, -0.9, e), 0, i === 1 ? lerp(-0.6, 0.6, e) : 0.2); p.hips.rotation.y = lerp(0.3, -0.3, e); },
    fx: (ff, i) => { G.fx.slash(ff.pos, ff.yaw, col, { tilt: i === 2 ? 1.5 : 0.2 * (i ? -1 : 1), scale: 2.1, life: 0.22 }); },
  });
  if (f.roleId === 'brv') return comboMelee(G, f, {
    dmgs: [10, 10, 17], durs: [0.3, 0.3, 0.42], endLag: 0.35, range: 4.1, arc: 1.05, cost: COST.normal, costLast: 20, sfx: 'swing',
    pose: (p, k, i) => (i === 2 ? (p.armR.rotation.set(lerp(-2.8, -1.2, easeOut(k)), 0, 0), p.armL.rotation.set(lerp(-2.8, -1.2, easeOut(k)), 0, 0), (p.hips.rotation.x = 0.25 * k)) : posePunch(p, k, i === 0)),
    fx: (ff, i, last) => { ff.fwd(V); V3.copy(ff.pos).addScaledVector(V, 2.6); V3.y += 3; G.fx.flare(V3, col, last ? 3.5 : 2, 0.15); if (last) G.fx.ring(V3.setY(ff.pos.y), col, 0.5, 4, 0.3); },
  });
  if (f.roleId === 'jus') {
    f.use('m1', 0.45);
    const m = softLock(G, f, 120);
    f.startAction({
      name: 'm1', dur: 0.22, lock: true, moveMul: 0.75, pose: (p, k) => poseAim(p, k), face: m && !f.isPlayer ? m : null,
      update(ff, t) {
        if (!this.hit && t >= 0.04) {
          this.hit = true;
          muzzle(ff, V); aimDir(G, ff, V, V2);
          ff.faceTo(V3.copy(ff.pos).add(V2), true);
          muzzle(ff, V);
          fireBullet(G, ff, V, V2, { dmg: 7, cost: 12 });
          G.sfx('block', 0.35, ff, 0.05);
        }
      },
    });
    return true;
  }
  return false;
}

// ---------- рывок ----------
export function humanDash(G, f, dir) {
  if (f.dead || !f.ready('dash') || f.stunned || f.grab || G.state !== 'fight') return false;
  if (f.action) { if (f.action.name === 'm1') f.cancelAction(); else return false; }
  if (dir.lengthSq() < 0.01) f.fwd(dir);
  f.use('dash', 2.4);
  f.dash(dir, 12, 0.2);
  G.fx.after(f.pos, f.color, 5.5, 0.3);
  G.sfx('dash', 0.5, f);
  return true;
}

// ---------- навыки ----------
export function humanSkill(G, f, idx) {
  const id = 's' + (idx + 1);
  if (!f.canAct() || !f.ready(id)) return false;
  const fn = SKILLS[f.roleId][idx];
  const ok = fn(G, f);
  if (ok) { f.use(id, f.role.skills[idx].cd); G.onEvent('skill', { f, idx }); }
  return ok;
}
export function canRevive(G, f) {
  if (f.reviveCharges <= 0) return null;
  let best = null, bd = 13;
  for (const h of G.humans) if (h.dead && h !== f) { const d = dist2(h.pos, f.pos); if (d < bd) { bd = d; best = h; } }
  return best;
}
export function healTarget(G, f, range = 32) {
  let best = null, bk = 0.97;
  for (const h of G.humans) {
    if (h.dead || dist2(h.pos, f.pos) > range) continue;
    const k = h.hp / h.maxHp - (h.karma > 4 ? 0.1 : 0);
    if (k < bk) { bk = k; best = h; }
  }
  return best;
}

const SKILLS = {
  det: [
    // Рывок-разрез
    (G, f) => {
      const m = G.monster;
      if (m && !m.dead && dist2(f.pos, m.pos) < 22) V.subVectors(m.pos, f.pos).setY(0).normalize(); else f.fwd(V);
      f.dash(V, 14, 0.24);
      G.sfx('dash', 0.6, f); G.fx.after(f.pos, f.color, 5.5, 0.35);
      f.startAction({
        name: 's1', dur: 0.32, lock: true, moveMul: 0,
        pose: (p) => { p.armR.rotation.set(-1.5, 0, -1.0); p.hips.rotation.x = 0.5; p.armL.rotation.x = 0.8; },
        update(ff) {
          if (!this.hit && m && !m.dead && dist2(ff.pos, m.pos) < m.radius + 2.8 && Math.abs(m.pos.y - ff.pos.y) < 6) {
            this.hit = true;
            G.fx.slash(m.pos, ff.yaw, ff.color, { scale: 1.5, tilt: 0.2 });
            G.sfx('slash', 0.7, ff);
            damageMonster(G, m, 18, ff, { cost: COST.normal });
          }
        },
      });
      return true;
    },
    // Шквал
    (G, f) => {
      const tgt = softLock(G, f, 12);
      f.startAction({
        name: 's2', dur: 0.98, lock: true, moveMul: 0.2,
        pose: (p, k) => { const s = Math.sin(k * 7 * Math.PI * 2); p.armR.rotation.set(-1.45 - s * 0.3, 0, s * 0.6); p.armL.rotation.set(-0.8, 0, -0.4); p.hips.rotation.y = s * 0.2; },
        update(ff, t, dt) {
          chase(ff, tgt, 4.6, dt, 10);
          this.n ??= 0;
          if (this.n < 7 && t >= 0.08 + this.n * 0.12) {
            const i = this.n++;
            if (tgt && !tgt.dead) ff.faceTo(tgt.pos, true);
            G.fx.slash(ff.pos, ff.yaw, ff.color, { tilt: (i % 2 ? 1 : -1) * (0.4 + Math.random() * 0.8), flip: i % 2 === 1, scale: 0.85, life: 0.12 });
            G.sfx('slash', 0.35, ff, 0.05);
            meleeHit(G, ff, 4.8, 1.25, 6, { cost: COST.light });
          }
        },
      });
      return true;
    },
    // Решающий удар
    (G, f) => {
      const tgt = softLock(G, f, 16);
      G.sfx('charge', 0.6, f);
      f.startAction({
        name: 's3', dur: 1.0, lock: true, moveMul: 0.1, face: tgt,
        pose: (p, k) => {
          if (k < 0.5) { const e = easeOut(k / 0.5); p.armR.rotation.set(-2.9 * e, 0, 0.6 * e); p.hips.rotation.y = 0.6 * e; p.legL.rotation.x = -0.4 * e; }
          else { const e = easeOut(Math.min(1, (k - 0.5) / 0.15)); p.armR.rotation.set(lerp(-2.9, -0.6, e), 0, lerp(0.6, -0.8, e)); p.hips.rotation.y = lerp(0.6, -0.6, e); p.hips.rotation.x = 0.3 * e; }
        },
        update(ff, t, dt) {
          if (t < 0.5) {
            if (Math.random() < 0.8 && ff.model.tip) { ff.model.root.updateMatrixWorld(true); ff.model.tip.getWorldPosition(V); G.fx.spark(V.x, V.y, V.z, (Math.random() - 0.5) * 4, 3, (Math.random() - 0.5) * 4, 0.4, 0.9, 0xff2b3d); }
            if (Math.random() < 0.5) { const a = Math.random() * 7; G.fx.spark(ff.pos.x + Math.cos(a) * 3, ff.pos.y + 0.3, ff.pos.z + Math.sin(a) * 3, -Math.cos(a) * 6, 2, -Math.sin(a) * 6, 0.45, 0.7, 0xff2b3d); }
          } else if (t < 0.65) {
            if (tgt && !tgt.dead) { const d = dist2(ff.pos, tgt.pos) - tgt.radius; if (d > 3) { V.subVectors(tgt.pos, ff.pos).setY(0).normalize(); ff.pos.addScaledVector(V, Math.min(d - 2.5, 45 * dt)); } }
          }
          if (!this.hit && t >= 0.6) {
            this.hit = true;
            G.fx.slash(ff.pos, ff.yaw, 0xff2b3d, { scale: 2.3, tilt: -0.5, life: 0.3, y: 3 });
            G.fx.slash(ff.pos, ff.yaw, 0xffffff, { scale: 1.7, tilt: -0.5, life: 0.2, y: 3 });
            G.sfx('slash', 1, ff);
            if (ff.isPlayer) G.fx.flash('#ff2b3d', 0.25);
            meleeHit(G, ff, 6.2, 1.4, 65, { cost: 40, heavy: true, color: 0xff2b3d, stun: 0.4 });
          }
        },
      });
      return true;
    },
  ],
  pat: [
    // Исцеление
    (G, f) => {
      const t = healTarget(G, f);
      if (!t) { if (f.isPlayer) G.toast('Рядом нет раненых союзников'); return false; }
      f.startAction({
        name: 's1', dur: 0.4, lock: true, moveMul: 0.4, pose: poseCast, face: t === f ? null : t,
        update(ff, tt) {
          if (!this.hit && tt >= 0.15) {
            this.hit = true;
            if (t.dead) return;
            muzzle(ff, V); V2.set(t.pos.x, t.pos.y + 3, t.pos.z);
            if (t !== ff) G.fx.line(V, V2, 0x7dffc0, 0.25, 0.4);
            const got = t.heal(35, ff);
            G.fx.burst(V2, 0x7dffc0, 18, 6, 0.6, 0.8, { up: 6, g: -3 });
            G.fx.ring(t.pos, 0x7dffc0, 0.5, 4, 0.5);
            G.fx.text(V2.setY(t.pos.y + 5.5), '+' + Math.round(got), 'heal');
            G.sfx('spawn', 0.6, ff);
            G.onEvent('heal', { f: ff, t });
          }
        },
      });
      return true;
    },
    // Щит
    (G, f) => {
      f.startAction({
        name: 's2', dur: 0.45, lock: true, moveMul: 0.3, pose: poseCast,
        update(ff, t) {
          if (!this.hit && t >= 0.18) {
            this.hit = true;
            G.fx.ring(ff.pos, 0x8fe9ff, 1, 16, 0.6);
            G.sfx('block', 0.8, ff);
            for (const h of G.humans) if (!h.dead && dist2(h.pos, ff.pos) < 16) {
              h.shield = 40; h.shieldUntil = G.time + 6;
              G.fx.burst(V.set(h.pos.x, h.pos.y + 3, h.pos.z), 0x8fe9ff, 10, 5, 0.6, 0.5);
            }
          }
        },
      });
      return true;
    },
    // Второй шанс
    (G, f) => {
      const t = canRevive(G, f);
      if (!t) { if (f.isPlayer) G.toast(f.reviveCharges > 0 ? 'Подойди к душе павшего союзника' : 'Воскрешение уже использовано'); return false; }
      G.sfx('charge', 0.5, f);
      f.startAction({
        name: 's3', dur: 1.2, lock: true, moveMul: 0, pose: poseCast, face: t,
        update(ff, tt) {
          if (Math.random() < 0.8) { const a = Math.random() * 7; G.fx.spark(t.pos.x + Math.cos(a) * 2.5, 0.3, t.pos.z + Math.sin(a) * 2.5, 0, 6, 0, 0.5, 0.7, 0x8fffd0); }
          if (!this.hit && tt >= 1.15) { this.hit = true; if (t.dead) { ff.reviveCharges = 0; reviveHuman(G, t, ff); } }
        },
      });
      return true;
    },
  ],
  brv: [
    // Таран
    (G, f) => {
      const m = G.monster;
      if (m && !m.dead && dist2(f.pos, m.pos) < 20) V.subVectors(m.pos, f.pos).setY(0).normalize(); else f.fwd(V);
      f.dash(V, 15, 0.32, false);
      G.sfx('dash', 0.7, f);
      f.startAction({
        name: 's1', dur: 0.4, lock: true, moveMul: 0,
        pose: (p) => { p.armR.rotation.set(-1.6, 0, 0); p.armL.rotation.set(-1.6, 0, 0); p.hips.rotation.x = 0.4; },
        update(ff) {
          if (Math.random() < 0.8) G.fx.spark(ff.pos.x, ff.pos.y + 3, ff.pos.z, (Math.random() - 0.5) * 4, 1, (Math.random() - 0.5) * 4, 0.3, 1, 0xff9a1f);
          if (!this.hit && m && !m.dead && dist2(ff.pos, m.pos) < m.radius + 2.4 && Math.abs(m.pos.y - ff.pos.y) < 6) {
            this.hit = true; ff.dashT = 0;
            ff.fwd(V2).multiplyScalar(14);
            G.fx.ring(m.pos, 0xff9a1f, 1, 6, 0.35);
            if (ff.isPlayer || m.isPlayer) G.fx.shake(0.35);
            damageMonster(G, m, 22, ff, { cost: 20, stun: 0.8, kb: V2, color: 0xff9a1f });
          }
        },
      });
      return true;
    },
    // Провокация
    (G, f) => {
      f.tauntUntil = G.time + 6;
      G.fx.ring(f.pos, 0xff9a1f, 1, 12, 0.6);
      G.fx.text(V.set(f.pos.x, f.pos.y + 6.5, f.pos.z), 'ПРОВОКАЦИЯ!', 'taunt', 1.1);
      G.sfx('march', 0.8, f);
      f.startAction({ name: 's2', dur: 0.5, lock: true, moveMul: 0.2, face: G.monster && !G.monster.dead ? G.monster : null,
        pose: (p, k) => { const s = Math.sin(k * Math.PI * 4); p.armR.rotation.set(-2.6, 0, 0.3 + s * 0.3); p.armL.rotation.set(-2.6, 0, -0.3 - s * 0.3); } });
      return true;
    },
    // Сокрушение
    (G, f) => {
      const m = G.monster;
      const tgt = m && !m.dead && dist2(f.pos, m.pos) < 16 ? m : null;
      f.vy = 21; f.onGround = false;
      G.sfx('jump', 0.7, f);
      const goal = tgt ? V3.subVectors(tgt.pos, f.pos).setY(0) : f.fwd(V3).multiplyScalar(6);
      const gl = goal.length(); if (tgt && gl > 0.1) goal.multiplyScalar(Math.max(0, gl - tgt.radius - 1.5) / gl);
      const move = goal.clone();
      f.startAction({
        name: 's3', dur: 0.9, lock: true, moveMul: 0, grav: 1.35,
        pose: (p, k, a) => {
          if (!a.landed && k < 0.55) { p.armR.rotation.set(-3.0, 0, 0.2); p.armL.rotation.set(-3.0, 0, -0.2); p.legL.rotation.x = -0.6; p.legR.rotation.x = 0.4; }
          else { p.armR.rotation.set(-0.8, 0, 0); p.armL.rotation.set(-0.8, 0, 0); p.hips.rotation.x = 0.35; }
        },
        update(ff, t, dt) {
          if (!this.landed) ff.pos.addScaledVector(move, Math.min(dt, Math.max(0, 0.48 - (t - dt))) / 0.48);
          if (!this.landed && t > 0.15 && ff.onGround) {
            this.landed = true;
            G.fx.ring(ff.pos, 0xff9a1f, 1, 10, 0.5); G.fx.ring(ff.pos, 0xffffff, 0.5, 6, 0.3);
            G.fx.puff(ff.pos, 14, 0x6070a0, 2.2, 0.8, 9);
            G.fx.burst(V.set(ff.pos.x, 0.5, ff.pos.z), 0xff9a1f, 22, 14, 0.6, 0.5, { up: 9 });
            G.sfx('heavy', 0.9, ff);
            if (ff.isPlayer) G.fx.shake(0.45);
            if (m && !m.dead && dist2(ff.pos, m.pos) < 7.5 + m.radius) damageMonster(G, m, 30, ff, { cost: COST.heavy, heavy: true, stun: 0.6, color: 0xff9a1f });
          }
        },
      });
      return true;
    },
  ],
  jus: [
    // Заряженный выстрел
    (G, f) => {
      G.sfx('charge', 0.6, f);
      f.startAction({
        name: 's1', dur: 1.0, lock: true, moveMul: 0.3, face: G.monster && !G.monster.dead && !f.isPlayer ? G.monster : null,
        pose: (p, k) => poseAim(p, k < 0.75 ? 0.4 : (k - 0.75) / 0.25, 0.9),
        update(ff, t) {
          muzzle(ff, V);
          if (t < 0.75) {
            const a = Math.random() * 7, r = 1.5;
            G.fx.spark(V.x + Math.cos(a) * r, V.y + Math.sin(a) * r, V.z, -Math.cos(a) * r * 4, -Math.sin(a) * r * 4, 0, 0.22, 0.6, 0xfff27a);
            if (ff.isPlayer && G.monster && !G.monster.dead) { aimDir(G, ff, V, V2); ff.faceTo(V3.copy(ff.pos).add(V2)); }
          } else if (!this.hit) {
            this.hit = true;
            aimDir(G, ff, V, V2); ff.faceTo(V3.copy(ff.pos).add(V2), true); muzzle(ff, V);
            fireBullet(G, ff, V, V2, { dmg: 40, cost: COST.heavy, heavy: true, speed: 150, size: 0.9, len: 4, color: 0xfff6b0, life: 0.9 });
            ff.kb.addScaledVector(V2.setY(0), -10);
            G.sfx('boom', 0.45, ff);
            if (ff.isPlayer) G.fx.shake(0.25);
          }
        },
      });
      return true;
    },
    // Дробь
    (G, f) => {
      f.startAction({
        name: 's2', dur: 0.38, lock: true, moveMul: 0.4, pose: (p, k) => poseAim(p, k, 0.7),
        update(ff, t) {
          if (!this.hit && t >= 0.05) {
            this.hit = true;
            muzzle(ff, V); aimDir(G, ff, V, V2); ff.faceTo(V3.copy(ff.pos).add(V2), true); muzzle(ff, V);
            for (let i = 0; i < 6; i++) {
              const a = (i / 5 - 0.5) * 0.36 + (Math.random() - 0.5) * 0.05;
              V3.set(V2.x * Math.cos(a) - V2.z * Math.sin(a), V2.y + (Math.random() - 0.5) * 0.06, V2.x * Math.sin(a) + V2.z * Math.cos(a)).normalize();
              fireBullet(G, ff, V, V3, { dmg: 5, cost: COST.light, speed: 110, life: 0.3, size: 0.18, len: 1.4, color: 0xffd23a });
            }
            G.sfx('heavy', 0.4, ff); G.sfx('hit', 0.4, ff);
          }
        },
      });
      return true;
    },
    // Отскок
    (G, f) => {
      const m = G.monster;
      if (m && !m.dead) V.subVectors(f.pos, m.pos).setY(0).normalize(); else f.fwd(V).negate();
      const dir = V.clone();
      f.vy = 17; f.onGround = false; f.iframeUntil = G.time + 0.5;
      G.sfx('jump', 0.6, f); G.fx.after(f.pos, f.color, 5.5, 0.3);
      if (m && !m.dead) f.faceTo(m.pos, true);
      f.startAction({
        name: 's3', dur: 0.5, lock: true, moveMul: 0,
        pose: (p, k) => { p.hips.rotation.x = -k * Math.PI * 2; p.legL.rotation.x = -0.8; p.legR.rotation.x = -0.8; p.armR.rotation.set(-1.57, 0, 0); },
        update(ff, t, dt) {
          if (t < 0.45) ff.pos.addScaledVector(dir, 24 * dt);
          if (!this.hit && t >= 0.22) {
            this.hit = true;
            muzzle(ff, V); aimDir(G, ff, V, V2);
            fireBullet(G, ff, V, V2, { dmg: 12, cost: COST.normal });
            G.sfx('block', 0.4, ff);
          }
        },
      });
      return true;
    },
  ],
};

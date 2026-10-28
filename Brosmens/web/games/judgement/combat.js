// Бойцы (люди и Судья): движение, прыжки, рывки, действия-анимации, урон, карма, уклонение, смерть.
import * as THREE from 'three';
import { animateAvatar } from '../../shared/avatar.js';
import { ARENA_HALF, GRAV, JUMP_V, KARMA_SHARE, KARMA_RATE, COST } from './data.js';
import { heartTex } from './fx.js';

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const easeOut = (k) => 1 - (1 - k) * (1 - k);
export const easeIn = (k) => k * k;
export const dist2 = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
export function lerpAngle(a, b, t) {
  let d = (b - a) % (Math.PI * 2);
  if (d > Math.PI) d -= Math.PI * 2; else if (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}
export function angleTo(f, p) {
  const want = Math.atan2(p.x - f.pos.x, p.z - f.pos.z);
  let d = (want - f.yaw) % (Math.PI * 2);
  if (d > Math.PI) d -= Math.PI * 2; else if (d < -Math.PI) d += Math.PI * 2;
  return Math.abs(d);
}

const V = new THREE.Vector3(), V2 = new THREE.Vector3();

export class Fighter {
  constructor(G, o) {
    this.G = G; this.name = o.name; this.bot = o.bot || null; this.isPlayer = !!o.isPlayer;
    this.team = o.team; this.roleId = o.roleId; this.role = o.role;
    this.color = o.color;
    this.maxHp = o.hp; this.hp = o.hp; this.karma = 0;
    this.speed = o.speed; this.radius = o.radius;
    this.pos = new THREE.Vector3(); this.hv = new THREE.Vector3(); this.kb = new THREE.Vector3();
    this.vy = 0; this.onGround = true; this.yaw = 0; this.targetYaw = 0; this.floatY = 0;
    this.moveDir = new THREE.Vector3();
    this.action = null; this.combo = 0; this.comboUntil = 0;
    this.cd = {}; this.cdLen = {};
    this.dashT = 0; this.dashDir = new THREE.Vector3(); this.dashSpeed = 0;
    this.iframeUntil = 0; this.stunUntil = 0; this.shield = 0; this.shieldUntil = 0; this.tauntUntil = 0;
    this.grab = null; this.boneImmuneUntil = 0; this.lastHurtAt = -9; this.slowUntil = 0;
    this.dead = false; this.deadT = 0; this.reviveCharges = 1;
    this.stats = { dmg: 0, heal: 0, kills: 0, taken: 0, dodged: 0 };
    this.flashT = 0; this.animT = Math.random() * 10;
    this.model = o.model;
    G.scene.add(this.model.root);
    if (this.model.shadow) G.scene.add(this.model.shadow);
    // Монстр
    if (this.team === 'monster') {
      this.dodgeMax = 100; this.dodge = 100; this.brokenUntil = 0; this.lastHitAt = -9; this.ult = 0; this.glow = 0;
    }
    this.soul = null;
  }
  remove() {
    const G = this.G;
    G.scene.remove(this.model.root);
    if (this.model.shadow) G.scene.remove(this.model.shadow);
    if (this.soul) G.scene.remove(this.soul);
    if (this.model.disposable) this.model.root.traverse((o) => {
      if (o.isMesh) o.geometry.dispose();
      if (o.isMesh || o.isSprite) [].concat(o.material).forEach((m) => { if (m.map?.userData.own) m.map.dispose(); m.dispose(); });
    });
    if (this.soul) this.soul.material.dispose();
  }
  get now() { return this.G.time; }
  ready(id) { return this.G.time >= (this.cd[id] || 0); }
  cdFrac(id) { const l = this.cdLen[id] || 1; return clamp(((this.cd[id] || 0) - this.G.time) / l, 0, 1); }
  use(id, len) { this.cd[id] = this.G.time + len; this.cdLen[id] = len; }
  get busy() { return !!this.action && this.action.lock; }
  get stunned() { return this.G.time < this.stunUntil; }
  canAct() { return !this.dead && !this.busy && !this.stunned && !this.grab && this.G.state === 'fight'; }
  faceTo(p, instant = false) {
    this.targetYaw = Math.atan2(p.x - this.pos.x, p.z - this.pos.z);
    if (instant) this.yaw = this.targetYaw;
  }
  fwd(out) { return out.set(Math.sin(this.yaw), 0, Math.cos(this.yaw)); }
  hspeed() { return Math.hypot(this.hv.x, this.hv.z); }
  startAction(a) { a.t = 0; this.action = a; return a; }
  cancelAction() { if (this.action) { this.action.end?.(this, true); this.action = null; } }
  jump(mul = 1) {
    if (!this.onGround || this.stunned || this.grab || this.dead) return false;
    this.vy = JUMP_V * mul; this.onGround = false;
    this.G.sfx('jump', 0.4, this);
    return true;
  }
  // рывок: dir — единичный вектор XZ
  dash(dir, dist = 12, dur = 0.2, iframes = true) {
    this.dashDir.copy(dir).setY(0).normalize();
    this.dashT = dur; this.dashSpeed = dist / dur;
    if (iframes) this.iframeUntil = Math.max(this.iframeUntil, this.G.time + dur + 0.05);
    this.yaw = this.targetYaw = Math.atan2(this.dashDir.x, this.dashDir.z);
  }
  heal(n, src) {
    if (this.dead) return 0;
    const before = this.hp;
    this.hp = Math.min(this.maxHp, this.hp + n);
    this.karma = 0;
    const got = this.hp - before;
    if (src && src !== this) src.stats.heal += got;
    return got;
  }

  update(dt) {
    const G = this.G, now = G.time;
    this.animT += dt;
    if (this.dead) { this.updateDead(dt); return; }
    // карма
    if (this.karma > 0) {
      const d = Math.min(this.karma, KARMA_RATE * dt);
      this.karma -= d;
      if (this.hp > 1) this.hp = Math.max(1, this.hp - d);
    }
    if (this.shield > 0 && now > this.shieldUntil) this.shield = 0;
    if (this.team === 'monster') this.updateMonsterPassive(dt);
    // действие
    const a = this.action;
    if (a) {
      a.t += dt;
      a.update?.(this, a.t, dt);
      if (this.action === a && a.t >= a.dur) { a.end?.(this, false); if (this.action === a) this.action = null; }
    }
    if (this.grab) { this.grab.drive(this, dt); this.animate(dt); return; }

    const stunned = this.stunned;
    let mul = stunned ? 0 : (this.action?.moveMul ?? 1);
    if (G.state !== 'fight') mul = G.state === 'intro' ? 0 : mul;
    if (this.dashT > 0) {
      const t = Math.min(dt, this.dashT); this.dashT -= dt;
      this.hv.copy(this.dashDir).multiplyScalar(this.dashSpeed);
      this.pos.addScaledVector(this.hv, t);
      if (this.dashT <= 0) this.hv.multiplyScalar(0.35);
      if (Math.random() < 0.7) G.fx.spark(this.pos.x, this.pos.y + 2.5 + Math.random() * 2, this.pos.z, 0, 0, 0, 0.25, 1.2, this.color);
    } else {
      V.copy(this.moveDir).multiplyScalar(this.speed * mul * (this.slowUntil > now ? 0.5 : 1));
      const acc = this.onGround ? 14 : 5;
      this.hv.lerp(V, 1 - Math.exp(-acc * dt));
      this.pos.addScaledVector(this.hv, dt);
    }
    if (this.kb.lengthSq() > 0.01) { this.pos.addScaledVector(this.kb, dt); this.kb.multiplyScalar(Math.exp(-6 * dt)); }
    // вертикаль
    if (this.floatY > 0 || this.action?.float) {
      const ty = this.action?.float ?? 0;
      this.floatY = lerp(this.floatY, ty, 1 - Math.exp(-4 * dt));
      if (this.floatY < 0.02 && !ty) this.floatY = 0;
      this.pos.y = this.floatY; this.vy = 0; this.onGround = true;
    } else {
      this.vy -= GRAV * dt * (this.action?.grav ?? 1);
      this.pos.y += this.vy * dt;
      if (this.pos.y <= 0) {
        if (!this.onGround && this.vy < -20) G.fx.puff(this.pos, 4, 0x6070a0, 1.2, 0.4, 3);
        this.pos.y = 0; this.vy = 0; this.onGround = true;
      } else this.onGround = false;
    }
    const L = ARENA_HALF - this.radius;
    this.pos.x = clamp(this.pos.x, -L, L); this.pos.z = clamp(this.pos.z, -L, L);
    // поворот
    const face = this.action?.face;
    if (face) this.faceTo(face.pos || face);
    else if (this.dashT <= 0 && this.hspeed() > 1.5 && mul > 0.2) this.targetYaw = Math.atan2(this.hv.x, this.hv.z);
    this.yaw = lerpAngle(this.yaw, this.targetYaw, 1 - Math.exp(-16 * dt));
    this.animate(dt);
  }

  updateMonsterPassive(dt) {
    const now = this.G.time;
    if (now < this.brokenUntil) { /* сломано: не восстанавливается */ }
    else {
      if (this.recover) { this.recover = false; this.dodge = Math.max(this.dodge, 40); this.G.fx.ring(this.pos, 0x6fd4ff, 1, 6, 0.4); }
      this.dodge = Math.min(this.dodgeMax, this.dodge + (now - this.lastHitAt > 1.2 ? 14 : 4) * dt);
    }
    if (this.G.state === 'fight') this.ult = Math.min(100, this.ult + dt * 0.75);
    this.glow = Math.max(0, this.glow - dt * 1.5);
    const e = this.model.eye;
    if (e) {
      const k = 0.55 + this.glow * 0.9 + Math.sin(this.animT * 9) * 0.06;
      e.scale.setScalar(k);
      e.material.color.setHex(this.action?.name === 'ult' && Math.sin(this.animT * 14) > 0 ? 0xffe040 : 0x3fe0ff);
      if (this.glow > 0.3 && Math.random() < 0.5) {
        e.getWorldPosition(V2);
        this.G.fx.spark(V2.x, V2.y, V2.z, -Math.sin(this.yaw) * 3, 1, -Math.cos(this.yaw) * 3, 0.35, 0.7, 0x3fe0ff);
      }
    }
  }

  animate(dt) {
    const m = this.model, p = m.parts;
    p.armL.rotation.set(0, 0, 0); p.armR.rotation.set(0, 0, 0); p.legL.rotation.set(0, 0, 0); p.legR.rotation.set(0, 0, 0);
    p.hips.rotation.set(0, 0, 0); p.neck.rotation.set(0, 0, 0); p.hips.position.y = 2;
    const hs = this.hspeed();
    let st = !this.onGround && !this.floatY ? 'air' : hs > 1.5 ? 'run' : 'idle';
    if (this.grab) st = 'air';
    animateAvatar(m, st, this.animT, clamp(hs / 16, 0.6, 1.4));
    if (this.dashT > 0) { p.hips.rotation.x = 0.45; p.armL.rotation.x = 0.9; p.armR.rotation.x = 0.9; }
    // Судья в покое — «руки в карманах», лёгкое покачивание
    if (this.team === 'monster' && st === 'idle' && !this.action) {
      p.armL.rotation.set(0.28, 0, 0.16); p.armR.rotation.set(0.28, 0, -0.16);
      p.neck.rotation.z = Math.sin(this.animT * 1.3) * 0.06; p.hips.rotation.y = Math.sin(this.animT * 0.9) * 0.05;
    }
    // победители радуются
    if (this.G.winnerTeam === this.team && (this.G.state === 'end' || this.G.state === 'results')) {
      const w = Math.sin(this.animT * 9);
      p.armL.rotation.set(-2.8, 0, -0.35 + w * 0.25); p.armR.rotation.set(-2.8, 0, 0.35 - w * 0.25);
      p.hips.position.y = 2 + Math.abs(Math.sin(this.animT * 6)) * 0.35;
    }
    const a = this.action;
    if (a?.pose) a.pose(p, clamp(a.t / a.dur, 0, 1), a, this);
    if (this.stunned) { p.neck.rotation.z = Math.sin(this.animT * 8) * 0.25; p.hips.rotation.x = -0.15; }
    if (this.G.time - this.lastHurtAt < 0.18) { p.hips.rotation.x -= 0.25; p.neck.rotation.x = -0.25; }
    m.root.position.copy(this.pos);
    m.root.rotation.set(0, this.yaw, 0);
    if (this.grab) m.root.rotation.z = Math.sin(this.animT * 6) * 0.3;
    if (m.shadow) {
      m.shadow.position.set(this.pos.x, 0.06, this.pos.z);
      const s = 1 / (1 + this.pos.y * 0.08); m.shadow.scale.set(s, s, s);
      m.shadow.material.opacity = s;
    }
    // вспышка от удара
    if (this.flashT > 0) {
      this.flashT -= dt;
      const k = Math.max(0, this.flashT / 0.14);
      for (const mt of m.mats) mt.emissive.setRGB(k * 0.9, k * 0.9, k * 0.9);
      if (this.flashT <= 0) for (const mt of m.mats) mt.emissive.setHex(mt.userData.e0);
    }
    if (m.heart) {
      m.heart.position.y = 6.5 + Math.sin(this.animT * 2.5) * 0.12;
      const blue = !!this.grab;
      if (blue !== m.heartBlue) { m.heartBlue = blue; m.heart.material.map = heartTex(blue ? '#2f6bff' : this.color); }
    }
    if (m.ribbon) m.ribbon.rotation.x = 0.6 + Math.sin(this.animT * 7) * 0.25 + hs * 0.03;
    if (m.tauntRing) m.tauntRing.visible = this.G.time < this.tauntUntil;
    if (m.shieldMesh) {
      m.shieldMesh.visible = this.shield > 0;
      if (this.shield > 0) { const s = 1 + Math.sin(this.animT * 6) * 0.03; m.shieldMesh.scale.set(s, s, s); m.shieldMesh.material.opacity = 0.18 + 0.12 * Math.min(1, this.shield / 40); }
    }
  }

  updateDead(dt) {
    this.deadT += dt;
    const m = this.model, k = Math.min(1, this.deadT / 0.5);
    if (this.team === 'monster') { // Судья рассыпается в пыль
      const t = this.deadT;
      m.root.position.copy(this.pos); m.root.position.x += Math.sin(t * 60) * Math.max(0, 0.15 - t * 0.1);
      m.root.rotation.set(0, this.yaw, 0);
      const c = Math.max(0, (t - 0.5) / 1.4);
      m.body.scale.set(1.25 * (1 + c * 0.15), 1.25 * Math.max(0.02, 1 - c), 1.25 * (1 + c * 0.15));
      if (c > 0 && c < 1 && Math.random() < 0.9) {
        V.set(this.pos.x + (Math.random() - 0.5) * 3, 7.5 * (1 - c) * Math.random() + 0.3, this.pos.z + (Math.random() - 0.5) * 3);
        this.G.fx.puff(V, 2, 0xb8bccc, 1.1, 1.2, 2.5);
        this.G.fx.spark(V.x, V.y, V.z, (Math.random() - 0.5) * 3, 1 + Math.random() * 2, (Math.random() - 0.5) * 3, 1, 0.4, 0xdfe8ff);
      }
      if (t > 2 && m.root.visible) { m.root.visible = false; if (m.shadow) m.shadow.visible = false; }
      return;
    }
    m.root.position.copy(this.pos); m.root.position.y = Math.max(0, this.pos.y - this.deadT * 6) + 0.5 * k;
    m.root.rotation.set(-Math.PI / 2 * easeOut(k), this.yaw, 0);
    if (this.deadT > 2.2 && m.root.visible) { m.root.visible = false; if (m.shadow) m.shadow.visible = false; }
    if (this.soul) {
      this.soul.position.y = 2.2 + Math.sin(this.deadT * 2) * 0.25;
      this.soul.material.opacity = 0.55 + Math.sin(this.deadT * 4) * 0.25;
    }
  }
}

// ---------- урон ----------
export function damageHuman(G, h, amount, src, o = {}) {
  if (!h || h.dead || G.state !== 'fight') return false;
  const now = G.time;
  if (now < h.iframeUntil && !o.unblockable) return false;
  if (h.tauntUntil > now) amount *= 0.55;
  amount = Math.round(amount);
  if (h.shield > 0) {
    const ab = Math.min(h.shield, amount); h.shield -= ab; amount -= ab;
    G.fx.burst(V.copy(h.pos).setY(h.pos.y + 3), 0x8fe9ff, 8, 7, 0.6, 0.35);
    G.sfx('block', 0.6, h);
    if (amount <= 0) { G.fx.text(V.set(h.pos.x, h.pos.y + 5.5, h.pos.z), 'ЩИТ', 'miss'); return true; }
  }
  const kr = o.karma === false ? 0 : amount * KARMA_SHARE;
  const inst = amount - kr;
  h.hp -= inst; h.karma += kr; h.lastHurtAt = now; h.flashT = 0.14;
  h.stats.taken += amount;
  if (G.dmgLog) G.dmgLog[o.cause || '?'] = (G.dmgLog[o.cause || '?'] || 0) + amount;
  if (src) { src.stats.dmg += amount; if (src.team === 'monster') src.ult = Math.min(100, src.ult + amount * 0.22); }
  if (o.kb) h.kb.add(o.kb);
  if (o.lift && h.onGround) { h.vy = o.lift; h.onGround = false; }
  V.set(h.pos.x, h.pos.y + 3, h.pos.z);
  G.fx.burst(V, o.color || 0xffffff, 10, 9, 0.55, 0.4);
  G.fx.text(V.set(h.pos.x, h.pos.y + 5.6, h.pos.z), '-' + amount, h.isPlayer ? 'hurt' : 'dmg');
  G.sfx('hit', 0.55, h);
  if (h.isPlayer || h === G.camFocus) { G.fx.hurt(Math.min(0.8, 0.25 + amount / 50)); G.fx.shake(Math.min(0.6, 0.2 + amount / 60)); }
  G.onEvent('hurt', { h, src, amount });
  if (h.hp <= 0) killHuman(G, h, src, o.cause);
  return true;
}

export function killHuman(G, h, src, cause = '') {
  if (h.dead) return;
  h.dead = true; h.deadT = 0; h.hp = 0; h.karma = 0; h.grab = null; h.action = null; h.shield = 0; h.dashT = 0;
  if (src) src.stats.kills++;
  V.set(h.pos.x, h.pos.y + 3, h.pos.z);
  G.fx.burst(V, h.color, 26, 14, 0.8, 0.8);
  G.fx.puff(h.pos, 10, 0x8090c0, 2, 0.9, 5);
  G.fx.flare(V, h.color, 6, 0.4);
  G.sfx('death', 0.8, h);
  if (h.bot) h.bot.dead = true;
  // душа остаётся на месте гибели (Терпение может поднять)
  if (!h.soul) {
    h.soul = new THREE.Sprite(new THREE.SpriteMaterial({ map: heartTex(h.color, true), transparent: true, depthWrite: false, fog: false }));
    h.soul.scale.setScalar(1.8); h.soul.renderOrder = 6;
  }
  h.soul.position.set(h.pos.x, 2.2, h.pos.z); h.soul.visible = true;
  G.scene.add(h.soul);
  if (h.model.heart) h.model.heart.visible = false;
  G.onEvent('kill', { h, src, cause });
}

export function reviveHuman(G, h, by) {
  if (!h.dead) return;
  h.dead = false; h.hp = Math.round(h.maxHp * 0.5); h.karma = 0; h.deadT = 0;
  h.pos.y = 0; h.vy = 0; h.iframeUntil = G.time + 2; h.stunUntil = 0;
  const m = h.model; m.root.visible = true; if (m.shadow) m.shadow.visible = true; if (m.heart) m.heart.visible = true;
  if (h.soul) { G.scene.remove(h.soul); }
  if (h.bot) h.bot.dead = false;
  G.fx.ring(h.pos, 0x8fffd0, 1, 9, 0.7);
  G.fx.burst(V.set(h.pos.x, 2, h.pos.z), 0x8fffd0, 30, 8, 0.7, 0.9, { up: 8, g: -2 });
  G.sfx('spawn', 0.8, h);
  G.onEvent('revive', { h, by });
}

// Удар по Монстру: проверка автоуклонения
export function damageMonster(G, m, amount, src, o = {}) {
  if (!m || m.dead || G.state !== 'fight') return false;
  const now = G.time, cost = o.cost ?? COST.normal;
  m.lastHitAt = now;
  const hitPos = V.set(m.pos.x, m.pos.y + 3.4, m.pos.z);
  if (!m.stunned && now >= m.brokenUntil && m.dodge >= cost) {
    m.dodge -= cost; m.stats.dodged++;
    dodgeStep(G, m, src);
    G.fx.text(V.set(m.pos.x, m.pos.y + 7, m.pos.z), 'МИМО', 'miss', 0.7);
    G.onEvent('dodge', { m, src });
    return false;
  }
  const wasBroken = now < m.brokenUntil;
  m.dodge = Math.max(0, m.dodge - cost);
  if (m.dodge <= 0 && !wasBroken) {
    m.brokenUntil = now + 2.4; m.recover = true;
    G.fx.ring(m.pos, 0xffffff, 1, 8, 0.4);
    G.sfx('block', 1, m);
    G.onEvent('broken', { m, src });
  }
  amount = Math.round(amount);
  m.hp -= amount; m.flashT = 0.12; m.lastHurtAt = now; m.stats.taken += amount;
  if (src) src.stats.dmg += amount;
  m.ult = Math.min(100, m.ult + amount * 0.05);
  if (o.stun) { m.stunUntil = Math.max(m.stunUntil, now + o.stun); if (m.action && m.action.name !== 'ult') m.cancelAction(); }
  if (o.kb && m.action?.name !== 'ult') m.kb.add(o.kb);
  hitPos.set(m.pos.x, m.pos.y + 3.4, m.pos.z);
  G.fx.burst(hitPos, o.color || src?.color || 0xffffff, o.heavy ? 26 : 12, o.heavy ? 16 : 10, 0.6, 0.45);
  if (o.heavy) { G.fx.flare(hitPos, o.color || 0xffffff, 7, 0.3); G.fx.shake(0.35); }
  G.fx.text(V.set(m.pos.x, m.pos.y + 7, m.pos.z), String(amount), o.heavy ? 'crit' : 'mdmg');
  G.sfx(o.heavy ? 'heavy' : 'hit', o.heavy ? 0.8 : 0.5, m);
  if (src?.isPlayer || m.isPlayer) G.hitStop(o.heavy ? 0.09 : 0.035);
  G.onEvent('mhit', { m, src, amount });
  if (m.hp <= 0) { m.hp = 0; m.dead = true; m.deadT = 0; G.onEvent('mdead', { m, src }); }
  return true;
}

// Автоуклонение: телепорт-шаг вбок с послеобразом
export function dodgeStep(G, m, src) {
  G.fx.after(m.pos, 0x5fb4ff, 7.5, 0.35);
  V2.subVectors(m.pos, src ? src.pos : m.pos).setY(0);
  if (V2.lengthSq() < 0.01) V2.set(1, 0, 0);
  V2.normalize();
  const side = Math.random() < 0.5 ? 1 : -1;
  const nx = -V2.z * side, nz = V2.x * side;
  const L = ARENA_HALF - m.radius;
  m.pos.x = clamp(m.pos.x + nx * 3.4 + V2.x * 0.8, -L, L);
  m.pos.z = clamp(m.pos.z + nz * 3.4 + V2.z * 0.8, -L, L);
  G.fx.burst(V.set(m.pos.x, m.pos.y + 3, m.pos.z), 0x8fd0ff, 8, 6, 0.5, 0.3);
  G.sfx('tp', 0.4, m);
}

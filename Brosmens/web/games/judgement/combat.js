// Бойцы (люди и Судья): движение, прыжки, полёт от «Отталкивания», действия-анимации, урон, карма, уклонение, смерть.
// Движение как в роблоксе: WalkSpeed 16, гравитация 196.2, JumpPower 50 (≈0.51 с в воздухе), разгон/торможение ≈0.1 с,
// полный контроль в воздухе. Урон по людям — мелкими тиками (1–5) + пул кармы; «больно» = красная вспышка 0.1 с и «ай».
// Судья: 15 уклонений («MISS» + шаг в сторону + 0.6 с неуязвимости), потом 1 HP.
// Люди: пассивки душ (Терпение — лечится стоя, Решимость — вторая жизнь), зелья (скорость/сила/лечение/святое).
import * as THREE from 'three';
import { animateAvatar } from '../../shared/avatar.js';
import { GRAV, JUMP_V, KR_CAP, krInterval, HALL_X, HALL_Z, COLUMNS, COL_X, COL_HIT, DODGES, DODGE_IFRAMES, FORCE_G, FADE_TIME } from './data.js';
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
const TAU = Math.PI * 2;

// ---------- стены и колонны зала ----------
// убирает из скоростей бойца составляющую «в препятствие» (n — нормаль наружу из препятствия)
function stopInto(f, nx, nz) {
  for (const v of [f.kb, f.hv]) { const d = v.x * nx + v.z * nz; if (d < 0) { v.x -= d * nx; v.z -= d * nz; } }
}
// Прямоугольник зала + круги колонн. Возвращает true, если упёрлись. f — боец (гасим его скорость в стену).
export function arenaCollide(p, r, f = null) {
  let hit = false;
  const lx = HALL_X - r, lz = HALL_Z - r;
  if (p.x > lx) { p.x = lx; hit = true; if (f) stopInto(f, -1, 0); } else if (p.x < -lx) { p.x = -lx; hit = true; if (f) stopInto(f, 1, 0); }
  if (p.z > lz) { p.z = lz; hit = true; if (f) stopInto(f, 0, -1); } else if (p.z < -lz) { p.z = -lz; hit = true; if (f) stopInto(f, 0, 1); }
  if (Math.abs(p.x) > COL_X - COL_HIT - r && p.y < 26) {
    const min = COL_HIT + r;
    for (let i = 0; i < COLUMNS.length; i++) {
      const c = COLUMNS[i], dz = p.z - c[1];
      if (dz > min || dz < -min) continue;
      const dx = p.x - c[0], d2 = dx * dx + dz * dz;
      if (d2 >= min * min) continue;
      let d = Math.sqrt(d2), nx, nz;
      if (d < 1e-3) { nx = -Math.sign(c[0]); nz = 0; d = 0; } else { nx = dx / d; nz = dz / d; }
      p.x = c[0] + nx * min; p.z = c[1] + nz * min; hit = true;
      if (f) stopInto(f, nx, nz);
    }
  }
  return hit;
}
// Свободное место вокруг точки (до стен и колонн), не больше cap
export function clearance(x, z, cap = 8) {
  let c = Math.min(cap, HALL_X - Math.abs(x), HALL_Z - Math.abs(z));
  if (Math.abs(x) > COL_X - COL_HIT - cap) for (const k of COLUMNS) { const d = Math.hypot(x - k[0], z - k[1]) - COL_HIT; if (d < c) c = d; }
  return c;
}
// Точка внутри зала (для прицеливания/спавна эффектов)
export function clampToHall(p, margin = 1) {
  p.x = clamp(p.x, -HALL_X + margin, HALL_X - margin); p.z = clamp(p.z, -HALL_Z + margin, HALL_Z - margin);
  return p;
}

export class Fighter {
  constructor(G, o) {
    this.G = G; this.name = o.name; this.bot = o.bot || null; this.isPlayer = !!o.isPlayer;
    this.team = o.team; this.roleId = o.roleId; this.role = o.role;
    this.color = o.color;
    this.maxHp = o.hp; this.hp = o.hp; this.karma = 0; this.krT = 0;
    this.speed = o.speed; this.radius = o.radius;
    this.pos = new THREE.Vector3(); this.hv = new THREE.Vector3(); this.kb = new THREE.Vector3();
    this.vy = 0; this.onGround = true; this.yaw = 0; this.targetYaw = 0;
    this.moveDir = new THREE.Vector3();
    this.action = null; this.combo = 0; this.comboUntil = 0;
    this.cd = {}; this.cdLen = {};
    this.iframeUntil = 0; this.stunUntil = 0; this.shield = 0; this.shieldUntil = 0;
    this.boneImmuneUntil = 0; this.lastHurtAt = -9; this.slowUntil = 0;
    this.flung = false; this.flungAt = -9; this.landedAt = -9;   // «Отталкивание»: полёт без управления
    this.dead = false; this.deadT = 0;
    this.stats = { dmg: 0, heal: 0, kills: 0, taken: 0, dodged: 0 };
    this.flashT = 0; this.animT = Math.random() * 10;
    this.model = o.model;
    G.scene.add(this.model.root);
    if (this.model.shadow) G.scene.add(this.model.shadow);
    if (this.team === 'monster') {
      // Монстр: 15 уклонений + 1 HP, шаг в сторону при уклонении
      this.dodges = this.maxDodges = o.dodges ?? DODGES; this.lastHitAt = -9; this.lastDodgeAt = -9; this.glow = 0; this.wispT = 0;
      this.sideT = 0; this.sideDir = new THREE.Vector3(); this.sideDist = 4.5; this.sideLean = 0;
    } else {
      // Человек: предметы раунда, зелья, пассивки душ
      this.equipped = 'weapon'; this.pies = 0; this.potion = null; this.potionId = null;
      this.speedUntil = 0; this.mightUntil = 0; this.holyUntil = 0; this.healUntil = 0; this.healRate = 0; this.krClearT = 0;
      this.dtUsed = false; this.dtUntil = 0; this.pulseAt = -9;  // Решимость: вторая жизнь
      this.stillT = 0; this.regenT = 0.5;                       // Терпение: стоишь — лечишься
      this.ammo = 6;                                            // Справедливость: барабан на 6
      this.lowAt = -99;
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
  cdLeft(id) { return Math.max(0, (this.cd[id] || 0) - this.G.time); }
  use(id, len) { this.cd[id] = this.G.time + len; this.cdLen[id] = len; }
  get busy() { return !!this.action && this.action.lock; }
  get stunned() { return this.G.time < this.stunUntil; }
  canAct() { return !this.dead && !this.busy && !this.stunned && !this.flung && this.G.state === 'fight'; }
  speedNow() { return this.speed * (this.G.time < (this.speedUntil || 0) ? 1.25 : 1); }
  faceTo(p, instant = false) {
    this.targetYaw = Math.atan2(p.x - this.pos.x, p.z - this.pos.z);
    if (instant) this.yaw = this.targetYaw;
  }
  fwd(out) { return out.set(Math.sin(this.yaw), 0, Math.cos(this.yaw)); }
  hspeed() { return Math.hypot(this.hv.x, this.hv.z); }
  startAction(a) { a.t = 0; this.action = a; return a; }
  cancelAction() { if (this.action) { this.action.end?.(this, true); this.action = null; } }
  jump(mul = 1) {
    if (!this.onGround || this.stunned || this.flung || this.dead) return false;
    this.vy = JUMP_V * mul; this.onGround = false;
    this.G.sfx('jump', 0.4, this);
    return true;
  }
  // Подлечиться (пассивка, пирог, зелье). Карму не снимает — это делает только зелье лечения.
  heal(n, src = null) {
    if (this.dead || n <= 0) return 0;
    const before = this.hp;
    this.hp = Math.min(this.maxHp, this.hp + n);
    const got = this.hp - before;
    if (src) src.stats.heal += got;
    return got;
  }
  // «Отталкивание»: v — горизонтальная скорость, vy — вверх. Без управления до приземления.
  fling(vx, vz, vy) {
    if (this.dead) return;
    this.cancelAction();
    this.kb.set(vx, 0, vz); this.hv.set(0, 0, 0);
    this.vy = vy; this.onGround = false; this.flung = true; this.flungAt = this.G.time;
  }

  update(dt) {
    const G = this.G, now = G.time;
    this.animT += dt;
    if (this.dead) { this.updateDead(dt); return; }
    // карма: тики по 1 очку, скорость зависит от размера пула; ниже 1 HP не опускает
    if (this.karma > 0) {
      this.krT -= dt;
      while (this.krT <= 0 && this.karma > 0) {
        this.karma = Math.max(0, this.karma - 1);
        if (this.hp > 1) this.hp = Math.max(1, this.hp - Math.max(1, this.maxHp * 0.01));
        this.krT += krInterval(this.karma);
      }
      if (this.hp <= 1 && this.roleId === 'det' && !this.dtUsed && G.state === 'fight') secondLife(G, this);
    } else this.krT = 0;
    if (this.shield > 0 && now > this.shieldUntil) this.shield = 0;
    if (this.team === 'monster') this.updateMonsterPassive(dt);
    else this.updateHumanPassive(dt);
    // действие
    const a = this.action;
    if (a) {
      a.t += dt;
      a.update?.(this, a.t, dt);
      if (this.action === a && a.t >= a.dur) { a.end?.(this, false); if (this.action === a) this.action = null; }
    }

    const stunned = this.stunned;
    let mul = stunned || this.flung ? 0 : (this.action?.moveMul ?? 1);
    // интро: люди ходят, едят и пьют, Судья стоит (говорит); после боя все замирают
    if (G.state === 'intro') { if (this.team === 'monster') mul = 0; } else if (G.state !== 'fight') mul = 0;
    if (this.sideT > 0) mul *= 0.3;
    V.copy(this.moveDir).multiplyScalar(this.speedNow() * mul * (this.slowUntil > now ? 0.5 : 1));
    // роблокс: полная скорость почти сразу (≈0.1 с) и такой же контроль в воздухе
    this.hv.lerp(V, 1 - Math.exp(-14 * dt));
    this.pos.addScaledVector(this.hv, dt);
    // отбрасывание; в полёте от «Отталкивания» скорость не гаснет (≈50 ст/с до приземления)
    if (this.kb.lengthSq() > 0.01) { this.pos.addScaledVector(this.kb, dt); if (!this.flung) this.kb.multiplyScalar(Math.exp(-6 * dt)); }
    // уклонение Судьи: скольжение вбок 0.6 с (ease-out)
    if (this.sideT > 0) {
      const D = DODGE_IFRAMES, e = (k) => 1 - Math.pow(1 - k, 3);
      const k0 = 1 - this.sideT / D; this.sideT = Math.max(0, this.sideT - dt); const k1 = 1 - this.sideT / D;
      this.pos.addScaledVector(this.sideDir, this.sideDist * (e(k1) - e(k0)));
    }
    // вертикаль (в полёте от «Отталкивания» — гравитация роблокса 196.2)
    this.vy -= (this.flung ? FORCE_G : GRAV * (this.action?.grav ?? 1)) * dt;
    this.pos.y += this.vy * dt;
    if (this.pos.y <= 0) {
      if (!this.onGround && (this.flung || this.vy < -62)) G.fx.puff(this.pos, this.flung ? 9 : 4, 0x6070a0, this.flung ? 1.8 : 1.2, 0.5, this.flung ? 6 : 3);
      if (this.flung) { this.flung = false; this.landedAt = now; this.kb.multiplyScalar(0.12); G.sfx('build', 0.35, this, 0.05); }
      this.pos.y = 0; this.vy = 0; this.onGround = true;
    } else this.onGround = false;
    arenaCollide(this.pos, this.radius, this);
    // поворот
    const face = this.action?.face;
    if (face) this.faceTo(face.pos || face);
    else if (!this.flung && this.hspeed() > 1.5 && mul > 0.2) this.targetYaw = Math.atan2(this.hv.x, this.hv.z);
    this.yaw = lerpAngle(this.yaw, this.targetYaw, 1 - Math.exp(-16 * dt));
    this.animate(dt);
  }

  updateHumanPassive(dt) {
    const G = this.G, now = G.time;
    // Терпение: стоишь ≥0.5 с — урон −10% (см. damageHuman) и +1–3 HP каждые 0.5 с; на 1 HP не работает
    if (this.roleId === 'pat') {
      const still = this.onGround && !this.flung && this.hspeed() < 0.9 && this.moveDir.lengthSq() < 0.01;
      this.stillT = still ? this.stillT + dt : 0;
      if (this.stillT >= 0.5 && this.hp > 1 && this.hp < this.maxHp && G.state === 'fight') {
        this.regenT -= dt;
        if (this.regenT <= 0) {
          this.regenT += 0.5;
          this.heal(1 + Math.floor(Math.random() * 3));
          if (Math.random() < 0.7) G.fx.spark(this.pos.x + (Math.random() - 0.5) * 1.6, this.pos.y + 1 + Math.random() * 3, this.pos.z + (Math.random() - 0.5) * 1.6, 0, 2.2, 0, 0.6, 0.45, 0x8ff8f8);
        }
      } else this.regenT = 0.5;
    }
    // зелье лечения: +56% макс. HP за 45 с, каждую секунду снимает карму
    if (now < this.healUntil) {
      this.heal(this.healRate * dt);
      this.krClearT -= dt;
      if (this.krClearT <= 0) { this.krClearT = 1; this.karma = 0; }
    }
    if (now < this.holyUntil) this.karma = 0; // святое зелье: карма не липнет
  }

  updateMonsterPassive(dt) {
    // уклонения не восстанавливаются (как у классического Санса)
    this.glow = Math.max(0, this.glow - dt * 1.5);
    const m = this.model, e = m.eye;
    if (!e || !e.visible) return;
    const k = 0.62 + this.glow * 0.8 + Math.sin(this.animT * 9) * 0.05;
    e.scale.setScalar(k * m.eyeSize);
    // слабый голубой «огонёк» над глазом: 2–4 частицы в секунду (и больше, когда Судья колдует)
    this.wispT -= dt * (1 + this.glow * 4);
    if (this.wispT <= 0) {
      this.wispT = 0.25 + Math.random() * 0.25;
      e.getWorldPosition(V2);
      this.G.fx.spark(V2.x + (Math.random() - 0.5) * 0.15, V2.y + 0.15, V2.z + (Math.random() - 0.5) * 0.15, (Math.random() - 0.5) * 0.5, 1.4 + Math.random() * 0.8, (Math.random() - 0.5) * 0.5, 0.7, 0.42, Math.random() < 0.3 ? 0x7fffd0 : 0x3fe0ff);
    }
  }

  animate(dt) {
    const m = this.model, p = m.parts;
    p.armL.rotation.set(0, 0, 0); p.armR.rotation.set(0, 0, 0); p.legL.rotation.set(0, 0, 0); p.legR.rotation.set(0, 0, 0);
    p.hips.rotation.set(0, 0, 0); p.neck.rotation.set(0, 0, 0); p.hips.position.y = m.hipY ?? 2;
    const hs = this.hspeed();
    const st = !this.onGround ? 'air' : hs > 1.5 ? 'run' : 'idle';
    let hop = 0;
    if (this.team === 'monster') hop = this.animateJudge(st, hs);
    else {
      animateAvatar(m, st, this.animT, clamp(hs / 16, 0.6, 1.4));
      if (this.flung) { // кувырок в воздухе: руки и ноги болтаются
        const t = this.animT * 22;
        p.armL.rotation.set(-2.2 + Math.sin(t) * 0.9, 0, -0.6 + Math.cos(t * 1.3) * 0.4);
        p.armR.rotation.set(-2.2 + Math.cos(t) * 0.9, 0, 0.6 - Math.sin(t * 1.2) * 0.4);
        p.legL.rotation.x = Math.sin(t * 0.8) * 0.8; p.legR.rotation.x = -Math.sin(t * 0.8) * 0.8;
        p.hips.rotation.x = -0.35;
      }
    }
    // победители радуются
    if (this.G.winnerTeam === this.team && (this.G.state === 'end' || this.G.state === 'results')) {
      const w = Math.sin(this.animT * 9);
      p.armL.rotation.set(-2.8, 0, -0.35 + w * 0.25); p.armR.rotation.set(-2.8, 0, 0.35 - w * 0.25);
      p.hips.position.y = (m.hipY ?? 2) + Math.abs(Math.sin(this.animT * 6)) * 0.35;
    }
    const a = this.action;
    if (a?.pose) a.pose(p, clamp(a.t / a.dur, 0, 1), a, this);
    if (this.stunned) { p.neck.rotation.z = Math.sin(this.animT * 8) * 0.25; p.hips.rotation.x = -0.15; }
    m.root.position.copy(this.pos); m.root.position.y += hop;
    m.root.rotation.set(0, this.yaw, 0);
    if (this.flung) m.root.rotation.x = -0.5 * Math.sin(Math.min(1, (this.G.time - this.flungAt) / 0.66) * Math.PI);
    if (m.shadow) {
      m.shadow.position.set(this.pos.x, 0.06, this.pos.z);
      const s = 1 / (1 + this.pos.y * 0.08); m.shadow.scale.set(s, s, s);
      m.shadow.material.opacity = s;
    }
    // Решимость: 2 с мерцания белым/красным (8 Гц) после второй жизни
    if (this.team === 'human' && this.G.time < this.dtUntil) {
      const on = Math.floor(this.G.time * 16) % 2 === 0;
      for (const mt of m.mats) mt.emissive.setHex(on ? 0xffffff : 0xd00000);
      this.dtFlick = true;
    } else if (this.dtFlick) { this.dtFlick = false; for (const mt of m.mats) mt.emissive.setHex(mt.userData.e0); }
    else if (this.flashT > 0) { // вспышка от удара: люди — красная 0.1 с, Судья — белая
      this.flashT -= dt;
      const k = this.flashT > 0 ? 1 : 0;
      if (this.team === 'human') for (const mt of m.mats) mt.emissive.setRGB(k * 0.85, 0, 0);
      else for (const mt of m.mats) mt.emissive.setRGB(k * 0.9, k * 0.9, k * 0.9);
      if (this.flashT <= 0) for (const mt of m.mats) mt.emissive.setHex(mt.userData.e0);
    }
    // аура зелья
    if (m.aura) {
      const now = this.G.time, pid = this.potionId;
      const on = !!pid && now < this.potionUntil;
      m.aura.visible = on;
      if (on) { m.aura.material.opacity = 0.32 + Math.sin(this.animT * 5) * 0.08 + (pid === 'holy' ? 0.12 : 0); }
    }
  }

  // Судья: руки в карманах, дыхание (≈0.4 Гц), короткие медленные шаги (размах ≤0.45 рад)
  animateJudge(st, hs) {
    const m = this.model, p = m.parts, hy = m.hipY ?? 2, t = this.animT;
    const pk = m.pocket || { x: -0.2, z: 0.18 };
    p.armL.rotation.set(pk.x, 0, pk.z); p.armR.rotation.set(pk.x, 0, -pk.z);
    const br = Math.sin(t * TAU * 0.4);
    if (st === 'run') {
      const w = t * 8.5 * clamp(hs / 16, 0.6, 1.3), s = Math.sin(w);
      p.legL.rotation.x = s * 0.42; p.legR.rotation.x = -s * 0.42;
      p.hips.position.y = hy + Math.abs(Math.cos(w)) * 0.06;
      p.hips.rotation.y = s * 0.05;
      p.armL.rotation.x = pk.x - s * 0.06; p.armR.rotation.x = pk.x + s * 0.06;
    } else if (st === 'air') {
      p.legL.rotation.x = 0.3; p.legR.rotation.x = -0.15;
    } else {
      p.hips.position.y = hy + br * 0.05;
      p.neck.rotation.x = br * 0.03; p.neck.rotation.z = Math.sin(t * 0.7) * 0.03;
    }
    if (p.torso.userData.sy) p.torso.scale.y = 1 + br * 0.015;
    // уклонение: наклон 15° в сторону шага, подскок на 0.5
    let hop = 0;
    const k = this.sideT > 0 ? 1 - this.sideT / DODGE_IFRAMES : 1, w = Math.sin(Math.PI * Math.min(1, k * 1.15));
    if (this.sideT > 0) { p.legL.rotation.x *= 0.3; p.legR.rotation.x *= 0.3; hop = 0.5 * Math.sin(Math.PI * k); }
    m.body.rotation.z = this.sideT > 0 ? -this.sideLean * 0.26 * w : 0;
    return hop;
  }

  updateDead(dt) {
    this.deadT += dt;
    const G = this.G, m = this.model, t = this.deadT;
    if (this.team === 'monster') { this.updateJudgeDeath(dt); return; }
    // Человек (§1.3): замер 0.3 с → душа вылетает из груди → трескается пополам → осколки; тело тает
    if (this.pos.y > 0) { this.vy -= GRAV * dt; this.pos.y = Math.max(0, this.pos.y + this.vy * dt); }
    m.root.position.copy(this.pos); m.root.rotation.set(0, this.yaw, 0);
    if (m.shadow) m.shadow.material.opacity = Math.max(0, 1 - t / 1.4);
    if (t < 0.3) { for (const mt of m.mats) mt.emissive.setRGB(0.55, 0, 0); }
    else if (!this.fadeOn) { this.fadeOn = true; for (const mt of m.mats) mt.emissive.setHex(mt.userData.e0); }
    if (t >= 0.3) {
      const a = Math.max(0, 1 - (t - 0.3) / 1.2);
      fadeModel(m, a);
      if (a <= 0 && m.root.visible) { m.root.visible = false; if (m.shadow) m.shadow.visible = false; }
    }
    const s = this.soul;
    if (!s) return;
    const y0 = this.pos.y + 3.1;
    if (t < 0.3) { s.visible = false; return; }
    if (!this.soulPop) { this.soulPop = true; s.visible = true; s.material.map = heartTex(this.color); s.material.needsUpdate = true; G.jd?.('pop', this, 0.9); }
    const k = Math.min(1, (t - 0.3) / 0.35), e = 1 - Math.pow(1 - k, 3);
    const over = k < 1 ? 1 + Math.sin(k * Math.PI) * 0.25 : 1;
    s.position.set(this.pos.x, y0 + e * 1.4, this.pos.z);
    s.scale.setScalar(1.9 * e * over);
    if (!this.soulCrack && t >= 0.95) {
      this.soulCrack = true; s.material.map = heartTex(this.color, true); s.material.needsUpdate = true;
      G.jd?.('crack', this, 1);
      V.copy(s.position); G.fx.burst(V, this.color, 8, 4, 0.35, 0.3, { up: 1, g: 4 });
    }
    if (this.soulCrack && t < 1.25) s.position.x += Math.sin(t * 90) * 0.06; // дрожит после трещины
    if (!this.soulGone && t >= 1.75) {
      this.soulGone = true; s.visible = false;
      V.copy(s.position); G.fx.burst(V, this.color, 18, 6, 0.4, 0.7, { up: 3, g: 14, drag: 1 });
      G.jd?.('shatter', this, 0.8);
    }
  }

  // Судья (V4): последнее уклонение, разрез, реплики; тело тает за FADE_TIME (полоска «0/1» остаётся), пыль с подола.
  // Разрез и начало таяния запускает катсцена (main.js): judgeSlash() и this.fadeAt.
  updateJudgeDeath(dt) {
    const G = this.G, m = this.model;
    if (this.sideT > 0) { // последний шаг в сторону
      const D = DODGE_IFRAMES, e = (k) => 1 - Math.pow(1 - k, 3);
      const k0 = 1 - this.sideT / D; this.sideT = Math.max(0, this.sideT - dt); const k1 = 1 - this.sideT / D;
      this.pos.addScaledVector(this.sideDir, this.sideDist * (e(k1) - e(k0)));
      arenaCollide(this.pos, this.radius);
    }
    this.hv.set(0, 0, 0);
    this.animate(dt);
    if (this.slashT != null) { // разрез: быстро «прочерчивается» и чуть пульсирует
      this.slashT += dt;
      const k = Math.min(1, this.slashT / 0.12);
      m.slash.scale.set(k * 1.0, 1 + Math.sin(this.slashT * 14) * 0.04 * (1 - Math.min(1, this.slashT)), 1);
    }
    if (this.fadeAt == null) return;
    const ft = this.deadT - this.fadeAt, a = Math.max(0, 1 - ft / FADE_TIME);
    m.setFade(a);
    if (m.shadow) m.shadow.material.opacity = a;
    // пыль сыплется с подола толстовки в последние 0.8 с
    if (ft > FADE_TIME - 0.8 && a > 0) {
      const n = G.fx.q < 1 ? 2 : 4;
      for (let i = 0; i < n; i++) {
        const ang = Math.random() * TAU, r = 0.6 + Math.random() * 0.9;
        V.set(this.pos.x + Math.cos(ang) * r * 1.2, 1.7 + Math.random() * 0.5, this.pos.z + Math.sin(ang) * r * 0.9);
        G.fx.fall(V, Math.random() < 0.5 ? 0x9a9aa4 : 0xc4c4cc, 0.5 + Math.random() * 0.4, 1.2);
      }
      if (!this.dustSnd) { this.dustSnd = true; G.jd?.('dust', this, 1); }
    }
    if (a <= 0 && m.root.visible) {
      m.root.visible = false; if (m.shadow) m.shadow.visible = false;
      V.set(this.pos.x, 0.3, this.pos.z); G.fx.puff(V, 10, 0x9a9aa4, 1.6, 1.0, 2.5);
    }
  }
}

// Плавно растворить модель человека (все материалы, включая оружие и ауру)
export function fadeModel(m, a) {
  if (!m.allMats) {
    m.allMats = [];
    m.root.traverse((o) => { if (o.material) for (const mt of [].concat(o.material)) if (!m.allMats.includes(mt)) { mt.userData.op0 = mt.opacity; mt.userData.tr0 = mt.transparent; m.allMats.push(mt); } });
  }
  for (const mt of m.allMats) {
    const tr = a < 0.999 || mt.userData.tr0;
    if (mt.transparent !== tr) { mt.transparent = tr; mt.needsUpdate = true; }
    mt.opacity = mt.userData.op0 * a;
  }
}

// ---------- урон ----------
// Решимость: на 1 HP — снова полное здоровье, 2 с неуязвимости, карма сгорает. Один раз за раунд.
export function secondLife(G, h) {
  if (h.dtUsed || h.dead) return;
  h.dtUsed = true; h.hp = h.maxHp; h.karma = 0; h.krT = 0;
  h.iframeUntil = G.time + 2; h.dtUntil = G.time + 2; h.pulseAt = G.time;
  V.set(h.pos.x, h.pos.y + 3, h.pos.z);
  G.fx.burst(V, 0xff2020, 30, 12, 0.7, 0.8, { up: 6, g: -1 });
  G.fx.burst(V, 0xffffff, 16, 9, 0.5, 0.5);
  G.fx.ring(h.pos, 0xff3030, 1, 9, 0.6); G.fx.ring(h.pos, 0xffffff, 0.5, 6, 0.4);
  G.fx.flare(V, 0xff4040, 7, 0.5);
  if (h.isPlayer || h === G.camFocus) G.fx.flash('#ffffff', 0.55);
  G.jd?.('chime', h, 1);
  G.onEvent('secondlife', { h });
}

// o.tick — «тиковый» урон (лучи, зона костей): без всплывающих цифр, звук/искры не чаще 1 раза в 0.15 с
export function damageHuman(G, h, amount, src, o = {}) {
  if (!h || h.dead || G.state !== 'fight') return false;
  const now = G.time, tick = !!o.tick;
  if (now < h.iframeUntil && !o.unblockable) return false;
  if (h.roleId === 'pat' && h.stillT >= 0.5) amount *= 0.9; // Терпение: стоишь — урон −10%
  amount = Math.max(0.5, amount);
  if (h.shield > 0) { // святое зелье: щит на всё здоровье (золотой сегмент полоски)
    const ab = Math.min(h.shield, amount); h.shield -= ab; amount -= ab;
    if (now - (h.lastTickFx || 0) > 0.15) { h.lastTickFx = now; G.fx.burst(V.copy(h.pos).setY(h.pos.y + 3), 0xffe080, tick ? 4 : 8, 7, 0.6, 0.35); G.sfx('block', 0.45, h); }
    if (amount <= 0.01) return true;
  }
  h.hp -= amount; h.lastHurtAt = now;
  if (o.karma !== false && src?.team === 'monster' && now >= h.holyUntil) { if (h.karma <= 0) h.krT = krInterval(amount); h.karma = Math.min(KR_CAP, h.karma + amount); }
  h.stats.taken += amount;
  if (G.dmgLog) G.dmgLog[o.cause || '?'] = (G.dmgLog[o.cause || '?'] || 0) + amount;
  if (src) src.stats.dmg += amount;
  if (o.kb) h.kb.add(o.kb);
  if (o.lift && h.onGround) { h.vy = o.lift; h.onGround = false; }
  // «больно» (§7.4): красная вспышка 0.1 с + хрусткий «ай», не чаще раза в 0.15 с на человека. Без цифр и тряски.
  if (now - (h.lastTickFx || 0) > 0.15) {
    h.lastTickFx = now; h.flashT = 0.1;
    V.set(h.pos.x, h.pos.y + 3, h.pos.z);
    G.fx.burst(V, o.color || 0xffffff, 4, 7, 0.45, 0.3);
    G.jd?.('hurt', h, h.isPlayer ? 0.9 : 0.6, null, 0.03);
    if (h.isPlayer || h === G.camFocus) G.fx.hurt(h.hp / h.maxHp < 0.3 ? 0.22 : 0.1);
  }
  if (h.hp <= 1 && h.roleId === 'det' && !h.dtUsed) { secondLife(G, h); return true; }
  G.onEvent('hurt', { h, src, amount });
  if (h.hp <= 0) killHuman(G, h, src, o.cause);
  return true;
}

export function killHuman(G, h, src, cause = '') {
  if (h.dead) return;
  h.dead = true; h.deadT = 0; h.hp = 0; h.karma = 0; h.action = null; h.shield = 0; h.flung = false;
  if (src) src.stats.kills++;
  h.hv.set(0, 0, 0); h.kb.set(0, 0, 0); h.vy = 0;
  h.soulPop = h.soulCrack = h.soulGone = h.fadeOn = false;
  G.jd?.('hurt', h, h.isPlayer ? 1 : 0.7);
  if (h.bot) h.bot.dead = true;
  // душа вылетит из груди через 0.3 с и треснет пополам (updateDead)
  if (!h.soul) {
    h.soul = new THREE.Sprite(new THREE.SpriteMaterial({ map: heartTex(h.color), transparent: true, depthWrite: false, depthTest: false, fog: false }));
    h.soul.renderOrder = 8;
  }
  h.soul.position.set(h.pos.x, h.pos.y + 3.1, h.pos.z); h.soul.scale.setScalar(0.01); h.soul.visible = false; h.soul.material.opacity = 1;
  G.scene.add(h.soul);
  G.onEvent('kill', { h, src, cause });
}

// Удар по Судье (спека C1/C1b/C2/C3/C13):
//  • в окне неуязвимости после уклонения (0.6 с) — удар просто теряется (без MISS и без траты);
//  • есть уклонения — «MISS», −1 уклонение (o.dodges: 2 у перчатки Храбрости; зелье силы — шанс 1/3 на +1),
//    шаг в сторону и 0.6 с неуязвимости. Снаряды и способности (o.noLast) не могут снять последнее уклонение;
//  • уклонений 0 — урон по HP (у Судьи 1 HP) → смерть.
// Возвращает false (удар потерян), 'miss' (снято уклонение) или true (урон по HP).
export function damageMonster(G, m, amount, src, o = {}) {
  if (!m || m.dead || G.state !== 'fight') return false;
  const now = G.time;
  if (now < m.iframeUntil) return false;
  m.lastHitAt = now;
  if (m.dodges > 0) {
    let cost = Math.max(1, o.dodges || 1);
    if (src && src.mightUntil > now && Math.random() < 1 / 3) cost++;
    cost = Math.min(cost, m.dodges);
    if (o.noLast) cost = Math.min(cost, m.dodges - 1);
    m.dodges -= cost; m.stats.dodged++; m.lastDodgeAt = now; m.lastDodgeSrc = src;
    m.iframeUntil = now + DODGE_IFRAMES;
    if (src) src.stats.dmg += Math.round(amount); // «урон» людей в итогах = сила попаданий
    sideStep(G, m, src);
    G.onEvent('dodge', { m, src, left: m.dodges, cost });
    return 'miss'; // попадание засчитано (уклонение потрачено), но урона нет
  }
  amount = Math.max(1, Math.round(amount));
  m.hp = Math.max(0, m.hp - amount); m.lastHurtAt = now; m.stats.taken += amount;
  if (src) src.stats.dmg += amount;
  G.onEvent('mhit', { m, src, amount });
  if (m.hp <= 0) {
    // «Судья уклоняется от последнего удара… и получает следующий» — шаг в сторону без MISS, дальше катсцена
    m.dead = true; m.deadT = 0; m.slashT = null; m.fadeAt = null; m.dustSnd = false;
    m.action = null; m.moveDir.set(0, 0, 0); m.kb.set(0, 0, 0);
    sideStep(G, m, src, true);
    if (src) src.stats.kills++;
    G.onEvent('mdead', { m, src });
  }
  return true;
}

// Уклонение: «MISS» рядом с головой + скольжение на 4–5 стадов поперёк линии «атакующий → Судья»,
// в ту сторону, где больше места (дальше от стен и колонн). Наклон, подскок, вспышка глаза, свист + шорох.
export function sideStep(G, m, src, noMiss = false) {
  V2.subVectors(m.pos, src ? src.pos : m.pos).setY(0);
  if (V2.lengthSq() < 0.01) m.fwd(V2).negate();
  V2.normalize();
  const nx = -V2.z, nz = V2.x, D = m.sideDist;
  const sc = (s) => clearance(m.pos.x + nx * s * D + V2.x * 0.8, m.pos.z + nz * s * D + V2.z * 0.8) + Math.random() * 0.8;
  const side = sc(1) >= sc(-1) ? 1 : -1;
  m.sideDir.set(nx * side + V2.x * 0.18, 0, nz * side + V2.z * 0.18).normalize();
  m.sideT = DODGE_IFRAMES;
  // наклон в сторону шага: + — вправо от взгляда Судьи
  m.sideLean = Math.sign(m.sideDir.x * Math.cos(m.yaw) - m.sideDir.z * Math.sin(m.yaw)) || 1;
  m.glow = 1;
  const e = m.model.eye;
  if (e && e.visible) { m.model.root.updateMatrixWorld(true); e.getWorldPosition(V); G.fx.flare(V, 0x6ff4ff, 2.6, 0.25); }
  if (!noMiss) G.fx.miss(m, G.camera);
  G.fx.puff(m.pos, 3, 0xc8a040, 1.0, 0.4, 2.5);
  G.jd?.('miss', m, 0.9, null, 0.05);
}

// Красный разрез поперёк груди Судьи (катсцена смерти): металлический «вжик», вспышка, искры
export function judgeSlash(G, m) {
  m.slashT = 0; m.model.slash.visible = true; m.model.slash.scale.set(0.01, 1, 1);
  m.model.root.updateMatrixWorld(true); m.model.slash.getWorldPosition(V);
  G.fx.burst(V, 0xff2020, 26, 12, 0.5, 0.45, { up: 2, g: 6 });
  G.fx.flare(V, 0xff3030, 6, 0.3);
  G.fx.flash('#ff1a1a', 0.28); G.fx.shake(0.12);
  G.jd?.('slice', null, 1);
}

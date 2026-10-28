// Боец: состояние, физика, M1-комбо, блок, рывки, уклонение (evasive), всплеск (burst), пробуждение, урон.
import * as THREE from 'three';
import { G } from './ctx.js';
import { buildModel, LOOKS, setKatana, setModelFade } from './rig.js';
import { NK, K, kf, blendInto, applyPose, POSE, M1ANIM, m1Variant, runPose, PX } from './anim.js';
import { clamp, rand, angleDamp, wrapAngle } from './util.js';
import { CHARS } from './skills.js';

// Физика роблокса (спека §0): гравитация 196.2, прыжок 40 (вершина ≈4.1 стада, ≈0.41 с в воздухе).
// Все вертикальные скорости отбрасывания масштабируются на VYK = √(196.2/82) ≈ 1.55 — та же высота полёта.
export const GRAV = 196.2, JUMP_V = 40;
export const VYK = Math.sqrt(196.2 / 82);
// Ходьба 16, бег ≈26 при джойстике дальше ~90 % (Auto Run)
export const WALK = 16, RUN = 26;
const DI_MAX = 5; // «направленное влияние» в полёте: до ±5 стадов
// Числа JJS (спека §5): M1 3+3+4+4, оглушение 0.75 с, 2 с простоя после 4-го удара, сброс цепочки через 1.2 с
export const M1_DMG = [3, 3, 4, 4];
const M1_STUN = 0.75, M1_DOWNTIME = 2.0, M1_RESET = 1.2, M1_WHIFF = 0.25, M1_BLOCKED = 0.5;
// Пробуждение заполняется только нанесённым уроном (JJS: 285.7 урона; для 4-минутного матча — ×0.45 ≈ 222)
export const AW_FILL = 0.45;
export const AW_DUR = 60;
// Рывки
export const FDASH_CD = 6, SDASH_CD = 2, BURST_CD = 7;
const FDASH_DIST = 25, FDASH_T = 0.42, SDASH_DIST = 17.5, SDASH_T = 0.3;

const _d = new THREE.Vector3(), _v = new THREE.Vector3(), _w = new THREE.Vector3(), _hp = new THREE.Vector3();
const _q = new THREE.Quaternion();
const JAB_WIND = PX(POSE.dashF, { rax: 0.6, raz: -0.3, twist: -0.5, lax: -1.2, laz: 0.2, hy: -0.35 });
const JAB_HIT = PX(POSE.idle.fist, { rax: -1.75, raz: 0.05, twist: 0.8, cx: 0.3, hy: -0.35, lax: -0.4, laz: 0.4, llx: -0.5, rlx: 0.5, lean: 0.15 });

export class Fighter {
  constructor({ name, isPlayer = false, isClaude = false, bot = null, skin, charId, color = '#fff' }) {
    this.name = name; this.isPlayer = isPlayer; this.isClaude = isClaude; this.bot = bot;
    this.skin = skin; this.color = color;
    this.pos = new THREE.Vector3(); this.vel = new THREE.Vector3();
    this.yaw = 0; this.onGround = true; this.lockYaw = null;
    this.maxHp = 100; this.hp = 100;
    this.meter = 0; this.awakened = 0;
    this.dead = true; this.respawnT = 0;
    this.kills = 0; this.deaths = 0; this.dmgDealt = 0;
    // перезарядки: базовый набор и набор пробуждения тикают независимо
    this.cdBase = [0, 0, 0, 0]; this.cdMaxBase = [1, 1, 1, 1];
    this.cdAw = [0, 0, 0, 0]; this.cdMaxAw = [1, 1, 1, 1];
    this.cd = this.cdBase; this.cdMax = this.cdMaxBase;
    this.specCd = 0; this.specCdMax = 1;
    this.fdashCd = 0; this.sdashCd = 0; this.m1Cd = 0; this.m1Buf = 0; this.jumpBuf = 0;
    this.combo = 0; this.comboT = 0;
    this.stun = 0; this.broken = 0; this.rag = false; this.ragT = 0; this.ragTrue = false; this.down = 0; this.wakeT = 0;
    this.iframes = 0; this.prot = 0; this.hitstop = 0; this.hitFlash = 0; this.hitVariant = 0; this.whiteT = 0;
    this.blocking = false; this.blockAbsorb = 0; this.counter = 0; this.counterKind = null; this.suspend = 0;
    this.evasive = 0; this.burst = 0; this.burstCd = 0; this.atkLog = []; this.burstOrb = null;
    this.lastDealtT = -99; this.bfChain = 0; this.bfChainT = 0;
    // Проклятый напарник: 0 — Рики нет, 1 — призрак у правого плеча, 2 — ячейки переключены на приёмы Рики (общая перезарядка)
    this.rikaMode = 0; this.rikaT = 0; this.cdRk = [0, 0, 0, 0]; this.cdMaxRk = [1, 1, 1, 1];
    this.katT = -99; this.vanish = 0; this.chant = 0; this.charge = null;
    this.action = null;
    this.input = { mx: 0, mz: 0, jump: false, jumpHeld: false, block: false };
    this.aim = new THREE.Vector3(0, 0, 1);
    this.lastHitBy = null; this.lastHitT = -99; this.lastDamagedT = -99;
    this.ragSpin = new THREE.Vector3(); this.ragW = new THREE.Vector3();
    this.runPhase = 0; this.runK = 0; this.diLeft = 0;
    this.pose = new Float32Array(NK); this.tp = new Float32Array(NK);
    this.model = null;
    this.setChar(charId);
  }

  // ---------- персонаж ----------
  setChar(id) {
    if (this.model) {
      G.scene.remove(this.model.root);
      this.model.bodyMat.dispose(); this.model.headMat.dispose();
    }
    if (this.awakened > 0) this.endAwaken();
    if (this.ch) this.ch.reset?.(this);
    this.rikaMode = 0; this.chant = 0; this.charge = null; this.vanish = 0;
    this.charId = id;
    this.ch = CHARS[id];
    this.look = LOOKS[id];
    this.maxHp = this.ch.hp || 100;
    if (this.hp > this.maxHp) this.hp = this.maxHp;
    this.model = buildModel(id, this.skin.skin || '#f2c9a0');
    this.model.root.visible = !this.dead;
    G.scene.add(this.model.root);
    this.idlePose = POSE.idle[this.ch.stance];
    this.updateIdle();
    this.pose.set(this.idlePose);
    this.cdBase.fill(0); this.cdAw.fill(0); this.cdRk.fill(0); this.specCd = 0;
    this.cd = this.cdBase; this.cdMax = this.cdMaxBase;
    // смена бойца сбрасывает прогресс пробуждения (как в JJS)
    this.meter = 0;
  }

  spawn(x, z) {
    const gy = G.world.groundAt(x, z, 50);
    this.pos.set(x, gy, z); this.vel.set(0, 0, 0);
    if (this.awakened > 0) this.endAwaken();
    this.hp = this.maxHp; this.dead = false;
    this.stun = this.broken = this.down = this.iframes = this.hitstop = this.wakeT = this.suspend = 0; this.rag = false; this.ragTrue = false;
    this.action = null; this.blocking = false; this.skillBuf = null;
    this.counter = 0; this.awakened = 0;
    this.ch.reset?.(this);
    this.rikaMode = 0; this.chant = 0; this.charge = null; this.vanish = 0; this.cdRk.fill(0);
    if (this.model.katana) { setKatana(this.model, false); this.updateIdle(); }
    setModelFade(this.model, 1);
    this.combo = 0; this.comboT = 0; this.m1Buf = 0; this.jumpBuf = 0;
    this.evasive = 0; this.burst = 0; this.burstCd = 0; this.atkLog.length = 0; this.burstOrb = null;
    this.bfChain = 0; this.bfChainT = 0;
    this.prot = 2.0;
    this.lastHitBy = null; this.lastDamagedT = -99;
    this.cdBase.fill(0); this.cdAw.fill(0); this.cd = this.cdBase; this.cdMax = this.cdMaxBase;
    this.specCd = 0; this.fdashCd = 0; this.sdashCd = 0; this.m1Cd = 0;
    this.yaw = Math.atan2(-x, -z);
    this.ragSpin.set(0, 0, 0);
    this.pose.set(this.idlePose);
    this.model.root.visible = true;
    this.syncModel(0);
    G.fx.ring(_v.set(x, gy + 0.2, z), this.look.color, 1, 7, 0.6, { axis: 'y' });
    G.fx.particles(_v.set(x, gy + 2.5, z), { n: 18, color: ['#ffffff', this.look.color], speed: 6, up: 6, size: 0.9, life: 0.7 });
    G.sound('spawn', this.pos, 0.5);
  }

  // ---------- геометрия ----------
  get scale() { return this.model.root.scale.x; }
  fwd(out) { return out.set(Math.sin(this.yaw), 0, Math.cos(this.yaw)); }
  chestPos(out) { return out.set(this.pos.x, this.pos.y + 3.1 * this.scale, this.pos.z); }
  headPos(out) { return out.set(this.pos.x, this.pos.y + 5.9 * this.scale, this.pos.z); }
  handPos(side, out) { (side === 'L' ? this.model.handL : this.model.handR).getWorldPosition(out); return out; }
  faceTo(p) { const dx = p.x - this.pos.x, dz = p.z - this.pos.z; if (dx * dx + dz * dz > 0.01) this.yaw = Math.atan2(dx, dz); }
  dist(o) { return Math.hypot(o.pos.x - this.pos.x, o.pos.z - this.pos.z); }
  isEnemy(o) { return o !== this && !o.dead && !G.isAlly(this, o); }
  canAct() { return !this.dead && !this.rag && this.down <= 0 && this.stun <= 0 && !this.action; }
  busy() { return this.dead || this.rag || this.down > 0 || this.stun > 0 || !!this.action; }
  airborne() { return !this.onGround && this.pos.y - G.world.groundAt(this.pos.x, this.pos.z, this.pos.y) > 2.5; }
  canJump() { return !this.dead && !this.rag && this.down <= 0 && this.onGround && !this.blocking; }
  mods() { return this.awakened > 0 ? this.ch.awaken.mods || {} : {}; }
  dmgMult() { return this.mods().dmg || 1; }
  cdMult() { return this.mods().cd || 1; }
  walkSpeed() { return WALK * (this.mods().speed || 1); }

  // Мягкий автоприцел: ближайший враг в конусе направления взгляда (или совсем рядом)
  autoTarget(maxDist = 16, minDot = 0.35) {
    let best = null, bs = 1e9;
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    for (const o of G.fighters) {
      if (!this.isEnemy(o)) continue;
      const dx = o.pos.x - this.pos.x, dz = o.pos.z - this.pos.z;
      const d = Math.hypot(dx, dz);
      if (d > maxDist || Math.abs(o.pos.y - this.pos.y) > 14) continue;
      const dotA = d > 0.01 ? (dx * this.aim.x + dz * this.aim.z) / d : 1;
      const dotF = d > 0.01 ? (dx * fx + dz * fz) / d : 1;
      const dot = Math.max(dotA, dotF * 0.9);
      if (dot < minDot && d > 4.5) continue;
      let s = d * (1.7 - dot);
      if (o === this.lastTarget) s *= 0.75;
      if (s < bs) { bs = s; best = o; }
    }
    if (best) this.lastTarget = best;
    return best;
  }
  // Цель для навыков «TARGET» (спека §2.1): враг в ≈20° конусе вокруг луча камеры, ближайший к лучу;
  // иначе — ближайший враг впереди (≤90°); иначе null (навык не тратит перезарядку).
  camTarget(range) {
    let best = null, ba = 1e9, near = null, nd = 1e9;
    const cr = this.isPlayer ? G.camRay : null;
    if (cr) {
      // игрок: луч из центра камеры (с наклоном), конус ≈20°; иначе — ближайший враг перед собой (≤90°)
      for (const o of G.fighters) {
        if (!this.isEnemy(o)) continue;
        const d = this.dist(o);
        if (d > range || Math.abs(o.pos.y - this.pos.y) > 30) continue;
        o.chestPos(_v).sub(cr.origin);
        const l = _v.length() || 1;
        const dot = _v.dot(cr.dir) / l;
        if (dot >= 0.9397) { const ang = Math.acos(Math.min(1, dot)); if (ang < ba) { ba = ang; best = o; } }
        const dx = o.pos.x - this.pos.x, dz = o.pos.z - this.pos.z;
        if (dx * this.aim.x + dz * this.aim.z >= 0 && d < nd) { nd = d; near = o; }
      }
      const t = best || near;
      if (t) this.lastTarget = t;
      return t;
    }
    const ax = this.aim.x, az = this.aim.z;
    for (const o of G.fighters) {
      if (!this.isEnemy(o)) continue;
      const dx = o.pos.x - this.pos.x, dz = o.pos.z - this.pos.z;
      const d = Math.hypot(dx, dz);
      if (d > range || Math.abs(o.pos.y - this.pos.y) > 18) continue;
      const dot = d > 0.01 ? (dx * ax + dz * az) / d : 1;
      if (dot >= 0.94) { const ang = Math.acos(Math.min(1, dot)) * (1 + d / range * 0.3); if (ang < ba) { ba = ang; best = o; } }
      else if (dot > 0 && d < nd) { nd = d; near = o; }
    }
    const t = best || near || (this.brain && this.brain.target && this.isEnemy(this.brain.target) && this.dist(this.brain.target) <= range ? this.brain.target : null);
    if (t) this.lastTarget = t;
    return t;
  }
  // Направление прицела: у игрока — в точку под центром экрана (камера с наклоном), у бота — вперёд
  aimDir(origin, out) {
    const cr = this.isPlayer ? G.camRay : null;
    if (!cr) return this.fwd(out);
    let t = 90;
    if (cr.dir.y < -0.02) t = Math.min(t, (cr.origin.y - 0.3) / -cr.dir.y);
    out.copy(cr.origin).addScaledVector(cr.dir, Math.max(t, 18)).sub(origin);
    if (out.lengthSq() < 1e-4) this.fwd(out);
    return out.normalize();
  }
  // Катана Проклятого напарника: обнажается для M1 и приёмов мечом, убирается в ножны через 8 с без боя
  drawKatana() {
    this.katT = G.time;
    const m = this.model;
    if (!m.katana || m.katDrawn) return;
    setKatana(m, true);
    this.updateIdle();
    m.handR.getWorldPosition(_v);
    G.fx.burst(_v, '#ffe6fb', 2.5, 0.12);
    G.sound('slash', this.pos, 0.25);
  }
  updateIdle() {
    if (this.model && this.model.katana) this.idlePose = this.model.katDrawn ? POSE.idle.katana : POSE.idle.katanaH;
  }
  setRikaMode(m) {
    this.rikaMode = m;
    if (this.awakened > 0) return;
    this.cd = m === 2 ? this.cdRk : this.cdBase;
    this.cdMax = m === 2 ? this.cdMaxRk : this.cdMaxBase;
  }
  // Эмоция (колесо 🕺): отменяется прыжком, M1, блоком, ударом, движением
  emote(def) {
    if (!this.canAct() || !this.onGround || this.blocking) return false;
    this.startAction({ name: 'emote', dur: def.dur || 99, allowJump: true, poseSpeed: 12, emote: def, pose: (f, a, out) => def.pose(f, a.t, out) });
    return true;
  }
  // Враги в конусе перед собой
  meleeTargets(range, cosMin = 0.35, dyMax = 4.5) {
    const out = [];
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    for (const o of G.fighters) {
      if (!this.isEnemy(o)) continue;
      const dx = o.pos.x - this.pos.x, dz = o.pos.z - this.pos.z, dy = o.pos.y - this.pos.y;
      const d = Math.hypot(dx, dz);
      if (d > range + 1 || dy > dyMax || dy < -dyMax) continue;
      if (d > 2.4 && (dx * fx + dz * fz) / d < cosMin) continue;
      out.push(o);
    }
    return out;
  }
  enemiesNear(p, r, maxDy = 8) {
    const out = [];
    for (const o of G.fighters) {
      if (!this.isEnemy(o)) continue;
      const dx = o.pos.x - p.x, dz = o.pos.z - p.z, dy = o.pos.y + 2.5 - p.y;
      if (dx * dx + dz * dz <= r * r && Math.abs(dy) <= maxDy) out.push(o);
    }
    return out;
  }

  // ---------- действия ----------
  startAction(a) {
    a.t = 0; a.ev = 0;
    if (a.events) a.events.sort((x, y) => x[0] - y[0]);
    this.action = a;
    this.blocking = false;
    if (a.iframes) this.iframes = Math.max(this.iframes, a.iframes);
    return a;
  }
  endAction() {
    const a = this.action;
    this.action = null;
    if (a && a.onEnd) a.onEnd(this, a);
  }
  interrupt(force = false) {
    const a = this.action;
    if (!a || (a.armor && !force)) return false;
    this.action = null;
    if (a.onCancel) a.onCancel(this, a);
    return true;
  }
  updateAction(dt) {
    const a = this.action;
    a.t += dt;
    if (a.events) {
      while (a.ev < a.events.length && a.t >= a.events[a.ev][0]) {
        const fn = a.events[a.ev][1]; a.ev++;
        fn(this, a);
        if (this.action !== a) return;
      }
    }
    if (a.update) { a.update(this, dt, a.t, a); if (this.action !== a) return; }
    if (a.move) {
      const sp = this.walkSpeed() * a.move;
      this.vel.x = this.vel.x + (this.input.mx * sp - this.vel.x) * (1 - Math.exp(-10 * dt));
      this.vel.z = this.vel.z + (this.input.mz * sp - this.vel.z) * (1 - Math.exp(-10 * dt));
    } else if (!a.keepVel) this.friction(dt, 10);
    if (a.t >= a.dur) this.endAction();
  }
  friction(dt, k) { const f = Math.exp(-k * dt); this.vel.x *= f; this.vel.z *= f; }
  // Короткая «заминка» после промаха/блока: действие без управления
  endlag(t, pose) {
    this.startAction({ name: 'endlag', dur: t, locked: true, pose: (f, a, out) => out.set(pose || PX(f.idlePose, { hy: -0.25, cx: 0.25 })) });
  }

  // ---------- M1 ----------
  m1() {
    if (this.dead || this.blocking) return;
    if (this.action && this.action.name === 'emote') this.action = null;
    const a = this.action;
    if (a && (a.name === 'm1' || a.name === 'sdash' || a.name === 'fdash' || a.name === 'endlag')) { this.m1Buf = 0.35; return; }
    if (!this.canAct() || this.m1Cd > 0) return;
    this.prot = 0;
    if (this.comboT <= 0 || this.combo >= 4) this.combo = 0;
    const n = ++this.combo;
    const last = n === 4;
    // пассив «Shrine» (King of Curses / Heian): M1 — разрезы на 24 стада, без апперкота и удара вниз
    const shrine = this.awakened > 0 && this.ch.awaken.shrineM1;
    const tgt = this.autoTarget(shrine ? 24 : 12, 0.3);
    if (tgt) this.faceTo(tgt.pos);
    const style = this.ch.m1;
    if (style === 'katana') this.drawKatana();
    // 4-й удар: вариант по вертикальной скорости (спека §5.1)
    let variant = 'neutral';
    if (last && !shrine) {
      if (!this.onGround && this.vel.y < -1.5 && !this.input.jumpHeld) variant = 'slam';
      else if (this.input.jumpHeld || (!this.onGround && this.vel.y > 1.5)) variant = 'up';
    }
    const frames = shrine ? M1ANIM.sukuna[3] : variant === 'neutral' ? M1ANIM[style][n - 1] : m1Variant(style, this.idlePose, variant);
    const hitAt = last ? 0.23 : 0.18;
    const dur = last ? 0.5 : 0.36;
    // подтяжка к цели не дальше 2 стадов
    let lunge = 4;
    if (tgt) lunge = clamp(this.dist(tgt) - 3.0, 0, 2) / hitAt;
    if (shrine) lunge *= 0.3;
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    if (!this.onGround && variant !== 'slam' && this.vel.y < 0) this.vel.y *= 0.3;
    this.startAction({
      name: 'm1', kind: 'melee', dur, frames, hitAt, keepVel: true, poseSpeed: 30, n, variant, allowJump: true,
      events: [[hitAt, (f, a) => f.m1Hit(n, a)]],
      update: (f, dt, t, a) => {
        if (t < hitAt) { f.vel.x = fx * lunge; f.vel.z = fz * lunge; if (variant === 'slam') f.vel.y = Math.min(f.vel.y, -37); }
        else f.friction(dt, 14);
        if (!f.onGround && variant !== 'slam' && f.vel.y < -9) f.vel.y = -9;
        if (!last && !a.locked && t > dur * 0.78 && f.m1Buf > 0) f.endAction();
      },
      onEnd: (f) => { if (f.m1Buf > 0 && f.combo < 4 && f.canAct()) { f.m1Buf = 0; f.m1(); } },
    });
    this.comboT = M1_RESET;
    this.m1Buf = 0;
    G.sound(style === 'katana' || shrine ? 'slash' : 'swing', this.pos, 0.45);
    // взмах катаной: розово-белые дуги
    if (style === 'katana') {
      const it = this, act = this.action;
      G.addTask(() => {
        if (it.action !== act) return false;
        if (act.t < hitAt * 0.85) return true;
        it.chestPos(_v); _w.set(Math.sin(it.yaw), 0, Math.cos(it.yaw));
        _v.addScaledVector(_w, 2.5);
        _q.setFromUnitVectors(_d.set(0, 0, 1), _w);
        const roll = n === 1 || n === 4 ? Math.PI / 2 : n === 3 ? 0.25 : -0.25;
        _q.multiply(new THREE.Quaternion().setFromAxisAngle(_d.set(0, 0, 1), roll));
        G.fx.crescent(_v, _q, '#ffd9f7', 2.5, 4.4, 0.18, { a0: 0.95 });
        G.fx.crescent(_v, _q, '#ff7be8', 2.2, 3.6, 0.14, { a0: 0.55 });
        return false;
      });
    }
  }
  m1Hit(n, a) {
    const last = n === 4;
    const aw = this.awakened > 0 ? this.ch.awaken : null;
    if (aw && aw.shrineM1) {
      aw.shrineM1(this, n);
      if (last) this.m1Cd = M1_DOWNTIME;
      // последний разрез Shrine — с заминкой
      if (last && this.action === a) { a.dur = a.hitAt + 0.42; a.locked = true; }
      return;
    }
    let v = a.variant;
    if (last && v === 'neutral' && this.input.jumpHeld) v = 'up';
    const katana = this.ch.m1 === 'katana';
    const range = katana ? 5.9 : 5.4;
    const hits = this.meleeTargets(range + (v === 'slam' ? 1 : 0), 0.35, v === 'slam' ? 7 : 4.5);
    let landed = false, blocked = false;
    for (const o of hits) {
      let r;
      if (!last) {
        r = G.hit(this, o, { dmg: M1_DMG[n - 1], melee: true, m1: true, stun: M1_STUN, push: 2.5, hitstop: 0.055, fx: katana ? 'slash' : 'hit', shake: 0.18, sfx: katana ? 'slash' : 'm1_' + n });
      } else if (v === 'slam') {
        r = G.hit(this, o, { dmg: M1_DMG[3], melee: true, m1: true, unblockable: true, bypassRag: true, downslam: true, rag: 1.0, kb: { f: 6, up: -62 }, hitstop: 0.1, fx: 'heavy', shake: 0.5, sfx: 'm1_4' });
        if (r === 'hit') { _v.set(o.pos.x, G.world.groundAt(o.pos.x, o.pos.z, o.pos.y) + 0.2, o.pos.z); G.fx.crater(_v, 6); G.fx.dust(_v, 12, 3); G.fx.debris(_v, 7); G.fx.ring(_v, '#ffffff', 1, 9, 0.3, { axis: 'y', a0: 0.9 }); }
      } else if (v === 'up') {
        r = G.hit(this, o, { dmg: M1_DMG[3], melee: true, m1: true, rag: 1.1, kb: { f: 8, up: 36 }, hitstop: 0.09, fx: katana ? 'slash' : 'heavy', shake: 0.45, sfx: 'm1_4' });
      } else {
        r = G.hit(this, o, { dmg: M1_DMG[3], melee: true, m1: true, rag: 0.9, kb: { f: 45, up: 12 }, hitstop: 0.085, fx: katana ? 'slash' : 'heavy', shake: 0.45, sfx: 'm1_4' });
      }
      if (r === 'hit' || r === 'break' || r === 'counter') landed = true;
      else if (r === 'blocked') blocked = true;
      // «Стальная рука» (True Love): к каждому из первых трёх M1 — быстрый джеб
      if (!last && aw && aw.steelJab && (r === 'hit' || r === 'break')) aw.steelJab(this, o);
    }
    if (last) {
      this.m1Cd = M1_DOWNTIME;
      if (v === 'up' && landed && this.onGround) { this.vel.y = 37; this.onGround = false; }
    }
    if (this.action !== a) return;
    if (blocked && !landed) { a.dur = a.hitAt + M1_BLOCKED; a.locked = true; this.m1Buf = 0; }
    else if (!landed) a.dur = Math.max(a.dur, a.hitAt + M1_WHIFF);
  }

  // ---------- рывки ----------
  // Направление рывка относительно взгляда (камера у игрока, цель у бота): вперёд/на месте — фронтальный, иначе боковой.
  dashKind() {
    const mx = this.input.mx, mz = this.input.mz, l = Math.hypot(mx, mz);
    if (l < 0.2) return 'front';
    return (mx * this.aim.x + mz * this.aim.z) / l > 0.55 ? 'front' : 'side';
  }
  dashReady(kind = this.dashKind()) { return kind === 'front' ? this.fdashCd <= 0 : this.sdashCd <= 0; }
  dash() {
    if (this.dead || this.blocking) return false;
    // уклонение из рэгдолла (evasive) или всплеск
    if (this.rag || this.down > 0) {
      if (this.burst > 0 && this.burstCd <= 0) this.doBurst();
      if (this.evasive >= 100 && !this.ragTrue) { this.ragCancel(); return true; }
      return false;
    }
    const kind = this.dashKind();
    if (this.action && this.action.name === 'emote') this.action = null;
    if (this.stun > 0) {
      if (!(this.burst > 0 && this.burstCd <= 0)) return false;
      this.doBurst();
      this.stun = 0; this.broken = 0; this.suspend = 0;
      this.interrupt(true);
      return this.sideDash(true);
    }
    const a = this.action;
    if (a) {
      const m1Rec = a.name === 'm1' && !a.locked;
      const startup = a.slot != null && a.t < (a.windup ?? 0.25) && !a.armor;
      if (a.name === 'land') this.action = null;
      else if (kind === 'side' && (m1Rec || startup)) { if (a.onCancel) a.onCancel(this, a); this.action = null; }
      else if (kind === 'front' && m1Rec && a.t >= a.hitAt) this.action = null;
      else return false;
    }
    if (kind === 'side' && this.burst > 0 && this.burstCd <= 0) this.doBurst();
    return kind === 'front' ? this.frontDash() : this.sideDash(false);
  }
  dashDir() {
    let dx = this.input.mx, dz = this.input.mz;
    const l = Math.hypot(dx, dz);
    if (l < 0.2) { dx = this.aim.x; dz = this.aim.z; const k = Math.hypot(dx, dz) || 1; dx /= k; dz /= k; }
    else { dx /= l; dz /= l; }
    return [dx, dz];
  }
  // Фронтальный рывок: скольжение ≈25 стадов с замахом, затем джеб 4 урона (рэгдолл в первой половине пути)
  frontDash() {
    if (this.fdashCd > 0) return false;
    let [dx, dz] = this.dashDir();
    const tgt = this.autoTarget(FDASH_DIST + 2, 0.55);
    if (tgt) { this.faceTo(tgt.pos); dx = Math.sin(this.yaw); dz = Math.cos(this.yaw); }
    else this.yaw = Math.atan2(dx, dz);
    const v0 = (FDASH_DIST * 1.5) / FDASH_T;
    const jab = (f, a, v) => {
      a.jabbed = true;
      const early = a.trav < FDASH_DIST / 2 && f.awakened <= 0;
      f.vel.x *= 0.15; f.vel.z *= 0.15;
      if (v) {
        const r = G.hit(f, v, { dmg: 4, melee: true, stun: M1_STUN, rag: early ? 0.9 : 0, kb: early ? { f: 42, up: 12 } : null, push: early ? 0 : 6, hitstop: 0.09, fx: 'heavy', shake: 0.4, sfx: 'heavy' });
        if (r === 'blocked') { f.endlag(0.75); return; }
        if (r === 'hit') { f.combo = 0; f.comboT = 0; }
      }
      f.startAction({ name: 'fdashJab', dur: 0.26, frames: [[0, JAB_WIND], [0.3, JAB_HIT], [1, f.idlePose]] });
    };
    this.startAction({
      name: 'fdash', dur: FDASH_T, keepVel: true, poseSpeed: 20, trav: 0,
      pose: (f, a, out) => out.set(JAB_WIND),
      update: (f, dt, t, a) => {
        if (tgt && !tgt.dead && f.dist(tgt) > 2) { f.yaw = angleDamp(f.yaw, Math.atan2(tgt.pos.x - f.pos.x, tgt.pos.z - f.pos.z), 10, dt); }
        const fx = Math.sin(f.yaw), fz = Math.cos(f.yaw);
        const k = Math.sqrt(Math.max(0, 1 - t / FDASH_T));
        const sp = v0 * k;
        f.vel.x = fx * sp; f.vel.z = fz * sp;
        a.trav += sp * dt;
        if (Math.random() < 0.7) { _v.set(f.pos.x + rand(-1, 1), f.pos.y + rand(0.5, 4.5), f.pos.z + rand(-1, 1)); _w.set(-fx * 34, 0, -fz * 34); G.fx.str.add(_v, _w, '#ffffff', 0.18, 0.08, 2.6, { drag: 8 }); }
        const v = f.meleeTargets(3.3, 0.55)[0];
        if (v) jab(f, a, v);
      },
      onEnd: (f, a) => { if (!a.jabbed) { const v = f.meleeTargets(4.6, 0.5)[0]; jab(f, a, v || null); } },
    });
    this.fdashCd = FDASH_CD;
    if (this.onGround) G.fx.dust(_v.copy(this.pos), 6, 2);
    G.sound('dash', this.pos, 0.6);
    return true;
  }
  // Боковой/задний рывок: шаг ≈17.5 стадов, управляемый
  sideDash(free) {
    if (!free && this.sdashCd > 0) return false;
    let [dx, dz] = this.dashDir();
    if (Math.hypot(this.input.mx, this.input.mz) < 0.2) { dx = -this.aim.x; dz = -this.aim.z; }
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    const dot = dx * fx + dz * fz, cross = fx * dz - fz * dx;
    const pose = dot < -0.5 ? POSE.dashB : dot > 0.5 ? POSE.dashF : cross > 0 ? POSE.dashR : POSE.dashL;
    const v0 = (SDASH_DIST * 1.5) / SDASH_T;
    let ddx = dx, ddz = dz;
    this.startAction({
      name: 'sdash', dur: SDASH_T, iframes: 0.1, keepVel: true, poseSpeed: 24,
      pose: (f, a, out) => out.set(pose),
      update: (f, dt, t) => {
        // управляемая траектория
        const mx = f.input.mx, mz = f.input.mz, l = Math.hypot(mx, mz);
        if (l > 0.3) { const k = 1 - Math.exp(-7 * dt); ddx += (mx / l - ddx) * k; ddz += (mz / l - ddz) * k; const n = Math.hypot(ddx, ddz) || 1; ddx /= n; ddz /= n; }
        const sp = v0 * Math.sqrt(Math.max(0, 1 - t / SDASH_T));
        f.vel.x = ddx * sp; f.vel.z = ddz * sp;
        if (f.vel.y > 0 && !f.onGround) f.vel.y *= 0.9;
        if (Math.random() < 0.6) { _v.set(f.pos.x + rand(-1, 1), f.pos.y + rand(0.5, 4.5), f.pos.z + rand(-1, 1)); _w.set(-ddx * 30, 0, -ddz * 30); G.fx.str.add(_v, _w, '#ffffff', 0.18, 0.08, 2.4, { drag: 8 }); }
      },
      onEnd: (f) => { if (f.m1Buf > 0) { f.m1Buf = 0; f.m1(); } },
    });
    if (!free) this.sdashCd = SDASH_CD;
    if (this.onGround) G.fx.dust(_v.copy(this.pos), 6, 2);
    G.sound('dash', this.pos, 0.55);
    return true;
  }
  // Уклонение из рэгдолла: встать + рывок + 1 с полной неуязвимости, порыв ветра
  ragCancel() {
    this.rag = false; this.ragTrue = false; this.down = 0; this.stun = 0; this.broken = 0; this.suspend = 0;
    this.ragSpin.set(0, 0, 0);
    this.pose.set(this.idlePose);
    this.evasive = 0;
    this.iframes = Math.max(this.iframes, 1.0);
    if (Math.hypot(this.input.mx, this.input.mz) < 0.2) {
      const src = this.lastHitBy && !this.lastHitBy.dead ? this.lastHitBy : null;
      if (src) { _d.set(this.pos.x - src.pos.x, 0, this.pos.z - src.pos.z).normalize(); const s = Math.random() < 0.5 ? 1 : -1; this.input.mx = _d.x * 0.6 - _d.z * 0.8 * s; this.input.mz = _d.z * 0.6 + _d.x * 0.8 * s; }
    }
    if (!this.onGround) this.vel.y = Math.max(this.vel.y, 12);
    this.sideDash(true);
    this.chestPos(_v);
    _w.set(this.pos.x, this.pos.y + 0.3, this.pos.z);
    G.fx.ring(_w, '#ffffff', 1.5, 9, 0.35, { axis: 'y', a0: 0.95 });
    G.fx.ring(_w, '#e8f4ff', 1, 6, 0.28, { axis: 'y', a0: 0.7, delay: 0.05 });
    G.fx.ring(_v, '#ffffff', 1, 5, 0.25, { a0: 0.8 });
    for (let i = 0; i < 10; i++) {
      const an = (i / 10) * Math.PI * 2;
      _d.set(Math.cos(an), 0, Math.sin(an));
      _v.set(this.pos.x + _d.x * 1.2, this.pos.y + rand(0.4, 3), this.pos.z + _d.z * 1.2);
      G.fx.str.add(_v, _d.multiplyScalar(26), '#ffffff', 0.3, 0.1, 2.2, { drag: 5 });
    }
    G.fx.dust(_w, 12, 3, '#f4f4f4');
    G.sound('dash', this.pos, 0.8); G.sound('tp', this.pos, 0.35);
    if (this.isPlayer) G.hud.pop(this.headPos(_v), 'EVASIVE', '#ffffff', 1.1);
  }
  // Всплеск против толпы: +10 HP и полная шкала уклонения
  doBurst() {
    this.burst = 0; this.burstCd = BURST_CD;
    this.hp = Math.min(this.maxHp, this.hp + 10);
    this.evasive = 100;
    this.chestPos(_v);
    G.fx.burst(_v, '#ffffff', 12, 0.25);
    G.fx.ring(_v, '#ffffff', 1, 10, 0.4, { a0: 1 });
    G.fx.particles(_v, { n: 20, color: ['#ffffff', '#dff3ff'], speed: 16, size: 0.9, life: 0.5 });
    G.sound('tp', this.pos, 0.6);
    if (this.isPlayer) G.hud.pop(this.headPos(_v), 'BURST +10', '#ffffff', 1.2);
  }
  addEvasive(v) { if (v > 0) this.evasive = Math.min(100, this.evasive + v); }
  noteAttacker(att) {
    const now = G.time, log = this.atkLog;
    log.push(att, now);
    while (log.length > 12 || (log.length && now - log[1] > 1.75)) log.splice(0, 2);
    let distinct = 0;
    for (let i = 0; i < log.length; i += 2) { let seen = false; for (let j = 0; j < i; j += 2) if (log[j] === log[i]) seen = true; if (!seen) distinct++; }
    if (this.burst > 0 || (distinct >= 2 && this.burstCd <= 0)) this.burst = 1.75;
  }

  // ---------- навыки ----------
  skillDef(i) {
    let sk;
    if (this.awakened > 0 && this.ch.awakenSkills && this.ch.awakenSkills[i]) sk = this.ch.awakenSkills[i];
    else if (this.rikaMode === 2 && this.awakened <= 0 && this.ch.rikaSkills) sk = this.ch.rikaSkills[i] || null;
    else sk = this.ch.skills[i];
    // варианты по состоянию (Heian: число заклинаний меняет приём слота 1)
    return sk && sk.pick ? sk.pick(this) : sk;
  }
  specialDef() { return this.awakened > 0 && this.ch.awakenSpecial ? this.ch.awakenSpecial : this.ch.special || null; }
  clearM1Recovery() {
    const a = this.action;
    if (a && ((a.name === 'm1' && a.t >= a.hitAt && !a.locked) || a.name === 'land' || a.name === 'emote' || a.name === 'fdashJab' && a.t > 0.15)) this.action = null;
  }
  skill(i) {
    if (this.dead) return false;
    const a = this.action;
    // повторное нажатие во время навыка (Чёрная вспышка и т.п.)
    if (a && a.slot === i && a.onRepress && a.cdArr === this.cd) { a.onRepress(this, a); return true; }
    const sk = this.skillDef(i);
    if (!sk || this.cd[i] > 0 || this.blocking) return false;
    if (sk.instant) {
      // мгновенные (Rika Launch и т.п.) работают и посреди своего приёма
      if (this.rag || this.down > 0 || this.stun > 0) return false;
      if (a && a.name === 'emote') this.action = null;
    } else {
      this.clearM1Recovery();
      if (!this.canAct()) { if (this.isPlayer) this.skillBuf = { i, t: 0.35 }; return false; }
    }
    this.prot = 0;
    const cdArr = this.cd, cdMaxArr = this.cdMax, before = this.action;
    const res = sk.cast(this);
    if (res === false) {
      if (this.isPlayer && sk.tip === 'TARGET') G.hud.pop(this.headPos(_v), 'НЕТ ЦЕЛИ', '#c8c8c8', 0.9);
      return false;
    }
    const na = this.action;
    if (na && na !== before && na.slot == null) { na.slot = i; na.cdArr = cdArr; if (na.windup == null) na.windup = sk.windup ?? 0.25; }
    const c = (typeof res === 'number' ? res : sk.cd) * this.cdMult();
    if (sk.shared) { for (let j = 0; j < 4; j++) { cdArr[j] = Math.max(cdArr[j], c); cdMaxArr[j] = c; } }
    else cdArr[i] = cdMaxArr[i] = c;
    return true;
  }
  special() {
    if (this.dead) return false;
    const sk = this.specialDef();
    if (!sk || this.specCd > 0 || this.blocking) return false;
    if (sk.instant) { if (this.rag || this.down > 0 || this.stun > 0) return false; }
    else { this.clearM1Recovery(); if (!this.canAct()) return false; }
    this.prot = 0;
    if (sk.cast(this) === false) {
      if (this.isPlayer && sk.tip === 'TARGET') G.hud.pop(this.headPos(_v), 'НЕТ ЦЕЛИ', '#c8c8c8', 0.9);
      return false;
    }
    this.specCd = this.specCdMax = sk.cd;
    return true;
  }
  release(i) { if (this.action && this.action.slot === i) this.action.released = true; }
  // Трата % пробуждения (Limitless 6 %, финт 3 %): до пробуждения — со шкалы, во время — с оставшегося времени
  awakenPct() { return this.awakened > 0 ? (this.awakened / AW_DUR) * 100 : this.meter; }
  spendAwaken(pct) {
    if (this.awakened > 0) { this.awakened = Math.max(0.1, this.awakened - (pct / 100) * AW_DUR); return true; }
    if (this.meter < pct) return false;
    this.meter -= pct;
    return true;
  }

  // ---------- пробуждение ----------
  awaken() {
    if (this.dead || this.meter < 100 || this.awakened > 0) return false;
    this.clearM1Recovery();
    if (!this.canAct()) return false;
    const aw = this.ch.awaken;
    this.meter = 0;
    this.awakened = AW_DUR;
    this.hp = Math.min(this.maxHp, this.hp + aw.heal);
    this.cdAw.fill(0);
    this.cd = this.cdAw; this.cdMax = this.cdMaxAw;
    this.prot = 0;
    const cine = aw.cine || 3.2;
    this.vel.x = this.vel.z = 0;
    this.startAction({ name: 'awaken', dur: cine, armor: true, iframes: cine + 0.15, frames: aw.frames, events: (aw.events || []).map((e) => [e[0], e[1]]), noFeint: true });
    aw.start?.(this);
    G.onAwaken(this);
    return true;
  }
  setAwakenLook(on) {
    const m = this.model;
    if (m.blind) { m.blind.visible = !on; m.eyes.visible = on; }
    if (m.tattoo) m.tattoo.visible = on;
    if (m.steel) m.steel.visible = on;
    if (m.arm2L) { m.arm2L.visible = m.arm2R.visible = on; }
    if (!on) m.root.scale.setScalar(1);
  }
  endAwaken() {
    this.awakened = 0;
    this.chant = 0;
    this.cd = this.cdBase; this.cdMax = this.cdMaxBase;
    if (this.rikaMode === 2) this.rikaMode = 1;
    this.setAwakenLook(false);
    this.ch.awaken.end?.(this);
  }

  // ---------- урон ----------
  launch(vx, vy, vz, t, trueRag = false) {
    this.interrupt(true);
    this.blocking = false;
    this.rag = true; this.ragT = t; this.ragTrue = trueRag; this.down = 0; this.stun = 0; this.suspend = 0;
    this.vel.set(vx, vy, vz);
    this.onGround = false;
    this.pos.y += 0.2;
    this.diLeft = DI_MAX;
    // кувырок назад относительно направления полёта
    const lx = Math.sin(this.yaw), lz = Math.cos(this.yaw);
    const back = -(vx * lx + vz * lz);
    this.ragW.set(back >= 0 ? -rand(7, 11) : rand(7, 11), 0, rand(-4, 4));
    this.ragSpin.set(0, 0, 0);
  }
  die(killer) {
    this.dead = true;
    this.deaths++;
    this.respawnT = 4;
    if (this.awakened > 0) this.endAwaken();
    this.action = null; this.blocking = false; this.rag = false;
    this.counter = 0; this.burst = 0; this.charge = null; this.vanish = 0;
    this.ch.reset?.(this); this.rikaMode = 0; this.cd = this.cdBase; this.cdMax = this.cdMaxBase;
    setModelFade(this.model, 1);
    if (this.burstOrb) { G.fx.release(this.burstOrb); this.burstOrb = null; }
    this.model.root.updateMatrixWorld(true);
    // роблокс-стиль: тело разваливается на части
    const away = _d.set(this.pos.x - (killer ? killer.pos.x : this.pos.x), 0, this.pos.z - (killer ? killer.pos.z : this.pos.z));
    if (away.lengthSq() < 0.01) away.set(rand(-1, 1), 0, rand(-1, 1));
    away.normalize();
    for (const me of this.model.meshes) {
      if (!me.visible || !me.parent.visible) continue;
      const g = new THREE.Mesh(me.geometry, me.material);
      me.matrixWorld.decompose(g.position, g.quaternion, g.scale);
      g.castShadow = true;
      G.scene.add(g);
      G.gibs.push({ m: g, v: new THREE.Vector3(away.x * rand(8, 22) + rand(-6, 6), rand(8, 20), away.z * rand(8, 22) + rand(-6, 6)), w: new THREE.Vector3(rand(-8, 8), rand(-8, 8), rand(-8, 8)), t: 2.8 });
    }
    this.model.root.visible = false;
    this.chestPos(_v);
    G.fx.burst(_v, '#ffffff', 9, 0.25);
    G.fx.particles(_v, { n: 24, color: ['#ffffff', this.look.color], speed: 18, size: 1.1, life: 0.6 });
    G.sound('death', this.pos, 0.8);
  }

  // ---------- кадр ----------
  update(dt) {
    if (this.dead) return;
    if (this.input.jump) this.jumpBuf = 0.22;
    for (let i = 0; i < 4; i++) {
      if (this.cdBase[i] > 0) this.cdBase[i] = Math.max(0, this.cdBase[i] - dt);
      if (this.cdAw[i] > 0) this.cdAw[i] = Math.max(0, this.cdAw[i] - dt);
      if (this.cdRk[i] > 0) this.cdRk[i] = Math.max(0, this.cdRk[i] - dt);
    }
    if (this.vanish > 0) this.vanish -= dt;
    // катана — обратно в ножны после 8 с без M1 и приёмов мечом
    if (this.model.katDrawn && !this.action && !this.blocking && G.time - this.katT > 8) {
      setKatana(this.model, false); this.updateIdle();
      G.sound('block', this.pos, 0.2);
    }
    // эмоцию отменяют прыжок, блок и движение
    const ea = this.action;
    if (ea && ea.name === 'emote' && (this.input.jump || this.input.block || this.input.mx * this.input.mx + this.input.mz * this.input.mz > 0.04)) this.action = null;
    if (this.specCd > 0) this.specCd = Math.max(0, this.specCd - dt);
    if (this.fdashCd > 0) this.fdashCd -= dt;
    if (this.sdashCd > 0) this.sdashCd -= dt;
    if (this.m1Cd > 0) this.m1Cd -= dt;
    if (this.m1Buf > 0) this.m1Buf -= dt;
    if (this.comboT > 0) this.comboT -= dt;
    if (this.prot > 0) this.prot -= dt;
    if (this.iframes > 0) this.iframes -= dt;
    if (this.counter > 0) this.counter -= dt;
    if (this.hitFlash > 0) this.hitFlash -= dt;
    if (this.whiteT > 0) this.whiteT -= dt;
    if (this.broken > 0) this.broken -= dt;
    if (this.wakeT > 0) this.wakeT -= dt;
    if (this.blockAbsorb > 0) this.blockAbsorb -= dt;
    if (this.burstCd > 0) this.burstCd -= dt;
    if (this.bfChainT > 0) { this.bfChainT -= dt; if (this.bfChainT <= 0) this.bfChain = 0; }
    if (this.jumpBuf > 0) this.jumpBuf -= dt;
    if (this.burst > 0) {
      this.burst -= dt;
      if (!this.burstOrb) { this.burstOrb = G.fx.pool('glow'); this.burstOrb.mat.color.set('#ffffff'); }
      this.fwd(_w); this.chestPos(_v).addScaledVector(_w, 0.75);
      this.burstOrb.obj.position.copy(_v); this.burstOrb.obj.scale.setScalar(2.2 + Math.sin(G.time * 12) * 0.3);
    } else if (this.burstOrb) { G.fx.release(this.burstOrb); this.burstOrb = null; }
    if (this.awakened > 0) {
      if (!(this.action && this.action.name === 'awaken')) this.awakened -= dt;
      if (this.ch.awaken.tick) this.ch.awaken.tick(this, dt);
      if (this.awakened <= 0) this.endAwaken();
    }
    // реген JJS: 1 HP/с через 1 с после последнего урона
    if (G.time - this.lastDamagedT > 1 && this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + dt);
    // шкала уклонения медленно копится вне боя
    if (this.evasive < 100 && G.time - Math.max(this.lastDamagedT, this.lastDealtT) > 5) this.evasive = Math.min(100, this.evasive + 2 * dt);

    if (this.skillBuf) {
      const sb = this.skillBuf;
      sb.t -= dt;
      if (sb.t <= 0) this.skillBuf = null;
      else if (this.canAct()) { this.skillBuf = null; this.skill(sb.i); }
    }
    if (this.hitstop > 0) { this.hitstop -= dt; this.syncModel(dt); return; }

    let ctrl = false;
    if (this.rag) this.updateRag(dt);
    else if (this.down > 0) {
      this.down -= dt; this.friction(dt, 8);
      if (this.down <= 0) { this.wakeT = 0.5; this.iframes = Math.max(this.iframes, 0.2); this.stun = 0; }
    } else if (this.stun > 0) {
      this.stun -= dt; this.blocking = false; this.friction(dt, 9);
    } else if (this.action) this.updateAction(dt);
    else ctrl = true;

    if (ctrl) this.locomotion(dt);
    // прыжок: ни оглушение, ни M1 не «выключают» кнопку — нажатие буферизуется
    if (this.jumpBuf > 0 && this.onGround && !this.blocking && !this.rag && this.down <= 0 && this.stun <= 0 && (!this.action || this.action.allowJump || this.action.name === 'land')) {
      if (this.action && this.action.name === 'land') this.action = null;
      this.jumpBuf = 0;
      this.vel.y = JUMP_V; this.onGround = false;
      G.sound('jump', this.pos, 0.3);
    }
    this.physics(dt);
    this.animate(dt);
    this.syncModel(dt);
  }

  locomotion(dt) {
    const inp = this.input;
    this.blocking = inp.block;
    const m = inp.mx * inp.mx + inp.mz * inp.mz;
    // Auto Run: джойстик почти до упора → бег (плавный разгон), в блоке/воздухе — не разгоняемся
    const wantRun = m > 0.81 && !this.blocking ? 1 : 0;
    this.runK += (wantRun - this.runK) * (1 - Math.exp(-(wantRun ? 5 : 9) * dt));
    const base = this.walkSpeed() + (RUN - WALK) * (this.mods().speed || 1) * this.runK;
    // блок и «критическое» HP замедляют (×0.9 при почти нулевом HP)
    let sp = base * (this.blocking ? (this.blockAbsorb > 0 ? 0.14 : 0.32) : 1) * (0.9 + 0.1 * clamp(this.hp / this.maxHp * 2, 0, 1));
    // Shift-lock: персонаж смотрит по камере; назад — ×0.8 скорости
    if (this.lockYaw != null && !this.blocking) this.yaw = angleDamp(this.yaw, this.lockYaw, 30, dt);
    if (m > 0.01) { const dot = (inp.mx * Math.sin(this.yaw) + inp.mz * Math.cos(this.yaw)) / Math.sqrt(m); if (dot < 0) sp *= 1 + 0.2 * dot; }
    const k = 1 - Math.exp(-(this.onGround ? 14 : 5) * dt);
    this.vel.x += (inp.mx * sp - this.vel.x) * k;
    this.vel.z += (inp.mz * sp - this.vel.z) * k;
    if (this.lockYaw != null && !this.blocking) return;
    if (m > 0.01 && !this.blocking) this.yaw = angleDamp(this.yaw, Math.atan2(inp.mx, inp.mz), 13, dt);
    else if (this.blocking && this.lastHitBy && G.time - this.lastHitT < 1) this.faceTo(this.lastHitBy.pos);
    else if (this.blocking && this.lockYaw != null) this.yaw = angleDamp(this.yaw, this.lockYaw, 10, dt);
  }

  physics(dt) {
    const a = this.action;
    const vy0 = this.vel.y;
    if (this.suspend > 0) {
      // подвешен в воздухе (Lapse Blue, Twofold Kick)
      this.suspend -= dt;
      this.vel.multiplyScalar(Math.exp(-9 * dt));
    } else if (!(a && a.noGrav)) this.vel.y -= GRAV * dt;
    // по вертикали — средняя скорость за шаг: точная парабола при любом FPS (вершина прыжка ≈4.1 стада)
    this.pos.x += this.vel.x * dt; this.pos.z += this.vel.z * dt;
    this.pos.y += (vy0 + this.vel.y) * 0.5 * dt;
    const gy = G.world.groundAt(this.pos.x, this.pos.z, this.pos.y);
    if (this.pos.y <= gy) {
      if (!this.onGround && this.vel.y < -43) {
        G.fx.dust(_v.copy(this.pos), this.rag ? 10 : 4, this.rag ? 3 : 2);
        if (this.rag) { G.sound('thump', this.pos, 0.6); }
      }
      if (this.rag && this.vel.y < -37) { this.vel.y = -this.vel.y * 0.3; this.pos.y = gy + 0.01; this.onGround = false; }
      else { this.pos.y = gy; if (this.vel.y < 0) this.vel.y = 0; this.onGround = true; }
    } else if (this.pos.y > gy + 0.08) this.onGround = false;
    const sp2 = this.vel.x * this.vel.x + this.vel.z * this.vel.z;
    if (G.world.collide(this.pos, 1.2, 5) && this.rag && sp2 > 500) {
      // удар об стену
      this.chestPos(_v);
      G.fx.debris(_v, 6, ['#9a9ea6', '#c96a4a', '#7d7468']);
      G.fx.dust(_v, 8, 3);
      G.fx.ring(_v, '#ffffff', 1, 6, 0.3, { a0: 0.7 });
      G.shake(0.3, this.pos);
      G.sound('heavy', this.pos, 0.6);
      this.vel.x *= -0.25; this.vel.z *= -0.25;
    }
  }

  updateRag(dt) {
    // обычный рэгдолл: таймер идёт только после касания земли; «истинный» — сразу
    if (this.ragTrue || this.onGround) this.ragT -= dt;
    // направленное влияние: удерживая направление в полёте, смещаешь траекторию (до ±5 стадов)
    if (!this.onGround && this.diLeft > 0 && this.suspend <= 0) {
      const mx = this.input.mx, mz = this.input.mz, l = Math.hypot(mx, mz);
      if (l > 0.25) {
        const st = Math.min(this.diLeft, 9 * dt);
        this.pos.x += (mx / l) * st; this.pos.z += (mz / l) * st;
        this.diLeft -= st;
      }
    }
    if (this.onGround) {
      this.friction(dt, 5);
      this.ragW.multiplyScalar(Math.exp(-7 * dt));
    }
    this.ragSpin.addScaledVector(this.ragW, dt);
    const sp = Math.hypot(this.vel.x, this.vel.z);
    if (sp > 28 && Math.random() < 0.5) {
      this.chestPos(_v);
      G.fx.particles(_v, { n: 1, normal: true, color: '#e8e4dc', speed: 1, size: 1.4, size1: 3, life: 0.4, alpha: 0.4 });
    }
    if (this.ragT <= 0 && this.onGround) {
      this.rag = false; this.ragTrue = false;
      this.down = 0.38;
      this.pose[K.lean] = wrapAngle(this.pose[K.lean] + this.ragSpin.x);
      this.pose[K.roll] = wrapAngle(this.pose[K.roll] + this.ragSpin.z);
      this.ragSpin.set(0, 0, 0);
    }
  }

  animate(dt) {
    const tp = this.tp;
    let speed = 16;
    const t = G.time;
    const katana = this.model.katDrawn;
    if (this.rag) {
      tp.set(POSE.air);
      tp[K.lax] = -1.6 + Math.sin(t * 17) * 0.9; tp[K.laz] = 1.0 + Math.sin(t * 13) * 0.4;
      tp[K.rax] = -1.6 + Math.cos(t * 15) * 0.9; tp[K.raz] = -1.0 - Math.sin(t * 11) * 0.4;
      tp[K.llx] = Math.sin(t * 14) * 0.7; tp[K.rlx] = -Math.sin(t * 14) * 0.7;
      speed = 12;
    } else if (this.down > 0) { tp.set(POSE.down); speed = 12; }
    else if (this.stun > 0) {
      tp.set(this.broken > 0 ? POSE.dazed : this.hitVariant ? POSE.stun2 : POSE.stun1);
      if (this.broken > 0) { tp[K.cz] = Math.sin(t * 5) * 0.12; tp[K.hyaw] = Math.sin(t * 3) * 0.3; }
      speed = 24;
    } else if (this.action) {
      const a = this.action;
      if (a.frames) kf(a.frames, clamp(a.t / a.dur, 0, 1), tp);
      else if (a.pose) a.pose(this, a, tp);
      else tp.set(this.idlePose);
      speed = a.poseSpeed ?? 22;
    } else if (this.blocking) {
      if (this.charId === 'gojo') {
        // «Бесконечность»: парит и слегка покачивается
        tp.set(POSE.inf);
        tp[K.hy] += Math.sin(t * 2.2) * 0.08; tp[K.roll] = Math.sin(t * 1.3) * 0.04; tp[K.laz] += Math.sin(t * 1.7) * 0.06;
        speed = 10;
      } else { tp.set(katana ? POSE.blockK : POSE.block); speed = 24; }
    }
    else if (!this.onGround) { tp.set(POSE.air); tp[K.llx] = this.vel.y > 0 ? -0.8 : -0.3; speed = 10; }
    else {
      const hs = Math.hypot(this.vel.x, this.vel.z);
      if (hs > 1.5) {
        this.runPhase += dt * hs * 0.62;
        const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
        runPose(tp, this.idlePose, this.runPhase, clamp(hs / 17, 0, 1.25), katana, (this.vel.z * fx - this.vel.x * fz) / hs, (this.vel.x * fx + this.vel.z * fz) / hs);
        speed = 14;
      } else {
        tp.set(this.idlePose);
        const b = Math.sin(t * 2.3 + this.pos.x);
        tp[K.hy] += b * 0.035; tp[K.rax] += b * 0.05; tp[K.lax] -= b * 0.05; tp[K.cx] += b * 0.02;
        speed = 10;
      }
    }
    blendInto(this.pose, tp, 1 - Math.exp(-speed * dt));
  }

  syncModel() {
    const m = this.model;
    const vis = !(this.vanish > 0);
    if (m.root.visible !== vis) m.root.visible = vis;
    m.root.position.copy(this.pos);
    if (this.hitstop > 0 && this.stun > 0) { m.root.position.x += rand(-0.12, 0.12); m.root.position.z += rand(-0.12, 0.12); }
    m.root.rotation.y = this.yaw;
    applyPose(m, this.pose, this.rag ? this.ragSpin : null);
    // подсветка
    const e = m.bodyMat.emissive, eh = m.headMat.emissive;
    if (this.whiteT > 0) { const k = 0.75 + Math.sin(G.time * 60) * 0.15; e.setRGB(k, k, k); }
    else if (this.hitFlash > 0) { const k = this.hitFlash / 0.12 * 0.55; e.setRGB(k, k, k); }
    else if (this.burst > 0) { const k = 0.3 + Math.sin(G.time * 14) * 0.12; e.setRGB(k, k, k); }
    else if (this.prot > 0) { const k = 0.25 + Math.sin(G.time * 18) * 0.15; e.setRGB(k * 0.6, k * 0.8, k); }
    else if (this.awakened > 0) { e.set(this.ch.awaken.rim || this.look.color).multiplyScalar(0.06 + Math.sin(G.time * 6) * 0.025); }
    else if (this.counter > 0) { e.setRGB(0.35, 0.25, 0.05); }
    else e.setRGB(0, 0, 0);
    eh.copy(e);
  }
}

// ---------- Разрешение удара ----------
// o: dmg, melee, m1, bullet, stun, rag, kb{f,up}, push, unblockable, block360, chip (доля урона сквозь блок), chipKill,
//    bypassRag (бьёт лежачих), trueRag (без уклонения), downslam, noCounter, pierce, ignoreIframes, from, fx/sfx/…
export function hit(att, vic, o) {
  if (!vic || vic.dead || vic === att || G.isAlly(att, vic) || G.matchOver) return null;
  if (vic.prot > 0) return null;
  if (vic.iframes > 0 && !o.ignoreIframes) return null;
  // M1 и большинство ближних ударов проходят мимо лежачих (рэгдолл / подъём); только «BR»-удары их достают
  if ((vic.rag || vic.down > 0) && !(o.bypassRag ?? !o.melee)) return null;
  _d.set(vic.pos.x - (o.from ? o.from.x : att.pos.x), 0, vic.pos.z - (o.from ? o.from.z : att.pos.z));
  if (_d.lengthSq() < 0.001) _d.set(Math.sin(att.yaw), 0, Math.cos(att.yaw));
  _d.normalize();
  const dir = _d;
  vic.chestPos(_hp).addScaledVector(dir, -0.9);
  const contact = _hp;
  // контрудар (Manji Kick): только ближний бой и «пули»
  if (vic.counter > 0 && !o.noCounter && (o.melee || o.bullet) && vic.ch.onCounter && !vic.rag) {
    vic.counter = 0;
    vic.ch.onCounter(vic, att, o.bullet && !o.melee);
    return 'counter';
  }
  let dmg = o.dmg * att.dmgMult();
  const vf = Math.sin(vic.yaw) * -dir.x + Math.cos(vic.yaw) * -dir.z;
  let broke = false;
  if (vic.blocking) {
    const blockable = !o.unblockable && !o.guardBreak && !o.downslam;
    if (blockable && (o.block360 || vf > 0.05)) {
      // блок полностью гасит урон и оглушение (кроме ударов с «пробивом» chip)
      let cd = o.chip ? dmg * o.chip : 0;
      if (cd > 0 && !o.chipKill) cd = Math.min(cd, Math.max(0, vic.hp - 1));
      if (cd > 0) { vic.hp -= cd; vic.lastDamagedT = G.time; att.lastDealtT = G.time; if (att.awakened <= 0) att.meter = Math.min(100, att.meter + cd * AW_FILL); }
      vic.blockAbsorb = 0.45;
      if (!o.noPush) vic.vel.addScaledVector(dir, o.melee ? 5 : 9);
      if (!o.noStop) { vic.hitstop = Math.max(vic.hitstop, 0.04); if (o.melee) att.hitstop = Math.max(att.hitstop, 0.04); }
      if (o.fx === 'none') { if (Math.random() < 0.35) G.fx.sparks(contact, _w.copy(dir).negate(), '#fff2c8', 2, 26); }
      else if (vic.charId === 'gojo') {
        G.fx.ring(contact, '#cfeeff', 0.4, 2.8, 0.3, { a0: 0.9 });
        G.fx.particles(contact, { n: 6, color: ['#bfe6ff', '#ffffff'], speed: 5, size: 0.6, life: 0.3 });
      } else {
        G.fx.sparks(contact, _w.copy(dir).negate(), '#fff2c8', 7, 32);
        G.fx.burst(contact, '#ffe9b0', 3.5, 0.12);
      }
      if (cd > 0 && att.isPlayer) G.hud.dmg(cd);
      if (o.sfx !== 'none') G.sound('block', vic.pos, o.fx === 'none' ? 0.25 : 0.6);
      o.onBlocked?.(att, vic);
      G.onHit?.(att, vic, 'blocked', o, cd);
      if (cd > 0 && vic.hp <= 0) G.kill(vic, att);
      return 'blocked';
    }
    // пробой блока: неблокируемые, удары сбоку/сзади и удары вниз; атакующий переходит на 2-й удар M1
    broke = true;
    vic.blocking = false;
    att.combo = 1; att.comboT = M1_RESET;
    G.fx.ring(contact, '#ffffff', 1, 6, 0.3, { a0: 1 });
    if (att.isPlayer || vic.isPlayer) G.hud.pop(vic.headPos(_v), 'BLOCK BREAK', '#ffffff', 1.1);
    G.sound('block', vic.pos, 0.8);
  }
  // попадание
  vic.hp -= dmg;
  att.dmgDealt += dmg;
  att.lastDealtT = G.time;
  vic.lastHitBy = att; vic.lastHitT = G.time; vic.lastDamagedT = G.time;
  // шкала уклонения: от полученного (77 / 62.5) и нанесённого (200 / 100) урона
  vic.addEvasive(dmg * 100 / (vic.hp > 50 ? 77 : 62.5));
  att.addEvasive(dmg * 100 / (att.hp > 50 ? 200 : 100));
  if (o.downslam && vic.rag) vic.addEvasive(20);
  else if (vic.wakeT > 0) vic.addEvasive(20);
  if (att.awakened <= 0) att.meter = Math.min(100, att.meter + dmg * AW_FILL);
  vic.noteAttacker(att);
  const armor = vic.action && vic.action.armor;
  const stunImm = vic.wakeT > 0 && o.melee && !o.rag;
  // noInterrupt: только урон (разрезы Гробницы не сбивают действия и не оглушают)
  if (!armor && !o.noInterrupt) {
    vic.blocking = false;
    if (o.rag && !vic.rag) {
      vic.launch(dir.x * o.kb.f, (o.kb.up || 0) * VYK, dir.z * o.kb.f, o.rag, !!o.trueRag);
      vic.yaw = Math.atan2(-dir.x, -dir.z);
    } else if (vic.rag) {
      if (o.downslam) { vic.vel.set(dir.x * 4, -62 * VYK, dir.z * 4); vic.ragT = Math.max(vic.ragT, 1.0); vic.onGround = false; }
      else if (o.kb) { vic.vel.x += dir.x * o.kb.f * 0.5; vic.vel.z += dir.z * o.kb.f * 0.5; vic.vel.y = Math.max(vic.vel.y, (o.kb.up || 0) * 0.6 * VYK); if (o.rag) vic.ragT = Math.max(vic.ragT, o.rag * 0.6); }
      if (o.trueRag) vic.ragTrue = true;
    } else if (!stunImm) {
      vic.interrupt();
      if (vic.down > 0) vic.down = 0;
      if (o.stun) vic.stun = Math.max(vic.stun, o.stun);
      else if (broke) vic.stun = Math.max(vic.stun, M1_STUN);
      if (broke) vic.broken = Math.max(vic.broken, 0.6);
      if (o.kb) { vic.vel.x = dir.x * o.kb.f; vic.vel.z = dir.z * o.kb.f; if (o.kb.up) { vic.vel.y = o.kb.up * VYK; vic.onGround = false; } }
      else if (o.push) { vic.vel.x = dir.x * o.push; vic.vel.z = dir.z * o.push; }
      if (vic.down <= 0) vic.yaw = Math.atan2(-dir.x, -dir.z);
    }
  }
  vic.hitFlash = 0.12; vic.hitVariant ^= 1;
  const hs = o.hitstop ?? 0.05;
  if (!o.noStop) {
    vic.hitstop = Math.max(vic.hitstop, hs);
    if (o.melee) att.hitstop = Math.max(att.hitstop, hs);
  }
  // эффекты
  const col = o.color || '#ffffff';
  const fxType = o.fx || 'hit';
  if (fxType === 'hit') {
    G.fx.burst(contact, col, 4.2, 0.13);
    G.fx.sparks(contact, dir, '#fff6d8', 6, 34);
  } else if (fxType === 'heavy') {
    G.fx.burst(contact, col, 7.5, 0.18);
    G.fx.ring(contact, col, 0.6, 5.5, 0.25, { a0: 0.9 });
    G.fx.sparks(contact, dir, '#fff2c0', 12, 48);
    G.fx.particles(contact, { n: 8, color: '#ffffff', speed: 14, size: 0.7, life: 0.3 });
  } else if (fxType === 'slash') {
    _q.setFromUnitVectors(_v.set(0, 0, 1), dir);
    _q.multiply(new THREE.Quaternion().setFromAxisAngle(_v.set(0, 0, 1), rand(-1.2, 1.2) + Math.PI / 2));
    G.fx.crescent(contact, _q, col === '#ffffff' ? '#ff6070' : col, 1.8, 4.2, 0.2, { a0: 1 });
    G.fx.sparks(contact, dir, '#ffd0d0', 8, 40);
    G.fx.burst(contact, '#ffffff', 3.5, 0.12);
  } else if (fxType === 'fire') {
    G.fx.burst(contact, '#ffb040', 6, 0.2);
    G.fx.particles(contact, { n: 12, color: ['#ff7a1a', '#ffd040', '#ff3a10'], speed: 10, up: 6, size: 1.2, life: 0.5 });
  } else if (fxType === 'energy') {
    G.fx.burst(contact, col, 6, 0.18);
    G.fx.ring(contact, col, 0.5, 4, 0.25, { a0: 0.9 });
    G.fx.sparks(contact, dir, col, 8, 36);
  }
  if (o.sfx !== 'none') G.sound(o.sfx || 'hit', vic.pos, o.vol ?? 0.7);
  if (att.isPlayer || vic.isPlayer) G.shake(o.shake ?? 0.2, vic.pos);
  // счётчик урона JJS («N DMG») вместо цифр над головой
  if (att.isPlayer && dmg > 0) G.hud.dmg(dmg);
  if (vic.isPlayer) G.hud.hurt(dmg);
  G.onHit?.(att, vic, broke ? 'break' : 'hit', o, dmg);
  if (vic.hp <= 0) G.kill(vic, att);
  return broke ? 'break' : 'hit';
}

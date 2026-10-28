// Боец: состояние, физика, M1-комбо, блок, рывок, урон/отбрасывание, смерть.
import * as THREE from 'three';
import { G } from './ctx.js';
import { buildModel, LOOKS } from './rig.js';
import { NK, K, kf, blendInto, applyPose, POSE, M1ANIM, runPose, PX } from './anim.js';
import { clamp, rand, angleDamp, wrapAngle } from './util.js';
import { CHARS } from './skills.js';

export const GRAV = 82;
const _d = new THREE.Vector3(), _v = new THREE.Vector3(), _w = new THREE.Vector3(), _hp = new THREE.Vector3();
const _q = new THREE.Quaternion(), _m4 = new THREE.Matrix4();

export class Fighter {
  constructor({ name, isPlayer = false, isClaude = false, bot = null, skin, charId, color = '#fff' }) {
    this.name = name; this.isPlayer = isPlayer; this.isClaude = isClaude; this.bot = bot;
    this.skin = skin; this.color = color;
    this.pos = new THREE.Vector3(); this.vel = new THREE.Vector3();
    this.yaw = 0; this.onGround = true;
    this.maxHp = 100; this.hp = 100;
    this.meter = 0; this.awakened = 0;
    this.dead = true; this.respawnT = 0;
    this.kills = 0; this.deaths = 0; this.dmgDealt = 0;
    this.cd = [0, 0, 0, 0]; this.cdMax = [1, 1, 1, 1];
    this.dashCd = 0; this.m1Cd = 0; this.m1Buf = 0;
    this.combo = 0; this.comboT = 0;
    this.stun = 0; this.broken = 0; this.rag = false; this.ragT = 0; this.down = 0;
    this.iframes = 0; this.prot = 0; this.hitstop = 0; this.hitFlash = 0; this.hitVariant = 0;
    this.blocking = false; this.guard = 100; this.guardDelay = 0;
    this.infinity = 0; this.counter = 0;
    this.action = null;
    this.input = { mx: 0, mz: 0, jump: false, jumpHeld: false, block: false };
    this.aim = new THREE.Vector3(0, 0, 1);
    this.lastHitBy = null; this.lastHitT = -99; this.lastDamagedT = -99;
    this.ragSpin = new THREE.Vector3(); this.ragW = new THREE.Vector3();
    this.runPhase = 0;
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
    this.charId = id;
    this.ch = CHARS[id];
    this.look = LOOKS[id];
    this.model = buildModel(id, this.skin.skin || '#f2c9a0');
    this.model.root.visible = !this.dead;
    G.scene.add(this.model.root);
    this.idlePose = POSE.idle[this.ch.stance];
    this.pose.set(this.idlePose);
    this.cd = [0, 0, 0, 0];
  }

  spawn(x, z) {
    const gy = G.world.groundAt(x, z, 50);
    this.pos.set(x, gy, z); this.vel.set(0, 0, 0);
    this.hp = this.maxHp; this.dead = false;
    this.stun = this.broken = this.down = this.iframes = this.hitstop = 0; this.rag = false;
    this.action = null; this.blocking = false; this.guard = 100; this.skillBuf = null;
    this.infinity = this.counter = 0; this.awakened = 0;
    this.combo = 0; this.comboT = 0; this.m1Buf = 0;
    this.prot = 2.0;
    this.lastHitBy = null; this.lastDamagedT = -99;
    this.cd = [0, 0, 0, 0]; this.dashCd = 0; this.m1Cd = 0;
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
  fwd(out) { return out.set(Math.sin(this.yaw), 0, Math.cos(this.yaw)); }
  chestPos(out) { return out.set(this.pos.x, this.pos.y + 3.1, this.pos.z); }
  headPos(out) { return out.set(this.pos.x, this.pos.y + 5.9, this.pos.z); }
  handPos(side, out) { (side === 'L' ? this.model.handL : this.model.handR).getWorldPosition(out); return out; }
  faceTo(p) { const dx = p.x - this.pos.x, dz = p.z - this.pos.z; if (dx * dx + dz * dz > 0.01) this.yaw = Math.atan2(dx, dz); }
  dist(o) { return Math.hypot(o.pos.x - this.pos.x, o.pos.z - this.pos.z); }
  isEnemy(o) { return o !== this && !o.dead && !G.isAlly(this, o); }
  canAct() { return !this.dead && !this.rag && this.down <= 0 && this.stun <= 0 && !this.action; }
  busy() { return this.dead || this.rag || this.down > 0 || this.stun > 0 || !!this.action; }
  mods() { return this.awakened > 0 ? this.ch.awaken.mods || {} : {}; }
  dmgMult() { return this.mods().dmg || 1; }
  cdMult() { return this.mods().cd || 1; }
  walkSpeed() { return 17 * (this.ch.speed || 1) * (this.mods().speed || 1); }

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
  // Враги в конусе перед собой
  meleeTargets(range, cosMin = 0.35) {
    const out = [];
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    for (const o of G.fighters) {
      if (!this.isEnemy(o)) continue;
      const dx = o.pos.x - this.pos.x, dz = o.pos.z - this.pos.z, dy = o.pos.y - this.pos.y;
      const d = Math.hypot(dx, dz);
      if (d > range + 1 || dy > 4.5 || dy < -4.5) continue;
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

  // ---------- M1 ----------
  m1() {
    if (this.dead) return;
    if (this.action && (this.action.name === 'm1' || this.action.name === 'dash')) { this.m1Buf = 0.35; return; }
    if (!this.canAct() || this.m1Cd > 0) return;
    this.prot = 0;
    if (!this.onGround && this.pos.y - G.world.groundAt(this.pos.x, this.pos.z, this.pos.y) > 2.2) { this.slam(); return; }
    if (this.comboT <= 0 || this.combo >= 4) this.combo = 0;
    const n = ++this.combo;
    const last = n === 4;
    const tgt = this.autoTarget(15, 0.3);
    if (tgt) this.faceTo(tgt.pos);
    const style = this.ch.m1;
    const frames = M1ANIM[style][n - 1];
    const dur = last ? 0.5 : 0.34, hitAt = dur * 0.42;
    const range = style === 'katana' ? 5.9 : 5.4;
    let lunge = 6;
    if (tgt) lunge = clamp((this.dist(tgt) - 3.0) / hitAt, 0, 42);
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    this.startAction({
      name: 'm1', kind: 'melee', dur, frames, hitAt, keepVel: true, poseSpeed: 30,
      events: [[hitAt, (f) => f.m1Hit(n, range)]],
      update: (f, dt, t) => {
        if (t < hitAt) { f.vel.x = fx * lunge; f.vel.z = fz * lunge; }
        else f.friction(dt, 14);
        if (!last && t > dur * 0.78 && f.m1Buf > 0) f.endAction();
      },
      onEnd: (f) => { if (f.m1Buf > 0 && f.combo < 4 && f.canAct()) { f.m1Buf = 0; f.m1(); } },
    });
    this.comboT = dur + 0.55;
    this.m1Buf = 0;
    if (last) this.m1Cd = dur + 0.45;
    G.sound(style === 'katana' ? 'slash' : 'swing', this.pos, 0.45);
    // взмах катаной / след кулака
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
        G.fx.crescent(_v, _q, '#e8f0ff', 2.5, 4.2, 0.18, { a0: 0.9 });
        return false;
      });
    }
  }
  m1Hit(n, range) {
    const last = n === 4;
    const hits = this.meleeTargets(range, 0.35);
    const up = last && this.input.jumpHeld;
    const katana = this.ch.m1 === 'katana';
    for (const o of hits) {
      if (last) {
        if (this.ch.blackFlashM1 && (this.awakened > 0 || Math.random() < this.ch.bfChance)) { this.ch.blackFlash(this, o, true); continue; }
        G.hit(this, o, {
          dmg: 5.5, melee: true, rag: up ? 1.1 : 0.9, kb: up ? { f: 5, up: 40 } : { f: 46, up: 15 },
          hitstop: 0.085, fx: katana ? 'slash' : 'heavy', shake: 0.45, sfx: 'heavy', guardDmg: 28,
        });
      } else {
        G.hit(this, o, { dmg: 3.5, melee: true, stun: 0.6, push: 2.5, hitstop: 0.055, fx: katana ? 'slash' : 'hit', shake: 0.18, sfx: 'hit', guardDmg: 15 });
      }
    }
  }
  slam() {
    const tgt = this.autoTarget(12, 0.2);
    if (tgt) this.faceTo(tgt.pos);
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    const hs = tgt ? clamp(this.dist(tgt) * 2.2, 0, 30) : 8;
    const up = PX(POSE.air, { rax: -2.9, raz: -0.2, lax: -2.9, laz: 0.2, cx: -0.2, hy: 0.2, llx: -0.8, rlx: -0.3 });
    const dn = PX(POSE.air, { rax: -0.6, raz: 0.3, lax: -0.6, laz: -0.3, cx: 0.5, hy: -0.2, llx: -0.9, rlx: 0.2 });
    this.startAction({
      name: 'slam', kind: 'melee', dur: 1.4, keepVel: true, poseSpeed: 22,
      pose: (f, a, out) => out.set(a.t < 0.14 ? up : dn),
      update: (f, dt, t, a) => {
        if (t < 0.14) { f.vel.y = 4; f.vel.x = fx * hs * 0.3; f.vel.z = fz * hs * 0.3; }
        else { f.vel.y = -75; f.vel.x = fx * hs; f.vel.z = fz * hs; }
        if (t > 0.14 && f.onGround) {
          f.endAction();
          f.slamImpact();
        }
      },
    });
    G.sound('swing', this.pos, 0.5);
  }
  slamImpact() {
    const p = _v.copy(this.pos); p.y += 0.3;
    for (const o of this.enemiesNear(_w.set(this.pos.x, this.pos.y + 2, this.pos.z), 6.5)) {
      G.hit(this, o, { dmg: 6, melee: true, rag: 0.8, kb: { f: 16, up: 24 }, hitstop: 0.08, fx: 'heavy', shake: 0.5, sfx: 'heavy', guardDmg: 45 });
    }
    G.fx.ring(p, '#ffffff', 1, 9, 0.35, { axis: 'y', a0: 0.9 });
    G.fx.crater(p, 5);
    G.fx.dust(p, 14, 3);
    G.fx.debris(p, 8);
    G.shake(0.35, this.pos);
    G.sound('heavy', this.pos, 0.7);
    this.vel.set(0, 0, 0);
    this.startAction({ name: 'land', dur: 0.28, pose: (f, a, out) => out.set(PX(f.idlePose, { hy: -0.6, cx: 0.4 })) });
  }

  // ---------- рывок ----------
  dash() {
    if (this.dead || this.dashCd > 0 || this.stun > 0 || this.rag || this.down > 0) return false;
    if (this.action && this.action.name !== 'm1' && this.action.name !== 'land') return false;
    this.action = null;
    let dx = this.input.mx, dz = this.input.mz;
    const l = Math.hypot(dx, dz);
    if (l < 0.2) { dx = Math.sin(this.yaw); dz = Math.cos(this.yaw); } else { dx /= l; dz /= l; }
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    const dot = dx * fx + dz * fz, cross = fx * dz - fz * dx;
    let pose;
    if (this.isPlayer || dot > 0.5) {
      // игрок (и боты при рывке вперёд) разворачиваются по направлению рывка
      const tgt = this.autoTarget(25, 0.75);
      if (dot > 0.3 || this.isPlayer) this.yaw = Math.atan2(dx, dz);
      pose = POSE.dashF;
      if (tgt && dot > 0.3 && this.dist(tgt) < 25) this.faceTo(tgt.pos);
    } else if (dot < -0.5) pose = POSE.dashB;
    else pose = cross > 0 ? POSE.dashR : POSE.dashL;
    const D = 0.26, SP = 60 * (this.mods().speed || 1);
    this.startAction({
      name: 'dash', dur: D, iframes: 0.18, keepVel: true, poseSpeed: 24,
      pose: (f, a, out) => out.set(pose),
      update: (f, dt, t) => {
        const k = Math.sqrt(Math.max(0, 1 - t / D));
        f.vel.x = dx * SP * k; f.vel.z = dz * SP * k;
        if (f.vel.y > 0 && !f.onGround) f.vel.y *= 0.9;
        if (Math.random() < 0.6) {
          _v.set(f.pos.x + rand(-1, 1), f.pos.y + rand(0.5, 4.5), f.pos.z + rand(-1, 1));
          _w.set(-dx * 30, 0, -dz * 30);
          G.fx.str.add(_v, _w, '#ffffff', 0.18, 0.08, 2.4, { drag: 8 });
        }
      },
      onEnd: (f) => { if (f.m1Buf > 0) { f.m1Buf = 0; f.m1(); } },
    });
    this.dashCd = 1.7 * (this.mods().cd || 1);
    if (this.onGround) G.fx.dust(_v.copy(this.pos), 6, 2);
    G.sound('dash', this.pos, 0.55);
    return true;
  }

  // ---------- навыки ----------
  skillDef(i) {
    if (this.awakened > 0 && this.ch.awakenSkills && this.ch.awakenSkills[i]) return this.ch.awakenSkills[i];
    return this.ch.skills[i];
  }
  skill(i) {
    if (this.dead) return false;
    const sk = this.skillDef(i);
    if (!sk || this.cd[i] > 0) return false;
    // навык отменяет восстановление после M1 (продолжение комбо)
    const a = this.action;
    if (a && (a.name === 'm1' && a.t >= a.hitAt || a.name === 'land')) this.action = null;
    if (!this.canAct()) { if (this.isPlayer) this.skillBuf = { i, t: 0.35 }; return false; }
    this.prot = 0;
    if (sk.cast(this) === false) return false;
    this.cd[i] = this.cdMax[i] = sk.cd * this.cdMult();
    return true;
  }
  release(i) { if (this.action && this.action.slot === i) this.action.released = true; }
  awaken() {
    if (this.dead || this.meter < 100 || this.awakened > 0 || !this.canAct()) return false;
    this.meter = 0;
    this.awakened = this.ch.awaken.dur;
    this.cd = [0, 0, 0, 0];
    this.prot = 0;
    this.ch.awaken.cast(this);
    G.onAwaken(this);
    return true;
  }

  // ---------- урон ----------
  launch(vx, vy, vz, t) {
    this.interrupt(true);
    this.blocking = false;
    this.rag = true; this.ragT = t; this.down = 0; this.stun = 0;
    this.vel.set(vx, vy, vz);
    this.onGround = false;
    this.pos.y += 0.2;
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
    this.action = null; this.blocking = false; this.rag = false; this.awakened = 0;
    this.infinity = this.counter = 0;
    this.model.root.updateMatrixWorld(true);
    // роблокс-стиль: тело разваливается на части
    const away = _d.set(this.pos.x - (killer ? killer.pos.x : this.pos.x), 0, this.pos.z - (killer ? killer.pos.z : this.pos.z));
    if (away.lengthSq() < 0.01) away.set(rand(-1, 1), 0, rand(-1, 1));
    away.normalize();
    for (const me of this.model.meshes) {
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
    for (let i = 0; i < 4; i++) if (this.cd[i] > 0) this.cd[i] = Math.max(0, this.cd[i] - dt);
    if (this.dashCd > 0) this.dashCd -= dt;
    if (this.m1Cd > 0) this.m1Cd -= dt;
    if (this.m1Buf > 0) this.m1Buf -= dt;
    if (this.comboT > 0) this.comboT -= dt;
    if (this.prot > 0) this.prot -= dt;
    if (this.iframes > 0) this.iframes -= dt;
    if (this.infinity > 0) this.infinity -= dt;
    if (this.counter > 0) this.counter -= dt;
    if (this.hitFlash > 0) this.hitFlash -= dt;
    if (this.broken > 0) this.broken -= dt;
    if (this.awakened > 0) {
      this.awakened -= dt;
      if (this.ch.awaken.tick) this.ch.awaken.tick(this, dt);
      if (this.awakened <= 0) { this.awakened = 0; this.ch.awaken.end?.(this); }
    }
    if (G.time - this.lastDamagedT > 7 && this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + 2.5 * dt);
    if (!this.blocking) { this.guardDelay -= dt; if (this.guardDelay <= 0) this.guard = Math.min(100, this.guard + 30 * dt); }

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
      if (this.down <= 0) { this.iframes = Math.max(this.iframes, 0.45); this.stun = 0; }
    } else if (this.stun > 0) {
      this.stun -= dt; this.blocking = false; this.friction(dt, 9);
    } else if (this.action) this.updateAction(dt);
    else ctrl = true;

    if (ctrl) this.locomotion(dt);
    this.physics(dt);
    this.animate(dt);
    this.syncModel(dt);
  }

  locomotion(dt) {
    const inp = this.input;
    this.blocking = inp.block;
    const sp = this.walkSpeed() * (this.blocking ? 0.32 : 1);
    const k = 1 - Math.exp(-(this.onGround ? 14 : 5) * dt);
    this.vel.x += (inp.mx * sp - this.vel.x) * k;
    this.vel.z += (inp.mz * sp - this.vel.z) * k;
    const m = inp.mx * inp.mx + inp.mz * inp.mz;
    if (m > 0.01 && !this.blocking) this.yaw = angleDamp(this.yaw, Math.atan2(inp.mx, inp.mz), 13, dt);
    else if (this.blocking && this.lastHitBy && G.time - this.lastHitT < 1) this.faceTo(this.lastHitBy.pos);
    if (inp.jump && this.onGround && !this.blocking) {
      this.vel.y = 31; this.onGround = false;
      G.sound('jump', this.pos, 0.3);
    }
  }

  physics(dt) {
    const a = this.action;
    if (!(a && a.noGrav)) this.vel.y -= GRAV * dt;
    this.pos.addScaledVector(this.vel, dt);
    const gy = G.world.groundAt(this.pos.x, this.pos.z, this.pos.y);
    if (this.pos.y <= gy) {
      if (!this.onGround && this.vel.y < -28) {
        G.fx.dust(_v.copy(this.pos), this.rag ? 10 : 4, this.rag ? 3 : 2);
        if (this.rag) { G.sound('hit', this.pos, 0.35); }
      }
      if (this.rag && this.vel.y < -24) { this.vel.y = -this.vel.y * 0.3; this.pos.y = gy + 0.01; this.onGround = false; }
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
    this.ragT -= dt;
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
      this.rag = false;
      this.down = 0.55;
      this.pose[K.lean] = wrapAngle(this.pose[K.lean] + this.ragSpin.x);
      this.pose[K.roll] = wrapAngle(this.pose[K.roll] + this.ragSpin.z);
      this.ragSpin.set(0, 0, 0);
    }
  }

  animate(dt) {
    const tp = this.tp;
    let speed = 16;
    const t = G.time;
    const katana = this.ch.m1 === 'katana';
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
    } else if (this.blocking) { tp.set(katana ? POSE.blockK : POSE.block); speed = 24; }
    else if (!this.onGround) { tp.set(this.vel.y > 2 ? POSE.air : POSE.air); tp[K.llx] = this.vel.y > 0 ? -0.8 : -0.3; speed = 10; }
    else {
      const hs = Math.hypot(this.vel.x, this.vel.z);
      if (hs > 1.5) {
        this.runPhase += dt * hs * 0.62;
        runPose(tp, this.idlePose, this.runPhase, clamp(hs / 17, 0, 1.25), katana);
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
    m.root.position.copy(this.pos);
    if (this.hitstop > 0 && this.stun > 0) { m.root.position.x += rand(-0.12, 0.12); m.root.position.z += rand(-0.12, 0.12); }
    m.root.rotation.y = this.yaw;
    applyPose(m, this.pose, this.rag ? this.ragSpin : null);
    // подсветка
    const e = m.bodyMat.emissive, eh = m.headMat.emissive;
    if (this.hitFlash > 0) { const k = this.hitFlash / 0.12 * 0.55; e.setRGB(k, k, k); }
    else if (this.prot > 0) { const k = 0.25 + Math.sin(G.time * 18) * 0.15; e.setRGB(k * 0.6, k * 0.8, k); }
    else if (this.awakened > 0) { e.set(this.look.color).multiplyScalar(0.18 + Math.sin(G.time * 6) * 0.06); }
    else if (this.counter > 0) { e.setRGB(0.35, 0.25, 0.05); }
    else e.setRGB(0, 0, 0);
    eh.copy(e);
  }
}

// ---------- Разрешение удара ----------
export function hit(att, vic, o) {
  if (!vic || vic.dead || vic === att || G.isAlly(att, vic) || G.matchOver) return null;
  if (vic.prot > 0) return null;
  if (vic.iframes > 0 && !o.ignoreIframes) return null;
  _d.set(vic.pos.x - (o.from ? o.from.x : att.pos.x), 0, vic.pos.z - (o.from ? o.from.z : att.pos.z));
  if (_d.lengthSq() < 0.001) _d.set(Math.sin(att.yaw), 0, Math.cos(att.yaw));
  _d.normalize();
  const dir = _d;
  vic.chestPos(_hp).addScaledVector(dir, -0.9);
  const contact = _hp;
  // контрудар (Manji Kick)
  if (vic.counter > 0 && !o.noCounter && vic.ch.onCounter) {
    vic.counter = 0;
    vic.ch.onCounter(vic, att);
    return 'counter';
  }
  let dmg = o.dmg * att.dmgMult() * (vic.ch.dmgTaken || 1) * (o.melee && att.ch.m1Mult && !o.skill ? att.ch.m1Mult : 1);
  // Бесконечность
  if (vic.infinity > 0 && !o.pierce) {
    dmg *= 0.08;
    vic.hp -= dmg; vic.lastDamagedT = G.time;
    G.fx.ring(contact, '#bfe6ff', 0.4, 2.6, 0.3, { a0: 0.9 });
    G.fx.particles(contact, { n: 6, color: '#bfe6ff', speed: 4, size: 0.6, life: 0.3 });
    G.hud.pop(contact, '∞', '#bfe6ff', 0.9);
    G.sound('block', vic.pos, 0.5);
    if (o.melee) { att.interrupt(); att.stun = Math.max(att.stun, 0.35); att.vel.addScaledVector(dir, -10); }
    if (vic.hp <= 0) G.kill(vic, att);
    return 'inf';
  }
  const vf = Math.sin(vic.yaw) * -dir.x + Math.cos(vic.yaw) * -dir.z;
  if (vic.blocking && vf > 0.05 && !o.unblockable) {
    const gd = o.guardBreak ? 999 : o.guardDmg ?? dmg * 5;
    vic.guard -= gd; vic.guardDelay = 1.3;
    if (vic.guard <= 0) {
      vic.guard = 100; vic.blocking = false;
      vic.interrupt(true);
      vic.stun = 1.7; vic.broken = 1.7;
      vic.hp -= dmg * 0.5; vic.lastDamagedT = G.time; vic.lastHitBy = att; vic.lastHitT = G.time;
      vic.hitstop = att.hitstop = 0.12;
      G.fx.ring(contact, '#9fd8ff', 1, 7, 0.35, { a0: 1 });
      G.fx.burst(contact, '#cfefff', 8, 0.2);
      G.fx.debris(contact, 8, ['#bfe6ff', '#ffffff', '#8fc8ff'], 18);
      G.hud.pop(vic.headPos(_v), 'GUARD BREAK', '#7fd0ff', 1.3);
      G.sound('heavy', vic.pos, 0.8); G.sound('block', vic.pos, 0.8);
      if (att.isPlayer || vic.isPlayer) G.shake(0.5, vic.pos);
      if (vic.hp <= 0) G.kill(vic, att);
      return 'break';
    }
    dmg *= 0.2;
    vic.hp -= dmg; vic.lastDamagedT = G.time;
    vic.vel.addScaledVector(dir, 7);
    vic.hitstop = Math.max(vic.hitstop, 0.04); if (o.melee) att.hitstop = Math.max(att.hitstop, 0.04);
    G.fx.sparks(contact, _w.copy(dir).negate(), '#bfe6ff', 6, 30);
    G.fx.burst(contact, '#9fd8ff', 3.5, 0.12);
    G.hud.pop(contact, dmg.toFixed(1), '#9aa3b5', 0.8);
    G.sound('block', vic.pos, 0.6);
    if (att.awakened <= 0) att.meter = Math.min(100, att.meter + dmg * 0.6);
    if (vic.hp <= 0) G.kill(vic, att);
    return 'blocked';
  }
  // попадание
  vic.hp -= dmg;
  att.dmgDealt += dmg;
  vic.lastHitBy = att; vic.lastHitT = G.time; vic.lastDamagedT = G.time;
  const armor = vic.action && vic.action.armor;
  if (!armor) {
    vic.blocking = false;
    if (o.rag && !vic.rag) {
      vic.launch(dir.x * o.kb.f, o.kb.up, dir.z * o.kb.f, o.rag);
      vic.yaw = Math.atan2(-dir.x, -dir.z);
    } else if (vic.rag) {
      if (o.kb) { vic.vel.x += dir.x * o.kb.f * 0.5; vic.vel.z += dir.z * o.kb.f * 0.5; vic.vel.y = Math.max(vic.vel.y, (o.kb.up || 0) * 0.6); }
    } else {
      vic.interrupt();
      if (o.stun) vic.stun = Math.max(vic.stun, o.stun);
      if (o.kb) { vic.vel.x = dir.x * o.kb.f; vic.vel.z = dir.z * o.kb.f; if (o.kb.up) { vic.vel.y = o.kb.up; vic.onGround = false; } }
      else if (o.push) { vic.vel.x = dir.x * o.push; vic.vel.z = dir.z * o.push; }
      if (vic.down <= 0) vic.yaw = Math.atan2(-dir.x, -dir.z);
    }
  }
  vic.hitFlash = 0.12; vic.hitVariant ^= 1;
  if (att.awakened <= 0) att.meter = Math.min(100, att.meter + dmg * 1.15);
  if (vic.awakened <= 0) vic.meter = Math.min(100, vic.meter + dmg * 0.35);
  const hs = o.hitstop ?? 0.05;
  vic.hitstop = Math.max(vic.hitstop, hs);
  if (o.melee) att.hitstop = Math.max(att.hitstop, hs);
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
  G.sound(o.sfx || 'hit', vic.pos, o.vol ?? 0.7);
  G.hud.pop(contact, dmg >= 10 ? Math.round(dmg).toString() : dmg.toFixed(1), o.numColor || (dmg >= 10 ? '#ffd23f' : '#ffffff'), dmg >= 10 ? 1.25 : 0.95);
  if (att.isPlayer || vic.isPlayer) G.shake(o.shake ?? 0.2, vic.pos);
  if (att.isPlayer) G.hud.combo();
  if (vic.isPlayer) G.hud.hurt(dmg);
  if (vic.hp <= 0) G.kill(vic, att);
  return 'hit';
}

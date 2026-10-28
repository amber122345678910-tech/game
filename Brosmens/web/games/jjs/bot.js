// Мозг бота: выбор цели (ближайший/слабый/месть), сближение, комбо, блок, уклонение рывком,
// навыки по дистанции и перезарядке, отступление на низком HP, пробуждение.
import * as THREE from 'three';
import { G } from './ctx.js';
import { rand } from './util.js';

const RANGED_THREATS = new Set(['purple', 'love', 'fuga', 'red', 'blue', 'rsmash']);

export class Brain {
  constructor(f) {
    this.f = f;
    this.skill = f.bot?.skill ?? 0.6;
    this.target = null;
    this.think = rand(0, 0.3);
    this.strafe = Math.random() < 0.5 ? 1 : -1;
    this.blockT = 0;
    this.mode = 'hunt'; this.modeT = 0;
    this.m1T = 0;
    this.skillT = rand(0.8, 2);
    this.seen = new WeakSet();
    this.lastPos = new THREE.Vector3(); this.stuckT = 0; this.unstickT = 0; this.unstickX = 0; this.unstickZ = 0;
    this.reaction = 0.34 - this.skill * 0.24;
    this.jumpT = rand(3, 8);
    this.aggr = rand(0.7, 1.1);
    this.idleT = rand(0, 1);
    this.wanderX = rand(-30, 30); this.wanderZ = rand(-30, 30);
  }

  update(dt) {
    const f = this.f, inp = f.input;
    inp.mx = 0; inp.mz = 0; inp.jump = false; inp.jumpHeld = false; inp.block = false;
    if (f.dead || G.matchOver) return;
    this.think -= dt;
    if (this.think <= 0) { this.think = rand(0.2, 0.4); this.choose(); }
    if (this.blockT > 0) { this.blockT -= dt; inp.block = true; }
    const t = this.target;
    if (!t || t.dead) {
      // бродит
      const dx = this.wanderX - f.pos.x, dz = this.wanderZ - f.pos.z, d = Math.hypot(dx, dz);
      if (d < 4) { this.wanderX = rand(-40, 40); this.wanderZ = rand(-40, 40); }
      else { inp.mx = (dx / d) * 0.6; inp.mz = (dz / d) * 0.6; }
      this.unstick(dt);
      return;
    }
    const dx = t.pos.x - f.pos.x, dz = t.pos.z - f.pos.z;
    const d = Math.hypot(dx, dz) || 0.001;
    const nx = dx / d, nz = dz / d;
    f.aim.set(nx, 0, nz);
    const px = -nz * this.strafe, pz = nx * this.strafe;

    if (this.mode === 'retreat') {
      this.modeT -= dt;
      inp.mx = -nx * 0.9 + px * 0.4; inp.mz = -nz * 0.9 + pz * 0.4;
      if (d < 9 && f.dashCd <= 0 && Math.random() < dt * 2) f.dash();
      if (f.charId === 'gojo' && f.cd[2] <= 0 && d < 10) f.skill(2);
      if (this.modeT <= 0 || d > 34 || f.hp > 55) this.mode = 'hunt';
      this.unstick(dt);
      return;
    }

    this.defend(dt, d, nx, nz);
    if (f.dead) return;

    // движение
    const melee = 3.2;
    const busyAttack = f.action && (f.action.name === 'm1' || f.action.name === 'fuga');
    if (!inp.block) {
      if (d > melee + 1.2) {
        const s = d > 12 ? 1 : 0.9;
        inp.mx = nx * s + px * 0.18; inp.mz = nz * s + pz * 0.18;
        const dMin = f.ch.aiRush ? 8 : 18;
        if (d > dMin && d < 45 && f.dashCd <= 0 && Math.random() < dt * (f.ch.aiRush ? 2.2 : 0.9) * this.skill) { f.input.mx = nx; f.input.mz = nz; f.dash(); }
      } else if (d < melee - 1.3) { inp.mx = -nx * 0.5; inp.mz = -nz * 0.5; }
      else { inp.mx = px * 0.35; inp.mz = pz * 0.35; }
    } else { inp.mx = nx * 0.3; inp.mz = nz * 0.3; }
    if (busyAttack) { inp.mx *= 0.3; inp.mz *= 0.3; }

    // M1
    this.m1T -= dt;
    if (d < 6.5 && !inp.block && Math.abs(t.pos.y - f.pos.y) < 4) {
      // комбо-продолжение навыком после 3-го удара
      if (f.combo === 3 && f.comboT > 0 && !f.action && this.skill > 0.55 && Math.random() < this.skill * 0.5 && this.useSkill(d, true)) { /* навык */ }
      else if (this.m1T <= 0 && (!f.action || f.action.name === 'm1')) {
        f.m1();
        this.m1T = 0.2 + rand(0, 0.3) * (1.2 - this.skill);
        if (f.combo === 4 && Math.random() < 0.3 * this.skill) inp.jumpHeld = true;
      }
    } else if (!f.onGround && d < 7 && t.pos.y < f.pos.y - 1 && Math.random() < 0.1) f.m1();

    // навыки
    this.skillT -= dt;
    if (this.skillT <= 0 && !f.busy()) {
      this.skillT = rand(0.35, 1.1) * (1.5 - this.skill);
      this.useSkill(d, false);
    }
    // пробуждение
    if (f.meter >= 100 && !f.busy() && d < f.ch.awaken.aiRange && Math.random() < dt * 3) f.awaken();

    // прыжки для живости
    this.jumpT -= dt;
    if (this.jumpT <= 0) { this.jumpT = rand(3, 9); if (!f.busy() && d > 8) inp.jump = true; }
    this.unstick(dt);
  }

  unstick(dt) {
    const f = this.f, inp = this.f.input;
    if (this.unstickT > 0) { this.unstickT -= dt; inp.mx = this.unstickX; inp.mz = this.unstickZ; return; }
    const moving = inp.mx * inp.mx + inp.mz * inp.mz > 0.3 && !f.busy();
    this.stuckT += dt;
    if (this.stuckT > 0.7) {
      const moved = Math.hypot(f.pos.x - this.lastPos.x, f.pos.z - this.lastPos.z);
      if (moving && moved < 1.5) {
        inp.jump = true;
        const s = Math.random() < 0.5 ? 1 : -1;
        this.unstickX = -inp.mz * s; this.unstickZ = inp.mx * s; this.unstickT = 0.6;
      }
      this.stuckT = 0; this.lastPos.copy(f.pos);
    }
  }

  defend(dt, d, nx, nz) {
    const f = this.f;
    if (f.stun > 0 || f.rag || f.down > 0) return;
    for (const e of G.fighters) {
      if (!f.isEnemy(e) || !e.action) continue;
      const a = e.action;
      if (this.seen.has(a)) continue;
      const ed = f.dist(e);
      const ex = f.pos.x - e.pos.x, ez = f.pos.z - e.pos.z;
      const facing = ed > 0.01 ? (Math.sin(e.yaw) * ex + Math.cos(e.yaw) * ez) / ed : 1;
      if (a.kind === 'melee' && ed < 9 && facing > 0.4) {
        if (a.t < this.reaction) continue; // ещё не «увидел»
        this.seen.add(a);
        if (Math.random() > this.skill * 0.8) continue;
        if (!f.action || f.action.name === 'm1') {
          if (f.dashCd <= 0 && Math.random() < 0.25 + this.skill * 0.15) {
            f.input.mx = -ez / ed * this.strafe || nx; f.input.mz = ex / ed * this.strafe || nz;
            f.dash();
          } else {
            if (f.action && f.action.name === 'm1') f.interrupt();
            this.blockT = rand(0.35, 0.9);
            f.input.block = true;
          }
        }
      } else if (RANGED_THREATS.has(a.name) && ed < 60 && facing > 0.85) {
        if (a.t < this.reaction + 0.15) continue;
        this.seen.add(a);
        if (Math.random() < this.skill * 0.75 && f.dashCd <= 0 && !f.action) {
          const s = Math.random() < 0.5 ? 1 : -1;
          f.input.mx = (-ez / ed) * s; f.input.mz = (ex / ed) * s;
          f.dash();
        } else if (f.charId === 'gojo' && f.cd[2] <= 0 && !f.action && Math.random() < this.skill) f.skill(2);
      }
    }
  }

  useSkill(d, comboExt) {
    const f = this.f, t = this.target;
    const order = [0, 1, 2, 3].sort(() => Math.random() - 0.5);
    for (const i of order) {
      if (f.cd[i] > 0) continue;
      const sk = f.skillDef(i);
      const ai = sk.ai;
      let ok = false;
      switch (ai.kind) {
        case 'melee': ok = d <= ai.max && (comboExt || t.stun > 0 || Math.random() < 0.45); break;
        case 'ranged': ok = !comboExt && d >= ai.min && d <= ai.max && Math.random() < (t.stun > 0 || t.down > 0 ? 0.9 : 0.5); break;
        case 'gap': ok = d >= ai.min && d <= ai.max && (comboExt ? ai.min === 0 : Math.random() < 0.55); break;
        case 'charge': ok = !comboExt && d >= ai.min && d <= ai.max && Math.random() < 0.45; break;
        case 'buff': ok = (G.time - f.lastDamagedT < 1.0 && f.hp < 85) || (d < 6 && t.action && t.action.kind === 'melee'); break;
        case 'counter': ok = d < ai.max && t.action && t.action.kind === 'melee' && Math.random() < this.skill; break;
        case 'aoe': {
          let n = 0; for (const o of G.fighters) if (f.isEnemy(o) && f.dist(o) < ai.max) n++;
          ok = n >= 2 || (n === 1 && Math.random() < 0.5);
          break;
        }
      }
      if (!ok) continue;
      f.faceTo(t.pos);
      if (f.skill(i)) return true;
    }
    return false;
  }

  choose() {
    const f = this.f;
    if (f.hp < 28 && this.skill > 0.45 && this.mode !== 'retreat' && f.awakened <= 0 && Math.random() < 0.3) {
      this.mode = 'retreat'; this.modeT = rand(2, 3.5);
    }
    let best = null, bs = 1e9;
    for (const o of G.fighters) {
      if (!f.isEnemy(o)) continue;
      const d = f.dist(o);
      let s = d;
      s -= (1 - o.hp / o.maxHp) * 16 * this.skill;
      if (o === f.lastHitBy && G.time - f.lastHitT < 6) s -= 22 * this.aggr;
      if (o === this.target) s -= 8;
      // Клод прикрывает игрока: бьёт тех, кто нападает на него
      if (f.isClaude && G.player && !G.player.dead) {
        if (o.brain && o.brain.target === G.player && o.dist(G.player) < 20) s -= 14;
        if (G.player.lastHitBy === o && G.time - G.player.lastHitT < 4) s -= 20;
      }
      let n = 0;
      for (const b of G.fighters) if (b !== f && b.brain && b.brain.target === o) n++;
      s += n * 5;
      if (s < bs) { bs = s; best = o; }
    }
    this.target = best;
    if (Math.random() < 0.25) this.strafe *= -1;
  }
}

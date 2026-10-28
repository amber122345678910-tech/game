// Мозг бота: выбор цели (ближайший/слабый/месть), сближение, комбо, блок, рывки (фронтальный/боковой),
// уклонение из рэгдолла (новички сразу, сильные — копят для наказания), всплеск против толпы,
// навыки и особый навык по дистанции и перезарядке, отступление на низком HP, пробуждение.
import * as THREE from 'three';
import { G } from './ctx.js';
import { rand } from './util.js';

const RANGED_THREATS = new Set(['purple', 'love', 'fuga', 'red', 'redmax', 'lblue', 'bluemax', 'rsmash', 'sdismantle', 'dismantle']);

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
    this.specT = rand(1, 3);
    this.evaT = -1;
    this.tBlockT = 0;
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
    // рэгдолл: уклонение (evasive) — новички сразу, сильные боты берегут для наказания
    if (f.rag || f.down > 0) { this.evasive(dt); return; }
    this.evaT = -1;
    // всплеск: если зажали вдвоём — боковой рывок (+10 HP и полная шкала уклонения)
    if (f.burst > 0 && f.burstCd <= 0 && Math.random() < dt * (2 + this.skill * 6)) {
      const s = Math.random() < 0.5 ? 1 : -1;
      inp.mx = -f.aim.z * s; inp.mz = f.aim.x * s;
      if (f.dash()) return;
    }
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
      if (d < 9 && f.sdashCd <= 0 && Math.random() < dt * 2) f.dash();
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
        // фронтальный рывок с джебом для сближения (12–25 стадов)
        if (d > 11 && d < 25 && f.fdashCd <= 0 && Math.random() < dt * (f.ch.aiRush ? 1.2 : 0.6) * (0.4 + this.skill)) { f.input.mx = nx; f.input.mz = nz; f.dash(); }
      } else if (d < melee - 1.3) { inp.mx = -nx * 0.5; inp.mz = -nz * 0.5; }
      else { inp.mx = px * 0.35; inp.mz = pz * 0.35; }
    } else { inp.mx = nx * 0.3; inp.mz = nz * 0.3; }
    if (busyAttack) { inp.mx *= 0.3; inp.mz *= 0.3; }

    // цель долго держит блок — обойти боковым рывком и бить в спину
    if (t.blocking) this.tBlockT += dt; else this.tBlockT = 0;
    if (this.tBlockT > 0.4 && d < 8 && f.sdashCd <= 0 && !f.action && Math.random() < dt * 4 * this.skill) {
      inp.mx = -nz * this.strafe; inp.mz = nx * this.strafe;
      if (f.dash()) { f.m1Buf = 0.35; this.tBlockT = 0; }
    }
    // финт (Combat Instincts): отменить замах, если цель блокирует или стоит в контратаке
    const sp = f.specialDef();
    if (sp && sp.instant && f.specCd <= 0 && f.action && f.action.slot != null && f.action.t < (f.action.windup ?? 0.25) && (t.blocking || t.counter > 0) && Math.random() < this.skill * 0.5) f.special();

    // M1
    if (this.upper && f.action && f.action.name === 'm1' && f.action.n === 4) inp.jumpHeld = true;
    else if (!f.action) this.upper = false;
    this.m1T -= dt;
    if (d < 6.5 && !inp.block && Math.abs(t.pos.y - f.pos.y) < 4) {
      // комбо-продолжение навыком после 3-го удара
      if (f.combo === 3 && f.comboT > 0 && !f.action && this.skill > 0.55 && Math.random() < this.skill * 0.5 && this.useSkill(d, true)) { /* навык */ }
      else if (this.m1T <= 0 && (!f.action || f.action.name === 'm1')) {
        // 4-й удар: иногда апперкот (зажатый прыжок)
        if (f.combo === 3 && f.comboT > 0) this.upper = Math.random() < 0.1 + 0.35 * this.skill;
        inp.jumpHeld = !!this.upper && f.combo === 3;
        f.m1();
        this.m1T = 0.2 + rand(0, 0.3) * (1.2 - this.skill);
      }
    } else if (!f.onGround && d < 7 && t.pos.y < f.pos.y - 1 && f.vel.y < 0 && f.combo === 3 && Math.random() < 0.1) f.m1();

    // навыки
    this.skillT -= dt;
    if (this.skillT <= 0 && !f.busy()) {
      this.skillT = rand(0.35, 1.1) * (1.5 - this.skill);
      this.useSkill(d, false);
    }
    // особый навык (R)
    this.specT -= dt;
    if (this.specT <= 0 && !f.busy()) { this.specT = rand(0.6, 1.6) * (1.6 - this.skill); this.useSpecial(d); }
    // пробуждение: как только шкала полная — если HP < 60 % или враг ближе 30
    if (f.meter >= 100 && !f.busy() && (f.hp < f.maxHp * 0.6 || d < 30) && Math.random() < dt * 3) f.awaken();

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
          if (f.sdashCd <= 0 && Math.random() < 0.25 + this.skill * 0.15) {
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
        if (Math.random() < this.skill * 0.75 && f.sdashCd <= 0 && !f.action) {
          const s = Math.random() < 0.5 ? 1 : -1;
          f.input.mx = (-ez / ed) * s; f.input.mz = (ex / ed) * s;
          f.dash();
        }
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
        case 'domain': ok = d <= ai.max && (t.rag || t.stun > 0 || t.evasive < 100 || Math.random() < 0.3); break;
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

  useSpecial(d) {
    const f = this.f, t = this.target, sk = f.specialDef();
    if (!sk || f.specCd > 0 || !t) return false;
    // Limitless тратит 6 % пробуждения — бот бережёт шкалу, пока она почти пустая
    if (sk.id === 'limitless' && f.awakened <= 0 && f.meter < 25) return false;
    const ai = sk.ai || {};
    let ok = false;
    if (ai.kind === 'gap') ok = d >= ai.min && d <= ai.max && Math.random() < 0.5;
    else if (ai.kind === 'melee') ok = d <= (ai.max ?? 7) && (t.stun > 0 || Math.random() < 0.4);
    if (!ok) return false;
    f.faceTo(t.pos);
    return f.special();
  }

  // Уклонение из рэгдолла: слабые — сразу; сильные (skill > 0.7) — когда враг рядом и занят долгим действием или HP низкое
  evasive(dt) {
    const f = this.f;
    if (f.evasive < 100 || f.ragTrue || !f.rag) return;
    if (this.evaT < 0) this.evaT = this.reaction + rand(0.05, 0.25);
    this.evaT -= dt;
    if (this.evaT > 0) return;
    const a = f.lastHitBy;
    let go;
    if (this.skill <= 0.7) go = true;
    else go = f.hp < 35 || (a && !a.dead && f.dist(a) < 12 && a.action && a.action.dur - a.action.t > 0.35) || Math.random() < dt * 0.6;
    if (!go) return;
    if (a && !a.dead) {
      const dx = f.pos.x - a.pos.x, dz = f.pos.z - a.pos.z, l = Math.hypot(dx, dz) || 1, s = Math.random() < 0.5 ? 1 : -1;
      f.input.mx = (dx / l) * 0.5 - (dz / l) * 0.85 * s; f.input.mz = (dz / l) * 0.5 + (dx / l) * 0.85 * s;
    }
    if (f.dash()) { this.evaT = -1; if (this.skill > 0.7) f.m1Buf = 0.35; }
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

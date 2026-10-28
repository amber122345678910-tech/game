// ИИ ботов. Люди: уходят с линий лучей, перепрыгивают кости, замирают у синих, выходят из круга гравитации,
// держат дистанцию по роли, сбивают уклонение и добивают, лечат/щитуют/поднимают.
// Судья: выбирает цель (провокация!), комбинирует бластеры/кости/гравитацию, телепортируется из толпы, ульта.
import * as THREE from 'three';
import { dist2, clamp } from './combat.js';
import { ARENA_HALF } from './data.js';
import { humanM1, humanDash, humanSkill, healTarget, canRevive } from './human.js';
import { monsterM1, monsterTeleport, castBlasters, castBones, castGravity, castUlt } from './monster.js';

const rand = (a, b) => a + Math.random() * (b - a);
const ESC = new THREE.Vector3(), GOAL = new THREE.Vector3(), T = new THREE.Vector3(), ZERO = new THREE.Vector3();

const PREF = { det: 3.0, brv: 2.8, pat: 6.2, jus: 17 };
const RANGE = { det: 4.4, brv: 4.1, pat: 7.2, jus: 60 };

export class HumanBrain {
  constructor(G, f) {
    this.G = G; this.f = f;
    this.skill = clamp(f.bot?.skill ?? 0.7, 0.3, 0.98);
    this.react = 0.07 + (1 - this.skill) * 0.3;
    this.seen = new WeakMap();
    this.strafe = Math.random() < 0.5 ? 1 : -1; this.strafeT = rand(1.5, 4);
    this.m1Gap = 0; this.think = rand(0, 0.3); this.dashDir = new THREE.Vector3();
    this.jumpJit = rand(-0.05, 0.05);
  }
  note(hz) {
    let s = this.seen.get(hz);
    if (!s) {
      const miss = Math.random() > 0.55 + this.skill * 0.45;
      s = { t: this.G.time, delay: this.react * rand(0.7, 1.3) + (miss ? rand(0.3, 0.6) : 0) };
      this.seen.set(hz, s);
    }
    return this.G.time - s.t >= s.delay ? s : null;
  }
  update(dt) {
    const f = this.f, G = this.G;
    f.moveDir.set(0, 0, 0);
    if (f.dead || G.state !== 'fight' || f.grab) return;
    const m = G.monster;
    ESC.set(0, 0, 0);
    let urgent = false, jump = false, stop = false, dash = false, keepMoving = false;
    for (const hz of G.hazards) {
      if (hz.kind === 'blaster') {
        if (!hz.dangerous() || !this.note(hz)) continue;
        const rx = f.pos.x - hz.origin.x, rz = f.pos.z - hz.origin.z;
        const along = rx * hz.dir.x + rz * hz.dir.z;
        if (along < -3 || along > hz.len) continue;
        const cross = rx * hz.dir.z - rz * hz.dir.x, need = hz.R + f.radius + 1.4;
        if (Math.abs(cross) > need) continue;
        let side = Math.sign(cross) || this.strafe;
        const px = hz.dir.z * side, pz = -hz.dir.x * side;
        if (Math.abs(f.pos.x + px * 6) > ARENA_HALF - 2 || Math.abs(f.pos.z + pz * 6) > ARENA_HALF - 2) side = -side;
        const w = 1 + (need - Math.abs(cross));
        ESC.x += hz.dir.z * side * w * 3; ESC.z += -hz.dir.x * side * w * 3;
        urgent = true;
        const ttf = hz.timeToFire();
        if (ttf < 0.32 && ttf > -0.3 && Math.abs(cross) < hz.R + f.radius + 0.3) { dash = true; this.dashDir.set(hz.dir.z * side, 0, -hz.dir.x * side); }
      } else if (hz.kind === 'row') {
        if (hz.t < 0 || hz.riseK <= 0 || !this.note(hz)) continue;
        const cx = hz.origin.x + hz.dir.x * hz.s, cz = hz.origin.z + hz.dir.z * hz.s;
        const rx = f.pos.x - cx, rz = f.pos.z - cz;
        const along = rx * hz.dir.x + rz * hz.dir.z, across = rx * hz.perp.x + rz * hz.perp.z;
        if (Math.abs(across) > hz.halfW + 1.5 || along < -1.3 || along > 9) continue;
        if (hz.type === 1) { if (along < 5) stop = true; continue; }
        if (hz.type === 2) { if (along < 5) keepMoving = true; continue; }
        if (!hz.moving) { if (along < 3) { ESC.addScaledVector(hz.dir, 2); urgent = true; if (along < 1.3) jump = true; } continue; }
        const tArr = (along - 1.1) / hz.speed;
        if (tArr < 0.17 + this.jumpJit) jump = true;
      } else if (hz.kind === 'ring') {
        if (hz.t < 0 || hz.riseK <= 0 || hz.dmg <= 0 || !this.note(hz)) continue;
        const d = dist2(f.pos, hz.c) - hz.r;
        if (d < -1.3 || d > 9) continue;
        if (hz.type === 1) { if (d < 5) stop = true; continue; }
        if (hz.type === 2) { if (d < 5) keepMoving = true; continue; }
        if (hz.t < hz.rise) { if (d < 2.5) jump = d < 1.3; continue; }
        if ((d - 1.1) / hz.speed < 0.17 + this.jumpJit) jump = true;
      } else if (hz.kind === 'gravity') {
        if (hz.target !== f || hz.phase !== 'mark' || !this.note(hz)) continue;
        T.set(f.pos.x - hz.ringPos.x, 0, f.pos.z - hz.ringPos.z);
        if (T.lengthSq() < 0.1) T.set(this.strafe, 0, 0.3);
        T.normalize();
        ESC.addScaledVector(T, 4); urgent = true;
        if (hz.timeToLock() < 0.3) { dash = true; this.dashDir.copy(T); }
      }
    }
    // цель и дистанция
    GOAL.set(0, 0, 0);
    const role = f.roleId;
    let reviveT = null;
    if (role === 'pat') reviveT = f.reviveCharges > 0 ? G.humans.find((h) => h.dead && h !== f && h.deadT > 1) : null;
    this.strafeT -= dt; if (this.strafeT <= 0) { this.strafe = -this.strafe; this.strafeT = rand(1.5, 4); }
    if (m && !m.dead) {
      const d = dist2(f.pos, m.pos);
      T.set(m.pos.x - f.pos.x, 0, m.pos.z - f.pos.z).divideScalar(Math.max(0.1, d));
      let want = PREF[role];
      if (f.hp / f.maxHp < 0.3 && role !== 'brv') want = 24;
      if (m.action?.name === 'ult') want = Math.max(want, 14);
      const diff = d - m.radius - want;
      const ap = clamp(diff / 3, -1, 1);
      const st = role === 'jus' ? 0.6 : 0.35;
      GOAL.set(T.x * ap - T.z * this.strafe * st, 0, T.z * ap + T.x * this.strafe * st);
      if (reviveT) { T.set(reviveT.pos.x - f.pos.x, 0, reviveT.pos.z - f.pos.z); const dd = T.length(); if (dd > 6) GOAL.copy(T.divideScalar(dd)); else GOAL.set(0, 0, 0); }
      else if (role === 'pat') {
        const ht = healTarget(this.G, f, 60);
        if (ht && ht !== f && ht.hp / ht.maxHp < 0.6 && dist2(ht.pos, f.pos) > 26) { T.set(ht.pos.x - f.pos.x, 0, ht.pos.z - f.pos.z).normalize(); GOAL.copy(T); }
      }
    }
    // не толпиться (лучи бьют по линии)
    for (const o of G.humans) {
      if (o === f || o.dead) continue;
      const d = dist2(f.pos, o.pos);
      if (d < 4.5 && d > 0.01) { GOAL.x += ((f.pos.x - o.pos.x) / d) * 0.6; GOAL.z += ((f.pos.z - o.pos.z) / d) * 0.6; }
    }
    // от стен
    const L = ARENA_HALF - 5;
    if (f.pos.x > L) GOAL.x -= 1; if (f.pos.x < -L) GOAL.x += 1; if (f.pos.z > L) GOAL.z -= 1; if (f.pos.z < -L) GOAL.z += 1;
    if (urgent) { ESC.addScaledVector(GOAL, 0.15); f.moveDir.copy(ESC); } else f.moveDir.copy(GOAL);
    const ml = f.moveDir.length();
    if (ml > 1) f.moveDir.divideScalar(ml);
    else if (ml > 0.05 && ml < 0.5 && !urgent) f.moveDir.multiplyScalar(0.5 / ml * Math.min(1, ml * 4));
    if (stop && !urgent) f.moveDir.set(0, 0, 0);
    if (keepMoving && f.moveDir.lengthSq() < 0.5) f.moveDir.set(-T.z * this.strafe || this.strafe, 0, T.x * this.strafe || 0).normalize();

    if (dash && f.ready('dash')) humanDash(G, f, this.dashDir);
    if (jump && f.onGround) f.jump();
    if (!m || m.dead) return;
    // атака
    const d = dist2(f.pos, m.pos) - m.radius;
    this.m1Gap -= dt;
    if (!urgent && !stop && !keepMoving && d < RANGE[role] + 0.2 && this.m1Gap <= 0 && f.canAct()) {
      if (humanM1(G, f)) this.m1Gap = rand(0, 0.25) * (1.2 - this.skill);
    }
    this.think -= dt;
    if (this.think > 0 || urgent || stop || keepMoving || !f.canAct()) return;
    this.think = rand(0.2, 0.45);
    const broken = G.time < m.brokenUntil || m.stunned, lowDodge = broken || m.dodge < 34;
    const S = (i) => f.ready('s' + (i + 1)) && humanSkill(G, f, i);
    if (role === 'det') {
      if (d < 7 && lowDodge && S(2)) return;
      if (d < 4.6 && m.dodge > 25 && !broken && S(1)) return;
      if (d > 6 && d < 15 && S(0)) return;
    } else if (role === 'brv') {
      const weak = G.humans.find((h) => !h.dead && h !== f && h.hp / h.maxHp < 0.4 && dist2(h.pos, m.pos) < 14);
      if ((weak || Math.random() < 0.06) && d < 25 && S(1)) return;
      if (d < 8 && (lowDodge || Math.random() < 0.2) && S(2)) return;
      if (d > 5 && d < 16 && S(0)) return;
    } else if (role === 'jus') {
      if (d < 6.5 && S(2)) return;
      if (d < 45 && lowDodge && S(0)) return;
      if (d < 14 && m.dodge >= 12 && S(1)) return;
    } else if (role === 'pat') {
      if (canRevive(G, f) && S(2)) return;
      const ht = healTarget(G, f);
      if (ht && ht.hp / ht.maxHp < 0.78 && S(0)) return;
      const near = G.humans.filter((h) => !h.dead && dist2(h.pos, f.pos) < 15).length;
      if (near >= 2 && (m.action?.name === 'ult' || G.humans.some((h) => !h.dead && h.hp / h.maxHp < 0.55)) && S(1)) return;
    }
  }
}

export class MonsterBrain {
  constructor(G, m) {
    this.G = G; this.m = m;
    this.skill = clamp(m.bot?.skill ?? 0.75, 0.55, 0.95);
    this.next = rand(1.5, 2.5); this.target = null; this.retarget = 0; this.strafe = 1; this.strafeT = 2;
  }
  pickTarget() {
    const G = this.G, m = this.m;
    const taunt = G.humans.find((h) => !h.dead && G.time < h.tauntUntil && dist2(h.pos, m.pos) < 45);
    if (taunt) return taunt;
    let best = null, bs = 1e9;
    for (const h of G.humans) {
      if (h.dead) continue;
      const s = dist2(h.pos, m.pos) + (h.hp / h.maxHp) * 18 + (h.roleId === 'pat' ? -6 : 0) + (h === this.target ? -5 : 0) + Math.random() * 6;
      if (s < bs) { bs = s; best = h; }
    }
    return best;
  }
  update(dt) {
    const G = this.G, m = this.m;
    m.moveDir.set(0, 0, 0);
    if (m.dead || G.state !== 'fight') return;
    this.retarget -= dt;
    if (this.retarget <= 0 || !this.target || this.target.dead || (G.time < (this.taunter?.tauntUntil ?? 0))) {
      this.target = this.pickTarget(); this.retarget = rand(1.2, 2.2);
      this.taunter = this.target && G.time < this.target.tauntUntil ? this.target : null;
    }
    const t = this.target;
    if (!t) return;
    const d = dist2(m.pos, t.pos);
    // толпа вокруг
    let crowd = 0; const cen = T.set(0, 0, 0);
    for (const h of G.humans) if (!h.dead && dist2(h.pos, m.pos) < 8.5) { crowd++; cen.add(h.pos); }
    if (crowd) cen.divideScalar(crowd);
    // движение
    this.strafeT -= dt; if (this.strafeT <= 0) { this.strafe = -this.strafe; this.strafeT = rand(1.5, 3.5); }
    const want = t.hp < 40 || crowd >= 1 || this.taunter ? 3.2 : 10;
    GOAL.set(t.pos.x - m.pos.x, 0, t.pos.z - m.pos.z).divideScalar(Math.max(0.1, d));
    const ap = clamp((d - want) / 4, -1, 1);
    m.moveDir.set(GOAL.x * ap - GOAL.z * this.strafe * 0.45, 0, GOAL.z * ap + GOAL.x * this.strafe * 0.45);
    if (m.moveDir.lengthSq() > 1) m.moveDir.normalize();
    // уйти из толпы телепортом
    if (crowd >= 2 && m.dodge < 45 && m.ready('dash') && !m.busy) {
      ESC.set(m.pos.x - cen.x, 0, m.pos.z - cen.z);
      if (ESC.lengthSq() < 0.1) ESC.set(Math.random() - 0.5, 0, Math.random() - 0.5);
      ESC.normalize();
      ESC.x -= m.pos.x / ARENA_HALF * 0.8; ESC.z -= m.pos.z / ARENA_HALF * 0.8;
      if (Math.random() < 0.6) { monsterTeleport(G, m, ESC); return; }
    }
    // атаки
    this.next -= dt;
    if (this.next <= 0 && m.canAct()) {
      const opts = [];
      if (m.ult >= 100 && (m.hp < m.maxHp * 0.65 || G.roundLeft < 75)) opts.push(['ult', 100]);
      if (m.ready('s3') && d < 34) opts.push(['grav', crowd >= 2 ? 0.4 : 1.3]);
      if (m.ready('s1')) opts.push(['blast', 1.6]);
      if (m.ready('s2')) opts.push(['bones', crowd >= 2 ? 2.4 : d < 30 ? 1.0 : 0.2]);
      let sum = opts.reduce((a, o) => a + o[1], 0), r = Math.random() * sum, pick = null;
      for (const o of opts) { r -= o[1]; if (r <= 0) { pick = o[0]; break; } }
      let ok = false;
      if (pick === 'ult') ok = castUlt(G, m);
      else if (pick === 'grav') ok = castGravity(G, m, t.pos.y < 3 ? t : this.pickTarget());
      else if (pick === 'blast') {
        const list = G.humans.filter((h) => !h.dead).sort((a, b) => (a === t ? -1 : b === t ? 1 : dist2(a.pos, m.pos) - dist2(b.pos, m.pos)));
        ok = castBlasters(G, m, list);
      } else if (pick === 'bones') {
        ESC.set(t.pos.x - m.pos.x, 0, t.pos.z - m.pos.z);
        ok = castBones(G, m, ESC);
      }
      this.next = ok ? rand(0.8, 1.7) * (1.45 - this.skill * 0.6) : 0.3;
    }
    // комбо: гравитация -> бластеры по месту падения
    if (m.ready('s1') && m.canAct()) {
      const g = G.hazards.find((hz) => hz.kind === 'gravity' && hz.owner === m && hz.phase === 'slam');
      if (g && !g.comboed) { g.comboed = true; if (Math.random() < 0.5 + this.skill * 0.4) castBlasters(G, m, [{ pos: g.slamTo, hv: ZERO, dead: false }]); }
    }
    if (d - t.radius < 4.8 && m.canAct() && Math.random() < 0.5) monsterM1(G, m);
  }
}

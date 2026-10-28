// ИИ ботов. Люди: уходят с линий лучей, выбегают из красных квадратов (или перепрыгивают кости),
// уклоняются от брошенных костей, на голубых стенах замирают, белые перепрыгивают; держат дистанцию по роли,
// «ловят» окно после уклонения Судьи, бегут в атаку сразу после «Отталкивания» (оно на 15 с перезарядке),
// едят пироги ниже 40% HP; в интро (пока Судья говорит) расходятся на 20–30 стадов от него и пьют зелья (A5).
// Способность души (R) — по роли.
// Судья: идёт по сценарию по числу уклонений (как NPC-Санс в UJD): сначала бластеры, потом бросок костей,
// на ~60% уклонений — Синяя атака (один раз), дальше зоны и стены костей, на ≤3 — Круг бластеров (один раз).
// «Отталкивание» — когда люди облепили. Ни удара вблизи, ни телепорта.
import * as THREE from 'three';
import { dist2, clamp, clearance, angleTo } from './combat.js';
import { HALL_X, HALL_Z, MELEE } from './data.js';
import { humanM1, humanAbility, usePie, usePotion } from './human.js';
import { castBlaster, castQuad, castBoneZone, castBoneThrow, castBoneWall, castForce, castBlue, castCircle } from './monster.js';

const rand = (a, b) => a + Math.random() * (b - a);
const ESC = new THREE.Vector3(), GOAL = new THREE.Vector3(), T = new THREE.Vector3(), AIM = new THREE.Vector3();

const PREF = { det: 3.0, brv: 2.8, pat: 3.2, jus: 20 };
const MELEE_R = MELEE.reach + 1.5 * 0.6 - 0.4;
const RANGE = { det: MELEE_R, brv: MELEE_R, pat: MELEE_R, jus: 45 };

export class HumanBrain {
  constructor(G, f) {
    this.G = G; this.f = f;
    this.skill = clamp(f.bot?.skill ?? 0.7, 0.3, 0.98);
    this.react = 0.12 + (1 - this.skill) * 0.5; // ветеран ~0.13 с, новичок ~0.45 с (§6.2)
    this.seen = new WeakMap();
    this.strafe = Math.random() < 0.5 ? 1 : -1; this.strafeT = rand(1.5, 4);
    this.m1Gap = 0; this.think = rand(0, 0.3);
    this.jumpJit = rand(-0.05, 0.05);
    // ритм «ждёт момента — подбежал, ударил 1–3 раза — отошёл»; одновременно в атаке не больше двух ботов
    this.mode = 'hold'; this.modeT = rand(0.5, 3); this.engageEnd = 0; this.holdSince = 0;
    this.hits = 0; this.burst = this.newBurst(); this.seenDodge = -1; this.backDist = rand(12, 17); this.holdDist = rand(10, 15);
    this.pieAt = rand(0.36, 0.4); this.potionPlan = rand(0, 1);
    this.spot = null; this.potT = 0;
  }
  newBurst() { return Math.random() < 0.6 ? 1 : Math.random() < 0.75 ? 2 : 3; }
  // сколько ботов могут одновременно лезть к Судье: обычно один, под конец — двое, на последнем уклонении — все;
  // сразу после «Отталкивания» (оно на перезарядке) — все
  maxEngaged(m) {
    if (m.cdLeft('force') > 6 && this.skill > 0.5) return 3;
    return m.dodges <= 1 ? 4 : m.dodges <= 4 ? 2 : 1;
  }
  // заметил ли бот опасность. В атаке — «туннельное зрение»: реагирует позже, иногда не замечает вовсе
  note(hz) {
    let s = this.seen.get(hz);
    if (!s) {
      const greedy = this.mode === 'engage';
      const miss = Math.random() > 0.5 + this.skill * 0.42 - (greedy ? 0.35 : 0);
      const blind = miss && Math.random() < (greedy ? 0.55 : 0.2);
      s = { t: this.G.time, delay: blind ? 99 : this.react * rand(0.7, 1.3) * (greedy ? 1.6 : 1) + (miss ? rand(0.4, 0.9) : 0),
        // новички в 30% случаев путают правило синих
        rule: this.skill > 0.6 || Math.random() > 0.3 };
      this.seen.set(hz, s);
    }
    return this.G.time - s.t >= s.delay ? s : null;
  }
  // сторона уклонения поперёк линии (nx,nz): туда, где больше места
  sideFor(nx, nz, pref) {
    const f = this.f, a = clearance(f.pos.x + nx * 6, f.pos.z + nz * 6), b = clearance(f.pos.x - nx * 6, f.pos.z - nz * 6);
    if (Math.abs(a - b) < 1) return pref;
    return a > b ? 1 : -1;
  }
  // Интро: встать на своё место (веером поперёк зала, 20–30 стадов от Судьи; Справедливость — дальше),
  // выпить зелье, пока Судья договаривает. Новички от скуки прыгают на месте.
  intro(dt) {
    const f = this.f, G = this.G, m = G.monster;
    if (!m) return;
    if (!this.spot) {
      const idx = G.humans.indexOf(f), n = G.humans.length, side = Math.sign(f.pos.z - m.pos.z) || 1;
      const x = clamp((idx - (n - 1) / 2) * 11 + rand(-3, 3), -HALL_X + 5, HALL_X - 5);
      const dz = f.roleId === 'jus' ? rand(30, 38) : rand(20, 30);
      this.spot = new THREE.Vector3(x, 0, clamp(m.pos.z + side * dz, -HALL_Z + 6, HALL_Z - 6));
      this.potT = rand(1.0, 5.5) * (1.4 - this.skill * 0.6);
    }
    const dx = this.spot.x - f.pos.x, dz = this.spot.z - f.pos.z, d = Math.hypot(dx, dz);
    if (d > 1.2) f.moveDir.set(dx / d, 0, dz / d).multiplyScalar(Math.min(1, d / 3));
    else {
      f.faceTo(m.pos);
      if (f.onGround && Math.random() < dt * 0.35 * (1 - this.skill)) f.jump();
    }
    this.potT -= dt;
    if (this.potT <= 0 && f.potion && this.potionPlan < 0.85 && !f.busy) usePotion(G, f);
  }
  update(dt) {
    const f = this.f, G = this.G;
    f.moveDir.set(0, 0, 0);
    if (f.dead || f.flung) return;
    if (G.state === 'intro') { this.intro(dt); return; }
    if (G.state !== 'fight') return;
    const m = G.monster;
    ESC.set(0, 0, 0); GOAL.set(0, 0, 0);
    let urgent = false, jump = false, stop = false, blueOn = false;
    for (const hz of G.hazards) {
      if (hz.kind === 'blaster') {
        if (!hz.dangerous() || !this.note(hz)) continue;
        const rx = f.pos.x - hz.origin.x, rz = f.pos.z - hz.origin.z;
        const along = rx * hz.dir2.x + rz * hz.dir2.z;
        if (along < hz.a0 - 3 || along > hz.a1) continue;
        const cross = rx * hz.dir2.z - rz * hz.dir2.x, need = hz.w0 / 2 + f.radius + 1.4;
        if (Math.abs(cross) > need) continue;
        const px = hz.dir2.z, pz = -hz.dir2.x;
        const side = this.sideFor(px, pz, Math.sign(cross) || this.strafe);
        const w = 1 + (need - Math.abs(cross));
        ESC.x += px * side * w * 3; ESC.z += pz * side * w * 3;
        urgent = true;
        // горизонтальный луч уже бьёт, а выйти не успеваем — прыжок (ноги выше центра луча)
        if (hz.timeToFire() < 0 && !hz.quad && Math.abs(cross) < hz.r + f.radius && this.skill > 0.5) jump = true;
      } else if (hz.kind === 'zone') {
        if (hz.t < 0 || !this.note(hz)) continue;
        const dx = f.pos.x - hz.c.x, dz = f.pos.z - hz.c.z, pad = f.radius + 0.9;
        const inX = hz.hs + pad - Math.abs(dx), inZ = hz.hs + pad - Math.abs(dz);
        if (inX <= 0 || inZ <= 0) {
          if (inX > -3 && inZ > -3) { T.set(dx, 0, dz).normalize(); GOAL.addScaledVector(T, 0.6); }
          continue;
        }
        // выходим по ближайшей оси, но не в стену
        let ax = inX < inZ;
        if (ax && Math.abs(f.pos.x + Math.sign(dx || this.strafe) * inX) > HALL_X - 2) ax = false;
        if (!ax && Math.abs(f.pos.z + Math.sign(dz || this.strafe) * inZ) > HALL_Z - 2) ax = true;
        if (ax) ESC.x += Math.sign(dx || this.strafe) * 4; else ESC.z += Math.sign(dz || this.strafe) * 4;
        urgent = true;
        if (hz.up > 0.3 || (hz.timeToPop() < 0.12 && Math.min(inX, inZ) > 1.2)) jump = true;
      } else if (hz.kind === 'throw') {
        if (hz.t < 0 || !this.note(hz)) continue;
        for (const b of hz.bones) {
          if (!b.alive) continue;
          const rx = f.pos.x - b.pos.x, rz = f.pos.z - b.pos.z;
          const along = rx * b.dir.x + rz * b.dir.z;
          if (along < -1 || along > 34) continue;
          const cross = rx * b.dir.z - rz * b.dir.x;
          if (Math.abs(cross) > f.radius + 1.6) continue;
          const tArr = (hz.launched ? 0 : hz.hover - hz.t) + along / hz.speed;
          if (tArr > 0.85) continue;
          if (b.type === 1 && this.seen.get(hz).rule) { stop = true; continue; }
          const px = b.dir.z, pz = -b.dir.x, side = this.sideFor(px, pz, Math.sign(cross) || this.strafe);
          ESC.x += px * side * 3; ESC.z += pz * side * 3; urgent = true;
        }
      } else if (hz.kind === 'row') {
        if (hz.t < 0 || hz.riseK <= 0 || !this.note(hz)) continue;
        const cx = hz.origin.x + hz.dir.x * hz.s, cz = hz.origin.z + hz.dir.z * hz.s;
        const rx = f.pos.x - cx, rz = f.pos.z - cz;
        const along = rx * hz.dir.x + rz * hz.dir.z, across = rx * hz.perp.x + rz * hz.perp.z;
        const look = hz.speed > 30 ? hz.speed * 0.45 : 11;
        if (Math.abs(across) > hz.halfW + 1.5 || along < -1.3 || along > look) continue;
        const rule = this.seen.get(hz).rule;
        if (hz.type === 1 && rule) { stop = true; continue; }    // голубые: замереть
        if (hz.type !== 0) continue;
        if (!hz.moving) { if (along < 3) { ESC.addScaledVector(hz.dir, 2); urgent = true; if (along < 1.3) jump = true; } continue; }
        const tArr = (along - 1.1) / hz.speed;
        if (tArr < 0.17 + this.jumpJit) jump = true;         // белые: перепрыгнуть
      } else if (hz.kind === 'blueatk') blueOn = true;
    }
    const role = f.roleId;
    this.strafeT -= dt; if (this.strafeT <= 0) { this.strafe = -this.strafe; this.strafeT = rand(1.5, 4); }
    // счёт своих попаданий (каждое — «MISS» у Судьи) и смена режима: ждёт → атакует → отходит
    const now = G.time;
    if (m && !m.dead) {
      if (m.lastDodgeSrc === f && m.lastDodgeAt !== this.seenDodge) { this.seenDodge = m.lastDodgeAt; this.hits++; }
      if (this.mode === 'engage') {
        if (this.hits >= this.burst || now > this.engageEnd) {
          this.mode = 'retreat'; this.modeT = now + rand(2.5, 4.5) * (role === 'jus' ? 1.3 : 1);
          this.hits = 0; this.burst = this.newBurst(); this.backDist = rand(12, 18);
        }
      } else if (this.mode === 'retreat') {
        if (now > this.modeT) { this.mode = 'hold'; this.holdSince = now; this.modeT = now + rand(3.5, 7.5) * (1.3 - this.skill * 0.5); this.holdDist = rand(10, 15); } // пауза между заходами: раунд 1–3 мин, как в UJD
      } else {
        // окно: Судья только что начал атаку, «Отталкивание» на перезарядке, или надоело ждать
        const opening = (m.busy && this.skill > 0.7 && now - this.holdSince > 1.5) || (m.cdLeft('force') > 8 && this.skill > 0.55);
        let engaged = 0;
        for (const b of G.brains.values()) if (b !== this && b.mode === 'engage') engaged++;
        if ((now > this.modeT || opening) && engaged < this.maxEngaged(m) && f.hp / f.maxHp >= 0.3 && !blueOn) {
          this.mode = 'engage'; this.engageEnd = now + rand(2.5, 4); this.hits = 0;
          // зелье пьют в начале схватки (лечебное — когда ранен)
          if (f.potion && f.potion !== 'heal' && this.potionPlan < 0.85) usePotion(G, f);
        }
      }
    }
    const retreat = this.mode !== 'engage';
    if (m && !m.dead) {
      const d = dist2(f.pos, m.pos);
      T.set(m.pos.x - f.pos.x, 0, m.pos.z - f.pos.z).divideScalar(Math.max(0.1, d));
      let want = PREF[role];
      if (this.mode === 'retreat') want = role === 'jus' ? 26 : this.backDist;
      else if (this.mode === 'hold') want = role === 'jus' ? 24 : this.holdDist;
      if (f.hp / f.maxHp < 0.3 && role !== 'brv') want = 24;
      // опытные не лезут в «окно неуязвимости» после уклонения — чуть отходят и заходят снова
      if (this.skill > 0.75 && G.time < m.iframeUntil - 0.15 && role !== 'jus') want += 1.5;
      const diff = d - m.radius - want;
      const ap = clamp(diff / 3, -1, 1);
      const st = retreat ? 0.8 : role === 'jus' ? 0.6 : 0.35;
      GOAL.x += T.x * ap - T.z * this.strafe * st; GOAL.z += T.z * ap + T.x * this.strafe * st;
      // Терпение между заходами стоит на месте — лечится (пассивка души)
      if (role === 'pat' && retreat && f.hp < f.maxHp * 0.9 && Math.abs(diff) < 6) GOAL.set(0, 0, 0);
    }
    // не толпиться (лучи бьют по линии)
    for (const o of G.humans) {
      if (o === f || o.dead) continue;
      const d = dist2(f.pos, o.pos);
      if (d < 4.5 && d > 0.01) { GOAL.x += ((f.pos.x - o.pos.x) / d) * 0.6; GOAL.z += ((f.pos.z - o.pos.z) / d) * 0.6; }
    }
    // от стен зала
    if (f.pos.x > HALL_X - 4) GOAL.x -= 1; if (f.pos.x < -HALL_X + 4) GOAL.x += 1;
    if (f.pos.z > HALL_Z - 5) GOAL.z -= 1; if (f.pos.z < -HALL_Z + 5) GOAL.z += 1;
    // во время Синей атаки опытные почти не двигаются
    if (blueOn && !urgent && this.skill > 0.45) GOAL.multiplyScalar(0.35);
    if (urgent) { ESC.addScaledVector(GOAL, 0.15); f.moveDir.copy(ESC); } else f.moveDir.copy(GOAL);
    const ml = f.moveDir.length();
    if (ml > 1) f.moveDir.divideScalar(ml);
    else if (ml > 0.05 && ml < 0.5 && !urgent) f.moveDir.multiplyScalar(0.5 / ml * Math.min(1, ml * 4));
    if (stop && !urgent) f.moveDir.set(0, 0, 0);
    if (jump && f.onGround) f.jump();

    // предметы: пирог на малом HP, зелье лечения — когда ранен
    if (!f.busy) {
      if (f.pies > 0 && f.hp / f.maxHp < this.pieAt && Math.random() < dt * 3) { if (usePie(G, f)) return; }
      if (f.potion === 'heal' && f.hp / f.maxHp < 0.5 && usePotion(G, f)) return;
      if (f.potion && (f.hp / f.maxHp < 0.35 || G.roundLeft < 200) && Math.random() < dt * 0.5 && usePotion(G, f)) return;
    }
    if (!m || m.dead) return;
    // атака: опытные ждут конца неуязвимости Судьи, новички бьют как попало
    const d = dist2(f.pos, m.pos);
    this.m1Gap -= dt;
    const waitIF = this.skill > 0.7 && G.time < m.iframeUntil - 0.06;
    // Справедливость стреляет в основном в своём заходе; между заходами — редко, когда Судья занят атакой
    const shooter = role === 'jus' && f.ammo > 0;
    const shootOk = shooter && (!retreat || (m.busy && Math.random() < dt * 0.35));
    if (!urgent && !stop && (!retreat || shootOk) && !waitIF && d < RANGE[role] + (shooter ? 0 : 0.2) && this.m1Gap <= 0 && f.canAct()) {
      if (!shooter && angleTo(f, m.pos) > 0.9) f.faceTo(m.pos, true);
      if (humanM1(G, f)) this.m1Gap = shooter ? rand(0.6, 1.3) * (1.4 - this.skill * 0.5) : rand(0, 0.25) * (1.2 - this.skill);
    }
    this.think -= dt;
    if (this.think > 0 || urgent || stop || !f.canAct() || !f.ready('R')) return;
    this.think = rand(0.25, 0.5);
    // способность души. Не снимает последнее уклонение — на последнем добиваем только в ближнем бою
    const canSkill = m.dodges > 1 && !waitIF;
    const front = angleTo(f, m.pos) < 0.8 || !retreat;
    if (role === 'pat' && canSkill && !retreat && d < 15 && d > 3 && front) humanAbility(G, f);
    else if (role === 'brv' && canSkill && d > 7 && d < 45) humanAbility(G, f);
    else if (role === 'jus' && (f.ammo === 0 || (f.ammo <= 2 && retreat))) humanAbility(G, f);
  }
}

export class MonsterBrain {
  constructor(G, m) {
    this.G = G; this.m = m;
    this.skill = clamp(m.bot?.skill ?? 0.75, 0.55, 0.95);
    this.next = rand(1.2, 2.0); this.target = null; this.retarget = 0; this.strafe = 1; this.strafeT = 2;
    this.blueDone = false; this.circleDone = false; this.fightT = 0;
  }
  pickTarget() {
    const G = this.G, m = this.m;
    let best = null, bs = 1e9;
    for (const h of G.humans) {
      if (h.dead) continue;
      const s = dist2(h.pos, m.pos) + (h.hp / h.maxHp) * 18 + (h === this.target ? -5 : 0) + (h.isPlayer ? -6 : 0) + Math.random() * 6;
      if (s < bs) { bs = s; best = h; }
    }
    return best;
  }
  // линия бластера, на которую попадёт больше всего людей (луч идёт от Судьи через цель)
  bestBlastAim(t) {
    const G = this.G, m = this.m;
    let best = t, bn = -1;
    for (const h of G.humans) {
      if (h.dead) continue;
      AIM.copy(h.pos).addScaledVector(h.hv, 0.8);
      const dx = AIM.x - m.pos.x, dz = AIM.z - m.pos.z, l = Math.hypot(dx, dz) || 1;
      let n = h === t ? 0.5 : 0;
      for (const o of G.humans) {
        if (o.dead) continue;
        const rx = o.pos.x - m.pos.x, rz = o.pos.z - m.pos.z;
        if ((rx * dx + rz * dz) / l < 2) continue;
        if (Math.abs(rx * dz - rz * dx) / l < 2.8) n++;
      }
      if (n > bn) { bn = n; best = h; }
    }
    return AIM.copy(best.pos).addScaledVector(best.hv, 0.8);
  }
  update(dt) {
    const G = this.G, m = this.m;
    m.moveDir.set(0, 0, 0);
    if (m.dead || G.state !== 'fight') return;
    this.fightT += dt;
    this.retarget -= dt;
    if (this.retarget <= 0 || !this.target || this.target.dead) { this.target = this.pickTarget(); this.retarget = rand(1.2, 2.2); }
    const t = this.target;
    if (!t) return;
    const d = dist2(m.pos, t.pos);
    // кто рядом
    let crowd = 0, near = 1e9;
    for (const h of G.humans) { if (h.dead) continue; const dd = dist2(h.pos, m.pos); if (dd < 7.5) crowd++; if (dd < near) near = dd; }
    // движение (§6.1): держит людей на 15–30 стадах, пятится вдоль коридора и стрейфит, не жмётся к стенам
    this.strafeT -= dt; if (this.strafeT <= 0) { this.strafe = -this.strafe; this.strafeT = rand(1.5, 3.5); }
    ESC.set(0, 0, 0);
    for (const h of G.humans) {
      if (h.dead) continue;
      const dx = m.pos.x - h.pos.x, dz = m.pos.z - h.pos.z, dd = Math.hypot(dx, dz) || 0.1;
      if (dd < 24) { const w = (24 - dd) / 24; ESC.x += (dx / dd) * w; ESC.z += (dz / dd) * w; }
    }
    const jus = G.humans.some((h) => !h.dead && h.roleId === 'jus' && dist2(h.pos, m.pos) < 40);
    const keep = 15 + (1 - this.skill) * 4 + (jus ? 5 : 0);
    if (near < keep && ESC.lengthSq() > 0.01) {
      // отход: в основном вдоль зала, у торца — вдоль стены в обход
      ESC.normalize(); ESC.z *= 1.4;
      if (Math.abs(m.pos.z) > HALL_Z - 14 && Math.sign(ESC.z) === Math.sign(m.pos.z)) { ESC.z *= -0.3; ESC.x += (m.pos.x >= 0 ? -1 : 1) * 0.3 + this.strafe * 0.8; }
      m.moveDir.set(ESC.x + -ESC.z * this.strafe * 0.25, 0, ESC.z + ESC.x * this.strafe * 0.25);
    } else {
      GOAL.set(t.pos.x - m.pos.x, 0, t.pos.z - m.pos.z).divideScalar(Math.max(0.1, d));
      const ap = clamp((d - keep - 8) / 6, -0.6, 0.8);
      m.moveDir.set(GOAL.x * ap - GOAL.z * this.strafe * 0.5, 0, GOAL.z * ap + GOAL.x * this.strafe * 0.5);
    }
    if (Math.abs(m.pos.x) > HALL_X - 8) m.moveDir.x -= Math.sign(m.pos.x) * 0.7;
    if (Math.abs(m.pos.z) > HALL_Z - 8) m.moveDir.z -= Math.sign(m.pos.z) * 0.7;
    if (m.moveDir.lengthSq() > 1) m.moveDir.normalize();
    if (!m.canAct()) return;
    // «Отталкивание»: люди облепили (≥2 в 7 стадах) или зажали в углу сразу после уклонения
    const cornered = near < 5 && clearance(m.pos.x, m.pos.z, 8) < 6;
    if (m.ready('force') && (crowd >= 2 || (cornered && G.time - m.lastDodgeAt < 1.5) || (crowd >= 1 && m.dodges <= 3 && G.time - m.lastDodgeAt < 0.8))) {
      if (Math.random() < 0.08 + this.skill * 0.12 && castForce(G, m)) { this.next = Math.max(this.next, 0.4); return; }
    }
    // атаки по сценарию уклонений; между кастами — пауза
    this.next -= dt;
    if (this.next > 0) return;
    const dg = m.dodges, opts = [];
    const blueNow = G.hazards.some((hz) => hz.kind === 'blueatk');
    // Круг бластеров — один раз, когда уклонений ≤ 3
    if (!this.circleDone && dg <= 3 && m.ready('circle')) {
      const tg = this.pickTarget();
      if (tg && castCircle(G, m, tg)) { this.circleDone = true; this.next = rand(1.0, 1.6); return; }
    }
    // Синяя атака — один раз за раунд, на ~60% уклонений (или если бой затянулся)
    if (!this.blueDone && m.ready('blue') && (dg <= 9 || this.fightT > 110) && !blueNow) {
      if (castBlue(G, m)) { this.blueDone = true; this.next = rand(0.8, 1.4); return; }
    }
    // во время Синей атаки — наказать тех, кто замер, быстрой атакой
    let tgt = t;
    // кто сейчас бьёт/стреляет (занят действием) — предсказуемее, по нему и бьём
    const busy = G.humans.find((h) => !h.dead && h.busy && dist2(h.pos, m.pos) < 40);
    if (busy && Math.random() < 0.6) tgt = busy;
    if (blueNow) { const still = G.humans.find((h) => !h.dead && h.hspeed() < 1 && dist2(h.pos, m.pos) < 45); if (still) tgt = still; }
    const dt2 = dist2(m.pos, tgt.pos);
    if (dg >= 13) {
      if (m.ready('blast')) opts.push(['blast', 2.2]);
      if (m.ready('throw') && dt2 < 40 && dg <= 14) opts.push(['throw', 0.8]);
      if (m.ready('quad') && dt2 < 55) opts.push(['quad', 0.35]);
    } else if (dg >= 10) {
      if (m.ready('blast')) opts.push(['blast', 1.6]);
      if (m.ready('throw') && dt2 < 40) opts.push(['throw', 1.3]);
      if (m.ready('zone') && dt2 < 45) opts.push(['zone', 0.9]);
      if (m.ready('quad') && dt2 < 55) opts.push(['quad', 0.6]);
    } else {
      if (m.ready('blast')) opts.push(['blast', dg <= 3 ? 1.8 : 1.2]);
      if (m.ready('zone') && dt2 < 45) opts.push(['zone', 1.4]);
      if (m.ready('wall') && dt2 < 26) opts.push(['wall', crowd >= 1 ? 1.4 : 0.9]);
      if (m.ready('throw') && dt2 < 40) opts.push(['throw', blueNow ? 2 : 1.0]);
      if (m.ready('quad') && dt2 < 55) opts.push(['quad', 0.8]);
    }
    let sum = opts.reduce((a, o) => a + o[1], 0), r = Math.random() * sum, pick = null;
    for (const o of opts) { r -= o[1]; if (r <= 0) { pick = o[0]; break; } }
    let ok = false;
    if (pick === 'blast') ok = castBlaster(G, m, blueNow ? AIM.copy(tgt.pos) : this.bestBlastAim(tgt));
    else if (pick === 'quad') ok = castQuad(G, m, AIM.copy(tgt.pos).addScaledVector(tgt.hv, 0.55));
    else if (pick === 'zone') ok = castBoneZone(G, m, AIM.copy(tgt.pos).addScaledVector(tgt.hv, 0.75));
    else if (pick === 'throw') ok = castBoneThrow(G, m, AIM.copy(tgt.pos).addScaledVector(tgt.hv, dt2 / 60 + 0.35));
    else if (pick === 'wall') ok = castBoneWall(G, m, tgt.pos);
    this.next = ok ? rand(0.5, 1.3) * (1.45 - this.skill * 0.6) : 0.3;
  }
}

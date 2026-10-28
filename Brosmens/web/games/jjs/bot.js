// Мозг бота — играет как живые игроки JJS (спека §6):
//  • стиль по характеру (bot.persona): M1-спамер / блокер / бегун-кайтер / трайхардер; реакция 180–350 мс по скиллу;
//  • комбо-строки персонажей (Сегодня: 3 M1 → апперкот → Twofold → Rapid → Red → Blue → Limitless; Сосуд: M1 → Cursed
//    Strikes → 3 M1 → Crushing Blow; История: 3 M1 → Cleave → Dismantle → Rush; и т.д.);
//  • вход фронтальным рывком с 12–25 стадов (~30 %), обход блока боковым рывком и удар в спину, наказание за
//    заблокированный M1, умный блок (не блокирует неблокируемое и удары вниз), уклонение (новички — сразу, сильные —
//    копят под долгую заминку врага), «третья сторона» — 20–35 % вмешаться в чужую драку и украсть килл;
//  • пробуждение при полной шкале (HP < 60 % или враг ≤ 30), домен — только по лежачему или без уклонения;
//    внутри чужой Гробницы — блок/атака кастера, на каст домена — сбить печать или убежать;
//  • отступление на низком HP с репликой, месть убийце после возрождения, «направленное влияние» в полёте.
import * as THREE from 'three';
import { G } from './ctx.js';
import { rand, pick } from './util.js';

const RANGED_THREATS = new Set(['purple', 'love', 'open', 'furnace', 'red', 'redmax', 'lblue', 'bluemax', 'sdismantle', 'dismantle', 'dismantleAir', 'wcs', 'kai', 'rush', 'elbow']);
// приёмы ближнего боя, которые нельзя (или бесполезно) блокировать спереди
const UNBLOCKABLE = new Set(['rapid', 'twofold', 'crushing', 'cleave', 'rush', 'divergent', 'cstrikesAir', 'elbow', 'resolute', 'limitlessKick', 'rushCombo']);
const MELEE_SKILLS = new Set(['rapid', 'twofold', 'crushing', 'cleave', 'cstrikes', 'divergent', 'severing', 'secondwind', 'elbow', 'rkHay']);

// Комбо-строки: 'm1' — удар, 'up' — 4-й удар с зажатым прыжком (апперкот), 'R' — особый навык, иначе id навыка
const COMBOS = {
  gojo: [['m1', 'm1', 'm1', 'up', 'twofold', 'rapid', 'red', 'lblue', 'R'], ['m1', 'm1', 'm1', 'up', 'rapid', 'lblue', 'red', 'twofold']],
  gojoAw: [['m1', 'm1', 'm1', 'up', 'redmax', 'bluemax', 'R']],
  yuji: [['m1', 'cstrikes', 'm1', 'm1', 'm1', 'crushing'], ['m1', 'm1', 'm1', 'up', 'crushing', 'cstrikes', 'm1', 'm1', 'm1', 'divergent']],
  yujiAw: [['m1', 'm1', 'm1', 'm1', 'dismantle', 'm1', 'm1', 'm1', 'R', 'rush']],
  sukuna: [['m1', 'm1', 'm1', 'R', 'dismantle', 'rush'], ['m1', 'm1', 'm1', 'up', 'sdismantle', 'rush']],
  sukunaAw: [['m1', 'm1', 'm1', 'sdismantleH', 'kamutoke'], ['m1', 'm1', 'm1', 'kamutoke', 'sdismantleH']],
  yuta: [['m1', 'm1', 'm1', 'up', 'severing', 'resolute'], ['m1', 'm1', 'm1', 'secondwind', 'severing']],
  yutaAw: [['m1', 'm1', 'm1', 'elbow', 'R'], ['m1', 'm1', 'm1', 'up', 'ripple']],
};
// Стиль по характеру бота
const STYLES = {
  spammer: { m1: 1.5, block: 0.45, combo: 0.35, fdash: 0.45, keep: 0, retreat: 0.25 },
  blocker: { m1: 0.9, block: 1.6, combo: 0.8, fdash: 0.22, keep: 0, retreat: 0.4 },
  runner: { m1: 0.7, block: 0.8, combo: 0.5, fdash: 0.12, keep: 13, retreat: 0.7 },
  tryhard: { m1: 1.1, block: 1.2, combo: 1.2, fdash: 0.3, keep: 0, retreat: 0.4 },
};
function styleOf(bot, f) {
  if (f.isClaude) return 'tryhard';
  const p = bot?.persona || '';
  if (/новичок|шутник/.test(p)) return 'spammer';
  if (/дружелюб|злишься/.test(p)) return 'blocker';
  if (/лаги|жалуешься/.test(p)) return 'runner';
  if (/про|молчун/.test(p)) return 'tryhard';
  const h = [...p].reduce((a, c) => a + c.charCodeAt(0), 0);
  return ['spammer', 'blocker', 'runner', 'tryhard'][h % 4];
}

export class Brain {
  constructor(f) {
    this.f = f;
    this.skill = f.bot?.skill ?? 0.6;
    this.styleId = styleOf(f.bot, f);
    this.st = STYLES[this.styleId];
    this.target = null;
    this.think = rand(0, 0.3);
    this.strafe = Math.random() < 0.5 ? 1 : -1;
    this.blockT = 0;
    this.mode = 'hunt'; this.modeT = 0;
    this.m1T = 0;
    this.skillT = rand(0.8, 2);
    this.specT = rand(1, 3);
    this.evaT = -1;
    this.tBlockT = 0; this.rikaT = 0;
    this.seen = new WeakSet();
    this.lastPos = new THREE.Vector3(); this.stuckT = 0; this.unstickT = 0; this.unstickX = 0; this.unstickZ = 0;
    // реакция 180–350 мс в зависимости от скилла
    this.reaction = 0.35 - this.skill * 0.17;
    this.jumpT = rand(3, 8);
    this.aggr = rand(0.7, 1.1);
    this.thirdP = rand(0.2, 0.35); this.tpMode = false; this.tpT = rand(1, 3);
    this.engaged = false;
    this.combo = null; this.comboCd = rand(0.5, 2);
    this.punishT = -1; this.punishOn = null;
    this.revenge = null; this.revengeT = 0;
    this.wander = null;
    this.domainFlee = 0;
    this.dbg = { combos: 0, comboDone: 0, fdash: 0, wrap: 0, punish: 0, evasive: 0, steps: 0 };
  }

  // --- внешние события ---
  // заблокировал M1 врага → отпустить блок и ударить в его заминку
  onBlocked(att) { if (this.skill > 0.35 && Math.random() < 0.4 + this.skill * 0.5) { this.punishT = this.reaction * 0.7; this.punishOn = att; } }
  // пойман чужим доменом: в Гробнице — блок на низком HP или атака кастера
  onDomain(D) { if (this.f.isEnemy(D.owner)) { this.target = D.owner; this.combo = null; } }
  onRespawn(killer) {
    this.combo = null; this.mode = 'hunt'; this.blockT = 0;
    if (killer && !killer.dead && Math.random() < 0.55) { this.revenge = killer; this.revengeT = rand(10, 18); }
  }

  update(dt) {
    const f = this.f, inp = f.input;
    inp.mx = 0; inp.mz = 0; inp.jump = false; inp.jumpHeld = false; inp.block = false;
    if (f.dead || G.matchOver) return;
    // складывает печать домена — ничего не трогаем, чтобы не сбить её самим себе
    if (f.action && f.action.kind === 'domain') return;
    // эмоция после убийства: стоим, пока рядом нет врага (любое движение отменит её)
    if (f.action && f.action.name === 'emote') { const t = this.target; if (!t || t.dead || f.dist(t) > 12) return; }
    if (this.revengeT > 0) { this.revengeT -= dt; if (this.revengeT <= 0 || this.revenge?.dead) this.revenge = null; }
    this.tpT -= dt;
    if (this.tpT <= 0) { this.tpT = rand(2.5, 4); this.tpMode = Math.random() < this.thirdP; }
    this.think -= dt;
    if (this.think <= 0) { this.think = rand(0.2, 0.4); this.choose(); }
    // рэгдолл: уклонение (evasive) и «направленное влияние» в полёте
    if (f.rag || f.down > 0) { this.combo = null; this.evasive(dt); this.di(); return; }
    this.evaT = -1;
    // всплеск: если зажали вдвоём — боковой рывок (+10 HP и полная шкала уклонения)
    if (f.burst > 0 && f.burstCd <= 0 && Math.random() < dt * (2 + this.skill * 6)) {
      const s = Math.random() < 0.5 ? 1 : -1;
      inp.mx = -f.aim.z * s; inp.mz = f.aim.x * s;
      if (f.dash()) return;
    }
    if (this.blockT > 0) { this.blockT -= dt; inp.block = true; }
    const t = this.target;
    if (!t || t.dead) { this.roam(dt); return; }
    const dx = t.pos.x - f.pos.x, dz = t.pos.z - f.pos.z;
    const d = Math.hypot(dx, dz) || 0.001;
    const nx = dx / d, nz = dz / d;
    f.aim.set(nx, 0, nz);
    const px = -nz * this.strafe, pz = nx * this.strafe;

    // внутри чужой Гробницы: держать блок на низком HP (разрезы не убивают в блоке)
    const dom = this.domainOf();
    if (dom && dom.kind === 'shrine' && f.isEnemy(dom.owner) && (f.hp < f.maxHp * 0.45 || (d > 14 && Math.random() < 0.5))) {
      inp.block = true; this.blockT = Math.max(this.blockT, 0.3);
      inp.mx = nx * 0.3; inp.mz = nz * 0.3;
      return;
    }
    // кто-то рядом складывает печать домена: трайхарды бегут сбивать, остальные — убегают из радиуса
    const caster = this.domainCaster();
    if (caster && !dom) {
      const cd = f.dist(caster);
      if (this.skill > 0.55 && cd < 22) { this.target = caster; f.aim.set((caster.pos.x - f.pos.x) / cd, 0, (caster.pos.z - f.pos.z) / cd); inp.mx = (caster.pos.x - f.pos.x) / cd; inp.mz = (caster.pos.z - f.pos.z) / cd; if (cd > 9 && f.fdashCd <= 0) f.dash(); else if (cd < 6) f.m1(); this.unstick(dt); return; }
      if (cd < 42) { inp.mx = (f.pos.x - caster.pos.x) / cd; inp.mz = (f.pos.z - caster.pos.z) / cd; if (f.sdashCd <= 0 && Math.random() < dt * 3) f.dash(); this.unstick(dt); return; }
    }

    if (this.mode === 'retreat') {
      this.modeT -= dt;
      inp.mx = -nx * 0.95 + px * 0.35; inp.mz = -nz * 0.95 + pz * 0.35;
      if (d < 9 && f.sdashCd <= 0 && Math.random() < dt * 2) f.dash();
      if (this.modeT <= 0 || d > 38 || f.hp > 55) this.mode = 'hunt';
      this.unstick(dt);
      return;
    }

    // наказание: отпустить блок и ударить, пока у врага заминка после заблокированного M1
    if (this.punishT >= 0) {
      this.punishT -= dt;
      const a = this.punishOn;
      if (this.punishT < 0 && a && !a.dead && f.dist(a) < 7.5) {
        this.blockT = 0; inp.block = false;
        if (a.action && (a.action.locked || a.action.name === 'endlag')) { f.faceTo(a.pos); f.m1(); this.m1T = 0.15; this.dbg.punish++; }
      }
      if (this.punishT < -0.6) { this.punishT = -1; this.punishOn = null; }
    }

    if (t.blocking) this.tBlockT += dt; else this.tBlockT = 0;
    this.defend(dt, d, nx, nz);
    if (f.dead) return;

    // комбо-строка в процессе
    if (this.combo) { this.runCombo(dt, t, d, nx, nz); this.unstick(dt); return; }

    // движение (кайтер держит дистанцию и тыкает дальними навыками)
    const keep = this.st.keep && f.hp < f.maxHp * 0.95 ? this.st.keep : this.st.keep * 0.7;
    const melee = 3.2;
    const busyAttack = f.action && (f.action.name === 'm1' || f.action.name === 'fuga');
    if (!inp.block) {
      if (keep && d < keep - 3 && t.stun <= 0 && !t.rag) { inp.mx = -nx * 0.8 + px * 0.5; inp.mz = -nz * 0.8 + pz * 0.5; }
      else if (keep && d < keep + 4 && t.stun <= 0 && !t.rag) { inp.mx = px * 0.8; inp.mz = pz * 0.8; }
      else if (d > melee + 1.2) {
        const s = d > 12 ? 1 : 0.9;
        inp.mx = nx * s + px * 0.18; inp.mz = nz * s + pz * 0.18;
      } else if (d < melee - 1.3) { inp.mx = -nx * 0.5; inp.mz = -nz * 0.5; }
      else { inp.mx = px * 0.35; inp.mz = pz * 0.35; }
    } else { inp.mx = nx * 0.3; inp.mz = nz * 0.3; }
    if (busyAttack) { inp.mx *= 0.3; inp.mz *= 0.3; }

    // вход фронтальным рывком с джебом: при сближении 12–25 стадов ~30 % (по стилю)
    if (d > 28 || d < 8) this.engaged = false;
    else if (!this.engaged && d > 12 && d < 25 && f.fdashCd <= 0 && f.canAct()) {
      this.engaged = true;
      if (Math.random() < this.st.fdash * (f.ch.aiRush ? 1.4 : 1)) { inp.mx = nx; inp.mz = nz; if (f.dash()) this.dbg.fdash++; }
    }

    // цель держит блок > 0.4 с — обойти боковым рывком и бить в спину/бок
    if (this.tBlockT > 0.4 && d < 8 && f.sdashCd <= 0 && (!f.action || (f.action.name === 'm1' && !f.action.locked)) && Math.random() < dt * (3 + 6 * this.skill)) {
      inp.mx = px * 0.85 + nx * 0.55; inp.mz = pz * 0.85 + nz * 0.55;
      if (f.dash()) { f.m1Buf = 0.35; this.tBlockT = 0; this.strafe *= -1; this.dbg.wrap++; }
    }
    // финт (Combat Instincts): отменить замах, если цель блокирует или стоит в контратаке
    const sp = f.specialDef();
    if (sp && sp.instant && f.specCd <= 0 && f.action && f.action.slot != null && f.action.t < (f.action.windup ?? 0.25) && (t.blocking || t.counter > 0) && Math.random() < this.skill * 0.5) f.special();

    // начать комбо-строку: цель рядом и не в блоке
    this.comboCd -= dt;
    if (d < 6.2 && !t.blocking && !t.rag && f.canAct() && f.m1Cd <= 0 && this.comboCd <= 0 && Math.abs(t.pos.y - f.pos.y) < 4) {
      this.comboCd = rand(0.6, 1.4);
      if (Math.random() < (0.25 + this.skill * 0.55) * this.st.combo) this.startCombo();
      if (this.combo) { this.runCombo(dt, t, d, nx, nz); this.unstick(dt); return; }
    }

    // нейтраль: размен M1
    if (this.upper && f.action && f.action.name === 'm1' && f.action.n === 4) inp.jumpHeld = true;
    else if (!f.action) this.upper = false;
    this.m1T -= dt;
    // в держащий блок не долбим M1 — ждём боковой рывок для обхода (умные боты)
    const holdOff = t.blocking && this.tBlockT > 0.25 && f.sdashCd <= 0 && this.skill > 0.4;
    if (d < 6.5 && !inp.block && !holdOff && Math.abs(t.pos.y - f.pos.y) < 4) {
      if (this.m1T <= 0 && (!f.action || f.action.name === 'm1')) {
        if (f.combo === 3 && f.comboT > 0) this.upper = Math.random() < 0.1 + 0.35 * this.skill;
        inp.jumpHeld = !!this.upper && f.combo === 3;
        f.m1();
        this.m1T = (0.2 + rand(0, 0.3) * (1.2 - this.skill)) / this.st.m1;
      }
    } else if (!f.onGround && d < 7 && t.pos.y < f.pos.y - 1 && f.vel.y < 0 && f.combo === 3 && Math.random() < 0.1) f.m1();

    // навыки
    this.skillT -= dt;
    if (this.skillT <= 0 && !f.busy()) {
      this.skillT = rand(0.35, 1.1) * (1.5 - this.skill) / (this.st.keep ? 1.4 : 1);
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

  domainOf() { for (const d of G.domains || []) if (!d.closing && d.caught.has(this.f)) return d; return null; }
  domainCaster() {
    const f = this.f;
    for (const o of G.fighters) if (f.isEnemy(o) && o.action && o.action.kind === 'domain' && f.dist(o) < 44) return o;
    return null;
  }

  roam(dt) {
    const f = this.f, inp = f.input;
    const pts = G.world.roam || G.world.spawns;
    if (!this.wander || Math.hypot(this.wander[0] - f.pos.x, this.wander[1] - f.pos.z) < 5) this.wander = pick(pts);
    const dx = this.wander[0] - f.pos.x, dz = this.wander[1] - f.pos.z, d = Math.hypot(dx, dz) || 1;
    inp.mx = (dx / d) * 0.6; inp.mz = (dz / d) * 0.6;
    this.unstick(dt);
  }

  // «Направленное влияние»: в полёте тянуть в сторону от обидчика (сильные боты)
  di() {
    const f = this.f;
    if (f.onGround || this.skill < 0.5) return;
    const a = f.lastHitBy;
    if (!a || a.dead) return;
    const dx = f.pos.x - a.pos.x, dz = f.pos.z - a.pos.z, l = Math.hypot(dx, dz) || 1;
    f.input.mx = (dx / l) * 0.9 + (-dz / l) * 0.3 * this.strafe; f.input.mz = (dz / l) * 0.9 + (dx / l) * 0.3 * this.strafe;
  }

  // ---------- комбо-строки ----------
  startCombo() {
    const f = this.f;
    const key = f.charId + (f.awakened > 0 ? 'Aw' : '');
    let list = COMBOS[key] || COMBOS[f.charId];
    if (!list) return;
    let steps = pick(list);
    // спамеры и слабые боты — только M1-строка с апперкотом и одним навыком
    if (this.styleId === 'spammer' || this.skill < 0.45) steps = steps.slice(0, Math.min(steps.length, 5));
    if (f.rikaMode === 2) steps = ['m1', 'm1', 'm1', 'up'];
    this.combo = { steps, i: 0, t: 0, wait: 0, m1a: null, sk: null };
    this.dbg.combos++;
  }
  runCombo(dt, t, d, nx, nz) {
    const f = this.f, inp = f.input, c = this.combo;
    c.t += dt;
    const step = c.steps[c.i];
    const abort = () => { this.combo = null; this.comboCd = rand(0.8, 1.6); };
    // пока идёт свой приём (захват, шквал и т.п.) — таймаут шага не тикает
    if (f.action && f.action.name !== 'm1' && f.action.name !== 'land') c.t = 0;
    if (!step) { this.dbg.comboDone++; return abort(); }
    if (t.dead || c.t > 1.6 || f.stun > 0 || f.rag) return abort();
    this.dbg.steps = Math.max(this.dbg.steps, c.i);
    // держаться рядом с целью
    if (d > 3.4) { inp.mx = nx * 0.9; inp.mz = nz * 0.9; } else { inp.mx = nx * 0.15; inp.mz = nz * 0.15; }
    if (c.wait > 0) { c.wait -= dt; return; }
    if (step === 'm1' || step === 'up') {
      if (d > 9 || this.tBlockT > 0.3) return abort();
      if (step === 'up') inp.jumpHeld = true;
      if (f.action && f.action.name === 'm1' && f.action !== c.m1a) { c.m1a = f.action; c.i++; c.t = 0; return; }
      if (step === 'up' && f.combo !== 3 && !(f.action && f.action.name === 'm1')) { c.i++; return; }
      if (f.m1Cd > 0 && !f.action) { c.i++; return; }
      f.m1();
      if (f.action && f.action.name === 'm1' && f.action !== c.m1a) { c.m1a = f.action; c.i++; c.t = 0; }
      return;
    }
    // шаг-навык: ждём конца текущего действия (M1 после попадания можно отменить навыком)
    if (c.sk) {
      if (f.action === c.sk) { inp.mx = inp.mz = 0; return; }
      c.sk = null; c.i++; c.t = 0; c.wait = this.reaction * 0.5;
      return;
    }
    if (f.action && !(f.action.name === 'm1' && f.action.t >= f.action.hitAt) && f.action.name !== 'land') return;
    if (step === 'R') {
      const sk = f.specialDef();
      if (!sk || f.specCd > 0 || (sk.id === 'limitless' && f.awakenPct() < 6)) { c.i++; return; }
      f.faceTo(t.pos);
      if (f.special()) { c.sk = f.action; if (!c.sk) { c.i++; c.wait = 0.2; } } else c.i++;
      return;
    }
    let slot = -1;
    for (let i = 0; i < 4; i++) { const sk = f.skillDef(i); if (sk && sk.id === step) { slot = i; break; } }
    if (slot < 0 || f.cd[slot] > 0) { c.i++; return; }
    const ai = f.skillDef(slot).ai || {};
    if (ai.max != null && d > ai.max + 2) return abort();
    f.faceTo(t.pos);
    if (f.skill(slot)) { c.sk = f.action; if (!c.sk) { c.i++; c.wait = 0.2; } }
    else c.i++;
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
        this.wander = null;
      }
      this.stuckT = 0; this.lastPos.copy(f.pos);
    }
  }

  defend(dt, d, nx, nz) {
    const f = this.f;
    if (f.stun > 0 || f.rag || f.down > 0) return;
    const smart = this.skill > 0.6;
    for (const e of G.fighters) {
      if (!f.isEnemy(e) || !e.action) continue;
      const a = e.action;
      if (this.seen.has(a)) continue;
      const ed = f.dist(e);
      const ex = f.pos.x - e.pos.x, ez = f.pos.z - e.pos.z;
      const facing = ed > 0.01 ? (Math.sin(e.yaw) * ex + Math.cos(e.yaw) * ez) / ed : 1;
      const meleeSkill = MELEE_SKILLS.has(a.name) || UNBLOCKABLE.has(a.name);
      if ((a.kind === 'melee' || meleeSkill) && ed < 9 && facing > 0.4) {
        if (a.t < this.reaction) continue; // ещё не «увидел»
        this.seen.add(a);
        const unblock = UNBLOCKABLE.has(a.name) || (a.name === 'm1' && a.variant === 'slam');
        if (Math.random() > this.skill * 0.85) {
          // «не заметил»: слабые боты иногда блокируют и неблокируемое
          if (unblock && !smart && Math.random() < 0.5) { this.blockT = rand(0.3, 0.6); f.input.block = true; }
          continue;
        }
        if (!f.action || f.action.name === 'm1') {
          // умный блок: от неблокируемого и ударов вниз — уходить рывком, а не блокировать
          if (unblock && smart) {
            if (f.sdashCd <= 0) { f.input.mx = (-ez / ed) * this.strafe; f.input.mz = (ex / ed) * this.strafe; if (f.action) f.interrupt(); f.dash(); }
            continue;
          }
          if (f.sdashCd <= 0 && Math.random() < (0.25 + this.skill * 0.15) / this.st.block) {
            f.input.mx = (-ez / ed) * this.strafe || nx; f.input.mz = (ex / ed) * this.strafe || nz;
            f.dash();
          } else if (Math.random() < Math.min(0.95, (0.35 + this.skill * 0.35) * this.st.block)) {
            if (f.action && f.action.name === 'm1') f.interrupt();
            this.blockT = rand(0.35, 0.9) * (this.styleId === 'blocker' ? 1.4 : 1);
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
      if (!sk) continue;
      const ai = sk.ai || {};
      let ok = false;
      switch (ai.kind) {
        case 'melee': ok = d <= ai.max && (comboExt || t.stun > 0 || Math.random() < 0.45); break;
        case 'ranged': ok = !comboExt && d >= ai.min && d <= ai.max && Math.random() < (t.stun > 0 || t.down > 0 ? 0.9 : this.st.keep ? 0.75 : 0.5); break;
        case 'gap': ok = d >= ai.min && d <= ai.max && (comboExt ? ai.min === 0 : Math.random() < 0.55); break;
        case 'charge': ok = !comboExt && d >= ai.min && d <= ai.max && Math.random() < 0.45; break;
        // домен — только по лежачему или потратившему уклонение, в радиусе 30, на земле и вне чужого домена
        case 'domain': {
          let n = 0; for (const o of G.fighters) if (f.isEnemy(o) && f.dist(o) < 30) n++;
          ok = d <= 30 && f.onGround && !this.domainOf() && (t.rag || t.evasive < 100) && (n >= 2 || t.rag || Math.random() < 0.6);
          break;
        }
        case 'counter': ok = d < ai.max && t.action && (t.action.kind === 'melee' || MELEE_SKILLS.has(t.action.name)) && Math.random() < this.skill; break;
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
    const kind = sk.ai && sk.ai.kind;
    // Проклятый напарник: призвать Рику, переключиться на её приёмы рядом с целью, вернуть свой набор, если затянулось
    if (kind === 'rika') {
      if (f.rikaMode === 0) return f.special();
      if (f.rikaMode === 1) { if (d < 24 && f.cdRk.every((c) => c <= 0) && Math.random() < 0.45) { this.rikaT = 0; return f.special(); } return false; }
      if ((this.rikaT += 1) > 3) return f.special();
      return false;
    }
    // Heian: заклинания, пока есть запас пробуждения
    if (kind === 'chant') {
      if (f.chant >= 3 || f.awakenPct() < 22 || (d < 9 && Math.random() < 0.7)) return false;
      return f.special();
    }
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

  // Уклонение из рэгдолла: слабые (скилл < 0.5) — сразу; сильные — когда враг рядом занят долгим действием или HP низкое
  evasive(dt) {
    const f = this.f;
    if (f.evasive < 100 || f.ragTrue || !f.rag) return;
    if (this.evaT < 0) this.evaT = this.reaction + rand(0.05, 0.25);
    this.evaT -= dt;
    if (this.evaT > 0) return;
    const a = f.lastHitBy;
    let go;
    if (this.skill < 0.5) go = true;
    else go = f.hp < 30 || (a && !a.dead && f.dist(a) < 12 && a.action && a.action.dur - a.action.t > 0.35) || Math.random() < dt * 0.5;
    if (!go) return;
    if (a && !a.dead) {
      const dx = f.pos.x - a.pos.x, dz = f.pos.z - a.pos.z, l = Math.hypot(dx, dz) || 1, s = Math.random() < 0.5 ? 1 : -1;
      // сильные — рывком к врагу с M1 (наказание долгой заминки), слабые — прочь
      if (this.skill > 0.65 && a.action && a.action.dur - a.action.t > 0.35) { f.input.mx = -(dx / l) * 0.6 - (dz / l) * 0.8 * s; f.input.mz = -(dz / l) * 0.6 + (dx / l) * 0.8 * s; }
      else { f.input.mx = (dx / l) * 0.5 - (dz / l) * 0.85 * s; f.input.mz = (dz / l) * 0.5 + (dx / l) * 0.85 * s; }
    }
    if (f.dash()) { this.evaT = -1; this.dbg.evasive++; if (this.skill > 0.65) f.m1Buf = 0.35; }
  }

  choose() {
    const f = this.f;
    if (f.hp < 25 && this.skill > 0.4 && this.mode !== 'retreat' && f.awakened <= 0 && !this.domainOf() && Math.random() < this.st.retreat) {
      this.mode = 'retreat'; this.modeT = rand(2.5, 4);
      this.combo = null;
      if (Math.random() < 0.6) G.botLine?.(f, 'lowhp', {});
      else G.botEvent?.(f, 'help', { eventText: 'у тебя мало здоровья, ты убегаешь и просишь помощи' });
    }
    // пойман доменом — бьём кастера
    const dom = this.domainOf();
    if (dom && f.isEnemy(dom.owner)) { this.target = dom.owner; return; }
    let best = null, bs = 1e9;
    for (const o of G.fighters) {
      if (!f.isEnemy(o)) continue;
      // за стенкой чужого домена не достать
      if ((G.domains || []).some((dd) => !dd.closing && dd.caught.has(o) !== dd.caught.has(f))) continue;
      const d = f.dist(o);
      let s = d;
      s -= (1 - o.hp / o.maxHp) * 16 * this.skill;
      if (o === f.lastHitBy && G.time - f.lastHitT < 6) s -= 22 * this.aggr;
      if (o === this.target) s -= 8;
      if (o === this.revenge) s -= 30;
      // Клод прикрывает игрока: бьёт тех, кто нападает на него
      if (f.isClaude && G.player && !G.player.dead) {
        if (o.brain && o.brain.target === G.player && o.dist(G.player) < 20) s -= 14;
        if (G.player.lastHitBy === o && G.time - G.player.lastHitT < 4) s -= 20;
      }
      let n = 0;
      for (const b of G.fighters) if (b !== f && b.brain && b.brain.target === o) n++;
      // «третья сторона»: вмешаться в чужую драку, особенно добить слабого (кража килла)
      const fighting = G.time - o.lastHitT < 2 || G.time - o.lastDealtT < 2;
      if (this.tpMode && fighting && d < 60) s -= 16 + (1 - o.hp / o.maxHp) * 28;
      else s += n * 5;
      if (s < bs) { bs = s; best = o; }
    }
    if (best !== this.target) this.combo = null;
    this.target = best;
    if (Math.random() < 0.25) this.strafe *= -1;
  }
}

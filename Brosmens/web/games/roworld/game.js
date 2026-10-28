// BroWorld — симуляция: провинции, войска, золото, постройки, армии, бои, дипломатия и ИИ наций.
// Чистая логика без DOM. События наружу через game.on(fn): fn(type, data).
export const TERRAIN = {
  plains: { name: 'Равнина', icon: '🌾', def: 1.0, gold: 1.2, prod: 1.2, color: '#a7c76a' },
  forest: { name: 'Лес', icon: '🌲', def: 1.3, gold: 1.0, prod: 1.0, color: '#5f9a4c' },
  mountains: { name: 'Горы', icon: '⛰️', def: 1.7, gold: 1.0, prod: 0.65, color: '#a99f8c' },
  desert: { name: 'Пустыня', icon: '🏜️', def: 0.9, gold: 0.7, prod: 0.8, color: '#e3cb8c' },
  snow: { name: 'Снега', icon: '❄️', def: 1.3, gold: 0.6, prod: 0.6, color: '#e9eff3' },
};
export const BUILD = {
  city: { name: 'Город', icon: '🏙️', cost: 80, desc: '+золото, +лимит войск' },
  port: { name: 'Порт', icon: '⚓', cost: 50, desc: 'морские высадки' },
  factory: { name: 'Завод', icon: '🏭', cost: 90, desc: '×1.9 войск в секунду' },
  fort: { name: 'Форт', icon: '🏰', cost: 60, desc: '+60% защиты' },
};
export const BUILD_ORDER = ['city', 'port', 'factory', 'fort'];
export const WIN_SHARE = 0.6;
export const HIRE_COST = 25, HIRE_N = 10;
const LAND_SPEED = 36, SEA_SPEED = 52;
const rnd = (a, b) => a + Math.random() * (b - a);
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export class Game {
  constructor(world, nations) {
    this.w = world; this.P = world.provinces; this.N = nations;
    this.time = 0; this.running = false; this.over = false;
    this.armies = []; this.armyId = 1; this.demands = {};
    this.handlers = [];
    const n = nations.length;
    const mk = (v) => Array.from({ length: n }, () => Array.from({ length: n }, () => (typeof v === 'function' ? v() : v)));
    this.st = mk('neutral');
    this.op = mk(() => rnd(-12, 14));
    this.truce = mk(0);
    this.warSince = mk(0);
    this.lastOffer = mk(-999);
    for (const p of this.P) {
      const T = TERRAIN[p.terrain];
      p.owner = -1; p.capital = false;
      p.gar = Math.round((3 + Math.random() * 5) * T.def + Math.min(4, p.area / 90));
      p.troops = p.gar;
      p.b = { city: 0, port: 0, factory: 0, fort: 0 };
      p.goldAcc = 0; p.hit = -99;
    }
    for (const N of nations) {
      N.gold = 40; N.alive = true; N.capital = -1;
      N.s = { count: 0, area: 0, troops: 0, income: 0, prod: 0, share: 0 };
      N.captured = 0; N.lost = 0; N.battles = 0; N.peak = 0;
      N.mul = N.isPlayer ? 1.12 : 1; // небольшая фора живому игроку
      const L = N.leader || {};
      N.ai = {
        think: rnd(0.3, 1.2), diplo: rnd(6, 12),
        skill: N.isClaude ? 0.8 : L.skill ?? 0.6,
        toxic: N.isClaude ? 0.05 : L.toxic ?? 0.4,
        stage: -1, stageUntil: 0,
        aggr: N.isClaude ? 0.35 : clamp((L.toxic ?? 0.4) * 0.6 + rnd(0, 0.45), 0.1, 0.95),
      };
    }
    this.recount();
  }

  on(fn) { this.handlers.push(fn); }
  emit(type, d) { for (const h of this.handlers) try { h(type, d); } catch (e) { console.error(e); } }

  // ---------- правила ----------
  defMult(p) { return TERRAIN[p.terrain].def * (p.b.fort ? 1.6 : 1) * (p.capital ? 1.25 : 1); }
  prodRate(p) {
    if (p.owner < 0) return 0;
    return (0.36 * TERRAIN[p.terrain].prod + (p.capital ? 0.55 : 0) + (p.b.city ? 0.35 : 0)) * (p.b.factory ? 1.9 : 1) * this.N[p.owner].mul;
  }
  capOf(p) { return 30 + (p.b.city ? 45 : 0) + (p.capital ? 40 : 0) + (p.b.fort ? 20 : 0) + (p.b.factory ? 15 : 0); }
  goldRate(p) {
    if (p.owner < 0) return 0;
    return 0.24 * TERRAIN[p.terrain].gold + (p.b.city ? 1.0 : 0) + (p.b.port ? 0.35 : 0) + (p.capital ? 1.0 : 0);
  }
  count(n, type) { let c = 0; for (const p of this.P) if (p.owner === n && p.b[type]) c++; return c; }
  cost(n, type) { return Math.round(BUILD[type].cost * (1 + 0.15 * this.count(n, type))); }
  state(a, b) { return a === b ? 'self' : this.st[a][b]; }
  S(n) { const s = this.N[n].s; return s.troops + s.count * 4 + 1; }
  allies(n) { const o = []; for (let m = 0; m < this.N.length; m++) if (m !== n && this.N[m].alive && this.st[n][m] === 'ally') o.push(m); return o; }
  wars(n) { const o = []; for (let m = 0; m < this.N.length; m++) if (m !== n && this.N[m].alive && this.st[n][m] === 'war') o.push(m); return o; }

  isTarget(from, to) {
    const a = this.P[from];
    if (a.neighbors.includes(to)) return { naval: false };
    if (a.b.port) for (const r of this.w.seaReach(from)) if (r.id === to) return { naval: true };
    return null;
  }
  targets(from) {
    const a = this.P[from], out = new Map();
    for (const q of a.neighbors) out.set(q, false);
    if (a.b.port) for (const r of this.w.seaReach(from)) if (!out.has(r.id)) out.set(r.id, true);
    return out; // id -> naval
  }
  incoming(pid, n) { let s = 0; for (const a of this.armies) if (a.to === pid && a.owner === n) s += a.n; return s; }

  // ---------- действия ----------
  setCapital(n, pid, troops = 18) {
    const p = this.P[pid], N = this.N[n];
    p.owner = n; p.capital = true; p.troops = troops;
    N.capital = pid;
    this.recount();
  }

  build(n, pid, type) {
    const p = this.P[pid], N = this.N[n];
    if (p.owner !== n) return 'not-own';
    if (p.b[type]) return 'has';
    if (type === 'port' && !p.coastal) return 'no-coast';
    const c = this.cost(n, type);
    if (N.gold < c) return 'gold';
    N.gold -= c; p.b[type] = 1;
    if (type === 'port') this.w.seaReach(pid);
    this.emit('build', { n, pid, type });
    return 'ok';
  }

  order(n, from, to, frac) {
    const a = this.P[from], b = this.P[to];
    if (!a || !b || a.owner !== n || from === to) return 'bad';
    const tg = this.isTarget(from, to);
    if (!tg) return 'far';
    if (b.owner >= 0 && b.owner !== n) {
      const st = this.st[n][b.owner];
      if (st === 'ally') return 'ally';
      if (st !== 'war') this.declareWar(n, b.owner);
    }
    let k = Math.floor(a.troops * frac);
    if (k > a.troops - 1) k = Math.floor(a.troops - 1);
    if (k < 1) return 'few';
    a.troops -= k;
    const path = tg.naval ? this.w.seaPath(from, to) : [a.lx, a.ly, b.lx, b.ly];
    const cum = [0];
    for (let i = 2; i < path.length; i += 2) cum.push(cum[cum.length - 1] + Math.hypot(path[i] - path[i - 2], path[i + 1] - path[i - 1]));
    const army = { id: this.armyId++, owner: n, from, to, n: k, path, cum, len: cum[cum.length - 1] || 1, d: 0, speed: tg.naval ? SEA_SPEED : LAND_SPEED, naval: tg.naval, born: this.time };
    this.armies.push(army);
    this.emit('send', army);
    return 'ok';
  }

  declareWar(a, b, why = '') {
    if (a === b || this.st[a][b] === 'war') return;
    if (this.st[a][b] === 'ally') this.breakAlly(a, b, true);
    this.st[a][b] = this.st[b][a] = 'war';
    this.warSince[a][b] = this.warSince[b][a] = this.time;
    this.op[b][a] = clamp(this.op[b][a] - 30, -100, 100);
    this.op[a][b] = clamp(this.op[a][b] - 10, -100, 100);
    for (let x = 0; x < this.N.length; x++) if (x !== a && x !== b) this.op[x][a] -= 2;
    this.emit('war', { a, b, why });
  }
  makePeace(a, b) {
    this.st[a][b] = this.st[b][a] = 'peace';
    this.truce[a][b] = this.truce[b][a] = this.time + 60;
    this.op[a][b] += 12; this.op[b][a] += 12;
    this.emit('peace', { a, b });
  }
  makeAlly(a, b) {
    this.st[a][b] = this.st[b][a] = 'ally';
    this.op[a][b] += 15; this.op[b][a] += 15;
    this.emit('ally', { a, b });
  }
  breakAlly(a, b, silent = false) {
    if (this.st[a][b] !== 'ally') return;
    this.st[a][b] = this.st[b][a] = 'neutral';
    this.op[b][a] = clamp(this.op[b][a] - 40, -100, 100);
    this.emit('breakAlly', { a, b, silent });
  }

  // предложение от a нации b (игрок → бот: ответ сразу; бот → игрок: событие offer)
  propose(a, b, kind) {
    const st = this.st[a][b];
    if (kind === 'peace' && st !== 'war') return { ok: false, why: 'not-war' };
    if (kind === 'ally' && (st === 'war' || st === 'ally')) return { ok: false, why: st };
    if (this.time - this.lastOffer[a][b] < 15) return { ok: false, why: 'cooldown' };
    this.lastOffer[a][b] = this.time;
    const ok = this.aiAccept(b, a, kind);
    if (ok) kind === 'peace' ? this.makePeace(a, b) : this.makeAlly(a, b);
    else this.op[b][a] -= 2;
    return { ok };
  }
  aiAccept(m, a, kind) {
    const M = this.N[m];
    if (M.isClaude && this.N[a].isPlayer) return Math.random() < 0.97;
    const r = this.S(a) / this.S(m);
    if (kind === 'peace') {
      if (this.st[m][a] !== 'war') return false;
      const dur = this.time - this.warSince[m][a];
      const p = 0.12 + (r - 1) * 0.45 + this.op[m][a] / 160 + Math.min(0.35, dur / 160) - M.ai.aggr * 0.3 + (M.lost > 2 ? 0.2 : 0);
      return Math.random() < clamp(p, 0.04, 0.95);
    }
    if (this.st[m][a] === 'war') return false;
    if (this.allies(m).length >= 2) return false;
    const common = this.wars(m).some((e) => this.st[a][e] === 'war');
    const p = -0.15 + this.op[m][a] / 70 + (common ? 0.35 : 0) + (r > 0.6 ? 0.15 : -0.1) - M.ai.toxic * 0.15 + (this.st[m][a] === 'peace' ? 0.1 : 0);
    return Math.random() < clamp(p, 0.03, 0.9);
  }
  answerDemand(n, pay) {
    const d = this.demands[n];
    if (!d) return false;
    delete this.demands[n];
    const me = this.N.findIndex((x) => x.isPlayer);
    if (!this.N[n].alive || this.st[n][me] === 'war') return false;
    if (pay && this.N[me].gold >= d.gold) {
      this.N[me].gold -= d.gold; this.N[n].gold += d.gold;
      this.op[n][me] += 20;
      this.makePeace(n, me);
      this.truce[n][me] = this.truce[me][n] = this.time + 90;
      return true;
    }
    this.declareWar(n, me, 'refused');
    return false;
  }
  offer(n, m, kind) {
    if (this.time - this.lastOffer[n][m] < (this.N[m].isPlayer ? 45 : 20)) return;
    this.lastOffer[n][m] = this.time;
    if (this.N[m].isPlayer) { this.emit('offer', { from: n, kind }); return; }
    if (this.aiAccept(m, n, kind)) kind === 'peace' ? this.makePeace(n, m) : this.makeAlly(n, m);
  }

  // ---------- цикл ----------
  update(dt) {
    if (!this.running || this.over) return;
    this.time += dt;
    const P = this.P;
    for (const p of P) {
      if (p.owner < 0) {
        if (p.troops < p.gar) p.troops = Math.min(p.gar, p.troops + 0.1 * dt);
        continue;
      }
      const cap = this.capOf(p);
      if (p.troops < cap) p.troops = Math.min(cap, p.troops + this.prodRate(p) * dt);
      else p.troops -= (p.troops - cap) * 0.03 * dt;
      const g = this.goldRate(p) * dt;
      this.N[p.owner].gold += g;
      if (this.N[p.owner].isPlayer && (p.b.city || p.capital)) p.goldAcc += g;
    }
    // армии
    for (let i = this.armies.length - 1; i >= 0; i--) {
      const a = this.armies[i];
      a.d += a.speed * dt;
      if (a.d >= a.len) { this.armies.splice(i, 1); this.arrive(a); }
    }
    // ИИ
    for (const N of this.N) {
      if (!N.alive || N.isPlayer) continue;
      N.ai.think -= dt;
      if (N.ai.think <= 0) { N.ai.think = rnd(0.7, 1.5) / (0.6 + N.ai.skill * 0.5); this.think(N.id); }
      N.ai.diplo -= dt;
      if (N.ai.diplo <= 0) { N.ai.diplo = N.isClaude ? rnd(2, 4) : rnd(5, 10); this.diplo(N.id); }
    }
    // требования дани без ответа → война
    for (const k in this.demands) if (this.time > this.demands[k].until) this.answerDemand(+k, false);
    // мнения, доход-всплывашки, статистика
    this._sec = (this._sec || 0) + dt;
    if (this._sec >= 1) { this._sec -= 1; this.drift(); }
    this._inc = (this._inc || 0) + dt;
    if (this._inc >= 3) {
      this._inc = 0;
      for (const p of P) if (p.goldAcc >= 1) { this.emit('income', { pid: p.id, amount: Math.floor(p.goldAcc) }); p.goldAcc -= Math.floor(p.goldAcc); }
    }
    this._rc = (this._rc || 0) + dt;
    if (this._rc >= 0.25) { this._rc = 0; this.recount(); this.checkEnd(); }
  }

  arrive(a) {
    const b = this.P[a.to], o = b.owner, A = this.N[a.owner];
    if (!A.alive) return;
    if (o === a.owner) { b.troops += a.n; this.emit('reinforce', a); return; }
    if (o >= 0 && this.st[a.owner][o] !== 'war') {
      // пока шли — заключили мир/союз: войска возвращаются домой
      const f = this.P[a.from];
      if (f.owner === a.owner) f.troops += a.n;
      return;
    }
    const mult = this.defMult(b), def = b.troops * mult;
    b.hit = this.time;
    if (a.n > def) {
      const wasCap = b.capital;
      b.owner = a.owner; b.troops = Math.max(1, a.n - def);
      A.captured++; A.battles++;
      if (o >= 0) { this.N[o].lost++; this.op[o][a.owner] -= 3; }
      this.emit('battle', { pid: b.id, att: a.owner, def: o, won: true, n: a.n, naval: a.naval });
      this.emit('capture', { pid: b.id, from: o, to: a.owner });
      if (wasCap && o >= 0) {
        b.capital = false;
        const loot = Math.floor(this.N[o].gold * 0.4);
        this.N[o].gold -= loot; A.gold += loot;
        this.relocateCapital(o);
        this.emit('capital', { pid: b.id, from: o, to: a.owner, loot });
      }
      if (o >= 0) this.checkAlive(o, a.owner);
    } else {
      b.troops = Math.max(0, (def - a.n) / mult);
      if (o >= 0) this.N[o].battles++;
      this.emit('battle', { pid: b.id, att: a.owner, def: o, won: false, n: a.n, naval: a.naval });
    }
  }

  relocateCapital(n) {
    let best = null, bs = -1;
    for (const p of this.P) if (p.owner === n) { const s = p.troops + (p.b.city ? 30 : 0) + p.area / 20; if (s > bs) { bs = s; best = p; } }
    this.N[n].capital = best ? best.id : -1;
    if (best) best.capital = true;
  }

  checkAlive(n, by) {
    const N = this.N[n];
    if (!N.alive) return;
    if (this.P.some((p) => p.owner === n)) return;
    N.alive = false; N.capital = -1;
    this.armies = this.armies.filter((a) => a.owner !== n);
    for (let m = 0; m < this.N.length; m++) { this.st[n][m] = this.st[m][n] = 'neutral'; }
    this.emit('eliminated', { n, by });
  }

  drift() {
    const n = this.N.length;
    for (let a = 0; a < n; a++) for (let b = 0; b < n; b++) {
      if (a === b) continue;
      const s = this.st[a][b];
      let v = this.op[a][b];
      if (s === 'ally') v += 0.35; else if (s === 'peace') v += 0.2; else if (s === 'war') v -= 0.05; else v *= 0.995;
      if (s === 'peace' && this.time > this.truce[a][b] + 120 && Math.random() < 0.002) { this.st[a][b] = this.st[b][a] = 'neutral'; }
      this.op[a][b] = clamp(v, -100, 100);
    }
  }

  recount() {
    for (const N of this.N) { const s = N.s; s.count = s.area = s.troops = s.income = s.prod = 0; }
    for (const p of this.P) {
      if (p.owner < 0) continue;
      const s = this.N[p.owner].s;
      s.count++; s.area += p.area; s.troops += p.troops; s.income += this.goldRate(p); s.prod += this.prodRate(p);
    }
    for (const a of this.armies) this.N[a.owner].s.troops += a.n;
    for (const N of this.N) { N.s.share = N.s.area / this.w.landCount; if (N.s.share > N.peak) N.peak = N.s.share; }
  }

  checkEnd() {
    if (this.over) return;
    const me = this.N.find((N) => N.isPlayer);
    if (!me.alive || me.s.count === 0) { me.alive = false; this.finish(false, 'lost'); return; }
    if (me.s.share >= WIN_SHARE) { this.finish(true, 'share'); return; }
    const rivals = this.N.filter((N) => !N.isPlayer && N.alive);
    if (!rivals.length) { this.finish(true, 'alone'); return; }
    const big = rivals.find((N) => N.s.share >= WIN_SHARE);
    if (big) this.finish(false, 'other', big.id);
  }
  finish(win, reason, who) {
    this.over = true;
    this.emit('end', { win, reason, who });
  }

  // ---------- ИИ ----------
  threat(p, n) {
    let t = 0;
    for (const q of p.neighbors) {
      const o = this.P[q].owner;
      if (o < 0 || o === n) continue;
      const s = this.st[n][o];
      const v = this.P[q].troops * (s === 'war' ? 1 : s === 'neutral' ? 0.3 : 0.05);
      if (v > t) t = v;
    }
    return t;
  }

  think(n) {
    const N = this.N[n], P = this.P, ai = N.ai;
    const mine = P.filter((p) => p.owner === n);
    if (!mine.length) return;
    this.aiBuild(n, mine);
    const used = new Set(), usedQ = new Set();
    const cands = [];
    const me = this.N.findIndex((x) => x.isPlayer);
    for (const p of mine) {
      if (p.troops < 4) continue;
      const th = this.threat(p, n);
      const avail = p.troops - 1 - Math.min(p.troops * 0.5, th * 0.7);
      if (avail < 3) continue;
      for (const [qid, naval] of this.targets(p.id)) {
        const q = P[qid];
        if (q.owner === n) continue;
        let enemy = false;
        if (q.owner >= 0) { if (this.st[n][q.owner] !== 'war') continue; enemy = true; }
        const need = q.troops * this.defMult(q) + 1.5 - this.incoming(qid, n);
        if (need <= 0) continue;
        if (avail < need * 1.1) continue;
        let val = 1 + (q.b.city ? 1.5 : 0) + (q.capital ? 2.5 : 0) + (q.b.factory ? 1 : 0) + TERRAIN[q.terrain].gold * 0.4;
        if (!enemy) val *= 1.35;
        else {
          val *= 0.75 + ai.aggr;
          if (q.owner === me) val *= N.isClaude ? 0 : 1 + ai.toxic * 0.25;
        }
        if (naval) val *= 0.55;
        cands.push({ p, q, score: val / (need + 6), send: Math.min(avail, need * 1.35 + 3) });
      }
    }
    cands.sort((a, b) => b.score - a.score);
    const maxOrders = 1 + Math.round(ai.skill * 2) + (mine.length > 18 ? 1 : 0);
    let orders = 0;
    for (const c of cands) {
      if (orders >= maxOrders) break;
      if (used.has(c.p.id) || usedQ.has(c.q.id) || c.score <= 0) continue;
      if (this.order(n, c.p.id, c.q.id, c.send / c.p.troops) === 'ok') { used.add(c.p.id); usedQ.add(c.q.id); orders++; }
    }
    // подтянуть войска: на войне — к «точке удара» (у самой слабой вражеской провинции), иначе — к фронту
    const np = P.length, dist = new Int16Array(np).fill(-1), q = [];
    const wars = this.wars(n);
    let stage = -1;
    if (wars.length) {
      if (ai.stage >= 0 && P[ai.stage].owner === n && this.time < ai.stageUntil && P[ai.stage].neighbors.some((x) => P[x].owner >= 0 && this.st[n][P[x].owner] === 'war')) stage = ai.stage;
      else {
        let bs = 1e9;
        for (const p of mine) for (const x of p.neighbors) {
          const t = P[x];
          if (t.owner < 0 || this.st[n][t.owner] !== 'war') continue;
          const sc = (t.troops * this.defMult(t) + 5) / (1 + (t.capital ? 1 : 0) + (t.b.city ? 0.5 : 0)) - p.troops * 0.3;
          if (sc < bs) { bs = sc; stage = p.id; }
        }
        ai.stage = stage; ai.stageUntil = this.time + rnd(15, 30);
      }
    }
    if (stage >= 0) { dist[stage] = 0; q.push(stage); }
    else for (const p of mine) {
      let hot = false;
      for (const x of p.neighbors) { const o = P[x].owner; if (o !== n && (o < 0 || this.st[n][o] !== 'ally')) { hot = true; break; } }
      if (hot) { dist[p.id] = 0; q.push(p.id); }
    }
    for (let h = 0; h < q.length; h++) {
      for (const x of P[q[h]].neighbors) if (P[x].owner === n && dist[x] < 0) { dist[x] = dist[q[h]] + 1; q.push(x); }
    }
    let moves = 0;
    const maxMoves = stage >= 0 ? 3 : 2;
    for (const p of mine) {
      if (moves >= maxMoves || used.has(p.id) || p.troops < 10 || dist[p.id] <= 0) continue;
      let best = -1;
      for (const x of p.neighbors) if (P[x].owner === n && dist[x] >= 0 && dist[x] < dist[p.id] && (best < 0 || P[x].troops < P[best].troops)) best = x;
      const th = this.threat(p, n);
      const frac = th > p.troops * 0.5 ? 0.4 : 0.8;
      if (best >= 0 && this.order(n, p.id, best, frac) === 'ok') { moves++; used.add(p.id); }
    }
    // лишнее золото — наёмники в точку удара
    if (stage >= 0 && N.gold > 160) this.hire(n, stage);
  }

  hire(n, pid) {
    const p = this.P[pid], N = this.N[n];
    if (p.owner !== n) return 'not-own';
    if (N.gold < HIRE_COST) return 'gold';
    N.gold -= HIRE_COST; p.troops += HIRE_N;
    this.emit('hire', { n, pid });
    return 'ok';
  }

  aiBuild(n, mine) {
    const N = this.N[n];
    if (N.gold < 50) return;
    const atWar = this.wars(n).length > 0;
    let neutralAdj = 0, hasPort = false;
    for (const p of mine) { if (p.b.port) hasPort = true; for (const x of p.neighbors) if (this.P[x].owner < 0) neutralAdj++; }
    let best = null, bw = 0;
    const consider = (p, t, w) => { w *= rnd(0.7, 1.3); if (w > bw && this.cost(n, t) <= N.gold) { bw = w; best = { p, t }; } };
    for (const p of mine) {
      const T = TERRAIN[p.terrain];
      if (!p.b.city) consider(p, 'city', (p.capital ? 3 : 1) * T.gold * (mine.length > 3 ? 1 : 0.4));
      if (!p.b.factory && (p.b.city || p.capital)) consider(p, 'factory', 1.6);
      if (!p.b.fort && atWar) { const th = this.threat(p, n); if (th > p.troops * 0.5) consider(p, 'fort', 2 + (p.capital ? 1.2 : 0)); }
      if (!p.b.port && p.coastal && !hasPort && neutralAdj < 2) consider(p, 'port', 2.2);
    }
    if (best) this.build(n, best.p.id, best.t);
  }

  diplo(n) {
    const N = this.N[n], ai = N.ai;
    const me = this.N.findIndex((x) => x.isPlayer);
    const myS = this.S(n), wars = this.wars(n);
    // 1. мир, если проигрываем
    for (const m of wars) {
      const dur = this.time - this.warSince[n][m];
      if (dur > 25 && (this.S(m) > myS * 1.5 || N.lost > 3) && Math.random() < 0.35) this.offer(n, m, 'peace');
    }
    // 2. помочь союзникам
    for (const a of this.allies(n)) {
      for (const e of this.wars(a)) {
        if (e === n || this.st[n][e] !== 'neutral') continue;
        const pr = N.isClaude && a === me ? 0.85 : 0.2;
        if (Math.random() < pr) this.declareWar(n, e, a === me ? 'ally-player' : 'ally');
      }
    }
    // 3. новая война
    const adj = new Set();
    let neutralAdj = 0;
    for (const p of this.P) {
      if (p.owner !== n) continue;
      for (const x of p.neighbors) { const o = this.P[x].owner; if (o < 0) neutralAdj++; else if (o !== n) adj.add(o); }
    }
    if (wars.length === 0 || (wars.length === 1 && Math.random() < 0.12)) {
      if (neutralAdj <= 2 || this.time > 220 || Math.random() < 0.04) {
        let best = -1, bs = -1e9;
        for (const m of adj) {
          const s = this.st[n][m];
          if (s === 'ally' || s === 'war') continue;
          if (s === 'peace' && !(this.time > this.truce[n][m] && ai.toxic > 0.6 && Math.random() < 0.3)) continue;
          if (N.isClaude && me >= 0 && (m === me || this.st[me][m] === 'ally')) continue;
          if (m === me && this.time < 75) continue; // первые минуты игрока не трогают
          let sc = myS / this.S(m) - this.op[n][m] / 60 + rnd(0, 0.4);
          if (m === me) { // не наваливаться на игрока всей толпой
            const pw = this.wars(me).filter((x) => !this.N[x].isClaude).length;
            sc += ai.toxic * 0.15 - pw * 0.9;
            if (pw >= 3 || myS < this.S(me)) continue;
          }
          if (sc > bs) { bs = sc; best = m; }
        }
        if (best >= 0 && myS > this.S(best) * (1.15 - ai.aggr * 0.45) && Math.random() < 0.45 + ai.aggr * 0.4) {
          // торг: иногда сначала требуют дань у игрока
          if (best === me && !this.demands[n] && this.N[me].gold >= 25 && Math.random() < 0.45) {
            const g = Math.round(clamp(this.N[me].gold * 0.5, 25, 150));
            this.demands[n] = { gold: g, until: this.time + 16 };
            this.emit('demand', { from: n, gold: g });
          } else this.declareWar(n, best);
        }
      }
    }
    // 4. союзы
    if (Math.random() < 0.3 && this.allies(n).length < 2) {
      for (let m = 0; m < this.N.length; m++) {
        if (m === n || !this.N[m].alive) continue;
        const s = this.st[n][m];
        if (s === 'war' || s === 'ally') continue;
        const common = wars.some((e) => this.st[m][e] === 'war');
        if (this.op[n][m] > 30 || (common && this.op[n][m] > 5)) { this.offer(n, m, 'ally'); break; }
      }
    }
    // 5. предательство
    if (!N.isClaude && ai.toxic > 0.7 && Math.random() < 0.04 && neutralAdj === 0) {
      for (const m of this.allies(n)) if (adj.has(m) && this.S(m) < myS * 0.5) { this.breakAlly(n, m); break; }
    }
  }
}

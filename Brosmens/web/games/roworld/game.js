// BroWorld — тайловый движок (как в оригинале): владелец каждой клетки, общий запас войск и золота у игрока,
// атаки «ползут» по клеткам из очереди с приоритетом, тик 100 мс. Чистая логика без DOM.
// Войска хранятся ×10 (на экране — делённые на 10). События: game.on(fn) → fn(type, data).
import { W, H, N_TILES, T_PLAINS, T_HIGH, T_MTN, T_IMPASS } from './world.js';

export const KIND = { HUMAN: 0, NATION: 1, TRIBE: 2 };
export const TICK = 0.1;
// Наша карта 1000×500 вдвое мельче оригинальной 2000×1000: расстояния в клетках ×0.5, площади ×0.25.
export const WIN_SHARE = 0.8;                       // 80% суши вне радиации
export const PROT_TICKS = 5 * 60 * 10;              // 5:00 защиты: люди не нападают на людей
export const NATION_IMMUNE = 50;                    // у наций и племён иммунитет всего 5 с
export const MATCH_TICKS = PROT_TICKS + 40 * 60 * 10; // после защиты — 40:00 до конца матча
export const ELIM_TILES = 25;                       // гибель ниже 100 клеток оригинала (×0.25)
export const RETREAT_TICKS = 20;
export const SPAWN_R = 4.6;                         // стартовый диск ≈9 клеток оригинала
export const SPAWN_GAP = 15;                        // 30 клеток оригинала между игроками
export const TRIBE_GAP = 10;                        // племена — плотнее, но диски не пересекаются
export const BOAT_MAX = 3, BOAT_SPEED = 0.6;        // не больше 3 десантов сразу
export const TRAITOR_TICKS = 300, DONATE_CD = 100;
// нации — сложность «Hard» (как в матчах оригинала): старт 2.5K, лимит ×1, прирост ×1
export const NATION_DIFF = { start: 25000, cap: 1, regen: 1 };
// темп захвата: наша клетка вчетверо больше по площади, поэтому фронт продвигается вдвое медленнее в клетках —
// тогда по карте он идёт с той же скоростью, что в оригинале (мир делят минут за 5, матч — 10–25 минут)
export const PACE = 0.5;
// Постройки (клавиши 1–7). time — тики стройки; range — радиус действия в клетках.
export const STRUCTS = {
  city: { name: 'Город', key: '1', time: 20, upg: true },
  port: { name: 'Порт', key: '2', time: 50, upg: true },
  factory: { name: 'Завод', key: '3', time: 20, upg: true },
  post: { name: 'Оборонный пост', key: '4', time: 50, upg: false, range: 15 },
  sam: { name: 'ПВО', key: '5', time: 300, upg: true, range: 35 },
  silo: { name: 'Ракетная шахта', key: '6', time: 100, upg: true },
};
export const SNAP_R = 8, STRUCT_GAP = 8, PORT_R = 10; // 15 / 15 / 20 клеток оригинала
export const SHIP = { hp: 1000, range: 65, patrol: 50, reload: 20, speed: 0.5, dmg: [200, 300] };
const MAG = [0, 0, 80, 100, 120, 0];
const COST = [0, 0, 16.5, 20, 25, 0];
const TMAG = [0, 0, 1, 1.5, 2, 0];
const LN_MID = Math.log(300000);
const within = (v, a, b) => (v < a ? a : v > b ? b : v);
const largeBonus = (tiles, depth) => 1 - depth / (1 + Math.exp(-2.5 * (Math.log(Math.max(1, tiles)) - LN_MID)));

// Числа как в оригинале: <1000 целое, 1.23K, 12.3K, 123K, 1.23M, 12.3M, 1.23B (с округлением вниз)
export function fmt(v) {
  v = v > 0 ? v : 0;
  if (v >= 1e10) return (Math.floor(v / 1e8) / 10).toFixed(1) + 'B';
  if (v >= 1e9) return (Math.floor(v / 1e7) / 100).toFixed(2) + 'B';
  if (v >= 1e7) return (Math.floor(v / 1e5) / 10).toFixed(1) + 'M';
  if (v >= 1e6) return (Math.floor(v / 1e4) / 100).toFixed(2) + 'M';
  if (v >= 1e5) return Math.floor(v / 1000) + 'K';
  if (v >= 1e4) return (Math.floor(v / 100) / 10).toFixed(1) + 'K';
  if (v >= 1000) return (Math.floor(v / 10) / 100).toFixed(2) + 'K';
  return String(Math.floor(v));
}
export const fmtT = (internal) => fmt(internal / 10); // войска: внутренние → экранные

// мин-куча (приоритет, клетка), растёт по мере надобности
class Heap {
  constructor(cap = 64) { this.k = new Float64Array(cap); this.v = new Int32Array(cap); this.n = 0; }
  push(key, val) {
    if (this.n === this.k.length) {
      const k = new Float64Array(this.n * 2), v = new Int32Array(this.n * 2);
      k.set(this.k); v.set(this.v); this.k = k; this.v = v;
    }
    let i = this.n++;
    const K = this.k, V = this.v;
    while (i > 0) { const p = (i - 1) >> 1; if (K[p] <= key) break; K[i] = K[p]; V[i] = V[p]; i = p; }
    K[i] = key; V[i] = val;
  }
  pop() {
    const K = this.k, V = this.v, top = V[0];
    const key = K[--this.n], val = V[this.n];
    let i = 0;
    for (;;) {
      let c = 2 * i + 1; if (c >= this.n) break;
      if (c + 1 < this.n && K[c + 1] < K[c]) c++;
      if (K[c] >= key) break;
      K[i] = K[c]; V[i] = V[c]; i = c;
    }
    K[i] = key; V[i] = val;
    return top;
  }
}

export class Game {
  constructor(world) {
    this.w = world;
    this.terr = world.terr;
    this.owner = new Uint16Array(N_TILES);
    this.structAt = new Int32Array(N_TILES).fill(-1);
    this.P = [null]; // по id (0 — ничья земля)
    this.attacks = [];
    this.structs = [];
    this.boats = [];  // десант в пути
    this.ships = [];  // военные корабли
    this.fallout = 0; // клетки радиации (не считаются в 80%)
    this.tickN = 0; this.running = false; this.over = false;
    this.handlers = [];
    this.chg = new Int32Array(16384); this.chgN = 0;
    this.attackSeq = 1; this.structSeq = 1; this.boatSeq = 1;
    this.dirtyEnclave = false;
    this.brain = null; // ИИ: fn(game) каждый тик
    this.lab = null; this.stk = null;
  }
  on(fn) { this.handlers.push(fn); }
  emit(type, d) { for (const h of this.handlers) try { h(type, d); } catch (e) { console.error(e); } }
  get time() { return this.tickN * TICK; }
  get landCount() { return this.w.landCount; }
  get winLand() { return Math.max(1, this.w.landCount - this.fallout); } // суша вне радиации

  addPlayer(o) {
    const p = {
      id: this.P.length, kind: o.kind, name: o.name, color: o.color, col: o.col,
      isPlayer: !!o.isPlayer, isClaude: !!o.isClaude, leader: o.leader || null,
      troops: o.kind === KIND.TRIBE ? 10000 : o.kind === KIND.NATION ? NATION_DIFF.start : 25000,
      gold: 0, tiles: 0, border: new Set(), alive: true, attacks: [], hitBy: new Map(), allies: new Set(),
      cityLevels: 0, posts: [], paid: { city: 0, port: 0, factory: 0, post: 0, sam: 0, silo: 0, warship: 0 },
      peakTiles: 0, maxTroopsSeen: 0, kills: 0, killsN: 0, boats: [], traitorUntil: -1, donateAt: -1e9,
      spawn: -1, spawnTiles: null, ai: {}, diedAt: 0,
    };
    this.P.push(p);
    return p;
  }
  alivePlayers() { const o = []; for (let i = 1; i < this.P.length; i++) if (this.P[i].alive) o.push(this.P[i]); return o; }

  // ---------- правила (формулы оригинала) ----------
  maxTroops(p) {
    const m = 2 * (Math.pow(p.tiles, 0.6) * 1000 + 50000) + 250000 * p.cityLevels;
    if (p.kind === KIND.TRIBE) return m / 3;
    if (p.kind === KIND.NATION) return m * NATION_DIFF.cap;
    return m;
  }
  regen(p) {
    const max = this.maxTroops(p);
    let add = (10 + Math.pow(Math.max(0, p.troops), 0.73) / 4) * (1 - p.troops / max);
    if (p.kind === KIND.TRIBE) add *= 0.5;
    else if (p.kind === KIND.NATION) add *= NATION_DIFF.regen;
    return Math.min(p.troops + add, max) - p.troops;
  }
  // золото за тик: 1K/с у людей и наций, 500/с у племён; порты и заводы — доход от торговли и промышленности
  goldRate(p) { return p.kind === KIND.TRIBE ? 50 : 100 + 50 * (p.portLevels || 0) + 40 * (p.factLevels || 0); }
  troopsAtWar(p) { let s = 0; for (const a of p.attacks) if (!a.dead) s += a.troops; for (const b of p.boats) s += b.troops; return s; }
  // защита: люди неуязвимы для людей первые 5:00, нации и племена — только 5 с
  isImmune(q) { return !!q && this.tickN < (q.kind === KIND.HUMAN ? PROT_TICKS : NATION_IMMUNE); }
  get protLeft() { return Math.max(0, PROT_TICKS - this.tickN); }
  canAttack(p, q) {
    if (!q) return true;
    if (q === p || !q.alive || this.allied(p, q)) return false;
    return !(p.kind === KIND.HUMAN && this.isImmune(q)); // нации и племена иммунитет людей не смотрят
  }
  isTraitor(p) { return p.traitorUntil > this.tickN; }
  // разорвать союз: предатель на 30 с (атаки на него дешевле вдвое и на 20% быстрее)
  breakAlly(p, q) {
    if (!this.allied(p, q)) return false;
    p.allies.delete(q.id); q.allies.delete(p.id);
    p.traitorUntil = this.tickN + TRAITOR_TICKS;
    this.emit('betray', { p, q });
    return true;
  }
  donate(p, q, troops) {
    if (!this.allied(p, q) || this.tickN - p.donateAt < DONATE_CD) return 0;
    troops = Math.floor(Math.min(troops, p.troops, Math.max(0, this.maxTroops(q) - q.troops)));
    if (troops < 1) return 0;
    p.troops -= troops; q.troops += troops; p.donateAt = this.tickN;
    this.emit('donate', { p, q, troops });
    return troops;
  }
  allied(a, b) { return !!a && !!b && a !== b && a.allies.has(b.id); }
  makeAlly(a, b) {
    if (a === b || this.allied(a, b)) return;
    a.allies.add(b.id); b.allies.add(a.id);
    this.emit('ally', { a, b });
  }
  attackersOn(q) { let n = 0; for (const a of this.attacks) if (!a.dead && a.target === q) n++; return n; }
  // статус для карточки цели: союз / война (идёт атака в любую сторону) / нейтрал
  relation(me, q) {
    if (this.allied(me, q)) return 'ally';
    for (const a of me.attacks) if (!a.dead && a.target === q) return 'war';
    for (const a of q.attacks) if (!a.dead && a.target === me) return 'war';
    for (const b of me.boats) if (b.target === q) return 'war';
    for (const b of q.boats) if (b.target === me) return 'war';
    const t = this.tickN, h1 = me.hitBy.get(q.id), h2 = q.hitBy.get(me.id);
    if ((h1 !== undefined && t - h1 < 300) || (h2 !== undefined && t - h2 < 300)) return 'war';
    return 'neutral';
  }

  // ---------- клетки ----------
  isLand(t) { const v = this.terr[t]; return v >= T_PLAINS && v !== T_IMPASS; }
  isBorderTile(t, id) {
    const o = this.owner, x = t % W;
    return x === 0 || x === W - 1 || t < W || t >= N_TILES - W || o[t - 1] !== id || o[t + 1] !== id || o[t - W] !== id || o[t + W] !== id;
  }
  refreshBorder(t) {
    const id = this.owner[t];
    if (!id) return;
    const b = this.P[id].border;
    if (this.isBorderTile(t, id)) b.add(t); else b.delete(t);
  }
  mark(t) {
    if (this.chgN === this.chg.length) { const c = new Int32Array(this.chg.length * 2); c.set(this.chg); this.chg = c; }
    this.chg[this.chgN++] = t;
  }
  setOwner(t, id) {
    const o = this.owner, prev = o[t];
    if (prev === id) return;
    if (prev) { const q = this.P[prev]; q.tiles--; q.border.delete(t); }
    o[t] = id;
    if (id) { const p = this.P[id]; p.tiles++; if (p.tiles > p.peakTiles) p.peakTiles = p.tiles; }
    this.refreshBorder(t);
    const x = t % W;
    if (x > 0) this.refreshBorder(t - 1);
    if (x < W - 1) this.refreshBorder(t + 1);
    if (t >= W) this.refreshBorder(t - W);
    if (t < N_TILES - W) this.refreshBorder(t + W);
    this.mark(t);
    this.dirtyEnclave = true;
    const s = this.structAt[t];
    if (s >= 0) this.captureStruct(this.structs[s], id, prev);
  }
  flush() { if (this.chgN) { this.emit('tiles', { buf: this.chg, n: this.chgN }); this.chgN = 0; } }

  // граничит ли p с землёй цели (target — игрок или null для ничьей земли)
  borders(p, target) {
    const tid = target ? target.id : 0, o = this.owner;
    for (const t of p.border) {
      const x = t % W;
      if (x > 0 && o[t - 1] === tid && this.isLand(t - 1)) return true;
      if (x < W - 1 && o[t + 1] === tid && this.isLand(t + 1)) return true;
      if (t >= W && o[t - W] === tid && this.isLand(t - W)) return true;
      if (t < N_TILES - W && o[t + W] === tid && this.isLand(t + W)) return true;
    }
    return false;
  }

  // ---------- появление ----------
  spawnTilesAt(center) {
    const out = [], cx = center % W, cy = (center / W) | 0, R = Math.ceil(SPAWN_R), R2 = SPAWN_R * SPAWN_R;
    for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
      if (dx * dx + dy * dy > R2) continue;
      const x = cx + dx, y = cy + dy;
      if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const t = y * W + x;
      if (this.isLand(t) && !this.owner[t]) out.push(t);
    }
    return out;
  }
  canSpawn(center) { return center >= 0 && this.isLand(center) && !this.owner[center] && this.spawnTilesAt(center).length >= 30; }
  // этап выбора: только метка столицы; диски земли появляются, когда начинается война (spawnAll)
  reserveSpawn(p, center) { p.spawn = center; }
  spawnAll() {
    for (let i = 1; i < this.P.length; i++) { const p = this.P[i]; if (p.alive && p.spawn >= 0 && !p.spawnTiles) this.spawn(p, p.spawn); }
    for (let i = 1; i < this.P.length; i++) { const p = this.P[i]; if (p.alive && !p.tiles) p.alive = false; }
  }
  spawn(p, center) {
    const tiles = this.spawnTilesAt(center);
    for (const t of tiles) this.setOwner(t, p.id);
    p.spawn = center; p.spawnTiles = tiles; p.alive = true;
    this.flush();
    this.emit('spawn', { p });
  }
  unspawn(p) {
    if (!p.spawnTiles) return;
    for (const t of p.spawnTiles) if (this.owner[t] === p.id) this.setOwner(t, 0);
    p.spawnTiles = null; p.spawn = -1;
    this.flush();
  }

  // ---------- атаки ----------
  // p атакует цель (игрок или null — ничья земля) отрядом troops (внутренние единицы).
  attack(p, target, troops, landed = false) {
    if (!p.alive || this.over) return { ok: false, reason: 'dead' };
    if (target && (target === p || !target.alive)) return { ok: false, reason: 'bad' };
    if (target && this.allied(p, target)) return { ok: false, reason: 'ally' };
    if (target && !this.canAttack(p, target)) return { ok: false, reason: 'immune' };
    troops = Math.floor(landed ? troops : Math.min(troops, p.troops));
    if (troops < 1) return { ok: false, reason: 'few' };
    if (!this.borders(p, target)) return { ok: false, reason: 'far' };
    if (!landed) p.troops -= troops;
    // встречные атаки гасят друг друга: большая остаётся с разницей
    if (target) {
      for (const a of target.attacks) {
        if (a.dead || a.target !== p || a.boat || a.retreatAt >= 0) continue;
        if (a.troops > troops) {
          a.troops -= troops;
          this.emit('clash', { p, target, troops, absorbed: true });
          return { ok: true, absorbed: true, troops };
        }
        troops -= a.troops;
        this.emit('clash', { p, target, troops: a.troops, absorbed: false });
        this.killAttack(a);
      }
      target.hitBy.set(p.id, this.tickN);
    }
    // повторный тап по той же цели — добавить к идущей атаке (высадка с моря — отдельная атака)
    for (const a of p.attacks) {
      if (landed) break;
      if (a.dead || a.target !== target || a.boat || a.retreatAt >= 0) continue;
      a.troops += troops;
      this.emit('attack', { a, merged: true, add: troops });
      return { ok: true, attack: a, merged: true, troops };
    }
    const a = { id: this.attackSeq++, owner: p, target, troops, start: troops, heap: new Heap(), front: new Set(), retreatAt: -1, born: this.tickN, dead: false, boat: landed };
    this.fillFront(a);
    if (!a.front.size) { p.troops += troops; return { ok: false, reason: 'far' }; }
    p.attacks.push(a); this.attacks.push(a);
    this.emit('attack', { a, merged: false, add: troops });
    return { ok: true, attack: a, troops };
  }
  fillFront(a) {
    const tid = a.target ? a.target.id : 0, o = this.owner;
    for (const t of a.owner.border) {
      const x = t % W;
      if (x > 0 && o[t - 1] === tid) this.addFront(a, t - 1);
      if (x < W - 1 && o[t + 1] === tid) this.addFront(a, t + 1);
      if (t >= W && o[t - W] === tid) this.addFront(a, t - W);
      if (t < N_TILES - W && o[t + W] === tid) this.addFront(a, t + W);
    }
  }
  addFront(a, t) {
    if (!this.isLand(t)) return;
    const o = this.owner, id = a.owner.id, x = t % W;
    let own = 0;
    if (x > 0 && o[t - 1] === id) own++;
    if (x < W - 1 && o[t + 1] === id) own++;
    if (t >= W && o[t - W] === id) own++;
    if (t < N_TILES - W && o[t + W] === id) own++;
    const pr = (Math.floor(Math.random() * 7) + 10) * (1 - 0.5 * own + TMAG[this.terr[t]] / 2) + this.tickN;
    a.heap.push(pr, t);
    a.front.add(t);
  }
  hasPostNear(def, t) {
    if (!def.posts.length) return false;
    const x = t % W, y = (t / W) | 0, R2 = STRUCTS.post.range * STRUCTS.post.range;
    for (const s of def.posts) {
      if (!s.built) continue;
      const dx = (s.tile % W) - x, dy = ((s.tile / W) | 0) - y;
      if (dx * dx + dy * dy <= R2) return true;
    }
    return false;
  }
  stepAttack(a) {
    const p = a.owner, def = a.target;
    if (a.retreatAt >= 0) {
      if (this.tickN >= a.retreatAt) {
        const back = a.troops * (def ? 0.75 : 1);
        this.endAttack(a, back, 'retreat');
      }
      return;
    }
    if (def && (!def.alive || this.allied(p, def))) { this.endAttack(a, a.troops, def.alive ? 'ally' : 'done'); return; }
    const trait = def && this.isTraitor(def);
    const o = this.owner, terr = this.terr, tid = def ? def.id : 0, id = p.id;
    const borderSize = a.front.size + Math.floor(Math.random() * 5);
    let budget = PACE;
    while (budget > 0) {
      if (a.troops < 1) { this.endAttack(a, 0, 'wiped'); return; }
      if (!a.heap.n) { this.endAttack(a, a.troops, 'done'); return; }
      const t = a.heap.pop();
      a.front.delete(t);
      if (o[t] !== tid || !this.isLand(t)) continue;
      const x = t % W;
      if (!((x > 0 && o[t - 1] === id) || (x < W - 1 && o[t + 1] === id) || (t >= W && o[t - W] === id) || (t < N_TILES - W && o[t + W] === id))) continue;
      const ter = terr[t];
      let mag = MAG[ter], cost = COST[ter];
      if (!def) {
        budget -= within((2000 * cost) / Math.max(1, a.troops), 5, 100) / (2 * borderSize);
        a.troops -= mag / (p.kind === KIND.TRIBE ? 10 : 5);
      } else {
        if (this.hasPostNear(def, t)) { mag *= 5; cost *= 3; }
        if (p.kind !== KIND.TRIBE && def.kind === KIND.TRIBE) mag *= 0.7;
        const dT = Math.max(1, def.troops), ratio = dT / Math.max(1, a.troops), dTiles = Math.max(1, def.tiles);
        const defLoss = def.troops / dTiles;
        const lbD = largeBonus(dTiles, 0.3);
        a.troops -= mag * (trait ? 0.5 : 1) * within(ratio, 0.6, 2) * (0.463 * largeBonus(p.tiles, 0.7) * lbD + 0.0039 * defLoss);
        const speed = (within(ratio, 0.82, 7.5) * within(ratio / 20, 1, 50)) / 8.55;
        budget -= (speed * cost * largeBonus(p.tiles, 0.73) * lbD * (trait ? 0.8 : 1)) / borderSize;
        def.troops = Math.max(0, def.troops - defLoss);
      }
      this.setOwner(t, id);
      if (x > 0 && o[t - 1] === tid) this.addFront(a, t - 1);
      if (x < W - 1 && o[t + 1] === tid) this.addFront(a, t + 1);
      if (t >= W && o[t - W] === tid) this.addFront(a, t - W);
      if (t < N_TILES - W && o[t + W] === tid) this.addFront(a, t + W);
      if (def && def.tiles < ELIM_TILES) {
        this.eliminate(def, p);
        this.endAttack(a, Math.max(0, a.troops), 'done');
        return;
      }
    }
  }
  retreat(a) {
    if (a.dead || a.retreatAt >= 0) return;
    a.retreatAt = this.tickN + RETREAT_TICKS;
    this.emit('retreat', { a });
  }
  killAttack(a) {
    if (a.dead) return;
    a.dead = true;
    const L = a.owner.attacks, i = L.indexOf(a);
    if (i >= 0) L.splice(i, 1);
  }
  endAttack(a, back, why) {
    if (a.dead) return;
    if (back > 0 && a.owner.alive) a.owner.troops += back;
    this.killAttack(a);
    this.emit('attackEnd', { a, why, back });
  }

  // ---------- гибель игрока ----------
  eliminate(v, by) {
    if (!v.alive) return;
    v.alive = false; v.diedAt = this.tickN;
    // вся оставшаяся земля отходит победителю
    const o = this.owner, vid = v.id;
    if (v.tiles > 0) for (let t = 0; t < N_TILES; t++) if (o[t] === vid) this.setOwner(t, by ? by.id : 0);
    for (const a of v.attacks.slice()) this.killAttack(a);
    for (const a of this.attacks) if (!a.dead && a.target === v) this.endAttack(a, a.troops, 'done');
    for (const b of v.boats.slice()) this.killBoat(b);
    for (const s of this.ships.slice()) if (s.owner === v) this.killShip(s);
    let gold = 0;
    if (by) {
      gold = Math.floor(v.kind === KIND.HUMAN ? v.gold * 0.5 : v.gold);
      by.gold += gold; by.kills++;
      if (v.kind !== KIND.TRIBE) by.killsN++;
    }
    v.gold = 0; v.troops = 0;
    for (const id of v.allies) this.P[id].allies.delete(vid);
    this.emit('eliminated', { v, by, gold });
  }

  // анклавы: кусок земли, со всех сторон (по суше, без выхода к морю) окружённый одним враждебным игроком, отходит ему
  enclaves() {
    if (!this.dirtyEnclave) return;
    this.dirtyEnclave = false;
    const n = N_TILES, o = this.owner;
    if (!this.lab) { this.lab = new Int32Array(n); this.stk = new Int32Array(n); }
    const lab = this.lab, stk = this.stk;
    lab.fill(0);
    const cSize = [0], cOwner = [0], cSur = [0], cStart = [0];
    const best = new Int32Array(this.P.length), bestSize = new Int32Array(this.P.length);
    for (let s = 0; s < n; s++) {
      const id = o[s];
      if (!id || lab[s]) continue;
      const c = cSize.length;
      let sp = 0, size = 0, sur = -2;
      stk[sp++] = s; lab[s] = c;
      while (sp) {
        const t = stk[--sp]; size++;
        const x = t % W;
        for (let k = 0; k < 4; k++) {
          let nb;
          if (k === 0) { if (x === 0) continue; nb = t - 1; } else if (k === 1) { if (x === W - 1) continue; nb = t + 1; } else if (k === 2) { if (t < W) continue; nb = t - W; } else { if (t >= n - W) continue; nb = t + W; }
          const on = o[nb];
          if (on === id) { if (!lab[nb]) { lab[nb] = c; stk[sp++] = nb; } continue; }
          if (on === 0) { sur = -1; continue; } // ничья земля или вода рядом — не окружён
          if (sur === -2) sur = on; else if (sur !== on) sur = -1;
        }
      }
      cSize.push(size); cOwner.push(id); cSur.push(sur); cStart.push(s);
      if (size > bestSize[id]) { bestSize[id] = size; best[id] = c; }
    }
    for (let c = 1; c < cSize.length; c++) {
      const id = cOwner[c], sur = cSur[c];
      if (sur <= 0) continue;
      const p = this.P[id], q = this.P[sur];
      if (!p.alive || !q.alive || this.allied(p, q)) continue;
      if (best[id] === c && p.tiles >= ELIM_TILES) continue; // основная земля не трогается
      // перекрасить компоненту
      let sp = 0; stk[sp++] = cStart[c]; lab[cStart[c]] = -1;
      const list = [];
      while (sp) {
        const t = stk[--sp]; list.push(t);
        const x = t % W;
        if (x > 0 && lab[t - 1] === c) { lab[t - 1] = -1; stk[sp++] = t - 1; }
        if (x < W - 1 && lab[t + 1] === c) { lab[t + 1] = -1; stk[sp++] = t + 1; }
        if (t >= W && lab[t - W] === c) { lab[t - W] = -1; stk[sp++] = t - W; }
        if (t < n - W && lab[t + W] === c) { lab[t + W] = -1; stk[sp++] = t + W; }
      }
      for (const t of list) this.setOwner(t, sur);
      this.emit('enclave', { from: p, to: q, n: list.length });
      if (p.tiles === 0) this.eliminate(p, q);
      else if (p.tiles < ELIM_TILES && best[id] === c) this.eliminate(p, q);
    }
  }

  // ---------- постройки ----------
  // цена (как в оригинале): n = min(Σ уровней в собственности, включая строящиеся; оплаченных построек) —
  // захваченные постройки цену не поднимают. Порт и завод делят один счётчик.
  levelsOf(p, types) { let s = 0; for (const x of this.structs) if (x.owner === p.id && types.includes(x.type)) s += x.level + (x.pending || 0); return s; }
  shipsOf(p) { let n = 0; for (const s of this.ships) if (s.owner === p) n++; return n; }
  countOf(p, type) {
    if (type === 'warship') return this.shipsOf(p);
    let n = 0; for (const s of this.structs) if (s.owner === p.id && s.type === type) n++; return n;
  }
  cost(p, type) {
    if (type === 'silo') return 1e6;
    if (type === 'warship') return Math.min(1e6, (Math.min(this.shipsOf(p), p.paid.warship) + 1) * 250000);
    const pf = type === 'port' || type === 'factory';
    const types = pf ? ['port', 'factory'] : [type];
    const n = Math.min(this.levelsOf(p, types), pf ? p.paid.port + p.paid.factory : p.paid[type]);
    if (type === 'city' || pf) return Math.min(1e6, Math.pow(2, n) * 125000);
    if (type === 'post') return Math.min(250000, (n + 1) * 50000);
    if (type === 'sam') return Math.min(3e6, (n + 1) * 1.5e6);
    return 0;
  }
  structNear(t, r, pred) {
    const x = t % W, y = (t / W) | 0, R2 = r * r;
    let best = null, bd = 1e9;
    for (const s of this.structs) {
      if (pred && !pred(s)) continue;
      const dx = (s.tile % W) - x, dy = ((s.tile / W) | 0) - y, d = dx * dx + dy * dy;
      if (d <= R2 && d < bd) { bd = d; best = s; }
    }
    return best;
  }
  // постройки любых владельцев рядом с тапом (для проверки отступа)
  nearList(t0, r) {
    const x0 = t0 % W, y0 = (t0 / W) | 0, out = [];
    for (const s of this.structs) { const dx = (s.tile % W) - x0, dy = ((s.tile / W) | 0) - y0; if (dx * dx + dy * dy <= r * r) out.push(s); }
    return out;
  }
  spaced(t, list) {
    const x = t % W, y = (t / W) | 0, G2 = STRUCT_GAP * STRUCT_GAP;
    for (const s of list) { const dx = (s.tile % W) - x, dy = ((s.tile / W) | 0) - y; if (dx * dx + dy * dy < G2) return false; }
    return true;
  }
  // ближайшая своя клетка в радиусе SNAP_R от тапа, не ближе STRUCT_GAP к любой постройке
  snapTile(p, t0) {
    const o = this.owner, id = p.id, x0 = t0 % W, y0 = (t0 / W) | 0, R = SNAP_R;
    const list = this.nearList(t0, R + STRUCT_GAP + 1);
    let best = -1, bd = 1e9;
    for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
      const d = dx * dx + dy * dy; if (d > R * R || d >= bd) continue;
      const x = x0 + dx, y = y0 + dy; if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const t = y * W + x;
      if (o[t] !== id || !this.isLand(t) || !this.spaced(t, list)) continue;
      best = t; bd = d;
    }
    return best;
  }
  // порт: ближайшая своя береговая клетка в пределах PORT_R (манхэттен)
  snapPort(p, t0) {
    const o = this.owner, id = p.id, x0 = t0 % W, y0 = (t0 / W) | 0, R = PORT_R, shore = this.w.shore;
    const list = this.nearList(t0, R + STRUCT_GAP + 1);
    let best = -1, bd = 1e9;
    for (let dy = -R; dy <= R; dy++) for (let dx = -R + Math.abs(dy); dx <= R - Math.abs(dy); dx++) {
      const d = dx * dx + dy * dy; if (d >= bd) continue;
      const x = x0 + dx, y = y0 + dy; if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const t = y * W + x;
      if (o[t] !== id || !shore[t] || !this.spaced(t, list)) continue;
      best = t; bd = d;
    }
    return best;
  }
  // куда встанет постройка при тапе в t0: { tile, up (улучшаемая постройка), ok, reason }
  placement(p, type, t0) {
    if (t0 < 0) return { tile: -1, up: null, ok: false, reason: 'far' };
    if (type === 'warship') {
      const port = this.shipPort(p, t0);
      return port ? { tile: port.tile, up: null, ok: true, port } : { tile: t0, up: null, ok: false, reason: 'port' };
    }
    const S = STRUCTS[type];
    if (S.upg) {
      const up = this.structNear(t0, SNAP_R, (s) => s.owner === p.id && s.type === type);
      if (up) return up.built && !up.pending ? { tile: up.tile, up, ok: true } : { tile: up.tile, up, ok: false, reason: 'busy' };
    }
    const t = type === 'port' ? this.snapPort(p, t0) : this.snapTile(p, t0);
    if (t < 0) return { tile: t0, up: null, ok: false, reason: this.owner[t0] !== p.id ? 'own' : type === 'port' ? 'shore' : 'space' };
    return { tile: t, up: null, ok: true };
  }
  build(p, type, t0) {
    if (!p.alive || this.over) return { ok: false, reason: 'dead' };
    const pl = this.placement(p, type, t0);
    if (!pl.ok) return { ok: false, reason: pl.reason, tile: pl.tile };
    const c = this.cost(p, type);
    if (p.gold < c) return { ok: false, reason: 'gold', cost: c, tile: pl.tile };
    p.gold -= c; p.paid[type]++;
    if (type === 'warship') {
      const s = this.addShip(p, pl.port, t0);
      this.emit('build', { s, upgrade: false, p, ship: true });
      return { ok: true, s, ship: true };
    }
    const S = STRUCTS[type];
    if (pl.up) {
      const up = pl.up;
      up.pending = 1; up.startAt = this.tickN; up.doneAt = this.tickN + S.time;
      this.emit('build', { s: up, upgrade: true, p });
      return { ok: true, s: up, upgrade: true };
    }
    const s = { id: this.structSeq++, type, owner: p.id, builder: p.id, tile: pl.tile, level: 1, pending: 0, built: false, startAt: this.tickN, doneAt: this.tickN + S.time, born: this.tickN };
    this.structAt[pl.tile] = this.structs.length;
    this.structs.push(s);
    if (type === 'post') p.posts.push(s);
    this.emit('build', { s, upgrade: false, p });
    return { ok: true, s };
  }
  // уровни достроенных городов (лимит войск), портов и заводов (доход)
  recountCities(p) {
    let c = 0, po = 0, f = 0;
    for (const s of this.structs) {
      if (s.owner !== p.id || !s.built) continue;
      if (s.type === 'city') c += s.level; else if (s.type === 'port') po += s.level; else if (s.type === 'factory') f += s.level;
    }
    p.cityLevels = c; p.portLevels = po; p.factLevels = f;
  }
  removeStruct(s) {
    const i = this.structs.indexOf(s);
    if (i < 0) return;
    this.structs.splice(i, 1);
    this.structAt[s.tile] = -1;
    for (let k = i; k < this.structs.length; k++) this.structAt[this.structs[k].tile] = k;
    const P = this.P[s.owner];
    if (P) { const j = P.posts.indexOf(s); if (j >= 0) P.posts.splice(j, 1); this.recountCities(P); }
    if (s.type === 'post' && s.built) this.emit('defense', { s });
  }
  captureStruct(s, to, from) {
    if (s.type === 'post' || !to) { this.removeStruct(s); this.emit('capture', { s, from: this.P[from], to: this.P[to], destroyed: true }); return; }
    s.owner = to;
    if (from) this.recountCities(this.P[from]);
    this.recountCities(this.P[to]);
    this.emit('capture', { s, from: this.P[from], to: this.P[to], destroyed: false });
  }
  // защищена ли клетка t владельца постом (для отрисовки «шахматки» на границе)
  defended(id, t) { const p = this.P[id]; return !!p && p.posts.length > 0 && this.hasPostNear(p, t); }

  // ---------- вода: поиск пути (BFS) для десанта и кораблей ----------
  isWater(t) { return this.terr[t] < T_PLAINS; }
  bfsInit() {
    if (!this.bPrev) { this.bPrev = new Int32Array(N_TILES); this.bSeen = new Uint32Array(N_TILES); this.bQ = new Int32Array(N_TILES); this.bStamp = 0; }
    return ++this.bStamp;
  }
  // водоёмы (связные куски воды) — корабль строится только в порту того же водоёма
  waterBody() {
    if (this.wb) return this.wb;
    const wb = this.wb = new Int32Array(N_TILES), q = new Int32Array(N_TILES);
    let id = 0;
    for (let s = 0; s < N_TILES; s++) {
      if (wb[s] || !this.isWater(s)) continue;
      id++; let h = 0, tl = 0; q[tl++] = s; wb[s] = id;
      while (h < tl) {
        const t = q[h++], x = t % W;
        if (x > 0 && !wb[t - 1] && this.isWater(t - 1)) { wb[t - 1] = id; q[tl++] = t - 1; }
        if (x < W - 1 && !wb[t + 1] && this.isWater(t + 1)) { wb[t + 1] = id; q[tl++] = t + 1; }
        if (t >= W && !wb[t - W] && this.isWater(t - W)) { wb[t - W] = id; q[tl++] = t - W; }
        if (t < N_TILES - W && !wb[t + W] && this.isWater(t + W)) { wb[t + W] = id; q[tl++] = t + W; }
      }
    }
    return wb;
  }
  // связана ли клетка t по суше (через земли того же владельца) с территорией p — иначе только десантом
  landConnected(p, t0) {
    if (t0 < 0 || !this.isLand(t0)) return false;
    const st = this.bfsInit(), seen = this.bSeen, Q = this.bQ, o = this.owner, id = o[t0], pid = p.id;
    let h = 0, tl = 0; seen[t0] = st; Q[tl++] = t0;
    while (h < tl) {
      const t = Q[h++], x = t % W;
      for (let k = 0; k < 4; k++) {
        let nb;
        if (k === 0) { if (x === 0) continue; nb = t - 1; } else if (k === 1) { if (x === W - 1) continue; nb = t + 1; } else if (k === 2) { if (t < W) continue; nb = t - W; } else { if (t >= N_TILES - W) continue; nb = t + W; }
        if (o[nb] === pid && this.isLand(nb)) return true;
        if (seen[nb] === st || o[nb] !== id || !this.isLand(nb)) continue;
        seen[nb] = st; Q[tl++] = nb;
      }
    }
    return false;
  }
  // береговая клетка того же владельца рядом с тапом (куда высаживаться)
  landingNear(t0) {
    if (t0 < 0 || !this.isLand(t0)) return -1;
    const id = this.owner[t0], shore = this.w.shore;
    if (shore[t0]) return t0;
    return this.w.nearest(t0, 30, (t) => shore[t] && this.owner[t] === id && this.isLand(t));
  }
  // маршрут десанта p к береговой клетке land: путь по воде от своего берега до цели
  boatRoute(p, land) {
    if (land < 0) return null;
    const st = this.bfsInit(), prev = this.bPrev, seen = this.bSeen, Q = this.bQ, o = this.owner, id = p.id;
    let h = 0, tl = 0;
    const lx = land % W;
    for (const nb of [lx > 0 ? land - 1 : -1, lx < W - 1 ? land + 1 : -1, land - W, land + W]) {
      if (nb < 0 || nb >= N_TILES || !this.isWater(nb) || seen[nb] === st) continue;
      seen[nb] = st; prev[nb] = -1; Q[tl++] = nb;
    }
    let goal = -1, src = -1;
    while (h < tl && goal < 0) {
      const t = Q[h++], x = t % W;
      for (let k = 0; k < 4; k++) {
        let nb;
        if (k === 0) { if (x === 0) continue; nb = t - 1; } else if (k === 1) { if (x === W - 1) continue; nb = t + 1; } else if (k === 2) { if (t < W) continue; nb = t - W; } else { if (t >= N_TILES - W) continue; nb = t + W; }
        if (o[nb] === id && this.isLand(nb)) { goal = t; src = nb; break; }
        if (seen[nb] === st || !this.isWater(nb)) continue;
        seen[nb] = st; prev[nb] = t; Q[tl++] = nb;
      }
    }
    if (goal < 0) return null;
    const path = [];
    for (let t = goal; t >= 0; t = prev[t]) path.push(t);
    return { path: Int32Array.from(path), land, src };
  }
  // разведка для ИИ: ближайший достижимый по воде берег, где ok(клетка суши) — от своего берега наружу
  boatScout(p, ok, maxVisit = 90000) {
    const st = this.bfsInit(), prev = this.bPrev, seen = this.bSeen, Q = this.bQ;
    let h = 0, tl = 0;
    for (const t of p.border) {
      if (!this.w.shore[t]) continue;
      const x = t % W;
      for (const nb of [x > 0 ? t - 1 : -1, x < W - 1 ? t + 1 : -1, t - W, t + W]) {
        if (nb < 0 || nb >= N_TILES || !this.isWater(nb) || seen[nb] === st) continue;
        seen[nb] = st; prev[nb] = -1; Q[tl++] = nb;
      }
    }
    let goal = -1, land = -1;
    while (h < tl && goal < 0 && h < maxVisit) {
      const t = Q[h++], x = t % W;
      for (let k = 0; k < 4; k++) {
        let nb;
        if (k === 0) { if (x === 0) continue; nb = t - 1; } else if (k === 1) { if (x === W - 1) continue; nb = t + 1; } else if (k === 2) { if (t < W) continue; nb = t - W; } else { if (t >= N_TILES - W) continue; nb = t + W; }
        if (seen[nb] === st) continue;
        if (!this.isWater(nb)) { if (this.isLand(nb) && this.owner[nb] !== p.id && ok(nb)) { goal = t; land = nb; break; } continue; }
        seen[nb] = st; prev[nb] = t; Q[tl++] = nb;
      }
    }
    if (goal < 0) return null;
    const path = [];
    for (let t = goal; t >= 0; t = prev[t]) path.push(t);
    path.reverse();
    return { path: Int32Array.from(path), land };
  }
  // отправить десант: troops — внутренние единицы, land — клетка высадки (береговая)
  sendBoat(p, land, troops, route = null) {
    if (!p.alive || this.over) return { ok: false, reason: 'dead' };
    if (p.boats.length >= BOAT_MAX) return { ok: false, reason: 'boats' };
    const id = this.owner[land], target = id ? this.P[id] : null;
    if (target === p) return { ok: false, reason: 'bad' };
    if (target && !this.canAttack(p, target)) return { ok: false, reason: this.allied(p, target) ? 'ally' : 'immune' };
    troops = Math.floor(Math.min(troops, p.troops));
    if (troops < 1) return { ok: false, reason: 'few' };
    const r = route || this.boatRoute(p, land);
    if (!r || r.path.length < 1) return { ok: false, reason: 'noroute' };
    p.troops -= troops;
    const b = { id: this.boatSeq++, owner: p, target, land: r.land, path: r.path, i: 0, troops, back: false, born: this.tickN };
    p.boats.push(b); this.boats.push(b);
    if (target) target.hitBy.set(p.id, this.tickN);
    this.emit('boat', { b });
    return { ok: true, b, troops };
  }
  boatPos(b) {
    const P = b.path, i = Math.max(0, Math.min(P.length - 1, b.i)), k = Math.floor(i), f = i - k;
    const a = P[k], c = P[Math.min(P.length - 1, k + 1)];
    return [(a % W) + 0.5 + ((c % W) - (a % W)) * f, ((a / W) | 0) + 0.5 + (((c / W) | 0) - ((a / W) | 0)) * f];
  }
  killBoat(b) {
    if (b.dead) return;
    b.dead = true;
    let i = b.owner.boats.indexOf(b); if (i >= 0) b.owner.boats.splice(i, 1);
    i = this.boats.indexOf(b); if (i >= 0) this.boats.splice(i, 1);
  }
  retreatBoat(b) { if (!b.dead && !b.back) { b.back = true; this.emit('retreat', { b }); } }
  stepBoat(b) {
    const p = b.owner;
    if (!p.alive) { this.killBoat(b); return; }
    if (b.back) {
      b.i -= BOAT_SPEED;
      if (b.i <= 0) { const back = b.troops * 0.75; p.troops += back; this.killBoat(b); this.emit('boatHome', { b, back }); }
      return;
    }
    b.i += BOAT_SPEED;
    if (b.i < b.path.length - 1) return;
    const L = b.land, id = this.owner[L], q = id ? this.P[id] : null;
    this.killBoat(b);
    if (!this.isLand(L) || id === p.id || (q && !this.canAttack(p, q))) { p.troops += b.troops; this.emit('boatHome', { b, back: b.troops }); return; }
    this.setOwner(L, p.id); // плацдарм
    const r = this.attack(p, q, b.troops, true);
    if (!r.ok) p.troops += b.troops;
    this.emit('boatLand', { b, target: q, attack: r.attack || null });
  }

  // ---------- военные корабли ----------
  // ближайший достроенный свой порт в том же водоёме, что и вода у тапа
  shipPort(p, t0) {
    const wb = this.waterBody();
    let w0 = -1;
    if (this.isWater(t0)) w0 = wb[t0];
    else { const t = this.w.nearest(t0, 6, (t) => this.isWater(t)); if (t >= 0) w0 = wb[t]; }
    let best = null, bd = 1e18;
    for (const s of this.structs) {
      if (s.owner !== p.id || s.type !== 'port' || !s.built) continue;
      const wt = this.portWater(s.tile); if (wt < 0 || (w0 >= 0 && wb[wt] !== w0)) continue;
      const dx = (s.tile % W) - (t0 % W), dy = ((s.tile / W) | 0) - ((t0 / W) | 0), d = dx * dx + dy * dy;
      if (d < bd) { bd = d; best = s; }
    }
    return best;
  }
  portWater(t) { const x = t % W; for (const nb of [x > 0 ? t - 1 : -1, x < W - 1 ? t + 1 : -1, t - W, t + W]) if (nb >= 0 && nb < N_TILES && this.isWater(nb)) return nb; return -1; }
  addShip(p, port, tap) {
    const w = this.portWater(port.tile);
    const patrol = this.isWater(tap) ? tap : w;
    const s = { id: this.boatSeq++, kind: 'warship', owner: p, tile: w, hp: SHIP.hp, patrol, goal: patrol, path: null, pi: 0, mv: 0, wait: 0, reload: 0, home: port.tile, born: this.tickN, shotAt: -99, shot: null };
    this.ships.push(s);
    return s;
  }
  killShip(s) { const i = this.ships.indexOf(s); if (i >= 0) this.ships.splice(i, 1); s.dead = true; }
  moveShip(s, tile) { if (this.isWater(tile)) { s.patrol = tile; s.goal = tile; s.path = null; } }
  // короткий путь по воде (BFS с ограничением) от s.tile к goal
  shipPath(s, goal) {
    const st = this.bfsInit(), prev = this.bPrev, seen = this.bSeen, Q = this.bQ;
    let h = 0, tl = 0; seen[s.tile] = st; prev[s.tile] = -1; Q[tl++] = s.tile;
    let found = -1;
    while (h < tl && h < 60000) {
      const t = Q[h++];
      if (t === goal) { found = t; break; }
      const x = t % W;
      for (const nb of [x > 0 ? t - 1 : -1, x < W - 1 ? t + 1 : -1, t - W, t + W]) {
        if (nb < 0 || nb >= N_TILES || seen[nb] === st || !this.isWater(nb)) continue;
        seen[nb] = st; prev[nb] = t; Q[tl++] = nb;
      }
    }
    if (found < 0) return null;
    const path = [];
    for (let t = found; t >= 0; t = prev[t]) path.push(t);
    return path.reverse();
  }
  stepShip(s) {
    const p = s.owner;
    // огонь: вражеский десант (приоритет), затем вражеские корабли в радиусе
    if (s.reload > 0) s.reload--;
    if (!s.reload) {
      const [sx, sy] = this.shipXY(s);
      let tgt = null, td = SHIP.range * SHIP.range;
      for (const b of this.boats) {
        if (b.owner === p || this.allied(p, b.owner)) continue;
        const [bx, by] = this.boatPos(b), d = (bx - sx) ** 2 + (by - sy) ** 2;
        if (d < td) { td = d; tgt = b; }
      }
      if (!tgt) for (const o of this.ships) {
        if (o === s || o.owner === p || this.allied(p, o.owner)) continue;
        const [ox, oy] = this.shipXY(o), d = (ox - sx) ** 2 + (oy - sy) ** 2;
        if (d < td) { td = d; tgt = o; }
      }
      if (tgt) {
        s.reload = SHIP.reload; s.shotAt = this.tickN;
        const dmg = SHIP.dmg[0] + Math.random() * (SHIP.dmg[1] - SHIP.dmg[0]);
        if (tgt.kind === 'warship') {
          s.shot = this.shipXY(tgt);
          tgt.hp -= dmg;
          if (tgt.hp <= 0) { this.killShip(tgt); this.emit('shipSunk', { s: tgt, by: p }); }
        } else {
          s.shot = this.boatPos(tgt);
          this.killBoat(tgt); // транспорт тонет с одного попадания, войска гибнут
          this.emit('boatSunk', { b: tgt, by: p });
        }
      }
    }
    // движение: к цели патруля; по прибытии — новая точка в радиусе патруля
    if (s.wait > 0) { s.wait--; return; }
    if (!s.path) {
      if (s.tile === s.goal) {
        const px = s.patrol % W, py = (s.patrol / W) | 0, R = SHIP.patrol * 0.5;
        for (let k = 0; k < 12; k++) {
          const x = px + Math.round((Math.random() * 2 - 1) * R), y = py + Math.round((Math.random() * 2 - 1) * R);
          if (x < 0 || y < 0 || x >= W || y >= H) continue;
          const t = y * W + x;
          if (this.isWater(t)) { s.goal = t; break; }
        }
      }
      s.path = s.goal !== s.tile ? this.shipPath(s, s.goal) : null; s.pi = 1;
      if (!s.path) { s.goal = s.tile; s.wait = 30; return; }
    }
    s.mv = (s.mv || 0) + SHIP.speed;
    while (s.mv >= 1 && s.pi < s.path.length) { s.mv -= 1; s.tile = s.path[s.pi++]; }
    if (s.pi >= s.path.length) s.path = null;
  }
  shipXY(s) { return [(s.tile % W) + 0.5, ((s.tile / W) | 0) + 0.5]; }

  // ---------- цикл ----------
  tick() {
    if (!this.running || this.over) return;
    const t = ++this.tickN;
    const P = this.P;
    for (let i = 1; i < P.length; i++) {
      const p = P[i];
      if (!p.alive) continue;
      p.troops += this.regen(p);
      p.gold += this.goldRate(p);
      const tot = p.troops + this.troopsAtWar(p);
      if (tot > p.maxTroopsSeen) p.maxTroopsSeen = tot;
    }
    for (let i = 0; i < this.attacks.length; i++) { const a = this.attacks[i]; if (!a.dead) this.stepAttack(a); }
    if (this.attacks.some((a) => a.dead)) this.attacks = this.attacks.filter((a) => !a.dead);
    for (let i = this.boats.length - 1; i >= 0; i--) { const b = this.boats[i]; if (b && !b.dead) this.stepBoat(b); }
    for (let i = this.ships.length - 1; i >= 0; i--) { const s = this.ships[i]; if (s && !s.dead) this.stepShip(s); }
    for (const s of this.structs) {
      if (s.doneAt === t) {
        s.built = true;
        if (s.pending) { s.level += s.pending; s.pending = 0; }
        this.recountCities(P[s.owner]);
        this.emit('built', { s });
        if (s.type === 'post') this.emit('defense', { s });
      }
    }
    if (this.brain) this.brain(this);
    if (t % 20 === 0) this.enclaves();
    this.flush();
    if (t % 10 === 0) this.checkEnd();
  }
  leader() { let L = null; for (let i = 1; i < this.P.length; i++) { const p = this.P[i]; if (p.alive && (!L || p.tiles > L.tiles)) L = p; } return L; }
  checkEnd() {
    if (this.over) return;
    const L = this.leader();
    if (!L) return;
    if (L.tiles >= WIN_SHARE * this.winLand) this.finish(L, 'share');
    else if (this.tickN >= MATCH_TICKS) this.finish(L, 'time');
  }
  finish(winner, reason) {
    if (this.over) return;
    this.over = true;
    this.emit('end', { winner, reason });
  }
}

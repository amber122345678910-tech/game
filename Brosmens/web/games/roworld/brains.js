// BroWorld — ИИ как в оригинале (OpenFront). Нации: порог атаки 50–60% лимита, резерв 30–40%, расширение
// 10–20%, ход раз в 4.5–6 с (сложность «Hard»), действия разнесены по третям цикла: расширение и поедание
// племён → атака (контратака обидчика, предатели, слабые соседи по войскам на клетку) → постройки и десант.
// Племена: слабые, кусают соседей войсками/20 раз в 4–8 с. Боты-игроки ведут себя как люди: спамят
// расширение, едят племена и слабых, во время защиты не трогают людей. Клод — союзник игрока.
import { KIND, SPAWN_GAP, TRIBE_GAP, BOAT_MAX, PROT_TICKS, NUKES } from './game.js';
import { W, H, N_TILES, T_MTN } from './world.js';

const ri = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
const rf = (a, b) => a + Math.random() * (b - a);

// ---------- выбор стартовой точки (этап «Выбери стартовую точку») ----------
// t подходит игроку p: свободная суша и отступ от уже поставленных столиц (30 клеток оригинала между
// игроками, у племён плотнее). Клод ставится рядом с игроком и с ним отступ не проверяется.
export function spawnOk(g, t, p, ignore = null) {
  if (!g.canSpawn(t)) return false;
  const x = t % W, y = (t / W) | 0;
  for (let i = 1; i < g.P.length; i++) {
    const q = g.P[i];
    if (q === p || q === ignore || q.spawn < 0 || !q.alive) continue;
    if ((p.isClaude && q.isPlayer) || (p.isPlayer && q.isClaude)) continue;
    const gap = p.kind === KIND.TRIBE || q.kind === KIND.TRIBE ? TRIBE_GAP : SPAWN_GAP;
    const dx = (q.spawn % W) - x, dy = ((q.spawn / W) | 0) - y;
    if (dx * dx + dy * dy < gap * gap) return false;
  }
  return true;
}
// точка для бота: нация — у своих реальных координат, остальные — случайно по суше (Антарктида — в крайнем случае)
export function pickSpawnTile(g, world, p, coord) {
  if (coord) {
    const [lat, lon] = coord;
    const t = world.nearest(world.tileOf(lon, lat), 40, (x) => spawnOk(g, x, p));
    if (t >= 0) return t;
  }
  for (let tries = 0; tries < 3000; tries++) {
    const c = Math.floor(Math.random() * N_TILES);
    if (!g.isLand(c) || g.owner[c]) continue;
    if (p.kind !== KIND.TRIBE && world.terr[c] === T_MTN && tries < 1800) continue;
    if (((c / W) | 0) > H * 0.88 && tries < 2400) continue;
    if (spawnOk(g, c, p)) return c;
  }
  return -1;
}

// столица Клода: в 30–46 клетках от игрока, там, где вокруг много свободной земли, которая ближе к Клоду, чем
// к игроку (чтобы друзья не делили одну поляну). Возвращает клетку или -1.
export const CLAUDE_ZONE_R = 26, CLAUDE_ZONE_TICKS = 2400;
export function placeClaudeTile(g, world, me, claude) {
  if (me.spawn < 0) return -1;
  const cx = me.spawn % W, cy = (me.spawn / W) | 0;
  let best = -1, bs = -1e9;
  for (let k = 0; k < 500; k++) {
    const a = Math.random() * 6.283, r = 30 + Math.random() * 16;
    const x = Math.round(cx + Math.cos(a) * r), y = Math.round(cy + Math.sin(a) * r);
    if (x < 0 || y < 0 || x >= W || y >= H) continue;
    const t = y * W + x;
    if (!spawnOk(g, t, claude)) continue;
    let room = 0; // свободная суша вокруг, которая ближе к кандидату, чем к игроку
    for (let i = 0; i < 24; i++) {
      const b = (i / 24) * 6.283, rr = i & 1 ? 22 : 12;
      const sx = Math.round(x + Math.cos(b) * rr), sy = Math.round(y + Math.sin(b) * rr);
      if (sx < 0 || sy < 0 || sx >= W || sy >= H) continue;
      const st = sy * W + sx;
      if (!g.isLand(st) || g.owner[st]) continue;
      if ((sx - cx) ** 2 + (sy - cy) ** 2 > (sx - x) ** 2 + (sy - y) ** 2) room++;
    }
    const sc = room * 3 + g.spawnTilesAt(t).length * 0.3 + Math.random() * 6 - (world.terr[t] === T_MTN ? 12 : 0);
    if (sc > bs) { bs = sc; best = t; }
  }
  if (best < 0) best = world.nearest(me.spawn, 90, (t) => spawnOk(g, t, claude));
  return best;
}

export function setupBrain(g, me) {
  const cnt = new Int32Array(g.P.length + 1);
  const touched = [];
  for (const p of g.P) {
    if (!p || p.isPlayer) continue;
    const ai = p.ai;
    if (p.kind === KIND.NATION) Object.assign(ai, { trigger: rf(0.5, 0.6), reserve: rf(0.3, 0.4), expand: rf(0.1, 0.2), rate: ri(45, 60), step: 0, next: ri(1, 40), boatAt: -9999, sly: Math.random() < 0.3 });
    else if (p.kind === KIND.TRIBE) Object.assign(ai, { reserve: rf(0.3, 0.4), next: ri(5, 60) });
    else {
      const skill = p.isClaude ? 0.8 : p.leader?.skill ?? 0.6; // «нубы» тапают реже и тратят войска неумело
      Object.assign(ai, { skill, ratio: skill > 0.6 ? 0.25 : Math.random() < 0.5 ? 0.35 : 0.5, toxic: p.leader?.toxic ?? 0.4, rate: Math.round(22 + (1 - skill) * 40), next: ri(1, 20), boatAt: -9999, step: 0 });
    }
  }

  // соседи по суше и свободная земля вдоль границы
  function scan(p) {
    const o = g.owner, id = p.id;
    let free = 0;
    touched.length = 0;
    const see = (nb) => {
      const q = o[nb];
      if (q === id) return;
      if (q === 0) { if (g.isLand(nb) && !g.fall[nb] && !(p.isClaude && g.claudeSkip(nb))) free++; return; } // радиацию ИИ не считает свободной землёй
      if (!cnt[q]) touched.push(q);
      cnt[q]++;
    };
    for (const t of p.border) {
      const x = t % W;
      if (x > 0) see(t - 1);
      if (x < W - 1) see(t + 1);
      if (t >= W) see(t - W);
      if (t < N_TILES - W) see(t + W);
    }
    const nb = touched.map((q) => ({ q: g.P[q], n: cnt[q] }));
    for (const q of touched) cnt[q] = 0;
    return { free, nb };
  }

  const attacking = (a, b) => { for (const x of a.attacks) if (!x.dead && x.target === b) return true; return false; };
  const density = (q) => q.troops / Math.max(1, q.tiles);
  const recentHit = (p, q, ticks = 300) => { const h = p.hitBy.get(q.id); return h !== undefined && g.tickN - h < ticks; };

  // цель для атаки: обидчик (контратака) > предатель > слабый сосед (мало войск на клетку) > племя
  function chooseTarget(p, info, strict = 1) {
    let best = null, bs = 0;
    const t = g.tickN, myD = density(p);
    for (const { q, n } of info.nb) {
      if (!g.canAttack(p, q)) continue;
      if (p.isClaude && (q.isPlayer || g.allied(q, me))) continue;
      const hit = recentHit(p, q);
      // Клод в первые минуты не задирает нации и ботов — ест племена и защищает игрока
      if (p.isClaude && t < PROT_TICKS && q.kind !== KIND.TRIBE && !hit && !attacking(q, me)) continue;
      const friend = q.isPlayer || q.isClaude; // игрок и его друг Клод: без повода их не травят
      if (friend && !hit) {
        if (t < (p.kind === KIND.NATION ? 2400 : PROT_TICKS + 600)) continue; // в первые минуты игрока не травят
        if (g.attackersOn(q) >= 2 && !attacking(p, q)) continue; // не наваливаться толпой
      }
      const ratio = (p.troops + 1) / (q.troops + 1);
      // слабый: мало войск на клетку или просто заметно меньше войск (большой стране плотность не важна);
      // на игрока без повода (он не бил первым и не лидирует) — только при двойном перевесе
      const weak = (density(q) < myD * 0.7 && q.troops < p.troops * 0.75) || ratio >= (friend && q !== lead ? 2 : 1.4);
      if (!hit && !g.isTraitor(q) && q.kind !== KIND.TRIBE && !weak && strict > 0) continue;
      // пока вокруг есть ничья земля, на сильных соседей не лезут (кроме ответа обидчику)
      if (info.free > 6 && q.kind !== KIND.TRIBE && !hit && !g.isTraitor(q) && q.troops > p.troops * 0.35) continue;
      // выгода: перевес (с потолком, чтобы крошечные огрызки не забирали все ходы) × длина границы × размер добычи
      let s = Math.min(ratio, 4) * Math.sqrt(n) * (1 + Math.log10(1 + q.tiles / 150)) * rf(0.7, 1.3);
      if (q.kind === KIND.TRIBE) s *= 2.4;
      if (hit) s *= 4;
      if (g.isTraitor(q)) s *= 3;
      if (info.free && q.kind !== KIND.TRIBE && !hit) s *= 0.2;
      if (q.isPlayer) s *= p.kind === KIND.HUMAN ? 0.4 + p.ai.toxic : 0.8;
      if (p.isClaude && attacking(q, me)) s *= 6; // Клод бьёт тех, кто напал на игрока
      if (q === lead && q.tiles > g.winLand * 0.35) s *= 1.8; // лидера к концу матча «заваливают» толпой
      if (q.kind !== KIND.TRIBE && !friend && q.troops < p.troops * 0.35) s *= 2; // добить слабого — меньше игроков, быстрее развязка
      if (p === lead && p.tiles > g.winLand * 0.2) s *= 1 + p.tiles / g.winLand; // лидер давит к победе
      if (s > bs) { bs = s; best = q; }
    }
    return best;
  }

  // десант: ближайший по воде берег (свободный или враждебный) — когда на суше расти некуда;
  // prefer — высадка именно к этому сопернику (крупная страна за морем)
  let scoutTick = -1;
  // десант против того, кто в разы сильнее, бессмысленен (и только спамит ленту событий)
  const worthBoat = (p, q, troops) => !q || q.kind === KIND.TRIBE || (troops >= q.troops * 0.25 && q.troops < p.troops * 1.2);
  // берег цели, ближайший к нашей столице (куда плыть десанту)
  function coastOf(q, p) {
    const shore = g.w.shore, base = p.spawn >= 0 ? p.spawn : p.border.values().next().value;
    if (base === undefined) return -1;
    const bx = base % W, by = (base / W) | 0;
    let best = -1, bd = 1e9, k = 0;
    for (const t of q.border) {
      if (!shore[t]) continue;
      const d = Math.abs((t % W) - bx) + Math.abs(((t / W) | 0) - by);
      if (d < bd) { bd = d; best = t; }
      if (++k > 5000) break;
    }
    return best;
  }
  // большой стране некуда расти по суше: самая выгодная цель за морем (слабее нас и не слишком далеко)
  function overseasTarget(p, troops) {
    const base = p.spawn >= 0 ? p.spawn : p.border.values().next().value;
    if (base === undefined) return null;
    const bx = base % W, by = (base / W) | 0;
    let best = null, bs = 0;
    for (let i = 1; i < g.P.length; i++) {
      const q = g.P[i];
      if (!q.alive || q === p || !q.tiles || !g.canAttack(p, q) || !worthBoat(p, q, troops)) continue;
      if (p.isClaude && (q.isPlayer || g.allied(q, me))) continue;
      if ((q.isPlayer || q.isClaude) && g.tickN < PROT_TICKS + 600 && !recentHit(p, q)) continue;
      const qb = q.spawn >= 0 && g.owner[q.spawn] === q.id ? q.spawn : q.border.values().next().value;
      if (qb === undefined) continue;
      const d = Math.hypot((qb % W) - bx, ((qb / W) | 0) - by);
      const s = ((p.troops + 1) / (q.troops + 1)) * (1 + Math.log10(1 + q.tiles / 200)) / (1 + d / 250) * (q.kind === KIND.TRIBE ? 0.6 : 1) * rf(0.8, 1.2);
      if (s > bs) { bs = s; best = q; }
    }
    return best;
  }
  function tryBoat(p, troops, prefer = null) {
    const big = p.tiles > 2500;
    if (p.boats.length >= (p.kind === KIND.NATION || big ? 3 : 1) || p.boats.length >= BOAT_MAX || g.tickN - p.ai.boatAt < (prefer || big ? 120 : 250)) return false;
    if (prefer && !worthBoat(p, prefer, troops)) return false;
    if (scoutTick === g.tickN) return false; // поиск пути по воде — не больше одного за тик на весь сервер
    scoutTick = g.tickN;
    p.ai.boatAt = g.tickN - (p.kind === KIND.NATION ? 100 : 0);
    // выбранный соперник или большая страна: путь A* к ближайшему берегу цели (кэшируется), а не обход всего океана
    const q = prefer || (big ? overseasTarget(p, troops) : null);
    if (q) {
      const land = coastOf(q, p);
      const r = land >= 0 ? g.boatRoute(p, land, 90000) : null;
      return !!r && g.sendBoat(p, land, troops, r).ok;
    }
    const o = g.owner;
    const r = g.boatScout(p, (L) => {
      const id = o[L];
      if (!id) return !g.fall[L];
      const q = g.P[id];
      if (!g.canAttack(p, q) || (p.isClaude && (q.isPlayer || g.allied(q, me)))) return false;
      return q.kind === KIND.TRIBE || (density(q) < density(p) * 1.2 && worthBoat(p, q, troops));
    }, 20000);
    if (!r) return false;
    return g.sendBoat(p, r.land, troops, r).ok;
  }

  // постройка рядом со столицей/по территории; порт — на своём берегу
  function aiBuild(p, type) {
    if (p.gold < g.cost(p, type)) return false;
    const o = g.owner;
    let base = p.spawn;
    if (base < 0 || o[base] !== p.id) { const it = p.border.values().next(); if (it.done) return false; base = it.value; }
    if (type === 'port') { // несколько случайных своих береговых клеток (каждая попытка — поиск места с отступом)
      let k = 0, tries = 0;
      for (const t of p.border) {
        if (++k > 6000 || tries >= 6) break;
        if (!g.w.shore[t] || Math.random() > 0.08) continue;
        tries++;
        if (g.build(p, 'port', t).ok) return true;
      }
      return false;
    }
    if (type === 'warship') {
      const port = g.structs.find((s) => s.owner === p.id && s.type === 'port' && s.built);
      return !!port && g.build(p, 'warship', port.tile).ok;
    }
    const R = Math.max(6, Math.min(60, Math.sqrt(p.tiles) * 0.7));
    for (let k = 0; k < 14; k++) {
      const x = (base % W) + ri(-R, R), y = ((base / W) | 0) + ri(-R, R);
      if (x < 0 || y < 0 || x >= W || y >= H) continue;
      const t = y * W + x;
      if (o[t] !== p.id) continue;
      if (g.build(p, type, t).ok) return true;
    }
    return false;
  }
  // оборонный пост на «горячей» границе (с тем, кто недавно напал)
  function aiPost(p) {
    let foe = -1, ft = -1e9;
    for (const [id, t] of p.hitBy) if (t > ft && g.P[id].alive) { ft = t; foe = id; }
    if (foe < 0 || g.tickN - ft > 300 || p.gold < g.cost(p, 'post') || p.posts.length >= 1 + Math.ceil(p.cityLevels / 2)) return false;
    const o = g.owner;
    for (const t of p.border) {
      const x = t % W;
      if ((x > 0 && o[t - 1] === foe) || (x < W - 1 && o[t + 1] === foe) || (t >= W && o[t - W] === foe) || (t < N_TILES - W && o[t + W] === foe)) {
        return g.build(p, 'post', t).ok; // встанет на ближайшей своей клетке с отступом
      }
    }
    return false;
  }
  // нужна ли ПВО: по нам недавно били ядеркой, или середина матча, шахта уже есть, а ПВО мало
  function samWanted(p) {
    const t = g.tickN, sams = g.countOf(p, 'sam');
    if (p.nukedAt !== undefined && t - p.nukedAt < 3000 && sams < 1 + Math.floor(p.tiles / 6000)) return true;
    return t > 7000 && p.tiles > 1500 && g.countOf(p, 'silo') > 0 && sams < 1 + Math.floor(p.tiles / 15000);
  }
  // порядок построек наций: города → порты и заводы → посты на горячих границах → шахта и ПВО к середине
  function buildOrder(p) {
    const c = (t) => g.countOf(p, t), tiles = p.tiles, t = g.tickN;
    if (aiPost(p)) return;
    // ПВО: копим на неё (1.5M), мелочь не строим, ядерку не тратим
    if (samWanted(p)) { if (p.gold >= g.cost(p, 'sam') && aiBuild(p, 'sam')) return; if (p.gold < g.cost(p, 'sam')) return; }
    // к середине матча — ракетная шахта (пока копим на неё, мелочь не строим)
    if (t > 6000 && !c('silo')) { if (p.gold >= g.cost(p, 'silo') && aiBuild(p, 'silo')) return; if (c('city') >= 2) return; }
    // когда шахта есть — держим запас на атомную бомбу
    const reserve = t > 7200 && g.silosOf(p) ? NUKES.atom.cost + 300000 : 0;
    const can = (type) => p.gold - g.cost(p, type) >= reserve;
    if (c('city') < 1 + Math.min(3, Math.floor(tiles / 1500))) { if (can('city')) aiBuild(p, 'city'); return; }
    let coastal = false;
    for (const x of p.border) if (g.w.shore[x]) { coastal = true; break; }
    if (coastal && c('port') < 1 + Math.min(6, Math.floor(tiles / 3000))) { if (can('port') && aiBuild(p, 'port')) return; }
    if (c('factory') < Math.min(5, Math.floor(tiles / 3000))) { if (can('factory') && aiBuild(p, 'factory')) return; }
    if (t > 3600 && coastal && c('port') && g.shipsOf(p) < 1 && p.gold > 600000 + reserve) { if (aiBuild(p, 'warship')) return; }
    if (c('city') < 1 + Math.min(10, Math.floor(tiles / 600)) && can('city') && Math.random() < 0.5) aiBuild(p, 'city');
  }

  // ---------- ядерные удары (поздняя игра) ----------
  // цель — главная угроза: тот, кто бьёт нас (особенно ядеркой), или лидер, который близок к победе;
  // точка — самое плотное место (скопление построек), иначе столица
  const NUKE_FROM = { nation: 7200, human: 9000 }; // с 12-й и 15-й минуты матча
  let atPlayer = -1e9; // по игроку — не чаще раза в 90 с
  function aiNuke(p) {
    const t = g.tickN, ai = p.ai;
    if (t < (p.kind === KIND.NATION ? NUKE_FROM.nation : NUKE_FROM.human) || t < (ai.nukeAt || 0)) return false;
    const base = p.spawn >= 0 ? p.spawn : p.border.values().next().value;
    if (base === undefined || !g.readySilo(p, base)) return false;
    ai.nukeAt = t + ri(350, 800);
    if (p.gold < NUKES.atom.cost + 300000) return false;
    const revenge = p.nukedAt !== undefined && t - p.nukedAt < 1200;
    if (!revenge && samWanted(p) && p.gold < g.cost(p, 'sam') + NUKES.atom.cost) return false; // сначала ПВО
    let best = null, bs = 0;
    for (let i = 1; i < g.P.length; i++) {
      const q = g.P[i];
      if (!q.alive || q === p || q.kind === KIND.TRIBE || q.tiles < 150 || g.allied(p, q) || g.nukeSpares(p, q)) continue;
      if (p.isClaude && (q.isPlayer || g.allied(q, me))) continue;
      if (q.isPlayer && t - atPlayer < 900) continue;
      const hit = recentHit(p, q, 900);
      let s = q.troops * (hit ? 3 : 0.4);
      if (q.nukedBy === p) s *= 0.6;
      if (p.nukedBy === q && p.nukedAt !== undefined && t - p.nukedAt < 3000) s *= 4; // ответный удар
      if (q === lead && q.tiles > g.winLand * 0.2) s *= 3 + (q.tiles / g.winLand) * 6;
      if (q.isPlayer) s *= p.kind === KIND.HUMAN ? 0.5 + p.ai.toxic : 0.9;
      if (s > bs) { bs = s; best = q; }
    }
    if (!best || bs < 1) return false;
    const q = best;
    let type = 'atom';
    if (q === lead && q.tiles > g.winLand * 0.4 && p.gold >= g.nukeCost('mirv') + 2e6) type = 'mirv';
    else if (q.tiles > 2500 && p.gold >= NUKES.hydro.cost + 1e6) type = 'hydro';
    let tile = -1;
    if (type === 'mirv') tile = q.border.values().next().value;
    else {
      const R2 = NUKES[type].outer ** 2;
      let bc = 0;
      const mine = g.structs.filter((s) => s.owner === q.id);
      for (const s of mine) {
        let k = 0;
        for (const o of mine) { const dx = (o.tile % W) - (s.tile % W), dy = ((o.tile / W) | 0) - ((s.tile / W) | 0); if (dx * dx + dy * dy <= R2) k += o.type === 'city' ? 1.5 : 1; }
        if (k > bc) { bc = k; tile = s.tile; }
      }
      if (tile < 0 && q.spawn >= 0 && g.owner[q.spawn] === q.id) tile = q.spawn;
      if (tile < 0) tile = q.border.values().next().value;
    }
    if (tile === undefined || tile < 0) return false;
    const r = g.launchNuke(p, type, tile);
    if (r.ok && q.isPlayer) atPlayer = t;
    return r.ok;
  }

  // крупный соперник за морем: лидер (если догоняет нас) или следующая по величине страна
  function rival(p) {
    let best = null;
    for (let i = 1; i < g.P.length; i++) {
      const q = g.P[i];
      if (!q.alive || q === p || q.kind === KIND.TRIBE || q.tiles < p.tiles * 0.25 || q.tiles < 800 || !g.canAttack(p, q) || q.troops > p.troops * 1.2) continue;
      if (p.isClaude && (q.isPlayer || g.allied(q, me))) continue;
      if (q.isPlayer && g.tickN < PROT_TICKS + 1200) continue;
      if (!best || q.tiles > best.tiles) best = q;
    }
    return best;
  }

  function nation(p) {
    const ai = p.ai, cap = g.maxTroops(p), tr = p.troops;
    const step = ai.step; ai.step = (ai.step + 1) % 3;
    const info = scan(p);
    if (step === 0) { // расширение в ничью землю, поедание соседних племён
      if (info.free && tr > cap * 0.18) { g.attack(p, null, tr * ai.expand); return; }
      const tribes = info.nb.filter(({ q }) => q.kind === KIND.TRIBE && g.canAttack(p, q));
      if (tribes.length && tr > cap * ai.reserve) {
        const q = tribes.reduce((a, b) => (b.q.troops < a.q.troops ? b : a)).q;
        g.attack(p, q, Math.max(tr * ai.expand * 2, Math.min(tr * 0.5, q.troops * 1.5)));
      }
      return;
    }
    if (step === 1) { // атака: порог triggerRatio, резерв reserveRatio; к середине матча — смелее, лидер давит
      const late = g.tickN > PROT_TICKS + 1800, isLead = p === lead && p.tiles > g.winLand * 0.15;
      const trig = isLead ? 0.4 : late ? Math.min(ai.trigger, 0.46) : ai.trigger;
      if (tr < cap * trig) return;
      if (aiBetray(p)) return;
      const q = chooseTarget(p, info, tr > cap * (late ? 0.62 : 0.85) ? 0 : 1);
      const send = tr - cap * (isLead ? 0.22 : late ? Math.min(ai.reserve, 0.3) : ai.reserve);
      // по суше остались только огрызки — бьём крупного соперника десантом через море
      if (send > 1 && g.tickN > PROT_TICKS && (!q || q.tiles < p.tiles * 0.03) && Math.random() < 0.45) {
        const big = rival(p);
        if (big && !info.nb.some((x) => x.q === big) && tryBoat(p, send * 0.75, big)) return;
      }
      if (q && send > 1) g.attack(p, q, send);
      else if (!info.free && send > 1 && (!info.nb.length || Math.random() < 0.15)) tryBoat(p, send * 0.6);
      return;
    }
    if (aiNuke(p)) return;
    buildOrder(p);
    if (!info.free && !info.nb.some(({ q }) => g.canAttack(p, q)) && tr > cap * ai.trigger) tryBoat(p, tr - cap * ai.reserve);
  }

  function tribe(p) {
    const cap = g.maxTroops(p), tr = p.troops, info = scan(p);
    if (tr < cap * p.ai.reserve) return;
    if (info.free) { g.attack(p, null, tr / 20); return; }
    const c = info.nb.filter(({ q }) => g.canAttack(p, q) && (!q.isPlayer || Math.random() < 0.3));
    if (c.length && Math.random() < 0.6) g.attack(p, c[ri(0, c.length - 1)].q, tr / 20);
  }

  // боты-игроки и Клод: как люди — тап-тап по свободной земле, едят племена и слабых, строят города
  function human(p) {
    const ai = p.ai, cap = g.maxTroops(p), tr = p.troops, info = scan(p);
    if (tr > cap * 0.5 && aiBetray(p)) return;
    const calm = p.isClaude && g.tickN < 1800; // Клод первые 3 минуты растёт спокойно — землю у игрока не отбивает
    if (info.free && tr > cap * (calm ? 0.4 : 0.28)) g.attack(p, null, tr * (calm ? 0.12 : ai.ratio));
    else if (tr > cap * 0.42) {
      const q = chooseTarget(p, info, tr > cap * (g.tickN > PROT_TICKS + 1800 ? 0.6 : 0.75) ? 0 : 1);
      if (q) g.attack(p, q, tr * Math.min(0.75, ai.ratio + 0.15));
      else if (!info.free && tr > cap * 0.6) tryBoat(p, tr * (p.tiles > g.winLand * 0.15 ? 0.5 : ai.ratio));
    }
    ai.step = (ai.step + 1) % 4;
    if (ai.step === 2 && !p.isClaude && ai.toxic > 0.3 && aiNuke(p)) return;
    if (ai.step === 0) {
      if (aiPost(p)) return;
      if (g.tickN > 7200 && !p.isClaude && ai.toxic > 0.3 && !g.countOf(p, 'silo') && p.gold > 1.6e6 && aiBuild(p, 'silo')) return;
      if (samWanted(p) && p.gold >= g.cost(p, 'sam') && aiBuild(p, 'sam')) return;
      if (p.gold > 3e6) { aiBuild(p, 'city') || aiBuild(p, 'factory') || aiBuild(p, 'port'); return; } // богатый бот не копит без дела
      const r = Math.random();
      if (r < 0.65) aiBuild(p, 'city');
      else if (r < 0.8) aiBuild(p, 'port');
      else if (r < 0.92) aiBuild(p, 'factory');
      else if (g.tickN > PROT_TICKS && g.countOf(p, 'port') && g.shipsOf(p) < 1) aiBuild(p, 'warship');
    }
  }

  // ---------- дипломатия ----------
  // ответы ИИ на запросы союза (через 1–3.5 с «раздумий»), продление союзов, предложения союза игроку
  // и редкое предательство союзника-игрока токсичными ботами и «хитрыми» нациями
  let proposeAt = 700; // первое предложение игроку — не раньше чем через ~1 минуту
  const isAI = (p) => !p.isPlayer;
  function diplo(t) {
    for (const r of g.requests.slice()) {
      if (!isAI(r.to)) continue;
      if (r.decideAt < 0) r.decideAt = t + ri(10, 35);
      else if (t >= r.decideAt) g.answerAlly(r, aiAcceptAlly(g, r.to, r.from));
    }
    for (const pc of g.pacts.values()) {
      if (!pc.renew) continue;
      for (const [side, other, k] of [[pc.a, pc.b, 'a'], [pc.b, pc.a, 'b']]) {
        if (!isAI(side) || pc.renew[k]) continue;
        if (t - pc.renew.at < ri(15, 60)) continue;
        g.renewAlly(side, other, aiRenew(side, other));
        if (!g.pact(side, other)) break;
      }
    }
    if (t >= proposeAt && me.alive && !g.isTraitor(me) && !g.requests.some((r) => r.to === me)) {
      proposeAt = t + ri(450, 900); // проверка раз в 45–90 с
      const early = t < 1800;
      const cands = [];
      for (let i = 1; i < g.P.length; i++) {
        const q = g.P[i];
        if (!q.alive || q.isPlayer || q.isClaude || q.kind === KIND.TRIBE || q.tiles < 60 || g.allied(q, me) || g.reqCooldown(q, me)) continue;
        if (recentHit(q, me, 900) || recentHit(me, q, 900) || attacking(q, me) || attacking(me, q)) continue;
        if (!g.borders(q, me)) continue;
        cands.push(q);
      }
      // охотнее предлагают те, кто слабее игрока (ищут защиты), и в первые минуты
      cands.sort((a, b) => a.troops - b.troops);
      const q = cands[0];
      if (q && Math.random() < (early ? 0.65 : 0.35) * (q.troops < me.troops * 1.5 ? 1 : 0.5)) g.requestAlly(q, me);
    }
  }
  // продлить ли союз: с игроком — если он не бил нас и не стал опасно сильным; предателям — нет
  function aiRenew(q, p) {
    if (q.isClaude) return true;
    if (g.isTraitor(p) || recentHit(q, p, 1200)) return false;
    if (p.tiles > g.winLand * 0.35 && p.tiles > q.tiles * 3) return Math.random() < 0.35;
    return Math.random() < (q.kind === KIND.NATION ? 0.8 : 0.85 - (q.ai.toxic ?? 0.4) * 0.4);
  }
  // предательство союзника-игрока: сильный токсичный бот или «хитрая» нация на общей границе
  function aiBetray(p) {
    if (!g.allied(p, me) || p.isClaude || !me.alive) return false;
    const pc = g.pact(p, me);
    if (!pc || g.tickN - pc.at < 1500 || pc.until - g.tickN < 400) return false;
    const evil = p.kind === KIND.NATION ? p.ai.sly : (p.ai.toxic ?? 0) > 0.55;
    if (!evil || p.troops < me.troops * 1.6 || Math.random() > 0.05 || !g.borders(p, me)) return false;
    g.breakAlly(p, me);
    g.attack(p, me, p.troops * 0.45);
    return true;
  }

  let lead = null;
  g.brain = () => {
    const t = g.tickN, P = g.P;
    if (t % 50 === 1) lead = g.leader();
    if (t % 5 === 0) diplo(t);
    for (let i = 1; i < P.length; i++) {
      const p = P[i];
      if (!p.alive || p.isPlayer || p.ai.next > t) continue;
      if (p.kind === KIND.NATION) { p.ai.next = t + Math.round(p.ai.rate / 3); nation(p); }
      else if (p.kind === KIND.TRIBE) { p.ai.next = t + ri(40, 80); tribe(p); }
      else { p.ai.next = t + p.ai.rate + ri(-4, 4); human(p); }
    }
  };
}

// согласится ли ИИ q на союз с p: охотно в первые минуты, предателям — почти никогда
export function aiAcceptAlly(g, q, p) {
  if (q.isClaude) return true;
  if (g.isTraitor(p)) return Math.random() < 0.03;
  const hitT = q.hitBy.get(p.id);
  if (hitT !== undefined && g.tickN - hitT < 600) return false;
  for (const a of p.attacks) if (!a.dead && a.target === q) return false;
  const early = g.tickN < 1800;
  if (q.kind === KIND.TRIBE) return Math.random() < 0.5;
  if (q.kind === KIND.NATION) return Math.random() < (early ? 0.8 : p.troops > q.troops * 1.5 ? 0.55 : 0.3);
  return Math.random() < (early ? 0.8 : 0.85 - (q.ai.toxic ?? 0.4) * 0.6);
}

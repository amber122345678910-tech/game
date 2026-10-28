// BroWorld [World PvP] — «Построй свою нацию». Точка входа: интерфейс, ввод, чат, связка мира/симуляции/отрисовки.
import { initGameUI, pixelRatio, graphicsLevel } from '../../shared/ui.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS, pick, rand, typingDelay } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { getProfile, addCoins, addStat } from '../../shared/profile.js';
import { aiEnabled, aiBotLine } from '../../shared/ai.js';
import { generateWorld, WW, WH } from './world.js';
import { buildNations, dat, ins, va } from './nations.js';
import { Game, TERRAIN, BUILD, BUILD_ORDER, WIN_SHARE, HIRE_COST, HIRE_N } from './game.js';
import { Renderer } from './render.js';

const HELP = `<b>Карта:</b> перетаскивай пальцем, щипок или колёсико — зум.<br>
<b>Атака:</b> тапни свою провинцию, затем соседнюю (или прибрежную, если у тебя порт ⚓). Ползунок 25/50/75/100% — сколько войск отправить.<br>
<b>Постройки:</b> 🏙️ Город (+золото, +лимит войск), ⚓ Порт (высадки по морю), 🏭 Завод (×1.9 войск), 🏰 Форт (+60% защиты), 🪖 наёмники.<br>
<b>Дипломатия 🤝:</b> мир, союз, война. Союзники не нападают друг на друга.<br>
<b>Победа:</b> 60% суши или остаться единственным. <b>ПК:</b> пробел — пауза, 1–4 — доля войск, +/− — зум.`;
const ui = initGameUI({ title: 'BroWorld [World PvP]', players: () => playersList(), controlsHelp: HELP });
function playersList() {
  if (!N.length) return [{ name: profile.name, skin: profile.skin }];
  return N.filter((n) => n.alive || n.isPlayer).sort((a, b) => b.s.share - a.s.share).map((n) => ({
    name: n.isPlayer ? profile.name : n.leader.name, skin: n.isPlayer ? profile.skin : n.leader.skin,
    score: `${n.alive ? (n.s.share * 100).toFixed(1) + '%' : '☠'} · ${n.name}`, team: n.name, teamColor: n.light,
  }));
}
ui.loading(true, 'Генерация мира…');
const profile = getProfile();
const ME = 0, CLAUDE = 1;
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

const canvas = $('map');
const R = new Renderer(canvas, pixelRatio);
addEventListener('resize', () => { R.resize(); });
R.detail = graphicsLevel();
ui.onSettings(() => { const g = graphicsLevel(); const tier = (x) => (x <= 3 ? 0 : x <= 7 ? 1 : 2); const re = tier(g) !== tier(R.detail); R.detail = g; R.resize(); if (re && world) R.buildBase(); });

let world = null, game = null, N = [];
let phase = 'load'; // load | title | pick | play | over
let speed = 1, sendFrac = 0.5;
let sel = -1, targets = null;
let hintStage = 0, firstSend = false, firstBuild = false;
let diploOpen = false;

// ---------------- чат ----------------
const chat = createChat({ bots: () => N.filter((n) => !n.isPlayer && n.alive).map((n) => n.leader), me: profile.name });
const CUSTOM = {
  acceptPeace: { nice: ['ок, мир', 'ладно, мир так мир', 'давай, я устал воевать', 'мир, но я слежу за тобой', 'норм, мир'], toxic: ['ладно, живи пока', 'мир. но ты мне должен', 'ок, но в след раз не пощажу'] },
  refusePeace: { nice: ['не, пока рано', 'сначала верни мои земли', 'неа, я почти победил', 'мир? нее'], toxic: ['мир? ахах нет', 'проси лучше', 'не, ты слишком слабый', 'плачь', 'никакого мира, только война'] },
  acceptAlly: { nice: ['го союз!', 'давай вместе', 'союз, круто', 'ок, прикрою тебя'], toxic: ['ладно, пригодишься', 'ок, но если что я главный'] },
  refuseAlly: { nice: ['не, я сам по себе', 'может позже', 'хм, нет пока'], toxic: ['с тобой? не', 'союз с нубом? нет', 'ты мне не нужен'] },
  breakAlly: { nice: ['сорян, союз всё', 'прости, так надо'], toxic: ['союз всё, ты бесполезный', 'предательство? это стратегия', 'ахах бай'] },
  capital: { nice: ['моя столица!!', 'нееет столица', 'ладно, перенесу столицу'], toxic: ['ВЕРНИ СТОЛИЦУ', 'это лаги, я не успел', 'ну всё, война до конца'] },
  offerPeace: { nice: ['может мир? хватит воевать', 'давай мир, а?', 'предлагаю мир'], toxic: ['ладно, давай мир пока', 'мир? только быстро решай'] },
  demand: { nice: ['слушай, заплати немного золота и разойдёмся миром', 'дань и мы друзья', 'гони золото, и я тебя не трону'], toxic: ['гони золото или война', 'плати дань, нуб', 'плати или сноси свою столицу', 'золото на стол, быстро'] },
  offerAlly: { nice: ['го союз?', 'давай дружить нациями', 'союз против всех?'], toxic: ['союз? будешь моим щитом', 'ну давай союз, мне нужен кто-то спереди'] },
};
const CLAUDE_LINES = {
  start: ['привет! я рядом — вместе захватим мир 🌍', 'Клодия на связи! прикрою твой фланг', 'погнали! сначала берём нейтральные земли, пока они слабые'],
  war: ['держись, иду на помощь!', 'я тоже объявил им войну, вместе справимся 💪', 'бьём с двух сторон!', 'не трогай моего друга!'],
  tip: ['совет: форт на границе даёт +60% защиты', 'город = больше золота и выше лимит войск', 'завод почти удваивает производство войск', 'с портом можно высаживаться на другие берега ⚓', 'собери войска в одной провинции и бей кулаком, а не растопыркой', 'горы и леса защищать легче — нападай через равнины'],
  sad: ['эх, а мы же были союзниками…', 'ладно, я не обижаюсь. почти 🙃'],
  win: ['ПОБЕДА! ты лучший стратег 🎉', 'гг! мир наш 🌍'],
  lose: ['ничего, в следующий раз точно получится!', 'гг… давай реванш?'],
  lost: ['у меня отжали провинцию, но я держусь', 'на меня напали! если можешь — помоги'],
};
let chatNext = 0, chatQueued = null;
const nowS = () => performance.now() / 1000;
function sayAs(n, text) {
  if (!text) return;
  setTimeout(() => { if (phase !== 'load') chat.say(n.leader.name, text, n.color); }, typingDelay(text));
}
function customLine(n, kind) {
  const L = CUSTOM[kind];
  if (!L) return null;
  const toxic = Math.random() < (n.leader.toxic ?? 0.4);
  let s = pick(toxic ? L.toxic : L.nice);
  if (n.leader.typo && Math.random() < 0.2 && s.length > 5) s = s.slice(0, -1);
  return s;
}
function doTalk(nid, kind, eventText) {
  const n = N[nid];
  if (!n || n.isPlayer) return;
  if (n.isClaude && CLAUDE_LINES[kind]) {
    const fb = pick(CLAUDE_LINES[kind]);
    if (aiEnabled() && eventText && Math.random() < 0.5) aiBotLine(n.leader, eventText, { chatLog: chat.log }).then((t) => sayAs(n, t || fb));
    else sayAs(n, fb);
    return;
  }
  if (CUSTOM[kind]) {
    const fb = customLine(n, kind);
    if (aiEnabled() && eventText && Math.random() < 0.4) aiBotLine(n.leader, eventText, { chatLog: chat.log }).then((t) => sayAs(n, t || fb));
    else sayAs(n, fb);
    return;
  }
  chat.botSay(n.leader, kind, { target: profile.name, eventText });
}
// prio: реплики, касающиеся игрока (ответы на предложения, объявления войны) — в очередь, если чат занят
function talk(nid, kind, eventText = '', prio = false) {
  const t = nowS();
  if (t < chatNext) { if (prio) chatQueued = { nid, kind, eventText }; return; }
  chatNext = t + rand(4, 7.5);
  doTalk(nid, kind, eventText);
}
setInterval(() => {
  if (chatQueued && nowS() >= chatNext) { const q = chatQueued; chatQueued = null; chatNext = nowS() + rand(4, 7); doTalk(q.nid, q.kind, q.eventText); }
}, 500);
let sysNext = 0;
function sys(text, force = false) {
  const t = nowS();
  if (!force && t < sysNext) return;
  sysNext = t + 1.5;
  chat.system(text);
}

// ---------------- мир ----------------
function newWorld() {
  phase = 'load';
  ui.loading(true, 'Генерация мира…');
  closeAll();
  setTimeout(() => {
    const seed = (Math.random() * 2 ** 31) | 0;
    world = generateWorld(seed);
    const bots = makeBots(9, { exclude: [profile.name, 'Клод'] });
    N = buildNations({ playerName: profile.name, claude: FRIENDS[0], bots, rand: Math.random });
    game = new Game(world, N);
    game.on(onEvent);
    placeBotCapitals();
    R.setWorld(world, game, N);
    R.fitAll();
    R.pickMode = false;
    sel = -1; targets = null; speed = 1; sendFrac = 0.5;
    hintStage = 0; firstSend = firstBuild = false;
    ui.loading(false);
    showTitle();
  }, 40);
}

function hopDist(from) {
  const P = world.provinces, d = new Int16Array(P.length).fill(-1), q = [from];
  d[from] = 0;
  for (let h = 0; h < q.length; h++) for (const x of P[q[h]].neighbors) if (d[x] < 0) { d[x] = d[q[h]] + 1; q.push(x); }
  return d;
}
function placeBotCapitals() {
  const P = world.provinces;
  const cand = P.filter((p) => p.area >= 90 && p.terrain !== 'snow' && p.neighbors.length >= 2);
  const chosen = [];
  for (let i = 2; i < N.length; i++) {
    let best = null, bs = -1;
    for (const p of cand) {
      if (p.owner >= 0) continue;
      let md = 1e9;
      for (const c of chosen) md = Math.min(md, Math.hypot(c.cx - p.cx, c.cy - p.cy));
      if (!chosen.length) md = Math.hypot(p.cx - WW / 2, p.cy - WH / 2) * 0.3 + 300;
      const s = md * rand(0.75, 1.25) + p.neighbors.length * 6;
      if (s > bs) { bs = s; best = p; }
    }
    if (!best) best = P.find((p) => p.owner < 0);
    game.setCapital(i, best.id, 18);
    chosen.push(best);
  }
}
function placeClaude(capId) {
  const P = world.provinces, d = hopDist(capId);
  const caps = N.filter((n) => n.capital >= 0).map((n) => P[n.capital]);
  let best = null, bs = -1e9;
  for (const p of P) {
    if (p.owner >= 0 || d[p.id] < 0) continue;
    const hop = d[p.id];
    let md = 1e9;
    for (const c of caps) md = Math.min(md, Math.hypot(c.cx - p.cx, c.cy - p.cy));
    const s = (hop >= 3 && hop <= 5 ? 400 : hop === 2 || hop === 6 ? 150 : -hop * 20) + Math.min(md, 400) * 0.5 + rand(0, 60) - (p.terrain === 'snow' ? 80 : 0);
    if (s > bs) { bs = s; best = p; }
  }
  if (!best) best = P.find((p) => p.owner < 0);
  if (best) game.setCapital(CLAUDE, best.id, 18);
}

// ---------------- титул ----------------
function showTitle() {
  phase = 'title';
  $('hud').classList.add('hidden');
  setHint('');
  const me = N[ME];
  const t = $('title');
  t.innerHTML = `<div class="card">
    <div class="logo">BroWorld<small>World PvP</small></div>
    <div class="sub">Построй свою нацию</div>
    <div class="you"><img src="${me.flagUrl}"> ${esc(me.name)} <span style="opacity:.6;font-weight:700">· союзник: <img src="${N[CLAUDE].flagUrl}" style="width:24px;height:16px;vertical-align:-3px"> ${esc(N[CLAUDE].name)}</span></div>
    <div class="feats">
      <div>👆 Тапни свою провинцию, потом соседнюю — войска идут в атаку</div>
      <div>🏙️ Строй города, ⚓ порты, 🏭 заводы и 🏰 форты за 💰</div>
      <div>🤝 Заключай мир и союзы, объявляй войны</div>
      <div>🏆 Захвати 60% суши или останься единственным</div>
    </div>
    <div class="btns"><button id="tPlay">▶ Играть</button><button class="gray" id="tNew">🎲 Другая карта</button></div>
  </div>`;
  t.classList.remove('hidden');
  $('tPlay').onclick = () => { sfx.play('ui'); t.classList.add('hidden'); startPick(); };
  $('tNew').onclick = () => { sfx.play('ui'); t.classList.add('hidden'); newWorld(); };
}

function startPick() {
  phase = 'pick';
  R.pickMode = true;
  setHint('👆 Выбери стартовую провинцию — тапни по свободной земле');
}

function foundCapital(pid) {
  const p = world.provinces[pid];
  if (p.owner >= 0) { ui.toast('Эта земля уже занята'); return; }
  const d = hopDist(pid);
  for (const n of N) if (n.capital >= 0 && d[n.capital] >= 0 && d[n.capital] <= 1) { ui.toast('Слишком близко к соседу — выбери подальше'); return; }
  game.setCapital(ME, pid, 24);
  placeClaude(pid);
  game.st[ME][CLAUDE] = game.st[CLAUDE][ME] = 'ally';
  game.op[ME][CLAUDE] = game.op[CLAUDE][ME] = 80;
  game.running = true;
  phase = 'play';
  R.pickMode = false;
  R.dirty = true;
  select(-1);
  R.flyTo(p.lx, p.ly, Math.max(1.25, R.minZ * 2.5), 1.2);
  $('hud').classList.remove('hidden');
  $('hFlag').src = N[ME].flagUrl; $('hName').textContent = N[ME].name;
  sfx.play('spawn');
  ui.banner(N[ME].name, 'Твоя нация основана!', 2200, '#9cc8ff');
  hintStage = 1;
  setHint('⭐ Тапни свою столицу, затем соседнюю провинцию — войска пойдут в атаку');
  sys(`🌍 Мир из ${world.provinces.length} провинций. Наций: ${N.length}. Победа — 60% суши.`, true);
  setTimeout(() => talk(CLAUDE, 'start', 'игра началась, ты союзник игрока и стоишь рядом с ним', true), 1500);
  setTimeout(() => { const b = pick(N.filter((n) => !n.isPlayer && !n.isClaude)); if (b) talk(b.id, 'start', 'матч в стратегии про захват мира начался'); }, 7000);
  updateHUD(true);
}

// ---------------- события игры ----------------
const capMsgT = {};
function nameOf(i) { return N[i]?.name || '?'; }
function onEvent(type, d) {
  const P = world.provinces;
  switch (type) {
    case 'send':
      if (d.owner === ME) { sfx.play('march', { vol: 0.35 }); if (!firstSend) { firstSend = true; if (hintStage === 1) { hintStage = 2; setHint('💰 Копи золото и строй в панели провинции: город, порт, завод, форт', 7000); } } }
      break;
    case 'battle': {
      const p = P[d.pid];
      const mine = d.att === ME || d.def === ME;
      const vis = onScreen(p.lx, p.ly);
      if (vis) { R.ring(p.lx, p.ly, d.won ? '#ffe082' : '#ff8a65', 34, 0.55); R.sparks(p.lx, p.ly, d.won ? '#ffd54a' : '#ff7043', mine ? 14 : 7); }
      if (mine) sfx.play('hit', { vol: 0.45 });
      else if (vis && Math.random() < 0.3) sfx.play('hit', { vol: 0.12 });
      break;
    }
    case 'capture': {
      R.dirty = true;
      const p = P[d.pid], to = N[d.to];
      R.flash(d.pid, to.rgb.join(','));
      if (d.to === ME) { if (d.from >= 0) R.text(p.lx, p.ly, 'Захвачено!', '#b9f6ca', 14); sfx.play('spawn', { vol: 0.35 }); if (d.from >= 0 && Math.random() < 0.3) talk(d.from, 'death', `нация игрока ${profile.name} захватила твою провинцию ${p.name}`); }
      else if (d.from === ME) {
        R.text(p.lx, p.ly, 'Потеряно!', '#ff8a80', 15); sfx.play('death', { vol: 0.3 });
        if (d.to === CLAUDE) {} else if (Math.random() < 0.35) talk(d.to, 'kill', `ты захватил провинцию ${p.name} у нации игрока ${profile.name}`);
      } else if (d.from === CLAUDE && Math.random() < 0.15) talk(CLAUDE, 'lost', `нация ${to.name} захватила твою провинцию`);
      if (sel === d.pid || (targets && targets.has(d.pid)) || d.to === ME || d.from === ME) refreshSelection();
      break;
    }
    case 'capital': {
      const p = P[d.pid];
      R.ring(p.lx, p.ly, '#ffd54a', 90, 1.2); R.sparks(p.lx, p.ly, '#ffd54a', 24);
      const k = 'cap' + d.from;
      if (d.from === ME || d.to === ME || !(capMsgT[k] > nowS())) { capMsgT[k] = nowS() + 25; sys(`🏛 Столица нации ${nameOf(d.from)} пала! Её взял${/[ая]$/.test(nameOf(d.to)) ? 'а' : ''} ${nameOf(d.to)}.`, d.from === ME || d.to === ME); }
      if (d.to === ME) { sfx.play('boom', { vol: 0.5 }); ui.banner('СТОЛИЦА ВЗЯТА!', `${nameOf(d.from)} · добыча +${d.loot} 💰`, 2200, '#ffd54a'); R.text(p.lx, p.ly - 10, `+${d.loot} 💰`, '#ffd54a', 18, 2); talk(d.from, 'capital', `игрок ${profile.name} захватил твою столицу`, true); }
      else if (d.from === ME) { sfx.play('boom', { vol: 0.6 }); ui.banner('СТОЛИЦА ПОТЕРЯНА', `её захватил${/[ая]$/.test(nameOf(d.to)) ? 'а' : ''} ${nameOf(d.to)}`, 2400, '#ff8a80'); }
      break;
    }
    case 'eliminated': {
      R.dirty = true;
      sys(`☠ Нация ${nameOf(d.n)} уничтожена${d.by >= 0 ? ` (${nameOf(d.by)})` : ''}.`, true);
      if (d.n !== ME) talk(d.n, 'lose', `твоя нация ${nameOf(d.n)} уничтожена нацией ${nameOf(d.by)}`, d.by === ME);
      if (d.by === ME) { ui.toast(`☠ ${nameOf(d.n)} уничтожена!`); sfx.play('win', { vol: 0.4 }); }
      if (diploOpen) renderDiplo();
      break;
    }
    case 'war':
      if (d.a === ME || d.b === ME) dropOffer(d.a === ME ? d.b : d.a);
      sys(`⚔ ${nameOf(d.a)} ${va(nameOf(d.a), 'объявил')} войну ${dat(nameOf(d.b))}`, d.a === ME || d.b === ME);
      if (d.b === ME) {
        sfx.play('heavy', { vol: 0.5 });
        ui.toast(`⚔ ${nameOf(d.a)} ${va(nameOf(d.a), 'объявил')} вам войну!`, 2600);
        $('bDiplo').classList.add('alert'); setTimeout(() => $('bDiplo').classList.remove('alert'), 4000);
        if (d.a !== CLAUDE) talk(d.a, 'attack', `твоя нация ${nameOf(d.a)} объявила войну нации игрока ${profile.name} и нападает`, true);
      } else if (d.a === ME) {
        if (d.b !== CLAUDE) talk(d.b, 'hit', `игрок ${profile.name} (нация ${nameOf(ME)}) объявил войну твоей нации ${nameOf(d.b)}`, true);
      } else if (d.a === CLAUDE && d.why === 'ally-player') {
        talk(CLAUDE, 'war', `ты объявил войну нации ${nameOf(d.b)}, чтобы помочь игроку`, true);
      }
      refreshSelection();
      if (diploOpen) renderDiplo();
      break;
    case 'peace':
      sys(`☮ ${nameOf(d.a)} и ${nameOf(d.b)} заключили мир`, d.a === ME || d.b === ME);
      refreshSelection(); if (diploOpen) renderDiplo();
      break;
    case 'ally':
      sys(`🤝 ${nameOf(d.a)} и ${nameOf(d.b)} теперь союзники`, d.a === ME || d.b === ME);
      refreshSelection(); if (diploOpen) renderDiplo();
      break;
    case 'breakAlly':
      if (!d.silent) sys(`💔 ${nameOf(d.a)} ${va(nameOf(d.a), 'разорвал')} союз с ${ins(nameOf(d.b))}`, true);
      if (d.b === ME && d.a !== CLAUDE) { ui.toast(`💔 ${nameOf(d.a)} ${va(nameOf(d.a), 'предал')} союз!`, 2500); talk(d.a, 'breakAlly', 'ты разорвал союз с игроком', true); }
      if (d.a === ME && d.b === CLAUDE) talk(CLAUDE, 'sad', 'игрок разорвал с тобой союз', true);
      refreshSelection(); if (diploOpen) renderDiplo();
      break;
    case 'offer': showOffer(d.from, d.kind); break;
    case 'demand': showOffer(d.from, 'demand', d.gold); break;
    case 'build':
      if (d.n === ME) { const p = P[d.pid]; sfx.play('build', { vol: 0.6 }); R.text(p.lx, p.ly, `${BUILD[d.type].icon} ${BUILD[d.type].name}!`, '#fff', 14); R.ring(p.lx, p.ly, '#b3e5fc', 30, 0.5); refreshSelection(); }
      break;
    case 'hire':
      if (d.n === ME) { const p = P[d.pid]; R.text(p.lx, p.ly, `+${HIRE_N} ⚔`, '#ffe082', 14, 1); sfx.play('coin', { vol: 0.3 }); }
      break;
    case 'income': {
      const p = P[d.pid];
      if (onScreen(p.lx, p.ly)) R.text(p.lx, p.ly - 6, `+${d.amount} 💰`, '#ffd54a', 13, 1.3);
      if (p.capital && Math.random() < 0.25) sfx.play('coin', { vol: 0.12 });
      break;
    }
    case 'end': endGame(d); break;
  }
}
function onScreen(x, y) { const [sx, sy] = R.w2s(x, y); return sx > -40 && sy > -40 && sx < R.w + 40 && sy < R.h + 40; }

// ---------------- выбор и приказы ----------------
const TCOL = { own: 'rgba(120,255,150,A)', land: 'rgba(255,255,255,A)', war: 'rgba(255,70,70,A)', other: 'rgba(255,170,60,A)' };
function computeTargets(pid) {
  const m = new Map();
  for (const [id, naval] of game.targets(pid)) {
    const q = world.provinces[id];
    let kind;
    if (q.owner === ME) kind = 'own';
    else if (q.owner < 0) kind = 'land';
    else { const st = game.st[ME][q.owner]; if (st === 'ally') continue; kind = st === 'war' ? 'war' : 'other'; }
    m.set(id, { naval, kind, color: TCOL[kind] });
  }
  return m;
}
function select(pid) {
  sel = pid;
  targets = (phase === 'play' && pid >= 0 && world.provinces[pid].owner === ME) ? computeTargets(pid) : null;
  R.sel = pid; R.targets = targets;
  renderPanel();
}
function refreshSelection() {
  if (sel < 0) return;
  const p = world.provinces[sel];
  if (phase === 'play' && p.owner === ME) { targets = computeTargets(sel); R.targets = targets; }
  else if (targets) { targets = null; R.targets = null; }
  renderPanel();
}

function tap(sx, sy) {
  if (!world) return;
  const [wx, wy] = R.s2w(sx, sy);
  const pid = world.pick(wx, wy);
  if (phase === 'pick') { if (pid >= 0) sfx.play('ui', { vol: 0.5 }); select(pid); return; }
  if (phase !== 'play') return;
  if (pid < 0) { select(-1); return; }
  if (pid === sel) { select(-1); return; }
  const P = world.provinces;
  if (sel >= 0 && P[sel].owner === ME && targets && targets.has(pid)) { sendOrder(sel, pid); return; }
  sfx.play('ui', { vol: 0.4 });
  select(pid);
}

function sendOrder(from, to) {
  const P = world.provinces, q = P[to];
  if (q.owner >= 0 && q.owner !== ME) {
    const st = game.st[ME][q.owner];
    if (st === 'ally') { ui.toast('Это союзник — союзников атаковать нельзя'); return; }
    if (st === 'peace') {
      ui.modal(`<h2>Разорвать мир?</h2><p>У вас мир с <b>${esc(ins(N[q.owner].name))}</b>. Напасть — значит объявить войну.</p>`, [
        { label: 'Отмена', gray: true },
        { label: '⚔ Напасть', onClick: () => { game.declareWar(ME, q.owner); doSend(from, to); } },
      ]);
      return;
    }
    if (st === 'neutral') { game.declareWar(ME, q.owner); ui.toast(`⚔ Война с ${ins(N[q.owner].name)}!`); }
  }
  doSend(from, to);
}
function doSend(from, to) {
  const r = game.order(ME, from, to, sendFrac);
  if (r === 'few') { ui.toast('Мало войск в провинции'); sfx.play('block', { vol: 0.4 }); return; }
  if (r !== 'ok') { ui.toast('Туда нельзя'); return; }
  const p = world.provinces[from];
  R.ring(p.lx, p.ly, '#ffffff', 20, 0.35);
  renderPanel();
}

// ---------------- панель провинции ----------------
const REL = { war: 'Война', neutral: 'Нейтралитет', peace: 'Мир', ally: 'Союз', self: 'Ваша' };
function renderPanel() {
  const el = $('panel');
  document.body.classList.toggle('haspanel', sel >= 0 && !!world);
  if (sel < 0 || !world) { el.classList.add('hidden'); el.innerHTML = ''; return; }
  const p = world.provinces[sel], T = TERRAIN[p.terrain];
  const own = p.owner >= 0 ? N[p.owner] : null;
  const st = own ? game.state(ME, p.owner) : null;
  const flag = own ? `<img src="${own.flagUrl}">` : '<span class="nb"></span>';
  const def = game.defMult(p);
  let h = `<div class="pinfo">
    <div class="pname">${flag}<span>${esc(p.name)}</span></div>
    <div class="psub">${T.icon} ${T.name}${p.coastal ? ' · 🌊 берег' : ''}${own ? ` · ${esc(own.name)} <span class="rel ${st}">${REL[st]}</span>` : ' · ничья'}</div>
    <div class="pst" id="pStats"></div>
  </div>`;
  if (phase === 'pick') {
    h += p.owner < 0 ? `<button class="pbig green" id="pFound">🏛 Основать столицу<small>здесь начнётся ${esc(N[ME].name)}</small></button>`
      : `<div class="pmsg">Здесь уже нация ${esc(own.name)}. Выбери свободную землю.</div>`;
  } else if (p.owner === ME) {
    h += `<div class="pcol"><label id="pSendL">Отправить войска</label><div class="seg" id="pSeg">${[0.25, 0.5, 0.75, 1].map((f) => `<button data-f="${f}" class="${f === sendFrac ? 'on' : ''}">${f * 100}%</button>`).join('')}</div></div>`;
    h += '<div class="pbuild">';
    for (const t of BUILD_ORDER) {
      const B = BUILD[t];
      h += `<button class="bb" data-b="${t}" title="${B.name}: ${B.desc}"><i>${B.icon}</i><span>${B.name}</span><em></em></button>`;
    }
    h += `<button class="bb" data-b="hire" title="Наёмники: +${HIRE_N} войск"><i>🪖</i><span>+${HIRE_N}</span><em>${HIRE_COST}</em></button>`;
    h += '</div>';
  } else if (p.owner < 0) {
    h += `<div class="pmsg">${sel >= 0 && phase === 'play' ? 'Нейтральная земля. Выбери свою соседнюю провинцию и тапни сюда — захватишь.' : ''}</div>`;
  } else {
    const nid = p.owner;
    h += '<div class="pacts">';
    if (st === 'war') h += `<button class="pbig green" data-d="peace">☮ Мир</button>`;
    else if (st === 'ally') h += `<button class="pbig gray" data-d="break">💔 Разорвать</button>`;
    else h += `<button class="pbig" data-d="ally">🤝 Союз</button><button class="pbig red" data-d="war">⚔ Война</button>`;
    h += `<button class="pbig gray" data-d="open" style="min-width:60px">📜</button></div>`;
    el.dataset.nid = nid;
  }
  h += '<button class="pclose" id="pClose">✕</button>';
  el.innerHTML = h;
  el.classList.remove('hidden');
  $('pClose').onclick = () => select(-1);
  if ($('pFound')) $('pFound').onclick = () => foundCapital(sel);
  el.querySelectorAll('#pSeg button').forEach((b) => (b.onclick = () => { sendFrac = +b.dataset.f; sfx.play('ui', { vol: 0.4 }); el.querySelectorAll('#pSeg button').forEach((x) => x.classList.toggle('on', x === b)); }));
  el.querySelectorAll('.bb').forEach((b) => (b.onclick = () => doBuild(b.dataset.b)));
  el.querySelectorAll('[data-d]').forEach((b) => (b.onclick = () => {
    const nid = p.owner;
    if (b.dataset.d === 'open') openDiplo(); else diploAction(nid, b.dataset.d);
  }));
  updatePanel();
}
function updatePanel() {
  if (sel < 0 || !world) return;
  const p = world.provinces[sel], s = $('pStats');
  if (s) {
    const inc = game.goldRate(p), prod = game.prodRate(p);
    s.innerHTML = `⚔ <b>${Math.floor(p.troops)}</b>${p.owner >= 0 ? `/${game.capOf(p)}` : ''} · 🛡×${game.defMult(p).toFixed(1)}${p.owner >= 0 ? ` · +${prod.toFixed(1)}⚔/с · +${inc.toFixed(1)}💰` : ''}`;
  }
  if (p.owner === ME) {
    const gold = N[ME].gold;
    const L = $('pSendL');
    if (L) { let k = Math.floor(p.troops * sendFrac); if (k > p.troops - 1) k = Math.floor(p.troops - 1); L.textContent = k >= 1 ? `Отправить: ${k} ⚔ → тапни цель` : 'Мало войск'; }
    $('panel').querySelectorAll('.bb').forEach((b) => {
      const t = b.dataset.b, em = b.querySelector('em');
      if (t === 'hire') { b.classList.toggle('no', gold < HIRE_COST); return; }
      const has = p.b[t], c = game.cost(ME, t), bad = t === 'port' && !p.coastal;
      b.classList.toggle('has', !!has);
      b.classList.toggle('no', !has && (gold < c || bad));
      em.textContent = has ? '✓' : bad ? '—' : c;
    });
  }
}
function doBuild(t) {
  if (sel < 0) return;
  if (t === 'hire') {
    const r = game.hire(ME, sel);
    if (r === 'gold') { ui.toast(`Нужно ${HIRE_COST} 💰`); sfx.play('block', { vol: 0.4 }); }
    updatePanel(); return;
  }
  const r = game.build(ME, sel, t);
  if (r === 'gold') { ui.toast(`Не хватает золота: нужно ${game.cost(ME, t)} 💰`); sfx.play('block', { vol: 0.4 }); }
  else if (r === 'has') ui.toast(`${BUILD[t].name} уже построен`);
  else if (r === 'no-coast') ui.toast('Порт можно строить только на берегу');
  else if (r === 'ok') { if (!firstBuild) { firstBuild = true; if (hintStage === 2) { hintStage = 3; setHint(''); } } }
  updatePanel();
}

// ---------------- дипломатия ----------------
function diploAction(nid, act) {
  const n = N[nid];
  if (!n || !n.alive) return;
  sfx.play('ui', { vol: 0.5 });
  if (act === 'war') {
    const st = game.st[ME][nid];
    const go = () => { game.declareWar(ME, nid); ui.toast(`⚔ Вы объявили войну ${dat(n.name)}`); refreshSelection(); if (diploOpen) renderDiplo(); };
    if (st === 'peace') ui.modal(`<h2>Разорвать мир?</h2><p>Объявить войну нации <b>${esc(n.name)}</b>?</p>`, [{ label: 'Отмена', gray: true }, { label: '⚔ Война', onClick: go }]);
    else go();
    return;
  }
  if (act === 'break') {
    ui.modal(`<h2>Разорвать союз?</h2><p>Союз с <b>${esc(ins(n.name))}</b> будет расторгнут.</p>`, [{ label: 'Отмена', gray: true }, { label: '💔 Разорвать', onClick: () => { game.breakAlly(ME, nid); refreshSelection(); if (diploOpen) renderDiplo(); } }]);
    return;
  }
  const kind = act === 'peace' ? 'peace' : 'ally';
  const r = game.propose(ME, nid, kind);
  if (!r.ok && r.why === 'cooldown') { ui.toast('Подожди немного перед новым предложением'); return; }
  if (!r.ok && r.why) { ui.toast('Сейчас это невозможно'); return; }
  if (r.ok) {
    ui.toast(kind === 'peace' ? `☮ ${n.name} ${va(n.name, 'согласен')} на мир` : `🤝 ${n.name} теперь ваш союзник!`, 2200);
    sfx.play('coin', { vol: 0.4 });
    if (!n.isClaude) talk(nid, kind === 'peace' ? 'acceptPeace' : 'acceptAlly', `игрок ${profile.name} предложил ${kind === 'peace' ? 'мир' : 'союз'}, и ты согласился`, true);
  } else {
    ui.toast(`❌ ${n.name} ${va(n.name, 'отказал')}`, 1800);
    talk(nid, kind === 'peace' ? 'refusePeace' : 'refuseAlly', `игрок ${profile.name} предложил ${kind === 'peace' ? 'мир' : 'союз'}, а ты отказал`, true);
  }
  refreshSelection();
  if (diploOpen) renderDiplo();
}
function openDiplo() { diploOpen = true; $('diplo').classList.remove('hidden'); renderDiplo(); }
function closeDiplo() { diploOpen = false; $('diplo').classList.add('hidden'); }
$('dClose').onclick = closeDiplo;
$('bDiplo').onclick = () => { sfx.play('ui', { vol: 0.5 }); diploOpen ? closeDiplo() : openDiplo(); };
function mood(v) { return v > 35 ? '😊' : v > 5 ? '🙂' : v > -25 ? '😐' : v > -60 ? '😠' : '🤬'; }
function renderDiplo() {
  const list = N.filter((n) => !n.isPlayer).sort((a, b) => (b.alive - a.alive) || b.s.share - a.s.share);
  $('dList').innerHTML = list.map((n) => {
    const st = game.st[ME][n.id];
    let btn = '';
    if (n.alive) {
      if (st === 'war') btn = `<button class="g" data-a="peace" data-n="${n.id}">☮ Мир</button>`;
      else if (st === 'ally') btn = `<button data-a="break" data-n="${n.id}">💔</button>`;
      else btn = `<button class="b" data-a="ally" data-n="${n.id}">🤝 Союз</button><button class="r" data-a="war" data-n="${n.id}">⚔</button>`;
      btn += `<button data-a="look" data-n="${n.id}">👁</button>`;
    }
    return `<div class="dr ${n.alive ? '' : 'dead'}"><img src="${n.flagUrl}"><div class="di">
      <div class="dn" style="color:${n.light}">${esc(n.name)} ${n.alive ? `<span class="rel ${st}">${REL[st]}</span>` : '☠'}</div>
      <div class="ds">${n.isClaude ? '🤖' : '👤'} ${esc(n.leader.name)} · 🗺 ${(n.s.share * 100).toFixed(1)}% · ⚔ ${Math.floor(n.s.troops)} · ${mood(game.op[n.id][ME])}</div>
    </div><div class="da">${btn}</div></div>`;
  }).join('');
  $('dList').querySelectorAll('button').forEach((b) => (b.onclick = () => {
    const nid = +b.dataset.n;
    if (b.dataset.a === 'look') { const L = N[nid].label; if (L) R.flyTo(L.x, L.y, Math.max(R.cam.z, 0.8), 0.8); closeDiplo(); return; }
    diploAction(nid, b.dataset.a);
  }));
}

// ---------------- предложения от ботов ----------------
const offerCards = {};
function dropOffer(from) { offerCards[from]?.(false, true); }
function showOffer(from, kind, gold = 0) {
  const n = N[from];
  if (!n || !n.alive) return;
  dropOffer(from);
  const box = document.createElement('div'); box.className = 'offer' + (kind === 'demand' ? ' dem' : '');
  const title = kind === 'peace' ? 'предлагает мир ☮' : kind === 'ally' ? 'предлагает союз 🤝' : `требует дань ${gold} 💰 — иначе война!`;
  box.innerHTML = `<div class="ot"><img src="${n.flagUrl}"><span>${esc(n.name)} ${title}<br><small style="opacity:.7;font-weight:700">👤 ${esc(n.leader.name)}</small></span></div>
    <div class="ob"><button class="yes">${kind === 'demand' ? `Заплатить ${gold}` : 'Принять'}</button><button class="no">${kind === 'demand' ? 'Отказать ⚔' : 'Отклонить'}</button></div><div class="tm" style="width:100%"></div>`;
  $('offers').appendChild(box);
  sfx.play(kind === 'demand' ? 'heavy' : 'tp', { vol: 0.4 });
  if (kind === 'demand') talk(from, 'demand', `ты требуешь у игрока ${profile.name} дань ${gold} золота, иначе нападёшь`, true);
  else talk(from, kind === 'peace' ? 'offerPeace' : 'offerAlly', `ты предлагаешь игроку ${profile.name} ${kind === 'peace' ? 'мир' : 'союз'}`, true);
  const tm = box.querySelector('.tm');
  const ttl = kind === 'demand' ? 15 : 14;
  requestAnimationFrame(() => { tm.style.transitionDuration = ttl + 's'; tm.style.width = '0%'; });
  let done = false;
  const close = (ok, silent = false) => {
    if (done) return; done = true; box.remove(); delete offerCards[from];
    if (silent) return;
    if (kind === 'demand') {
      if (ok && N[ME].gold < gold) { ui.toast('Не хватает золота!'); ok = false; }
      const paid = game.answerDemand(from, ok);
      if (paid) { sfx.play('coin', { vol: 0.5 }); ui.toast(`Дань уплачена: −${gold} 💰. Мир на 90 с`); talk(from, 'thanks', 'игрок заплатил тебе дань', true); }
      return;
    }
    if (!ok || !n.alive) return;
    if (kind === 'peace') { if (game.st[ME][from] === 'war') game.makePeace(ME, from); }
    else if (game.st[ME][from] !== 'war') game.makeAlly(ME, from);
    sfx.play('coin', { vol: 0.4 });
    talk(from, 'thanks', 'игрок принял твоё предложение', true);
  };
  offerCards[from] = close;
  box.querySelector('.yes').onclick = () => close(true);
  box.querySelector('.no').onclick = () => { if (kind !== 'demand') game.op[from][ME] -= 5; close(false); };
  setTimeout(() => close(false), ttl * 1000);
}

// ---------------- HUD ----------------
function fmtT(t) { const m = Math.floor(t / 60), s = Math.floor(t % 60); return `${m}:${String(s).padStart(2, '0')}`; }
function fmtN(v) { v = Math.floor(v); return v >= 100000 ? (v / 1000).toFixed(0) + 'k' : v >= 10000 ? (v / 1000).toFixed(1) + 'k' : String(v); }
let lastLeaders = '';
function updateHUD(force) {
  if (!game || (phase !== 'play' && phase !== 'over' && !force)) return;
  const me = N[ME];
  $('hGold').textContent = fmtN(me.gold);
  $('hInc').textContent = `+${me.s.income.toFixed(1)}/с`;
  $('hTroops').textContent = fmtN(me.s.troops);
  $('hShare').textContent = (me.s.share * 100).toFixed(1) + '%';
  $('hShareBar').style.width = Math.min(100, (me.s.share / WIN_SHARE) * 60) + '%';
  $('hTime').textContent = fmtT(game.time);
  const rows = N.filter((n) => n.alive).sort((a, b) => b.s.share - a.s.share);
  let shown = rows.slice(0, 6);
  if (!shown.includes(me) && me.alive) shown = rows.slice(0, 5).concat([me]);
  const html = shown.map((n) => {
    const st = n.isPlayer ? '' : game.st[ME][n.id];
    const ic = st === 'war' ? '⚔' : st === 'ally' ? '🤝' : st === 'peace' ? '☮' : '';
    return `<div class="lr ${n.isPlayer ? 'me' : ''}" data-n="${n.id}"><img src="${n.flagUrl}"><span class="nm" style="color:${n.light}">${esc(n.name)}</span><span class="st">${ic}</span><span class="pc">${(n.s.share * 100).toFixed(0)}%</span></div>`;
  }).join('');
  if (html !== lastLeaders) {
    lastLeaders = html;
    $('lRows').innerHTML = html;
    $('lRows').querySelectorAll('.lr').forEach((r) => (r.onclick = () => { const L = N[+r.dataset.n].label; if (L) R.flyTo(L.x, L.y, Math.max(R.cam.z, 0.7), 0.8); }));
  }
  updatePanel();
}
$('leaders').querySelector('.lh').onclick = () => { $('leaders').classList.toggle('min'); $('lToggle').textContent = $('leaders').classList.contains('min') ? '▸' : '▾'; };
setInterval(() => updateHUD(), 250);
setInterval(() => { if (diploOpen && phase === 'play') renderDiplo(); }, 1500);
$('speed').querySelectorAll('button').forEach((b) => (b.onclick = () => setSpeed(+b.dataset.s)));
function setSpeed(s) {
  speed = s;
  $('speed').querySelectorAll('button').forEach((x) => x.classList.toggle('on', +x.dataset.s === s));
  if (s === 0) ui.toast('⏸ Пауза', 900);
}
$('hNat').onclick = () => { const c = N[ME].capital; if (c >= 0) { const p = world.provinces[c]; R.flyTo(p.lx, p.ly, Math.max(R.cam.z, 1.2), 0.7); select(c); } };

let hintTimer = 0;
function setHint(t, ms = 0) {
  $('hint').textContent = t;
  clearTimeout(hintTimer);
  if (ms) hintTimer = setTimeout(() => { if ($('hint').textContent === t) $('hint').textContent = ''; }, ms);
}

// ---------------- конец игры ----------------
function endGame(d) {
  phase = 'over';
  $('offers').innerHTML = ''; closeDiplo(); select(-1); setHint('');
  const me = N[ME];
  const win = d.win;
  const coins = win ? 60 + Math.round(me.peak * 100) : 5 + Math.round(me.peak * 35);
  addCoins(coins);
  addStat('roworld', 'games', 1);
  addStat('roworld', win ? 'wins' : 'losses', 1);
  addStat('roworld', 'captured', me.captured);
  sfx.play(win ? 'win' : 'lose');
  const why = { share: `Ты контролируешь ${(me.s.share * 100).toFixed(0)}% суши!`, alone: 'Все соперники повержены!', lost: 'Твоя нация пала…', other: `${nameOf(d.who)} ${va(nameOf(d.who), 'захватил')} 60% мира.` }[d.reason];
  if (N[CLAUDE].alive || true) talk(CLAUDE, win ? 'win' : 'lose', win ? 'игрок победил в стратегии, поздравь' : 'игрок проиграл, подбодри', true);
  const winner = win ? null : N[d.who] || N.filter((n) => n.alive).sort((a, b) => b.s.share - a.s.share)[0];
  if (winner && !winner.isClaude && !winner.isPlayer) setTimeout(() => talk(winner.id, 'win', 'ты победил в стратегии про захват мира', true), 2500);
  setTimeout(() => {
    const e = $('endscr');
    e.innerHTML = `<div class="card">
      <div class="res" style="color:${win ? '#ffd54a' : '#ff8a80'}">${win ? '🏆 ПОБЕДА!' : '💀 ПОРАЖЕНИЕ'}</div>
      <div class="sub">${esc(why)}</div>
      <div class="you"><img src="${me.flagUrl}"> ${esc(me.name)}</div>
      <div class="stats">
        <div>⏱ Время<b>${fmtT(game.time)}</b></div>
        <div>🗺 Пик территории<b>${(me.peak * 100).toFixed(1)}%</b></div>
        <div>⚔ Захвачено провинций<b>${me.captured}</b></div>
        <div>🪙 Монеты<b>+${coins}</b></div>
      </div>
      <div class="btns"><button id="eNew">🔄 Новая игра</button><button class="gray" id="eHome">⌂ В меню</button></div>
    </div>`;
    e.classList.remove('hidden');
    $('eNew').onclick = () => { sfx.play('ui'); e.classList.add('hidden'); newWorld(); };
    $('eHome').onclick = () => ui.goHome();
  }, 1600);
  ui.banner(win ? 'ПОБЕДА!' : 'ПОРАЖЕНИЕ', why, 1500, win ? '#ffd54a' : '#ff8a80');
}
function closeAll() {
  $('endscr').classList.add('hidden'); $('title').classList.add('hidden'); closeDiplo();
  $('offers').innerHTML = ''; $('panel').classList.add('hidden'); $('hud').classList.add('hidden'); setHint('');
}

// ---------------- ввод: перетаскивание, щипок, колёсико, тап ----------------
const ptrs = new Map();
let drag = null, pinch = null, vel = { x: 0, y: 0 }, multi = false;
canvas.addEventListener('pointerdown', (e) => {
  try { canvas.setPointerCapture(e.pointerId); } catch {}
  ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptrs.size === 1) { drag = { x0: e.clientX, y0: e.clientY, lx: e.clientX, ly: e.clientY, t0: performance.now(), lt: performance.now(), moved: false }; vel.x = vel.y = 0; multi = false; R.fly = null; }
  else if (ptrs.size === 2) {
    multi = true;
    const [a, b] = [...ptrs.values()];
    pinch = { d0: Math.hypot(a.x - b.x, a.y - b.y) || 1, z0: R.cam.z, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2 };
  }
});
canvas.addEventListener('pointermove', (e) => {
  if (!ptrs.has(e.pointerId)) {
    if (e.pointerType === 'mouse' && world && phase !== 'load') { const [wx, wy] = R.s2w(e.clientX, e.clientY); R.hover = world.pick(wx, wy); }
    return;
  }
  ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptrs.size >= 2 && pinch) {
    const [a, b] = [...ptrs.values()];
    const d = Math.hypot(a.x - b.x, a.y - b.y) || 1, mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    R.zoomAt(mx, my, (pinch.z0 * d / pinch.d0) / R.cam.z);
    R.pan(mx - pinch.mx, my - pinch.my);
    pinch.mx = mx; pinch.my = my;
    return;
  }
  if (drag) {
    const dx = e.clientX - drag.lx, dy = e.clientY - drag.ly;
    if (!drag.moved && Math.hypot(e.clientX - drag.x0, e.clientY - drag.y0) > 9) drag.moved = true;
    if (drag.moved) {
      R.pan(dx, dy);
      const now = performance.now(), dtt = Math.max(1, now - drag.lt);
      vel.x = vel.x * 0.6 + (dx / dtt) * 1000 * 0.4; vel.y = vel.y * 0.6 + (dy / dtt) * 1000 * 0.4;
      drag.lt = now;
    }
    drag.lx = e.clientX; drag.ly = e.clientY;
  }
});
function ptrUp(e) {
  if (!ptrs.has(e.pointerId)) return;
  ptrs.delete(e.pointerId);
  if (ptrs.size < 2) pinch = null;
  if (ptrs.size === 1) { const [p] = [...ptrs.values()]; if (drag) { drag.lx = p.x; drag.ly = p.y; drag.moved = true; } }
  if (ptrs.size === 0 && drag) {
    if (!drag.moved && !multi && e.type === 'pointerup' && performance.now() - drag.t0 < 700) tap(e.clientX, e.clientY);
    if (performance.now() - drag.lt > 80) vel.x = vel.y = 0;
    drag = null;
  }
}
canvas.addEventListener('pointerup', ptrUp);
canvas.addEventListener('pointercancel', ptrUp);
canvas.addEventListener('wheel', (e) => { e.preventDefault(); R.zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT') return;
  if (phase !== 'play') return;
  if (e.code === 'Space') { setSpeed(speed === 0 ? 1 : 0); e.preventDefault(); }
  else if (e.code === 'Digit1') setFrac(0.25); else if (e.code === 'Digit2') setFrac(0.5);
  else if (e.code === 'Digit3') setFrac(0.75); else if (e.code === 'Digit4') setFrac(1);
  else if (e.code === 'Equal' || e.code === 'NumpadAdd') R.zoomAt(R.w / 2, R.h / 2, 1.25);
  else if (e.code === 'Minus' || e.code === 'NumpadSubtract') R.zoomAt(R.w / 2, R.h / 2, 0.8);
  else if (e.code === 'KeyD' && e.shiftKey) openDiplo();
});
function setFrac(f) { sendFrac = f; renderPanel(); }

// ---------------- главный цикл ----------------
let last = performance.now(), acc = 0;
const STEP = 0.05;
function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000); last = now;
  if (game && phase === 'play') {
    acc += dt * speed;
    let steps = 0;
    while (acc >= STEP && steps < 6) { game.update(STEP); acc -= STEP; steps++; }
    if (steps >= 6) acc = 0;
  }
  if (!drag && (Math.abs(vel.x) > 5 || Math.abs(vel.y) > 5)) { R.pan(vel.x * dt, vel.y * dt); const k = Math.exp(-dt * 5); vel.x *= k; vel.y *= k; }
  R.draw(now / 1000, dt);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// болтовня в чате и советы Клода
setInterval(() => {
  if (phase !== 'play' || speed === 0) return;
  const r = Math.random();
  if (r < 0.35) talk(CLAUDE, 'tip', 'дай игроку короткий совет по стратегии захвата территорий');
  else if (r < 0.8) { const b = pick(N.filter((n) => n.alive && !n.isPlayer && !n.isClaude)); if (b) talk(b.id, 'idle', `идёт стратегия про захват мира, твоя нация ${b.name} занимает ${(b.s.share * 100).toFixed(0)}% суши`); }
}, 28000);

window.__bw = { get game() { return game; }, get world() { return world; }, R, tap, select, foundCapital, get phase() { return phase; }, setSpeed, diploAction, openDiplo };
newWorld();

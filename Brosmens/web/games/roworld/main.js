// BroWorld [World PvP] — точка входа: интерфейс как у оригинала на телефоне (круглые кнопки слева сверху,
// плашка таймера и места справа, нижняя панель, карточка цели, радиальное меню, лист построек),
// этап выбора столицы, «НАЧАЛАСЬ ВОЙНА», 5:00 защиты, 40:00 матча, выбывание с наблюдением и экран итогов.
import { initGameUI, pixelRatio } from '../../shared/ui.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS, pick, rand, typingDelay } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { getProfile, addCoins, addStat } from '../../shared/profile.js';
import { aiEnabled, aiBotLine } from '../../shared/ai.js';
import { buildWorld, W } from './world.js';
import { NATIONS, tribeNames, pastel, ownerColors, acc as accName, PLAYER_COLOR, CLAUDE_COLOR, TRIBE_COLOR } from './nations.js';
import { Game, KIND, fmt, fmtT, TICK, MATCH_TICKS, PROT_TICKS, WIN_SHARE, STRUCTS, SPAWN_GAP, TRIBE_GAP, BOAT_MAX } from './game.js';
import { setupBrain, aiAcceptAlly, spawnOk, pickSpawnTile } from './brains.js';
import { Renderer } from './render.js';
import { openRadial, closeRadial, radialOpen, hover as radialHover, release as radialRelease } from './radial.js';
import { horn } from './sounds.js';

const N_BOTS = 12, N_NATIONS = 42, N_TRIBES = 190;
const RATIOS = [0.1, 0.25, 0.35, 0.5, 0.75];
const SPAWN_SECONDS = 20;
const STARS_KEY = 'brosmens.roworld.stars';

const HELP = `<b>Цель:</b> захвати 80% суши мира (вне радиации) — или будь крупнейшим, когда выйдет время (40:00).<br>
<b>Старт:</b> 20 секунд на выбор — тапни свободную землю, чтобы поставить столицу. Потом 5:00 <b>защиты</b>: игроки не могут нападать друг на друга (нации и племена — могут!).<br>
<b>Расширение:</b> тапни по свободной земле — туда пойдёт выбранная доля войск (10–75%). Земля за морем — <b>десант</b> ⛵.<br>
<b>Атака:</b> тапни соседа — откроется карточка цели, жми «⚔ Атаковать». Повторная атака добавляет войска к идущей.<br>
<b>Своя земля или долгое нажатие</b> — радиальное меню: атака, десант, союз, постройки, камера.<br>
<b>Войска</b> растут сами, быстрее всего — около 40% от лимита. <b>Золото</b> (+1K/с) — на постройки: кнопка «Строить» или клавиши 1–7.<br>
<b>Карта:</b> перетаскивай пальцем, щипок — зум, двойной тап — приблизить. 🌐 — вид «свои / союзники / враги».<br>
<b>ПК:</b> Q/E — доля войск, B — постройки, 1–7 — выбрать постройку, Esc/X — отмена, +/− — зум.<br>
<small>Карта: Natural Earth (public domain), рельеф: NASA Visible Earth / GEBCO.</small>`;
const profile = getProfile();
const ui = initGameUI({ title: 'BroWorld [World PvP]', players: () => playersList(), controlsHelp: HELP });
ui.loading(true, 'Загрузка карты мира…');
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

const canvas = $('map');
const R = new Renderer(canvas, pixelRatio);
addEventListener('resize', () => R.resize());
ui.onSettings(() => R.resize());

let world = null, game = null, me = null, claude = null;
let phase = 'load'; // load | title | pick | play | out | spectate | over
let ratio = 0.25;
let cardQ = null, cardTile = -1, placing = null, sheetOpen = false, lbOpen = false, atkOpen = false, altView = false;
let spawnStart = 0, spawnEnd = 0, spawnQ = [], claudeAt = 0, coords = new Map();
let firstExpand = false, firstAttack = false, fast = 1;
const stats = { start: 0 };

function playersList() {
  if (!game) return [{ name: profile.name, skin: profile.skin }];
  return game.P.filter((p) => p && p.kind === KIND.HUMAN && (p.alive || p.isPlayer)).sort((a, b) => b.tiles - a.tiles).map((p) => ({
    name: p.name, skin: p.skin, score: p.alive ? pct(p.tiles) : '☠', team: p.isPlayer || p.isClaude ? 'союз' : '', teamColor: p.color,
  }));
}
// доля суши: одна цифра после запятой, у совсем маленьких — две
const share = (tiles) => (game ? tiles / game.winLand : 0) * 100;
const pct = (tiles) => { const v = share(tiles); return (v >= 0.1 || v === 0 ? v.toFixed(1) : v.toFixed(2)) + '%'; };

// ---------------- чат ----------------
const chat = createChat({ bots: () => (game ? game.P.filter((p) => p && p.leader && p.alive).map((p) => p.leader) : []), me: profile.name });
const CUSTOM = {
  acceptAlly: { nice: ['го союз!', 'давай вместе', 'союз, круто', 'ок, прикрою тебя'], toxic: ['ладно, пригодишься', 'ок, но если что я главный'] },
  refuseAlly: { nice: ['не, я сам по себе', 'может позже', 'хм, нет пока'], toxic: ['с тобой? не', 'союз с нубом? нет', 'ты мне не нужен'] },
  eaten: { nice: ['эх, меня съели', 'ну всё, я всё', 'гг, я выбыл'], toxic: ['ЛАГИ', 'это нечестно, у тебя войск в 10 раз больше', 'ну и ладно, скучная игра', 'репорт'] },
  betrayed: { nice: ['ты чего?? мы же были в союзе', 'вот так, значит…', 'эй, предатель!'], toxic: ['ПРЕДАТЕЛЬ', 'ну всё, тебе конец', 'запомню это', 'крыса'] },
};
const CLAUDE_LINES = {
  start: ['привет! я рядом — вместе захватим мир 🌍', 'Клод на связи! прикрою твой фланг', 'погнали! сначала тапай по свободной земле — растём, пока она ничья'],
  help: ['держись, иду на помощь!', 'вижу, на тебя напали — бью их с тыла 💪', 'не трогай моего друга!'],
  tip: ['совет: войска растут быстрее всего, когда их около 40% от лимита — не копи до максимума', '25% — норм для расширения, 50% и больше — для атаки', 'города поднимают лимит войск — копи золото и жми «Строить»', 'племена слабые — их удобно есть первыми', 'не отправляй всё сразу, держи войска дома на случай нападения', 'горы захватывать дольше и дороже — равнины быстрее', 'оборонный пост на границе — и враг теряет впятеро больше войск', 'пока идёт защита 5:00, другие игроки нас не тронут — растём!'],
  win: ['ПОБЕДА! ты лучший стратег 🎉', 'гг! мир наш 🌍'],
  lose: ['ничего, в следующий раз точно получится!', 'гг… давай реванш?'],
  fallen: ['эх, тебя съели… смотри, я ещё держусь!', 'не сдавайся, в следующем матче отыграемся'],
};
let chatNext = 0, chatQueued = null;
const nowS = () => performance.now() / 1000;
function sayAs(p, text) { if (text) setTimeout(() => { if (phase !== 'load') chat.say(p.name, text, p.color); }, typingDelay(text)); }
function customLine(p, kind) {
  const L = CUSTOM[kind]; if (!L) return null;
  const toxic = Math.random() < (p.leader?.toxic ?? 0.4);
  return pick(toxic ? L.toxic : L.nice);
}
function doTalk(p, kind, eventText) {
  if (!p || !p.leader || p.isPlayer) return;
  if (p.isClaude) {
    const fb = pick(CLAUDE_LINES[kind] || CLAUDE_LINES.tip);
    if (aiEnabled() && eventText && Math.random() < 0.5) aiBotLine(p.leader, eventText, { chatLog: chat.log }).then((t) => sayAs(p, t || fb));
    else sayAs(p, fb);
    return;
  }
  if (CUSTOM[kind]) {
    const fb = customLine(p, kind);
    if (aiEnabled() && eventText && Math.random() < 0.4) aiBotLine(p.leader, eventText, { chatLog: chat.log }).then((t) => sayAs(p, t || fb));
    else sayAs(p, fb);
    return;
  }
  chat.botSay(p.leader, kind, { target: profile.name, eventText });
}
// не чаще одного сообщения в 4–7 с на весь сервер; важные (prio) — в очередь
function talk(p, kind, eventText = '', prio = false) {
  const t = nowS();
  if (t < chatNext) { if (prio) chatQueued = { p, kind, eventText }; return; }
  chatNext = t + rand(4, 7.5);
  doTalk(p, kind, eventText);
}
setInterval(() => {
  if (chatQueued && nowS() >= chatNext) { const q = chatQueued; chatQueued = null; chatNext = nowS() + rand(4, 7); doTalk(q.p, q.kind, q.eventText); }
}, 500);

// ---------------- круглые кнопки слева сверху (после ☰ и 💬) ----------------
const ICON = {
  help: '<svg width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="9.5" fill="#fff"/><path d="M8.2 8.6c0-1.7 1.3-2.8 2.9-2.8s2.9 1 2.9 2.6c0 1.9-2.3 2.2-2.3 3.9" stroke="#000" stroke-width="2.1" fill="none" stroke-linecap="round"/><circle cx="11.6" cy="15.6" r="1.3" fill="#000"/></svg>',
  podium: '<svg width="22" height="22" viewBox="0 0 22 22"><rect x="1.5" y="12" width="6" height="8.5" rx="1" fill="#fff"/><rect x="8" y="8" width="6" height="12.5" rx="1" fill="#fff"/><rect x="14.5" y="14" width="6" height="6.5" rx="1" fill="#fff"/><path d="M11 1.2l1.2 2.5 2.7.4-2 1.9.5 2.7-2.4-1.3-2.4 1.3.5-2.7-2-1.9 2.7-.4z" fill="#fff"/></svg>',
  globe: '<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="#fff" stroke-width="1.7"><circle cx="11" cy="11" r="9"/><ellipse cx="11" cy="11" rx="4" ry="9"/><path d="M2 11h18M3.6 6.2h14.8M3.6 15.8h14.8"/></svg>',
  gear: '<svg width="22" height="22" viewBox="0 0 22 22"><path fill="#fff" fill-rule="evenodd" d="M9.4 1.5h3.2l.5 2.6 1.6.7 2.2-1.5 2.3 2.3-1.5 2.2.7 1.6 2.6.5v3.2l-2.6.5-.7 1.6 1.5 2.2-2.3 2.3-2.2-1.5-1.6.7-.5 2.6H9.4l-.5-2.6-1.6-.7-2.2 1.5-2.3-2.3 1.5-2.2-.7-1.6-2.6-.5V9.4l2.6-.5.7-1.6-1.5-2.2 2.3-2.3 2.2 1.5 1.6-.7zM11 7.6a3.4 3.4 0 1 0 0 6.8 3.4 3.4 0 0 0 0-6.8z"/></svg>',
  exit: '<svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M9 3H4.5A1.5 1.5 0 0 0 3 4.5v13A1.5 1.5 0 0 0 4.5 19H9"/><path d="M14 6.5l4.5 4.5-4.5 4.5M18.5 11H8.5"/></svg>',
};
const topBtn = (svg, title, fn) => { const b = ui.addTopButton(svg, fn); b.classList.add('gb'); b.title = title; b.setAttribute('aria-label', title); return b; };
topBtn(ICON.help, 'Как играть', () => { sfx.play('ui', { vol: 0.4 }); openHelp(); });
const lbBtn = topBtn(ICON.podium, 'Лидеры', () => toggleLB());
const altBtn = topBtn(ICON.globe, 'Вид: свои / союзники / враги', () => toggleAlt());
topBtn(ICON.gear, 'Настройки', () => ui.openMenu());
topBtn(ICON.exit, 'Выйти', () => confirmExit());

function openHelp() {
  const h = $('help');
  h.innerHTML = `<div class="hc pnl"><div class="hh"><b>КАК ИГРАТЬ</b><button id="hX">✕</button></div><div class="hb">${HELP}</div></div>`;
  h.classList.remove('hidden');
  $('hX').onclick = () => h.classList.add('hidden');
  h.onclick = (e) => { if (e.target === h) h.classList.add('hidden'); };
}
function confirmExit() {
  sfx.play('ui', { vol: 0.4 });
  if (phase === 'title' || phase === 'load') { ui.modal('<h2>Выйти из BroWorld?</h2><p>Ты вернёшься в меню «Бросменс».</p>', [{ label: 'Отмена', gray: true }, { label: 'Выйти', onClick: () => ui.goHome() }]); return; }
  ui.modal('<h2>Покинуть матч?</h2><p>Матч закончится для тебя, страна останется без командира.</p>', [
    { label: 'Отмена', gray: true },
    { label: 'В главное меню', onClick: () => { leaveMatch(); } },
    { label: 'Выйти из игры', onClick: () => { leaveMatch(true); } },
  ]);
}
function toggleAlt() {
  altView = !altView;
  altBtn.classList.toggle('on', altView);
  sfx.play('ui', { vol: 0.35 });
  if (game) { altSig = ''; R.setAlt(altView, affiliation); }
  ui.toast(altView ? 'Вид: свои • союзники • нейтральные • враги' : 'Обычный вид карты', 1300);
}
const affiliation = (p) => (p === me ? 'self' : game.allied(me, p) ? 'ally' : game.relation(me, p) === 'war' ? 'enemy' : 'neutral');
let altSig = '';
function refreshAlt() {
  if (!altView || !game) return;
  let s = '';
  for (let i = 1; i < game.P.length; i++) { const p = game.P[i]; if (p.alive) s += affiliation(p)[0]; }
  if (s !== altSig) { altSig = s; R.setAlt(true, affiliation); }
}

// ---------------- матч ----------------
function newMatch() {
  phase = 'load';
  closeAll();
  ui.loading(true, 'Загрузка карты мира…');
  setTimeout(() => {
    world = buildWorld();
    R.setWorld(world);
    game = new Game(world);
    const add = (o) => game.addPlayer({ ...o, col: ownerColors(o.color) });
    me = add({ kind: KIND.HUMAN, name: profile.name || 'Игрок', color: PLAYER_COLOR, isPlayer: true });
    me.skin = profile.skin;
    claude = add({ kind: KIND.HUMAN, name: FRIENDS[0].name, color: CLAUDE_COLOR, isClaude: true, leader: FRIENDS[0] });
    claude.skin = FRIENDS[0].skin;
    coords = new Map();
    makeBots(N_BOTS, { exclude: [profile.name, 'Клод'] }).forEach((b, i) => { const p = add({ kind: KIND.HUMAN, name: b.name, color: pastel(i), leader: b }); p.skin = b.skin; });
    const order = NATIONS.slice().sort(() => Math.random() - 0.5).slice(0, N_NATIONS);
    order.forEach(([name, lat, lon], i) => { const p = add({ kind: KIND.NATION, name, color: pastel(N_BOTS + i) }); coords.set(p, [lat, lon]); });
    tribeNames(N_TRIBES, Math.random).forEach((name) => add({ kind: KIND.TRIBE, name, color: TRIBE_COLOR }));
    game.makeAlly(me, claude);
    game.on(onEvent);
    R.setGame(game);
    R.me = me;
    R.fitAll();
    cardQ = null; placing = null; ratio = 0.25; firstExpand = firstAttack = false; fast = 1; altView = false; altBtn.classList.remove('on');
    renderChips();
    ui.loading(false);
    showTitle();
  }, 30);
}

function showTitle() {
  phase = 'title';
  document.body.classList.remove('ingame');
  $('hud').classList.add('hidden');
  const t = $('title');
  t.innerHTML = `<div class="card">
    <div class="logo">BROWORLD</div>
    <div class="tag">ЗАХВАТИ НАСТОЯЩИЙ МИР</div>
    <div class="wel">Добро пожаловать, командир <b>${esc(profile.name)}</b></div>
    <div class="feats">
      <div>👆 Тапай по свободной земле — твоя страна растёт</div>
      <div>⚔ Тапни соседа и жми «Атаковать» — бери его землю</div>
      <div>🏙 Строй города за золото — больше войск</div>
      <div>🏆 Захвати 80% суши мира, пока не вышло время</div>
    </div>
    <div class="btns"><button id="tPlay">▶ ИГРАТЬ</button></div>
    <div class="credits">${N_NATIONS} наций · ${N_TRIBES} племён · ${N_BOTS + 2} игроков · союзник: Клод · ★ ${starsTotal().toLocaleString('ru-RU')}</div>
  </div>`;
  t.classList.remove('hidden');
  $('tPlay').onclick = () => { sfx.play('ui'); t.classList.add('hidden'); startPick(); };
}
function starsTotal() { try { return +(localStorage.getItem(STARS_KEY) || 0) || 0; } catch { return 0; } }

// ---------------- этап выбора стартовой точки (20 с) ----------------
function startPick() {
  phase = 'pick';
  document.body.classList.add('ingame');
  spawnStart = nowS(); spawnEnd = spawnStart + SPAWN_SECONDS; claudeAt = 0;
  R.pickMode = true; R.me = me;
  R.fitAll();
  // боты ставят столицы постепенно, чтобы счётчик «n / N на месте» рос
  spawnQ = [];
  for (const p of game.P) {
    if (!p || p.isPlayer || p.isClaude) continue;
    const at = p.kind === KIND.TRIBE ? rand(0.2, 14) : p.kind === KIND.NATION ? rand(0.4, 11) : rand(1.2, 18.6);
    spawnQ.push({ p, at: spawnStart + at });
  }
  spawnQ.sort((a, b) => a.at - b.at);
  $('spawn').classList.remove('hidden');
  updateSpawnPill(true);
}
function runSpawnQueue(all = false) {
  const t = nowS();
  while (spawnQ.length && (all || spawnQ[0].at <= t)) { const { p } = spawnQ.shift(); placeBot(p); }
  if (claudeAt && (all || t >= claudeAt)) { claudeAt = 0; placeClaude(); }
}
function placeBot(p) {
  const t = pickSpawnTile(game, world, p, coords.get(p));
  if (t >= 0) game.reserveSpawn(p, t); else p.alive = false;
}
const humansAll = () => game.P.filter((p) => p && p.kind === KIND.HUMAN);
let pillKey = '';
function updateSpawnPill(force = false) {
  const t = nowS(), left = Math.max(0, spawnEnd - t);
  const hs = humansAll(), placed = hs.filter((p) => p.spawn >= 0);
  const dep = me.spawn >= 0, sec = Math.ceil(left);
  const C = 2 * Math.PI * 15, f = Math.min(1, left / SPAWN_SECONDS);
  const key = `${dep}|${sec}|${placed.length}|${Math.round(f * 60)}`;
  if (force || key !== pillKey) {
    pillKey = key;
    const avs = placed.slice(-5).map((p) => `<img src="${avatarUrl(p)}" alt="">`).join('');
    $('spawn').innerHTML = `<div class="sx"><div class="st ${dep ? 'dep' : ''}">${dep ? `РАЗВЁРТЫВАНИЕ ЧЕРЕЗ ${sec}` : 'ВЫБЕРИ СТАРТОВУЮ ТОЧКУ'}</div>
      <div class="ss">${dep ? 'Тапни в другое место, чтобы перенести столицу.' : 'Тапни любую свободную землю, чтобы поставить столицу.'}</div></div>
      <div class="av">${avs}</div><div class="sp">${placed.length} / ${hs.length} на месте</div>
      <div class="ring"><svg width="36" height="36" viewBox="0 0 36 36"><circle cx="18" cy="18" r="15" stroke="rgba(255,255,255,.14)" stroke-width="3" fill="none"/><circle cx="18" cy="18" r="15" stroke="${dep ? '#EE4062' : '#F3B647'}" stroke-width="3" fill="none" stroke-linecap="round" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - f)).toFixed(1)}" transform="rotate(-90 18 18)"/></svg><b>${sec}</b></div>`;
  }
  if (left <= 0) {
    runSpawnQueue(true);
    if (me.spawn < 0) autoSpawn();
    if (claude.spawn < 0) placeClaude();
    startWar();
  }
}
function avatarUrl(p) {
  if (p.avUrl) return p.avUrl;
  const c = R.avatarOf(p);
  p.avUrl = c ? c.toDataURL() : '';
  return p.avUrl;
}
// столица игрока: свободная суша не ближе 30 клеток оригинала к другим игрокам; племена уступают место
function playerSpawnOk(t) {
  if (!game.canSpawn(t)) return false;
  const x = t % W, y = (t / W) | 0;
  for (const q of game.P) {
    if (!q || q === me || q === claude || q.spawn < 0 || !q.alive || q.kind === KIND.TRIBE) continue;
    const dx = (q.spawn % W) - x, dy = ((q.spawn / W) | 0) - y;
    if (dx * dx + dy * dy < SPAWN_GAP * SPAWN_GAP) return false;
  }
  return true;
}
function nearestFoe(t) {
  let best = null, bd = 1e9;
  const x = t % W, y = (t / W) | 0;
  for (const q of game.P) {
    if (!q || q === me || q === claude || q.spawn < 0 || q.kind === KIND.TRIBE) continue;
    const d = Math.hypot((q.spawn % W) - x, ((q.spawn / W) | 0) - y);
    if (d < bd) { bd = d; best = q; }
  }
  return best;
}
function pickSpawn(sx, sy) {
  const t0 = R.tileAt(sx, sy);
  if (t0 < 0 || !game.isLand(t0)) { tapToast(sx, sy, 'ⓘ Тапни по суше', true); sfx.play('block', { vol: 0.4 }); return; }
  const t = world.nearest(t0, 6, playerSpawnOk);
  if (t < 0) {
    const q = nearestFoe(t0);
    tapToast(sx, sy, q ? `ⓘ Слишком близко к ${q.kind === KIND.NATION ? accName(q.name) : q.name}` : 'ⓘ Здесь нельзя — выбери другое место', true);
    sfx.play('block', { vol: 0.4 });
    return;
  }
  const first = me.spawn < 0;
  game.reserveSpawn(me, t);
  // племена рядом переезжают
  const x = t % W, y = (t / W) | 0;
  for (const q of game.P) {
    if (!q || q.kind !== KIND.TRIBE || q.spawn < 0) continue;
    const dx = (q.spawn % W) - x, dy = ((q.spawn / W) | 0) - y;
    if (dx * dx + dy * dy < TRIBE_GAP * TRIBE_GAP) { q.spawn = -1; placeBot(q); }
  }
  const [wx, wy] = R.tileCenter(t);
  R.ring(wx, wy, '#D7263D', 34, 0.6);
  sfx.play('spawn', { vol: 0.6 });
  // Клод встаёт рядом (и переезжает, если игрок перенёс столицу далеко)
  const cd = claude.spawn >= 0 ? Math.hypot((claude.spawn % W) - x, ((claude.spawn / W) | 0) - y) : 1e9;
  if (first || cd > 45 || cd < 10) claudeAt = nowS() + rand(0.9, 2.2);
  updateSpawnPill(true);
}
function autoSpawn() {
  for (let k = 0; k < 6000; k++) {
    const t = Math.floor(Math.random() * world.n);
    if (world.terr[t] >= 2 && world.terr[t] <= 3 && ((t / W) | 0) < world.H * 0.86 && playerSpawnOk(t)) { game.reserveSpawn(me, t); return; }
  }
  const t = world.nearest(world.tileOf(15, 50), 200, playerSpawnOk);
  if (t >= 0) game.reserveSpawn(me, t);
}
function placeClaude() {
  if (me.spawn < 0) return;
  const cx = me.spawn % W, cy = (me.spawn / W) | 0;
  let best = -1, bs = -1e9;
  for (let k = 0; k < 700; k++) {
    const a = Math.random() * 6.283, r = 15 + Math.random() * 20;
    const x = Math.round(cx + Math.cos(a) * r), y = Math.round(cy + Math.sin(a) * r);
    if (x < 0 || y < 0 || x >= W || y >= world.H) continue;
    const t = y * W + x;
    if (!spawnOk(game, t, claude)) continue;
    const s = game.spawnTilesAt(t).length + Math.random() * 10 - (world.terr[t] === 4 ? 15 : 0);
    if (s > bs) { bs = s; best = t; }
  }
  if (best < 0) best = world.nearest(me.spawn, 90, (t) => spawnOk(game, t, claude));
  if (best >= 0) game.reserveSpawn(claude, best); else claude.alive = false;
}

// ---------------- «НАЧАЛАСЬ ВОЙНА» ----------------
function startWar() {
  phase = 'play';
  $('spawn').classList.add('hidden');
  R.pickMode = false;
  game.spawnAll();
  if (!me.alive || me.spawn < 0) { me.alive = true; autoSpawn(); game.spawn(me, me.spawn); }
  setupBrain(game, me);
  game.running = true;
  stats.start = nowS();
  $('hud').classList.remove('hidden');
  const [x, y] = R.tileCenter(me.spawn);
  R.flyTo(x, y, 5, 1.1);
  horn();
  const wb = $('warBegins');
  wb.classList.remove('hidden', 'go'); void wb.offsetWidth; wb.classList.add('go');
  setTimeout(() => wb.classList.add('hidden'), 2300);
  setHint('👆 Тапни по свободной земле рядом с собой — так твоя страна растёт');
  sys(`🌍 Война началась! Игроков: ${humansAll().length}, наций: ${game.P.filter((p) => p && p.kind === KIND.NATION && p.alive).length}. 5:00 защиты, потом 40:00 до конца. Победа — 80% суши.`, true);
  setTimeout(() => talk(claude, 'start', 'игра началась, ты союзник игрока и стоишь рядом с ним', true), 1500);
  setTimeout(() => { const b = randomBot(); if (b) talk(b, 'start', 'матч в стратегии про захват мира начался'); }, 7000);
  updateHUD(true);
}
function randomBot() { const c = game.P.filter((p) => p && p.leader && !p.isClaude && p.alive); return c.length ? pick(c) : null; }

let sysNext = 0;
function sys(text, force = false) { const t = nowS(); if (!force && t < sysNext) return; sysNext = t + 1.5; chat.system(text); }

// ---------------- события движка ----------------
const lastHitTalk = {};
const SNAME = { city: 'город', port: 'порт', factory: 'завод', post: 'оборонный пост', sam: 'ПВО', silo: 'ракетную шахту' };
const nm = (p) => esc(p.kind === KIND.NATION ? accName(p.name) : p.name); // винительный падеж для наций
function onEvent(type, d) {
  switch (type) {
    case 'tiles': R.onTiles(d.buf, d.n); break;
    case 'attack': {
      const a = d.a, p = a.owner, q = a.target;
      if (q === me && !d.merged && !a.boat) {
        const counter = p.hitBy.get(me.id) !== undefined && game.tickN - p.hitBy.get(me.id) < 400;
        feed(counter ? `${esc(p.name)} контратакует тебя!` : `${esc(p.name)} (${fmtT(a.troops)}) нападает на тебя!`, 'bad', '✕', 8000);
        sfx.play('heavy', { vol: 0.35 });
        if (p.leader && !p.isClaude) talk(p, 'attack', `ты напал на игрока ${profile.name} в стратегии про захват мира`, true);
        if (claude.alive && Math.random() < 0.5) setTimeout(() => talk(claude, 'help', `на игрока напал ${p.name}, ты идёшь на помощь`, true), 2500);
      }
      if (p === me && q && q.leader && !q.isClaude && !d.merged) {
        const k = q.id, t = nowS();
        if (!(lastHitTalk[k] > t)) { lastHitTalk[k] = t + 40; talk(q, 'hit', `игрок ${profile.name} напал на тебя и отжимает твою землю`, true); }
      }
      break;
    }
    case 'clash':
      if (d.p === me) feed(`Встречная атака: ${esc(d.target.name)} −${fmtT(d.troops)}`, 'info', '⚔', 4000);
      else if (d.target === me) feed(`${esc(d.p.name)} отбивает твою атаку`, 'loss', '⚔', 4000);
      break;
    case 'attackEnd':
      if (d.a.owner === me && d.why === 'retreat') feed(`Войска вернулись домой (+${fmtT(d.back)})`, 'faded', 'ⓘ', 3500);
      break;
    case 'boat':
      if (d.b.target === me) { feed(`${esc(d.b.owner.name)} отправил десант к твоему берегу`, 'bad', '⊕', 7000); sfx.play('heavy', { vol: 0.25 }); }
      break;
    case 'boatLand':
      if (d.b.owner === me) feed(d.target ? `Твой десант высадился на землю ${esc(d.target.name)}` : 'Твой десант высадился', 'good', '⛵', 4000);
      else if (d.target === me) { feed(`${esc(d.b.owner.name)} высадил войска на твоём берегу!`, 'bad', '⊕', 7000); sfx.play('heavy', { vol: 0.3 }); }
      break;
    case 'boatHome':
      if (d.b.owner === me) feed('Твой десант вернул войска домой', 'faded', 'ⓘ', 3500);
      break;
    case 'boatSunk':
      if (d.b.owner === me) feed(`Корабль ${esc(d.by.name)} потопил твой десант`, 'loss', '✕', 5000);
      else if (d.by === me) feed(`Твой корабль потопил десант ${esc(d.b.owner.name)}`, 'good', '⚓', 4000);
      break;
    case 'shipSunk':
      if (d.s.owner === me) feed(`${esc(d.by.name)} потопил твой военный корабль`, 'loss', '✕', 5000);
      else if (d.by === me) feed(`Твой корабль потопил корабль ${esc(d.s.owner.name)}`, 'good', '⚓', 4000);
      break;
    case 'eliminated': onEliminated(d); break;
    case 'capture': {
      const s = d.s;
      if (d.to === me && d.from && !d.destroyed) feed(`Ты захватил ${SNAME[s.type]} у ${esc(d.from.name)}`, 'good', '♛', 4000);
      else if (d.from === me && d.to) feed(d.destroyed ? `${esc(d.to.name)} разрушил твой ${SNAME[s.type]}` : `${esc(d.to.name)} захватил твой ${SNAME[s.type]}`, 'loss', '✕', 6000);
      break;
    }
    case 'build':
      if (d.p === me) { const [x, y] = R.tileCenter(d.s.tile ?? 0); if (!d.ship) R.ring(x, y, '#FBE99F', 26, 0.6); sfx.play('build', { vol: 0.6 }); }
      break;
    case 'built':
      if (d.s.owner === me.id) {
        const [x, y] = R.tileCenter(d.s.tile);
        const n = STRUCTS[d.s.type].name;
        R.text(x, y, d.s.level > 1 ? `${n}: ур. ${d.s.level}` : `${n} готов${d.s.type === 'post' ? '' : d.s.type === 'silo' ? 'а' : ''}`, '#fff', 13);
      }
      break;
    case 'defense': R.repaintArea(d.s.tile, STRUCTS.post.range + 1); break;
    case 'ally':
      if (d.a === me || d.b === me) { const o = d.a === me ? d.b : d.a; if (phase === 'play') feed(`Теперь ты в союзе с ${esc(o.name)}`, 'good', '🤝', 4500); }
      break;
    case 'betray':
      if (d.p === me) feed(`Ты разорвал союз с ${esc(d.q.name)}. 30 с ты предатель: атаки на тебя стоят вдвое меньше войск.`, 'info', 'ⓘ', 7000);
      else if (d.q === me) feed(`${esc(d.p.name)} предал тебя!`, 'bad', '✕', 7000);
      break;
    case 'donate':
      if (d.p === me) feed(`Ты отдал ${fmtT(d.troops)} войск ${esc(d.q.name)}`, 'info', '🎁', 3500);
      else if (d.q === me) feed(`${esc(d.p.name)} прислал тебе ${fmtT(d.troops)} войск`, 'good', '🎁', 4000);
      break;
    case 'enclave':
      if (d.to === me) feed(`Окружённая земля ${esc(d.from.name)} теперь твоя`, 'good', '♛', 3500);
      else if (d.from === me) feed(`${esc(d.to.name)} забрал твою окружённую землю`, 'loss', '✕', 4500);
      break;
    case 'end': endGame(d); break;
  }
}
function onEliminated(d) {
  const { v, by, gold } = d;
  if (cardQ === v) closeCard();
  if (v === me) { playerFell(by); return; }
  if (by === me) {
    feed(`Ты уничтожил ${nm(v)}`, 'good', '♛', 5000);
    sfx.play('coin', { vol: 0.45 });
    const L = R.labels.find((l) => l.p === me);
    if (gold > 0 && L) R.text(L.x, L.y + 8, `+${fmt(gold)}`, '#FBE99F', 15, 2.5);
    if (v.leader && !v.isClaude) talk(v, 'eaten', `игрок ${profile.name} уничтожил твою страну`, true);
  } else if (v.kind !== KIND.TRIBE) {
    feed(`${esc(v.name)} уничтожена · ${by ? esc(by.name) : '…'}`, 'faded', 'ⓘ', 4000);
    if (v === claude) talk(claude, 'lose', 'твою страну уничтожили, но игрок ещё в игре', true);
    else if (v.leader && Math.random() < 0.5) talk(v, 'lose', `твою страну уничтожил ${by ? by.name : 'кто-то'}`);
  }
}

// ---------------- выбывание: «ТВОЯ НАЦИЯ ПАЛА» → «ВЫБЫЛ» (смотреть / в меню) ----------------
function playerFell(by) {
  if (phase !== 'play') return;
  phase = 'out';
  closeCard(); closeSheet(); cancelPlacing(); closeRadial(); setHint('');
  sfx.play('death', { vol: 0.7 });
  if (by && by.leader && !by.isClaude) talk(by, 'kill', `ты уничтожил страну игрока ${profile.name}`, true);
  if (claude.alive) setTimeout(() => talk(claude, 'fallen', 'страну игрока уничтожили, подбодри его', true), 3000);
  const f = $('fallen');
  f.innerHTML = '<div class="big">ТВОЯ НАЦИЯ ПАЛА</div>';
  f.classList.remove('hidden', 'go'); void f.offsetWidth; f.classList.add('go');
  setTimeout(() => {
    if (phase !== 'out') return;
    f.classList.remove('go');
    f.innerHTML = `<div class="ocard pnl"><div class="mc">ТЫ ВЫБЫЛ ИЗ МАТЧА</div><div class="res def">ВЫБЫЛ</div>
      <div class="sub">${by ? `Твою страну захватил <b>${esc(by.name)}</b>.` : 'Твоя страна пала.'} Пик: ${pct(me.peakTiles)} суши.</div>
      <div class="btns"><button id="fWatch">👁 Смотреть</button><button class="gray" id="fMenu">↪ В меню</button></div></div>`;
    $('fWatch').onclick = () => { sfx.play('ui'); f.classList.add('hidden'); spectate(); };
    $('fMenu').onclick = () => { sfx.play('ui'); f.classList.add('hidden'); leaveMatch(); };
  }, 2300);
}
function spectate() {
  phase = 'spectate';
  document.body.classList.add('spect');
  $('spect').classList.remove('hidden');
  renderSpect();
  updateHUD(true);
}
function renderSpect() {
  $('spect').innerHTML = `<span>👁 Наблюдение</span><button id="spFast" class="${fast > 1 ? 'on' : ''}">⏩ ×${fast > 1 ? 1 : 3}</button><button id="spMenu">↪ В меню</button>`;
  $('spFast').onclick = () => { fast = fast > 1 ? 1 : 3; sfx.play('ui', { vol: 0.3 }); renderSpect(); };
  $('spMenu').onclick = () => { sfx.play('ui'); leaveMatch(); };
}
// выйти из матча досрочно: награды за то, что успел, и в лобби (или из игры)
function leaveMatch(home = false) {
  if (game && phase !== 'over' && phase !== 'title' && phase !== 'pick' && phase !== 'load') {
    const lead = game.leader();
    awardMatch(false, lead);
  }
  if (home) { ui.goHome(); return; }
  newMatch();
}

// ---------------- ввод: тапы ----------------
// (a) свободная земля — сразу расширение (или десант за море); (b) игрок/нация/племя — карточка цели;
// (c) своя земля — радиальное меню; (d) двойной тап — приблизить ×2
function tap(sx, sy) {
  if (!game) return 'none';
  if (phase === 'pick') { pickSpawn(sx, sy); return 'pick'; }
  if (phase !== 'play' && phase !== 'spectate') return 'none';
  if (radialOpen()) { closeRadial(); return 'none'; }
  if (sheetOpen) { closeSheet(); return 'none'; }
  if (atkOpen) { atkOpen = false; renderRight(); }
  const t = R.tileAt(sx, sy);
  if (placing) { tryBuild(sx, sy); return 'build'; }
  if (t < 0 || !game.isLand(t)) { closeCard(); return 'water'; }
  const id = game.owner[t];
  if (phase === 'spectate') { if (id) openCard(game.P[id], t); else closeCard(); return 'card'; }
  if (id === me.id) { closeCard(); openRadialAt(t, sx, sy); return 'own'; }
  if (id === 0) { closeCard(); expandOrBoat(null, t, sx, sy); return 'attack'; }
  openCard(game.P[id], t);
  sfx.play('ui', { vol: 0.35 });
  return 'card';
}
// по суше достижимо — наземная атака; иначе — десант к ближайшему берегу цели
function expandOrBoat(q, t, sx, sy) {
  if (q ? game.borders(me, q) : game.landConnected(me, t)) return sendAttack(q, sx, sy, t);
  return sendBoatTo(t, sx, sy);
}
const sendN = () => Math.floor(me.troops * ratio);
function sendAttack(target, sx, sy, tile = -1) {
  const n = sendN();
  if (n < 10) { tapToast(sx, sy, 'ⓘ Мало войск. Дай им вырасти', true); sfx.play('block', { vol: 0.35 }); return false; }
  const r = game.attack(me, target, n);
  if (!r.ok) { failToast(r.reason, target, sx, sy); return false; }
  tapToast(sx, sy, target ? `⚔ Атакую ${nm(target)}: ${fmtT(r.troops)}` : `⚔ Расширение: ${fmtT(r.troops)}`);
  const [wx, wy] = tile >= 0 ? R.tileCenter(tile) : R.s2w(sx, sy);
  R.ring(wx, wy, '#ffffff', 30, 0.45);
  sfx.play('march', { vol: 0.35 });
  if (!target && !firstExpand) { firstExpand = true; setHint('Отлично! Тапай ещё — пока вокруг есть ничья земля, расти быстро', 6000); }
  if (target && !firstAttack) { firstAttack = true; setHint('Атаки видно справа сверху (⚔). Там же — ↺ отступление', 6000); }
  if (atkOpen) renderAttacks();
  return true;
}
function sendBoatTo(t, sx, sy) {
  const n = sendN();
  if (n < 10) { tapToast(sx, sy, 'ⓘ Мало войск. Дай им вырасти', true); sfx.play('block', { vol: 0.35 }); return false; }
  if (me.boats.length >= BOAT_MAX) { tapToast(sx, sy, `ⓘ Уже ${BOAT_MAX} десанта в пути`, true); sfx.play('block', { vol: 0.35 }); return false; }
  const land = game.landingNear(t);
  const r = land >= 0 ? game.sendBoat(me, land, n) : { ok: false, reason: 'noroute' };
  if (!r.ok) { failToast(r.reason, game.P[game.owner[t]] || null, sx, sy); return false; }
  const q = r.b.target;
  tapToast(sx, sy, q ? `⛵ Десант на ${nm(q)}: ${fmtT(r.troops)}` : `⛵ Десант: ${fmtT(r.troops)}`);
  const [wx, wy] = R.tileCenter(land);
  R.ring(wx, wy, '#ffffff', 30, 0.45);
  sfx.play('swing', { vol: 0.5 });
  if (atkOpen) renderAttacks();
  return true;
}
function failToast(reason, target, sx, sy) {
  const msg = reason === 'immune' ? `🛡 ${target ? esc(target.name) : 'Цель'} под защитой ещё ${mmss(Math.max(1, (target && target.kind !== KIND.HUMAN ? 50 : game.protLeft) * TICK))}`
    : reason === 'far' ? (target ? `ⓘ Нет общей границы с ${esc(target.name)}` : 'ⓘ Рядом нет свободной земли')
    : reason === 'ally' ? 'ⓘ Это твой союзник' : reason === 'boats' ? `ⓘ Уже ${BOAT_MAX} десанта в пути`
    : reason === 'noroute' ? 'ⓘ Туда не доплыть — нет выхода к морю' : 'ⓘ Мало войск. Дай им вырасти';
  tapToast(sx, sy, msg, true); sfx.play('block', { vol: 0.35 });
}
function tapToast(x, y, text, warn = false) {
  const el = document.createElement('div');
  el.className = 'tt' + (warn ? ' warn' : '');
  el.innerHTML = text;
  el.style.left = Math.max(110, Math.min(innerWidth - 110, x)) + 'px'; el.style.top = Math.max(70, y) + 'px';
  $('taps').appendChild(el);
  while ($('taps').children.length > 4) $('taps').firstChild.remove();
  setTimeout(() => el.remove(), 1500);
}

// ---------------- карточка цели ----------------
const REL = { neutral: ['НЕЙТРАЛ', ''], war: ['ВОЙНА', 'war'], ally: ['СОЮЗ', 'ally'], self: ['ТЫ', 'self'] };
const ROLE = ['Командир', 'Нация', 'Племя'];
const allyAsked = {};
const SW = '<svg width="16" height="16" viewBox="0 0 18 18"><path d="M3 3l9 9M2.5 6.5l4-4M12 12l2.5 2.5M15 3L6 12M15.5 6.5l-4-4M6 12l-2.5 2.5" stroke="#1B2134" stroke-width="2.2" stroke-linecap="round" fill="none"/></svg>';
function openCard(q, t = -1) {
  cardQ = q; cardTile = t;
  R.setHighlight(q.id);
  $('card').classList.remove('hidden');
  document.body.classList.add('card-open');
  renderCard();
}
function closeCard() {
  if (!cardQ) return;
  cardQ = null; cardTile = -1;
  R.setHighlight(0);
  $('card').classList.add('hidden');
  document.body.classList.remove('card-open');
}
function renderCard() {
  const q = cardQ;
  if (!q) return;
  if (!q.alive) { closeCard(); return; }
  $('cSq').style.background = q.color;
  $('cName').textContent = q.name;
  const self = q === me, rel = self ? 'self' : game.relation(me, q), [rt, rc] = REL[rel];
  const pill = $('cRel'); pill.textContent = game.isTraitor(q) ? 'ПРЕДАТЕЛЬ' : rt; pill.className = 'pill ' + (game.isTraitor(q) ? 'war' : rc);
  $('cSub').textContent = `${ROLE[q.kind]} • ${fmtT(q.troops)} войск • ${pct(q.tiles)} земли`;
  const b = $('cAtk'), a = $('cAlly'), n = sendN();
  const spect = phase !== 'play';
  if (self) {
    b.disabled = spect; b.innerHTML = '🏙 Строить';
    a.disabled = false; a.textContent = '📍 Камера';
    return;
  }
  if (spect) { b.disabled = true; b.textContent = '👁 Наблюдение'; a.disabled = false; a.textContent = '📍 Камера'; return; }
  if (rel === 'ally') { b.disabled = true; b.innerHTML = '🤝 Союзник'; }
  else if (!game.canAttack(me, q)) { b.disabled = true; b.innerHTML = `🛡 Защита • ${mmss((q.kind === KIND.HUMAN ? game.protLeft : Math.max(0, 50 - game.tickN)) * TICK)}`; }
  else if (game.borders(me, q)) { b.disabled = false; b.innerHTML = `${SW}Атаковать • ${fmtT(n)}`; }
  else { b.disabled = false; b.innerHTML = `⛵ Десант • ${fmtT(n)}`; }
  if (q.isClaude) { a.disabled = false; a.textContent = '🎁 Помочь'; return; }
  a.disabled = rel === 'ally' || (allyAsked[q.id] || 0) > nowS();
  a.textContent = rel === 'ally' ? '🤝 В союзе' : '🤝 Союз';
}
$('cX').onclick = () => closeCard();
$('cAtk').onclick = () => {
  const q = cardQ;
  if (!q || phase !== 'play') return;
  const r = $('cAtk').getBoundingClientRect(), x = r.left + r.width / 2, y = r.top;
  if (q === me) { closeCard(); openSheet(); return; }
  if (game.borders(me, q)) sendAttack(q, x, y, cardTile);
  else sendBoatTo(cardTile >= 0 && game.owner[cardTile] === q.id ? cardTile : (q.spawn >= 0 ? q.spawn : cardTile), x, y);
  renderCard();
};
$('cAlly').onclick = () => {
  const q = cardQ;
  if (!q) return;
  const r = $('cAlly').getBoundingClientRect(), x = r.left + r.width / 2, y = r.top;
  if (q === me || phase !== 'play') { focusOn(q); return; }
  if (q.isClaude) { doDonate(q, x, y); return; }
  if (game.allied(me, q)) return;
  askAlly(q, x, y);
  renderCard();
};
function askAlly(q, x, y) {
  allyAsked[q.id] = nowS() + 30;
  if (aiAcceptAlly(game, q, me)) {
    game.makeAlly(me, q);
    tapToast(x, y, `🤝 ${esc(q.name)} — теперь союзник`);
    sfx.play('coin', { vol: 0.4 });
    if (q.leader) talk(q, 'acceptAlly', `игрок ${profile.name} предложил союз, и ты согласился`, true);
  } else {
    tapToast(x, y, `${esc(q.name)} отказывается от союза`, true);
    if (q.leader) talk(q, 'refuseAlly', `игрок ${profile.name} предложил союз, а ты отказал`, true);
  }
}
function doDonate(q, x, y) {
  const n = game.donate(me, q, me.troops / 3);
  if (n > 0) { tapToast(x, y, `🎁 ${esc(q.name)}: +${fmtT(n)} войск`); sfx.play('coin', { vol: 0.35 }); }
  else tapToast(x, y, game.tickN - me.donateAt < 100 ? 'ⓘ Подожди немного перед новой помощью' : `ⓘ У ${esc(q.name)} и так полно войск`, true);
}

// ---------------- радиальное меню (тап по своей земле или долгое нажатие) ----------------
const RI = {
  atk: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M3 3l10 10M3 7l4-4M13 13l3 3M17 3L7 13M17 7l-4-4M7 13l-3 3"/></svg>',
  boat: '<svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor"><path d="M2 12h16l-2.6 4.6H4.6z"/><path d="M9.2 2.5v8.5H4.5z"/><path d="M10.6 4.5v6.5h4.8z"/></svg>',
  nuke: '<svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor"><circle cx="10" cy="10" r="2"/><path d="M10 7.6a2.4 2.4 0 0 0-2.1 1.2L4.3 6.7A6.5 6.5 0 0 1 10 3.5zM12.1 8.8a2.4 2.4 0 0 0-2.1-1.2V3.5a6.5 6.5 0 0 1 5.7 3.2zM12.1 11.2a2.4 2.4 0 0 0 0-2.4l3.6-2.1a6.5 6.5 0 0 1 0 6.6zM10 12.4a2.4 2.4 0 0 0 2.1-1.2l3.6 2.1A6.5 6.5 0 0 1 10 16.5zM7.9 11.2a2.4 2.4 0 0 0 2.1 1.2v4.1a6.5 6.5 0 0 1-5.7-3.2zM7.9 8.8a2.4 2.4 0 0 0 0 2.4l-3.6 2.1a6.5 6.5 0 0 1 0-6.6z" opacity=".95"/></svg>',
  ally: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1.5 9l3.5-3.5 3 1.5 2.5-1.5 2.5 1.5 3-1.5L19 9M4 8l5 5.5c.8.8 1.8.3 1.8-.5M7.5 10.5l3 3M10 8.5l3.5 3.5c.8.8 2 0 1.4-.9L16 9"/></svg>',
  focus: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10" cy="10" r="5.5"/><path d="M10 1.5v3M10 15.5v3M1.5 10h3M15.5 10h3"/><circle cx="10" cy="10" r="1.2" fill="currentColor"/></svg>',
  info: '<svg width="20" height="20" viewBox="0 0 20 20"><circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" stroke-width="2"/><rect x="9" y="8.5" width="2" height="6" rx="1" fill="currentColor"/><circle cx="10" cy="6" r="1.3" fill="currentColor"/></svg>',
  retreat: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 6.5A6.5 6.5 0 1 1 3.5 11"/><path d="M4.5 2.5v4h4"/></svg>',
  donate: '<svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor"><rect x="3" y="8" width="14" height="10" rx="1.5"/><rect x="2" y="5.5" width="16" height="3.5" rx="1"/><rect x="9" y="5.5" width="2" height="12.5" fill="#0E1528"/><path d="M10 5.5C8 2 5 2.5 5.5 4.5S10 5.5 10 5.5zM10 5.5c2-3.5 5-3 4.5-1S10 5.5 10 5.5z"/></svg>',
  betray: '<svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor"><path d="M15.5 2l2.5 2.5-8 8-2.5-2.5z"/><path d="M6.5 10.5l3 3-1.5 1.5-3-3z"/><path d="M5 14l1 1-3.5 3.5-1-1z"/></svg>',
  expand: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 3v14M3 10h14M10 3l-2.5 2.5M10 3l2.5 2.5M10 17l-2.5-2.5M10 17l2.5-2.5M3 10l2.5-2.5M3 10l2.5 2.5M17 10l-2.5-2.5M17 10l-2.5 2.5"/></svg>',
  build: '<svg width="20" height="20" viewBox="0 0 20 17" fill="currentColor"><rect x="1" y="7" width="5" height="10" rx="1"/><rect x="7.5" y="1" width="5" height="16" rx="1"/><rect x="14" y="4" width="5" height="13" rx="1"/></svg>',
};
function openRadialAt(t, sx, sy) {
  if (phase !== 'play') return;
  const id = t >= 0 && game.isLand(t) ? game.owner[t] : -1, q = id > 0 ? game.P[id] : null, n = fmtT(sendN()), pr = Math.round(ratio * 100);
  const hasSilo = game.countOf(me, 'silo') > 0;
  const nuke = { id: 'nuke', icon: RI.nuke, label: 'Ядерка', off: true, salmon: true, hint: hasSilo ? 'Ядерные удары — скоро' : 'ⓘ Требуется ракетная шахта' };
  const focus = { id: 'focus', icon: RI.focus, label: 'Камера', hint: 'Камера сюда' };
  let items, title, color = '#fff';
  if (q === me) {
    title = `${me.name} • ${pct(me.tiles)}`; color = me.color;
    const it = (type, label) => {
      const c = game.cost(me, type), pl = game.placement(me, type, t);
      return { id: 'b:' + type, icon: `<g color="#fff">${SVG[type].replace(/width="\d+" height="\d+"/, 'width="20" height="20"')}</g>`, label, off: !pl.ok, hint: pl.ok ? `${STRUCTS[type].name}${pl.up ? ` → ур. ${pl.up.level + 1}` : ''} • ${fmt(c)}${me.gold < c ? ' (мало золота)' : ''}` : type === 'port' ? 'ⓘ Порт — только у берега' : 'ⓘ Слишком близко к другой постройке' };
    };
    items = [it('city', 'Город'), it('port', 'Порт'), it('factory', 'Завод'), it('post', 'Оборона'), { id: 'sheet', icon: RI.build, label: 'Ещё', hint: 'Все постройки' }, focus];
  } else if (q && game.allied(me, q)) {
    title = q.name; color = q.color;
    items = [nuke, { id: 'donate', icon: RI.donate, label: 'Помочь', hint: `Отдать ${fmtT(me.troops / 3)} войск` },
      { id: 'betray', icon: RI.betray, label: 'Предать', red: true, off: q.isClaude, hint: q.isClaude ? 'Клод — твой друг навсегда' : 'Разорвать союз (30 с ты предатель)' }, focus, { id: 'info', icon: RI.info, label: 'Инфо', hint: 'Карточка' }];
  } else if (q) {
    title = q.name; color = q.color;
    const can = game.canAttack(me, q), land = game.borders(me, q);
    const attacking = me.attacks.find((a) => !a.dead && a.target === q && a.retreatAt < 0);
    items = [
      { id: 'attack', icon: RI.atk, label: 'Атака', off: !can || !land, hint: !can ? '🛡 Под защитой' : land ? `Атака • ${n} (${pr}%)` : 'Нет общей границы — десант' },
      { id: 'boat', icon: RI.boat, label: 'Десант', off: !can, hint: `Десант • ${n} войск (${pr}%)` },
      attacking ? { id: 'retreat', icon: RI.retreat, label: 'Отступить', hint: 'Отступить (−25% войск)' } : nuke,
      { id: 'ally', icon: RI.ally, label: 'Союз', off: (allyAsked[q.id] || 0) > nowS(), hint: 'Предложить союз' },
      focus, { id: 'info', icon: RI.info, label: 'Инфо', hint: 'Карточка цели' },
    ];
  } else if (id === 0) {
    title = 'Ничья земля';
    const land = game.landConnected(me, t);
    items = [{ id: 'expand', icon: RI.expand, label: 'Расшириться', off: !land, hint: land ? `Расширение • ${n} (${pr}%)` : 'Не граничит с тобой' },
      { id: 'boat', icon: RI.boat, label: 'Десант', hint: `Десант • ${n} войск (${pr}%)` }, nuke, focus];
  } else {
    title = 'Океан';
    items = [nuke, focus];
  }
  openRadial(sx, sy, {
    title, color, items, hint: '',
    onPick: (k) => radialPick(k, q, t, sx, sy),
  });
  sfx.play('ui', { vol: 0.3 });
}
function radialPick(k, q, t, sx, sy) {
  sfx.play('ui', { vol: 0.35 });
  if (k.startsWith('b:')) { const type = k.slice(2); const r = game.build(me, type, t); buildResult(r, type, sx, sy); return; }
  if (k === 'sheet') { openSheet(); return; }
  if (k === 'focus') { const [x, y] = R.s2w(sx, sy); R.flyTo(x, y, Math.max(R.cam.z * 1.6, 5), 0.3); return; }
  if (k === 'info' && q) { openCard(q, t); return; }
  if (k === 'attack' && q) { sendAttack(q, sx, sy, t); return; }
  if (k === 'expand') { sendAttack(null, sx, sy, t); return; }
  if (k === 'boat') { sendBoatTo(t, sx, sy); return; }
  if (k === 'retreat' && q) { for (const a of me.attacks) if (!a.dead && a.target === q) game.retreat(a); tapToast(sx, sy, '↺ Отступаем'); return; }
  if (k === 'ally' && q) { askAlly(q, sx, sy); return; }
  if (k === 'donate' && q) { doDonate(q, sx, sy); return; }
  if (k === 'betray' && q && !q.isClaude) { game.breakAlly(me, q); sfx.play('heavy', { vol: 0.3 }); if (q.leader) talk(q, 'betrayed', `игрок ${profile.name} предал ваш союз`, true); }
}

// ---------------- нижняя панель ----------------
function renderChips() {
  $('chips').innerHTML = RATIOS.map((r) => `<button data-r="${r}" class="${r === ratio ? 'on' : ''}">${Math.round(r * 100)}%</button>`).join('');
  $('chips').querySelectorAll('button').forEach((b) => (b.onclick = () => setRatio(+b.dataset.r)));
}
function setRatio(r) {
  ratio = r;
  $('chips').querySelectorAll('button').forEach((b) => b.classList.toggle('on', +b.dataset.r === r));
  sfx.play('ui', { vol: 0.3 });
  updateHUD(true);
}
const prev = {};
const setT = (id, v) => { if (prev[id] !== v) { prev[id] = v; $(id).textContent = v; } };
const setH = (id, v) => { if (prev[id] !== v) { prev[id] = v; $(id).innerHTML = v; } };
const SHIELD = '<svg width="14" height="16" viewBox="0 0 14 16"><path d="M7 .8l5.8 2.4v4.6c0 3.6-2.5 6-5.8 7.4C3.7 13.8 1.2 11.4 1.2 7.8V3.2z" fill="#8BE1B4"/><path d="M4.4 8l1.9 1.9 3.4-3.6" stroke="#0f3a26" stroke-width="1.6" fill="none" stroke-linecap="round"/></svg>';
function updateHUD(force) {
  if (!game || !me || (phase !== 'play' && phase !== 'spectate' && phase !== 'out' && !force)) return;
  const cap = game.maxTroops(me), war = game.troopsAtWar(me);
  setT('hTroops', fmtT(me.troops));
  setT('hRate', `+${fmt(Math.max(0, game.regen(me)))}/с`);
  const bw = Math.min(100, (me.troops / cap) * 100).toFixed(1) + '%';
  if (prev.bar !== bw) { prev.bar = bw; $('hBar').style.width = bw; }
  setT('hGold', fmt(me.gold));
  setT('hSend', fmtT(sendN()));
  const hw = $('hWar');
  if (war >= 10) { hw.classList.remove('hidden'); setT('hWar', `${fmtT(war)} в бою`); } else hw.classList.add('hidden');
  $('bTroops').title = `Войска ${fmtT(me.troops)} / ${fmtT(cap)}`;
  // плашка справа сверху: защита (зелёный щит) или оставшееся время, своё место и доля суши
  const prot = game.protLeft;
  if (game.over) setH('sTime', 'КОНЕЦ');
  else if (prot > 0) setH('sTime', `${SHIELD}<span>${mmss(prot * TICK)}</span>`);
  else setH('sTime', `<span>${mmss(Math.max(0, MATCH_TICKS - game.tickN) * TICK)}</span>`);
  $('sTime').classList.toggle('prot', prot > 0 && !game.over);
  $('sSq').style.background = me.color;
  setT('sRank', me.alive ? `#${rankOf(me)} • ${pct(me.tiles)}` : 'ВЫБЫЛ');
  renderRight();
  if (cardQ) renderCard();
  if (sheetOpen) renderSheet();
  if (placing) updateGhostInfo();
  refreshAlt();
}
function rankOf(p) { let r = 1; for (const q of game.P) if (q && q !== p && q.alive && q.tiles > p.tiles) r++; return r; }
setInterval(() => updateHUD(), 200);

// ---------------- атаки и лидеры (справа) ----------------
let lastRight = '';
function renderRight() {
  const out = me.attacks.filter((a) => !a.dead), inc = game.attacks.filter((a) => !a.dead && a.target === me);
  const binc = game.boats.filter((b) => b.target === me);
  const n = out.length + inc.length + me.boats.length + binc.length;
  const chip = $('atk');
  chip.classList.toggle('hidden', n === 0 || atkOpen || phase !== 'play');
  chip.classList.toggle('inc', inc.length + binc.length > 0);
  setT('atkN', String(n));
  if (n === 0 && atkOpen) atkOpen = false;
  $('atkList').classList.toggle('hidden', !atkOpen);
  $('lb').classList.toggle('hidden', !lbOpen);
  lbBtn.classList.toggle('on', lbOpen);
  if (atkOpen) renderAttacks();
  if (lbOpen) renderLB();
}
function renderAttacks() {
  const out = me.attacks.filter((a) => !a.dead), inc = game.attacks.filter((a) => !a.dead && a.target === me);
  const binc = game.boats.filter((b) => b.target === me), bout = me.boats;
  const no = out.length + bout.length, ni = inc.length + binc.length;
  const sum = [no ? `${no} исх.` : '', ni ? `<em>${ni} вх.</em>` : ''].filter(Boolean).join(' • ');
  let h = `<div class="ph"><svg width="13" height="13" viewBox="0 0 18 18"><path d="M3 3l9 9M2.5 6.5l4-4M12 12l2.5 2.5M15 3L6 12M15.5 6.5l-4-4M6 12l-2.5 2.5" stroke="#F3B647" stroke-width="2.2" stroke-linecap="round" fill="none"/></svg><b>АТАКИ</b><span>${sum}</span><button data-x="1">⌃</button></div>`;
  for (const a of inc) h += `<div class="ar in"><span style="color:#F06A8C">⊕</span><i class="sq" style="background:${a.owner.color}"></i><span class="nm">${esc(a.owner.name)}</span><span class="tr">${fmtT(a.troops)}</span><button data-f="${a.owner.id}">👁</button></div>`;
  for (const b of binc) h += `<div class="ar in"><span style="color:#F06A8C">⛵</span><i class="sq" style="background:${b.owner.color}"></i><span class="nm">${esc(b.owner.name)}</span><span class="tr">${fmtT(b.troops)}</span><button data-f="${b.owner.id}">👁</button></div>`;
  for (const a of out) {
    const nmT = a.target ? esc(a.target.name) : 'Расширение';
    const ic = a.target ? `<i class="sq" style="background:${a.target.color}"></i>` : '<i class="dot"></i>';
    h += `<div class="ar ${a.retreatAt >= 0 ? 'ret' : ''}"><span style="color:#F3B647">⚔</span>${ic}<span class="nm">${nmT}</span><span class="tr">${fmtT(a.troops)}</span><button data-r="${a.id}" ${a.retreatAt >= 0 ? 'disabled' : ''}>↺</button></div>`;
  }
  for (const b of bout) {
    const ic = b.target ? `<i class="sq" style="background:${b.target.color}"></i>` : '<i class="dot"></i>';
    h += `<div class="ar ${b.back ? 'ret' : ''}"><span style="color:#F3B647">⛵</span>${ic}<span class="nm">${b.target ? esc(b.target.name) : 'Высадка'}</span><span class="tr">${fmtT(b.troops)}</span><button data-b="${b.id}" ${b.back ? 'disabled' : ''}>↺</button></div>`;
  }
  if (h === lastRight) return;
  lastRight = h;
  const el = $('atkList');
  el.innerHTML = h;
  el.querySelector('[data-x]').onclick = () => { atkOpen = false; renderRight(); };
  el.querySelectorAll('[data-r]').forEach((b) => (b.onclick = () => {
    const a = me.attacks.find((x) => x.id === +b.dataset.r);
    if (a) { game.retreat(a); sfx.play('ui', { vol: 0.4 }); lastRight = ''; renderAttacks(); }
  }));
  el.querySelectorAll('[data-b]').forEach((b) => (b.onclick = () => {
    const x = me.boats.find((y) => y.id === +b.dataset.b);
    if (x) { game.retreatBoat(x); sfx.play('ui', { vol: 0.4 }); lastRight = ''; renderAttacks(); }
  }));
  el.querySelectorAll('[data-f]').forEach((b) => (b.onclick = () => focusOn(game.P[+b.dataset.f])));
}
function focusOn(p) {
  const L = R.labels.find((l) => l.p === p);
  if (L) R.flyTo(L.x, L.y, Math.max(R.cam.z, 4), 0.35);
  else if (p.spawn >= 0) { const [x, y] = R.tileCenter(p.spawn); R.flyTo(x, y, Math.max(R.cam.z, 4), 0.35); }
}
let lastLB = '';
function renderLB() {
  const alive = game.P.filter((p) => p && p.alive && p.tiles > 0).sort((a, b) => b.tiles - a.tiles);
  const rows = alive.slice(0, 10);
  if (!rows.includes(me) && me.alive) rows.push(me);
  const nAlive = alive.filter((p) => p.kind !== KIND.TRIBE).length;
  let h = `<div class="ph"><span style="margin:0;color:#F3B647;letter-spacing:0">🏆</span><b>ЛИДЕРЫ</b><span>${nAlive} в живых</span><button data-x="1">✕</button></div>
    <div class="lr lh"><span class="rk">#</span><span class="nmc">НАЦИЯ</span><span class="ld">ЗЕМЛЯ</span><span class="tp">ВОЙСКА</span></div>`;
  for (const p of rows) {
    const rk = alive.indexOf(p) + 1;
    const av = p.kind === KIND.HUMAN && p.skin ? `<img src="${avatarUrl(p)}" alt="">` : '';
    h += `<div class="lr ${p === me ? 'me' : ''}" data-f="${p.id}"><span class="rk">${rk}</span><span class="nmc"><i class="sq" style="background:${p.color}"></i>${av}<span class="nn">${esc(p.name)}</span></span><span class="ld">${pct(p.tiles)}</span><span class="tp">${fmtT(p.troops)}</span></div>`;
  }
  if (h === lastLB) return;
  lastLB = h;
  const el = $('lb');
  el.innerHTML = h;
  el.querySelector('[data-x]').onclick = () => toggleLB(false);
  el.querySelectorAll('.lr[data-f]').forEach((r) => (r.onclick = () => focusOn(game.P[+r.dataset.f])));
}
function toggleLB(v = !lbOpen) {
  if (!game || (phase !== 'play' && phase !== 'spectate')) return;
  lbOpen = v; if (lbOpen) atkOpen = false; lastLB = '';
  sfx.play('ui', { vol: 0.3 });
  renderRight();
}
$('status').onclick = () => toggleLB();
$('atk').onclick = () => { atkOpen = true; lbOpen = false; lastRight = ''; sfx.play('ui', { vol: 0.3 }); renderRight(); };

// ---------------- лента событий ----------------
function feed(html, type = 'info', icon = 'ⓘ', ttl = 4000) {
  if (phase !== 'play' && phase !== 'spectate') return;
  const box = $('feed');
  for (const c of box.children) { // повтор того же события — счётчик ×N вместо новой карточки
    if (c.dataset.h !== html) continue;
    const n = (+c.dataset.n || 1) + 1; c.dataset.n = n;
    let x = c.querySelector('em'); if (!x) { x = document.createElement('em'); c.appendChild(x); }
    x.textContent = '×' + n;
    clearTimeout(c._t); c.style.opacity = 1;
    c._t = setTimeout(() => { c.style.opacity = 0; setTimeout(() => c.remove(), 450); }, ttl);
    return;
  }
  const el = document.createElement('div');
  el.className = 'fe pnl ' + type;
  el.innerHTML = `<i>${icon}</i><span>${html}</span>`;
  el.dataset.h = html;
  box.appendChild(el);
  while (box.children.length > 2) box.firstChild.remove();
  el._t = setTimeout(() => { el.style.opacity = 0; setTimeout(() => el.remove(), 450); }, ttl);
}

// ---------------- постройки: лист 5×2, подсказки, размещение с «призраком» ----------------
const SVG = {
  city: '<svg width="22" height="18" viewBox="0 0 20 17"><rect x="1" y="7" width="5" height="10" rx="1" fill="#fff"/><rect x="7.5" y="1" width="5" height="16" rx="1" fill="#fff"/><rect x="14" y="4" width="5" height="13" rx="1" fill="#fff"/></svg>',
  port: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="10" cy="4" r="2"/><path d="M10 6v12M6 9h8M3 12c1 4 4 6 7 6s6-2 7-6"/></svg>',
  factory: '<svg width="22" height="18" viewBox="0 0 22 18"><path d="M1 17V8l5-3v3l5-3v3l5-3V1h4v16z" fill="#fff"/></svg>',
  post: '<svg width="18" height="20" viewBox="0 0 18 20"><path d="M9 1l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V4z" fill="#fff"/></svg>',
  sam: '<svg width="20" height="20" viewBox="0 0 20 20"><path d="M2 3h16l-3 4H5z" fill="#fff"/><rect x="9" y="7" width="2" height="9" fill="#fff"/><rect x="5" y="16" width="10" height="3" rx="1" fill="#fff"/></svg>',
  silo: '<svg width="16" height="20" viewBox="0 0 16 20"><path d="M8 1c3 3 4 7 4 11H4c0-4 1-8 4-11z" fill="#fff"/><path d="M4 12l-3 5h4zM12 12l3 5h-4z" fill="#fff"/></svg>',
  warship: '<svg width="22" height="16" viewBox="0 0 22 16"><path d="M1 10h20l-3 5H4z" fill="#fff"/><rect x="7" y="5" width="8" height="4" fill="#fff"/><rect x="10" y="1" width="2" height="4" fill="#fff"/></svg>',
  atom: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="1.6"><ellipse cx="10" cy="10" rx="8.5" ry="3.3"/><ellipse cx="10" cy="10" rx="8.5" ry="3.3" transform="rotate(60 10 10)"/><ellipse cx="10" cy="10" rx="8.5" ry="3.3" transform="rotate(-60 10 10)"/><circle cx="10" cy="10" r="1.6" fill="#fff"/></svg>',
  hydro: '<svg width="20" height="20" viewBox="0 0 20 20"><path d="M3 9a7 6 0 0 1 14 0c0 2-2 3-4 3H7c-2 0-4-1-4-3z" fill="#fff"/><rect x="8" y="11" width="4" height="7" fill="#fff"/><rect x="5" y="17" width="10" height="2" rx="1" fill="#fff"/></svg>',
  mirv: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M10 18V8M10 8L4 2M10 8l6-6M10 8V1"/></svg>',
};
const ITEMS = [
  { k: '1', type: 'city', name: 'Город', desc: 'Лимит войск +25K за каждый уровень. Поставь рядом с городом ещё один — он улучшится.' },
  { k: '2', type: 'port', name: 'Порт', desc: 'Ставится на своём берегу. Торговля: +500 золота/с за уровень. Нужен для военных кораблей.' },
  { k: '3', type: 'factory', name: 'Завод', desc: 'Промышленность: +400 золота/с за уровень. Порт и завод дорожают вместе.' },
  { k: '4', type: 'post', name: 'Оборона', full: 'Оборонный пост', desc: 'Атаки на твою землю рядом с постом: враг теряет ×5 войск и идёт ×3 медленнее. Не улучшается.' },
  { k: '5', type: 'sam', name: 'ПВО', full: 'Зенитный комплекс (ПВО)', desc: 'Сбивает вражеские ядерные ракеты в радиусе действия. Строится 30 с.' },
  { k: '6', type: 'silo', name: 'Шахта', full: 'Ракетная шахта', desc: 'Нужна для запуска ядерных ракет. Строится 10 с.' },
  { k: '7', type: 'warship', name: 'Корабль', full: 'Военный корабль', desc: 'Тапни по воде — выйдет из ближайшего порта и будет патрулировать. Топит вражеский десант и корабли.' },
  { k: '8', type: 'atom', name: 'Атомная', full: 'Атомная бомба', cost: 750000, nuke: true, desc: 'Взрыв радиусом 30 клеток (12 — полное уничтожение).' },
  { k: '9', type: 'hydro', name: 'Водородная', full: 'Водородная бомба', cost: 5e6, nuke: true, desc: 'Огромный взрыв: всё внутри стирается.' },
  { k: '0', type: 'mirv', name: 'MIRV', full: 'MIRV', cost: 25e6, nuke: true, desc: 'Раскалывается на сотни боеголовок над землёй цели.' },
];
const itemOf = (type) => ITEMS.find((x) => x.type === type);
const costOf = (it) => (it.nuke ? it.cost : game.cost(me, it.type));
let lastSheet = '';
function renderSheet() {
  let h = '';
  const silo = game.countOf(me, 'silo') > 0;
  for (const it of ITEMS) {
    const cost = costOf(it), lock = it.nuke && !silo;
    const ok = me.gold >= cost;
    const own = it.nuke ? 0 : game.countOf(me, it.type);
    h += `<button class="bi ${lock ? 'lock' : ''} ${placing === it.type ? 'sel' : ''}" data-t="${it.type}"><span class="k">${it.k}</span><span class="o">×${own}</span>${SVG[it.type]}<span class="nm">${it.name}</span><span class="c ${ok ? '' : 'no'}">${fmt(cost)}</span></button>`;
  }
  if (h === lastSheet) return;
  lastSheet = h;
  const el = $('sheet');
  el.innerHTML = h;
  el.querySelectorAll('.bi').forEach((b) => {
    let lp = 0, held = false;
    b.onpointerdown = (e) => { held = false; clearTimeout(lp); lp = setTimeout(() => { held = true; showTip(b.dataset.t, b); }, 450); };
    b.onpointerup = b.onpointercancel = b.onpointerleave = () => { clearTimeout(lp); if (held) setTimeout(hideTip, 1600); };
    b.onclick = () => { if (!held) selectBuild(b.dataset.t); };
    b.onmouseenter = () => { if (matchMedia('(hover:hover)').matches) showTip(b.dataset.t, b); };
    b.onmouseleave = () => hideTip();
  });
}
function showTip(type, btn) {
  const it = itemOf(type), cost = costOf(it), silo = game.countOf(me, 'silo') > 0;
  const own = it.nuke ? 0 : game.countOf(me, type);
  const el = $('tip');
  el.innerHTML = `<div class="tt1"><b>${it.full || it.name}</b><kbd>${it.k}</kbd></div>
    <div class="tt2">Цена <b class="${me.gold >= cost ? '' : 'no'}">${fmt(cost)}</b> золота</div><div class="tt2">Есть ${own}</div>
    <div class="tt3">${it.desc}</div>${it.nuke && !silo ? '<div class="tt4">ⓘ Требуется ракетная шахта</div>' : it.nuke ? '<div class="tt4 dim">ⓘ Ядерные удары — в следующем обновлении</div>' : ''}`;
  el.classList.remove('hidden');
  const r = btn.getBoundingClientRect(), tw = el.offsetWidth, th = el.offsetHeight;
  el.style.left = Math.max(8, Math.min(innerWidth - tw - 8, r.left + r.width / 2 - tw / 2)) + 'px';
  el.style.top = Math.max(8, r.top - th - 8) + 'px';
}
function hideTip() { $('tip').classList.add('hidden'); }
function openSheet() { if (phase !== 'play') return; sheetOpen = true; lastSheet = ''; renderSheet(); $('sheet').classList.remove('hidden'); $('bBuild').classList.add('on'); closeCard(); closeRadial(); }
function closeSheet() { sheetOpen = false; hideTip(); $('sheet').classList.add('hidden'); $('bBuild').classList.toggle('on', !!placing); }
$('bBuild').onclick = () => { sfx.play('ui', { vol: 0.35 }); if (sheetOpen) closeSheet(); else { cancelPlacing(); openSheet(); } };
function selectBuild(type) {
  const it = itemOf(type);
  if (!it || phase !== 'play') return;
  if (it.nuke) {
    if (!game.countOf(me, 'silo')) ui.toast('ⓘ Требуется ракетная шахта (6)', 1700);
    else ui.toast(`${it.full} — ядерные удары появятся в следующем обновлении`, 1900);
    sfx.play('block', { vol: 0.3 });
    return;
  }
  sfx.play('ui', { vol: 0.4 });
  placing = type;
  closeSheet(); closeCard();
  $('bBuild').classList.add('on');
  $('placing').classList.remove('hidden');
  // призрак — сразу в центре экрана, дальше следует за пальцем
  setGhost(R.tileAt(R.w / 2, R.h / 2));
  updateGhostInfo();
}
function setGhost(t0) {
  if (!placing) return;
  const pl = game.placement(me, placing, t0), cost = game.cost(me, placing);
  const why = { own: 'не твоя земля', space: 'тесно', shore: 'нужен берег', busy: 'строится', port: 'нет порта', far: '' }[pl.reason] || '';
  R.ghost = { type: placing, tile: placing === 'warship' && pl.ok ? pl.tile : pl.tile, ok: pl.ok, up: pl.up, cost, afford: me.gold >= cost, why: pl.ok ? '' : `✕ ${why}`, tap: t0 };
}
function updateGhostInfo() {
  const it = itemOf(placing), cost = game.cost(me, placing);
  if (R.ghost) { R.ghost.cost = cost; R.ghost.afford = me.gold >= cost; }
  const hint = placing === 'warship' ? 'тапни по воде у своего порта' : placing === 'port' ? 'тапни у своего берега' : R.ghost && R.ghost.up ? 'улучшение' : 'веди пальцем, отпусти — построить';
  setH('plTxt', `${it.full || it.name} · <b class="${me.gold >= cost ? '' : 'no'}">${fmt(cost)}</b> · ${hint}`);
}
function cancelPlacing() { placing = null; R.ghost = null; $('placing').classList.add('hidden'); $('bBuild').classList.toggle('on', sheetOpen); }
$('plX').onclick = () => { sfx.play('ui', { vol: 0.3 }); cancelPlacing(); };
function tryBuild(sx, sy) {
  const t = R.tileAt(sx, sy);
  setGhost(t);
  const r = game.build(me, placing, t);
  if (!r.ok) {
    const msg = r.reason === 'gold' ? `ⓘ Нужно ${fmt(r.cost)} золота` : r.reason === 'space' ? 'ⓘ Слишком близко к другой постройке'
      : r.reason === 'shore' ? 'ⓘ Порт ставится на своём берегу' : r.reason === 'busy' ? 'ⓘ Эта постройка ещё строится'
      : r.reason === 'port' ? 'ⓘ Нужен достроенный порт у этой воды' : 'ⓘ Строить можно только на своей земле';
    tapToast(sx, sy, msg, true); sfx.play('block', { vol: 0.35 });
    return;
  }
  buildResult(r, placing, sx, sy);
  cancelPlacing();
}
function buildResult(r, type, sx, sy) {
  if (!r.ok) {
    const msg = r.reason === 'gold' ? `ⓘ Нужно ${fmt(r.cost)} золота` : r.reason === 'shore' ? 'ⓘ Порт ставится на своём берегу' : 'ⓘ Здесь нельзя строить';
    tapToast(sx, sy, msg, true); sfx.play('block', { vol: 0.35 });
    return;
  }
  const it = itemOf(type);
  tapToast(sx, sy, r.ship ? '⚓ Корабль выходит из порта' : r.upgrade ? `⬆ ${it.full || it.name}: улучшение` : `🏗 ${it.full || it.name} строится`);
}

// ---------------- подсказка ----------------
let hintTimer = 0;
function setHint(t, ms = 0) {
  $('hint').textContent = t;
  clearTimeout(hintTimer);
  if (ms) hintTimer = setTimeout(() => { if ($('hint').textContent === t) $('hint').textContent = ''; }, ms);
}

// ---------------- конец матча: МАТЧ ЗАВЕРШЁН, ПОБЕДА/ПОРАЖЕНИЕ, 4 карточки, звёзды ----------------
let awarded = false, endTimer = 0;
function awardMatch(win, winner) {
  if (awarded) return { stars: 0, coins: 0 };
  awarded = true;
  const peak = share(me.peakTiles);
  const stars = Math.round(200 + 60 * peak + 150 * me.killsN + (win ? 3000 : 0));
  try { localStorage.setItem(STARS_KEY, String(starsTotal() + stars)); } catch {}
  const coins = win ? 60 + Math.round(peak) : 5 + Math.round(peak * 0.6);
  addCoins(coins);
  addStat('roworld', 'games', 1);
  if (win) addStat('roworld', 'wins', 1);
  if (me.killsN) addStat('roworld', 'kills', me.killsN);
  return { stars, coins };
}
function endGame(d) {
  if (phase === 'over') return;
  const wasOut = phase === 'out' || phase === 'spectate';
  phase = 'over';
  closeCard(); closeSheet(); cancelPlacing(); closeRadial(); setHint('');
  $('fallen').classList.add('hidden'); $('spect').classList.add('hidden');
  const win = d.winner === me && me.alive;
  const { stars, coins } = awardMatch(win, d.winner);
  sfx.play(win ? 'win' : 'lose');
  talk(claude, win ? 'win' : 'lose', win ? 'игрок победил в стратегии, поздравь' : 'игрок проиграл, подбодри', true);
  const wname = d.winner ? esc(d.winner.name) : '—';
  const land = d.winner ? share(d.winner.tiles).toFixed(1) : '0';
  const why = win ? (d.reason === 'share' ? `Ты захватил мир: ${land}% суши вне радиации.` : `Время вышло — ты крупнейшая страна: ${land}% суши вне радиации.`)
    : d.reason === 'share' ? `${wname} захватил мир (${land}% суши вне радиации).` : `Время вышло. Победил ${wname} (${land}% суши вне радиации).`;
  if (!win && d.winner && d.winner.leader && !d.winner.isClaude) setTimeout(() => talk(d.winner, 'win', 'ты победил в стратегии про захват мира', true), 2500);
  const dur = game.time;
  const IC = {
    globe: '<svg width="18" height="18" viewBox="0 0 22 22" fill="none" stroke="#E8A33D" stroke-width="2"><circle cx="11" cy="11" r="9"/><ellipse cx="11" cy="11" rx="4" ry="9"/><path d="M2 11h18"/></svg>',
    helm: '<svg width="20" height="17" viewBox="0 0 16 14"><path d="M1.5 10.5C1.5 5.5 4.5 2 8 2s6.5 3.5 6.5 8.5z" fill="#5CC8D7"/><rect x="0.5" y="10" width="15" height="2.4" rx="1.2" fill="#5CC8D7"/></svg>',
    skull: '<svg width="18" height="18" viewBox="0 0 18 18"><path d="M9 1.5c-4 0-6.8 2.8-6.8 6.4 0 2.2 1 3.7 2.3 4.6v2.4h9v-2.4c1.3-.9 2.3-2.4 2.3-4.6C15.8 4.3 13 1.5 9 1.5z" fill="#E0607F"/><circle cx="6.3" cy="8.3" r="1.7" fill="#131B2E"/><circle cx="11.7" cy="8.3" r="1.7" fill="#131B2E"/><rect x="7.5" y="12.5" width="1.2" height="2.4" fill="#131B2E"/><rect x="9.3" y="12.5" width="1.2" height="2.4" fill="#131B2E"/></svg>',
    clock: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="#A58BEA" stroke-width="2" stroke-linecap="round"><circle cx="9" cy="9" r="7.2"/><path d="M9 5v4.3l2.8 1.8"/></svg>',
  };
  setTimeout(() => {
    const e = $('endscr');
    let next = 30, close = 18;
    e.innerHTML = `<div class="ec">
      <div class="mc">МАТЧ ЗАВЕРШЁН</div>
      <div class="resw ${win ? '' : 'def'}"><span class="rb">${win ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ'}</span><span class="rf">${win ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ'}</span></div>
      <div class="sub">${why}</div>
      <div class="st4">
        <div>${IC.globe}<b>${share(me.peakTiles).toFixed(1)}%</b><small>ПИК ЗЕМЛИ</small></div>
        <div>${IC.helm}<b>${fmtT(me.maxTroopsSeen)}</b><small>МАКС. ВОЙСК</small></div>
        <div>${IC.skull}<b>${me.killsN}</b><small>НАЦИЙ УНИЧТОЖЕНО</small></div>
        <div>${IC.clock}<b>${mmss(dur)}</b><small>ДЛИТЕЛЬНОСТЬ</small></div>
      </div>
      <div class="erow"><div class="stars">★ +${stars.toLocaleString('ru-RU')} Звёзд</div><div class="coins">🪙 +${coins}</div><button id="eHome">↪ В главное меню</button></div>
      <div class="efoot" id="eFoot"></div>
    </div>`;
    e.classList.remove('hidden');
    const tickFoot = () => {
      $('eFoot').textContent = `Следующий матч через ${mmss(next)} • итоги закроются через ${mmss(close)}`;
      if (close <= 0) { clearInterval(endTimer); e.classList.add('hidden'); newMatch(); return; }
      next--; close--;
    };
    tickFoot();
    clearInterval(endTimer);
    endTimer = setInterval(tickFoot, 1000);
    $('eHome').onclick = () => { sfx.play('ui'); clearInterval(endTimer); e.classList.add('hidden'); newMatch(); };
  }, wasOut ? 300 : 1500);
}
function closeAll() {
  clearInterval(endTimer);
  for (const id of ['endscr', 'title', 'spawn', 'hud', 'fallen', 'spect', 'help', 'warBegins']) $(id).classList.add('hidden');
  $('feed').innerHTML = ''; $('taps').innerHTML = '';
  document.body.classList.remove('spect', 'card-open');
  closeCard(); closeRadial(); hideTip(); sheetOpen = false; $('sheet').classList.add('hidden'); placing = null; R.ghost = null; $('placing').classList.add('hidden');
  atkOpen = lbOpen = false; lastRight = lastLB = lastSheet = ''; pillKey = ''; R.spawnMark = -1; R.pickMode = false; setHint('');
  awarded = false;
  for (const k in prev) delete prev[k];
}

// ---------------- ввод: тап, долгое нажатие (радиальное меню), двойной тап (зум ×2),
// перетаскивание с инерцией, щипок; в режиме постройки палец ведёт «призрак» ----------------
const ptrs = new Map();
let drag = null, pinch = null, vel = { x: 0, y: 0 }, multi = false, lastTap = null;
const LONG_MS = 500;
canvas.addEventListener('pointerdown', (e) => {
  try { canvas.setPointerCapture(e.pointerId); } catch {}
  ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptrs.size === 1) {
    drag = { x0: e.clientX, y0: e.clientY, lx: e.clientX, ly: e.clientY, t0: performance.now(), lt: performance.now(), moved: false, hold: false, lp: 0 };
    vel.x = vel.y = 0; multi = false; R.fly = null;
    if (placing && phase === 'play') { setGhost(R.tileAt(e.clientX, e.clientY)); drag.place = true; }
    else if (phase === 'play' && !radialOpen()) {
      drag.lp = setTimeout(() => {
        if (!drag || drag.moved || multi) return;
        drag.hold = true;
        closeCard(); closeSheet();
        openRadialAt(R.tileAt(drag.x0, drag.y0), drag.x0, drag.y0);
        if (navigator.vibrate) try { navigator.vibrate(12); } catch {}
      }, LONG_MS);
    }
  } else if (ptrs.size === 2) {
    multi = true;
    if (drag) clearTimeout(drag.lp);
    const [a, b] = [...ptrs.values()];
    pinch = { d0: Math.hypot(a.x - b.x, a.y - b.y) || 1, z0: R.cam.z, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2 };
  }
});
canvas.addEventListener('pointermove', (e) => {
  if (!ptrs.has(e.pointerId)) {
    if (placing && e.pointerType === 'mouse') setGhost(R.tileAt(e.clientX, e.clientY)); // ПК: призрак за курсором
    return;
  }
  ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptrs.size >= 2 && pinch) {
    const [a, b] = [...ptrs.values()];
    const d = Math.hypot(a.x - b.x, a.y - b.y) || 1, mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    R.zoomAt(mx, my, (pinch.z0 * d) / pinch.d0 / R.cam.z);
    R.pan(mx - pinch.mx, my - pinch.my);
    pinch.mx = mx; pinch.my = my;
    return;
  }
  if (!drag) return;
  if (drag.hold) { radialHover(e.clientX, e.clientY); return; }
  const dx = e.clientX - drag.lx, dy = e.clientY - drag.ly;
  if (!drag.moved && Math.hypot(e.clientX - drag.x0, e.clientY - drag.y0) > 9) { drag.moved = true; clearTimeout(drag.lp); }
  if (drag.place) { setGhost(R.tileAt(e.clientX, e.clientY)); drag.lx = e.clientX; drag.ly = e.clientY; return; }
  if (drag.moved) {
    R.pan(dx, dy);
    const now = performance.now(), dtt = Math.max(1, now - drag.lt);
    vel.x = vel.x * 0.6 + (dx / dtt) * 1000 * 0.4; vel.y = vel.y * 0.6 + (dy / dtt) * 1000 * 0.4;
    drag.lt = now;
  }
  drag.lx = e.clientX; drag.ly = e.clientY;
});
function ptrUp(e) {
  if (!ptrs.has(e.pointerId)) return;
  ptrs.delete(e.pointerId);
  if (ptrs.size < 2) pinch = null;
  if (ptrs.size === 1) { const [p] = [...ptrs.values()]; if (drag) { drag.lx = p.x; drag.ly = p.y; drag.moved = true; drag.place = false; clearTimeout(drag.lp); } }
  if (ptrs.size === 0 && drag) {
    clearTimeout(drag.lp);
    const up = e.type === 'pointerup';
    if (drag.hold) radialRelease(e.clientX, e.clientY, true);
    else if (drag.place && !multi && up) tryBuild(e.clientX, e.clientY);
    else if (!drag.moved && !multi && up && performance.now() - drag.t0 < 700) onTap(e.clientX, e.clientY);
    if (performance.now() - drag.lt > 80) vel.x = vel.y = 0;
    drag = null;
  }
}
// двойной тап — зум ×2 (если первый тап не отправил войска — тогда второй просто добавит войска)
function onTap(x, y) {
  const now = performance.now();
  if (lastTap && now - lastTap.t < 320 && Math.hypot(x - lastTap.x, y - lastTap.y) < 34 && lastTap.what !== 'attack' && lastTap.what !== 'pick' && phase !== 'pick') {
    lastTap = null;
    closeRadial();
    const [wx, wy] = R.s2w(x, y);
    R.flyTo(wx, wy, R.cam.z * 2, 0.25);
    return;
  }
  const what = tap(x, y);
  lastTap = { t: now, x, y, what };
}
canvas.addEventListener('pointerup', ptrUp);
canvas.addEventListener('pointercancel', ptrUp);
canvas.addEventListener('contextmenu', (e) => { e.preventDefault(); if (phase === 'play') openRadialAt(R.tileAt(e.clientX, e.clientY), e.clientX, e.clientY); });
canvas.addEventListener('wheel', (e) => { e.preventDefault(); R.zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || phase !== 'play') return;
  const i = RATIOS.indexOf(ratio);
  const keyItem = ITEMS.find((it) => e.code === 'Digit' + it.k);
  if (e.code === 'KeyQ') setRatio(RATIOS[Math.max(0, i - 1)]);
  else if (e.code === 'KeyE') setRatio(RATIOS[Math.min(RATIOS.length - 1, i + 1)]);
  else if (e.code === 'KeyB') { sheetOpen ? closeSheet() : openSheet(); }
  else if (keyItem) selectBuild(keyItem.type);
  else if (e.code === 'Space') { e.preventDefault(); toggleAlt(); }
  else if (e.code === 'KeyX' || e.code === 'Escape') { cancelPlacing(); closeSheet(); closeCard(); closeRadial(); }
  else if (e.code === 'Equal' || e.code === 'NumpadAdd') R.zoomAt(R.w / 2, R.h / 2, 1.25);
  else if (e.code === 'Minus' || e.code === 'NumpadSubtract') R.zoomAt(R.w / 2, R.h / 2, 0.8);
});

// ---------------- главный цикл: тик 100 мс (пока открыто меню ☰ — мир замирает) ----------------
let last = performance.now(), acc = 0, pillT = 0;
function frame(now) {
  const dt = Math.min(0.25, (now - last) / 1000); last = now;
  const live = game && (phase === 'play' || phase === 'out' || phase === 'spectate') && !game.over && !ui.menuOpen();
  if (live) {
    acc += dt * (phase === 'spectate' ? fast : 1);
    let steps = 0;
    const maxSteps = phase === 'spectate' && fast > 1 ? 8 : 4;
    while (acc >= TICK && steps < maxSteps) { game.tick(); acc -= TICK; steps++; }
    if (steps >= maxSteps) acc = 0;
  }
  if (phase === 'pick' && !ui.menuOpen()) { runSpawnQueue(); if (now - pillT > 150) { pillT = now; updateSpawnPill(); } }
  if (!drag && (Math.abs(vel.x) > 5 || Math.abs(vel.y) > 5)) { R.pan(vel.x * dt, vel.y * dt); const k = Math.exp(-dt * 5); vel.x *= k; vel.y *= k; }
  R.draw(now / 1000, dt);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// болтовня в чате и советы Клода
setInterval(() => {
  if (phase !== 'play' && phase !== 'spectate') return;
  const r = Math.random();
  if (r < 0.35 && claude.alive) talk(claude, 'tip', 'дай игроку короткий совет по стратегии захвата территорий');
  else if (r < 0.8) { const b = randomBot(); if (b) talk(b, 'idle', `идёт стратегия про захват мира, у тебя ${pct(b.tiles)} суши`); }
}, 28000);

window.__bw = {
  get game() { return game; }, get world() { return world; }, get me() { return me; }, get phase() { return phase; }, get claude() { return claude; },
  R, tap, onTap, newMatch, setRatio, openCard, closeCard, sendAttack, sendBoatTo, openRadialAt, selectBuild, openSheet, toggleLB, toggleAlt, fmt, WIN_SHARE, PROT_TICKS,
  endNow: (win) => game.finish(win ? me : game.P.find((p) => p && p.kind === KIND.NATION && p.alive) || game.leader(), 'share'),
  killMe: () => { const by = game.P.find((p) => p && p.kind === KIND.NATION && p.alive); game.eliminate(me, by); },
};
newMatch();

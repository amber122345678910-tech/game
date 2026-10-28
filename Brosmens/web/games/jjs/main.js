// Jujutsu Brosmens — аренный файтинг FFA в стиле роблокс-игры Jujutsu Shenanigans.
import * as THREE from 'three';
import { initGameUI, pixelRatio, graphicsLevel, shakeEnabled } from '../../shared/ui.js';
import { createControls } from '../../shared/touch.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS, botSay, typingDelay } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { audio } from './audio.js';
import { inDomainOf } from './domain.js';
import { getProfile, addStat, addCoins } from '../../shared/profile.js';
import { G } from './ctx.js';
import { buildWorld } from './world.js';
import { FX } from './fx.js';
import { Fighter, hit, FDASH_CD, SDASH_CD } from './fighter.js';
import { CHARS, CHAR_IDS, resetSkills } from './skills.js';
import { Brain } from './bot.js';
import { createHUD } from './hud.js';
import { createTopBar } from './topbar.js';
import { EMOTES } from './emotes.js';
import { LOOKS, setModelFade } from './rig.js';
import { rand, clamp, pick, angleDamp, wrapAngle, ease } from './util.js';

const MATCH_TIME = 240, KILL_LIMIT = 15;
const NAME_COLORS = ['#ff6b6b', '#ffd93d', '#6bcb77', '#4d96ff', '#c77dff', '#ff9f45', '#5ee6eb', '#ff7eb6'];
const colorOf = (name) => NAME_COLORS[[...name].reduce((a, c) => a + c.charCodeAt(0), 0) % NAME_COLORS.length];

const profile = getProfile();
const ui = initGameUI({
  title: 'Jujutsu Brosmens',
  players: () => G.fighters.slice().sort((a, b) => b.kills - a.kills).map((f) => ({ name: f.name, skin: f.skin, score: `${f.kills} уб.` })),
  onReset: () => resetPlayer(),
  controlsHelp: `<b>Телефон:</b> левая часть экрана — джойстик, свайп справа — камера, щипок двумя пальцами справа — приблизить/отдалить. Кулак — M1 (4 удара; 4-й в прыжке — апперкот, в падении — удар вниз). Щит — блок (держать), бегун — рывок (вперёд/на месте — рывок с ударом, вбок/назад — уклон; в рэгдолле при полной левой подшкале — уклонение), стрелка — прыжок, звезда — особый навык, замок — Shift-lock (включён: боец смотрит туда же, куда камера; навыки с TARGET бьют того, кто ближе к центру экрана). Навыки — ячейки 1–4 внизу; когда шкала пробуждения полная — нажми на неё. Вверху: «Персонажи» — сменить бойца прямо в бою (пробуждение сбросится), $ — монеты (+$5 за убийство), 🕺 — колесо эмоций.<br>
  <b>ПК:</b> WASD — ход, мышь (зажать) — камера, колесо/I/O — зум, ЛКМ — M1, F — блок, Q — рывок, Space — прыжок, R — особый навык, 1–4 — навыки, G — пробуждение, Shift — Shift-lock, B — эмоции. Держи Space на 4-м ударе — апперкот.`,
});

// ---------- рендер ----------
let gfx = graphicsLevel();
const renderer = new THREE.WebGLRenderer({ antialias: gfx >= 5, powerPreference: 'high-performance' });
renderer.setPixelRatio(pixelRatio());
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xc6b9a3, 95, 330);
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.3, 1400);
// тёплый туманный свет как в JJS: небо бежевое, «земля» серая, солнце чуть тёплое
const hemi = new THREE.HemisphereLight(0xf3ead9, 0x77746e, 1.75);
scene.add(hemi);
const sunL = new THREE.DirectionalLight(0xffeccc, 2.2);
sunL.shadow.mapSize.set(1024, 1024);
const sc = sunL.shadow.camera; sc.left = -42; sc.right = 42; sc.top = 42; sc.bottom = -42; sc.near = 10; sc.far = 260;
sunL.shadow.bias = -0.0006; sunL.shadow.normalBias = 0.04;
scene.add(sunL, sunL.target);

G.scene = scene; G.camera = camera; G.renderer = renderer; G.ui = ui;
G.world = buildWorld(scene, { shadows: false });
G.fx = new FX(scene, camera);
G.hud = createHUD();
G.gibs = [];
G.hit = hit;

let fogFar0 = 330;
let domIn = null, domK = 0, domKind = 'void';
function applyFogFar() { fogFar0 = 250 + graphicsLevel() * 20; if (!domK) scene.fog.far = fogFar0; }
function applyGfx() {
  gfx = graphicsLevel();
  renderer.setPixelRatio(pixelRatio());
  renderer.setSize(innerWidth, innerHeight);
  sunL.castShadow = gfx >= 4;
  applyFogFar();
  G.fx.k = gfx <= 3 ? 0.5 : gfx <= 7 ? 0.8 : 1;
}
applyGfx();
ui.onSettings(applyGfx);
function onResize() {
  renderer.setSize(innerWidth, innerHeight);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  G.fx.setScale(innerHeight * renderer.getPixelRatio(), camera.fov);
}
addEventListener('resize', onResize);
onResize();

// ---------- управление ----------
// Кнопки в стиле JJS: чёрный круг, серое кольцо, плоский серый значок без текста.
const SVG = (inner) => `<svg viewBox="0 0 64 64" aria-hidden="true">${inner}</svg>`;
const ICON = {
  fist: SVG(`<g fill="currentColor"><rect x="13" y="15" width="10" height="17" rx="4.5"/><rect x="23.5" y="12" width="10" height="20" rx="4.5"/><rect x="34" y="13" width="10" height="19" rx="4.5"/><rect x="44.5" y="17" width="8.5" height="16" rx="4.2"/><path d="M12 29h41v9c0 10-7 16-17 16h-7c-9 0-17-6-17-15z"/></g><path d="M23.3 17v13M33.8 15v15M44.3 19v12" stroke="#0e0e0e" stroke-width="1.6"/><path d="M11 36c0-4 3-6 6-6h13c3 0 5 2 5 4.5S33 39 30 39h-8" fill="currentColor" stroke="#0e0e0e" stroke-width="1.8" stroke-linejoin="round"/>`),
  shield: SVG(`<path fill="currentColor" d="M32 7l21 6.5V30c0 13.5-9 21.5-21 27C20 51.5 11 43.5 11 30V13.5z"/><path fill="#0e0e0e" opacity=".35" d="M32 13l15 4.6V30c0 9.8-6.2 16-15 20.6z"/>`),
  dash: SVG(`<circle cx="40" cy="11" r="5.6" fill="currentColor"/><path d="M36 21L29.5 35M29.5 35l8.5 6-2.5 13M29.5 35L21 45.5h-8M35 22l9.5 5 5.5-6M35 22l-9.5 3-5 6.5" stroke="currentColor" stroke-width="5.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 23h11M1 31h9M5 39h7" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>`),
  jump: SVG(`<path fill="currentColor" d="M32 17l14 15.5h-8.6V46H26.6V32.5H18z"/>`),
  star: SVG(`<path fill="currentColor" d="M32 5c2 19 8 25 27 27-19 2-25 8-27 27-2-19-8-25-27-27C24 30 30 24 32 5z"/>`),
  lock: SVG(`<path d="M22 29v-8a10 10 0 0 1 20 0v8" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round"/><rect x="15" y="28" width="34" height="27" rx="4.5" fill="currentColor"/><rect x="29.5" y="35" width="5" height="12" rx="2.5" fill="#0e0e0e"/>`),
};
document.body.classList.add('jjs');
{
  const st = document.createElement('style');
  st.textContent = `
body.jjs .tc-btn{background:rgba(14,14,14,.9);border:3px solid #5A5A5A;color:#878787;text-shadow:none}
body.jjs .tc-btn.on{background:rgba(48,48,48,.95);transform:scale(.94)}
body.jjs .tc-btn span{padding:0;width:60%;height:60%;display:flex;align-items:center;justify-content:center;line-height:0}
body.jjs .tc-btn svg{width:100%;height:100%;display:block}
body.jjs .tc-btn .cd{background:conic-gradient(rgba(150,150,150,.55) var(--a,0deg),transparent 0)}
body.jjs .tc-btn.lockon{color:#4fa6ff;border-color:#3a7fd6}
body.jjs .tc-btn.blk{border-color:#8a8a8a;color:#b4b4b4}
body.jjs .tc-btn .k{color:#9a9a9a;font-size:8px;bottom:2px}
@media (pointer:coarse){body.jjs .tc-btn .k{display:none}}`;
  document.head.appendChild(st);
}
// Позиции — центры кнопок для ландшафта ≈915×412 (JJS/Roblox-раскладка), отсчёт от правого нижнего угла.
const ctl = createControls({
  buttons: [
    { id: 'm1', label: ICON.fist, x: -192, y: -115, size: 78 },
    { id: 'block', label: ICON.shield, x: -174, y: -206, size: 60, key: 'KeyF' },
    { id: 'dash', label: ICON.dash, x: -73, y: -165, size: 60, key: 'KeyQ' },
    { id: 'jump', label: ICON.jump, x: -60, y: -55, size: 70, key: 'Space' },
    { id: 'special', label: ICON.star, x: -293, y: -198, size: 56, key: 'KeyR' },
    { id: 'lock', label: ICON.lock, x: -73, y: -255, size: 46, key: 'ShiftLeft' },
  ],
  keyMap: { Digit1: 's0', Digit2: 's1', Digit3: 's2', Digit4: 's3', ShiftRight: 'lock' },
});
G.ctl = ctl;
let jumpQueued = false;
// Shift-lock в JJS включён по умолчанию («держите включённым всегда»); выбор игрока запоминается
let shiftLock = true;
try { shiftLock = localStorage.getItem('jjs.shiftlock') !== '0'; } catch {}
const P = () => (state === 'play' && G.player && !G.player.dead && !ui.menuOpen() ? G.player : null);
ctl.onPress('m1', () => { const p = P(); if (p) { p.m1(); p.lastAttackT = G.time; } });
ctl.onPress('dash', () => P()?.dash());
ctl.onPress('jump', () => { jumpQueued = true; });
ctl.onPress('special', () => { const p = P(); if (p) { p.special(); p.lastAttackT = G.time; } });
ctl.onPress('lock', () => {
  shiftLock = !shiftLock;
  try { localStorage.setItem('jjs.shiftlock', shiftLock ? '1' : '0'); } catch {}
  ui.toast(shiftLock ? 'Shift-lock: ВКЛ' : 'Shift-lock: ВЫКЛ', 900);
});
const skillPress = (i) => { const p = P(); if (p) { p.skill(i); p.lastAttackT = G.time; } };
const skillRelease = (i) => G.player?.release(i);
for (let i = 0; i < 4; i++) { ctl.onPress('s' + i, () => skillPress(i)); ctl.onRelease('s' + i, () => skillRelease(i)); }
G.hud.onSkill(skillPress, skillRelease);
// пробуждение: тап по шкале (телефон) или G (ПК)
G.hud.onAwakenTap(() => P()?.awaken());
addEventListener('keydown', (e) => { if (e.code === 'KeyG' && !e.repeat) P()?.awaken(); });
renderer.domElement.addEventListener('pointerdown', (e) => {
  if (e.pointerType === 'mouse' && e.button === 0) { const p = P(); if (p) { p.m1(); p.lastAttackT = G.time; } }
});
G.hud.setGL(renderer.domElement);
{ const k = ctl.el('lock').querySelector('.k'); if (k) k.textContent = 'Shift'; }

// ---------- чат ----------
const chat = createChat({ bots: () => G.fighters.filter((f) => f.bot).map((f) => { f.bot.dead = f.dead; return f.bot; }) });
G.chat = chat;

// ---------- верхняя панель JJS: Персонажи / $ / эмоции ----------
let coins = getProfile().coins || 0;
const topbar = createTopBar({
  ui,
  chars: CHAR_IDS.map((id) => ({ id, name: CHARS[id].name, ru: CHARS[id].ru, color: LOOKS[id].color })),
  emotes: EMOTES,
  onChar: (id) => switchChar(id),
  onEmote: (def) => { const p = P(); if (p && !p.emote(def)) ui.toast('Сейчас нельзя', 800); },
});
topbar.setCoins(coins);
topbar.setVisible(false);
addEventListener('keydown', (e) => {
  if (e.repeat || e.target.closest?.('input,textarea')) return;
  if (e.code === 'KeyB' && state === 'play') topbar.toggleWheel();
  else if (e.code === 'KeyI') camDist = clamp(camDist - 2, 6, 25);
  else if (e.code === 'KeyO') camDist = clamp(camDist + 2, 6, 25);
});
// Смена бойца посреди матча (как в JJS: прогресс пробуждения теряется); раз в 8 с
let switchT = 0;
function switchChar(id) {
  nextChar = id; saveChar(id);
  topbar.setChar(id);
  const p = G.player;
  if (state !== 'play' || !p) return;
  if (p.dead) { ui.toast(`Возродишься за: ${CHARS[id].name}`, 1400); return; }
  if (p.charId === id) return;
  if (G.time < switchT) { ui.toast(`Сменить бойца можно через ${Math.ceil(switchT - G.time)} с`, 1100); return; }
  if (p.rag || p.down > 0) { ui.toast('Сначала встань на ноги', 1000); return; }
  const k = p.hp / p.maxHp;
  p.interrupt(true); p.action = null; p.blocking = false; p.charge = null; p.counter = 0; p.vanish = 0;
  p.setChar(id);
  p.hp = Math.max(1, Math.round(p.maxHp * k));
  p.pose.set(p.idlePose);
  p.syncModel(0);
  G.hud.setChar(p);
  p.chestPos(_t);
  G.fx.ring(_t, p.look.color, 1, 9, 0.45, { a0: 0.9 });
  G.fx.particles(_t, { n: 22, normal: true, color: ['#0c0a0e', '#2a2430'], speed: 10, up: 3, size: 2, size1: 4.5, life: 0.7, alpha: 0.8 });
  G.sound('spawn', p.pos, 0.6);
  switchT = G.time + 8;
  ui.toast(`Боец: ${CHARS[id].name} • пробуждение сброшено`, 1600);
}

// ---------- зум камеры: щипок двумя пальцами на правой половине (свои слушатели, touch.js не трогаем), колесо мыши ----------
const pinch = new Map();
let pinchD0 = 1, pinchC0 = 13;
const isUI = (el) => !!(el && el.closest && el.closest('.tc-btn,.jh-slot,.jh-aw,.ui-top,.bc-wrap,.bc-btn,.rm,.ui-panel,.jt-ew,.jh-scr,.jh-death,button,input'));
addEventListener('pointerdown', (e) => {
  if (e.pointerType !== 'touch' || e.clientX < innerWidth * 0.42 || isUI(e.target)) return;
  pinch.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (pinch.size === 2) { const [a, b] = [...pinch.values()]; pinchD0 = Math.max(20, Math.hypot(a.x - b.x, a.y - b.y)); pinchC0 = camDist; }
});
addEventListener('pointermove', (e) => {
  const q = pinch.get(e.pointerId);
  if (!q) return;
  q.x = e.clientX; q.y = e.clientY;
  if (pinch.size >= 2) { const [a, b] = [...pinch.values()]; camDist = clamp(pinchC0 * pinchD0 / Math.max(20, Math.hypot(a.x - b.x, a.y - b.y)), 6, 25); }
});
const pinchUp = (e) => { pinch.delete(e.pointerId); };
addEventListener('pointerup', pinchUp);
addEventListener('pointercancel', pinchUp);
addEventListener('wheel', (e) => { if (state === 'play' && !ui.menuOpen()) camDist = clamp(camDist * (e.deltaY > 0 ? 1.1 : 0.9), 6, 25); }, { passive: true });
// ---------- чат ботов: JJS-реплики + пузыри над головами ----------
// Общий бюджет ≈ 1 сообщение в 4–8 с на весь сервер; «важные» события могут чуть опередить очередь.
let chatNext = 0, idleChat = rand(8, 14);
function canTalk(prio) {
  const now = performance.now() / 1000;
  if (now < chatNext && !(prio && now > chatNext - 3)) return false;
  chatNext = now + rand(4, 7.5);
  return true;
}
// реплика с «набором текста»: в чат и пузырём над головой (пузырь создаёт наблюдатель лога чата)
function speak(f, text, delay) {
  if (!text) return;
  setTimeout(() => { if (state === 'select' || !G.fighters.includes(f)) return; chat.say(f.name, text); }, delay ?? typingDelay(text));
}
const JL = {
  comboed: { nice: ['хватит м1 спамить', 'дай хоть встать', 'ну хватит комбить(', 'ай ай ай', 'блин опять комба'], toxic: ['хватит м1 спамить', 'блок абуз', 'дай хоть встать', 'м1 спамер', 'скилл ишью', 'только м1 и умеешь?'] },
  teamed: { nice: ['тимеры!!', '2 на 1 серьёзно', 'эй вы чего вдвоём', 'меня тимят помогите'], toxic: ['тимеры!!', '2 на 1 серьёзно', 'без тимы слабо?', 'тимеры как всегда', 'ну и тимеры'] },
  domainCaught: { nice: ['ДОМЕН ДИФ', 'ну всё мне конец', 'неееет домен', 'ой домен', 'всё я в домене'], toxic: ['ДОМЕН ДИФ', 'ну всё мне конец', 'домен абуз', 'опять домен', 'без домена слабо?'] },
  domainCast: { nice: ['РАСШИРЕНИЕ ТЕРРИТОРИИ', 'domain expansion!', 'добро пожаловать в мой домен'], toxic: ['РАСШИРЕНИЕ ТЕРРИТОРИИ', 'ДОМЕН ДИФ ахах', 'всё вы в моём домене', 'бегите нубы'] },
  lowhp: { nice: ['хп 10 помогите', 'я на лоу хп', 'отбегаю хилюсь', 'хил плз', 'дайте отрегениться'], toxic: ['хп 10 помогите', 'не трогайте я на лоу', 'отстаньте я хилюсь', 'вы где вообще'] },
  revenge: { nice: ['{t} я иду за тобой', '{t} реванш!', 'ну всё {t} держись'], toxic: ['{t} я иду за тобой', '{t} ты труп', 'щас отомщу {t}', '{t} готовься'] },
  taunt: { nice: ['гг', 'хороший бой', 'ахах', 'гг вп'], toxic: ['ez', 'сиди', 'изи', 'L', 'гг изи'] },
  bf: { nice: ['ЧЁРНАЯ ВСПЫШКА!!', 'кокусен!!', 'ВСПЫШКА ахах'], toxic: ['ЧЁРНАЯ ВСПЫШКА изи', 'КОКУСЕН', 'вспышка в лицо'] },
  awaken: { nice: ['ПРОБУЖДЕНИЕ!!', 'ну всё пробуждение', 'держитесь ахах', 'вот теперь серьёзно', 'ульта готова)', 'смотрите что умею'], toxic: ['ну всё вам конец', 'изи пробуждение', 'щас всех разнесу', 'бегите нубы', 'ДОМЕН НА ВСЕХ', 'вы уже проиграли'] },
  idle: { nice: ['кто 1 на 1 у кафе?', 'го на крышу', 'у кого домен есть?', 'какой перс лучше?', 'годжо имба', 'сукуна топ', 'кто в тиму', 'кто знает как кокусен делать', 'я сегодня 3 часа тут'], toxic: ['кто 1 на 1?', 'тут одни нубы', 'годжо мейнеры...', 'м1 спамеры везде', 'я топ 1 сервера', 'скучно некого бить'] },
};
const CLAUDE = { playerKill: ['красава!', 'красиво!', 'вот это комбо', 'топ, гг', 'ахах красавчик'], playerDeath: ['держись, иду', 'ничего, отомстим', 'я рядом, отомщу', 'не сдавайся!'], playerLow: ['держись, иду', 'отходи, я прикрою', 'хилься, я тут'] };
function typo(s) { if (s.length < 6 || Math.random() > 0.2) return s; const i = 1 + Math.floor(Math.random() * (s.length - 3)); return s.slice(0, i) + s[i + 1] + s[i] + s.slice(i + 2); }
function lineFor(bot, pool, t) {
  const L = JL[pool];
  let s = pick(Math.random() < (bot.toxic ?? 0.4) ? L.toxic : L.nice).replace('{t}', t || 'бро');
  if (bot.typo) s = typo(s);
  if (Math.random() < 0.1) s = s.toUpperCase();
  return s;
}
// JJS-реплика бота из пула: учитывает болтливость (chatty), токсичность (toxic) и общий бюджет
G.botLine = (f, pool, { target = '', prio = false, chance = 1, delay } = {}) => {
  if (!f || !f.bot || state !== 'play') return false;
  if (Math.random() > chance * (0.5 + 0.5 * (f.bot.chatty ?? 0.6))) return false;
  if (!canTalk(prio)) return false;
  const text = f.isClaude && CLAUDE[pool] ? pick(CLAUDE[pool]) : lineFor(f.bot, pool, target);
  speak(f, text, delay);
  return true;
};
// Событийная реплика из общих заготовок/ИИ (start/kill/death/hit/help/thanks/win/lose/idle)
G.botEvent = (f, event, opts = {}, prio = false) => {
  if (!f || !f.bot) return;
  if (!canTalk(prio)) return;
  botSay(f.bot, event, { ...opts, chatLog: chat.log }).then((text) => speak(f, text)).catch(() => {});
};
// пузыри: любая новая строка лога чата от бойца (боты, ответы ботов игроку, сам игрок)
const seenLog = new WeakSet();
function watchChat() {
  const log = chat.log;
  for (let i = log.length - 1; i >= 0; i--) {
    const m = log[i];
    if (seenLog.has(m)) break;
    seenLog.add(m);
    if (state === 'select') continue;
    const f = G.fighters.find((o) => o.name === m.name);
    if (f && !f.dead) G.hud.bubble(f, m.text);
  }
}
// удары: наказание за заблокированный M1 и поводы для реплик (комбят, тимят, больно)
G.onHit = (att, vic, res, o, dmg) => {
  if (res === 'blocked') { if (o.m1 && vic.brain) vic.brain.onBlocked(att); return; }
  if (!vic.bot || !att) return;
  const now = G.time;
  vic._cmb = vic._cmbBy === att && now - vic._cmbT < 1.3 ? vic._cmb + 1 : 1;
  vic._cmbBy = att; vic._cmbT = now;
  if (vic._cmb === 5 && !vic.dead) G.botLine(vic, 'comboed', { target: att.name, chance: 0.6 });
  const atk = (vic._atk ||= new Map());
  atk.set(att, now);
  let n = 0; for (const [a, t] of atk) { if (now - t > 2) atk.delete(a); else n++; }
  if (n >= 2 && now - (vic._teamSaid ?? -99) > 12 && !vic.dead) { vic._teamSaid = now; G.botLine(vic, 'teamed', { chance: 0.55 }); }
  else if (dmg >= 9 && !vic.dead && Math.random() < 0.2) G.botEvent(vic, 'hit', { target: att.name, eventText: `тебя сильно ударил ${att.name}` });
  if (o.numColor === '#ff3050' && att.bot && Math.random() < 0.35) G.botLine(att, 'bf', {});
};
let claudeLowT = 0;
// домен: кастер кричит, пойманные паникуют
G.onDomain = (D) => {
  if (D.owner.bot && Math.random() < 0.6) { G.botLine(D.owner, 'domainCast', { prio: true, delay: 300 }); return; }
  const v = [...D.caught].filter((o) => o !== D.owner && o.bot && !o.isClaude);
  if (v.length) G.botLine(pick(v), 'domainCaught', { prio: true, chance: 0.9, delay: rand(900, 1800) });
};

// ---------- общие хуки ----------
let trauma = 0, fovKick = 0;
G.shake = (amount, pos) => {
  const p = G.player;
  let k = 1;
  if (pos && p) k = clamp(1 - Math.hypot(pos.x - p.pos.x, pos.z - p.pos.z) / 60, 0, 1);
  trauma = Math.min(1, trauma + amount * k);
  if (amount * k > 0.45) fovKick = Math.max(fovKick, amount * k * 6);
};
const sndLast = {};
let sndWindow = 0, sndCount = 0;
G.sound = (name, pos, vol = 1) => {
  const p = G.player;
  let k = 1;
  if (pos && p) k = clamp(1 - camera.position.distanceTo(pos) / 85, 0, 1);
  const v = vol * k;
  if (v < 0.04) return;
  const now = performance.now();
  if (now - (sndLast[name] || 0) < 45) return;
  if (now - sndWindow > 100) { sndWindow = now; sndCount = 0; }
  if (++sndCount > 9) return;
  sndLast[name] = now;
  // свои синтезированные звуки JJS (audio.js), остальное — общий sfx
  if (!audio.play(name, v)) sfx.play(name, { vol: v });
};
G.flashNear = (pos, color, alpha, range) => {
  const p = G.player; if (!p) return;
  const d = Math.hypot(pos.x - p.pos.x, pos.z - p.pos.z);
  if (d < range) G.hud.flash(color, alpha * (1 - d / range * 0.7), 2.5);
};
G.callout = (f, text, color, selfOnly = false, dur = 2) => {
  const p = G.player; if (!p) return;
  if (f === p || (!selfOnly && f.dist(p) < 55)) G.hud.callout(text, f === p ? '' : f.name, color, dur);
};
G.onAwaken = (f) => {
  const aw = f.ch.awaken;
  f.chestPos(_t);
  G.fx.ring(_t, aw.color, 1, 12, 0.5, { a0: 1 });
  G.sound('awaken', f.pos, 0.9);
  // манга-реплики рядом с персонажем
  aw.lines.forEach(([at, text], i) => {
    let t = 0;
    G.addTask((dt) => { t += dt; if (f.dead || G.matchOver) return false; if (t < at) return true; G.hud.manga(f, text, i); return false; });
  });
  if (f.isPlayer) { G.cine = { f, t: 0, dur: aw.cine || 3.2 }; G.hud.flash('#000000', 0.25, 2); }
  else if (f.bot && Math.random() < 0.6) G.botLine(f, 'awaken', { prio: true, delay: 400 + rand(0, 500) });
};
G.kill = (vic, att) => {
  if (vic.dead) return;
  vic.hp = 0;
  let killer = att && att !== vic ? att : null;
  if (!killer && vic.lastHitBy && G.time - vic.lastHitT < 6 && !vic.lastHitBy.dead) killer = vic.lastHitBy;
  // кто помогал «спасённому»: бот, которого бил погибший, благодарит убийцу
  const saved = G.fighters.find((o) => o.bot && o !== killer && o !== vic && !o.dead && o.lastHitBy === vic && G.time - o.lastHitT < 3);
  vic.die(killer);
  vic.lastKiller = killer;
  if (killer) {
    killer.kills++;
    killer.evasive = 100;
  }
  G.hud.killfeed(killer ? killer.name : '', vic.name, killer ? killer.color : '#fff', vic.color);
  if (killer && killer.isPlayer) {
    vic.headPos(_t); G.hud.pop(_t, 'K.O.!', '#ffd23f', 2);
    G.sound('coin', killer.pos, 0.8);
    // как в JJS: +$5 за каждое убийство
    addCoins(5); coins += 5; matchCoins += 5;
    topbar.setCoins(coins); topbar.coinPop('+$5');
  }
  // боты в 25 % случаев «флексят» эмоцией над поверженным или пишут дразнилку через 1–3 с (эмоцию отменяет любой удар)
  if (killer && killer.bot && Math.random() < 0.25) {
    let et = rand(1, 3);
    const k = killer, emote = Math.random() < 0.65;
    G.addTask((dt) => {
      et -= dt;
      if (et > 0) return !G.matchOver && !k.dead;
      if (k.dead || G.matchOver) return false;
      if (emote && k.canAct()) k.emote({ ...pick(EMOTES), dur: rand(2, 3.5) });
      else G.botLine(k, 'taunt', { target: vic.name, delay: 200 });
      return false;
    });
  }
  if (vic.isPlayer) {
    G.hud.showDeath(killer ? killer.name : '', nextChar, profile.skin.skin, (id) => { nextChar = id; saveChar(id); topbar.setChar(id); });
    G.sound('lose', vic.pos, 0.4);
  }
  // чат: Клод реагирует на убийства и смерти игрока, остальные — на свои
  const claude = G.fighters.find((o) => o.isClaude && !o.dead);
  if (killer && killer.isPlayer && claude && Math.random() < 0.5) G.botLine(claude, 'playerKill', { prio: true, chance: 1.2 });
  else if (vic.isPlayer && claude && Math.random() < 0.65) G.botLine(claude, 'playerDeath', { prio: true, chance: 1.2 });
  else if (killer && killer.bot && Math.random() < 0.55) G.botEvent(killer, 'kill', { target: vic.name, eventText: `ты победил игрока ${vic.name} в файтинге` }, true);
  else if (vic.bot && Math.random() < 0.5) G.botEvent(vic, 'death', { target: killer ? killer.name : '', eventText: killer ? `тебя только что победил ${killer.name}` : 'ты упал и проиграл' }, true);
  else if (saved && killer && Math.random() < 0.5) G.botEvent(saved, 'thanks', { target: killer.name, eventText: `${killer.name} победил того, кто тебя бил` });
  if (state === 'play' && killer && killer.kills >= KILL_LIMIT) endMatch();
};
const _t = new THREE.Vector3(), _u = new THREE.Vector3(), _w = new THREE.Vector3();

// ---------- матч ----------
let state = 'select';
let matchTime = MATCH_TIME, matchCoins = 0;
let nextChar = loadChar();
function loadChar() { try { const c = localStorage.getItem('jjs.char'); return CHARS[c] ? c : 'gojo'; } catch { return 'gojo'; } }
function saveChar(c) { try { localStorage.setItem('jjs.char', c); } catch {} }

function clearMatch() {
  for (const f of G.fighters) G.scene.remove(f.model.root);
  G.fighters.length = 0;
  for (const gb of G.gibs) G.scene.remove(gb.m);
  G.gibs.length = 0;
  // задачи навыков сами завершаются; на всякий случай прогоняем их «до конца»
  G.matchOver = true;
  for (let i = 0; i < 40 && G.tasks.length; i++) { const l = G.tasks; G.tasks = []; for (const fn of l) if (fn(0.25)) G.tasks.push(fn); }
  G.tasks.length = 0;
  resetSkills();
  G.fx.clear();
  G.debugCam = null;
  G.cine = null;
  audio.music(null); domIn = null;
}

function bestSpawn(f) {
  let best = null, bs = -1;
  for (const [x, z] of G.world.spawns) {
    let md = 999;
    for (const o of G.fighters) if (o !== f && !o.dead) md = Math.min(md, Math.hypot(o.pos.x - x, o.pos.z - z));
    const s = md + rand(0, 12);
    if (s > bs) { bs = s; best = [x, z]; }
  }
  return best;
}

function startMatch(charId) {
  document.querySelectorAll('.jh-scr').forEach((e) => e.remove());
  clearMatch();
  nextChar = charId; saveChar(charId);
  G.matchOver = false;
  G.time = 0;
  const player = new Fighter({ name: profile.name, isPlayer: true, skin: profile.skin, charId, color: '#ffffff' });
  G.player = player;
  G.fighters.push(player);
  const claudeBot = { ...FRIENDS[0], skill: 0.8, chatty: 0.9, typo: false };
  const claude = new Fighter({ name: claudeBot.name, isClaude: true, bot: claudeBot, skin: claudeBot.skin, charId: pick(CHAR_IDS), color: '#ffb37a' });
  claude.brain = new Brain(claude);
  G.fighters.push(claude);
  const n = 5 + (Math.random() < 0.5 ? 1 : 0);
  for (const b of makeBots(n, { exclude: [profile.name, claudeBot.name] })) {
    const f = new Fighter({ name: b.name, bot: b, skin: b.skin, charId: pick(CHAR_IDS), color: colorOf(b.name) });
    f.brain = new Brain(f);
    G.fighters.push(f);
  }
  for (const f of G.fighters) { const [x, z] = bestSpawn(f); f.spawn(x, z); }
  resetCam(player);
  matchTime = MATCH_TIME; matchCoins = 0; switchT = 0;
  topbar.setChar(charId); topbar.setVisible(true);
  state = 'play';
  G.hud.showHUD(true);
  G.hud.setChar(player);
  G.hud.hideDeath();
  ui.banner('Jujutsu Brosmens', `FFA • ${G.fighters.length} игроков • до ${KILL_LIMIT} убийств`, 2600, '#d9a0ff');
  chat.system(`Матч начался! Бойцов: ${G.fighters.length}. Клод на твоей стороне.`);
  setTimeout(() => { const b = pick(G.fighters.filter((f) => f.bot)); G.botEvent(b, 'start', { eventText: 'начался новый матч в аренном файтинге' }, true); }, 1500);
  setTimeout(() => G.botEvent(claude, 'start', { target: player.name, eventText: `начался матч, ты в одной команде со своим другом ${player.name}` }, true), 7000);
}

function respawn(f) {
  const [x, z] = bestSpawn(f);
  f.spawn(x, z);
  if (f.brain) {
    f.brain.onRespawn(f.lastKiller);
    // месть после возрождения
    if (f.brain.revenge) G.botLine(f, 'revenge', { target: f.brain.revenge.name, chance: 0.7, delay: rand(600, 1600) });
  }
}

function resetPlayer() {
  const p = G.player;
  if (state !== 'play' || !p) return;
  if (p.dead) { p.respawnT = Math.min(p.respawnT, 0.5); return; }
  G.kill(p, null);
}

function endMatch() {
  if (state !== 'play') return;
  state = 'end';
  G.matchOver = true;
  audio.music(null); domIn = null;
  topbar.closeAll();
  const rows = G.fighters.slice().sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
  const p = G.player;
  const place = rows.indexOf(p) + 1;
  // +$5 за убийство уже начислены по ходу матча; в конце — бонус за участие и место
  const bonus = 5 + (place === 1 ? 30 : place <= 3 ? 12 : 0);
  addCoins(bonus); coins += bonus; topbar.setCoins(coins);
  const earned = matchCoins + bonus;
  addStat('jjs', 'matches', 1);
  addStat('jjs', 'kills', p.kills);
  addStat('jjs', 'deaths', p.deaths);
  if (place === 1) addStat('jjs', 'wins', 1);
  G.hud.hideDeath();
  ui.banner(place === 1 ? 'ПОБЕДА!' : 'Матч окончен', `${rows[0].name} — ${rows[0].kills} убийств`, 2600, place === 1 ? '#ffd23f' : '#fff');
  sfx.play(place === 1 ? 'win' : 'lose');
  const winner = rows[0];
  if (winner.bot) setTimeout(() => chat.botSay(winner.bot, 'win', { eventText: 'ты выиграл матч в файтинге, больше всех убийств' }), 900);
  const loser = rows.slice(1).find((f) => f.bot);
  if (loser) setTimeout(() => chat.botSay(loser.bot, 'lose', { target: winner.name, eventText: `матч закончился, победил ${winner.name}` }), 2600);
  setTimeout(() => {
    topbar.setVisible(false);
    G.hud.showResults(rows, p, earned, () => showSelect(), () => ui.goHome());
  }, 2800);
}

function showSelect() {
  state = 'select';
  topbar.setVisible(false);
  G.hud.showHUD(false);
  G.hud.hideDeath();
  G.hud.showSelect(nextChar, profile.skin.skin, (id) => startMatch(id));
}

// ---------- игрок и камера ----------
let camYaw = 0, camPitch = -0.2, camDist = 13, camCur = 13;
const camPos = new THREE.Vector3(30, 20, 30), camLook = new THREE.Vector3();
G.camRay = null; // луч из центра экрана: прицел навыков TARGET (не точка касания пальца)
// Направление камеры, при котором «штанга» (camDist) свободна от стволов, домов и т.п. — при появлении/возрождении
function clearYaw(p, prefer) {
  const R = shiftLock ? 1.75 : 1.25, pc = Math.cos(-0.2), ps = Math.sin(-0.2);
  let best = prefer, bs = -1e9;
  for (let i = 0; i < 24; i++) {
    const yaw = prefer + (i / 24) * Math.PI * 2;
    const dx = Math.sin(yaw) * pc, dz = Math.cos(yaw) * pc;
    _u.set(p.pos.x - Math.cos(yaw) * R, p.pos.y + 4.1, p.pos.z + Math.sin(yaw) * R);
    _t.set(-dx, -ps, -dz);
    const d = Math.min(G.world.rayDist(_u, _t, camDist + 1), camDist + 1);
    const sc = d - (1 - Math.cos(wrapAngle(yaw - prefer))) * 1.2;
    if (sc > bs) { bs = sc; best = yaw; }
  }
  return wrapAngle(best);
}
// Камера при появлении: свободный обзор, FOV 70, без тряски (как в JJS)
function resetCam(p) {
  camYaw = clearYaw(p, p.yaw); camPitch = -0.2;
  p.yaw = camYaw;
  camLook.set(p.pos.x, p.pos.y + 3.6, p.pos.z);
  camCur = camDist;
  fovKick = 0; trauma = 0;
  if (camera.fov !== 70) { camera.fov = 70; camera.updateProjectionMatrix(); }
}
function playerInput(dt) {
  const p = G.player;
  const look = ctl.consumeLook();
  if (pinch.size >= 2) look.dx = look.dy = 0; // щипок — только зум
  if (state === 'play') {
    camYaw -= look.dx * 0.0058;
    camPitch = clamp(camPitch - look.dy * 0.0045, -1.05, 0.6);
  }
  if (!p) return;
  const inp = p.input;
  const fx = Math.sin(camYaw), fz = Math.cos(camYaw);
  const rx = -Math.cos(camYaw), rz = Math.sin(camYaw);
  const m = ctl.move;
  let mx = fx * m.y + rx * m.x, mz = fz * m.y + rz * m.x;
  const l = Math.hypot(mx, mz);
  if (l > 1) { mx /= l; mz /= l; }
  inp.mx = state === 'play' ? mx : 0; inp.mz = state === 'play' ? mz : 0;
  inp.jump = jumpQueued && state === 'play'; jumpQueued = false;
  inp.jumpHeld = ctl.down('jump');
  inp.block = ctl.down('block') && state === 'play';
  p.aim.set(fx, 0, fz);
  p.lockYaw = shiftLock && state === 'play' ? camYaw : null;
}

function updateCamera(dt) {
  const p = G.player;
  if (G.debugCam) { camera.position.copy(G.debugCam.pos); camera.lookAt(G.debugCam.look); return; }
  if (state === 'select' || !p) {
    const t = performance.now() / 1000;
    camPos.set(Math.cos(t * 0.08) * 24, 26, Math.sin(t * 0.08) * 24);
    camera.position.copy(camPos);
    camera.lookAt(0, 4, 0);
    return;
  }
  let focus = p;
  if (p.dead && p.lastHitBy && !p.lastHitBy.dead && G.time - p.lastHitT < 8) focus = p.lastHitBy;
  _t.set(focus.pos.x, focus.pos.y + 3.6, focus.pos.z);
  if (focus === p && p.rag) _t.y = p.pos.y + 2.6;
  camLook.lerp(_t, 1 - Math.exp(-(focus === p ? 22 : 4) * dt));
  if (camLook.distanceTo(_t) > 30) camLook.copy(_t);
  // мягкий доворот камеры к цели во время боя
  const tg = p.lastTarget;
  if (!p.dead && tg && !tg.dead && G.time - (p.lastAttackT || -9) < 1.4 && p.dist(tg) < 24 && Math.hypot(ctl.move.x, ctl.move.y) < 0.2) {
    const want = Math.atan2(tg.pos.x - p.pos.x, tg.pos.z - p.pos.z);
    if (Math.abs(wrapAngle(want - camYaw)) < 1.4) camYaw = angleDamp(camYaw, want, 2.2, dt);
  }
  const cp = Math.cos(camPitch);
  const dx = Math.sin(camYaw) * cp, dy = Math.sin(camPitch), dz = Math.cos(camYaw) * cp;
  const rx = -Math.cos(camYaw), rz = Math.sin(camYaw);
  const sh = shiftLock ? 1.75 : 1.25;
  const base = _u.set(camLook.x + rx * sh, camLook.y + 0.5, camLook.z + rz * sh);
  _t.set(-dx, -dy, -dz);
  let dist = G.world.rayDist(base, _t, camDist);
  dist = Math.max(2.5, dist - 0.6);
  if (dist < camCur) camCur = dist; else camCur += (dist - camCur) * (1 - Math.exp(-5 * dt));
  dist = camCur;
  camera.position.set(base.x - dx * dist, base.y - dy * dist, base.z - dz * dist);
  if (camera.position.y < 0.8) camera.position.y = 0.8;
  _w.set(base.x + dx * 10, base.y + dy * 10, base.z + dz * 10);
  const cr = (G.camRay ||= { origin: new THREE.Vector3(), dir: new THREE.Vector3() });
  cr.origin.copy(camera.position); cr.dir.subVectors(_w, camera.position).normalize();
  // кинематика пробуждения: камера облетает к лицу (3/4 спереди) и возвращается
  const cn = G.cine;
  if (cn) {
    cn.t += dt;
    if (cn.t >= cn.dur || cn.f.dead) G.cine = null;
    else {
      const f = cn.f, s = f.scale;
      const kin = Math.min(1, cn.t / 0.45), kout = Math.min(1, (cn.dur - cn.t) / 0.45);
      const k = ease.smooth(Math.min(kin, kout));
      const fx = Math.sin(f.yaw), fz = Math.cos(f.yaw);
      const zoom = 1 - Math.min(1, cn.t / cn.dur) * 0.18;
      f.headPos(_u); _u.y -= 0.55 * s;
      let cx = _u.x + (fx * 5.4 - fz * 2.6) * s * zoom, cy = _u.y - 0.25 * s, cz = _u.z + (fz * 5.4 + fx * 2.6) * s * zoom;
      // не залезать в стволы/стены: укорачиваем «штангу» до препятствия
      _t.set(cx - _u.x, cy - _u.y, cz - _u.z);
      const cl = _t.length() || 1;
      _t.multiplyScalar(1 / cl);
      const free = Math.max(1.4, G.world.rayDist(_u, _t, cl) - 0.5);
      if (free < cl) { const kk = free / cl; cx = _u.x + (cx - _u.x) * kk; cy = _u.y + (cy - _u.y) * kk; cz = _u.z + (cz - _u.z) * kk; }
      camera.position.set(camera.position.x + (cx - camera.position.x) * k, camera.position.y + (cy - camera.position.y) * k, camera.position.z + (cz - camera.position.z) * k);
      _w.lerp(_u, k);
    }
  }
  camera.lookAt(_w);
  // тряска
  const s = shakeEnabled() ? trauma * trauma : 0;
  if (s > 0.001) {
    camera.position.x += rand(-1, 1) * s * 1.1; camera.position.y += rand(-1, 1) * s * 1.1; camera.position.z += rand(-1, 1) * s * 1.1;
    camera.rotation.z += rand(-1, 1) * s * 0.05;
  }
  trauma = Math.max(0, trauma - dt * 1.9);
  fovKick = Math.max(0, fovKick - dt * 18);
  const fov = 70 + fovKick;
  if (Math.abs(camera.fov - fov) > 0.05) { camera.fov = fov; camera.updateProjectionMatrix(); }
}

// ---------- кнопки и панель: перезарядки, состояния ----------
const btnC = {};
const setBtn = (id, key, v, fn) => { const c = (btnC[id] ||= {}); if (c[key] !== v) { c[key] = v; fn(v); } };
function updateButtons() {
  const p = G.player;
  if (!p) return;
  G.hud.setSkills([0, 1, 2, 3].map((i) => p.skillDef(i)));
  G.hud.setCooldowns(p.cd, p.cdMax);
  // рывок: показываем перезарядку того рывка, который выйдет сейчас (вперёд — 6 с, вбок/назад — 2 с)
  const front = p.dashKind() === 'front';
  const dcd = front ? Math.max(0, p.fdashCd) / FDASH_CD : Math.max(0, p.sdashCd) / SDASH_CD;
  setBtn('dash', 'cd', Math.round(dcd * 90), (v) => ctl.setCooldown('dash', v / 90));
  const sp = p.specialDef();
  setBtn('special', 'cd', sp && p.specCd > 0 ? Math.round((p.specCd / p.specCdMax) * 90) : 0, (v) => ctl.setCooldown('special', v / 90));
  setBtn('special', 'has', !!sp, (v) => { ctl.el('special').style.opacity = v ? '' : '0.35'; });
  // прыжок не гаснет от оглушения и M1 — тускнеет только когда прыгнуть нельзя
  setBtn('jump', 'ok', p.dead || p.canJump() || p.stun > 0 || (p.action && p.onGround), (v) => { ctl.el('jump').style.opacity = v ? '' : '0.4'; });
  setBtn('block', 'on', p.blocking, (v) => ctl.el('block').classList.toggle('blk', v));
  setBtn('lock', 'on', shiftLock, (v) => ctl.el('lock').classList.toggle('lockon', v));
  // ячейки скрыты во время кинематики пробуждения, в меню и на экране смерти; в меню скрыты и все кнопки
  const menu = ui.menuOpen() || topbar.isOpen();
  G.hud.setBoxesHidden(menu || p.dead || (G.cine && G.cine.f === p));
  setBtn('all', 'vis', !menu, (v) => ctl.setVisible(v));
}

// ---------- кадр ----------
let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last) / 1000; last = now;
  if (dt > 0.05) dt = 0.05;
  if (dt <= 0) return;
  const steps = G.speed || 1;
  for (let i = 0; i < steps; i++) simulate(dt);
  render(dt);
}
function simulate(dt) {
  G.time += dt;
  playerInput(dt);
  if (state === 'play' || state === 'end') {
    if (state === 'play') {
      matchTime -= dt;
      G.hud.setTimer(matchTime);
      if (matchTime <= 0) endMatch();
    }
    for (const f of G.fighters) if (f.brain) f.brain.update(dt);
    for (const f of G.fighters) f.update(dt);
    separate();
    const list = G.tasks; G.tasks = [];
    for (const fn of list) if (fn(dt)) G.tasks.push(fn);
    // возрождение
    for (const f of G.fighters) {
      if (!f.dead || state !== 'play') continue;
      f.respawnT -= dt;
      if (f.isPlayer) G.hud.setDeathTimer(f.respawnT);
      if (f.respawnT <= 0) {
        if (f.isPlayer) { if (nextChar !== f.charId) f.setChar(nextChar); G.hud.hideDeath(); G.hud.setChar(f); }
        else if (Math.random() < 0.3) f.setChar(pick(CHAR_IDS));
        respawn(f);
        if (f.isPlayer) resetCam(f);
      }
    }
    // болтовня
    idleChat -= dt;
    if (idleChat <= 0) {
      idleChat = rand(7, 13);
      const b = pick(G.fighters.filter((f) => f.bot && !f.dead));
      if (b) { if (Math.random() < 0.5) G.botLine(b, 'idle', { chance: 1.3 }); else G.botEvent(b, 'idle', { eventText: 'идёт матч в аренном файтинге Jujutsu, просто болтаешь в чате' }); }
    }
    const p = G.player;
    // Клод подбадривает, когда у игрока мало HP
    if (p && !p.dead && p.hp < p.maxHp * 0.3 && G.time > claudeLowT) {
      claudeLowT = G.time + 20;
      const c = G.fighters.find((o) => o.isClaude && !o.dead && o.dist(p) < 45);
      if (c) G.botLine(c, 'playerLow', { prio: true, chance: 1.2 });
    }
    // внутри домена: оттенок экрана, оверлей и музыка
    const pd = p && !p.dead ? inDomainOf(p) : null;
    domIn = pd && pd.t > 1.25 && !pd.closing ? pd.kind : null;
    if (domIn === 'shrine') G.hud.tint('radial-gradient(ellipse at center, rgba(90,0,0,.06), rgba(140,0,8,.4))');
    else if (domIn === 'void') G.hud.tint('radial-gradient(ellipse at center, rgba(0,0,0,0), rgba(10,16,70,.42))');
    else G.hud.tint(null);
    G.hud.setDomainFx(pd ? pd.kind : null, pd ? pd.t : 0);
    audio.music(domIn);
    updateButtons();
  }
  // куски тел
  for (let i = G.gibs.length - 1; i >= 0; i--) {
    const gb = G.gibs[i];
    gb.t -= dt;
    gb.v.y -= 70 * dt;
    gb.m.position.addScaledVector(gb.v, dt);
    if (gb.m.position.y < 0.5) { gb.m.position.y = 0.5; gb.v.y *= -0.3; gb.v.x *= 0.7; gb.v.z *= 0.7; gb.w.multiplyScalar(0.7); }
    gb.m.rotation.x += gb.w.x * dt; gb.m.rotation.y += gb.w.y * dt; gb.m.rotation.z += gb.w.z * dt;
    if (gb.t < 0.5) gb.m.scale.setScalar(Math.max(0.01, gb.t / 0.5));
    if (gb.t <= 0) { G.scene.remove(gb.m); G.gibs.splice(i, 1); }
  }
  G.world.update(dt);
  G.fx.update(dt, camera);
}
// Бойцы ближе ~4 стадов к камере плавно растворяются (как в роблоксе), чтобы не закрывать обзор
function fadeNearCamera() {
  const cp = camera.position;
  for (const f of G.fighters) {
    if (f.dead) continue;
    const y0 = f.pos.y, y1 = f.pos.y + 6 * f.scale;
    const cy = cp.y < y0 ? y0 : cp.y > y1 ? y1 : cp.y;
    const d = Math.hypot(cp.x - f.pos.x, cp.y - cy, cp.z - f.pos.z) - 1.2;
    setModelFade(f.model, d < 4 ? clamp((d - 0.6) / 3.4, 0, 1) : 1);
  }
}
// атмосфера внутри домена: туман и свет плавно уходят в тёмно-синий (Пустота) или тёмно-красный (Гробница)
const FOG0 = new THREE.Color(0xc6b9a3), HEMI0 = new THREE.Color(0xf3ead9);
const DFOG = { void: new THREE.Color(0x070818), shrine: new THREE.Color(0x240405) }, DHEMI = { void: new THREE.Color(0x9aa8ff), shrine: new THREE.Color(0xffb4a8) };
function domainAtmos(dt) {
  if (domIn) domKind = domIn;
  domK += ((domIn ? 1 : 0) - domK) * (1 - Math.exp(-4 * dt));
  if (domK < 0.002 && !domIn) { if (domK !== 0) { domK = 0; scene.fog.color.copy(FOG0); hemi.color.copy(HEMI0); scene.fog.near = 95; applyFogFar(); } return; }
  scene.fog.color.copy(FOG0).lerp(DFOG[domKind], domK);
  hemi.color.copy(HEMI0).lerp(DHEMI[domKind], domK);
  scene.fog.near = 95 + (22 - 95) * domK;
  scene.fog.far = fogFar0 + (85 - fogFar0) * domK;
}
function render(dt) {
  updateCamera(dt);
  if (state !== 'select') fadeNearCamera();
  watchChat();
  domainAtmos(dt);
  G.hud.update(dt, camera, state === 'select' ? [] : G.fighters, state === 'select' ? null : G.player);
  // солнце/тень следуют за игроком
  const c = G.player && state !== 'select' ? G.player.pos : camLook;
  const cy = c.y > 100 ? c.y : 0; // в интерьере домена (высоко над городом) свет и тень едут вместе с игроком
  sunL.target.position.set(c.x, cy, c.z);
  sunL.position.set(c.x + G.world.sunDir.x * 120, cy + G.world.sunDir.y * 120, c.z + G.world.sunDir.z * 120);
  renderer.render(scene, camera);
  G.hud.afterRender(renderer.domElement);
}

function separate() {
  const F = G.fighters;
  for (let i = 0; i < F.length; i++) {
    const a = F[i]; if (a.dead) continue;
    for (let j = i + 1; j < F.length; j++) {
      const b = F[j]; if (b.dead) continue;
      const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z, d2 = dx * dx + dz * dz;
      if (d2 > 4.6 || Math.abs(a.pos.y - b.pos.y) > 4) continue;
      const d = Math.sqrt(d2) || 0.01, push = (2.15 - d) * 0.5;
      const nx = d > 0.01 ? dx / d : 1, nz = d > 0.01 ? dz / d : 0;
      a.pos.x -= nx * push; a.pos.z -= nz * push; b.pos.x += nx * push; b.pos.z += nz * push;
    }
  }
}

// ---------- старт ----------
ui.loading(false);
G.hud.showHUD(false);
showSelect();
requestAnimationFrame((t) => { last = t; frame(t); });

// для автотестов (не влияет на игру)
window.__jjs = { G, renderer, startMatch, endMatch, switchChar, topbar, get state() { return state; }, get cam() { return { yaw: camYaw, pitch: camPitch, dist: camDist, cur: camCur, shiftLock, fov: camera.fov }; }, setCam(y, p) { camYaw = y; if (p != null) camPitch = p; } };

// Jujutsu Brosmens — аренный файтинг FFA в стиле роблокс-игры Jujutsu Shenanigans.
import * as THREE from 'three';
import { initGameUI, pixelRatio, graphicsLevel, shakeEnabled } from '../../shared/ui.js';
import { createControls } from '../../shared/touch.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { getProfile, addStat, addCoins } from '../../shared/profile.js';
import { G } from './ctx.js';
import { buildWorld } from './world.js';
import { FX } from './fx.js';
import { Fighter, hit } from './fighter.js';
import { CHARS, CHAR_IDS, resetSkills } from './skills.js';
import { Brain } from './bot.js';
import { createHUD } from './hud.js';
import { rand, clamp, pick, angleDamp, wrapAngle } from './util.js';

const MATCH_TIME = 240, KILL_LIMIT = 15;
const NAME_COLORS = ['#ff6b6b', '#ffd93d', '#6bcb77', '#4d96ff', '#c77dff', '#ff9f45', '#5ee6eb', '#ff7eb6'];
const colorOf = (name) => NAME_COLORS[[...name].reduce((a, c) => a + c.charCodeAt(0), 0) % NAME_COLORS.length];

const profile = getProfile();
const ui = initGameUI({
  title: 'Jujutsu Brosmens',
  players: () => G.fighters.slice().sort((a, b) => b.kills - a.kills).map((f) => ({ name: f.name, skin: f.skin, score: `${f.kills} уб.` })),
  onReset: () => resetPlayer(),
  controlsHelp: `<b>Телефон:</b> левая часть экрана — джойстик, свайп справа — камера. Большая кнопка — M1 (комбо из 4 ударов, 4-й отбрасывает; в прыжке — удар вниз). 🛡 — блок (держать), рывок, прыжок, ⚡ — пробуждение. Навыки — панель 1–4 внизу.<br>
  <b>ПК:</b> WASD — ход, мышь (зажать) — камера, ЛКМ/F — M1, R — блок, Q — рывок, Space — прыжок, 1–4 — навыки, G — пробуждение. Держи Space на 4-м ударе — апперкот.`,
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
scene.fog = new THREE.Fog(0xcfe6fb, 120, 360);
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.3, 1400);
const hemi = new THREE.HemisphereLight(0xe6f2ff, 0x5a7a48, 1.7);
scene.add(hemi);
const sunL = new THREE.DirectionalLight(0xfff3dd, 2.4);
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

function applyGfx() {
  gfx = graphicsLevel();
  renderer.setPixelRatio(pixelRatio());
  renderer.setSize(innerWidth, innerHeight);
  sunL.castShadow = gfx >= 4;
  scene.fog.far = 230 + gfx * 22;
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
const ctl = createControls({
  buttons: [
    { id: 'm1', label: '<b style="font-size:22px">M1</b>', x: -88, y: -92, size: 100, key: 'KeyF' },
    { id: 'block', label: '🛡<br><small style="font-size:10px">Блок</small>', x: -196, y: -64, size: 62, key: 'KeyR' },
    { id: 'dash', label: '💨<br><small style="font-size:10px">Рывок</small>', x: -182, y: -156, size: 60, key: 'KeyQ' },
    { id: 'jump', label: '⤒', x: -82, y: -202, size: 62, key: 'Space' },
    { id: 'g', label: '⚡', x: -196, y: -240, size: 58, key: 'KeyG' },
  ],
  keyMap: { Digit1: 's0', Digit2: 's1', Digit3: 's2', Digit4: 's3' },
});
G.ctl = ctl;
ctl.el('jump').style.fontSize = '26px';
ctl.el('g').style.fontSize = '22px';
let jumpQueued = false;
const P = () => (state === 'play' && G.player && !G.player.dead ? G.player : null);
ctl.onPress('m1', () => { const p = P(); if (p) { p.m1(); p.lastAttackT = G.time; } });
ctl.onPress('dash', () => P()?.dash());
ctl.onPress('jump', () => { jumpQueued = true; });
ctl.onPress('g', () => P()?.awaken());
const skillPress = (i) => { const p = P(); if (p) { p.skill(i); p.lastAttackT = G.time; } };
const skillRelease = (i) => P()?.release(i);
for (let i = 0; i < 4; i++) { ctl.onPress('s' + i, () => skillPress(i)); ctl.onRelease('s' + i, () => skillRelease(i)); }
G.hud.onSkill(skillPress, skillRelease);
renderer.domElement.addEventListener('pointerdown', (e) => {
  if (e.pointerType === 'mouse' && e.button === 0) { const p = P(); if (p) { p.m1(); p.lastAttackT = G.time; } }
});

// ---------- чат ----------
const chat = createChat({ bots: () => G.fighters.filter((f) => f.bot).map((f) => { f.bot.dead = f.dead; return f.bot; }) });
G.chat = chat;
let chatNext = 0, idleChat = rand(14, 24);
G.botEvent = (f, event, opts = {}, prio = false) => {
  if (!f || !f.bot) return;
  const now = performance.now() / 1000;
  if (now < chatNext && !(prio && now > chatNext - 3)) return;
  chatNext = now + rand(4.5, 8);
  chat.botSay(f.bot, event, opts);
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
  sfx.play(name, { vol: v });
};
G.flashNear = (pos, color, alpha, range) => {
  const p = G.player; if (!p) return;
  const d = Math.hypot(pos.x - p.pos.x, pos.z - p.pos.z);
  if (d < range) G.hud.flash(color, alpha * (1 - d / range * 0.7), 2.5);
};
G.callout = (f, text, color, selfOnly = false) => {
  const p = G.player; if (!p) return;
  if (f === p || (!selfOnly && f.dist(p) < 55)) G.hud.callout(text, f === p ? '' : f.name, color);
};
G.onAwaken = (f) => {
  f.chestPos(_t);
  G.fx.ring(_t, f.look.color, 1, 12, 0.5, { a0: 1 });
  G.fx.burst(_t, '#ffffff', 12, 0.25);
  G.sound('charge', f.pos, 0.8);
  if (f.isPlayer) { G.hud.flash(f.look.color, 0.35, 2); ui.toast('ПРОБУЖДЕНИЕ!', 1400); }
  else if (f.bot && Math.random() < 0.5) awakenLine(f);
};
const AW_NICE = ['ПРОБУЖДЕНИЕ!!', 'ну всё, пробуждение', 'держитесь ахах', 'вот теперь серьёзно', 'ульта готова)', 'смотрите что умею'];
const AW_TOXIC = ['ну всё вам конец', 'изи, пробуждение', 'щас всех разнесу', 'бегите нубы', 'ДОМЕН НА ВСЕХ', 'вы уже проиграли'];
function awakenLine(f) {
  const now = performance.now() / 1000;
  if (now < chatNext - 2) return;
  chatNext = now + rand(4.5, 8);
  if (Math.random() > (f.bot.chatty ?? 0.6)) return;
  const line = pick(Math.random() < (f.bot.toxic ?? 0.4) ? AW_TOXIC : AW_NICE);
  setTimeout(() => chat.say(f.name, line), 500 + line.length * 70);
}
G.kill = (vic, att) => {
  if (vic.dead) return;
  vic.hp = 0;
  let killer = att && att !== vic ? att : null;
  if (!killer && vic.lastHitBy && G.time - vic.lastHitT < 6 && !vic.lastHitBy.dead) killer = vic.lastHitBy;
  vic.die(killer);
  if (killer) {
    killer.kills++;
    if (killer.awakened <= 0) killer.meter = Math.min(100, killer.meter + 15);
  }
  G.hud.killfeed(killer ? killer.name : '', vic.name, killer ? killer.color : '#fff', vic.color);
  if (killer && killer.isPlayer) {
    vic.headPos(_t); G.hud.pop(_t, 'K.O.!', '#ffd23f', 2);
    G.sound('coin', killer.pos, 0.8);
  }
  if (vic.isPlayer) {
    G.hud.showDeath(killer ? killer.name : '', nextChar, profile.skin.skin, (id) => { nextChar = id; saveChar(id); });
    G.sound('lose', vic.pos, 0.4);
  }
  // чат
  if (killer && killer.bot && Math.random() < 0.55) G.botEvent(killer, 'kill', { target: vic.name, eventText: `ты победил игрока ${vic.name} в файтинге` }, true);
  else if (vic.bot && Math.random() < 0.5) G.botEvent(vic, 'death', { target: killer ? killer.name : '', eventText: killer ? `тебя только что победил ${killer.name}` : 'ты упал и проиграл' }, true);
  if (state === 'play' && killer && killer.kills >= KILL_LIMIT) endMatch();
};
const _t = new THREE.Vector3(), _u = new THREE.Vector3();

// ---------- матч ----------
let state = 'select';
let matchTime = MATCH_TIME;
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
  camYaw = player.yaw; camPitch = -0.2;
  matchTime = MATCH_TIME;
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
  const rows = G.fighters.slice().sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
  const p = G.player;
  const place = rows.indexOf(p) + 1;
  const coins = 5 + p.kills * 4 + (place === 1 ? 30 : place <= 3 ? 12 : 0);
  addCoins(coins);
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
    G.hud.showResults(rows, p, coins, () => showSelect(), () => ui.goHome());
  }, 2800);
}

function showSelect() {
  state = 'select';
  G.hud.showHUD(false);
  G.hud.hideDeath();
  G.hud.showSelect(nextChar, profile.skin.skin, (id) => startMatch(id));
}

// ---------- игрок и камера ----------
let camYaw = 0, camPitch = -0.2, camDist = 13, camCur = 13;
const camPos = new THREE.Vector3(30, 20, 30), camLook = new THREE.Vector3();
function playerInput(dt) {
  const p = G.player;
  const look = ctl.consumeLook();
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
}

function updateCamera(dt) {
  const p = G.player;
  if (G.debugCam) { camera.position.copy(G.debugCam.pos); camera.lookAt(G.debugCam.look); return; }
  if (state === 'select' || !p) {
    const t = performance.now() / 1000;
    camPos.set(Math.cos(t * 0.08) * 55, 26, Math.sin(t * 0.08) * 55);
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
  const sh = 1.25;
  const base = _u.set(camLook.x + rx * sh, camLook.y + 0.5, camLook.z + rz * sh);
  _t.set(-dx, -dy, -dz);
  let dist = G.world.rayDist(base, _t, camDist);
  dist = Math.max(2.5, dist - 0.6);
  if (dist < camCur) camCur = dist; else camCur += (dist - camCur) * (1 - Math.exp(-5 * dt));
  dist = camCur;
  camera.position.set(base.x - dx * dist, base.y - dy * dist, base.z - dz * dist);
  if (camera.position.y < 0.8) camera.position.y = 0.8;
  camera.lookAt(base.x + dx * 10, base.y + dy * 10, base.z + dz * 10);
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

// ---------- кнопки: перезарядки ----------
let lastG = '';
function updateButtons() {
  const p = G.player;
  if (!p) return;
  const defs = [0, 1, 2, 3].map((i) => p.skillDef(i));
  G.hud.setSkills(defs);
  G.hud.setCooldowns(p.cd, p.cdMax);
  ctl.setCooldown('dash', p.dashCd > 0 ? p.dashCd / 1.7 : 0);
  ctl.setCooldown('m1', p.m1Cd > 0 ? p.m1Cd / 0.95 : 0);
  const ready = p.meter >= 100 && p.awakened <= 0;
  ctl.setCooldown('g', p.awakened > 0 ? 0 : 1 - p.meter / 100);
  const gk = ready ? 'r' : p.awakened > 0 ? 'a' : 'n';
  if (gk !== lastG) {
    lastG = gk;
    const el = ctl.el('g');
    el.style.borderColor = ready || p.awakened > 0 ? p.look.color : 'rgba(255,255,255,.75)';
    el.style.boxShadow = ready ? `0 0 14px ${p.look.color}, 0 0 4px #fff` : 'none';
    ctl.setLabel('g', ready ? `⚡<br><small style="font-size:9px">${p.ch.awaken.label}</small>` : p.awakened > 0 ? '<small style="font-size:10px">ON</small>' : '⚡');
  }
  ctl.el('block').style.borderColor = p.blocking ? '#9fd8ff' : 'rgba(255,255,255,.75)';
}

// ---------- кадр ----------
let last = performance.now();
let fountainT = 0;
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
      }
    }
    // болтовня
    idleChat -= dt;
    if (idleChat <= 0) {
      idleChat = rand(16, 30);
      const b = pick(G.fighters.filter((f) => f.bot && !f.dead));
      if (b) G.botEvent(b, 'idle', { eventText: 'идёт матч в аренном файтинге, просто болтаешь в чате' });
    }
    // зоны доменов
    const p = G.player;
    if (p && !p.dead && G.shrineZone && Math.hypot(p.pos.x - G.shrineZone.center.x, p.pos.z - G.shrineZone.center.z) < G.shrineZone.r) G.hud.tint('radial-gradient(ellipse at center, rgba(120,0,0,.08), rgba(150,0,10,.4))');
    else if (p && !p.dead && G.voidZone && p.pos.distanceTo(G.voidZone.center) < G.voidZone.r) G.hud.tint('radial-gradient(ellipse at center, rgba(0,0,0,0), rgba(20,30,90,.35))');
    else G.hud.tint(null);
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
  // фонтан
  fountainT += dt;
  if (fountainT > 0.05) {
    fountainT = 0;
    for (let i = 0; i < 2; i++) { const a = rand(0, 6.28); G.fx.norm.spawn(Math.cos(a) * 0.3, 5.4, Math.sin(a) * 0.3, Math.cos(a) * rand(2, 4), rand(9, 13), Math.sin(a) * rand(2, 4), '#cfeaff', 0.7, 0.55, 0.3, 1.3, 26, 0.3); }
  }
  G.world.update(dt);
  G.fx.update(dt, camera);
}
function render(dt) {
  updateCamera(dt);
  G.hud.update(dt, camera, state === 'select' ? [] : G.fighters, state === 'select' ? null : G.player);
  // солнце/тень следуют за игроком
  const c = G.player && state !== 'select' ? G.player.pos : camLook;
  sunL.target.position.set(c.x, 0, c.z);
  sunL.position.set(c.x + G.world.sunDir.x * 120, G.world.sunDir.y * 120, c.z + G.world.sunDir.z * 120);
  renderer.render(scene, camera);
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
window.__jjs = { G, renderer, startMatch, endMatch, get state() { return state; } };

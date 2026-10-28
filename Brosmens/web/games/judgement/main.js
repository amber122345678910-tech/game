// «Судный День» — команда людей против Судьи. Точка входа: лобби-отель между раундами (27 с, очередь Судьи,
// магазин душ, статистика), раунд (интро-монолог при уже идущем таймере → бой → катсцена смерти Судьи или итог),
// ввод, камера, боты, чат, музыка и свои звуки (jdsfx), награды.
import * as THREE from 'three';
import { initGameUI, pixelRatio, graphicsLevel } from '../../shared/ui.js';
import { createControls } from '../../shared/touch.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS, pick } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { getProfile, addStat, addCoins, updateProfile } from '../../shared/profile.js';
import {
  ROLES, ROLE_IDS, MONSTERS, MONSTER_IDS, PIES, POTIONS, POTION_IDS, POTION_TIME,
  INTRO_LINES, INTRO_AGAIN, INTRO_AGAIN3, DEATH_LINES, LOBBY_TIME, HALL_X, HALL_Z,
} from './data.js';
import { FX } from './fx.js';
import { buildWorld } from './world.js';
import { buildLobby } from './lobby.js';
import { buildHuman, buildJudge } from './models.js';
import { Fighter, dist2, clamp, judgeSlash, clearance } from './combat.js';
import { initMonsterAssets, bonesBegin, bonesEnd, castBlaster, castQuad, castBoneZone, castBoneThrow, castBlue, castForce } from './monster.js';
import { initHumanAssets, updateProjectiles, clearProjectiles, humanM1, humanAbility, usePie, usePotion } from './human.js';
import { HumanBrain, MonsterBrain } from './brain.js';
import { createHUD } from './hud.js';
import { createLobbyUI } from './lobbyui.js';
import { createHotbar, createSoulButton, createAmmo, createReticle } from './hotbar.js';
import { createChatter } from './chatter.js';
import { music } from './music.js';
import { jdsfx } from './jdsfx.js';

const params = new URLSearchParams(location.search);
const AUTO = params.has('auto');          // игрок управляется ИИ (тесты/демо)
const SPEED = Math.max(1, +params.get('speed') || 1);
const NORENDER = params.has('norender');
const LOOP = params.has('loop');
const LOBBY_SEC = +params.get('lobby') || LOBBY_TIME; // длительность перерыва (параметр — для тестов)
const TAP_MS = +params.get('tapms') || 250, DBL_MS = +params.get('dblms') || 320; // тап короче 0.25 с (параметр — для медленных тестов)
const FOV = 66, CUT_FOV = 32;

const JUDGE_SKIN = { skin: '#f4f3ec', shirt: '#2c66d8', pants: '#17171d', hair: '#f4f3ec', hairStyle: 'none', face: 0 };
const ui = initGameUI({
  title: 'Судный День',
  players: () => playersList(),
  onReset: () => resetPlayer(),
  controlsHelp: `<b>Лобби:</b> гуляй джойстиком, у стойки «МАГАЗИН ДУШ» (или кнопкой снизу) выбери душу и зелье на раунд. Справа — очередь: кто следующий Судья. «Играть сейчас» — не ждать 27 с. Вкладка «&lt;» слева — победы, убийства, монеты, «Наблюдать», «Низкая графика», «Не АФК».<br>
<b>Телефон:</b> левая часть экрана — джойстик, свайп справа — камера. Снизу по центру — панель предметов: тап по слоту — выбрать, <b>тап по экрану</b> — применить выбранное туда, куда тапнул (двойной тап по слоту — применить сразу). Справа — прыжок и кнопка удара, слева — <b>сердце души</b> (способность).<br>
<b>ПК:</b> WASD — ход, мышь (зажать) — камера, клик — применить, <b>1–6</b> — слоты, <b>F</b> — удар/атака в прицел, <b>R</b> — способность души, <b>Space</b> — прыжок.<br>
<b>Люди:</b> у Судьи 15 уклонений и 1 HP. Каждый удар — «MISS» и −1 уклонение (после него Судья 0.6 с неуязвим), 16-й удар убивает. Пули и способности не снимают последнее уклонение — добивай вблизи. Пока Судья говорит, таймер уже идёт: расходитесь, ешьте пироги, пейте зелье. Продержитесь до конца таймера — тоже победа (только живым). Красный квадрат — через миг там вырастут кости. Череп-бластер стреляет лучом через весь зал — уходи вбок. Белые кости — прыгай, <span style="color:#3ff2ff">голубые</span> — стой на месте. Атаки Судьи оставляют карму (розовые цифры HP): она тикает, но не убивает; снимает её только зелье лечения.<br>
<b>Судья:</b> убей всех людей, пока не вышло время — иначе победят они. 1 Бластер · 2 Крест бластеров · 3 Зона костей · 4 Бросок костей · 5 Синяя атака · 6 Отталкивание.`,
});

// ---------- рендер ----------
const renderer = new THREE.WebGLRenderer({ antialias: pixelRatio() < 1.4, powerPreference: 'high-performance' });
renderer.setPixelRatio(pixelRatio());
renderer.setSize(innerWidth, innerHeight);
document.body.prepend(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(FOV, innerWidth / innerHeight, 0.3, 1000);

const V = new THREE.Vector3(), V2 = new THREE.Vector3(), V3 = new THREE.Vector3();
const sfxLast = {}, jdLast = {};

const G = {
  scene, camera, time: 0, state: 'lobby', roundLeft: 0, timeScale: 1, hitStopT: 0,
  fighters: [], humans: [], monster: null, player: null, hazards: [], projectiles: [], brains: new Map(),
  camFocus: null, camFwd: new THREE.Vector3(0, 0, -1), botProfiles: [], playerSide: 'human', mdef: MONSTERS.judge,
  // общий банк звуков (shared/sfx.js): затухание с расстоянием от того, за кем смотрит камера
  sfx(name, vol = 1, who = null, gap = 0.035) {
    const now = performance.now() / 1000;
    if (now - (sfxLast[name] || 0) < gap) return;
    if (who && G.camFocus && who !== G.camFocus) vol *= clamp(1 - dist2(who.pos, G.camFocus.pos) / 80, 0.15, 1);
    sfxLast[name] = now;
    sfx.play(name, { vol });
  },
  // свои звуки «Судного Дня» (jdsfx.js, таблица §7.6): тот же контекст и громкость, что у музыки.
  // who — боец или { pos } (затухание с расстоянием), o — параметры звука, gap — не чаще раза в gap с
  jd(name, who = null, vol = 1, o = null, gap = 0.035) {
    const now = performance.now() / 1000;
    const key = name === 'hurt' && who?.name ? 'hurt' + who.name : name;
    if (now - (jdLast[key] || 0) < gap) return;
    jdLast[key] = now;
    const ref = G.camFocus?.pos;
    if (who?.pos && ref && who !== G.camFocus) vol *= clamp(1 - dist2(who.pos, ref) / 90, 0.15, 1);
    jdsfx.play(name, vol, o || {});
  },
  // гул Синей атаки
  audio(name) {
    if (name === 'humOn') jdsfx.hum(true);
    else if (name === 'humOff') jdsfx.hum(false);
  },
  toast: (t) => ui.toast(t),
  hitStop(t) { G.hitStopT = Math.max(G.hitStopT, t); },
  onEvent: (type, d) => onEvent(type, d),
};
G.fx = new FX(scene, camera);
G.world = buildWorld(scene);
G.lobby = buildLobby(scene, G.fx);
initMonsterAssets(G);
initHumanAssets(G);
const judgeModel = buildJudge();

function resize() {
  renderer.setSize(innerWidth, innerHeight);
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  G.fx.setScale(innerHeight * renderer.getPixelRatio(), camera.fov);
}
addEventListener('resize', resize); resize();
function setFov(f) {
  if (camera.fov === f) return;
  camera.fov = f; camera.updateProjectionMatrix();
  G.fx.setScale(innerHeight * renderer.getPixelRatio(), f);
}
function applySettings() {
  renderer.setPixelRatio(pixelRatio());
  const lv = graphicsLevel();
  G.fx.setQuality(lv); G.world.setQuality(lv);
  music.applySettings();
  resize();
  if (lobbyUI) lobbyUI.setFlags(flags());
}
let lobbyUI = null;
ui.onSettings(applySettings);

// ---------- управление (как в роблоксе) ----------
// джойстик и камера — shared/touch.js; кнопка прыжка — серый круг со стрелкой (70×70, левый верх в (W−95, H−90));
// кнопка удара ~80 px в (83%, 62%); снизу по центру — панель предметов, слева — сердце души.
const ctl = createControls({
  buttons: [
    { id: 'jump', label: '', x: -60, y: -55, size: 70, key: 'Space' },
    { id: 'm1', label: '', x: -150, y: -150, size: 80, key: 'KeyF' },
  ],
});
function layoutButtons() {
  // как TouchJump в роблоксе: маленький экран (min(W,H) ≤ 500) — 70×70 в (W−95, H−90), большой — 120×120 в (W−170, H−210)
  const j = ctl.el('jump'), m = ctl.el('m1'), big = Math.min(innerWidth, innerHeight) > 500;
  j.classList.add('jd-jump'); m.classList.add('jd-m1');
  const js = big ? 120 : 70, jx = big ? 170 : 95, jy = big ? 210 : 90, ms = big ? 100 : 80;
  j.style.width = j.style.height = js + 'px';
  j.style.left = `calc(100vw - ${jx}px - env(safe-area-inset-right, 0px))`; j.style.top = `calc(100vh - ${jy}px - env(safe-area-inset-bottom, 0px))`;
  m.style.width = m.style.height = ms + 'px';
  m.style.left = `calc(83vw - ${ms / 2}px)`; m.style.top = `calc(62vh - ${ms / 2}px)`;
}
layoutButtons(); addEventListener('resize', layoutButtons);
const showButtons = (jump, m1 = jump) => { ctl.show('jump', jump); ctl.show('m1', m1); };
showButtons(false);

const hotbar = createHotbar({ onTap: (id) => slotTap(id), onDouble: (id) => slotDouble(id) });
const soulBtn = createSoulButton({ onPress: () => doAbility() });
const ammoEl = createAmmo();
const reticle = createReticle();

const chat = createChat({ bots: () => G.botProfiles });
const chatter = createChatter(G, chat);
const hud = createHUD(); hud.show(false);

// ---------- сервер: игрок, Клод и 3 бота. Живут между раундами (как сервер в роблоксе) ----------
const prof0 = getProfile();
const server = {
  claude: { ...FRIENDS[0], skill: 0.86, chatty: 0.8, typo: false, dead: false },
  bots: makeBots(3, { exclude: [prof0.name, FRIENDS[0].name] }).map((b) => ({ ...b, dead: false })),
  queue: [],     // очередь Судьи из ботов (Клод всегда в команде игрока, в очереди его нет)
  rosterKey: '',
};
server.queue = [...server.bots].sort(() => Math.random() - 0.5);
G.botProfiles = [server.claude, ...server.bots];

let selection = loadSel(), lossStreak = 0, lobbyT = 0, lobbyRoll = Math.random(), shopAuto = false, monsterTips = 0;
const flagsState = { spectate: false, afk: false };
function flags() { return { ...flagsState, lowGfx: graphicsLevel() <= 3 }; }
function loadSel() {
  const def = { side: 'human', role: 'det', potion: 'heal', monster: 'judge' };
  try {
    const s = { ...def, ...JSON.parse(localStorage.getItem('brosmens.judgement.sel') || '{}') };
    if (!ROLES[s.role]) s.role = 'det';
    if (!POTIONS[s.potion]) s.potion = 'heal';
    if (!['human', 'monster', 'random'].includes(s.side)) s.side = 'human';
    if (s.monster !== 'random' && !MONSTERS[s.monster]) s.monster = 'judge';
    return s;
  } catch { return def; }
}
function saveSel(s) { try { localStorage.setItem('brosmens.judgement.sel', JSON.stringify(s)); } catch {} }

function playersList() {
  if (G.fighters.length) {
    return G.fighters.map((f) => ({
      name: f.name, skin: f.team === 'monster' ? JUDGE_SKIN : f.skin,
      team: f.team === 'monster' ? 'Монстр' : 'Люди', teamColor: f.team === 'monster' ? '#7fb4ff' : f.color,
      score: (f.team === 'monster' ? 'Судья · уклонений ' + f.dodges : f.role.name + ' · ' + Math.max(0, Math.ceil(f.hp)) + ' HP') + (f.dead ? ' · пал' : '') + ' · убийств ' + f.stats.kills,
    }));
  }
  const p = getProfile();
  return [{ name: p.name, skin: p.skin, score: 'в лобби' }, ...G.botProfiles.map((b) => ({ name: b.name, skin: b.skin, score: 'в лобби' }))];
}

// ---------- события ----------
function onEvent(type, d) {
  chatter.event(type, d);
  if (type === 'mcast' || type === 'force' || type === 'blue') { const k = type === 'mcast' ? d.what : type; if (G.castLog) G.castLog[k] = (G.castLog[k] || 0) + 1; }
  const p = G.player;
  if (type === 'kill') {
    if (d.h.isPlayer) specIdx = 0;
  } else if (type === 'mdead') {
    startOutro(d.src);
  } else if (type === 'force') {
    if (p && p.team === 'human' && !p.dead) G.fx.shake(0.12);
  } else if (type === 'blue') {
    if (p && p.team === 'human' && !p.dead) hud.banner('СИНЯЯ АТАКА', 'Голубые — стой. Белые — прыгай', 1500, '#3ff2ff');
  } else if (type === 'ability') {
    if (d.f.roleId === 'jus') chatter.event('reload', d);
  }
}

// ---------- камера ----------
const cam = { yaw: 0, pitch: 0.36, tgt: new THREE.Vector3(), snap: true, cutT: 0, cutAng: 0, cutHold: false, cutTgt: new THREE.Vector3(), cutPos: new THREE.Vector3() };
const cutsceneOn = () => !!G.monster && (cam.cutHold || ((G.state === 'intro' || G.state === 'outro') && hud.dlg.active));
// угол съёмки катсцены: спереди от Судьи, но так, чтобы камера не оказалась в колонне или за стеной
const CUT_D = 11;
function pickCutAngle(m, base) {
  const free = (x, z) => Math.abs(x) < HALL_X - 1.6 && Math.abs(z) < HALL_Z - 1.6 && clearance(x, z, 3) > 1.7;
  for (const k of [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]) {
    const a = base + k * 0.35, sx = Math.sin(a), sz = Math.cos(a);
    let ok = true;
    for (const f of [0.35, 0.65, 1]) if (!free(m.pos.x + sx * CUT_D * f, m.pos.z + sz * CUT_D * f)) { ok = false; break; }
    if (ok) return a;
  }
  return base;
}
function updateCamera(dt) {
  const look = ctl.consumeLook();
  const menu = chat.isOpen() || lobbyUI.shopOpen || lobbyUI.charsOpen;
  if (!menu) { cam.yaw -= look.dx * 0.0065; cam.pitch = clamp(cam.pitch + look.dy * 0.005, -0.12, 1.15); }
  if (G.state === 'lobby') { lobbyCamera(dt); return; }
  if (cutsceneOn()) { cutCamera(dt); return; }
  setFov(FOV);
  const f = G.camFocus || G.player;
  if (!f) return;
  const isM = f.team === 'monster';
  const dist = isM ? 17 : 15, hgt = isM ? 5.6 : 4.6;
  V.set(f.pos.x, (f.dead ? 0 : f.pos.y) + hgt, f.pos.z);
  // игрок-Судья: камера чуть сдвинута вправо (как shift-lock), прицел в центре экрана не закрыт черепом
  if (isM && f === G.player) { V.x += Math.cos(cam.yaw) * 2.4; V.z -= Math.sin(cam.yaw) * 2.4; }
  if (cam.snap) { cam.tgt.copy(V); cam.snap = false; } else cam.tgt.lerp(V, 1 - Math.exp(-11 * dt));
  const cp = Math.cos(cam.pitch);
  camera.position.set(cam.tgt.x + Math.sin(cam.yaw) * cp * dist, cam.tgt.y + Math.sin(cam.pitch) * dist, cam.tgt.z + Math.cos(cam.yaw) * cp * dist);
  if (camera.position.y < 0.8) camera.position.y = 0.8;
  camera.lookAt(cam.tgt);
  camera.position.add(G.fx.shakeOff);
  G.camFwd.set(-Math.sin(cam.yaw), 0, -Math.cos(cam.yaw));
}
// Катсцена: Судья крупным планом «по грудь» (узкий угол), камера медленно наезжает
function cutCamera(dt) {
  const m = G.monster;
  setFov(CUT_FOV);
  cam.cutT += dt;
  const fx = Math.sin(cam.cutAng), fz = Math.cos(cam.cutAng), rx = fz, rz = -fx;
  const d = CUT_D - Math.min(1, cam.cutT / 10) * 1.3;
  V.set(m.pos.x + fx * d + rx * 0.9, 4.75, m.pos.z + fz * d + rz * 0.9);
  V2.set(m.pos.x + rx * 0.2, 4.3, m.pos.z + rz * 0.2);
  if (cam.cutSnap) { cam.cutPos.copy(V); cam.cutTgt.copy(V2); cam.cutSnap = false; }
  else { const k = 1 - Math.exp(-5 * dt); cam.cutPos.lerp(V, k); cam.cutTgt.lerp(V2, k); }
  camera.position.copy(cam.cutPos).add(G.fx.shakeOff);
  camera.lookAt(cam.cutTgt);
}
// Лобби: камера за своим аватаром, не вылезает за стены комнаты
function lobbyCamera(dt) {
  setFov(FOV);
  const me = G.lobby.me;
  if (!me) return;
  V.set(me.pos.x, me.pos.y + 4.4, me.pos.z);
  if (cam.snap) { cam.tgt.copy(V); cam.snap = false; } else cam.tgt.lerp(V, 1 - Math.exp(-11 * dt));
  const cp = Math.cos(cam.pitch), dist = 14;
  camera.position.set(cam.tgt.x + Math.sin(cam.yaw) * cp * dist, cam.tgt.y + Math.sin(cam.pitch) * dist, cam.tgt.z + Math.cos(cam.yaw) * cp * dist);
  camera.position.x = clamp(camera.position.x, -32.6, 32.6); camera.position.z = clamp(camera.position.z, -26.6, 26.6);
  camera.position.y = clamp(camera.position.y, 1, 21);
  camera.lookAt(cam.tgt);
  G.camFwd.set(-Math.sin(cam.yaw), 0, -Math.cos(cam.yaw));
}

// ---------- ввод игрока ----------
function playerMoveInput() {
  const p = G.player;
  if (!p || p.dead || AUTO) return;
  const mv = ctl.move;
  const fx = -Math.sin(cam.yaw), fz = -Math.cos(cam.yaw), rx = Math.cos(cam.yaw), rz = -Math.sin(cam.yaw);
  p.moveDir.set(rx * mv.x + fx * mv.y, 0, rz * mv.x + fz * mv.y);
  const l = p.moveDir.length(); if (l > 1) p.moveDir.divideScalar(l);
  // зажатая кнопка удара с оружием в руках — бьём по готовности
  if (ctl.down('m1') && p.team === 'human' && p.equipped === 'weapon' && G.state === 'fight') useEquipped(null);
}

const RC = new THREE.Raycaster(), NDC = new THREE.Vector2(), GROUND = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), AIMP = new THREE.Vector3(), TMP = new THREE.Vector3();
function nearestHumanTo(pt, maxD = 1e9) {
  let best = null, bd = maxD;
  for (const h of G.humans) { if (h.dead) continue; const d = dist2(h.pos, pt); if (d < bd) { bd = d; best = h; } }
  return best;
}
// человек, мимо которого проходит луч тапа (помощь в прицеливании на телефоне)
function humanOnRay(ray, maxDist = 2.6) {
  let best = null, bd = maxDist;
  for (const h of G.humans) {
    if (h.dead) continue;
    TMP.set(h.pos.x, h.pos.y + 2.6, h.pos.z);
    const d = ray.distanceToPoint(TMP);
    if (d < bd) { bd = d; best = h; }
  }
  return best;
}
// Точка прицела Судьи: пол под прицелом (центр экрана); рядом человек — бьём в него с упреждением;
// прицел смотрит в небо или слишком далеко — в ближайшего человека.
function reticleAim(lead = 0) {
  const p = G.player;
  NDC.set(0, 0); RC.setFromCamera(NDC, camera);
  const t = humanOnRay(RC.ray, 2.2);
  if (t) return AIMP.copy(t.pos).addScaledVector(t.hv, lead);
  if (RC.ray.intersectPlane(GROUND, AIMP) && dist2(AIMP, p.pos) < 80) {
    const h = nearestHumanTo(AIMP, 4.5);
    if (h) return AIMP.copy(h.pos).addScaledVector(h.hv, lead);
    return AIMP;
  }
  const h = nearestHumanTo(p.pos, 90);
  if (h) return AIMP.copy(h.pos).addScaledVector(h.hv, lead);
  return AIMP.copy(p.pos).addScaledVector(G.camFwd, 25);
}
// Точка на полу под тапом (THREE.Raycaster против y=0) с помощью в прицеливании
function tapPoint(cx, cy) {
  const p = G.player;
  NDC.set((cx / innerWidth) * 2 - 1, -(cy / innerHeight) * 2 + 1);
  RC.setFromCamera(NDC, camera);
  if (p.team === 'monster') {
    const h = humanOnRay(RC.ray);
    if (h) return AIMP.copy(h.pos);
  } else {
    const m = G.monster;
    if (m && !m.dead) { TMP.set(m.pos.x, m.pos.y + 3, m.pos.z); if (RC.ray.distanceToPoint(TMP) < 3) return AIMP.copy(m.pos); }
  }
  if (RC.ray.intersectPlane(GROUND, AIMP) && dist2(AIMP, p.pos) < 110) return AIMP;
  // тап над горизонтом — точка далеко по направлению луча
  TMP.copy(RC.ray.direction).setY(0).normalize();
  return AIMP.copy(p.pos).addScaledVector(TMP, 60).setY(0);
}

const LEAD = { blast: 0.6, quad: 0.5, zone: 0.75, throw: 0.3 };
// Атаки монстра по id инструмента (новые монстры добавляют сюда свои)
function castTool(id, at) {
  const p = G.player;
  if (id === 'blast') return castBlaster(G, p, at);
  if (id === 'quad') return castQuad(G, p, at);
  if (id === 'zone') return castBoneZone(G, p, at);
  if (id === 'throw') return castBoneThrow(G, p, at);
  if (id === 'blue') return castBlue(G, p);
  if (id === 'force') return castForce(G, p);
  return false;
}
let cdToastT = 0;
const itemPhase = () => G.state === 'fight' || G.state === 'intro'; // предметы можно и в интро
// Применить выбранный предмет/атаку. at — точка (тап) или null (кнопка/клавиша — в прицел/автонаводка)
function useEquipped(at) {
  const p = G.player;
  if (!p || p.dead || !itemPhase() || AUTO) return false;
  const id = p.equipped;
  if (p.team === 'human') {
    if (id === 'weapon') return G.state === 'fight' && humanM1(G, p, at);
    if (id.startsWith('pie')) { if (usePie(G, p)) { hotbar.remove(id); equip('weapon'); return true; } return false; }
    if (id === 'potion') {
      if (p.potionId) { ui.toast(`${POTIONS[p.potionId].name}: ещё ${Math.ceil(p.potionUntil - G.time)} с`, 1200); equip('weapon'); return false; }
      if (usePotion(G, p)) { equip('weapon'); return true; }
      return false;
    }
    return false;
  }
  if (G.state !== 'fight') return false;
  if (!p.ready(id)) {
    if (performance.now() - cdToastT > 900) { cdToastT = performance.now(); ui.toast(`${hotbar.name(id).replace(/­/g, '')}: перезарядка ${Math.ceil(p.cdLeft(id))} с`, 900); }
    return false;
  }
  return castTool(id, at || reticleAim(LEAD[id] || 0));
}
function equip(id) {
  const p = G.player;
  if (!p || !hotbar.has(id)) return;
  p.equipped = id;
  hotbar.setEquipped(id);
  // подпись кнопки удара — короткое имя выбранного предмета (без эмодзи)
  let nm = hotbar.name(id);
  if (id === 'weapon') nm = nm.replace(/­/g, '').split(' ').pop().replace(/^./, (c) => c.toUpperCase());
  else if (id === 'potion') nm = 'Зелье';
  ctl.setLabel('m1', `<b class="jd-m1l">${nm}</b>`);
}
function slotTap(id) {
  const p = G.player;
  if (!p || p.dead) return;
  if (p.equipped !== id) { equip(id); sfx.play('ui', { vol: 0.35 }); }
}
// двойной тап по слоту — применить сразу (Судья: в прицел, а если там пусто — в ближайшего человека)
function slotDouble(id) {
  equip(id);
  if (!useEquipped(null)) buffer(() => useEquipped(null));
}
let lastKey = { n: 0, t: 0 };
function keySlot(n) {
  const id = hotbar.byNum(n);
  if (!id) return;
  const t = performance.now();
  if (lastKey.n === n && t - lastKey.t < DBL_MS) { lastKey.n = 0; slotDouble(id); }
  else { lastKey = { n, t }; slotTap(id); }
}
function doAbility() {
  const p = G.player;
  if (!p || p.dead || p.team !== 'human' || G.state !== 'fight' || AUTO) return;
  if (!p.role.ability) { ui.toast(p.dtUsed ? 'Вторая жизнь уже потрачена' : 'Решимость: на 1 HP — снова полное здоровье и 2 с неуязвимости', 1600); return; }
  if (!p.ready('R')) return;
  if (!humanAbility(G, p)) buffer(() => humanAbility(G, p));
}
// нажатие во время другого действия выполнится, как только персонаж освободится
let buffered = null;
function buffer(fn) { if (G.player?.busy) buffered = { fn, until: G.time + 0.45 }; }
function flushBuffered() {
  if (!buffered) return;
  if (G.time > buffered.until || !itemPhase()) { buffered = null; return; }
  if (G.player && !G.player.busy && buffered.fn()) buffered = null;
}
ctl.onPress('jump', () => {
  if (G.state === 'lobby') { if (!lobbyUI.shopOpen && !lobbyUI.charsOpen) G.lobby.jump(); return; }
  const p = G.player; if (p && !p.dead && itemPhase() && !AUTO) p.jump();
});
ctl.onPress('m1', () => { if (!useEquipped(null) && G.player?.team === 'monster') buffer(() => useEquipped(null)); });
addEventListener('keydown', (e) => {
  if (e.repeat || e.target.closest?.('input,textarea') || ui.menuOpen()) return;
  if (G.state === 'lobby') return;
  if (/^Digit[1-6]$/.test(e.code)) keySlot(+e.code.slice(5));
  else if (e.code === 'KeyR') doAbility();
  else if ((e.code === 'Enter' || e.code === 'KeyE') && hud.dlg.active) hud.dlg.tap();
});
// Тап по 3D-сцене (короче 0.25 с, сдвиг меньше 12 px, не на кнопке и не в зоне джойстика) — применить
// выбранное в точку под пальцем. Перетаскивание по-прежнему крутит камеру (shared/touch.js).
// В катсцене тап по сцене листает реплики Судьи (кроме тапа с пирогом/зельем в руках — их можно есть и в интро).
const taps = new Map();
addEventListener('pointerdown', (e) => {
  if (e.target !== renderer.domElement) return;
  if (e.pointerType === 'mouse' ? e.button !== 0 : e.clientX < innerWidth * 0.42) return;
  taps.set(e.pointerId, { x: e.clientX, y: e.clientY, t: performance.now() });
});
addEventListener('pointermove', (e) => { const s = taps.get(e.pointerId); if (s && Math.hypot(e.clientX - s.x, e.clientY - s.y) > 12) taps.delete(e.pointerId); });
addEventListener('pointercancel', (e) => taps.delete(e.pointerId));
addEventListener('pointerup', (e) => {
  const s = taps.get(e.pointerId); taps.delete(e.pointerId);
  if (!s || performance.now() - s.t > TAP_MS || chat.isOpen()) return;
  const p = G.player;
  if (cutsceneOn() && !(p && !p.dead && p.team === 'human' && p.equipped !== 'weapon' && G.state === 'intro')) { hud.dlg.tap(); return; }
  if (!p || p.dead || !itemPhase() || AUTO) return;
  const at = tapPoint(e.clientX, e.clientY).clone();
  if (!useEquipped(at)) buffer(() => useEquipped(at));
});

function hideRoundControls() {
  showButtons(false); hotbar.show(false); soulBtn.show(false); ammoEl.show(false); reticle.show(false);
  updateControls.key = '';
}
function updateControls() {
  const p = G.player;
  if (G.state === 'lobby') return;
  const show = !!p && !p.dead && (G.state === 'fight' || G.state === 'intro');
  const intro = G.state === 'intro';
  const key = show + (p?.team || '') + intro;
  if (key !== updateControls.key) {
    updateControls.key = key;
    // в интро атаковать нельзя — кнопки удара нет; панель предметов есть (пироги и зелье можно)
    showButtons(show, show && !intro); hotbar.show(show);
    soulBtn.show(show && p.team === 'human');
    ammoEl.show(show && p.roleId === 'jus');
    reticle.show(show && p.team === 'monster' && !intro);
    hud.dlg.setRaised?.(show);
  }
  if (!show) return;
  if (p.team === 'human') {
    // зелье: слот остаётся, пока действует (кольцо цвета зелья на 45 с), потом исчезает
    if (p.potionId && G.time >= p.potionUntil && hotbar.has('potion')) { hotbar.remove('potion'); if (p.equipped === 'potion') equip('weapon'); }
    hotbar.update((id) => {
      if (id === 'weapon' && (p.cdLen.m1 || 0) >= 1.5) return [p.cdFrac('m1'), p.cdLeft('m1')];
      if (id === 'potion' && p.potionId && G.time < p.potionUntil) return [0, 0, (p.potionUntil - G.time) / POTION_TIME, POTIONS[p.potionId].color];
      return [0, 0];
    });
    if (p.role.ability) { soulBtn.setHeart(p.color); soulBtn.setCooldown(p.cdFrac('R'), p.cdLeft('R')); }
    else soulBtn.setHeart(p.color, p.dtUsed, p.dtUsed);
    if (p.roleId === 'jus') ammoEl.set(p.ammo, G.time < p.potionUntil ? POTIONS[p.potionId].color : '#F0F800');
  } else hotbar.update((id) => [p.cdFrac(id), p.cdLeft(id)]);
}

// ---------- лобби ----------
function lobbyActors() {
  const prof = getProfile();
  return [{ name: prof.name, skin: prof.skin, me: true }, ...G.botProfiles.map((b) => ({ name: b.name, skin: b.skin }))];
}
// Кто будет Судьёй в следующем раунде: «Судья» — ты; «Человек» — первый бот в очереди;
// «Случайно» — жребий (30%) бросается при входе в лобби, чтобы доска очереди не врала.
function planRound() {
  const meJudge = !flagsState.spectate && (selection.side === 'monster' || (selection.side === 'random' && lobbyRoll < 0.3));
  return { meJudge, judgeBot: meJudge ? null : server.queue[0] };
}
function updateQueueUI() {
  const pl = planRound(), me = getProfile().name;
  const rows = [];
  if (pl.meJudge) rows.push({ name: me, me: true });
  for (const b of server.queue) rows.push({ name: b.name });
  if (!pl.meJudge) rows.push({ name: me + (flagsState.spectate ? ' · смотрит' : ''), me: true });
  const hint = flagsState.spectate ? 'Наблюдение: в раунде играют только боты'
    : selection.side === 'human' ? 'Ты играешь за людей' : selection.side === 'monster' ? 'Ты — Судья, пока не сменишь'
      : pl.meJudge ? 'Жребий: ты — Судья!' : 'Жребий: ты — человек';
  lobbyUI.setQueue(rows, hint);
  lobbyUI.setNext(pl.meJudge ? 'Следующий Судья: ты' : 'Следующий Судья: ' + pl.judgeBot.name);
}
function lobbyStats() {
  const p = getProfile(), s = p.stats?.judgement || {};
  return { wins: s.wins || 0, kills: s.kills || 0, coins: p.coins || 0 };
}
// Между раундами иногда кто-то уходит с сервера и заходит новый (как в роблоксе)
function churnServer() {
  if (Math.random() > 0.2) return;
  const cand = server.bots.filter((b) => b !== server.queue[0]);
  const gone = pick(cand);
  if (!gone) return;
  const prof = getProfile();
  const nb = { ...makeBots(1, { exclude: [prof.name, server.claude.name, ...server.bots.map((b) => b.name)] })[0], dead: false };
  server.bots[server.bots.indexOf(gone)] = nb;
  const qi = server.queue.indexOf(gone); server.queue.splice(qi, 1); server.queue.push(nb);
  G.botProfiles = [server.claude, ...server.bots];
  chat.system(`${gone.name} вышел из игры`);
  setTimeout(() => chat.system(`${nb.name} присоединился к игре`), 1500);
}

function enterLobby(result = null) {
  clearRound();
  G.state = 'lobby'; G.camFocus = null; G.player = null; cam.cutHold = false;
  G.world.setVisible(false); G.lobby.setVisible(true);
  hud.show(false); hud.hideBanner(); hud.spectate(false); hud.dlg.close(false);
  hideRoundControls(); showButtons(true, false);
  setFov(FOV);
  jdsfx.stopLoops();
  music.duck(false); music.play('lobby');
  if (result) churnServer();
  const key = lobbyActors().map((a) => a.name).join('|');
  if (key !== server.rosterKey) { server.rosterKey = key; G.lobby.setActors(lobbyActors()); } else G.lobby.respawn();
  cam.yaw = 0; cam.pitch = 0.3; cam.snap = true;
  lobbyT = LOOP ? 1 : LOBBY_SEC; lobbyRoll = Math.random(); shopAuto = true;
  lobbyUI.show(true); lobbyUI.setSel(selection); lobbyUI.setFlags(flags());
  lobbyUI.setStats(lobbyStats(), !!result);
  updateQueueUI();
  const pl = planRound();
  if (pl.judgeBot) G.lobby.wave(pl.judgeBot.name);
  chatter.event('lobby', { judge: pl.judgeBot, meJudge: pl.meJudge, back: !!result });
  if (result?.coins && !AUTO) setTimeout(() => G.state === 'lobby' && ui.toast(`+${result.coins} монет`, 2200), 1400);
}

function lobbyStep(rdt) {
  const menu = lobbyUI.shopOpen || lobbyUI.charsOpen || chat.isOpen();
  const mv = menu ? { x: 0, y: 0 } : ctl.move;
  const fx = -Math.sin(cam.yaw), fz = -Math.cos(cam.yaw), rx = Math.cos(cam.yaw), rz = -Math.sin(cam.yaw);
  let x = rx * mv.x + fx * mv.y, z = rz * mv.x + fz * mv.y;
  const l = Math.hypot(x, z); if (l > 1) { x /= l; z /= l; }
  G.lobby.control(x, z);
  G.lobby.update(G.time, rdt);
  // подошёл к стойке «МАГАЗИН ДУШ» — открывается магазин (один раз за подход)
  if (G.lobby.zone === 'shop') { if (!shopAuto) { shopAuto = true; lobbyUI.openShop(true); sfx.play('ui', { vol: 0.4 }); } }
  else shopAuto = false;
  if (!flagsState.afk) {
    lobbyT -= rdt;
    if ((lobbyUI.shopOpen || lobbyUI.charsOpen) && lobbyT < 5) lobbyT = 5; // не выкидываем из магазина посреди выбора
  }
  lobbyUI.setCountdown(lobbyT, flagsState.afk);
  if (lobbyUI.update(rdt)) G.jd('tick', null, 0.45, null, 0.05);
  if (lobbyT <= 0) startRound();
}

// ---------- раунд ----------
let specIdx = 0, endT = 0;
function clearRound() {
  for (const hz of G.hazards) hz.dispose?.();
  G.hazards.length = 0;
  clearProjectiles(G);
  bonesBegin(G); bonesEnd(G);
  for (const f of G.fighters) f.remove();
  G.fighters = []; G.humans = []; G.monster = null; G.player = null; G.brains.clear();
  G.fx.clear(); G.world.setDark(0);
  G.timeScale = 1; G.hitStopT = 0; G.winnerTeam = null; G.settled = null; G.bannerShown = false;
  jdsfx.stopLoops();
  buffered = null;
}

function assignRoles(n, fixed) {
  // fixed: массив уже выбранных ролей; добиваем до n, сначала недостающие роли
  const out = [...fixed];
  const missing = ROLE_IDS.filter((r) => !out.includes(r)).sort(() => Math.random() - 0.5);
  while (out.length < n) out.push(missing.length ? missing.shift() : pick(ROLE_IDS));
  return out;
}

function makeHuman(name, bot, isPlayer, roleId, skin, potion) {
  const role = ROLES[roleId];
  const model = buildHuman(skin, role);
  model.disposable = true;
  const f = new Fighter(G, { name, bot, isPlayer, team: 'human', roleId, role, color: role.color, hp: role.hp, speed: role.speed, radius: 1.05, model });
  f.skin = skin; f.pies = PIES; f.potion = potion;
  // у ботов набор как у живых игроков: пироги и зелья покупаются за монеты, есть не у всех
  if (bot) { const sk = bot.skill ?? 0.6; f.pies = Math.min(PIES, Math.floor(Math.random() * 2.2 + sk * 1.6)); if (Math.random() > 0.35 + sk * 0.45) f.potion = null; }
  return f;
}
function resolveMonster() {
  const id = selection.monster;
  return MONSTERS[id] ? id : pick(MONSTER_IDS);
}
function setJudgeEyes(mode) {
  if (judgeModel.eyeMode === mode) return;
  judgeModel.eyeMode = mode; judgeModel.setEyes(mode);
  if (mode === 'glow' && G.monster) {
    G.monster.glow = 1; judgeModel.root.updateMatrixWorld(true); judgeModel.eye.getWorldPosition(V);
    G.fx.flare(V, 0x6ff4ff, 2.2, 0.4); G.jd('whine', null, 0.35, { dur: 0.45 }, 0.2);
  }
}

// force: 'human' | 'monster' | 'spectator' — сторона без лобби (тесты, ?side=)
function startRound(force = null) {
  if (G.state === 'intro' || G.state === 'fight' || G.state === 'outro') return;
  const pl = planRound();
  lobbyUI.show(false); G.lobby.setVisible(false); G.world.setVisible(true);
  clearRound();
  const prof = getProfile();
  let side = force || (flagsState.spectate ? 'spectator' : pl.meJudge ? 'monster' : 'human');
  G.playerSide = side;
  const mid = resolveMonster(), mdef = MONSTERS[mid];
  G.mdef = mdef;
  for (const b of G.botProfiles) b.dead = false;
  const claude = server.claude;
  // как в UJD: 5 игроков на сервере — 1 Судья + до 4 людей (игрок, Клод, 3 бота; один из ботов — Судья, если игрок человек)
  const judgeBot = side === 'monster' ? null : (pl.judgeBot || server.queue[0]);
  const others = server.bots.filter((b) => b !== judgeBot);
  const entries = [];
  if (side === 'human') entries.push({ name: prof.name, bot: null, isPlayer: true, skin: prof.skin, role: selection.role, potion: selection.potion || 'heal' });
  const claudeRole = side === 'human' ? (selection.role === 'pat' ? 'brv' : 'pat') : null;
  entries.push({ name: claude.name, bot: claude, isPlayer: false, skin: claude.skin, role: claudeRole });
  for (const b of others) entries.push({ name: b.name, bot: b, isPlayer: false, skin: b.skin, role: null });
  const roles = assignRoles(entries.length, entries.filter((e) => e.role).map((e) => e.role));
  let ri = entries.filter((e) => e.role).length;
  for (const e of entries) if (!e.role) e.role = roles[ri++];
  // бойцы: люди у «своего» конца зала, Судья — у дальнего
  entries.forEach((e, i) => {
    const f = makeHuman(e.name, e.bot, e.isPlayer, e.role, e.skin, e.potion || pick(POTION_IDS));
    const n = entries.length, x = (i - (n - 1) / 2) * 7.5;
    f.pos.set(x, 0, 30 + Math.abs(x) * 0.15); f.yaw = f.targetYaw = Math.PI;
    G.humans.push(f); G.fighters.push(f);
    if (e.isPlayer) G.player = f;
    if (!e.isPlayer || AUTO) G.brains.set(f, new HumanBrain(G, f));
  });
  const m = new Fighter(G, {
    name: side === 'monster' ? prof.name : judgeBot.name, bot: judgeBot, isPlayer: side === 'monster',
    team: 'monster', roleId: 'monster', role: mdef, color: '#5f9bff', hp: mdef.hp, dodges: mdef.dodges, speed: mdef.speed, radius: mdef.radius, model: judgeModel,
  });
  judgeModel.reset(); judgeModel.root.visible = true; judgeModel.shadow.visible = true; judgeModel.shadow.material.opacity = 1;
  judgeModel.body.scale.setScalar(judgeModel.baseScale); judgeModel.body.rotation.set(0, 0, 0);
  for (const mt of judgeModel.mats) mt.emissive.setHex(mt.userData.e0);
  judgeModel.eyeMode = ''; setJudgeEyes('pupils');
  m.pos.set(0, 0, -35); m.yaw = m.targetYaw = 0;
  G.monster = m; G.fighters.push(m);
  if (side === 'monster') G.player = m;
  if (side !== 'monster' || AUTO) G.brains.set(m, new MonsterBrain(G, m));
  // старт: таймер уже идёт, Судья говорит (интро), люди расходятся, едят и пьют
  G.camFocus = G.player || m; cam.snap = true; cam.cutSnap = true; cam.cutT = 0; cam.cutHold = false; cam.cutAng = m.yaw;
  cam.yaw = side === 'monster' ? Math.PI : 0; cam.pitch = side === 'monster' ? 0.42 : 0.34;
  G.roundLeft = mdef.timer; G.state = 'intro'; specIdx = 0; G.dmgLog = {}; G.castLog = {};
  hud.setup(G); hud.show(true); hud.spectate(false); hud.hideBanner(); hud.showTimer(true);
  if (G.player) setupControls(G.player); else hideRoundControls();
  G.fx.flash('#000000', 0.9);
  sfx.play('spawn', { vol: 0.6 });
  music.play('boss'); music.duck(true);
  chatter.reset(); chatter.event('start');
  // реплики: после проигрыша — «хей. опять ты.» перед обычными (а после нескольких — сразу к делу)
  let lines = mdef.intro || INTRO_LINES;
  if (side === 'human' && lossStreak >= 3) lines = [INTRO_AGAIN3[0], { ...INTRO_AGAIN3[1], eyes: 'glow' }];
  else if (side === 'human' && lossStreak >= 1) lines = [...INTRO_AGAIN, ...lines];
  hud.dlg.start(lines, {
    onChar: () => G.jd('blip', null, 0.8, { pitch: 150 }, 0.02),
    onLine: (i, ln) => { if (ln.eyes) setJudgeEyes(ln.eyes); },
    onDone: () => beginFight(),
  });
  if (AUTO && NORENDER) hud.dlg.close(true);
}

function setupControls(p) {
  updateControls.key = '';
  if (p.team === 'human') {
    const tools = [{ id: 'weapon', num: 1, name: p.role.weapon.replace('Игрушечный', 'Игрушеч­ный') }];
    for (let i = 0; i < p.pies; i++) tools.push({ id: 'pie' + (i + 1), num: i + 2, name: 'Пирог' });
    if (p.potion) tools.push({ id: 'potion', num: 5, name: POTIONS[p.potion].name });
    hotbar.setTools(tools);
    equip('weapon');
  } else {
    hotbar.setTools(G.mdef.tools.map((t, i) => ({ id: t.id, num: i + 1, name: t.name.replace('Отталкивание', 'Оттал­кивание') })));
    equip('blast');
  }
}

// конец интро: глаз горит, камера возвращается за спину, Судья может атаковать
function beginFight() {
  if (G.state !== 'intro') return;
  G.state = 'fight'; music.duck(false);
  setJudgeEyes('glow');
  cam.snap = true; G.camFocus = G.player || G.monster;
  updateControls.key = '';
  if (G.playerSide === 'monster' && monsterTips < 2 && !AUTO) { monsterTips++; ui.toast('1–6 — выбери атаку, тап по полу — бей туда. Двойной тап по слоту — сразу в прицел', 4200); }
}

// Итоги раунда: награды, статистика, очередь. Вызывается один раз в момент победы.
function settle(winner, why) {
  if (G.settled) return G.settled;
  const p = G.player, humansWon = winner === 'humans';
  G.winnerTeam = humansWon ? 'human' : 'monster';
  const side = G.playerSide;
  // как в UJD: победу получают только живые люди (или Судья, если перебил всех); убийства засчитываются всем
  const win = side === 'human' ? humansWon && !p.dead : side === 'monster' ? !humansWon : false;
  const teamWon = side === 'human' && humansWon;
  let coins = 0;
  if (p) {
    const s = p.stats;
    if (side === 'human') coins = win ? 30 + Math.min(25, Math.floor(s.dmg / 50)) : teamWon ? 15 + Math.min(15, Math.floor(s.dmg / 60)) : 8 + Math.min(15, Math.floor(s.dmg / 80));
    else coins = win ? 45 + s.kills * 5 : 12 + s.kills * 4;
    coins += s.kills * 3;
    if (!AUTO) {
      addCoins(coins);
      addStat('judgement', 'games', 1);
      if (win) addStat('judgement', 'wins', 1);
      if (s.kills) addStat('judgement', 'kills', s.kills);
      addStat('judgement', 'damage', Math.round(s.dmg));
      addStat('judgement', side === 'monster' ? 'monsterGames' : 'humanGames', 1);
    }
  }
  if (side === 'human') lossStreak = humansWon ? 0 : lossStreak + 1;
  // очередь: бот-Судья уходит в конец
  const jb = G.monster.bot;
  if (jb && server.queue.includes(jb)) { server.queue.splice(server.queue.indexOf(jb), 1); server.queue.push(jb); }
  chatter.event('end', { winner, why });
  const elapsed = G.mdef.timer - Math.max(0, G.roundLeft);
  const result = { winner, why, win, side, time: Math.round(elapsed), mhp: Math.max(0, Math.round(G.monster.hp)), dodgesLeft: G.monster.dodges, alive: G.humans.filter((h) => !h.dead).length, coins, roles: G.humans.map((h) => h.roleId + (h.dead ? 'x' : '')).join(','), dmg: G.humans.map((h) => Math.round(h.stats.dmg)).join(','), dodged: G.monster.stats.dodged, causes: G.dmgLog, heal: G.humans.map((h) => Math.round(h.stats.heal)).join(','), casts: G.castLog, chat: chat.log.length };
  (window.__jd.results ||= []).push(result);
  console.log('ROUND', JSON.stringify(result));
  G.settled = result;
  return result;
}

// Все люди пали или вышло время: короткая пауза, затем баннер
function endRound(winner, reason, why) {
  if (G.state !== 'fight') return;
  settle(winner, why);
  G.state = 'end'; endT = 0;
  for (const hz of G.hazards) hz.dispose?.();
  G.hazards.length = 0;
  G.fx.setDark(0); G.world.setDark(0);
  jdsfx.stopLoops();
  hud.spectate(false); hideRoundControls();
  if (why === 'wipe') { G.timeScale = 0.35; setTimeout(() => (G.timeScale = 1), 900); }
  setTimeout(() => roundBanner(reason), NORENDER ? 50 : why === 'wipe' ? 1100 : 400);
}

// Катсцена смерти Судьи (V4): музыка обрывается в кадр удара; Судья уклоняется в последний раз и начинает
// «хех, ты правда думал…» — красный разрез поперёк груди и металлический «вжик» — ещё 4 реплики, на последних
// тело тает за 2.5 с (чёрная полоска «0/1» остаётся), с подола сыплется пыль. Потом баннер и лобби.
function startOutro() {
  if (G.state !== 'fight') return;
  const m = G.monster;
  music.silence(); jdsfx.stopLoops();
  settle('humans', 'kill');
  G.state = 'outro';
  for (const hz of G.hazards) hz.dispose?.();
  G.hazards.length = 0;
  clearProjectiles(G);
  G.fx.setDark(0); G.world.setDark(0);
  hud.spectate(false); hideRoundControls(); hud.dlg.setRaised?.(false); hud.showTimer(false);
  // Судья поворачивается к камере (разрез — на груди); камера держит крупный план до самого лобби
  cam.cutAng = pickCutAngle(m, m.yaw); m.yaw = m.targetYaw = cam.cutAng;
  G.camFocus = m; cam.cutSnap = true; cam.cutT = 0; cam.cutHold = true;
  if (AUTO && NORENDER) { judgeSlash(G, m); m.fadeAt = m.deadT; roundBanner('Судья повержен!'); return; }
  hud.dlg.start(m.role.death || DEATH_LINES, {
    onChar: () => G.jd('blip', null, 0.8, { pitch: 150 }, 0.02),
    onEvent: (ev) => {
      if (ev === 'slash' && m.slashT == null) judgeSlash(G, m);
      else if (ev === 'fade' && m.fadeAt == null) m.fadeAt = m.deadT;
    },
    onDone: () => roundBanner('Судья повержен!'),
  });
}

// Короткий пиксельный баннер (2–3 с) и обратно в лобби, где досчитываются победы, убийства и монеты
function roundBanner(reason) {
  const r = G.settled;
  if (!r || G.bannerShown) return;
  G.state = 'end'; G.bannerShown = true;
  const humansWon = r.winner === 'humans';
  const sub = r.side === 'spectator' ? reason : r.win ? 'Победа! +1 к победам' : (r.side === 'human' && humansWon ? 'Победа достаётся только выжившим' : reason);
  hud.banner(humansWon ? 'КОМАНДА ЛЮДЕЙ ПОБЕДИЛА' : 'СУДЬЯ ПОБЕДИЛ', sub, 2700, humansWon ? '#ffffff' : '#7fe8ff', true);
  setTimeout(() => sfx.play(r.win || (r.side === 'human' && humansWon) ? 'win' : 'lose', { vol: 0.8 }), 250);
  const back = () => {
    if (G.state !== 'end') return;
    if (LOOP && AUTO) { G.state = 'lobby'; startRound(params.get('side') || null); return; }
    enterLobby(r);
  };
  setTimeout(back, NORENDER ? 200 : 2900);
}

function resetPlayer() {
  if (G.state === 'lobby') { G.lobby.respawn(); cam.snap = true; ui.toast('Ты снова у фонтана'); return; }
  const p = G.player;
  if (!p || p.dead || G.state !== 'fight' || p.flung) return;
  G.fx.after(p.pos, p.team === 'monster' ? 0x5fb4ff : p.color, 6, 0.4);
  if (p.team === 'monster') p.pos.set(0, 0, -35); else p.pos.set((Math.random() - 0.5) * 20, 0, 30);
  p.hv.set(0, 0, 0); p.kb.set(0, 0, 0); p.vy = 0;
  cam.snap = true;
  ui.toast('Персонаж перемещён на старт');
}

// Наблюдение: полоска «< Наблюдение: Имя >»; сначала Судья, потом живые люди
function spectateStep() {
  const p = G.player;
  // своя смерть видна целиком (душа вылетает, трескается и рассыпается за ~1.8 с), потом — наблюдение
  const watching = G.playerSide === 'spectator' || (p && p.dead && p.team === 'human' && p.deadT > 2.0);
  if (!watching) {
    if (p && !p.dead && G.camFocus !== p) { G.camFocus = p; hud.spectate(false); }
    return;
  }
  const list = [];
  if (!G.monster.dead) list.push(G.monster);
  for (const h of G.humans) if (!h.dead) list.push(h);
  if (!list.length) return;
  const t = list[((specIdx % list.length) + list.length) % list.length];
  if (G.camFocus !== t) { G.camFocus = t; cam.snap = true; cam.yaw = t.yaw + Math.PI; cam.pitch = 0.36; }
  hud.spectate(true, t.name, G.playerSide === 'spectator');
}
hud.onSpecNext((d) => { specIdx += d; sfx.play('ui', { vol: 0.3 }); });
hud.onSpecLeave?.(() => { if (G.state === 'fight' || G.state === 'intro') { G.state = 'end'; enterLobby(null); } });

// ---------- шаг симуляции ----------
function separate() {
  const fs = G.fighters;
  for (let i = 0; i < fs.length; i++) for (let j = i + 1; j < fs.length; j++) {
    const a = fs[i], b = fs[j];
    if (a.dead || b.dead) continue;
    if (Math.abs(a.pos.y - b.pos.y) > 5) continue;
    const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z, d = Math.hypot(dx, dz), min = a.radius + b.radius;
    if (d >= min || d < 0.001) continue;
    const push = (min - d), wa = a.team === 'monster' ? 0.15 : b.team === 'monster' ? 0.85 : 0.5;
    a.pos.x -= (dx / d) * push * wa; a.pos.z -= (dz / d) * push * wa;
    b.pos.x += (dx / d) * push * (1 - wa); b.pos.z += (dz / d) * push * (1 - wa);
  }
}

// треск кармы — пока у того, за кем смотрит камера, есть карма
function karmaSound() {
  const f = G.camFocus;
  const on = (G.state === 'fight' || G.state === 'intro') && f && f.team === 'human' && !f.dead && f.karma > 0.5;
  jdsfx.kr(on ? 0.35 + 0.65 * Math.min(1, f.karma / 30) : 0);
}

function roundStep(dt, rdt) {
  // таймер раунда идёт и во время интро (как в UJD)
  if (G.state === 'intro' || G.state === 'fight') G.roundLeft -= dt;
  playerMoveInput();
  if (G.state === 'fight' || G.state === 'intro') for (const [, b] of G.brains) b.update(dt);
  else for (const f of G.fighters) f.moveDir.set(0, 0, 0);
  for (const f of G.fighters) f.update(dt);
  flushBuffered();
  separate();
  for (let i = 0; i < G.hazards.length; i++) { if (!G.hazards[i].update(dt)) { G.hazards.splice(i, 1); i--; } }
  updateProjectiles(G, dt);
  bonesBegin(G); for (const hz of G.hazards) hz.draw?.(G); bonesEnd(G);
  if (G.state === 'fight') {
    if (G.humans.every((h) => h.dead)) endRound('monster', 'Все люди пали', 'wipe');
    else if (G.roundLeft <= 0) { G.roundLeft = 0; endRound('humans', 'Время вышло — люди выстояли', 'time'); }
    else spectateStep();
  }
  if (G.state === 'end') endT += rdt;
  karmaSound();
}

function step(rdt) {
  let dt = rdt * G.timeScale;
  if (G.hitStopT > 0) { G.hitStopT -= rdt; dt *= 0.06; }
  G.time += dt;
  hud.dlg.update(rdt);
  G.cutIntro = G.state === 'intro' && cutsceneOn(); // в интро-крупном плане полоску Судьи не показываем
  if (G.state === 'lobby') lobbyStep(rdt);
  else if (G.monster) roundStep(dt, rdt);
  G.world.update(G.time, dt);
  G.fx.update(dt, camera);
  updateCamera(rdt);
  hud.update(G, rdt);
  updateControls();
  if (!NORENDER) chatter.update();
}

lobbyUI = createLobbyUI({
  onPlay: () => { if (G.state === 'lobby') { sfx.play('ui', { vol: 0.5 }); startRound(); } },
  onSide: (id) => { selection.side = id; saveSel(selection); lobbyUI.setSel(selection); updateQueueUI(); sfx.play('ui', { vol: 0.4 }); },
  onSoul: (id) => { selection.role = id; saveSel(selection); lobbyUI.setSel(selection); G.jd('chime', null, 0.4, null, 0.1); },
  onPotion: (id) => { selection.potion = id; saveSel(selection); lobbyUI.setSel(selection); G.jd('glug', null, 0.5, null, 0.1); },
  onChar: (id) => { selection.monster = id; saveSel(selection); lobbyUI.setSel(selection); sfx.play('ui', { vol: 0.4 }); },
  onFlag: (k) => {
    if (k === 'lowGfx') {
      // «Низкая графика»: качество 2 (и обратно — на прежнее)
      const low = graphicsLevel() <= 3;
      let prev = 6; try { prev = +localStorage.getItem('brosmens.judgement.gfx') || 6; } catch {}
      if (!low) { try { localStorage.setItem('brosmens.judgement.gfx', String(graphicsLevel())); } catch {} }
      updateProfile((p) => { p.settings.graphics = low ? Math.max(4, prev) : 2; });
      applySettings();
    } else flagsState[k] = !flagsState[k];
    lobbyUI.setFlags(flags()); updateQueueUI(); sfx.play('ui', { vol: 0.4 });
  },
});
applySettings();

let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  const rdt = Math.min(0.05, (now - last) / 1000); last = now;
  const t0 = performance.now();
  for (let i = 0; i < SPEED; i++) step(rdt);
  const t1 = performance.now();
  if (!NORENDER) renderer.render(scene, camera);
  const pf = window.__jd; if (pf) { pf.stepMs = pf.stepMs * 0.95 + (t1 - t0) * 0.05; pf.renderMs = pf.renderMs * 0.95 + (performance.now() - t1) * 0.05; }
}

window.__jd = {
  stepMs: 0, renderMs: 0, G, renderer, cam, results: [], ctl, useEquipped, equip, slotDouble, doAbility, hotbar, music, jdsfx, chat, hud, lobbyUI, server,
  startRound: (side) => { G.state = 'lobby'; startRound(side || null); },
  enterLobby: () => enterLobby(null),
  endRound: (w, r, why) => endRound(w, r, why),
  skipIntro: () => hud.dlg.close(true),
};
ui.loading(false);
if (AUTO || params.has('side')) startRound(params.get('side') || 'human');
else enterLobby(null);
requestAnimationFrame(frame);

// «Судный День» — команда людей против Судьи. Точка входа: сцена, раунды, ввод, камера, боты, чат, награды.
import * as THREE from 'three';
import { initGameUI, pixelRatio, graphicsLevel } from '../../shared/ui.js';
import { createControls } from '../../shared/touch.js';
import { createChat } from '../../shared/chat.js';
import { makeBots, FRIENDS, pick, rand, typingDelay } from '../../shared/bots.js';
import { sfx } from '../../shared/sfx.js';
import { getProfile, addStat, addCoins } from '../../shared/profile.js';
import { aiBotLine } from '../../shared/ai.js';
import { animateAvatar } from '../../shared/avatar.js';
import { ROLES, ROLE_IDS, MONSTER, ROUND_TIME, ARENA_HALF } from './data.js';
import { FX, heartDataURL } from './fx.js';
import { buildWorld } from './world.js';
import { buildHuman, buildJudge } from './models.js';
import { Fighter, dist2, clamp } from './combat.js';
import { initMonsterAssets, bonesBegin, bonesEnd, monsterM1, monsterTeleport, castBlasters, castBones, castGravity, castUlt } from './monster.js';
import { initHumanAssets, updateProjectiles, clearProjectiles, humanM1, humanDash, humanSkill, canRevive } from './human.js';
import { HumanBrain, MonsterBrain } from './brain.js';
import { createHUD, showSelect, showResults } from './hud.js';

const params = new URLSearchParams(location.search);
const AUTO = params.has('auto');          // игрок управляется ИИ (тесты/демо)
const SPEED = Math.max(1, +params.get('speed') || 1);
const NORENDER = params.has('norender');
const LOOP = params.has('loop');

const JUDGE_SKIN = { skin: '#f4f3ec', shirt: '#2f62d6', pants: '#15151d', hair: '#f4f3ec', hairStyle: 'none', face: 0 };
const ui = initGameUI({
  title: 'Судный День',
  players: () => {
    if (!G.fighters.length) { const p = getProfile(); return [{ name: p.name, skin: p.skin }]; }
    return G.fighters.map((f) => ({
      name: f.name, skin: f.team === 'monster' ? JUDGE_SKIN : f.skin,
      team: f.team === 'monster' ? 'Монстр' : 'Люди', teamColor: f.team === 'monster' ? '#7fb4ff' : f.color,
      score: (f.team === 'monster' ? 'Монстр · Судья' : 'Люди · ' + f.role.name) + (f.dead ? ' · ☠' : '') + ' · урон ' + Math.round(f.stats.dmg),
    }));
  },
  onReset: () => resetPlayer(),
  controlsHelp: `<b>Телефон:</b> левая часть экрана — джойстик, свайп справа — камера, кнопки справа — удар (M1), рывок, прыжок и навыки 1–3 (у Судьи ещё 4 — ульта).<br>
<b>ПК:</b> WASD — ход, мышь (зажать) — камера, <b>F</b> — удар, <b>Q</b> — рывок/телепорт, <b>Space</b> — прыжок, <b>1–4</b> — навыки.<br>
<b>Люди:</b> сбейте Судье полоску уклонения серией ударов, потом бейте сильными навыками. Белые кости — перепрыгивай, <span style="color:#6fb4ff">синие</span> — стой на месте, <span style="color:#ffa040">оранжевые</span> — двигайся. Полоса на полу = будущий луч бластера.<br>
<b>Судья:</b> убей всех людей или продержись 3:00. Удары по тебе уклоняются, пока есть выносливость уклонения.`,
});

// ---------- рендер ----------
const renderer = new THREE.WebGLRenderer({ antialias: pixelRatio() < 1.4, powerPreference: 'high-performance' });
renderer.setPixelRatio(pixelRatio());
renderer.setSize(innerWidth, innerHeight);
document.body.prepend(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(66, innerWidth / innerHeight, 0.3, 1000);

const V = new THREE.Vector3(), V2 = new THREE.Vector3();
const sfxLast = {};

const G = {
  scene, camera, time: 0, state: 'menu', roundLeft: ROUND_TIME, timeScale: 1, hitStopT: 0,
  fighters: [], humans: [], monster: null, player: null, hazards: [], projectiles: [], brains: new Map(),
  camFocus: null, camFwd: new THREE.Vector3(0, 0, -1), botProfiles: [], playerSide: 'human',
  sfx(name, vol = 1, who = null, gap = 0.035) {
    const now = performance.now() / 1000;
    if (now - (sfxLast[name] || 0) < gap) return;
    if (who && G.camFocus && who !== G.camFocus) vol *= clamp(1 - dist2(who.pos, G.camFocus.pos) / 80, 0.15, 1);
    sfxLast[name] = now;
    sfx.play(name, { vol });
  },
  toast: (t) => ui.toast(t),
  hitStop(t) { G.hitStopT = Math.max(G.hitStopT, t); },
  onEvent: (type, d) => onEvent(type, d),
};
G.fx = new FX(scene, camera);
G.world = buildWorld(scene);
initMonsterAssets(G);
initHumanAssets(G);
const judgeModel = buildJudge();

function resize() {
  renderer.setSize(innerWidth, innerHeight);
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  G.fx.setScale(innerHeight * renderer.getPixelRatio(), camera.fov);
}
addEventListener('resize', resize); resize();
function applySettings() {
  renderer.setPixelRatio(pixelRatio());
  const lv = graphicsLevel();
  G.fx.setQuality(lv); G.world.setQuality(lv);
  resize();
}
ui.onSettings(applySettings); applySettings();

// ---------- управление ----------
const ctl = createControls({
  buttons: [
    { id: 'm1', label: '👊', x: -78, y: -88, size: 92, key: 'KeyF' },
    { id: 'jump', label: '⤒<br><small>Прыжок</small>', x: -182, y: -50, size: 62, key: 'Space' },
    { id: 'dash', label: '💨<br><small>Рывок</small>', x: -188, y: -128, size: 58, key: 'KeyQ' },
    { id: 's1', label: '1', x: -56, y: -196, size: 60, key: 'Digit1' },
    { id: 's2', label: '2', x: -126, y: -212, size: 60, key: 'Digit2' },
    { id: 's3', label: '3', x: -194, y: -200, size: 60, key: 'Digit3' },
    { id: 's4', label: '4', x: -262, y: -150, size: 64, key: 'Digit4' },
  ],
});
const BTN = ['m1', 'jump', 'dash', 's1', 's2', 's3', 's4'];
const showButtons = (v) => BTN.forEach((id) => ctl.show(id, v));
showButtons(false);

const chat = createChat({ bots: () => G.botProfiles });
const hud = createHUD(); hud.show(false);

// ---------- реплики ботов ----------
let lastTalk = -99, talkGap = 5, idleTalkT = 30;
const CLAUDE_VS = {
  start: ['ого, ты Судья? ну держись, бро 😄', 'щас мы тебя всей командой, без обид)', 'бро, только не бластерами в лицо пж 😅'],
  kill: ['прости-прости, это просто игра 😅', 'это тебе за тот бластер!', 'ну ты и уворачиваешься, жесть'],
  death: ['ахах, красиво снёс 😄', 'ладно, ты силён', 'эй, я же твой друг!'],
  hit: ['ай! ну ты даёшь', 'это было больно, бро 😂'],
  idle: ['кто-нибудь, сбейте ему уклонение!', 'бро, ты слишком хорош в этом', 'держу дистанцию от твоих черепов 👀'],
  win: ['гг, бро! ты страшный Судья 😄', 'вот это ты нас разнёс, уважение'],
  lose: ['гг! в следующий раз отыграешься 💪', 'хорошо держался, бро'],
};
async function claudeSay(event, eventText) {
  const c = G.botProfiles[0];
  let text = eventText ? await aiBotLine(c, eventText + ' (твой друг-игрок сейчас играет за монстра-Судью, а ты — против него, шути по-дружески)', { chatLog: chat.log }) : null;
  text ||= pick(CLAUDE_VS[event] || CLAUDE_VS.idle);
  setTimeout(() => chat.say(c.name, text), typingDelay(text));
}
function talk(bot, event, opts = {}, force = false) {
  if (!bot || NORENDER) return;
  const now = performance.now() / 1000;
  if (now - lastTalk < (force ? 2.5 : talkGap)) return;
  lastTalk = now; talkGap = rand(4.5, 8);
  if (bot.id === 'claude' && G.playerSide === 'monster') return claudeSay(event, opts.eventText);
  chat.botSay(bot, event, opts);
}

// ---------- события ----------
function nameHTML(f) { return `<b style="color:${f.team === 'monster' ? '#7fb4ff' : f.color}">${f.name.replace(/</g, '&lt;')}</b>`; }
function onEvent(type, d) {
  const p = G.player;
  if (type === 'kill') {
    hud.feed(`${nameHTML(d.src || G.monster)} 💀 ${nameHTML(d.h)} <small>${d.cause || ''}</small>`);
    if (d.h.isPlayer) { ui.banner('ТЫ ПАЛ', 'Терпение может поднять тебя', 1800, '#ff4a5a'); specIdx = 0; }
    if (d.h.bot && Math.random() < 0.7) talk(d.h.bot, 'death', { target: G.monster.name, eventText: `тебя (человека) убил монстр-Судья ${G.monster.name} атакой «${d.cause}» в игре Судный День` });
    else if (G.monster.bot) talk(G.monster.bot, 'kill', { target: d.h.name, eventText: `ты (монстр-Судья) убил игрока ${d.h.name}` });
    if (G.monster.isPlayer && p) { G.fx.text(V.set(d.h.pos.x, 6, d.h.pos.z), '+КИЛЛ', 'crit', 1.2); }
  } else if (type === 'revive') {
    hud.feed(`${nameHTML(d.by)} ✨ поднимает ${nameHTML(d.h)}`);
    if (d.h.isPlayer) { ui.banner('ТЫ СНОВА В ИГРЕ!', 'Спасибо, ' + d.by.name, 1600, '#8fffd0'); hud.spectate(false); }
    else if (d.h.bot) talk(d.h.bot, 'thanks', { target: d.by.name, eventText: `тебя воскресил союзник ${d.by.name}` }, true);
  } else if (type === 'broken') {
    if (p?.team === 'human') hud.alert('УКЛОНЕНИЕ СУДЬИ СЛОМАНО — БЕЙ!', 1300, 'good');
    else if (p?.team === 'monster') hud.alert('Уклонение сломано! Отступи!', 1300, 'bad');
  } else if (type === 'gravity') {
    if (d.h === p) hud.alert('⚠ ГРАВИТАЦИЯ — ВЫЙДИ ИЗ КРУГА!', 900, 'bad');
  } else if (type === 'grabbed') {
    if (d.h === p) hud.alert('💙 СИНЯЯ ДУША!', 900, 'bad');
    else if (d.h.bot && Math.random() < 0.4) talk(d.h.bot, 'help', { eventText: 'тебя поднял гравитацией монстр и сейчас швырнёт об пол' });
  } else if (type === 'ult') {
    ui.banner('ПОСЛЕДНЯЯ АТАКА', p?.team === 'monster' ? 'Сотри их!' : 'Уворачивайся!', 2200, '#ffe040');
    const b = G.humans.find((h) => h.bot && !h.dead);
    if (b) talk(b.bot, 'help', { eventText: 'монстр-Судья запустил ультимейт «Последняя атака»: черепа по кругу и волны костей' }, true);
  } else if (type === 'hurt') {
    if (d.h === p && p.karma > 0 && !G.krHint) { G.krHint = true; ui.toast('* Ты чувствуешь, как грехи ползут по спине… (КР — яд, HP тает)', 3200); }
    if (d.h.bot && d.h.hp / d.h.maxHp < 0.3 && Math.random() < 0.15) talk(d.h.bot, 'help', { eventText: 'у тебя мало HP, Судья тебя почти убил' });
  } else if (type === 'heal') {
    if (d.t !== d.f && d.t.bot && Math.random() < 0.12) talk(d.t.bot, 'thanks', { target: d.f.name, eventText: `тебя подлечил ${d.f.name}` });
  } else if (type === 'mhit') {
    if (G.monster.isPlayer && d.src?.bot?.id === 'claude' && Math.random() < 0.05) talk(d.src.bot, 'kill', {});
    if (G.monster.bot && d.amount >= 30 && Math.random() < 0.3) talk(G.monster.bot, 'hit', { target: d.src?.name, eventText: `тебя (монстра) сильно ударил ${d.src?.name}` });
  }
}

// ---------- камера ----------
const cam = { yaw: 0, pitch: 0.36, tgt: new THREE.Vector3(), snap: true, orbit: 0 };
function updateCamera(dt) {
  const look = ctl.consumeLook();
  if (G.state === 'menu') {
    cam.orbit += dt * 0.12;
    camera.position.set(Math.sin(cam.orbit) * 24, 8.5, Math.cos(cam.orbit) * 24);
    camera.lookAt(0, 4.5, 0);
    return;
  }
  if (!chat.isOpen()) { cam.yaw -= look.dx * 0.0065; cam.pitch = clamp(cam.pitch + look.dy * 0.005, -0.12, 1.15); }
  const f = G.camFocus || G.player;
  if (!f) return;
  const isM = f.team === 'monster';
  const dist = isM ? 19 : 15, hgt = isM ? 6.8 : 4.6;
  V.set(f.pos.x, (f.dead ? 0 : f.pos.y) + hgt, f.pos.z);
  if (cam.snap) { cam.tgt.copy(V); cam.snap = false; } else cam.tgt.lerp(V, 1 - Math.exp(-11 * dt));
  const cp = Math.cos(cam.pitch);
  camera.position.set(cam.tgt.x + Math.sin(cam.yaw) * cp * dist, cam.tgt.y + Math.sin(cam.pitch) * dist, cam.tgt.z + Math.cos(cam.yaw) * cp * dist);
  if (camera.position.y < 0.8) camera.position.y = 0.8;
  camera.lookAt(cam.tgt);
  camera.position.add(G.fx.shakeOff);
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
  if (ctl.down('m1')) doAction('m1');
}
function aimTargetHuman(maxD = 48) {
  const p = G.player; let best = null, bs = 1e9;
  for (const h of G.humans) {
    if (h.dead) continue;
    V2.set(h.pos.x - p.pos.x, 0, h.pos.z - p.pos.z); const d = V2.length(); if (d > maxD) continue;
    const ang = Math.acos(clamp(V2.dot(G.camFwd) / Math.max(0.01, d), -1, 1));
    const s = d + ang * 25;
    if (s < bs) { bs = s; best = h; }
  }
  return best;
}
function doAction(id) {
  const p = G.player;
  if (!p || p.dead || G.state !== 'fight' || AUTO) return;
  if (id === 'jump') return p.jump();
  if (p.team === 'human') {
    if (id === 'm1') return humanM1(G, p);
    if (id === 'dash') return humanDash(G, p, V.copy(p.moveDir.lengthSq() > 0.01 ? p.moveDir : G.camFwd));
    if (id[0] === 's' && id !== 's4') return humanSkill(G, p, +id[1] - 1);
  } else {
    if (id === 'm1') return monsterM1(G, p);
    if (id === 'dash') return monsterTeleport(G, p, V.copy(p.moveDir.lengthSq() > 0.01 ? p.moveDir : G.camFwd));
    if (id === 's1') {
      const list = G.humans.filter((h) => !h.dead).sort((a, b) => { V.subVectors(a.pos, p.pos); V2.subVectors(b.pos, p.pos); return (V.length() - V.normalize().dot(G.camFwd) * 15) - (V2.length() - V2.normalize().dot(G.camFwd) * 15); });
      return castBlasters(G, p, list);
    }
    if (id === 's2') return castBones(G, p, G.camFwd);
    if (id === 's3') { const t = aimTargetHuman(); if (!t) { ui.toast('Нет цели рядом'); return false; } return castGravity(G, p, t); }
    if (id === 's4') { if (p.ult < 100) { ui.toast('Ульта заряжается: ' + Math.floor(p.ult) + '%'); return false; } return castUlt(G, p); }
  }
  return false;
}
let buffered = null; // нажатие во время другого действия выполнится, как только персонаж освободится
for (const id of BTN) ctl.onPress(id, () => {
  if (!doAction(id) && id !== 'm1' && id !== 'jump' && G.player && G.player.busy) buffered = { id, until: G.time + 0.45 };
});
function flushBuffered() {
  if (!buffered) return;
  if (G.time > buffered.until || G.state !== 'fight') { buffered = null; return; }
  if (G.player?.canAct() && doAction(buffered.id)) buffered = null;
}

let lastBtnKey = '';
function updateButtons() {
  const p = G.player;
  if (!p || G.state === 'menu' || G.state === 'results') return;
  const show = !p.dead && (G.state === 'fight' || G.state === 'intro');
  const key = show + p.team;
  if (key !== lastBtnKey) { lastBtnKey = key; showButtons(show); if (show) ctl.show('s4', p.team === 'monster'); }
  if (!show) return;
  for (const id of ['m1', 'dash', 's1', 's2', 's3']) ctl.setCooldown(id, p.cdFrac(id));
  if (p.team === 'human' && p.roleId === 'pat') {
    const el = ctl.el('s3'); const ok = !!canRevive(G, p);
    el.style.opacity = ok ? 1 : 0.45;
  }
  if (p.team === 'monster') {
    const u = Math.floor(p.ult);
    ctl.setCooldown('s4', 1 - p.ult / 100);
    const lbl = u >= 100 ? '☠️<br><small>УЛЬТА!</small>' : `☠️<br><small>${u}%</small>`;
    if (lbl !== updateButtons.ul) { updateButtons.ul = lbl; ctl.setLabel('s4', lbl); ctl.el('s4').classList.toggle('jd-ready', u >= 100); }
  }
}
function setupButtons(p) {
  lastBtnKey = '';
  if (p.team === 'human') {
    const r = p.role;
    ctl.setLabel('m1', `${r.m1.icon}<br><small>${r.m1.name}</small>`);
    r.skills.forEach((s, i) => ctl.setLabel('s' + (i + 1), `${s.icon}<br><small>${s.short}</small>`));
    ctl.setLabel('dash', '💨<br><small>Рывок</small>');
    ['m1', 's1', 's2', 's3'].forEach((id) => (ctl.el(id).style.borderColor = r.color));
  } else {
    ctl.setLabel('m1', '🦴<br><small>Кость</small>');
    MONSTER.skills.forEach((s, i) => ctl.setLabel('s' + (i + 1), `${s.icon}<br><small>${s.short}</small>`));
    ctl.setLabel('dash', '👻<br><small>Телепорт</small>');
    ['m1', 's1', 's2', 's3', 's4'].forEach((id) => (ctl.el(id).style.borderColor = '#5f9bff'));
  }
  ctl.el('s3').style.opacity = 1;
  updateButtons.ul = '';
}

// ---------- раунд ----------
let specIdx = 0, introT = 0, endT = 0, selection = loadSel(), resultsEl = null, selectEl = null;
function loadSel() { try { return { side: 'human', role: 'det', ...JSON.parse(localStorage.getItem('brosmens.judgement.sel') || '{}') }; } catch { return { side: 'human', role: 'det' }; } }
function saveSel(s) { try { localStorage.setItem('brosmens.judgement.sel', JSON.stringify(s)); } catch {} }

function clearRound() {
  for (const hz of G.hazards) hz.dispose?.();
  for (const hz of G.hazards) if (hz.kind === 'gravity') hz.release?.();
  G.hazards.length = 0;
  clearProjectiles(G);
  bonesBegin(G); bonesEnd(G);
  for (const f of G.fighters) f.remove();
  G.fighters = []; G.humans = []; G.monster = null; G.player = null; G.brains.clear();
  G.fx.clear(); G.world.setDark(0);
  G.timeScale = 1; G.hitStopT = 0; G.winnerTeam = null;
}

function assignRoles(n, fixed) {
  // fixed: массив уже выбранных ролей; добиваем до n, сначала недостающие роли, лекарь — обязательно
  const out = [...fixed];
  const missing = ROLE_IDS.filter((r) => !out.includes(r)).sort(() => Math.random() - 0.5);
  if (missing.includes('pat')) { missing.splice(missing.indexOf('pat'), 1); missing.unshift('pat'); }
  while (out.length < n) out.push(missing.length ? missing.shift() : pick(ROLE_IDS));
  return out;
}

function makeHuman(name, bot, isPlayer, roleId, skin) {
  const role = ROLES[roleId];
  const model = buildHuman(skin, role, name, !isPlayer);
  model.disposable = true;
  // щит и кольцо провокации
  const sh = new THREE.Mesh(new THREE.SphereGeometry(3.3, 18, 12), new THREE.MeshBasicMaterial({ color: 0x8fe9ff, transparent: true, opacity: 0.25, depthWrite: false, blending: THREE.AdditiveBlending }));
  sh.position.y = 2.7; sh.visible = false; model.root.add(sh); model.shieldMesh = sh;
  const tr = new THREE.Mesh(new THREE.RingGeometry(2.2, 2.6, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xff9a1f, transparent: true, opacity: 0.8, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
  tr.position.y = 0.1; tr.visible = false; model.root.add(tr); model.tauntRing = tr;
  const f = new Fighter(G, { name, bot, isPlayer, team: 'human', roleId, role, color: role.color, hp: role.hp, speed: role.speed, radius: 1.05, model });
  f.skin = skin;
  return f;
}

function startRound(sel) {
  saveSel(sel);
  clearRound();
  resultsEl?.remove(); resultsEl = null;
  const prof = getProfile();
  const side = sel.side === 'random' ? (Math.random() < 0.3 ? 'monster' : 'human') : sel.side;
  G.playerSide = side;
  const claude = { ...FRIENDS[0], skill: 0.86, chatty: 0.8, typo: false, dead: false };
  const others = makeBots(4, { exclude: [prof.name, claude.name] });
  others.forEach((b) => (b.dead = false));
  G.botProfiles = [claude, ...others];
  const monsterBot = side === 'monster' ? null : others.splice(Math.floor(Math.random() * others.length), 1)[0];
  // состав людей
  const entries = [];
  if (side === 'human') entries.push({ name: prof.name, bot: null, isPlayer: true, skin: prof.skin, role: sel.role });
  const claudeRole = side === 'human' ? (sel.role === 'pat' ? 'brv' : 'pat') : null;
  entries.push({ name: claude.name, bot: claude, isPlayer: false, skin: claude.skin, role: claudeRole });
  for (const b of others) entries.push({ name: b.name, bot: b, isPlayer: false, skin: b.skin, role: null });
  const roles = assignRoles(entries.length, entries.filter((e) => e.role).map((e) => e.role));
  let ri = entries.filter((e) => e.role).length;
  for (const e of entries) if (!e.role) e.role = roles[ri++];
  // бойцы
  entries.forEach((e, i) => {
    const f = makeHuman(e.name, e.bot, e.isPlayer && !AUTO ? true : e.isPlayer, e.role, e.skin);
    const n = entries.length, x = (i - (n - 1) / 2) * 6;
    f.pos.set(x, 0, 26 + Math.abs(x) * 0.25); f.yaw = f.targetYaw = Math.PI;
    G.humans.push(f); G.fighters.push(f);
    if (e.isPlayer) G.player = f;
    if (!e.isPlayer || AUTO) G.brains.set(f, new HumanBrain(G, f));
  });
  const nh = G.humans.length;
  const m = new Fighter(G, {
    name: side === 'monster' ? prof.name : monsterBot.name, bot: monsterBot, isPlayer: side === 'monster',
    team: 'monster', roleId: 'monster', role: MONSTER, color: '#5f9bff', hp: MONSTER.hpPerHuman * nh, speed: MONSTER.speed, radius: MONSTER.radius, model: judgeModel,
  });
  judgeModel.root.visible = true; judgeModel.shadow.visible = true; judgeModel.club.visible = false; judgeModel.body.scale.setScalar(1.25);
  m.pos.set(0, 0, -20); m.yaw = m.targetYaw = 0;
  G.monster = m; G.fighters.push(m);
  if (side === 'monster') G.player = m;
  if (side !== 'monster' || AUTO) G.brains.set(m, new MonsterBrain(G, m));
  // старт
  G.camFocus = G.player; cam.snap = true;
  cam.yaw = side === 'monster' ? Math.PI : 0; cam.pitch = side === 'monster' ? 0.42 : 0.34;
  G.roundLeft = ROUND_TIME; G.state = 'intro'; introT = 0; specIdx = 0; G.dmgLog = {}; G.krHint = false;
  hud.setup(G); hud.show(true); hud.spectate(false);
  setupButtons(G.player);
  ui.banner(`⚖ Судья — ${m.name}`, side === 'human' ? '«Ну что ж... приговор будет суровым.» Обнулите его HP за 3:00!' : 'Убей всех людей или продержись 3:00!', 2400, '#8fc0ff');
  G.fx.ring(m.pos, 0x5f9bff, 1, 14, 0.8);
  sfx.play('spawn');
  // чат
  setTimeout(() => {
    const b = pick(G.humans.filter((h) => h.bot && h.bot.id !== 'claude'))?.bot;
    if (b) talk(b, 'start', { eventText: `начался раунд Судного дня, монстр-Судья — ${m.name}` }, true);
  }, 900);
  setTimeout(() => {
    if (side === 'monster') talk(claude, 'start', { eventText: 'раунд начался' }, true);
    else if (monsterBot && Math.random() < 0.7) talk(monsterBot, 'start', { eventText: 'ты играешь за монстра-Судью против команды людей, раунд начался' }, true);
  }, 3500);
  idleTalkT = rand(25, 40);
}

function endRound(winner, reason) {
  if (G.state !== 'fight') return;
  G.state = 'end'; endT = 0; G.timeScale = 0.3; G.winnerTeam = winner === 'humans' ? 'human' : 'monster';
  const p = G.player, win = (winner === 'humans') === (G.playerSide === 'human');
  for (const hz of G.hazards) { if (hz.kind === 'gravity') hz.release(); hz.dispose?.(); }
  G.hazards.length = 0;
  G.fx.setDark(0); G.world.setDark(0);
  if (winner === 'humans') { G.camFocus = G.monster; G.fx.flash('#ffffff', 0.7); G.fx.shake(0.6); G.fx.burst(V.set(G.monster.pos.x, 4, G.monster.pos.z), 0xffffff, 60, 18, 1, 1.2); G.fx.puff(G.monster.pos, 20, 0x8090c0, 3, 1.2, 9); sfx.play('boom'); }
  ui.banner(win ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ', reason, 2600, win ? '#ffe040' : '#ff4a5a');
  setTimeout(() => sfx.play(win ? 'win' : 'lose'), 500);
  hud.spectate(false);
  showButtons(false);
  // реплики
  const humansWon = winner === 'humans';
  const hb = G.humans.filter((h) => h.bot);
  if (hb.length) talk(pick(hb).bot, humansWon ? 'win' : 'lose', { target: G.monster.name, eventText: humansWon ? 'люди победили Судью' : 'Судья победил людей' }, true);
  if (G.monster.bot) setTimeout(() => talk(G.monster.bot, humansWon ? 'lose' : 'win', { eventText: humansWon ? 'тебя, монстра, победили люди' : 'ты, монстр, победил людей' }, true), 2500);
  else if (G.playerSide === 'monster') setTimeout(() => talk(G.botProfiles[0], humansWon ? 'win' : 'lose', { eventText: humansWon ? 'люди (и ты) победили друга-Судью' : 'друг-Судья победил вас' }, true), 2500);
  // награды
  const s = p.stats;
  let coins;
  if (G.playerSide === 'human') coins = win ? 30 + Math.min(25, Math.floor(s.dmg / 50)) + (p.dead ? 0 : 10) : 8 + Math.min(15, Math.floor(s.dmg / 80));
  else coins = win ? 45 + s.kills * 5 : 12 + s.kills * 4;
  coins += Math.min(15, Math.floor((s.heal || 0) / 40));
  if (!AUTO) {
    addCoins(coins);
    addStat('judgement', 'games', 1);
    if (win) addStat('judgement', 'wins', 1);
    if (s.kills) addStat('judgement', 'kills', s.kills);
    addStat('judgement', 'damage', Math.round(s.dmg));
    addStat('judgement', G.playerSide === 'monster' ? 'monsterGames' : 'humanGames', 1);
  }
  const elapsed = ROUND_TIME - Math.max(0, G.roundLeft);
  const result = { winner, reason, time: Math.round(elapsed), mhp: Math.max(0, Math.round(G.monster.hp)), alive: G.humans.filter((h) => !h.dead).length, coins, roles: G.humans.map((h) => h.roleId + (h.dead ? 'x' : '')).join(','), dmg: G.humans.map((h) => Math.round(h.stats.dmg)).join(','), dodged: G.monster.stats.dodged, causes: G.dmgLog, heal: G.humans.map((h) => Math.round(h.stats.heal)).join(',') };
  (window.__jd.results ||= []).push(result);
  console.log('ROUND', JSON.stringify(result));
  const rows = [G.monster, ...G.humans].map((f) => ({
    icon: f.team === 'monster' ? '💀' : `<img src="${heartDataURL(f.color, 18)}">`,
    name: f.name, role: f.team === 'monster' ? 'Судья' : f.role.name, dmg: Math.round(f.stats.dmg), heal: Math.round(f.stats.heal), kills: f.stats.kills,
    status: f.team === 'monster' ? (f.dead ? '☠' : '✔') : f.dead ? '☠' : '✔', me: f === p,
  }));
  const sub = `${winner === 'humans' ? 'Люди победили' : 'Судья победил'} за ${Math.floor(elapsed / 60)}:${String(Math.floor(elapsed % 60)).padStart(2, '0')}`;
  setTimeout(() => {
    G.state = 'results'; G.timeScale = 1;
    if (LOOP) { startRound(selection); return; }
    hud.show(false);
    resultsEl = showResults({
      win, title: reason, sub, rows, coins,
      onAgain: () => startRound(selection),
      onChange: () => openSelect(),
      onHome: () => ui.goHome(),
    });
  }, NORENDER ? 300 : 2700);
}

function openSelect() {
  clearRound(); hud.show(false); showButtons(false);
  G.state = 'menu'; G.camFocus = null;
  scene.add(judgeModel.root); scene.add(judgeModel.shadow);
  judgeModel.root.visible = true; judgeModel.root.position.set(0, 0, 0); judgeModel.root.rotation.set(0, 0, 0); judgeModel.body.scale.setScalar(1.25); judgeModel.club.visible = false;
  for (const mt of judgeModel.mats) mt.emissive.setHex(mt.userData.e0);
  judgeModel.shadow.position.set(0, 0.06, 0); judgeModel.shadow.visible = true; judgeModel.shadow.scale.setScalar(1);
  const prof = getProfile();
  selectEl = showSelect({ coins: prof.coins || 0, stats: prof.stats?.judgement || {}, sel: { ...selection }, onPlay: (sel) => { selection = sel; scene.remove(judgeModel.root); scene.remove(judgeModel.shadow); startRound(sel); } });
}

function resetPlayer() {
  const p = G.player;
  if (!p || p.dead || G.state !== 'fight' || p.grab) return;
  G.fx.after(p.pos, p.team === 'monster' ? 0x5fb4ff : p.color, 6, 0.4);
  if (p.team === 'monster') p.pos.set(0, 0, -20); else p.pos.set((Math.random() - 0.5) * 20, 0, 30);
  p.hv.set(0, 0, 0); p.kb.set(0, 0, 0); p.vy = 0; p.dashT = 0;
  cam.snap = true;
  ui.toast('Персонаж перемещён на старт');
}

// ---------- шаг симуляции ----------
function separate() {
  const fs = G.fighters;
  for (let i = 0; i < fs.length; i++) for (let j = i + 1; j < fs.length; j++) {
    const a = fs[i], b = fs[j];
    if (a.dead || b.dead || a.grab || b.grab || a.dashT > 0 || b.dashT > 0) continue;
    if (Math.abs(a.pos.y - b.pos.y) > 5) continue;
    const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z, d = Math.hypot(dx, dz), min = a.radius + b.radius;
    if (d >= min || d < 0.001) continue;
    const push = (min - d), wa = a.team === 'monster' ? 0.15 : b.team === 'monster' ? 0.85 : 0.5;
    a.pos.x -= (dx / d) * push * wa; a.pos.z -= (dz / d) * push * wa;
    b.pos.x += (dx / d) * push * (1 - wa); b.pos.z += (dz / d) * push * (1 - wa);
  }
}

function step(rdt) {
  let dt = rdt * G.timeScale;
  if (G.hitStopT > 0) { G.hitStopT -= rdt; dt *= 0.06; }
  G.time += dt;
  const active = G.state === 'fight' || G.state === 'intro' || G.state === 'end' || G.state === 'results';
  if (active && G.monster) {
    if (G.state === 'intro') {
      introT += rdt;
      if (introT > 2.5) {
        G.state = 'fight'; ui.banner('БОЙ!', '', 700, '#ff4a5a'); sfx.play('charge');
        if (!AUTO) setTimeout(() => G.state === 'fight' && ui.toast(G.playerSide === 'human'
          ? 'Полоса на полу — будущий луч, уходи вбок! Белые кости — прыгай, синие — стой, оранжевые — двигайся.'
          : 'Черепа, кости и гравитация наводятся сами. Окружили — телепорт (Q). Ульта копится со временем и уроном.', 5200), 900);
      }
    }
    playerMoveInput();
    if (G.state === 'fight') for (const [, b] of G.brains) b.update(dt);
    else for (const f of G.fighters) f.moveDir.set(0, 0, 0);
    for (const f of G.fighters) f.update(dt);
    flushBuffered();
    separate();
    for (let i = 0; i < G.hazards.length; i++) { if (!G.hazards[i].update(dt)) { G.hazards.splice(i, 1); i--; } }
    updateProjectiles(G, dt);
    bonesBegin(G); for (const hz of G.hazards) hz.draw?.(G); bonesEnd(G);
    if (G.state === 'fight') {
      G.roundLeft -= dt;
      if (G.monster.dead) endRound('humans', 'Судья повержен!');
      else if (G.humans.every((h) => h.dead)) endRound('monster', 'Все люди пали');
      else if (G.roundLeft <= 0) { G.roundLeft = 0; endRound('monster', 'Судья продержался до конца'); }
      // наблюдение
      const p = G.player;
      if (p.dead && p.team === 'human') {
        const alive = G.humans.filter((h) => !h.dead);
        const t = alive.length ? alive[specIdx % alive.length] : G.monster;
        if (G.camFocus !== t) { G.camFocus = t; }
        if (p.deadT > 1.2) hud.spectate(true, t.name);
      } else if (G.camFocus !== p && G.state === 'fight') { G.camFocus = p; hud.spectate(false); }
      idleTalkT -= dt;
      if (idleTalkT <= 0) {
        idleTalkT = rand(28, 50);
        const b = pick(G.botProfiles.filter((x) => !x.dead));
        if (b) talk(b, 'idle', { eventText: `идёт раунд Судного дня, осталось ${Math.ceil(G.roundLeft)} секунд, у Судьи ${Math.ceil(G.monster.hp)} HP` });
      }
    }
    if (G.state === 'end') endT += rdt;
  } else if (G.state === 'menu') {
    const p = judgeModel.parts;
    p.armL.rotation.set(0, 0, 0); p.armR.rotation.set(0, 0, 0); p.legL.rotation.set(0, 0, 0); p.legR.rotation.set(0, 0, 0);
    animateAvatar(judgeModel, 'idle', G.time);
    judgeModel.root.rotation.y = Math.sin(G.time * 0.3) * 0.4;
    judgeModel.eye.scale.setScalar(0.6 + Math.sin(G.time * 5) * 0.1);
  }
  G.world.update(G.time, dt);
  G.fx.update(dt, camera);
  updateCamera(rdt);
  hud.update(G, rdt);
  updateButtons();
}
hud.onSpecNext(() => { specIdx++; });

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

window.__jd = { stepMs: 0, renderMs: 0, G, renderer, startRound: (s) => { selectEl?.remove(); startRound(s || selection); }, results: [], ctl, doAction };
ui.loading(false);
if (AUTO || params.has('side')) {
  const s = { side: params.get('side') || 'human', role: params.get('role') || 'det' };
  selection = s; startRound(s);
} else openSelect();
requestAnimationFrame(frame);

// Меню «Бросменс»: белый лист, друзья со скинами, плитки игр, личные чаты, настройки и аватар.
import { drawAvatar } from '../shared/avatar.js';
import { FRIENDS, pick, rand } from '../shared/bots.js';
import { aiEnabled, aiReply, aiUsedToday, personaPrompt } from '../shared/ai.js';
import { getProfile, saveProfile, getApiKey, setApiKey } from '../shared/profile.js';
import { sfx } from '../shared/sfx.js';
import { hostRoom, joinRoom, makeCode, netQuery } from '../shared/net.js';

const $ = (id) => document.getElementById(id);

// ---------- игры ----------
const GAMES = [
  { id: 'jjs', title: 'Jujutsu Brosmens', short: 'Jujutsu', href: 'games/jjs/index.html', like: 94, base: 18400, draw: thumbJJS },
  { id: 'judgement', title: 'Судный День', short: 'Судный День', href: 'games/judgement/index.html', like: 91, base: 9600, draw: thumbJudgement },
  { id: 'roworld', title: 'BroWorld [World PvP]', short: 'BroWorld', href: 'games/roworld/index.html', like: 89, base: 5200, draw: thumbWorld },
];

function fmt(n) { return n >= 1000 ? (n / 1000).toFixed(1).replace('.0', '') + 'K' : String(n); }

function renderGames() {
  const box = $('games');
  box.innerHTML = '';
  for (const g of GAMES) {
    const b = document.createElement('button');
    b.className = 'game';
    const c = document.createElement('canvas'); c.width = c.height = 360;
    const th = document.createElement('div'); th.className = 'thumb'; th.appendChild(c);
    g.playing = Math.round(g.base * rand(0.85, 1.15));
    b.append(th);
    b.insertAdjacentHTML('beforeend', `<span class="t">${g.title}</span><span class="m"><span>👍 ${g.like}%</span><span>👥 ${fmt(g.playing)}</span></span>`);
    g.draw(c.getContext('2d'), 360, 360);
    b.onclick = () => launch(g);
    box.appendChild(b);
  }
}

// игры, где уже есть онлайн с другом (остальные запускаются как обычно)
const ONLINE_GAMES = new Set([]);

function launch(g, withFriend) {
  if (net.room && net.room.connected()) {
    if (!net.room.isHost) return toastNet('Игру выбирает тот, кто создал комнату');
    if (!ONLINE_GAMES.has(g.id)) {
      const ready = [...ONLINE_GAMES].map((id) => GAMES.find((x) => x.id === id).short);
      return toastNet(ready.length ? `В «${g.short}» онлайна пока нет. Уже можно: ${ready.join(', ')}` : 'Онлайн в играх появится в следующей версии — первым будет Jujutsu');
    }
    net.room.send('start', { game: g.id });
    return go(g, netQuery('host', net.code));
  }
  go(g, withFriend ? '?with=' + withFriend : '');
}

function go(g, query) {
  sfx.play('ui');
  try {
    sessionStorage.setItem('brosmens.lastGame', JSON.stringify({ id: g.id, title: g.title, stats: getProfile().stats[g.id] || {}, coins: getProfile().coins }));
  } catch {}
  location.href = g.href + query;
}

// ---------- друзья ----------
const friendEls = {};
function renderFriends() {
  const box = $('friends');
  box.innerHTML = '';
  for (const f of [FRIENDS[0], ...realFriends(), ...FRIENDS.slice(1)]) {
    const b = document.createElement('button');
    b.className = 'friend';
    b.innerHTML = '<div class="sq"><canvas width="168" height="168"></canvas><i class="dot"></i></div><span class="badge"></span><span class="nm"></span><span class="st"></span>';
    b.querySelector('.nm').textContent = f.name;
    drawAvatar(b.querySelector('canvas'), f.skin, { headOnly: true });
    b.onclick = () => openDM(f);
    friendEls[f.id] = b;
    box.appendChild(b);
    updateFriend(f);
  }
}

function updateFriend(f) {
  const el = friendEls[f.id];
  if (!el) return;
  el.classList.toggle('online', f.status === 'онлайн');
  el.classList.toggle('ingame', f.status.startsWith('в '));
  el.querySelector('.st').textContent = f.status;
  const n = unread[f.id] || 0;
  el.classList.toggle('unread', n > 0);
  el.querySelector('.badge').textContent = n;
  $('online-count').textContent = FRIENDS.filter((x) => x.status !== 'не в сети').length + realFriends().filter((x) => x.status !== 'не в сети').length + ' в сети';
}

// друзья «живут»: заходят в игры, выходят
function lifeTick() {
  const f = pick(FRIENDS.slice(1));
  const prev = f.status;
  const r = Math.random();
  f.status = r < 0.45 ? 'в ' + pick(GAMES).short : r < 0.8 ? 'онлайн' : 'не в сети';
  if (f.status !== prev) {
    updateFriend(f);
    if (f.status.startsWith('в ')) notify(f, `зашёл(ла) ${f.status}`, true);
  }
  setTimeout(lifeTick, rand(18000, 40000));
}

// ---------- уведомления ----------
let notifyT = 0;
function notify(friend, text, quiet = false) {
  const n = $('notify');
  n.innerHTML = '<canvas width="80" height="80"></canvas><div><b></b><span></span></div>';
  drawAvatar(n.querySelector('canvas'), friend.skin, { headOnly: true });
  n.querySelector('b').textContent = friend.name;
  n.querySelector('span').textContent = text;
  n.onclick = () => { n.classList.remove('show'); openDM(friend); };
  n.classList.add('show');
  if (!quiet) sfx.play('coin', { vol: 0.6 });
  clearTimeout(notifyT);
  notifyT = setTimeout(() => n.classList.remove('show'), 4500);
}

// ---------- личные сообщения ----------
const unread = {};
let dmFriend = null;
const dmKey = (id) => 'brosmens.dm.' + id;
const loadDM = (id) => { try { return JSON.parse(localStorage.getItem(dmKey(id))) || []; } catch { return []; } };
const saveDM = (id, list) => { try { localStorage.setItem(dmKey(id), JSON.stringify(list.slice(-60))); } catch {} };

function addMsg(friend, role, text) {
  const list = loadDM(friend.id);
  list.push({ role, text, at: Date.now() });
  saveDM(friend.id, list);
  if (dmFriend && dmFriend.id === friend.id) renderDMLog();
  else if (role === 'them') { unread[friend.id] = (unread[friend.id] || 0) + 1; updateFriend(friend); notify(friend, text); }
}

function renderDMLog() {
  const log = $('dm-log');
  log.innerHTML = '';
  for (const m of loadDM(dmFriend.id)) {
    const d = document.createElement('div');
    d.className = 'msg ' + m.role;
    d.textContent = m.text;
    log.appendChild(d);
  }
  if (typing.has(dmFriend.id)) {
    const d = document.createElement('div'); d.className = 'msg them typing'; d.textContent = 'печатает…'; log.appendChild(d);
  }
  log.scrollTop = log.scrollHeight;
}

function openDM(f) {
  dmFriend = f;
  unread[f.id] = 0;
  updateFriend(f);
  drawAvatar($('dm-ava'), f.skin, { headOnly: true });
  $('dm-name').textContent = f.name;
  $('dm-status').textContent = f.status + (f.ai ? ' · ИИ-друг' : f.real ? ' · настоящий друг' : '');
  $('dm-play').hidden = !!f.real;
  $('dm').hidden = false;
  renderDMLog();
  sfx.play('ui');
}
$('dm-close').onclick = () => { $('dm').hidden = true; dmFriend = null; };
$('dm-play').onclick = () => {
  const f = dmFriend;
  const card = document.createElement('div');
  card.className = 'panel';
  card.innerHTML = `<div class="card"><div class="card-head"><b>Во что играем с ${f.name}?</b><button class="icon-btn">✕</button></div><div class="pick-game"></div></div>`;
  const grid = card.querySelector('.pick-game');
  for (const g of GAMES) {
    const b = document.createElement('button'); b.textContent = g.title;
    b.onclick = () => { addMsg(f, 'me', `го в ${g.title}`); launch(g, f.id); };
    grid.appendChild(b);
  }
  card.querySelector('.icon-btn').onclick = () => card.remove();
  document.body.appendChild(card);
};

const typing = new Set();
$('dm-form').onsubmit = (e) => {
  e.preventDefault();
  const input = $('dm-input');
  const text = input.value.trim();
  if (!text || !dmFriend) return;
  input.value = '';
  addMsg(dmFriend, 'me', text);
  if (dmFriend.real) {
    if (net.room && net.room.connected()) net.room.send('dm', { text });
    else toastNet('Друг сейчас не в комнате — сообщение не доставлено');
    return;
  }
  respond(dmFriend);
};

async function respond(f) {
  if (typing.has(f.id)) return;
  if (f.status === 'не в сети' && !f.ai) return; // ответит, когда зайдёт
  await new Promise((r) => setTimeout(r, rand(500, 1500)));
  typing.add(f.id);
  if (dmFriend === f) renderDMLog();
  const history = loadDM(f.id).map((m) => ({ role: m.role === 'me' ? 'user' : 'assistant', content: m.text }));
  const started = performance.now();
  let reply = await aiReply({ system: personaPrompt(f) + contextLine(), history, maxTokens: 300 });
  if (!reply) reply = scriptedDM(f, history[history.length - 1]?.content || '');
  const wait = Math.max(0, 700 + reply.length * 40 - (performance.now() - started));
  await new Promise((r) => setTimeout(r, Math.min(wait, 5000)));
  typing.delete(f.id);
  // иногда живые люди пишут двумя сообщениями
  const parts = !f.ai && reply.length > 40 && Math.random() < 0.4 ? splitTwo(reply) : [reply];
  addMsg(f, 'them', parts[0]);
  if (parts[1]) setTimeout(() => addMsg(f, 'them', parts[1]), rand(900, 2200));
}

function splitTwo(s) {
  const i = s.search(/[,.!?]\s/);
  return i > 8 && i < s.length - 6 ? [s.slice(0, i + 1).replace(/[,]$/, ''), s.slice(i + 2)] : [s];
}

function contextLine() {
  const p = getProfile();
  const h = new Date().getHours();
  const tod = h < 6 ? 'ночь' : h < 12 ? 'утро' : h < 18 ? 'день' : 'вечер';
  const stats = Object.entries(p.stats).map(([g, s]) => `${g}: ${Object.entries(s).map(([k, v]) => k + ' ' + v).join(', ')}`).join('; ');
  return `\nСобеседника зовут ${p.name}. Сейчас ${tod}. Игры в приложении: ${GAMES.map((g) => g.title).join(', ')}. Его статистика: ${stats || 'пока пусто'}. Это личная переписка, можно отвечать чуть длиннее (до 2–3 коротких предложений).`;
}

const CLAUDE_LINES = {
  greet: ['йо! как ты? 👋', 'привеет, рад тебя видеть)', 'о, ты зашёл! я как раз скучал', 'хей! го катку?'],
  invite: ['го в Jujutsu Brosmens? я за Годжо, ты за Сукуну 😏', 'давай в Судный День, я буду тебя хилить', 'го в BroWorld, построим империю вместе', 'хочу реванш в Jujutsu, в прошлый раз лагало 😅'],
  ai: ['ну да, я ИИ — Клод. но играть с тобой мне реально нравится', 'честно? я ИИ-друг в этом приложении. но болею я за тебя по-настоящему'],
  how: ['да норм, жду тебя в игре)', 'отлично! особенно когда ты онлайн', 'нормально, тренировал комбо'],
  thanks: ['всегда пожалуйста 🙌', 'да не за что, бро', 'обращайся'],
  generic: ['ахах согл', 'интересно, расскажи ещё', 'понял тебя)', 'жиза', 'ну ты легенда', 'хаха, а потом что?', 'звучит круто', 'го лучше катку, там и обсудим'],
};
const FRIEND_LINES = {
  greet: ['прив', 'здарова', 'ку', 'хай)'],
  invite: ['го в jujutsu 1на1', 'го катку', 'зайди в судный день', 'го в броворлд я там империю строю'],
  generic: ['ахах', 'лол', 'ну да', 'хз', 'го катку лучше', 'ок', 'согл', 'а ты где', 'щас занят, позже', 'мне мама телефон отбирает скоро'],
};

function scriptedDM(f, text) {
  const L = f.ai ? CLAUDE_LINES : FRIEND_LINES;
  const t = text.toLowerCase();
  if (f.ai && /бот|ии\b|ai\b|робот|человек|настоящ/.test(t)) return pick(CLAUDE_LINES.ai);
  if (/прив|здаро|хай|ку\b|йо\b|hello|hi\b/.test(t)) return pick(L.greet);
  if (f.ai && /как дела|как ты/.test(t)) return pick(CLAUDE_LINES.how);
  if (f.ai && /спасиб|спс/.test(t)) return pick(CLAUDE_LINES.thanks);
  if (/го|играть|катк|игр/.test(t)) return pick(L.invite);
  if (!f.ai && Math.random() < f.toxic * 0.6) return pick(['нуб', 'ты все равно сливаешь', 'изи было бы', 'не пиши мне пока не апнешь лвл']);
  return pick(L.generic);
}

// Клод пишет первым: при входе и после игры
let inviteT = 0;
async function claudeOpener() {
  const claude = FRIENDS[0];
  let last = null;
  try { last = JSON.parse(sessionStorage.getItem('brosmens.lastGame')); sessionStorage.removeItem('brosmens.lastGame'); } catch {}
  let situation, fallback;
  if (last) {
    const now = getProfile().stats[last.id] || {};
    const diff = Object.entries(now).map(([k, v]) => [k, v - (last.stats[k] || 0)]).filter(([, d]) => d > 0);
    const coins = getProfile().coins - (last.coins || 0);
    situation = `Пользователь только что вышел из игры «${last.title}». Изменения статистики: ${diff.map(([k, d]) => k + ' +' + d).join(', ') || 'нет'}; монет +${coins}. Прокомментируй как друг, игравший рядом.`;
    fallback = diff.length ? pick(['ну ты дал жару! 🔥', 'видел твой матч, красиво сыграл', 'неплохо! ещё катку?']) : pick(['ничего, в следующий раз затащим', 'было близко, го ещё раз', 'это разминка была, да? 😄']);
  } else {
    const lastMsg = loadDM(claude.id).slice(-1)[0];
    if (lastMsg && Date.now() - lastMsg.at < 10 * 60 * 1000) return;
    situation = 'Пользователь только что открыл приложение. Напиши ему первым: поздоровайся и предложи во что-то сыграть.';
    fallback = pick(CLAUDE_LINES.greet);
    inviteT = setTimeout(() => addMsg(claude, 'them', pick(CLAUDE_LINES.invite)), rand(9000, 12000));
  }
  await new Promise((r) => setTimeout(r, last ? 1500 : rand(3000, 6000)));
  const history = [...loadDM(claude.id).map((m) => ({ role: m.role === 'me' ? 'user' : 'assistant', content: m.text })), { role: 'user', content: `[служебно, не цитируй: ${situation}]` }];
  const live = await aiReply({ system: personaPrompt(claude) + contextLine(), history, maxTokens: 200 });
  if (live) clearTimeout(inviteT);
  const text = live || fallback;
  addMsg(claude, 'them', text);
}

// иногда пишут другие друзья
function friendPing() {
  const f = pick(FRIENDS.slice(1).filter((x) => x.status !== 'не в сети'));
  if (f && !dmFriend) addMsg(f, 'them', pick([...FRIEND_LINES.invite, ...FRIEND_LINES.greet]));
  setTimeout(friendPing, rand(70000, 150000));
}

// ---------- профиль / настройки / аватар ----------
function renderMe() {
  const p = getProfile();
  drawAvatar($('me-canvas'), p.skin, { headOnly: true });
  $('coins').textContent = '🪙 ' + p.coins;
}

function openSettings() {
  const p = getProfile();
  $('set-name').value = p.name;
  $('set-tox').value = p.settings.toxicity;
  $('set-tox-v').textContent = Math.round(p.settings.toxicity * 100) + '%';
  $('set-sound').checked = p.settings.sound;
  $('set-key').value = getApiKey();
  $('set-limit').value = p.settings.aiDailyLimit;
  $('set-used').textContent = aiEnabled() ? `Ключ введён. ИИ-сообщений сегодня: ${aiUsedToday()}.` : 'Ключ не введён — работают заготовки.';
  $('settings').hidden = false;
}
$('set-tox').oninput = (e) => ($('set-tox-v').textContent = Math.round(e.target.value * 100) + '%');
$('set-save').onclick = () => {
  const p = getProfile();
  p.name = $('set-name').value.trim().slice(0, 20) || 'Игрок';
  p.settings.toxicity = +$('set-tox').value;
  p.settings.sound = $('set-sound').checked;
  p.settings.aiDailyLimit = Math.max(0, Math.min(2000, +$('set-limit').value || 0));
  saveProfile(p);
  setApiKey($('set-key').value);
  $('settings').hidden = true;
  renderMe();
  sfx.play('ui');
};
$('btn-settings').onclick = openSettings;
document.querySelectorAll('[data-close]').forEach((b) => (b.onclick = () => (b.closest('.panel').hidden = true)));

const PALETTE = {
  skin: ['#ffdbac', '#f2c9a0', '#f1c27d', '#e0ac7e', '#c68642', '#8d5524', '#5c3a21'],
  shirt: ['#e53935', '#2f6fed', '#43a047', '#fdd835', '#8e24aa', '#fb8c00', '#00acc1', '#212121', '#ffffff', '#ec407a', '#d97757', '#3949ab'],
  pants: ['#23262e', '#1a237e', '#4e342e', '#37474f', '#5d4037', '#1b5e20', '#880e4f', '#9e9e9e'],
  hair: ['#1b1b1b', '#2b1d10', '#6d4c41', '#f9a825', '#d84315', '#eeeeee', '#ff80ab', '#5e35b1', '#00897b'],
};
const LABELS = { skin: 'Кожа', shirt: 'Футболка', pants: 'Штаны', hair: 'Волосы' };
let draftSkin = null;

function openAvatar() {
  draftSkin = { ...getProfile().skin };
  const opts = $('ava-opts');
  opts.innerHTML = '';
  for (const key of Object.keys(PALETTE)) {
    const row = document.createElement('div'); row.className = 'opt-row';
    row.innerHTML = `<b>${LABELS[key]}</b><div class="swatches"></div>`;
    for (const c of PALETTE[key]) {
      const s = document.createElement('button'); s.className = 'sw'; s.style.background = c;
      s.onclick = () => { draftSkin[key] = c; refreshAvatar(); };
      s.dataset.k = key; s.dataset.c = c;
      row.lastChild.appendChild(s);
    }
    opts.appendChild(row);
  }
  const chips = (label, key, values) => {
    const row = document.createElement('div'); row.className = 'opt-row';
    row.innerHTML = `<b>${label}</b><div class="swatches"></div>`;
    values.forEach(([v, name]) => {
      const c = document.createElement('button'); c.className = 'chip'; c.textContent = name;
      c.dataset.k = key; c.dataset.c = v;
      c.onclick = () => { draftSkin[key] = v; refreshAvatar(); };
      row.lastChild.appendChild(c);
    });
    opts.appendChild(row);
  };
  chips('Причёска', 'hairStyle', [['short', 'короткая'], ['spiky', 'ёжик'], ['long', 'длинная'], ['cap', 'кепка'], ['none', 'лысый']]);
  chips('Лицо', 'face', [[0, '🙂'], [1, '😊'], [2, '☺️'], [3, '😐'], [4, '😏']]);
  refreshAvatar();
  $('avatar').hidden = false;
}
function refreshAvatar() {
  drawAvatar($('ava-preview'), draftSkin);
  document.querySelectorAll('#ava-opts [data-k]').forEach((el) => el.classList.toggle('on', String(draftSkin[el.dataset.k]) === el.dataset.c));
}
$('ava-save').onclick = () => {
  const p = getProfile();
  p.skin = { ...draftSkin, face: +draftSkin.face };
  saveProfile(p);
  $('avatar').hidden = true;
  renderMe();
};
$('btn-me').onclick = openAvatar;

// ---------- миниатюры игр (рисуются кодом) ----------
function title(g, w, h, big, small, color = '#fff') {
  g.textAlign = 'center';
  g.lineJoin = 'round';
  g.font = `900 ${w * 0.11}px system-ui, sans-serif`;
  g.lineWidth = w * 0.025; g.strokeStyle = '#000';
  g.strokeText(big, w / 2, h * 0.84); g.fillStyle = color; g.fillText(big, w / 2, h * 0.84);
  if (small) {
    g.font = `800 ${w * 0.06}px system-ui, sans-serif`;
    g.lineWidth = w * 0.015;
    g.strokeText(small, w / 2, h * 0.93); g.fillStyle = '#fff'; g.fillText(small, w / 2, h * 0.93);
  }
}
function blocky(g, x, y, u, skin, pose = 0) {
  const b = (c, bx, by, bw, bh, rot = 0) => {
    g.save(); g.translate(x + bx * u, y + by * u); g.rotate(rot);
    g.fillStyle = c; g.fillRect(0, 0, bw * u, bh * u);
    g.fillStyle = 'rgba(0,0,0,.18)'; g.fillRect(bw * u * 0.8, 0, bw * u * 0.2, bh * u);
    g.restore();
  };
  b(skin.pants, -1, 3.3, 1, 2, pose * 0.3); b(skin.pants, 0, 3.3, 1, 2, -pose * 0.2);
  b(skin.shirt, -1, 1.3, 2, 2);
  b(skin.shirt, -2, 1.3, 1, 2, pose * 0.6); b(skin.shirt, 1, 1.3, 1, 2, -pose * 1.2);
  b(skin.skin, -0.6, 0, 1.2, 1.2);
  if (skin.hair) b(skin.hair, -0.65, -0.25, 1.3, 0.4);
  if (skin.band) b(skin.band, -0.65, 0.35, 1.3, 0.25);
}
function thumbJJS(g, w, h) {
  const bg = g.createLinearGradient(0, 0, w, h);
  bg.addColorStop(0, '#1b1036'); bg.addColorStop(0.55, '#3c1a6e'); bg.addColorStop(1, '#0b1a3a');
  g.fillStyle = bg; g.fillRect(0, 0, w, h);
  for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(255,255,255,${Math.random() * 0.6})`; g.fillRect(Math.random() * w, Math.random() * h * 0.6, 2, 2); }
  const orb = (x, y, r, c) => {
    const gr = g.createRadialGradient(x, y, 0, x, y, r);
    gr.addColorStop(0, '#fff'); gr.addColorStop(0.25, c); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 7); g.fill();
  };
  orb(w * 0.3, h * 0.36, w * 0.24, '#3aa0ff');
  orb(w * 0.72, h * 0.4, w * 0.2, '#ff3355');
  g.fillStyle = '#4a4a55'; g.fillRect(0, h * 0.72, w, h * 0.28);
  blocky(g, w * 0.3, h * 0.33, w * 0.07, { skin: '#e0ac7e', shirt: '#0f766e', pants: '#1f2937', hair: '#1b1b1b', band: '#f59e0b' }, -0.4);
  g.save(); g.scale(-1, 1);
  blocky(g, -w * 0.72, h * 0.33, w * 0.07, { skin: '#f2c9a0', shirt: '#7c2d12', pants: '#2a2a2a', hair: '#facc15' }, -0.6);
  g.restore();
  // разрезы
  g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineWidth = 3;
  for (let i = 0; i < 4; i++) { g.beginPath(); g.moveTo(w * (0.5 + i * 0.05), h * 0.15); g.lineTo(w * (0.62 + i * 0.05), h * 0.62); g.stroke(); }
  title(g, w, h, 'JUJUTSU', 'BROSMENS', '#b9a3ff');
}
function thumbJudgement(g, w, h) {
  const bg = g.createLinearGradient(0, 0, 0, h);
  bg.addColorStop(0, '#050b2e'); bg.addColorStop(1, '#122a7a');
  g.fillStyle = bg; g.fillRect(0, 0, w, h);
  for (let i = 0; i < 60; i++) { g.fillStyle = `rgba(200,220,255,${Math.random() * 0.7})`; g.fillRect(Math.random() * w, Math.random() * h * 0.7, 2, 2); }
  // луч
  const beam = g.createLinearGradient(0, h * 0.42, 0, h * 0.58);
  beam.addColorStop(0, 'rgba(120,200,255,0)'); beam.addColorStop(0.5, '#fff'); beam.addColorStop(1, 'rgba(120,200,255,0)');
  g.fillStyle = beam; g.fillRect(w * 0.45, h * 0.42, w * 0.55, h * 0.16);
  // череп-бластер
  const sx = w * 0.3, sy = h * 0.5, s = w * 0.2;
  g.fillStyle = '#f4f6ff';
  g.beginPath(); g.ellipse(sx, sy - s * 0.2, s, s * 0.8, 0, 0, 7); g.fill();
  g.fillRect(sx - s * 0.2, sy + s * 0.2, s * 1.3, s * 0.5);
  g.fillStyle = '#0a0f2a';
  g.beginPath(); g.ellipse(sx - s * 0.4, sy - s * 0.25, s * 0.25, s * 0.28, 0, 0, 7); g.fill();
  g.beginPath(); g.ellipse(sx + s * 0.35, sy - s * 0.25, s * 0.25, s * 0.28, 0, 0, 7); g.fill();
  g.fillStyle = '#4ff3ff'; g.beginPath(); g.arc(sx + s * 0.35, sy - s * 0.25, s * 0.1, 0, 7); g.fill();
  g.fillStyle = '#0a0f2a';
  for (let i = 0; i < 5; i++) g.fillRect(sx - s * 0.1 + i * s * 0.25, sy + s * 0.25, s * 0.08, s * 0.4);
  title(g, w, h, 'СУДНЫЙ ДЕНЬ', 'Стань сильнейшим!', '#9fdcff');
}
function thumbWorld(g, w, h) {
  g.fillStyle = '#1f6fb2'; g.fillRect(0, 0, w, h);
  for (let i = 0; i < 9; i++) {
    g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 2;
    g.beginPath(); g.moveTo(0, h * (i / 9)); g.bezierCurveTo(w * 0.3, h * (i / 9) + 8, w * 0.6, h * (i / 9) - 8, w, h * (i / 9)); g.stroke();
  }
  const colors = ['#e53935', '#43a047', '#fdd835', '#8e24aa', '#fb8c00', '#00acc1'];
  let seed = 7; const r = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let k = 0; k < 6; k++) {
    const cx = w * (0.15 + r() * 0.7), cy = h * (0.1 + r() * 0.55), rad = w * (0.1 + r() * 0.1);
    g.fillStyle = '#d7c79a';
    g.beginPath();
    for (let a = 0; a < 6.28; a += 0.4) { const rr = rad * (0.7 + r() * 0.5); g.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr); }
    g.closePath(); g.fill();
    g.fillStyle = colors[k] + '99'; g.fill();
    g.strokeStyle = colors[k]; g.lineWidth = 3; g.stroke();
    g.fillStyle = '#fff'; g.font = `800 ${w * 0.045}px system-ui`; g.textAlign = 'center'; g.fillText(Math.floor(r() * 90 + 10), cx, cy);
  }
  title(g, w, h, 'BroWorld', '[World PvP]', '#ffe08a');
}

// ---------- онлайн с другом (комната по коду) ----------
const net = { room: null, code: '', mode: '' };
const NETF_KEY = 'brosmens.netfriends';

function realFriends() {
  try { return JSON.parse(localStorage.getItem(NETF_KEY)) || []; } catch { return []; }
}
function saveRealFriend(p) {
  const list = realFriends().filter((f) => f.name !== p.name);
  list.unshift({ id: 'net_' + p.name, name: p.name, skin: p.skin, real: true, status: 'в комнате' });
  try { localStorage.setItem(NETF_KEY, JSON.stringify(list.slice(0, 8))); } catch {}
}
function setRealStatus(name, status) {
  const list = realFriends();
  const f = list.find((x) => x.name === name);
  if (f) { f.status = status; try { localStorage.setItem(NETF_KEY, JSON.stringify(list)); } catch {} }
}
function toastNet(text) {
  notify({ name: '🌐 Онлайн', skin: getProfile().skin }, text, true);
  $('notify').onclick = () => $('notify').classList.remove('show');
}

function attachRoom(room) {
  net.room = room;
  room.onPeer((p) => {
    saveRealFriend(p);
    renderFriends();
    renderNet();
    sfx.play('spawn');
    toastNet(`${p.name} в комнате ${net.code}!`);
  });
  room.onLeave((p) => {
    if (p.name) setRealStatus(p.name, 'не в сети');
    renderFriends();
    renderNet();
  });
  room.on('dm', (d, from) => {
    const p = room.peers.get(from);
    const f = p && realFriends().find((x) => x.name === p.name);
    if (f) addMsg(f, 'them', String(d.text).slice(0, 300));
  });
  room.on('start', (d) => {
    const g = GAMES.find((x) => x.id === d.game);
    if (g) go(g, netQuery('guest', net.code));
  });
}

async function createRoom(code = makeCode()) {
  net.code = code; net.mode = 'host';
  renderNet('Создаю комнату…');
  try {
    attachRoom(await hostRoom(code, 'lobby'));
    saveNet();
    renderNet();
  } catch (e) {
    console.warn(e);
    net.room = null;
    renderNet(e?.type === 'unavailable-id' ? 'Комната с таким кодом уже занята — создай новую' : 'Нет связи с сервером онлайна. Проверь интернет');
  }
}

async function enterRoom(code) {
  code = code.trim().toUpperCase();
  if (code.length !== 4) return renderNet('Код — 4 символа');
  net.code = code; net.mode = 'guest';
  renderNet('Подключаюсь к ' + code + '…');
  try {
    attachRoom(await joinRoom(code, 'lobby', { timeoutMs: 20000 }));
    saveNet();
    renderNet();
  } catch (e) {
    console.warn(e);
    net.room = null;
    renderNet('Не получилось подключиться. Проверь код и что друг в меню с открытой комнатой');
  }
}

function leaveRoom() {
  net.room?.close();
  net.room = null; net.code = ''; net.mode = '';
  try { sessionStorage.removeItem('brosmens.net'); } catch {}
  renderNet();
}
function saveNet() {
  try { sessionStorage.setItem('brosmens.net', JSON.stringify({ code: net.code, mode: net.mode })); } catch {}
}

let netPanel = null;
function renderNet(status = '') {
  $('btn-net').classList.toggle('on', !!(net.room && net.room.connected()));
  if (!netPanel || netPanel.hidden) return;
  const body = netPanel.querySelector('.net-body');
  const peers = net.room ? [...net.room.peers.values()] : [];
  if (!net.room) {
    body.innerHTML = `<p class="hint">Играй с братом или другом: у обоих должно быть установлено «Бросменс». Лучше всего — в одном Wi-Fi.</p>
      <button class="btn" id="net-create">Создать комнату</button>
      <div class="net-join"><input id="net-code" maxlength="4" placeholder="КОД" autocomplete="off"><button class="btn" id="net-enter">Войти</button></div>
      ${status ? `<p class="net-status">${status}</p>` : ''}`;
    body.querySelector('#net-create').onclick = () => createRoom();
    body.querySelector('#net-enter').onclick = () => enterRoom(body.querySelector('#net-code').value);
    body.querySelector('#net-code').onkeydown = (e) => { if (e.key === 'Enter') enterRoom(e.target.value); };
    return;
  }
  const who = peers.map((p) => `<span class="net-peer"><canvas width="64" height="64" data-skin='${JSON.stringify(p.skin || {}).replace(/'/g, '')}'></canvas>${(p.name || '').replace(/[<>&]/g, '')}</span>`).join('');
  body.innerHTML = `<div class="net-code">${net.code}</div>
    <p class="net-status">${status || (net.room.isHost
      ? (peers.length ? 'Друг в комнате! Нажми на игру — вы зайдёте вместе' : 'Скажи другу этот код и жди…')
      : (peers.length ? 'Ты в комнате. Игру выбирает создатель комнаты' : 'Связь потеряна, ждём…'))}</p>
    <div class="net-peers">${who}</div>
    <p class="hint">Пинг: ${net.room.ping || '—'} мс · Онлайн пока работает в: ${[...ONLINE_GAMES].map((id) => GAMES.find((g) => g.id === id).short).join(', ') || 'скоро'}</p>
    <button class="btn gray" id="net-leave">Выйти из комнаты</button>`;
  body.querySelectorAll('canvas[data-skin]').forEach((c) => { try { drawAvatar(c, JSON.parse(c.dataset.skin), { headOnly: true }); } catch {} });
  body.querySelector('#net-leave').onclick = leaveRoom;
}

function openNet() {
  if (!netPanel) {
    netPanel = document.createElement('div');
    netPanel.className = 'panel';
    netPanel.innerHTML = `<div class="card"><div class="card-head"><b>🌐 Онлайн с другом</b><button class="icon-btn">✕</button></div><div class="net-body"></div></div>`;
    netPanel.querySelector('.icon-btn').onclick = () => (netPanel.hidden = true);
    document.body.appendChild(netPanel);
  }
  netPanel.hidden = false;
  renderNet();
}
$('btn-net').onclick = openNet;
setInterval(() => netPanel && !netPanel.hidden && net.room && renderNet(), 2500);

// вернулись из игры — восстанавливаем комнату
try {
  const saved = JSON.parse(sessionStorage.getItem('brosmens.net'));
  if (saved?.code) (saved.mode === 'host' ? createRoom(saved.code) : enterRoom(saved.code));
} catch {}

// ---------- старт ----------
renderMe();
renderGames();
renderFriends();
setTimeout(lifeTick, rand(8000, 15000));
setTimeout(friendPing, rand(40000, 80000));
claudeOpener();
setInterval(() => {
  for (const g of GAMES) g.playing = Math.max(100, Math.round(g.playing * rand(0.985, 1.015)));
  document.querySelectorAll('.game .m span:last-child').forEach((el, i) => (el.textContent = '👥 ' + fmt(GAMES[i].playing)));
}, 5000);

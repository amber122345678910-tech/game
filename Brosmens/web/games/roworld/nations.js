// Нации: названия из имён лидеров («Кирилстан», «Димония»), цвета, флаги (рисуются на canvas).
const TR = [
  ['shch', 'щ'], ['sch', 'щ'], ['yo', 'ё'], ['yu', 'ю'], ['ya', 'я'], ['zh', 'ж'], ['kh', 'х'], ['ch', 'ч'], ['sh', 'ш'], ['ts', 'ц'],
  ['oo', 'у'], ['ee', 'и'], ['gh', 'г'], ['ph', 'ф'], ['th', 'т'], ['ck', 'к'], ['ey', 'ей'], ['iy', 'ий'], ['ay', 'ай'], ['oy', 'ой'],
  ['a', 'а'], ['b', 'б'], ['c', 'к'], ['d', 'д'], ['e', 'е'], ['f', 'ф'], ['g', 'г'], ['h', 'х'], ['i', 'и'], ['j', 'дж'], ['k', 'к'], ['l', 'л'],
  ['m', 'м'], ['n', 'н'], ['o', 'о'], ['p', 'п'], ['q', 'к'], ['r', 'р'], ['s', 'с'], ['t', 'т'], ['u', 'у'], ['v', 'в'], ['w', 'в'], ['x', 'кс'],
  ['y', 'ы'], ['z', 'з'],
];
function translit(s) {
  s = s.toLowerCase();
  let out = '';
  for (let i = 0; i < s.length;) {
    let hit = false;
    for (const [a, b] of TR) if (s.startsWith(a, i)) { out += b; i += a.length; hit = true; break; }
    if (!hit) { out += s[i]; i++; }
  }
  return out;
}
const SPECIAL = { noob: 'Нуб', gamer: 'Геймер', shadow: 'Шэдоу', ghost: 'Гост', pro: 'Про', dark: 'Дарк', sigma: 'Сигм', lol: 'Лол', zed: 'Зед' };
const SUFFIX = ['ия', 'стан', 'ландия', 'овия', 'град', 'ония'];
export const FALLBACK = ['Пинговия', 'Лагистан', 'Изиград', 'Нубляндия', 'Кринжония', 'Сигмария', 'Донатия', 'Респания', 'Читерстан', 'Тиммейтия', 'Афкландия', 'Бустония'];

export function nationName(raw, salt = 0) {
  let s = String(raw).replace(/^xX_|_Xx$/g, '');
  s = (s.match(/[A-ZА-ЯЁ]?[a-zа-яё]+|[A-ZА-ЯЁ]+(?![a-zа-яё])/) || [''])[0];
  if (!s) return null;
  let root = /[А-Яа-яЁё]/.test(s) ? s.toLowerCase() : SPECIAL[s.toLowerCase()]?.toLowerCase() || translit(s);
  root = root.replace(/(.)\1$/, '$1'); // Кирилл → Кирил
  const V = /[аяоеёыиуюэ]/;
  if (root.length < 2 || !V.test(root) || /(.)\1\1/.test(root)) return null;
  let pool = SUFFIX;
  if (/[аяоеёыиуюэь]$/.test(root)) {
    const st = root.replace(/[аяоеёыиуюэь]+$/, '');
    if (st.length >= 2 && V.test(st)) { root = st; pool = ['ландия', 'ия', 'стан', 'овия']; }
    else pool = ['вия', 'стан', 'ландия'];
  }
  const h = [...root].reduce((a, c) => a + c.charCodeAt(0), 0);
  let suf = pool[(h + salt) % pool.length];
  if (/н$/.test(root) && suf === 'ония') suf = 'ия';
  if (/[шщжчй]$/.test(root) && (suf === 'ия' || suf === 'ония')) suf = 'ландия';
  if (/[кгх]$/.test(root) && suf === 'ия') suf = 'стан';
  const name = root + suf;
  return name[0].toUpperCase() + name.slice(1);
}

export const PLAYER_COLOR = '#2f7bff';
export const CLAUDE_COLOR = '#e07a4f';
export const BOT_COLORS = ['#e53935', '#2ea043', '#9c27b0', '#f2c00f', '#00b3a4', '#ff5fa2', '#8d6e63', '#9ccc3a', '#8e1b3a', '#546e7a'];

export function hexToRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
export function shade(h, k) { // k<0 темнее, k>0 светлее
  const [r, g, b] = hexToRgb(h);
  const f = (c) => Math.round(k < 0 ? c * (1 + k) : c + (255 - c) * k);
  return `rgb(${f(r)},${f(g)},${f(b)})`;
}

// Флаг: полосы/крест/круг + эмблема. Возвращает canvas 48×32.
const FLAG_EXTRA = ['#ffffff', '#ffd54a', '#111827', '#ffffff', '#e8e8e8'];
export function makeFlag(color, rand) {
  const c = document.createElement('canvas'); c.width = 48; c.height = 32;
  const g = c.getContext('2d');
  const extra = FLAG_EXTRA[Math.floor(rand() * FLAG_EXTRA.length)];
  const dark = shade(color, -0.45);
  const style = Math.floor(rand() * 6);
  g.fillStyle = color; g.fillRect(0, 0, 48, 32);
  if (style === 0) { g.fillStyle = extra; g.fillRect(0, 0, 48, 11); g.fillStyle = dark; g.fillRect(0, 21, 48, 11); }
  else if (style === 1) { g.fillStyle = extra; g.fillRect(16, 0, 16, 32); g.fillStyle = dark; g.fillRect(32, 0, 16, 32); }
  else if (style === 2) { g.fillStyle = extra; g.fillRect(13, 0, 7, 32); g.fillRect(0, 12, 48, 7); }
  else if (style === 3) { g.fillStyle = extra; g.beginPath(); g.moveTo(0, 0); g.lineTo(22, 16); g.lineTo(0, 32); g.fill(); }
  else if (style === 4) { g.fillStyle = dark; g.beginPath(); g.moveTo(48, 0); g.lineTo(48, 32); g.lineTo(0, 32); g.fill(); }
  else { g.fillStyle = extra; g.fillRect(0, 13, 48, 6); }
  // эмблема
  const em = Math.floor(rand() * 4);
  const ex = style === 3 ? 8 : style === 2 ? 16 : 24, ey = 16;
  g.fillStyle = style === 0 || style === 5 ? '#ffd54a' : extra === '#ffd54a' ? '#ffffff' : '#ffd54a';
  if (em === 0) star(g, ex, ey, 7, 3);
  else if (em === 1) { g.beginPath(); g.arc(ex, ey, 6, 0, 7); g.fill(); }
  else if (em === 2) { g.beginPath(); g.arc(ex, ey, 7, 0, 7); g.fill(); g.fillStyle = color; g.beginPath(); g.arc(ex + 3, ey - 1, 6, 0, 7); g.fill(); }
  g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = 2; g.strokeRect(1, 1, 46, 30);
  return c;
}
export function star(g, x, y, R, r, n = 5) {
  g.beginPath();
  for (let i = 0; i < n * 2; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / n, rr = i % 2 ? r : R;
    g.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr);
  }
  g.closePath(); g.fill();
}

// Сборка списка наций. leaders: [{bot, isPlayer, isClaude}]
export function buildNations({ playerName, claude, bots, rand }) {
  const used = new Set(), stems = new Set();
  const stem = (s) => s.slice(0, 3).toLowerCase();
  const list = [];
  const uniq = (n, i) => {
    let name = n;
    if (!name || used.has(name) || stems.has(stem(name))) name = FALLBACK.find((f) => !used.has(f) && !stems.has(stem(f))) || 'Нация ' + (i + 1);
    used.add(name); stems.add(stem(name));
    return name;
  };
  // игрок
  const pn = playerName && playerName !== 'Игрок' ? nationName(playerName) : null;
  list.push({ name: uniq(pn || 'Брославия', 0), color: PLAYER_COLOR, leader: { id: 'player', name: playerName || 'Игрок' }, isPlayer: true });
  list.push({ name: uniq('Клодия', 1), color: CLAUDE_COLOR, leader: claude, isClaude: true });
  bots.forEach((b, i) => {
    const n = nationName(b.name, i);
    list.push({ name: uniq(n, i + 2), color: BOT_COLORS[i % BOT_COLORS.length], leader: b });
  });
  list.forEach((n, i) => {
    n.id = i;
    n.flag = makeFlag(n.color, rand);
    n.flagUrl = n.flag.toDataURL();
    const [r, g, b] = hexToRgb(n.color);
    n.rgb = [r, g, b];
    n.fill = `rgba(${r},${g},${b},0.38)`;
    n.fillHi = `rgba(${r},${g},${b},0.6)`;
    n.dark = shade(n.color, -0.35);
    n.light = shade(n.color, 0.35);
  });
  return list;
}

// падежи для названий наций (упрощённо): кому? (дательный), с кем? (творительный), род для глагола
export const fem = (n) => /[ая]$/.test(n);
export function dat(n) { return /ия$/.test(n) ? n.slice(0, -1) + 'и' : /а$/.test(n) ? n.slice(0, -1) + 'е' : /я$/.test(n) ? n.slice(0, -1) + 'е' : n + 'у'; }
export function ins(n) { return /ия$/.test(n) ? n.slice(0, -1) + 'ей' : /а$/.test(n) ? n.slice(0, -1) + 'ой' : /я$/.test(n) ? n.slice(0, -1) + 'ей' : n + 'ом'; }
export const va = (n, verb) => verb + (fem(n) ? 'а' : '');

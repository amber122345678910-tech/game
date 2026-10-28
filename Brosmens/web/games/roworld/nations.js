// BroWorld — нации (реальные регионы Земли, ИИ), племена, цвета территорий (пастель как в оригинале).
// NATIONS: [название, широта, долгота] — точка появления нации на карте.
export const NATIONS = [
  ['Аляска', 64.5, -152], ['Юкон', 63.5, -135.5], ['Канада', 54, -112], ['Квебек', 52, -72],
  ['Калифорния', 37, -120], ['Техас', 31.5, -99], ['США', 39.5, -90], ['Мексика', 23.5, -102],
  ['Куба', 21.8, -79], ['Гренландия', 73, -40], ['Колумбия', 4, -73.5], ['Венесуэла', 7.5, -65.5],
  ['Перу', -9.5, -75], ['Бразилия', -10, -52], ['Аргентина', -36, -65], ['Исландия', 64.9, -18.5],
  ['Великобритания', 53, -1.5], ['Испания', 40, -3.7], ['Франция', 46.6, 2.4], ['Италия', 43, 12.5],
  ['Германия', 51, 10], ['Финляндия', 63, 26], ['Польша', 52, 19.5], ['Украина', 49, 32],
  ['Турция', 39, 34], ['Россия', 57, 42], ['Сибирь', 63, 105], ['Казахстан', 48, 68],
  ['Монголия', 46.5, 103], ['Китай', 33, 112], ['Япония', 36.5, 138.5], ['Индия', 22, 79],
  ['Иран', 32, 54], ['Саудовская Аравия', 24, 45], ['Египет', 26.5, 30], ['Алжир', 28, 2],
  ['Марокко', 32, -6], ['Нигерия', 9, 8], ['Эфиопия', 9, 39.5], ['Кения', 0.3, 38],
  ['ДР Конго', -3, 23], ['Намибия', -22, 17], ['ЮАР', -30, 24.5], ['Мадагаскар', -19.5, 46.7],
  ['Таиланд', 15, 101], ['Индонезия', -0.5, 114], ['Австралия', -25, 134], ['Новая Зеландия', -42, 172.5],
  ['Западная Антарктида', -78, -100], ['Восточная Антарктида', -75, 80],
];

const TRIBE_A = ['Серых', 'Быстрых', 'Горных', 'Северных', 'Тихих', 'Каменных', 'Ледяных', 'Степных', 'Лесных', 'Дальних', 'Песчаных', 'Красных', 'Солнечных', 'Лунных', 'Громовых', 'Речных', 'Ночных', 'Рыжих', 'Белых', 'Тёмных'];
const TRIBE_B = ['Волков', 'Бизонов', 'Ястребов', 'Медведей', 'Лис', 'Коней', 'Орлов', 'Барсов', 'Сов', 'Туров', 'Рысей', 'Воронов', 'Буйволов', 'Оленей', 'Клыков', 'Когтей'];
export function tribeNames(n, rand) {
  const all = [];
  for (const a of TRIBE_A) for (const b of TRIBE_B) all.push(`Племя ${a} ${b}`);
  for (let i = all.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = all[i]; all[i] = all[j]; all[j] = t; }
  return all.slice(0, n);
}

// ---------- цвета ----------
export const PLAYER_COLOR = '#8AB4F8';
export const CLAUDE_COLOR = '#F7B98B';
export const TRIBE_COLOR = '#C9C6BF';
const BASE = ['#F2A6C4', '#C7B5F0', '#A8E6C1', '#F3E08A', '#F59A8F', '#9FD3F0', '#7FD1C7', '#E7B7F2', '#B9E28C', '#F6C6A0', '#A6C8F2', '#F2D0A6'];
export function hexToRgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
export function rgbHex([r, g, b]) { return '#' + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1); }
function rgb2hsl([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  if (mx === mn) return [0, 0, l];
  const d = mx - mn, s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  let h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
}
function hsl2rgb([h, s, l]) {
  if (!s) { const v = Math.round(l * 255); return [v, v, v]; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [Math.round(f(h + 1 / 3) * 255), Math.round(f(h) * 255), Math.round(f(h - 1 / 3) * 255)];
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
export function brighten(rgb, k) { return rgb.map((c) => Math.min(255, Math.round(c + (255 - c) * k))); }
export function darken(rgb, k) { return rgb.map((c) => Math.round(c * (1 - k))); }

// пастельная палитра на любое число игроков
export function pastel(i) {
  if (i < BASE.length) return BASE[i];
  const h = ((i * 137.508) % 360) / 360;
  const s = 0.55 + ((i * 7) % 5) * 0.06, l = 0.74 + ((i * 3) % 4) * 0.025;
  return rgbHex(hsl2rgb([h, s, l]));
}

// Все производные цвета владельца: заливка (насыщенность ×0.85), полоса границы (темнее и насыщеннее),
// подсвеченные варианты (+15% / +25% яркости), тёмный — для значков построек.
export function ownerColors(hex) {
  const rgb = hexToRgb(hex);
  const [h, s, l] = rgb2hsl(rgb);
  const fill = hsl2rgb([h, s * 0.85, l]);
  const border = hsl2rgb([h, s < 0.2 ? s * 1.2 : Math.min(0.58, s * 0.9 + 0.12), clamp01(l * 0.63)]);
  return {
    css: hex, rgb, fill, border,
    fillHi: brighten(fill, 0.15), borderHi: brighten(border, 0.25),
    dark: rgbHex(darken(rgb, 0.35)), deep: rgbHex(hsl2rgb([h, clamp01(s * 0.9), clamp01(l * 0.42)])),
    borderCss: rgbHex(border),
  };
}

// винительный падеж для названий наций: «Ты уничтожил Украину / Саудовскую Аравию»; аббревиатуры и прочее — без изменений
export function acc(name) {
  if (!/[а-яё]/.test(name)) return name;
  return name.split(' ').map((w) => {
    if (/^[А-ЯЁ]{2,}$/.test(w) || !/[а-яё]$/.test(w)) return w;
    if (/ая$/.test(w)) return w.slice(0, -2) + 'ую';
    if (/[^аеиоуыэюя]а$/.test(w)) return w.slice(0, -1) + 'у';
    if (/я$/.test(w)) return w.slice(0, -1) + 'ю';
    return w;
  }).join(' ');
}

// род для согласования глаголов: «Аргентина захватила», «Иран захватил», «Перу захватило», «США захватили»
const GENDER = { 'США': 'pl', 'Перу': 'n', 'Марокко': 'n', 'Сибирь': 'f', 'ЮАР': 'f', 'ДР Конго': 'f' };
export function gender(name, kind) {
  if (kind === 2) return 'n';            // племя
  if (kind === 0) return 'm';            // игрок (ник)
  if (GENDER[name]) return GENDER[name];
  return /[ая]$/.test(name) ? 'f' : 'm';
}
// прошедшее время / краткое причастие мужского рода → нужный род: past('захватил', 'f') = 'захватила'
export function past(word, g) { return g === 'f' ? word + 'а' : g === 'n' ? word + 'о' : g === 'pl' ? word + (/н$/.test(word) ? 'ы' : 'и') : word; }

// родительный, дательный и творительный падежи для названий: «от Монголии», «близко к Канаде»,
// «уничтожена Сибирью». Ники игроков и аббревиатуры не склоняются; у племени склоняется только слово «Племя».
const NODECL = /^(США|ЮАР|Перу|Марокко|ДР Конго)$/;
function declWord(w, c) {
  if (!/[а-яё]$/.test(w) || /^[А-ЯЁ]{2,}$/.test(w)) return w;
  const gen = c === 'gen', ins = c === 'ins';
  if (w === 'Египет') return gen ? 'Египта' : ins ? 'Египтом' : 'Египту';
  if (/ая$/.test(w)) return w.slice(0, -2) + 'ой';                 // Саудовская → Саудовской
  if (/ия$/.test(w)) return w.slice(0, -2) + (ins ? 'ией' : 'ии');   // Монголия → Монголии / Монголией
  if (ins && /[жшщчц]а$/.test(w)) return w.slice(0, -1) + 'ей';     // Польша → Польшей
  if (ins && /а$/.test(w)) return w.slice(0, -1) + 'ой';            // Канада → Канадой
  if (/[гкхжшщч]а$/.test(w)) return w.slice(0, -1) + (gen ? 'и' : 'е'); // Аляска → Аляски / Аляске
  if (/а$/.test(w)) return w.slice(0, -1) + (gen ? 'ы' : 'е');       // Канада → Канады / Канаде
  if (/я$/.test(w)) return w.slice(0, -1) + (gen ? 'и' : ins ? 'ей' : 'е');
  if (/ь$/.test(w)) return w.slice(0, -1) + (ins ? 'ью' : 'и');      // Сибирь → Сибири / Сибирью
  if (/й$/.test(w)) return w.slice(0, -1) + (gen ? 'я' : ins ? 'ем' : 'ю'); // Китай → Китая / Китаем
  if (/[оуеиюэы]$/.test(w)) return w;
  return w + (gen ? 'а' : ins ? 'ом' : 'у');                        // Иран → Ирана / Ираном / Ирану
}
function decl(name, kind, c) {
  if (kind === 0 || NODECL.test(name) || !/[а-яё]/.test(name)) return name;
  if (kind === 2) return name.replace(/^Племя/, c === 'ins' ? 'Племенем' : 'Племени');
  return name.split(' ').map((w) => declWord(w, c)).join(' ');
}
export const genName = (p) => decl(p.name, p.kind, 'gen');
export const datName = (p) => decl(p.name, p.kind, 'dat');
export const insName = (p) => decl(p.name, p.kind, 'ins');

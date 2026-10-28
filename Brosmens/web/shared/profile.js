// Профиль игрока, настройки и ключ API — всё хранится только на телефоне (localStorage).
const KEY = 'brosmens.profile.v1';
const API_KEY = 'brosmens.apikey';

// Мощный телефон (флагман вроде Galaxy S26 Ultra) — сразу высокая графика
const STRONG = (navigator.deviceMemory || 4) >= 8 && (navigator.hardwareConcurrency || 4) >= 8;

const DEFAULT = {
  name: 'Игрок',
  skin: { skin: '#f2c9a0', shirt: '#2f6fed', pants: '#23262e', hair: '#2b1d10', hairStyle: 'short', face: 0 },
  coins: 0,
  stats: {},
  settings: { sound: true, graphics: STRONG ? 8 : 6, volume: 7, sensitivity: 5, shake: true, toxicity: 0.5, aiDailyLimit: 150 },
};

function read() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return structuredClone(DEFAULT);
    const p = JSON.parse(raw);
    return { ...structuredClone(DEFAULT), ...p, skin: { ...DEFAULT.skin, ...p.skin }, settings: { ...DEFAULT.settings, ...p.settings } };
  } catch {
    return structuredClone(DEFAULT);
  }
}

export function getProfile() {
  return read();
}

let settingsCache = null;

export function saveProfile(p) {
  try { localStorage.setItem(KEY, JSON.stringify(p)); } catch {}
  settingsCache = null;
  window.dispatchEvent(new CustomEvent('brosmens:settings', { detail: p.settings }));
  return p;
}

// Быстрый доступ к настройкам (кэш) — для горячих мест: звук, камера, рендер
export function getSettings() {
  return (settingsCache ??= Object.freeze({ ...read().settings }));
}

export function updateProfile(fn) {
  const p = read();
  fn(p);
  return saveProfile(p);
}

// Добавить к статистике игры: addStat('jjs', 'kills', 1)
export function addStat(game, key, n = 1) {
  return updateProfile((p) => {
    p.stats[game] ??= {};
    p.stats[game][key] = (p.stats[game][key] || 0) + n;
  });
}

export function addCoins(n) {
  return updateProfile((p) => { p.coins = Math.max(0, (p.coins || 0) + n); });
}

export function getApiKey() {
  try { return localStorage.getItem(API_KEY) || ''; } catch { return ''; }
}

export function setApiKey(k) {
  try {
    if (k) localStorage.setItem(API_KEY, k.trim());
    else localStorage.removeItem(API_KEY);
  } catch {}
}

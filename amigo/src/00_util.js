/* ===== 00_util.js ===== */
'use strict';
// Общие помощники: случайные числа, склонение, хранилище.
const AMIGO_VERSION = '2.0';
const U = {
  // детерминированный генератор случайных чисел (mulberry32)
  rng(seed) {
    let t = seed >>> 0;
    return () => {
      t = (t + 0x6D2B79F5) >>> 0;
      let r = Math.imul(t ^ (t >>> 15), 1 | t);
      r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  },
  pick(a, rnd = Math.random) { return a[Math.floor(rnd() * a.length)]; },
  shuffle(a, rnd = Math.random) {
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  },
  clamp(v, a, b) { return v < a ? a : v > b ? b : v; },
  // 1 яблоко, 2 яблока, 5 яблок
  plural(n, one, few, many) {
    const a = Math.abs(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b === 1) return one;
    if (b >= 2 && b <= 4) return few;
    return many;
  },
  cap(s) { return s ? s[0].toUpperCase() + s.slice(1) : s; },
  // кириллица латиницей: для имён файлов
  translit(s) {
    const m = { а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch', ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya' };
    return String(s).replace(/[а-яё]/gi, c => { const r = m[c.toLowerCase()]; return c === c.toLowerCase() ? r : U.cap(r); });
  },
  // число по-русски: 2,5 и 1 000 000
  num(x) {
    if (!isFinite(x)) return String(x);
    let s;
    if (Number.isInteger(x) && Math.abs(x) < 1e15) s = String(x);
    else s = String(+x.toPrecision(10));
    if (/e/.test(s)) return s.replace('.', ',');
    const neg = s[0] === '-'; if (neg) s = s.slice(1);
    let [i, f] = s.split('.');
    if (i.length > 4) i = i.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    return (neg ? '−' : '') + i + (f ? ',' + f : '');
  },
  // localStorage может быть недоступен (приватный режим, песочница) — тогда работаем без него
  store: {
    get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch (e) { return false; } },
    del(k) { try { localStorage.removeItem(k); } catch (e) { /* нет доступа */ } },
  },
  tick() { return new Promise(r => setTimeout(r, 0)); },
  b64enc(bytes) {
    if (typeof Buffer !== 'undefined') return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('base64');
    let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  },
  b64dec(str) {
    if (typeof Buffer !== 'undefined') return new Uint8Array(Buffer.from(str, 'base64'));
    const s = atob(str), out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  },
};

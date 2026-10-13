/* ===== 01_text.js ===== */
// Работа с текстом: очистка, слова, основы слов (стеммер Портера для русского) и признаки для нейросети.
const Text = (() => {
  // нижний регистр, ё→е, только буквы и цифры, «приииивет» → «привет»
  function clean(s) {
    return String(s).toLowerCase().replace(/ё/g, 'е')
      .replace(/[^a-zа-я0-9]+/g, ' ')
      .replace(/([a-zа-я])\1{2,}/g, '$1')
      .trim();
  }
  function words(s) { const c = clean(s); return c ? c.split(' ') : []; }

  // --- стеммер Портера (Snowball) для русского, без lookbehind, чтобы работал и на старых телефонах ---
  const RV = /^(.*?[аеиоуыэюя])(.*)$/;
  const PG1 = /(ив|ивши|ившись|ыв|ывши|ывшись)$/, PG2 = /[ая](в|вши|вшись)$/;
  const REFL = /(ся|сь)$/;
  const ADJ = /(ее|ие|ые|ое|ими|ыми|ей|ий|ый|ой|ем|им|ым|ом|его|ого|ему|ому|их|ых|ую|юю|ая|яя|ою|ею)$/;
  const PART1 = /(ивш|ывш|ующ)$/, PART2 = /[ая](ем|нн|вш|ющ|щ)$/;
  const VERB1 = /(ила|ыла|ена|ейте|уйте|ите|или|ыли|ей|уй|ил|ыл|им|ым|ен|ило|ыло|ено|ят|ует|уют|ит|ыт|ены|ить|ыть|ишь|ую|ю)$/;
  const VERB2 = /[ая](ла|на|ете|йте|ли|й|л|ем|н|ло|но|ет|ют|ны|ть|ешь|нно)$/;
  const NOUN = /(а|ев|ов|ие|ье|е|иями|ями|ами|еи|ии|и|ией|ей|ой|ий|й|иям|ям|ием|ем|ам|ом|о|у|ах|иях|ях|ы|ь|ию|ью|ю|ия|ья|я)$/;
  const DERIV = /[^аеиоуыэюя][аеиоуыэюя]+[^аеиоуыэюя]+[аеиоуыэюя].*ость?$/;
  // убирает самое длинное подходящее окончание; второе выражение — окончания, которые идут после «а»/«я»
  function strip(w, re1, re2) {
    let best = -1;
    const m1 = re1.exec(w); if (m1) best = m1.index;
    if (re2) { const m2 = re2.exec(w); if (m2 && (best < 0 || m2.index + 1 < best)) best = m2.index + 1; }
    return best < 0 ? null : w.slice(0, best);
  }
  const cache = new Map();
  function stem(word) {
    if (word.length < 3 || !/[а-я]/.test(word)) return word;
    const hit = cache.get(word); if (hit) return hit;
    const m = RV.exec(word);
    if (!m) return word;
    const pre = m[1]; let rv = m[2], t;
    if ((t = strip(rv, PG1, PG2)) !== null) rv = t;
    else {
      rv = rv.replace(REFL, '');
      if ((t = strip(rv, ADJ)) !== null) { rv = t; const p = strip(rv, PART1, PART2); if (p !== null) rv = p; }
      else if ((t = strip(rv, VERB1, VERB2)) !== null) rv = t;
      else if ((t = strip(rv, NOUN)) !== null) rv = t;
    }
    rv = rv.replace(/и$/, '');
    if (DERIV.test(rv)) rv = rv.replace(/ость?$/, '');
    if (/ь$/.test(rv)) rv = rv.slice(0, -1);
    else { rv = rv.replace(/(ейше|ейш)$/, ''); rv = rv.replace(/нн$/, 'н'); }
    const out = pre + rv;
    if (cache.size < 20000) cache.set(word, out);
    return out;
  }

  // FNV-1a — превращает признак-строку в номер входа нейросети
  function hash(s) {
    let h = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
    return h >>> 0;
  }
  // Признаки фразы: основы слов, пары основ и кусочки слов по 3 буквы.
  // Кусочки помогают понимать опечатки и незнакомые формы слов.
  function features(text, D, withKeys) {
    const ws = words(text);
    const st = ws.map(w => /^\d+$/.test(w) ? '#' : stem(w));
    const map = new Map(), keys = withKeys ? new Map() : null;
    const add = (k, v) => { const i = hash(k) % D; map.set(i, (map.get(i) || 0) + v); if (keys && !keys.has(i)) keys.set(i, k); };
    for (const s of st) add('w:' + s, 1);
    for (let i = 0; i + 1 < st.length; i++) add('b:' + st[i] + ' ' + st[i + 1], 0.6);
    for (const w of ws) {
      if (/^\d+$/.test(w)) continue;
      const p = '<' + w + '>';
      for (let i = 0; i + 3 <= p.length; i++) add('c:' + p.substr(i, 3), 0.3);
    }
    let n = 0; map.forEach(v => { n += v * v; }); n = Math.sqrt(n) || 1;
    const idx = new Int32Array(map.size), val = new Float32Array(map.size);
    let j = 0; map.forEach((v, k) => { idx[j] = k; val[j] = v / n; j++; });
    return { idx, val, words: ws, stems: st, keys };
  }

  // косинусная близость двух наборов признаков
  function cosine(a, b) {
    const m = new Map(); for (let i = 0; i < a.idx.length; i++) m.set(a.idx[i], a.val[i]);
    let s = 0; for (let i = 0; i < b.idx.length; i++) { const v = m.get(b.idx[i]); if (v) s += v * b.val[i]; }
    return s;
  }

  // --- числа словами: «сто двадцать пять» → 125 ---
  const UNITS = { ноль: 0, нуль: 0, один: 1, одна: 1, одно: 1, два: 2, две: 2, три: 3, четыре: 4, пять: 5, шесть: 6, семь: 7, восемь: 8, девять: 9,
    десять: 10, одиннадцать: 11, двенадцать: 12, тринадцать: 13, четырнадцать: 14, пятнадцать: 15, шестнадцать: 16, семнадцать: 17, восемнадцать: 18, девятнадцать: 19,
    двадцать: 20, тридцать: 30, сорок: 40, пятьдесят: 50, шестьдесят: 60, семьдесят: 70, восемьдесят: 80, девяносто: 90,
    сто: 100, двести: 200, триста: 300, четыреста: 400, пятьсот: 500, шестьсот: 600, семьсот: 700, восемьсот: 800, девятьсот: 900,
    полтора: 1.5, полторы: 1.5 };
  const BIG = { тысяча: 1e3, тысячи: 1e3, тысяч: 1e3, миллион: 1e6, миллиона: 1e6, миллионов: 1e6, миллиард: 1e9, миллиарда: 1e9, миллиардов: 1e9 };
  // заменяет числа, записанные словами, на цифры
  function wordsToDigits(s) {
    const toks = String(s).toLowerCase().replace(/ё/g, 'е').split(/(\s+)/);
    const out = []; let total = null, cur = 0, pendingSpace = '';
    const flush = () => { if (total !== null) { out.push(String(total + cur)); total = null; cur = 0; } };
    for (const tok of toks) {
      if (/^\s+$/.test(tok)) { if (total !== null) pendingSpace = tok; else out.push(tok); continue; }
      const w = tok.replace(/[.,!?;:]+$/, ''), tail = tok.slice(w.length);
      if (w in UNITS) {
        if (total === null) { total = 0; cur = 0; }
        cur += UNITS[w];
        if (tail) { flush(); out.push(tail); }
        pendingSpace = '';
        continue;
      }
      if (w in BIG) {
        if (total === null) { total = 0; cur = 1; }
        total += (cur || 1) * BIG[w]; cur = 0;
        if (tail) { flush(); out.push(tail); }
        pendingSpace = '';
        continue;
      }
      flush();
      if (pendingSpace) { out.push(pendingSpace); pendingSpace = ''; }
      out.push(tok);
    }
    flush();
    if (pendingSpace) out.push(pendingSpace);
    return out.join('');
  }

  return { clean, words, stem, hash, features, cosine, wordsToDigits };
})();

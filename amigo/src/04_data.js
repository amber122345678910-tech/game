/* ===== 04_data.js ===== */
// Подготовка обучающих примеров: подстановка слов в шаблоны, «шум» для устойчивости к опечаткам,
// и отдельная тема для бессмыслицы, чтобы сеть умела говорить «не понял».
const Data = (() => {
  const RU = 'йцукенгшщзхфывапролджэячсмитьбю', EN = 'qwertyuiopasdfghjklzxcvbnm';
  const FILLERS = ['амиго', 'слушай', 'а', 'ну', 'скажи', 'пожалуйста', 'эй', 'слушай амиго', 'а ты', 'ну и', 'так', 'короче'];

  function expand(p, rnd, k) {
    if (p.indexOf('{') < 0) return [p];
    const out = new Set();
    for (let i = 0; i < k * 3 && out.size < k; i++) out.add(p.replace(/\{(\w+)\}/g, (m, key) => U.pick(FILL[key], rnd)));
    return [...out];
  }
  function gibberish(rnd, n) {
    const out = ['ываыва', 'фывапролд', 'asdfgh', 'qwerty', 'йцукен', 'ячсмить', 'ааааа', 'ыыыы', 'zxcvb', 'лдодлод', 'ghjk', 'щшгнек'];
    while (out.length < n) {
      const abc = rnd() < 0.7 ? RU : EN, words = rnd() < 0.25 ? 2 : 1;
      const parts = [];
      for (let w = 0; w < words; w++) {
        const len = 3 + Math.floor(rnd() * 8); let s = '';
        for (let i = 0; i < len; i++) s += abc[Math.floor(rnd() * abc.length)];
        parts.push(s);
      }
      out.push(parts.join(' '));
    }
    return out;
  }
  // небольшая порча фразы: опечатка, пропуск слова или слово-паразит
  function augment(text, rnd) {
    let ws = text.split(' ');
    const r = rnd();
    if (r < 0.35) {
      const i = Math.floor(rnd() * ws.length), w = ws[i];
      if (w.length > 3) {
        const j = 1 + Math.floor(rnd() * (w.length - 2)), kind = rnd();
        if (kind < 0.4) ws[i] = w.slice(0, j) + w.slice(j + 1);
        else if (kind < 0.7) ws[i] = w.slice(0, j) + w[j + 1] + w[j] + w.slice(j + 2);
        else ws[i] = w.slice(0, j) + RU[Math.floor(rnd() * RU.length)] + w.slice(j + 1);
      }
    } else if (r < 0.55 && ws.length > 2) {
      ws.splice(Math.floor(rnd() * ws.length), 1);
    } else if (r < 0.85) {
      const f = U.pick(FILLERS, rnd);
      if (rnd() < 0.6) ws.unshift(f); else ws.push(f);
    } else {
      ws = ws.map(w => (rnd() < 0.3 && w.length > 4) ? w.replace(/е/g, 'и') : w);
    }
    return ws.join(' ');
  }

  // intents — список тем; customs — то, чему научил пользователь
  function build(intents, customs = [], opts = {}) {
    const rnd = U.rng(opts.seed || 2026), k = opts.expand || 5, aug = opts.augment == null ? 2 : opts.augment;
    const all = intents.concat([{ tag: 'gibberish', t: 'бессмыслица', p: gibberish(rnd, 60), act: 'gibberish' }]).concat(customs);
    const tags = all.map(i => i.tag), titles = all.map(i => i.t || i.tag);
    const examples = [];
    if (opts.noExamples) return { intents: all, tags, titles, examples };
    all.forEach((it, y) => {
      const reps = it.custom ? 6 : 1; // свои фразы пользователя повторяем, их мало
      for (const p of it.p) for (const s of expand(p, rnd, k)) {
        const c = Text.clean(s); if (!c) continue;
        for (let r = 0; r < reps; r++) {
          examples.push({ text: c, y });
          for (let a = 0; a < aug; a++) examples.push({ text: Text.clean(augment(c, rnd)), y });
        }
      }
    });
    return { intents: all, tags, titles, examples };
  }
  function featurize(examples, D) { return examples.map(e => ({ x: Text.features(e.text, D), y: e.y })); }

  return { build, featurize, augment, gibberish };
})();

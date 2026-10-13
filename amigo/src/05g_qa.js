/* ===== 05g_qa.js ===== */
// Ответы на частые детские вопросы («почему небо голубое?», «сколько костей у человека?») без интернета.
// Вопрос пользователя сравнивается со всеми формулировками из QA_DATA: должны совпасть главные слова
// и общий «отпечаток» фразы. Лучше честно сказать «не знаю», чем ответить на другой вопрос.
const QA = (() => {
  const QSTOP = new Set(('почему зачем как какой какая какое какие каких каким сколько кто что чем чего чему где куда откуда когда ли а и в во на у о об обо про ' +
    'это такое такой такая такие есть бывает бывают нужно нужен нужна можно вообще ну скажи расскажи объясни мне меня ты тебе знаешь амиго же бы да ' +
    'там тут из за от до по с со к ко для при через они он она оно мы вы их его ее её всё все весь вся так тоже еще ещё очень правда разве ' +
    'случилось происходит получается делает делают такими таким').split(/\s+/));
  let idx = null;
  const SYN = { звер: 'животн', зверюшк: 'животн', зверек: 'животн', км: 'километр', килом: 'километр', ребят: 'дет', ребенк: 'дет', малыш: 'дет', тачк: 'машин', комп: 'компьютер' };
  const content = text => [...new Set(Text.words(text).filter(w => !QSTOP.has(w) && !/^\d+$/.test(w)).map(w => { const s = Text.stem(w); return SYN[s] || s; }))];
  function build() {
    idx = [];
    if (typeof QA_DATA === 'undefined') return;
    for (const item of QA_DATA) for (const q of item.q) idx.push({ item, f: Text.features(q, 4096), c: new Set(content(q)) });
  }
  function find(text) {
    if (!idx) build();
    if (!idx.length) return null;
    // сначала ищем по словам как есть, и только если не нашли — с исправленными опечатками
    const fixed = typeof Spell !== 'undefined' ? Spell.fix(text) : '';
    return find1(text) || (fixed && fixed !== Text.clean(text) ? find1(fixed) : null);
  }
  function find1(t) {
    const f = Text.features(t, 4096), c = content(t);
    if (!c.length) return null;
    let best = null;
    for (const e of idx) {
      let inter = 0; for (const s of c) if (e.c.has(s)) inter++;
      if (!inter) continue;
      // почти все главные слова вопроса должны быть в найденной формулировке, и наоборот
      if (inter / c.length < 0.75 || inter / e.c.size < (inter >= 2 ? 0.5 : 0.6) || (inter < 2 && (c.length > 1 || e.c.size > 1))) continue;
      const cos = Text.cosine(f, e.f);
      if (cos < 0.35) continue;
      const score = cos + inter / Math.max(c.length, e.c.size);
      if (!best || score > best.score) best = { item: e.item, score };
    }
    return best ? best.item : null;
  }
  return { find, get size() { return typeof QA_DATA === 'undefined' ? 0 : QA_DATA.length; } };
})();

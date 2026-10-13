/* ===== 05_skills.js ===== */
// Навыки Амиго, которые работают без интернета: калькулятор, время, игры, таймер, перевод, мини-энциклопедия.
const Skills = (() => {
  const low = s => String(s).toLowerCase().replace(/ё/g, 'е');

  // ---------- калькулятор (свой разбор выражений, без eval) ----------
  const CALC_OK = new Set(['сколько', 'будет', 'посчитай', 'посчитать', 'подсчитай', 'реши', 'решить', 'вычисли', 'вычислить', 'равно', 'а', 'ну', 'амиго', 'пожалуйста',
    'скажи', 'мне', 'пример', 'это', 'чему', 'получится', 'если', 'помоги', 'сосчитай', 'ответ', 'быстро', 'плиз', 'калькулятор', 'так', 'а теперь', 'теперь', 'тогда',
    'будет?', 'нам', 'сколько-сколько', 'выйдет', 'равен', 'равна', 'ровно', 'всего', 'итого']);
  function prep(text) {
    let s = ' ' + Text.wordsToDigits(low(text)) + ' ';
    s = s.replace(/(\d),(\d)/g, '$1.$2')
      .replace(/квадратный корень из|корень квадратный из|квадратный корень|корень из|корень/g, ' sqrt ')
      .replace(/в квадрате/g, ' ^2 ').replace(/в кубе/g, ' ^3 ').replace(/в степени|в \^/g, ' ^ ')
      .replace(/(\d+(?:\.\d+)?)\s*(?:процентов|процента|процент|%)\s*от\s*/g, '($1/100)*')
      .replace(/(\d)\s*%/g, '$1/100')
      .replace(/дважды/g, ' 2* ').replace(/трижды/g, ' 3* ')
      .replace(/факториал(?: от)?\s*(\d+)/g, ' $1! ')
      .replace(/умножить на|умноженное на|помножить на|умножь|умножить|times/g, ' * ')
      .replace(/разделить на|делить на|поделить на|деленное на|поделенное на|раздели|поделить|делить/g, ' / ')
      .replace(/прибавить|плюс|сложить с|plus/g, ' + ')
      .replace(/отнять|минус|вычесть|minus/g, ' - ')
      .replace(/синус/g, ' sin ').replace(/косинус/g, ' cos ').replace(/тангенс/g, ' tan ').replace(/модуль/g, ' abs ').replace(/(^|\s)пи(?=\s|$)/g, ' pi ')
      .replace(/[×·∙]/g, '*').replace(/÷/g, '/').replace(/[−–—]/g, '-').replace(/√/g, ' sqrt ');
    // «5 x 3», «5 х 3», «10:2»
    for (let i = 0; i < 3; i++) s = s.replace(/(\d)\s*[xх]\s*(\d)/g, '$1*$2').replace(/(\d)\s*:\s*(\d)/g, '$1/$2');
    // «сложи 2 и 3»
    if (/слож/.test(s)) s = s.replace(/сложи(?:ть)?/g, ' ').replace(/(\d)\s+и\s+(\d)/g, '$1+$2');
    return s;
  }
  function lex(s, force) {
    const toks = [], re = /\s*(\d+(?:\.\d+)?|sqrt|sin|cos|tan|abs|pi|[+\-*/^()!]|[a-zа-я?=,.]+)/gy;
    let m, last = 0;
    while ((m = re.exec(s))) {
      last = re.lastIndex;
      const t = m[1];
      if (/^\d/.test(t)) toks.push({ n: parseFloat(t) });
      else if (/^(sqrt|sin|cos|tan|abs)$/.test(t)) toks.push({ f: t });
      else if (t === 'pi') toks.push({ n: Math.PI, pi: 1 });
      else if (/^[+\-*/^()!]$/.test(t)) toks.push({ o: t });
      else if (/^[?=,.]+$/.test(t) || CALC_OK.has(t.replace(/[?,.]+$/, ''))) continue;
      else if (!force) return null;
    }
    if (s.slice(last).trim()) { if (!force) return null; }
    return toks;
  }
  function evaluate(toks) {
    let i = 0;
    const peek = () => toks[i], next = () => toks[i++];
    const isOp = (t, o) => t && t.o === o;
    function expr() {
      let v = term();
      while (isOp(peek(), '+') || isOp(peek(), '-')) { const o = next().o; const r = term(); v = o === '+' ? v + r : v - r; }
      return v;
    }
    function term() {
      let v = factor();
      for (;;) {
        const t = peek();
        if (isOp(t, '*') || isOp(t, '/')) { next(); const r = factor(); v = t.o === '*' ? v * r : v / r; }
        else if (t && (t.f || isOp(t, '(') || t.pi)) v *= factor(); // 2(3+4), 2 sqrt 9
        else break;
      }
      return v;
    }
    function factor() { const b = unary(); if (isOp(peek(), '^')) { next(); return Math.pow(b, factor()); } return b; }
    function unary() {
      if (isOp(peek(), '-')) { next(); return -unary(); }
      if (isOp(peek(), '+')) { next(); return unary(); }
      return postfix();
    }
    function postfix() {
      let v = primary();
      while (isOp(peek(), '!')) {
        next();
        if (v < 0 || v > 170 || !Number.isInteger(v)) throw new Error('fact');
        let r = 1; for (let k = 2; k <= v; k++) r *= k; v = r;
      }
      return v;
    }
    function primary() {
      const t = next();
      if (!t) throw new Error('end');
      if ('n' in t) return t.n;
      if (t.f) {
        const a = isOp(peek(), '(') ? primary() : unary();
        const rad = a * Math.PI / 180;
        if (t.f === 'sqrt') return Math.sqrt(a);
        if (t.f === 'abs') return Math.abs(a);
        const r = t.f === 'sin' ? Math.sin(rad) : t.f === 'cos' ? Math.cos(rad) : Math.tan(rad);
        return Math.abs(r) < 1e-12 ? 0 : r;
      }
      if (isOp(t, '(')) { const v = expr(); if (isOp(peek(), ')')) next(); return v; }
      throw new Error('bad');
    }
    const v = expr();
    if (i < toks.length) throw new Error('rest');
    return v;
  }
  function pretty(toks) {
    return toks.map(t => 'n' in t ? (t.pi ? 'π' : U.num(t.n)) : t.f ? (t.f === 'sqrt' ? '√' : t.f) : t.o === '*' ? '×' : t.o === '/' ? '÷' : t.o === '-' ? '−' : t.o)
      .join(' ').replace(/\( /g, '(').replace(/ \)/g, ')').replace(/√ /g, '√').replace(/ !/g, '!').replace(/ \^ /g, '^');
  }
  // вернёт {expr, value} или null, если это не пример; force — нейросеть уверена, что это математика
  function calc(text, force) {
    const toks = lex(prep(text), force);
    if (!toks || !toks.length) return null;
    const nums = toks.filter(t => 'n' in t).length, ops = toks.filter(t => t.f || (t.o && t.o !== '(' && t.o !== ')')).length;
    if (!nums || !ops) return null;
    try {
      const v = evaluate(toks);
      if (typeof v !== 'number' || isNaN(v)) return { expr: pretty(toks), value: NaN };
      return { expr: pretty(toks), value: v };
    } catch (e) { return null; }
  }
  function calcText(r) {
    if (!isFinite(r.value)) return r.value !== r.value ? `Хм, у примера ${r.expr} нет ответа в обычных числах 🤔` : 'На ноль делить нельзя! Даже нейросетям 🙂';
    return `${r.expr} = **${U.num(r.value)}**`;
  }

  // ---------- время и даты ----------
  const DAYS = ['воскресенье', 'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота'];
  const MONTHS = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
  const MONTHS_N = ['январь', 'февраль', 'март', 'апрель', 'май', 'июнь', 'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'];
  function timeText(now) {
    const h = now.getHours(), m = now.getMinutes();
    const part = h < 5 ? 'ночи' : h < 12 ? 'утра' : h < 17 ? 'дня' : 'вечера';
    const hh = String(h).padStart(2, '0'), mm = String(m).padStart(2, '0');
    const extra = h >= 22 || h < 5 ? ' Уже поздно, не пора ли спать? 🌙' : h < 9 ? ' Доброе утро! ☀️' : '';
    return `Сейчас **${hh}:${mm}** (${h % 12 || 12} ${part}).${extra}`;
  }
  function dateText(now, text) {
    const t = low(text);
    let d = now, when = 'Сегодня';
    if (/послезавтра/.test(t)) { d = new Date(now.getTime() + 2 * 864e5); when = 'Послезавтра'; }
    else if (/завтра/.test(t)) { d = new Date(now.getTime() + 864e5); when = 'Завтра'; }
    else if (/вчера/.test(t)) { d = new Date(now.getTime() - 864e5); when = 'Вчера был'; }
    if (/какой (сейчас )?год|который год/.test(t)) return `Сейчас **${now.getFullYear()}** год.`;
    if (/месяц/.test(t)) return `Сейчас **${MONTHS_N[now.getMonth()]}** ${now.getFullYear()} года.`;
    const dow = d.getDay(), weekend = dow === 0 || dow === 6;
    let s = `${when} **${DAYS[dow]}, ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}** года.`;
    if (/выходн/.test(t)) s += weekend ? ' Да, это выходной! 🎉' : ' Это будний день.';
    return s;
  }
  function countdownText(now, text) {
    const t = low(text), y = now.getFullYear(), day = 864e5;
    const start = new Date(y, now.getMonth(), now.getDate());
    const until = (date) => Math.round((date - start) / day);
    let target, what;
    if (/лет/.test(t)) { target = new Date(y, 5, 1); if (target <= start) target = new Date(y + 1, 5, 1); what = 'лета'; }
    else if (/зим/.test(t)) { target = new Date(y, 11, 1); if (target <= start) target = new Date(y + 1, 11, 1); what = 'зимы'; }
    else if (/сентябр|школ/.test(t)) { target = new Date(y, 8, 1); if (target <= start) target = new Date(y + 1, 8, 1); what = '1 сентября'; }
    else if (/каникул/.test(t)) {
      const c = [new Date(y, 0, 1), new Date(y, 2, 23), new Date(y, 4, 27), new Date(y, 9, 27), new Date(y, 11, 29), new Date(y + 1, 0, 1)].find(x => x > start);
      target = c; what = 'ближайших каникул (примерно)';
    } else { target = new Date(y + 1, 0, 1); what = 'Нового года'; }
    const n = until(target);
    return `До ${what} осталось **${n} ${U.plural(n, 'день', 'дня', 'дней')}** ${what === 'Нового года' ? '🎄' : '⏳'}`;
  }

  // ---------- маленькие игры ----------
  function coin(rnd) { return rnd() < 0.5 ? 'Подбрасываю... 🪙 Выпал **орёл**!' : 'Подбрасываю... 🪙 Выпала **решка**!'; }
  const DIE = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
  function dice(text, rnd) {
    const t = Text.wordsToDigits(low(text));
    let n = 1; const m = /(\d+)\s*(?:кубик|кост|игральн)/.exec(t); if (m) n = U.clamp(parseInt(m[1], 10), 1, 6);
    const r = []; for (let i = 0; i < n; i++) r.push(1 + Math.floor(rnd() * 6));
    const faces = r.map(v => DIE[v - 1]).join(' ');
    return n === 1 ? `Бросаю кубик... ${faces} Выпало **${r[0]}**!` : `Бросаю ${n} ${U.plural(n, 'кубик', 'кубика', 'кубиков')}... ${faces} Выпало ${r.join(' + ')} = **${r.reduce((a, b) => a + b, 0)}**`;
  }
  function random(text, rnd) {
    const t = Text.wordsToDigits(low(text));
    let a = 1, b = 100; const m = /от\s*(-?\d+)\s*до\s*(-?\d+)/.exec(t) || /(-?\d+)\s*-\s*(-?\d+)/.exec(t);
    if (m) { a = parseInt(m[1], 10); b = parseInt(m[2], 10); if (a > b) [a, b] = [b, a]; }
    else { const one = /до\s*(\d+)/.exec(t); if (one) b = parseInt(one[1], 10); }
    const v = a + Math.floor(rnd() * (b - a + 1));
    return `Случайное число от ${a} до ${b}: **${v}** 🎲`;
  }
  function chooseOptions(text) {
    let t = low(text).replace(/[?!.]+$/, '').trim();
    t = t.replace(/^(?:а\s+)?(?:амиго\s+)?(?:что\s+лучше|что\s+выбрать|выбери(?:\s+мне)?|помоги\s+выбрать|как\s+думаешь|ты\s+за|что\s+ты\s+выберешь|что\s+ты\s+больше\s+любишь|что\s+круче|кто\s+круче|кто\s+сильнее|что\s+вкуснее)[:,]?\s*/, '');
    if (!/\sили\s/.test(' ' + t + ' ')) return null;
    const parts = t.split(/\s*,\s*|\s+или\s+(?:за\s+)?/).map(x => x.replace(/^за\s+/, '').trim()).filter(Boolean);
    return parts.length >= 2 && parts.length <= 8 ? parts : null;
  }
  const RPS = { к: 'камень', н: 'ножницы', б: 'бумага' }, RPS_E = { камень: '✊', ножницы: '✌️', бумага: '✋' };
  function rpsMove(text) {
    const t = low(text);
    if (/камен|камн|кулак/.test(t)) return 'камень';
    if (/ножниц/.test(t)) return 'ножницы';
    if (/бумаг|ладон/.test(t)) return 'бумага';
    return null;
  }
  function rpsJudge(a, b) { if (a === b) return 0; return (a === 'камень' && b === 'ножницы') || (a === 'ножницы' && b === 'бумага') || (a === 'бумага' && b === 'камень') ? 1 : -1; }

  // ответ на загадку подходит, если совпадает хотя бы одна основа слова
  function answerMatches(text, answers) {
    const st = new Set(Text.words(text).map(Text.stem));
    return answers.some(a => Text.words(a).map(Text.stem).every(s => st.has(s)));
  }
  // вариант ответа в викторине: буква, цифра или сам текст
  function quizPick(text, opts) {
    const t = Text.clean(text);
    const L = [['а', 'a', '1', 'первый', 'первое', 'один'], ['б', 'b', '2', 'второй', 'второе', 'два'], ['в', 'c', 'v', '3', 'третий', 'третье', 'три']];
    const ws = t.split(' ');
    for (let i = 0; i < opts.length; i++) if (ws.some(w => L[i].includes(w))) return i;
    for (let i = 0; i < opts.length; i++) if (answerMatches(t, [opts[i]])) return i;
    return -1;
  }

  // ---------- таймер ----------
  function duration(text) {
    const t = Text.wordsToDigits(low(text));
    let sec = 0, found = false;
    if (/полчаса/.test(t)) { sec += 1800; found = true; }
    if (/полминуты/.test(t)) { sec += 30; found = true; }
    const re = /(\d+(?:[.,]\d+)?)\s*(секунд[а-я]*|сек(?![а-яa-z0-9])|с(?![а-яa-z0-9])|минут[а-я]*|мин(?![а-яa-z0-9])|м(?![а-яa-z0-9])|час[а-я]*|ч(?![а-яa-z0-9]))/g;
    let m;
    while ((m = re.exec(t))) {
      const n = parseFloat(m[1].replace(',', '.')), u = m[2];
      sec += n * (/^с/.test(u) ? 1 : /^м/.test(u) ? 60 : 3600); found = true;
    }
    if (!found) {
      if (/через\s+час|на\s+час|(?:^|\s)час(?![а-яa-z0-9])/.test(t)) sec = 3600;
      else if (/минут(у|ку)(?![а-яa-z0-9])/.test(t)) sec = 60;
      else if (/секунд(у|очку)(?![а-яa-z0-9])/.test(t)) sec = 1;
    }
    return Math.round(Math.min(sec, 24 * 3600));
  }
  function timerLabel(text) {
    let t = low(text).replace(/[.!?]+$/, '');
    const m = /(?:напомни|разбуди)(?:\s+мне)?\s+(?:через\s+)?(?:[\d.,]+\s*\S+|полчаса|час|минуту)\s+(?:что\s+(?:надо|нужно)\s+|чтобы\s+|о\s+том\s+что\s+|про\s+)?(.+)$/.exec(t);
    return m ? m[1].trim() : '';
  }
  function durText(s) {
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60, out = [];
    if (h) out.push(`${h} ${U.plural(h, 'час', 'часа', 'часов')}`);
    if (m) out.push(`${m} ${U.plural(m, 'минуту', 'минуты', 'минут')}`);
    if (sec) out.push(`${sec} ${U.plural(sec, 'секунду', 'секунды', 'секунд')}`);
    return out.join(' ') || '0 секунд';
  }

  // ---------- мини-энциклопедия ----------
  const STOP = new Set(['что', 'такое', 'кто', 'такой', 'такая', 'такие', 'это', 'про', 'о', 'об', 'расскажи', 'мне', 'а', 'ты', 'знаешь', 'объясни', 'значит', 'слово', 'за', 'и', 'в', 'на', 'ну']);
  const kbIndex = KB.map(e => ({ e, al: e.a.map(a => Text.words(a).map(Text.stem)) }));
  function kbFind(topic) {
    const st = new Set(Text.words(topic).filter(w => !STOP.has(w)).map(Text.stem));
    if (!st.size) return null;
    let best = null, bestLen = 0;
    for (const { e, al } of kbIndex) for (const a of al) {
      if (a.every(s => st.has(s)) && a.length > bestLen && a.length >= st.size - 1) { best = e; bestLen = a.length; }
    }
    return best;
  }
  // тема вопроса: «что такое чёрная дыра?» → «чёрная дыра»
  function topicOf(text) {
    let t = String(text).trim().replace(/[?!.…]+$/, '').trim();
    const re = /^(?:(?:а|ну|слушай|амиго|скажи|скажи-ка|пожалуйста)[,\s]+)*(?:ты\s+)?(?:знаешь\s+|не\s+знаешь\s+)?(?:что\s+такое|что\s+это\s+такое|кто\s+такой|кто\s+такая|кто\s+такие|что\s+значит\s+слово|что\s+значит|что\s+означает\s+слово|что\s+означает|что\s+за|расскажи(?:\s+мне)?\s+(?:про|о|об|обо)|что\s+ты\s+знаешь\s+(?:про|о|об)|что\s+известно\s+(?:про|о|об)|объясни(?:\s+мне)?(?:\s+что\s+такое)?|кто\s+изобр[её]л|кто\s+придумал|кто\s+открыл|где\s+находится|где\s+находятся|как\s+устроен[аоы]?|из\s+чего\s+состоит|зачем\s+нужн[аоы]?|сколько\s+лет|сколько\s+весит|информация\s+о|инфа\s+про)\s+/i;
    const m = re.exec(t);
    return m ? t.slice(m[0].length).trim() : '';
  }

  // ---------- перевод ----------
  const REV = {};
  for (const [ru, [en, es]] of Object.entries(DICT)) { REV[en.toLowerCase()] = REV[en.toLowerCase()] || ru; REV[es.toLowerCase()] = REV[es.toLowerCase()] || ru; }
  function translate(text) {
    const t = low(text).replace(/[?!.]+$/, '').trim();
    const lang = /испан|spanish|espan/.test(t) ? 'es' : 'en';
    const langName = lang === 'es' ? 'по-испански' : 'по-английски';
    let w = '';
    const pats = [
      /переведи(?:\s+мне)?(?:\s+слово)?\s+[«"]?([^«»"]+?)[»"]?\s+(?:на|с)\s+\S+$/, /переведи(?:\s+мне)?(?:\s+на\s+\S+)?(?:\s+слово)?\s+[«"]?([^«»"]+?)[»"]?$/,
      /как\s+(?:по[\s-]+\S+|на\s+\S+)\s+(?:будет\s+)?(?:слово\s+)?[«"]?([^«»"]+?)[»"]?$/, /как\s+(?:будет|сказать|написать|пишется)\s+(?:слово\s+)?[«"]?([^«»"]+?)[»"]?\s+(?:по[\s-]+\S+|на\s+\S+)$/,
      /перевод\s+(?:слова\s+)?[«"]?([^«»"]+?)[»"]?(?:\s+на\s+\S+)?$/, /что\s+(?:значит|означает)\s+(?:слово\s+)?[«"]?([^«»"]+?)[»"]?$/, /как\s+переводится\s+(?:слово\s+)?[«"]?([^«»"]+?)[»"]?$/,
      /^[«"]?([^«»"]+?)[»"]?\s+(?:по[\s-]+(?:английски|испански)|на\s+(?:английском|испанском))$/,
    ];
    for (const re of pats) { const m = re.exec(t); if (m) { w = m[1].trim(); break; } }
    if (!w) return { need: true };
    if (/^[a-záéíóúñü¿?\s'-]+$/i.test(w)) {
      const ru = REV[w.toLowerCase()];
      return ru ? { text: `«${w}» — это **«${ru}»** по-русски.` } : { unknown: w, reverse: true };
    }
    const key = Text.clean(w);
    let hit = DICT[key];
    if (!hit) { const s = Text.stem(key); for (const k of Object.keys(DICT)) if (Text.stem(k) === s) { hit = DICT[k]; break; } }
    if (!hit) return { unknown: w, lang };
    const other = lang === 'es' ? `, а по-английски — «${hit[0]}»` : `, а по-испански — «${hit[1]}»`;
    return { text: `«${w}» ${langName} — **${lang === 'es' ? hit[1] : hit[0]}**${other}.` };
  }

  // ---------- погода: город ----------
  // координаты популярных городов, чтобы не искать их каждый раз
  const CITIES = [
    ['Москва', 55.7558, 37.6173, ['москва', 'мск']], ['Санкт-Петербург', 59.9343, 30.3351, ['петербург', 'питер', 'спб', 'санкт петербург']],
    ['Новосибирск', 55.0084, 82.9357, ['новосибирск']], ['Екатеринбург', 56.8389, 60.6057, ['екатеринбург', 'екб']], ['Казань', 55.7963, 49.1088, ['казань']],
    ['Нижний Новгород', 56.2965, 43.9361, ['нижний новгород', 'нижний']], ['Челябинск', 55.1644, 61.4368, ['челябинск']], ['Самара', 53.1959, 50.1002, ['самара']],
    ['Омск', 54.9885, 73.3242, ['омск']], ['Ростов-на-Дону', 47.2357, 39.7015, ['ростов', 'ростов на дону']], ['Уфа', 54.7388, 55.9721, ['уфа']],
    ['Красноярск', 56.0153, 92.8932, ['красноярск']], ['Пермь', 58.0105, 56.2502, ['пермь']], ['Воронеж', 51.672, 39.1843, ['воронеж']],
    ['Волгоград', 48.708, 44.5133, ['волгоград']], ['Краснодар', 45.0355, 38.9753, ['краснодар']], ['Сочи', 43.5855, 39.7231, ['сочи']],
    ['Владивосток', 43.1155, 131.8855, ['владивосток']], ['Калининград', 54.7104, 20.4522, ['калининград']], ['Иркутск', 52.287, 104.305, ['иркутск']],
    ['Тюмень', 57.153, 65.5343, ['тюмень']], ['Минск', 53.9006, 27.559, ['минск']], ['Алматы', 43.222, 76.8512, ['алматы', 'алма ата']],
    ['Астана', 51.1694, 71.4491, ['астана']], ['Ташкент', 41.2995, 69.2401, ['ташкент']], ['Киев', 50.4501, 30.5234, ['киев']], ['Ереван', 40.1792, 44.4991, ['ереван']],
    ['Тбилиси', 41.7151, 44.8271, ['тбилиси']], ['Бишкек', 42.8746, 74.5698, ['бишкек']], ['Лондон', 51.5072, -0.1276, ['лондон', 'london']],
    ['Париж', 48.8566, 2.3522, ['париж', 'paris']], ['Берлин', 52.52, 13.405, ['берлин', 'berlin']], ['Рим', 41.9028, 12.4964, ['рим']],
    ['Мадрид', 40.4168, -3.7038, ['мадрид']], ['Нью-Йорк', 40.7128, -74.006, ['нью йорк', 'нью-йорк', 'new york']], ['Токио', 35.6762, 139.6503, ['токио', 'tokyo']],
    ['Пекин', 39.9042, 116.4074, ['пекин']], ['Дубай', 25.2048, 55.2708, ['дубай']], ['Стамбул', 41.0082, 28.9784, ['стамбул']],
  ].map(([name, lat, lon, al]) => ({ name, lat, lon, al: al.map(a => Text.words(a).map(Text.stem).join(' ')) }));
  const WEATHER_STOP = new Set(['сегодня', 'завтра', 'послезавтра', 'сейчас', 'утром', 'вечером', 'днем', 'ночью', 'там', 'у', 'нас', 'на', 'улице', 'неделю', 'выходные', 'будет', 'какая', 'погода', 'погоду', 'погоды']);
  function cityPhrase(text) {
    const ws = Text.words(text).filter(w => !WEATHER_STOP.has(w));
    for (let i = ws.length - 1; i >= 0; i--) if (ws[i] === 'в' || ws[i] === 'во') return ws.slice(i + 1, i + 3).join(' ');
    // «погода москва»
    const all = Text.words(text), p = all.findIndex(w => /^погод/.test(w));
    if (p >= 0 && all[p + 1] && !WEATHER_STOP.has(all[p + 1]) && all[p + 1] !== 'в') return all.slice(p + 1, p + 3).filter(w => !WEATHER_STOP.has(w)).join(' ');
    return '';
  }
  function cityKnown(phrase) {
    if (!phrase) return null;
    const ws = Text.words(phrase).map(Text.stem);
    for (const n of [2, 1]) {
      if (ws.length < n) continue;
      const key = ws.slice(0, n).join(' ');
      const c = CITIES.find(c => c.al.includes(key));
      if (c) return c;
    }
    return null;
  }
  // варианты именительного падежа: «лондоне» → «лондон», «самаре» → «самара», «твери» → «тверь»
  function cityGuesses(phrase) {
    const ws = phrase.split(' '), last = ws.pop(), pre = ws.length ? ws.join(' ') + ' ' : '';
    const out = [phrase];
    if (/е$/.test(last)) { out.push(pre + last.slice(0, -1), pre + last.slice(0, -1) + 'а', pre + last.slice(0, -1) + 'я'); }
    else if (/и$/.test(last)) { out.push(pre + last.slice(0, -1) + 'ь', pre + last.slice(0, -1) + 'я'); }
    else if (/у$/.test(last)) { out.push(pre + last.slice(0, -1) + 'а'); }
    return [...new Set(out)];
  }
  const WMO = { 0: ['ясно', '☀️'], 1: ['почти ясно', '🌤️'], 2: ['переменная облачность', '⛅'], 3: ['пасмурно', '☁️'], 45: ['туман', '🌫️'], 48: ['туман с изморозью', '🌫️'],
    51: ['слабая морось', '🌦️'], 53: ['морось', '🌦️'], 55: ['сильная морось', '🌧️'], 56: ['ледяная морось', '🌧️'], 57: ['ледяная морось', '🌧️'],
    61: ['небольшой дождь', '🌦️'], 63: ['дождь', '🌧️'], 65: ['сильный дождь', '🌧️'], 66: ['ледяной дождь', '🌧️'], 67: ['ледяной дождь', '🌧️'],
    71: ['небольшой снег', '🌨️'], 73: ['снег', '🌨️'], 75: ['сильный снегопад', '❄️'], 77: ['снежная крупа', '🌨️'], 80: ['ливень', '🌦️'], 81: ['ливни', '🌧️'],
    82: ['очень сильный ливень', '⛈️'], 85: ['снегопад', '🌨️'], 86: ['сильный снегопад', '❄️'], 95: ['гроза', '⛈️'], 96: ['гроза с градом', '⛈️'], 99: ['гроза с сильным градом', '⛈️'] };
  function wmo(code) { return WMO[code] || ['непонятная погода', '🌈']; }
  function dressTip(t, code) {
    const wet = (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
    let s = t <= -15 ? 'Очень холодно: тёплая куртка, шапка, шарф и варежки!' : t <= 0 ? 'Холодно: надень куртку и шапку.' : t <= 10 ? 'Прохладно: куртка не помешает.'
      : t <= 18 ? 'Свежо: подойдёт кофта или лёгкая куртка.' : t <= 25 ? 'Тепло и приятно!' : 'Жарко: пей воду и не забудь кепку.';
    if (wet) s += ' Возьми зонт ☂️';
    return s;
  }

  // ---------- бессмыслица: нет гласных, длинные ряды согласных, «ряды» клавиатуры ----------
  function isGibberish(text) {
    const ws = Text.words(text).filter(w => w.length >= 4 && !/\d/.test(w));
    if (!ws.length || ws.length !== Text.words(text).length) return false;
    return ws.every(w => /^[а-я]+$/.test(w)
      ? (!/[аеиоуыэюя]/.test(w) || /[бвгджзйклмнпрстфхцчшщ]{5,}/.test(w) || /фыва|олдж|йцук|ячсм|цукен|ролд|вапр|шщз/.test(w) || /^(.{2,3})\1+$/.test(w))
      : (/^[a-z]+$/.test(w) && (!/[aeiouy]/.test(w) || /[bcdfghjklmnpqrstvwxz]{5,}/.test(w) || /qwer|asdf|zxcv|sdfg|hjkl/.test(w))));
  }

  return { calc, calcText, timeText, dateText, countdownText, coin, dice, random, chooseOptions, rpsMove, rpsJudge, RPS_E, answerMatches, quizPick,
    duration, timerLabel, durText, kbFind, topicOf, translate, cityPhrase, cityKnown, cityGuesses, wmo, dressTip, isGibberish, DAYS, MONTHS };
})();

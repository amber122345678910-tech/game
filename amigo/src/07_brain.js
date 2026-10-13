/* ===== 07_brain.js ===== */
// Мозг Амиго: нейросеть определяет тему, а дальше навыки, игры, память и обучение строят ответ.
const BRAIN_TH = 0.3;            // ниже этой уверенности Амиго считает, что не понял
const BRAIN_MARGIN = 0.08;       // и если две темы почти равны — тоже
const CRISIS_RE = /(хочу|хочется|буду)\s+(умереть|сдохнуть|покончить)|не\s+хочу\s+(больше\s+)?жить|жить\s+не\s+хочу|покончить\s+с\s+собой|убить\s+себя|меня\s+(бьют|избивают|травят|буллят)|самоубий/;
const TEACH_RE = /^(?:запомни[:,]?\s*)?(?:когда|если)\s+я\s+(?:говорю|пишу|скажу|напишу)\s+[«"']?(.+?)[»"']?[,\s]+(?:то\s+)?(?:ты\s+)?(?:отвечай|ответь|говори|скажи|пиши)\s+[«"']?(.+?)[»"']?\s*$/i;
const TEACH_RE2 = /^на\s+[«"'](.+?)[»"']\s+(?:отвечай|ответь|говори)\s+[«"']?(.+?)[»"']?\s*$/i;
const NAME_RE = /(?:^|[\s,.!])(?:меня\s+зовут|мо[её]\s+имя(?:\s*[-—:]|\s+это)?|зови\s+меня|называй\s+меня|можешь\s+звать\s+меня)\s+([A-Za-zА-Яа-яЁё][A-Za-zА-Яа-яЁё-]{1,24})(?:\s+([A-Za-zА-Яа-яЁё][A-Za-zА-Яа-яЁё-]{1,24}))?/i;
const NOT_NAMES = new Set(['не', 'никак', 'секрет', 'тайна', 'зовут', 'так', 'просто', 'ты', 'я', 'да', 'нет', 'это', 'кто', 'как', 'а', 'и', 'вообще', 'никто', 'там', 'все']);
const WHO_AI_RE = /(клауд|клод|claude|антропик|anthropic)/;
const OTHER_AI_RE = /(чат\s?гпт|chat\s?gpt|gpt|гпт|алис[аеу]|siri|сири|gemini|джемини|гигачат|яндекс\s?gpt)/;
const YOU_RE = /(^|\s)(ты|тебя|тебе|тобой|вы|амиго)(?![а-яa-z])/;
const AGE_RE = /(?:^|\s)мне\s+(\d{1,2})\s*(?:лет|год|года)(?![а-яa-z0-9])/;

class Brain {
  constructor(model, opts = {}) {
    this.model = model;
    this.D = model.D;
    this.rnd = opts.rnd || Math.random;
    this.now = opts.now || (() => new Date());
    this.online = opts.online || Online;
    this.profile = Object.assign({ name: '', facts: [], city: null, age: 0, likes: [], dislikes: [], has: [], wants: [], favs: {}, grade: null, from: '', words: {}, asked: [] }, opts.profile || {});
    this.ensureProfile();
    Lex.addUser(this.profile.words);
    this.settings = Object.assign({ voice: false, superOn: false, superTier: 'quick', apiKey: '', model: 'claude-opus-5-5', online: true, codexOn: false, codexLevel: 'high', codexAsk: true }, opts.settings || {});
    // с версии 2 Амиго по умолчанию отвечает сам, без супер-мозга
    if (!this.settings.v) { this.settings.superOn = false; this.settings.v = 2; }
    this.codexMem = { words: Object.assign({}, opts.codexMem && opts.codexMem.words), recipes: (opts.codexMem && opts.codexMem.recipes || []).slice() };
    this.lastSpec = null;
    if (model.codex) Codex.setNet(model.codex);
    this.customs = (opts.customs || []).map(c => Object.assign({}, c, { custom: true }));
    this.ctx = null;        // текущий режим: игра, вопрос, обучение
    this.lastAct = null;    // для «ещё»
    this.history = [];      // реплики для супер-мозга
    this.decks = {};        // перемешанные колоды шуток, фактов и т.п.
    this.lastCls = null;
    this.topic = null;      // о чём сейчас разговор (для «а ты?»)
    this.prevUserText = ''; // прошлая фраза пользователя (для «ты не прав»)
    this.lastBotText = '';  // прошлый ответ Амиго (для «не понял»)
    this.lastIntent = null;
    this.onSave = opts.onSave || null;
    this.reset();
  }

  // собрать сеть из встроенной модели и добавить выученное пользователем
  reset() {
    this.net = MLP.fromJSON(this.model.net);
    this.base = Data.build(INTENTS, [], { noExamples: true });
    if (this.base.tags.join() !== this.model.tags.join()) console.warn('Амиго: модель не совпадает с данными, пересоберите index.html');
    this.intents = this.base.intents.slice();
    this.tuned = 0;
    this.syncCustoms();
  }
  syncCustoms() {
    for (const c of this.customs) if (!this.intents.some(i => i.tag === c.tag)) { this.intents.push(c); this.net.addClass(); }
    this.tags = this.intents.map(i => i.tag);
    this.byTag = new Map(this.intents.map(i => [i.tag, i]));
  }
  get needsTuning() { return this.customs.length > 0 && this.tuned !== this.customVersion(); }
  customVersion() { return this.customs.reduce((s, c) => s + c.p.length * 31 + c.tag.length, this.customs.length); }

  // ---------- нейросеть ----------
  classify(text) {
    let best = this.classifyRaw(text);
    // сокращения и опечатки: пробуем «расшифрованный» вариант и берём тот, в котором сеть увереннее
    const clean = Text.clean(text), exp = Spell.expand(text), fixed = Spell.fix(exp);
    for (const v of [exp, fixed]) {
      if (!v || v === clean) continue;
      const b = this.classifyRaw(v);
      if (b.conf > best.conf + 0.05) { b.text = text; b.fixed = v; best = b; }
    }
    this.lastCls = best;
    return best;
  }
  classifyRaw(text) {
    const x = Text.features(text, this.D, true);
    const f = this.net.forward(x);
    const p = Float32Array.from(f.p), hid = Float32Array.from(f.hid);
    const order = Array.from(p.keys()).sort((a, b) => p[b] - p[a]);
    const top = order.slice(0, 5).map(i => ({ tag: this.tags[i], title: (this.byTag.get(this.tags[i]) || {}).t || this.tags[i], p: p[i] }));
    // какая доля признаков фразы знакома сети (строка весов не нулевая)
    let known = 0, H = this.net.H;
    for (let k = 0; k < x.idx.length; k++) {
      const row = x.idx[k] * H; let nz = false;
      for (let h = 0; h < H; h++) if (this.net.W1[row + h] !== 0) { nz = true; break; }
      if (nz) known += x.val[k] * x.val[k];
    }
    return { tag: top[0].tag, conf: top[0].p, margin: top[0].p - (top[1] ? top[1].p : 0), top, x, hid, p, known, text };
  }
  // дообучение на фразах пользователя: новые выходы + повтор старых примеров, чтобы не забыть прежнее
  async fineTune(opt = {}) {
    if (!this.customs.length) { this.tuned = this.customVersion(); return []; }
    const rnd = U.rng(99);
    const ds = Data.build(INTENTS, this.customs.map(c => Object.assign({}, c, { custom: true })));
    const baseN = this.base.tags.length;
    const own = ds.examples.filter(e => e.y >= baseN);
    const replay = U.shuffle(ds.examples.filter(e => e.y < baseN), rnd).slice(0, Math.max(600, own.length * 4));
    const ex = Data.featurize(own.concat(replay), this.D);
    this.net.resetOptimizer();
    const hist = await this.net.train(ex, { epochs: opt.epochs || 8, batch: 16, lr: 0.005, lrMin: 0.001, smooth: 0.1, dropout: 0.2, seed: 5, tick: opt.tick, onEpoch: opt.onEpoch });
    this.tuned = this.customVersion();
    return hist;
  }
  // на телефоне полное обучение долгое, поэтому в браузере эпох меньше, чем при сборке
  get retrainEpochs() { return Math.min(this.model.epochs || 20, 8); }
  // полное переобучение с нуля (кнопка в панели «Мозг»)
  async retrain(opt = {}) {
    const ds = Data.build(INTENTS, this.customs.map(c => Object.assign({}, c, { custom: true })));
    const ex = Data.featurize(ds.examples, this.D);
    const net = new MLP(this.D, this.model.H, ds.tags.length, 1);
    const hist = await net.train(ex, Object.assign({ epochs: this.retrainEpochs, batch: 16, lr: 0.01, smooth: 0.1, dropout: 0.2, seed: 7 }, opt));
    this.net = net; this.intents = ds.intents; this.tags = ds.tags; this.byTag = new Map(this.intents.map(i => [i.tag, i]));
    this.tuned = this.customVersion();
    return hist;
  }

  // ---------- память ----------
  save() { if (this.onSave) this.onSave({ profile: this.profile, settings: this.settings, customs: this.customs.map(({ tag, t, p, r }) => ({ tag, t, p, r })), codexMem: this.codexMem }); }
  forgetCodex(kind, key) {
    if (kind === 'recipe') this.codexMem.recipes = this.codexMem.recipes.filter(r => r.name !== key);
    else { for (const k of Object.keys(this.codexMem.words)) if (k === key || this.codexMem.words[k].name === key) delete this.codexMem.words[k]; }
    this.save();
  }
  learn(phrase, answer) {
    const p = Text.clean(phrase), a = String(answer).trim();
    if (!p || !a) return null;
    let c = this.customs.find(c => c.r[0].toLowerCase() === a.toLowerCase());
    if (!c) {
      const id = 1 + this.customs.reduce((m, c) => Math.max(m, parseInt(c.tag.slice(7), 10) || 0), 0);
      c = { tag: 'custom_' + id, t: '«' + (phrase.length > 28 ? phrase.slice(0, 27) + '…' : phrase) + '»', p: [], r: [a], custom: true };
      this.customs.push(c);
    }
    if (!c.p.includes(p)) c.p.push(p);
    this.syncCustoms();
    this.save();
    return c;
  }
  forgetCustom(tag) {
    this.customs = this.customs.filter(c => c.tag !== tag);
    this.reset();
    this.save();
  }
  // быстрый поиск по выученным фразам, пока сеть ещё не дообучилась
  taughtMatch(text) {
    if (!this.customs.length) return null;
    const x = Text.features(text, this.D);
    let best = null, bs = 0;
    for (const c of this.customs) for (const p of c.p) {
      const s = Text.cosine(x, Text.features(p, this.D));
      if (s > bs) { bs = s; best = c; }
    }
    return bs >= 0.86 ? best : null;
  }

  // ---------- оформление ответа ----------
  fill(s) {
    const n = this.profile.name;
    return String(s).replace(/\{,name\}/g, n ? ', ' + n : '').replace(/\{name\}/g, n || 'друг')
      .replace(/\{hidden\}/g, String(this.net.H)).replace(/\{params\}/g, U.num(this.net.params)).replace(/\{intents\}/g, String(this.tags.length));
  }
  deal(kind, list) {
    let d = this.decks[kind];
    if (!d || !d.length) d = this.decks[kind] = U.shuffle(list.map((_, i) => i), this.rnd);
    return d.pop();
  }
  say(text, extra = {}) { return Object.assign({ text }, extra); }

  // ---------- главный вход ----------
  async reply(raw, io = {}) {
    const text = String(raw).trim().slice(0, 2000);
    const t = Text.clean(text);
    this.history.push({ role: 'user', content: text });
    let a;
    this._topicSet = false;
    try { a = await this.route(text, t, io); }
    catch (e) { console.error(e); a = this.say('Ой, у меня в нейронах что-то перепуталось 😵 Попробуй сказать по-другому.', { src: 'rule', mood: 'sad' }); }
    if (a.offer && !this.ctx) this.ctx = { type: 'offer', act: a.offer };
    a.text = this.fill(a.text);
    if (a.chips) a.chips = a.chips.map(c => this.fill(c));
    if (!this._topicSet && a.intent) this.topic = { kind: 'intent', tag: a.intent };
    // Амиго спросил «как дела?» — следующий ответ поймём как рассказ о настроении
    if (!this.ctx && /(как\s+(твои\s+|у\s+тебя\s+)?дела|а\s+(ты|у\s+тебя)\s+как|как\s+ты\s+сам|как\s+настроение|как\s+спалось|как\s+ты\s+себя\s+чувствуешь|как\s+прош[её]л\s+(твой\s+)?день)[^.!?]*\?\s*$/i.test(a.text)) this.ctx = { type: 'expect', key: 'mood' };
    this.prevUserText = text; this.lastBotText = a.text; this.lastIntent = a.intent || null;
    if (this.mainCls) { this.lastCls = this.mainCls; this.mainCls = null; }
    this.history.push({ role: 'assistant', content: a.text });
    if (this.history.length > 40) this.history.splice(0, this.history.length - 40);
    return a;
  }

  async route(text, t, io, sub = false) {
    if (!t) {
      if (/[\d+\-*/^()]/.test(text)) { const r = Skills.calc(text, true); if (r) return this.say(Skills.calcText(r), { src: 'skill', intent: 'calc' }); }
      return this.say(U.pick(['😊', '🙂 Напиши мне что-нибудь словами!', '👍'], this.rnd), { src: 'rule' });
    }
    if (CRISIS_RE.test(t)) { this.ctx = null; return this.say(CRISIS_TEXT, { src: 'rule', intent: 'crisis', mood: 'care' }); }

    // «когда я говорю X, отвечай Y»
    const tm = TEACH_RE.exec(text) || TEACH_RE2.exec(text);
    if (tm) {
      this.ctx = null;
      this.learn(tm[1], tm[2]);
      return this.say(`Запомнил! Когда ты скажешь «${tm[1]}», я отвечу «${tm[2]}» ✅`, { src: 'rule', intent: 'teach', mood: 'learn', action: { type: 'learned' } });
    }

    const cls = this.classify(text);
    if (!sub) this.mainCls = cls;

    if (this.ctx) {
      const r = await this.inCtx(text, t, cls, io);
      if (r) return r;
    }

    // несколько частей: «привет, как дела?», «спасибо! а ты?»
    if (!sub && !this.settings.codexOn) { const r = await this.routeMulti(text, io); if (r) return r; }

    // режим Кодекс: команды и описания игр
    const cc = this.codexCommand(text, t, cls);
    if (cc) return cc;
    if (this.settings.codexOn && !CRISIS_RE.test(t)) { const r = await this.codexMessage(text, t, cls, io); if (r) return r; }
    // правка последней игры: только если сеть не видит во фразе другой ясной темы («смысл жизни», «телефон» — не правки)
    else if (this.lastSpec && this.looksEdit(t) && /(игр|(?:^|\s)(?:ее|её|его)(?:\s|$)|быстрее|медленнее|сложнее|легче|босс|вместо|жизн|(?:^|\s)мир|(?:^|\s)фон|поменя|добав|назови|переименуй)/.test(t) && !GameList.find(text) &&
      !(cls.conf >= 0.5 && !['make_game', 'statement', 'more', 'codex_on', 'show_code'].includes(cls.tag))) return this.codexEdit(text, io);

    // «ты Claude?» — отвечает сам Амиго, честно и от своего имени
    if (WHO_AI_RE.test(t) && (YOU_RE.test(t) || t.split(' ').length <= 2)) return this.handle('are_you_claude', text, t, cls, io);
    if (OTHER_AI_RE.test(t) && YOU_RE.test(t)) return this.handle('compare_ai', text, t, cls, io);

    // пример по математике
    const m = Skills.calc(text, false);
    if (m) { this.lastAct = null; return this.say(Skills.calcText(m), { src: 'skill', intent: 'calc', conf: cls.tag === 'calc' ? cls.conf : undefined }); }

    // игры в чате
    const gameDesc = /(^|\s)(сделай|создай|придумай|напиши|запрограммируй|сочини|собери)\s+(мне\s+|нам\s+)?(\S+\s+)?(игр|игрушк)/.test(t) || /^(игр\S*|игрушк\S*)\s+(про|где|о|об|в\s+которой|с)\s/.test(t + ' ');
    if (GameList.find(text) || gameDesc || (cls.tag === 'make_game' && cls.conf >= BRAIN_TH)) return this.makeGame(text, t, cls, io);

    // «меня зовут ...»
    const nm = NAME_RE.exec(text);
    if (nm) { const r = this.setName(nm[1], nm[2]); if (r) return r; }
    const ag = AGE_RE.exec(t);
    if (ag) { this.profile.age = +ag[1]; this.save(); return this.say(`Запомнил: тебе ${ag[1]} ${U.plural(+ag[1], 'год', 'года', 'лет')} 🎂 Классный возраст!`, { src: 'rule', intent: 'remember' }); }

    // то, чему научил пользователь
    const taught = this.taughtMatch(text);
    if (taught) return this.say(taught.r[0], { src: 'taught', intent: taught.tag, conf: cls.tag === taught.tag ? cls.conf : undefined, top: cls.top });

    // знакомое слово — точно не бессмыслица («шрек», «скибиди»)
    const lexHit = Lex.main(text);
    if (Skills.isGibberish(text) && !lexHit && !(cls.conf >= 0.6 && cls.tag !== 'gibberish')) return this.handle('gibberish', text, t, cls, io);

    // «я люблю …», «ты умеешь …?» — сеть угадывает семейство, а точный вид берём по словам
    const fr = Talk.frames(text)[0];
    // одно-два знакомых слова («телефон», «мой кот»), а сеть сомневается — расскажем про слово
    if (lexHit && !fr && Text.words(text).length <= 2 && cls.conf < 0.6) return this.wordReply(lexHit, text, cls);
    if (fr && (TALK_FRAME_FAMILY.has(cls.tag) || cls.conf < 0.6) && cls.tag !== fr.type && !(cls.tag === 'love' && cls.conf >= 0.5)) return this.handle(fr.type, text, t, cls, io);

    // уверенность: чем больше знакомых признаков, тем меньше нужно запаса над второй темой
    let strong = cls.conf >= BRAIN_TH && cls.margin >= BRAIN_MARGIN && (cls.known >= 0.35 || (cls.conf >= 0.55 && cls.known >= 0.15));
    // «бессмыслица» по мнению сети, но слово похоже на настоящее — спросим, что это, а не скажем «шифр»
    if (strong && cls.tag === 'gibberish' && lexHit) return this.wordReply(lexHit, text, cls);
    if (strong && cls.tag === 'gibberish' && !Skills.isGibberish(text) && /[аеиоуыэюяaeiouy]/.test(t)) strong = false;
    if (strong) return this.handle(cls.tag, text, t, cls, io);

    // сеть не уверена: вопрос о мире → энциклопедия / супер-мозг / Википедия
    const question = /\?\s*$/.test(text) || /^(что|кто|где|когда|почему|зачем|как|какой|какая|какое|какие|сколько|чем|откуда|куда|расскажи|объясни|напиши|придумай|сочини|можно ли|правда ли|чей|чья)(?![а-яa-z0-9])/.test(t);
    // вопрос про самого Амиго — не ищем в Википедии, а берём лучшую догадку сети
    const aboutBot = /(^|\s)(ты|тебя|тебе|тобой|твой|твоя|твое|твои|амиго)(?![а-яa-z0-9])/.test(t) && cls.tag !== 'knowledge';
    const it = this.byTag.get(cls.tag) || {};
    const safe = (it.r && !it.act) || ['name_bot', 'how_works', 'help', 'age_bot'].includes(it.act);
    if (aboutBot && safe && cls.conf >= 0.18 && cls.margin >= 0.05 && !this.superMode()) return this.handle(cls.tag, text, t, cls, io);
    if (!aboutBot && !fr && (question || (cls.tag === 'knowledge' && cls.conf >= 0.3)) && !(lexHit && Text.words(text).length <= 2)) return this.knowledge(text, io, cls);
    return this.smartFallback(text, t, cls, io, { question, aboutBot });
  }

  notUnderstood(text, cls) {
    this.ctx = { type: 'teach_offer', phrase: text };
    const hint = cls.conf > 0.2 ? ` Похоже на тему «${cls.top[0].title}», но я не уверен.` : '';
    return this.say(U.pick([
      `Я пока не знаю, что на это ответить 🤔${hint} Нажми «Научить», и я запомню правильный ответ.`,
      `Хм, такого я ещё не встречал.${hint} Можешь научить меня — нажми «Научить».`,
    ], this.rnd), { src: 'net', intent: cls.tag, conf: cls.conf, top: cls.top, mood: 'think', chips: ['Научить', 'Что ты умеешь?'], unsure: true });
  }

  superMode() { return this.online.Super.mode(this.settings); }
  async askSuper(text, io, cls, prompt) {
    if (io.onThinking) io.onThinking('super');
    try {
      const hist = this.history.slice(0, -1);
      const r = await this.online.Super.ask(this.settings, this.profile, hist, prompt || text, io.onStream, io.signal);
      return this.say(r.text.trim() + (r.truncated ? '…' : ''), { src: 'claude', intent: cls && cls.tag, conf: cls && cls.conf, top: cls && cls.top });
    } catch (e) {
      if (e && e.code === 'cancelled') return this.say(e.text || 'Хорошо, остановился.', { src: 'claude', partial: true });
      if (e && e.text) return this.say(e.text + '…', { src: 'claude', partial: true });
      return null;
    }
  }

  // ---------- режимы (игры, вопросы, обучение) ----------
  async inCtx(text, t, cls, io) {
    const c = this.ctx;
    if (c.type === 'expect' || c.type === 'teach_word') return this.inCtxTalk(c, text, t, cls, io);
    const sure = cls.conf >= 0.6, tag = cls.conf >= 0.5 ? cls.tag : (cls.tag === 'yes' || cls.tag === 'no' ? '' : cls.tag);
    const quit = (tag === 'stop' && sure) || /^(стоп|хватит|выход|закончим|надоело|отмена)(?![а-яa-z0-9])/.test(t);
    const giveUp = /сда(юсь|юся)|не\s+знаю|без\s+понятия|скажи\s+ответ|какой\s+ответ|хз(?![а-яa-z0-9])|подскажи/.test(t);
    // ясно другая тема — выходим из режима и отвечаем как обычно
    const switchTopic = sure && !['yes', 'no', 'more', 'laugh', 'statement', 'dont_know', 'user_good', 'stop', 'thanks', 'gibberish', 'calc', 'random'].includes(tag);

    switch (c.type) {
      case 'offer': {
        this.ctx = null;
        if (tag === 'yes' || (tag === 'more' && sure) || /^(да|давай|ага|конечно|хочу|ок|го)(?![а-яa-z0-9])/.test(t)) return this.handle(c.act, text, t, cls, io);
        if (tag === 'no' || /^(нет|не|неа)(?![а-яa-z0-9])/.test(t)) return this.say(U.pick(['Хорошо! Я рядом, если что 🙂', 'Ладно! Тогда о чём поболтаем?', 'Как скажешь!'], this.rnd), { src: 'net', intent: 'no', conf: cls.conf, top: cls.top });
        return null;
      }
      case 'ask_name': {
        this.ctx = null;
        if (tag === 'no' || /не\s+скажу|секрет|не\s+хочу/.test(t)) return this.say('Хорошо, секрет так секрет 🙂', { src: 'rule' });
        const nm = NAME_RE.exec(text);
        if (nm) return this.setName(nm[1], nm[2]);
        const ws = text.replace(/[.!,?]+/g, ' ').trim().split(/\s+/);
        const w = ws[0] === 'я' || ws[0] === 'Я' ? ws.slice(1) : ws;
        if (w.length >= 1 && w.length <= 2 && /^[A-Za-zА-Яа-яЁё-]{2,25}$/.test(w[0]) && !NOT_NAMES.has(w[0].toLowerCase()) && !(sure && !['statement', 'set_name', 'gibberish'].includes(tag))) return this.setName(w[0], w[1]);
        return null;
      }
      case 'teach_phrase': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо, научишь в другой раз 🙂', { src: 'rule' });
        this.ctx = { type: 'teach', phrase: text };
        return this.say(`А что мне отвечать на «${text}»?`, { src: 'rule', intent: 'teach', mood: 'learn' });
      }
      case 'teach_offer': {
        this.ctx = null;
        if (/^(научить|научу|научи|давай научу|хочу научить)(?![а-яa-z0-9])/.test(t) || (tag === 'teach' && sure) || (tag === 'yes' && sure)) {
          this.ctx = { type: 'teach', phrase: c.phrase };
          return this.say(`Что мне отвечать на «${c.phrase}»? Напиши ответ 📝`, { src: 'rule', intent: 'teach', mood: 'learn', chips: ['Отмена'] });
        }
        return null;
      }
      case 'teach': {
        this.ctx = null;
        if (/^(пропустить|отмена|не\s+надо|нет|неа|потом|не\s+буду|забей)(?![а-яa-z0-9])/.test(t)) return this.say('Хорошо, пропустим 🙂', { src: 'rule' });
        this.learn(c.phrase, text);
        return this.say(U.pick([`Запомнил! Теперь на «${c.phrase}» я отвечу: «${text}» ✅`, `Ура, я стал умнее! На «${c.phrase}» теперь отвечаю «${text}» 🧠`], this.rnd),
          { src: 'rule', intent: 'teach', mood: 'learn', action: { type: 'learned' } });
      }
      case 'guess_number': {
        const n = this.numberIn(text);
        if (n !== null) {
          c.tries++;
          if (n === c.secret) {
            this.ctx = null; this.lastAct = 'guess_number';
            return this.say(`🎉 Угадал! Это было число **${c.secret}**. Попыток: ${c.tries}.${c.tries <= 7 ? ' Отличный результат!' : ''}`, { src: 'skill', intent: 'guess_number', mood: 'happy', chips: ['Ещё раз', 'Хватит'], offer: 'guess_number' });
          }
          const dir = n < c.secret ? 'больше ⬆️' : 'меньше ⬇️', d = Math.abs(n - c.secret);
          const hint = d <= 3 ? ' Очень горячо! 🔥' : d <= 10 ? ' Тепло!' : d >= 40 ? ' Холодно ❄️' : '';
          return this.say(`Моё число ${dir}${hint}`, { src: 'skill', intent: 'guess_number' });
        }
        if (quit || giveUp) { this.ctx = null; return this.say(`Я загадал **${c.secret}**! Сыграем ещё?`, { src: 'skill', chips: ['Ещё раз', 'Нет'], offer: 'guess_number' }); }
        if (switchTopic) { this.ctx = null; return null; }
        return this.say('Напиши число от 1 до 100 🙂 Или «сдаюсь».', { src: 'skill' });
      }
      case 'guess_my_number': {
        const more = /больше|выше|побольше|бол[ьш]/.test(t), less = /меньше|ниже|поменьше/.test(t);
        const yes = /угадал|верно|правильно|точно|(?:^|\s)да(?![а-яa-z0-9])|ага|оно|это оно|молодец/.test(t);
        if (quit) { this.ctx = null; return this.say('Ладно, сыграем в другой раз 🙂', { src: 'skill' }); }
        if (yes && !more && !less) { this.ctx = null; this.lastAct = 'guess_my_number'; return this.say(`Ура! Я угадал за ${c.tries} ${U.plural(c.tries, 'попытку', 'попытки', 'попыток')} 😎 Нейросети умеют делить пополам!`, { src: 'skill', mood: 'happy', chips: ['Ещё раз', 'Хватит'], offer: 'guess_my_number' }); }
        if (more || less) {
          if (more) c.lo = c.guess + 1; else c.hi = c.guess - 1;
          if (c.lo > c.hi) { this.ctx = null; return this.say('Хм, кажется, в подсказках ошибка 😄 Давай начнём заново?', { src: 'skill', chips: ['Давай', 'Нет'], offer: 'guess_my_number' }); }
          c.guess = Math.floor((c.lo + c.hi) / 2); c.tries++;
          return this.say(`Может, **${c.guess}**?`, { src: 'skill', chips: ['Больше', 'Меньше', 'Угадал!'] });
        }
        if (switchTopic) { this.ctx = null; return null; }
        return this.say(`Моя догадка — **${c.guess}**. Скажи «больше», «меньше» или «угадал».`, { src: 'skill', chips: ['Больше', 'Меньше', 'Угадал!'] });
      }
      case 'rps': {
        const mv = Skills.rpsMove(text);
        if (mv) {
          const mine = U.pick(['камень', 'ножницы', 'бумага'], this.rnd), res = Skills.rpsJudge(mv, mine);
          if (res > 0) c.you++; else if (res < 0) c.me++;
          const verdict = res > 0 ? 'Ты победил! 🎉' : res < 0 ? 'Я победил! 😎' : 'Ничья! 🤝';
          return this.say(`${Skills.RPS_E[mv]} против ${Skills.RPS_E[mine]} (${mine}). ${verdict}\nСчёт: ты ${c.you} : ${c.me} я. Ещё раунд?`,
            { src: 'skill', intent: 'rps', mood: res < 0 ? 'happy' : 'idle', chips: ['Камень', 'Ножницы', 'Бумага', 'Хватит'] });
        }
        if (quit || tag === 'no') { this.ctx = null; return this.say(`Игра окончена! Итог: ты ${c.you} : ${c.me} я. ${c.you > c.me ? 'Ты чемпион! 🏆' : c.you < c.me ? 'В этот раз победил я 😎' : 'Боевая ничья!'}`, { src: 'skill' }); }
        if (switchTopic) { this.ctx = null; return null; }
        return this.say('Выбирай: камень, ножницы или бумага?', { src: 'skill', chips: ['Камень', 'Ножницы', 'Бумага'] });
      }
      case 'riddle': {
        const R = RIDDLES[c.i];
        if (Skills.answerMatches(text, R.a)) {
          this.ctx = null; this.lastAct = 'riddle';
          return this.say(U.pick(['Правильно! 🎉 Ты отлично отгадываешь загадки!', 'Верно! Молодец{,name}! 🧠', 'Точно! Это ' + R.a[0] + ' 🎉'], this.rnd), { src: 'skill', intent: 'riddle', mood: 'happy', chips: ['Ещё загадку', 'Хватит'], offer: 'riddle' });
        }
        if (quit || giveUp || c.tries >= 2) { this.ctx = null; this.lastAct = 'riddle'; return this.say(`Ответ: **${R.a[0]}**! ${giveUp || quit ? '' : 'Ничего, в следующий раз получится 😉'} Ещё загадку?`, { src: 'skill', chips: ['Ещё загадку', 'Хватит'], offer: 'riddle' }); }
        if (switchTopic) { this.ctx = null; return null; }
        c.tries++;
        return this.say(c.tries === 1 ? 'Не-а! Подумай ещё 🤔' : `Почти... Подсказка: первая буква «${R.a[0][0].toUpperCase()}», всего букв: ${R.a[0].length}.`, { src: 'skill', chips: ['Сдаюсь'] });
      }
      case 'quiz': {
        const Q = QUIZ[c.qs[c.i]];
        const k = Skills.quizPick(text, Q.o);
        if (k < 0) {
          if (quit) { this.ctx = null; return this.say(`Викторина окончена. Правильных ответов: ${c.score} из ${c.i}.`, { src: 'skill' }); }
          if (giveUp) return this.nextQuiz(c, `Правильный ответ: **${Q.o[Q.c]}**.`);
          if (switchTopic) { this.ctx = null; return null; }
          return this.say('Выбери вариант: А, Б или В 🙂', { src: 'skill', chips: this.quizChips(Q) });
        }
        if (k === Q.c) { c.score++; return this.nextQuiz(c, U.pick(['✅ Правильно!', '✅ Верно! Так держать!', '✅ Точно!'], this.rnd)); }
        return this.nextQuiz(c, `❌ Не совсем. Правильный ответ: **${Q.o[Q.c]}**.`);
      }
      case 'game_wait': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо, поиграем потом! 🎮', { src: 'rule' });
        if (switchTopic && tag !== 'make_game' && tag !== 'play' && !GameList.find(text, true)) return null;
        return this.makeGame(text, t, cls, io, true);
      }
      case 'confirm_forget': {
        this.ctx = null;
        if (tag === 'yes' || /^(да|давай|ага|конечно|уверен)/.test(t)) {
          const words = this.profile.words;
          this.profile = { name: '', facts: [], city: null, age: 0, likes: [], dislikes: [], has: [], wants: [], favs: {}, grade: null, from: '', words, asked: [] }; this.save();
          return this.say('Готово, я всё забыл. Будто мы только что познакомились 🙂 Привет! Я Амиго.', { src: 'rule', intent: 'forget' });
        }
        return this.say('Хорошо, ничего не стираю 👍', { src: 'rule' });
      }
      case 'ask_city': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо!', { src: 'rule' });
        if ((switchTopic && !/погод/.test(t)) || (!Skills.cityKnown(t) && (t.split(' ').length > 3 || /(^|\s)(я|ты|не|мне|меня|у|это|что)(?![а-я])/.test(t)))) return null;
        return this.weather('погода в ' + text.replace(/^(?:в|во|я в|я живу в)\s+/i, ''), io, true);
      }
      case 'calc_wait': {
        this.ctx = null;
        const r = Skills.calc(text, true);
        if (r) return this.say(Skills.calcText(r), { src: 'skill', intent: 'calc' });
        return null;
      }
      case 'translate_wait': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо!', { src: 'rule' });
        return this.translateAns('переведи ' + text + (c.lang === 'es' ? ' на испанский' : ''), io, cls);
      }
      case 'remember_wait': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо, ничего не записываю.', { src: 'rule' });
        return this.remember(text);
      }
      case 'timer_wait': {
        this.ctx = null;
        const s = Skills.duration(text);
        if (s > 0) return this.timer(text, s);
        return null;
      }
      case 'homework': {
        this.ctx = null;
        if (quit || tag === 'no') return this.say('Хорошо! Если что, я тут.', { src: 'rule' });
        const r = Skills.calc(text, false);
        if (r) return this.say(Skills.calcText(r), { src: 'skill', intent: 'calc' });
        if (this.superMode()) {
          const a = await this.askSuper(text, io, cls, 'Помоги школьнику с домашним заданием: объясни решение по шагам, коротко и понятно, но не просто выдай ответ. Задание: ' + text);
          if (a) return a;
        }
        return null;
      }
    }
    return null;
  }
  quizChips(Q) { return Q.o.map((o, i) => 'АБВ'[i] + ') ' + o); }
  nextQuiz(c, verdict) {
    c.i++;
    if (c.i >= c.qs.length) {
      this.ctx = null; this.lastAct = 'quiz';
      const s = c.score, n = c.qs.length;
      const grade = s === n ? 'Идеально! Ты гений 🏆' : s >= n - 1 ? 'Отлично! 🌟' : s >= n / 2 ? 'Неплохо! 👍' : 'Ничего, в следующий раз будет лучше 💪';
      return this.say(`${verdict}\n\nВикторина окончена! Результат: **${s} из ${n}**. ${grade}`, { src: 'skill', intent: 'quiz', mood: s >= n - 1 ? 'happy' : 'idle', chips: ['Ещё викторину', 'Хватит'], offer: 'quiz' });
    }
    const Q = QUIZ[c.qs[c.i]];
    return this.say(`${verdict}\n\nВопрос ${c.i + 1} из ${c.qs.length}: ${Q.q}\n` + Q.o.map((o, i) => `${'АБВ'[i]}) ${o}`).join('\n'), { src: 'skill', intent: 'quiz', chips: this.quizChips(Q) });
  }
  numberIn(text) {
    const m = /-?\d+/.exec(Text.wordsToDigits(text.toLowerCase()));
    return m ? parseInt(m[0], 10) : null;
  }
  setName(a, b) {
    if (NOT_NAMES.has(a.toLowerCase())) return null;
    const cap = w => w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : '';
    const name = cap(a) + (b && !NOT_NAMES.has(b.toLowerCase()) && /^[А-ЯЁA-Z]/.test(b) ? ' ' + cap(b) : '');
    const was = this.profile.name;
    this.profile.name = name; this.save(); this.ctx = null;
    return this.say(was && was !== name ? `Хорошо, теперь буду звать тебя ${name}! 😊` : U.pick([`Приятно познакомиться, ${name}! 😊 Я запомнил твоё имя.`, `${name} — классное имя! Я запомню 💛`], this.rnd),
      { src: 'rule', intent: 'set_name', mood: 'happy' });
  }
  remember(fact) {
    let f = String(fact).trim().replace(/^(?:что|пожалуйста|это)\s+/i, '').replace(/[.!]+$/, '');
    if (!f || f.length < 3) { this.ctx = { type: 'remember_wait' }; return this.say('Что именно запомнить? Напиши, а я запишу в свою память 📝', { src: 'skill' }); }
    if (!this.profile.facts.includes(f)) this.profile.facts.push(f);
    if (this.profile.facts.length > 30) this.profile.facts.shift();
    this.save();
    return this.say(`Запомнил: «${f}» ✅`, { src: 'skill', intent: 'remember', mood: 'learn' });
  }
  timer(text, sec) {
    const label = Skills.timerLabel(text);
    this.lastAct = null;
    return this.say(`⏱️ Таймер на **${Skills.durText(sec)}** запущен!${label ? ` Напомню: «${label}».` : ' Я скажу, когда время выйдет.'}`, { src: 'skill', intent: 'timer', action: { type: 'timer', sec, label } });
  }
  timerDone(label) {
    return this.fill(label ? `⏰ Время вышло{,name}! Ты просил напомнить: «${label}».` : '⏰ Время вышло{,name}! Таймер сработал.');
  }

  // ---------- ответы по темам ----------
  async handle(tag, text, t, cls, io) {
    const it = this.byTag.get(tag) || {};
    const meta = { src: it.custom ? 'taught' : 'net', intent: tag, conf: cls && cls.conf, top: cls && cls.top };
    if (it.r && !it.act) {
      const r = it.r[this.deal('r:' + tag, it.r)], o = typeof r === 'string' ? { s: r } : r;
      if (o.offer) this.ctx = { type: 'offer', act: o.offer };
      return this.say(o.s, Object.assign(meta, { chips: o.chips || it.chips, mood: /грус|жаль|обид/.test(o.s) ? 'care' : 'happy' }));
    }
    const P = this.profile;
    if (TALK_ACTS.has(it.act || tag)) { const r = await this.handleTalk(it.act || tag, text, t, cls, io, meta); if (r) return r; }
    switch (it.act || tag) {
      case 'crisis': this.ctx = null; return this.say(CRISIS_TEXT, Object.assign(meta, { mood: 'care' }));
      case 'gibberish': return this.say(U.pick(['Кажется, по клавиатуре прошёлся кот 🐱 Попробуешь ещё раз?', 'Это какой-то шифр? Я пока не умею такие разгадывать 😅', 'Ыыы... Я не понял ни буквы 😄 Напиши по-другому?'], this.rnd), Object.assign(meta, { src: 'rule', mood: 'think' }));
      case 'play': this.lastAct = null; return this.say(`Давай поиграем! 🎮\n• **Прямо в чате:** ${GameList.list()}\n• **Словами:** угадай число, угадай моё число, камень-ножницы-бумага, загадки, викторина, монетка и кубики` +
        '\n• **Свою игру:** опиши её, например «сделай игру про кота-космонавта», и я сам её запрограммирую в Кодексе 🧑‍💻' + '\nВо что сыграем?',
        Object.assign(meta, { chips: ['Змейка', 'Тетрис', 'Игра 2048', 'Крестики-нолики', 'Угадай число', 'Загадка'] }));
      case 'name_bot':
        if (!P.name) { this.ctx = { type: 'ask_name' }; return this.say('Меня зовут Амиго! По-испански это «друг». А тебя как зовут?', meta); }
        return this.say(`Меня зовут Амиго, по-испански это «друг». А ты — ${P.name}, я помню 😊`, meta);
      case 'how_works': {
        const net = this.net;
        return this.say(`Внутри меня настоящая нейросеть, написанная с нуля:\n• **${U.num(net.D)}** входов — это признаки фразы: слова, пары слов и кусочки слов по 3 буквы\n• **${net.H}** скрытых нейронов\n• **${net.C}** выходов — по одному на каждую тему, которую я знаю\nВсего **${U.num(net.params)}** параметров. Я разбиваю твою фразу на признаки, пропускаю через сеть и получаю, о чём ты говоришь, с уверенностью в процентах. Ещё у меня есть словарь на ${U.num(Lex.size)} слов и память о тебе. Потом мои навыки строят ответ. А когда ты меня учишь, я дообучаюсь прямо здесь, на твоём устройстве. Нажми «Мозг», чтобы посмотреть, как я думаю!`,
          Object.assign(meta, { chips: ['Показать мозг'], mood: 'learn' }));
      }
      case 'help': return this.say('Вот что я умею:\n• **болтать** почти обо всём: я знаю тысячи слов, а новые выучу, если объяснишь\n• **запоминать** твоё имя, что ты любишь, откуда ты и в каком классе\n• **считать**: «сколько будет 17 × 23», «корень из 144», «15% от 300»\n• **сам программировать игры** в режиме **Кодекс**: опиши игру, и я её сделаю\n• **запускать готовые игры**: змейка, тетрис, 2048, сапёр, крестики-нолики и другие\n• **играть словами**: угадай число, камень-ножницы-бумага, загадки, викторина\n• **шутить**, рассказывать **факты**, **сказки** и **стихи**\n• говорить **время и дату**, ставить **таймер**\n• узнавать **погоду** и отвечать на вопросы «**что такое...**»\n• **переводить** слова на английский и испанский\n• **учиться**: если я что-то не понял, научи меня!',
        Object.assign(meta, { chips: ['Змейка', 'Расскажи шутку', 'Сколько будет 17 × 23?', 'Что такое нейросеть?'] }));
      case 'are_you_claude':
        return this.say('Нет, я Амиго! 🙂 У меня своя маленькая нейросеть: она живёт прямо на твоём устройстве, и обычные разговоры, игры, счёт и память — это я сам. ' +
          'А когда вопрос сложный, я могу позвать на помощь «супер-мозг» — это Claude от компании Anthropic. Такие ответы подписаны «супер-мозг Claude». Но разговариваю с тобой всегда я, Амиго 💛',
          Object.assign(meta, { src: meta.conf != null && cls && cls.tag === 'are_you_claude' ? 'net' : 'rule', mood: 'happy' }));
      case 'make_game': return this.makeGame(text, t, cls, io);
      case 'codex_on': case 'codex_off': case 'codex_how': case 'show_code': {
        const r = this.codexCommand(text, t, Object.assign({}, cls, { conf: 1 }));
        if (r) return r;
        if (tag === 'codex_on') { this.settings.codexOn = true; this.save(); return this.say('🧑‍💻 Режим Кодекс включён! Опиши игру, и я её запрограммирую.', { src: 'rule', action: { type: 'codex', on: true } }); }
        return this.notUnderstood(text, cls);
      }
      case 'age_bot': return this.say(`Я совсем молодой: появился в 2026 году. Но уже знаю ${this.tags.length} ${U.plural(this.tags.length, 'тему', 'темы', 'тем')} и учусь каждый день!`, meta);
      case 'yes':
        return this.say(U.pick(['Отлично! 😊 Чем займёмся?', 'Супер! Что будем делать?'], this.rnd), Object.assign(meta, { chips: ['Расскажи шутку', 'Сыграем', 'Интересный факт'] }));
      case 'no': return this.say(U.pick(['Хорошо 🙂', 'Ладно! Если что, я тут.', 'Как скажешь!'], this.rnd), meta);
      case 'more':
        if (this.lastAct) return this.handle(this.lastAct, text, t, cls, io);
        return this.say('Ещё чего? Могу шутку, факт или загадку 🙂', Object.assign(meta, { chips: ['Шутку', 'Факт', 'Загадку'] }));
      case 'dont_know': return this.say(U.pick(['Ничего страшного, никто не знает всего на свете 🙂 Хочешь, спросим вместе? Начни вопрос с «что такое...».', 'Бывает! Я тоже многого не знаю. Зато мы можем узнать вместе.'], this.rnd), meta);
      case 'rick': {
        const kb = KB.filter(e => /рик|морти|саммер|бет|джерри|мисикс|цитадел|портал|огурчик/.test(e.a[0]));
        const exact = Skills.kbFind(Skills.topicOf(text) || text);
        if (exact) return this.say(exact.s, Object.assign(meta, { src: 'memory' }));
        if (/вабба|wubba|вубба/.test(t)) return this.say('Вабба лабба даб даб! 🥒 Птичья Личность говорил, что на его языке это значит «мне очень больно, помогите». Но я в порядке! Хочешь факт про «Рика и Морти»?', Object.assign(meta, { mood: 'happy' }));
        const e = kb[this.deal('rick', kb)];
        return this.say(e.s + ' Хочешь ещё про «Рика и Морти»?', Object.assign(meta, { chips: ['Кто такой Морти?', 'Кто такой Огурчик-Рик?', 'Что такое Цитадель?'] }));
      }
      case 'set_name': {
        const nm = NAME_RE.exec(text);
        if (nm) { const r = this.setName(nm[1], nm[2]); if (r) return r; }
        const ws = text.trim().split(/\s+/);
        if (ws.length === 2 && /^я$/i.test(ws[0]) && /^[А-ЯЁA-Z]/.test(ws[1])) { const r = this.setName(ws[1]); if (r) return r; }
        this.ctx = { type: 'ask_name' };
        return this.say('Как тебя зовут? Напиши своё имя 🙂', meta);
      }
      case 'ask_my_name':
        if (P.name) return this.say(`Тебя зовут ${P.name}! Я помню 😊`, Object.assign(meta, { mood: 'happy' }));
        this.ctx = { type: 'ask_name' };
        return this.say('Ты мне ещё не говорил своё имя. Как тебя зовут?', meta);
      case 'remember': {
        const m = /запом(?:ни|нить)|запиши/.exec(t);
        const f = m ? text.replace(/^.*?(?:запомни(?:ть)?|запиши)(?:\s+пожалуйста)?[:,]?\s*/i, '') : '';
        if (!f || /^(это|одну вещь)$/i.test(f.trim())) { this.ctx = { type: 'remember_wait' }; return this.say('Что запомнить? Напиши 📝', meta); }
        return this.remember(f);
      }
      case 'about_me': {
        const lines = [];
        if (P.name) lines.push(`тебя зовут ${P.name}`);
        if (P.age) lines.push(`тебе ${P.age} ${U.plural(P.age, 'год', 'года', 'лет')}`);
        if (P.city) lines.push(`твой город — ${P.city.name}`);
        else if (P.from) lines.push(`ты из места «${P.from}»`);
        if (P.grade) lines.push(typeof P.grade === 'number' ? `ты учишься в ${P.grade} классе` : `ты — ${P.grade === 'садик' ? 'ходишь в садик' : P.grade}`);
        if (P.likes && P.likes.length) lines.push('ты любишь: ' + P.likes.slice(-8).join(', '));
        if (P.dislikes && P.dislikes.length) lines.push('ты не любишь: ' + P.dislikes.slice(-6).join(', '));
        if (P.has && P.has.length) lines.push('у тебя есть: ' + P.has.slice(-6).join(', '));
        for (const [k, v] of Object.entries(P.favs || {}).slice(-8)) lines.push(`любимое (${FAV_NAMES[k] || k.replace(/^fav_/, '')}): ${v}`);
        if (P.wants && P.wants.length) lines.push('мечты: ' + P.wants.slice(-4).join(', '));
        for (const f of P.facts) lines.push(`«${f}»`);
        const nw = Object.keys(P.words || {}).length;
        if (nw) lines.push(`ты научил меня ${nw} ${U.plural(nw, 'слову', 'словам', 'словам')}`);
        if (!lines.length) return this.say('Пока я почти ничего о тебе не знаю 🙂 Расскажи! Например: «меня зовут ...» или «запомни, что я люблю ...».', meta);
        return this.say('Вот что я о тебе знаю:\n' + lines.map(l => '• ' + l).join('\n'), Object.assign(meta, { mood: 'happy' }));
      }
      case 'forget': this.ctx = { type: 'confirm_forget' }; return this.say('Забыть твоё имя и всё, что ты мне рассказывал? Выученные фразы останутся.', Object.assign(meta, { chips: ['Да, забудь', 'Нет'] }));
      case 'time': return this.say(Skills.timeText(this.now()), meta);
      case 'date': return this.say(Skills.dateText(this.now(), text), meta);
      case 'countdown': return this.say(Skills.countdownText(this.now(), text), meta);
      case 'calc': {
        const r = Skills.calc(text, true);
        if (r) return this.say(Skills.calcText(r), meta);
        if (/таблиц/.test(t)) {
          const n = 2 + Math.floor(this.rnd() * 8), rows = [];
          for (let i = 1; i <= 10; i++) rows.push(`${n} × ${i} = ${n * i}`);
          return this.say(`Таблица умножения на ${n}:\n` + rows.join('\n'), meta);
        }
        this.ctx = { type: 'calc_wait' };
        return this.say('Давай! Напиши пример, например **25 × 4**, **корень из 144** или **15% от 300**.', meta);
      }
      case 'joke': this.lastAct = 'joke'; return this.say(JOKES[this.deal('joke', JOKES)], Object.assign(meta, { mood: 'happy', chips: ['Ещё шутку', 'Интересный факт'] }));
      case 'fact': this.lastAct = 'fact'; return this.say(FACTS[this.deal('fact', FACTS)], Object.assign(meta, { mood: 'wow', chips: ['Ещё факт', 'Расскажи шутку'] }));
      case 'riddle': {
        this.lastAct = 'riddle';
        const i = this.deal('riddle', RIDDLES);
        this.ctx = { type: 'riddle', i, tries: 0 };
        return this.say('Загадка! 🧩 ' + RIDDLES[i].q, Object.assign(meta, { chips: ['Сдаюсь'], mood: 'think' }));
      }
      case 'quiz': {
        const qs = U.shuffle(QUIZ.map((_, i) => i), this.rnd).slice(0, 5);
        this.ctx = { type: 'quiz', qs, i: 0, score: 0 };
        const Q = QUIZ[qs[0]];
        return this.say(`Викторина! 5 вопросов. Поехали 🎯\n\nВопрос 1 из 5: ${Q.q}\n` + Q.o.map((o, i) => `${'АБВ'[i]}) ${o}`).join('\n'), Object.assign(meta, { chips: this.quizChips(Q) }));
      }
      case 'rps': {
        this.ctx = { type: 'rps', me: 0, you: 0 };
        const mv = Skills.rpsMove(text);
        if (mv && !/камень\s+ножницы|ножницы\s+бумага/.test(t)) return this.inCtx(text, t, cls, io);
        return this.say('Камень, ножницы, бумага! Я уже выбрал. А ты? ✊✌️✋', Object.assign(meta, { chips: ['Камень', 'Ножницы', 'Бумага'] }));
      }
      case 'guess_number': {
        this.ctx = { type: 'guess_number', secret: 1 + Math.floor(this.rnd() * 100), tries: 0 };
        return this.say('Я загадал число от 1 до 100 🤫 Попробуй угадать!', meta);
      }
      case 'guess_my_number': {
        this.ctx = { type: 'guess_my_number', lo: 1, hi: 100, guess: 50, tries: 1 };
        return this.say('Загадай число от 1 до 100, а я буду угадывать. Отвечай «больше», «меньше» или «угадал». Моя первая догадка: **50**?', Object.assign(meta, { chips: ['Больше', 'Меньше', 'Угадал!'] }));
      }
      case 'coin': this.lastAct = 'coin'; return this.say(Skills.coin(this.rnd), Object.assign(meta, { chips: ['Ещё раз'] }));
      case 'dice': this.lastAct = 'dice'; return this.say(Skills.dice(text, this.rnd), Object.assign(meta, { chips: ['Ещё раз'] }));
      case 'random': return this.say(Skills.random(text, this.rnd), meta);
      case 'choose': {
        const opts = Skills.chooseOptions(text);
        if (!opts) return this.say('Напиши варианты через «или», например: «пицца или бургер?», и я выберу!', meta);
        const pick = U.pick(opts, this.rnd);
        return this.say(U.pick([`Я выбираю **${pick}**! 🎯`, `Хм... **${pick}**! Мои нейроны проголосовали за это 😄`, `Думаю, **${pick}**. Но решать тебе!`], this.rnd), meta);
      }
      case 'timer': {
        const s = Skills.duration(text);
        if (!s) { this.ctx = { type: 'timer_wait' }; return this.say('На сколько поставить таймер? Например: «5 минут» или «30 секунд».', meta); }
        return Object.assign(this.timer(text, s), { conf: meta.conf, top: meta.top });
      }
      case 'timer_cancel': return this.say('Хорошо, выключаю таймеры ⏹️', Object.assign(meta, { action: { type: 'timer_cancel' } }));
      case 'weather': return this.weather(text, io, false, meta);
      case 'knowledge': return this.knowledge(text, io, cls);
      case 'translate': return this.translateAns(text, io, cls);
      case 'teach': this.ctx = { type: 'teach_phrase' }; return this.say('Ура, учиться я люблю! 🧠 Напиши фразу, на которую мне нужно научиться отвечать.', Object.assign(meta, { mood: 'learn' }));
      case 'story': {
        const about = /(?:про|о|об)\s+(.+)$/i.exec(text);
        if (about && this.superMode()) { const a = await this.askSuper(text, io, cls, `Сочини короткую добрую сказку для ребёнка (5–8 предложений) про ${about[1]}. Без заголовка.`); if (a) return a; }
        this.lastAct = 'story';
        const scary = STORIES.findIndex(s => s.startsWith('Страшилка'));
        let i = /страш/.test(t) ? scary : this.deal('story', STORIES);
        if (i === scary && !/страш/.test(t)) i = this.deal('story', STORIES);
        return this.say(STORIES[i], Object.assign(meta, { chips: ['Ещё сказку', 'Спасибо!'] }));
      }
      case 'poem': {
        const about = /(?:про|о|об)\s+(.+)$/i.exec(text);
        if (about && this.superMode()) { const a = await this.askSuper(text, io, cls, `Сочини короткое смешное стихотворение для ребёнка (4–8 строк, с рифмой) про ${about[1]}. Только стихи.`); if (a) return a; }
        this.lastAct = 'poem';
        let i = this.deal('poem', POEMS);
        if (/кот|кош/.test(t)) i = 0; else if (/осен/.test(t)) i = 3; else if (/космос|ракет/.test(t)) i = 4; else if (/школ/.test(t)) i = 5; else if (/друж|друг/.test(t)) i = 1;
        return this.say(POEMS[i], Object.assign(meta, { chips: ['Ещё стих'] }));
      }
      case 'sing': this.lastAct = 'sing'; return this.say(SONGS[this.deal('song', SONGS)], Object.assign(meta, { mood: 'happy', action: { type: 'dance' } }));
      case 'dance': return this.say(U.pick(['Смотри, как я умею! 💃🕺', 'Включаю танцевальный режим! 🎶'], this.rnd), Object.assign(meta, { mood: 'happy', action: { type: 'dance' } }));
      case 'recommend': {
        const k = /книг|почитать|читать/.test(t) ? 'book' : /игр|поиграть/.test(t) ? 'game' : /музык|послушать|песн/.test(t) ? 'music' : /фильм|кино/.test(t) ? 'film' : 'cartoon';
        const list = U.shuffle(RECS[k].slice(), this.rnd).slice(0, 3);
        const what = { book: 'почитать', game: 'поиграть в', music: 'послушать', film: 'посмотреть фильмы', cartoon: 'посмотреть мультфильмы' }[k];
        return this.say(`Советую ${what}: ${list.join(', ')}. Если понравится, расскажи мне! 😊`, meta);
      }
      case 'advice': this.lastAct = 'advice'; return this.say(ADVICE[this.deal('advice', ADVICE)], Object.assign(meta, { chips: ['Ещё совет'] }));
      case 'motivation': this.lastAct = 'motivation'; return this.say(MOTIVATION[this.deal('motivation', MOTIVATION)], Object.assign(meta, { mood: 'happy' }));
      case 'homework':
        this.ctx = { type: 'homework' };
        if (this.superMode()) return this.say('Давай разберёмся вместе! Напиши задание целиком, и я объясню решение по шагам 📚', meta);
        return this.say('Давай! Сам я могу:\n• посчитать пример — просто напиши его\n• объяснить слово — спроси «что такое ...»\n• перевести слово на английский\nНапиши задание 📚', meta);
      case 'clear_chat': return this.say('Чат очищен ✨', Object.assign(meta, { action: { type: 'clear' } }));
      case 'voice_on': this.settings.voice = true; this.save(); return this.say('Теперь я говорю вслух! 🔊', Object.assign(meta, { action: { type: 'voice', on: true } }));
      case 'voice_off': this.settings.voice = false; this.save(); return this.say('Хорошо, молчу. Только пишу 🔇', Object.assign(meta, { action: { type: 'voice', on: false } }));
      case 'stop': this.ctx = null; return this.say('Хорошо, остановились 👍 Чем займёмся?', Object.assign(meta, { chips: ['Что ты умеешь?'] }));
    }
    if (it.custom) return this.say(it.r[0], meta);
    return this.notUnderstood(text, cls);
  }

  async knowledge(text, io, cls) {
    const meta = { intent: 'knowledge', conf: cls && cls.conf, top: cls && cls.top };
    const topic = Skills.topicOf(text);
    const make = /^(?:(?:а|ну|амиго|пожалуйста)[,\s]+)*(напиши|придумай|сочини|нарисуй|сделай|составь|создай|переделай|перескажи)(?![а-я])/i.test(text.trim());
    if (/^(ты|тебе|тебя|амиго)$/i.test(topic)) return this.handle('who_are_you', text, Text.clean(text), cls, io);
    // «что такое X» — сначала мини-энциклопедия; «почему…», «сколько…» — сначала ответы на частые вопросы
    const kb = Skills.kbFind(topic || text), qa = QA.find(text);
    if (kb && (topic || !qa)) return this.say(kb.s, Object.assign(meta, { src: 'memory' }));
    if (qa) return this.say(qa.a, Object.assign(meta, { src: 'memory' }));
    if (this.superMode()) { const a = await this.askSuper(text, io, cls); if (a) return a; }
    if (make) {
      this.ctx = { type: 'teach_offer', phrase: text };
      return this.say('Сам я такое пока не умею 😅 Это задача для супер-мозга: включи его в настройках. А ещё можешь научить меня ответу.', Object.assign(meta, { src: 'net', mood: 'think', chips: ['Научить', 'Настройки'], unsure: true }));
    }
    if (this.settings.online) {
      if (io.onThinking) io.onThinking('wiki');
      try {
        const w = await this.online.wiki(topic || text);
        if (w) return this.say(w.text, Object.assign(meta, { src: 'wiki', link: { url: w.url, title: w.title } }));
      } catch (e) { /* нет сети */ }
    }
    this.ctx = { type: 'teach_offer', phrase: text };
    const hit = Lex.main(topic || text);
    if (hit) return this.say(`Точного ответа я пока не знаю 🤔 Но вот что знаю: ${Lex.describe(hit.entry)} Если знаешь больше — нажми «Научить», и я запомню!`,
      Object.assign(meta, { src: 'memory', mood: 'think', chips: ['Научить'] }));
    return this.say(`Этого я пока не знаю 🤔 ${this.settings.online ? 'И в интернете не нашёл: может, нет связи. ' : ''}Если знаешь ответ, нажми «Научить», и я запомню!`,
      Object.assign(meta, { src: 'net', mood: 'think', chips: ['Научить'], unsure: true }));
  }

  async translateAns(text, io, cls) {
    const meta = { src: 'skill', intent: 'translate', conf: cls && cls.conf, top: cls && cls.top };
    const r = Skills.translate(text);
    if (r.text) return this.say(r.text, meta);
    if (r.need) { this.ctx = { type: 'translate_wait', lang: /испан/.test(text.toLowerCase()) ? 'es' : 'en' }; return this.say('Какое слово перевести?', meta); }
    if (this.superMode()) {
      const a = await this.askSuper(text, io, cls, r.reverse ? `Переведи на русский и коротко поясни: ${r.unknown}` : `Переведи ${r.lang === 'es' ? 'на испанский' : 'на английский'} и покажи, как читается: ${r.unknown}`);
      if (a) return a;
    }
    return this.say(`Слова «${r.unknown}» пока нет в моём словаре 📖 Я знаю около ${Object.keys(DICT).length} самых нужных слов. Попробуй другое!`, meta);
  }

  async weather(text, io, fromCtx, meta = {}) {
    meta = Object.assign({ src: 'web', intent: 'weather' }, meta, { src: 'web' });
    const phrase = Skills.cityPhrase(text);
    let city = Skills.cityKnown(phrase);
    if (!this.settings.online) return this.say('Погоду я узнаю в интернете, а он выключен в настройках. Включи «Интернет» в настройках, и я посмотрю!', meta);
    if (!city && phrase) {
      if (io.onThinking) io.onThinking('web');
      for (const g of Skills.cityGuesses(phrase)) {
        try { const r = await this.online.geocode(g); if (r) { city = r; break; } } catch (e) { return this.say('Не получилось узнать погоду: нет связи с интернетом 😕', meta); }
      }
      if (!city) return this.say(`Не нашёл город «${phrase}» 🤔 Напиши название по-другому, например «погода в Казани».`, meta);
    }
    if (!city) city = this.profile.city;
    if (!city) { this.ctx = { type: 'ask_city' }; return this.say('В каком ты городе? Я запомню и буду показывать погоду там 🌤️', Object.assign(meta, { src: 'skill' })); }
    if (!this.profile.city || fromCtx) { this.profile.city = { name: city.name, lat: city.lat, lon: city.lon }; this.save(); }
    if (io.onThinking) io.onThinking('web');
    let w;
    try { w = await this.online.forecast(city); } catch (e) { return this.say('Не получилось узнать погоду: нет связи с интернетом 😕 Если ты открыл меня внутри приложения, там доступ в сеть закрыт.', meta); }
    const cur = w.current || {}, d = w.daily || {};
    const sign = v => (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(Math.round(v));
    const tomorrow = /завтра/.test(text.toLowerCase());
    if (tomorrow && d.time && d.time[1]) {
      const [desc, em] = Skills.wmo(d.weather_code[1]);
      const pr = d.precipitation_probability_max ? d.precipitation_probability_max[1] : null;
      return this.say(`Завтра в городе ${city.name}: ${desc} ${em}, от ${sign(d.temperature_2m_min[1])} до ${sign(d.temperature_2m_max[1])} °C${pr != null ? `, вероятность осадков ${pr}%` : ''}.\n${Skills.dressTip(d.temperature_2m_max[1], d.weather_code[1])}`, meta);
    }
    const [desc, em] = Skills.wmo(cur.weather_code);
    let s = `Сейчас в городе ${city.name}: **${sign(cur.temperature_2m)} °C**, ощущается как ${sign(cur.apparent_temperature)} °C. ${U.cap(desc)} ${em}, ветер ${Math.round(cur.wind_speed_10m)} м/с.`;
    if (d.time && d.time[0]) s += `\nСегодня от ${sign(d.temperature_2m_min[0])} до ${sign(d.temperature_2m_max[0])} °C.`;
    s += '\n' + Skills.dressTip(cur.apparent_temperature, cur.weather_code);
    return this.say(s, meta);
  }

  // ---------- игры в чате ----------
  async makeGame(text, t, cls, io, fromCtx) {
    const meta = { src: cls && cls.tag === 'make_game' ? 'net' : 'skill', intent: 'make_game', conf: cls && cls.tag === 'make_game' ? cls.conf : undefined, top: cls && cls.top };
    const described = fromCtx || /(игр\S*|игрушк\S*)\s+(про|о|об|где|в\s+которой|с|как|на)\s/.test(t + ' ') || t.split(' ').length >= 4;
    // точное название — встроенная игра; описание — Амиго программирует её сам в Кодексе
    const key = GameList.find(text, true, true);
    if (key) {
      const g = GAME_LIST[key];
      this.lastAct = null;
      const intro = U.pick([`Запускаю «${g.title}» ${g.icon}`, `Держи «${g.title}» ${g.icon} Удачи{,name}!`, `Поехали! «${g.title}» ${g.icon}`], this.rnd);
      return this.say(intro + '\n' + g.help, Object.assign(meta, { mood: 'happy', game: { kind: 'builtin', key, opts: GameList.opts(text) } }));
    }
    if (described) return this.codexBuild(text, io, meta);
    this.ctx = { type: 'game_wait' };
    return this.say(`Какую игру? Опиши её, и я сам её запрограммирую 🧑‍💻 Например: «кот ловит рыбу под водой» или «динозавр прыгает через кактусы».\nА ещё у меня есть готовые: ${GameList.list()}.`,
      Object.assign(meta, { chips: ['Кот ловит рыбу под водой', 'Корабль стреляет в пришельцев', 'Змейка', 'Тетрис'] }));
  }

  // ---------- Кодекс: Амиго сам программирует игры ----------
  codexLevelName(l) { return (CODEX_LEVELS[l || this.settings.codexLevel] || CODEX_LEVELS.high).name; }
  canAskClaude() { return this.settings.codexAsk !== false && !!this.online.Super.avail && !!this.online.Super.avail(this.settings); }
  codexCommand(text, t, cls) {
    const lv = /(средн|высок|ультр)/.exec(t), level = lv ? { средн: 'medium', высок: 'high', ультр: 'ultra' }[lv[1]] : null;
    const on = /(^|\s)(включи|открой|запусти|включить|режим|давай)\s+(режим\s+)?кодекс|^кодекс(\s|$)/.test(t) || (cls.tag === 'codex_on' && cls.conf >= 0.6);
    const off = /(выключи|закрой|выйди из|выйти из|отключи|хватит)\s+(режим\s+)?кодекс/.test(t) || (cls.tag === 'codex_off' && cls.conf >= 0.6);
    if (off) {
      this.settings.codexOn = false; this.save();
      return this.say('Режим Кодекс выключен. Если захочешь программировать игры, скажи «включи Кодекс» 🧑‍💻', { src: 'rule', intent: 'codex_off', action: { type: 'codex', on: false } });
    }
    if (on || (level && (/кодекс|режим|уровень/.test(t) || (this.settings.codexOn && t.split(' ').length <= 2)))) {
      this.settings.codexOn = true; if (level) this.settings.codexLevel = level; this.save();
      const L = this.settings.codexLevel;
      const about = { medium: 'Средний — простые игры без лишнего, быстро и понятно.', high: 'Высокий — игры качественнее: эффекты, звуки, бонусы, уровни и боссы.',
        ultra: 'Ультра — я долго думаю: собираю несколько вариантов, даю роботу-тестеру поиграть и подбираю сложность. Если не знаю, как что-то сделать, спрашиваю у Claude только «как это делается», запоминаю и дальше делаю сам.' }[L];
      return this.say(`🧑‍💻 Режим Кодекс: **${this.codexLevelName(L)}**.\n${about}\n\nОпиши игру: кто герой, что он делает и где. Например: «кот ловит рыбу под водой».`,
        { src: 'rule', intent: 'codex_on', mood: 'learn', action: { type: 'codex', on: true, level: L }, chips: ['Кот ловит рыбу под водой', 'Динозавр прыгает через кактусы', 'Корабль стреляет в пришельцев', 'Пингвин прыгает по льдинам вверх'] });
    }
    if (/(покажи|показать|дай|открой)\s+(мне\s+)?(код|чертеж)/.test(t) || (cls.tag === 'show_code' && cls.conf >= 0.6)) {
      if (!this.lastSpec) return this.say('Сначала давай сделаем игру! Опиши её, например «кот ловит рыбу».', { src: 'rule', intent: 'show_code' });
      return this.say(`Вот код игры «${this.lastSpec.title}». Сверху — чертёж: из него мой движок собирает игру. Полный код можно скопировать кнопкой ниже.`, { src: 'rule', intent: 'show_code', action: { type: 'code', spec: this.lastSpec } });
    }
    if (/как\s+(ты\s+)?(делаешь|программируешь|создаешь|пишешь|придумываешь)\s+игр|как\s+работает\s+кодекс|что\s+такое\s+кодекс|ты\s+сам\s+(делаешь|программируешь|пишешь)/.test(t) || (cls.tag === 'codex_how' && cls.conf >= 0.6)) {
      const nn = this.model.codex ? `${Object.keys(CODEX_GENRES).length} жанров, ${U.num(this.model.codex.params)} параметров` : '';
      return this.say('Я программирую игры сам, в режиме **Кодекс**:\n' +
        `• своя нейросеть Кодекса (${nn}) понимает, какой жанр ты описал\n• из описания я нахожу героя, призы, врагов и мир (знаю около ${CODEX_WORDS.length} слов и могу выучить новые)\n` +
        '• собираю чертёж игры из своих приёмов: появление предметов, касания, умения, бонусы, уровни, боссы\n• мой движок оживляет чертёж прямо в чате\n' +
        '• в режиме **Ультра** робот-тестер играет в разные варианты, а я подбираю сложность. Если чего-то не умею, спрашиваю у Claude, КАК это делается, запоминаю приём и дальше делаю сам.' +
        (this.codexMem.recipes.length || Object.keys(this.codexMem.words).length ? `\nУже выучил сам: ${this.codexMem.recipes.length} ${U.plural(this.codexMem.recipes.length, 'приём', 'приёма', 'приёмов')} и ${Object.keys(this.codexMem.words).length} ${U.plural(Object.keys(this.codexMem.words).length, 'слово', 'слова', 'слов')}.` : ''),
        { src: 'rule', intent: 'codex_how', chips: ['Включи Кодекс', 'Кодекс ультра'] });
    }
    return null;
  }
  // в режиме Кодекс почти всё — описание игры или правка последней игры
  async codexMessage(text, t, cls, io) {
    if (this.lastSpec && this.looksEdit(t)) return this.codexEdit(text, io);
    const other = cls.conf >= 0.6 && !['make_game', 'play', 'statement', 'knowledge', 'gibberish', 'more', 'dont_know', 'pets', 'story', 'fav_game'].includes(cls.tag);
    const gamey = /(игр|про |где |лов|прыга|стреля|собира|уворач|бега|беж|лета|лети|гонк|лопа|ход|убега|сбива)/.test(t) || Codex.genreProbs(text)[0].p > 0.45;
    if (other && !gamey) return null;
    if (t.split(' ').length < 2 && !gamey) return null;
    return this.codexBuild(text, io, { src: 'skill', intent: 'make_game' });
  }
  looksEdit(t) {
    if (/игр\S*\s+(про|где|о|об)\s|нов\S*\s+игр|друг\S*\s+игр/.test(t + ' ')) return false;
    return /(быстрее|медленнее|сложнее|легче|проще|больше|меньше|добав|убер|вместо|поменя|измени|назови|переименуй|жизн|(?:^|\s)фон|мир на|без звук|со звук|красивее|пусть|сделай\s+(ее|её|его|так|чтобы))/.test(t);
  }
  explainUnknown(u) {
    const words = u.unknown.map(x => '«' + x.word + '»');
    return words.length ? `Я пока не знаю, как выглядит ${words.join(', ')}, поэтому нарисовал по-своему.` : '';
  }
  async codexBuild(text, io, meta = {}) {
    const level = this.settings.codexLevel || 'high';
    if (level === 'ultra') return this.codexUltra(text, io, meta);
    if (io.onThinking) io.onThinking('codex');
    const u = Codex.understand(text, this.codexMem);
    const spec = Codex.design(u, level);
    this.lastSpec = spec;
    const lines = [];
    const unk = this.explainUnknown(u);
    if (unk) lines.push(unk + ' В режиме Ультра я спрошу, как это нарисовать, и запомню.');
    if (u.unknownMech.length) lines.push(`Делать «${u.unknownMech.join('», «')}» я ещё не умею. В режиме Ультра я спрошу, как это делается, и научусь.`);
    const notes = spec.notes.length ? '\nДобавил: ' + spec.notes.join(', ') + '.' : '';
    const intro = U.pick([`Готово! Я сам запрограммировал игру «${spec.title}» 🧑‍💻`, `Сам написал игру «${spec.title}»! 🎮`, `Вот твоя игра «${spec.title}» — код я написал сам 🧑‍💻`], this.rnd);
    return this.say(`${intro}\n${Codex.describe(spec)}.${notes}` + (lines.length ? '\n' + lines.join('\n') : '') + '\nХочешь что-то поменять? Напиши, например: «быстрее», «добавь босса», «вместо кота собака».',
      Object.assign({}, meta, { src: 'codex', intent: 'make_game', mood: 'happy', codexLevel: level, game: { kind: 'builtin', key: 'codex', opts: spec } }));
  }
  // спросить у Claude, КАК что-то сделать (только в Ультра), и запомнить ответ
  async askHow(prompt, io) {
    const r = await this.online.Super.ask(this.settings, this.profile, [], prompt, null, io.signal, { raw: true, force: true, tier: 'default', effort: 'low', maxTokens: 4000 });
    return Codex.parseJSON(r.text);
  }
  async codexUltra(text, io, meta) {
    const t0 = Date.now(), lines = [];
    const tick = () => new Promise(r => setTimeout(r, 0));
    const pause = ms => (this.fastThink ? tick() : new Promise(r => setTimeout(r, ms)));
    const think = async (s, ms = 380) => { lines.push(s); if (io.onThink) io.onThink(lines.slice()); await pause(ms); };
    const update = s => { lines[lines.length - 1] = s; if (io.onThink) io.onThink(lines.slice()); };
    if (io.onThinking) io.onThinking('ultra');
    await think(`📖 Читаю задание: «${text}»`);
    let u = Codex.understand(text, this.codexMem);
    const g = u.genres.slice(0, 3).map(x => `${CODEX_GENRES[x.g].name} ${Math.round(x.p * 100)}%`).join(', ');
    await think(`🧠 Моя нейросеть Кодекса решает, какой это жанр: ${g}. Беру «${CODEX_GENRES[u.genres[0].g].name}».`, 500);
    const roleLine = uu => {
      const r = uu.roles, bits = [];
      if (r.h[0]) bits.push(`герой ${r.h[0].entry.emoji} ${r.h[0].entry.name}`);
      if (r.g.length) bits.push('призы ' + r.g.map(f => f.entry.emoji).join(''));
      if (r.b.length) bits.push('враги ' + r.b.map(f => f.entry.emoji).join(''));
      if (r.p[0]) bits.push('платформы ' + r.p[0].entry.emoji);
      return bits.length ? bits.join(', ') : 'ничего не назвали — придумаю сам';
    };
    await think(`🔎 Нахожу, кто есть кто: ${roleLine(u)}.`);
    const asked = [];
    if (u.unknown.length) {
      const words = u.unknown.map(x => '«' + x.word + '»').join(', ');
      if (this.canAskClaude()) {
        await think(`❓ Я не знаю, как выглядит ${words}. Спрашиваю у Claude, как это нарисовать…`, 100);
        try {
          const ans = await this.askHow(Codex.wordsPrompt(u.unknown), io);
          const got = Codex.learnWords(this.codexMem, ans);
          if (got.length) { this.save(); asked.push('слова'); update(`📚 Запомнил: ${got.map(x => x.name + ' — ' + x.emoji).join(', ')}. В следующий раз нарисую сам.`); await pause(450); u = Codex.understand(text, this.codexMem); }
          else { update(`❓ Не понял ответ про ${words}, нарисую по-своему.`); await pause(300); }
        } catch (e) { if (e && e.code === 'cancelled') return this.say('Хорошо, остановился.', { src: 'rule' }); update(`❓ Спросить не получилось (${Online.superError(e)}). Нарисую по-своему.`); await pause(300); }
      } else await think(`❓ Я не знаю, как выглядит ${words}. Спросить у Claude сейчас нельзя, поэтому нарисую по-своему.`);
    }
    for (const phrase of u.unknownMech) {
      if (!this.canAskClaude()) { await think(`❓ Я ещё не умею «${phrase}». Спросить у Claude сейчас нельзя: это можно включить в настройках. Сделаю игру без этого.`); continue; }
      await think(`❓ Я не умею «${phrase}». Спрашиваю у Claude, КАК это делается, чтобы научиться самому…`, 100);
      try {
        const base = Codex.design(u, 'ultra');
        const ans = await this.askHow(Codex.mechPrompt(phrase, base), io);
        const v = Codex.validateRecipe(ans);
        if (v.ok) {
          const r = Codex.learnRecipe(this.codexMem, phrase, v.recipe);
          this.save(); asked.push('приём');
          update(`📚 Понял, как делать «${r.name}»: ${r.explain || 'запомнил правила.'} Записал этот приём себе — дальше умею сам.`); await pause(700);
          u = Codex.understand(text, this.codexMem);
        } else {
          update(`❓ Claude объяснил, но этого не сделать моими блоками${ans && ans.explain ? ': ' + ans.explain : ''}. Сделаю без этого.`); await pause(400);
        }
      } catch (e) { if (e && e.code === 'cancelled') return this.say('Хорошо, остановился.', { src: 'rule' }); update(`❓ Спросить не получилось (${Online.superError(e)}). Сделаю без этого.`); await pause(300); }
    }
    const spec0 = Codex.design(u, 'ultra');
    await think(`🌍 Мир: ${spec0.theme.name}. Беру из своей библиотеки: ${spec0.notes.join(', ') || 'основные правила'}${spec0.goal.level ? `, цель — ${spec0.goal.level} уровней и финальный босс` : ''}.`);
    const vars = Codex.variants(spec0);
    await think(`🧪 Собираю ${vars.length} варианта игры и даю роботу-тестеру в них поиграть…`, 200);
    const tested = [];
    for (let i = 0; i < vars.length; i++) {
      await tick();
      const res = Codex.playtestSpec(vars[i].spec, 150);
      tested.push({ v: vars[i], res, score: Codex.rate(res, vars[i].spec) });
      await think(`   Вариант ${i + 1} «${vars[i].name}»: робот ${spec0.timeLimit ? `успел ${res.score} очков за ${res.time} с` : `продержался ${res.time} с`}, дошёл до ${res.level} уровня.`, 260);
    }
    tested.sort((a, b) => b.score - a.score);
    const pick = tested[0];
    await think(`⚖️ Самым интересным получился вариант «${pick.v.name}».`);
    await think('🎛 Подбираю сложность, чтобы было не скучно и не слишком трудно…', 150);
    const best = await Codex.tune(pick.v.spec, it => {
      const verdict = pick.v.spec.timeLimit ? (it.m > 0.82 ? 'легко' : it.m < 0.62 ? 'трудно' : 'то что надо') : (it.m > 110 ? 'слишком легко' : it.m < 70 ? 'слишком трудно' : 'то что надо');
      lines.push(`   темп ${it.pace.toFixed(2)}: робот ${pick.v.spec.timeLimit ? `поймал ${Math.round(it.m * 100)}%` : `продержался ${Math.round(it.m)} с`} — ${verdict}`);
      if (io.onThink) io.onThink(lines.slice());
    }, { tick: () => pause(220) });
    const spec = Object.assign({}, pick.v.spec, { pace: best.pace });
    spec.id = spec.id + 'u';
    const n = spec.spawns.length + spec.touch.length + spec.events.length + spec.abilities.length + Object.keys(spec.things).length;
    await think(`💾 Пишу код: чертёж из ${n} правил для своего движка.`, 300);
    const secs = Math.round((Date.now() - t0) / 1000);
    await think(`✅ Готово! Думал ${secs} с, робот сыграл ${3 * (vars.length + (best ? 1 : 0))}+ партий.`, 100);
    this.lastSpec = spec;
    const learned = asked.length ? `\nПо ходу я спросил у Claude, как это делается, и научился: теперь это умею сам 📚` : '';
    return this.say(`Готово! Я сам сделал игру «${spec.title}» 🧑‍💻 (Кодекс · Ультра)\n${Codex.describe(spec)}.\nДобавил: ${spec.notes.join(', ') || 'основные правила'}. Сложность подобрал по тестам робота.${learned}\nХочешь что-то поменять? Напиши «быстрее», «добавь босса» или «вместо … …».`,
      Object.assign({}, meta, { src: 'codex', intent: 'make_game', mood: 'happy', codexLevel: 'ultra', think: lines.slice(), thinkSecs: secs, game: { kind: 'builtin', key: 'codex', opts: spec } }));
  }
  async codexEdit(text, io) {
    const level = this.settings.codexLevel || 'high';
    let r = Codex.edit(this.lastSpec, text, this.codexMem);
    const lines = [];
    if (!r.changes.length && r.unknownMech.length && level === 'ultra' && this.canAskClaude()) {
      const phrase = r.unknownMech[0];
      if (io.onThinking) io.onThinking('ultra');
      lines.push(`❓ Я не умею «${phrase}». Спрашиваю у Claude, как это делается…`); if (io.onThink) io.onThink(lines.slice());
      try {
        const ans = await this.askHow(Codex.mechPrompt(phrase, this.lastSpec), io);
        const v = Codex.validateRecipe(ans);
        if (v.ok) {
          const rec = Codex.learnRecipe(this.codexMem, phrase, v.recipe); this.save();
          lines.push(`📚 Понял, как делать «${rec.name}»: ${rec.explain} Запомнил.`); if (io.onThink) io.onThink(lines.slice());
          const s = JSON.parse(JSON.stringify(this.lastSpec)); Codex.applyRecipe(s, rec, s.notes); s.version = (s.version || 1) + 1;
          r = { spec: s, changes: ['приём «' + rec.name + '» (выучил сам)'] };
        }
      } catch (e) { if (e && e.code === 'cancelled') return this.say('Хорошо, оставим как есть.', { src: 'rule' }); }
    }
    if (!r.changes.length) {
      return this.say('Не понял, что поменять 🤔 Можно так: «быстрее», «медленнее», «сложнее», «легче», «больше врагов», «добавь босса», «добавь бонусы», «5 жизней», «вместо кота собака», «поменяй мир на космос», «назови игру …».' +
        (level === 'ultra' ? '' : '\nА в режиме Ультра я могу спросить у Claude, как сделать что-то новое, и научиться.'), { src: 'rule', intent: 'make_game', chips: ['Быстрее', 'Добавь босса', 'Сложнее', 'Покажи код'] });
    }
    let spec = r.spec;
    if (level === 'ultra' && r.changes.some(c => /быстрее|медленнее|сложнее|легче|врагов|босс/.test(c)) === false && r.changes.some(c => /приём|добавил/.test(c))) {
      const res = Codex.playtestSpec(spec, 120);
      lines.push(`🧪 Проверил роботом: продержался ${res.time} с.`);
    }
    this.lastSpec = spec;
    return this.say(`Поменял: ${r.changes.join(', ')} ✅ Вот новая версия «${spec.title}».`, { src: 'codex', intent: 'make_game', mood: 'happy', codexLevel: level, think: lines.length ? lines : undefined, game: { kind: 'builtin', key: 'codex', opts: spec } });
  }

  // кнопка «Не то»: научить другому ответу на фразу
  startTeach(phrase) {
    this.ctx = { type: 'teach', phrase };
    return this.fill(`Хорошо! Что мне нужно было ответить на «${phrase}»? Напиши ответ, и я запомню.`);
  }
}

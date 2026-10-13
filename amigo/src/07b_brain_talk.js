/* ===== 07b_brain_talk.js ===== */
// Разговорная часть мозга: Амиго понимает рассказы о себе («я люблю…», «у меня есть…»),
// вопросы к нему («ты умеешь…?», «а ты?»), отдельные слова, учит новые слова и сам поддерживает беседу.
// Здесь же «умный запасной ответ»: вместо «я ещё не научился» Амиго отвечает по смыслу.
// темы, которые вполне могут оказаться ответом на вопрос Амиго («синий», «кошка», «наверное, футбол»)
const TALK_ANSWERISH = new Set(['statement', 'user_likes', 'user_dislikes', 'user_fav', 'user_doing', 'user_has', 'user_wants', 'user_from', 'user_grade', 'yes', 'no',
  'dont_know', 'gibberish', 'user_good', 'user_bad', 'pets', 'set_name', 'family', 'fav_color', 'fav_food', 'fav_game', 'fav_music', 'fav_movie',
  'achievement', 'knowledge', 'bot_likes', 'bot_know', 'bot_opinion', 'school_talk', 'friends_talk']);
// темы-«рамки»: если сеть выбрала одну из них, точный вид уточняем по словам
const TALK_FRAME_FAMILY = new Set(['user_likes', 'user_dislikes', 'user_has', 'user_from', 'user_wants', 'user_doing', 'bot_can', 'bot_likes', 'bot_opinion', 'bot_know',
  'statement', 'remember', 'knowledge', 'fav_food', 'fav_game', 'fav_music', 'fav_movie', 'fav_color', 'bot_feelings', 'help']);
// навыки, которые можно попросить словами «ты можешь …?»: «можешь засечь 5 минут?» — сразу делаем
const TALK_SKILLS = new Set(['time', 'date', 'countdown', 'calc', 'joke', 'fact', 'riddle', 'quiz', 'rps', 'guess_number', 'guess_my_number', 'coin', 'dice', 'random',
  'choose', 'timer', 'timer_cancel', 'weather', 'translate', 'story', 'poem', 'sing', 'dance', 'recommend', 'advice', 'motivation', 'make_game', 'play', 'tongue_twister',
  'voice_on', 'voice_off', 'teach', 'homework', 'clear_chat', 'codex_on', 'show_code', 'cheer_me', 'get_to_know', 'lets_talk']);
const TALK_ACTS = new Set(['bot_does', 'user_likes', 'user_dislikes', 'user_has', 'user_from', 'user_grade', 'user_fav', 'user_wants', 'user_doing', 'bot_can', 'bot_likes', 'bot_opinion',
  'bot_know', 'bot_fav', 'ask_back', 'why', 'what', 'bot_wrong', 'get_to_know', 'lets_talk', 'tongue_twister', 'statement', 'pets']);

Object.assign(Brain.prototype, {
  // ---------- память о пользователе ----------
  ensureProfile() {
    const P = this.profile;
    for (const k of ['facts', 'likes', 'dislikes', 'has', 'wants', 'asked']) if (!Array.isArray(P[k])) P[k] = [];
    for (const k of ['favs', 'words']) if (!P[k] || typeof P[k] !== 'object') P[k] = {};
    if (P.from == null) P.from = '';
    return P;
  },
  pushMem(list, v, max = 25) {
    v = String(v).trim(); if (!v) return;
    const i = list.findIndex(x => Text.clean(x) === Text.clean(v));
    if (i >= 0) list.splice(i, 1);
    list.push(v); if (list.length > max) list.shift();
  },
  setTopic(t) { this.topic = t; this._topicSet = true; },
  // Амиго задаёт вопрос и ждёт ответа
  expect(q, key, acks, extra = {}) {
    this.ctx = { type: 'expect', key, acks: acks || null, q };
    this.setTopic({ kind: 'fav', key });
    return this.say(q, Object.assign({ src: 'talk', mood: 'happy' }, extra));
  },

  // ---------- несколько частей в одной фразе ----------
  // «привет, как дела?», «спасибо! а расскажи шутку», «хорошо, а ты?»
  async routeMulti(text, io) {
    const g = Talk.splitGreeting(text);
    if (g) {
      const a = await this.route(g.rest, Text.clean(g.rest), io, true);
      if (!a || a.unsure || ['greet', 'gibberish'].includes(a.intent)) return null;
      const hi = a.intent === 'how_are_you' || a.intent === 'set_name' ? 'Привет! ' : U.pick(['Привет{,name}! ', 'Привет-привет! ', 'Хола{,name}! '], this.rnd);
      return Object.assign(a, { text: hi + a.text });
    }
    const th = Talk.splitThanks(text);
    if (th) {
      const a = await this.route(th.rest, Text.clean(th.rest), io, true);
      if (!a || a.unsure || a.intent === 'thanks') return null;
      return Object.assign(a, { text: U.pick(['Пожалуйста! ', 'Всегда рад! ', 'Не за что! '], this.rnd) + a.text });
    }
    const b = Talk.splitAskBack(text);
    if (b) {
      this._topicSet = false;
      const a = await this.route(b.main, Text.clean(b.main), io, true);
      if (!a || a.unsure) return null;
      if (!this._topicSet && a.intent) this.topic = { kind: 'intent', tag: a.intent };
      const back = this.askBackText();
      // уже спросили что-то в ответе? тогда вопрос из первой части убираем
      const first = a.text.replace(/\s*[^.!?…]*\?\s*$/, '').trim() || a.text;
      return Object.assign(a, { text: first + ' ' + back });
    }
    return null;
  },

  // ---------- «а ты?» ----------
  askBackText() {
    const tp = this.topic || {}, tag = tp.tag;
    if (tp.kind === 'fav' && tp.key) return BOT_FAVS[tp.key] || BOT_FAVS.open;
    if (tp.kind === 'like' && tp.entry) return 'Я? ' + Lex.opinion(tp.entry, this.rnd);
    if (tp.kind === 'from' || tag === 'user_from') return 'А я живу прямо у тебя в телефоне 📱 Тут уютно!';
    if (tp.kind === 'grade' || tag === 'user_grade') return 'А я учусь каждый день — у тебя! 😄';
    if (tp.kind === 'want' || tag === 'user_wants') return 'А я мечтаю выучить побольше слов и стать для тебя лучшим собеседником 🌟';
    if (tp.kind === 'doing' || tag === 'user_doing' || tag === 'what_doing') return 'А я болтаю с тобой — это моё любимое занятие 😊';
    if (tag === 'set_name' || tag === 'name_bot') return 'А меня зовут Амиго 🙂 По-испански это «друг».';
    if (['user_good', 'user_bad', 'how_are_you', 'greet', 'goodmorning'].includes(tag)) return U.pick(['А у меня всё отлично, спасибо! 😊', 'У меня тоже всё хорошо: мои нейроны бодры!', 'А у меня супер — ведь ты мне пишешь 😄'], this.rnd);
    if (tag === 'user_tired') return 'А я никогда не устаю — я же программа 😄 Но отдых — это важно!';
    if (tag === 'remember' || tag === 'user_has') return 'А у меня из вещей только код и нейроны 😄 Зато есть ты!';
    if (tag === 'age_bot' || /лет/.test(tp.text || '')) return `А я совсем молодой: появился в 2026 году!`;
    return U.pick(['А я? У меня всё хорошо, болтаю с тобой 😊', 'А мне интересно всё, что ты рассказываешь!', 'Я тоже! 😊'], this.rnd);
  },

  // ---------- ответ про отдельное слово ----------
  wordReply(hit, text, cls) {
    const e = hit.entry, f = Lex.followUp(e, this.rnd);
    this.setTopic({ kind: 'like', entry: e });
    const meta = { src: 'memory', intent: 'word', conf: cls && cls.conf, top: cls && cls.top, mood: 'happy' };
    if (f.offer) { this.ctx = { type: 'offer', act: f.offer }; return this.say(Lex.describe(e) + ' ' + f.q, meta); }
    if (f.key && f.key !== 'open') return this.expect(Lex.describe(e) + ' ' + f.q, f.key, null, meta);
    return this.say(Lex.describe(e) + ' ' + f.q, meta);
  },

  // ---------- когда сеть не уверена ----------
  async smartFallback(text, t, cls, io, o = {}) {
    const words = Text.words(text);
    const fr = Talk.frames(text)[0];
    if (fr) return this.handle(fr.type, text, t, cls, io);
    if (Talk.fav(text)) return this.handle('user_fav', text, t, cls, io);
    if (/класс|садик|детск\S+ сад/.test(t) && Talk.grade(text) && /^(?:ну\s+)?я\s/.test(t)) return this.handle('user_grade', text, t, cls, io);
    const hit = Lex.main(text);
    // одно-два слова: «кошка», «мой кот», «футбол!», «аниме?»
    if (hit && (words.length <= 2 || (words.length <= 3 && !o.question))) return this.wordReply(hit, text, cls);
    // вопрос о любимом у Амиго: «какой цвет ты любишь больше всего?»
    const fk = Talk.favKey(text);
    if (fk && o.aboutBot && /(любим|нрав|любишь|обожаешь)/.test(t)) {
      const own = { fav_color: 'fav_color', fav_food: 'fav_food', fav_music: 'fav_music', fav_movie: 'fav_movie', fav_cartoon: 'fav_movie', fav_game: 'fav_game' }[fk];
      return this.handle(own || 'bot_fav', text, t, cls, io);
    }
    if (o.question && !o.aboutBot) return this.knowledge(text, io, cls);
    if (this.superMode()) { const a = await this.askSuper(text, io, cls); if (a) return a; }
    // сеть не уверена, но догадка неплохая — лучше ответить по догадке, чем сдаться
    const it = this.byTag.get(cls.tag) || {};
    if (cls.conf >= 0.35 && cls.margin >= 0.1 && cls.tag !== 'gibberish' && !['crisis', 'forget', 'clear_chat', 'voice_on', 'voice_off', 'codex_on', 'codex_off', 'timer_cancel'].includes(cls.tag) && (it.r || it.act)) return this.handle(cls.tag, text, t, cls, io);
    // незнакомое слово — спросим, что это, и запомним
    if (!hit && words.length <= 2 && !o.question && !/\d/.test(t) && Talk.meaningful(text) && !words.every(w => Lex.STOP.has(w)) && (words.length === 1 || cls.known < 0.4)) {
      const w = words.join(' ');
      this.ctx = { type: 'teach_word', word: w };
      return this.say(U.pick([`«${U.cap(w)}»? Я пока не знаю такого слова 🤔 Что это? Расскажи — и я запомню!`, `Хм, «${w}» — новое для меня слово 🧐 Объяснишь, что это? Я выучу!`], this.rnd),
        { src: 'talk', intent: cls.tag, conf: cls.conf, top: cls.top, mood: 'think', chips: ['Не скажу', 'Что ты умеешь?'] });
    }
    // вопрос к Амиго, который сеть не поняла
    if (o.question) {
      const guess = cls.conf > 0.2 ? ` Похоже на тему «${cls.top[0].title}», но я не уверен.` : '';
      this.ctx = { type: 'teach_offer', phrase: text };
      return this.say(U.pick([`Хороший вопрос! 🤔 Но ответа я пока не знаю.${guess} Если подскажешь — нажми «Научить», и я запомню.`, `Ой, тут я пока не силён 😅${guess} Научишь меня? Нажми «Научить».`], this.rnd),
        { src: 'net', intent: cls.tag, conf: cls.conf, top: cls.top, mood: 'think', chips: ['Научить', 'Что ты умеешь?'], unsure: true });
    }
    // рассказ или реплика — живой ответ по смыслу
    if (words.length >= 2 || hit) {
      this.setTopic({ kind: 'doing', text });
      return this.say(Talk.reply(text, this.rnd, { lex: hit }), { src: 'talk', intent: 'statement', conf: cls.conf, top: cls.top, mood: Talk.mood(text) < 0 ? 'care' : 'happy' });
    }
    return this.notUnderstood(text, cls);
  },

  // ---------- ответы новых тем ----------
  async handleTalk(tag, text, t, cls, io, meta) {
    const P = this.ensureProfile(), rnd = this.rnd;
    const fr = Talk.frame(text, tag);
    const obj = fr ? fr.obj : '';
    const hit = obj ? Lex.main(obj) : Lex.main(text);
    const tm = Object.assign({}, meta, { src: 'talk' });
    const echoOf = () => {
      const m = Talk.low(text).replace(/[?!.…]+$/, '').trim();
      return U.cap(Talk.reflect(m));
    };
    const about = (prefix = '') => hit ? prefix + Lex.describe(hit.entry) : '';
    switch (tag) {
      case 'user_likes': {
        if (!obj && !hit) return this.say(U.pick(['Здорово, когда что-то нравится! 😊 А что именно?', 'Класс! Расскажи, что ты любишь?'], rnd), tm);
        this.pushMem(P.likes, obj || hit.form); this.save();
        if (hit) this.setTopic({ kind: 'like', entry: hit.entry }); else this.setTopic({ kind: 'like_text', text: obj });
        const r1 = U.pick(['Классно!', 'Здорово!', 'Понимаю тебя!', 'Отличный вкус!', 'Ого!'], rnd);
        const q = hit ? Lex.followUp(hit.entry, rnd) : null;
        const tail = q && q.key && !P.favs[q.key] && rnd() < 0.5 ? q.q : U.pick(['Запомню! 😊', 'Я запомнил 😊', 'Запомнил! А что ещё ты любишь?', 'Буду знать 😊 А почему тебе это нравится?'], rnd);
        if (q && q.key && tail === q.q) this.ctx = { type: 'expect', key: q.key, acks: null, q: q.q };
        return this.say(`${echoOf()}? ${r1} ${about()} ${tail}`.replace(/\s+/g, ' '), Object.assign(tm, { mood: 'happy' }));
      }
      case 'user_dislikes': {
        if (obj || hit) { this.pushMem(P.dislikes, obj || hit.form); this.save(); }
        return this.say(`${echoOf()}? ${U.pick(['Понимаю, у всех свои вкусы 🙂', 'Бывает! Всем нравится разное.', 'Ничего страшного, так бывает.'], rnd)} ${U.pick(['А что тебе нравится больше?', 'А что тогда любишь?', 'Запомню, чтобы не предлагать 😉'], rnd)}`, tm);
      }
      case 'user_has': {
        if (hit && hit.entry.c === 'pets_farm') return this.handleTalk('pets', text, t, cls, io, meta);
        if (obj || hit) { this.pushMem(P.has, obj || hit.form); this.save(); }
        if (hit) this.setTopic({ kind: 'like', entry: hit.entry });
        return this.say(`${echoOf()}? ${U.pick(['Круто!', 'Здорово!', 'Вот это да!', 'Классно!'], rnd)} ${about()} ${U.pick(['Тебе нравится?', 'Расскажи, какой он?', 'Давно он у тебя?', 'Поздравляю! 🎉'], rnd)}`.replace(/\s+/g, ' '), Object.assign(tm, { mood: 'happy' }));
      }
      case 'pets': {
        const pet = hit && ['pets_farm', 'animals_wild'].includes(hit.entry.c) ? hit : null;
        if (pet) { this.pushMem(P.has, pet.form); this.save(); this.setTopic({ kind: 'like', entry: pet.entry }); }
        const s = pet ? `${U.pick(['Здорово!', 'Как классно!', 'Обожаю!'], rnd)} ${pet.entry.e} ${U.cap(pet.entry.w)} — ${pet.entry.d}. Как зовут твоего питомца?` : U.pick(['Здорово! Как зовут твоего питомца? 🐾', 'Обожаю животных! Как его зовут? 🐾'], rnd);
        return this.expect(s, 'pet_name', ['{ans} — классное имя! 🐾 Передавай привет!', 'Какое милое имя — {ans}! Запомню 😊'], tm);
      }
      case 'user_from': {
        let place = obj || (hit ? hit.form : '');
        place = place.replace(/^(?:город[еа]?|город)\s+/, '');
        if (!place) return this.say('А откуда ты? Напиши город 🙂', tm);
        const c = Skills.cityKnown(place);
        P.from = c ? c.name : U.cap(place);
        if (c) P.city = { name: c.name, lat: c.lat, lon: c.lon };
        this.save(); this.setTopic({ kind: 'from' });
        return this.say(`${P.from}? ${U.pick(['Здорово!', 'Классное место!', 'Ого!'], rnd)} ${hit && hit.entry.c === 'geography' ? about() + ' ' : ''}Запомнил, откуда ты 🏙️${c ? ' Теперь могу рассказать про погоду там — просто спроси «какая погода».' : ''}`, tm);
      }
      case 'user_grade': {
        const g = Talk.grade(text);
        if (!g) return this.say('А в каком ты классе? 📚', tm);
        P.grade = g.n || g.kind; this.save(); this.setTopic({ kind: 'grade' });
        const s = g.kind === 'садик' ? 'В садике весело! 🧸 Ты уже знаешь буквы?' : g.kind === 'студент' ? 'Студент — это круто! 🎓 Что изучаешь?' :
          g.n <= 4 ? `${g.n} класс — время открытий! 📚` : g.n <= 8 ? `${g.n} класс — классный возраст! 📚` : `${g.n} класс? Ты уже почти взрослый! 🎓`;
        if (g.kind) return this.say(s, tm);
        if (!P.favs.fav_subject) return this.expect(s + ' А какой у тебя любимый предмет?', 'fav_subject', null, tm);
        return this.say(s + ' Если понадобится помощь с уроками — я рядом!', tm);
      }
      case 'user_fav': {
        const f = Talk.fav(text);
        if (!f) return this.say('Расскажи, что у тебя самое любимое? 😊', tm);
        P.favs[f.key] = f.value; this.save();
        this.setTopic({ kind: 'fav', key: f.key });
        const h = Lex.main(f.value);
        const mine = BOT_FAVS[f.key];
        return this.say(`${U.cap(f.value)} — ${U.pick(['отличный выбор!', 'классно!', 'хороший вкус!', 'здорово!'], rnd)} ${h ? h.entry.e + ' ' : ''}Запомнил 😊${mine && rnd() < 0.6 ? ' ' + mine : ''}`, Object.assign(tm, { mood: 'happy' }));
      }
      case 'user_wants': {
        const w = obj || '';
        if (w) { this.pushMem(P.wants, w); this.save(); }
        this.setTopic({ kind: 'want' });
        const prof = hit && hit.entry.c === 'people_family_professions';
        const lead = /(стать|быть|стану|буду)\s/.test(Talk.low(text)) && w ? `Стать ${w}?` : echoOf() + '?';
        return this.say(`${lead} ${U.pick(['Отличная мечта! 🌟', 'Здорово! Я в тебя верю 💪', 'Классная цель! 🌟'], rnd)}${prof ? ' ' + about() : ''} ${U.pick(['Мечты сбываются, если идти к ним понемногу каждый день.', 'А что для этого нужно, как думаешь?', 'Расскажи, почему именно это?'], rnd)}`.replace(/\s+/g, ' '), Object.assign(tm, { mood: 'happy' }));
      }
      case 'user_doing': {
        this.setTopic({ kind: 'doing', text });
        if (hit) this.topic.entry = hit.entry;
        return this.say(Talk.reply(text, rnd, { lex: hit }), Object.assign(tm, { mood: Talk.mood(text) < 0 ? 'care' : 'happy' }));
      }
      case 'statement': {
        this.setTopic({ kind: 'doing', text });
        const short = Text.words(text).length <= 2 && !hit;
        if (short) return this.say(U.pick(['Ага 🙂 Расскажи что-нибудь ещё!', 'Понятно! О чём поболтаем?', 'Угу 👂 Я слушаю.'], rnd), Object.assign(tm, { chips: ['Расскажи шутку', 'Давай поговорим', 'Интересный факт'] }));
        return this.say(Talk.reply(text, rnd, { lex: hit }), Object.assign(tm, { mood: Talk.mood(text) < 0 ? 'care' : 'happy' }));
      }
      case 'bot_can': {
        const what = obj || '';
        // «можешь рассказать шутку?» — просто делаем это
        if (what) {
          const c2 = this.classify(what);
          if (c2.conf >= 0.55 && TALK_SKILLS.has(c2.tag)) return this.handle(c2.tag, what, Text.clean(what), c2, io);
        }
        if (/игр|сыгра|поигра/.test(what) && (GameList.find(what) || /(змейк|тетрис|2048|сап[её]р|крестик|понг|арканоид|флэппи|пар[уы])/.test(what))) return this.makeGame(what, Text.clean(what), cls, io);
        if (/(сделать|создать|запрограммировать|написать|придумать)\s+игр/.test(what)) return this.handle('codex_how', text, t, cls, io);
        if (/(посчитать|считать|решать\s+пример|математик)/.test(what)) return this.say('Конечно! Считаю быстрее калькулятора 😎 Напиши пример, например **17 × 23** или **корень из 144**.', Object.assign(tm, { chips: ['Сколько будет 17 × 23?'] }));
        const r = this.canAnswer(what);
        if (r) return this.say(r, tm);
        return this.say(U.pick([`Хм, «${what || 'это'}» я пока не умею 😅 Зато я умею болтать, шутить, считать, играть и даже делать игры! Что выберешь?`, `Этого я пока не умею, но учусь каждый день! 🤖 Хочешь, сыграем или расскажу что-нибудь интересное?`], rnd),
          Object.assign(tm, { chips: ['Что ты умеешь?', 'Расскажи шутку', 'Сыграем'] }));
      }
      case 'bot_does': {
        if (hit) {
          this.setTopic({ kind: 'like', entry: hit.entry });
          return this.say(`${U.pick(['Сам я так не умею — у меня нет глаз и рук 😄 Но', 'Я программа, поэтому сам не могу, но'], rnd)} знаю: ${Lex.describe(hit.entry)} ${U.pick(['А ты?', 'А тебе нравится?', 'Расскажешь, что тебе в этом нравится?'], rnd)}`, Object.assign(tm, { mood: 'happy' }));
        }
        return this.say(U.pick([`Я программа, поэтому сам не могу${obj ? ` — но про «${obj}» мне было бы интересно послушать` : ''}! Расскажешь?`, 'У меня нет глаз и рук, зато есть ты — расскажи, как это! 😊'], rnd), tm);
      }
      case 'bot_likes': case 'bot_opinion': {
        if (hit) {
          this.setTopic({ kind: 'like', entry: hit.entry });
          return this.say(Lex.opinion(hit.entry, rnd) + ' ' + U.pick(['А ты?', 'А тебе нравится?', tag === 'bot_opinion' ? 'А ты что думаешь?' : 'А ты как к этому относишься?'], rnd), Object.assign(tm, { mood: 'happy' }));
        }
        if (obj) return this.say(U.pick([`Про «${obj}» я знаю мало, но звучит интересно! А тебе нравится?`, `Хм, «${obj}»… Мне интересно всё новое! Расскажешь, что это?`], rnd), tm);
        return this.say(U.pick(['Мне нравится почти всё, о чём можно узнать что-то новое! А тебе?', 'У нейросетей нет любимчиков, но мне интересно всё на свете 😊 А ты как к этому относишься?'], rnd), tm);
      }
      case 'bot_know': {
        const q = obj;
        if (!q && !hit) return this.say('Я знаю много всего: животных, игры, мультики, города, науку… Спроси: «ты знаешь …?» или «что такое …?» 🙂', tm);
        if (hit) { this.setTopic({ kind: 'like', entry: hit.entry }); return this.say(U.pick(['Конечно знаю! ', 'Знаю! ', 'Да! '], rnd) + Lex.describe(hit.entry) + ' ' + U.pick(['А тебе нравится?', 'А ты откуда про это знаешь?', 'Расскажешь, что тебе в этом нравится?'], rnd), Object.assign(tm, { src: 'memory', mood: 'happy' })); }
        const kb = Skills.kbFind(q);
        if (kb) return this.say('Знаю! ' + kb.s, Object.assign(tm, { src: 'memory' }));
        if (this.settings.online || this.superMode()) { const a = await this.knowledge('что такое ' + q, io, cls); if (a && !a.unsure) return a; }
        this.ctx = { type: 'teach_word', word: Text.clean(q).split(' ').slice(0, 3).join(' ') };
        return this.say(`Нет, про «${q}» я пока не слышал 🤔 Расскажешь, что это? Я запомню!`, Object.assign(tm, { mood: 'think', chips: ['Не скажу'] }));
      }
      case 'bot_fav': {
        const fk = Talk.favKey(text);
        const key = fk && BOT_FAVS[fk] ? fk : null;
        if (!key) return this.say(U.pick(['Мне нравится всё, что связано со знаниями и играми! А что любишь ты?', 'Моё любимое — болтать с тобой 😊 А твоё?'], rnd), tm);
        return this.expect(BOT_FAVS[key] + ' А твоё?', key, null, tm);
      }
      case 'ask_back': return this.say(this.askBackText(), tm);
      case 'why': {
        const last = this.lastIntent;
        if (['fact', 'knowledge', 'word'].includes(last)) return this.say(U.pick(['Так устроен мир 🙂 Если хочешь подробнее, спроси целиком: «почему …?» — поищу ответ.', 'Хороший вопрос! Учёные тоже часто спрашивают «почему» — так и делаются открытия 🔬'], rnd), tm);
        if (['bot_likes', 'bot_opinion', 'bot_fav', 'fav_color', 'fav_food', 'fav_music', 'fav_movie', 'fav_game'].includes(last)) return this.say(U.pick(['Потому что это интересно! Мне нравится всё, о чём можно узнать новое 🤓', 'Просто нравится — как тебе что-то нравится без объяснений 😊'], rnd), tm);
        return this.say(U.pick(['Хороший вопрос! 🤔 Иногда я и сам не знаю почему — я ведь ещё учусь.', 'Потому что так подсказали мои нейроны 😄 А ты как думаешь?', 'Хм, а ты как думаешь — почему?'], rnd), tm);
      }
      case 'what': {
        const last = this.lastBotText;
        if (!last) return this.say('Я Амиго — нейросеть-друг 🙂 Спроси меня о чём-нибудь или напиши «что ты умеешь».', Object.assign(tm, { chips: ['Что ты умеешь?'] }));
        const short = last.replace(/\*\*/g, '').split('\n')[0].slice(0, 140);
        return this.say(`Прости, я сказал непонятно 😅 Я имел в виду: «${short}${short.length >= 140 ? '…' : ''}». Можем поговорить о чём-нибудь другом — выбирай!`, Object.assign(tm, { chips: ['Расскажи шутку', 'Давай поговорим', 'Что ты умеешь?'] }));
      }
      case 'bot_wrong': {
        const prev = this.prevUserText;
        if (prev && Text.clean(prev)) {
          this.ctx = { type: 'teach', phrase: prev };
          return this.say(`Ой, извини! 😅 Я ещё учусь. А как надо было ответить на «${prev.length > 60 ? prev.slice(0, 59) + '…' : prev}»? Напиши — и я запомню.`, Object.assign(tm, { mood: 'learn', chips: ['Отмена'] }));
        }
        return this.say('Ой, извини! Я ещё учусь 😅 Если я ответил не то, нажми «Не то» под ответом и научи меня.', tm);
      }
      case 'get_to_know': case 'lets_talk': {
        const s = this.pickStarter(tag === 'get_to_know');
        const intro = tag === 'lets_talk' ? U.pick(['Давай! 😊 ', 'С удовольствием! ', 'Конечно, давай поболтаем! '], rnd) : U.pick(['Давай! 😊 ', 'Отличная идея! ', 'С радостью! '], rnd);
        if (!s) return this.say(intro + 'Расскажи, что у тебя нового?', tm);
        return this.expect(intro + s.q, s.key, s.acks, tm);
      }
      case 'tongue_twister': {
        this.lastAct = 'tongue_twister';
        const list = typeof TWISTERS !== 'undefined' && TWISTERS.length ? TWISTERS : ['Шла Саша по шоссе и сосала сушку.'];
        return this.say(`Скороговорка! 👅 «${list[this.deal('twister', list)]}» Попробуй сказать быстро три раза!`, Object.assign(tm, { chips: ['Ещё скороговорку', 'Расскажи шутку'] }));
      }
    }
    return null;
  },
  canAnswer(what) {
    if (typeof BOT_CAN === 'undefined' || !what) return null;
    if (!this._canIdx) {
      this._canIdx = BOT_CAN.map(([v, kind, r]) => ({ st: Text.words(v).map(Text.stem), kind, r }));
    }
    const st = Text.words(what).map(Text.stem);
    let best = null, bl = 0;
    for (const c of this._canIdx) {
      if (c.st.length > st.length) continue;
      let ok = true; for (let i = 0; i < c.st.length; i++) if (c.st[i] !== st[i]) { ok = false; break; }
      if (ok && c.st.length > bl) { best = c; bl = c.st.length; }
    }
    return best ? best.r : null;
  },
  pickStarter(personal) {
    const P = this.ensureProfile();
    const list = STARTERS.filter(s => !P.asked.includes(s.q) && !(s.key.startsWith('fav_') && P.favs[s.key]) && (!personal || s.key !== 'would_rather'));
    const pool = list.length ? list : STARTERS;
    const s = U.pick(pool, this.rnd);
    this.pushMem(P.asked, s.q, 60);
    return s;
  },

  // ---------- ответы на вопросы Амиго и обучение словам ----------
  async inCtxTalk(c, text, t, cls, io) {
    const P = this.ensureProfile(), rnd = this.rnd;
    const quit = /^(стоп|хватит|отмена|не\s+скажу|не\s+хочу|секрет|не\s+буду|потом|забей)(?![а-яa-z0-9])/.test(t);
    const other = cls.conf >= 0.75 && !TALK_ANSWERISH.has(cls.tag) && !(cls.tag || '').startsWith('custom_');
    if (c.type === 'teach_word') {
      this.ctx = null;
      if (quit || (cls.tag === 'no' && cls.conf > 0.6)) return this.say('Хорошо, не страшно 🙂', { src: 'rule' });
      if (other || Talk.isQuestion(text) || cls.tag === 'dont_know') return null;
      let d = String(text).trim().replace(/^(?:ну|это|это\s+такой|это\s+такая|это\s+такое|—|-)\s+/i, '').replace(/[.!]+$/, '');
      if (Text.words(d).length < 2) return null;
      if (d[0] && d[0] !== d[0].toLowerCase() && !/^[А-ЯЁA-Z]{2}/.test(d)) d = d[0].toLowerCase() + d.slice(1);
      const w = Text.clean(c.word);
      const hitD = Lex.main(d);
      P.words[w] = { d, e: hitD ? hitD.entry.e : '💡' };
      Lex.addUser({ [w]: P.words[w] });
      this.save();
      return this.say(U.pick([`Спасибо! Запомнил: ${P.words[w].e} ${U.cap(w)} — ${d} 📚`, `Ура, новое слово! ${P.words[w].e} ${U.cap(w)} — ${d}. Теперь я это знаю 🧠`], rnd),
        { src: 'rule', intent: 'teach', mood: 'learn' });
    }
    // c.type === 'expect': Амиго задал вопрос и ждёт ответа
    this.ctx = null;
    if (quit) return this.say('Хорошо, можно и не отвечать 🙂', { src: 'rule' });
    // «как дела?» — «хорошо, а у тебя?»
    if (c.key === 'mood') {
      const b = Talk.splitAskBack(text), main = b ? b.main : text, mt = Text.clean(main);
      const mc = b ? this.classify(main) : cls;
      const m = Talk.mood(main);
      let tag = null;
      if (['user_good', 'user_bad', 'user_tired', 'user_angry', 'user_lonely', 'bored', 'sick', 'worried'].includes(mc.tag) && mc.conf >= 0.4) tag = mc.tag;
      else if ((mc.tag === 'yes' && mc.conf >= 0.5) || m > 0 || /^(норм\S*|хорош\S*|отлич\S*|супер|класс\S*|неплох\S*|пойдет|ничего|нормас|збс|четко|топ|огонь)(?![а-я])/.test(mt)) tag = 'user_good';
      else if (m < 0 || /^(плохо|так себе|не очень|ужасно|грустно|фигово|паршиво)/.test(mt)) tag = 'user_bad';
      if (!tag) return null;
      const a = await this.handle(tag, main, mt, mc, io);
      if (b) { this.topic = { kind: 'intent', tag: 'how_are_you' }; this._topicSet = true; a.text = a.text.replace(/\s*[^.!?…]*\?\s*$/, '').trim() + ' ' + this.askBackText(); }
      return a;
    }
    if (other || (Talk.isQuestion(text) && cls.tag !== 'user_fav')) return null;
    // в ответе целый рассказ («да, у меня есть кошка») — пусть его разберёт обычный путь
    if (Talk.frames(text).length && Text.words(text).length >= 3) return null;
    if (cls.tag === 'dont_know' && cls.conf > 0.5) return this.say(U.pick(['Ничего страшного! Подумаешь и расскажешь потом 🙂', 'Бывает! Это сложный выбор 😄'], rnd), { src: 'talk' });
    const words = Text.words(text);
    let ans = String(text).trim().replace(/[.!?…]+$/, '')
      .replace(/^(?:(?:ну|да|ага|наверное|наверно|мне\s+кажется|я\s+думаю|думаю|пожалуй|хм|эм|конечно|короче|это|я\s+бы\s+выбрал[а]?|я\s+выбираю|выбираю)[,\s]+)+/i, '')
      .replace(/^(?:мой|моя|мое|моё|мои)\s+(?:самый\s+|самая\s+)?любим\S*\s+\S+\s*(?:это\s+|—\s*|-\s*)?/i, '')
      .replace(/^(?:я\s+люблю|мне\s+нравится|мне\s+нравятся|я\s+хочу\s+стать|хочу\s+стать|я\s+хочу|хочу|его\s+зовут|ее\s+зовут|её\s+зовут|зовут)\s+/i, '').trim();
    if (!ans) ans = String(text).trim();
    const key = c.key || 'open';
    const longAns = words.length > 6 || key === 'open' || key === 'today';
    if (key.startsWith('fav_') && !longAns) P.favs[key] = ans;
    else if (key === 'pet_name') this.pushMem(P.facts, 'питомца зовут ' + U.cap(ans));
    else if (key === 'dream_job') this.pushMem(P.wants, 'стать ' + ans);
    else if (['hobby', 'superpower', 'dream_trip', 'pet', 'dream_pet', 'best_friend'].includes(key) && !longAns) this.pushMem(P.facts, ({ hobby: 'любит ', superpower: 'хочет суперсилу: ', dream_trip: 'мечтает поехать: ', pet: 'питомец: ', dream_pet: 'хочет питомца: ', best_friend: 'лучший друг: ' })[key] + ans);
    this.save();
    this.setTopic({ kind: 'fav', key });
    const acks = (c.acks && c.acks.length ? c.acks : ['{ans} — классно! Запомнил 😊', 'О, {ans}! Здорово 😊', '{ans}? Отличный выбор! Запомню 😊']);
    let ack = longAns ? Talk.reply(text, rnd, { lex: Lex.main(text) }).replace(/\s*[^.!?…]*\?\s*$/, '') || 'Как интересно! Спасибо, что рассказал 😊' : U.pick(acks, rnd);
    let ansShow = ans.length > 40 ? ans.slice(0, 39) + '…' : ans;
    if (['pet_name', 'best_friend'].includes(key)) ansShow = ansShow.split(' ').map(U.cap).join(' ');
    ack = ack.replace(/^\{ans\}/, U.cap(ansShow)).replace(/\{ans\}/g, ansShow);
    const h = !longAns && Lex.main(ans);
    const extra = h && rnd() < 0.6 ? ' ' + Lex.describe(h.entry) : '';
    const mine = BOT_FAVS[key] && key !== 'open' && key !== 'today' && rnd() < 0.5 ? ' ' + BOT_FAVS[key] : '';
    return this.say((ack + extra + mine).replace(/\s+/g, ' ').trim(), { src: 'talk', intent: 'answer', mood: 'happy', chips: ['Давай ещё поболтаем', 'Расскажи шутку'] });
  },
});

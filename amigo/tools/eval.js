#!/usr/bin/env node
// Проверка Амиго на фразах, которых он никогда не видел при обучении (data/eval.json, data/eval_free.json).
//   node tools/eval.js                     — проверить текущий мозг (src/ + data/model.json)
//   node tools/eval.js --src DIR --model F — проверить другую версию (например, старую)
//   node tools/eval.js --show 40           — показать больше ошибок
//   node tools/eval.js --eval data/test2.json --free data/test2_free.json — второй, совсем новый проверочный набор
'use strict';
const fs = require('fs'), path = require('path');
const { load, offlineBrain, readModel } = require('./load');

const ROOT = path.join(__dirname, '..');
const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i < 0 ? d : args[i + 1]; };
const src = arg('src', path.join(ROOT, 'src'));
const modelFile = arg('model', path.join(ROOT, 'data', 'model.json'));
const SHOW = +arg('show', 15);
const JSON_OUT = arg('json', null);

// ответы-тупики: Амиго честно не понял или ответил «научи меня»
const DEAD = /(не знаю, что на это ответить|такого я ещё не встречал|не понял ни буквы|какой-то шифр|прошёлся кот|но я не уверен|нажми «Научить»|Научишь меня|не знаю такого слова|новое для меня слово|Этого я пока не знаю|ответа я пока не знаю|я пока не силён|пока не слышал|я пока не умею|Этого я пока не умею)/i;

(async () => {
  const model = readModel(modelFile);
  const X = load(model, { src });
  const tags = new Set(model.tags);
  const E = JSON.parse(fs.readFileSync(arg('eval', path.join(ROOT, 'data', 'eval.json')), 'utf8'));
  const FREE = JSON.parse(fs.readFileSync(arg('free', path.join(ROOT, 'data', 'eval_free.json')), 'utf8'));
  // фразы, которые дословно есть в обучении, считаем отдельно
  const seen = new Set(X.Data.build(X.INTENTS, [], { expand: 5, augment: 0 }).examples.map(e => e.text));

  // 1) сама нейросеть: угадывает ли тему
  const net = X.MLP.fromJSON(model.net);
  let ok = 0, okOld = 0, nOld = 0, okUnseen = 0, nUnseen = 0, nKnown = 0;
  const conf = {};
  for (const e of E) {
    if (!tags.has(e.intent)) continue;
    nKnown++;
    const p = net.predict(X.Text.features(e.text, model.D));
    let a = 0; for (let c = 1; c < p.length; c++) if (p[c] > p[a]) a = c;
    const hit = model.tags[a] === e.intent;
    if (hit) ok++; else { (conf[e.intent] = conf[e.intent] || []).push(`${e.text} → ${model.tags[a]}`); }
    const unseen = !seen.has(X.Text.clean(e.text));
    if (unseen) { nUnseen++; if (hit) okUnseen++; }
  }
  // 2) весь мозг целиком: какой ответ получился
  const brain = offlineBrain(X, model);
  const ALIAS = { set_name: ['set_name', 'remember'], remember: ['remember'], knowledge: ['knowledge', 'word', 'bot_know'], calc: ['calc'], statement: ['statement', 'user_doing', 'word'],
    user_doing: ['user_doing', 'statement'], bot_know: ['bot_know', 'knowledge', 'word'], make_game: ['make_game'], user_likes: ['user_likes'], pets: ['pets', 'user_has'] };
  const fresh = () => {
    brain.ctx = null; brain.topic = null; brain.lastSpec = null; brain.lastAct = null; brain.settings.codexOn = false; brain.settings.voice = false;
    brain.profile = { name: '', facts: [], city: null, age: 0 }; if (brain.ensureProfile) brain.ensureProfile();
    brain.prevUserText = ''; brain.lastBotText = ''; brain.lastIntent = null; brain.history = []; brain.mainCls = null;
  };
  let routeOk = 0, dead = 0, n = 0;
  const routeFail = [], deadList = [];
  for (const e of E) {
    fresh();
    const a = await brain.reply(e.text);
    n++;
    const good = (ALIAS[e.intent] || [e.intent]).includes(a.intent);
    if (good) routeOk++; else routeFail.push(`[${e.intent}] ${e.text} → ${a.intent || '-'}: ${a.text.replace(/\n/g, ' ').slice(0, 90)}`);
    if (a.unsure || DEAD.test(a.text)) { dead++; deadList.push(`[${e.intent}] ${e.text} → ${a.text.replace(/\n/g, ' ').slice(0, 90)}`); }
  }
  // 3) свободная болтовня: сколько раз Амиго «упёрся в тупик»
  let fdead = 0; const byKind = {}, fdeadList = [], samples = [];
  for (const e of FREE) {
    fresh();
    const a = await brain.reply(e.text);
    const d = a.unsure || DEAD.test(a.text);
    byKind[e.kind] = byKind[e.kind] || { n: 0, dead: 0 }; byKind[e.kind].n++;
    if (d) { fdead++; byKind[e.kind].dead++; fdeadList.push(`[${e.kind}] ${e.text} → ${a.text.replace(/\n/g, ' ').slice(0, 100)}`); }
    samples.push({ kind: e.kind, text: e.text, reply: a.text, intent: a.intent, src: a.src, dead: d });
  }
  const pct = (a, b) => b ? (100 * a / b).toFixed(1) + '%' : '—';
  console.log(`Модель: ${model.tags.length} тем, сеть ${model.D}×${model.H}, обучена на ${model.examples} примерах`);
  console.log(`Нейросеть угадывает тему:              ${pct(ok, nKnown)}  (${ok}/${nKnown}; тем, которых сеть не знает, в наборе: ${E.length - nKnown})`);
  console.log(`  на фразах, которых не было в обучении: ${pct(okUnseen, nUnseen)}  (${okUnseen}/${nUnseen})`);
  console.log(`Весь мозг выбрал правильную тему:      ${pct(routeOk, n)}  (${routeOk}/${n})`);
  console.log(`Тупиковых ответов («не понял/научи»):  ${pct(dead, n)} на темах, ${pct(fdead, FREE.length)} в свободной болтовне`);
  for (const k of Object.keys(byKind)) console.log(`   ${k.padEnd(10)} тупиков ${pct(byKind[k].dead, byKind[k].n)} (${byKind[k].dead}/${byKind[k].n})`);
  if (SHOW) {
    console.log('\nПримеры ошибок выбора темы:'); routeFail.slice(0, SHOW).forEach(s => console.log('  ' + s));
    console.log('\nТупики в свободной болтовне:'); fdeadList.slice(0, SHOW).forEach(s => console.log('  ' + s));
  }
  if (JSON_OUT) fs.writeFileSync(JSON_OUT, JSON.stringify({ net: ok / nKnown, netUnseen: okUnseen / nUnseen, route: routeOk / n, dead: dead / n, freeDead: fdead / FREE.length, byKind, routeFail, fdeadList, samples }, null, 1));
})().catch(e => { console.error(e); process.exit(1); });

#!/usr/bin/env node
// Сборка Амиго: обучает нейросеть на примерах из src/ и собирает один файл index.html,
// который работает без интернета (его можно открыть в браузере или установить на телефон).
//
//   node tools/build.js                 — обучить заново и собрать index.html
//   node tools/build.js --no-train      — собрать index.html из уже обученной data/model.json
//   node tools/build.js --holdout 0.05  — отложить 5% фраз для проверки (для экспериментов)
//   node tools/build.js --H 128 --D 8192 --epochs 24
'use strict';
const fs = require('fs'), path = require('path');
const { load, readModel, SRC } = require('./load');

const ROOT = path.join(__dirname, '..');
const args = process.argv.slice(2);
const arg = (name, def) => { const i = args.indexOf('--' + name); return i < 0 ? def : (args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : true); };

const OPT = {
  D: +arg('D', 8192), H: +arg('H', 96), epochs: +arg('epochs', 16),
  expand: +arg('expand', 5), augment: +arg('augment', 2), holdout: +arg('holdout', 0),
  lr: +arg('lr', 0.01), batch: +arg('batch', 16), seed: +arg('seed', 7), dropout: +arg('dropout', 0.2), smooth: +arg('smooth', 0.1),
  train: !args.includes('--no-train'), out: arg('out', path.join(ROOT, 'index.html')),
  model: arg('model', path.join(ROOT, 'data', 'model.json')),
};

function log(...a) { console.log(...a); }

async function train() {
  const X = load(null);
  const { U, Text, MLP, INTENTS, Data } = X;
  // отложенные фразы для проверки (по желанию)
  const rnd = U.rng(OPT.seed + 1000);
  let intents = INTENTS, held = [];
  if (OPT.holdout > 0) {
    intents = INTENTS.map(it => {
      if (it.p.length < 8) return it;
      const keep = [];
      for (const p of it.p) { if (p.indexOf('{') < 0 && rnd() < OPT.holdout) held.push({ text: Text.clean(p), tag: it.tag }); else keep.push(p); }
      return Object.assign({}, it, { p: keep });
    });
  }
  const t0 = Date.now();
  const ds = Data.build(intents, [], { expand: OPT.expand, augment: OPT.augment });
  log(`Тем: ${ds.tags.length}, примеров: ${ds.examples.length} (фраз в данных: ${INTENTS.reduce((s, i) => s + i.p.length, 0)})`);
  const ex = Data.featurize(ds.examples, OPT.D);
  const net = new MLP(OPT.D, OPT.H, ds.tags.length, 1);
  log(`Сеть: ${OPT.D} входов → ${OPT.H} скрытых → ${ds.tags.length} выходов, параметров: ${net.params}`);
  const history = await net.train(ex, {
    epochs: OPT.epochs, batch: OPT.batch, lr: OPT.lr, smooth: OPT.smooth, dropout: OPT.dropout, decay: 0, seed: OPT.seed,
    onEpoch: r => log(`  эпоха ${String(r.epoch).padStart(2)}: ошибка ${r.loss.toFixed(4)}, точность ${(r.acc * 100).toFixed(2)}%  (${((Date.now() - t0) / 1000).toFixed(0)} с)`),
  });
  // проверка на отложенных фразах
  let val = null;
  if (held.length) {
    let ok = 0;
    for (const h of held) { const p = net.predict(Text.features(h.text, OPT.D)); let a = 0; for (let c = 1; c < p.length; c++) if (p[c] > p[a]) a = c; if (ds.tags[a] === h.tag) ok++; }
    val = { acc: +(ok / held.length).toFixed(4), n: held.length };
    log(`Проверка на отложенных фразах: ${(val.acc * 100).toFixed(2)}% из ${held.length}`);
  }
  // проверка на независимом наборе data/eval.json (если он есть)
  const evalFile = path.join(ROOT, 'data', 'eval.json');
  if (fs.existsSync(evalFile)) {
    const E = JSON.parse(fs.readFileSync(evalFile, 'utf8')).filter(e => e.intent && ds.tags.includes(e.intent));
    let ok = 0;
    for (const e of E) { const p = net.predict(Text.features(e.text, OPT.D)); let a = 0; for (let c = 1; c < p.length; c++) if (p[c] > p[a]) a = c; if (ds.tags[a] === e.intent) ok++; }
    if (E.length) { const ev = { acc: +(ok / E.length).toFixed(4), n: E.length }; log(`Независимая проверка (data/eval.json): ${(ev.acc * 100).toFixed(2)}% из ${E.length}`); if (!val) val = ev; }
  }
  const codex = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'codex_model.json'), 'utf8'));
  const model = {
    v: 2, D: OPT.D, H: OPT.H, epochs: OPT.epochs, tags: ds.tags, examples: ds.examples.length, params: net.params,
    history: history.map(h => [+h.loss.toFixed(4), +h.acc.toFixed(4)]), val: val || { acc: 0, n: 0 }, net: net.toJSON(), codex,
  };
  log(`Обучение заняло ${((Date.now() - t0) / 1000).toFixed(1)} с`);
  return model;
}

function assemble(model) {
  const head = fs.readFileSync(path.join(SRC, '_head.html'), 'utf8').replace(/\s+$/, '');
  const mods = fs.readdirSync(SRC).filter(f => /\.js$/.test(f)).sort();
  let js = '/* ===== обученная модель (создаётся tools/build.js) ===== */\nconst AMIGO_MODEL = ' + JSON.stringify(model) + ';\n\n';
  for (const f of mods) js += fs.readFileSync(path.join(SRC, f), 'utf8').replace(/\s+$/, '') + '\n\n';
  if (/<\/script/i.test(js.replace(/<\\\/script/g, ''))) throw new Error('В коде модулей встретился </script> — экранируйте его как <\\/script>');
  return head + '\n<script>\n' + js + '</script>\n</body>\n</html>\n';
}

(async () => {
  let model;
  if (OPT.train) {
    model = await train();
    fs.writeFileSync(OPT.model, JSON.stringify(model));
    log(`Модель сохранена: ${path.relative(ROOT, OPT.model)} (${(fs.statSync(OPT.model).size / 1024).toFixed(0)} КБ)`);
  } else {
    model = readModel(OPT.model);
    // проверим, что модель подходит к данным
    const X = load(null);
    const tags = X.Data.build(X.INTENTS, [], { expand: 1, augment: 0 }).tags;
    if (tags.join() !== model.tags.join()) { console.error('Модель не совпадает с темами в src/03_intents.js — запустите сборку с обучением.'); process.exit(1); }
  }
  const html = assemble(model);
  fs.writeFileSync(OPT.out, html);
  // новая версия для офлайн-кэша: телефон поймёт, что пора обновить Амиго
  const swFile = path.join(ROOT, 'sw.js');
  if (OPT.out === path.join(ROOT, 'index.html') && fs.existsSync(swFile)) {
    const ver = (fs.readFileSync(path.join(SRC, '00_util.js'), 'utf8').match(/AMIGO_VERSION = '([^']+)'/) || [])[1] || 'dev';
    const hash = require('crypto').createHash('sha1').update(html).digest('hex').slice(0, 8);
    fs.writeFileSync(swFile, fs.readFileSync(swFile, 'utf8').replace(/const VERSION = '[^']*';/, `const VERSION = 'amigo-${ver}-${hash}';`));
  }
  log(`Готово: ${path.relative(ROOT, OPT.out)} (${(html.length / 1024).toFixed(0)} КБ)`);
})().catch(e => { console.error(e); process.exit(1); });

// Загружает «мозг» Амиго (модули без интерфейса) в Node, чтобы обучать сеть и проверять ответы без браузера.
'use strict';
const fs = require('fs'), vm = require('vm'), path = require('path');

const SRC = path.join(__dirname, '..', 'src');
// модули, которым не нужен DOM: всё до интерфейса (08_*) и запуска (09_*)
function brainFiles(src = SRC) {
  return fs.readdirSync(src).filter(f => /^0[0-7].*\.js$/.test(f)).sort();
}

// model — объект модели (или null, тогда подставляется пустышка, чтобы можно было обучать с нуля)
function load(model, opts = {}) {
  const src = opts.src || SRC;
  const code = brainFiles(src).map(f => fs.readFileSync(path.join(src, f), 'utf8')).join('\n;\n') +
    '\n;globalThis.__x = { U, Text, MLP, INTENTS, FILL, Data, Skills, Brain, Online, KB, DICT, Codex,' +
    ' JOKES, FACTS, RIDDLES, QUIZ, STORIES, POEMS, SONGS, RECS, ADVICE, MOTIVATION,' +
    ' LEX: typeof LEX !== "undefined" ? LEX : null, Lex: typeof Lex !== "undefined" ? Lex : null, Talk: typeof Talk !== "undefined" ? Talk : null, QA: typeof QA !== "undefined" ? QA : null, Spell: typeof Spell !== "undefined" ? Spell : null };';
  const ctx = {
    console, setTimeout, clearTimeout, Buffer, TextEncoder, TextDecoder, performance, AbortController, URL,
    fetch: async () => { throw new Error('offline'); },
    navigator: { language: 'ru' },
    AMIGO_MODEL: model,
  };
  ctx.globalThis = ctx; ctx.window = undefined; ctx.self = ctx;
  vm.createContext(ctx);
  vm.runInContext('var AMIGO_MODEL = globalThis.AMIGO_MODEL;\n' + code, ctx, { filename: 'amigo-brain.js' });
  return ctx.__x;
}

// мозг без интернета: Википедия и погода «не отвечают»
function offlineBrain(X, model, extra = {}) {
  const online = Object.assign({}, X.Online, {
    wiki: async () => null, geocode: async () => null, forecast: async () => { throw new Error('offline'); },
  });
  const brain = new X.Brain(model, Object.assign({ online, rnd: X.U.rng(123) }, extra));
  brain.settings.online = false;
  brain.fastThink = true;
  return brain;
}

function readModel(file) {
  const s = fs.readFileSync(file, 'utf8');
  return JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1));
}

module.exports = { load, offlineBrain, readModel, SRC, brainFiles };

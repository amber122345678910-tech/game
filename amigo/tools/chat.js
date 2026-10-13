#!/usr/bin/env node
// Поболтать с Амиго в терминале или прогнать сценарий диалога.
//   node tools/chat.js                         — интерактивно
//   node tools/chat.js "привет" "как дела?"    — несколько реплик подряд (один диалог)
//   node tools/chat.js --file dialogs.txt      — диалоги из файла (пустая строка — новый диалог)
'use strict';
const fs = require('fs'), path = require('path'), readline = require('readline');
const { load, offlineBrain, readModel } = require('./load');
const ROOT = path.join(__dirname, '..');
const args = process.argv.slice(2);
const mi = args.indexOf('--model'); const modelFile = mi >= 0 ? args.splice(mi, 2)[1] : path.join(ROOT, 'data', 'model.json');
const model = readModel(modelFile);
const X = load(model);
const newBrain = () => offlineBrain(X, model);
const show = (u, a) => console.log(`👤 ${u}\n🤖 ${a.text.replace(/\n/g, '\n   ')}   [${a.src || '-'}/${a.intent || '-'}${a.conf != null ? ' ' + a.conf.toFixed(2) : ''}]${a.chips ? '\n   ⟨' + a.chips.join(' | ') + '⟩' : ''}`);
(async () => {
  const fi = args.indexOf('--file');
  if (fi >= 0) {
    const blocks = fs.readFileSync(args[fi + 1], 'utf8').split(/\n\s*\n/);
    for (const b of blocks) { const brain = newBrain(); for (const line of b.split('\n').map(s => s.trim()).filter(Boolean)) show(line, await brain.reply(line)); console.log('—'.repeat(40)); }
    return;
  }
  const brain = newBrain();
  if (args.length) { for (const a of args) show(a, await brain.reply(a)); return; }
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: '> ' });
  rl.prompt();
  for await (const line of rl) { if (line.trim()) show(line, await brain.reply(line)); rl.prompt(); }
})();

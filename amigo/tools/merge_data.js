#!/usr/bin/env node
// Собирает новые обучающие данные (сгенерированные JSON-файлы) в модули src/03c_more.js, src/03e_lexicon.js, src/03f_content_more.js.
//   node tools/merge_data.js <папка с json> [<файл с правками проверяющих>]
// Файлы в папке: para_*.json, new_*.json, lex_*.json, bot_can.json, jokes.json, facts.json, riddles.json, quiz.json, kb.json, misc.json, starters.json.
// Правки (fixes.json): { "lex_1.json": [{word, desc|null, emoji|null}], "facts.json": {remove:[{index}], fix:[{index, replacement}]}, ... }
'use strict';
const fs = require('fs'), path = require('path');
const { load } = require('./load');

const ROOT = path.join(__dirname, '..'), SRC = path.join(ROOT, 'src');
const dir = process.argv[2];
const fixes = process.argv[3] && fs.existsSync(process.argv[3]) ? JSON.parse(fs.readFileSync(process.argv[3], 'utf8')) : {};
if (!dir) { console.error('укажите папку с данными'); process.exit(1); }
const rd = f => { const p = path.join(dir, f); return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null; };
const files = re => fs.readdirSync(dir).filter(f => re.test(f)).sort();

// модули 03c/03e/03f сами себя не должны учитывать: грузим мозг без них
const GEN = ['03c_more.js', '03e_lexicon.js', '03f_content_more.js', '03g_qa.js'];
for (const f of GEN) { const p = path.join(SRC, f); if (fs.existsSync(p)) fs.renameSync(p, p + '.off'); }
let X;
try { X = load(null); } finally { for (const f of GEN) { const p = path.join(SRC, f); if (fs.existsSync(p + '.off')) fs.renameSync(p + '.off', p); } }
const { Text, INTENTS } = X;
const clean = s => Text.clean(String(s).replace(/\{(\w+)\}/g, 'PH$1PH')).replace(/ph(\w+?)ph/g, '{$1}');
const okPhrase = p => typeof p === 'string' && p.trim().length > 0 && p.length <= 120 && !/[<>]/.test(p);
const normPhrase = p => String(p).toLowerCase().replace(/ё/g, 'е').replace(/[.!?…,;:«»"“”()]+/g, ' ').replace(/\s+/g, ' ').trim();

// ---------- 1. темы ----------
const existing = new Map(INTENTS.map(i => [i.tag, i]));
const more = {};       // tag → новые фразы для старых тем
const neu = new Map(); // tag → { p, r }
for (const f of files(/^para_\d+\.json$/)) for (const [tag, ps] of Object.entries(rd(f))) { if (!existing.has(tag)) { console.warn('неизвестная тема', tag, 'в', f); continue; } (more[tag] = more[tag] || []).push(...ps.filter(okPhrase).map(normPhrase)); }
for (const f of files(/^new_\d+\.json$/)) for (const [tag, v] of Object.entries(rd(f))) {
  const cur = neu.get(tag) || { p: [], r: [] };
  cur.p.push(...(v.p || []).filter(okPhrase).map(normPhrase));
  if (v.r && v.r.length) cur.r = v.r;
  neu.set(tag, cur);
}
const SPEC = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools', 'new_intents.json'), 'utf8'));
const specBy = new Map(SPEC.map(s => [s.tag, s]));
// bot_likes есть и в старых темах: новые фразы идут в «more»
if (neu.has('bot_likes')) { (more.bot_likes = more.bot_likes || []).push(...neu.get('bot_likes').p); neu.delete('bot_likes'); }
for (const s of SPEC) if (s.tag !== 'bot_likes' && !neu.has(s.tag)) console.warn('нет данных для новой темы', s.tag);

// перенос старых фраз в новые, более точные темы
const MOVE = {
  user_doing: { statement: ['я играю в футбол', 'я читаю книгу', 'я делаю уроки', 'я сижу дома', 'я играю в роблокс', 'я тут'] },
  user_likes: { statement: ['я люблю рисовать'], pets: ['я люблю котиков', 'я люблю собак'] },
  user_tired: { user_bad: ['я устал', 'я устала'] },
  user_angry: { user_bad: ['я злюсь', 'все бесит', 'меня все бесит'] },
  user_lonely: { user_bad: ['мне одиноко'] },
};
const moved = {};
for (const [to, from] of Object.entries(MOVE)) for (const [tag, ps] of Object.entries(from)) {
  const it = existing.get(tag); if (!it) continue;
  for (const p of ps) { const i = it.p.indexOf(p); if (i >= 0) { it.p.splice(i, 1); (moved[tag] = moved[tag] || []).push(p); (neu.get(to) || { p: [] }).p.unshift(p); } }
}

// дубли и конфликты: одинаковая фраза в двух темах сбивает сеть — оставляем её только в старой теме, иначе убираем
const owner = new Map(); // чистая фраза → тема
for (const it of INTENTS) for (const p of it.p) owner.set(clean(p), it.tag);
const conflicts = [];
const take = (tag, list) => {
  const out = [], seen = new Set();
  for (const p of list) {
    const c = clean(p); if (!c || seen.has(c)) continue;
    const o = owner.get(c);
    if (o && o !== tag) { conflicts.push(`${p} (${tag} ↔ ${o})`); continue; }
    if (o === tag) continue; // уже есть
    seen.add(c); out.push(p);
  }
  return out;
};
// сначала собираем владельцев новых фраз, чтобы найти конфликты между новыми темами
const pending = [];
for (const [tag, ps] of Object.entries(more)) pending.push([tag, ps]);
for (const [tag, v] of neu) pending.push([tag, v.p]);
const newOwner = new Map(), dropped = new Set();
for (const [tag, ps] of pending) for (const p of ps) { const c = clean(p); const o = newOwner.get(c); if (o && o !== tag) dropped.add(c); else newOwner.set(c, tag); }
const filt = (tag, ps) => take(tag, ps.filter(p => !dropped.has(clean(p))));
const MORE = {}; let addedOld = 0;
for (const [tag, ps] of Object.entries(more)) { MORE[tag] = filt(tag, ps); addedOld += MORE[tag].length; }
const NEW = []; let addedNew = 0;
for (const [tag, v] of neu) {
  const s = specBy.get(tag) || {};
  const p = filt(tag, v.p);
  addedNew += p.length;
  const it = { tag, t: s.title || tag, p };
  if (s.kind === 'r' && v.r && v.r.length) it.r = v.r; else it.act = tag;
  NEW.push(it);
}
console.log(`Фраз: старые темы +${addedOld}, новые темы ${NEW.length} шт. с ${addedNew} фразами; конфликтов убрано: ${conflicts.length + dropped.size}`);
fs.writeFileSync(path.join(dir, '_conflicts.txt'), conflicts.join('\n') + '\n' + [...dropped].join('\n'));

const js = s => JSON.stringify(s);
let out = `/* ===== 03c_more.js ===== */
// Дополнительные обучающие фразы (в 5+ раз больше, чем было) и новые темы для разговора.
// Создаётся tools/merge_data.js. Фразы для старых тем добавляются к INTENTS, новые темы — в конец списка.
const INTENTS_MORE = {
${Object.entries(MORE).map(([t, ps]) => `  ${t}: ${js(ps)},`).join('\n')}
};
const INTENTS_NEW = [
${NEW.map(it => '  ' + js(it) + ',').join('\n')}
];
(function mergeIntents() {
  const by = new Map(INTENTS.map(i => [i.tag, i]));
  const MOVED = ${js(moved)};
  for (const [tag, ps] of Object.entries(MOVED)) { const it = by.get(tag); if (it) it.p = it.p.filter(p => !ps.includes(p)); }
  for (const [tag, ps] of Object.entries(INTENTS_MORE)) { const it = by.get(tag); if (it) it.p = it.p.concat(ps); }
  for (const it of INTENTS_NEW) { if (!by.has(it.tag)) { INTENTS.push(it); by.set(it.tag, it); } }
  // эти старые темы теперь отвечают через разговорный модуль (с памятью и словарём)
  for (const tag of ['bot_likes', 'statement', 'pets']) { const it = by.get(tag); if (it) it.act = tag; }
})();
`;
fs.writeFileSync(path.join(SRC, '03c_more.js'), out);

// ---------- 2. словарь ----------
const LEX = {}; let nLex = 0, nFix = 0, nDel = 0;
for (const f of files(/^lex_\d+\.json$/)) {
  const data = rd(f), fx = new Map((fixes[f] || []).map(x => [String(x.word).toLowerCase(), x]));
  for (const [cat, list] of Object.entries(data)) {
    const seen = new Set();
    LEX[cat] = [];
    for (const e of list) {
      if (!Array.isArray(e) || e.length < 3) continue;
      let [w, em, d, al] = e; w = String(w).toLowerCase().trim();
      if (!w || seen.has(w)) continue;
      const x = fx.get(w);
      if (x) { if (x.desc === null) { nDel++; continue; } if (x.desc) { d = x.desc; nFix++; } if (x.emoji) em = x.emoji; }
      d = String(d).trim().replace(/\.$/, '');
      if (d.length < 8) continue;
      seen.add(w);
      const row = [w, em || '💡', d]; const als = (al || []).map(a => String(a).toLowerCase().trim()).filter(a => a && a !== w);
      if (als.length) row.push(als);
      LEX[cat].push(row); nLex++;
    }
  }
}
let can = rd('bot_can.json') || [];
const canFix = new Map((fixes['bot_can.json'] || []).map(x => [String(x.word).toLowerCase(), x]));
can = can.filter(c => Array.isArray(c) && c.length >= 3).map(([v, k, r]) => { const x = canFix.get(String(v).toLowerCase()); if (x && x.desc === null) return null; return [String(v).toLowerCase(), k, x && x.desc ? x.desc : r]; }).filter(Boolean);
console.log(`Словарь: ${nLex} слов (исправлено ${nFix}, убрано ${nDel}); ответов «умеешь ли»: ${can.length}`);
out = `/* ===== 03e_lexicon.js ===== */
// Словарь Амиго: слово → эмодзи, описание, другие формы. И ответы на «ты умеешь …?». Создаётся tools/merge_data.js.
const LEX_DATA = {
${Object.entries(LEX).map(([c, l]) => `  ${c}: [\n${l.map(r => '    ' + js(r) + ',').join('\n')}\n  ],`).join('\n')}
};
const BOT_CAN = [
${can.map(r => '  ' + js(r) + ',').join('\n')}
];
`;
fs.writeFileSync(path.join(SRC, '03e_lexicon.js'), out);

// ---------- 3. контент ----------
function applyFix(name, arr, sub) {
  const f = fixes[name]; if (!f || !Array.isArray(arr)) return arr;
  const tag = s => sub ? new RegExp('\\[' + sub + '\\]').test(s || '') : !/^\[\w+\]/.test(s || '');
  const rm = new Set((f.remove || []).filter(x => tag(x.why)).map(x => x.index));
  const fx = new Map((f.fix || []).filter(x => tag(x.why)).map(x => [x.index, x.replacement]));
  return arr.map((v, i) => rm.has(i) ? null : fx.has(i) ? fx.get(i) : v).filter(v => v != null);
}
const uniq = (arr, key = x => x) => { const s = new Set(); return arr.filter(x => { const k = key(x); if (s.has(k)) return false; s.add(k); return true; }); };
const isStr = x => typeof x === 'string' && x.trim();
const jokes = uniq(applyFix('jokes.json', rd('jokes.json') || []).filter(isStr));
const facts = uniq(applyFix('facts.json', rd('facts.json') || []).filter(isStr));
const riddles = applyFix('riddles.json', rd('riddles.json') || []).filter(r => r && r.q && Array.isArray(r.a) && r.a.length).map(r => ({ q: r.q, a: r.a.map(a => String(a).toLowerCase()) }));
const quiz = applyFix('quiz.json', rd('quiz.json') || []).filter(q => q && q.q && Array.isArray(q.o) && q.o.length === 3 && [0, 1, 2].includes(q.c));
const kbOld = new Set(X.KB.flatMap(e => e.a.map(a => Text.clean(a))));
const kb = applyFix('kb.json', rd('kb.json') || []).filter(e => e && Array.isArray(e.a) && e.a.length && e.s && !e.a.some(a => kbOld.has(Text.clean(a)))).map(e => ({ a: e.a.map(a => String(a).toLowerCase()), s: e.s }));
const misc = rd('misc.json') || {};
const M = k => uniq(applyFix('misc.json', misc[k] || [], k).filter(isStr));
const recs = misc.recs || {};
const st = rd('starters.json') || {};
const starters = applyFix('starters.json', st.starters || [], 'starters').filter(s => s && s.q && s.key && Array.isArray(s.acks) && s.acks.length);
const askBack = st.ask_back || {};
console.log(`Контент: шуток +${jokes.length}, фактов +${facts.length}, загадок +${riddles.length}, вопросов викторины +${quiz.length}, статей +${kb.length}, советов +${M('advice').length}, мотивации +${M('motivation').length}, скороговорок ${M('tongue_twisters').length}, сказок +${M('stories').length}, стихов +${M('poems').length}, песен +${M('songs').length}, вопросов-заводил +${starters.length}`);
const pushTo = (name, arr) => arr.length ? `${name}.push(\n${arr.map(x => '  ' + js(x) + ',').join('\n')}\n);\n` : '';
out = `/* ===== 03f_content_more.js ===== */
// Больше шуток, фактов, загадок, вопросов викторины, статей мини-энциклопедии, сказок, стихов и скороговорок.
// Создаётся tools/merge_data.js; всё проверено отдельным «редактором» на правдивость и уместность для детей.
${pushTo('JOKES', jokes)}${pushTo('FACTS', facts)}${pushTo('RIDDLES', riddles)}${pushTo('QUIZ', quiz)}${pushTo('KB', kb)}${pushTo('ADVICE', M('advice'))}${pushTo('MOTIVATION', M('motivation'))}${pushTo('STORIES', M('stories'))}${pushTo('POEMS', M('poems'))}${pushTo('SONGS', M('songs'))}${Object.entries(recs).filter(([k, v]) => X.RECS[k] && Array.isArray(v)).map(([k, v]) => pushTo(`RECS.${k}`, uniq(v.filter(isStr)).filter(x => !X.RECS[k].includes(x)))).join('')}const TWISTERS = ${js(M('tongue_twisters'))};
${pushTo('STARTERS', starters)}for (const [k, v] of Object.entries(${js(askBack)})) if (!BOT_FAVS[k]) BOT_FAVS[k] = v;
`;
fs.writeFileSync(path.join(SRC, '03f_content_more.js'), out);

// ---------- 4. ответы на частые вопросы ----------
const qa = [];
for (const f of files(/^qa_\w+\.json$/)) {
  const list = applyFix(f, rd(f) || []);
  for (const x of list) if (x && Array.isArray(x.q) && x.q.length && typeof x.a === 'string' && x.a.trim()) qa.push({ q: uniq(x.q.map(q => String(q).trim()).filter(Boolean)), a: x.a.trim() });
}
console.log(`Ответов на частые вопросы: ${qa.length}`);
out = `/* ===== 03g_qa.js ===== */
// Частые детские вопросы и короткие проверенные ответы (работают без интернета). Создаётся tools/merge_data.js.
const QA_DATA = [
${qa.map(x => '  ' + js(x) + ',').join('\n')}
];
`;
fs.writeFileSync(path.join(SRC, '03g_qa.js'), out);
console.log('Готово: src/03c_more.js, src/03e_lexicon.js, src/03f_content_more.js, src/03g_qa.js');

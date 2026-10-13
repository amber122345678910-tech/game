#!/usr/bin/env node
// Проверка готового index.html в настоящем браузере (Chromium через Playwright):
// страница открывается без ошибок, Амиго отвечает, игры запускаются, офлайн-кэш работает.
//   node tools/smoke.js            — проверить amigo/index.html (через локальный сервер)
//   node tools/smoke.js --shots    — ещё и сохранить скриншоты (телефон и компьютер)
'use strict';
const path = require('path'), http = require('http'), fs = require('fs');
let pw;
try { pw = require('playwright'); } catch (e) { pw = require('/opt/node-tools/node_modules/playwright'); }
const ROOT = path.join(__dirname, '..');
const SHOTS = process.argv.includes('--shots') ? (process.argv[process.argv.indexOf('--shots') + 1] || path.join(ROOT, 'data', 'shots')) : null;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
  const f = path.join(ROOT, p);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nope'); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const browser = await pw.chromium.launch({ executablePath: fs.existsSync('/opt/pw-browsers/chromium') ? undefined : undefined });
  const fails = [];
  const check = (ok, msg) => { console.log((ok ? '✅ ' : '❌ ') + msg); if (!ok) fails.push(msg); };
  try {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'ru-RU' });
    // без интернета: шрифты и внешние запросы блокируем
    await ctx.route(/^https?:\/\/(?!127\.0\.0\.1)/, r => r.abort());
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push('pageerror: ' + e.message));
    page.on('console', m => { if (m.type() === 'error' && !/net::ERR|Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    const t0 = Date.now();
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForSelector('#log .msg', { timeout: 15000 });
    check(true, `страница открылась за ${Date.now() - t0} мс`);
    const ask = async (text) => {
      const n = await page.locator('#log .msg').count();
      await page.fill('#input', text);
      await page.press('#input', 'Enter');
      await page.waitForFunction(k => document.querySelectorAll('#log .msg').length >= k + 2 && !document.querySelector('#log .typing'), n, { timeout: 20000 });
      return (await page.locator('#log .msg').last().innerText()).replace(/\s+/g, ' ').trim();
    };
    const convo = [
      ['меня зовут Саша', /Саша/],
      ['привет как дела', /./],
      ['кошка', /Кошка —/],
      ['я люблю пиццу', /пицц/i],
      ['ты умеешь рисовать?', /./],
      ['сколько будет 17 * 23', /391/],
      ['расскажи шутку', /./],
      ['что ты обо мне знаешь', /Саша/],
    ];
    for (const [q, re] of convo) { const a = await ask(q); check(re.test(a) && !/не знаю, что на это ответить|такого я ещё не встречал/.test(a), `«${q}» → ${a.slice(0, 90)}`); }
    if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, 'phone-chat.png') }); }
    // игра в чате
    const g = await ask('змейка');
    check(/Змейка/.test(g) && await page.locator('#log canvas').count() > 0, 'встроенная игра «Змейка» запустилась');
    // настройки и кнопка установки
    await page.click('#btnSettings');
    check(await page.locator('#appGroup').isVisible(), 'в настройках есть раздел «Приложение»');
    const ver = await page.locator('#appVersion').innerText();
    check(/Версия 2/.test(ver), 'версия: ' + ver);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'phone-settings.png') });
    await page.click('#btnSetClose');
    // офлайн-кэш (service worker)
    const sw = await page.evaluate(async () => { if (!('serviceWorker' in navigator)) return 'нет'; const r = await navigator.serviceWorker.ready; return r && r.active ? 'активен' : 'нет'; });
    check(sw === 'активен', 'service worker: ' + sw);
    const manifest = await page.evaluate(async () => { const l = document.querySelector('link[rel=manifest]'); const j = await (await fetch(l.href)).json(); return j.name + ' / ' + j.icons.length + ' значка'; });
    check(/Амиго/.test(manifest), 'манифест: ' + manifest);
    // работает ли после перезагрузки без сервера (из кэша)
    await page.reload({ waitUntil: 'load' });
    await page.waitForSelector('#log .msg', { timeout: 15000 });
    const restored = await page.locator('#log .msg').count();
    check(restored > 3, `после перезагрузки переписка на месте (${restored} сообщений)`);
    server.close();
    await page.reload({ waitUntil: 'load' }).catch(() => {});
    const offline = await page.locator('#app').count().catch(() => 0);
    check(offline > 0, 'без сервера Амиго открылся из офлайн-кэша');
    check(errors.length === 0, 'ошибок в консоли нет' + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''));
    if (SHOTS) {
      const desk = await browser.newPage({ viewport: { width: 1280, height: 800 } });
      await desk.route(/^https?:\/\/(?!127\.0\.0\.1)/, r => r.abort());
      await new Promise(r => server.listen(server.address() ? 0 : 0, '127.0.0.1', r));
      await desk.goto(`http://127.0.0.1:${server.address().port}/`, { waitUntil: 'load' }).catch(() => {});
      await desk.waitForTimeout(800);
      await desk.screenshot({ path: path.join(SHOTS, 'desktop.png') });
    }
  } finally {
    await browser.close();
    server.close();
  }
  console.log(fails.length ? `\nПровалено проверок: ${fails.length}` : '\nВсе проверки пройдены 🎉');
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });

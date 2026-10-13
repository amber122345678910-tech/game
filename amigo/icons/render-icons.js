#!/usr/bin/env node
// Рисует PNG-иконки Амиго из icon.svg и maskable.svg (через Chromium из Playwright).
//
//   NODE_PATH=$(npm root -g) node icons/render-icons.js
//
// Пишет: icons/icon-192.png, icon-512.png, maskable-512.png, apple-touch-icon.png, favicon-32.png
// и старые (до Android 8) значки приложения: android/app/src/main/res/mipmap-*/ic_launcher(_round).png.
// Значок для Android 8+ — векторный (res/drawable/ic_launcher_foreground.xml), его рисовать не нужно.
'use strict';
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');

const ICONS = __dirname;
const RES = path.join(ICONS, '..', 'android', 'app', 'src', 'main', 'res');
const icon = fs.readFileSync(path.join(ICONS, 'icon.svg'), 'utf8');
const maskable = fs.readFileSync(path.join(ICONS, 'maskable.svg'), 'utf8');
// iOS сам скругляет углы и не любит прозрачность: фон на весь квадрат, лицо как в icon.svg.
const apple = icon.replace(/ rx="112"/, '');
// Круглый значок для старых лаунчеров: круглый фон, лицо чуть меньше.
const round = icon
  .replace(/<rect width="512" height="512" rx="112"([^>]*)\/>/, '<circle cx="256" cy="256" r="256"$1/>')
  .replace('translate(256 262) scale(4.35)', 'translate(256 258) scale(4.05)');

const jobs = [
  [icon, 192, path.join(ICONS, 'icon-192.png')],
  [icon, 512, path.join(ICONS, 'icon-512.png')],
  [maskable, 512, path.join(ICONS, 'maskable-512.png')],
  [apple, 180, path.join(ICONS, 'apple-touch-icon.png')],
  [icon, 32, path.join(ICONS, 'favicon-32.png')],
];
const DENSITIES = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
for (const [d, px] of Object.entries(DENSITIES)) {
  jobs.push([icon, px, path.join(RES, 'mipmap-' + d, 'ic_launcher.png')]);
  jobs.push([round, px, path.join(RES, 'mipmap-' + d, 'ic_launcher_round.png')]);
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const [svg, size, out] of jobs) {
    await page.setViewportSize({ width: size, height: size });
    const sized = svg.replace(/width="512" height="512"/, `width="${size}" height="${size}"`);
    await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${sized}</body></html>`);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
    console.log(path.relative(path.join(ICONS, '..'), out), size + 'px');
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });

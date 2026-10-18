// node render.mjs scene.json out_prefix [cameras.json] [w h]
// cameras.json: [{name, pos:[x,y,z], look:[x,y,z], fov}]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { chromium } from 'playwright-core';

const here = path.dirname(new URL(import.meta.url).pathname);
const [sceneFile, outPrefix, camFile, w = '1280', h = '720'] = process.argv.slice(2);
const sceneAbs = path.resolve(sceneFile);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let file = url.pathname === '/scene.json' ? (url.searchParams.get('f') || sceneAbs) : path.join(here, decodeURIComponent(url.pathname));
  if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const base = JSON.parse(fs.readFileSync(sceneAbs, 'utf8'));
const cams = camFile ? JSON.parse(fs.readFileSync(camFile, 'utf8')) : [{ name: 'default', ...(base.camera || {}) }];

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: +w, height: +h } });
page.on('console', m => { if (m.type() === 'error') console.error('page:', m.text()); });
page.on('pageerror', e => console.error('pageerror:', e.message));
// временная папка вне дерева проекта (несколько рендеров могут идти параллельно)
const tmpDir = fs.mkdtempSync(path.join(process.env.PREVIEW_TMP || os.tmpdir(), 'lc-preview-'));
for (const cam of cams) {
  const sc = { ...base, camera: cam.pos ? cam : base.camera };
  if (cam.clockTime !== undefined) sc.lighting = { ...(base.lighting || {}), clockTime: cam.clockTime };
  const f = path.join(tmpDir, 'scene.json');
  fs.writeFileSync(f, JSON.stringify(sc));
  const t0 = Date.now();
  await page.goto(`http://127.0.0.1:${port}/view.html?scene=${encodeURIComponent('/scene.json?f=' + f)}&w=${w}&h=${h}`);
  await page.waitForFunction(() => document.title.startsWith('done'), null, { timeout: 300000 });
  const out = `${outPrefix}_${cam.name || 'view'}.png`;
  await page.screenshot({ path: out });
  console.log(out, (Date.now() - t0) + 'ms');
}
fs.rmSync(tmpDir, { recursive: true, force: true });
await browser.close();
server.close();

// Рендер кадров из JSON (dump.luau) в PNG через headless Chromium + three.js.
//   node tools/preview/render.mjs in.json outDir [width height]
import { createRequire } from 'module';
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch { playwright = require('/opt/node22/lib/node_modules/playwright'); }

const here = path.dirname(fileURLToPath(import.meta.url));
const [, , inJson, outDir, wArg, hArg] = process.argv;
const W = Number(wArg || 1280), H = Number(hArg || 720);
fs.mkdirSync(outDir, { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(here, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(here) || !fs.existsSync(p)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const browser = await playwright.chromium.launch({
  executablePath: fs.existsSync('/opt/pw-browsers/chromium') ? undefined : undefined,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on('console', m => { if (m.type() === 'error') console.error('[page]', m.text()); });
page.on('pageerror', e => console.error('[pageerror]', e.message));
await page.addInitScript(([w, h]) => { window.__W = w; window.__H = h; }, [W, H]);
await page.goto(`http://127.0.0.1:${port}/viewer.html`);
await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
const data = JSON.parse(fs.readFileSync(inJson, 'utf8'));
const n = await page.evaluate(d => window.loadData(d), data);
for (let i = 0; i < n; i++) {
  const url = await page.evaluate(i => window.renderFrame(i), i);
  const fr = data.frames[i];
  const name = `${fr.shot}_t${fr.t.toFixed(3)}.png`;
  fs.writeFileSync(path.join(outDir, name), Buffer.from(url.split(',')[1], 'base64'));
  console.log(path.join(outDir, name));
}
await browser.close();
server.close();

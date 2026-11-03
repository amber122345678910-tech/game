// Renders exported frames with the three.js preview renderer in headless
// Chromium and writes PNG files.
//   node render.cjs <scene.json> <outDir> [width] [height] [firstFrame] [lastFrame]
//   node render.cjs <frames.jsonl> <outDir> [width] [height]   (streams frames;
//        the scene is read from <frames>.scene.json)
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { chromium } = require('playwright');

const ROOT = __dirname;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };

(async () => {
  const [inPath, outDir, wArg, hArg, f0Arg, f1Arg] = process.argv.slice(2);
  const W = parseInt(wArg || '1280', 10), H = parseInt(hArg || '720', 10);
  const streaming = inPath.endsWith('.jsonl');
  const data = JSON.parse(fs.readFileSync(streaming ? inPath.replace(/\.jsonl$/, '.scene.json') : inPath, 'utf8'));
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  page.on('console', m => { if (m.type() === 'error') console.log('[page]', m.text()); });
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  await page.route('http://preview.local/**', route => {
    const url = new URL(route.request().url());
    const file = path.join(ROOT, decodeURIComponent(url.pathname));
    if (!file.startsWith(ROOT) || !fs.existsSync(file)) return route.fulfill({ status: 404, body: 'not found' });
    route.fulfill({ status: 200, contentType: TYPES[path.extname(file)] || 'application/octet-stream', body: fs.readFileSync(file) });
  });
  await page.goto('http://preview.local/render.html');
  await page.waitForFunction(() => window.Preview && window.Preview.ready, null, { timeout: 60000 });
  const t0 = Date.now();
  const frames = data.frames || [];
  delete data.frames;
  await page.evaluate(({ data, W, H }) => { data.frames = []; window.Preview.init(data, W, H); }, { data, W, H });
  console.log(`init ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  const save = async i => {
    const url = await page.evaluate(i => window.Preview.renderFrame(i), i);
    const b64 = url.slice(url.indexOf(',') + 1);
    fs.writeFileSync(path.join(outDir, `f_${String(i).padStart(4, '0')}.png`), Buffer.from(b64, 'base64'));
    if (i % 30 === 0) console.log(`frame ${i} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
  };
  if (streaming) {
    const rl = readline.createInterface({ input: fs.createReadStream(inPath), crlfDelay: Infinity });
    let i = 0;
    for await (const line of rl) {
      if (!line.trim()) continue;
      await page.evaluate(([i, s]) => window.Preview.pushFrame(i, JSON.parse(s)), [i, line]);
      await save(i);
      i++;
    }
  } else {
    const f0 = parseInt(f0Arg || '0', 10);
    const f1 = Math.min(parseInt(f1Arg || String(frames.length - 1), 10), frames.length - 1);
    for (let i = 0; i < frames.length; i++) await page.evaluate(([i, fr]) => window.Preview.pushFrame(i, fr), [i, frames[i]]);
    for (let i = f0; i <= f1; i++) await save(i);
  }
  await browser.close();
})();

#!/usr/bin/env node
// Offline 3D preview renderer for SOUL VERDICT (three.js r170 in headless Chromium via Playwright).
//
// 1) dump a model with Lune:   lune run tools/lune/dump_model.luau rig Dummy --out tools/preview/out/dummy.json
// 2) render it:               node tools/preview/render.mjs --in tools/preview/out/dummy.json --out shot.png
//
// Options
//   --in <scene.json>          (repeatable) models to render; several = lineup side by side along X
//   --out <file.png>           output PNG (default tools/preview/out/render.png)
//   --env <env.json>           lighting/post preset (format: tools/preview/scene/env.js header)
//   --view front|back|left|right|threeQuarter|threeQuarterLeft|head|top|iso|custom
//                              (default threeQuarter; front when several --in are given)
//                              front = camera on -Z looking at the face; left/right = the MODEL's left/right
//   --cam x,y,z --target x,y,z custom camera (implies --view custom)
//   --width 1600 --height 1000 output size;  --fov 35 vertical field of view (deg)
//   --sheet N                  turntable contact sheet: N azimuths (front, then every 360/N deg) in one image
//   --spacing 2                gap (studs) between lineup models;  --labels  name labels under lineup models
//   --quality draft|normal|high  draft = 1x + MSAA4 (~3 s), normal = 2x supersampling (~5 s, default),
//                              high = 3x supersampling + MSAA4 (showcase); --ss / --msaa override it
//   --ss 2                     supersampling factor (1..4);  --msaa 4  MSAA samples on the HDR target (0 = off)
//   --outline                  black toon outline on every model without its own Highlight (Toon style preview)
//   --outline-px 2.5           outline thickness in output pixels
//   --floor auto|grid|plain|none   ground disc (auto: grid for rigs/props, none for maps)
//   --ortho                    orthographic camera (iso is always orthographic)
//   --no-textures              disable procedural material textures
//   --vignette 0.16            vignette strength;  --title "text"  caption at the top
//   --shadow-map 4096          sun shadow map size;  --max-lights 24  cap on part lights
//   --timeout 120              seconds before giving up
//   --quiet                    no progress output
// Renders approximate Roblox: Y up, -Z forward, Cylinder axis X, SpecialMesh Sphere = ellipsoid filling the
// part, Ball = min(size) diameter; ACES tone mapping; Neon unlit + selective bloom; Highlight fill/outline.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ROOT = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const opts = { in: [] };
  const flags = new Set(['outline', 'ortho', 'labels', 'quiet', 'no-textures', 'help']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new Error(`unexpected argument ${a}`);
    const key = a.slice(2);
    if (flags.has(key)) {
      opts[key] = true;
      continue;
    }
    const value = argv[++i];
    if (value === undefined) throw new Error(`missing value for ${a}`);
    if (key === 'in') opts.in.push(value);
    else opts[key] = value;
  }
  return opts;
}

const vec = (s) => {
  const v = String(s).split(',').map(Number);
  if (v.length !== 3 || v.some((x) => !Number.isFinite(x))) throw new Error(`bad vector ${s} (expected x,y,z)`);
  return v;
};

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png' };

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const url = decodeURIComponent((req.url || '/').split('?')[0]);
      const file = path.normalize(path.join(ROOT, url));
      if (!file.startsWith(ROOT + path.sep) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404);
        res.end('not found');
        return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store', Connection: 'close' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || args.in.length === 0) {
    const header = fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n');
    console.log(header);
    process.exit(args.help ? 0 : 1);
  }
  const scenes = args.in.map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));
  const env = args.env ? JSON.parse(fs.readFileSync(args.env, 'utf8')) : null;
  const out = args.out || path.join(ROOT, 'out', 'render.png');
  const opts = {
    width: Number(args.width || 1600),
    height: Number(args.height || 1000),
    fov: Number(args.fov || 35),
    view: args.cam || args.target ? 'custom' : args.view || (args.in.length > 1 ? 'front' : 'threeQuarter'),
    cam: args.cam ? vec(args.cam) : undefined,
    target: args.target ? vec(args.target) : undefined,
    sheet: Number(args.sheet || 0),
    spacing: args.spacing !== undefined ? Number(args.spacing) : 2,
    ss: Number(args.ss || { draft: 1, normal: 2, high: 3 }[args.quality || 'normal'] || 2),
    msaa: args.msaa !== undefined ? Number(args.msaa) : { draft: 4, normal: 0, high: 4 }[args.quality || 'normal'] ?? 0,
    outline: !!args.outline,
    outlinePx: args['outline-px'] !== undefined ? Number(args['outline-px']) : 2.5,
    floor: args.floor || 'auto',
    ortho: !!args.ortho,
    labels: !!args.labels,
    textures: !args['no-textures'],
    vignette: args.vignette !== undefined ? Number(args.vignette) : 0.16,
    title: args.title,
    shadowMap: Number(args['shadow-map'] || (args.quality === 'draft' ? 2048 : 4096)),
    maxLights: Number(args['max-lights'] || 24),
  };
  const log = (...m) => {
    if (!args.quiet) console.log(...m);
  };

  const { chromium } = require('playwright');
  const server = await serve();
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const timeoutMs = Number(args.timeout || 120) * 1000;
  let failed = false;
  try {
    const page = await browser.newPage();
    page.on('pageerror', (e) => {
      failed = true;
      console.error('[page error]', e.message);
    });
    page.on('console', (m) => {
      if (m.type() === 'error' || m.type() === 'warning') console.error(`[page ${m.type()}]`, m.text());
    });
    await page.goto(`http://127.0.0.1:${port}/scene/index.html`);
    await page.waitForFunction(() => window.SVReady === true, null, { timeout: 30000 });
    const t0 = Date.now();
    let timer;
    const result = await Promise.race([
      page.evaluate((payload) => window.SVRender(payload), { scenes, env, opts }),
      new Promise((_, rej) => {
        timer = setTimeout(() => rej(new Error(`render timed out after ${timeoutMs / 1000}s`)), timeoutMs);
      }),
    ]).finally(() => clearTimeout(timer));
    const png = Buffer.from(result.png.split(',')[1], 'base64');
    fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
    fs.writeFileSync(out, png);
    log(`render: ${out} (${opts.width}x${opts.height}, view ${result.info.view}, ${result.info.parts} parts, ${result.info.triangles} tris, ${Date.now() - t0} ms)`);
    if (!args.quiet) log(JSON.stringify(result.info));
  } finally {
    await browser.close();
    server.closeAllConnections();
    server.close();
  }
  if (failed) process.exit(2);
}

main().catch((e) => {
  console.error('render.mjs:', e.message || e);
  process.exit(1);
});

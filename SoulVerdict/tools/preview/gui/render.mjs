#!/usr/bin/env node
// SoulVerdict offline GUI renderer: dump_gui JSON -> HTML/CSS (engine.js) -> PNG via Playwright Chromium.
//
// Usage:
//   node tools/preview/gui/render.mjs --in gui.json --out shot.png [--size 1920x1080]
//        [--in b.json --out b.png ...]      several pairs share one browser
//        [--html page.html]                 also write the generated HTML (debugging)
//        [--dpr 1]                          device scale factor
//        [--debug]                          tag DOM nodes with class/name (inspect the --html output)
// Fonts are loaded locally from tools/preview/gui/node_modules/@fontsource/* (run `npm install` there once).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// Roblox font family (content/fonts/families/<Name>.json) -> [web family, exact match?, @fontsource package]
export const FONT_MAP = {
	PressStart2P: ['Press Start 2P', true, 'press-start-2p'],
	Michroma: ['Michroma', true, 'michroma'],
	Oswald: ['Oswald', true, 'oswald'],
	Merriweather: ['Merriweather', true, 'merriweather'],
	Bangers: ['Bangers', true, 'bangers'],
	Sarpanch: ['Sarpanch', true, 'sarpanch'],
	TitilliumWeb: ['Titillium Web', true, 'titillium-web'],
	RobotoMono: ['Roboto Mono', true, 'roboto-mono'],
	Nunito: ['Nunito', true, 'nunito'],
	Jura: ['Jura', true, 'jura'],
	SourceSansPro: ['Source Sans 3', true, 'source-sans-3'],
	Montserrat: ['Montserrat', true, 'montserrat'],
	GothamSSm: ['Montserrat', false, 'montserrat'],
	BuilderSans: ['Inter', false, 'inter'],
	BuilderExtended: ['Inter', false, 'inter'],
	BuilderMono: ['Roboto Mono', false, 'roboto-mono'],
	Roboto: ['Roboto', true, 'roboto'],
	RobotoCondensed: ['Roboto Condensed', true, 'roboto-condensed'],
	Ubuntu: ['Ubuntu', true, 'ubuntu'],
	Fondamento: ['Fondamento', true, 'fondamento'],
	GrenzeGotisch: ['Grenze Gotisch', true, 'grenze-gotisch'],
	LuckiestGuy: ['Luckiest Guy', true, 'luckiest-guy'],
	Creepster: ['Creepster', true, 'creepster'],
	FredokaOne: ['Fredoka One', true, 'fredoka-one'],
	DenkOne: ['Denk One', true, 'denk-one'],
	AmaticSC: ['Amatic SC', true, 'amatic-sc'],
	SpecialElite: ['Special Elite', true, 'special-elite'],
	PermanentMarker: ['Permanent Marker', true, 'permanent-marker'],
	PatrickHand: ['Patrick Hand', true, 'patrick-hand'],
	JosefinSans: ['Josefin Sans', true, 'josefin-sans'],
	Kalam: ['Kalam', true, 'kalam'],
	IndieFlower: ['Indie Flower', true, 'indie-flower'],
	Inconsolata: ['Inconsolata', true, 'inconsolata'],
	Arimo: ['Arimo', true, 'arimo'],
	Arial: ['Arimo', false, 'arimo'],
	LegacyArial: ['Arimo', false, 'arimo'],
	LegacyArimo: ['Arimo', false, 'arimo'],
	Balthazar: ['Balthazar', true, 'balthazar'],
	ComicNeueAngular: ['Comic Neue', false, 'comic-neue'],
	AccanthisADFStd: ['Merriweather', false, 'merriweather'],
	Guru: ['Merriweather', false, 'merriweather'],
	Zekton: ['Michroma', false, 'michroma'],
	HighwayGothic: ['Roboto Condensed', false, 'roboto-condensed'],
	RomanAntique: ['Merriweather', false, 'merriweather'],
};

function parseArgs(argv) {
	const out = { pairs: [], size: null, html: null, dpr: 1, debug: false };
	let pendingIn = null;
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		const v = argv[i + 1];
		if (a === '--in') { pendingIn = v; i++; }
		else if (a === '--out') { out.pairs.push({ in: pendingIn, out: v }); pendingIn = null; i++; }
		else if (a === '--size') { out.size = v; i++; }
		else if (a === '--html') { out.html = v; i++; }
		else if (a === '--dpr') { out.dpr = Number(v) || 1; i++; }
		else if (a === '--debug') out.debug = true;
	}
	if (pendingIn) out.pairs.push({ in: pendingIn, out: pendingIn.replace(/\.json$/, '') + '.png' });
	return out;
}

// Lune's JSON encoder writes empty tables as {}; normalise child lists to arrays.
function normalize(n) {
	if (!Array.isArray(n.children)) n.children = [];
	if (!n.props || Array.isArray(n.props)) n.props = {};
	n.children.forEach(normalize);
	return n;
}

function fontCssLinks(doc) {
	const used = new Set();
	const walk = (n) => {
		const f = n.props && n.props.FontFace;
		if (f) {
			const m = /families\/([^/.]+)\.json/.exec(f.family || '');
			if (m) used.add(m[1]);
		}
		(n.children || []).forEach(walk);
	};
	walk(doc.root);
	used.add('SourceSansPro');
	const pkgs = new Set([...used].map((k) => (FONT_MAP[k] || FONT_MAP.SourceSansPro)[2]));
	const links = [];
	for (const pkg of pkgs) {
		const dir = path.join(here, 'node_modules', '@fontsource', pkg);
		if (!fs.existsSync(dir)) {
			console.warn(`[render] missing @fontsource/${pkg} (run npm install in tools/preview/gui)`);
			continue;
		}
		for (const f of fs.readdirSync(dir)) {
			if (/^\d{3}(-italic)?\.css$/.test(f)) links.push(pathToFileURL(path.join(dir, f)).href);
		}
	}
	return links;
}

function buildHtml(doc, opts) {
	const links = fontCssLinks(doc).map((h) => `<link rel="stylesheet" href="${h}">`).join('\n');
	const fontMap = Object.fromEntries(Object.entries(FONT_MAP).map(([k, v]) => [k, [v[0], v[1]]]));
	const engine = pathToFileURL(path.join(here, 'engine.js')).href;
	const data = JSON.stringify(doc).replace(/</g, '\\u003c');
	return `<!doctype html>
<html><head><meta charset="utf-8">
${links}
<style>
html,body{margin:0;padding:0;background:#000;overflow:hidden}
#stage{position:relative;overflow:hidden;background:#000}
.g{position:absolute;box-sizing:border-box}
.stroke{position:absolute;box-sizing:border-box;pointer-events:none;z-index:0}
.clip{position:absolute;left:0;top:0;right:0;bottom:0;overflow:hidden}
.canvas{position:absolute}
.sbar{position:absolute;z-index:100;border-radius:2px}
.t{position:absolute;z-index:0;overflow:visible;overflow-wrap:break-word;pointer-events:none;font-kerning:normal}
.vp{position:absolute;left:0;top:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center;flex-direction:column;opacity:.55}
.vp-fig{width:28%;height:52%;border-radius:40% 40% 18% 18%;border:2px dashed rgba(255,255,255,.35)}
.vp-cap{margin-top:6px;font:10px "Source Sans 3",sans-serif;letter-spacing:2px;color:rgba(255,255,255,.55)}
.img{position:absolute;left:0;top:0;right:0;bottom:0}
#measure{position:absolute;left:-100000px;top:0;visibility:hidden}
</style></head>
<body><div id="stage"></div><div id="measure"></div>
<script>window.__GUI__=${data};window.__FONTMAP__=${JSON.stringify(fontMap)};window.__OPTS__=${JSON.stringify({ debugNames: !!opts.debug })};</script>
<script src="${engine}"></script>
</body></html>`;
}

async function main() {
	const args = parseArgs(process.argv.slice(2));
	if (!args.pairs.length) {
		console.error('usage: node render.mjs --in gui.json --out shot.png [--size 1920x1080] [--html page.html] [--dpr 1]');
		process.exit(2);
	}
	const { chromium } = require('playwright');
	const browser = await chromium.launch();
	const tmpDir = path.join(here, '..', 'out');
	fs.mkdirSync(tmpDir, { recursive: true });
	try {
		for (const pair of args.pairs) {
			const doc = JSON.parse(fs.readFileSync(pair.in, 'utf8'));
			normalize(doc.root);
			let [w, h] = doc.viewport;
			if (args.size) [w, h] = args.size.split('x').map(Number);
			doc.viewport = [w, h];
			const html = buildHtml(doc, args);
			const htmlPath = args.html && args.pairs.length === 1 ? path.resolve(args.html) : path.join(tmpDir, `render_${process.pid}_${path.basename(pair.out, '.png')}.html`);
			fs.writeFileSync(htmlPath, html);
			const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: args.dpr });
			const errors = [];
			page.on('pageerror', (e) => errors.push(String(e)));
			page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
			await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'load' });
			const info = await page.evaluate(() => window.__render());
			await page.waitForTimeout(50);
			fs.mkdirSync(path.dirname(path.resolve(pair.out)), { recursive: true });
			await page.screenshot({ path: pair.out, clip: { x: 0, y: 0, width: w, height: h } });
			await page.close();
			if (!(args.html && args.pairs.length === 1)) fs.rmSync(htmlPath, { force: true });
			if (errors.length) console.warn(`[render] page errors for ${pair.in}:\n  ${errors.join('\n  ')}`);
			console.log(`render: ${pair.in} -> ${pair.out} (${w}x${h}, ${info.elements} nodes, ${info.fonts.length} font faces)`);
		}
	} finally {
		await browser.close();
	}
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});

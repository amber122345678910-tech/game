#!/usr/bin/env node
// Batch preview: dumps a screen with Lune for every theme x size x page and renders all PNGs in one browser.
//
//   node tools/preview/gui/gallery.mjs [--screen src/client/UI/Gallery] [--themes Classic,Royal,Void,Fell]
//        [--sizes 1920x1080,844x390] [--pages default|All,Controls,Data,Icons,Overlay] [--lang en|ru]
//        [--hud Battle|Modern] [--out previews/dev] [--prefix ui_gallery] [--jobs 2]
// Output names: <out>/<prefix>_<theme>_<WxH>.png for the default page, ..._<page>.png for explicit pages,
// with a _ru suffix when --lang ru. Intermediate JSON goes to tools/preview/out/ (gitignored).
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, '..', '..', '..');

function arg(name, fallback) {
	const i = process.argv.indexOf(`--${name}`);
	return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : fallback;
}

const screen = arg('screen', 'src/client/UI/Gallery');
const themes = arg('themes', 'Classic,Royal,Void,Fell').split(',');
const sizes = arg('sizes', '1920x1080,844x390').split(',');
const pages = arg('pages', 'default').split(',');
const lang = arg('lang', 'en');
const hud = arg('hud', null);
const outDir = path.resolve(projectRoot, arg('out', 'previews/dev'));
const prefix = arg('prefix', 'ui_gallery');
const jobs = Number(arg('jobs', '2'));
const lune = path.join(projectRoot, '.tools', 'cargo', 'bin', 'lune');
const tmp = path.join(projectRoot, 'tools', 'preview', 'out');
fs.mkdirSync(tmp, { recursive: true });
fs.mkdirSync(outDir, { recursive: true });

const tasks = [];
for (const theme of themes)
	for (const size of sizes)
		for (const page of pages) {
			const suffix = (page === 'default' ? '' : `_${page.toLowerCase()}`) + (lang === 'en' ? '' : `_${lang}`);
			const name = `${prefix}_${theme.toLowerCase()}_${size}${suffix}`;
			const args = ['run', 'tools/lune/dump_gui.luau', '--screen', screen, '--theme', theme, '--size', size, '--lang', lang, '--out', path.join(tmp, `${name}.json`)];
			if (page !== 'default') args.push('--deps-json', JSON.stringify({ Page: page }));
			if (hud) args.push('--hud', hud);
			tasks.push({ name, args });
		}

function run(cmd, args) {
	return new Promise((resolve, reject) => {
		const p = spawn(cmd, args, { cwd: projectRoot, stdio: ['ignore', 'pipe', 'pipe'] });
		let out = '';
		p.stdout.on('data', (d) => (out += d));
		p.stderr.on('data', (d) => (out += d));
		p.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} ${args.join(' ')}\n${out}`))));
	});
}

const queue = tasks.slice();
await Promise.all(
	Array.from({ length: Math.max(1, jobs) }, async () => {
		while (queue.length) {
			const t = queue.shift();
			process.stdout.write(await run(lune, t.args));
		}
	}),
);
const renderArgs = [path.join(here, 'render.mjs')];
for (const t of tasks) renderArgs.push('--in', path.join(tmp, `${t.name}.json`), '--out', path.join(outDir, `${t.name}.png`));
process.stdout.write(await run(process.execPath, renderArgs));

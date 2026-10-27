// Сборка игры в один HTML-файл: node claude-quest/build.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const src = (f) => readFileSync(join(root, "src", f), "utf8");
const order = ["luart.js", "viewport.js", "lessons.js", "sprites.js", "world.js", "battle.js", "editor.js", "claude.js", "main.js"];

const prelude = src("prelude.lua");
const js = [`const LUA_PRELUDE = ${JSON.stringify(prelude)};`, ...order.map((f) => `// ===== ${f} =====\n${src(f)}`)].join("\n\n");
const safeJs = js.replace(/<\/script/gi, "<\\/script");
const page = src("page.html").replace("<!--SCRIPT-->", () => `<script>\n"use strict";\n${safeJs}\n</script>`);

mkdirSync(join(root, "dist"), { recursive: true });
// для публикации как Artifact: без doctype/head (их добавляет платформа)
writeFileSync(join(root, "dist", "artifact.html"), page);
// самостоятельный файл: можно открыть в любом браузере телефона
const standalone = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content">
<meta name="theme-color" content="#07060c">
</head>
<body>
${page}
</body>
</html>
`;
writeFileSync(join(root, "index.html"), standalone);
console.log("ok", (standalone.length / 1024).toFixed(1) + " KB");

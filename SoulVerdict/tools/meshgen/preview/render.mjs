// Offline preview renderer for tools/meshgen: three.js in headless Chromium (Playwright).
// Usage: node render.mjs jobs.json
// jobs.json: { width, height, jobs: [ { out, view: "front"|"threequarter"|"side"|"top"|"back"|"low",
//              label?, meshes: [ { json: "/abs/path.json", matrix?: [16 row-major] } ] } ] }
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

// Playwright is installed globally (NODE_PATH); ESM imports ignore NODE_PATH, so use require().
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const threePath = path.join(here, "node_modules", "three", "build", "three.module.js");
const jobsFile = process.argv[2];
if (!jobsFile) {
	console.error("usage: node render.mjs jobs.json");
	process.exit(2);
}
const spec = JSON.parse(fs.readFileSync(jobsFile, "utf8"));
const W = spec.width || 640;
const H = spec.height || 640;

const html = `<!doctype html><html><head><meta charset="utf-8">
<style>
html,body{margin:0;padding:0;background:#000;}
#wrap{position:relative;width:${W}px;height:${H}px;overflow:hidden;
 background: radial-gradient(ellipse at 50% 38%, #3a4258 0%, #1d2130 55%, #0d0f16 100%);}
#label{position:absolute;left:12px;bottom:9px;font:600 15px/1.2 Inter,Segoe UI,Arial,sans-serif;color:#cfd6ea;
 letter-spacing:.3px;text-shadow:0 1px 2px #000}
#sub{position:absolute;right:12px;bottom:9px;font:500 13px/1.2 Inter,Segoe UI,Arial,sans-serif;color:#8d96ad}
canvas{display:block}
</style>
<script type="importmap">{"imports":{"three":"http://meshgen.local/three.module.js"}}</script>
</head><body><div id="wrap"><div id="label"></div><div id="sub"></div></div>
<script type="module">
import * as THREE from "three";
const W=${W}, H=${H};
const renderer = new THREE.WebGLRenderer({antialias:true, alpha:true, preserveDrawingBuffer:true});
renderer.setPixelRatio(1);
renderer.setSize(W,H);
renderer.setClearColor(0x000000, 0);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.getElementById("wrap").prepend(renderer.domElement);
const cache = new Map();
async function loadMesh(url){
  if(cache.has(url)) return cache.get(url);
  const r = await fetch(url); const j = await r.json();
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(j.positions,3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(j.normals,3));
  const lin = new Float32Array(j.colors.length);
  const c = new THREE.Color();
  for(let i=0;i<j.colors.length;i+=3){ c.setRGB(j.colors[i],j.colors[i+1],j.colors[i+2], THREE.SRGBColorSpace);
    lin[i]=c.r; lin[i+1]=c.g; lin[i+2]=c.b; }
  g.setAttribute("color", new THREE.Float32BufferAttribute(lin,3));
  g.setIndex(j.indices);
  const out = {geometry:g, info:j};
  cache.set(url,out);
  return out;
}
window.renderJob = async function(job){
  const scene = new THREE.Scene();
  const group = new THREE.Group();
  let tris = 0;
  for(const m of job.meshes){
    const {geometry, info} = await loadMesh(m.url);
    const mat = new THREE.MeshStandardMaterial({vertexColors:!job.noColor, roughness:0.62, metalness:0.0,
      flatShading:!!job.flat});
    const mesh = new THREE.Mesh(geometry, mat);
    mesh.castShadow = !job.noShadow; mesh.receiveShadow = !job.noShadow;
    if(m.matrix){ const M = new THREE.Matrix4(); M.set(...m.matrix); mesh.matrixAutoUpdate=false; mesh.matrix.copy(M); }
    group.add(mesh);
    tris += geometry.index.count/3;
  }
  scene.add(group);
  const box = new THREE.Box3().setFromObject(group);
  const center = box.getCenter(new THREE.Vector3());
  const size = box.getSize(new THREE.Vector3());
  const radius = size.length()*0.5;
  const views = {
    front:[0,0.10,-1], threequarter:[0.62,0.22,-0.78], side:[1,0.08,0], back:[-0.4,0.25,1],
    top:[0,1,-0.25], low:[0.45,-0.35,-0.85], threequarterL:[-0.62,0.22,-0.78]
  };
  const dir = new THREE.Vector3(...(views[job.view]||views.front)).normalize();
  const fov = 28;
  const dist = radius / Math.sin(THREE.MathUtils.degToRad(fov*0.5)) * (job.zoom||1.0);
  const cam = new THREE.PerspectiveCamera(fov, W/H, 0.01, 100);
  cam.position.copy(center).addScaledVector(dir, dist);
  cam.lookAt(center);
  // lights: key (upper left-front, shadowed), fill, rim, hemisphere ambient
  scene.add(new THREE.HemisphereLight(0xc9d6ff, 0x2a2430, 0.85));
  const key = new THREE.DirectionalLight(0xfff3e2, 2.6);
  key.position.copy(center).add(new THREE.Vector3(-0.55,0.75,-0.65).multiplyScalar(radius*4));
  key.target.position.copy(center);
  key.castShadow = true;
  key.shadow.mapSize.set(2048,2048);
  const sc = key.shadow.camera; sc.left=-radius*1.3; sc.right=radius*1.3; sc.top=radius*1.3; sc.bottom=-radius*1.3;
  sc.near=0.1; sc.far=radius*10; key.shadow.bias=-0.0004; key.shadow.normalBias=0.012; key.shadow.radius=3;
  scene.add(key); scene.add(key.target);
  const fill = new THREE.DirectionalLight(0xbcd0ff, 0.9);
  fill.position.copy(center).add(new THREE.Vector3(0.8,0.2,-0.5).multiplyScalar(radius*4));
  scene.add(fill);
  const rim = new THREE.DirectionalLight(0xa6c4ff, 1.6);
  rim.position.copy(center).add(new THREE.Vector3(0.3,0.5,1.0).multiplyScalar(radius*4));
  scene.add(rim);
  renderer.render(scene, cam);
  document.getElementById("label").textContent = job.label || "";
  document.getElementById("sub").textContent = job.sub || (tris + " tris");
  scene.traverse(o=>{ if(o.material) o.material.dispose(); });
  return true;
};
window.ready = true;
</script></body></html>`;

const browser = await chromium.launch({
	args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width: W, height: H } });
page.on("console", (m) => {
	if (m.type() === "error") console.error("[page]", m.text());
});
page.on("pageerror", (e) => console.error("[pageerror]", e.message));
await page.route("http://meshgen.local/**", async (route) => {
	const url = new URL(route.request().url());
	if (url.pathname === "/index.html") {
		return route.fulfill({ status: 200, contentType: "text/html", body: html });
	}
	if (url.pathname === "/three.module.js") {
		return route.fulfill({ status: 200, contentType: "text/javascript", body: fs.readFileSync(threePath) });
	}
	if (url.pathname.startsWith("/file/")) {
		const p = decodeURIComponent(url.pathname.slice("/file".length));
		return route.fulfill({ status: 200, contentType: "application/json", body: fs.readFileSync(p) });
	}
	return route.fulfill({ status: 404, body: "not found" });
});
await page.goto("http://meshgen.local/index.html");
await page.waitForFunction(() => window.ready === true);
for (const job of spec.jobs) {
	const j = {
		...job,
		meshes: job.meshes.map((m) => ({ ...m, url: "http://meshgen.local/file" + encodeURI(m.json) })),
	};
	await page.evaluate(async (jj) => await window.renderJob(jj), j);
	const el = await page.$("#wrap");
	await el.screenshot({ path: job.out });
	console.log("wrote", job.out);
}
await browser.close();

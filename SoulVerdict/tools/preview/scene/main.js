// Browser side of tools/preview/render.mjs. Exposes window.SVRender(payload) -> { png, info }.
// payload = { scenes: [dumpJson...], env: envJson|null, opts: {...} } (see render.mjs for options).
import * as THREE from 'three';
import { forPart, cframeMatrix } from './geometry.js';
import { makeMaterial } from './materials.js';
import { resolveEnv, buildSky, buildEnvMap, buildLights, buildPartLights, untonemap, srgbToLinear } from './env.js';
import { Post } from './post.js';

const DEG = Math.PI / 180;

// name -> [azimuth (deg, 0 = camera in front of the model on -Z, +90 = camera on the model's right/+X),
//          elevation (deg)]
const VIEWS = {
  front: [0, 6],
  back: [180, 6],
  left: [-90, 6],
  right: [90, 6],
  threeQuarter: [35, 12],
  threeQuarterLeft: [-35, 12],
  head: [18, 4],
  top: [0, 89.5],
  iso: [45, 35.264],
};

function boxOf(points) {
  const b = new THREE.Box3();
  for (const p of points) b.expandByPoint(p);
  return b;
}

function partCorners(part, offset) {
  const { scale, offset: meshOffset } = forPart(part);
  const m = cframeMatrix(part.cf);
  const out = [];
  for (const sx of [-0.5, 0.5]) for (const sy of [-0.5, 0.5]) for (const sz of [-0.5, 0.5]) {
    const p = new THREE.Vector3(sx * scale.x + meshOffset.x, sy * scale.y + meshOffset.y, sz * scale.z + meshOffset.z).applyMatrix4(m);
    out.push(p.add(offset));
  }
  return out;
}

// Grid floor that fades out radially (seamless with the sky), receives shadows.
function buildFloor(y, center, radius, kind) {
  const R = Math.max(120, radius * 40);
  const geo = new THREE.CircleGeometry(R, 96);
  geo.rotateX(-Math.PI / 2);
  const mat = new THREE.MeshStandardMaterial({ color: srgbToLinear([0.52, 0.52, 0.54]), roughness: 0.9, metalness: 0, transparent: true, envMapIntensity: 0.2 });
  const fade0 = Math.max(10, radius * 5), fade1 = Math.max(26, radius * 13);
  mat.onBeforeCompile = (shader) => {
    shader.uniforms.uCenter = { value: new THREE.Vector2(center.x, center.z) };
    shader.uniforms.uFade = { value: new THREE.Vector2(fade0, fade1) };
    shader.uniforms.uGrid = { value: kind === 'grid' ? 1 : 0 };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vSvWorld;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvSvWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vSvWorld;\nuniform vec2 uCenter;\nuniform vec2 uFade;\nuniform float uGrid;\nfloat svLine(vec2 p, float s){ vec2 q = p / s; vec2 g = abs(fract(q - 0.5) - 0.5) / fwidth(q); return 1.0 - min(min(g.x, g.y), 1.0); }')
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
float svR = length(vSvWorld.xz - uCenter);
if (uGrid > 0.5) {
  float near = 1.0 - smoothstep(uFade.x * 0.4, uFade.x * 1.4, svR);
  diffuseColor.rgb *= 1.0 - (0.07 * svLine(vSvWorld.xz, 1.0) + 0.12 * svLine(vSvWorld.xz, 4.0)) * near;
}
diffuseColor.a *= 1.0 - smoothstep(uFade.x, uFade.y, svR);`,
      );
  };
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(center.x, y - 0.002, center.z);
  mesh.receiveShadow = true;
  mesh.userData.isFloor = true;
  return mesh;
}

// Positions the camera for azimuth/elevation so that `box` fills the frame. Returns the camera.
function frameCamera(camera, box, azDeg, elDeg, margin) {
  const az = azDeg * DEG, el = elDeg * DEG;
  const dir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), -Math.cos(az) * Math.cos(el)).normalize();
  const upHint = Math.abs(dir.y) > 0.98 ? new THREE.Vector3(0, 0, -1) : new THREE.Vector3(0, 1, 0);
  const corners = [];
  for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) corners.push(new THREE.Vector3(x, y, z));
  let target = box.getCenter(new THREE.Vector3());
  const f = dir.clone().negate();
  const r = new THREE.Vector3().crossVectors(f, upHint).normalize();
  const u = new THREE.Vector3().crossVectors(r, f).normalize();
  camera.up.copy(upHint);
  if (camera.isOrthographicCamera) {
    let hx = 0, hy = 0;
    for (const c of corners) {
      const rel = c.clone().sub(target);
      hx = Math.max(hx, Math.abs(rel.dot(r)));
      hy = Math.max(hy, Math.abs(rel.dot(u)));
    }
    const aspect = (camera.right - camera.left) / (camera.top - camera.bottom);
    const half = Math.max(hy, hx / aspect) * margin;
    camera.left = -half * aspect; camera.right = half * aspect; camera.top = half; camera.bottom = -half;
    const dist = box.getSize(new THREE.Vector3()).length() * 2 + 10;
    camera.position.copy(target).addScaledVector(dir, dist);
    camera.near = 0.1; camera.far = dist * 4;
    camera.lookAt(target);
    camera.updateProjectionMatrix();
    return camera;
  }
  const tanV = Math.tan((camera.fov * DEG) / 2) / margin;
  const tanH = tanV * camera.aspect;
  for (let iter = 0; iter < 3; iter++) {
    let d = 0;
    for (const c of corners) {
      const rel = c.clone().sub(target);
      const z = rel.dot(f);
      d = Math.max(d, Math.abs(rel.dot(r)) / tanH - z, Math.abs(rel.dot(u)) / tanV - z);
    }
    camera.position.copy(target).addScaledVector(dir, d);
    camera.lookAt(target);
    camera.updateMatrixWorld();
    // re-centre the projected bounds
    let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
    const proj = new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
    for (const c of corners) {
      const p = c.clone().applyMatrix4(proj);
      minx = Math.min(minx, p.x); maxx = Math.max(maxx, p.x); miny = Math.min(miny, p.y); maxy = Math.max(maxy, p.y);
    }
    const cx = (minx + maxx) / 2, cy = (miny + maxy) / 2;
    target = target.clone().addScaledVector(r, cx * d * tanH * margin).addScaledVector(u, cy * d * tanV * margin);
  }
  const dist = camera.position.distanceTo(target);
  camera.near = Math.max(0.02, dist * 0.01);
  camera.far = Math.max(4000, dist * 60);
  camera.updateProjectionMatrix();
  return camera;
}

function downsample(src, dst, dx, dy, w, h) {
  let canvas = src;
  let cw = src.width, ch = src.height;
  while (cw / 2 >= w * 1.0001 && cw > w * 2) {
    const tmp = document.createElement('canvas');
    tmp.width = Math.round(cw / 2); tmp.height = Math.round(ch / 2);
    const tctx = tmp.getContext('2d');
    tctx.imageSmoothingEnabled = true;
    tctx.imageSmoothingQuality = 'high';
    tctx.drawImage(canvas, 0, 0, cw, ch, 0, 0, tmp.width, tmp.height);
    canvas = tmp; cw = tmp.width; ch = tmp.height;
  }
  const ctx = dst.getContext('2d');
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(canvas, 0, 0, cw, ch, dx, dy, w, h);
}

function label(ctx, text, x, y, size) {
  ctx.save();
  ctx.font = `600 ${size}px "DejaVu Sans", Arial, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'bottom';
  ctx.lineWidth = Math.max(2, size / 5);
  ctx.strokeStyle = 'rgba(0,0,0,0.55)';
  ctx.strokeText(text, x, y);
  ctx.fillStyle = 'rgba(255,255,255,0.92)';
  ctx.fillText(text, x, y);
  ctx.restore();
}

// Lune's JSON encoder writes empty Lua tables as {} -> normalise list fields.
const arr = (x) => (Array.isArray(x) ? x : []);
function normaliseScene(s) {
  s.parts = arr(s.parts);
  s.lights = arr(s.lights);
  s.highlights = arr(s.highlights).map((h) => ({ ...h, parts: arr(h.parts) }));
  s.anchors = s.anchors && !Array.isArray(s.anchors) ? s.anchors : {};
  s.bounds = s.bounds || { min: [-1, 0, -1], max: [1, 2, 1] };
  return s;
}

window.SVRender = async function SVRender(payload) {
  const t0 = performance.now();
  payload.scenes = payload.scenes.map(normaliseScene);
  const opts = payload.opts || {};
  const env = resolveEnv(payload.env);
  const W = opts.width || 1600, H = opts.height || 1000;
  const ss = Math.max(1, Math.min(4, opts.ss || 2));
  const sheet = Math.max(0, opts.sheet || 0);
  const cols = sheet > 0 ? (sheet <= 4 ? sheet : Math.ceil(sheet / 2)) : 1;
  const rows = sheet > 0 ? Math.ceil(sheet / cols) : 1;
  const cellW = Math.floor(W / cols), cellH = Math.floor(H / rows);
  const rw = cellW * ss, rh = cellH * ss;
  const exposure = env.exposure ?? 1;

  const canvas = document.createElement('canvas');
  canvas.width = rw; canvas.height = rh;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(1);
  renderer.setSize(rw, rh, false);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = exposure;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  const anisotropy = renderer.capabilities.getMaxAnisotropy();

  const scene = new THREE.Scene();
  const bloomMeshes = new Set();
  const meshToHighlight = new Map();
  const highlightSets = [];
  const allLights = [];
  const allCorners = [];
  const perScene = [];
  let partCount = 0;

  // Lineup: models side by side along X. Scene 0 is the left-most in the front view
  // (front view looks towards +Z, so image-left is world +X).
  const spacing = opts.spacing ?? 2;
  const widths = payload.scenes.map((s) => s.bounds.max[0] - s.bounds.min[0]);
  const totalW = widths.reduce((a, b) => a + b, 0) + spacing * Math.max(0, payload.scenes.length - 1);
  let cursor = totalW / 2;
  payload.scenes.forEach((s, si) => {
    const offset = new THREE.Vector3();
    if (payload.scenes.length > 1) {
      const centreX = (s.bounds.min[0] + s.bounds.max[0]) / 2;
      offset.x = cursor - widths[si] / 2 - centreX;
      cursor -= widths[si] + spacing;
    }
    const group = new THREE.Group();
    group.position.copy(offset);
    scene.add(group);
    const meshes = [];
    const corners = [];
    for (const part of s.parts) {
      const { geometry, scale, offset: meshOffset } = forPart(part);
      const { material, bloom } = makeMaterial(part, scale, { anisotropy, textures: opts.textures !== false });
      const mesh = new THREE.Mesh(geometry, material);
      mesh.matrixAutoUpdate = false;
      mesh.matrix.copy(cframeMatrix(part.cf)).multiply(new THREE.Matrix4().makeTranslation(meshOffset.x, meshOffset.y, meshOffset.z)).multiply(new THREE.Matrix4().makeScale(scale.x, scale.y, scale.z));
      mesh.castShadow = part.castShadow !== false && !(part.transparency > 0.6) && !bloom;
      mesh.receiveShadow = !bloom;
      mesh.userData.part = part;
      group.add(mesh);
      meshes.push(mesh);
      if (bloom) bloomMeshes.add(mesh);
      const pc = partCorners(part, offset);
      corners.push(...pc);
      allCorners.push(...pc);
      partCount++;
    }
    for (const h of s.highlights || []) {
      const idx = highlightSets.length;
      highlightSets.push(h);
      for (const pi of h.parts || []) if (meshes[pi]) meshToHighlight.set(meshes[pi], idx);
    }
    if (opts.outline && !(s.highlights || []).length) {
      const idx = highlightSets.length;
      highlightSets.push({ fill: [0, 0, 0], outline: opts.outlineColor || [0, 0, 0], fillT: 1, outlineT: 0, depthMode: 'Occluded' });
      for (const m of meshes) meshToHighlight.set(m, idx);
    }
    for (const L of s.lights || []) allLights.push({ ...L, pos: [L.pos[0] + offset.x, L.pos[1] + offset.y, L.pos[2] + offset.z] });
    perScene.push({ json: s, offset, corners, meshes });
  });

  const box = allCorners.length ? boxOf(allCorners) : new THREE.Box3(new THREE.Vector3(-1, 0, -1), new THREE.Vector3(1, 2, 1));
  const center = box.getCenter(new THREE.Vector3());
  const size = box.getSize(new THREE.Vector3());
  const radius = Math.max(1, size.length() / 2);

  // Floor
  const kinds = payload.scenes.map((s) => s.kind);
  let floorMode = opts.floor || 'auto';
  if (floorMode === 'auto') floorMode = kinds.every((k) => k !== 'map') ? 'grid' : 'none';
  if (floorMode !== 'none') scene.add(buildFloor(box.min.y, center, radius, floorMode));

  // Lights, environment, sky, fog
  const focusRadius = floorMode !== 'none' ? radius * 1.9 : radius * 1.05;
  for (const l of buildLights(env, { center, radius: focusRadius }, opts.shadowMap || 4096)) scene.add(l);
  for (const l of buildPartLights(allLights, opts.maxLights ?? 24)) scene.add(l);
  scene.environment = buildEnvMap(renderer, env);
  if (env.fog && env.fog.color) {
    const fc = untonemap(env.fog.color, exposure);
    scene.fog = new THREE.Fog(fc, env.fog.near ?? radius * 8, env.fog.far ?? radius * 40);
  }

  // Camera
  const aspect = cellW / cellH;
  const viewName = opts.view || 'threeQuarter';
  const ortho = opts.ortho || viewName === 'iso';
  const camera = ortho ? new THREE.OrthographicCamera(-aspect, aspect, 1, -1, 0.1, 1000) : new THREE.PerspectiveCamera(opts.fov || 35, aspect, 0.1, 4000);
  const sky = buildSky(env, 1, exposure);
  scene.add(sky);

  // Framing box (head view: only the head's visual parts of the first model)
  let frameBox = box;
  if (viewName === 'head') {
    const first = perScene[0];
    const prefix = `${first.json.name}.Head.`;
    const headCorners = [];
    first.json.parts.forEach((p) => {
      if ((p.path || '').startsWith(prefix)) headCorners.push(...partCorners(p, first.offset));
    });
    if (headCorners.length) frameBox = boxOf(headCorners);
  }

  const post = new Post(renderer, rw, rh, { msaa: opts.msaa ?? 4, outlinePx: (opts.outlinePx ?? 2.5) * ss, vignette: opts.vignette ?? 0.16 });
  post.bloomEnabled = bloomMeshes.size > 0 && (env.bloom?.strength ?? 0) > 0;
  post.setup(scene, camera, env, highlightSets);

  const out = document.createElement('canvas');
  out.width = W; out.height = H;
  const octx = out.getContext('2d');
  octx.fillStyle = '#000';
  octx.fillRect(0, 0, W, H);

  const placeSky = () => {
    const far = camera.far * 0.9;
    sky.scale.setScalar(ortho ? camera.far * 0.45 : far);
    sky.position.copy(camera.position);
    sky.updateMatrixWorld();
  };

  const shots = [];
  if (sheet > 0) {
    const [baseAz, baseEl] = VIEWS[viewName === 'head' ? 'head' : 'front'] || [0, 8];
    for (let i = 0; i < sheet; i++) shots.push({ az: baseAz + (360 / sheet) * i, el: viewName === 'top' ? 30 : baseEl + 4 });
  } else if (viewName === 'custom' || (opts.cam && opts.target)) {
    shots.push({ custom: true });
  } else {
    const v = VIEWS[viewName];
    if (!v) throw new Error(`unknown view ${viewName}; use ${Object.keys(VIEWS).join('|')}|custom`);
    shots.push({ az: v[0], el: v[1] });
  }

  shots.forEach((shot, i) => {
    if (shot.custom) {
      const cam = opts.cam || [center.x, center.y, center.z - radius * 3];
      const tgt = opts.target || [center.x, center.y, center.z];
      camera.position.set(...cam);
      camera.up.set(0, 1, 0);
      camera.lookAt(new THREE.Vector3(...tgt));
      const dist = camera.position.distanceTo(new THREE.Vector3(...tgt));
      camera.near = Math.max(0.02, dist * 0.005);
      camera.far = Math.max(4000, dist * 60);
      camera.updateProjectionMatrix();
    } else {
      frameCamera(camera, frameBox, shot.az, shot.el, viewName === 'head' ? 1.2 : 1.1);
    }
    camera.updateMatrixWorld();
    placeSky();
    post.render(bloomMeshes, meshToHighlight);
    const cx = (i % cols) * cellW, cy = Math.floor(i / cols) * cellH;
    downsample(canvas, out, cx, cy, cellW, cellH);
    if (sheet > 0) {
      const a = ((Math.round(shot.az) % 360) + 360) % 360;
      const names = { 0: 'front', 90: 'right side', 180: 'back', 270: 'left side' };
      label(octx, `${names[a] || ''} ${a}°`.trim(), cx + cellW / 2, cy + cellH - 10, Math.round(Math.min(cellW, cellH) * 0.045) + 8);
    }
  });

  if (opts.labels && payload.scenes.length > 1 && sheet === 0) {
    // Label each model under its feet in the final view.
    perScene.forEach((ps) => {
      const b = boxOf(ps.corners);
      const p = new THREE.Vector3((b.min.x + b.max.x) / 2, b.min.y, (b.min.z + b.max.z) / 2).project(camera);
      const x = (p.x * 0.5 + 0.5) * W, y = (-p.y * 0.5 + 0.5) * H;
      label(octx, ps.json.name || ps.json.id, x, Math.min(H - 8, y + 34), 22);
    });
  }
  if (opts.title) label(octx, opts.title, W / 2, 40, 26);

  const info = {
    ms: Math.round(performance.now() - t0),
    parts: partCount,
    triangles: renderer.info.render.triangles,
    bloomParts: bloomMeshes.size,
    highlights: highlightSets.length,
    lights: allLights.length,
    view: viewName,
    camera: camera.position.toArray().map((v) => +v.toFixed(3)),
    bounds: { min: box.min.toArray().map((v) => +v.toFixed(3)), max: box.max.toArray().map((v) => +v.toFixed(3)) },
  };
  const png = out.toDataURL('image/png');
  renderer.dispose();
  return { png, info };
};

window.SVReady = true;

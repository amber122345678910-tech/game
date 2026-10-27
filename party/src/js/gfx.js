'use strict';
// Графика: рендерер, небо, свет, процедурные текстуры (шипы-«стады» как у Роблокса), детали, эффекты.

const R = {
  renderer: null,
  scene: null,
  sun: null,
  hemi: null,
  sunDir: new THREE.Vector3(0.45, 0.8, 0.3).normalize(),
  maxAniso: 4,
  quality: 'high',
  theme: null,
  tex: {},
};

function initRenderer(container) {
  const q = Store.data.settings.quality;
  const renderer = new THREE.WebGLRenderer({ antialias: q !== 'low', powerPreference: 'high-performance' });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.setScissorTest(true);
  container.appendChild(renderer.domElement);
  R.renderer = renderer;
  R.maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const scene = new THREE.Scene();
  R.scene = scene;
  scene.fog = new THREE.Fog(0xcfe7ff, 150, 900);

  R.hemi = new THREE.HemisphereLight(0xd8ecff, 0x6b8a4e, 0.9);
  scene.add(R.hemi);
  const sun = new THREE.DirectionalLight(0xfff4e0, 2.6);
  sun.castShadow = true;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.04;
  const sc = sun.shadow.camera;
  sc.left = -55; sc.right = 55; sc.top = 55; sc.bottom = -55; sc.near = 1; sc.far = 420;
  scene.add(sun);
  scene.add(sun.target);
  R.sun = sun;

  buildTextures();
  buildSky();
  buildClouds();
  buildWater();
  FX.init(scene);
  applyQuality(q);
}

function applyQuality(q) {
  R.quality = q;
  const r = R.renderer;
  const dpr = window.devicePixelRatio || 1;
  r.setPixelRatio(q === 'high' ? Math.min(dpr, 1.6) : q === 'mid' ? Math.min(dpr, 1) : Math.min(dpr, 0.75));
  const shadows = q !== 'low';
  if (r.shadowMap.enabled !== shadows) {
    r.shadowMap.enabled = shadows;
    R.scene.traverse((o) => {
      if (!o.material) return;
      (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => { m.needsUpdate = true; });
    });
  }
  const size = q === 'high' ? 2048 : 1024;
  if (R.sun.shadow.mapSize.x !== size) {
    R.sun.shadow.mapSize.set(size, size);
    if (R.sun.shadow.map) { R.sun.shadow.map.dispose(); R.sun.shadow.map = null; }
  }
  R.clouds && (R.clouds.visible = q !== 'low' || true);
  resizeRenderer();
}

function resizeRenderer() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  R.renderer.setSize(w, h, false);
  R.w = w;
  R.h = h;
}

// Тень следует за тем игроком, чья половина экрана сейчас рисуется.
const _shadowTmp = new THREE.Vector3();
function focusShadow(p) {
  const step = 110 / R.sun.shadow.mapSize.x;
  _shadowTmp.set(Math.round(p.x / step) * step, Math.round(p.y / step) * step, Math.round(p.z / step) * step);
  R.sun.target.position.copy(_shadowTmp);
  R.sun.position.copy(_shadowTmp).addScaledVector(R.sunDir, 200);
  R.sun.target.updateMatrixWorld();
  R.sun.updateMatrixWorld();
}

// ---------------------------------------------------------------------------
// Небо: градиент + солнце, облака из многогранников, звёзды для ночных карт.

const SKY_VS = `
varying vec3 vDir;
void main() {
  vDir = normalize(position);
  vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  gl_Position = p.xyww;
}`;
const SKY_FS = `
uniform vec3 top; uniform vec3 horizon; uniform vec3 bottom; uniform vec3 sunDir; uniform vec3 sunColor; uniform float sunSize;
varying vec3 vDir;
void main() {
  vec3 d = normalize(vDir);
  float h = d.y;
  vec3 col = h > 0.0 ? mix(horizon, top, pow(clamp(h, 0.0, 1.0), 0.55)) : mix(horizon, bottom, pow(clamp(-h, 0.0, 1.0), 0.35));
  float s = max(dot(d, normalize(sunDir)), 0.0);
  col += sunColor * (smoothstep(1.0 - sunSize, 1.0 - sunSize * 0.6, s) * 1.6 + pow(s, 14.0) * 0.28 + pow(s, 3.0) * 0.06);
  gl_FragColor = vec4(col, 1.0);
}`;

function buildSky() {
  const uniforms = {
    top: { value: new THREE.Color('#3b8ce6') },
    horizon: { value: new THREE.Color('#c4e6ff') },
    bottom: { value: new THREE.Color('#e6f4ff') },
    sunDir: { value: R.sunDir.clone() },
    sunColor: { value: new THREE.Color('#fff2cc') },
    sunSize: { value: 0.0016 },
  };
  const mat = new THREE.ShaderMaterial({ uniforms, vertexShader: SKY_VS, fragmentShader: SKY_FS, side: THREE.BackSide, depthWrite: false, fog: false });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(1000, 32, 16), mat);
  sky.renderOrder = -10;
  sky.frustumCulled = false;
  R.scene.add(sky);
  R.sky = sky;
  R.skyUniforms = uniforms;

  // Тот же шейдер в отдельной сцене — из неё делается карта окружения для бликов.
  R.envScene = new THREE.Scene();
  R.envScene.add(new THREE.Mesh(new THREE.SphereGeometry(10, 32, 16), mat));
  R.pmrem = new THREE.PMREMGenerator(R.renderer);

  const starGeo = new THREE.BufferGeometry();
  const pts = [];
  for (let i = 0; i < 900; i++) {
    const v = new THREE.Vector3(rand(-1, 1), rand(0.05, 1), rand(-1, 1)).normalize().multiplyScalar(900);
    pts.push(v.x, v.y, v.z);
  }
  starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  R.stars = new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xffffff, size: 2.2, sizeAttenuation: false, fog: false, transparent: true, opacity: 0.85 }));
  R.stars.frustumCulled = false;
  R.stars.visible = false;
  R.scene.add(R.stars);
}

function buildClouds() {
  const group = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, flatShading: true, emissive: 0xffffff, emissiveIntensity: 0.28, fog: true });
  R.cloudMat = mat;
  const blob = new THREE.IcosahedronGeometry(1, 1);
  for (let i = 0; i < 34; i++) {
    const parts = [];
    const n = randi(4, 7);
    const w = rand(16, 34);
    for (let k = 0; k < n; k++) {
      const g = blob.clone();
      const s = rand(0.35, 0.6) * w * (1 - Math.abs(k - n / 2) / n);
      g.scale(s, s * 0.7, s * 0.85);
      g.translate((k / (n - 1) - 0.5) * w * 1.3, rand(-1, 3), rand(-w * 0.2, w * 0.2));
      parts.push(g);
    }
    const mesh = new THREE.Mesh(mergeGeos(parts), mat);
    const a = rand(0, TAU);
    const d = rand(150, 750);
    mesh.position.set(Math.cos(a) * d, rand(70, 170), Math.sin(a) * d);
    mesh.rotation.y = rand(0, TAU);
    mesh.userData.speed = rand(1.5, 4);
    group.add(mesh);
  }
  R.scene.add(group);
  R.clouds = group;
}

function buildWater() {
  const geo = new THREE.PlaneGeometry(5000, 5000);
  geo.rotateX(-Math.PI / 2);
  const tex = R.tex.waterN;
  const mat = new THREE.MeshStandardMaterial({ color: 0x2b93d8, roughness: 0.12, metalness: 0.05, normalMap: tex, normalScale: new THREE.Vector2(0.55, 0.55), envMapIntensity: 1.1 });
  const water = new THREE.Mesh(geo, mat);
  water.receiveShadow = true;
  water.visible = false;
  R.scene.add(water);
  R.water = water;
}

const THEMES = {
  day: { top: '#3b8ce6', horizon: '#c4e6ff', bottom: '#e6f4ff', sun: '#fff2cc', sunI: 2.7, hemiS: '#d8ecff', hemiG: '#71905a', hemiI: 0.85, fog: '#cfe7ff', near: 160, far: 950, exp: 1.05, clouds: true, cloud: '#ffffff', sunDir: [0.45, 0.8, 0.3] },
  sunset: { top: '#3d5bb8', horizon: '#ffb37a', bottom: '#ffd9b0', sun: '#ffd7a1', sunI: 2.4, hemiS: '#ffd6c0', hemiG: '#6a5a7a', hemiI: 0.8, fog: '#f3b996', near: 150, far: 900, exp: 1.05, clouds: true, cloud: '#ffe2d0', sunDir: [0.7, 0.35, -0.4] },
  night: { top: '#0b1030', horizon: '#3a2a6a', bottom: '#120c2a', sun: '#cfd8ff', sunI: 1.5, hemiS: '#7f7ff0', hemiG: '#2a1840', hemiI: 0.9, fog: '#1a1438', near: 120, far: 700, exp: 1.15, clouds: false, stars: true, sunDir: [-0.4, 0.7, 0.35] },
  disco: { top: '#170a3a', horizon: '#7a2a8a', bottom: '#2a0f40', sun: '#ffd0ff', sunI: 1.6, hemiS: '#b48cff', hemiG: '#40205a', hemiI: 1.1, fog: '#2a1450', near: 140, far: 700, exp: 1.2, clouds: false, stars: true, sunDir: [0.3, 0.8, 0.4] },
  lava: { top: '#5a2a3a', horizon: '#ff8a4a', bottom: '#3a1410', sun: '#ffc08a', sunI: 2.3, hemiS: '#ffc9a0', hemiG: '#5a2a20', hemiI: 0.9, fog: '#d9714a', near: 120, far: 650, exp: 1.05, clouds: true, cloud: '#ffcfb5', sunDir: [0.5, 0.6, 0.4] },
  heaven: { top: '#6db6ff', horizon: '#fff3d6', bottom: '#ffffff', sun: '#fff6d0', sunI: 2.8, hemiS: '#ffffff', hemiG: '#c9b98a', hemiI: 1.0, fog: '#eaf4ff', near: 150, far: 900, exp: 1.05, clouds: true, cloud: '#ffffff', sunDir: [0.3, 0.85, 0.2] },
};

function setTheme(name) {
  const t = THEMES[name] || THEMES.day;
  R.theme = name;
  const u = R.skyUniforms;
  u.top.value.set(t.top);
  u.horizon.value.set(t.horizon);
  u.bottom.value.set(t.bottom);
  u.sunColor.value.set(t.sun);
  R.sunDir.set(...t.sunDir).normalize();
  u.sunDir.value.copy(R.sunDir);
  u.sunSize.value = t.stars ? 0.0009 : 0.0016;
  R.sun.color.set(t.sun);
  R.sun.intensity = t.sunI;
  R.hemi.color.set(t.hemiS);
  R.hemi.groundColor.set(t.hemiG);
  R.hemi.intensity = t.hemiI;
  R.scene.fog.color.set(t.fog);
  R.scene.fog.near = t.near;
  R.scene.fog.far = t.far;
  R.renderer.toneMappingExposure = t.exp;
  R.clouds.visible = !!t.clouds;
  if (t.cloud) { R.cloudMat.color.set(t.cloud); R.cloudMat.emissive.set(t.cloud); }
  R.stars.visible = !!t.stars;
  if (R.envRT) R.envRT.dispose();
  R.envRT = R.pmrem.fromScene(R.envScene, 0, 0.1, 100);
  R.scene.environment = R.envRT.texture;
}

function updateSkyFrame(dt, t) {
  for (const c of R.clouds.children) {
    c.position.x += c.userData.speed * dt;
    if (c.position.x > 800) c.position.x = -800;
  }
  R.tex.waterN.offset.set(t * 0.01, t * 0.006);
  R.tex.lava.offset.set(t * 0.03, t * 0.05);
  R.tex.conveyor.offset.y = -t * 0.5;
  R.water.material.normalMap = R.tex.waterN;
}

// ---------------------------------------------------------------------------
// Процедурные текстуры.

function canvasTex(w, h, draw, opts = {}) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const g = c.getContext('2d');
  draw(g, w, h);
  const t = new THREE.CanvasTexture(c);
  if (opts.srgb !== false) t.colorSpace = THREE.SRGBColorSpace;
  if (opts.repeat !== false) { t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.RepeatWrapping; }
  t.anisotropy = R.maxAniso;
  if (opts.rep) t.repeat.set(opts.rep, opts.rep);
  return t;
}

function heightToNormal(g, w, h, hf, strength) {
  const img = g.createImageData(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = (hf((x + 1) % w, y) - hf((x - 1 + w) % w, y)) * strength;
      const dy = (hf(x, (y + 1) % h) - hf(x, (y - 1 + h) % h)) * strength;
      let nx = -dx;
      let ny = dy;
      let nz = 1;
      const l = Math.hypot(nx, ny, nz);
      nx /= l; ny /= l; nz /= l;
      const i = (y * w + x) * 4;
      img.data[i] = (nx * 0.5 + 0.5) * 255;
      img.data[i + 1] = (ny * 0.5 + 0.5) * 255;
      img.data[i + 2] = (nz * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
}

function speckle(g, w, h, n, colors, rmin, rmax, alpha = 1) {
  g.globalAlpha = alpha;
  for (let i = 0; i < n; i++) {
    g.fillStyle = pick(colors);
    const r = rand(rmin, rmax);
    g.fillRect(rand(0, w), rand(0, h), r, r);
  }
  g.globalAlpha = 1;
}

function buildTextures() {
  const T = R.tex;
  const S = 64;
  const studH = (x, y) => {
    const d = Math.hypot(x + 0.5 - S / 2, y + 0.5 - S / 2);
    return 1 - smooth01((d - 17) / 3);
  };
  T.studN = canvasTex(S, S, (g, w, h) => heightToNormal(g, w, h, studH, 2.2), { srgb: false });
  T.stud = canvasTex(S, S, (g, w, h) => {
    const img = g.createImageData(w, h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const d = Math.hypot(x + 0.5 - w / 2, y + 0.5 - h / 2);
      let v = 236 + rand(-3, 3);
      if (d < 17) v = 246 + rand(-2, 2);
      else if (d < 22) v = 236 - (22 - d) * 4;
      const i = (y * w + x) * 4;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
      img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
  });
  T.plastic = canvasTex(S, S, (g, w, h) => {
    g.fillStyle = '#efefef';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 260, ['#e4e4e4', '#f7f7f7'], 1, 2);
  });
  T.grass = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#62b33f';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 900, ['#58a838', '#6fc24a', '#7ccf52', '#4f9a33'], 1, 3);
    g.strokeStyle = '#86d65a';
    g.globalAlpha = 0.6;
    for (let i = 0; i < 140; i++) {
      const x = rand(0, w); const y = rand(0, h);
      g.beginPath(); g.moveTo(x, y); g.lineTo(x + rand(-1.5, 1.5), y - rand(2, 4)); g.stroke();
    }
    g.globalAlpha = 1;
  }, { rep: 0.25 });
  T.dirt = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#8a5a35';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 700, ['#7a4e2d', '#996640', '#6e4426', '#a8754a'], 1, 4);
  }, { rep: 0.25 });
  T.sand = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#ecd9a3';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 900, ['#e2cc90', '#f4e4b5', '#d8c086'], 1, 2);
  }, { rep: 0.25 });
  T.stone = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#d9d9d9';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 500, ['#c8c8c8', '#e6e6e6', '#bdbdbd'], 2, 6);
    g.strokeStyle = 'rgba(0,0,0,0.12)';
    g.lineWidth = 2;
    for (let i = 0; i < 6; i++) { g.beginPath(); g.moveTo(rand(0, w), rand(0, h)); g.lineTo(rand(0, w), rand(0, h)); g.stroke(); }
  }, { rep: 0.25 });
  T.wood = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#e9e9e9';
    g.fillRect(0, 0, w, h);
    for (let p = 0; p < 4; p++) {
      const y = p * 32;
      g.fillStyle = ['#e2e2e2', '#f0f0f0', '#dadada', '#ebebeb'][p];
      g.fillRect(0, y, w, 32);
      g.strokeStyle = 'rgba(0,0,0,0.08)';
      for (let k = 0; k < 6; k++) { g.beginPath(); const yy = y + rand(3, 29); g.moveTo(0, yy); g.bezierCurveTo(w * 0.3, yy + rand(-3, 3), w * 0.6, yy + rand(-3, 3), w, yy); g.stroke(); }
      g.fillStyle = 'rgba(0,0,0,0.28)';
      g.fillRect(0, y, w, 2);
      g.fillRect((p * 47) % w, y, 2, 32);
    }
  }, { rep: 0.25 });
  T.brick = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#cfcfcf';
    g.fillRect(0, 0, w, h);
    for (let r = 0; r < 8; r++) for (let c = 0; c < 5; c++) {
      const off = r % 2 ? 16 : 0;
      g.fillStyle = pick(['#f2f2f2', '#e8e8e8', '#fafafa', '#e0e0e0']);
      g.fillRect(c * 32 + off - 32 + 2, r * 16 + 2, 28, 12);
      g.fillRect(c * 32 + off + 2, r * 16 + 2, 28, 12);
    }
  }, { rep: 0.25 });
  T.metal = canvasTex(64, 64, (g, w, h) => {
    g.fillStyle = '#d0d4da';
    g.fillRect(0, 0, w, h);
    g.fillStyle = '#e8ebef';
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
      g.save(); g.translate(x * 16 + 8 + (y % 2) * 8, y * 16 + 8); g.rotate(y % 2 ? 0.7 : -0.7); g.fillRect(-5, -1.5, 10, 3); g.restore();
    }
  }, { rep: 0.5 });
  T.lava = canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#ff4a10';
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 60; i++) {
      const x = rand(0, w); const y = rand(0, h); const r = rand(6, 18);
      const gr = g.createRadialGradient(x, y, 0, x, y, r);
      gr.addColorStop(0, pick(['#ffd34a', '#ffb02e', '#ff7a1a']));
      gr.addColorStop(1, 'rgba(255,60,0,0)');
      g.fillStyle = gr;
      for (const ox of [-w, 0, w]) for (const oy of [-h, 0, h]) { g.save(); g.translate(ox, oy); g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill(); g.restore(); }
    }
    speckle(g, w, h, 120, ['#a8200a', '#c42a0c'], 2, 5, 0.6);
  }, { rep: 0.125 });
  T.waterN = canvasTex(128, 128, (g, w, h) => {
    const hm = new Float32Array(w * h);
    for (let k = 0; k < 14; k++) {
      const fx = randi(1, 5); const fy = randi(1, 5); const ph = rand(0, TAU); const a = rand(0.3, 1);
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) hm[y * w + x] += a * Math.sin((x / w) * TAU * fx + (y / h) * TAU * fy + ph);
    }
    heightToNormal(g, w, h, (x, y) => hm[y * w + x], 0.12);
  }, { srgb: false });
  T.waterN.repeat.set(220, 220);
  T.truss = canvasTex(64, 64, (g, w, h) => {
    g.clearRect(0, 0, w, h);
    g.strokeStyle = '#d6d6d6';
    g.lineWidth = 7;
    g.strokeRect(4, 4, w - 8, h - 8);
    g.lineWidth = 5;
    g.beginPath(); g.moveTo(4, 4); g.lineTo(w - 4, h - 4); g.moveTo(w - 4, 4); g.lineTo(4, h - 4); g.stroke();
  }, { rep: 0.5 });
  T.conveyor = canvasTex(64, 64, (g, w, h) => {
    g.fillStyle = '#34363d';
    g.fillRect(0, 0, w, h);
    g.fillStyle = '#ffcc1a';
    for (let k = 0; k < 2; k++) {
      const y = k * 32;
      g.beginPath(); g.moveTo(8, y + 24); g.lineTo(32, y + 6); g.lineTo(56, y + 24); g.lineTo(56, y + 30); g.lineTo(32, y + 12); g.lineTo(8, y + 30); g.closePath(); g.fill();
    }
  }, { rep: 0.25 });
  T.checker = canvasTex(64, 64, (g) => {
    for (let y = 0; y < 2; y++) for (let x = 0; x < 2; x++) { g.fillStyle = (x + y) % 2 ? '#1d1d24' : '#f4f4f4'; g.fillRect(x * 32, y * 32, 32, 32); }
  }, { rep: 0.5 });
  T.glow = canvasTex(64, 64, (g, w, h) => {
    const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, 'rgba(255,255,255,1)');
    gr.addColorStop(0.4, 'rgba(255,255,255,0.5)');
    gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr;
    g.fillRect(0, 0, w, h);
  }, { repeat: false });
  T.heart = canvasTex(64, 64, (g) => {
    g.fillStyle = '#fff';
    g.beginPath();
    g.moveTo(32, 56);
    g.bezierCurveTo(4, 36, 4, 10, 20, 10);
    g.bezierCurveTo(28, 10, 32, 18, 32, 22);
    g.bezierCurveTo(32, 18, 36, 10, 44, 10);
    g.bezierCurveTo(60, 10, 60, 36, 32, 56);
    g.fill();
  }, { repeat: false });
  T.star = canvasTex(64, 64, (g) => {
    g.fillStyle = '#fff';
    g.beginPath();
    for (let i = 0; i < 10; i++) {
      const r = i % 2 ? 12 : 30;
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      g.lineTo(32 + Math.cos(a) * r, 32 + Math.sin(a) * r);
    }
    g.closePath();
    g.fill();
  }, { repeat: false });
  for (const k in T) if (T[k]) SHARED_TEX.add(T[k]);
}

// ---------------------------------------------------------------------------
// Материалы с кэшем: один материал на (вид, цвет).

const MAT_KINDS = {
  plastic: { tex: 'plastic', top: 'stud', topN: 'studN', rough: 0.55 },
  smooth: { tex: 'plastic', rough: 0.45 },
  grass: { tex: 'grass', side: 'dirt', rough: 0.95, white: true },
  dirt: { tex: 'dirt', rough: 0.95, white: true },
  sand: { tex: 'sand', rough: 0.95, white: true },
  stone: { tex: 'stone', rough: 0.85 },
  wood: { tex: 'wood', rough: 0.8 },
  brick: { tex: 'brick', rough: 0.9 },
  metal: { tex: 'metal', rough: 0.35, metal: 0.6 },
  checker: { tex: 'checker', rough: 0.5, white: true },
  conveyor: { tex: 'conveyor', rough: 0.6, white: true, sideTex: 'plastic' },
};

const SHARED_TEX = new Set();

const Mat = {
  cache: new Map(),
  get(kind, color) {
    const key = kind + '|' + color;
    let m = this.cache.get(key);
    if (m) return m;
    m = this.make(kind, color);
    for (const one of Array.isArray(m) ? m : [m]) one.userData.cached = true;
    this.cache.set(key, m);
    return m;
  },
  make(kind, color) {
    const T = R.tex;
    if (kind === 'neon') return new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(1.15), toneMapped: false });
    if (kind === 'glass') return new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.38, roughness: 0.04, metalness: 0.1, envMapIntensity: 1.8, depthWrite: false });
    if (kind === 'ice') return new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.88, roughness: 0.06, metalness: 0.05, envMapIntensity: 1.4 });
    if (kind === 'gold') return new THREE.MeshStandardMaterial({ color, roughness: 0.22, metalness: 1, envMapIntensity: 1.3 });
    if (kind === 'lava') return new THREE.MeshStandardMaterial({ color: 0xffffff, map: T.lava, emissive: 0xffffff, emissiveMap: T.lava, emissiveIntensity: 0.9, roughness: 0.6 });
    if (kind === 'truss') return new THREE.MeshStandardMaterial({ color, map: T.truss, alphaTest: 0.5, side: THREE.DoubleSide, roughness: 0.4, metalness: 0.3 });
    if (kind === 'glow') return new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 0.55, roughness: 0.4 });
    const k = MAT_KINDS[kind] || MAT_KINDS.plastic;
    // У «цветных» текстур (трава, песок, шахматка) белый — это «без подкраски».
    const tint = k.white ? (color && color !== '#ffffff' ? color : 0xffffff) : color;
    const mk = (texName, extra) => new THREE.MeshStandardMaterial({ color: tint, map: T[texName], roughness: k.rough, metalness: k.metal || 0, ...extra });
    // Порядок граней BoxGeometry: +x, -x, +y, -y, +z, -z.
    if (kind === 'grass') {
      const side = new THREE.MeshStandardMaterial({ color: 0xffffff, map: T.dirt, roughness: 0.95 });
      const top = mk('grass');
      return [side, side, top, side, side, side];
    }
    if (kind === 'conveyor') {
      const side = new THREE.MeshStandardMaterial({ color, map: T.plastic, roughness: 0.5 });
      const top = new THREE.MeshStandardMaterial({ color: 0xffffff, map: T.conveyor, roughness: 0.6 });
      return [side, side, top, side, side, side];
    }
    if (k.top) {
      const side = mk(k.tex);
      const top = mk(k.top, { normalMap: T[k.topN], roughness: k.rough - 0.05 });
      return [side, side, top, side, side, side];
    }
    return mk(k.tex);
  },
};

function scaleBoxUV(geo, sx, sy, sz) {
  const uv = geo.attributes.uv;
  const dims = [[sz, sy], [sz, sy], [sx, sz], [sx, sz], [sx, sy], [sx, sy]];
  const per = uv.count / 6;
  for (let f = 0; f < 6; f++) {
    for (let i = 0; i < per; i++) {
      const k = f * per + i;
      uv.setXY(k, uv.getX(k) * dims[f][0], uv.getY(k) * dims[f][1]);
    }
  }
  uv.needsUpdate = true;
  return geo;
}

function boxGeo(sx, sy, sz) {
  return scaleBoxUV(new THREE.BoxGeometry(sx, sy, sz), sx, sy, sz);
}

// Деталь-кирпичик: меш + (по умолчанию) коллайдер. Координаты — центр.
function part(parent, x, y, z, sx, sy, sz, o = {}) {
  const kind = o.mat || 'plastic';
  const mesh = new THREE.Mesh(boxGeo(sx, sy, sz), Mat.get(kind, o.color || '#a3a2a5'));
  mesh.position.set(x, y, z);
  mesh.castShadow = o.cast !== undefined ? o.cast : kind !== 'neon' && kind !== 'glass' && kind !== 'lava';
  mesh.receiveShadow = o.receive !== undefined ? o.receive : kind !== 'neon';
  if (o.rotY) mesh.rotation.y = o.rotY;
  parent.add(mesh);
  let col = null;
  if (o.collide !== false) {
    col = World.addBox(x, y, z, sx, sy, sz, {
      mesh, kill: !!o.kill, bounce: o.bounce || 0, conveyor: o.conveyor || null, climb: !!o.climb, ice: !!o.ice,
      noCam: !!o.noCam || kind === 'glass' || kind === 'neon', solid: o.solid !== false, ...(o.props || {}),
    });
  }
  return { mesh, col };
}

function cylGeo(r, h, seg = 24, rTop = r) {
  const g = new THREE.CylinderGeometry(rTop, r, h, seg);
  const uv = g.attributes.uv;
  const sideCount = (seg + 1) * 2;
  for (let i = 0; i < uv.count; i++) {
    if (i < sideCount) uv.setXY(i, uv.getX(i) * TAU * r, uv.getY(i) * h);
    else uv.setXY(i, uv.getX(i) * r * 2, uv.getY(i) * r * 2);
  }
  return g;
}

// Цилиндр стоит на y0, высота h.
function cylPart(parent, x, y0, z, r, h, o = {}) {
  const kind = o.mat || 'plastic';
  let mat = Mat.get(kind, o.color || '#a3a2a5');
  if (Array.isArray(mat)) mat = [mat[0], mat[2], mat[3]];
  const mesh = new THREE.Mesh(cylGeo(r, h, o.seg || 32, o.rTop || r), mat);
  mesh.position.set(x, y0 + h / 2, z);
  mesh.castShadow = o.cast !== undefined ? o.cast : kind !== 'neon';
  mesh.receiveShadow = true;
  parent.add(mesh);
  let col = null;
  if (o.collide !== false) col = World.addCyl(x, z, o.colR || r, y0, y0 + h, { mesh, kill: !!o.kill, bounce: o.bounce || 0 });
  return { mesh, col };
}

// Склейка геометрий (позиции, нормали, uv) — меньше вызовов отрисовки.
function mergeGeos(list) {
  let vCount = 0;
  let iCount = 0;
  const geos = list;
  for (const g of geos) {
    vCount += g.attributes.position.count;
    iCount += g.index ? g.index.count : g.attributes.position.count;
  }
  const pos = new Float32Array(vCount * 3);
  const nor = new Float32Array(vCount * 3);
  const uv = new Float32Array(vCount * 2);
  const idx = new Uint32Array(iCount);
  let vo = 0;
  let io = 0;
  for (const g of geos) {
    if (!g.attributes.normal) g.computeVertexNormals();
    pos.set(g.attributes.position.array, vo * 3);
    nor.set(g.attributes.normal.array, vo * 3);
    if (g.attributes.uv) uv.set(g.attributes.uv.array, vo * 2);
    if (g.index) for (let i = 0; i < g.index.count; i++) idx[io++] = g.index.array[i] + vo;
    else for (let i = 0; i < g.attributes.position.count; i++) idx[io++] = i + vo;
    vo += g.attributes.position.count;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  out.computeBoundingSphere();
  return out;
}

// Скруглённая коробка: вершины прижимаются к внутренней коробке и выталкиваются на радиус.
function roundedBox(w, h, d, r, seg = 3) {
  const g = new THREE.BoxGeometry(w, h, d, seg * 2, seg * 2, seg * 2);
  const p = g.attributes.position;
  const n = g.attributes.normal;
  const iw = w / 2 - r;
  const ih = h / 2 - r;
  const id = d / 2 - r;
  const v = new THREE.Vector3();
  const c = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    c.set(clamp(v.x, -iw, iw), clamp(v.y, -ih, ih), clamp(v.z, -id, id));
    v.sub(c);
    const len = v.length();
    if (len > 1e-6) {
      v.multiplyScalar(r / len);
      n.setXYZ(i, v.x / r, v.y / r, v.z / r);
    }
    v.add(c);
    p.setXYZ(i, v.x, v.y, v.z);
  }
  p.needsUpdate = true;
  n.needsUpdate = true;
  return g;
}

// ---------------------------------------------------------------------------
// Надписи: табло, таблички, ники над головой.

function roundRect(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

const FONT = '"Rubik", "Arial Black", "Segoe UI", sans-serif';

function signTexture(lines, o = {}) {
  const w = o.w || 1024;
  const h = o.h || 384;
  return canvasTex(w, h, (g) => {
    if (o.bg !== null) {
      g.fillStyle = o.bg || '#1b2033';
      roundRect(g, 6, 6, w - 12, h - 12, o.radius || 40);
      g.fill();
      if (o.border) { g.lineWidth = 12; g.strokeStyle = o.border; g.stroke(); }
    }
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    let y = o.top || h * 0.5 - ((lines.length - 1) * (lines[0].size || 80) * 0.6);
    for (const L of lines) {
      const size = L.size || 80;
      g.font = `${L.weight || 900} ${size}px ${FONT}`;
      if (L.stroke) { g.lineWidth = L.strokeW || size * 0.14; g.strokeStyle = L.stroke; g.lineJoin = 'round'; g.strokeText(L.text, w / 2, y); }
      g.fillStyle = L.color || '#fff';
      g.fillText(L.text, w / 2, y, w - 40);
      y += size * (L.gap || 1.2);
    }
  }, { repeat: false });
}

function signMesh(parent, lines, x, y, z, width, height, o = {}) {
  const tex = signTexture(lines, { ...o, w: o.texW || 1024, h: o.texH || Math.round(1024 * height / width) });
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, toneMapped: false, side: o.double ? THREE.DoubleSide : THREE.FrontSide });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), mat);
  mesh.position.set(x, y, z);
  if (o.rotY) mesh.rotation.y = o.rotY;
  parent.add(mesh);
  return mesh;
}

function textSprite(text, o = {}) {
  const size = o.size || 64;
  const c = document.createElement('canvas');
  const g = c.getContext('2d');
  g.font = `900 ${size}px ${FONT}`;
  const tw = Math.ceil(g.measureText(text).width) + size;
  c.width = tw;
  c.height = Math.ceil(size * 1.6);
  g.font = `900 ${size}px ${FONT}`;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  if (o.bg) { g.fillStyle = o.bg; roundRect(g, 4, 4, c.width - 8, c.height - 8, size * 0.4); g.fill(); }
  g.lineJoin = 'round';
  g.lineWidth = size * 0.2;
  g.strokeStyle = o.stroke || 'rgba(0,0,0,0.75)';
  g.strokeText(text, c.width / 2, c.height / 2);
  g.fillStyle = o.color || '#fff';
  g.fillText(text, c.width / 2, c.height / 2);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: o.depthTest !== false, depthWrite: false, toneMapped: false });
  const s = new THREE.Sprite(mat);
  const hgt = o.height || 1;
  s.scale.set((hgt * c.width) / c.height, hgt, 1);
  s.renderOrder = o.renderOrder || 5;
  return s;
}

// ---------------------------------------------------------------------------
// Частицы: кубики-конфетти (освещённые) и светящиеся искры; плюс всплывающие надписи.

const FX = {
  cap: 1600,
  init(scene) {
    const box = new THREE.BoxGeometry(1, 1, 1);
    this.solid = new THREE.InstancedMesh(box, new THREE.MeshStandardMaterial({ roughness: 0.5 }), this.cap);
    this.glow = new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.6, 0), new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.95, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false }), this.cap);
    for (const m of [this.solid, this.glow]) {
      m.frustumCulled = false;
      m.count = 0;
      m.setColorAt(0, new THREE.Color(1, 1, 1));
      m.castShadow = false;
      scene.add(m);
    }
    this.list = [];
    this.sprites = [];
    this.debris = [];
    this.rings = [];
    this.scene = scene;
    this._m = new THREE.Matrix4();
    this._q = new THREE.Quaternion();
    this._e = new THREE.Euler();
    this._s = new THREE.Vector3();
    this._c = new THREE.Color();
    this.spriteMats = {
      heart: new THREE.SpriteMaterial({ map: R.tex.heart, transparent: true, depthWrite: false, toneMapped: false }),
      star: new THREE.SpriteMaterial({ map: R.tex.star, transparent: true, depthWrite: false, toneMapped: false }),
      glow: new THREE.SpriteMaterial({ map: R.tex.glow, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false }),
    };
  },

  emit(o) {
    if (this.list.length >= this.cap * 2 - 10) return;
    this.list.push({
      x: o.x, y: o.y, z: o.z,
      vx: o.vx || 0, vy: o.vy || 0, vz: o.vz || 0,
      life: o.life || 1, t: 0,
      size: o.size || 0.4,
      color: new THREE.Color(o.color || '#ffffff'),
      glow: !!o.glow,
      grav: o.grav == null ? 30 : o.grav,
      drag: o.drag || 0,
      rx: rand(0, TAU), ry: rand(0, TAU), spin: o.spin == null ? rand(-8, 8) : o.spin,
      floorY: o.floorY == null ? -Infinity : o.floorY,
    });
  },

  burst(pos, n, o = {}) {
    const colors = o.colors || [o.color || '#ffffff'];
    for (let i = 0; i < n; i++) {
      const a = rand(0, TAU);
      const up = o.up == null ? 0.6 : o.up;
      const sp = rand(0.4, 1) * (o.speed || 12);
      const el = rand(-0.2, 1) * up;
      this.emit({
        x: pos.x + rand(-1, 1) * (o.spread || 0.3), y: pos.y + rand(-1, 1) * (o.spread || 0.3), z: pos.z + rand(-1, 1) * (o.spread || 0.3),
        vx: Math.cos(a) * sp * (1 - Math.abs(el) * 0.5), vy: el * sp + (o.lift || 0), vz: Math.sin(a) * sp * (1 - Math.abs(el) * 0.5),
        life: rand(0.6, 1) * (o.life || 1), size: rand(0.6, 1.2) * (o.size || 0.4), color: pick(colors), glow: o.glow, grav: o.grav, drag: o.drag || 1.2,
        floorY: o.floorY,
      });
    }
  },

  confetti(pos, n = 120) {
    this.burst(pos, n, { colors: ['#ff4d6d', '#ffd23f', '#3ea6ff', '#7ed321', '#c77dff', '#ff9d2e'], speed: 26, up: 1.4, lift: 18, size: 0.45, grav: 22, drag: 1.8, life: 3.2, spread: 1 });
  },

  ring(pos, color, o = {}) {
    const geo = new THREE.TorusGeometry(1, 0.12, 6, 32);
    geo.rotateX(Math.PI / 2);
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, toneMapped: false, depthWrite: false });
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(pos);
    this.scene.add(m);
    this.rings.push({ m, t: 0, life: o.life || 0.5, size: o.size || 6 });
  },

  sprite(kind, pos, o = {}) {
    const s = new THREE.Sprite(this.spriteMats[kind].clone());
    s.material.color.set(o.color || '#ffffff');
    s.position.copy(pos);
    const sz = o.size || 0.8;
    s.scale.set(sz, sz, 1);
    this.scene.add(s);
    this.sprites.push({ s, t: 0, life: o.life || 1, vx: o.vx || 0, vy: o.vy == null ? 2 : o.vy, vz: o.vz || 0, size: sz, grow: o.grow || 0, text: false });
  },

  text(pos, text, o = {}) {
    const s = textSprite(text, { color: o.color || '#fff', size: 64, height: o.height || 1.6, depthTest: false, renderOrder: 20 });
    s.position.copy(pos);
    this.scene.add(s);
    this.sprites.push({ s, t: 0, life: o.life || 1.1, vx: 0, vy: o.vy == null ? 3 : o.vy, vz: 0, size: 0, text: true, base: s.scale.clone() });
  },

  // Обломки тела при «ауч» — как в Роблоксе, персонаж разваливается на части.
  addDebris(mesh, vel, spin) {
    this.scene.add(mesh);
    this.debris.push({ mesh, vel, spin, t: 0 });
  },

  clearAll() {
    this.list.length = 0;
    for (const sp of this.sprites) { this.scene.remove(sp.s); sp.s.material.map && sp.text && sp.s.material.map.dispose(); sp.s.material.dispose(); }
    this.sprites.length = 0;
    for (const d of this.debris) this.scene.remove(d.mesh);
    this.debris.length = 0;
    for (const r of this.rings) { this.scene.remove(r.m); r.m.geometry.dispose(); r.m.material.dispose(); }
    this.rings.length = 0;
  },

  update(dt) {
    const L = this.list;
    let ns = 0;
    let ng = 0;
    for (let i = L.length - 1; i >= 0; i--) {
      const p = L[i];
      p.t += dt;
      if (p.t >= p.life) { L[i] = L[L.length - 1]; L.pop(); continue; }
      p.vy -= p.grav * dt;
      const dr = Math.exp(-p.drag * dt);
      p.vx *= dr; p.vz *= dr; if (p.drag > 0) p.vy *= Math.exp(-p.drag * 0.3 * dt);
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      if (p.y < p.floorY) { p.y = p.floorY; p.vy *= -0.3; p.vx *= 0.6; p.vz *= 0.6; p.spin *= 0.5; }
      p.rx += p.spin * dt; p.ry += p.spin * 0.7 * dt;
      const k = p.t / p.life;
      const sc = p.size * (k < 0.75 ? 1 : 1 - (k - 0.75) / 0.25);
      const mesh = p.glow ? this.glow : this.solid;
      const idx = p.glow ? ng++ : ns++;
      if (idx >= this.cap) continue;
      this._e.set(p.rx, p.ry, 0);
      this._q.setFromEuler(this._e);
      this._s.set(sc, sc, sc);
      this._m.makeRotationFromQuaternion(this._q);
      this._m.scale(this._s);
      this._m.setPosition(p.x, p.y, p.z);
      mesh.setMatrixAt(idx, this._m);
      mesh.setColorAt(idx, p.color);
    }
    this.solid.count = Math.min(ns, this.cap);
    this.glow.count = Math.min(ng, this.cap);
    for (const m of [this.solid, this.glow]) {
      m.instanceMatrix.needsUpdate = true;
      if (m.instanceColor) m.instanceColor.needsUpdate = true;
    }

    for (let i = this.sprites.length - 1; i >= 0; i--) {
      const sp = this.sprites[i];
      sp.t += dt;
      const k = sp.t / sp.life;
      if (k >= 1) {
        this.scene.remove(sp.s);
        if (sp.text) sp.s.material.map.dispose();
        sp.s.material.dispose();
        this.sprites.splice(i, 1);
        continue;
      }
      sp.s.position.x += sp.vx * dt;
      sp.s.position.y += sp.vy * dt;
      sp.s.position.z += sp.vz * dt;
      sp.s.material.opacity = k < 0.7 ? 1 : 1 - (k - 0.7) / 0.3;
      if (sp.text) {
        const pop = k < 0.15 ? 0.5 + (k / 0.15) * 0.7 : k < 0.25 ? 1.2 - ((k - 0.15) / 0.1) * 0.2 : 1;
        sp.s.scale.copy(sp.base).multiplyScalar(pop);
      } else {
        const s = sp.size * (1 + sp.grow * k);
        sp.s.scale.set(s, s, 1);
      }
    }

    for (let i = this.debris.length - 1; i >= 0; i--) {
      const d = this.debris[i];
      d.t += dt;
      d.vel.y -= 70 * dt;
      d.mesh.position.addScaledVector(d.vel, dt);
      const fl = World.groundAt(d.mesh.position.x, d.mesh.position.z, d.mesh.position.y + 0.6);
      if (d.mesh.position.y - 0.4 < fl && d.vel.y < 0 && fl > -Infinity) {
        d.mesh.position.y = fl + 0.4;
        d.vel.y *= -0.35;
        d.vel.x *= 0.7;
        d.vel.z *= 0.7;
        d.spin.multiplyScalar(0.7);
      }
      d.mesh.rotation.x += d.spin.x * dt;
      d.mesh.rotation.y += d.spin.y * dt;
      d.mesh.rotation.z += d.spin.z * dt;
      if (d.t > 1.6) d.mesh.scale.multiplyScalar(Math.max(0, 1 - dt * 6));
      if (d.t > 2.2) {
        this.scene.remove(d.mesh);
        this.debris.splice(i, 1);
      }
    }

    for (let i = this.rings.length - 1; i >= 0; i--) {
      const r = this.rings[i];
      r.t += dt;
      const k = r.t / r.life;
      if (k >= 1) { this.scene.remove(r.m); r.m.geometry.dispose(); r.m.material.dispose(); this.rings.splice(i, 1); continue; }
      const s = 0.5 + r.size * smooth01(k);
      r.m.scale.set(s, s, s);
      r.m.material.opacity = 0.9 * (1 - k);
    }
  },
};

// ---------------------------------------------------------------------------
// Декор: деревья, цветы, камни, фонари, облачка-острова.

const Deco = {
  tree(parent, x, y, z, s = 1, o = {}) {
    const g = new THREE.Group();
    const trunkH = 5 * s;
    const trunk = new THREE.Mesh(cylGeo(0.7 * s, trunkH, 8, 0.55 * s), Mat.get('wood', '#8a5a35'));
    trunk.position.y = trunkH / 2;
    trunk.castShadow = true;
    trunk.receiveShadow = true;
    g.add(trunk);
    const leafColor = o.color || pick(['#4caf50', '#3e9d42', '#5cbf4a', '#43a047']);
    const leafMat = Mat.get('smooth', leafColor);
    const leaves = o.round === false ? null : new THREE.IcosahedronGeometry(1, 1);
    const blobs = o.pine ? 0 : 4;
    if (o.pine) {
      for (let i = 0; i < 3; i++) {
        const cone = new THREE.Mesh(new THREE.ConeGeometry((3.6 - i * 0.9) * s, 3.4 * s, 8), leafMat);
        cone.position.y = trunkH * 0.7 + i * 2.2 * s + 1.4 * s;
        cone.castShadow = true;
        g.add(cone);
      }
    }
    for (let i = 0; i < blobs; i++) {
      const m = new THREE.Mesh(leaves, leafMat);
      const r = (i === 0 ? 3.2 : rand(1.9, 2.5)) * s;
      m.scale.set(r, r * 0.9, r);
      const a = (i / 3) * TAU + rand(0, 1);
      m.position.set(i === 0 ? 0 : Math.cos(a) * 2 * s, trunkH + (i === 0 ? 1.4 : rand(0, 1.6)) * s, i === 0 ? 0 : Math.sin(a) * 2 * s);
      m.castShadow = true;
      m.receiveShadow = true;
      g.add(m);
    }
    g.position.set(x, y, z);
    g.rotation.y = rand(0, TAU);
    parent.add(g);
    if (o.collide !== false) World.addCyl(x, z, 0.8 * s, y, y + trunkH, {});
    return g;
  },

  flowers(parent, x, y, z, n = 6, spread = 3) {
    const colors = ['#ff6fb5', '#ffd23f', '#ffffff', '#c3a6ff', '#ff8c1a'];
    const stem = Mat.get('smooth', '#3e9d42');
    for (let i = 0; i < n; i++) {
      const fx = x + rand(-spread, spread);
      const fz = z + rand(-spread, spread);
      const s = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.8, 0.15), stem);
      s.position.set(fx, y + 0.4, fz);
      parent.add(s);
      const head = new THREE.Mesh(new THREE.IcosahedronGeometry(0.35, 0), Mat.get('smooth', pick(colors)));
      head.position.set(fx, y + 0.9, fz);
      head.castShadow = true;
      parent.add(head);
    }
  },

  rock(parent, x, y, z, s = 1, collide = true) {
    const m = new THREE.Mesh(new THREE.DodecahedronGeometry(1.6 * s, 0), Mat.get('stone', '#9aa0a8'));
    m.position.set(x, y + 0.6 * s, z);
    m.rotation.set(rand(0, 1), rand(0, TAU), rand(0, 1));
    m.scale.y = 0.7;
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    if (collide) World.addCyl(x, z, 1.4 * s, y, y + 1.6 * s, {});
    return m;
  },

  lamp(parent, x, y, z) {
    part(parent, x, y + 4, z, 0.5, 8, 0.5, { color: '#2b2f3a', mat: 'metal', collide: false });
    World.addCyl(x, z, 0.4, y, y + 8, {});
    const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.75, 12, 8), new THREE.MeshBasicMaterial({ color: 0xfff1b8, toneMapped: false }));
    bulb.position.set(x, y + 8.6, z);
    parent.add(bulb);
    return bulb;
  },

  // Плавучий островок-декорация вдалеке.
  islet(parent, x, y, z, r) {
    const top = new THREE.Mesh(cylGeo(r, 1.5, 12), [Mat.get('grass', '#ffffff')[0], Mat.get('grass', '#ffffff')[2], Mat.get('dirt', '#ffffff')]);
    top.position.set(x, y, z);
    top.receiveShadow = true;
    parent.add(top);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(r, r * 1.6, 12), Mat.get('dirt', '#ffffff'));
    cone.rotation.x = Math.PI;
    cone.position.set(x, y - 0.75 - r * 0.8, z);
    parent.add(cone);
    if (r > 6) this.tree(parent, x + rand(-r / 3, r / 3), y + 0.75, z + rand(-r / 3, r / 3), rand(0.8, 1.2), { collide: false });
  },
};

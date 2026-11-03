// Offline preview renderer: draws the exported cutscene (tools/export.luau)
// with three.js, approximating the Roblox look (parts, SurfaceGui paintings,
// lights, particles, atmosphere, post effects, ScreenGui overlay, subtitles).
// It is a preview only: the real look is what Roblox Studio renders.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { BokehPass } from 'three/addons/postprocessing/BokehPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const PI = Math.PI;
const st = {};
const arr = x => (Array.isArray(x) ? x : []);

function srgb(c) { return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace); }
function cfMatrix(cf) {
  const m = new THREE.Matrix4();
  m.set(cf[3], cf[4], cf[5], cf[0], cf[6], cf[7], cf[8], cf[1], cf[9], cf[10], cf[11], cf[2], 0, 0, 0, 1);
  return m;
}
function lum(c) { return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }

// --- unit geometries -----------------------------------------------------------
function wedgeGeometry() {
  const A = x => [x, -0.5, -0.5], B = x => [x, -0.5, 0.5], C = x => [x, 0.5, 0.5];
  const L = -0.5, R = 0.5;
  const quads = [[A(L), B(L), B(R), A(R)], [B(L), C(L), C(R), B(R)], [A(L), A(R), C(R), C(L)]];
  const tris = [[A(L), B(L), C(L)], [A(R), C(R), B(R)]];
  for (const q of quads) { tris.push([q[0], q[1], q[2]]); tris.push([q[0], q[2], q[3]]); }
  const centroid = new THREE.Vector3(0, -1 / 6, 1 / 6);
  const pos = [];
  for (const t of tris) {
    const a = new THREE.Vector3(...t[0]), b = new THREE.Vector3(...t[1]), c = new THREE.Vector3(...t[2]);
    const n = new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(c, a));
    const mid = new THREE.Vector3().add(a).add(b).add(c).multiplyScalar(1 / 3);
    if (n.dot(mid.sub(centroid)) < 0) pos.push(...t[0], ...t[2], ...t[1]);
    else pos.push(...t[0], ...t[1], ...t[2]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}
const GEO = {
  Block: new THREE.BoxGeometry(1, 1, 1),
  Wedge: wedgeGeometry(),
  Ball: new THREE.SphereGeometry(0.5, 32, 20),
  Ellipsoid: new THREE.SphereGeometry(0.5, 32, 20),
  Cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 32).rotateZ(-PI / 2),
};
function partScale(size, shape) {
  const [x, y, z] = size;
  if (shape === 'Ball') { const d = Math.min(x, y, z); return new THREE.Vector3(d, d, d); }
  if (shape === 'Cylinder') { const d = Math.min(y, z); return new THREE.Vector3(x, d, d); }
  return new THREE.Vector3(x, y, z);
}
const MAT = {
  SmoothPlastic: { roughness: 0.6, metalness: 0 },
  Plastic: { roughness: 0.72, metalness: 0 },
  Fabric: { roughness: 0.96, metalness: 0 },
  Snow: { roughness: 0.92, metalness: 0 },
  Ice: { roughness: 0.25, metalness: 0.05 },
  Glacier: { roughness: 0.3, metalness: 0.05 },
  Slate: { roughness: 0.9, metalness: 0 },
  Concrete: { roughness: 0.95, metalness: 0 },
  Metal: { roughness: 0.38, metalness: 0.55 },
  Neon: { roughness: 1, metalness: 0 },
  Glass: { roughness: 0.1, metalness: 0 },
};

// --- sky dome ------------------------------------------------------------------------
function skyDome(style) {
  const clouds = style.clouds;
  const atm = style.atmosphere;
  const uniforms = {
    topCol: { value: clouds ? srgb([0.30, 0.35, 0.47]) : srgb([0.24, 0.56, 0.94]) },
    horCol: { value: atm ? srgb(atm.Color) : srgb([0.81, 0.9, 1]) },
    cloudCol: { value: clouds ? srgb(clouds.Color) : srgb([1, 1, 1]) },
    cover: { value: clouds ? clouds.Cover : 0.35 },
    overcast: { value: clouds ? 1 : 0 },
    dim: { value: 1 },
  };
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false, uniforms,
    vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `
      varying vec3 vDir; uniform vec3 topCol, horCol, cloudCol; uniform float cover, overcast, dim;
      float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
      float noise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
        return mix(mix(hash(i),hash(i+vec2(1,0)),u.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x), u.y); }
      float fbm(vec2 p){ float v=0.0, a=0.5; for(int i=0;i<6;i++){ v+=a*noise(p); p*=2.03; a*=0.5; } return v; }
      void main(){
        float h = clamp(vDir.y, -0.2, 1.0);
        vec3 col = mix(horCol, topCol, smoothstep(0.0, 0.55, h));
        if (h > 0.0) {
          vec2 uv = vDir.xz / (vDir.y + 0.12) * 1.6;
          float n = fbm(uv + vec2(3.1, 1.7));
          float c = smoothstep(1.0 - cover - 0.05, 1.0 - cover + 0.35, n);
          vec3 cc = mix(cloudCol * (overcast > 0.5 ? 0.55 : 0.8), cloudCol * 1.08, fbm(uv * 2.0 + 7.0));
          col = mix(col, cc, c * (overcast > 0.5 ? 0.95 : 0.85));
          col = mix(col, horCol, 1.0 - smoothstep(0.0, 0.18, h));
        }
        gl_FragColor = vec4(col * dim, 1.0);
        #include <colorspace_fragment>
      }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(5000, 48, 24), mat);
  m.frustumCulled = false;
  return m;
}

// --- SurfaceGui textures (re-drawn when the visible groups change) -------------------
function guiCanvas(gui) {
  const cv = document.createElement('canvas');
  cv.width = Math.ceil(gui.canvas[0]);
  cv.height = Math.ceil(gui.canvas[1]);
  return cv;
}
function drawGui(entry, visSet) {
  const gui = entry.p.gui;
  const ctx = entry.cv.getContext('2d');
  ctx.clearRect(0, 0, entry.cv.width, entry.cv.height);
  const elems = gui.elems.filter(e => !e.grp || visSet.has(e.grp));
  RbxPaint.drawElems(ctx, elems);
  entry.tex.needsUpdate = true;
}
function guiKey(entry, visSet) {
  if (!entry.groups.length) return '';
  return entry.groups.filter(g => visSet.has(g)).join('|');
}

function lightFactor(n) {
  const L = st.light;
  return L.amb + L.sun * Math.max(0, n.dot(L.sunDir));
}

// --- post shaders --------------------------------------------------------------------
const OutlineShader = {
  uniforms: { tDiffuse: { value: null }, tMask: { value: null }, color: { value: new THREE.Color(0, 0, 0) }, alpha: { value: 1 }, px: { value: new THREE.Vector2() }, radius: { value: 1.5 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse, tMask; uniform vec3 color; uniform float alpha, radius; uniform vec2 px; varying vec2 vUv;
    void main(){
      vec4 base = texture2D(tDiffuse, vUv);
      float m = texture2D(tMask, vUv).r;
      float e = 0.0;
      if (m < 0.5) {
        for (int x=-2; x<=2; x++) for (int y=-2; y<=2; y++) {
          vec2 o = vec2(float(x), float(y));
          if (length(o) <= radius + 0.01) e = max(e, texture2D(tMask, vUv + o*px).r);
        }
      }
      gl_FragColor = vec4(mix(base.rgb, color, e * alpha), base.a);
    }`,
};
const ColorCorrectionShader = {
  uniforms: { tDiffuse: { value: null }, brightness: { value: 0 }, contrast: { value: 0 }, saturation: { value: 0 }, tint: { value: new THREE.Color(1, 1, 1) } },
  vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float brightness, contrast, saturation; uniform vec3 tint; varying vec2 vUv;
    void main(){
      vec4 c = texture2D(tDiffuse, vUv);
      vec3 s = pow(max(c.rgb, 0.0), vec3(1.0/2.2));
      s += brightness;
      s = (s - 0.5) * (1.0 + contrast) + 0.5;
      float l = dot(s, vec3(0.2126, 0.7152, 0.0722));
      s = mix(vec3(l), s, 1.0 + saturation);
      s *= tint;
      gl_FragColor = vec4(pow(max(s, 0.0), vec3(2.2)), c.a);
    }`,
};

// --- particles -------------------------------------------------------------------------
function sparkleTexture() {
  const cv = document.createElement('canvas'); cv.width = cv.height = 64;
  const ctx = cv.getContext('2d');
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.25, 'rgba(255,255,255,0.85)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; return t;
}
const NORMALS = { Top: [0, 1, 0], Bottom: [0, -1, 0], Front: [0, 0, -1], Back: [0, 0, 1], Right: [1, 0, 0], Left: [-1, 0, 0] };
function makeEmitter(em, partIndex) {
  const maxCount = 4000;
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(maxCount * 3), 3));
  geo.setAttribute('aSize', new THREE.Float32BufferAttribute(new Float32Array(maxCount), 1));
  geo.setAttribute('aAlpha', new THREE.Float32BufferAttribute(new Float32Array(maxCount), 1));
  const additive = em.preset.lightEmission > 0.5;
  const mat = new THREE.ShaderMaterial({
    uniforms: { map: { value: st.sparkle }, color: { value: srgb(em.color) }, scale: { value: st.H / 2 }, glow: { value: additive ? 1.8 : 1.0 } },
    vertexShader: `attribute float aSize; attribute float aAlpha; varying float vA; uniform float scale;
      void main(){ vec4 mv = modelViewMatrix * vec4(position,1.0); gl_Position = projectionMatrix * mv;
        gl_PointSize = clamp(aSize * scale * projectionMatrix[1][1] / -mv.z, 0.0, 256.0); vA = aAlpha; }`,
    fragmentShader: `uniform sampler2D map; uniform vec3 color; uniform float glow; varying float vA;
      void main(){ vec4 t = texture2D(map, gl_PointCoord); gl_FragColor = vec4(color * glow, t.a * vA);
      #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  });
  const pts = new THREE.Points(geo, mat);
  pts.frustumCulled = false;
  return { em, pts, maxCount, partIndex };
}
// deterministic simulation from the frame history (spawn positions follow the emitter part)
function updateEmitter(s, fi) {
  const data = st.data, em = s.em, P = em.preset;
  const pos = s.pts.geometry.attributes.position.array;
  const asz = s.pts.geometry.attributes.aSize.array;
  const aal = s.pts.geometry.attributes.aAlpha.array;
  const lifeMax = P.lifetime[1];
  const fps = data.fps;
  const now = data.frames[fi].t;
  let k = 0;
  const startF = Math.max(0, fi - Math.ceil(lifeMax * fps) - 1);
  const dir0 = new THREE.Vector3(...NORMALS[P.direction]);
  for (let f = startF; f <= fi && k < s.maxCount; f++) {
    const fr = data.frames[f];
    if (!fr) continue;
    const rate = fr.emit ? fr.emit[em.name] || 0 : 0;
    if (rate <= 0) continue;
    const n = Math.floor(rate / fps + ((f * 7919) % 97) / 97);
    const cf = s.partIndex !== undefined ? fr.cfs[s.partIndex] : data.parts[em.part - 1].cf;
    const m = cfMatrix(cf);
    const size = data.parts[em.part - 1].size;
    for (let j = 0; j < n && k < s.maxCount; j++) {
      let seed = (f * 1000003 + j * 7907 + em.name.length * 131) % 2147483647 || 1;
      const rnd = () => (seed = (seed * 48271) % 2147483647) / 2147483647;
      const life = P.lifetime[0] + (P.lifetime[1] - P.lifetime[0]) * rnd();
      const age = now - fr.t;
      if (age < 0 || age > life) continue;
      const lp = new THREE.Vector3((rnd() - 0.5) * size[0], (rnd() - 0.5) * size[1], (rnd() - 0.5) * size[2]).applyMatrix4(m);
      // direction within the spread cone
      const sp = (P.spread * PI) / 180;
      const th = rnd() * 2 * PI, ph = Math.acos(1 - rnd() * (1 - Math.cos(sp)));
      let d = new THREE.Vector3(Math.sin(ph) * Math.cos(th), Math.cos(ph), Math.sin(ph) * Math.sin(th));
      d.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir0));
      d.transformDirection(m);
      const speed = (P.speed[0] + (P.speed[1] - P.speed[0]) * rnd()) * em.speed;
      const drag = P.drag || 0;
      const tt = drag > 0 ? (1 - Math.exp(-drag * age)) / drag : age;
      const p = lp.add(d.multiplyScalar(speed * tt)).add(new THREE.Vector3(...P.accel).multiplyScalar(0.5 * age * age));
      pos[k * 3] = p.x; pos[k * 3 + 1] = p.y; pos[k * 3 + 2] = p.z;
      const u = age / life;
      asz[k] = (P.size[0] + (P.size[1] - P.size[0]) * u) * em.scale;
      const fade = Math.min(1, u / 0.12, (1 - u) / 0.2);
      aal[k] = Math.max(0, fade) * (1 - P.transparency);
      k++;
    }
  }
  for (let i = k; i < s.maxCount; i++) { pos[i * 3 + 1] = -99999; asz[i] = 0; aal[i] = 0; }
  s.pts.geometry.attributes.position.needsUpdate = true;
  s.pts.geometry.attributes.aSize.needsUpdate = true;
  s.pts.geometry.attributes.aAlpha.needsUpdate = true;
  s.pts.geometry.setDrawRange(0, Math.max(1, k));
}

// --- init -------------------------------------------------------------------------------
function init(data, W, H) {
  st.data = data; st.W = W; st.H = H;
  const style = data.style;
  st.sparkle = sparkleTexture();
  const canvas = document.createElement('canvas');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H, false);
  renderer.setPixelRatio(1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.shadowMap.enabled = !!style.lighting.GlobalShadows;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  st.renderer = renderer;

  const scene = new THREE.Scene();
  st.scene = scene;
  const atm = style.atmosphere;
  const sky = style.defaultSky ? skyDome(style) : null;
  if (sky) scene.add(sky);
  st.sky = sky;
  scene.background = atm ? srgb(atm.Color) : srgb([0.6, 0.65, 0.8]);
  if (atm) {
    const fc = srgb(atm.Color).lerp(srgb(atm.Decay), 0.25);
    scene.fog = new THREE.FogExp2(fc, atm.Density * 0.0068 * (0.6 + 0.25 * atm.Haze));
    st.fogBase = scene.fog.density;
  }

  const L = style.lighting;
  const soft = L.LightingStyle === 'Soft';
  const amb = (soft ? 0.95 : 0.72) * Math.min(1.1, lum(L.OutdoorAmbient) / 0.7) * (L.GlobalShadows ? 0.9 : 1);
  const sun = L.Brightness * (soft ? 0.22 : 0.3) * (style.clouds ? 0.45 : 1);
  const sunDir = new THREE.Vector3(-0.45, 0.78, 0.43).normalize();
  st.light = { amb, sun, sunDir };
  scene.add(new THREE.HemisphereLight(srgb(L.OutdoorAmbient).lerp(new THREE.Color(1, 1, 1), 0.35), srgb(L.OutdoorAmbient).multiplyScalar(0.7), amb * PI));
  const dl = new THREE.DirectionalLight(new THREE.Color(1, 0.97, 0.92), sun * PI);
  dl.position.copy(sunDir).multiplyScalar(300);
  scene.add(dl); scene.add(dl.target);
  st.sun = dl;
  if (renderer.shadowMap.enabled) {
    dl.castShadow = true;
    dl.shadow.mapSize.set(2048, 2048);
    const c = dl.shadow.camera; c.left = -60; c.right = 60; c.top = 60; c.bottom = -60; c.near = 10; c.far = 700;
    dl.shadow.radius = 2 + L.ShadowSoftness * 6;
    dl.shadow.bias = -0.0008;
  }

  // parts
  st.entries = {};
  st.outlineMeshes = [];
  const outlineModels = new Set(arr(data.models).filter(m => m.outline).map(m => m.name));
  const matCache = new Map();
  st.partIndex = {};
  arr(data.dynamicIds).forEach((id, i) => { st.partIndex[id] = i; });
  for (const p of data.parts) {
    const entry = { p, mesh: null, gui: null, cv: null, tex: null, groups: [], key: null, size: p.size, transparency: p.transparency, color: p.color, matShared: true };
    if (p.transparency < 0.999 || p.dynamic) {
      const key = p.color.join(',') + p.material + p.transparency;
      let mat = matCache.get(key);
      if (!mat) {
        const mp = MAT[p.material] || MAT.SmoothPlastic;
        mat = new THREE.MeshStandardMaterial({ color: srgb(p.color), roughness: mp.roughness, metalness: mp.metalness });
        if (p.material === 'Neon') { mat.emissive = srgb(p.color); mat.emissiveIntensity = 2.2; mat.color.setScalar(0); }
        if (p.material === 'Glass' || p.material === 'Ice') { mat.transparent = true; mat.opacity = 0.75; }
        if (p.transparency > 0) { mat.transparent = true; mat.opacity = 1 - p.transparency; mat.depthWrite = p.transparency < 0.5; }
        matCache.set(key, mat);
      }
      const mesh = new THREE.Mesh(GEO[p.shape] || GEO.Block, mat);
      mesh.matrixAutoUpdate = false;
      mesh.castShadow = p.castShadow && p.material !== 'Neon'; mesh.receiveShadow = p.material !== 'Neon';
      mesh.visible = p.transparency < 0.999;
      scene.add(mesh);
      entry.mesh = mesh;
      if (outlineModels.has(p.model)) st.outlineMeshes.push(mesh);
    }
    if (p.gui) {
      if (!Array.isArray(p.gui.elems)) p.gui.elems = []; // empty Luau table -> {}
      entry.cv = guiCanvas(p.gui);
      entry.tex = new THREE.CanvasTexture(entry.cv);
      entry.tex.colorSpace = THREE.SRGBColorSpace;
      entry.tex.anisotropy = 8;
      entry.groups = [...new Set(p.gui.elems.filter(e => e.grp).map(e => e.grp))];
      const mat = new THREE.MeshBasicMaterial({ map: entry.tex, transparent: true, depthWrite: false, side: THREE.FrontSide });
      const plane = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), mat);
      plane.matrixAutoUpdate = false;
      plane.renderOrder = 1;
      scene.add(plane);
      entry.gui = plane;
      drawGui(entry, new Set());
      entry.key = '';
    }
    st.entries[p.id] = entry;
    applyPart(entry, cfMatrix(p.cf));
  }
  // lights
  st.lights = arr(data.lights).map(l => {
    const light = l.kind === 'Spot' ? new THREE.SpotLight(srgb(l.color), 0, l.range, ((l.angle || 60) * PI) / 180, 0.4, 1.6) : new THREE.PointLight(srgb(l.color), 0, l.range, 1.6);
    light.visible = false;
    scene.add(light);
    if (light.target) scene.add(light.target);
    return { l, light };
  });
  // particles
  st.emitters = arr(data.emitters).map(em => {
    const e = makeEmitter(em, st.partIndex[em.part]);
    scene.add(e.pts);
    return e;
  });

  const camera = new THREE.PerspectiveCamera(30, W / H, 0.1, 12000);
  camera.matrixAutoUpdate = false;
  st.camera = camera;

  const composer = new EffectComposer(renderer);
  composer.setPixelRatio(1);
  composer.setSize(W, H);
  composer.addPass(new RenderPass(scene, camera));
  if (style.outline) {
    st.maskRT = new THREE.WebGLRenderTarget(W, H, { depthBuffer: true });
    const op = new ShaderPass(OutlineShader);
    op.uniforms.tMask.value = st.maskRT.texture;
    op.uniforms.color.value = srgb(style.outline.color);
    op.uniforms.alpha.value = 1 - style.outline.transparency;
    op.uniforms.px.value.set(1 / W, 1 / H);
    op.uniforms.radius.value = Math.max(1, (H / 720) * 1.6);
    composer.addPass(op);
  }
  if (style.post.dof) {
    const bokeh = new BokehPass(scene, camera, { focus: 100, aperture: 0.00025, maxblur: 0.008 });
    const orig = bokeh.render.bind(bokeh);
    bokeh.render = (r, wb, rb, dt, mask) => {
      const hidden = [];
      scene.traverse(o => {
        if (o.visible && ((o.isMesh && o.material && o.material.transparent) || o.isPoints)) { hidden.push(o); o.visible = false; }
      });
      orig(r, wb, rb, dt, mask);
      for (const o of hidden) o.visible = true;
    };
    st.bokeh = bokeh;
    composer.addPass(bokeh);
  }
  if (style.post.bloom) {
    const b = style.post.bloom;
    st.bloomPass = new UnrealBloomPass(new THREE.Vector2(W, H), b.Intensity * 0.6, 0.55, Math.min(0.92, b.Threshold * 0.6));
    st.bloomBase = b.Intensity * 0.6;
    composer.addPass(st.bloomPass);
  }
  if (style.post.cc) {
    st.cc = new ShaderPass(ColorCorrectionShader);
    composer.addPass(st.cc);
  }
  composer.addPass(new OutputPass());
  st.composer = composer;
  const out = document.getElementById('out');
  out.width = W; out.height = H;
  st.out = out;
}

const tmpS = new THREE.Matrix4(), tmpF = new THREE.Matrix4();
function applyPart(entry, world) {
  const p = entry.p;
  if (entry.mesh) {
    const sc = partScale(entry.size, p.shape);
    entry.mesh.matrix.copy(world).multiply(tmpS.makeScale(sc.x, sc.y, sc.z));
    entry.mesh.matrixWorldNeedsUpdate = true;
  }
  if (entry.gui) {
    const [sx, sy, sz] = entry.size;
    tmpF.makeRotationY(PI).setPosition(0, 0, -sz / 2 - 0.004);
    entry.gui.matrix.copy(world).multiply(tmpF).multiply(tmpS.makeScale(sx, sy, 1));
    entry.gui.matrixWorldNeedsUpdate = true;
    const li = p.gui.lightInfluence;
    if (li > 0) {
      const n = new THREE.Vector3(0, 0, -1).transformDirection(world);
      entry.gui.material.color.setScalar(1 + (lightFactor(n) - 1) * li);
    }
  }
}
function applyProps(entry, pr) {
  if (!entry.mesh) return;
  if (pr.s) entry.size = pr.s;
  const changed = (pr.t !== undefined && pr.t !== entry.transparency) || (pr.c && pr.c.join() !== entry.color.join());
  if (!changed) return;
  if (entry.matShared) { entry.mesh.material = entry.mesh.material.clone(); entry.matShared = false; }
  const m = entry.mesh.material;
  if (pr.t !== undefined) {
    entry.transparency = pr.t;
    m.transparent = pr.t > 0;
    m.opacity = 1 - pr.t;
    m.depthWrite = pr.t < 0.5;
    entry.mesh.visible = pr.t < 0.999;
  }
  if (pr.c) {
    entry.color = pr.c;
    if (entry.p.material === 'Neon') m.emissive = srgb(pr.c);
    else m.color = srgb(pr.c);
  }
  m.needsUpdate = true;
}

function renderMask() {
  const r = st.renderer, scene = st.scene;
  const saved = new Map();
  const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
  const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
  scene.traverse(o => { if (o.isMesh || o.isPoints) saved.set(o, { m: o.material, v: o.visible }); });
  const outline = new Set(st.outlineMeshes);
  const fog = scene.fog, bg = scene.background;
  scene.fog = null; scene.background = new THREE.Color(0, 0, 0);
  for (const [o] of saved) {
    if (o.isPoints || (o.material && o.material.transparent) || o === st.sky) o.visible = false;
    else o.material = outline.has(o) ? white : black;
  }
  r.setRenderTarget(st.maskRT); r.clear(); r.render(scene, st.camera); r.setRenderTarget(null);
  for (const [o, s] of saved) { o.material = s.m; o.visible = s.v; }
  scene.fog = fog; scene.background = bg;
}

function wrapText(ctx, text, maxW) {
  const words = text.split(' ');
  const lines = [];
  let cur = '';
  for (const w of words) {
    const t = cur ? cur + ' ' + w : w;
    if (ctx.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t;
  }
  if (cur) lines.push(cur);
  return lines;
}

function renderFrame(i) {
  const data = st.data;
  const fr = data.frames[i];
  const cam = st.camera;
  cam.fov = fr.fov;
  cam.updateProjectionMatrix();
  cam.matrix.copy(cfMatrix(fr.camera));
  cam.matrixWorldNeedsUpdate = true;
  cam.updateMatrixWorld(true);
  const props = fr.props || {};
  data.dynamicIds.forEach((id, k) => {
    const e = st.entries[id];
    const pr = props[String(id)];
    if (pr) applyProps(e, pr);
    applyPart(e, cfMatrix(fr.cfs[k]));
  });
  for (const id in props) {
    if (!(id in st.partIndex)) { const e = st.entries[id]; applyProps(e, props[id]); applyPart(e, cfMatrix(e.p.cf)); }
  }
  // GUI group visibility
  const visSet = new Set(arr(fr.vis));
  for (const id in st.entries) {
    const e = st.entries[id];
    if (!e.gui || !e.groups.length) continue;
    const key = guiKey(e, visSet);
    if (key !== e.key) { drawGui(e, visSet); e.key = key; }
  }
  // lights
  for (const L of st.lights) {
    const s = fr.lights ? fr.lights[L.l.name] : null;
    if (s && s.b > 0) {
      const idx = st.partIndex[L.l.part];
      const m = idx !== undefined ? cfMatrix(fr.cfs[idx]) : cfMatrix(data.parts[L.l.part - 1].cf);
      L.light.position.setFromMatrixPosition(m);
      if (L.light.target) {
        const n = NORMALS[L.l.face || 'Front'];
        L.light.target.position.copy(new THREE.Vector3(...n).applyMatrix4(m));
        L.light.target.updateMatrixWorld();
      }
      L.light.visible = true;
      L.light.intensity = s.b * 14;
      if (s.c) L.light.color = srgb(s.c);
      L.light.distance = s.r || L.l.range;
    } else L.light.visible = false;
  }
  for (const e of st.emitters) updateEmitter(e, i);
  if (st.sky) st.sky.position.copy(new THREE.Vector3().setFromMatrixPosition(cam.matrix));
  st.scene.updateMatrixWorld(true);
  if (st.bokeh) {
    st.bokeh.uniforms.focus.value = fr.focus;
    st.bokeh.uniforms.aperture.value = 0.00025 * (data.style.post.dof.FarIntensity / 0.3) * (fr.dof ?? 1);
  }
  if (st.bloomPass) st.bloomPass.strength = st.bloomBase * (fr.bloom ?? 1);
  if (st.scene.fog && st.fogBase) st.scene.fog.density = st.fogBase * (fr.fog ?? 1);
  if (st.cc) {
    const g = fr.grade || { brightness: data.style.post.cc.Brightness, contrast: data.style.post.cc.Contrast, saturation: data.style.post.cc.Saturation, tint: data.style.post.cc.TintColor };
    st.cc.uniforms.brightness.value = g.brightness;
    st.cc.uniforms.contrast.value = g.contrast;
    st.cc.uniforms.saturation.value = g.saturation;
    st.cc.uniforms.tint.value = new THREE.Color(...g.tint);
  }
  if (st.maskRT) renderMask();
  st.composer.render();

  // 2D composite: 3D + vignette + overlay groups + flash + subtitles
  const ctx = st.out.getContext('2d');
  const W = st.W, H = st.H;
  ctx.drawImage(st.renderer.domElement, 0, 0, W, H);
  const v = data.style.vignette;
  if (v > 0) {
    const col = a => `rgba(5,8,18,${a})`;
    const edge = (x0, y0, x1, y1, rx, ry, rw, rh) => {
      const g = ctx.createLinearGradient(x0, y0, x1, y1);
      g.addColorStop(0, col(v)); g.addColorStop(1, col(0));
      ctx.fillStyle = g; ctx.fillRect(rx, ry, rw, rh);
    };
    edge(0, 0, W * 0.22, 0, 0, 0, W * 0.22, H);
    edge(W, 0, W * 0.78, 0, W * 0.78, 0, W * 0.22, H);
    edge(0, 0, 0, H * 0.3, 0, 0, W, H * 0.3);
    edge(0, H, 0, H * 0.7, 0, H * 0.7, W, H * 0.3);
  }
  const alpha = fr.alpha || {};
  const visArr = new Set(arr(fr.vis));
  const overlay = arr(data.overlay).filter(e => {
    if (!e.grp) return true;
    const a = alpha[e.grp] ?? (visArr.has(e.grp) ? 1 : 0);
    return a > 0.001;
  }).map(e => {
    if (!e.grp) return e;
    const a = alpha[e.grp] ?? 1;
    return Object.assign({}, e, { a: 1 - (1 - e.a) * a });
  });
  ctx.save();
  ctx.scale(W / 1113, H / 626);
  RbxPaint.drawElems(ctx, overlay);
  ctx.restore();
  if (fr.flash && fr.flash.a > 0) {
    ctx.fillStyle = RbxPaint.css(fr.flash.c, fr.flash.a);
    ctx.fillRect(0, 0, W, H);
  }
  if (fr.sub) {
    const fs = Math.round(H * 0.042);
    ctx.font = `600 ${fs}px "DejaVu Sans", Arial, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    const lines = wrapText(ctx, fr.sub, W * 0.7);
    lines.forEach((ln, li) => {
      const y = H * 0.94 - (lines.length - 1 - li) * fs * 1.15;
      ctx.lineWidth = Math.max(2, fs * 0.16);
      ctx.strokeStyle = 'rgba(0,0,0,0.9)';
      ctx.lineJoin = 'round';
      ctx.strokeText(ln, W / 2, y);
      ctx.fillStyle = '#ffffff';
      ctx.fillText(ln, W / 2, y);
    });
  }
  return st.out.toDataURL('image/png');
}

// frames arrive one by one; only a window of recent frames is kept (particles need history)
function pushFrame(i, fr) {
  st.data.frames[i] = fr;
  const drop = i - 420;
  if (drop >= 0) st.data.frames[drop] = undefined;
}

window.Preview = { init, renderFrame, pushFrame, ready: true };

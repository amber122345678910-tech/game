// Offline preview renderer: draws the exported cutscene (tools/export.luau)
// with three.js, approximating the Roblox look (parts, SurfaceGui paintings,
// lighting, atmosphere, outlines, snow, post effects, ScreenGui overlay).
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

function partScale(p) {
  const [x, y, z] = p.size;
  if (p.shape === 'Ball') { const d = Math.min(x, y, z); return new THREE.Vector3(d, d, d); }
  if (p.shape === 'Cylinder') { const d = Math.min(y, z); return new THREE.Vector3(x, d, d); }
  return new THREE.Vector3(x, y, z);
}

const MAT = {
  SmoothPlastic: { roughness: 0.6, metalness: 0 },
  Plastic: { roughness: 0.72, metalness: 0 },
  Fabric: { roughness: 0.96, metalness: 0 },
  Snow: { roughness: 0.92, metalness: 0 },
  Metal: { roughness: 0.38, metalness: 0.55 },
  Neon: { roughness: 1, metalness: 0 },
};

// --- sky dome -----------------------------------------------------------------------
function skyDome(style) {
  const clouds = style.clouds;
  const atm = style.atmosphere;
  const uniforms = {
    topCol: { value: clouds ? srgb([0.30, 0.35, 0.47]) : srgb([0.24, 0.56, 0.94]) },
    horCol: { value: atm ? srgb(atm.Color) : srgb([0.81, 0.9, 1]) },
    cloudCol: { value: clouds ? srgb(clouds.Color) : srgb([1, 1, 1]) },
    cover: { value: clouds ? clouds.Cover : 0.35 },
    overcast: { value: clouds ? 1 : 0 },
  };
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false, uniforms,
    vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `
      varying vec3 vDir; uniform vec3 topCol, horCol, cloudCol; uniform float cover, overcast;
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
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(5000, 48, 24), mat);
  m.frustumCulled = false;
  return m;
}

// --- SurfaceGui planes ---------------------------------------------------------------
function guiTexture(gui) {
  const cv = document.createElement('canvas');
  cv.width = Math.ceil(gui.canvas[0]);
  cv.height = Math.ceil(gui.canvas[1]);
  const ctx = cv.getContext('2d');
  RbxPaint.drawElems(ctx, gui.elems);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  tex.generateMipmaps = true;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  return tex;
}

// light factor seen by a plane facing direction n (approximates SurfaceGui.LightInfluence)
function lightFactor(n) {
  const L = st.light;
  const ndl = Math.max(0, n.dot(L.sunDir));
  return L.amb + L.sun * ndl;
}

// --- outlines (Roblox Highlight approximation) ------------------------------------
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
      vec3 s = pow(max(c.rgb, 0.0), vec3(1.0/2.2));      // work in display space like Roblox's grading
      s += brightness;
      s = (s - 0.5) * (1.0 + contrast) + 0.5;
      float l = dot(s, vec3(0.2126, 0.7152, 0.0722));
      s = mix(vec3(l), s, 1.0 + saturation);
      s *= tint;
      gl_FragColor = vec4(pow(max(s, 0.0), vec3(2.2)), c.a);
    }`,
};

// --- snow ----------------------------------------------------------------------------
function snowTexture() {
  const cv = document.createElement('canvas'); cv.width = cv.height = 64;
  const ctx = cv.getContext('2d');
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.45, 'rgba(255,255,255,0.8)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function makeSnow(em) {
  // deterministic particle list covering t in [-life, 4]
  let seed = 1234567;
  const rnd = () => (seed = (seed * 48271) % 2147483647) / 2147483647;
  const life = em.lifetime[1];
  const count = Math.ceil(em.rate * (life + 4));
  const parts = [];
  for (let i = 0; i < count; i++) {
    parts.push({
      t0: -life + i / em.rate, life: em.lifetime[0] + (em.lifetime[1] - em.lifetime[0]) * rnd(),
      p: [(rnd() - 0.5) * em.size[0], (rnd() - 0.5) * em.size[1], (rnd() - 0.5) * em.size[2]],
      v: em.speed[0] + (em.speed[1] - em.speed[0]) * rnd(), sx: (rnd() - 0.5) * 0.6, sz: (rnd() - 0.5) * 0.6,
      size: em.sizeRange[0] + (em.sizeRange[1] - em.sizeRange[0]) * rnd(),
    });
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(count * 3), 3));
  const mat = new THREE.PointsMaterial({ map: snowTexture(), size: (em.sizeRange[0] + em.sizeRange[1]) / 2, sizeAttenuation: true, transparent: true, opacity: 1 - em.transparency, depthWrite: false, color: srgb(em.color) });
  const pts = new THREE.Points(geo, mat);
  pts.frustumCulled = false;
  return { em, parts, pts, m: cfMatrix(em.cf) };
}
function updateSnow(s, t) {
  const pos = s.pts.geometry.attributes.position.array;
  const v = new THREE.Vector3();
  let k = 0;
  for (const p of s.parts) {
    const age = t - p.t0;
    if (age < 0 || age > p.life) { pos[k++] = 0; pos[k++] = -9999; pos[k++] = 0; continue; }
    v.set(p.p[0] + (p.sx + 1.2 * 0.5 * age) * age, p.p[1] - p.v * age - 0.3 * age * age, p.p[2] + p.sz * age);
    v.applyMatrix4(s.m);
    pos[k++] = v.x; pos[k++] = v.y; pos[k++] = v.z;
  }
  s.pts.geometry.attributes.position.needsUpdate = true;
}

// --- init ---------------------------------------------------------------------------
function init(data, W, H) {
  st.data = data; st.W = W; st.H = H;
  const style = data.style;
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
  }

  // lighting (heuristic match of Roblox Soft / Realistic styles)
  const L = style.lighting;
  const soft = L.LightingStyle === 'Soft';
  const amb = (soft ? 0.95 : 0.72) * Math.min(1.1, lum(L.OutdoorAmbient) / 0.7) * (L.GlobalShadows ? 0.9 : 1);
  const sun = L.Brightness * (soft ? 0.22 : 0.3) * (style.clouds ? 0.45 : 1);
  const sunDir = new THREE.Vector3(-0.45, 0.78, 0.43).normalize();
  st.light = { amb, sun, sunDir };
  const hemi = new THREE.HemisphereLight(srgb(L.OutdoorAmbient).lerp(new THREE.Color(1, 1, 1), 0.35), srgb(L.OutdoorAmbient).multiplyScalar(0.7), amb * PI);
  scene.add(hemi);
  const dl = new THREE.DirectionalLight(new THREE.Color(1, 0.97, 0.92), sun * PI);
  dl.position.copy(sunDir).multiplyScalar(300).add(new THREE.Vector3(0, 0, -120));
  dl.target.position.set(0, 0, -120);
  scene.add(dl); scene.add(dl.target);
  if (renderer.shadowMap.enabled) {
    dl.castShadow = true;
    dl.shadow.mapSize.set(2048, 2048);
    const c = dl.shadow.camera; c.left = -70; c.right = 70; c.top = 70; c.bottom = -70; c.near = 10; c.far = 700;
    dl.shadow.radius = 2 + L.ShadowSoftness * 6;
    dl.shadow.bias = -0.0008;
  }

  // parts
  st.meshes = {}; st.guiMeshes = {}; st.outlineMeshes = [];
  const outlineModels = new Set((Array.isArray(data.models) ? data.models : []).filter(m => m.outline).map(m => m.name));
  const matCache = new Map();
  for (const p of data.parts) {
    const entry = { p, scale: partScale(p), mesh: null, gui: null };
    if (p.transparency < 0.999) {
      const key = p.color.join(',') + p.material + p.transparency;
      let mat = matCache.get(key);
      if (!mat) {
        const mp = MAT[p.material] || MAT.SmoothPlastic;
        mat = new THREE.MeshStandardMaterial({ color: srgb(p.color), roughness: mp.roughness, metalness: mp.metalness });
        if (p.material === 'Neon') { mat.emissive = srgb(p.color); mat.emissiveIntensity = 1.6; }
        if (p.transparency > 0) { mat.transparent = true; mat.opacity = 1 - p.transparency; }
        matCache.set(key, mat);
      }
      const mesh = new THREE.Mesh(GEO[p.shape] || GEO.Block, mat);
      mesh.matrixAutoUpdate = false;
      mesh.castShadow = p.castShadow; mesh.receiveShadow = true;
      scene.add(mesh);
      entry.mesh = mesh;
      if (outlineModels.has(p.model)) st.outlineMeshes.push(mesh);
    }
    if (p.gui) {
      const tex = guiTexture(p.gui);
      const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, side: THREE.FrontSide });
      const plane = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), mat);
      plane.matrixAutoUpdate = false;
      plane.renderOrder = 1;
      scene.add(plane);
      entry.gui = plane;
    }
    st.meshes[p.id] = entry;
    applyPart(entry, cfMatrix(p.cf));
  }
  st.snow = (Array.isArray(data.emitters) ? data.emitters : []).map(makeSnow);
  for (const s of st.snow) scene.add(s.pts);

  const camera = new THREE.PerspectiveCamera(30, W / H, 0.1, 12000);
  camera.matrixAutoUpdate = false;
  st.camera = camera;

  // post chain
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
    op.uniforms.radius.value = Math.max(1, H / 720 * 1.6);
    composer.addPass(op);
  }
  if (style.post.dof) {
    const bokeh = new BokehPass(scene, camera, { focus: 100, aperture: 0.00025 * style.post.dof.FarIntensity / 0.3, maxblur: 0.008 });
    // Roblox's depth of field only sees opaque geometry: hide transparent
    // plates (SurfaceGui paintings, mist) and particles while the pass
    // renders its depth buffer. The color it blurs comes from the previous pass.
    const orig = bokeh.render.bind(bokeh);
    bokeh.render = (renderer, writeBuffer, readBuffer, dt, mask) => {
      const hidden = [];
      scene.traverse(o => {
        if (o.visible && ((o.isMesh && o.material && o.material.transparent) || o.isPoints)) { hidden.push(o); o.visible = false; }
      });
      orig(renderer, writeBuffer, readBuffer, dt, mask);
      for (const o of hidden) o.visible = true;
    };
    st.bokeh = bokeh;
    composer.addPass(bokeh);
  }
  if (style.post.bloom) {
    const b = style.post.bloom;
    composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), b.Intensity * 0.55, 0.5, Math.min(0.95, b.Threshold * 0.6)));
  }
  if (style.post.cc) {
    const cc = new ShaderPass(ColorCorrectionShader);
    cc.uniforms.brightness.value = style.post.cc.Brightness;
    cc.uniforms.contrast.value = style.post.cc.Contrast;
    cc.uniforms.saturation.value = style.post.cc.Saturation;
    cc.uniforms.tint.value = new THREE.Color(...style.post.cc.TintColor);
    composer.addPass(cc);
  }
  composer.addPass(new OutputPass());
  st.composer = composer;

  // 2D output canvas (3D + ScreenGui overlay)
  const out = document.getElementById('out');
  out.width = W; out.height = H;
  st.out = out;
}

const tmpS = new THREE.Matrix4(), tmpF = new THREE.Matrix4();
function applyPart(entry, world) {
  const p = entry.p;
  if (entry.mesh) {
    entry.mesh.matrix.copy(world).multiply(tmpS.makeScale(entry.scale.x, entry.scale.y, entry.scale.z));
    entry.mesh.matrixWorldNeedsUpdate = true;
  }
  if (entry.gui) {
    // Front face (normal = -Z local); GUI x runs along -X local (viewer's right)
    const [sx, sy, sz] = p.size;
    tmpF.makeRotationY(PI).setPosition(0, 0, -sz / 2 - 0.004);
    entry.gui.matrix.copy(world).multiply(tmpF).multiply(tmpS.makeScale(sx, sy, 1));
    entry.gui.matrixWorldNeedsUpdate = true;
    const li = p.gui.lightInfluence;
    if (li > 0) {
      const n = new THREE.Vector3(0, 0, -1).transformDirection(world);
      const f = lightFactor(n);
      entry.gui.material.color.setScalar(1 + (f - 1) * li);
    }
  }
}

function renderMask() {
  const r = st.renderer, scene = st.scene;
  const saved = new Map();
  const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
  const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
  scene.traverse(o => { if (o.isMesh || o.isPoints) { saved.set(o, { m: o.material, v: o.visible }); } });
  const outline = new Set(st.outlineMeshes);
  const fog = scene.fog, bg = scene.background;
  scene.fog = null; scene.background = new THREE.Color(0, 0, 0);
  for (const [o] of saved) {
    if (o.isPoints || (o.material && o.material.transparent) || o === st.sky) o.visible = false;
    else o.material = outline.has(o) ? white : black;
  }
  r.setRenderTarget(st.maskRT);
  r.clear();
  r.render(scene, st.camera);
  r.setRenderTarget(null);
  for (const [o, s] of saved) { o.material = s.m; o.visible = s.v; }
  scene.fog = fog; scene.background = bg;
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
  data.dynamicIds.forEach((id, k) => applyPart(st.meshes[id], cfMatrix(fr.cfs[k])));
  for (const s of st.snow) updateSnow(s, fr.t);
  if (st.sky) st.sky.position.copy(new THREE.Vector3().setFromMatrixPosition(cam.matrix));
  st.scene.updateMatrixWorld(true);
  if (st.bokeh) {
    st.bokeh.uniforms.focus.value = fr.focus;
    st.bokeh.uniforms.aperture.value = 0.00025 * (data.style.post.dof.FarIntensity / 0.3) * (fr.dof ?? 1);
  }
  if (st.maskRT) renderMask();
  st.composer.render();
  // composite with the ScreenGui overlay
  const ctx = st.out.getContext('2d');
  ctx.drawImage(st.renderer.domElement, 0, 0, st.W, st.H);
  const v = data.style.vignette;
  if (v > 0) {
    const col = a => `rgba(5,8,18,${a})`;
    const edge = (x0, y0, x1, y1, rx, ry, rw, rh) => {
      const g = ctx.createLinearGradient(x0, y0, x1, y1);
      g.addColorStop(0, col(v)); g.addColorStop(1, col(0));
      ctx.fillStyle = g; ctx.fillRect(rx, ry, rw, rh);
    };
    const W = st.W, H = st.H;
    edge(0, 0, W * 0.22, 0, 0, 0, W * 0.22, H);
    edge(W, 0, W * 0.78, 0, W * 0.78, 0, W * 0.22, H);
    edge(0, 0, 0, H * 0.3, 0, 0, W, H * 0.3);
    edge(0, H, 0, H * 0.7, 0, H * 0.7, W, H * 0.3);
  }
  const visible = {};
  for (const k in fr.overlay) if (!fr.overlay[k]) visible[k] = true;
  ctx.save();
  ctx.scale(st.W / 1113, st.H / 626);
  RbxPaint.drawElems(ctx, Array.isArray(data.overlay) ? data.overlay : [], { hide: visible });
  ctx.restore();
  return st.out.toDataURL('image/png');
}

window.Preview = { init, renderFrame, ready: true };

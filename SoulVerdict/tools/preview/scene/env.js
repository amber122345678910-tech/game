// Environment: defaults for env.json, sky dome, sun/ambient lights, fog and reflection probe.
//
// env.json (every key optional; colours are 0..1 sRGB floats like Roblox Color3):
// {
//   "sky":     { "top": [r,g,b], "horizon": [r,g,b], "bottom": [r,g,b] },
//   "sun":     { "dir": [x,y,z], "color": [r,g,b], "intensity": n },
//   "ambient": { "sky": [r,g,b], "ground": [r,g,b], "intensity": n },
//   "fog":     { "color": [r,g,b], "near": n, "far": n },
//   "bloom":   { "strength": n, "radius": n, "threshold": n },
//   "exposure": n, "saturation": n, "contrast": n, "tint": [r,g,b]
// }
// Semantics (so presets can be converted from Roblox Lighting):
//   sun.dir      unit vector FROM the scene TOWARDS the sun (= Lighting:GetSunDirection()).
//   sun.intensity  1 = a white surface facing the sun reflects its full albedo (Roblox Brightness ~2-3
//                  => intensity ~0.9-1.3). ambient.intensity 1 = surfaces get albedo * ambient colour
//                  (ambient.sky ~ OutdoorAmbient, ambient.ground ~ Ambient / ColorShift_Bottom).
//   sky colours and fog.color are reproduced as-is on screen (pre-compensated for tone mapping).
//   fog: linear fog in studs (Atmosphere density -> nearer far). Omit for none.
//   bloom: applies to Neon/ForceField only. strength ~ BloomEffect.Intensity*1.5, radius ~ Size/56,
//          threshold on the neon-only buffer (0..1, 0 = everything that is neon blooms).
//   exposure: linear multiplier (2^ExposureCompensation). saturation/contrast: like
//   ColorCorrectionEffect (-1..1, 0 = neutral). tint: multiplicative like TintColor.
import * as THREE from 'three';

export const DEFAULT_ENV = {
  sky: { top: [0.32, 0.42, 0.58], horizon: [0.74, 0.77, 0.8], bottom: [0.42, 0.42, 0.43] },
  sun: { dir: [0.5, 0.78, -0.62], color: [1.0, 0.96, 0.9], intensity: 1.15 },
  ambient: { sky: [0.66, 0.71, 0.8], ground: [0.42, 0.39, 0.36], intensity: 0.62 },
  fog: null,
  bloom: { strength: 0.85, radius: 0.5, threshold: 0.05 },
  exposure: 1.0,
  saturation: 0.06,
  contrast: 0.06,
  tint: [1, 1, 1],
};

function merge(base, over) {
  if (over === undefined) return base;
  if (over === null) return null;
  if (Array.isArray(base) || typeof base !== 'object' || base === null) return over;
  const out = { ...base };
  for (const k of Object.keys(over)) out[k] = merge(base[k], over[k]);
  return out;
}

export function resolveEnv(json) {
  const env = merge(DEFAULT_ENV, json || {});
  // A fog object without near/far gets sensible values later (scene-size dependent).
  return env;
}

export function srgbToLinear(c) {
  return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
}

// ---------------------------------------------------------------------------------------------
// Inverse of three.js ACESFilmicToneMapping (r170) so a requested display colour survives tone
// mapping: returns the HDR linear colour that maps to `displaySrgb` at the given exposure.
// ---------------------------------------------------------------------------------------------
const IN = new THREE.Matrix3().set(0.59719, 0.35458, 0.04823, 0.076, 0.90834, 0.01566, 0.0284, 0.13383, 0.83777);
const OUT = new THREE.Matrix3().set(1.60475, -0.53108, -0.07367, -0.10208, 1.10813, -0.00605, -0.00327, -0.07276, 1.07602);
const IN_INV = IN.clone().invert();
const OUT_INV = OUT.clone().invert();

function rrtInverse(y) {
  const a1 = 0.0245786, a2 = 0.000090537, b1 = 0.983729, b2 = 0.432951, b3 = 0.238081;
  const A = 1 - y * b1, B = a1 - y * b2, C = -(a2 + y * b3);
  const disc = Math.max(0, B * B - 4 * A * C);
  return (-B + Math.sqrt(disc)) / (2 * A);
}

export function untonemap(displaySrgb, exposure, toneMapped = true) {
  const lin = srgbToLinear(displaySrgb);
  if (!toneMapped) return lin;
  const y = new THREE.Vector3(Math.min(lin.r, 0.97), Math.min(lin.g, 0.97), Math.min(lin.b, 0.97));
  const z = y.applyMatrix3(OUT_INV);
  const v = new THREE.Vector3(rrtInverse(Math.max(z.x, 0)), rrtInverse(Math.max(z.y, 0)), rrtInverse(Math.max(z.z, 0)));
  const x = v.applyMatrix3(IN_INV).multiplyScalar(0.6 / Math.max(exposure, 1e-3));
  return new THREE.Color(Math.max(x.x, 0), Math.max(x.y, 0), Math.max(x.z, 0));
}

// ---------------------------------------------------------------------------------------------
// Sky dome (gradient); rendered without fog, colours pre-compensated for tone mapping.
// ---------------------------------------------------------------------------------------------
export function buildSky(env, radius, exposure) {
  const top = untonemap(env.sky.top, exposure);
  const hor = untonemap(env.sky.horizon, exposure);
  const bot = untonemap(env.sky.bottom, exposure);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
    uniforms: {
      uTop: { value: new THREE.Vector3(top.r, top.g, top.b) },
      uHor: { value: new THREE.Vector3(hor.r, hor.g, hor.b) },
      uBot: { value: new THREE.Vector3(bot.r, bot.g, bot.b) },
    },
    vertexShader: `
      varying vec3 vDir;
      void main() {
        vDir = normalize(position);
        vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        gl_Position = p.xyww;
      }`,
    fragmentShader: `
      uniform vec3 uTop; uniform vec3 uHor; uniform vec3 uBot;
      varying vec3 vDir;
      void main() {
        float t = normalize(vDir).y;
        vec3 c = t > 0.0 ? mix(uHor, uTop, pow(t, 0.55)) : mix(uHor, uBot, pow(-t, 0.45));
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 48, 24), mat);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  mesh.userData.isSky = true;
  return mesh;
}

// Reflection probe from the (linear, non-compensated) sky gradient for PBR reflections.
export function buildEnvMap(renderer, env) {
  const scene = new THREE.Scene();
  const top = srgbToLinear(env.sky.top), hor = srgbToLinear(env.sky.horizon), bot = srgbToLinear(env.sky.bottom);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    uniforms: {
      uTop: { value: new THREE.Vector3(top.r, top.g, top.b) },
      uHor: { value: new THREE.Vector3(hor.r, hor.g, hor.b) },
      uBot: { value: new THREE.Vector3(bot.r, bot.g, bot.b) },
      uSun: { value: new THREE.Vector3(...env.sun.dir).normalize() },
      uSunCol: { value: new THREE.Vector3(...env.sun.color).multiplyScalar(env.sun.intensity * 6) },
    },
    vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `
      uniform vec3 uTop; uniform vec3 uHor; uniform vec3 uBot; uniform vec3 uSun; uniform vec3 uSunCol;
      varying vec3 vDir;
      void main() {
        vec3 d = normalize(vDir);
        float t = d.y;
        vec3 c = t > 0.0 ? mix(uHor, uTop, pow(t, 0.55)) : mix(uHor, uBot * 0.6, pow(-t, 0.45));
        c += uSunCol * pow(max(dot(d, uSun), 0.0), 64.0);
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  scene.add(new THREE.Mesh(new THREE.SphereGeometry(10, 32, 16), mat));
  const pmrem = new THREE.PMREMGenerator(renderer);
  const rt = pmrem.fromScene(scene, 0.02);
  pmrem.dispose();
  return rt.texture;
}

// Sun + hemisphere ambient. `focus` = { center: Vector3, radius } of the shadow region.
export function buildLights(env, focus, shadowMapSize) {
  const out = [];
  const sunDir = new THREE.Vector3(...env.sun.dir).normalize();
  const sun = new THREE.DirectionalLight(srgbToLinear(env.sun.color), env.sun.intensity * Math.PI);
  const dist = focus.radius * 4 + 20;
  sun.position.copy(focus.center).addScaledVector(sunDir, dist);
  sun.target.position.copy(focus.center);
  sun.castShadow = sunDir.y > 0.02;
  const r = focus.radius * 1.15;
  const cam = sun.shadow.camera;
  cam.left = -r; cam.right = r; cam.top = r; cam.bottom = -r;
  cam.near = Math.max(0.1, dist - r * 2); cam.far = dist + r * 2;
  sun.shadow.mapSize.set(shadowMapSize, shadowMapSize);
  const texel = (2 * r) / shadowMapSize;
  sun.shadow.bias = -0.00015;
  sun.shadow.normalBias = texel * 1.5;
  sun.shadow.radius = 2.5;
  out.push(sun, sun.target);
  if (env.ambient && env.ambient.intensity > 0) {
    const hemi = new THREE.HemisphereLight(srgbToLinear(env.ambient.sky), srgbToLinear(env.ambient.ground), env.ambient.intensity * Math.PI);
    out.push(hemi);
  }
  return out;
}

// Roblox PointLight/SpotLight/SurfaceLight -> three lights (brightest `cap` only).
export function buildPartLights(lights, cap) {
  const sorted = [...lights].sort((a, b) => b.brightness * b.range - a.brightness * a.range).slice(0, cap);
  const out = [];
  for (const L of sorted) {
    const color = srgbToLinear(L.color);
    const intensity = L.brightness * Math.PI * 1.6;
    let light;
    if (L.type === 'Point') {
      light = new THREE.PointLight(color, intensity, L.range, 1);
      light.position.set(...L.pos);
    } else {
      const angle = Math.min(Math.max((L.angle || 90) * (Math.PI / 180) * 0.5, 0.05), Math.PI / 2 - 0.01);
      light = new THREE.SpotLight(color, intensity, L.range, angle, 0.45, 1);
      light.position.set(...L.pos);
      light.target.position.set(L.pos[0] + L.dir[0], L.pos[1] + L.dir[1], L.pos[2] + L.dir[2]);
      out.push(light.target);
    }
    light.castShadow = false;
    out.push(light);
  }
  return out;
}

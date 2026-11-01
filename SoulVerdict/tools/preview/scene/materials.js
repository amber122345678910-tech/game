// Roblox Enum.Material -> three.js materials (PBR approximation) + procedural, tileable surface
// textures applied with object-space triplanar mapping in studs (so textures keep their
// real-world density on any primitive, and follow the part when it is posed).
import * as THREE from 'three';

// roughness / metalness / environment reflection strength / procedural texture parameters
// tex: generator name, tile: studs per texture tile, depth: bump height (studs),
// albedo: albedo modulation amount, rough: roughness modulation amount.
const TABLE = {
  SmoothPlastic: { r: 0.42, m: 0, env: 0.45 },
  Plastic: { r: 0.6, m: 0, env: 0.35, tex: 'speckle', tile: 2.0, depth: 0.0015, albedo: 0.035, rough: 0.08 },
  Neon: { neon: true },
  ForceField: { forcefield: true },
  Glass: { glass: true, r: 0.04, m: 0, env: 1.6 },
  Metal: { r: 0.36, m: 0.85, env: 1.0, tex: 'brushed', tile: 2.5, depth: 0.002, albedo: 0.08, rough: 0.25 },
  DiamondPlate: { r: 0.34, m: 0.9, env: 1.0, tex: 'diamond', tile: 1.6, depth: 0.02, albedo: 0.1, rough: 0.2 },
  Foil: { r: 0.22, m: 1.0, env: 1.2, tex: 'crinkle', tile: 2.0, depth: 0.01, albedo: 0.12, rough: 0.3 },
  CorrodedMetal: { r: 0.72, m: 0.55, env: 0.6, tex: 'rust', tile: 4.0, depth: 0.012, albedo: 0.38, rough: 0.35 },
  Fabric: { r: 0.94, m: 0, env: 0.15, tex: 'weave', tile: 0.7, depth: 0.0035, albedo: 0.13, rough: 0.08 },
  Carpet: { r: 1.0, m: 0, env: 0.1, tex: 'fuzz', tile: 1.0, depth: 0.006, albedo: 0.18, rough: 0.0 },
  Leather: { r: 0.58, m: 0, env: 0.35, tex: 'leather', tile: 1.5, depth: 0.004, albedo: 0.1, rough: 0.2 },
  Wood: { r: 0.72, m: 0, env: 0.25, tex: 'wood', tile: 4.0, depth: 0.006, albedo: 0.3, rough: 0.15 },
  WoodPlanks: { r: 0.75, m: 0, env: 0.25, tex: 'planks', tile: 4.0, depth: 0.03, albedo: 0.32, rough: 0.15 },
  Marble: { r: 0.22, m: 0, env: 0.8, tex: 'marble', tile: 6.0, depth: 0.002, albedo: 0.3, rough: 0.1 },
  Granite: { r: 0.62, m: 0, env: 0.4, tex: 'granite', tile: 3.0, depth: 0.004, albedo: 0.35, rough: 0.2 },
  Slate: { r: 0.8, m: 0, env: 0.25, tex: 'slate', tile: 5.0, depth: 0.04, albedo: 0.3, rough: 0.2 },
  Concrete: { r: 0.9, m: 0, env: 0.15, tex: 'concrete', tile: 6.0, depth: 0.01, albedo: 0.2, rough: 0.1 },
  Pavement: { r: 0.88, m: 0, env: 0.15, tex: 'concrete', tile: 4.0, depth: 0.015, albedo: 0.22, rough: 0.1 },
  Asphalt: { r: 0.92, m: 0, env: 0.1, tex: 'granite', tile: 2.0, depth: 0.006, albedo: 0.25, rough: 0.1 },
  Brick: { r: 0.86, m: 0, env: 0.15, tex: 'brick', tile: 4.0, depth: 0.05, albedo: 0.32, rough: 0.1 },
  Cobblestone: { r: 0.84, m: 0, env: 0.2, tex: 'cobble', tile: 5.0, depth: 0.08, albedo: 0.4, rough: 0.15 },
  Pebble: { r: 0.8, m: 0, env: 0.2, tex: 'pebble', tile: 2.5, depth: 0.04, albedo: 0.35, rough: 0.15 },
  Rock: { r: 0.85, m: 0, env: 0.2, tex: 'rock', tile: 6.0, depth: 0.08, albedo: 0.35, rough: 0.15 },
  Basalt: { r: 0.82, m: 0, env: 0.2, tex: 'rock', tile: 5.0, depth: 0.06, albedo: 0.3, rough: 0.15 },
  Limestone: { r: 0.85, m: 0, env: 0.2, tex: 'concrete', tile: 5.0, depth: 0.03, albedo: 0.22, rough: 0.1 },
  Sandstone: { r: 0.88, m: 0, env: 0.15, tex: 'slate', tile: 6.0, depth: 0.03, albedo: 0.22, rough: 0.1 },
  CrackedLava: { r: 0.8, m: 0, env: 0.2, tex: 'lava', tile: 6.0, depth: 0.05, albedo: 0.55, rough: 0.1, emissiveCracks: true },
  Ground: { r: 0.95, m: 0, env: 0.1, tex: 'concrete', tile: 6.0, depth: 0.02, albedo: 0.3, rough: 0.05 },
  Mud: { r: 0.6, m: 0, env: 0.3, tex: 'concrete', tile: 6.0, depth: 0.015, albedo: 0.25, rough: 0.3 },
  Sand: { r: 0.95, m: 0, env: 0.1, tex: 'sand', tile: 2.0, depth: 0.004, albedo: 0.18, rough: 0.05 },
  Salt: { r: 0.8, m: 0, env: 0.3, tex: 'sand', tile: 2.0, depth: 0.004, albedo: 0.12, rough: 0.1 },
  Snow: { r: 0.85, m: 0, env: 0.3, tex: 'snow', tile: 4.0, depth: 0.01, albedo: 0.08, rough: 0.2 },
  Ice: { r: 0.12, m: 0, env: 1.2, tex: 'ice', tile: 6.0, depth: 0.004, albedo: 0.1, rough: 0.15 },
  Glacier: { r: 0.18, m: 0, env: 1.0, tex: 'ice', tile: 8.0, depth: 0.01, albedo: 0.14, rough: 0.15 },
  Grass: { r: 0.95, m: 0, env: 0.1, tex: 'grass', tile: 3.0, depth: 0.012, albedo: 0.3, rough: 0.05 },
  LeafyGrass: { r: 0.95, m: 0, env: 0.1, tex: 'grass', tile: 3.0, depth: 0.02, albedo: 0.38, rough: 0.05 },
  Cardboard: { r: 0.9, m: 0, env: 0.1, tex: 'concrete', tile: 2.0, depth: 0.003, albedo: 0.12, rough: 0.05 },
  Plaster: { r: 0.92, m: 0, env: 0.12, tex: 'concrete', tile: 3.0, depth: 0.004, albedo: 0.1, rough: 0.05 },
  Rubber: { r: 0.72, m: 0, env: 0.2 },
  CeramicTiles: { r: 0.28, m: 0, env: 0.7, tex: 'tiles', tile: 4.0, depth: 0.02, albedo: 0.18, rough: 0.25 },
  ClayRoofTiles: { r: 0.78, m: 0, env: 0.2, tex: 'brick', tile: 3.0, depth: 0.05, albedo: 0.3, rough: 0.1 },
  RoofShingles: { r: 0.85, m: 0, env: 0.15, tex: 'brick', tile: 3.0, depth: 0.04, albedo: 0.32, rough: 0.1 },
};

export const NEON_GAIN = 1.65; // Neon renders unlit at ~1.65x its colour (HDR) before tone mapping

// ------------------------------------------------------------------------------------------------
// Procedural tileable height textures (512^2, values 0..1)
// ------------------------------------------------------------------------------------------------
const N = 512;

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// Periodic value noise with `period` lattice cells per tile.
function makeNoise(period, seed) {
  const r = rng(seed);
  const lat = new Float32Array(period * period);
  for (let i = 0; i < lat.length; i++) lat[i] = r();
  const sm = (t) => t * t * (3 - 2 * t);
  return (u, v) => {
    // u, v in tile units (0..1 wraps)
    const x = (((u % 1) + 1) % 1) * period;
    const y = (((v % 1) + 1) % 1) * period;
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = sm(x - xi), yf = sm(y - yi);
    const x0 = xi % period, y0 = yi % period, x1 = (xi + 1) % period, y1 = (yi + 1) % period;
    const a = lat[y0 * period + x0], b = lat[y0 * period + x1];
    const c = lat[y1 * period + x0], d = lat[y1 * period + x1];
    return (a + (b - a) * xf) + ((c + (d - c) * xf) - (a + (b - a) * xf)) * yf;
  };
}

function makeFbm(base, octaves, seed) {
  const layers = [];
  for (let o = 0; o < octaves; o++) layers.push(makeNoise(base * 2 ** o, seed + o * 101));
  return (u, v) => {
    let sum = 0, amp = 0.5, norm = 0;
    for (const n of layers) {
      sum += n(u, v) * amp;
      norm += amp;
      amp *= 0.5;
    }
    return sum / norm;
  };
}

// Periodic Voronoi: returns [f1, f2] distances (tile units) to the nearest two feature points.
function makeVoronoi(cells, seed) {
  const r = rng(seed);
  const pts = [];
  for (let i = 0; i < cells * cells; i++) pts.push([r(), r()]);
  return (u, v) => {
    const x = (((u % 1) + 1) % 1) * cells, y = (((v % 1) + 1) % 1) * cells;
    const xi = Math.floor(x), yi = Math.floor(y);
    let f1 = 9, f2 = 9;
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        const cx = xi + dx, cy = yi + dy;
        const p = pts[(((cy % cells) + cells) % cells) * cells + (((cx % cells) + cells) % cells)];
        const px = cx + p[0], py = cy + p[1];
        const d = Math.hypot(px - x, py - y) / cells;
        if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d;
      }
    }
    return [f1, f2];
  };
}

const clamp01 = (x) => Math.min(1, Math.max(0, x));
const smooth = (e0, e1, x) => {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
};

const GENERATORS = {
  speckle() {
    const n = makeFbm(32, 3, 7);
    return (u, v) => 0.5 + (n(u, v) - 0.5) * 0.9;
  },
  weave() {
    const threads = 26;
    const fine = makeFbm(64, 2, 3);
    const slub = makeNoise(13, 5);
    return (u, v) => {
      const x = u * threads, y = v * threads;
      const cx = Math.floor(x), cy = Math.floor(y);
      const fx = x - cx, fy = y - cy;
      const over = (cx + cy) % 2 === 0;
      const across = over ? Math.sin(Math.PI * fx) : Math.sin(Math.PI * fy);
      const along = over ? 0.75 + 0.25 * Math.sin(Math.PI * fy) : 0.75 + 0.25 * Math.sin(Math.PI * fx);
      const h = Math.pow(across, 0.7) * along;
      return clamp01(0.08 + h * 0.8 + (fine(u, v) - 0.5) * 0.25 + (slub(u, v) - 0.5) * 0.15);
    };
  },
  fuzz() {
    const n = makeFbm(48, 3, 11);
    return (u, v) => n(u, v);
  },
  leather() {
    const vo = makeVoronoi(18, 17);
    const n = makeFbm(32, 2, 19);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      return clamp01(smooth(0, 0.012, f2 - f1) * 0.8 + n(u, v) * 0.3);
    };
  },
  brushed() {
    const n = makeFbm(4, 2, 23);
    const lines = makeNoise(256, 29);
    return (u, v) => clamp01(0.5 + (lines(u * 0.02, v) - 0.5) * 0.7 + (n(u, v) - 0.5) * 0.4);
  },
  diamond() {
    const k = 6;
    return (u, v) => {
      const x = u * k, y = v * k;
      const a = Math.abs(((x + y) % 1 + 1) % 1 - 0.5), b = Math.abs(((x - y) % 1 + 1) % 1 - 0.5);
      const ridge = Math.max(0, 1 - Math.min(a, b) * 6);
      const cell = (Math.floor(x + y) + Math.floor(x - y)) % 2 === 0;
      return cell ? ridge : 0.15;
    };
  },
  crinkle() {
    const n = makeFbm(8, 4, 31);
    return (u, v) => clamp01(1 - Math.abs(n(u, v) - 0.5) * 3);
  },
  rust() {
    const n = makeFbm(6, 5, 37);
    const spots = makeFbm(12, 3, 41);
    return (u, v) => clamp01(n(u, v) * 0.7 + smooth(0.55, 0.7, spots(u, v)) * 0.5);
  },
  wood() {
    const warp = makeFbm(4, 3, 43);
    const fine = makeNoise(128, 47);
    return (u, v) => {
      const g = Math.sin((v * 22 + warp(u, v) * 6) * Math.PI * 2);
      return clamp01(0.5 + g * 0.3 + (fine(u * 0.1, v) - 0.5) * 0.3);
    };
  },
  planks() {
    const wood = GENERATORS.wood();
    const rows = 5;
    const jitter = makeNoise(rows, 53);
    return (u, v) => {
      const y = v * rows;
      const row = Math.floor(y), fy = y - row;
      const shift = jitter(0.5 / rows, (row + 0.5) / rows) * 3;
      const fx = ((u * 1.5 + shift) % 1 + 1) % 1;
      const seam = Math.min(smooth(0, 0.04, fy), smooth(0, 0.04, 1 - fy), smooth(0, 0.01, fx), smooth(0, 0.01, 1 - fx));
      return clamp01(wood(u, v + row * 0.37) * 0.8 * seam + 0.15 * seam);
    };
  },
  marble() {
    const n = makeFbm(4, 5, 59);
    return (u, v) => {
      const s = Math.abs(Math.sin((u * 3 + v * 2 + n(u, v) * 5) * Math.PI));
      return clamp01(0.75 + 0.25 * n(u * 2, v * 2) - Math.pow(1 - s, 10) * 0.8);
    };
  },
  granite() {
    const n = makeFbm(48, 3, 61);
    const r = rng(67);
    const spots = makeNoise(160, 71);
    return (u, v) => clamp01(n(u, v) * 0.6 + (spots(u, v) > 0.78 ? 0.45 : 0) + (spots(u + 0.5, v) < 0.12 ? -0.3 : 0) + r() * 0.05);
  },
  slate() {
    const n = makeFbm(3, 5, 73);
    const flakes = makeVoronoi(7, 79);
    const fine = makeFbm(24, 2, 81);
    return (u, v) => {
      const [f1, f2] = flakes(u * 0.6 + n(u, v) * 0.3, v);
      const plate = smooth(0, 0.035, f2 - f1);
      return clamp01(0.25 + n(u, v) * 0.45 + plate * 0.25 + (fine(u, v) - 0.5) * 0.2);
    };
  },
  concrete() {
    const n = makeFbm(8, 5, 83);
    const pits = makeNoise(180, 89);
    return (u, v) => clamp01(n(u, v) * 0.8 + 0.2 - (pits(u, v) > 0.86 ? 0.35 : 0));
  },
  brick() {
    const rows = 8, cols = 4;
    const n = makeFbm(16, 3, 97);
    return (u, v) => {
      const y = v * rows;
      const row = Math.floor(y), fy = y - row;
      const x = u * cols + (row % 2) * 0.5;
      const fx = x - Math.floor(x);
      const mortar = Math.min(smooth(0, 0.07, fy), smooth(0, 0.07, 1 - fy), smooth(0, 0.035, fx), smooth(0, 0.035, 1 - fx));
      return clamp01(mortar * (0.7 + n(u, v) * 0.3));
    };
  },
  cobble() {
    const vo = makeVoronoi(9, 101);
    const n = makeFbm(24, 2, 103);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      const edge = smooth(0, 0.04, f2 - f1);
      return clamp01(edge * (0.55 + (0.06 - Math.min(f1, 0.06)) * 6) + n(u, v) * 0.2);
    };
  },
  pebble() {
    const vo = makeVoronoi(22, 107);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      return clamp01(smooth(0, 0.02, f2 - f1) * (1 - f1 * 18));
    };
  },
  rock() {
    const n = makeFbm(4, 6, 109);
    const vo = makeVoronoi(6, 113);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      return clamp01(n(u, v) * 0.85 + smooth(0, 0.03, f2 - f1) * 0.25 - 0.1);
    };
  },
  lava() {
    const vo = makeVoronoi(7, 127);
    const n = makeFbm(8, 3, 131);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      return clamp01(smooth(0, 0.03, f2 - f1) * 0.9 + n(u, v) * 0.1);
    };
  },
  sand() {
    const n = makeFbm(96, 2, 137);
    const ripples = makeFbm(3, 2, 139);
    return (u, v) => clamp01(n(u, v) * 0.6 + Math.sin((v * 10 + ripples(u, v) * 4) * Math.PI * 2) * 0.12 + 0.2);
  },
  snow() {
    const n = makeFbm(6, 4, 149);
    return (u, v) => n(u, v);
  },
  ice() {
    const vo = makeVoronoi(5, 151);
    const n = makeFbm(6, 3, 157);
    return (u, v) => {
      const [f1, f2] = vo(u, v);
      return clamp01(0.75 - (1 - smooth(0, 0.01, f2 - f1)) * 0.5 + n(u, v) * 0.25);
    };
  },
  grass() {
    const n = makeFbm(24, 3, 163);
    const blades = makeNoise(220, 167);
    const patches = makeFbm(3, 3, 173);
    return (u, v) => clamp01(n(u, v) * 0.4 + blades(u, v) * 0.45 + (patches(u, v) - 0.5) * 0.4);
  },
  tiles() {
    const k = 4;
    const n = makeFbm(16, 2, 179);
    return (u, v) => {
      const fx = (u * k) % 1, fy = (v * k) % 1;
      const grout = Math.min(smooth(0, 0.03, fx), smooth(0, 0.03, 1 - fx), smooth(0, 0.03, fy), smooth(0, 0.03, 1 - fy));
      return clamp01(grout * (0.85 + n(u, v) * 0.15));
    };
  },
};

const textureCache = new Map();
function heightTexture(name) {
  let tex = textureCache.get(name);
  if (tex) return tex;
  const gen = (GENERATORS[name] || GENERATORS.speckle)();
  const data = new Uint8Array(N * N * 4);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const h = clamp01(gen((x + 0.5) / N, (y + 0.5) / N));
      const i = (y * N + x) * 4;
      const b = Math.round(h * 255);
      data[i] = b; data[i + 1] = b; data[i + 2] = b; data[i + 3] = 255;
    }
  }
  tex = new THREE.DataTexture(data, N, N, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.colorSpace = THREE.NoColorSpace;
  tex.needsUpdate = true;
  textureCache.set(name, tex);
  return tex;
}

// Shader injection: object-space triplanar height -> albedo/roughness modulation + bump normals.
function applyTriplanar(material, spec, partScale, anisotropy) {
  const tex = heightTexture(spec.tex);
  tex.anisotropy = anisotropy;
  const uniforms = {
    uSvTex: { value: tex },
    uSvTile: { value: spec.tile },
    uSvDepth: { value: spec.depth },
    uSvAlbedo: { value: spec.albedo },
    uSvRough: { value: spec.rough },
    uSvSize: { value: partScale.clone() },
    uSvTexel: { value: 1.5 / N },
    uSvEmissive: { value: spec.emissiveCracks ? 1 : 0 },
  };
  material.userData.svUniforms = uniforms;
  material.customProgramCacheKey = () => 'sv-triplanar';
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace(
        '#include <common>',
        `#include <common>
uniform vec3 uSvSize;
varying vec3 vSvPos;
varying vec3 vSvNrm;
varying vec3 vSvAX;
varying vec3 vSvAY;
varying vec3 vSvAZ;`,
      )
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
vSvPos = position * uSvSize;
vSvNrm = normal / uSvSize;
vSvAX = normalMatrix * vec3(uSvSize.x, 0.0, 0.0);
vSvAY = normalMatrix * vec3(0.0, uSvSize.y, 0.0);
vSvAZ = normalMatrix * vec3(0.0, 0.0, uSvSize.z);`,
      );
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
uniform sampler2D uSvTex;
uniform float uSvTile;
uniform float uSvDepth;
uniform float uSvAlbedo;
uniform float uSvRough;
uniform float uSvTexel;
uniform float uSvEmissive;
varying vec3 vSvPos;
varying vec3 vSvNrm;
varying vec3 vSvAX;
varying vec3 vSvAY;
varying vec3 vSvAZ;
float svH;
vec3 svG;
void svSample() {
  vec3 w = pow(abs(normalize(vSvNrm)), vec3(4.0));
  w /= (w.x + w.y + w.z);
  vec3 p = vSvPos / uSvTile;
  float e = uSvTexel;
  float hx = texture2D(uSvTex, p.zy).r;
  float hxu = texture2D(uSvTex, p.zy + vec2(e, 0.0)).r;
  float hxv = texture2D(uSvTex, p.zy + vec2(0.0, e)).r;
  float hy = texture2D(uSvTex, p.xz).r;
  float hyu = texture2D(uSvTex, p.xz + vec2(e, 0.0)).r;
  float hyv = texture2D(uSvTex, p.xz + vec2(0.0, e)).r;
  float hz = texture2D(uSvTex, p.xy).r;
  float hzu = texture2D(uSvTex, p.xy + vec2(e, 0.0)).r;
  float hzv = texture2D(uSvTex, p.xy + vec2(0.0, e)).r;
  svH = hx * w.x + hy * w.y + hz * w.z;
  vec3 gx = vec3(0.0, hxv - hx, hxu - hx);
  vec3 gy = vec3(hyu - hy, 0.0, hyv - hy);
  vec3 gz = vec3(hzu - hz, hzv - hz, 0.0);
  svG = (gx * w.x + gy * w.y + gz * w.z) * (uSvDepth / (e * uSvTile));
}`,
      )
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
svSample();
diffuseColor.rgb *= (1.0 - uSvAlbedo) + uSvAlbedo * 2.0 * svH;`,
      )
      .replace(
        '#include <roughnessmap_fragment>',
        `#include <roughnessmap_fragment>
roughnessFactor = clamp(roughnessFactor + (0.5 - svH) * uSvRough, 0.04, 1.0);`,
      )
      .replace(
        '#include <normal_fragment_maps>',
        `#include <normal_fragment_maps>
normal = normalize(normal - (svG.x * vSvAX + svG.y * vSvAY + svG.z * vSvAZ));`,
      )
      .replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
if (uSvEmissive > 0.5) { totalEmissiveRadiance += vec3(1.6, 0.45, 0.08) * pow(1.0 - svH, 6.0); }`,
      );
  };
}

function srgb(c) {
  return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
}

// Creates the three.js material for a dumped part. Returns { material, bloom: boolean }.
export function makeMaterial(part, partScale, opts = {}) {
  const spec = TABLE[part.material] || TABLE.SmoothPlastic;
  const color = srgb(part.color);
  const transparency = Math.min(Math.max(part.transparency || 0, 0), 1);
  const reflectance = Math.min(Math.max(part.reflectance || 0, 0), 1);
  const anisotropy = opts.anisotropy || 8;

  if (spec.neon) {
    const m = new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(NEON_GAIN) });
    if (transparency > 0) {
      m.transparent = true;
      m.opacity = 1 - transparency;
      m.depthWrite = false;
      m.blending = THREE.AdditiveBlending; // translucent neon reads as glow in Roblox
    }
    return { material: m, bloom: true };
  }
  if (spec.forcefield) {
    const m = new THREE.MeshBasicMaterial({
      color: color.clone().multiplyScalar(0.9),
      transparent: true,
      opacity: 0.45 * (1 - transparency * 0.6),
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      side: THREE.DoubleSide,
    });
    return { material: m, bloom: true };
  }
  if (spec.glass) {
    const m = new THREE.MeshPhysicalMaterial({
      color,
      roughness: spec.r,
      metalness: 0,
      envMapIntensity: spec.env,
      clearcoat: 1,
      clearcoatRoughness: 0.05,
      transparent: transparency > 0,
      opacity: transparency > 0 ? Math.max(0.12, 1 - transparency) : 1,
      depthWrite: transparency === 0,
    });
    return { material: m, bloom: false };
  }
  const m = new THREE.MeshStandardMaterial({
    color,
    roughness: spec.r + (0.05 - spec.r) * reflectance,
    metalness: Math.max(spec.m, reflectance * 0.6),
    envMapIntensity: spec.env + reflectance * 1.5,
  });
  if (transparency > 0) {
    m.transparent = true;
    m.opacity = 1 - transparency;
    m.depthWrite = transparency < 0.5;
  }
  if (spec.tex && opts.textures !== false) {
    applyTriplanar(m, spec, partScale, anisotropy);
  }
  return { material: m, bloom: false };
}

export function materialNames() {
  return Object.keys(TABLE);
}

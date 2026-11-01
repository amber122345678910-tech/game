// Post-processing: HDR render (MSAA) -> selective bloom (Neon/ForceField only) -> ACES tone mapping
// -> colour grading (saturation/contrast/tint/vignette) -> Highlight emulation (fill + crisp outline).
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const BLACK = new THREE.MeshBasicMaterial({ color: 0x000000 });

const MixShader = {
  uniforms: { tDiffuse: { value: null }, tBloom: { value: null } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform sampler2D tBloom; varying vec2 vUv;
    void main(){ gl_FragColor = texture2D(tDiffuse, vUv) + vec4(texture2D(tBloom, vUv).rgb, 0.0); }`,
};

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uSaturation: { value: 0 },
    uContrast: { value: 0 },
    uTint: { value: new THREE.Vector3(1, 1, 1) },
    uVignette: { value: 0 },
    uAspect: { value: 1 },
  },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float uSaturation; uniform float uContrast; uniform vec3 uTint;
    uniform float uVignette; uniform float uAspect; varying vec2 vUv;
    void main(){
      vec4 src = texture2D(tDiffuse, vUv);
      vec3 c = src.rgb * uTint;
      float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
      c = mix(vec3(l), c, 1.0 + uSaturation);
      c = (c - 0.5) * (1.0 + uContrast) + 0.5;
      vec2 d = (vUv - 0.5) * vec2(uAspect, 1.0);
      c *= 1.0 - uVignette * smoothstep(0.35, 1.05, length(d) * 1.25);
      gl_FragColor = vec4(clamp(c, 0.0, 1.0), src.a);
    }`,
};

// Separable exact Euclidean dilation of the highlight id mask (two passes).
const DilateH = {
  uniforms: { tMask: { value: null }, uTexel: { value: new THREE.Vector2() }, uRadius: { value: 4 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tMask; uniform vec2 uTexel; uniform float uRadius; varying vec2 vUv;
    void main(){
      float best = 1e5; float id = 0.0;
      for (int i = -16; i <= 16; i++) {
        float fi = float(i);
        if (abs(fi) > uRadius + 1.0) continue;
        float m = texture2D(tMask, vUv + vec2(fi * uTexel.x, 0.0)).r;
        if (m > 0.0 && abs(fi) < best) { best = abs(fi); id = m; }
      }
      gl_FragColor = vec4(id, best, 0.0, 1.0);
    }`,
};

const DilateV = {
  uniforms: { tH: { value: null }, uTexel: { value: new THREE.Vector2() }, uRadius: { value: 4 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tH; uniform vec2 uTexel; uniform float uRadius; varying vec2 vUv;
    void main(){
      float best = 1e10; float id = 0.0;
      for (int j = -16; j <= 16; j++) {
        float fj = float(j);
        if (abs(fj) > uRadius + 1.0) continue;
        vec4 h = texture2D(tH, vUv + vec2(0.0, fj * uTexel.y));
        if (h.r > 0.0) {
          float d2 = h.g * h.g + fj * fj;
          if (d2 < best) { best = d2; id = h.r; }
        }
      }
      gl_FragColor = vec4(id, sqrt(best), 0.0, 1.0);
    }`,
};

const MAX_HL = 16;
const HighlightShader = {
  uniforms: {
    tDiffuse: { value: null },
    tMask: { value: null },
    tDist: { value: null },
    uRadius: { value: 4 },
    uFill: { value: Array.from({ length: MAX_HL }, () => new THREE.Vector4()) },
    uOutline: { value: Array.from({ length: MAX_HL }, () => new THREE.Vector4()) },
  },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform sampler2D tMask; uniform sampler2D tDist; uniform float uRadius;
    uniform vec4 uFill[${MAX_HL}]; uniform vec4 uOutline[${MAX_HL}];
    varying vec2 vUv;
    vec4 pick(vec4 arr[${MAX_HL}], int idx) {
      vec4 r = vec4(0.0);
      for (int i = 0; i < ${MAX_HL}; i++) { if (i == idx) r = arr[i]; }
      return r;
    }
    void main(){
      vec4 c = texture2D(tDiffuse, vUv);
      float own = texture2D(tMask, vUv).r;
      if (own > 0.0) {
        int idx = int(floor(own * 255.0 + 0.5)) - 1;
        vec4 f = pick(uFill, idx);
        c.rgb = mix(c.rgb, f.rgb, f.a);
      } else {
        vec4 d = texture2D(tDist, vUv);
        if (d.r > 0.0) {
          int idx = int(floor(d.r * 255.0 + 0.5)) - 1;
          vec4 o = pick(uOutline, idx);
          float a = clamp(uRadius + 0.5 - d.g, 0.0, 1.0) * o.a;
          c.rgb = mix(c.rgb, o.rgb, a);
        }
      }
      gl_FragColor = c;
    }`,
};

export class Post {
  constructor(renderer, width, height, opts) {
    this.renderer = renderer;
    this.width = width;
    this.height = height;
    this.opts = opts;
    const samples = opts.msaa || 0;
    const rtMain = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples });
    this.composer = new EffectComposer(renderer, rtMain);
    this.composer.setPixelRatio(1);
    this.composer.setSize(width, height);

    this.bloomEnabled = false;
    const rtBloom = new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, samples });
    this.bloomComposer = new EffectComposer(renderer, rtBloom);
    this.bloomComposer.setPixelRatio(1);
    this.bloomComposer.setSize(width, height);
    this.bloomComposer.renderToScreen = false;

    this.maskRT = new THREE.WebGLRenderTarget(width, height, { type: THREE.UnsignedByteType, samples: 0 });
    this.hRT = new THREE.WebGLRenderTarget(width, height, { type: THREE.FloatType, samples: 0 });
    this.dRT = new THREE.WebGLRenderTarget(width, height, { type: THREE.FloatType, samples: 0 });
    this.fsQuadScene = new THREE.Scene();
    this.fsCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
    this.fsQuadScene.add(this.quad);
    this.dilateH = new THREE.ShaderMaterial(DilateH);
    this.dilateV = new THREE.ShaderMaterial(DilateV);
  }

  setup(scene, camera, env, highlightSets) {
    const { width, height } = this;
    this.scene = scene;
    this.camera = camera;
    // bloom chain
    this.bloomComposer.passes.length = 0;
    this.bloomComposer.addPass(new RenderPass(scene, camera));
    const b = env.bloom || { strength: 0, radius: 0, threshold: 1 };
    this.bloomPass = new UnrealBloomPass(new THREE.Vector2(width, height), b.strength, b.radius, b.threshold);
    this.bloomComposer.addPass(this.bloomPass);

    // main chain
    this.composer.passes.length = 0;
    this.composer.addPass(new RenderPass(scene, camera));
    this.mixPass = new ShaderPass(MixShader);
    this.mixPass.uniforms.tBloom.value = this.bloomComposer.renderTarget2.texture;
    this.composer.addPass(this.mixPass);
    this.composer.addPass(new OutputPass());
    this.gradePass = new ShaderPass(GradeShader);
    this.gradePass.uniforms.uSaturation.value = env.saturation || 0;
    this.gradePass.uniforms.uContrast.value = env.contrast || 0;
    this.gradePass.uniforms.uTint.value.set(...(env.tint || [1, 1, 1]));
    this.gradePass.uniforms.uVignette.value = this.opts.vignette ?? 0.18;
    this.gradePass.uniforms.uAspect.value = width / height;
    this.composer.addPass(this.gradePass);

    this.highlightSets = highlightSets.slice(0, MAX_HL);
    this.hlPass = null;
    if (this.highlightSets.length > 0) {
      this.hlPass = new ShaderPass(HighlightShader);
      const u = this.hlPass.uniforms;
      this.highlightSets.forEach((h, i) => {
        u.uFill.value[i].set(...h.fill, 1 - h.fillT);
        u.uOutline.value[i].set(...h.outline, 1 - h.outlineT);
      });
      u.tMask.value = this.maskRT.texture;
      u.tDist.value = this.dRT.texture;
      u.uRadius.value = this.opts.outlinePx;
      this.composer.addPass(this.hlPass);
    }
  }

  // Renders the neon-only buffer: every non-bloom mesh is drawn black (keeps occlusion).
  renderBloom(bloomMeshes) {
    if (!this.bloomEnabled || bloomMeshes.size === 0) {
      this.renderer.setRenderTarget(this.bloomComposer.renderTarget2);
      this.renderer.setClearColor(0x000000, 1);
      this.renderer.clear();
      this.renderer.setRenderTarget(null);
      return;
    }
    const swapped = [];
    const background = this.scene.background;
    const fog = this.scene.fog;
    this.scene.background = null;
    this.scene.fog = null;
    this.scene.traverse((o) => {
      if (o.isMesh && !bloomMeshes.has(o)) {
        swapped.push([o, o.material, o.visible]);
        if (o.userData.isSky || (o.material && o.material.transparent && !bloomMeshes.has(o))) {
          o.visible = false;
        } else {
          o.material = BLACK;
        }
      }
    });
    this.bloomComposer.render();
    for (const [o, m, v] of swapped) {
      o.material = m;
      o.visible = v;
    }
    this.scene.background = background;
    this.scene.fog = fog;
  }

  // Id mask for highlights: highlighted meshes write (index+1)/255, everything else black.
  renderMask(meshToHighlight) {
    const r = this.renderer;
    const swapped = [];
    const background = this.scene.background;
    const fog = this.scene.fog;
    this.scene.background = null;
    this.scene.fog = null;
    const idMats = this.highlightSets.map((h, i) => new THREE.MeshBasicMaterial({
      color: new THREE.Color((i + 1) / 255, 0, 0),
      depthTest: h.depthMode !== 'AlwaysOnTop',
    }));
    this.scene.traverse((o) => {
      if (!o.isMesh) return;
      swapped.push([o, o.material, o.visible, o.renderOrder]);
      const idx = meshToHighlight.get(o);
      if (idx !== undefined) {
        o.material = idMats[idx];
        o.renderOrder = this.highlightSets[idx].depthMode === 'AlwaysOnTop' ? 1000 : 0;
      } else if (o.userData.isSky || o.userData.isFloor || (o.material && o.material.transparent)) {
        o.visible = false;
      } else {
        o.material = BLACK;
      }
    });
    const prevColorSpace = r.outputColorSpace;
    r.outputColorSpace = THREE.LinearSRGBColorSpace;
    r.setRenderTarget(this.maskRT);
    r.setClearColor(0x000000, 1);
    r.clear();
    r.render(this.scene, this.camera);
    r.outputColorSpace = prevColorSpace;
    for (const [o, m, v, ro] of swapped) {
      o.material = m;
      o.visible = v;
      o.renderOrder = ro;
    }
    this.scene.background = background;
    this.scene.fog = fog;
    idMats.forEach((m) => m.dispose());
    // dilation
    const texel = new THREE.Vector2(1 / this.width, 1 / this.height);
    this.dilateH.uniforms.tMask.value = this.maskRT.texture;
    this.dilateH.uniforms.uTexel.value.copy(texel);
    this.dilateH.uniforms.uRadius.value = this.opts.outlinePx;
    this.quad.material = this.dilateH;
    r.setRenderTarget(this.hRT);
    r.render(this.fsQuadScene, this.fsCam);
    this.dilateV.uniforms.tH.value = this.hRT.texture;
    this.dilateV.uniforms.uTexel.value.copy(texel);
    this.dilateV.uniforms.uRadius.value = this.opts.outlinePx;
    this.quad.material = this.dilateV;
    r.setRenderTarget(this.dRT);
    r.render(this.fsQuadScene, this.fsCam);
    r.setRenderTarget(null);
  }

  render(bloomMeshes, meshToHighlight) {
    this.renderBloom(bloomMeshes);
    if (this.hlPass) this.renderMask(meshToHighlight);
    this.composer.render();
  }
}

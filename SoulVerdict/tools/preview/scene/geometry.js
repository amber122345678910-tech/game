// Unit geometries that reproduce Roblox primitive shapes. Every geometry is centred on the origin
// and fills a 1x1x1 box; parts are placed with matrix = CFrame * T(mesh offset) * S(size [* mesh scale]).
// Roblox conventions: Y up, front = -Z, Part cylinders run along X, SpecialMesh Sphere fills the
// part box (ellipsoid), Ball parts use the smallest size component as diameter.
import * as THREE from 'three';

const cache = new Map();
function cached(key, make) {
  let g = cache.get(key);
  if (!g) {
    g = make();
    cache.set(key, g);
  }
  return g;
}

function fromTriangles(tris) {
  const pos = [];
  for (const t of tris) for (const p of t) pos.push(p[0], p[1], p[2]);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals(); // non-indexed -> flat face normals
  // planar UVs (only needed so bump-enabled materials compile; textures use triplanar mapping)
  const uv = [];
  for (let i = 0; i < pos.length; i += 3) uv.push(pos[i] + 0.5, pos[i + 1] + 0.5);
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  return g;
}

// WedgePart: bottom and back (+Z) faces are full, the slope rises from the bottom-front edge
// (-Z) to the top-back edge (+Z), so the slope faces forward/up.
export function wedge() {
  return cached('wedge', () => {
    const A = [-0.5, -0.5, -0.5], B = [0.5, -0.5, -0.5], C = [0.5, -0.5, 0.5], D = [-0.5, -0.5, 0.5];
    const E = [-0.5, 0.5, 0.5], F = [0.5, 0.5, 0.5];
    return fromTriangles([
      [A, B, C], [A, C, D], // bottom
      [D, C, F], [D, F, E], // back
      [A, E, F], [A, F, B], // slope
      [A, D, E], // left
      [B, F, C], // right
    ]);
  });
}

// CornerWedgePart: square base, apex above the (+X, +Z) corner; vertical faces at +X and +Z,
// slopes facing -Z and -X. NOTE: apex corner chosen to match WedgePart's tall back side
// (unverified against the engine; CornerWedges are not used by the rigs).
export const CORNER_WEDGE_APEX = [0.5, 0.5, 0.5];
export function cornerWedge() {
  return cached('cornerwedge', () => {
    const A = [-0.5, -0.5, -0.5], B = [0.5, -0.5, -0.5], C = [0.5, -0.5, 0.5], D = [-0.5, -0.5, 0.5];
    const G = CORNER_WEDGE_APEX;
    return fromTriangles([
      [A, B, C], [A, C, D], // bottom
      [B, G, C], // right (vertical)
      [D, C, G], // back (vertical)
      [A, G, B], // front slope
      [A, D, G], // left slope
    ]);
  });
}

export function box() {
  return cached('box', () => new THREE.BoxGeometry(1, 1, 1));
}

export function sphere() {
  return cached('sphere', () => new THREE.SphereGeometry(0.5, 64, 40));
}

// Cylinder whose axis is X (Part.Shape = Cylinder, SpecialMesh Cylinder).
export function cylinderX() {
  return cached('cylx', () => {
    const g = new THREE.CylinderGeometry(0.5, 0.5, 1, 64, 1);
    g.rotateZ(-Math.PI / 2);
    return g;
  });
}

// Cylinder whose axis is Y (legacy CylinderMesh).
export function cylinderY() {
  return cached('cyly', () => new THREE.CylinderGeometry(0.5, 0.5, 1, 64, 1));
}

// Classic Roblox "Head" mesh: a Y-axis cylinder with strongly rounded top/bottom edges.
export function head() {
  return cached('head', () => {
    const pts = [];
    const r = 0.5, h = 0.5, k = 0.22; // k = corner radius
    pts.push(new THREE.Vector2(0, -h));
    for (let i = 0; i <= 10; i++) {
      const a = -Math.PI / 2 + (i / 10) * (Math.PI / 2);
      pts.push(new THREE.Vector2(r - k + Math.cos(a) * k, -h + k + Math.sin(a) * k));
    }
    for (let i = 0; i <= 10; i++) {
      const a = (i / 10) * (Math.PI / 2);
      pts.push(new THREE.Vector2(r - k + Math.cos(a) * k, h - k + Math.sin(a) * k));
    }
    pts.push(new THREE.Vector2(0, h));
    return new THREE.LatheGeometry(pts, 64);
  });
}

// Returns { geometry, scale: THREE.Vector3, offset: THREE.Vector3 } for a dumped part.
export function forPart(part) {
  const size = new THREE.Vector3(...part.size);
  const mesh = part.mesh || null;
  if (mesh) {
    const s = new THREE.Vector3(...(mesh.scale || [1, 1, 1]));
    const off = new THREE.Vector3(...(mesh.offset || [0, 0, 0]));
    const scaled = size.clone().multiply(s);
    switch (mesh.type) {
      case 'Sphere':
        return { geometry: sphere(), scale: scaled, offset: off };
      case 'Cylinder':
        return { geometry: cylinderX(), scale: scaled, offset: off };
      case 'CylinderY':
        return { geometry: cylinderY(), scale: scaled, offset: off };
      case 'Head': {
        const d = Math.min(size.x, size.z);
        return { geometry: head(), scale: new THREE.Vector3(d * s.x, size.y * s.y, d * s.z), offset: off };
      }
      case 'Wedge':
        return { geometry: wedge(), scale: scaled, offset: off };
      default: // Brick, Torso, FileMesh (cannot load assets offline -> box)
        return { geometry: box(), scale: scaled, offset: off };
    }
  }
  const zero = new THREE.Vector3();
  switch (part.shape) {
    case 'Ball': {
      const d = Math.min(size.x, size.y, size.z);
      return { geometry: sphere(), scale: new THREE.Vector3(d, d, d), offset: zero };
    }
    case 'Cylinder': {
      const d = Math.min(size.y, size.z);
      return { geometry: cylinderX(), scale: new THREE.Vector3(size.x, d, d), offset: zero };
    }
    case 'Wedge':
      return { geometry: wedge(), scale: size, offset: zero };
    case 'CornerWedge':
      return { geometry: cornerWedge(), scale: size, offset: zero };
    default:
      return { geometry: box(), scale: size, offset: zero };
  }
}

// Roblox CFrame components [x,y,z, r00..r22] -> THREE.Matrix4 (both are right-handed, Y up).
export function cframeMatrix(cf) {
  const m = new THREE.Matrix4();
  m.set(
    cf[3], cf[4], cf[5], cf[0],
    cf[6], cf[7], cf[8], cf[1],
    cf[9], cf[10], cf[11], cf[2],
    0, 0, 0, 1,
  );
  return m;
}

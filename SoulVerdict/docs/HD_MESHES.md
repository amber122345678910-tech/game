# HD meshes — optional quality tier

The owner asked for Sans to look "maximum quality, not just an oval". Rigs and props stay part-built
(SPEC §0) and are always the fallback; on top of that the client can swap in smooth, sculpted meshes:

- 3 Sans skulls: `SansSkullClassic`, `SansSkullFell`, `SansSkullEclipse`
- 3 Gaster Blasters, each a skull plus a separately hinged jaw: `BlasterSkull<Style>` and `BlasterJaw<Style>`,
  where `<Style>` is `Classic`, `Fell` or `Eclipse`

The meshes are generated offline from code (signed-distance-field sculpts in `tools/meshgen/`). There are no
asset uploads and no gameplay dependency: if no tier is available, every API returns `nil` or `false`, and the
part-built model stays exactly as it is.

Previews: `previews/dev/hd_<Name>_<view>.png` (front, threequarter, side; blaster previews show the jaw opened
28°) and the contact sheet `previews/dev/hd_sheet.png`.

## Meshes

| Mesh | Triangles | Vertices | Nominal size (studs, X×Y×Z) | Data module |
|---|---|---|---|---|
<!-- MESH_TABLE -->

All meshes use studs at nominal size, with +Y up and the front facing −Z (Roblox LookVector). Each mesh's origin is
the centre of its own bounding box. The jaws pivot around `Hinge` (mesh-local). Opening the jaw is a rotation of
`CFrame.Angles(-angle, 0, 0)` about the hinge, because a positive X rotation would lift the front.

Named points are stored as `Anchors` in each data module (mesh-local, studs at nominal size):

<!-- ANCHOR_TABLE -->

## How the tiers work (`src/client/VFX/HDMesh.luau`)

`HDMesh.Create(name)` resolves a mesh name in this order:

1. **Tier A, imported.** If `ReplicatedStorage.SV_Meshes.<Name>` is a `MeshPart`, it is cloned. This tier needs
   no verification and no special settings.
2. **Tier B, editable.** If `AssetService:CreateEditableMesh()` works, the data module is decoded and an
   `EditableMesh` is built once per name.
   - The batch APIs are tried first and verified. If anything looks wrong, the build falls back to
     `AddVertex`/`AddNormal`/`AddColor`/`AddTriangle` + `SetFaceNormals`/`SetFaceColors` and yields every 1500
     faces.
   - The mesh then becomes a `MeshPart` through `AssetService:CreateMeshPartAsync(Content.fromObject(em))`
     (Box collision, Precise render fidelity). That part is cached as a template, and every request returns
     `template:Clone()`, which shares the mesh.
   - Colours are palette-indexed: one `AddColor` per palette entry, and faces reference the shared colour IDs.
3. **Otherwise** `nil`.

Every MeshPart that is returned has these settings: `Anchored=false`, `CanCollide/CanQuery/CanTouch=false`,
`Massless=true`, `Material=SmoothPlastic`, `Color=white`. The vertex colours carry the look: bone, dark
sockets, grin lines, the gold tooth, and the glowing cracks.

Budget and robustness:

- At most 8 EditableMeshes per client, one per mesh name. A round needs about 3: one skull, one blaster skull
  and one jaw.
- Creation that fails or returns `nil` (budget exhausted, API disabled, decode error) gives up quietly for that
  name, with one warning per cause.
- `HDMesh.Available()` caches its probe, and the probe mesh is destroyed.
- Measured community costs: about 22 ms for `CreateMeshPartAsync` on first use, plus the fill time for the
  vertex and face calls. Use `HDMesh.Preload({...})` at round start so the first `ApplyToModel` is instant.

### API

```lua
local HDMesh = require(StarterPlayerScripts.Client.VFX.HDMesh)
HDMesh.Decode(data: string | MeshData) -> Decoded   -- pure; {positions, normals, colors, alphas?, indices, palette, ...}
HDMesh.GetData(name) -> MeshData?                    -- ReplicatedStorage.Shared.Meshes.Get(name)
HDMesh.Names() -> {string}
HDMesh.Available() -> boolean                        -- any tier usable
HDMesh.Tier(name?) -> "Imported" | "Editable" | "None"
HDMesh.Create(name) -> MeshPart?                     -- yields; new unparented MeshPart sized to data.Size
HDMesh.Preload(names?)                               -- background builds
HDMesh.ApplyToModel(model) -> boolean                -- yields; see the rig contract below; idempotent
HDMesh.RemoveFromModel(model)                        -- destroys HD parts, shows the part-built groups again
HDMesh.CreateBlaster(style, scale?) -> Model?        -- yields; "Classic" | "Fell" | "Eclipse"
HDMesh.PoseBlasterJaw(model, angle)                  -- radians, 0 = closed; cheap, call per frame
```

`ReplicatedStorage.Shared.Meshes` (Lune-safe index): `Meshes.Names()`, `Meshes.Get(name) -> MeshData?`,
`Meshes.Has(name)`. A data module is required lazily on first `Get`.

## Contract for rig and VFX agents (SPEC §18)

The rig or prop builder must:

- set `HDGroup = "<Group>"` on every part the HD mesh replaces, for example the Head-shell parts of a Sans rig
  with `"Skull"`;
- add an `Attachment` named `HD_<Group>` to the limb or part the group belongs to:
  - put it at the group's bounding-box centre;
  - orient it so its LookVector (−Z) is the model's forward;
  - give it the attributes `HDMesh` (string, for example `"SansSkullClassic"`) and `HDSize` (Vector3, the
    group's bounding size in studs at scale 1).

The MeshPart is stretched to `HDSize × model:GetAttribute("RigScale")`. To avoid distortion, use an `HDSize` with
the same proportions as the mesh's nominal size in the table above, or simply the nominal size × k.

The client calls `HDMesh.ApplyToModel(model)` for each character model, in a separate thread, for example from
`RigStyleController` when a character appears and the graphics setting allows HD. `ApplyToModel` does this:

- it welds `HDMesh_<Group>` (a `WeldConstraint` to the anchor's parent) at the anchor's `WorldCFrame`;
- it hides the `HDGroup` parts locally with `LocalTransparencyModifier = 1`, so they still collide and remain the
  fallback;
- it re-asserts the hiding when the default camera scripts reset `LocalTransparencyModifier`;
- it skips groups that are already applied.

`RemoveFromModel` undoes all of this. The HD part carries the attribute `HDPart = "<Group>"` and has no `Role`,
so RigStyles leaves it alone.

A Gaster Blaster VFX either uses its part-built prop or calls `HDMesh.CreateBlaster(style, scale)`. The result is
a `Model` facing −Z with these parts:

- `Skull`: the PrimaryPart, anchored, with Attachments `JawHinge`, `Muzzle`, `LeftEye`, `RightEye`,
  `HornTipLeft` and `HornTipRight`;
- `Jaw`: anchored, with an Attachment `JawHinge`.

Move it with `model:PivotTo(cf)`, then call `HDMesh.PoseBlasterJaw(model, angle)` (about 0.5 rad is a good open
pose). `Muzzle` is where the beam starts, and `LeftEye`/`RightEye` sit on the socket floors, ready for eye-glow
VFX.

Recommended `HD_Skull` values for the Sans rigs are `HDMesh = "SansSkull<Style>"` and `HDSize` = the skull's
nominal size × the head scale. The eye anchors line up with the sockets, so put `LeftPupil`/`RightPupil` there
(skull-local `Anchors.LeftEye`/`RightEye` × scale).

## What the owner must do to enable a tier

You can enable either tier, or both. Without either, nothing changes in the game.

**Tier B, the most automatic one.** Studio → *File → Game Settings* (also called *Experience Settings*) →
*Security* → turn on **Allow Mesh / Image APIs**, then publish. The same switch is in the Creator Dashboard under
*Configure → Settings → Enable Mesh / Image APIs*.

Roblox requires the account that owns the experience to be ID-verified and 13+ age-verified (for a group game,
the group owner). Players do not need verification. EditableMesh is still labelled "Client Beta".

**Tier A, works without verification.** Run Studio → *File → Import 3D* (3D Importer) once for each file in
`assets/meshes/`:

- Prefer the `.glb` files. glTF carries the vertex colours (`COLOR_0`).
- The `.obj` files store the colours as `v x y z r g b`, which many importers ignore. An OBJ import is then plain
  white, though the shape still reads.

After importing:

1. Keep the mesh names (`SansSkullClassic`, …). Put the resulting MeshParts in a Folder named **`SV_Meshes`**
   directly under **ReplicatedStorage**.
2. Check orientation. The face or muzzle must point along the MeshPart's front (−Z, the LookVector). If an
   import is turned, add a number attribute **`HDYaw`** (degrees, for example 180) to that MeshPart instead of
   rotating it.
3. To keep a material or texture you applied yourself, add the bool attribute **`HDKeepLook = true`**.
   Otherwise the code sets SmoothPlastic and a white colour so that the vertex colours show.

## Regenerating the meshes

Run these from the project root:

```bash
python3 -m pip install --user numpy scipy scikit-image trimesh fast-simplification pymeshlab
sudo apt-get install -y libopengl0          # pymeshlab's filters need libOpenGL.so.0
(cd tools/meshgen/preview && npm install)    # three.js for the preview renderer (Playwright is preinstalled)
python3 tools/meshgen/build.py                                   # all meshes + exports + previews (~2.5 min)
python3 tools/meshgen/build.py SansSkullFell --views front,side  # one mesh
python3 tools/meshgen/build.py --res 120 --no-export --preview-dir /tmp/p   # fast look-dev loop
lune run tools/lune/run_tests.luau hdmesh                        # decoder + data tests
```

If pymeshlab is unavailable, the decimator falls back to `fast_simplification`. That works, but the triangles are
lower quality.

The build writes these outputs:

- `src/shared/Meshes/<Name>.luau` and `init.luau` (the index)
- `assets/meshes/<Name>.obj` and `.glb`
- `tools/meshgen/out/<Name>.json` (preview input, gitignored)
- `previews/dev/hd_*.png` and `hd_sheet.png`

Pipeline, in `tools/meshgen/`:

| File | Role |
|---|---|
| `sdf.py` | Vectorised SDF primitives: sphere, ellipsoid, round box, capsule, round cone, tapered tube, cylinder, capped cone, torus, plane, triangular prism, elliptic socket prism. Also smooth union, subtraction and intersection (polynomial smin), mirror-X, rotations, value noise and fBm. |
| `mesher.py` | 1. Narrow-band grid evaluation (8³ blocks; far blocks reuse their centre value). 2. Marching cubes (skimage). 3. Main components kept. 4. Taubin smoothing. 5. Newton projection onto the surface. 6. Colour-weighted quadric decimation in MeshLab, so eye rims, grin lines and cracks keep their vertices. 7. Re-projection. 8. Normals from the SDF gradient, with a mesh-normal fallback. 9. Region colours. 10. Smoothed SDF ambient-occlusion bake. 11. Palette (≤ 255 colours). 12. Centring. |
| `models/sans.py` | The Sans skulls. The grin is carved in cylindrical face coordinates. The sockets are steep elliptic tunnels. |
| `models/blaster.py` | Lofted snout, cranium, horns (Bezier tubes), fenestrae, teeth rows, jaw trough and hinge. |
| `models/common.py` | Grooves, crack random walks projected onto the surface, and colour helpers. |
| `export.py` | The `SVM1` codec, the Luau and index writers, and OBJ, GLB and JSON output. |
| `preview/render.mjs` | three.js in headless Chromium: key, fill and rim lights with soft shadows, ACES tone mapping. |

### Data format `SVM1` (little endian, base64 inside a `[[...]]` string)

| Offset | Content |
|---|---|
| 0 | `"SVM1"`, then `u16` version, `u16` flags (bit0 alpha, bit1 u32 indices) |
| 8 | `u32` V, then `u32` T |
| 16 | `u16` palette count P, then `u16` reserved |
| 20 | `f32[6]`: bbox min, then bbox max |
| 44 | `P×RGBA8` palette |
| then | `V×u16[3]` positions, quantised across the bbox |
| then | `V×u8[2]` octahedral normals |
| then | `V×u8` palette index |
| then | `T×u16[3]` indices, 0-based, counter-clockwise = front |

The size is about 9 bytes per vertex plus 6 bytes per triangle. Every module stays under 115 KB of source.

## Known limitations

- **Untested in the Roblox client.** EditableMesh needs the real client, so the runtime path has not run here.
  Only the decoder, the data and the offline fail-soft path are covered by the Lune tests. The API names and
  signatures were checked against `.tools/API-Dump.json` (v0.745) and the creator docs.
- **Vertex colours are not emissive.** For real bloom on the Eclipse cracks or the blaster eyes, add a
  `PointLight` or Neon parts at the anchors.
- **`SansHoodClassic` is not generated.** SPEC §18 lists it as optional, and the hoods stay part-built.

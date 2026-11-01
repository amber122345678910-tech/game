# Roblox engine APIs for a code-only Rojo/Luau Undertale-style game (as of 2026-11-01)

## 0. How this was researched, and its limits

- The network policy blocked direct page fetches from `create.roblox.com`, `devforum.roblox.com` and `bloxodes.com` (proxy 403). Every fact here comes from search-engine extracts of those pages, not from reading them in full.
- To check these facts directly, the session network settings must allow `create.roblox.com` and `devforum.roblox.com`.
- Roblox now publishes machine-readable doc indexes that a later pass could read once the host is allowed:
  - https://create.roblox.com/docs/llms.txt
  - https://create.roblox.com/docs/reference/engine/llms.txt
  - https://create.roblox.com/docs/reference/engine/deprecated.md
- The shared web-search budget (200 calls per turn) ran out before the end. Items not confirmed are marked **UNVERIFIED**.
- Source tags used below:
  - **[OFFICIAL]**: Roblox docs or Roblox staff announcement.
  - **[COMMUNITY]**: DevForum user, wiki or third-party site.
  - **UNVERIFIED**: prior knowledge, not re-checked this session.

---

## 1. Changes in 2025–2026 you must know about

| Change | Status and date | Impact on a code-only build | Source |
|---|---|---|---|
| **Unified Lighting.** `Lighting.Technology` is replaced by `Lighting.LightingStyle` (Realistic = 0, Soft = 1) plus `Lighting.PrioritizeLightingQuality` (bool). | Fully live; post update tag Jul 23, 2025 | Both properties are **RobloxScriptSecurity**, so scripts cannot set them. Set them in the place file or in Studio. New experiences start on **Soft**. | [devforum](https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512), [enum](https://create.roblox.com/docs/reference/engine/enums/LightingStyle.md), [security change history](https://robloxapi.github.io/ref/class/Lighting.html) |
| **Server Authority.** `Workspace.AuthorityMode = Server`, `RunService:BindToSimulation`, built-in client prediction and rollback. | Full Release 2026 (newsroom Jul 2026); opt-in | Engine-level anti-cheat and prediction for fighting games. | [docs](https://create.roblox.com/docs/projects/server-authority), [devforum](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993), [newsroom](https://about.roblox.com/newsroom/2026/07/creating-responsive-cheat-resistant-games-roblox-server-authority) |
| **Avatar Joint Upgrade.** Spawned R15 characters get `AnimationConstraint` + `BallSocketConstraint` instead of `Motor6D`. | Live (exact date UNVERIFIED) | Code that looks up `Motor6D` by name can break. Controlled by `StarterPlayer.AvatarJointUpgrade`, which scripts cannot change. | [devforum](https://devforum.roblox.com/t/avatar-joint-upgrade-for-physically-simulated-character-movement-is-now-live/4298561), [StarterPlayer](https://create.roblox.com/docs/en-us/reference/engine/classes/StarterPlayer.md) |
| **Input Action System (IAS).** `InputContext`/`InputAction`/`InputBinding`; default PlayerScripts converted to IAS. | Full Release 2026 (Client Beta updates Nov 21, 2025 and Feb 11, 2026) | Clean cross-device input, including touch through `InputBinding.UIButton`. | [devforum](https://devforum.roblox.com/t/full-release-input-action-system-ias-newly-converted-player-scripts/4678416), [docs](https://create.roblox.com/docs/input/input-action-system) |
| **`UserInputService.PreferredInput`** | Full Release (post updated Oct 14, 2025) | Replaces `LastInputTypeChanged`-style device detection. | [devforum](https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890) |
| **EditableMesh / EditableImage** | Still "Client Beta" in published games. Creator must be 13+ age-verified **and** ID-verified. No replication. | Generate meshes on each client only. Keep a Part-based fallback. | §4 |
| **`AssetService:CreateDataModelContentAsync`** (bakes editable data into static Content) | Full Release; post May 18, 2026 | See §4. | [devforum](https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898) |
| **UnreliableRemoteEvent payload** raised from 900 to **1000 bytes** | Class reference (Jun 2026) says 1000; another docs page still says 900 | Budget at most 900 bytes to be safe. | [ref](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent.md), [devforum](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155) |
| **`OverlapParams` new properties:** `ExcludeInstances`, `IncludeInstances`, `Tolerance` | In docs (Oct 2026) | Recommended over `FilterDescendantsInstances` for new work. | [docs](https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams) |
| **DataStore limits now per experience**, plus a storage cap of 100 MB + 1 MB × lifetime players | Announced Apr 2025; enforcement "April 2026" per a Jun 30, 2026 post (conflicts with "early 2026") | See §8. | [devforum](https://devforum.roblox.com/t/datastores-access-and-storage-updates/3597255) |
| **New Luau type solver**, including type functions | General release late Nov 2025; beta flag removed Jan 7, 2026 | See §10. | [devforum](https://devforum.roblox.com/t/general-release-luau%E2%80%99s-new-type-solver/4084991) |
| **Adaptive Animation** (one animation across any rig) | Studio Beta May 5, 2026; Full Release Jul 2, 2026 (thread titles only) | Only matters if animations are ever uploaded. | [devforum tag listing](https://devforum.roblox.com/tag/avatar) |
| **UIStroke improvements:** `StrokeSizingMode`, `BorderStrokePosition`, `BorderOffset`, `ZIndex` | Studio Beta; current status UNVERIFIED | Feature-detect before use. | [devforum](https://devforum.roblox.com/t/studio-beta-uistroke-improvements-scaling-offsets-and-more/3958036) |
| **Studio-native Script Sync** | Studio Beta (docs Jun 2026); scripts and folders only | Alternative to Rojo for scripts only. | [docs](https://create.roblox.com/docs/scripting/sync) |
| **Rojo v7.7.0** (websockets + MessagePack, Syncback) | Latest release, Jul 2, 2026 | Use 7.7.x. | [release](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0) |
| **`Enum.Font` is legacy.** Gotham and Arial removed; Gotham maps to Montserrat. | Docs Oct 16, 2026 | Use `FontFace` with the `Font` datatype. | [enum](https://create.roblox.com/docs/reference/engine/enums/Font) |

---

## 2. Custom player characters built from Parts at runtime

### Requirements
- **[COMMUNITY]** The Model needs a `Humanoid` and a part named `HumanoidRootPart`. Set `PrimaryPart` to the HumanoidRootPart, or positioning can fail. ([devforum](https://devforum.roblox.com/t/trouble-with-morphs/3915304), [devforum](https://devforum.roblox.com/t/the-process-of-rigging-a-custom-character/1104770))
- **[COMMUNITY]** The Humanoid dies if the Head and Torso/UpperTorso are disconnected. Set `Humanoid.RequiresNeck = false` for rigs without a standard neck. ([wiki](https://roblox.fandom.com/wiki/LoadCharacter), [devforum](https://devforum.roblox.com/t/how-to-set-character-to-a-model/1791428))
- **[COMMUNITY]** Humanoids are built for R6 or R15 topology. For non-humanoid rigs (bosses, Gaster Blaster skulls) use an `AnimationController` instead. ([devforum](https://devforum.roblox.com/t/custom-characters-guide/2825528))

### Three ways to spawn
1. **`StarterPlayer.StarterCharacter`** (a Model with that name).
   - **[COMMUNITY]** On spawn, R15 humanoids rebuild Motor6Ds from attachments whose names contain "Rig" (`Humanoid:BuildRigFromAttachments`). This can overwrite your joints. ([devforum](https://devforum.roblox.com/t/startercharacters-motor6d-gets-changed-and-cant-find-any-documentation-about-it/4010589), [api mirror](https://robloxapi.github.io/ref-temp/class/Humanoid.html))
   - **[COMMUNITY]** `BuildRigFromAttachments` resets HipHeight to 1.35. ([devforum](https://devforum.roblox.com/t/how-to-calculate-the-hipheight-when-the-character-has-no-legs/265366))
   - **[COMMUNITY]** `Player.CharacterAppearanceLoaded` does not fire when a StarterCharacter is present. ([devforum](https://devforum.roblox.com/t/playercharacterappearanceloaded-does-not-fire-if-there-is-a-startercharacter-present/3684116))
2. **Recommended for code: `Players.CharacterAutoLoads = false`, then build on the server and assign it.**
   - Code: `player.Character = model; model.Parent = workspace`. Assign a fresh clone each time. **[COMMUNITY]** ([devforum](https://devforum.roblox.com/t/how-to-set-character-to-a-model/1791428))
   - The engine's own order for `LoadCharacter` is: `Character` set, then `CharacterAdded`, then appearance, then parent set, then rig build, then spawn move. **[COMMUNITY, quoting docs]** ([devforum](https://devforum.roblox.com/t/improved-documentation-around-spawning-players-with-playerloadcharacter-and-playerscharacterautoloads/670533))
3. **`Player:LoadCharacter()`** is server-only and clears the Backpack and PlayerGui (ScreenGuis with `ResetOnSpawn = false` survive; UNVERIFIED). ([wiki](https://roblox.fandom.com/wiki/LoadCharacter))

### Humanoid settings for custom rigs
- **`HipHeight`** [COMMUNITY]:
  - R15: distance from the ground to the bottom of the HumanoidRootPart. Total height = `0.5 * HRP.Size.Y + HipHeight`.
  - R6: measured to the bottom of the legs, or to the HumanoidRootPart if there are no legs.
  - Do not put the HumanoidRootPart on the ground with HipHeight 0 on R15. It causes skidding.
  - Sources: [devforum](https://devforum.roblox.com/t/r15-anyone-know-how-to-properly-reset-hipheight-when-replacing-limbs-with-new-package-pieces/127383), [devforum](https://devforum.roblox.com/t/humanoidrootpart-positioning-adjustment-for-automatically-scaled-humanoids/258555)
- **`AutomaticScalingEnabled`:** R15 auto-creates `OriginalSize` Vector3Values in limbs and rescales them ([api mirror](https://robloxapi.github.io/ref-temp/class/Humanoid.html)). Set it to `false` for fixed-size code-built rigs (behaviour detail UNVERIFIED).
- **`RigType`** (`Enum.HumanoidRigType.R6` or `.R15`) ([enum](https://create.roblox.com/docs/reference/engine/enums/HumanoidRigType.md)).
  - Inference, not confirmed: an **R6-topology** rig (Torso, Head, "Left Arm"… with "Neck", "Left Shoulder"… joints) avoids two R15-only behaviours: rebuilding joints from rig attachments, and the Avatar Joint Upgrade (a forum user reports R6 is unaffected).
- **Avatar Joint Upgrade** [OFFICIAL]:
  - Property: `StarterPlayer.AvatarJointUpgrade : Enum.RolloutState`. RobloxScriptSecurity and not replicated, so set it in Studio or the place file.
  - When enabled, each Motor6D in spawned characters becomes `BallSocketConstraint` + `AnimationConstraint` (+ `NoCollisionConstraint`). `IsKinematic = true` by default.
  - Whether it applies to rigs assigned via `player.Character =` is UNVERIFIED. Write joint code that accepts both `Motor6D` and `AnimationConstraint`.
  - Sources: [devforum](https://devforum.roblox.com/t/avatar-joint-upgrade-for-physically-simulated-character-movement-is-now-live/4298561), [beta thread](https://devforum.roblox.com/t/studio-beta-avatar-joint-upgrade-enabling-physically-simulated-characters/3266099)
- **Default scripts** (UNVERIFIED): characters get the default `Animate`/`Health` scripts from StarterCharacterScripts. Ship empty LocalScripts named `Animate` and `Health` there to suppress them. Whether these copy for manually assigned characters is also UNVERIFIED.

### Stopping falls and flings [COMMUNITY]
- Call `Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)` and the same for `Ragdoll`.
  - Run it where the humanoid is simulated: on the client for players, on the server for NPCs.
  - Toggling `PlatformStand` back to false can fling.
  - For NPCs, `SetNetworkOwner(nil)` before ragdolling helps.
- Sources: [devforum](https://devforum.roblox.com/t/2510557), [devforum](https://devforum.roblox.com/t/platformstand-is-flinging-after-unragdoll/1034393), [devforum](https://devforum.roblox.com/t/ragdoll-problems/3020256)

### Physics-based alternative: Character Controller Library [OFFICIAL]
- Classes: `ControllerManager` (`RootPart`, `BaseMoveSpeed`, `MovingDirection`, `ActiveController`) with `GroundController`, `AirController`, `ClimbController`, `SwimController` and `ControllerPartSensor` (`SensedPart`).
- Set `Humanoid.EvaluateStateMachine = false`. `Humanoid.MoveDirection` still updates from input.
- Gotchas [COMMUNITY]:
  - Massless feet cause twitching.
  - The controller deactivates when the ground sensor's `SensedPart` is nil.
  - The Humanoid still changes CanCollide on parts.
- Sources: [docs](https://create.roblox.com/docs/characters/character-controller-library/controllers), [docs](https://create.roblox.com/docs/reference/engine/classes/ControllerManager.md), [zenn guide](https://zenn.dev/landho_roblox/articles/6adeeeede632f0), [devforum](https://devforum.roblox.com/t/releasing-character-physics-controllers/2623426), [devforum](https://devforum.roblox.com/t/controllermanagers-in-characters-with-massless-feet-causes-twitching-when-facing-diagonally/2726367)

### Cosmetic parts
- **[OFFICIAL]** `CanCollide` controls collisions. `CanQuery` controls whether spatial queries see the part. ([BasePart](https://create.roblox.com/docs/en-us/reference/engine/classes/BasePart))
- **[COMMUNITY]** `CanTouch = false` plus `CanCollide = false` skips collision work, but raycasts still see the part unless `CanQuery = false`. ([overdare docs](https://docs.overdare.com/api-reference/classes/basepart))
- Recommended for cosmetic parts: unanchored, welded, `Massless = true`, `CanCollide`/`CanTouch`/`CanQuery = false`. Keep dedicated hurtbox parts with `CanQuery = true`. Exact Massless semantics in an assembly are UNVERIFIED (budget ran out).

### Network ownership and camera (UNVERIFIED this session; standard API)
- Player character assemblies are owned by that client.
- Server-side `BasePart:SetNetworkOwner(nil | player)` errors on anchored parts. Use `nil` for NPC bosses.
- The default CameraModule sets `CameraSubject` to the Humanoid when `Player.Character` changes.
- For a custom camera: `Camera.CameraType = Scriptable` and `RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, fn)`. Bind-to-render-step only for camera-type work [OFFICIAL]: ([task scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler)).

```lua
-- Server spawner pattern (untested). Set Players.CharacterAutoLoads=false in project.json.
local Players = game:GetService("Players")
local RigBuilder = require(game:GetService("ServerStorage"):WaitForChild("RigBuilder"))
local function spawnRig(player: Player)
	local rig: Model = RigBuilder.build(player.UserId) -- Humanoid + HumanoidRootPart, PrimaryPart set
	rig.Name = player.Name
	rig:PivotTo(CFrame.new(0, 6, 0))
	player.Character = rig      -- engine order: Character set, then parented
	rig.Parent = workspace
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.Died:Once(function() task.delay(Players.RespawnTime, spawnRig, player) end)
end
Players.PlayerAdded:Connect(spawnRig)
```

---

## 3. Procedural animation in code

### Writing `Motor6D.Transform` [OFFICIAL]
- An Animator overwrites `Transform` every frame, **after `RunService.PreAnimation` and before `RunService.PreSimulation`**.
- Transforms are applied in a batch, in a parallel job right after PreSimulation and just before physics.
- **Write `Transform` in `RunService.PreSimulation`.**
- Sources: [Motor6D docs](https://create.roblox.com/docs/reference/engine/classes/Motor6D.md), [devforum](https://devforum.roblox.com/t/critical-bug-animation-overriding-motor6dtransform/3630180)
- **[OFFICIAL]** Even with no Animator, PreSimulation is the last Luau event before Transform is applied. ([task scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler))
- **[COMMUNITY]** `Heartbeat`/`PostSimulation` is too late. Animators reportedly reset Transforms only while tracks are playing. ([devforum](https://devforum.roblox.com/t/critical-bug-animation-overriding-motor6dtransform/3630180))
- The documented PostSimulation/Heartbeat ordering is disputed [COMMUNITY]. ([devforum](https://devforum.roblox.com/t/the-documentation-about-the-ordering-of-runservice-events-is-incorrect/3579327))

### Animator, replication and constraints
- You do not need to remove the Animator. A PreSimulation write wins.
- To layer over playing tracks, multiply your offset into `Transform` during PreSimulation [OFFICIAL]. ([AnimationConstraint guide](https://create.roblox.com/docs/physics/constraints/animation))
- **Replication:** `Transform` is local only. Each client computes poses from compact replicated state (attributes or an UnreliableRemoteEvent). Server-side `C0` changes do replicate but cost bandwidth. **[COMMUNITY]** ([Motor6D page summary](https://create.roblox.com/docs/reference/engine/classes/Motor6D.md))
- **`AnimationConstraint.Transform`** has the same rules: write in PreSimulation; `IsKinematic = true` behaves like a Motor6D; with `false`, `MaxForce`/`MaxTorque` drive it physically. [OFFICIAL] ([ref](https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint.md))

### Animations without uploading
- **[OFFICIAL]** `KeyframeSequenceProvider:RegisterKeyframeSequence` and `RegisterActiveKeyframeSequence` (the latter returns `active://`) give **temporary IDs that cannot be used outside Studio**. ([docs](https://create.roblox.com/docs/reference/engine/classes/KeyframeSequenceProvider.md))
- The feature request to allow this in live games is still open. ([devforum](https://devforum.roblox.com/t/create-animations-from-keyframesequences-in-live-games/2222384))
- **[OFFICIAL]** `AnimationClipProvider:RegisterAnimationClip` and `RegisterActiveAnimationClip` have the same Studio-only limit. `CurveAnimation` only plays from an uploaded asset. ([docs](https://create.roblox.com/docs/reference/engine/classes/AnimationClipProvider.md))
- **Conclusion: no runtime-authored Animation assets in live games. Use Transform, C0 or CFrame procedural animation.**
- Third-party runtime animation engine: Fluxa ([devforum](https://devforum.roblox.com/t/fluxa-a-custom-runtime-animation-engine-for-roblox/4573039)). The Animation Graph System (beta) is described [COMMUNITY] as authoring-only and not editable at runtime ([same thread](https://devforum.roblox.com/t/fluxa-a-custom-runtime-animation-engine-for-roblox/4573039)).
- **Roblox-owned animation IDs** (default Animate packages):
  - **[COMMUNITY]** Assets owned by Roblox are usable anywhere; user animations only play in experiences owned by the same creator. ([devforum](https://devforum.roblox.com/t/running-foreign-animations-in-my-game/3404809))
  - Others report failures. Treat as UNVERIFIED. ([devforum](https://devforum.roblox.com/t/public-animations/43299/34))

### Performance tips (recommendations, not sourced facts)
- Use one PreSimulation connection per client.
- Cache joint references and base CFrames.
- Skip rigs that are far away or off-screen.
- Avoid `FindFirstChild` calls inside the loop.
- Move many anchored VFX parts with `workspace:BulkMoveTo` ([WorldRoot](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#BulkMoveTo)).
- Whether Parallel Luau can write Transform is UNVERIFIED.

```lua
-- Client: StarterPlayerScripts/ProceduralAnimator.client.luau (pattern)
local RunService = game:GetService("RunService")
type Driver = { joint: Motor6D, pose: (t: number, dt: number) -> CFrame }
local drivers: { Driver } = {}
RunService.PreSimulation:Connect(function(dt)
	local t = os.clock()
	for _, d in drivers do
		d.joint.Transform = d.pose(t, dt) -- local-only; applied in batch before physics
	end
end)
```

---

## 4. EditableMesh / EditableImage

### Status (is it production-safe?)
- Published-game use was announced Nov 2024 ([Roblox on X](https://x.com/Roblox/status/1859359050326213031)) and is still labelled **Client Beta** (Jan 2025 update) ([devforum](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293)).
- **[OFFICIAL]** Use "fails by default for published experiences." The creator must be **13+ age-verified and ID-verified**. ([EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh))
- How to enable: Studio → Game Settings → Security → "Allow Mesh / Image APIs". For group games, the group owner must be verified and flip the toggle. Studio plugins (edit mode) work without it. ([devforum](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293))
- **[OFFICIAL staff reply]** Only the owner needs verification, not players. Using Editable* does not make the experience 13+. ([devforum p6](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293?page=6))
- Assets can only be loaded from meshes the creator owns. This does not matter for blank meshes. ([EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh))
- **[OFFICIAL]** As of Sep 2026, Roblox is "still working on enabling replication, reconciling the extra ID Verification requirement… and permissions restrictions." ([devforum](https://devforum.roblox.com/t/full-release-editablemesh-batching-apis-parallel-queries/4779401))
- **Verdict:** usable in production but beta-labelled, client-only and memory-budgeted. Build each mesh deterministically on every client in a LocalScript. Wrap creation in `pcall` and fall back to Part-based geometry.

### Limits
- **[OFFICIAL]** 60,000 vertices and 20,000 triangles per EditableMesh; exceeding this errors.
- **[OFFICIAL]** Strict client memory budgets; server, Studio and plugins are unlimited.
- **[OFFICIAL]** `FixedSize` meshes use less memory. One EditableMesh can be linked to multiple MeshParts.
- Sources: [EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh.md)
- **[OFFICIAL]** EditableImage maximum is 1024×1024; larger sizes are clamped. ([Size](https://create.roblox.com/docs/reference/engine/classes/EditableImage/Size))
- **[beta-era staff, may be outdated]** One EditableImage update per frame. **[COMMUNITY]** About 8 editable meshes per client. ([devforum p19](https://devforum.roblox.com/t/client-beta-in-experience-mesh-image-apis-now-available-in-published-experiences/3267293?page=19))

### API [OFFICIAL]
- Creation:
  - `AssetService:CreateEditableMesh(options?)` creates a blank mesh.
  - `AssetService:CreateEditableMeshAsync(content, {FixedSize = bool})`
  - `AssetService:CreateEditableImage({ Size = Vector2.new(256, 256) })`
  - `AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh))` returns a MeshPart.
  - Sources: [EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh), [EditableImage](https://create.roblox.com/docs/fr-fr/reference/engine/classes/EditableImage)
- EditableMesh methods ([tr-tr ref](https://create.roblox.com/docs/tr-tr/reference/engine/classes/EditableMesh), [it-it ref](https://create.roblox.com/docs/it-it/reference/engine/classes/EditableMesh)):
  - `AddVertex(p: Vector3): number`
  - `AddTriangle(v0: number, v1: number, v2: number): number`
  - `AddNormal(normal: Vector3?): number`
  - `AddUV(uv: Vector2): number`
  - `AddColor(color: Color3, alpha: number): number`
  - `SetFaceColors(faceId, ids)`, `SetFaceNormals(faceId, ids)`, `SetFaceUVs(faceId, ids)`
  - `SetUV`, `RaycastLocal`
- EditableImage methods:
  - `DrawRectangle(position: Vector2, size: Vector2, color: Color3, transparency: number, combineType: Enum.ImageCombineType)`. The position must be inside the canvas.
  - `DrawCircle(center, radius, color, transparency, combineType)`
  - `WritePixelsBuffer(...)`: RGBA, 4 bytes per pixel, buffer length `X*Y*4`.
  - Resizing crops or pads with transparent pixels; it does not rescale.

### Baking and batching
- **`CreateDataModelContentAsync` (Full Release 2026)** bakes editable data into static Content for the session. It is one-way.
  - Whether baked content replicates is **UNVERIFIED**.
  - **[COMMUNITY]** Measured costs:
    - Bake: about 7 ms + 3.6 ms per 1k triangles.
    - `CreateMeshPartAsync`: about 22 ms + 0.27 ms per 1k triangles.
    - About 20 ms main-thread stall on first use.
  - Sources: [devforum](https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898), [devforum](https://devforum.roblox.com/t/allow-applying-baked-mesh-content-to-a-meshpart-without-a-lag-spike/4752538), [devforum](https://devforum.roblox.com/t/createmeshpartasync-stalls-the-main-thread-20-ms-on-first-use-of-new-datamodelcontent/4884694)
- **EditableMesh batching APIs and parallel queries:**
  - Studio Beta Aug 2026; nine batch methods such as `BatchGetFaceAttributes`; up to about 8× faster; no skinning support.
  - The thread is titled "Full Release," but availability in published games is **UNVERIFIED**.
  - Source: [devforum](https://devforum.roblox.com/t/full-release-editablemesh-batching-apis-parallel-queries/4779401)

---

## 5. Networking and server-authoritative combat

### Remotes [OFFICIAL]
- `RemoteEvent` and `UnreliableRemoteEvent`: about **500 requests/s per client**, shared among remotes of the same type. This is a client-to-server limit. ([RemoteEvent](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent.md))
- UnreliableRemoteEvent is unordered and can drop for packet loss or engine load.
- Its payload limit is **1000 bytes** (older docs say 900). Oversized events are dropped, and Studio logs the overflow.
- Buffers are compressed, so exact sizes are hard to predict.
- Sources: [ref](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent.md), [announcement](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155)
- Use Unreliable for continuous cosmetic state such as aim or pose. Use reliable `RemoteEvent` for discrete actions (attack, ability, dodge).

### Security guidance [OFFICIAL]
- Assume all client data is manipulated; the server is the final authority.
- Validate argument types and plausibility against theoretical maximums, with latency tolerance.
- Quietly drop or clamp bad input. Do not ban based on client-side checks.
- Sources: [security tactics](https://create.roblox.com/docs/scripting/security/security-tactics.md), [client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary.md), [server-side detection](https://create.roblox.com/docs/scripting/security/server-side-detection.md)

### Spatial queries (WorldRoot) [OFFICIAL]
- Overlap queries:
  - `GetPartBoundsInBox(cframe, size, overlapParams)`
  - `GetPartBoundsInRadius(position, radius, overlapParams)`
  - `GetPartsInPart(part, overlapParams)`
- Shape casts:
  - `Blockcast(cframe: CFrame, size: Vector3, direction: Vector3, params: RaycastParams): RaycastResult?`
  - `Spherecast(position, radius, direction, params)`
  - `Shapecast(part: BasePart, direction, params)`
  - Maximum shape size 512 studs; maximum cast distance 1024 studs.
  - Casts that start flush with or inside a part do not detect it, so run an overlap query first.
  - `RaycastParams.Margin` expands Shapecast shapes.
- Sources: [WorldRoot](https://create.roblox.com/docs/en-us/reference/engine/classes/WorldRoot), [RaycastParams](https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams.md), [shapecasts](https://devforum.roblox.com/t/introducing-generalized-shapecasts/2804272)
- **`OverlapParams`** ([docs](https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams), [Tolerance](https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams/Tolerance)):
  - `FilterDescendantsInstances` with `FilterType` (`Enum.RaycastFilterType.Exclude` by default, or `Include`).
  - **New:** `ExcludeInstances` / `IncludeInstances`, preferred for new work.
  - `AddToFilter(instance | {instances})`
  - `MaxParts` (0 = unlimited), `CollisionGroup`, `RespectCanCollide`, `Tolerance`.
  - `BruteForceAllSlow`: do not use in live games.

### Server Authority (opt-in) [OFFICIAL]
- Setting `Workspace.AuthorityMode = Enum.AuthorityMode.Server` auto-sets the required settings, including StreamingEnabled and next-gen replication. They cannot be changed while it is on.
- Core logic goes in a ModuleScript running on both sides, via `RunService:BindToSimulation(fn)`. Rollback re-runs those functions.
- Read InputActions inside the bound functions. Only APIs labelled as simulation-safe are allowed there.
- `RunService:SetPredictionMode(instance, Enum.PredictionMode)`: `Off` means server-owned with no prediction. RemoteEvents still work for discrete messages.
- It blocks flyhack and speedhack classes of cheats. Games using default avatars and simple physics need no rewrite.
- Sources: [docs](https://create.roblox.com/docs/projects/server-authority), [enum](https://create.roblox.com/docs/reference/engine/enums/AuthorityMode.md), [devforum](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)
- Older community alternative: Chickynoid ([devforum](https://devforum.roblox.com/t/chickynoid-server-authoritative-character-replacement/1660558)).

### Recommended melee flow (my synthesis)
- The client plays the wind-up and VFX immediately, then sends `Attack(id, aim)`.
- The server checks cooldown and state, builds the hitbox at the server-side character CFrame and runs `GetPartBoundsInBox` with Include = hurtbox folder.
- It de-duplicates hits per Humanoid and applies damage.
- For lag compensation, keep about 1 s of root-CFrame history per character and rewind by the measured ping, capped. `workspace:GetServerTimeNow()` and `Player:GetNetworkPing()` exist but their exact semantics are UNVERIFIED.

```lua
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace:WaitForChild("Hurtboxes") }
params.MaxParts = 64
local hits = workspace:GetPartBoundsInBox(root.CFrame * CFrame.new(0, 0, -3), Vector3.new(5, 6, 6), params)
```

---

## 6. UI

### Fonts
- **[OFFICIAL]** `Enum.Font` is legacy. Use `GuiObject.FontFace = Font.new(family: Content, weight?: Enum.FontWeight, style?: Enum.FontStyle)`, `Font.fromEnum(...)` or `Font.fromId(assetId: number, ...)`. ([Font datatype](https://create.roblox.com/docs/reference/engine/datatypes/Font), [enum](https://create.roblox.com/docs/reference/engine/enums/Font))
- **[COMMUNITY]** `Font.fromId` takes a **number**, not an `rbxassetid://` string. ([devforum](https://devforum.roblox.com/t/fontfromid-not-working-with-rbxassetid-in-roblox-studio/2459526))
- **Pixel and retro built-ins:**
  - `Enum.Font.Arcade` (13) = `rbxasset://fonts/families/PressStart2P.json`, Regular only.
  - `Code` = `rbxasset://fonts/families/Inconsolata.json` (monospace, Extra Light to Black).
  - `RobotoMono` (41) = `RobotoMono.json`
  - `SciFi` = `Zekton.json`
  - `SpecialElite.json` (typewriter), `Michroma` (34), `Oswald` (Extra Light to Bold).
  - Sources: [Font datatype](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Font.md), [dev ref](https://developer.roblox.com/api-reference/datatype/Font)
  - `Cartoon` likely maps to Comic Neue Angular, which would suit Sans's dialogue (UNVERIFIED).
- **Verified enum numbers** ([robloxapi](https://robloxapi.github.io/ref/enum/Font.html), [enum](https://create.roblox.com/docs/reference/engine/enums/Font)):
  - Legacy 0, Arcade 13, AmaticSC 21, Bangers 22, Creepster 23, DenkOne 24, FredokaOne 26, GrenzeGotisch 27, IndieFlower 28, JosefinSans 29, Jura 30, LuckiestGuy 32, Michroma 34, PatrickHand 37, PermanentMarker 38, RobotoMono 41, Sarpanch 42, TitilliumWeb 44, Ubuntu 45, BuilderSans 46 / Medium 47 / Bold 48 / ExtraBold 49, Unknown 100.
  - Gap-fill from memory (UNVERIFIED): Fondamento 25, Kalam 31, Merriweather 33, Nunito 35, Oswald 36, Roboto 39, RobotoCondensed 40, SpecialElite 43.
- **Creator Store fonts** (Roblox-uploaded Google Fonts):
  - **[OFFICIAL]** Examples: Akronim 12187368317, Are You Serious 12187363616, Parisienne 12187361943. Roblox's stated goal was the whole Google Fonts catalog. ([devforum](https://devforum.roblox.com/t/fonts-in-creator-marketplace-81-new-fonts/2164977))
  - **[COMMUNITY]** Silkscreen = 12187371840 ([bloxodes](https://bloxodes.com/catalog/roblox-font-ids)).
  - To get an ID: apply the font in Studio, then `print(obj.FontFace.Family)` ([guide](https://alexxander.gitbook.io/textplus/fundamentals/options/fonts)).
  - Undertale's "Determination" font: not found on Roblox (UNVERIFIED).

### Modifiers and containers
- **UIStroke:**
  - Standard properties (UNVERIFIED this session): `Thickness`, `Color`, `Transparency`, `ApplyStrokeMode` (Contextual/Border), `LineJoinMode`, `Enabled`.
  - New, Studio Beta [OFFICIAL]: `StrokeSizingMode` (FixedSize by default, or ScaledSize), `BorderStrokePosition` (Outer by default, Center, Inner), `BorderOffset: UDim` (scale relative to the parent's shorter axis), `ZIndex` among sibling strokes.
  - Sources: [devforum](https://devforum.roblox.com/t/studio-beta-uistroke-improvements-scaling-offsets-and-more/3958036), [ref](https://create.roblox.com/docs/reference/engine/classes/UIStroke.md)
- **CanvasGroup** [OFFICIAL] ([ref](https://create.roblox.com/docs/reference/engine/classes/CanvasGroup.md)):
  - `GroupTransparency`, `GroupColor3`.
  - Costs extra texture memory, capped by the client's QualityLevel; over the cap it renders blank.
  - Prefer static sizes; resizing recreates the texture.
  - Children flatten only under `ZIndexBehavior.Sibling`.
  - Known bug: GroupTransparency does not affect UIStroke ([devforum](https://devforum.roblox.com/t/uistroke-transparency-isnt-reflected-when-you-change-grouptransparency-of-a-canvasgroup/2880215)). Text blur is also reported.
- **UIGradient / UICorner / UIAspectRatioConstraint / UIScale / UIPadding / UIListLayout / UIFlexItem** (UNVERIFIED this session; budget ran out):
  - UIGradient: `Color` (ColorSequence), `Transparency` (NumberSequence), `Offset`, `Rotation`.
  - UICorner: `CornerRadius: UDim`.
  - UIAspectRatioConstraint: `AspectRatio`, `AspectType`, `DominantAxis`.
  - UIScale: `Scale`. Tweening UIScale is cheaper than tweening Size.
  - UIListLayout: `FillDirection`, `Padding`, `SortOrder`, `Wraps`, `HorizontalFlex`, `VerticalFlex`.
  - UIFlexItem: `FlexMode` (None, Grow, Shrink, Fill, Custom), `GrowRatio`, `ShrinkRatio`, `ItemLineAlignment`.

### Screen layout and mobile [OFFICIAL]
- `ScreenGui.ScreenInsets` defaults to `CoreUISafeInsets` (stays below the top bar). `DeviceSafeInsets` avoids device cut-outs. `None` is full-bleed and can be clipped by notches.
- `ClipToDeviceSafeArea` (default changed to true in v553).
- `SafeAreaCompatibility`: `None` or `FullscreenExtension` (default).
- Pattern: backgrounds in a ScreenGui with `ScreenInsets = None`; text and buttons in a ScreenGui with CoreUISafeInsets or DeviceSafeInsets.
- `IgnoreGuiInset` is the older mechanism (relationship to ScreenInsets UNVERIFIED).
- Sources: [ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui.md), [notch support](https://devforum.roblox.com/t/notched-screen-support-full-release/2074324)

### Blur and tweens
- **BlurEffect:** Gaussian blur over the 3D world; depends on device and quality level ([ref](https://create.roblox.com/docs/reference/engine/classes/BlurEffect.md)).
  - **[COMMUNITY]** `Size` maximum 56; 10–20 is good for menus; may be disabled at the lowest graphics settings; reuse one instance ([site](https://robloxblureffectsizescript.pages.dev)).
- **TweenService** [OFFICIAL mirror] ([ref](https://robloxapi.github.io/ref-temp/class/Tween.html)):
  - `TweenService:Create(obj, TweenInfo, goals)` is the only way to create tweens.
  - Defaults: 1 s, Quad, Out (full constructor: `TweenInfo.new(time, style, dir, repeatCount, reverses, delay)`).
  - A tween's configuration cannot be changed after creation.
  - A newer tween on the same property cancels the older one.
  - `TweenService:GetValue` and `TweenService:SmoothDamp` are UNVERIFIED. Use your own springs for re-targeting motion.

### Input
- **Input Action System** [OFFICIAL] ([docs](https://create.roblox.com/docs/input/input-action-system), [InputActionType](https://create.roblox.com/docs/reference/engine/enums/InputActionType.md), [InputAction](https://create.roblox.com/docs/reference/engine/classes/InputAction.md)):
  - Hierarchy: `InputContext` → `InputAction` (`Type: Enum.InputActionType` Bool / Direction1D / Direction2D …) → `InputBinding` (`KeyCode`, `UIButton` links a GuiButton for touch, `Up`/`Down`/`Left`/`Right` for 2D composites).
  - Events: `Pressed` and `Released` (Bool only), `StateChanged` (all types). Method: `GetState()`.
  - Contexts can be enabled, disabled and prioritised.
  - **[COMMUNITY]** `InputAction:Fire` is deprecated.
- **`UserInputService.PreferredInput`** (`Enum.PreferredInput`: Touch, Gamepad, KeyboardAndMouse) is read-only. Listen with `GetPropertyChangedSignal("PreferredInput")`. Use `GetImageForKeyCode` for gamepad glyphs. ([devforum](https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890))
- **ContextActionService** [OFFICIAL] ([ref](https://create.roblox.com/docs/reference/engine/classes/ContextActionService.md)):
  - `BindAction(name, fn, createTouchButton: boolean, ...inputs)`
  - `SetTitle`, `SetImage`, `SetPosition`
  - `GetButton(name)` returns the ImageButton, which lives in "ContextButtonFrame".
  - `UnbindAction` removes the button.
- For fully styled mobile buttons, prefer your own ImageButtons wired through IAS `UIButton`.

---

## 7. Audio

### Built-in files (no upload)
- Paths from the `RbxCharacterSounds` `SOUND_DATA` table. Copy that script from PlayerScripts in Play mode to confirm.
  - Seen in a source:
    - `rbxasset://sounds/action_footsteps_plastic.mp3` (Climbing, Running)
    - `rbxasset://sounds/action_falling.ogg` (note: **.ogg**)
    - `rbxasset://sounds/action_get_up.*` (extension cut off in the source)
    - `rbxasset://sounds/action_jump_land.mp3`
  - From memory (UNVERIFIED): `action_jump.mp3`, `impact_water.mp3`, `action_swim.mp3`
  - Sources: [codepal snippet](https://codepal.ai/chat/query/c1Hr2dip/roblox-character-sound-management-guide), [devforum](https://devforum.roblox.com/t/how-can-i-change-or-alter-the-default-water-sounds/1941545), [devforum](https://devforum.roblox.com/t/i-chose-a-custom-jump-sound-and-its-saying-unable-to-download/1285514)
- **[COMMUNITY]** Classic sounds: `rbxasset://sounds/uuhhh.mp3`, `electronicpingshort.mp3` (a `.wav` is also reported), `swordslash.mp3`. The old `swoosh.mp3` jump sound is reported unsupported now. ([repo](https://github.com/Githolz/All-Classic-Roblox-Sound-Paths-), [devforum](https://devforum.roblox.com/t/old-roblox-sound-library-module/1587036/2))
- Built-in SFX are few and low quality. Probe at runtime with `ContentProvider:PreloadAsync(list, cb)` (callback signature UNVERIFIED).

### Creator Store audio [OFFICIAL]
- Toolbox → Creator Store tab → Audio has more than 100,000 free-to-use SFX and music tracks from Roblox and its partners. Reference them as `rbxassetid://<id>` with no upload. ([docs](https://create.roblox.com/docs/audio/assets))
- **[OFFICIAL]** Licensed music (APM, Monstercat history) is royalty-free on Roblox but not downloadable. ([devforum](https://devforum.roblox.com/t/roblox-monstercat-3/688452))
- **[COMMUNITY]** The ToU bans music-library or streaming experiences and allows up to 250 distinct licensed tracks at once. Some tracks have been taken down, so handle load failures. ([devforum](https://devforum.roblox.com/t/music-on-roblox-tos-rule/3305661), [devforum](https://devforum.roblox.com/t/apm-audio-8-bit-kicks-a-was-recently-blocked-for-copyright-reasons/1782862))
- Unlicensed music that gets flagged is replaced with licensed music ([devforum](https://devforum.roblox.com/t/upcoming-music-changes-and-copyright-related-action/130570)). **Undertale's soundtrack (for example, Megalovania) cannot be used.**
- Uploading your own audio requires rights to it. Limits: 2,000 per 30 days if ID-verified, 100 otherwise ([docs](https://create.roblox.com/docs/audio/assets)).

### New Audio API
- Exited beta (date UNVERIFIED) ([devforum](https://devforum.roblox.com/t/roblox-audio-api-exits-beta-enhanced-sound-controls-now-available/3153454)).
- Instances:
  - `AudioPlayer`: `Asset` (`AssetId` is deprecated), `AutoLoad`, `Looping`, `Volume` (0–3), `PlaybackSpeed`, `TimePosition`, `TimeLength`, `LoopRegion`, `PlaybackRegion`, `Play()`, `Stop()`.
  - `AudioEmitter` (3D source), `AudioListener`, `AudioDeviceOutput` (2D, UI and music).
  - `Wire` (`SourceInstance` → `TargetInstance`). Without a wire there is no sound.
  - Sources: [AudioPlayer](https://create.roblox.com/docs/reference/engine/classes/AudioPlayer.md), [beta post](https://devforum.roblox.com/t/new-audio-api-beta-elevate-sound-and-voice-in-your-experiences/2848873)
- Effects: `AudioFader`, `AudioFilter`, `AudioCompressor`, `AudioGate`, `AudioLimiter`, angle attenuation ([devforum](https://devforum.roblox.com/t/3282100)). `AudioReverb`/`AudioEqualizer`/`AudioEcho` are UNVERIFIED.
- **[COMMUNITY]** Stereo through a single emitter becomes effectively mono. SoundGroups are AudioFaders internally. Legacy `Sound` still works.

```lua
local SS = game:GetService("SoundService")
local function wire(a: Instance, b: Instance) local w = Instance.new("Wire"); w.SourceInstance = a; w.TargetInstance = b; w.Parent = b end
local music = Instance.new("AudioPlayer"); music.Asset = "rbxassetid://0"; music.Looping = true; music.Parent = SS
local bus = Instance.new("AudioFader"); bus.Parent = SS          -- music volume slider
local out = Instance.new("AudioDeviceOutput"); out.Parent = SS
wire(music, bus); wire(bus, out); music:Play()
```

---

## 8. DataStores, leaderboards and badges

### Request limits
- **Old per-server formula** (still on the errors page): Get = `60 + numPlayers × 10` per minute; Set shares its budget with Update.
- **New per-experience limits** (CCU = players across all servers) [OFFICIAL]:
  - Get (`GetAsync`, `GetVersionAsync`): `250 + CCU × 40` per minute.
  - Set (`SetAsync`, `IncrementAsync`, `UpdateAsync`): `250 + CCU × 20` per minute.
  - The Oct 2026 docs show writes as `300 + CCU × 20` for standard stores (conflict).
- Sources: [limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits), [devforum](https://devforum.roblox.com/t/datastores-access-and-storage-updates/3597255)

### Per-key and size limits [OFFICIAL]
- Per key: read 25 MB/min and write 4 MB/min, over a rolling 60 s.
  - `UpdateAsync` counts toward both read and write.
  - `IncrementAsync` and `RemoveAsync` count toward write.
  - Usage is rounded up per request.
- **The 6-second write cooldown was removed.**
- Value size is at most 4,194,304 bytes; error 105 is ValueTooLarge. Check with `JSONEncode`.
- Sources: [limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits), [devforum](https://devforum.roblox.com/t/removal-of-6s-cool-down-for-data-stores/2436230)

### Storage cap [OFFICIAL]
- 100 MB + 1 MB × lifetime players, shared by all stores.
- Warnings at 60/80/90/100 %. Check usage in Data Stores Manager. Extra capacity via Extended Services.
- Sources: [devforum](https://devforum.roblox.com/t/datastores-access-and-storage-updates/3597255), [devforum](https://devforum.roblox.com/t/extended-services-for-data-stores-is-now-available/4504347)

### Best practice
- **[OFFICIAL]** Read once on join, write on leave (plus autosave and `BindToClose`). Retry with fallback to default data. Use **session locking** to stop stale overwrites and item duplication. ([docs](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing), [best practices](https://create.roblox.com/docs/en-us/cloud-services/data-stores/best-practices))
- **[COMMUNITY]** Use ProfileService, or refresh a `{jobId, os.time()}` lock every 30–60 s. ([devforum](https://devforum.roblox.com/t/datastore-best-practices/2845439), [devforum](https://devforum.roblox.com/t/datastore-with-sessionlocking/1139113))
- UNVERIFIED this session:
  - `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.X)`.
  - Returning `nil` from the UpdateAsync transform cancels the write.

### OrderedDataStore [OFFICIAL]
- `GetSortedAsync(ascending: boolean, pagesize: number = 50 (max 100), minValue?, maxValue?): DataStorePages`
- Values must be integers (some docs say positive integers).
- Read with `GetCurrentPage()` and `AdvanceToNextPageAsync()`.
- Sources: [ref](https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore), [devforum](https://devforum.roblox.com/t/ordereddatastoregetsortedasync-incomplete-documentation/372281)

### Badges [OFFICIAL]
- **Badges must be created in the Creator Dashboard**: experience ⋯ → Create Badge; they appear under Engagement → Badges.
- Five free per 24 h (GMT) per experience, then 100 Robux each.
- Source: [docs](https://create.roblox.com/docs/production/publishing/badges)
- Awarding with `BadgeService:AwardBadge(userId, badgeId)` (server) comes from a third-party example. `UserHasBadgeAsync` and `GetBadgeInfoAsync` signatures and limits are UNVERIFIED.

---

## 9. Place and Workspace settings, plus Rojo 7

### Workspace
- **`SignalBehavior`** [OFFICIAL]: `Default` is currently equivalent to **Immediate** and will eventually become Deferred (doc of Oct 19, 2026). Template places use `Deferred`. **Set `Deferred` explicitly.** ([enum](https://create.roblox.com/docs/reference/engine/enums/SignalBehavior.md), [docs](https://create.roblox.com/docs/scripting/events/deferred.md))
- **`PhysicsSteppingMethod`** [OFFICIAL]: Default and Fixed run at 240 Hz. `Adaptive` uses solver islands at 60–240 Hz, is up to 2.5× faster and is "recommended in most cases." ([docs](https://create.roblox.com/docs/physics/adaptive-timestepping))
- **`FallenPartsDestroyHeight`** (number) destroys parts that fall below it ([Workspace](https://create.roblox.com/docs/reference/engine/classes/Workspace)). The default of -500 is UNVERIFIED.
- **Streaming:**
  - **[COMMUNITY]** StreamingEnabled is on by default for new places; radii default to 64/1024 ([blog](https://gamertagmythras.com/blog/roblox/roblox-instance-streaming-guide)).
  - **[OFFICIAL]** `ModelStreamingMode`: Default, Atomic, Persistent ([enum](https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode.md)).
  - **[OFFICIAL]** `StreamingIntegrityMode`: Default, Disabled, MinimumRadiusPause ([enum](https://create.roblox.com/docs/reference/engine/enums/StreamingIntegrityMode.md)).
  - For a small arena, either disable streaming or mark arena models Persistent. Note that `AuthorityMode = Server` forces streaming on.
- **`Workspace.AuthorityMode`**: see §5.

### Lighting
- Set `LightingStyle = "Realistic"` and `PrioritizeLightingQuality = true`. This is the old Future look.
- Old Technology values map as: Future → Realistic + true; ShadowMap → Soft + true; Voxel → Soft + false.
- **[COMMUNITY]** Realistic only engages at high graphics quality; one user reports level 11 in Studio.
- Sources: [devforum](https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512), [docs](https://create.roblox.com/docs/environment/lighting)

### Rojo 7 project format
- Keys: `$className`, `$path`, `$properties`, `$ignoreUnknownInstances`. `$className` is required when `$path` is absent. ([source](https://docs.rs/rojo/7.4.0/src/librojo/project.rs.html), [docs](https://rojo.space/docs/v7/project-format/))
- Implicit values: enums as strings (an invalid variant errors), arrays for Vector3/Color3, plain booleans.
- Explicit Rojo 7 form: `{"Enum": 4}`. Needed for properties or enums Rojo's reflection database does not know yet, or when the type differs. ([upgrade guide](https://rojo.space/docs/v7/upgrade/))
- `"emitLegacyScripts": false` makes `*.server.luau` and `*.client.luau` become Scripts with RunContext Server or Client ([changelog](https://docs.rs/crate/ken-rojo/7.4.0/source/CHANGELOG.md)).
- `*.meta.json` supports `properties`, `className` (in `init.meta.json` only) and `ignoreUnknownInstances`.
- Live sync of Attributes and Tags since 7.2 ([changelog](https://docs.rs/crate/rojo/7.2.0/source/CHANGELOG.md)). Ref properties link via `$id` plus a `Rojo_Target_<Prop>` attribute (7.5/7.6).
- The exact `$attributes` key syntax in project.json is UNVERIFIED.
- **Gotcha (inference):** RobloxScriptSecurity properties (`LightingStyle`, `PrioritizeLightingQuality`, `AvatarJointUpgrade`) probably cannot be live-synced by the plugin. Bake them with `rojo build`, or set them once in Studio.

```json
{
  "name": "JudgementGame",
  "emitLegacyScripts": false,
  "tree": {
    "$className": "DataModel",
    "Workspace": { "$className": "Workspace", "$properties": {
      "SignalBehavior": "Deferred", "PhysicsSteppingMethod": "Adaptive",
      "StreamingEnabled": false, "FallenPartsDestroyHeight": -200 } },
    "Lighting": { "$className": "Lighting", "$properties": {
      "LightingStyle": "Realistic", "PrioritizeLightingQuality": true, "GlobalShadows": true } },
    "Players": { "$className": "Players", "$properties": { "CharacterAutoLoads": false } },
    "ReplicatedStorage": { "$className": "ReplicatedStorage", "Shared": { "$path": "src/shared" } },
    "ServerScriptService": { "$className": "ServerScriptService", "Server": { "$path": "src/server" } },
    "StarterPlayer": { "$className": "StarterPlayer",
      "StarterPlayerScripts": { "$className": "StarterPlayerScripts", "Client": { "$path": "src/client" } } }
  }
}
```

---

## 10. Luau: usable features and deprecations

### Usable now
- **Task library:**
  - `task.wait`, `task.spawn`, `task.defer`, `task.delay`, `task.cancel`, `task.synchronize`, `task.desynchronize`.
  - Old `wait` has a longer minimum delay than `task.wait`. The closest replacement for `spawn` is `task.defer` (it resumes next frame).
  - Roblox plans to deprecate `wait`/`spawn`/`delay` but they keep working.
  - Source: [devforum](https://devforum.roblox.com/t/deeper-look-into-wait/2178317)
- **Require-by-string** [OFFICIAL] ([devforum](https://devforum.roblox.com/t/introducing-require-by-string/3405078), [RFC](https://rfcs.luau.org/new-require-by-string-semantics.html)):
  - Relative paths must start with `./` or `../`. Folders with an init module are supported. Strict mode type-errors unresolved paths.
  - Rojo works with it, but its init-file semantics differ.
  - Aliases were not available at launch; current alias support is UNVERIFIED. The announcement date is also UNVERIFIED (likely early 2025).
  - Recommendation: keep instance-path requires in a Rojo project.
- **New type solver** [OFFICIAL]: general release late Nov 2025. Includes `type function` and read-only table properties. Not fully backward compatible. Opt out with the `UseNewLuauTypeSolver` property. ([devforum](https://devforum.roblox.com/t/general-release-luau%E2%80%99s-new-type-solver/4084991), [guide](https://devforum.roblox.com/t/luaus-new-type-solver-how-to-utilize-type-functions/3637378))
- **`--!native` and `@native`:** documented for **server** scripts. Client support is not confirmed; a community report says client native code only runs in Studio. ([update](https://devforum.roblox.com/t/luau-native-code-generation-preview-update/2961746), [devforum](https://devforum.roblox.com/t/native-codegen-works-in-localscripts-in-studio-but-not-in-the-client/2710130))
- **`vector` library and `math.lerp`** shipped in 2025 ([recap](https://luau.org/news/2025-12-19-luau-recap-runtime-2025/), [RFC](https://rfcs.luau.org/vector-library.html)). The vector library includes `vector.create`, floor, ceil, abs, sign, clamp, max, min, zero and one.
- **64-bit integer type:** only an initial open-source implementation (Luau 0.715). **Do not use on Roblox** (UNVERIFIED there). ([release](https://github.com/luau-lang/luau/releases/tag/0.715))
- `buffer`, `table.freeze`, `table.clone`, string interpolation and `//`: established features (UNVERIFIED this session).

### Avoid, and use instead
| Avoid | Use instead |
|---|---|
| `wait` / `spawn` / `delay` | `task.*` |
| `Humanoid:LoadAnimation` | `Animator:LoadAnimation`, with the Animator created on the server first ([devforum](https://devforum.roblox.com/t/deprecating-loadanimation-on-humanoid-and-animationcontroller/857129)) |
| `BodyVelocity` | `LinearVelocity` (applies no gravity the way BodyVelocity did) |
| `BodyGyro` | `AlignOrientation` |
| `BodyPosition` | `AlignPosition` |
| `BodyForce` / `BodyThrust` | `VectorForce` |
| `BodyAngularVelocity` | `AngularVelocity` |
| `FindPartsInRegion3` | `GetPartBoundsInBox` / `GetPartsInPart` (the `Region3` class itself is not deprecated) |
| `RenderStepped` / `Stepped` / `Heartbeat` | `PreRender` / `PreSimulation` / `PostSimulation` (status contested) |
| `Enum.Font` | `FontFace` |
| `Lighting.Technology` | `LightingStyle` + `PrioritizeLightingQuality` |
| `AudioPlayer.AssetId` | `Asset` |
| `FindPartOnRay` | `workspace:Raycast` (UNVERIFIED) |

Sources for the table: [engine llms.txt](https://create.roblox.com/docs/reference/engine/llms.txt), [devforum](https://devforum.roblox.com/t/does-it-matter-if-i-use-bodyvelocity-even-though-its-deprecated/1851566), [devforum](https://devforum.roblox.com/t/region3-is-deprecated-but-does-that-mean-i-cant-use-it/3370915), [devforum](https://devforum.roblox.com/t/heartbeat-stepped-and-renderstepped-are-deprecated-what-can-i-use-instead/1055275)

---

## 11. Things only the human owner can do in Studio or the Dashboard

1. Set `Lighting.LightingStyle = Realistic` and `PrioritizeLightingQuality = true` (scripts cannot).
2. Choose `StarterPlayer.AvatarJointUpgrade`. Disabled is simplest for Motor6D-based procedural rigs.
3. Only if smooth procedural meshes are wanted: ID-verify and 13+ age-verify the owner account, then turn on Game Settings → Security → "Allow Mesh / Image APIs".
4. Create badges in the Creator Dashboard and send the IDs.
5. Pick licensed music and SFX in Toolbox → Creator Store and send the asset IDs. Original Undertale music is not allowed.
6. Optional big quality boost: upload real meshes, textures and animations. Uploaded animations are the only way to use Animator tracks or KeyframeSequences in live games.
7. Enable `Workspace.AuthorityMode = Server` later if anti-cheat matters, and any needed Studio Beta features (File → Beta Features).

## 12. Open items to re-check once the docs hosts are allowed

- Network ownership API details.
- `Massless` semantics in assemblies.
- Missing `Enum.Font` numbers.
- Full UIGradient, UIFlexItem and UIListLayout property lists.
- `TweenService:SmoothDamp` / `GetValue`.
- BadgeService signatures and limits.
- `GetRequestBudgetForRequestType`.
- Whether `RbxCharacterSounds` paths still exist.
- `FallenPartsDestroyHeight` default.
- Whether Avatar Joint Upgrade applies to rigs assigned via `player.Character =`.
- Client availability of `@native`.
- Require-by-string alias support.
- Exact current DataStore write formula.
- Whether baked DataModelContent replicates.
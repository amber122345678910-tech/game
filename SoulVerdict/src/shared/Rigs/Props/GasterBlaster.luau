--!strict
-- GasterBlaster prop: the dragon-like blaster skull in three styles (part-built). [Lune-safe]
-- This is the FALLBACK for the HD meshes BlasterSkull<Style> / BlasterJaw<Style> (SPEC section 18):
-- it is authored in the same design space as tools/meshgen/models/blaster.py, so bounding boxes,
-- jaw hinge, muzzle and eye anchors match the HD meshes and code can swap either in.
--   Classic : white skull, long snout, big sockets with white diamond pupils, back-swept horns.
--   Fell    : warm bone stained red at the tips, jagged teeth, brow spikes, horn prongs, cracks, red eyes.
--   Eclipse : lupine void-wolf skull (long sloped muzzle, ear blades, long fangs) with glowing
--             violet/cyan cracks and violet eyes.
--
-- API
--   GasterBlaster.Build(style: "Classic"|"Fell"|"Eclipse"?, scale: number?) -> Model   (<= 90 parts)
--        PrimaryPart "Core" (Anchored, at the skull's bounding-box centre = HD skull origin), faces -Z.
--        Core attachments: "JawHinge" (jaw pivot, rotate about its X axis), "Muzzle" (mouth front,
--        LookVector = beam direction), "LeftEye"/"RightEye" (socket floor), "HornTipLeft/Right",
--        "HD_BlasterSkull" (HDMesh = "BlasterSkull<Style>", HDSize). Child Model "Jaw": PrimaryPart
--        "Mandible" with attachments "JawHinge" and "HD_BlasterJaw" (HDMesh "BlasterJaw<Style>").
--        Skull parts carry HDGroup "BlasterSkull", jaw parts "BlasterJaw"; the glowing pupils
--        (Role "Eye"), eye halos and "MouthGlow" (Role "Glow") have no HDGroup so they stay visible
--        on top of HD meshes. PointLight "Glow" lives in MouthGlow (disabled until SetGlow).
--        Model attributes: PropId, Style, Scale, RigScale (= scale, read by HDMesh.ApplyToModel),
--        JawMaxOpen (radians), JawOpen (0..1), GlowIntensity, GlowColor, PartCount.
--   GasterBlaster.SetJaw(model, alpha: number)
--        opens the jaw: angle = alpha * JawMaxOpen about the hinge (alpha 0 = closed, 1 = wide open;
--        -0.1..1.25 allowed for anticipation/overshoot). Works wherever the model was moved
--        (reads Core.CFrame); welded HD jaw meshes follow the Mandible.
--   GasterBlaster.SetGlow(model, color: Color3, intensity: number)
--        0 = idle (white pupils, no halo, mouth dark, light off) .. 1 = charged (tinted pupils, eye
--        halos + mouth glow visible, light on). Pure instance edits; call per frame while charging.
--   GasterBlaster.Preview(style?, scale?, jawAlpha?, glow?) -> Model   Build + SetJaw + SetGlow
--   GasterBlaster.Styles() -> {string}
--   GasterBlaster.DefaultGlow(style) -> Color3
--   GasterBlaster.MeshInfo(style) -> table   the HD mesh numbers this fallback is matched to

local Props = require(script.Parent)
local PartKit = require(script.Parent.Parent.PartKit)
local Rng = require(script.Parent.Parent.Parent.Util.Rng)

local GasterBlaster = {}

local V = Vector3.new
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local HINGE = V(0, -0.36, 0.4) -- design-space jaw hinge (tools/meshgen/models/blaster.py HINGE)
local MAX_PARTS = 90
-- "off" glow parts stay a hair below fully transparent so pooled-blaster code that skips
-- Transparency >= 0.999 parts still moves them with the skull
local HIDDEN = 0.995

type Spike = { a: Vector3, b: Vector3, r: number }
type Horn = {
	Root: Vector3,
	C1: Vector3,
	C2: Vector3,
	Tip: Vector3,
	R0: number,
	R1: number,
	Prong: boolean?,
	Blade: boolean?,
}
type MeshInfo = {
	SkullSize: Vector3,
	SkullHinge: Vector3,
	Muzzle: Vector3,
	Eye: Vector3,
	HornTip: Vector3,
	JawSize: Vector3,
	JawHinge: Vector3,
}
type Style = {
	Bone: Color3,
	Socket: Color3,
	Inner: Color3,
	Seam: Color3,
	TipTint: Color3?,
	TipAmount: number,
	Pupil: Color3,
	Glow: Color3,
	Crack: Color3?,
	CrackHot: Color3?,
	CrackNeon: boolean,
	L: number,
	SnoutW: { number },
	SnoutH: { number },
	TopDrop: number,
	Stop: number,
	EyeC: Vector3,
	EyeR: { number },
	EyeYaw: number,
	EyeSlant: number,
	Horn: Horn,
	CheekSpikes: { Spike },
	BrowSpikes: { Spike },
	UpperTeeth: number,
	LowerTeeth: number,
	ToothLen: number,
	Canine: number,
	CanineLen: number,
	Jag: number,
	MaxOpen: number,
	Seed: number,
	Mesh: MeshInfo,
	Cracks: { { { number } } }, -- polylines of {yawDeg, pitchDeg} on the cranium
}

local function spike(a: Vector3, b: Vector3, r: number): Spike
	return { a = a, b = b, r = r }
end

-- Shape numbers mirror tools/meshgen/models/blaster.py STYLES; Mesh = generated HD mesh data
-- (src/shared/Meshes/Blaster*<Style>.luau; tests check they stay in sync).
local STYLES: { [string]: Style } = {
	Classic = {
		Bone = rgb(238, 241, 245),
		Socket = rgb(7, 8, 13),
		Inner = rgb(20, 18, 26),
		Seam = rgb(40, 40, 50),
		TipTint = nil,
		TipAmount = 0,
		Pupil = rgb(255, 255, 255),
		Glow = rgb(110, 215, 255),
		Crack = nil,
		CrackHot = nil,
		CrackNeon = false,
		L = 1.62,
		SnoutW = { 0.84, 0.42 },
		SnoutH = { 0.56, 0.33 },
		TopDrop = 0.28,
		Stop = 0,
		EyeC = V(0.52, 0.3, -0.32),
		EyeR = { 0.335, 0.275 },
		EyeYaw = 0.34,
		EyeSlant = 0,
		Horn = { Root = V(0.42, 0.6, 0.18), C1 = V(0.62, 1.1, 0.55), C2 = V(0.86, 1.1, 1.15), Tip = V(0.98, 0.78, 1.72), R0 = 0.22, R1 = 0.03 },
		CheekSpikes = {
			spike(V(0.9, -0.04, 0.32), V(1.36, -0.2, 1.1), 0.13),
			spike(V(0.8, -0.26, 0.24), V(1.16, -0.56, 0.92), 0.1),
		},
		BrowSpikes = {},
		UpperTeeth = 5,
		LowerTeeth = 4,
		ToothLen = 0.22,
		Canine = 2,
		CanineLen = 0.32,
		Jag = 0,
		MaxOpen = math.rad(52),
		Seed = 1,
		Mesh = {
			SkullSize = V(2.7324, 1.7657, 3.3632),
			SkullHinge = V(0, -0.6032, 0.3333),
			Muzzle = V(0, -0.7432, -1.7367),
			Eye = V(0.4696, 0.0568, -0.2453),
			HornTip = V(0.9796, 0.5368, 1.6533),
			JawSize = V(1.7448, 0.9048, 2.1479),
			JawHinge = V(0, 0.1949, 0.9493),
		},
		Cracks = {},
	},
	Fell = {
		Bone = rgb(233, 226, 214),
		Socket = rgb(22, 3, 10),
		Inner = rgb(30, 6, 8),
		Seam = rgb(70, 18, 22),
		TipTint = rgb(120, 10, 20),
		TipAmount = 0.85,
		Pupil = rgb(255, 60, 60),
		Glow = rgb(255, 40, 48),
		Crack = rgb(60, 8, 12),
		CrackHot = rgb(170, 24, 34),
		CrackNeon = false,
		L = 1.66,
		SnoutW = { 0.86, 0.4 },
		SnoutH = { 0.56, 0.32 },
		TopDrop = 0.3,
		Stop = 0,
		EyeC = V(0.52, 0.29, -0.32),
		EyeR = { 0.34, 0.27 },
		EyeYaw = 0.34,
		EyeSlant = 0.4,
		Horn = {
			Root = V(0.42, 0.6, 0.18),
			C1 = V(0.66, 1.18, 0.5),
			C2 = V(0.95, 1.22, 1.1),
			Tip = V(1.12, 0.92, 1.78),
			R0 = 0.23,
			R1 = 0.025,
			Prong = true,
		},
		CheekSpikes = {
			spike(V(0.9, -0.04, 0.32), V(1.42, -0.18, 1.12), 0.13),
			spike(V(0.8, -0.26, 0.24), V(1.22, -0.62, 0.92), 0.1),
			spike(V(0.86, 0.12, 0.18), V(1.3, 0.3, 0.78), 0.085),
		},
		BrowSpikes = {
			spike(V(0.62, 0.62, -0.18), V(0.82, 0.98, 0.1), 0.075),
			spike(V(0.4, 0.66, -0.02), V(0.52, 1.0, 0.3), 0.06),
		},
		UpperTeeth = 5,
		LowerTeeth = 4,
		ToothLen = 0.24,
		Canine = 2,
		CanineLen = 0.36,
		Jag = 0.35,
		MaxOpen = math.rad(56),
		Seed = 7,
		Mesh = {
			SkullSize = V(2.8473, 2.0313, 3.4553),
			SkullHinge = V(0, -0.7401, 0.3269),
			Muzzle = V(0, -0.8801, -1.7831),
			Eye = V(0.4683, -0.0901, -0.2517),
			HornTip = V(1.1183, 0.5399, 1.7069),
			JawSize = V(1.7444, 0.939, 2.1883),
			JawHinge = V(0, 0.1844, 0.969),
		},
		Cracks = {
			{ { -28, 72 }, { -38, 58 }, { -32, 46 }, { -48, 34 }, { -44, 22 } },
			{ { -38, 58 }, { -58, 62 }, { -70, 54 } },
			{ { 30, 40 }, { 24, 28 }, { 33, 16 } },
		},
	},
	Eclipse = {
		Bone = rgb(236, 235, 244),
		Socket = rgb(12, 6, 24),
		Inner = rgb(18, 10, 34),
		Seam = rgb(43, 12, 99),
		TipTint = rgb(70, 30, 140),
		TipAmount = 0.7,
		Pupil = rgb(125, 249, 255),
		Glow = rgb(139, 61, 255),
		Crack = rgb(139, 61, 255),
		CrackHot = rgb(125, 249, 255),
		CrackNeon = true,
		L = 2.05,
		SnoutW = { 0.74, 0.27 },
		SnoutH = { 0.52, 0.24 },
		TopDrop = 0.46,
		Stop = 0.12,
		EyeC = V(0.5, 0.33, -0.3),
		EyeR = { 0.31, 0.235 },
		EyeYaw = 0.3,
		EyeSlant = 0.24,
		Horn = {
			Root = V(0.44, 0.58, 0.26),
			C1 = V(0.56, 1.02, 0.42),
			C2 = V(0.7, 1.22, 0.78),
			Tip = V(0.78, 1.2, 1.22),
			R0 = 0.24,
			R1 = 0.02,
			Blade = true,
		},
		CheekSpikes = {
			spike(V(0.86, -0.04, 0.3), V(1.3, -0.26, 1.02), 0.12),
			spike(V(0.62, 0.7, 0.4), V(0.86, 0.96, 1.14), 0.09),
		},
		BrowSpikes = {},
		UpperTeeth = 5,
		LowerTeeth = 4,
		ToothLen = 0.19,
		Canine = 1,
		CanineLen = 0.46,
		Jag = 0.1,
		MaxOpen = math.rad(54),
		Seed = 3,
		Mesh = {
			SkullSize = V(2.5566, 2.0698, 3.2978),
			SkullHinge = V(0, -0.5662, 0.7941),
			Muzzle = V(0, -0.7062, -1.7059),
			Eye = V(0.4585, 0.1238, 0.2374),
			HornTip = V(0.7828, 0.9938, 1.6141),
			JawSize = V(1.7446, 0.9065, 2.5736),
			JawHinge = V(0, 0.1991, 1.1637),
		},
		Cracks = {
			{ { 4, 84 }, { 12, 72 }, { 8, 62 }, { 22, 52 }, { 18, 40 }, { 32, 30 } },
			{ { 12, 72 }, { -10, 66 }, { -24, 58 }, { -42, 54 } },
		},
	},
}

local ORDER = { "Classic", "Fell", "Eclipse" }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- SDF snout loft (blaster.py snout_profile): half width, half height and centre height at depth z.
local function profile(st: Style, z: number): (number, number, number)
	local t = math.clamp((0.15 - z) / (st.L + 0.15), 0, 1)
	local rx = lerp(st.SnoutW[1], st.SnoutW[2], t ^ 0.85)
	local ry = lerp(st.SnoutH[1], st.SnoutH[2], t)
	local cy = lerp(0.06, 0.06 - st.TopDrop * 0.55, t)
	return rx, ry, cy
end

local function bezier(h: Horn, t: number): Vector3
	local u = 1 - t
	return h.Root * (u * u * u) + h.C1 * (3 * u * u * t) + h.C2 * (3 * u * t * t) + h.Tip * (t * t * t)
end

local function mirror(v: Vector3, side: number): Vector3
	return V(v.X * side, v.Y, v.Z)
end

-- An oriented ellipsoid in design space (frame = centre + axes, half = half extents).
type Solid = { frame: CFrame, half: Vector3 }

local function inside(sol: Solid, p: Vector3): number
	local q = sol.frame:PointToObjectSpace(p)
	return (q.X / sol.half.X) ^ 2 + (q.Y / sol.half.Y) ^ 2 + (q.Z / sol.half.Z) ^ 2
end

-- Surface height of the union of `list` at (x, z), searching from the solids' centres downwards
-- (dir = -1: lowest bottom) or upwards (dir = 1: highest top). nil when no solid covers (x, z).
local function surfaceAt(list: { Solid }, x: number, z: number, dir: number): number?
	local best: number? = nil
	for _, sol in list do
		local cy = sol.frame.Position.Y
		local reach = math.max(sol.half.X, sol.half.Y, sol.half.Z)
		local yIn = cy
		if inside(sol, V(x, yIn, z)) <= 1 then
			local yOut = cy + dir * reach * 2
			for _ = 1, 22 do
				local mid = (yIn + yOut) / 2
				if inside(sol, V(x, mid, z)) <= 1 then
					yIn = mid
				else
					yOut = mid
				end
			end
			if best == nil or (dir < 0 and yIn < best) or (dir > 0 and yIn > best) then
				best = yIn
			end
		end
	end
	return best
end

function GasterBlaster.Styles(): { string }
	return table.clone(ORDER)
end

function GasterBlaster.DefaultGlow(style: string?): Color3
	local st = STYLES[style or "Classic"] or STYLES.Classic
	return st.Glow
end

function GasterBlaster.MeshInfo(style: string?): MeshInfo
	local st = STYLES[style or "Classic"] or STYLES.Classic
	return table.clone(st.Mesh)
end

function GasterBlaster.Build(style: string?, scale: number?): Model
	local styleId = if style and STYLES[style] then style else "Classic"
	local st = STYLES[styleId]
	local s = if scale and scale > 0 then scale else 1
	local kit = Props.Kit(s)
	local mesh = st.Mesh
	local L = st.L
	-- Core = HD skull bounding-box centre (design space); everything below is authored in design
	-- space and shifted by -C (Core space = model space at build time).
	local C = HINGE - mesh.SkullHinge
	local function P(v: Vector3): Vector3
		return v - C
	end
	local function at(v: Vector3): CFrame
		return CFrame.new(v - C)
	end

	local model = Props.NewModel("GasterBlaster", "GasterBlaster")
	local jaw = Instance.new("Model")
	jaw.Name = "Jaw"

	local function skullProps(role: string?, extra: { [string]: any }?): any
		local pr: { [string]: any } = { Role = role or "Bone", Attributes = { HDGroup = "BlasterSkull" } }
		if extra then
			for k, v in extra do
				pr[k] = v
			end
		end
		return pr
	end
	-- holes (sockets, nostrils, mouth): unlit near-black so they read as voids, not grey balls
	local function voidProps(group: string): any
		return { Role = "Dark", Material = NEON, CastShadow = false, Attributes = { HDGroup = group } }
	end
	local function jawProps(role: string?, extra: { [string]: any }?): any
		local pr: { [string]: any } = { Role = role or "Bone", Attributes = { HDGroup = "BlasterJaw" } }
		if extra then
			for k, v in extra do
				pr[k] = v
			end
		end
		return pr
	end

	local bone = st.Bone
	local function tint(t: number): Color3
		if st.TipTint == nil then
			return bone
		end
		return bone:Lerp(st.TipTint :: Color3, math.clamp(t, 0, 1) * st.TipAmount)
	end

	-- Ellipsoid stretched between two design points (axis = a->b), `k` = length factor (overlap).
	local function seg(
		parent: Instance,
		name: string,
		a: Vector3,
		b: Vector3,
		w: number,
		h: number,
		k: number,
		color: Color3,
		props: any,
		roll: number?
	): BasePart
		local dir = b - a
		local cf = PartKit.LookFrame(P((a + b) / 2), dir.Unit, V(0, 1, 0))
		if roll then
			cf = cf * CFrame.Angles(0, 0, roll)
		end
		return kit.Ellipsoid(parent, name, V(w, h, dir.Magnitude * k), cf, color, props)
	end
	local function solidOf(a: Vector3, b: Vector3, w: number, h: number, k: number): Solid
		local dir = b - a
		return { frame = PartKit.LookFrame((a + b) / 2, dir.Unit, V(0, 1, 0)), half = V(w, h, dir.Magnitude * k) / 2 }
	end

	------------------------------------------------------------------------------------------
	-- Skull
	------------------------------------------------------------------------------------------
	local core = kit.Ellipsoid(model, "Core", V(0.9, 0.8, 1.0), CFrame.new(), bone, skullProps())
	local craniumC = V(0, 0.17, 0.46)
	local craniumR = V(0.9, 0.69, 0.8)
	kit.Ellipsoid(model, "Cranium", craniumR * 2, at(craniumC), bone, skullProps())
	if st.Stop > 0 then
		kit.Ellipsoid(model, "Forehead", V(1.2, 0.58 + st.Stop, 1.1), at(V(0, 0.48, -0.1)), bone, skullProps())
	end
	-- occipital crest along the top of the cranium
	seg(model, "Crest", V(0, 0.76, 0.14), V(0, 0.55, 1.12), 0.16, 0.16, 1.02, bone, skullProps())

	-- snout: a central nasal ridge + two maxilla bars converging to the tip (bony, dragon-like),
	-- a recessed filler between them and a low, flat nose tip with slit nostrils
	local snout: { Solid } = {}
	local zb, zf = -0.05, -L + 0.14
	local _, ryb, cyb = profile(st, zb)
	local _, ryf, cyf = profile(st, zf)
	local bridgeA = V(0, cyb + ryb * 0.82 - 0.15, zb)
	local bridgeB = V(0, cyf + ryf * 0.78 - 0.13, zf)
	local bridgeW = math.max(st.SnoutW[2] * 1.0, 0.36)
	local bridge = seg(model, "Bridge", bridgeA, bridgeB, bridgeW, 0.26, 1.15, bone, skullProps())
	table.insert(snout, solidOf(bridgeA, bridgeB, bridgeW, 0.26, 1.15))
	local z0, z1 = -0.28, -L + 0.2
	local rx0, ry0, cy0 = profile(st, z0)
	local rx1, ry1, cy1 = profile(st, z1)
	local barH = (ry0 + ry1) * 0.42
	local bars: { Solid } = {}
	for _, side in { -1, 1 } do
		local a = V(rx0 * 0.78 * side, cy0 - ry0 * 0.32, z0)
		local b = V(rx1 * 0.62 * side, cy1 - ry1 * 0.25, z1)
		seg(model, if side < 0 then "MaxillaL" else "MaxillaR", a, b, 0.3, barH, 1.16, bone, skullProps())
		local sol = solidOf(a, b, 0.3, barH, 1.16)
		table.insert(snout, sol)
		table.insert(bars, sol)
	end
	local zm = -L * 0.5
	local rxm, rym, cym = profile(st, zm)
	local fillC = V(0, cym - 0.07, zm)
	local fillS = V(rxm * 1.64, rym * 1.0, L * 1.0)
	kit.Ellipsoid(model, "Snout", fillS, at(fillC), bone, skullProps())
	table.insert(snout, { frame = CFrame.new(fillC), half = fillS / 2 })
	local rxn, ryn, cyn = profile(st, -L)
	local noseC = V(0, cyn - 0.09, -L + 0.18)
	local noseS = V(rxn * 1.2, ryn * 0.9, 0.36)
	kit.Ellipsoid(model, "Nose", noseS, at(noseC), bone, skullProps())
	table.insert(snout, { frame = CFrame.new(noseC), half = noseS / 2 })

	-- centre seam along the top of the bridge (the blaster's iconic split line)
	do
		local bcf = bridge.CFrame -- already scaled; convert back to design space for authoring
		local half = (bridgeB - bridgeA).Magnitude * 1.15 / 2
		local pts: { Vector3 } = {}
		for _, u in { -0.78, -0.2, 0.4, 0.8 } do
			local yTop = 0.13 * math.sqrt(1 - u * u) + 0.01
			local wp = (bcf * CFrame.new(0, yTop * s, u * half * s)).Position / s + C
			table.insert(pts, wp)
		end
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local cf = PartKit.LookFrame(P((a + b) / 2), (b - a).Unit, V(0, 1, 0))
			kit.Box(model, "Seam" .. i, V(0.04, 0.03, (b - a).Magnitude + 0.03), cf, st.Seam, skullProps("Dark", { CastShadow = false }))
		end
	end

	-- dark mouth roof (seen when the jaw opens)
	do
		local rx, _, cy = profile(st, -L * 0.45)
		local bottom = surfaceAt(snout, 0, -L * 0.45, -1) or (cy - 0.4)
		kit.Ellipsoid(
			model,
			"MouthRoof",
			V(rx * 1.35, 0.1, L * 0.85),
			at(V(0, bottom + 0.035, -L * 0.48)),
			st.Inner,
			voidProps("BlasterSkull")
		)
	end

	-- eyes: brow ridge, dark socket, glowing pupil + halo (pupil/halo outside the HD groups)
	local meshEye = mesh.Eye + C -- design-space socket floor (right eye)
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		local look = V(math.sin(st.EyeYaw) * side, 0, -math.cos(st.EyeYaw))
		local anchor = mirror(meshEye, side)
		local frame = PartKit.LookFrame(anchor, look, V(0, 1, 0))
		local slant = st.EyeSlant * side
		-- brow ridge arching over the socket (angrier for slanted styles)
		local ec = mirror(st.EyeC, side)
		local browC = ec + V(0.0, 0.25, 0.15)
		local browCF = at(browC)
			* CFrame.Angles(0, -st.EyeYaw * side, 0)
			* CFrame.Angles(0, 0, (0.16 + st.EyeSlant * 0.8) * side)
		kit.Ellipsoid(model, "Brow" .. suffix, V(0.6, 0.2, 0.3), browCF, bone, skullProps())
		-- socket: dark lens recessed at the HD socket floor
		local sockCF = CFrame.new(P((frame * CFrame.new(0, 0, 0.02)).Position)) * frame.Rotation
			* CFrame.Angles(0, 0, slant * 0.35)
		kit.Ellipsoid(
			model,
			"Socket" .. suffix,
			V(st.EyeR[1] * 2.05, st.EyeR[2] * 2.05, 0.3),
			sockCF,
			st.Socket,
			voidProps("BlasterSkull")
		)
		-- cheekbone (zygomatic arch) under the socket, running back to the hinge
		seg(
			model,
			"Cheek" .. suffix,
			mirror(V(0.66, -0.08, -0.42), side),
			mirror(V(0.84, -0.18, 0.4), side),
			0.27,
			0.25,
			1.18,
			bone,
			skullProps()
		)
		-- pupil: small white diamond (Undertale), Role "Eye"
		local pupilCF = CFrame.new(P((frame * CFrame.new(0, 0, -0.14)).Position))
			* frame.Rotation
			* CFrame.Angles(0, 0, math.pi / 4)
		kit.Box(
			model,
			"Pupil" .. suffix,
			V(0.085, 0.085, 0.04),
			pupilCF,
			st.Pupil,
			{ Role = "Eye", Material = Enum.Material.SmoothPlastic, CastShadow = false, Attributes = { IdleColor = st.Pupil } }
		)
		local haloCF = CFrame.new(P((frame * CFrame.new(0, 0, -0.13)).Position)) * frame.Rotation
		kit.Ellipsoid(
			model,
			"EyeHalo" .. suffix,
			V(st.EyeR[1] * 1.45, st.EyeR[2] * 1.45, 0.04),
			haloCF,
			st.Glow,
			{ Role = "Glow", Material = NEON, Transparency = HIDDEN, CastShadow = false, Attributes = { GlowKind = "EyeHalo" } }
		)
		-- hinge boss
		kit.Ellipsoid(
			model,
			"HingeBoss" .. suffix,
			V(0.34, 0.4, 0.42),
			at(V(0.78 * side, HINGE.Y + 0.06, HINGE.Z)),
			bone,
			skullProps()
		)
		-- temporal fossa behind the eye (dragon-skull opening)
		local fossaCF = PartKit.OnEllipsoid(at(craniumC), craniumR, 72 * side, 14, 0.035)
		kit.Ellipsoid(model, "Temporal" .. suffix, V(0.34, 0.22, 0.08), fossaCF, st.Socket, skullProps("Dark"))
	end

	-- horns: tapered bezier sweep (4 overlapping ellipsoids, tips stained for Fell/Eclipse)
	local horn = st.Horn
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		local ts = { 0, 0.2, 0.4, 0.6, 0.8, 1.0 }
		for i = 1, #ts - 1 do
			local a = mirror(bezier(horn, ts[i]), side)
			local b = mirror(bezier(horn, ts[i + 1]), side)
			local tm = (ts[i] + ts[i + 1]) / 2
			local r = horn.R0 * (1 - tm) ^ 1.15 + horn.R1
			local k = if i == #ts - 1 then 1.35 else 1.9
			local w = r * 2.05
			local h = if horn.Blade then r * 2.3 else r * 2.05
			seg(model, "Horn" .. suffix .. i, a, b, w, h, k, tint(tm * 1.4 - 0.2), skullProps())
		end
		if horn.Prong then
			local mid = mirror(bezier(horn, 0.36), side)
			local tip = mid + mirror(V(0.18, 0.36, -0.05), side)
			seg(model, "Prong" .. suffix, mid, tip, 0.15, 0.15, 1.45, tint(0.9), skullProps())
		end
		if horn.Blade then
			-- wolf-ear fin under the horn sweep
			local a = mirror(bezier(horn, 0.12) + V(0.03, -0.12, 0.08), side)
			local b = mirror(bezier(horn, 0.72) + V(0.04, -0.2, 0.1), side)
			seg(model, "Ear" .. suffix, a, b, 0.14, 0.42, 1.25, tint(0.6), skullProps(), 0.25 * side)
		end
		-- cheek / brow spikes: an ellipsoid whose widest point sits near the root
		for i, sp in st.CheekSpikes do
			local a, b = mirror(sp.a, side), mirror(sp.b, side)
			local dir = b - a
			local len = dir.Magnitude
			local cf = PartKit.LookFrame(P(a + dir * 0.38), dir.Unit, V(0, 1, 0))
			kit.Ellipsoid(model, "Spike" .. suffix .. i, V(sp.r * 1.7, sp.r * 1.9, len * 1.24), cf, tint(0.85), skullProps())
		end
		for i, sp in st.BrowSpikes do
			local a, b = mirror(sp.a, side), mirror(sp.b, side)
			local dir = b - a
			local cf = PartKit.LookFrame(P(a + dir * 0.3), dir.Unit, V(0, 1, 0))
			kit.Ellipsoid(model, "BrowSpike" .. suffix .. i, V(sp.r * 2.2, sp.r * 2.2, dir.Magnitude * 1.4), cf, tint(0.95), skullProps())
		end
	end

	-- upper teeth along the palate edge (fangs = Canine); hang below the maxilla bodies
	local rng = Rng.new(st.Seed)
	local function toothLen(i: number, n: number, canineIdx: number, len: number, canineLen: number): number
		local l = len * (0.78 + 0.22 * (1 - (i - 1) / math.max(n - 1, 1)))
		if i == canineIdx then
			l = canineLen
		end
		if st.Jag > 0 then
			l *= 1 + st.Jag * rng:Number(-0.5, 0.45)
		end
		return l
	end
	local upperZ: { number } = {}
	for i = 1, st.UpperTeeth do
		upperZ[i] = lerp(-L + 0.16, -0.12, (i - 1) / math.max(st.UpperTeeth - 1, 1))
	end
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		for i = 1, st.UpperTeeth do
			local z = upperZ[i]
			local rx = profile(st, z)
			local x = math.max(rx - 0.15, 0.06)
			if i == 1 then
				x = math.max(0.07, x * 0.4)
			end
			local yb = surfaceAt(snout, x, z, -1) or -0.3
			local len = toothLen(i, st.UpperTeeth, st.Canine + 1, st.ToothLen, st.CanineLen)
			local w = if i == st.Canine + 1 then 0.15 else 0.115
			kit.Ellipsoid(
				model,
				"Tooth" .. suffix .. i,
				V(w, len * 2 + 0.1, w * 0.9),
				at(V(x * side, yb + 0.05, z)) * CFrame.Angles(0.06, 0, 0),
				bone:Lerp(rgb(255, 248, 234), 0.5),
				skullProps("Bone", { CastShadow = false })
			)
		end
	end

	-- cracks on the cranium (Fell: dark red; Eclipse: glowing violet/cyan)
	if st.Crack then
		local craniumCF = at(craniumC)
		for ci, path in st.Cracks do
			local pts: { CFrame } = {}
			for _, yp in path do
				table.insert(pts, PartKit.OnEllipsoid(craniumCF, craniumR, yp[1], yp[2], -0.012))
			end
			for i = 1, #pts - 1 do
				local a, b = pts[i].Position, pts[i + 1].Position
				local normal = (pts[i].LookVector + pts[i + 1].LookVector).Unit
				local dir = b - a
				local x = dir.Unit
				local z = (normal - x * x:Dot(normal)).Unit
				local y = z:Cross(x)
				local hot = st.CrackNeon and i % 2 == 0
				local color = if hot then (st.CrackHot or st.Crack) :: Color3 else st.Crack :: Color3
				local width = if ci == 1 then 0.06 else 0.045
				local props = if st.CrackNeon
					then { Role = "Glow", Material = NEON, CastShadow = false }
					else skullProps("Dark", { CastShadow = false })
				kit.Box(
					model,
					"Crack" .. ci .. "_" .. i,
					V(dir.Magnitude + width * 0.6, width, 0.04),
					CFrame.fromMatrix((a + b) / 2, x, y, z),
					color,
					props
				)
			end
		end
	end

	-- mouth glow (charge light), hidden until SetGlow
	local mouthGlow = kit.Ellipsoid(
		model,
		"MouthGlow",
		V(0.62, 0.2, L * 0.7),
		at(V(0, -0.47, -L * 0.52)),
		st.Glow,
		{ Role = "Glow", Material = NEON, Transparency = HIDDEN, CastShadow = false, Attributes = { GlowKind = "Mouth" } }
	)
	local light = kit.Light(mouthGlow, "Point", { Name = "Glow", Color = st.Glow, Brightness = 0, Range = 12 })
	light.Enabled = false

	------------------------------------------------------------------------------------------
	-- Jaw (child Model, hinged at Core.JawHinge)
	------------------------------------------------------------------------------------------
	local function jawProfile(z: number): (number, number, number)
		local t = math.clamp((0.4 - z) / (L + 0.4 - 0.12), 0, 1)
		local rx = lerp(st.SnoutW[1] * 0.98, st.SnoutW[2] * 0.95, t ^ 0.9)
		local top = lerp(-0.4, -0.4 - st.TopDrop * 0.1, t)
		local bot = lerp(-0.9, -0.7, t)
		return rx, top, bot
	end
	local jzBack, jzFront = 0.28, -(L - 0.08)
	local midRx = jawProfile((jzBack + jzFront) / 2)
	local mandibleC = V(0, -0.7, (jzBack + jzFront) / 2 + 0.06)
	local mandible = kit.Ellipsoid(
		jaw,
		"Mandible",
		V(midRx * 1.5, 0.28, (jzBack - jzFront) * 0.96),
		at(mandibleC),
		bone,
		jawProps()
	)
	local jawSolids: { Solid } = {}
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		local rxB, topB, botB = jawProfile(0.2)
		local rxF, topF, botF = jawProfile(jzFront + 0.26)
		local a = V((rxB - 0.1) * side, (topB + botB) / 2 + 0.05, 0.2)
		local b = V((rxF - 0.13) * side, (topF + botF) / 2 + 0.03, jzFront + 0.26)
		seg(jaw, "JawSide" .. suffix, a, b, 0.26, 0.4, 1.12, bone, jawProps())
		table.insert(jawSolids, solidOf(a, b, 0.26, 0.4, 1.12))
		seg(
			jaw,
			"Ramus" .. suffix,
			V(0.72 * side, -0.62, 0.14),
			V(0.76 * side, HINGE.Y, HINGE.Z),
			0.24,
			0.26,
			1.45,
			bone,
			jawProps()
		)
		if styleId == "Fell" then
			local cf = PartKit.LookFrame(P(V(0.62 * side, -0.8, -0.22)), V(0.18 * side, -0.3, 0.36).Unit, V(0, 1, 0))
			kit.Ellipsoid(jaw, "JawSpike" .. suffix, V(0.12, 0.12, 0.6), cf, tint(0.9), jawProps())
		end
	end
	local chinC = V(0, -0.66, -L + 0.26)
	kit.Ellipsoid(jaw, "Chin", V(0.4, 0.24, 0.36), at(chinC), bone, jawProps())
	if styleId == "Fell" then
		local cf = PartKit.LookFrame(P(chinC + V(0, -0.1, 0)), V(0, -0.9, -0.45).Unit, V(0, 0, -1))
		kit.Ellipsoid(jaw, "ChinSpike", V(0.13, 0.13, 0.48), cf, tint(0.9), jawProps())
	end
	kit.Ellipsoid(
		jaw,
		"MouthFloor",
		V(midRx * 1.3, 0.06, (jzBack - jzFront) * 0.8),
		at(V(0, -0.53, mandibleC.Z - 0.04)),
		st.Inner,
		voidProps("BlasterJaw")
	)
	-- lower teeth between the upper ones, standing on the jaw bars
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		for i = 1, st.LowerTeeth do
			local z = (upperZ[i] + upperZ[i + 1]) / 2
			local rx = jawProfile(z)
			local x = math.max(rx - 0.22, 0.08)
			local top = surfaceAt(jawSolids, x * side, z, 1) or -0.42
			local len = toothLen(i, st.LowerTeeth, st.Canine, st.ToothLen * 0.85, st.CanineLen * 0.7)
			local w = 0.11
			kit.Ellipsoid(
				jaw,
				"LowTooth" .. suffix .. i,
				V(w, len * 2 + 0.08, w * 0.9),
				at(V(x * side, top - 0.04, z)),
				bone:Lerp(rgb(255, 248, 234), 0.5),
				jawProps("Bone", { CastShadow = false })
			)
		end
	end

	------------------------------------------------------------------------------------------
	-- Attachments (HD contract) + rest pose bookkeeping
	------------------------------------------------------------------------------------------
	local hingeLocal = mesh.SkullHinge -- = HINGE - C
	kit.Attach(core, "JawHinge", CFrame.new(hingeLocal))
	kit.Attach(core, "Muzzle", CFrame.new(mesh.Muzzle))
	kit.Attach(core, "RightEye", CFrame.new(mesh.Eye))
	kit.Attach(core, "LeftEye", CFrame.new(mirror(mesh.Eye, -1)))
	kit.Attach(core, "HornTipRight", CFrame.new(mesh.HornTip))
	kit.Attach(core, "HornTipLeft", CFrame.new(mirror(mesh.HornTip, -1)))
	local hdSkull = kit.Attach(core, "HD_BlasterSkull", CFrame.new())
	hdSkull:SetAttribute("HDMesh", "BlasterSkull" .. styleId)
	hdSkull:SetAttribute("HDSize", mesh.SkullSize)

	local jawCentre = HINGE - mesh.JawHinge -- HD jaw bounding-box centre (design space)
	kit.Attach(mandible, "JawHinge", CFrame.new(HINGE - mandibleC))
	local hdJaw = kit.Attach(mandible, "HD_BlasterJaw", CFrame.new(jawCentre - mandibleC))
	hdJaw:SetAttribute("HDMesh", "BlasterJaw" .. styleId)
	hdJaw:SetAttribute("HDSize", mesh.JawSize)

	jaw.PrimaryPart = mandible
	jaw.Parent = model
	local mandibleInv = mandible.CFrame:Inverse()
	for _, d in jaw:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("JawRest", mandibleInv * d.CFrame)
		end
	end

	model:SetAttribute("Style", styleId)
	model:SetAttribute("Scale", s)
	model:SetAttribute("RigScale", s)
	model:SetAttribute("JawMaxOpen", st.MaxOpen)
	model:SetAttribute("JawOpen", 0)
	model:SetAttribute("GlowIntensity", 0)
	model:SetAttribute("GlowColor", st.Glow)
	Props.Finish(model, core)
	local count = model:GetAttribute("PartCount") :: number
	assert(count <= MAX_PARTS, ("GasterBlaster %s has %d parts (max %d)"):format(styleId, count, MAX_PARTS))
	return model
end

local function findPart(parent: Instance?, name: string): BasePart?
	if parent == nil then
		return nil
	end
	local p = parent:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

function GasterBlaster.SetJaw(model: Model, alpha: number)
	local core = model.PrimaryPart or findPart(model, "Core")
	local jaw = model:FindFirstChild("Jaw")
	if core == nil or jaw == nil or not jaw:IsA("Model") then
		return
	end
	local mandible = jaw.PrimaryPart or findPart(jaw, "Mandible")
	if mandible == nil then
		return
	end
	local hingeA = core:FindFirstChild("JawHinge")
	local hingeB = mandible:FindFirstChild("JawHinge")
	if hingeA == nil or hingeB == nil or not hingeA:IsA("Attachment") or not hingeB:IsA("Attachment") then
		return
	end
	local maxOpen = model:GetAttribute("JawMaxOpen")
	local a = math.clamp(alpha, -0.1, 1.25)
	local angle = a * (if type(maxOpen) == "number" then maxOpen else math.rad(52))
	local target = core.CFrame * hingeA.CFrame * CFrame.Angles(-angle, 0, 0) * hingeB.CFrame:Inverse()
	for _, d in jaw:GetDescendants() do
		if d:IsA("BasePart") then
			local rest = d:GetAttribute("JawRest")
			if typeof(rest) == "CFrame" then
				d.CFrame = target * rest
			end
		end
	end
	model:SetAttribute("JawOpen", a)
end

-- Built + posed in one call (galleries, previews): jaw alpha and glow intensity 0..1.
function GasterBlaster.Preview(style: string?, scale: number?, jaw: number?, glow: number?): Model
	local model = GasterBlaster.Build(style, scale)
	GasterBlaster.SetJaw(model, jaw or 0)
	if glow and glow > 0 then
		GasterBlaster.SetGlow(model, GasterBlaster.DefaultGlow(style), glow)
	end
	return model
end

function GasterBlaster.SetGlow(model: Model, color: Color3, intensity: number)
	local k = math.clamp(intensity, 0, 1)
	local white = Color3.new(1, 1, 1)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			local kind = d:GetAttribute("GlowKind")
			if role == "Eye" then
				local idle = d:GetAttribute("IdleColor")
				local base = if typeof(idle) == "Color3" then idle else white
				d.Color = base:Lerp(white:Lerp(color, 0.75), math.min(1, k * 1.5))
				d.Material = if k > 0.05 then NEON else Enum.Material.SmoothPlastic
				d.Transparency = 0
			elseif kind == "EyeHalo" then
				d.Color = color
				d.Transparency = HIDDEN - 0.7 * k
			elseif kind == "Mouth" then
				d.Color = color
				d.Transparency = HIDDEN - 0.85 * k
			end
		elseif d:IsA("PointLight") and d.Name == "Glow" then
			d.Color = color
			d.Brightness = 3 * k
			d.Enabled = k > 0.01
		end
	end
	model:SetAttribute("GlowIntensity", k)
	model:SetAttribute("GlowColor", color)
end

return GasterBlaster

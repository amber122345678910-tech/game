--!strict
-- AnimMath: pure maths of the procedural animation system (clip compile/sample with easing, pose
-- buffers, blending with masks, mirroring, locomotion & aim weights, clip authoring helpers including a
-- leg IK "Stance" builder, clip validation). [Lune-safe] Used by Anim/Clips/*, the client AnimController,
-- server AimService and tools/lune/tests/anim.spec.luau.
--
-- CLIP FORMAT (SPEC §8) + documented extensions:
--   Clip = { Length, Loop?, Priority? (1 base, 2 action, 3 hit/stun, 4 death), Mask?, Speed?,
--            Keys = { { t, Ease?, Dir?, Pose = { [joint] = {rx,ry,rz[,px,py,pz]} } } }, Events? = { {t, Name} },
--            -- extensions (all optional):
--            FullBody: boolean   keep the clip's legs/root even while moving (default: a "Full" one-shot is
--                                reduced to the UpperMove mask while the character walks/runs)
--            Hold: boolean       a non-looping clip keeps its last pose until stopped (Death, Sit...)
--            FadeIn, FadeOut     default cross-fade times (s) when played (Play opts override)
--            Stride: number      locomotion cycles: studs travelled per cycle (phase-synced cadence)
--            Aim: "Right"|"Left"|"Both"|"Torso"   arms/torso that follow the aim point while the clip plays }
--   Interpolation: a key's Ease/Dir shape the segment ARRIVING at that key (prev key -> this key), e.g.
--   { t = 0.1, Ease = "Back", Dir = "Out", Pose = STRIKE } = "snap into the strike with an overshoot".
--   A key without Ease arrives on a smooth monotone cubic spline (Fritsch-Butland tangents: no overshoot,
--   no stop at intermediate keys; tangents are zero at extremes, clip ends and next to eased segments).
--   Joints absent from EVERY key are not driven by the clip (they pass through to lower layers).
--   Rotation channels are wrapped to (-180, 180] after sampling (so a 0..360 Spin ends seamlessly).
--
-- AUTHORING HELPERS (used by the clip data files)
--   AnimMath.Clip(def) -> Clip            normalises: sorts nothing (keys must be in order), fills joints a key
--                                         omits from the previous key (hold; rest before first mention),
--                                         closes loops (appends a key at Length = first key), validates.
--   AnimMath.Merge(...poses) -> Pose      later poses override earlier ones per joint
--   AnimMath.Add(a, b) -> Pose            component-wise sum;  AnimMath.Scale(pose, k) -> Pose
--   AnimMath.Lerp(a, b, t) -> Pose        per-component lerp (wrap-aware for rotations)
--   AnimMath.MirrorPose(pose) -> Pose     left<->right;  AnimMath.MirrorClip(clip) -> Clip
--   AnimMath.Stance(family, spec) -> Pose leg IK: pelvis drop/pitch/roll/shift + foot targets -> Root, hips,
--                                         knees, ankles with planted, flat (or pitched) feet. See Stance below.
--
-- RUNTIME
--   AnimMath.Compile(clip, name?) -> Compiled      cached per clip table (weak keys)
--   AnimMath.Sample(compiled, time, out, mirror?)  writes driven joints into a pose buffer (90 numbers:
--                                                  joint j channel c at (j-1)*6 + c, Joints order)
--   AnimMath.SamplePose(clip, time, mirror?) -> Pose   convenience (tests / tools)
--   AnimMath.ClipTime(compiled, time) -> number    loop wrap / clamp
--   AnimMath.EventsBetween(compiled, a, b, fn(name, t))  markers with a < t <= b (loop aware)
--   AnimMath.EventTime(clip, name) -> number?      first marker time
--   AnimMath.NewBuffer() / ZeroBuffer(buf) / CopyBuffer(dst, src)
--   AnimMath.BlendInto(dst, src, w, mask?, driven?)   dst = lerp(dst, src, w * mask[j]) (wrap-aware)
--   AnimMath.AddInto(dst, src, w)                    dst += src * w
--   AnimMath.PoseToBuffer(pose, buf?) / BufferToPose(buf) -> Pose
--   AnimMath.ChannelCFrame(buf, j, scale) -> CFrame  Transform for joint j (Angles = Rx*Ry*Rz, one alloc)
--   AnimMath.PoseValueCFrame(value, scale?) -> CFrame
--   AnimMath.Wrap180(deg) -> number
-- LOCOMOTION / LAYERS
--   AnimMath.LocomotionWeights(speed, tuning?) -> (idle, walk, run)      sum = 1
--   AnimMath.DirectionWeights(angleRad) -> (fwd, back, left, right)      sum = 1; angle > 0 = moving left
--   AnimMath.Cadence(speed, stride, minRate?, maxRate?) -> cycles/s
--   AnimMath.Envelope(elapsed, fadeIn, remaining, fadeOut) -> 0..1       smooth fade in/out weight
--   AnimMath.ComboClipName(base, index, comboLength, has) -> string      "Slash1" + index -> SlashN (finisher
--                                                                        = last available when index = length)
--   AnimMath.WindupSpeed(clip, windup, minS?, maxS?) -> number?          speed so "Hit"/"Release" lands on windup
-- AIM
--   AnimMath.AimAngles(rootCF, from, point) -> (yawDeg, pitchDeg)       yaw > 0 = left, pitch > 0 = up
--   AnimMath.SanitizeAim(origin, point, maxRange) -> Vector3?           nil if invalid, clamped to range
--   AnimMath.RateGate(state, now, rate, burst) -> boolean                token bucket (state is a table)
-- VALIDATION
--   AnimMath.ValidateClip(clip, name?) -> (boolean, string?)
--   AnimMath.EASE_STYLES, AnimMath.EASE_DIRS, AnimMath.AIM_MODES

local Joints = require(script.Parent.Joints)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)
local Skeletons = require(script.Parent.Parent.Rigs.Skeletons)

local AnimMath = {}

export type PoseValue = { number }
export type Pose = { [string]: PoseValue }
export type ClipKey = { t: number, Ease: string?, Dir: string?, Pose: Pose }
export type ClipEvent = { t: number, Name: string }
export type Clip = {
	Length: number,
	Loop: boolean?,
	Priority: number?,
	Mask: string?,
	Speed: number?,
	Keys: { ClipKey },
	Events: { ClipEvent }?,
	FullBody: boolean?,
	Hold: boolean?,
	FadeIn: number?,
	FadeOut: number?,
	Stride: number?,
	Aim: string?,
}
export type Buffer = { number }

export type Compiled = {
	Name: string,
	Source: Clip,
	Length: number,
	Loop: boolean,
	Priority: number,
	Mask: string,
	Speed: number,
	FullBody: boolean,
	Hold: boolean,
	FadeIn: number?,
	FadeOut: number?,
	Stride: number?,
	Aim: string?,
	N: number,
	Times: { number },
	Ease: { string | false },
	Dir: { string },
	Driven: { boolean }, -- [jointIndex]
	DrivenList: { number },
	HasT: { boolean }, -- [jointIndex] translation channels non-zero somewhere
	V: { Buffer }, -- per key: 90 values
	M: { Buffer }, -- per key: tangents (units per second)
	Events: { ClipEvent },
	Mirrored: Compiled?,
	IsMirror: boolean,
}

local NJ = Joints.COUNT
local NC = NJ * 6
local ALL = Joints.ALL
local JINDEX = Joints.Index

AnimMath.EASE_STYLES = table.freeze({ "Linear", "Sine", "Quad", "Cubic", "Back", "Elastic", "Bounce", "Expo" })
AnimMath.EASE_DIRS = table.freeze({ "In", "Out", "InOut" })
AnimMath.AIM_MODES = table.freeze({ "Right", "Left", "Both", "Torso" })

local EASE_OK: { [string]: boolean } = {}
for _, s in AnimMath.EASE_STYLES do
	EASE_OK[s] = true
end
local DIR_OK: { [string]: boolean } = { In = true, Out = true, InOut = true }
local AIM_OK: { [string]: boolean } = { Right = true, Left = true, Both = true, Torso = true }

-- Scalars -----------------------------------------------------------------------------------------

local function wrap180(d: number): number
	d = d % 360
	if d > 180 then
		d -= 360
	end
	return d
end
AnimMath.Wrap180 = wrap180

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

-- Authoring helpers -------------------------------------------------------------------------------

local function copyValue(v: PoseValue): PoseValue
	return table.clone(v)
end

function AnimMath.Merge(...: Pose?): Pose
	local out: Pose = {}
	for i = 1, select("#", ...) do
		local p = select(i, ...)
		if p then
			for joint, v in p do
				out[joint] = copyValue(v)
			end
		end
	end
	return out
end

function AnimMath.Add(a: Pose, b: Pose): Pose
	local out: Pose = {}
	for joint, v in a do
		out[joint] = copyValue(v)
	end
	for joint, vb in b do
		local va = out[joint]
		if va == nil then
			out[joint] = copyValue(vb)
		else
			local n = math.max(#va, #vb)
			local v: PoseValue = {}
			for i = 1, n do
				v[i] = (va[i] or 0) + (vb[i] or 0)
			end
			out[joint] = v
		end
	end
	return out
end

function AnimMath.Scale(pose: Pose, k: number): Pose
	local out: Pose = {}
	for joint, v in pose do
		local s: PoseValue = {}
		for i, x in v do
			s[i] = x * k
		end
		out[joint] = s
	end
	return out
end

function AnimMath.Lerp(a: Pose, b: Pose, t: number): Pose
	local out: Pose = {}
	local seen: { [string]: boolean } = {}
	for joint in a do
		seen[joint] = true
	end
	for joint in b do
		seen[joint] = true
	end
	for joint in seen do
		local va, vb = a[joint] or {}, b[joint] or {}
		local n = math.max(#va, #vb, 3)
		local v: PoseValue = {}
		for i = 1, n do
			local x, y = va[i] or 0, vb[i] or 0
			if i <= 3 then
				v[i] = x + wrap180(y - x) * t
			else
				v[i] = x + (y - x) * t
			end
		end
		out[joint] = v
	end
	return out
end

local function mirrorValue(v: PoseValue): PoseValue
	local m: PoseValue = { v[1] or 0, -(v[2] or 0), -(v[3] or 0) }
	if #v > 3 then
		m[4] = -(v[4] or 0)
		m[5] = v[5] or 0
		m[6] = v[6] or 0
	end
	-- avoid "-0" noise in data dumps
	for i, x in m do
		if x == 0 then
			m[i] = 0
		end
	end
	return m
end

function AnimMath.MirrorPose(pose: Pose): Pose
	local out: Pose = {}
	for joint, v in pose do
		local target = Joints.MirrorOf[joint] or joint
		out[target] = mirrorValue(v)
	end
	return out
end

local function copyClipFields(src: Clip): Clip
	local out: Clip = {
		Length = src.Length,
		Loop = src.Loop,
		Priority = src.Priority,
		Mask = src.Mask,
		Speed = src.Speed,
		Keys = {},
		Events = nil,
		FullBody = src.FullBody,
		Hold = src.Hold,
		FadeIn = src.FadeIn,
		FadeOut = src.FadeOut,
		Stride = src.Stride,
		Aim = src.Aim,
	}
	if src.Events then
		local ev: { ClipEvent } = {}
		for _, e in src.Events do
			table.insert(ev, { t = e.t, Name = e.Name })
		end
		out.Events = ev
	end
	return out
end

local MIRROR_AIM: { [string]: string } = { Right = "Left", Left = "Right", Both = "Both", Torso = "Torso" }
local MIRROR_MASK: { [string]: string } = { LeftArm = "RightArm", RightArm = "LeftArm" }

function AnimMath.MirrorClip(clip: Clip): Clip
	local out = copyClipFields(clip)
	for _, key in clip.Keys do
		table.insert(out.Keys, { t = key.t, Ease = key.Ease, Dir = key.Dir, Pose = AnimMath.MirrorPose(key.Pose) })
	end
	if out.Aim then
		out.Aim = MIRROR_AIM[out.Aim] or out.Aim
	end
	if out.Mask then
		out.Mask = MIRROR_MASK[out.Mask] or out.Mask
	end
	return out
end

-- Re-times a LOOPING clip so its new t = 0 is the old t = fraction * Length (keeps locomotion cycles
-- phase-aligned, e.g. a mirrored strafe that must plant the LEFT foot at phase 0 like every other cycle).
function AnimMath.PhaseShift(clip: Clip, fraction: number): Clip
	assert(clip.Loop == true, "AnimMath.PhaseShift: clip must loop")
	local len = clip.Length
	local shift = (fraction % 1) * len
	local out = copyClipFields(clip)
	local keys: { ClipKey } = {}
	local hasZero = false
	for i, key in clip.Keys do
		local closing = i == #clip.Keys and math.abs(key.t - len) < 1e-6
		if not closing then
			local t = (key.t - shift) % len
			if math.abs(t - len) < 1e-6 then
				t = 0
			end
			if math.abs(t) < 1e-6 then
				hasZero = true
				t = 0
			end
			table.insert(keys, { t = t, Ease = key.Ease, Dir = key.Dir, Pose = AnimMath.Merge(key.Pose) })
		end
	end
	if not hasZero then
		table.insert(keys, { t = 0, Pose = AnimMath.SamplePose(clip, shift) })
	end
	table.sort(keys, function(a, b)
		return a.t < b.t
	end)
	out.Keys = keys
	if out.Events then
		for _, e in out.Events do
			e.t = (e.t - shift) % len
		end
		table.sort(out.Events, function(a, b)
			return a.t < b.t
		end)
	end
	return AnimMath.Clip(out)
end

-- Normalises an authored clip definition (see header). Errors on invalid data (caught by tests at load).
function AnimMath.Clip(def: Clip): Clip
	local out = copyClipFields(def)
	local held: Pose = {}
	local mentioned: { [string]: boolean } = {}
	for _, key in def.Keys do
		for joint in key.Pose do
			mentioned[joint] = true
		end
	end
	for _, key in def.Keys do
		for joint, v in key.Pose do
			held[joint] = v
		end
		local pose: Pose = {}
		for joint in mentioned do
			local v = held[joint]
			pose[joint] = if v then copyValue(v) else { 0, 0, 0 }
		end
		table.insert(out.Keys, { t = key.t, Ease = key.Ease, Dir = key.Dir, Pose = pose })
	end
	if out.Loop and #out.Keys >= 1 then
		local first, last = out.Keys[1], out.Keys[#out.Keys]
		if last.t < out.Length - 1e-6 then
			local pose: Pose = {}
			for joint, v in first.Pose do
				pose[joint] = copyValue(v)
			end
			table.insert(out.Keys, { t = out.Length, Pose = pose })
		end
	end
	local ok, err = AnimMath.ValidateClip(out, "AnimMath.Clip")
	if not ok then
		error(err, 2)
	end
	return out
end

-- Leg IK stance builder ----------------------------------------------------------------------------
-- spec = {
--   Drop: number?       pelvis lowered (studs at scale 1; negative = raised)
--   Pitch: number?      Root rx (deg; negative = lean forward)
--   Roll: number?       Root rz (deg; positive = top to the left)
--   Yaw: number?        Root ry (deg) — feet stay planted (hips counter-rotate)
--   Shift: Vector3?     pelvis offset x (right) / z (back), studs
--   Left / Right: { X: number?, Y: number?, Z: number?, Toe: number?, Out: number? }?
--       foot (ankle) offset from its rest position in character space: X = right, Y = up, Z = back (studs);
--       Toe = foot pitch in world (deg; + = toes up, - = on the toes); Out = foot turned outward (deg)
-- }
-- Returns { Root, LeftHip, LeftKnee, LeftAnkle, RightHip, RightKnee, RightAnkle }. Unreachable targets
-- are clamped to a nearly straight leg.
export type FootSpec = { X: number?, Y: number?, Z: number?, Toe: number?, Out: number? }
export type StanceSpec = {
	Drop: number?,
	Pitch: number?,
	Roll: number?,
	Yaw: number?,
	Shift: Vector3?,
	Left: FootSpec?,
	Right: FootSpec?,
}

type LegGeo = { Root: Vector3, Hip: { [string]: Vector3 }, Knee: { [string]: Vector3 }, Ankle: { [string]: Vector3 } }
local legGeoCache: { [string]: LegGeo } = {}

local function legGeometry(family: string): LegGeo
	local g = legGeoCache[family]
	if g then
		return g
	end
	local r = Skeletons.Resolve(family)
	local geo: LegGeo = { Root = r.Joints.Root.Pivot, Hip = {}, Knee = {}, Ankle = {} }
	for _, side in { "Left", "Right" } do
		geo.Hip[side] = r.Joints[side .. "Hip"].Pivot
		geo.Knee[side] = r.Joints[side .. "Knee"].Pivot
		geo.Ankle[side] = r.Joints[side .. "Ankle"].Pivot
	end
	legGeoCache[family] = geo
	return geo
end

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end

local function eulerDeg(cf: CFrame): (number, number, number)
	local x, y, z = cf:ToEulerAnglesXYZ()
	return r3(math.deg(x)), r3(math.deg(y)), r3(math.deg(z))
end

function AnimMath.Stance(family: string, spec: StanceSpec): Pose
	local geo = legGeometry(family)
	local drop = spec.Drop or 0
	local pitch, roll, yaw = spec.Pitch or 0, spec.Roll or 0, spec.Yaw or 0
	local shift = spec.Shift or Vector3.zero
	local rootOffset = Vector3.new(shift.X, -drop, shift.Z)
	local pelvisRot = CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
	local pelvis = CFrame.new(geo.Root + rootOffset) * pelvisRot
	local out: Pose = {
		Root = { pitch, yaw, roll, r3(shift.X), r3(-drop), r3(shift.Z) },
	}
	for _, side in { "Left", "Right" } do
		local foot: FootSpec = (if side == "Left" then spec.Left else spec.Right) or {}
		local hipRest, kneeRest, ankleRest = geo.Hip[side], geo.Knee[side], geo.Ankle[side]
		local a = (hipRest - kneeRest).Magnitude
		local b = (kneeRest - ankleRest).Magnitude
		local hipWorld = pelvis * (hipRest - geo.Root)
		local target = ankleRest + Vector3.new(foot.X or 0, foot.Y or 0, foot.Z or 0)
		local v = pelvis:VectorToObjectSpace(target - hipWorld)
		local L = math.clamp(v.Magnitude, math.abs(a - b) + 1e-3, (a + b) * 0.9995)
		local cosInner = math.clamp((a * a + b * b - L * L) / (2 * a * b), -1, 1)
		local flex = math.pi - math.acos(cosInner) -- knee flexion (0 = straight)
		-- ankle position in the hip frame before the hip rotation (thigh along -Y, shin rotated by -flex)
		local uy = -(a + b * math.cos(flex))
		local uz = b * math.sin(flex)
		local sinZ = math.clamp(v.X / (a + b * math.cos(flex)), -1, 1)
		local hz = math.asin(sinZ)
		local yP, zP = uy * math.cos(hz), uz
		local hx = math.atan2(v.Z, v.Y) - math.atan2(zP, yP)
		hx = math.rad(wrap180(math.deg(hx)))
		local hipRot = CFrame.Angles(hx, 0, hz)
		local kneeRot = CFrame.Angles(-flex, 0, 0)
		-- foot: world orientation = yaw of the character (0) * toe pitch; ankle = (pelvis*hip*knee)^-1 * that
		local outward = math.rad(foot.Out or 0) * (if side == "Left" then 1 else -1)
		local footWorld = CFrame.Angles(0, outward, 0) * CFrame.Angles(math.rad(foot.Toe or 0), 0, 0)
		local ankleRot = (pelvisRot * hipRot * kneeRot):Inverse() * footWorld
		local hxd, _, hzd = math.deg(hx), 0, math.deg(hz)
		out[side .. "Hip"] = { r3(hxd), 0, r3(hzd) }
		out[side .. "Knee"] = { r3(-math.deg(flex)), 0, 0 }
		local ax, ay, az = eulerDeg(ankleRot)
		out[side .. "Ankle"] = { ax, ay, az }
	end
	return out
end

-- Limb direction / arm IK ---------------------------------------------------------------------------
-- Limb(dir, bend?) -> {rx, ry, rz}: rotation of a joint whose child limb hangs along -Y at rest (shoulder,
-- hip, elbow...) so the limb points along `dir` (parent frame). `bend` = direction the NEXT joint flexes
-- toward (its +rx swings the child along this direction); default = the natural plane (ry = 0).
function AnimMath.Limb(dir: Vector3, bend: Vector3?): PoseValue
	local d = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(0, -1, 0)
	if bend == nil then
		local rz = math.asin(math.clamp(d.X, -1, 1))
		local rx = math.atan2(-d.Z, -d.Y)
		if math.abs(math.cos(rz)) < 1e-6 then
			rx = 0
		end
		return { r3(math.deg(rx)), 0, r3(math.deg(rz)) }
	end
	local b = bend :: Vector3
	local f = b - d * b:Dot(d)
	if f.Magnitude < 1e-5 then
		f = Vector3.new(0, 0, -1) - d * (-d.Z)
		if f.Magnitude < 1e-5 then
			f = Vector3.new(0, 1, 0)
		end
	end
	local y = -d
	local z = -f.Unit
	local x = y:Cross(z)
	local cf = CFrame.fromMatrix(Vector3.zero, x, y, z)
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return { r3(math.deg(rx)), r3(math.deg(ry)), r3(math.deg(rz)) }
end

type ArmGeo = {
	Root: Vector3,
	Waist: Vector3,
	Shoulder: { [string]: Vector3 },
	Upper: number,
	Lower: number,
}
local armGeoCache: { [string]: ArmGeo } = {}

local function armGeometry(family: string): ArmGeo
	local g = armGeoCache[family]
	if g then
		return g
	end
	local r = Skeletons.Resolve(family)
	local sh, el, wr = r.Joints.RightShoulder.Pivot, r.Joints.RightElbow.Pivot, r.Joints.RightWrist.Pivot
	local hand = r.Limbs.RightHand.Size.Y
	g = {
		Root = r.Joints.Root.Pivot,
		Waist = r.Joints.Waist.Pivot,
		Shoulder = { Left = r.Joints.LeftShoulder.Pivot, Right = sh },
		Upper = (sh - el).Magnitude,
		Lower = (el - wr).Magnitude + hand * 0.45, -- to the palm centre
	}
	armGeoCache[family] = g
	return g
end

local function poseCF(v: PoseValue?): CFrame
	if v == nil then
		return CFrame.new()
	end
	return CFrame.new(v[4] or 0, v[5] or 0, v[6] or 0) * CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
end

-- Reach(family, side, target, opts?) -> { [side.."Shoulder"], [side.."Elbow"], [side.."Wrist"] }
--   2-bone arm IK: puts the palm centre on `target` (character rest space, studs at scale 1: Y up, -Z
--   forward, feet at y = 0). opts.Spine = pose with Root/Waist values the target is NOT attached to (world
--   targets such as the knees); omit it for targets that move with the torso (pockets, belly, grips).
--   opts.Pole = where the elbow should point (torso frame; default down-out-back); opts.Wrist = wrist value.
export type ReachOpts = { Spine: Pose?, Pole: Vector3?, Wrist: PoseValue? }
function AnimMath.Reach(family: string, side: string, target: Vector3, opts: ReachOpts?): Pose
	local o: ReachOpts = opts or {}
	local g = armGeometry(family)
	local spine: Pose = o.Spine or {}
	local rootF = CFrame.new(g.Root) * poseCF(spine.Root)
	local waistF = rootF * CFrame.new(g.Waist - g.Root) * poseCF(spine.Waist)
	local shoulderW = waistF * (g.Shoulder[side] - g.Waist)
	local v = waistF:VectorToObjectSpace(target - shoulderW)
	local a, b = g.Upper, g.Lower
	local L = math.clamp(v.Magnitude, math.abs(a - b) + 1e-3, (a + b) * 0.999)
	local u = if v.Magnitude > 1e-6 then v.Unit else Vector3.new(0, -1, 0)
	local cosA = math.clamp((a * a + L * L - b * b) / (2 * a * L), -1, 1)
	local angA = math.acos(cosA)
	local s = if side == "Left" then -1 else 1
	local pole = o.Pole or Vector3.new(0.55 * s, -0.45, 0.6)
	local p = pole - u * pole:Dot(u)
	if p.Magnitude < 1e-5 then
		p = Vector3.new(s, 0, 0) - u * (u.X * s)
	end
	p = p.Unit
	local upper = u * math.cos(angA) + p * math.sin(angA)
	local fore = (u * L - upper * a).Unit
	local flex = math.acos(math.clamp(upper:Dot(fore), -1, 1))
	local bend = fore - upper * fore:Dot(upper)
	local out: Pose = {}
	out[side .. "Shoulder"] = AnimMath.Limb(upper, if bend.Magnitude > 1e-5 then bend else nil)
	out[side .. "Elbow"] = { r3(math.deg(flex)), 0, 0 }
	out[side .. "Wrist"] = if o.Wrist then table.clone(o.Wrist) else { 0, 0, 0 }
	return out
end

-- Compile & sample --------------------------------------------------------------------------------

local compiledCache: { [Clip]: Compiled } = setmetatable({} :: any, { __mode = "k" })

local function newBuffer(): Buffer
	local b = table.create(NC, 0)
	return b
end
AnimMath.NewBuffer = newBuffer

function AnimMath.ZeroBuffer(buf: Buffer)
	for i = 1, NC do
		buf[i] = 0
	end
end

function AnimMath.CopyBuffer(dst: Buffer, src: Buffer)
	for i = 1, NC do
		dst[i] = src[i]
	end
end

local function easeArrivalIsSmooth(compiled: Compiled, k: number): boolean
	return compiled.Ease[k] == false
end

-- Fritsch-Butland monotone tangent from two secant slopes over intervals h0, h1.
local function pchipTangent(d0: number, d1: number, h0: number, h1: number): number
	if d0 * d1 <= 0 then
		return 0
	end
	return 3 * (h0 + h1) / ((2 * h1 + h0) / d0 + (h1 + 2 * h0) / d1)
end

local function compileClip(clip: Clip, name: string?): Compiled
	local keys = clip.Keys
	local n = #keys
	local times: { number } = table.create(n, 0)
	local ease: { string | false } = table.create(n, false)
	local dirs: { string } = table.create(n, "Out")
	local values: { Buffer } = {}
	local driven: { boolean } = table.create(NJ, false)
	local hasT: { boolean } = table.create(NJ, false)
	for k, key in keys do
		times[k] = key.t
		ease[k] = if k > 1 and key.Ease ~= nil then key.Ease :: string else false
		dirs[k] = key.Dir or "Out"
		local buf = newBuffer()
		for joint, v in key.Pose do
			local j = JINDEX[joint]
			if j then
				driven[j] = true
				local o = (j - 1) * 6
				for c = 1, 6 do
					local x = v[c] or 0
					buf[o + c] = x
					if c > 3 and x ~= 0 then
						hasT[j] = true
					end
				end
			end
		end
		values[k] = buf
	end
	local drivenList: { number } = {}
	for j = 1, NJ do
		if driven[j] then
			table.insert(drivenList, j)
		end
	end
	local loop = clip.Loop == true
	local length = clip.Length
	-- tangents
	local tangents: { Buffer } = {}
	for k = 1, n do
		local m = newBuffer()
		local prev, nextK = k - 1, k + 1
		local tPrev, tNext
		if prev >= 1 then
			tPrev = times[prev]
		elseif loop and n >= 3 then
			prev = n - 1
			tPrev = times[prev] - length
		end
		if nextK <= n then
			tNext = times[nextK]
		elseif loop and n >= 3 then
			nextK = 2
			tNext = times[2] + length
		end
		-- zero tangents at clip ends (non-looping) and next to eased segments
		local zero = prev < 1 or nextK > n or tPrev == nil or tNext == nil
		if not zero then
			local arriveEased = ease[k] ~= false
			local leaveEased = if k + 1 <= n then ease[k + 1] ~= false else ease[2] ~= false
			if (k > 1 and arriveEased) or leaveEased then
				zero = true
			end
			if k == 1 and loop and ease[n] ~= false then
				zero = true
			end
		end
		if not zero then
			local h0 = times[k] - (tPrev :: number)
			local h1 = (tNext :: number) - times[k]
			if h0 > 1e-6 and h1 > 1e-6 then
				local vp, vk, vn = values[prev], values[k], values[nextK]
				for _, j in drivenList do
					local o = (j - 1) * 6
					for c = 1, 6 do
						local i = o + c
						local d0, d1
						if c <= 3 then
							d0 = wrap180(vk[i] - vp[i]) / h0
							d1 = wrap180(vn[i] - vk[i]) / h1
							-- authored multi-turn spins (|step| > 180) keep their raw slope
							if math.abs(vk[i] - vp[i]) > 180 then
								d0 = (vk[i] - vp[i]) / h0
							end
							if math.abs(vn[i] - vk[i]) > 180 then
								d1 = (vn[i] - vk[i]) / h1
							end
						else
							d0 = (vk[i] - vp[i]) / h0
							d1 = (vn[i] - vk[i]) / h1
						end
						m[i] = pchipTangent(d0, d1, h0, h1)
					end
				end
			end
		end
		tangents[k] = m
	end
	if loop and n >= 2 then
		tangents[n] = tangents[1]
	end
	local events: { ClipEvent } = {}
	if clip.Events then
		for _, e in clip.Events do
			table.insert(events, { t = e.t, Name = e.Name })
		end
		table.sort(events, function(x, y)
			return x.t < y.t
		end)
	end
	return {
		Name = name or "?",
		Source = clip,
		Length = length,
		Loop = loop,
		Priority = clip.Priority or 2,
		Mask = clip.Mask or "Full",
		Speed = clip.Speed or 1,
		FullBody = clip.FullBody == true,
		Hold = clip.Hold == true,
		FadeIn = clip.FadeIn,
		FadeOut = clip.FadeOut,
		Stride = clip.Stride,
		Aim = clip.Aim,
		N = n,
		Times = times,
		Ease = ease,
		Dir = dirs,
		Driven = driven,
		DrivenList = drivenList,
		HasT = hasT,
		V = values,
		M = tangents,
		Events = events,
		Mirrored = nil,
		IsMirror = false,
	}
end

function AnimMath.Compile(clip: Clip, name: string?): Compiled
	local c = compiledCache[clip]
	if c == nil then
		c = compileClip(clip, name)
		compiledCache[clip] = c
	end
	return c
end

local function mirrored(c: Compiled): Compiled
	local m = c.Mirrored
	if m then
		return m
	end
	local src = AnimMath.MirrorClip(c.Source)
	local mc = compileClip(src, c.Name)
	mc.IsMirror = true
	c.Mirrored = mc
	return mc
end

function AnimMath.ClipTime(c: Compiled, time: number): number
	local len = c.Length
	if c.Loop then
		if len <= 0 then
			return 0
		end
		local t = time % len
		return t
	end
	return math.clamp(time, 0, len)
end

-- Samples the compiled clip at `time` (seconds, unscaled) into `out` (driven joints only).
function AnimMath.Sample(c: Compiled, time: number, out: Buffer, mirror: boolean?)
	if mirror then
		c = mirrored(c)
	end
	local n = c.N
	if n == 0 then
		return
	end
	local t = AnimMath.ClipTime(c, time)
	local times = c.Times
	local list = c.DrivenList
	if n == 1 or t <= times[1] then
		local v = c.V[1]
		for _, j in list do
			local o = (j - 1) * 6
			for ch = 1, 6 do
				out[o + ch] = v[o + ch]
			end
		end
		return
	end
	if t >= times[n] then
		local v = c.V[n]
		for _, j in list do
			local o = (j - 1) * 6
			for ch = 1, 6 do
				local x = v[o + ch]
				if ch <= 3 and (x > 180 or x < -180) then
					x = wrap180(x)
				end
				out[o + ch] = x
			end
		end
		return
	end
	-- segment search (clips have few keys)
	local k = 1
	while k < n - 1 and t >= times[k + 1] do
		k += 1
	end
	local t0, t1 = times[k], times[k + 1]
	local h = t1 - t0
	local s = if h > 1e-9 then (t - t0) / h else 1
	local v0, v1 = c.V[k], c.V[k + 1]
	local style = c.Ease[k + 1]
	if style ~= false then
		local e = MathUtil.Ease(s, style, c.Dir[k + 1])
		-- Back/Elastic overshoot past the target is intended: the eased alpha may leave [0, 1].
		for _, j in list do
			local o = (j - 1) * 6
			for ch = 1, 6 do
				local i = o + ch
				local a = v0[i]
				local x = a + (v1[i] - a) * e
				if ch <= 3 and (x > 180 or x < -180) then
					x = wrap180(x)
				end
				out[i] = x
			end
		end
	else
		local s2 = s * s
		local s3 = s2 * s
		local h00 = 2 * s3 - 3 * s2 + 1
		local h10 = (s3 - 2 * s2 + s) * h
		local h01 = -2 * s3 + 3 * s2
		local h11 = (s3 - s2) * h
		local m0, m1 = c.M[k], c.M[k + 1]
		for _, j in list do
			local o = (j - 1) * 6
			for ch = 1, 6 do
				local i = o + ch
				local x = h00 * v0[i] + h10 * m0[i] + h01 * v1[i] + h11 * m1[i]
				if ch <= 3 and (x > 180 or x < -180) then
					x = wrap180(x)
				end
				out[i] = x
			end
		end
	end
end

function AnimMath.BufferToPose(buf: Buffer, driven: { boolean }?): Pose
	local pose: Pose = {}
	for j, joint in ALL do
		if driven == nil or driven[j] then
			local o = (j - 1) * 6
			local v: PoseValue = { buf[o + 1], buf[o + 2], buf[o + 3] }
			if buf[o + 4] ~= 0 or buf[o + 5] ~= 0 or buf[o + 6] ~= 0 then
				v[4], v[5], v[6] = buf[o + 4], buf[o + 5], buf[o + 6]
			end
			pose[joint] = v
		end
	end
	return pose
end

function AnimMath.PoseToBuffer(pose: Pose, buf: Buffer?): Buffer
	local b = buf or newBuffer()
	for joint, v in pose do
		local j = JINDEX[joint]
		if j then
			local o = (j - 1) * 6
			for c = 1, 6 do
				b[o + c] = v[c] or 0
			end
		end
	end
	return b
end

function AnimMath.SamplePose(clip: Clip, time: number, mirror: boolean?): Pose
	local c = AnimMath.Compile(clip)
	local buf = newBuffer()
	AnimMath.Sample(c, time, buf, mirror)
	local cc = if mirror then mirrored(c) else c
	return AnimMath.BufferToPose(buf, cc.Driven)
end

-- Fires fn(name, t) for every marker with a < t <= b (a, b = unwrapped clip times; loops repeat).
function AnimMath.EventsBetween(c: Compiled, a: number, b: number, fn: (string, number) -> ())
	local events = c.Events
	if #events == 0 or b <= a then
		return
	end
	if c.Loop and c.Length > 0 then
		local len = c.Length
		local n0 = math.floor(a / len)
		local n1 = math.floor(b / len)
		if n1 - n0 > 4 then
			n0 = n1 - 4 -- huge hitch: only the latest few cycles
		end
		for cycle = n0, n1 do
			local base = cycle * len
			for _, e in events do
				local tt = base + e.t
				if tt > a and tt <= b then
					fn(e.Name, e.t)
				end
			end
		end
	else
		for _, e in events do
			if e.t > a and e.t <= b then
				fn(e.Name, e.t)
			end
		end
	end
end

function AnimMath.EventTime(clip: Clip, name: string): number?
	if clip.Events then
		local best: number? = nil
		for _, e in clip.Events do
			if e.Name == name and (best == nil or e.t < (best :: number)) then
				best = e.t
			end
		end
		return best
	end
	return nil
end

-- Blending ----------------------------------------------------------------------------------------

function AnimMath.BlendInto(dst: Buffer, src: Buffer, w: number, mask: { number }?, driven: { boolean }?)
	if w <= 0 then
		return
	end
	for j = 1, NJ do
		if driven == nil or driven[j] then
			local wj = if mask then w * mask[j] else w
			if wj > 0 then
				if wj > 1 then
					wj = 1
				end
				local o = (j - 1) * 6
				for c = 1, 3 do
					local a = dst[o + c]
					local d = src[o + c] - a
					if d > 180 or d < -180 then
						d = wrap180(d)
					end
					dst[o + c] = a + d * wj
				end
				for c = 4, 6 do
					local a = dst[o + c]
					dst[o + c] = a + (src[o + c] - a) * wj
				end
			end
		end
	end
end

function AnimMath.AddInto(dst: Buffer, src: Buffer, w: number)
	if w == 0 then
		return
	end
	for i = 1, NC do
		dst[i] += src[i] * w
	end
end

-- Transform for joint j: CFrame.new(p * scale) * CFrame.Angles(rx, ry, rz), built with ONE allocation.
function AnimMath.ChannelCFrame(buf: Buffer, j: number, scale: number): CFrame
	local o = (j - 1) * 6
	local rx, ry, rz = math.rad(buf[o + 1]), math.rad(buf[o + 2]), math.rad(buf[o + 3])
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	return CFrame.new(
		buf[o + 4] * scale,
		buf[o + 5] * scale,
		buf[o + 6] * scale,
		cy * cz,
		-cy * sz,
		sy,
		cx * sz + sx * sy * cz,
		cx * cz - sx * sy * sz,
		-sx * cy,
		sx * sz - cx * sy * cz,
		sx * cz + cx * sy * sz,
		cx * cy
	)
end

function AnimMath.PoseValueCFrame(value: PoseValue, scale: number?): CFrame
	local s = scale or 1
	return CFrame.new((value[4] or 0) * s, (value[5] or 0) * s, (value[6] or 0) * s)
		* CFrame.Angles(math.rad(value[1] or 0), math.rad(value[2] or 0), math.rad(value[3] or 0))
end

-- Locomotion & layer weights ----------------------------------------------------------------------

export type LocoTuning = { MoveStart: number?, MoveFull: number?, RunStart: number?, RunFull: number? }

function AnimMath.LocomotionWeights(speed: number, tuning: LocoTuning?): (number, number, number)
	local tu: LocoTuning = tuning or {}
	local m = MathUtil.smoothstep(tu.MoveStart or 0.35, tu.MoveFull or 2.6, speed)
	local r = MathUtil.smoothstep(tu.RunStart or 9.5, tu.RunFull or 14.5, speed)
	return 1 - m, m * (1 - r), m * r
end

function AnimMath.DirectionWeights(angle: number): (number, number, number, number)
	local c, s = math.cos(angle), math.sin(angle)
	local f = if c > 0 then c * c else 0
	local b = if c < 0 then c * c else 0
	local l = if s > 0 then s * s else 0
	local r = if s < 0 then s * s else 0
	local sum = f + b + l + r
	if sum <= 1e-9 then
		return 1, 0, 0, 0
	end
	return f / sum, b / sum, l / sum, r / sum
end

function AnimMath.Cadence(speed: number, stride: number, minRate: number?, maxRate: number?): number
	if stride <= 0 then
		return minRate or 0
	end
	return math.clamp(speed / stride, minRate or 0.55, maxRate or 2.6)
end

function AnimMath.Envelope(elapsed: number, fadeIn: number, remaining: number, fadeOut: number): number
	local a = if fadeIn > 1e-4 then math.clamp(elapsed / fadeIn, 0, 1) else 1
	local b = if fadeOut > 1e-4 then math.clamp(remaining / fadeOut, 0, 1) else 1
	-- smoothstep shaping: no velocity kink when a fade starts or ends
	a = a * a * (3 - 2 * a)
	b = b * b * (3 - 2 * b)
	return a * b
end

function AnimMath.ComboClipName(base: string, index: number, comboLength: number, has: (string) -> boolean): string
	local prefix, num = string.match(base, "^(.-)(%d+)$")
	if prefix == nil or num == nil or comboLength <= 1 then
		return base
	end
	local count = 0
	for i = 1, 9 do
		if has(prefix .. i) then
			count = i
		else
			break
		end
	end
	if count <= 1 then
		return base
	end
	local idx = math.max(1, math.floor(index))
	if idx >= comboLength then
		return prefix .. count -- finisher
	end
	local cycle = math.max(1, count - 1)
	return prefix .. (((idx - 1) % cycle) + 1)
end

-- Playback speed that makes the clip's first "Hit"/"Release" marker land on the ability's windup.
function AnimMath.WindupSpeed(clip: Clip, windup: number?, minSpeed: number?, maxSpeed: number?): number?
	if windup == nil or windup <= 0.02 then
		return nil
	end
	local marker = AnimMath.EventTime(clip, "Release") or AnimMath.EventTime(clip, "Hit")
	if marker == nil or marker <= 0.02 then
		return nil
	end
	local base = clip.Speed or 1
	local s = marker / (windup * base)
	local lo, hi = minSpeed or 0.6, maxSpeed or 1.7
	if s < lo * 0.75 or s > hi * 1.35 then
		return nil -- too far off: the clip was not meant for this windup; play it as authored
	end
	return math.clamp(s, lo, hi)
end

-- Aim ---------------------------------------------------------------------------------------------

function AnimMath.AimAngles(rootCF: CFrame, from: Vector3, point: Vector3): (number, number)
	local d = point - from
	local x = d:Dot(rootCF.RightVector)
	local y = d:Dot(rootCF.UpVector)
	local f = d:Dot(rootCF.LookVector)
	local yaw = math.deg(math.atan2(-x, f))
	local pitch = math.deg(math.atan2(y, math.sqrt(x * x + f * f)))
	return yaw, pitch
end

function AnimMath.SanitizeAim(origin: Vector3, point: any, maxRange: number): Vector3?
	if typeof(point) ~= "Vector3" then
		return nil
	end
	local p = point :: Vector3
	if not (finite(p.X) and finite(p.Y) and finite(p.Z)) then
		return nil
	end
	if math.abs(p.X) > 1e6 or math.abs(p.Y) > 1e6 or math.abs(p.Z) > 1e6 then
		return nil
	end
	local d = p - origin
	local m = d.Magnitude
	if m > maxRange and m > 0 then
		return origin + d * (maxRange / m)
	end
	return p
end

export type RateState = { Tokens: number?, Last: number? }

function AnimMath.RateGate(state: RateState, now: number, rate: number, burst: number): boolean
	local last = state.Last or now
	local tokens = state.Tokens or burst
	tokens = math.min(burst, tokens + math.max(0, now - last) * rate)
	state.Last = now
	if tokens >= 1 then
		state.Tokens = tokens - 1
		return true
	end
	state.Tokens = tokens
	return false
end

-- Validation --------------------------------------------------------------------------------------

function AnimMath.ValidateClip(clip: any, name: string?): (boolean, string?)
	local label = name or "clip"
	local function fail(msg: string): (boolean, string?)
		return false, label .. ": " .. msg
	end
	if type(clip) ~= "table" then
		return fail("not a table")
	end
	if not finite(clip.Length) or clip.Length <= 0 or clip.Length > 60 then
		return fail("Length must be a number in (0, 60]")
	end
	if clip.Loop ~= nil and type(clip.Loop) ~= "boolean" then
		return fail("Loop must be boolean")
	end
	if clip.Priority ~= nil and (type(clip.Priority) ~= "number" or clip.Priority < 1 or clip.Priority > 4) then
		return fail("Priority must be 1..4")
	end
	if clip.Mask ~= nil and not Joints.IsMask(clip.Mask) then
		return fail("unknown Mask " .. tostring(clip.Mask))
	end
	if clip.Speed ~= nil and (not finite(clip.Speed) or clip.Speed <= 0) then
		return fail("Speed must be > 0")
	end
	for _, f in { "FullBody", "Hold" } do
		if clip[f] ~= nil and type(clip[f]) ~= "boolean" then
			return fail(f .. " must be boolean")
		end
	end
	for _, f in { "FadeIn", "FadeOut" } do
		if clip[f] ~= nil and (not finite(clip[f]) or clip[f] < 0 or clip[f] > 5) then
			return fail(f .. " must be in [0, 5]")
		end
	end
	if clip.Stride ~= nil and (not finite(clip.Stride) or clip.Stride <= 0) then
		return fail("Stride must be > 0")
	end
	if clip.Aim ~= nil and not AIM_OK[clip.Aim] then
		return fail("Aim must be Right/Left/Both/Torso")
	end
	local keys = clip.Keys
	if type(keys) ~= "table" or #keys == 0 then
		return fail("Keys must be a non-empty array")
	end
	local lastT = -math.huge
	for k, key in keys do
		if type(key) ~= "table" or not finite(key.t) then
			return fail(("key %d: t must be a finite number"):format(k))
		end
		if key.t < -1e-6 or key.t > clip.Length + 1e-6 then
			return fail(("key %d: t=%.3f outside [0, Length=%.3f]"):format(k, key.t, clip.Length))
		end
		if key.t <= lastT then
			return fail(("key %d: times must strictly increase"):format(k))
		end
		lastT = key.t
		if key.Ease ~= nil and not EASE_OK[key.Ease] then
			return fail(("key %d: unknown Ease %s"):format(k, tostring(key.Ease)))
		end
		if key.Dir ~= nil and not DIR_OK[key.Dir] then
			return fail(("key %d: unknown Dir %s"):format(k, tostring(key.Dir)))
		end
		if type(key.Pose) ~= "table" then
			return fail(("key %d: Pose must be a table"):format(k))
		end
		for joint, v in key.Pose do
			if not Joints.Valid[joint] then
				return fail(("key %d: unknown joint %s"):format(k, tostring(joint)))
			end
			if type(v) ~= "table" or (#v ~= 3 and #v ~= 6) then
				return fail(("key %d: %s must have 3 or 6 numbers"):format(k, joint))
			end
			for i, x in v do
				if not finite(x) then
					return fail(("key %d: %s[%d] is not finite"):format(k, joint, i))
				end
				if i <= 3 and math.abs(x) > 720 then
					return fail(("key %d: %s rotation %g out of range"):format(k, joint, x))
				end
				if i > 3 and math.abs(x) > 8 then
					return fail(("key %d: %s translation %g out of range"):format(k, joint, x))
				end
			end
		end
	end
	if clip.Loop == true then
		if math.abs(keys[1].t) > 1e-6 then
			return fail("looping clip must start with a key at t = 0")
		end
	end
	if clip.Events ~= nil then
		if type(clip.Events) ~= "table" then
			return fail("Events must be an array")
		end
		local lastE = -math.huge
		for i, e in clip.Events do
			if type(e) ~= "table" or not finite(e.t) or type(e.Name) ~= "string" or e.Name == "" then
				return fail(("event %d: needs t (number) and Name (string)"):format(i))
			end
			if e.t < 0 or e.t > clip.Length + 1e-6 then
				return fail(("event %d (%s) outside [0, Length]"):format(i, e.Name))
			end
			if e.t < lastE then
				return fail("events must be sorted by t")
			end
			lastE = e.t
		end
	end
	return true, nil
end

return AnimMath

--!strict
-- Chain prop: Fell Sans' Chain Grab - a chain of small red bones ending in a bone hook. [Lune-safe]
-- Each link is a tiny bone (shaft + a knob pair at each end, 5 parts); consecutive links are rolled 90
-- degrees and overlap knob-into-knob like real chain links. The chain starts at the origin ("Anchor")
-- and runs along -Z to a bone harpoon head ("Hook*": shank, point, two barbs).
--
-- API
--   Chain.Build(links: number?, color: Color3?, scale: number?) -> Model
--        links default 10 (1..24). PrimaryPart "Anchor" (small knob at the origin). Parts
--        "Link<i>" (shaft), "Link<i>k1..k4" (knobs) with attribute Link = i, hook parts "Hook*".
--        Attributes: PropId, Links, Pitch (studs per link at rest), Scale, PartCount.
--   Chain.Fit(model, from: Vector3, to: Vector3, sag: number?)
--        re-lays the links evenly from `from` (anchor) to `to` (hook tip) in world space (pure instance
--        edits; sag = sideways droop in studs at the middle, default 0). Use every frame while thrown.
--   Chain.Pitch -> number   link spacing at scale 1

local Props = require(script.Parent)

local Chain = {}

local PITCH = 0.62
Chain.Pitch = PITCH
local RED = Color3.fromRGB(194, 31, 43)
local DARK = Color3.fromRGB(110, 14, 22)

-- Local layout of one link around its centre (axis = -Z), rolled by `roll`.
local function linkParts(kit: any, model: Model, i: number, centre: CFrame, color: Color3)
	local roll = if i % 2 == 0 then math.pi / 2 else 0
	local frame = centre * CFrame.Angles(0, 0, roll)
	local props = { Role = "Bone", Attributes = { Link = i } }
	local knobProps = { Role = "Bone", CastShadow = false, Attributes = { Link = i } }
	local half = PITCH * 0.5
	kit.Cyl(model, "Link" .. i, PITCH * 0.9, 0.1, frame * CFrame.Angles(0, math.pi / 2, 0), color, props)
	local k = 0
	for _, z in { -half + 0.07, half - 0.07 } do
		for _, x in { -0.055, 0.055 } do
			k += 1
			kit.Ball(model, "Link" .. i .. "k" .. k, 0.15, frame * CFrame.new(x, 0, z), color:Lerp(DARK, 0.12), knobProps)
		end
	end
end

function Chain.Build(links: number?, color: Color3?, scale: number?): Model
	local n = math.clamp(math.floor(links or 10), 1, 24)
	local c = color or RED
	local s = scale or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("Chain", "Chain")
	local anchor = kit.Ball(model, "Anchor", 0.3, CFrame.new(), DARK, { Role = "Bone" })
	for i = 1, n do
		linkParts(kit, model, i, CFrame.new(0, 0, -(i - 0.5) * PITCH), c)
	end
	-- the hook: a curved bone claw at the end
	local zEnd = -n * PITCH
	local hook = { Role = "Bone", Attributes = { Link = n + 1 } }
	local function seg(name: string, a: Vector3, b: Vector3, d: number)
		local dir = b - a
		local x = Vector3.new(1, 0, 0)
		local z = -dir.Unit
		local y = z:Cross(x).Unit
		x = y:Cross(z)
		kit.Ellipsoid(model, name, Vector3.new(d, d, dir.Magnitude * 1.35), CFrame.fromMatrix((a + b) / 2, x, y, z), c, hook)
	end
	-- harpoon head: a thicker bone shank, a sharp point and two barbs swept back
	local p0 = Vector3.new(0, 0, zEnd + 0.02)
	local p1 = Vector3.new(0, 0, zEnd - 0.42)
	local tip = Vector3.new(0, 0, zEnd - 0.95)
	seg("HookShank", p0, p1, 0.16)
	seg("HookPoint", p1 + Vector3.new(0, 0, 0.12), tip, 0.2)
	for i, sx in { -1, 1 } do
		local root = Vector3.new(sx * 0.05, 0, zEnd - 0.62)
		seg("HookBarb" .. i, root, root + Vector3.new(sx * 0.3, 0, 0.32), 0.07)
	end
	kit.Ball(model, "HookKnobL", 0.2, CFrame.new(-0.07, 0, zEnd + 0.02), c:Lerp(DARK, 0.12), hook)
	kit.Ball(model, "HookKnobR", 0.2, CFrame.new(0.07, 0, zEnd + 0.02), c:Lerp(DARK, 0.12), hook)
	model:SetAttribute("Links", n)
	model:SetAttribute("Pitch", PITCH * s)
	model:SetAttribute("Scale", s)
	-- rest layout relative to each link's centre (for Fit)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local i = d:GetAttribute("Link")
			if type(i) == "number" then
				local centre = CFrame.new(0, 0, -(i - 0.5) * PITCH * s)
				d:SetAttribute("LinkRest", centre:Inverse() * d.CFrame)
			end
		end
	end
	return Props.Finish(model, anchor)
end

function Chain.Fit(model: Model, from: Vector3, to: Vector3, sag: number?)
	local n = model:GetAttribute("Links")
	local count = if type(n) == "number" then n else 10
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 1e-3 then
		return
	end
	local dir = delta / dist
	-- frame whose -Z points along the chain
	local up = if math.abs(dir.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local right = dir:Cross(up).Unit
	local y = right:Cross(dir).Unit
	local sAttr = model:GetAttribute("Scale")
	local s = if type(sAttr) == "number" then sAttr else 1
	local hookCentre = math.max(dist - 0.64 * s, 0.02)
	local step = math.max(hookCentre - 0.31 * s, 0.01) / count
	local droop = sag or 0
	local anchor = model.PrimaryPart
	if anchor then
		anchor.CFrame = CFrame.fromMatrix(from, right, y, -dir)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local i = d:GetAttribute("Link")
			local rest = d:GetAttribute("LinkRest")
			if type(i) == "number" and typeof(rest) == "CFrame" then
				local along = if i > count then hookCentre else (i - 0.5) * step
				local t = math.clamp(along / dist, 0, 1)
				local p = from + dir * along - y * (droop * 4 * t * (1 - t))
				d.CFrame = CFrame.fromMatrix(p, right, y, -dir) * rest
			end
		end
	end
end

return Chain

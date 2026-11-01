--!strict
-- Bone prop: the cartoon attack bone (Undertale's knobbed bone sprite in 3D). [Lune-safe]
-- 5 parts: a cylinder shaft + two overlapping ball knobs at each end (the knob pair spreads along the
-- model's X axis, so the classic bone silhouette faces the camera from the front, -Z).
-- Cheap enough for bone walls / spike rings (dozens of bones), robust from 0.5 to 40+ studs long.
--
-- API
--   Bone.Build(length: number, thickness: number, color: Color3, material: Enum.Material?) -> Model
--        length = tip to tip (knobs included); thickness = shaft diameter (knob pair ~2.1x wider).
--        Centred on the origin, axis along the model's local Y. PrimaryPart "Shaft" (a Cylinder part
--        rotated so its X axis runs along Y) carries a PivotOffset, so Model:GetPivot()/PivotTo use a
--        frame whose UpVector is the bone axis. Parts: Shaft, KnobTopL, KnobTopR, KnobBottomL,
--        KnobBottomR (Anchored, Role "Bone"). Default material SmoothPlastic; pass Neon for the
--        flat glowing blue/orange rule bones. Attributes: Length, Thickness, PropId, PartCount.
--   Bone.SetLength(model, length)         re-layout in place about the current pivot (pooled bones,
--                                         spikes that grow); keeps thickness (shrinks knobs if needed)
--   Bone.SetColor(model, color, material?) recolour every part (blue/orange rule swaps)
--   Bone.Frame(model) -> CFrame           the bone frame (centre, UpVector = axis) without engine calls
--   Bone.Colors = { White, Blue (#14A9FF), Orange (#FFA040), Red, Purple, Cyan }

local Props = require(script.Parent)

local Bone = {}

Bone.Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Blue = Color3.fromRGB(20, 169, 255),
	Orange = Color3.fromRGB(255, 160, 64),
	Red = Color3.fromRGB(255, 36, 48),
	Purple = Color3.fromRGB(213, 53, 217),
	Cyan = Color3.fromRGB(66, 252, 255),
}

local KNOB = 1.32 -- knob diameter / shaft thickness
local SPREAD = 0.4 -- knob centre offset from the axis / shaft thickness
local MIN_SIZE = 0.02
local Y_TO_X = CFrame.Angles(0, 0, math.pi / 2) -- part X axis -> model Y axis

type Layout = { shaft: number, shaftLength: number, knob: number, spread: number, knobY: number }

local function layout(length: number, thickness: number): Layout
	local len = math.max(length, MIN_SIZE * 4)
	local t = math.max(thickness, MIN_SIZE)
	local knob = t * KNOB
	-- short bones: the knobs never take more than ~45% of the length each
	local maxKnob = len * 0.45
	if knob > maxKnob then
		knob = maxKnob
		t = math.min(t, knob / KNOB * 1.08)
	end
	local knobY = math.max(len / 2 - knob / 2, 0)
	return {
		shaft = t,
		shaftLength = math.max(knobY * 2, MIN_SIZE),
		knob = knob,
		spread = t * SPREAD,
		knobY = knobY,
	}
end

local KNOBS = {
	{ "KnobTopL", -1, 1 },
	{ "KnobTopR", 1, 1 },
	{ "KnobBottomL", -1, -1 },
	{ "KnobBottomR", 1, -1 },
}

function Bone.Build(length: number, thickness: number, color: Color3, material: Enum.Material?): Model
	local L = layout(length, thickness)
	local kit = Props.Kit(1)
	local model = Props.NewModel("Bone", "Bone")
	local props = { Role = "Bone", Material = material or Enum.Material.SmoothPlastic }
	local shaft = kit.Cyl(model, "Shaft", L.shaftLength, L.shaft, Y_TO_X, color, props)
	shaft.PivotOffset = Y_TO_X:Inverse()
	for _, k in KNOBS do
		local name, sx, sy = k[1] :: string, k[2] :: number, k[3] :: number
		kit.Ball(model, name, L.knob, CFrame.new(sx * L.spread, sy * L.knobY, 0), color, props)
	end
	model:SetAttribute("Length", length)
	model:SetAttribute("Thickness", thickness)
	return Props.Finish(model, shaft)
end

function Bone.Frame(model: Model): CFrame
	local shaft = model:FindFirstChild("Shaft") :: BasePart?
	if shaft == nil then
		return CFrame.new()
	end
	return shaft.CFrame * Y_TO_X:Inverse()
end

function Bone.SetLength(model: Model, length: number)
	local shaft = model:FindFirstChild("Shaft") :: BasePart?
	if shaft == nil then
		return
	end
	local thickness = model:GetAttribute("Thickness")
	local L = layout(length, if type(thickness) == "number" then thickness else shaft.Size.Y)
	local frame = Bone.Frame(model)
	shaft.Size = Vector3.new(L.shaftLength, L.shaft, L.shaft)
	shaft.CFrame = frame * Y_TO_X
	for _, k in KNOBS do
		local part = model:FindFirstChild(k[1] :: string) :: BasePart?
		if part then
			part.Size = Vector3.new(L.knob, L.knob, L.knob)
			part.CFrame = frame * CFrame.new((k[2] :: number) * L.spread, (k[3] :: number) * L.knobY, 0)
		end
	end
	model:SetAttribute("Length", length)
end

function Bone.SetColor(model: Model, color: Color3, material: Enum.Material?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = color
			if material then
				d.Material = material
			end
		end
	end
end

return Bone

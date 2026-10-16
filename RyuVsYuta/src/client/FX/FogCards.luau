--!strict
-- Рисует карточки тумана (Sequence/FogCards) пулом Beam: два Attachment по краям листа вдоль
-- правого вектора камеры (с поворотом в плоскости кадра), ширина Beam = высота листа.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local FogCardsData = require(Shared:WaitForChild("Sequence"):WaitForChild("FogCards"))
local Types = require(Shared:WaitForChild("Sequence"):WaitForChild("Types"))
local TextureLoader = require(script.Parent:WaitForChild("TextureLoader"))

local FogCards = {}

type Slot = { beam: Beam, a0: Attachment, a1: Attachment, tex: string, used: boolean }

local holder: Part
local pool: { Slot } = {}

local function newSlot(): Slot
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 1
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	b.TextureSpeed = 0
	b.LightInfluence = 0.3
	b.LightEmission = 0
	b.Brightness = 1.35
	b.CurveSize0 = 0
	b.CurveSize1 = 0
	b.Enabled = false
	b.Parent = holder
	return { beam = b, a0 = a0, a1 = a1, tex = "", used = false }
end

function FogCards.init(parent: Instance)
	holder = Instance.new("Part")
	holder.Name = "FogCards"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new()
	holder.Parent = parent
	for _ = 1, 48 do
		table.insert(pool, newSlot())
	end
end

function FogCards.update(frame: Types.Frame, t: number)
	local cam = Workspace.CurrentCamera
	if not cam or not holder then
		return
	end
	local shot = if frame.shotName == "A" or frame.shotName == "Menu" then "A" else "BC"
	local camCF = frame.camera.cf
	local tt = if frame.shotName == "Menu" then 8.5 + (t % 20) * 0.1 else t
	local states: { FogCardsData.CardState } = if frame.shotName == "End" then {} else FogCardsData.evaluate(tt, shot, camCF)
	local right = camCF.RightVector
	local up = camCF.UpVector
	for i, s in states do
		local slot = pool[i]
		if not slot then
			slot = newSlot()
			pool[i] = slot
		end
		local r = math.rad(s.roll)
		local axis = (right * math.cos(r) + up * math.sin(r)) * (s.w * 0.5)
		slot.a0.Position = s.center - axis
		slot.a1.Position = s.center + axis
		slot.beam.Width0 = s.h
		slot.beam.Width1 = s.h
		slot.beam.Transparency = NumberSequence.new(1 - s.alpha)
		slot.beam.Color = ColorSequence.new(s.color)
		local tex = TextureLoader.get(s.tex)
		if slot.tex ~= tex then
			slot.tex = tex
			slot.beam.Texture = tex
		end
		slot.beam.Enabled = true
		slot.used = true
	end
	for i = #states + 1, #pool do
		local slot = pool[i]
		if slot.used then
			slot.used = false
			slot.beam.Enabled = false
		end
	end
end

return FogCards

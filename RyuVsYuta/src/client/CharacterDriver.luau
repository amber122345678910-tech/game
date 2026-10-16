--!strict
-- Двигает модель персонажа по состоянию кадра: скелет -> детали (BulkMoveTo), пряди, контур, видимость.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local Rig = require(Shared:WaitForChild("Rig"))
local Hair = require(Shared:WaitForChild("Anim"):WaitForChild("Hair"))
local Types = require(Shared:WaitForChild("Sequence"):WaitForChild("Types"))

local CharacterDriver = {}
CharacterDriver.__index = CharacterDriver

export type Driver = {
	model: Model,
	def: Rig.RigDef,
	binding: Rig.Binding,
	outline: Highlight?,
	stage: Instance,
	hidden: Instance,
	visible: boolean,
	carrierOf: { BasePart }, -- носитель (родительская деталь) каждой точки пряди
	update: (self: Driver, state: Types.CharState, t: number) -> (),
}

function CharacterDriver.new(model: Model, def: Rig.RigDef, hidden: Instance): Driver
	local root = model:FindFirstChild("Root") :: BasePart
	assert(root, "Model " .. model.Name .. " has no Root part")
	local binding = Rig.bind(def, model, root.CFrame)
	local carrierOf: { BasePart } = {}
	for i, a in binding.attachments do
		carrierOf[i] = a.Parent :: BasePart
	end
	local self = setmetatable({
		model = model,
		def = def,
		binding = binding,
		outline = model:FindFirstChildOfClass("Highlight"),
		stage = model.Parent :: Instance,
		hidden = hidden,
		visible = true,
		carrierOf = carrierOf,
	}, CharacterDriver)
	return (self :: any) :: Driver
end

local hairParams: Hair.Params = {
	wind = Vector3.zero,
	lift = Vector3.zero,
	turbulence = 0,
	freq = 1,
	scale = 0.2,
}

function CharacterDriver.update(self: Driver, state: Types.CharState, t: number)
	if state.visible ~= self.visible then
		self.visible = state.visible
		self.model.Parent = if state.visible then self.stage else self.hidden
	end
	if not state.visible then
		return
	end
	local world = Rig.solve(self.def, state.origin, state.pose, state.ik)
	local cfs = Rig.partCFrames(self.binding, world, t, state.flutter)
	Workspace:BulkMoveTo(self.binding.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	-- пряди: ветер задан в мире — переводим в оси носителя (кость)
	local hs = state.hair
	if #self.binding.attachments > 0 and hs then
		local atts = self.binding.attachments
		local rest = self.binding.attachRest
		local weights = self.binding.attachWeight
		local seeds = self.binding.attachSeed
		local lastCarrier: BasePart? = nil
		local lastCF = CFrame.identity
		for i = 1, #atts do
			local carrier = self.carrierOf[i]
			if carrier ~= lastCarrier then
				lastCarrier = carrier
				lastCF = carrier.CFrame
				hairParams.wind = lastCF:VectorToObjectSpace(hs.wind)
				hairParams.lift = lastCF:VectorToObjectSpace(hs.lift)
				hairParams.turbulence = hs.turbulence
				hairParams.freq = hs.freq
				hairParams.scale = hs.scale
			end
			local w = weights[i]
			if w > 0 then
				atts[i].CFrame = Hair.pointCFrame(rest[i], w, seeds[i], t, hairParams)
			end
		end
	end

	local h = self.outline
	if h then
		local fill = state.fill or 0
		h.OutlineTransparency = 1 - state.outline
		h.FillTransparency = 1 - fill
		if state.fillColor then
			h.FillColor = state.fillColor
		end
		h.Enabled = state.outline > 0.01 or fill > 0.01
	end
end

return CharacterDriver

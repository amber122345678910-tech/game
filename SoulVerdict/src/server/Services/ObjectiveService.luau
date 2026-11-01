--!strict
-- ObjectiveService (P45): SAVE stars (SPEC §1.4). One star per MapInfo.SavePoints entry (max
-- Config.Objectives.SavesPerMap). Humans that are up channel a star by standing within SaveRadius
-- (more humans = faster); a monster inside the radius pauses it ("Contested"). Progress persists.
-- Lit: every up human heals SaveHeal and gains SaveUlt ult; every monster loses 1 MaxDodges (floor
-- Config.Monster.MinDodges). All lit: DETERMINATION SURGE (humans "Surge" + SurgeUlt, monster Exhausted).
-- Channeling only runs while RoundState.Phase is "Round" or "Collapse".
--
-- Client contract (render rings/bars from these, star models live in workspace.Objectives):
--   star Model (tag "SaveStar"): attributes Index, Progress (0..1, 0.01 steps), Lit, Contested,
--   Channelers (humans inside), Radius. Its PrimaryPart is "Star".
--   RoundState: SavesLit, SavesTotal.  RoundEvents: "SaveLit" {index, by: {Model}, lit, total},
--   "Surge" {duration, endsAt}.
--
-- API (SPEC §17)
--   Setup(mapInfo), Clear(), LitCount() -> number, Total() -> number
--   SaveLit: Signal(index, channelers: {Model}), Surge: Signal()

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local RoundRules = require(Shared:WaitForChild("Round"):WaitForChild("RoundRules")) :: any

local ObjectiveService = {}
ObjectiveService.Priority = 45

ObjectiveService.SaveLit = Signal.new()
ObjectiveService.Surge = Signal.new()

local TICK = 0.1
local STAR_HEIGHT = 3.6 -- studs above the SAVE point (ground)
local VERTICAL_TOLERANCE = 9
local STAR_GOLD = Color3.fromRGB(255, 214, 92)
local STAR_LIT = Color3.fromRGB(255, 244, 196)

type Point = {
	Index: number,
	Position: Vector3,
	Container: Model,
	Star: Model,
	Zone: BasePart?,
	Light: PointLight?,
	Progress: number,
	Lit: boolean,
	Contested: boolean,
	Channelers: number,
}

local CharacterService: any = nil
local DamageService: any = nil
local StatusService: any = nil

local points: { Point } = {}
local folder: Folder? = nil
local litCount = 0
local surged = false
local saveStarModule: any = nil
local saveStarResolved = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function call(service: any, method: string, ...: any): (boolean, any)
	if service == nil then
		return false, nil
	end
	local fn = service[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[ObjectiveService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

local function roundState(): Instance?
	return ReplicatedStorage:FindFirstChild("RoundState")
end

local function setState(name: string, value: any)
	local rs = roundState()
	if rs then
		rs:SetAttribute(name, value)
	end
end

local function fireRoundEvent(name: string, data: any)
	pcall(Net.Server.FireAll, "RoundEvent", name, data)
end

local function addUlt(model: Model, amount: number)
	local current = model:GetAttribute("Ult")
	local value = if type(current) == "number" then current else 0
	model:SetAttribute("Ult", math.clamp(value + amount, 0, 100))
end

local function heal(model: Model, amount: number)
	local ok = call(DamageService, "Heal", model, amount, nil)
	if not ok then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		end
	end
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function charactersOf(team: string, upOnly: boolean): { Model }
	if CharacterService == nil then
		return {}
	end
	local ok, list = call(CharacterService, "GetAll", team)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out: { Model } = {}
	for _, model in list do
		local alive = if upOnly then CharacterService.IsUp(model) else CharacterService.IsAlive(model)
		if alive then
			table.insert(out, model)
		end
	end
	return out
end

-- Star visuals ------------------------------------------------------------------------------------------

local function getSaveStarModule(): any
	if not saveStarResolved then
		saveStarResolved = true
		local rigs = Shared:FindFirstChild("Rigs")
		local props = rigs and rigs:FindFirstChild("Props")
		local module = props and props:FindFirstChild("SaveStar")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type((result :: any).Build) == "function" then
				saveStarModule = result
			else
				warn("[ObjectiveService] Props/SaveStar failed to load: " .. tostring(result))
			end
		end
	end
	return saveStarModule
end

local function visualPart(parent: Instance, className: string, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Fallback SAVE star: two crossed 5-point stars (2 wedges per point) around a glowing core.
local function buildFallbackStar(): Model
	local model = Instance.new("Model")
	model.Name = "SaveStar"
	local core = visualPart(model, "Part", "Star", Vector3.new(1.1, 1.1, 1.1), CFrame.new(), STAR_LIT)
	;(core :: Part).Shape = Enum.PartType.Ball
	local tip = 1.7 -- centre-to-tip length
	local half = 0.42 * tip -- half width of each point at the centre
	local thickness = 0.45
	local planes: { Vector3 } = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
	local up = Vector3.new(0, 1, 0)
	for p, horizontal in planes do
		for k = 0, 4 do
			local theta = math.rad(90 + 72 * k)
			local u = horizontal * math.cos(theta) + up * math.sin(theta) -- towards the tip
			local v = horizontal * -math.sin(theta) + up * math.cos(theta) -- in-plane perpendicular
			for side = -1, 1, 2 do
				local y = v * side
				local z = -u
				local x = y:Cross(z)
				local center = y * (half / 2) + u * (tip / 2)
				visualPart(
					model,
					"WedgePart",
					("Point%d_%d_%d"):format(p, k, side),
					Vector3.new(thickness, half, tip),
					CFrame.fromMatrix(center, x, y, z),
					STAR_GOLD
				)
			end
		end
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = STAR_GOLD
	glow.Range = 14
	glow.Brightness = 1.4
	glow.Shadows = false
	glow.Parent = core
	model.PrimaryPart = core
	return model
end

local function buildStar(): Model
	local module = getSaveStarModule()
	if module then
		local ok, star = pcall(module.Build)
		if ok and typeof(star) == "Instance" and star:IsA("Model") then
			if star.PrimaryPart == nil then
				local named = star:FindFirstChild("Star")
				if named and named:IsA("BasePart") then
					star.PrimaryPart = named
				end
			end
			for _, d in star:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			return star
		end
		warn("[ObjectiveService] SaveStar.Build failed: " .. tostring(star))
	end
	return buildFallbackStar()
end

local function findLight(star: Model): PointLight?
	for _, d in star:GetDescendants() do
		if d:IsA("PointLight") then
			return d
		end
	end
	return nil
end

local function setPointAttributes(point: Point)
	local star = point.Star
	local rounded = math.floor(point.Progress * 100 + 0.5) / 100
	if star:GetAttribute("Progress") ~= rounded then
		star:SetAttribute("Progress", rounded)
	end
	if star:GetAttribute("Lit") ~= point.Lit then
		star:SetAttribute("Lit", point.Lit)
	end
	if star:GetAttribute("Contested") ~= point.Contested then
		star:SetAttribute("Contested", point.Contested)
	end
	if star:GetAttribute("Channelers") ~= point.Channelers then
		star:SetAttribute("Channelers", point.Channelers)
	end
end

-- Effects -------------------------------------------------------------------------------------------------

local function surge()
	if surged then
		return
	end
	surged = true
	local o = Config.Objectives
	for _, human in charactersOf("Humans", true) do
		call(StatusService, "Apply", human, "Surge", o.SurgeDuration, { mult = o.SurgeDamageMult })
		addUlt(human, o.SurgeUlt)
	end
	local exhaust: number = Config.Monster.ExhaustTime
	for _, monster in charactersOf("Monster", false) do
		monster:SetAttribute("Dodges", 0)
		monster:SetAttribute("Exhausted", now() + exhaust)
		call(StatusService, "Apply", monster, "Exhausted", exhaust)
	end
	ObjectiveService.Surge:Fire()
	fireRoundEvent("Surge", { duration = o.SurgeDuration, endsAt = now() + o.SurgeDuration })
end

local function light(point: Point, channelers: { Model })
	if point.Lit then
		return
	end
	local o = Config.Objectives
	point.Lit = true
	point.Progress = 1
	point.Contested = false
	point.Channelers = 0
	setPointAttributes(point)
	litCount += 1
	setState("SavesLit", litCount)
	if point.Light then
		point.Light.Color = STAR_LIT
		point.Light.Brightness = 3
		point.Light.Range = 20
	end
	if point.Zone then
		point.Zone.Color = STAR_LIT
		point.Zone.Transparency = 0.7
	end
	for _, human in charactersOf("Humans", true) do
		heal(human, o.SaveHeal)
		addUlt(human, o.SaveUlt)
	end
	for _, monster in charactersOf("Monster", false) do
		local maxDodges = monster:GetAttribute("MaxDodges")
		if type(maxDodges) == "number" then
			local newMax = math.max(Config.Monster.MinDodges, maxDodges - 1)
			if newMax < maxDodges then
				monster:SetAttribute("MaxDodges", newMax)
				local dodges = monster:GetAttribute("Dodges")
				if type(dodges) == "number" and dodges > newMax then
					monster:SetAttribute("Dodges", newMax)
				end
			end
		end
	end
	ObjectiveService.SaveLit:Fire(point.Index, channelers)
	fireRoundEvent("SaveLit", { index = point.Index, by = channelers, lit = litCount, total = #points })
	if litCount >= #points then
		surge()
	end
end

local function step(dt: number)
	if #points == 0 then
		return
	end
	local rs = roundState()
	local phase = if rs then rs:GetAttribute("Phase") else nil
	if phase ~= "Round" and phase ~= "Collapse" then
		return
	end
	local radius: number = Config.Objectives.SaveRadius
	local humans: { { model: Model, pos: Vector3 } } = {}
	for _, model in charactersOf("Humans", true) do
		local root = rootOf(model)
		if root then
			table.insert(humans, { model = model, pos = root.Position })
		end
	end
	local monsters: { Vector3 } = {}
	for _, model in charactersOf("Monster", false) do
		local root = rootOf(model)
		if root then
			table.insert(monsters, root.Position)
		end
	end
	local function inside(pos: Vector3, center: Vector3): boolean
		local dx, dz = pos.X - center.X, pos.Z - center.Z
		return dx * dx + dz * dz <= radius * radius and math.abs(pos.Y - center.Y) <= VERTICAL_TOLERANCE
	end
	for _, point in points do
		if not point.Lit then
			local channelers: { Model } = {}
			for _, h in humans do
				if inside(h.pos, point.Position) then
					table.insert(channelers, h.model)
				end
			end
			local monsterNear = false
			for _, pos in monsters do
				if inside(pos, point.Position) then
					monsterNear = true
					break
				end
			end
			point.Channelers = #channelers
			point.Contested = monsterNear and #channelers > 0
			local rate = RoundRules.SaveChannelRate(#channelers, monsterNear)
			if rate > 0 then
				point.Progress = math.min(1, point.Progress + rate * dt)
			end
			setPointAttributes(point)
			if point.Progress >= 1 then
				light(point, channelers)
			end
		end
	end
end

-- Public API --------------------------------------------------------------------------------------------

function ObjectiveService.Clear()
	for _, point in points do
		CollectionService:RemoveTag(point.Star, "SaveStar")
	end
	table.clear(points)
	litCount = 0
	surged = false
	if folder then
		folder:Destroy()
		folder = nil
	end
	setState("SavesLit", 0)
	setState("SavesTotal", 0)
end

function ObjectiveService.Setup(mapInfo: any)
	ObjectiveService.Clear()
	if type(mapInfo) ~= "table" or type(mapInfo.SavePoints) ~= "table" then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Objectives"
	folder = f
	local maxPoints: number = Config.Objectives.SavesPerMap
	local radius: number = Config.Objectives.SaveRadius
	for i, position in mapInfo.SavePoints do
		if i > maxPoints then
			break
		end
		if typeof(position) ~= "Vector3" then
			continue
		end
		local container = Instance.new("Model")
		container.Name = "SavePoint" .. i
		local star = buildStar()
		star.Name = "SaveStar"
		star:PivotTo(CFrame.new(position + Vector3.new(0, STAR_HEIGHT, 0)))
		star:SetAttribute("Index", i)
		star:SetAttribute("Progress", 0)
		star:SetAttribute("Lit", false)
		star:SetAttribute("Contested", false)
		star:SetAttribute("Channelers", 0)
		star:SetAttribute("Radius", radius)
		star.Parent = container
		-- faint channel zone on the ground (clients may draw a nicer ring from the attributes)
		local zone = visualPart(
			container,
			"Part",
			"Zone",
			Vector3.new(0.05, radius * 2, radius * 2),
			CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			STAR_GOLD
		)
		;(zone :: Part).Shape = Enum.PartType.Cylinder
		zone.Transparency = 0.88
		container.Parent = f
		CollectionService:AddTag(star, "SaveStar")
		table.insert(points, {
			Index = i,
			Position = position,
			Container = container,
			Star = star,
			Zone = zone,
			Light = findLight(star),
			Progress = 0,
			Lit = false,
			Contested = false,
			Channelers = 0,
		})
	end
	f.Parent = workspace
	setState("SavesLit", 0)
	setState("SavesTotal", #points)
end

function ObjectiveService.LitCount(): number
	return litCount
end

function ObjectiveService.Total(): number
	return #points
end

function ObjectiveService.Init()
	CharacterService = tryService("CharacterService")
	DamageService = tryService("DamageService")
	StatusService = tryService("StatusService")
end

function ObjectiveService.Start()
	task.spawn(function()
		while true do
			local dt = task.wait(TICK)
			local ok, err = pcall(step, math.min(dt, 0.5))
			if not ok then
				warn("[ObjectiveService] step: " .. tostring(err))
			end
		end
	end)
end

return ObjectiveService

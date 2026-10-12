--!strict
-- Яблоки: деревья в слотах, таймеры спавна, сбор по промпту, яблоки отряда (непроданные),
-- апгрейды фермы (дерево, разбрызгиватели, грабли), кража Собирателем.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local World = require(script.Parent:WaitForChild("World"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))

local AppleService = {}

type Tree = {
	Slot: BasePart,
	Index: number,
	Model: Model?,
	Spots: { Attachment },
	Apples: { BasePart },
	Timer: number,
}

local trees: { Tree } = {}
local slots: { BasePart } = {}
local applesFolder: Folder? = nil

AppleService.Apples = 0 -- непроданные яблоки отряда
AppleService.Sprinklers = 0
AppleService.Rake = false
AppleService.Changed = Signal.new() :: Signal.Signal<>
AppleService.Picked = Signal.new() :: Signal.Signal<Player>

local rng = Random.new()

local function interval(): number
	local base = if AppleService.Rake then Config.Economy.RakeInterval else Config.Economy.AppleInterval
	return base / (1 + AppleService.Sprinklers * Config.Economy.SprinklerBonus)
end

local function template(name: string): Instance?
	local t = World.houseFolder("Templates")
	return if t then t:FindFirstChild(name) else nil
end

local function folderFor(): Folder
	local f = applesFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "Apples"
	nf.Parent = World.House or workspace
	applesFolder = nf
	return nf
end

local function spotsOf(slot: BasePart): { Attachment }
	local list = {}
	local folder = slot:FindFirstChild("AppleSpots")
	if folder then
		for _, a in folder:GetDescendants() do
			if a:IsA("Attachment") then
				table.insert(list, a)
			end
		end
	end
	if #list == 0 then
		-- запасной вариант: вокруг слота
		for i = 1, 3 do
			local a = Instance.new("Attachment")
			a.Name = "Spot" .. i
			a.Position = Vector3.new(math.cos(i * 2.1) * 2.5, 4, math.sin(i * 2.1) * 2.5)
			a.Parent = slot
			table.insert(list, a)
		end
	end
	return list
end

function AppleService.treeCount(): number
	return #trees
end

local function spawnApple(tree: Tree)
	if #tree.Apples >= Config.Economy.MaxApplesPerTree then
		return
	end
	local used: { [Attachment]: boolean } = {}
	for _, a in tree.Apples do
		local spot = a:GetAttribute("SpotName")
		for _, s in tree.Spots do
			if s.Name == spot then
				used[s] = true
			end
		end
	end
	local free: { Attachment } = {}
	for _, s in tree.Spots do
		if not used[s] then
			table.insert(free, s)
		end
	end
	if #free == 0 then
		return
	end
	local spot = free[rng:NextInteger(1, #free)]
	local tpl = template("Apple")
	local apple: BasePart
	if tpl and tpl:IsA("BasePart") then
		apple = tpl:Clone()
	else
		apple = Instance.new("Part")
		apple.Shape = Enum.PartType.Ball
		apple.Size = Vector3.new(1.2, 1.2, 1.2)
		apple.Color = Color3.fromRGB(200, 40, 40)
		apple.Material = Enum.Material.SmoothPlastic
	end
	apple.Name = "Apple"
	apple.Anchored = true
	apple.CanCollide = false
	apple.CanTouch = false
	apple.CanQuery = true
	apple.CFrame = CFrame.new(spot.WorldPosition)
	apple:SetAttribute("SpotName", spot.Name)
	apple:SetAttribute("Apple", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickPrompt"
	prompt.ActionText = "Pick"
	prompt.ObjectText = "Apple"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Economy.ApplePickRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = apple
	apple.Parent = folderFor()
	table.insert(tree.Apples, apple)
end

local function treeOfApple(apple: BasePart): (Tree?, number?)
	for _, t in trees do
		local i = table.find(t.Apples, apple)
		if i then
			return t, i
		end
	end
	return nil, nil
end

local function pick(apple: BasePart, player: Player)
	local record = PlayerService.get(player)
	if not record or record.Status ~= "Alive" then
		return
	end
	local tree, i = treeOfApple(apple)
	if not tree or not i then
		return
	end
	local root = PlayerService.rootPart(player)
	if not root or (root.Position - apple.Position).Magnitude > Config.Economy.ApplePickRange + 4 then
		return
	end
	table.remove(tree.Apples, i)
	ServerSounds.playOn("Pickup", root, 0.5, 1, 40)
	NoiseService.emit(apple.Position, "Apple", player)
	apple:Destroy()
	AppleService.Apples += 1
	AppleService.Changed:Fire()
	AppleService.Picked:Fire(player)
end

-- Собиратель съедает ближайшее яблоко в радиусе
function AppleService.stealNear(position: Vector3, radius: number): boolean
	for _, t in trees do
		for i, a in t.Apples do
			if (a.Position - position).Magnitude <= radius then
				table.remove(t.Apples, i)
				a:Destroy()
				return true
			end
		end
	end
	return false
end

function AppleService.nearestApple(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, t in trees do
		for _, a in t.Apples do
			local d = (a.Position - position).Magnitude
			if d < bestDist then
				best = a
				bestDist = d
			end
		end
	end
	return best
end

function AppleService.takeAll(): number
	local n = AppleService.Apples
	AppleService.Apples = 0
	AppleService.Changed:Fire()
	return n
end

local function addTree(slot: BasePart, index: number, model: Model?): Tree
	local t: Tree = {
		Slot = slot,
		Index = index,
		Model = model,
		Spots = spotsOf(slot),
		Apples = {},
		Timer = interval(),
	}
	table.insert(trees, t)
	slot:SetAttribute("Planted", true)
	return t
end

-- Посадить дерево в следующий свободный слот
function AppleService.plantTree(): boolean
	if #trees >= Config.Economy.MaxTrees then
		return false
	end
	for i, slot in slots do
		local taken = false
		for _, t in trees do
			if t.Slot == slot then
				taken = true
				break
			end
		end
		if not taken then
			local tpl = template("Tree")
			local model: Model? = nil
			if tpl and tpl:IsA("Model") then
				local clone = tpl:Clone()
				clone.Name = "Tree"
				clone:PivotTo(slot.CFrame)
				clone.Parent = slot
				model = clone
			end
			local t = addTree(slot, i, model)
			spawnApple(t)
			AppleService.Changed:Fire()
			ServerSounds.playOn("Pickup", slot, 0.6, 0.8, 60)
			return true
		end
	end
	return false
end

function AppleService.setSprinklers(n: number)
	AppleService.Sprinklers = math.clamp(n, 0, Config.Economy.MaxSprinklers)
end

function AppleService.setRake(on: boolean)
	AppleService.Rake = on
end

-- Новый матч: только стартовые деревья, стартовые яблоки, таймеры заново
function AppleService.resetMatch()
	for _, t in trees do
		for _, a in t.Apples do
			a:Destroy()
		end
		if t.Index > Config.Economy.StartingTrees and t.Model then
			t.Model:Destroy()
		end
	end
	table.clear(trees)
	AppleService.Apples = 0
	AppleService.Sprinklers = 0
	AppleService.Rake = false
	for i, slot in slots do
		if i <= Config.Economy.StartingTrees then
			local model = slot:FindFirstChild("Tree")
			if not model then
				local tpl = template("Tree")
				if tpl and tpl:IsA("Model") then
					local clone = tpl:Clone()
					clone.Name = "Tree"
					clone:PivotTo(slot.CFrame)
					clone.Parent = slot
					model = clone
				end
			end
			addTree(slot, i, if model and model:IsA("Model") then model else nil)
		else
			slot:SetAttribute("Planted", false)
		end
	end
	-- стартовые яблоки
	local given = 0
	while given < Config.Economy.StartingApples and #trees > 0 do
		local t = trees[(given % #trees) + 1]
		spawnApple(t)
		given += 1
	end
	AppleService.Changed:Fire()
end

function AppleService.tick(dt: number, active: boolean)
	if not active then
		return
	end
	for _, t in trees do
		t.Timer -= dt
		if t.Timer <= 0 then
			t.Timer = interval()
			spawnApple(t)
		end
	end
end

function AppleService.init()
	local folder = World.houseFolder("Trees")
	if folder then
		local list: { BasePart } = {}
		for _, s in folder:GetChildren() do
			if s:IsA("BasePart") then
				table.insert(list, s)
			end
		end
		table.sort(list, function(a: BasePart, b: BasePart)
			return ((a:GetAttribute("Slot") :: number?) or 0) < ((b:GetAttribute("Slot") :: number?) or 0)
		end)
		slots = list
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local apple = prompt.Parent
		if prompt.Name == "PickPrompt" and apple and apple:IsA("BasePart") and apple:GetAttribute("Apple") then
			pick(apple, player)
		end
	end)
	AppleService.resetMatch()
	print(string.format("[Apples] slots %d, trees %d", #slots, #trees))
end

return AppleService

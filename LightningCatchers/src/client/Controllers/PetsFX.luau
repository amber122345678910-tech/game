--!strict
-- Питомцы-искрята всех игроков: модели строятся только на клиенте (Models.pet) по атрибуту Pets,
-- парят вокруг хозяина по свободной орбите, догоняют его пружинкой, смотрят по ходу движения
-- и подпрыгивают, когда хозяин ловит молнию. Все питомцы двигаются одним BulkMoveTo за кадр.
-- Главная деталь Body закреплена (Anchored), остальные приварены к ней — физика их не трогает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared:WaitForChild("Pets"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local ClientState = require(script.Parent.Parent.ClientState)

local PetsFX = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Визуальные константы
----------------------------------------------------------------------
local MAX_PETS = 6 -- на игрока (защита от мусора в атрибуте)
local FAR_DISTANCE = 80 -- дальше — обновляем реже
local FAR_STEP = 1 / 12
local HIDE_DISTANCE = 150 -- дальше — прячем
local SNAP_DISTANCE = 60 -- отстал так далеко (телепорт) — сразу к хозяину
local ORBIT_SPEED = 0.55
local ORBIT_RADIUS = 3.6
local SPRING = 5.5
local DAMPING = 0.75
local HOP_TIME = 0.4
local HOP_HEIGHT = 1.6
local TURN_SPEED = 8
local HIDDEN = CFrame.new(0, 1e4, 0)

type Pet = {
	model: Model,
	body: BasePart,
	loose: { BasePart }, -- детали, не приваренные к Body (двигаем сами)
	looseOffsets: { CFrame },
	pos: Vector3,
	vel: Vector3,
	yaw: number,
	index: number,
	phase: number,
	fresh: boolean,
}

type Owner = {
	player: Player,
	kinds: string,
	pets: { Pet },
	hopT: number,
	hopPower: number,
	hidden: boolean,
	accum: number,
	conns: { RBXScriptConnection },
}

local folder = Instance.new("Folder")
folder.Name = "PetsFX"
folder.Parent = Workspace

local owners: { [Player]: Owner } = {}

local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
local moveN = 0

local function queueMove(p: BasePart, cf: CFrame)
	moveN += 1
	moveParts[moveN] = p
	moveCFs[moveN] = cf
end

local function flushMoves()
	for i = #moveParts, moveN + 1, -1 do
		moveParts[i] = nil
		moveCFs[i] = nil
	end
	if moveN > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	moveN = 0
end

local function rootOf(char: Model?): BasePart?
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function parseKinds(v: any): { string }
	local out: { string } = {}
	if typeof(v) ~= "string" then
		return out
	end
	for kind in string.gmatch(v, "[^,%s]+") do
		if Pets.Kinds[kind] and #out < MAX_PETS then
			table.insert(out, kind)
		end
	end
	return out
end

-- Короткий угол от a к b
local function angleDelta(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

----------------------------------------------------------------------
-- Постройка
----------------------------------------------------------------------
local function buildPet(kind: string, index: number, startPos: Vector3): Pet?
	local ok, result = pcall(Models.pet, kind)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[PetsFX] не удалось построить питомца " .. kind .. ": " .. tostring(result))
		return nil
	end
	local model = result
	local bodyInst = model.PrimaryPart or model:FindFirstChild("Body")
	if not bodyInst or not bodyInst:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	local body = bodyInst
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
			d.Anchored = false
		elseif d:IsA("Light") then
			d.Enabled = false -- свет питомцев не нужен: лимит источников
		end
	end
	body.Anchored = true
	model:PivotTo(CFrame.new(startPos))
	model.Parent = folder
	-- что не приварено к Body, закрепляем и двигаем сами
	local loose: { BasePart } = {}
	local looseOffsets: { CFrame } = {}
	local bodyCF = body.CFrame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part: BasePart = d
			if part ~= body and part.AssemblyRootPart ~= body then
				part.Anchored = true
				table.insert(loose, part)
				local offset: CFrame = bodyCF:Inverse() * part.CFrame
				table.insert(looseOffsets, offset)
			end
		end
	end
	return {
		model = model,
		body = body,
		loose = loose,
		looseOffsets = looseOffsets,
		pos = startPos,
		vel = Vector3.zero,
		yaw = 0,
		index = index,
		phase = math.random() * math.pi * 2,
		fresh = true,
	}
end

local function destroyPets(o: Owner)
	for _, pet in o.pets do
		pet.model:Destroy()
	end
	table.clear(o.pets)
end

local function rebuild(o: Owner)
	local attr = o.player:GetAttribute(Net.PlayerAttrs.Pets)
	local kindsStr = if typeof(attr) == "string" then attr else ""
	if kindsStr == o.kinds and #o.pets > 0 then
		return
	end
	o.kinds = kindsStr
	destroyPets(o)
	local root = rootOf(o.player.Character)
	local start = if root then root.Position + Vector3.new(0, 2, 0) else HIDDEN.Position
	for i, kind in parseKinds(kindsStr) do
		local pet = buildPet(kind, i, start)
		if pet then
			table.insert(o.pets, pet)
		end
	end
	o.hidden = false
end

local function addPlayer(p: Player)
	if owners[p] then
		return
	end
	local o: Owner = {
		player = p,
		kinds = "",
		pets = {},
		hopT = -math.huge,
		hopPower = 1,
		hidden = false,
		accum = 0,
		conns = {},
	}
	owners[p] = o
	table.insert(o.conns, p:GetAttributeChangedSignal(Net.PlayerAttrs.Pets):Connect(function()
		rebuild(o)
	end))
	table.insert(o.conns, p.CharacterAdded:Connect(function()
		for _, pet in o.pets do
			pet.fresh = true -- после появления — сразу к хозяину
		end
	end))
	rebuild(o)
end

local function removePlayer(p: Player)
	local o = owners[p]
	if not o then
		return
	end
	owners[p] = nil
	for _, c in o.conns do
		c:Disconnect()
	end
	destroyPets(o)
end

local function hop(o: Owner?, power: number)
	if o then
		o.hopT = os.clock()
		o.hopPower = power
	end
end

----------------------------------------------------------------------
-- Движение
----------------------------------------------------------------------
local function hideOwner(o: Owner)
	if o.hidden then
		return
	end
	o.hidden = true
	for _, pet in o.pets do
		queueMove(pet.body, HIDDEN)
		for _, part in pet.loose do
			queueMove(part, HIDDEN)
		end
		pet.fresh = true
	end
end

local function updateOwner(o: Owner, dt: number, clock: number, camPos: Vector3)
	local root = rootOf(o.player.Character)
	local n = #o.pets
	if not root or n == 0 then
		hideOwner(o)
		return
	end
	local rootPos = root.Position
	local dist = (rootPos - camPos).Magnitude
	if dist > HIDE_DISTANCE then
		hideOwner(o)
		return
	end
	local stepDt = dt
	if o.player ~= player and dist > FAR_DISTANCE and not o.hidden then
		o.accum += dt
		if o.accum < FAR_STEP then
			return
		end
		stepDt = o.accum
	end
	o.accum = 0
	o.hidden = false

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local center = rootPos + Vector3.new(0, 1.3, 0) - flat * 1.2
	local ownerYaw = math.atan2(-flat.X, -flat.Z)
	local h = math.min(stepDt, 0.1)

	for i, pet in o.pets do
		local a = clock * ORBIT_SPEED + (i - 1) / n * math.pi * 2
		local radius = ORBIT_RADIUS + (i % 2) * 0.8
		local bob = math.sin(clock * 2.1 + pet.phase) * 0.45
		local target = center + Vector3.new(math.cos(a) * radius, bob, math.sin(a) * radius)

		if pet.fresh or (target - pet.pos).Magnitude > SNAP_DISTANCE then
			pet.fresh = false
			pet.pos = target
			pet.vel = Vector3.zero
			pet.yaw = ownerYaw
		elseif stepDt > 0.05 then
			-- редкие обновления (далеко): плавное сближение без пружины
			pet.pos = target + (pet.pos - target) * math.exp(-6 * stepDt)
			pet.vel = Vector3.zero
		else
			local acc = (target - pet.pos) * (SPRING * SPRING) - pet.vel * (2 * DAMPING * SPRING)
			pet.vel += acc * h
			pet.pos += pet.vel * h
		end

		-- смотрит по ходу движения, а стоя — на камеру (мордочкой к игроку)
		local v = Vector3.new(pet.vel.X, 0, pet.vel.Z)
		local speed = v.Magnitude
		local wantYaw: number
		if speed > 1.2 then
			wantYaw = math.atan2(-v.X, -v.Z)
		else
			local toCam = Vector3.new(camPos.X - pet.pos.X, 0, camPos.Z - pet.pos.Z)
			wantYaw = if toCam.Magnitude > 1e-3 then math.atan2(-toCam.X, -toCam.Z) else ownerYaw
		end
		pet.yaw += angleDelta(pet.yaw, wantYaw) * math.min(1, TURN_SPEED * h)

		-- подпрыгивание после поимки (по очереди)
		local hopK = (clock - o.hopT - (i - 1) * 0.06) / HOP_TIME
		local hopY = if hopK >= 0 and hopK <= 1 then math.sin(math.pi * hopK) * HOP_HEIGHT * o.hopPower else 0
		local lean = math.clamp(speed / 30, 0, 0.35)
		local roll = math.sin(clock * 1.7 + pet.phase) * 0.08
		local cf = CFrame.new(pet.pos + Vector3.new(0, hopY, 0)) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(-lean, 0, roll)
		queueMove(pet.body, cf)
		for j, part in pet.loose do
			queueMove(part, cf * pet.looseOffsets[j])
		end
	end
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function PetsFX.start()
	if started then
		return
	end
	started = true
	for _, p in Players:GetPlayers() do
		addPlayer(p)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	-- свой игрок поймал — питомцы подпрыгивают
	ClientState.StrikeResolved:Connect(function(msg: Net.StrikeResultMsg)
		local grade = (msg :: any).Grade
		if grade == "perfect" then
			hop(owners[player], 1)
		elseif grade == "good" then
			hop(owners[player], 0.6)
		end
	end)
	-- чужие поимки видны по их молниям
	task.spawn(function()
		Net.unreliable("BoltFX").OnClientEvent:Connect(function(msg: any)
			if typeof(msg) == "table" and msg.Caught == true and typeof(msg.UserId) == "number" then
				local p = Players:GetPlayerByUserId(msg.UserId)
				if p then
					hop(owners[p], 0.8)
				end
			end
		end)
	end)

	RunService.PreRender:Connect(function(dt: number)
		local clock = os.clock()
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for _, o in owners do
			updateOwner(o, dt, clock, camPos)
		end
		flushMoves()
	end)
end

return PetsFX

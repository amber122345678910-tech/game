--!strict
-- MapService (P20): builds, places and unloads maps (definitions in Shared/Maps/Registry).
-- The lobby is built at Registry.LobbyOrigin (world origin) and stays loaded; one round map at a time is
-- built at Registry.ArenaOrigin (far away) so both coexist. Map modules build around the origin; this
-- service moves the Model with PivotTo and translates EVERY CFrame/Vector3/KillY in the MapInfo to world
-- space. Any failure (missing module, Build error, invalid MapInfo) falls back to TestArena, then to an
-- emergency baseplate, so the round loop never stalls on a broken map.
-- Sets ReplicatedStorage.RoundState attributes GraphicsPreset / FinalPreset (map presets, see
-- Graphics/Presets.Resolve) and LobbyPreset.
--
-- API (SPEC §17)
--   LoadLobby() -> MapInfo          (idempotent)
--   Load(mapId) -> MapInfo          (unloads the previous round map first)
--   Current() -> MapInfo?           Lobby() -> MapInfo?            CurrentId() -> string?
--   Unload()                        RandomOptions(n) -> {string}  (distinct ids from Registry.Playable())
--   Loaded: Signal(mapInfo), Unloaded: Signal(mapId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any

local MapService = {}
MapService.Priority = 20

MapService.Loaded = Signal.new()
MapService.Unloaded = Signal.new()

local current: any = nil -- MapInfo of the round map (world space)
local lobby: any = nil -- MapInfo of the lobby (world space)
local random = Random.new()

local function roundState(): Instance?
	return ReplicatedStorage:FindFirstChild("RoundState")
end

local function setState(name: string, value: any)
	local rs = roundState()
	if rs then
		rs:SetAttribute(name, value)
	end
end

local function isCFrameList(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for _, item in v do
		if typeof(item) ~= "CFrame" then
			return false
		end
	end
	return true
end

-- Minimal structural validation of a freshly built MapInfo (local space).
local function validate(info: any): (boolean, string?)
	if type(info) ~= "table" then
		return false, "Build did not return a table"
	end
	if typeof(info.Model) ~= "Instance" or not info.Model:IsA("Model") then
		return false, "MapInfo.Model is not a Model"
	end
	if not isCFrameList(info.HumanSpawns) or #info.HumanSpawns == 0 then
		return false, "MapInfo.HumanSpawns must be a non-empty list of CFrames"
	end
	if typeof(info.MonsterSpawn) ~= "CFrame" then
		return false, "MapInfo.MonsterSpawn must be a CFrame"
	end
	if type(info.SavePoints) ~= "table" then
		return false, "MapInfo.SavePoints must be a list"
	end
	for _, p in info.SavePoints do
		if typeof(p) ~= "Vector3" then
			return false, "MapInfo.SavePoints must contain Vector3s"
		end
	end
	if typeof(info.Center) ~= "Vector3" then
		return false, "MapInfo.Center must be a Vector3"
	end
	if type(info.Radius) ~= "number" or info.Radius <= 0 then
		return false, "MapInfo.Radius must be a positive number"
	end
	if type(info.KillY) ~= "number" then
		return false, "MapInfo.KillY must be a number"
	end
	return true, nil
end

-- Returns a world-space copy of a local-space MapInfo (pure translation by `offset`).
local function translate(info: any, offset: Vector3): any
	local function cfList(list: any): { CFrame }
		local out: { CFrame } = {}
		if type(list) == "table" then
			for _, cf in list do
				if typeof(cf) == "CFrame" then
					table.insert(out, cf + offset)
				end
			end
		end
		return out
	end
	local out = table.clone(info)
	out.HumanSpawns = cfList(info.HumanSpawns)
	out.MonsterSpawn = info.MonsterSpawn + offset
	local saves: { Vector3 } = {}
	for _, p in info.SavePoints do
		table.insert(saves, p + offset)
	end
	out.SavePoints = saves
	out.Center = info.Center + offset
	out.KillY = info.KillY + offset.Y
	out.IntroPath = cfList(info.IntroPath)
	if info.DummySpawns ~= nil then
		out.DummySpawns = cfList(info.DummySpawns)
	end
	out.Origin = offset
	if type(out.Preset) ~= "string" or out.Preset == "" then
		out.Preset = "GoldenHall"
	end
	if type(out.FinalPreset) ~= "string" then
		out.FinalPreset = ""
	end
	if type(out.Music) ~= "string" then
		out.Music = ""
	end
	return out
end

-- Last resort: a plain lit baseplate so the game stays playable even with every map module broken.
local function emergencyMap(id: string): any
	local model = Instance.new("Model")
	model.Name = "EmergencyMap"
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(180, 4, 180)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(70, 66, 80)
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent = model
	local lamp = Instance.new("PointLight")
	lamp.Range = 60
	lamp.Brightness = 1.5
	lamp.Parent = floor
	model.WorldPivot = CFrame.new()
	local center = Vector3.new(0, 0, 0)
	local spawns: { CFrame } = {}
	for i = 0, 5 do
		local x = -15 + i * 6
		table.insert(spawns, CFrame.lookAt(Vector3.new(x, 0, 45), Vector3.new(x, 0, 0)))
	end
	return {
		Id = id,
		Model = model,
		HumanSpawns = spawns,
		MonsterSpawn = CFrame.lookAt(Vector3.new(0, 0, -45), center),
		SavePoints = { Vector3.new(-40, 0, 0), Vector3.new(40, 0, 0), Vector3.new(0, 0, -20) },
		Center = center,
		Radius = 80,
		KillY = -60,
		IntroPath = {
			CFrame.lookAt(Vector3.new(0, 60, 120), center),
			CFrame.lookAt(Vector3.new(90, 30, 0), center),
			CFrame.lookAt(Vector3.new(0, 10, -20), Vector3.new(0, 4, -45)),
			CFrame.lookAt(Vector3.new(0, 10, 70), center),
		},
		Preset = "GoldenHall",
		FinalPreset = "",
		Music = "",
		DummySpawns = {
			CFrame.lookAt(Vector3.new(20, 0, -10), center),
			CFrame.lookAt(Vector3.new(24, 0, 0), center),
			CFrame.lookAt(Vector3.new(20, 0, 10), center),
		},
	}
end

-- Builds a map in local space with fallbacks. Returns (info, usedId).
local function buildWithFallback(mapId: string): (any, string)
	local tried: { string } = {}
	for _, id in { mapId, "TestArena" } do
		if table.find(tried, id) == nil then
			table.insert(tried, id)
			local def = Registry.Get(id)
			if def then
				local ok, info = pcall(def.Build, random:NextInteger(1, 2 ^ 30))
				local valid, why = false, nil
				if ok then
					valid, why = validate(info)
				else
					why = tostring(info)
				end
				if valid then
					info.Id = id
					if type(info.Preset) ~= "string" or info.Preset == "" then
						info.Preset = def.Preset
					end
					if type(info.FinalPreset) ~= "string" or info.FinalPreset == "" then
						info.FinalPreset = def.FinalPreset
					end
					if type(info.Music) ~= "string" or info.Music == "" then
						info.Music = def.Music
					end
					return info, id
				end
				warn(("[MapService] map %s failed to build: %s"):format(id, tostring(why)))
				if ok and type(info) == "table" and typeof(info.Model) == "Instance" then
					info.Model:Destroy()
				end
			else
				warn(("[MapService] map %s is not available"):format(id))
			end
		end
	end
	warn("[MapService] every map failed; using the emergency baseplate")
	return emergencyMap(mapId), mapId
end

local function place(info: any, origin: Vector3, name: string): any
	local model: Model = info.Model
	model:PivotTo(CFrame.new(origin) * model:GetPivot())
	model.Name = name
	model:SetAttribute("MapId", info.Id)
	local world = translate(info, origin)
	model.Parent = workspace
	return world
end

function MapService.LoadLobby(): any
	if lobby and lobby.Model and lobby.Model.Parent ~= nil then
		return lobby
	end
	local id = Registry.LobbyId()
	local info, usedId = buildWithFallback(id)
	info.Id = usedId
	lobby = place(info, Registry.LobbyOrigin, "Lobby")
	setState("LobbyPreset", lobby.Preset)
	if current == nil then
		setState("GraphicsPreset", lobby.Preset)
		setState("FinalPreset", "")
	end
	return lobby
end

function MapService.Lobby(): any
	if lobby and lobby.Model and lobby.Model.Parent ~= nil then
		return lobby
	end
	return nil
end

function MapService.Current(): any
	return current
end

function MapService.CurrentId(): string?
	return if current then current.Id else nil
end

function MapService.Load(mapId: string): any
	if current then
		MapService.Unload()
	end
	local info, usedId = buildWithFallback(if type(mapId) == "string" then mapId else "TestArena")
	info.Id = usedId
	current = place(info, Registry.ArenaOrigin, "Arena")
	setState("GraphicsPreset", current.Preset)
	setState("FinalPreset", current.FinalPreset)
	setState("MapId", current.Id)
	MapService.Loaded:Fire(current)
	return current
end

function MapService.Unload()
	local info = current
	if info == nil then
		return
	end
	current = nil
	if info.Model then
		info.Model:Destroy()
	end
	local lobbyPreset = if lobby then lobby.Preset else "Lobby"
	setState("GraphicsPreset", lobbyPreset)
	setState("FinalPreset", "")
	MapService.Unloaded:Fire(info.Id)
end

function MapService.RandomOptions(n: number): { string }
	local pool = table.clone(Registry.Playable())
	for i = #pool, 2, -1 do
		local j = random:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out: { string } = {}
	for i = 1, math.min(math.max(1, math.floor(n)), #pool) do
		table.insert(out, pool[i])
	end
	return out
end

function MapService.Init() end

function MapService.Start()
	local ok, err = pcall(MapService.LoadLobby)
	if not ok then
		warn("[MapService] lobby failed to load: " .. tostring(err))
	end
end

return MapService

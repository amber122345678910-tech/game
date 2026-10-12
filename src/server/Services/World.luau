--!strict
-- Ссылки на объекты карты (Workspace.House / Workspace.Lobby) и геометрические помощники:
-- в какой комнате точка, ближайшие точки обхода, спавны. Все остальные сервисы ходят сюда, а не в workspace.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local World = {}

export type RoomVolume = {
	Name: string,
	Floor: number,
	Outdoor: boolean,
	Part: BasePart,
	Min: Vector3,
	Max: Vector3,
}

export type Waypoint = {
	Position: Vector3,
	Room: string,
	Floor: number,
}

export type Entry = {
	Id: string,
	Kind: string, -- Door | Window
	TargetId: string,
	Room: string,
	Position: Vector3,
}

World.House = nil :: Folder?
World.Lobby = nil :: Folder?
World.Rooms = {} :: { RoomVolume }
World.Waypoints = {} :: { Waypoint }
World.Entries = {} :: { Entry }
World.InmateSpawns = {} :: { Vector3 }
World.VesperSpots = {} :: { { Position: Vector3, Room: string } }
World.PlayerSpawns = {} :: { CFrame }
World.LobbySpawns = {} :: { CFrame }

World.COLLISION_PLAYERS = "Players"
World.COLLISION_INMATES = "Inmates"
World.COLLISION_PROPS = "Props"

local function folder(parent: Instance?, name: string): Folder?
	if not parent then
		return nil
	end
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function registerGroups()
	for _, name in { World.COLLISION_PLAYERS, World.COLLISION_INMATES, World.COLLISION_PROPS } do
		local ok = pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
		if not ok then
			-- группа уже есть
		end
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(World.COLLISION_PLAYERS, World.COLLISION_INMATES, false)
		PhysicsService:CollisionGroupSetCollidable(World.COLLISION_PLAYERS, World.COLLISION_PLAYERS, false)
		PhysicsService:CollisionGroupSetCollidable(World.COLLISION_INMATES, World.COLLISION_INMATES, false)
		PhysicsService:CollisionGroupSetCollidable(World.COLLISION_PROPS, World.COLLISION_PLAYERS, true)
		PhysicsService:CollisionGroupSetCollidable(World.COLLISION_PROPS, World.COLLISION_INMATES, true)
	end)
end

function World.init()
	registerGroups()
	local house = workspace:FindFirstChild("House")
	World.House = if house and house:IsA("Folder") then house else nil
	local lobby = workspace:FindFirstChild("Lobby")
	World.Lobby = if lobby and lobby:IsA("Folder") then lobby else nil
	if not World.House then
		warn("[World] Workspace.House missing — map not built")
	end

	-- Комнаты
	local rooms = folder(World.House, "Rooms")
	if rooms then
		for _, p in rooms:GetChildren() do
			if p:IsA("BasePart") then
				local half = p.Size / 2
				table.insert(World.Rooms, {
					Name = (p:GetAttribute("RoomName") :: string?) or p.Name,
					Floor = (p:GetAttribute("Floor") :: number?) or 1,
					Outdoor = p:GetAttribute("Outdoor") == true,
					Part = p,
					Min = p.Position - half,
					Max = p.Position + half,
				})
			end
		end
	end

	local nav = folder(World.House, "Nav")
	local wps = folder(nav, "Waypoints")
	if wps then
		for _, p in wps:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.Waypoints, {
					Position = p.Position,
					Room = (p:GetAttribute("Room") :: string?) or World.roomNameAt(p.Position),
					Floor = (p:GetAttribute("Floor") :: number?) or 1,
				})
			end
		end
	end
	local entries = folder(nav, "Entries")
	if entries then
		for _, p in entries:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.Entries, {
					Id = (p:GetAttribute("EntryId") :: string?) or p.Name,
					Kind = (p:GetAttribute("Kind") :: string?) or "Door",
					TargetId = (p:GetAttribute("TargetId") :: string?) or "",
					Room = (p:GetAttribute("Room") :: string?) or "",
					Position = p.Position,
				})
			end
		end
	end
	local spawns = folder(nav, "InmateSpawns")
	if spawns then
		for _, p in spawns:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.InmateSpawns, p.Position)
			end
		end
	end
	local vesper = folder(nav, "VesperSpots")
	if vesper then
		for _, p in vesper:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.VesperSpots, { Position = p.Position, Room = (p:GetAttribute("Room") :: string?) or World.roomNameAt(p.Position) })
			end
		end
	end
	local pspawns = folder(World.House, "Spawns")
	if pspawns then
		for _, p in pspawns:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.PlayerSpawns, p.CFrame + Vector3.new(0, 3.5, 0))
			end
		end
	end
	local lspawns = folder(World.Lobby, "Spawns")
	if lspawns then
		for _, p in lspawns:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(World.LobbySpawns, p.CFrame + Vector3.new(0, 3.5, 0))
			end
		end
	end
	if #World.PlayerSpawns == 0 then
		table.insert(World.PlayerSpawns, CFrame.new(Config.Map.HouseOrigin + Vector3.new(-12, 4, -6)))
	end
	if #World.LobbySpawns == 0 then
		table.insert(World.LobbySpawns, CFrame.new(Config.Map.LobbyOrigin + Vector3.new(0, 4, 0)))
	end
	print(string.format("[World] rooms %d, waypoints %d, entries %d, inmate spawns %d", #World.Rooms, #World.Waypoints, #World.Entries, #World.InmateSpawns))
end

-- Папка карты по имени (House.Doors и т.п.)
function World.houseFolder(name: string): Folder?
	return folder(World.House, name)
end

function World.lobbyFolder(name: string): Folder?
	return folder(World.Lobby, name)
end

function World.houseChild(name: string): Instance?
	return if World.House then World.House:FindFirstChild(name) else nil
end

function World.roomAt(position: Vector3): RoomVolume?
	local best: RoomVolume? = nil
	local bestVol = math.huge
	for _, r in World.Rooms do
		if position.X >= r.Min.X and position.X <= r.Max.X and position.Y >= r.Min.Y and position.Y <= r.Max.Y and position.Z >= r.Min.Z and position.Z <= r.Max.Z then
			local vol = r.Part.Size.X * r.Part.Size.Y * r.Part.Size.Z
			if vol < bestVol then
				best = r
				bestVol = vol
			end
		end
	end
	return best
end

function World.roomNameAt(position: Vector3): string
	local r = World.roomAt(position)
	return if r then r.Name else "Outside"
end

function World.isOutdoor(position: Vector3): boolean
	local r = World.roomAt(position)
	return r == nil or r.Outdoor
end

function World.roomByName(name: string): RoomVolume?
	for _, r in World.Rooms do
		if r.Name == name then
			return r
		end
	end
	return nil
end

function World.roomCenter(name: string): Vector3?
	local r = World.roomByName(name)
	return if r then r.Part.Position else nil
end

-- Случайная точка обхода, желательно не в указанной комнате
function World.randomWaypoint(rng: Random, avoidRoom: string?): Waypoint?
	if #World.Waypoints == 0 then
		return nil
	end
	for _ = 1, 8 do
		local wp = World.Waypoints[rng:NextInteger(1, #World.Waypoints)]
		if not avoidRoom or wp.Room ~= avoidRoom then
			return wp
		end
	end
	return World.Waypoints[rng:NextInteger(1, #World.Waypoints)]
end

function World.waypointsInRoom(room: string): { Waypoint }
	local list = {}
	for _, wp in World.Waypoints do
		if wp.Room == room then
			table.insert(list, wp)
		end
	end
	return list
end

function World.nearestWaypoint(position: Vector3, maxDistance: number?): Waypoint?
	local best: Waypoint? = nil
	local bestDist = maxDistance or math.huge
	for _, wp in World.Waypoints do
		local d = (wp.Position - position).Magnitude
		if d < bestDist then
			best = wp
			bestDist = d
		end
	end
	return best
end

function World.entryById(id: string): Entry?
	for _, e in World.Entries do
		if e.Id == id then
			return e
		end
	end
	return nil
end

function World.randomEntry(rng: Random): Entry?
	if #World.Entries == 0 then
		return nil
	end
	return World.Entries[rng:NextInteger(1, #World.Entries)]
end

function World.randomInmateSpawn(rng: Random): Vector3
	if #World.InmateSpawns == 0 then
		return Config.Map.HouseOrigin + Vector3.new(0, 3, -52)
	end
	return World.InmateSpawns[rng:NextInteger(1, #World.InmateSpawns)]
end

function World.playerSpawn(index: number): CFrame
	return World.PlayerSpawns[((index - 1) % #World.PlayerSpawns) + 1]
end

function World.lobbySpawn(index: number): CFrame
	return World.LobbySpawns[((index - 1) % #World.LobbySpawns) + 1]
end

-- Поставить всем частям модели группу коллизий
function World.setCollisionGroup(root: Instance, group: string)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	if root:IsA("BasePart") then
		root.CollisionGroup = group
	end
end

return World

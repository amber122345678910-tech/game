--!strict
-- Remote definitions + thin wrappers. NOT Lune-safe at call time (services are fetched lazily).
-- Server: call Net.Server.Init() once before anything else uses remotes.
-- See docs/SPEC.md §4 for payload shapes.

local Net = {}

Net.Events = {
	"Cast",
	"Block",
	"Dash",
	"Request",
	"BoxReport",
	"AbilityFx",
	"Hazard",
	"HazardEnd",
	"DamageFx",
	"ForceMove",
	"Cooldown",
	"RoundEvent",
	"Notify",
	"Profile",
	"BoxStart",
	"BoxEnd",
}

Net.Functions = {
	"GetProfile",
}

Net.Unreliable = {
	"Aim",
	"BoxSoul",
}

local FOLDER_NAME = "Remotes"

local function replicatedStorage(): ReplicatedStorage
	return game:GetService("ReplicatedStorage")
end

local remotes: { [string]: Instance } = {}

local function isKnown(name: string): boolean
	return table.find(Net.Events, name) ~= nil
		or table.find(Net.Functions, name) ~= nil
		or table.find(Net.Unreliable, name) ~= nil
end

-- SERVER ------------------------------------------------------------------------------------------
Net.Server = {}

function Net.Server.Init()
	local rs = replicatedStorage()
	local folder = rs:FindFirstChild(FOLDER_NAME)
	if not folder then
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = rs
		folder = f
	end
	assert(folder)
	local function make(className: string, name: string)
		local existing = folder:FindFirstChild(name)
		if existing then
			remotes[name] = existing
			return
		end
		local r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		remotes[name] = r
	end
	for _, name in Net.Events do
		make("RemoteEvent", name)
	end
	for _, name in Net.Functions do
		make("RemoteFunction", name)
	end
	for _, name in Net.Unreliable do
		make("UnreliableRemoteEvent", name)
	end
end

local function serverRemote(name: string): Instance
	local r = remotes[name]
	assert(r, "Net: unknown remote or Net.Server.Init() not called: " .. name)
	return r
end

function Net.Server.On(name: string, handler: (Player, ...any) -> ()): RBXScriptConnection
	local r = serverRemote(name)
	if r:IsA("RemoteEvent") then
		return r.OnServerEvent:Connect(handler)
	elseif r:IsA("UnreliableRemoteEvent") then
		return r.OnServerEvent:Connect(handler)
	end
	error("Net.Server.On: not an event: " .. name)
end

function Net.Server.OnInvoke(name: string, handler: (Player, ...any) -> ...any)
	local r = serverRemote(name)
	assert(r:IsA("RemoteFunction"), "Net.Server.OnInvoke: not a function: " .. name)
	r.OnServerInvoke = handler
end

function Net.Server.Fire(name: string, player: Player, ...: any)
	local r = serverRemote(name)
	if r:IsA("RemoteEvent") then
		r:FireClient(player, ...)
	elseif r:IsA("UnreliableRemoteEvent") then
		r:FireClient(player, ...)
	end
end

function Net.Server.FireAll(name: string, ...: any)
	local r = serverRemote(name)
	if r:IsA("RemoteEvent") then
		r:FireAllClients(...)
	elseif r:IsA("UnreliableRemoteEvent") then
		r:FireAllClients(...)
	end
end

function Net.Server.FireList(name: string, players: { Player }, ...: any)
	for _, p in players do
		Net.Server.Fire(name, p, ...)
	end
end

function Net.Server.FireExcept(name: string, except: Player?, ...: any)
	local Players = game:GetService("Players")
	for _, p in Players:GetPlayers() do
		if p ~= except then
			Net.Server.Fire(name, p, ...)
		end
	end
end

-- CLIENT ------------------------------------------------------------------------------------------
Net.Client = {}

local function clientRemote(name: string): Instance
	local cached = remotes[name]
	if cached then
		return cached
	end
	assert(isKnown(name), "Net: unknown remote " .. name)
	local folder = replicatedStorage():WaitForChild(FOLDER_NAME)
	local r = folder:WaitForChild(name)
	remotes[name] = r
	return r
end

function Net.Client.On(name: string, handler: (...any) -> ()): RBXScriptConnection
	local r = clientRemote(name)
	if r:IsA("RemoteEvent") then
		return r.OnClientEvent:Connect(handler)
	elseif r:IsA("UnreliableRemoteEvent") then
		return r.OnClientEvent:Connect(handler)
	end
	error("Net.Client.On: not an event: " .. name)
end

function Net.Client.Fire(name: string, ...: any)
	local r = clientRemote(name)
	if r:IsA("RemoteEvent") then
		r:FireServer(...)
	elseif r:IsA("UnreliableRemoteEvent") then
		r:FireServer(...)
	end
end

function Net.Client.Invoke(name: string, ...: any): ...any
	local r = clientRemote(name)
	assert(r:IsA("RemoteFunction"), "Net.Client.Invoke: not a function: " .. name)
	return r:InvokeServer(...)
end

-- Payload validation helpers (server handlers must type-check everything from clients)
Net.Check = {}

function Net.Check.Vector3(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

function Net.Check.Number(v: any, min: number?, max: number?): boolean
	if type(v) ~= "number" or v ~= v then
		return false
	end
	if min and v < min then
		return false
	end
	if max and v > max then
		return false
	end
	return true
end

function Net.Check.String(v: any, maxLen: number?): boolean
	return type(v) == "string" and #v <= (maxLen or 64)
end

return Net

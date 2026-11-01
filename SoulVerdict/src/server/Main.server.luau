--!strict
-- Server bootstrap. Auto-discovers every ModuleScript in ./Services, then:
--   1) Net.Server.Init() (creates remotes)
--   2) require all services (sorted by optional `Priority` field, lower first, then by name)
--   3) call Init() on all (no yields; services resolve each other here via require)
--   4) call Start() on all (connect events, start loops; each in its own thread)
-- RULE: services must require OTHER SERVICES only inside Init()/functions, never at module top level
-- (avoids cyclic-require errors). Shared modules (Config, Kits, Net, Util...) may be required at top level.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Config = require(Shared:WaitForChild("Config")) :: any

Net.Server.Init()

local servicesFolder = script.Parent:WaitForChild("Services")

type ServiceEntry = { name: string, module: any, priority: number }
local entries: { ServiceEntry } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = xpcall(require, debug.traceback, child)
		if ok and type(result) == "table" then
			local priority = (result :: any).Priority
			table.insert(entries, {
				name = child.Name,
				module = result,
				priority = if type(priority) == "number" then priority else 100,
			})
		else
			warn(("[SoulVerdict] Failed to load service %s:\n%s"):format(child.Name, tostring(result)))
		end
	end
end

table.sort(entries, function(a, b)
	if a.priority ~= b.priority then
		return a.priority < b.priority
	end
	return a.name < b.name
end)

for _, entry in entries do
	if type(entry.module.Init) == "function" then
		local ok, err = xpcall(entry.module.Init, debug.traceback)
		if not ok then
			warn(("[SoulVerdict] %s.Init failed:\n%s"):format(entry.name, tostring(err)))
		end
	end
end

for _, entry in entries do
	if type(entry.module.Start) == "function" then
		task.spawn(function()
			local ok, err = xpcall(entry.module.Start, debug.traceback)
			if not ok then
				warn(("[SoulVerdict] %s.Start failed:\n%s"):format(entry.name, tostring(err)))
			end
		end)
	end
end

print(("[SoulVerdict] %s v%s server started with %d services"):format(Config.GameName, Config.Version, #entries))

--!strict
-- Client bootstrap. Auto-discovers every ModuleScript in ./Controllers, then requires them
-- (sorted by optional `Priority`, lower first, then name), calls Init() on all, then Start() on all.
-- RULE: controllers must require OTHER CONTROLLERS only inside Init()/functions, never at module top level.
-- The UI is mounted by Controllers/UIController (it pushes the title screen / HUD).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any

-- Hide default Roblox HUD pieces we replace, and disable the Esc-menu "Reset Character": it kills the custom
-- character outright (the monster forfeits the round, a downed human skips the bleed-out, a frozen intro body
-- dies). Lobby bodies never need it (the void watchdog puts fallen players back). SetCore / SetCoreGuiEnabled
-- fail until the CoreScripts registered them: retry each call on its own.
task.spawn(function()
	local pending = {
		function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end,
		function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end,
	}
	for _ = 1, 40 do
		for i = #pending, 1, -1 do
			if pcall(pending[i]) then
				table.remove(pending, i)
			end
		end
		if #pending == 0 then
			break
		end
		task.wait(0.25)
	end
end)

local controllersFolder = script.Parent:WaitForChild("Controllers")

type Entry = { name: string, module: any, priority: number }
local entries: { Entry } = {}

for _, child in controllersFolder:GetChildren() do
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
			warn(("[SoulVerdict] Failed to load controller %s:\n%s"):format(child.Name, tostring(result)))
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

print(("[SoulVerdict] %s v%s client started with %d controllers"):format(Config.GameName, Config.Version, #entries))

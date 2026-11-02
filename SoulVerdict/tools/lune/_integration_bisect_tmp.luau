--!nocheck
-- temporary (integration audit): which suite leaks state into ui_screens? deleted after use
local process = require("@lune/process")
local Loader = require("./loader")
local T = require("./test")
local list = string.split(process.args[1], ",")
for _, f in list do
	local suite = require("./tests/" .. f .. ".spec")
	local names = {}
	for name in suite do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		T.current = f .. "::" .. name
		local ok, err = pcall(suite[name], T, Loader)
		if not ok then table.insert(T.failures, T.current .. " ERROR " .. tostring(err)) end
	end
	local Players = Loader.roblox and nil
	local okP, lp = pcall(function() return require("@lune/roblox") end)
end
local ui = 0
for _, f in T.failures do if string.find(f, "^ui_screens") then ui += 1 end end
print(process.args[1] .. " -> ui_screens failures: " .. ui)

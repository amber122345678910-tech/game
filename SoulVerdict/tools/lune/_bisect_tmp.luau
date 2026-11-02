--!nocheck
local fs = require("@lune/fs")
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
end
print(#T.failures .. " failures")
for i = 1, math.min(3, #T.failures) do print(T.failures[i]) end

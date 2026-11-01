--!nocheck
-- Runs every tools/lune/tests/*.spec.luau. Each spec returns { [testName] = function(T, Loader) end }.
-- Usage (from project root): lune run tools/lune/run_tests.luau [filter]
local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("./loader")
local T = require("./test")

local filter = process.args[1]
local files = {}
for _, f in fs.readDir("tools/lune/tests") do
	if string.find(f, "%.spec%.luau$") and (not filter or string.find(f, filter, 1, true)) then
		table.insert(files, f)
	end
end
table.sort(files)

local total, failedSuites = 0, 0
for _, f in files do
	local okLoad, suite = pcall(require, "./tests/" .. string.gsub(f, "%.luau$", ""))
	if not okLoad then
		print("SUITE LOAD ERROR " .. f .. ": " .. tostring(suite))
		failedSuites += 1
		table.insert(T.failures, f .. ": load error")
	else
		local names = {}
		for name in suite do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			T.current = f .. " :: " .. name
			Loader.reset()
			local ok, err = pcall(suite[name], T, Loader)
			total += 1
			if not ok then
				table.insert(T.failures, T.current .. ": ERROR " .. tostring(err))
			end
		end
	end
end

print(("Ran %d tests (%d assertions) from %d suites"):format(total, T.count, #files))
if #T.failures > 0 then
	print(("FAILED: %d"):format(#T.failures))
	for _, msg in T.failures do
		print("  - " .. msg)
	end
	process.exit(1)
end
print("ALL TESTS PASSED")

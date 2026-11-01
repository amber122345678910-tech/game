--!nocheck
-- Requires EVERY module in the Lune-safe roots (tools/checks/lune_safe.json: src/shared/** except the
-- runtime_only list, i.e. Net.luau) through the Lune harness and fails for each one that errors or returns
-- nil. Empty / not-yet-created folders are simply skipped. Prints a one-line summary.
-- Each module is loaded with a fresh Loader cache so one broken dependency is reported once per module
-- that needs it (with the real error) instead of as a cascade of "cyclic require" errors.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CONFIG = "tools/checks/lune_safe.json"

local function collect(dir, out)
	if not fs.isDir(dir) then
		return
	end
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, name in entries do
		local path = dir .. "/" .. name
		if string.sub(name, 1, 1) ~= "." then
			if fs.isDir(path) then
				collect(path, out)
			elseif
				(string.find(name, "%.luau$") or string.find(name, "%.lua$"))
				and not string.find(name, "%.server%.lua")
				and not string.find(name, "%.client%.lua")
			then
				table.insert(out, path)
			end
		end
	end
end

return {
	require_all_lune_safe_modules = function(T, Loader)
		local config = serde.decode("json", fs.readFile(CONFIG))
		local skip = {}
		for path in config.runtime_only or {} do
			skip[path] = true
		end
		local files = {}
		for _, root in config.lune_safe_roots or {} do
			collect(root, files)
		end
		Loader.rescan()
		local loaded, failed, skipped = 0, 0, 0
		local quiet = Loader.quietWarnings
		Loader.quietWarnings = true
		for _, file in files do
			if skip[file] then
				skipped += 1
			else
				local modulePath = string.gsub(string.gsub(file, "%.luau?$", ""), "/init$", "")
				Loader.reset()
				local ok, result = pcall(Loader.requirePath, modulePath)
				if not ok then
					failed += 1
					T.ok(false, ("%s failed to load under Lune: %s"):format(file, tostring(result)))
				elseif result == nil then
					failed += 1
					T.ok(false, file .. " returned nil (a ModuleScript must return exactly one value)")
				else
					loaded += 1
					T.ok(true)
				end
			end
		end
		Loader.quietWarnings = quiet
		Loader.reset()
		print(
			("  requireall: %d Lune-safe modules loaded, %d failed, %d runtime-only skipped"):format(
				loaded,
				failed,
				skipped
			)
		)
	end,
}

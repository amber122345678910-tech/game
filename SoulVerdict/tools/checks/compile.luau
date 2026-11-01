--!nocheck
-- compile.luau — compiles EVERY .luau/.lua file under src/ (and tools/) with Lune's Luau compiler and
-- reports syntax errors as `path:line: error: message [compile]`. Exit code 1 if any file fails.
-- Catches: syntax errors, unbalanced blocks, bad escapes, invalid assignments, misuse of reserved words.
-- It does NOT type-check (no luau-analyze here); see tools/check.sh for the other checks.
-- Usage (from the project root): lune run tools/checks/compile.luau [dir ...]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local roots = {}
for _, a in process.args do
	table.insert(roots, a)
end
if #roots == 0 then
	roots = { "src", "tools" }
end

local files = {}
local function walk(dir)
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, name in entries do
		local path = dir .. "/" .. name
		if string.sub(name, 1, 1) ~= "." and name ~= "node_modules" then
			if fs.isDir(path) then
				walk(path)
			elseif string.find(name, "%.luau$") or string.find(name, "%.lua$") then
				table.insert(files, path)
			end
		end
	end
end
for _, root in roots do
	if fs.isDir(root) then
		walk(root)
	elseif fs.isFile(root) then
		table.insert(files, root)
	end
end

local failures = 0
for _, path in files do
	local source = fs.readFile(path)
	local ok, err = pcall(luau.compile, source, { optimizationLevel = 1, debugLevel = 1 })
	if not ok then
		failures += 1
		local text = tostring(err)
		-- "syntax error: <line>: <message>" (Lune wraps it in a LuaError with a stack trace)
		local line, msg = string.match(text, "(%d+):%s*([^\n]+)")
		if not line then
			line, msg = "1", (string.match(text, "[^\n]+") or text)
		end
		msg = string.gsub(msg, "%s*%[Stack Begin%].*$", "")
		print(("%s:%s: error: %s [compile]"):format(path, line, msg))
	end
end

print(("compile: %d files, %d errors, 0 warnings"):format(#files, failures))
process.exit(if failures > 0 then 1 else 0)

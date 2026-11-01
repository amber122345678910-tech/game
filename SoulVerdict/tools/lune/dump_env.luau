--!nocheck
-- Exports graphics presets as environment JSON for the offline 3D preview renderer (three.js).
-- Format + value semantics: see src/shared/Graphics/EnvExport.luau (header).
--
-- Usage (from the project root):
--   lune run tools/lune/dump_env.luau <presetId> [--out env.json]   one preset (stdout without --out)
--   lune run tools/lune/dump_env.luau --all <dir>                     every preset -> <dir>/<Id>.json
--   lune run tools/lune/dump_env.luau --list                          preset ids, kinds and names
-- Exit code 1 on an unknown preset, bad arguments or out-of-range values.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

if not fs.isDir("src/shared/Graphics") then
	print("dump_env: run me from the project root (the folder that contains src/ and tools/)")
	process.exit(1)
end

local Loader = require("./loader")
local Presets = Loader.require("ReplicatedStorage.Shared.Graphics.Presets")
local EnvExport = Loader.require("ReplicatedStorage.Shared.Graphics.EnvExport")

local function usage(message)
	if message then
		print("dump_env: " .. message)
	end
	print("usage: lune run tools/lune/dump_env.luau <presetId> [--out env.json]")
	print("       lune run tools/lune/dump_env.luau --all <dir>")
	print("       lune run tools/lune/dump_env.luau --list")
	process.exit(1)
end

local function export(preset)
	local env = EnvExport.FromPreset(preset)
	local problems = EnvExport.Validate(env)
	if #problems > 0 then
		print(("dump_env: %s produced out-of-range values:\n  %s"):format(preset.Id, table.concat(problems, "\n  ")))
		process.exit(1)
	end
	return EnvExport.ToJson(env, true)
end

local args = process.args
local first = args[1]
if first == nil then
	usage("missing preset id")
end

if first == "--list" then
	for _, preset in Presets.All() do
		print(("%-20s %-8s %s"):format(preset.Id, Presets.Kind(preset.Id), preset.Name.en))
	end
	return
end

if first == "--all" then
	local dir = args[2]
	if dir == nil or dir == "" then
		usage("--all needs an output directory")
	end
	dir = string.gsub(dir, "/+$", "")
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local count = 0
	for _, preset in Presets.All() do
		fs.writeFile(dir .. "/" .. preset.Id .. ".json", export(preset))
		count += 1
	end
	print(("dump_env: wrote %d presets to %s/"):format(count, dir))
	return
end

local preset = Presets.Get(first)
if preset == nil then
	usage(("unknown preset '%s' (try --list)"):format(tostring(first)))
end

local outPath = nil
local i = 2
while i <= #args do
	local arg = args[i]
	if arg == "--out" then
		outPath = args[i + 1]
		if outPath == nil then
			usage("--out needs a file path")
		end
		i += 2
	else
		usage("unexpected argument " .. tostring(arg))
	end
end

local json = export(preset)
if outPath then
	fs.writeFile(outPath, json)
	print(("dump_env: wrote %s"):format(outPath))
else
	stdio.write(json)
end

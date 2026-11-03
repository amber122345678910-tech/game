--!nocheck
-- Builds every style with the real Realizer inside a Lune DataModel. Lune
-- validates each property name/value against the Roblox reflection database,
-- so a misspelled property or a wrong enum fails here instead of in Studio.
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local game = roblox.Instance.new("DataModel")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = Workspace
Loader.globals.game = game
Loader.globals.Instance = roblox.Instance

-- engine-only methods that Lune does not implement
local Scene = Loader.load("src/Cutscene/Scene")
local Realizer = Loader.load("src/Cutscene/Realizer")

local ok = true
for _, run in { { id = "cinema", part = 1 }, { id = "cinema", part = 2 }, { id = "cinema", part = 3 } } do
	local id, part = run.id, run.part
	local success, err = pcall(function()
		local live = Realizer.build(id, Workspace, part)
		-- the overlay layers become Frames in a ScreenGui container
		local sg = roblox.Instance.new("ScreenGui")
		local safe = roblox.Instance.new("Frame")
		safe.Parent = sg
		Realizer.buildOverlay(live, safe)
		local count, guis, frames = 0, 0, 0
		for _, d in live.root:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			elseif d:IsA("SurfaceGui") then
				guis += 1
			elseif d:IsA("Frame") then
				frames += 1
			end
		end
		local fx = {}
		for _, ch in Lighting:GetChildren() do
			table.insert(fx, ch.ClassName)
		end
		local lights, emitters, overlay = 0, 0, #safe:GetChildren()
		for _, d in live.root:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		print(string.format("%-8s part %d: parts=%d surfaceGuis=%d frames=%d lights=%d emitters=%d overlay=%d lighting=[%s]", id, part, count, guis, frames, lights, emitters, overlay, table.concat(fx, ",")))
		Realizer.destroy(live)
	end)
	if not success then
		ok = false
		print(id, "FAILED:", err)
	end
end
if not ok then
	error("realizer check failed")
end

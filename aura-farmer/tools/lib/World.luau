--!nocheck
-- Сборка всего мира в памяти (Lune): декорации, риги каждого плана, запечённые анимации.
-- Используется и сборкой места (tools/build.luau), и превью (tools/preview/dump.luau).

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local Loader = require("./loader")
local Build = require("./Build")
local Pose = require("./Pose")

local World = {}

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- opts.shots: список id планов (по умолчанию все); opts.sets: список декораций (по умолчанию нужные планам или все)
function World.build(opts)
	opts = opts or {}
	local Config = Loader.load("src/shared/Config")
	local root = Instance.new("Folder")
	root.Name = "AuraFarmer"
	local setsFolder = folder("Sets", root)
	local shotsFolder = folder("Shots", root)
	local animSaves = Instance.new("Model")
	animSaves.Name = "RBX_ANIMSAVES"

	local wantShots = {}
	for _, id in opts.shots or Config.ShotOrder do
		wantShots[id] = true
	end

	local result = { root = root, sets = {}, shots = {}, animSaves = animSaves, stats = {} }
	local neededSets = {}

	for _, id in Config.ShotOrder do
		if wantShots[id] then
			local shot = Loader.load("src/shared/Shots/" .. id)
			shot.id = shot.id or id
			neededSets[shot.set] = true
			local f = folder(id, shotsFolder)
			local animPath = "tools/anims/" .. id .. ".luau"
			local anims = if fs.isFile(animPath) then require("../anims/" .. id) else {}
			local entry = { shot = shot, folder = f, actors = {} }
			for actorName, actor in shot.actors or {} do
				local charPath = "tools/chars/" .. actor.char .. ".luau"
				assert(fs.isFile(charPath), "нет персонажа " .. charPath)
				local build = require("../chars/" .. actor.char)
				local rig = build(actor.opts or {})
				local rigName = id .. "_" .. actorName
				rig.model.Name = rigName
				rig.model:SetAttribute("Actor", actorName)
				rig.model:SetAttribute("Shot", id)
				rig.model:SetAttribute("Clip", id)
				rig:finish(actor.place)
				rig.model.Parent = f
				local kfs
				local anim = anims[actorName]
				if anim and anim.keys and #anim.keys > 0 then
					kfs = Pose.bake(rig, shot, anim, id, Config.BakeFPS)
					local holder = Instance.new("ObjectValue")
					holder.Name = rigName
					holder.Value = rig.model
					holder.Parent = animSaves
					kfs.Parent = holder
					-- ссылка, по которой Animation Editor находит сохранения этого рига
					local link = Instance.new("ObjectValue")
					link.Name = "AnimSaves"
					link.Value = holder
					link.Parent = rig.model
				end
				entry.actors[actorName] = { rig = rig, model = rig.model, kfs = kfs, name = rigName }
				table.insert(result.stats, string.format("%s: %d деталей, %s", rigName, #rig.visuals, if kfs then (kfs:GetAttribute("Keyframes") .. " ключевых кадров") else "без анимации"))
			end
			result.shots[id] = entry
		end
	end

	for name in Config.Sets do
		local include = if opts.sets then table.find(opts.sets, name) ~= nil else (opts.allSets or neededSets[name])
		if include then
			local path = "tools/sets/" .. name .. ".luau"
			local model = Instance.new("Model")
			model.Name = name
			if fs.isFile(path) then
				local builder = require("../sets/" .. name)
				builder(Build.new(name, model))
			end
			model.Parent = setsFolder
			result.sets[name] = model
		end
	end
	return result
end

return World

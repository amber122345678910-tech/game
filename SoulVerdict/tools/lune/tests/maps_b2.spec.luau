--!nocheck
-- Arena maps, batch 2 (src/shared/Maps/VoidRift.luau, src/shared/Maps/CoreReactor.luau):
-- MapInfo contract via MapKit.Validate (>= 8 human spawns, exactly SavesPerMap SAVE points, every spawn/save on
-- solid ground, KillY below them, part/light budgets, folders), IntroPath >= 4, determinism for the same seed,
-- gameplay data independent of the seed, decor never collides/queries, invisible boundary walls, light ranges,
-- arena size (160-220 studs across), spawn/save spread, Registry metadata and the Maps3 strings.
-- NOTE (Lune): Instance userdata are not identity-stable; compare with == and never key tables by Instance.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local MAPS = { "VoidRift", "CoreReactor" }

local function mapModule(Loader, id)
	return Loader.require("ReplicatedStorage.Shared.Maps." .. id)
end

local function exists(id)
	local fs = require("@lune/fs")
	return fs.isFile("src/shared/Maps/" .. id .. ".luau")
end

local built = {}
local function build(Loader, id, seed)
	local key = id .. ":" .. tostring(seed)
	if built[key] == nil then
		built[key] = mapModule(Loader, id).Build(seed)
	end
	return built[key]
end

local function parts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function each(T, fn)
	for _, id in MAPS do
		if exists(id) then
			T.current = T.current .. "[" .. id .. "]"
			fn(id)
		end
	end
end

local tests = {}

tests.modulesExist = function(T, Loader)
	T.ok(exists("VoidRift"), "VoidRift module exists")
	T.ok(exists("CoreReactor"), "CoreReactor module exists")
end

tests.definitionMatchesRegistry = function(T, Loader)
	local Registry = Loader.require("ReplicatedStorage.Shared.Maps.Registry")
	each(T, function(id)
		local def = mapModule(Loader, id)
		local meta = Registry.Info(id)
		T.ok(meta ~= nil, id .. " is listed in the Registry")
		T.eq(def.Id, id, "Id")
		T.ok(type(def.Name) == "table" and def.Name.en ~= "" and def.Name.ru ~= "", "Name en+ru")
		T.ok(type(def.Desc) == "table" and def.Desc.en ~= "" and def.Desc.ru ~= "", "Desc en+ru")
		if meta then
			T.eq(def.Preset, meta.Preset, "Preset")
			T.eq(def.FinalPreset, meta.FinalPreset, "FinalPreset")
			T.eq(def.Music, meta.Music, "Music")
		end
		local Presets = Loader.require("ReplicatedStorage.Shared.Graphics.Presets")
		if Presets.Get then
			T.ok(Presets.Get(def.Preset) ~= nil, "preset exists: " .. def.Preset)
			T.ok(Presets.Get(def.FinalPreset) ~= nil, "final preset exists: " .. def.FinalPreset)
		end
		T.ok(Registry.Get(id) ~= nil, "Registry loads the module")
	end)
end

tests.validMapInfo = function(T, Loader)
	local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
	local Config = Loader.require("ReplicatedStorage.Shared.Config")
	each(T, function(id)
		local info = build(Loader, id, 1)
		local ok, problems = MapKit.Validate(info, { Kind = "Arena", MinHumanSpawns = 8 })
		T.ok(ok, id .. " MapKit.Validate: " .. table.concat(problems, "; "))
		T.eq(#info.SavePoints, Config.Objectives.SavesPerMap, "exactly SavesPerMap SAVE points")
		T.ok(#info.HumanSpawns >= 8, "at least 8 human spawns")
		T.ok(typeof(info.MonsterSpawn) == "CFrame", "monster spawn")
		T.ok(#info.IntroPath >= 4, "IntroPath has >= 4 keyframes")
		T.eq(info.Id, id, "MapInfo.Id")
		T.eq(info.Model.Name, id, "model name")
		T.eq(info.Model:GetAttribute("MapId"), id, "MapId attribute")
		local stats = MapKit.Stats(info.Model)
		T.ok(stats.Parts <= 6000, ("part budget (%d)"):format(stats.Parts))
		T.ok(stats.Lights <= 60, ("light budget (%d)"):format(stats.Lights))
		T.eq(info.Model:GetAttribute("PartCount"), stats.Parts, "PartCount attribute is exact")
		T.eq(info.Model:GetAttribute("LightCount"), stats.Lights, "LightCount attribute is exact")
		T.ok(info.Model:FindFirstChild("Markers"):FindFirstChild("KillFloor", true) ~= nil, "KillFloor marker")
		T.ok(info.Model:FindFirstChild("Markers"):FindFirstChild("Center", true) ~= nil, "Center marker")
		for i = 1, #info.SavePoints do
			T.ok(info.Model:FindFirstChild("Markers"):FindFirstChild("SavePoint_" .. i, true) ~= nil, "SavePoint marker " .. i)
		end
		T.ok(info.Model:FindFirstChild("Markers"):FindFirstChild("MonsterSpawn_1", true) ~= nil, "MonsterSpawn marker")
	end)
end

tests.arenaShape = function(T, Loader)
	each(T, function(id)
		local info = build(Loader, id, 1)
		-- every gameplay point inside the Collapse ring; arena 160-220 studs across
		local far = 0
		local function inside(label, p)
			local d = flatDist(p, info.Center)
			far = math.max(far, d)
			T.ok(d <= info.Radius, ("%s inside Radius (%.1f > %.1f)"):format(label, d, info.Radius))
		end
		for i, cf in info.HumanSpawns do
			inside("HumanSpawns[" .. i .. "]", cf.Position)
		end
		inside("MonsterSpawn", info.MonsterSpawn.Position)
		for i, p in info.SavePoints do
			inside("SavePoints[" .. i .. "]", p)
		end
		T.ok(info.Radius * 2 >= 150 and info.Radius * 2 <= 240, ("Collapse diameter %.0f in 150..240"):format(info.Radius * 2))
		-- walkable extent (collidable, visible geometry above KillY)
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, p in parts(info.Model.Geometry) do
			if p.CanCollide and p.Transparency < 1 and p.Size.Magnitude < 400 then
				local pos = p.CFrame.Position
				if pos.Y > info.KillY and flatDist(pos, info.Center) < info.Radius + 30 then
					minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
					minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
				end
			end
		end
		local across = math.max(maxX - minX, maxZ - minZ)
		T.ok(across >= 150 and across <= 240, ("arena ~160-220 studs across (got %.0f)"):format(across))
		-- spread: humans far from the monster, SAVE points apart from each other
		for i, cf in info.HumanSpawns do
			T.ok(flatDist(cf.Position, info.MonsterSpawn.Position) >= 90, "human spawn " .. i .. " far from the monster")
		end
		for i = 1, #info.SavePoints do
			for j = i + 1, #info.SavePoints do
				T.ok(flatDist(info.SavePoints[i], info.SavePoints[j]) >= 45, ("SAVE %d/%d spread"):format(i, j))
			end
		end
		-- spawn points do not overlap
		for i = 1, #info.HumanSpawns do
			for j = i + 1, #info.HumanSpawns do
				T.ok(flatDist(info.HumanSpawns[i].Position, info.HumanSpawns[j].Position) >= 3, ("spawns %d/%d apart"):format(i, j))
			end
		end
	end)
end

tests.deterministic = function(T, Loader)
	local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
	each(T, function(id)
		local def = mapModule(Loader, id)
		local a = MapKit.Fingerprint(def.Build(7).Model)
		local b = MapKit.Fingerprint(def.Build(7).Model)
		T.eq(a, b, "same seed -> identical map")
		-- gameplay data never depends on the seed
		local i1, i2 = build(Loader, id, 1), build(Loader, id, 4242)
		T.eq(#i1.HumanSpawns, #i2.HumanSpawns, "spawn count independent of seed")
		for i, cf in i1.HumanSpawns do
			T.ok((cf.Position - i2.HumanSpawns[i].Position).Magnitude < 1e-6, "spawn " .. i .. " independent of seed")
		end
		for i, p in i1.SavePoints do
			T.ok((p - i2.SavePoints[i]).Magnitude < 1e-6, "SAVE " .. i .. " independent of seed")
		end
		local ok, problems = MapKit.Validate(i2, { Kind = "Arena" })
		T.ok(ok, "valid with another seed: " .. table.concat(problems, "; "))
	end)
end

tests.decorAndFolders = function(T, Loader)
	each(T, function(id)
		local info = build(Loader, id, 1)
		local model = info.Model
		local badDecor, badMarker, badLight, unanchored = 0, 0, 0, 0
		for _, p in parts(model.Decor) do
			-- MapKit B:Stairs keeps its visual steps queryable on purpose (ground probes hit the steps while
			-- physics uses the invisible ramp); everything else in Decor is inert
			local stairStep = string.find(p.Name, "_Step%d+$") ~= nil
			if p.CanCollide or (p.CanQuery and not stairStep) then
				badDecor += 1
			end
		end
		for _, p in parts(model.Markers) do
			if p.CanCollide or p.CanQuery or p.Transparency < 1 then
				badMarker += 1
			end
		end
		for _, p in parts(model.Lights) do
			if p.CanCollide or p.CanQuery or p.Transparency < 1 then
				badLight += 1
			end
		end
		for _, p in parts(model) do
			if not p.Anchored then
				unanchored += 1
			end
		end
		T.eq(badDecor, 0, "decor parts never collide or answer queries")
		T.eq(badMarker, 0, "markers are invisible and non-colliding")
		T.eq(badLight, 0, "light holders are invisible and non-colliding")
		T.eq(unanchored, 0, "every part anchored")
		-- lights: range <= 120, every light lives under Lights
		local outside = 0
		for _, d in model:GetDescendants() do
			if d:IsA("Light") then
				T.ok(d.Range <= 120, "light range <= 120")
				if not d:IsDescendantOf(model.Lights) then
					outside += 1
				end
			end
		end
		T.eq(outside, 0, "every light is under the Lights folder")
	end)
end

tests.boundaryWalls = function(T, Loader)
	each(T, function(id)
		local info = build(Loader, id, 1)
		local folder = info.Model.Geometry:FindFirstChild("Boundary", true)
		T.ok(folder ~= nil, "Geometry/Boundary folder")
		if folder == nil then
			return
		end
		local walls = 0
		local minR = math.huge
		for _, p in parts(folder) do
			walls += 1
			T.ok(p.CanCollide and p.Transparency >= 1 and not p.CastShadow, "boundary wall invisible + collidable")
			minR = math.min(minR, flatDist(p.CFrame.Position, info.Center))
		end
		T.ok(walls >= 4, "at least 4 boundary walls")
		T.ok(minR >= info.Radius, ("boundary outside the Collapse ring (%.0f >= %.0f)"):format(minR, info.Radius))
	end)
end

tests.strings = function(T, Loader)
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	local raw = Loader.requirePath("src/shared/Strings/Maps3")
	local n = 0
	for key, v in raw do
		n += 1
		T.ok(string.sub(key, 1, 5) == "maps.", "key prefix maps.: " .. key)
		T.ok(type(v.en) == "string" and v.en ~= "" and type(v.ru) == "string" and v.ru ~= "", "en+ru: " .. key)
	end
	T.ok(n > 0, "Maps3 has keys")
	T.eq(Strings.L("maps.voidrift.name"), "Void Rift", "Maps3 merged into Strings")
	each(T, function(id)
		local def = mapModule(Loader, id)
		local key = "maps." .. string.lower(id) .. ".name"
		T.eq(raw[key] and raw[key].en, def.Name.en, "name string matches the module: " .. key)
	end)
end

return tests

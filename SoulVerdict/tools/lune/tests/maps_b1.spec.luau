--!nocheck
-- Wave-2 arenas SnowdinCrossroads + WaterfallGrotto (src/shared/Maps/*): MapDef fields, MapInfo contract
-- (MapKit.Validate: spawns / SAVE points on solid ground, KillY, IntroPath, budgets, folders), extra
-- design rules (>= 8 human spawns with head-room, exactly SavesPerMap SAVE points spread apart and inside
-- the Collapse radius with a clear channel area, IntroPath >= 4, invisible boundary walls, decor never
-- collides / is never queried, light ranges <= 120), determinism for a seed, sign strings (en + ru) and
-- Registry integration. A map whose module file does not exist yet is skipped (reported by the test name).
-- NOTE (Lune): Instance userdata are not identity-stable; compare with == and never key tables by Instance.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local MAPS = { "SnowdinCrossroads", "WaterfallGrotto" }

local function exists(id)
	return fs.isFile("src/shared/Maps/" .. id .. ".luau")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function eachPart(root, fn)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

-- Builds once per map and seed (the same Instance tree is reused by several tests).
local cache = {}
local function build(Loader, id, seed)
	local key = id .. ":" .. tostring(seed)
	if cache[key] == nil then
		local def = Loader.require("ReplicatedStorage.Shared.Maps." .. id)
		cache[key] = def.Build(seed)
	end
	return cache[key]
end

local function forMaps(T, fn)
	for _, id in MAPS do
		if exists(id) then
			fn(id)
		else
			T.ok(true, id .. " not written yet (skipped)")
		end
	end
end

return {
	maps_b1_definitions = function(T, Loader)
		local Presets = Loader.require("ReplicatedStorage.Shared.Graphics.Presets")
		forMaps(T, function(id)
			local def = Loader.require("ReplicatedStorage.Shared.Maps." .. id)
			T.eq(def.Id, id, id .. ": Id")
			T.ok(type(def.Name) == "table" and def.Name.en ~= "" and def.Name.ru ~= "", id .. ": Name en + ru")
			T.ok(type(def.Desc) == "table" and def.Desc.en ~= "" and def.Desc.ru ~= "", id .. ": Desc en + ru")
			T.ok(Presets.Has(def.Preset), id .. ": preset exists " .. tostring(def.Preset))
			T.ok(Presets.Has(def.FinalPreset), id .. ": final preset exists " .. tostring(def.FinalPreset))
			T.ok(type(def.Music) == "string" and def.Music ~= "", id .. ": music key")
			T.ok(type(def.Build) == "function", id .. ": Build")
			T.ok(type(def.Layout) == "table", id .. ": Layout exported")
		end)
	end,

	maps_b1_validate = function(T, Loader)
		local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		forMaps(T, function(id)
			for _, seed in { 7, 123 } do
				local info = build(Loader, id, seed)
				local ok, problems = MapKit.Validate(info, { Kind = "Arena", MinHumanSpawns = 8 })
				T.ok(ok, ("%s seed %d: MapKit.Validate: %s"):format(id, seed, table.concat(problems, "; ")))
			end
			local info = build(Loader, id, 7)
			T.eq(info.Id, id, id .. ": MapInfo.Id")
			T.ok(#info.HumanSpawns >= 8, id .. ": >= 8 human spawns")
			T.eq(#info.SavePoints, Config.Objectives.SavesPerMap, id .. ": SAVE count")
			T.ok(#info.IntroPath >= 4, id .. ": IntroPath >= 4 keyframes")
			T.ok(info.Radius >= 80 and info.Radius <= 115, id .. ": Collapse radius ~ half the arena (" .. info.Radius .. ")")
			T.eq(info.Model.Name, id, id .. ": model name")
			T.eq(info.Model:GetAttribute("MapId"), id, id .. ": MapId attribute")
			T.ok(info.Model.Parent == nil, id .. ": model unparented")
			local def = Loader.require("ReplicatedStorage.Shared.Maps." .. id)
			T.eq(info.Preset, def.Preset, id .. ": MapInfo preset")
			T.eq(info.FinalPreset, def.FinalPreset, id .. ": MapInfo final preset")
			T.eq(info.Music, def.Music, id .. ": MapInfo music")
		end)
	end,

	maps_b1_budgets = function(T, Loader)
		local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
		forMaps(T, function(id)
			local info = build(Loader, id, 7)
			local stats = MapKit.Stats(info.Model)
			T.ok(stats.Parts <= 6000, ("%s: %d parts (<= 6000)"):format(id, stats.Parts))
			T.ok(stats.Lights <= 60, ("%s: %d lights (<= 60)"):format(id, stats.Lights))
			T.eq(info.Model:GetAttribute("PartCount"), stats.Parts, id .. ": PartCount attribute matches")
			local badRange = 0
			for _, d in info.Model:GetDescendants() do
				if d:IsA("Light") and (d.Range > 120 or d.Range <= 0) then
					badRange += 1
				end
			end
			T.eq(badRange, 0, id .. ": light ranges within (0, 120]")
		end)
	end,

	maps_b1_collision_folders = function(T, Loader)
		forMaps(T, function(id)
			local model = build(Loader, id, 7).Model
			local decorBad, lightBad, markerBad, geoBad = 0, 0, 0, 0
			eachPart(model.Decor, function(p)
				if p.CanCollide or p.CanQuery then
					decorBad += 1
				end
			end)
			eachPart(model.Lights, function(p)
				if p.CanCollide or p.CanQuery or p.Transparency < 1 then
					lightBad += 1
				end
			end)
			eachPart(model.Markers, function(p)
				if p.CanCollide or p.CanQuery or p.Transparency < 1 then
					markerBad += 1
				end
			end)
			eachPart(model.Geometry, function(p)
				if not p.CanCollide or not p.Anchored then
					geoBad += 1
				end
			end)
			T.eq(decorBad, 0, id .. ": decor never collides / is never queried")
			T.eq(lightBad, 0, id .. ": light holders invisible + non-colliding")
			T.eq(markerBad, 0, id .. ": markers invisible + non-colliding")
			T.eq(geoBad, 0, id .. ": geometry anchored + collidable")
			local boundary = model.Geometry:FindFirstChild("Boundary")
			T.ok(boundary ~= nil and #boundary:GetChildren() >= 4, id .. ": invisible boundary walls")
			if boundary then
				for _, w in boundary:GetChildren() do
					T.ok(w.Transparency == 1 and w.CanCollide and not w.CastShadow, id .. ": boundary wall " .. w.Name .. " invisible + solid")
				end
			end
			local markers = {}
			for _, d in model.Markers:GetDescendants() do
				markers[d.Name] = true
			end
			for _, name in { "MonsterSpawn_1", "HumanSpawn_1", "HumanSpawn_8", "SavePoint_1", "SavePoint_3", "Center", "KillFloor" } do
				T.ok(markers[name], id .. ": marker " .. name)
			end
		end)
	end,

	maps_b1_layout_rules = function(T, Loader)
		local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		forMaps(T, function(id)
			local info = build(Loader, id, 7)
			local probe = MapKit.Ground(info.Model)
			-- head-room: nothing solid between the ground and 6 studs above any spawn (5 rays per spawn)
			local function clear(label, p, spread)
				for _, off in { Vector3.new(0, 0, 0), Vector3.new(spread, 0, 0), Vector3.new(-spread, 0, 0), Vector3.new(0, 0, spread), Vector3.new(0, 0, -spread) } do
					local y = probe(p + off, 6, 7)
					T.ok(y ~= nil and y <= p.Y + 0.8, ("%s: %s clear at %s (hit %s)"):format(id, label, tostring(p + off), tostring(y)))
				end
			end
			for i, cf in info.HumanSpawns do
				clear("HumanSpawn " .. i, cf.Position, 1.5)
			end
			clear("MonsterSpawn", info.MonsterSpawn.Position, 2)
			-- SAVE stars: a clear channel area, spread apart, inside the Collapse ring
			local r = Config.Objectives.SaveRadius
			for i, p in info.SavePoints do
				clear("SAVE " .. i, p, r * 0.6)
				T.ok((flat(p) - flat(info.Center)).Magnitude <= info.Radius - r, id .. ": SAVE " .. i .. " inside the Collapse ring")
				for j = i + 1, #info.SavePoints do
					T.ok((flat(p) - flat(info.SavePoints[j])).Magnitude >= 45, ("%s: SAVE %d and %d spread apart"):format(id, i, j))
				end
				for _, cf in info.HumanSpawns do
					T.ok((flat(p) - flat(cf.Position)).Magnitude >= 30, id .. ": SAVE " .. i .. " not on top of the human spawns")
				end
			end
			-- spawns: distinct points, monster far from the humans, everybody inside the Collapse radius
			for i, a in info.HumanSpawns do
				T.ok((flat(a.Position) - flat(info.Center)).Magnitude <= info.Radius, id .. ": human spawn " .. i .. " inside radius")
				T.ok((a.Position - info.MonsterSpawn.Position).Magnitude >= 100, id .. ": human spawn " .. i .. " far from the monster")
				for j = i + 1, #info.HumanSpawns do
					T.ok((a.Position - info.HumanSpawns[j].Position).Magnitude >= 4, ("%s: spawns %d/%d apart"):format(id, i, j))
				end
			end
			T.ok((flat(info.MonsterSpawn.Position) - flat(info.Center)).Magnitude <= info.Radius, id .. ": monster spawn inside radius")
			-- intro path: finite, spread out (a sweeping flight, not a static shot)
			local span = 0
			for i, cf in info.IntroPath do
				local p = cf.Position
				T.ok(p.X == p.X and p.Y == p.Y and p.Z == p.Z, id .. ": IntroPath " .. i .. " finite")
				span = math.max(span, (p - info.IntroPath[1].Position).Magnitude)
			end
			T.ok(span >= 80, id .. ": IntroPath sweeps >= 80 studs")
		end)
	end,

	maps_b1_determinism = function(T, Loader)
		local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
		forMaps(T, function(id)
			local def = Loader.require("ReplicatedStorage.Shared.Maps." .. id)
			local a = MapKit.Fingerprint(def.Build(42).Model)
			local b = MapKit.Fingerprint(def.Build(42).Model)
			T.eq(a, b, id .. ": same seed -> identical map")
			T.noerror(function()
				def.Build(nil)
			end, id .. ": Build() without a seed")
		end)
	end,

	maps_b1_strings = function(T, Loader)
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		local own = Loader.require("ReplicatedStorage.Shared.Strings.Maps2")
		for key, value in own do
			T.ok(key:sub(1, 5) == "maps.", "Maps2 key prefix " .. key)
			T.ok(type(value.en) == "string" and value.en ~= "" and type(value.ru) == "string" and value.ru ~= "", "Maps2 en + ru " .. key)
			T.ok(Strings.Has(key), "Maps2 merged (listed in Strings SOURCES): " .. key)
		end
		forMaps(T, function(id)
			local model = build(Loader, id, 7).Model
			local count = 0
			for _, d in model:GetDescendants() do
				local key = d:GetAttribute("TextKey")
				if key then
					count += 1
					T.ok(Strings.Has(key), id .. ": sign key exists " .. key)
				end
			end
			T.ok(count >= 3, id .. ": has localised signs")
		end)
	end,

	maps_b1_registry = function(T, Loader)
		local Registry = Loader.require("ReplicatedStorage.Shared.Maps.Registry")
		forMaps(T, function(id)
			T.ok(Registry.IsAvailable(id), id .. ": Registry.IsAvailable")
			local meta = Registry.Info(id)
			local def = Loader.require("ReplicatedStorage.Shared.Maps." .. id)
			T.ok(meta ~= nil and meta.Kind == "Arena", id .. ": registry arena")
			T.eq(meta.Preset, def.Preset, id .. ": registry preset matches")
			local playable = false
			for _, p in Registry.Playable() do
				if p == id then
					playable = true
				end
			end
			T.ok(playable, id .. ": playable")
		end)
	end,

	maps_b1_snowdin_specifics = function(T, Loader)
		if not exists("SnowdinCrossroads") then
			return
		end
		local MapKit = Loader.require("ReplicatedStorage.Shared.Maps.MapKit")
		local def = Loader.require("ReplicatedStorage.Shared.Maps.SnowdinCrossroads")
		local L = def.Layout
		local info = build(Loader, "SnowdinCrossroads", 7)
		local probe = MapKit.Ground(info.Model)
		-- the creek can be crossed everywhere (walkable banks + frozen bed), the bridge deck spans it
		for _, x in { -80, -40, 30, 70 } do
			for z = 40, 80, 2 do
				local y = probe(Vector3.new(x, 0, z), 2, 6)
				T.ok(y ~= nil and y >= L.CreekBedY - 0.1, ("creek crossable at x=%d z=%d"):format(x, z))
			end
		end
		local mid = probe(Vector3.new(0, 4, (L.BridgeZ0 + L.BridgeZ1) / 2), 4, 10)
		T.ok(mid ~= nil and mid > 2, "bridge deck arches over the creek (" .. tostring(mid) .. ")")
		-- the pond SAVE sits on the ice
		local y, name = probe(info.SavePoints[1], 2.5, 6)
		T.near(y, L.IceTop, 0.01, "pond SAVE on the ice")
		T.ok(name == "PondIce", "pond SAVE ground part " .. tostring(name))
	end,
}

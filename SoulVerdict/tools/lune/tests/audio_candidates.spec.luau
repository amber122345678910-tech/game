--!nocheck
-- Audio candidate ids: Shared/Audio `Ids` lists (Candidates normalization / de-dupe / aliases / no Fallback chain,
-- IsFilled, Resolve + Fallback with Ids, Validate on bad Ids, the Theme_* entries and MonsterTheme) and the pure
-- SoundController helpers (PickCandidate good/bad/pending combinations, ResolveChain, ArenaMusicOrder, MusicFor with
-- the ctx.Usable predicate: normal, final, a dead theme falls back to the map track, lobby / box / override / stinger
-- unchanged). Also the offline-safe runtime queries (Status / ActiveId / NowPlaying / PreviewMusic state), a runtime
-- simulation of the whole controller with fake engine objects (probe -> next candidate -> crossfade, dead theme ->
-- map track, final chain, preview, timeout + late answer, TimeLength 0, SFX pool switch + Fallback, background batch,
-- PreloadAsync error, warn once / probe once) and the admin panel TEST -> MUSIC section (buttons, status lines from a
-- fake SoundController, phone touch targets).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local AUDIO = "ReplicatedStorage.Shared.Audio"
local KITS = "ReplicatedStorage.Shared.Kits"
local REGISTRY = "ReplicatedStorage.Shared.Maps.Registry"
local SOUND = CLIENT .. "Controllers.SoundController"

local BUILTIN_SOUNDS = {
	["rbxasset://sounds/action_falling.ogg"] = true,
	["rbxasset://sounds/action_footsteps_plastic.mp3"] = true,
	["rbxasset://sounds/action_get_up.mp3"] = true,
	["rbxasset://sounds/action_jump.mp3"] = true,
	["rbxasset://sounds/action_jump_land.mp3"] = true,
	["rbxasset://sounds/action_swim.mp3"] = true,
	["rbxasset://sounds/impact_water.mp3"] = true,
	["rbxasset://sounds/uuhhh.mp3"] = true,
}

local NIL = {} -- patch value meaning "field = nil"

local function quiet(Loader, fn)
	local before = Loader.quietWarnings
	Loader.quietWarnings = true
	local ok, err = pcall(fn)
	Loader.quietWarnings = before
	if not ok then
		error(err, 0)
	end
end

local function load(Loader, path)
	local module
	quiet(Loader, function()
		module = Loader.require(path)
	end)
	return module
end

-- runs fn with fields of Audio.Sounds entries patched ({ [entry] = { [field] = value | NIL } }), always restoring them
local function withPatch(Audio, patches, fn)
	local saved = {}
	for name, fields in patches do
		local def = assert(Audio.Sounds[name], "patch: no entry " .. name)
		saved[name] = {}
		for field, value in fields do
			saved[name][field] = { def[field] }
			if value == NIL then
				def[field] = nil
			else
				def[field] = value
			end
		end
	end
	local ok, err = pcall(fn)
	for name, fields in saved do
		for field, box in fields do
			Audio.Sounds[name][field] = box[1]
		end
	end
	if not ok then
		error(err, 0)
	end
end

local function clientMode(Loader, fn)
	local isServer, quietBefore = Loader.isServer, Loader.quietWarnings
	Loader.isServer = false
	Loader.quietWarnings = true
	local ok, err = pcall(fn)
	Loader.isServer, Loader.quietWarnings = isServer, quietBefore
	if not ok then
		error(err, 0)
	end
end

local function makeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local entry = { fn = fn }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				for i, e in handlers do
					if e == entry then
						table.remove(handlers, i)
						break
					end
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, e in table.clone(handlers) do
			e.fn(...)
		end
	end
	return signal
end

-- Loads src/client/Controllers/SoundController.luau with fake engine objects: Sounds whose assets load on the next
-- step according to world.fetch, a ContentProvider, StateController / InputController fakes, and a manual scheduler
-- (task.delay / defer / spawn / wait, os.clock) driven by world.advance(seconds).
-- world.fetch[id] = "Success" | "Failure" | "TimedOut" | "Empty" (PreloadAsync says Success but the Sound loads with
-- TimeLength 0) | "Hang" (no answer until world.release(id, answer)) | "Error" (PreloadAsync throws).
local function loadSoundWithMocks(Loader)
	local roblox = Loader.roblox
	local Enum = roblox.Enum
	local world = {
		now = 0,
		fetch = {},
		preloads = {},
		warnings = {},
		prints = {},
		round = { Phase = "Waiting" },
		role = "Human",
	}
	local timers, deferred, hanging, loading = {}, {}, {}, {}
	local seq = 0
	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(err, 0)
		end
	end
	local function addTimer(t, fn, ...)
		seq += 1
		table.insert(timers, { at = world.now + (t or 0), seq = seq, fn = fn, args = table.pack(...) })
	end
	local fakeTask = {
		delay = function(t, fn, ...)
			addTimer(t, fn, ...)
		end,
		defer = function(fn, ...)
			table.insert(deferred, { fn = fn, args = table.pack(...) })
		end,
		spawn = function(fn, ...)
			local co = coroutine.create(fn)
			resume(co, ...)
			return co
		end,
		wait = function(t)
			local co = coroutine.running()
			addTimer(t, function()
				resume(co)
			end)
			return coroutine.yield()
		end,
	}
	function world.flush()
		for _ = 1, 500 do
			local d = table.remove(deferred, 1)
			if d == nil then
				return
			end
			d.fn(table.unpack(d.args, 1, d.args.n))
		end
		error("the deferred queue does not drain")
	end
	-- fake Instances: Sound (+ SoundGroup / Folder / Attachment); IsLoaded / TimeLength are read-only for the code
	local heartbeat = makeSignal()
	local function fakeInstance(className)
		local props = { ClassName = className, Name = className, Destroying = makeSignal() }
		local methods = {}
		local obj = {}
		function methods:IsA(c)
			return c == className or c == "Instance"
		end
		function methods:FindFirstChild()
			return nil
		end
		function methods:Destroy()
			props.Parent = nil
			props.Destroying:Fire()
		end
		if className == "Sound" then
			props.SoundId = ""
			props.Volume = 0.5
			props.Looped = false
			props.Playing = false
			props.IsLoaded = false
			props.TimeLength = 0
			props.PlaybackSpeed = 1
			props.TimePosition = 0
			props.Ended = makeSignal()
			props.Loaded = makeSignal()
			function methods:Play()
				props.Playing = true
			end
			function methods:Stop()
				props.Playing = false
			end
		end
		return setmetatable(obj, {
			__index = function(_, k)
				local m = methods[k]
				if m ~= nil then
					return m
				end
				return props[k]
			end,
			__newindex = function(_, k, v)
				if k == "IsLoaded" or k == "TimeLength" or k == "ClassName" then
					error("mock: " .. k .. " is read-only", 2)
				end
				props[k] = v
				if k == "SoundId" then
					props.IsLoaded = false
					props.TimeLength = 0
					loading[obj] = props
				end
			end,
		})
	end
	function world.step(dt)
		world.now += dt
		while true do
			local best, index = nil, nil
			for i, t in timers do
				if
					t.at <= world.now + 1e-9
					and (best == nil or t.at < best.at or (t.at == best.at and t.seq < best.seq))
				then
					best, index = t, i
				end
			end
			if best == nil then
				break
			end
			table.remove(timers, index)
			best.fn(table.unpack(best.args, 1, best.args.n))
			world.flush()
		end
		local batch = loading
		loading = {}
		for _, props in batch do
			local answer = world.fetch[props.SoundId]
			if answer == "Success" or answer == "Empty" then
				props.IsLoaded = true
				props.TimeLength = if answer == "Success" then 30 else 0
				props.Loaded:Fire()
			end
		end
		world.flush()
		heartbeat:Fire(dt)
		world.flush()
	end
	function world.advance(seconds)
		for _ = 1, math.max(1, math.floor(seconds / 0.1 + 0.5)) do
			world.step(0.1)
		end
	end
	local contentProvider = {}
	function contentProvider:PreloadAsync(items, callback)
		local id = items[1].SoundId
		table.insert(world.preloads, id)
		local answer = world.fetch[id]
		if answer == "Hang" then
			hanging[id] = coroutine.running()
			coroutine.yield()
			answer = world.fetch[id]
		end
		if answer == "Error" then
			error("mock: PreloadAsync is not available")
		end
		local status = if answer == "Success" or answer == "Empty"
			then Enum.AssetFetchStatus.Success
			elseif answer == "TimedOut" then Enum.AssetFetchStatus.TimedOut
			else Enum.AssetFetchStatus.Failure
		callback(id, status)
	end
	function contentProvider:GetAssetFetchStatus()
		return Enum.AssetFetchStatus.None
	end
	function world.release(id, answer)
		world.fetch[id] = answer
		local co = hanging[id]
		hanging[id] = nil
		if co then
			resume(co)
		end
		world.flush()
	end
	-- client controllers the SoundController looks up lazily
	local state = { RoundChanged = makeSignal(), RoleChanged = makeSignal(), SettingChanged = makeSignal() }
	function state.Round()
		return world.round
	end
	function state.Role()
		return world.role
	end
	function state.Setting()
		return 1
	end
	function state.OnRoundEvent() end
	function world.setRound(attr, value)
		world.round[attr] = value
		state.RoundChanged:Fire(attr, value)
		world.flush()
	end
	local input = { ContextChanged = makeSignal() }
	function input.HasContext()
		return false
	end
	local function module(path, fake)
		return {
			__module = path,
			__fake = fake,
			IsA = function(_, c)
				return c == "ModuleScript"
			end,
		}
	end
	local function folder(children)
		return {
			WaitForChild = function(_, n)
				return children[n] or error("mock: missing child " .. n)
			end,
			FindFirstChild = function(_, n)
				return children[n]
			end,
		}
	end
	local replicatedStorage = folder({
		Shared = folder({
			Audio = module(AUDIO),
			Maps = folder({ Registry = module(REGISTRY) }),
			Util = folder({ Signal = module("ReplicatedStorage.Shared.Util.Signal") }),
		}),
	})
	local services = {
		SoundService = fakeInstance("SoundService"),
		RunService = { Heartbeat = heartbeat },
		TweenService = {
			Create = function()
				return { Play = function() end, Completed = makeSignal() }
			end,
		},
		ContentProvider = contentProvider,
		ReplicatedStorage = replicatedStorage,
	}
	local env = setmetatable({
		game = {
			GetService = function(_, n)
				return services[n] or error("mock: no service " .. n)
			end,
		},
		workspace = {},
		script = {
			Name = "SoundController",
			Parent = folder({ StateController = module(nil, state), InputController = module(nil, input) }),
		},
		require = function(target)
			if type(target) == "table" and target.__fake then
				return target.__fake
			elseif type(target) == "table" and target.__module then
				return Loader.require(target.__module)
			end
			error("mock: unexpected require")
		end,
		warn = function(...)
			table.insert(world.warnings, table.concat({ ... }, " "))
		end,
		print = function(...)
			table.insert(world.prints, table.concat({ ... }, " "))
		end,
		task = fakeTask,
		os = setmetatable({
			clock = function()
				return world.now
			end,
		}, { __index = os }),
		Instance = { new = fakeInstance },
		Enum = Enum,
		Random = Loader.Random,
		TweenInfo = roblox.TweenInfo,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
	}, { __index = _G })
	local source = fs.readFile("src/client/Controllers/SoundController.luau")
	local chunk = luau.load(source, { debugName = "SoundController(mock)", environment = env, injectGlobals = true })
	world.controller = chunk()
	function world.count(list, needle)
		local n = 0
		for _, line in list do
			if string.find(line, needle, 1, true) then
				n += 1
			end
		end
		return n
	end
	return world
end

local function list(t)
	return table.concat(t, ",")
end

local function hasProblem(problems, pattern)
	for _, p in problems do
		if string.find(p, pattern) then
			return true
		end
	end
	return false
end

return {
	------------------------------------------------------------------------------------------- Shared/Audio
	audio_candidates_normalize_dedupe = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		T.eq(
			list(Audio.CandidatesOf({
				Id = "123",
				Ids = { "rbxassetid://123", "456", "", "rbxassetid://789", "456" },
				Group = "Music",
				Volume = 1,
			})),
			"rbxassetid://123,rbxassetid://456,rbxassetid://789",
			"Id first, then Ids; normalized; empty and duplicate ids dropped"
		)
		T.eq(#Audio.CandidatesOf({ Id = "", Ids = {}, Group = "SFX", Volume = 1 }), 0, "no candidates")
		T.eq(#Audio.CandidatesOf({ Id = "", Group = "SFX", Volume = 1 }), 0, "no Ids field")
		T.eq(#Audio.CandidatesOf(nil), 0, "nil def")
		T.eq(
			#Audio.CandidatesOf({ Id = "", Ids = { 123, false }, Group = "SFX", Volume = 1 }),
			0,
			"non-strings skipped"
		)
		T.eq(
			list(Audio.CandidatesOf({ Id = "rbxasset://sounds/uuhhh.mp3", Group = "SFX", Volume = 1 })),
			"rbxasset://sounds/uuhhh.mp3",
			"built-in file kept as is"
		)
		T.eq(list(Audio.Candidates("Land")), Audio.Builtin.Land, "built-in entry")
		T.eq(#Audio.Candidates("NoSuchSound"), 0, "unknown entry")
		withPatch(Audio, {
			Theme_FellSans = { Id = "", Ids = { "111", "rbxassetid://111", "222" } },
			FinalPhase = { Id = "", Ids = { "333" } },
			Map_HallOfVerdicts = { Id = "444", Ids = { "555" } },
		}, function()
			T.eq(list(Audio.Candidates("Theme_FellSans")), "rbxassetid://111,rbxassetid://222", "entry Ids")
			T.eq(list(Audio.Candidates("Final")), "rbxassetid://333", "alias resolved")
			T.eq(list(Audio.Candidates("Map_TestArena")), "rbxassetid://444,rbxassetid://555", "alias + Id + Ids")
			T.eq(#Audio.Candidates("Map_VoidRift_Final"), 0, "exact entry only: the Fallback chain is not followed")
		end)
		T.ok(not Audio.IsFilled({ Id = "", Ids = {}, Group = "SFX", Volume = 1 }), "empty list = not filled")
		T.ok(not Audio.IsFilled({ Id = "", Ids = { "" }, Group = "SFX", Volume = 1 }), "only empty ids = not filled")
		T.ok(Audio.IsFilled({ Id = "", Ids = { "1" }, Group = "SFX", Volume = 1 }), "Ids list = filled")
		T.ok(Audio.IsFilled({ Id = "1", Group = "SFX", Volume = 1 }), "Id = filled")
		T.ok(not Audio.IsFilled(nil), "nil = not filled")
	end,

	audio_resolve_with_ids = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		withPatch(Audio, {
			Hit = { Id = "", Ids = { "111" } },
			HitHeavy = { Id = "", Ids = NIL },
		}, function()
			local def, name = Audio.Resolve("HitHeavy")
			T.ok(def == Audio.Sounds.Hit and name == "Hit", "an Ids-only fallback target resolves like a filled Id")
			Audio.Sounds.HitHeavy.Ids = { "222" }
			local own, ownName = Audio.Resolve("HitHeavy")
			T.ok(own == Audio.Sounds.HitHeavy and ownName == "HitHeavy", "own Ids beat the fallback")
			Audio.Sounds.HitHeavy.Ids = { "" }
			local _, viaFallback = Audio.Resolve("HitHeavy")
			T.eq(viaFallback, "Hit", "a list of empty ids is not filled")
		end)
		withPatch(Audio, {
			FinalPhase = { Id = "", Ids = { "333" } },
			Map_VoidRift_Final = { Id = "", Ids = {} },
		}, function()
			local _, name = Audio.Resolve("Map_VoidRift_Final")
			T.eq(name, "FinalPhase", "per-map final -> FinalPhase")
			local _, alias = Audio.Resolve("Final")
			T.eq(alias, "FinalPhase", "alias")
			Audio.Sounds.Map_VoidRift_Final.Ids = { "444" }
			local _, own = Audio.Resolve("Map_VoidRift_Final")
			T.eq(own, "Map_VoidRift_Final", "per-map final with its own Ids")
		end)
		withPatch(Audio, { Theme_EclipseSans_Final = { Id = "", Ids = {} } }, function()
			T.eq(Audio.Resolve("Theme_EclipseSans_Final"), nil, "empty theme (no Fallback) is silent")
		end)
		withPatch(Audio, { Theme_EclipseSans_Final = { Id = "", Ids = { "777" } } }, function()
			local _, name = Audio.Resolve("Theme_EclipseSans_Final")
			T.eq(name, "Theme_EclipseSans_Final", "filled theme")
		end)
	end,

	audio_validate_checks_ids = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		T.eq(#Audio.Validate(), 0, "registry well-formed: " .. table.concat(Audio.Validate(), "; "))
		local cases = {
			{ { "abc" }, "Hit: bad Ids%[1%] abc", "not a number" },
			{ { "rbxassetid://12", "rbxassetid://12x" }, "Hit: bad Ids%[2%]", "second id malformed" },
			{ { " 123" }, "Hit: bad Ids%[1%]", "whitespace" },
			{ { 123 }, "Hit: bad Ids%[1%] 123", "number instead of a string" },
			{ "123", "Hit: Ids must be a list", "a string instead of a list" },
			{ { a = "123" }, "Hit: Ids must be a plain list", "named keys" },
		}
		for _, case in cases do
			withPatch(Audio, { Hit = { Ids = case[1] } }, function()
				local problems = Audio.Validate()
				T.ok(hasProblem(problems, case[2]), case[3] .. ": " .. table.concat(problems, "; "))
			end)
		end
		withPatch(Audio, { Hit = { Ids = { "rbxassetid://12", "34", "rbxasset://sounds/uuhhh.mp3", "" } } }, function()
			T.eq(#Audio.Validate(), 0, "valid Ids: " .. table.concat(Audio.Validate(), "; "))
		end)
		-- the shipped data: every candidate is well-formed and built-in files are confirmed ones
		for _, name in Audio.Names() do
			for _, id in Audio.Candidates(name) do
				T.ok(
					string.match(id, "^rbxassetid://%d+$") or BUILTIN_SOUNDS[id],
					name .. ": candidate is an asset id or a confirmed built-in file: " .. id
				)
			end
		end
	end,

	audio_theme_entries = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		local Kits = Loader.require(KITS)
		local monsters = {}
		for _, kit in Kits.ForRole("Monster") do
			monsters[kit.Id] = true
		end
		T.eq(#Audio.ThemeKits, 3, "three monster kits have themes")
		for _, kitId in Audio.ThemeKits do
			T.ok(monsters[kitId], kitId .. " is a monster kit")
		end
		for kitId in monsters do
			T.ok(table.find(Audio.ThemeKits, kitId) ~= nil, "monster kit " .. kitId .. " has a theme")
			for _, key in { "Theme_" .. kitId, "Theme_" .. kitId .. "_Final" } do
				local def = Audio.Get(key)
				if T.ok(def ~= nil, "entry " .. key) then
					T.eq(def.Group, "Music", key .. " group")
					T.eq(def.Looped, true, key .. " loops")
					T.eq(def.MaxInstances, 1, key .. " one voice")
					T.ok(def.Volume >= 0.4 and def.Volume <= 0.6, key .. " volume about 0.5")
					T.eq(type(def.Ids), "table", key .. " has an Ids list for the candidates")
					T.ok(type(def.Note) == "string" and #def.Note > 10, key .. " note")
					T.eq(def.Fallback, nil, key .. " has no Fallback (the music selection orders the options)")
				end
			end
		end
		for _, name in Audio.Names("Music") do
			T.eq(type(Audio.Get(name).Ids), "table", name .. ": music entry has an Ids list")
		end
		T.eq(Audio.MonsterTheme("FellSans"), "Theme_FellSans")
		T.eq(Audio.MonsterTheme("FellSans", false), "Theme_FellSans")
		T.eq(Audio.MonsterTheme("FellSans", true), "Theme_FellSans_Final")
		T.eq(Audio.MonsterTheme("ClassicSans", true), "Theme_ClassicSans_Final")
		T.eq(Audio.MonsterTheme("EclipseSans"), "Theme_EclipseSans")
		T.eq(Audio.MonsterTheme("Determination"), nil, "human kit: no theme")
		T.eq(Audio.MonsterTheme("Nope", true), nil, "unknown kit")
		T.eq(Audio.MonsterTheme(""), nil, "empty kit")
		T.eq(Audio.MonsterTheme(nil), nil, "no kit")
	end,

	------------------------------------------------------------------------------- SoundController (pure)
	sound_pick_candidate = function(T, Loader)
		local Sound = load(Loader, SOUND)
		local function pick(cands, states)
			local id, status = Sound.PickCandidate(cands, function(id)
				return states[id]
			end)
			return tostring(id) .. "/" .. status
		end
		T.eq(pick({}, {}), "nil/empty", "no candidates")
		T.eq(pick({ "a", "b" }, {}), "a/pending", "untested first candidate (optimistic / probe it)")
		T.eq(pick({ "a", "b" }, { a = "pending" }), "a/pending", "first candidate being probed")
		T.eq(pick({ "a", "b" }, { a = "good" }), "a/ok", "good first")
		T.eq(pick({ "a", "b" }, { a = "good", b = "bad" }), "a/ok", "good first, bad second")
		T.eq(pick({ "a", "b" }, { a = "bad" }), "b/pending", "bad first -> next untested")
		T.eq(pick({ "a", "b" }, { a = "bad", b = "pending" }), "b/pending", "bad first -> next pending")
		T.eq(pick({ "a", "b" }, { a = "bad", b = "good" }), "b/ok", "bad first -> next good")
		T.eq(pick({ "a", "b" }, { a = "pending", b = "good" }), "a/pending", "strict order: wait for the first")
		T.eq(pick({ "a", "b" }, { a = "bad", b = "bad" }), "nil/dead", "all bad = dead")
		T.eq(pick({ "a" }, { a = "bad" }), "nil/dead", "single bad = dead")
	end,

	sound_resolve_chain = function(T, Loader)
		local Sound = load(Loader, SOUND)
		local Audio = Loader.require(AUDIO)
		local defs = {
			A = { Id = "", Ids = { "1", "2" }, Group = "SFX", Volume = 1, Fallback = "B" },
			B = { Id = "3", Group = "SFX", Volume = 1 },
			C = { Id = "", Ids = {}, Group = "SFX", Volume = 1 },
			D = { Id = "", Group = "SFX", Volume = 1, Fallback = "C" },
			E = { Id = "5", Group = "SFX", Volume = 1, Fallback = "F" },
			F = { Id = "6", Group = "SFX", Volume = 1, Fallback = "E" },
			G = { Id = "7", Group = "SFX", Volume = 1, Fallback = "Missing" },
			H = { Id = "", Group = "SFX", Volume = 1, Fallback = "B" },
		}
		local states = {}
		local function chain(name, listFn)
			local entry, id, status = Sound.ResolveChain(name, function(n)
				return defs[n]
			end, function(id)
				return states[id]
			end, listFn)
			return ("%s/%s/%s"):format(tostring(entry), tostring(id), status)
		end
		local a1, a2, b = "rbxassetid://1", "rbxassetid://2", "rbxassetid://3"
		T.eq(chain("A"), "A/" .. a1 .. "/pending", "first untested candidate of the entry")
		states[a1] = "bad"
		T.eq(chain("A"), "A/" .. a2 .. "/pending", "next candidate")
		states[a2] = "good"
		T.eq(chain("A"), "A/" .. a2 .. "/ok", "good second candidate")
		states[a2] = "bad"
		T.eq(chain("A"), "B/" .. b .. "/pending", "dead entry -> Fallback")
		states[b] = "good"
		T.eq(chain("A"), "B/" .. b .. "/ok", "Fallback good")
		T.eq(chain("H"), "B/" .. b .. "/ok", "empty entry -> Fallback")
		states[b] = "bad"
		T.eq(chain("A"), "nil/nil/dead", "whole chain failed = dead")
		T.eq(chain("H"), "nil/nil/dead", "empty entry whose Fallback is dead = dead")
		T.eq(chain("C"), "nil/nil/empty", "no candidates = empty")
		T.eq(chain("D"), "nil/nil/empty", "empty -> empty = empty")
		T.eq(chain("Nope"), "nil/nil/empty", "unknown = empty")
		states["rbxassetid://5"] = "bad"
		states["rbxassetid://6"] = "bad"
		T.eq(chain("E"), "nil/nil/dead", "Fallback cycle terminates")
		states["rbxassetid://7"] = "bad"
		T.eq(chain("G"), "nil/nil/dead", "missing Fallback target stops the walk")
		T.eq(
			chain("C", function()
				return { "custom" }
			end),
			"C/custom/pending",
			"custom candidate lister"
		)
		-- real data: Revive (no ids) -> GetUp (built-in); the pure helper only knows the states it is given
		local entry, id, status = Sound.ResolveChain("Revive", Audio.Get, function()
			return nil
		end)
		T.eq(("%s/%s/%s"):format(entry, id, status), "GetUp/" .. Audio.Builtin.GetUp .. "/pending", "Revive -> GetUp")
	end,

	sound_arena_music_order = function(T, Loader)
		local Sound = load(Loader, SOUND)
		local Audio = Loader.require(AUDIO)
		local function order(round)
			return list(Sound.ArenaMusicOrder(round))
		end
		T.eq(
			order({ Phase = "Round", MapId = "SnowdinCrossroads", MonsterKit = "FellSans" }),
			"Theme_FellSans,Map_SnowdinCrossroads",
			"normal: theme, then the map track"
		)
		T.eq(
			order({ Phase = "Round", MapId = "SnowdinCrossroads", MonsterKit = "FellSans", FinalPhase = true }),
			"Theme_FellSans_Final,Theme_FellSans,Map_SnowdinCrossroads_Final,FinalPhase,Map_SnowdinCrossroads",
			"final: final theme, theme, map final chain, map track"
		)
		T.eq(
			order({ Phase = "Collapse", MapId = "SnowdinCrossroads", MonsterKit = "FellSans" }),
			"CollapsePhase,Theme_FellSans,Map_SnowdinCrossroads",
			"collapse: its own track first, then the fight music"
		)
		T.eq(
			order({ Phase = "Collapse", MapId = "SnowdinCrossroads", MonsterKit = "FellSans", FinalPhase = true }),
			"CollapsePhase,Theme_FellSans_Final,Theme_FellSans,Map_SnowdinCrossroads_Final,FinalPhase,Map_SnowdinCrossroads",
			"collapse in the final phase"
		)
		T.eq(order({ Phase = "Round", MapId = "VoidRift" }), "Map_VoidRift", "no monster kit")
		T.eq(
			order({ Phase = "Round", MapId = "VoidRift", FinalPhase = true }),
			"Map_VoidRift_Final,FinalPhase,Map_VoidRift",
			"final without a monster kit"
		)
		T.eq(order({ Phase = "Round", MapId = "VoidRift", MonsterKit = "Determination" }), "Map_VoidRift", "no theme")
		T.eq(order({ Phase = "Round", MapId = "", MonsterKit = "" }), "Lobby", "no map: the lobby track as before")
		T.eq(order({ Phase = "Round", FinalPhase = true }), "FinalPhase,Lobby", "no map, final: no duplicates")
		T.eq(order({ Phase = "Round", MapId = "TestArena" }), "Map_HallOfVerdicts", "test arena -> alias")
		local Registry = Loader.require(REGISTRY)
		for _, meta in Registry.List() do
			for _, final in { false, true } do
				for _, key in Sound.ArenaMusicOrder({ MapId = meta.Id, MonsterKit = "ClassicSans", FinalPhase = final }) do
					T.ok(Audio.Get(key) ~= nil, ("map %s order key %s is registered"):format(meta.Id, key))
				end
			end
		end
	end,

	sound_music_for_usable = function(T, Loader)
		local Sound = load(Loader, SOUND)
		local Audio = Loader.require(AUDIO)
		local fight = { Phase = "Round", MapId = "SnowdinCrossroads", MonsterKit = "FellSans" }
		local final = { Phase = "Round", MapId = "SnowdinCrossroads", MonsterKit = "FellSans", FinalPhase = true }
		local asked = {}
		local function usableOnly(keys)
			local set = {}
			for _, k in keys do
				set[k] = true
			end
			return function(key)
				asked[key] = true
				return set[key] == true
			end
		end
		local function pick(round, keys, extra)
			local ctx = { Participant = true, Usable = usableOnly(keys) }
			for k, v in extra or {} do
				ctx[k] = v
			end
			return Sound.MusicFor(round, ctx)
		end
		local all = {
			"Theme_FellSans_Final",
			"Theme_FellSans",
			"Map_SnowdinCrossroads_Final",
			"FinalPhase",
			"Map_SnowdinCrossroads",
		}
		-- normal
		T.eq(pick(fight, all), "Theme_FellSans", "the monster's theme first")
		T.eq(pick(fight, { "Map_SnowdinCrossroads" }), "Map_SnowdinCrossroads", "dead theme -> the map track")
		T.eq(pick(fight, {}), "Map_SnowdinCrossroads", "nothing usable -> the map track (silent, as before)")
		for _, phase in { "Intro", "Collapse" } do
			T.eq(
				pick({ Phase = phase, MapId = "VoidRift", MonsterKit = "EclipseSans" }, { "Theme_EclipseSans" }),
				"Theme_EclipseSans",
				phase .. " uses the theme too"
			)
		end
		-- final phase
		T.eq(pick(final, all), "Theme_FellSans_Final", "final theme first")
		T.eq(
			pick(final, { "Theme_FellSans", "FinalPhase", "Map_SnowdinCrossroads" }),
			"Theme_FellSans",
			"no final theme -> the normal theme"
		)
		T.eq(
			pick(final, { "Map_SnowdinCrossroads_Final", "FinalPhase", "Map_SnowdinCrossroads" }),
			"Map_SnowdinCrossroads_Final",
			"dead themes -> the map's final chain"
		)
		T.eq(pick(final, { "FinalPhase", "Map_SnowdinCrossroads" }), "FinalPhase", "-> FinalPhase")
		T.eq(pick(final, { "Map_SnowdinCrossroads" }), "Map_SnowdinCrossroads", "-> the map track")
		T.eq(pick(final, {}), "Map_SnowdinCrossroads", "nothing usable in the final phase -> the map track")
		-- unchanged rules (Usable is not consulted)
		asked = {}
		T.eq(pick({ Phase = "Waiting" }, {}), "Lobby", "lobby, even when silent")
		T.eq(pick({ Phase = "Intermission", MapId = "VoidRift" }, {}), "Lobby", "intermission")
		T.eq(pick(fight, {}, { Box = true }), "VerdictBox", "the Verdict Box")
		T.eq(pick(fight, {}, { Override = "Theme_ClassicSans", Box = true }), "Theme_ClassicSans", "override wins")
		T.eq(pick(fight, all, { Participant = false }), "Lobby", "lobby viewer during a round")
		T.eq(pick({ Phase = "Ending" }, {}, { Stinger = "Victory" }), "Victory", "stinger")
		T.eq(pick({ Phase = "Ending" }, {}, { Current = "Theme_FellSans" }), "Theme_FellSans", "ending keeps the track")
		T.eq(next(asked), nil, "Usable is only asked about arena tracks")
		-- default predicate: Shared/Audio data (no runtime state)
		local expected
		local order = Sound.ArenaMusicOrder(final)
		for _, key in order do
			if Audio.Resolve(key) ~= nil then
				expected = key
				break
			end
		end
		T.eq(
			Sound.MusicFor(final, { Participant = true }),
			expected or order[#order],
			"default Usable = has candidates"
		)
		withPatch(Audio, { Theme_FellSans = { Ids = { "123" } } }, function()
			T.eq(Sound.MusicFor(fight, { Participant = true }), "Theme_FellSans", "a filled theme is used by default")
		end)
	end,

	------------------------------------------------------------------------- SoundController (runtime, offline)
	sound_runtime_queries_offline = function(T, Loader)
		local Sound = load(Loader, SOUND)
		local Audio = Loader.require(AUDIO)
		for _, fn in
			{
				"ActiveId",
				"Status",
				"PreviewMusic",
				"NowPlaying",
				"IdState",
				"PickCandidate",
				"ResolveChain",
				"ArenaMusicOrder",
				"MusicFor",
			}
		do
			T.eq(type(Sound[fn]), "function", "SoundController." .. fn)
		end
		T.eq(Sound.Status(""), "empty", "no name")
		T.eq(Sound.Status("NoSuchSound"), "empty", "unknown")
		T.eq(Sound.ActiveId(""), nil, "no name -> no id")
		T.eq(Sound.Status("Land"), "ok", "built-in files are trusted without a probe")
		T.eq(Sound.ActiveId("Land"), Audio.Builtin.Land, "built-in id in use")
		T.eq(Sound.IdState(Audio.Builtin.Land), "good", "built-in state")
		T.eq(Sound.IdState("123"), nil, "untested id")
		withPatch(Audio, { Theme_FellSans = { Id = "", Ids = {} } }, function()
			T.eq(Sound.Status("Theme_FellSans"), "empty", "theme without candidates")
			T.eq(Sound.ActiveId("Theme_FellSans"), nil, "no id")
		end)
		withPatch(Audio, { Theme_FellSans = { Id = "", Ids = { "555", "666" } } }, function()
			T.eq(Sound.Status("Theme_FellSans"), "pending", "filled theme: not checked yet")
			T.eq(Sound.ActiveId("Theme_FellSans"), "rbxassetid://555", "the first candidate is the one to check")
		end)
		local before = Sound.NowPlaying()
		T.eq(before.Preview, false, "no preview")
		T.eq(before.Status, "empty", "nothing requested offline")
		Sound.PreviewMusic("Final")
		T.eq(Sound.NowPlaying().Preview, true, "preview is sticky")
		Sound.PreviewMusic(nil)
		T.eq(Sound.NowPlaying().Preview, false, "nil clears the preview")
	end,

	sound_runtime_simulation = function(T, Loader)
		local Audio = Loader.require(AUDIO)
		local function id(n)
			return "rbxassetid://" .. n
		end
		local function fmt(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			return table.concat(parts, "|")
		end
		withPatch(Audio, {
			Lobby = { Ids = { "301" } },
			Theme_FellSans = { Ids = { "101", "102" } },
			Theme_EclipseSans = { Ids = { "401" } },
			Theme_ClassicSans = { Ids = { "601" } },
			Map_SnowdinCrossroads = { Ids = { "201" } },
			FinalPhase = { Ids = { "501" } },
			VerdictBox = { Ids = { "701", "702" } },
			Hit = { Ids = { "801", "802" } },
			HitHeavy = { Ids = { "803" } },
			Shot = { Ids = { "904" } },
			Dash = { Ids = { "901" } },
			Teleport = { Ids = { "902", "903" } },
		}, function()
			local world = loadSoundWithMocks(Loader)
			local S = world.controller
			for n, answer in
				{
					[301] = "Success",
					[101] = "Failure",
					[102] = "Hang",
					[401] = "Failure",
					[201] = "Success",
					[501] = "Success",
					[601] = "Hang",
					[701] = "Empty",
					[702] = "Success",
					[801] = "Failure",
					[802] = "Success",
					[803] = "TimedOut",
					[904] = "Error",
					[901] = "Success",
					[902] = "Failure",
					[903] = "Success",
				}
			do
				world.fetch[id(n)] = answer
			end
			S.Init()
			S.Start()
			world.advance(0.3)
			local now = S.NowPlaying()
			T.eq(
				fmt(now.Key, now.Id, now.Status, now.Playing),
				fmt("Lobby", id(301), "ok", true),
				"lobby on a checked id"
			)
			T.eq(S.CurrentMusic(), "Lobby", "current music")

			-- SFX: the first candidate plays optimistically; when it fails the pool switches to the next one
			local hit = S.Play("Hit")
			T.ok(hit ~= nil, "Hit plays while its id is checked")
			T.eq(S.IdState(id(801)), "bad", "801 failed")
			T.eq(hit and hit.SoundId, id(802), "the pool's SoundId moved to the next candidate")
			T.eq(S.ActiveId("Hit"), id(802), "ActiveId Hit")
			world.advance(0.1)
			S.Play("HitHeavy") -- its only id times out -> dead -> Fallback "Hit"
			T.eq(S.Status("HitHeavy"), "ok", "dead entry -> Fallback")
			T.eq(S.ActiveId("HitHeavy"), id(802), "via Fallback")
			world.advance(0.1)
			local heavy = S.Play("HitHeavy")
			T.eq(heavy and heavy.SoundId, id(802), "the next play uses the Fallback entry")
			world.advance(0.1)
			S.Play("Shot") -- PreloadAsync throws: played unchecked
			T.eq(S.Status("Shot"), "ok", "a checker error never silences an id")
			T.eq(world.count(world.warnings, "could not check audio id " .. id(904)), 1, "checker error warned")

			-- a round with Fell Sans: 101 fails, 102 is still being checked -> the lobby track keeps playing
			world.setRound("MapId", "SnowdinCrossroads")
			world.setRound("MonsterKit", "FellSans")
			world.setRound("Phase", "Intro")
			T.eq(S.Status("Theme_FellSans"), "pending", "theme: 101 bad, 102 being checked")
			T.eq(S.NowPlaying().Key, "Theme_FellSans", "the theme is requested")
			T.eq(S.CurrentMusic(), "Lobby", "the old track keeps playing while the theme is checked")
			T.eq(
				world.count(world.warnings, "[Sound] audio id failed to load: " .. id(101) .. " (Theme_FellSans)"),
				1,
				"warned about 101"
			)
			world.release(id(102), "Success")
			world.advance(0.3)
			now = S.NowPlaying()
			T.eq(fmt(S.CurrentMusic(), now.Id, now.Index, now.Count), fmt("Theme_FellSans", id(102), 2, 2), "2nd id")
			T.eq(S.ActiveId("Theme_FellSans"), id(102), "ActiveId theme")

			-- Eclipse Sans' only theme id fails -> the map track
			world.setRound("MonsterKit", "EclipseSans")
			world.advance(0.3)
			T.eq(S.Status("Theme_EclipseSans"), "dead", "every candidate failed")
			now = S.NowPlaying()
			T.eq(fmt(now.Key, now.Id, now.Status), fmt("Map_SnowdinCrossroads", id(201), "ok"), "dead theme -> map")
			T.eq(S.CurrentMusic(), "Map_SnowdinCrossroads", "map track on the deck")

			-- final phase: no Eclipse final, dead theme -> the map's final chain (<map>_Final -> FinalPhase)
			world.setRound("FinalPhase", true)
			world.advance(0.3)
			now = S.NowPlaying()
			T.eq(fmt(now.Key, now.Entry, now.Id), fmt("Map_SnowdinCrossroads_Final", "FinalPhase", id(501)), "final")
			world.setRound("MonsterKit", "FellSans")
			world.advance(0.3)
			T.eq(S.NowPlaying().Key, "Theme_FellSans", "no Fell final theme -> the normal Fell theme")

			-- preview: sticky (beats round changes), nil -> automatic selection again
			S.PreviewMusic("Lobby")
			world.advance(0.3)
			now = S.NowPlaying()
			T.eq(fmt(now.Preview, now.Key, now.Id), fmt(true, "Lobby", id(301)), "preview Lobby")
			world.setRound("Phase", "Round")
			T.eq(S.NowPlaying().Key, "Lobby", "the preview survives round changes")
			S.PreviewMusic(nil)
			world.advance(0.3)
			now = S.NowPlaying()
			T.eq(fmt(now.Preview, now.Key, now.Id), fmt(false, "Theme_FellSans", id(102)), "automatic again")

			-- no answer within PROBE_TIMEOUT -> bad (warned); a late Success makes it good again
			S.PreviewMusic("Theme_ClassicSans")
			world.advance(S.PROBE_TIMEOUT + 0.5)
			T.eq(S.Status("Theme_ClassicSans"), "dead", "timed out")
			T.eq(world.count(world.warnings, id(601) .. " (Theme_ClassicSans) - no answer"), 1, "timeout warned")
			world.release(id(601), "Success")
			world.advance(0.3)
			T.eq(S.Status("Theme_ClassicSans"), "ok", "late answer")
			T.eq(S.NowPlaying().Id, id(601), "plays after the late answer")
			T.eq(world.count(world.prints, id(601)), 1, "late answer printed")

			-- TimeLength 0: PreloadAsync said Success but the deck loads an empty asset -> the next candidate
			S.PreviewMusic("VerdictBox")
			world.advance(0.5)
			T.eq(S.IdState(id(701)), "bad", "IsLoaded with TimeLength 0 = bad")
			T.eq(world.count(world.warnings, id(701) .. " (VerdictBox) - empty audio"), 1, "empty asset warned")
			T.eq(S.NowPlaying().Id, id(702), "next candidate plays")
			S.PreviewMusic(nil)
			world.advance(0.3)

			-- the background batch (PROBE_BATCH_DELAY after Start) checked the short sounds
			T.eq(S.Status("Dash"), "ok", "background: Dash checked")
			T.eq(S.Status("Teleport"), "ok", "background: Teleport's second candidate")
			T.eq(S.IdState(id(902)), "bad", "background: 902 failed")
			-- the unchecked Shot id never loads: caught by the first-play watchdog after LOAD_TIMEOUT
			world.advance(S.LOAD_TIMEOUT)
			T.eq(S.Status("Shot"), "dead", "an id whose Sound never loads is bad")
			T.eq(S.NowPlaying().Id, id(102), "music unaffected by the long wait")

			-- every id probed once, every bad id warned once, nothing else warned (no runtime errors)
			local probes = {}
			for _, pid in world.preloads do
				probes[pid] = (probes[pid] or 0) + 1
			end
			for pid, n in probes do
				T.eq(n, 1, "probed once: " .. pid)
			end
			T.eq(probes[id(301)], 1, "lobby id probed")
			for _, n in { 101, 401, 601, 701, 801, 803, 902, 904 } do
				T.eq(world.count(world.warnings, "failed to load: " .. id(n) .. " "), 1, "warned once: " .. n)
			end
			local other = {}
			for _, w in world.warnings do
				if
					not string.find(w, "[Sound] audio id failed to load", 1, true)
					and not string.find(w, "[Sound] could not check", 1, true)
				then
					table.insert(other, w)
				end
			end
			T.eq(#other, 0, "no unexpected warnings: " .. table.concat(other, " | "))
		end)
	end,

	------------------------------------------------------------------------------ admin panel: TEST -> MUSIC
	admin_music_section = function(T, Loader)
		clientMode(Loader, function()
			local Themes = Loader.requirePath("src/client/UI/Themes")
			local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
			local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
			local Screen = Loader.requirePath("src/client/UI/Screens/Admin")
			local layout = UIRoot.ComputeLayout(Loader.roblox.Vector2.new(860, 400))
			local function find(root, name)
				for _, inst in root:GetDescendants() do
					if inst.Name == name then
						return inst
					end
				end
				return nil
			end
			local info = {
				Key = "Map_VoidRift_Final",
				Entry = "FinalPhase",
				Id = "rbxassetid://1234567890",
				Status = "ok",
				Index = 2,
				Count = 3,
				Preview = true,
				Playing = true,
			}
			local fakeSound = {
				NowPlaying = function()
					return info
				end,
				PreviewMusic = function() end,
			}
			local keys = { "Lobby", "VerdictBox", "FinalPhase" }
			for _, kitId in { "ClassicSans", "FellSans", "EclipseSans" } do
				table.insert(keys, "Theme_" .. kitId)
				table.insert(keys, "Theme_" .. kitId .. "_Final")
			end
			for _, lang in { "en", "ru" } do
				Strings.SetLanguage(lang)
				for _, theme in Themes.List() do
					local label = ("Admin music %s %s"):format(theme.Id, lang)
					local handle = Screen.Create(theme, { Layout = layout, Tab = "Test", Sound = fakeSound })
					for _, key in keys do
						T.ok(find(handle.Root, "Music_" .. key) ~= nil, label .. ": preview button " .. key)
					end
					T.ok(find(handle.Root, "MusicStop") ~= nil, label .. ": stop button")
					local now = find(handle.Root, "MusicNow")
					local idLine = find(handle.Root, "MusicId")
					if T.ok(now ~= nil and idLine ~= nil, label .. ": status lines") then
						T.ok(
							string.find(now.Text, "Map_VoidRift_Final -> FinalPhase", 1, true) ~= nil
								and string.find(now.Text, Strings.L("admin.music.st.ok"), 1, true) ~= nil
								and string.find(now.Text, Strings.L("admin.music.preview"), 1, true) ~= nil,
							label .. ": key -> entry, mode and status: " .. now.Text
						)
						T.ok(
							string.find(idLine.Text, "rbxassetid://1234567890", 1, true) ~= nil
								and string.find(idLine.Text, "#2", 1, true) ~= nil,
							label .. ": id in use and its place: " .. idLine.Text
						)
					end
					-- phone touch targets: the music buttons are grid cells (TAP tall) or full-width TAP rows
					local minPx = math.ceil(44 / layout.Scale)
					for _, name in { "MusicStop", "Music_Lobby", "Music_Theme_FellSans" } do
						local btn = find(handle.Root, name)
						local parent = btn and btn.Parent
						local grid = parent and parent:FindFirstChildOfClass("UIGridLayout")
						local h = if grid then grid.CellSize.Y.Offset else (btn and btn.Size.Y.Offset or 0)
						T.ok(h >= minPx, ("%s: %s is >= 44 pt tall (%d)"):format(label, name, h))
					end
					handle.Destroy()
				end
			end
			-- without a SoundController (offline previews) the section still builds and says so
			Strings.SetLanguage("en")
			local handle = Screen.Create(Themes.Get("Classic"), { Layout = layout, Tab = "Test" })
			local now = find(handle.Root, "MusicNow")
			T.eq(now and now.Text, Strings.L("admin.music.off"), "no sound controller")
			handle.Destroy()
			info = { Key = nil, Status = "empty", Count = 0, Preview = false }
			local silent = Screen.Create(Themes.Get("Void"), { Layout = layout, Tab = "Test", Sound = fakeSound })
			local line = find(silent.Root, "MusicNow")
			T.ok(
				line and string.find(line.Text, Strings.L("admin.music.none"), 1, true) ~= nil,
				"automatic, nothing requested -> silence"
			)
			silent.Destroy()
		end)
	end,
}

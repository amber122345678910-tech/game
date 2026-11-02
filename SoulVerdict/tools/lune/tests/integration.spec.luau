--!nocheck
-- Cross-module integration contracts that can be checked offline (docs/INTEGRATION.md).
-- Text-level checks read the sources with @lune/fs (sender vs receiver names: AbilityFx phases, RoundEvents,
-- Request actions, Style Lab actions, settings keys, RoundState attributes, phase names); behaviour checks load
-- the real modules through the Lune harness (leaderboard format, revive prompt rule, collapse ring frames).
-- Each allow-list below documents a deliberate exception — extend it consciously, never to silence drift.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local SHARED = "ReplicatedStorage.Shared."

------------------------------------------------------------------------------------------------- helpers

local function read(path: string): string
	return fs.readFile(path)
end

local function luauFiles(dir: string, out: { string }?): { string }
	local list = out or {}
	if not fs.isDir(dir) then
		return list
	end
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, list)
		elseif string.find(name, "%.luau$") then
			table.insert(list, path)
		end
	end
	return list
end

-- Removes `--` comments (keeps strings intact well enough for these scans: no `--` inside our string literals).
local function code(src: string): string
	local lines = {}
	for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
		local cut = string.find(line, "%-%-")
		table.insert(lines, if cut then string.sub(line, 1, cut - 1) else line)
	end
	return table.concat(lines, "\n")
end

-- Top-level `<prefix>.<Name> = function` blocks: body up to the first column-0 `end`.
local function blocks(src: string, prefix: string): { [string]: string }
	local out = {}
	local current, buf = nil, nil
	for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
		if current == nil then
			local name = string.match(line, "^" .. prefix .. "%.([%w_]+)%s*=%s*function")
			if name then
				current = name
				buf = {}
			end
		elseif string.match(line, "^end") then
			out[current] = table.concat(buf, "\n")
			current = nil
		else
			table.insert(buf, line)
		end
	end
	return out
end

local function keys(set: { [string]: any }): string
	local list = {}
	for k in set do
		table.insert(list, k)
	end
	table.sort(list)
	return table.concat(list, ",")
end

local function scan(files: { string }, patterns: { string }, filter: ((string, string) -> boolean)?): { [string]: string }
	local found = {}
	for _, path in files do
		local src = code(read(path))
		if filter == nil or filter(path, src) then
			for _, pattern in patterns do
				for name in string.gmatch(src, pattern) do
					found[name] = found[name] or path
				end
			end
		end
	end
	return found
end

------------------------------------------------------------------------------------------- AbilityFx phases

-- Phases a server ability broadcasts (besides AbilityService's automatic "Start").
local function serverPhases(body: string): { [string]: boolean }
	local set = {}
	for phase in string.gmatch(body, 'ctx:Fx%(%s*"([%w_]+)"') do
		set[phase] = true
	end
	if string.find(body, "Common.ComboStrike", 1, true) then
		set.Strike = true
	end
	if string.find(body, "Common.DashStrike", 1, true) then
		set.Dash = true
	end
	if string.find(body, "ctx:Teleport", 1, true) then
		set.Teleport = true -- CastContext:Teleport sends Fx "Teleport" {from, to}
	end
	return set
end

local function clientPhases(body: string): { [string]: boolean }
	local set = {}
	for phase in string.gmatch(body, 'phase%s*[=~]=%s*"([%w_]+)"') do
		set[phase] = true
	end
	return set
end

-- Phases sent outside the ability's own handler (passive hooks using AbilityService.ContextFor(model, abilityId)).
local OUT_OF_BLOCK = {
	Determination = { Afterimage = { "Counter" } },
}
-- Phases with no client kit handler on purpose.
local ALLOW_UNHANDLED = {
	ClassicSans = { BoneWall = { Wall = "the wall is a BoneLine hazard drawn by HazardVisuals" } },
	Determination = {},
}
local REFERENCE_KITS = { ClassicSans = "Monsters", Determination = "Humans" }

local function checkKitPhases(T, Loader, kitId: string)
	local Kits = Loader.require(SHARED .. "Kits")
	local serverSrc = code(read("src/server/Kits/" .. kitId .. ".luau"))
	local clientSrc = code(read("src/client/Kits/" .. kitId .. ".luau"))
	local server = blocks(serverSrc, "Abilities")
	local client = blocks(clientSrc, "Effects")
	T.ok(next(server) ~= nil, kitId .. ": no server Abilities.* handlers found")
	T.ok(next(client) ~= nil, kitId .. ": no client Effects.* handlers found")
	local sent: { [string]: { [string]: boolean } } = {}
	for abilityId, body in server do
		T.ok(Kits.Ability(kitId, abilityId) ~= nil, kitId .. ": server handler for unknown ability " .. abilityId)
		sent[abilityId] = serverPhases(body)
	end
	for abilityId, phases in (OUT_OF_BLOCK[kitId] or {}) do
		sent[abilityId] = sent[abilityId] or {}
		for _, phase in phases do
			T.ok(
				string.find(serverSrc, 'ctx:Fx%(%s*"' .. phase .. '"') ~= nil,
				kitId .. ": OUT_OF_BLOCK phase " .. phase .. " is no longer sent (update the table)"
			)
			sent[abilityId][phase] = true
		end
	end
	for abilityId, phases in sent do
		local handled = if client[abilityId] then clientPhases(client[abilityId]) else {}
		local allowed = (ALLOW_UNHANDLED[kitId] or {})[abilityId] or {}
		for phase in phases do
			T.ok(
				handled[phase] == true or allowed[phase] ~= nil,
				("%s.%s: server sends phase %q but the client kit has no handler (handled: %s)"):format(
					kitId,
					abilityId,
					phase,
					keys(handled)
				)
			)
		end
	end
	for abilityId, body in client do
		T.ok(Kits.Ability(kitId, abilityId) ~= nil, kitId .. ": client Effects for unknown ability " .. abilityId)
		local phases = sent[abilityId] or {}
		for phase in clientPhases(body) do
			T.ok(
				phase == "Start" or phases[phase] == true,
				("%s.%s: client handles phase %q that the server never sends (sent: %s)"):format(
					kitId,
					abilityId,
					phase,
					keys(phases)
				)
			)
		end
	end
	-- every active ability in the kit data has a server handler (or the generic M1 ComboStrike fallback)
	local kit = Kits.Get(kitId)
	for _, ability in kit.Abilities do
		if ability.Slot ~= nil and ability.Passive ~= true then
			local fallback = ability.Slot == "M1" and type(ability.Numbers) == "table" and ability.Numbers.Damage1 ~= nil
			T.ok(server[ability.Id] ~= nil or fallback, kitId .. ": no server handler for " .. ability.Id)
		end
	end
end

------------------------------------------------------------------------------------------------------ tests

return {
	integration_reference_kit_phases_match = function(T, Loader)
		for kitId in REFERENCE_KITS do
			checkKitPhases(T, Loader, kitId)
		end
	end,

	integration_round_events_have_consumers = function(T, _Loader)
		local serverFiles = luauFiles("src/server")
		local clientFiles = luauFiles("src/client")
		local fired = scan(serverFiles, {
			'fireRoundEvent%(%s*"([%w_]+)"',
			'"RoundEvent",%s*[%w_.]+,%s*"([%w_]+)"',
			'FireAll%(%s*"RoundEvent",%s*"([%w_]+)"',
		})
		local listened = scan(clientFiles, { 'OnRoundEvent%(%s*"([%w_]+)"' })
		local matched = scan(clientFiles, { 'name%s*==%s*"([%w_]+)"' }, function(_path, src)
			return string.find(src, "RoundEvent", 1, true) ~= nil
		end)
		for _, name in { "PhaseChanged", "MapVote", "MonsterChosen", "Intro", "Kill", "RoundEnd", "Rewards" } do
			T.ok(fired[name] ~= nil, "server never fires RoundEvent " .. name .. " (SPEC §4.2)")
		end
		for name, path in fired do
			T.ok(
				listened[name] ~= nil or matched[name] ~= nil,
				("RoundEvent %q (fired in %s) has no client consumer"):format(name, path)
			)
		end
		for name, path in listened do
			T.ok(fired[name] ~= nil, ("%s listens to RoundEvent %q that the server never fires"):format(path, name))
		end
	end,

	integration_request_actions_are_registered = function(T, _Loader)
		local serverFiles = luauFiles("src/server")
		local registered = scan(serverFiles, { 'Register%(%s*"([%w_]+)"', 'Register,%s*"([%w_]+)"' })
		-- RoundService registers through a table literal: { Vote = onVote, StartPractice = ... }
		local round = code(read("src/server/Services/RoundService.luau"))
		local tbl = string.match(round, "for action, handler in (%b{})")
		T.ok(tbl ~= nil, "RoundService request table not found")
		for name in string.gmatch(tbl or "", "([%w_]+)%s*=%s*on") do
			registered[name] = "src/server/Services/RoundService.luau"
		end
		local sent = scan(luauFiles("src/client"), {
			'Request%(%s*d,%s*"([%w_]+)"',
			'State%.Request,%s*"([%w_]+)"',
			'%.Request%(%s*"([%w_]+)"',
			'Fire%(%s*"Request",%s*"([%w_]+)"',
		})
		T.ok(next(sent) ~= nil, "no client Request actions found (scan patterns are stale)")
		for name, path in sent do
			T.ok(registered[name] ~= nil, ("%s sends Request %q but no server service registers it"):format(path, name))
		end
		for _, name in { "EquipKit", "EquipSkin", "Buy", "ClaimQuest", "RerollQuest", "SetSetting", "SetRolePref", "SetTitle", "Vote", "StartPractice", "TryKit", "StyleLab" } do
			T.ok(registered[name] ~= nil, "SPEC §17 request action not registered: " .. name)
		end
	end,

	integration_stylelab_actions_exist = function(T, _Loader)
		local server = code(read("src/server/Services/StyleLabService.luau"))
		local actions = {}
		for name in string.gmatch(server, "\n\t([%w_]+) = function%(") do
			actions[name] = true
		end
		local client = code(read("src/client/UI/Screens/StyleLab.luau"))
		local count = 0
		for name in string.gmatch(client, 'action%s*=%s*"([%w_]+)"') do
			count += 1
			T.ok(actions[name] == true, "Style Lab button sends unknown action " .. name .. " (server: " .. keys(actions) .. ")")
		end
		T.ok(count > 0, "no Style Lab actions found in the screen")
	end,

	integration_settings_keys_are_whitelisted = function(T, Loader)
		local ProfileSchema = Loader.require(SHARED .. "Progression.ProfileSchema")
		local specs = ProfileSchema.Settings()
		local screen = code(read("src/client/UI/Screens/Settings.luau"))
		local shown = 0
		for name in string.gmatch(screen, '%a+%(content,%s*"([%w_]+)"') do
			shown += 1
			T.ok(specs[name] ~= nil, "Settings screen edits " .. name .. " which ProfileSchema does not whitelist")
		end
		T.ok(shown >= 10, "Settings screen scan found too few keys")
		-- keys controllers read: whitelisted, or a documented local-only default (never persisted, no UI yet)
		local LOCAL_ONLY = { QuickCast = true, InvertY = true, CameraSensitivity = true }
		local read = scan(luauFiles("src/client/Controllers"), {
			'State%.Setting,%s*"([%w_]+)"',
			'[%.:]Setting%(%s*"([%w_]+)"',
			'setting%(%s*"([%w_]+)"',
		})
		for name, path in read do
			T.ok(
				specs[name] ~= nil or LOCAL_ONLY[name] == true,
				("%s reads setting %q that the server whitelist (ProfileSchema.Settings) does not know"):format(path, name)
			)
		end
		T.ok(read.Sensitivity ~= nil, "CameraController must read the whitelisted Sensitivity key")
	end,

	integration_roundstate_attributes_exist = function(T, _Loader)
		local round = code(read("src/server/Services/RoundService.luau"))
		local defaults = string.match(round, "local STATE_DEFAULTS[^=]*= (%b{})")
		T.ok(defaults ~= nil, "RoundService STATE_DEFAULTS not found")
		local known = { GraphicsPreset = true, FinalPreset = true, LobbyPreset = true }
		for name in string.gmatch(defaults or "", "([%w_]+)%s*=") do
			known[name] = true
		end
		for _, name in { "Phase", "PhaseEndsAt", "MapId", "VoteOptions", "MonsterUserId", "MonsterKit", "HumansAlive", "HumansTotal", "SavesLit", "SavesTotal", "FinalPhase", "Winner", "WinReason", "Practice", "TeamRevives", "CollapseRadius", "CollapseCenter" } do
			T.ok(known[name] == true, "SPEC §4.1 RoundState attribute missing from STATE_DEFAULTS: " .. name)
		end
		local files = {
			"src/client/UI/Hud/Data.luau",
			"src/client/Controllers/SoundController.luau",
			"src/client/Controllers/CollapseController.luau",
			"src/client/Controllers/GraphicsController.luau",
		}
		local used = scan(files, { "round%.([A-Z][%w_]+)", 'rs:GetAttribute%(%s*"([%w_]+)"' })
		for name, path in used do
			T.ok(known[name] == true, ("%s reads RoundState.%s which the server never sets"):format(path, name))
		end
	end,

	integration_phase_names_are_valid = function(T, _Loader)
		local PHASES = { Waiting = true, Intermission = true, Intro = true, Round = true, Collapse = true, Ending = true }
		-- round-phase comparisons only: State.Phase() / phase() calls, <snapshot>.Phase fields, PhaseChanged data
		local used = scan(luauFiles("src/client"), {
			'[Pp]hase%(%)%s*[=~]=%s*"([%w_]+)"',
			'[%w_]%.Phase%s*[=~]=%s*"([%w_]+)"',
			'newPhase%s*[=~]=%s*"([%w_]+)"',
		}, function(path, _src)
			-- hazard / VFX / kit files compare their own animation phases (blaster pose "Charge", ...)
			return string.find(path, "HazardVisuals", 1, true) == nil
				and string.find(path, "/VFX/", 1, true) == nil
				and string.find(path, "/Kits/", 1, true) == nil
		end)
		T.ok(next(used) ~= nil, "phase scan found nothing (patterns are stale)")
		for name, path in used do
			T.ok(PHASES[name] == true, ("%s compares the round phase with unknown name %q"):format(path, name))
		end
	end,

	integration_leaderboard_stringvalue_format = function(T, Loader)
		local State = Loader.require(CLIENT .. "Controllers.StateController")
		local root = Instance.new("Folder")
		root.Name = "Leaderboards"
		local wins = Instance.new("StringValue")
		wins.Name = "Wins"
		-- exactly what LeaderboardService.publish writes
		wins.Value = '[{"rank":1,"userId":1,"name":"Sans","value":12},{"rank":2,"userId":2,"name":"Frisk","value":7}]'
		wins.Parent = root
		local rows = State.ReadBoard(root, "Wins")
		T.eq(#rows, 2, "rows parsed from the StringValue JSON")
		T.eq(rows[1] and rows[1].name, "Sans")
		T.eq(rows[1] and rows[1].value, 12)
		T.eq(#State.ReadBoard(root, "Level"), 0, "missing board -> empty list")
		root:SetAttribute("Level", '[{"name":"Papyrus","value":20}]')
		local level = State.ReadBoard(root, "Level")
		T.eq(level[1] and level[1].name, "Papyrus", "attribute JSON format still supported")
		local boards = code(read("src/server/Services/LeaderboardService.luau"))
		T.ok(string.find(boards, 'Instance.new("StringValue")', 1, true) ~= nil, "LeaderboardService format changed")
	end,

	integration_revive_prompt_visibility = function(T, Loader)
		local Prompt = Loader.require(CLIENT .. "Controllers.PromptController")
		local function character(team: string, opts: any?)
			local m = Instance.new("Model")
			m:SetAttribute("Team", team)
			m:SetAttribute("Dead", opts and opts.Dead or false)
			m:SetAttribute("Downed", opts and opts.Downed or false)
			m.Parent = Instance.new("Folder")
			return m
		end
		local victim = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = victim
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RevivePrompt"
		prompt:SetAttribute("HumansOnly", true)
		prompt:SetAttribute("VictimUserId", 42)
		prompt.Parent = root
		T.eq(Prompt.Eligible(prompt, character("Humans"), 7), true, "an up ally sees the prompt")
		T.eq(Prompt.Eligible(prompt, character("Monster"), 7), false, "the monster never sees it (G = its ultimate)")
		T.eq(Prompt.Eligible(prompt, character("Humans", { Downed = true }), 7), false, "downed allies cannot revive")
		T.eq(Prompt.Eligible(prompt, character("Humans", { Dead = true }), 7), false, "dead allies cannot revive")
		T.eq(Prompt.Eligible(prompt, character("Humans"), 42), false, "the victim does not see its own prompt")
		T.eq(Prompt.Eligible(prompt, nil, 7), false, "no character -> hidden")
		-- the server contract the controller relies on
		local cs = code(read("src/server/Services/CharacterService.luau"))
		for _, needle in { '"RevivePrompt"', '"HumansOnly"', '"VictimUserId"', '"ActionKey"', '"ObjectKey"' } do
			T.ok(string.find(cs, needle, 1, true) ~= nil, "CharacterService revive prompt contract changed: " .. needle)
		end
	end,

	integration_collapse_ring_frames = function(T, Loader)
		local Collapse = Loader.require(CLIENT .. "Controllers.CollapseController")
		local center = Vector3.new(10, 2, -5)
		local frames = Collapse.SegmentFrames(center, 30, 16, 40)
		T.eq(#frames, 16)
		for _, cf in frames do
			local p = cf.Position
			local flat = Vector3.new(p.X - center.X, 0, p.Z - center.Z)
			T.near(flat.Magnitude, 30, 1e-3, "segment on the safe radius")
			T.near(p.Y, center.Y + 20, 1e-3, "segment centred at half height")
			T.near(cf.LookVector:Dot(-flat.Unit), 1, 1e-3, "segment faces the ring centre")
			T.near(cf.UpVector.Y, 1, 1e-3, "segment upright")
			T.near(cf.RightVector:Cross(cf.UpVector):Dot(-cf.LookVector), 1, 1e-3, "right-handed basis")
		end
		local round = code(read("src/server/Services/RoundService.luau"))
		T.ok(string.find(round, 'setState("CollapseRadius"', 1, true) ~= nil, "RoundService no longer drives CollapseRadius")
	end,

	integration_intro_freeze_is_not_stun = function(T, _Loader)
		local round = code(read("src/server/Services/RoundService.luau"))
		local body = string.match(round, "local function freeze%(.-\nend")
		T.ok(body ~= nil, "RoundService.freeze not found")
		T.ok(string.find(body or "", '"Stunned"', 1, true) == nil, "intro freeze must not use Stunned (stun stars / dizzy pose)")
		T.ok(string.find(body or "", '"Rooted"', 1, true) ~= nil, "intro freeze roots the characters")
	end,

	integration_cast_clips_single_owner = function(T, _Loader)
		local fx = code(read("src/client/Controllers/FxController.luau"))
		T.ok(
			string.find(fx, '"AnimController", "MarkPredicted"', 1, true) ~= nil,
			"FxController.MarkPredicted must forward to AnimController.MarkPredicted (AnimController plays echo clips)"
		)
		local anim = code(read("src/client/Controllers/AnimController.luau"))
		T.ok(string.find(anim, "function AnimController.MarkPredicted", 1, true) ~= nil, "AnimController.MarkPredicted missing")
		T.ok(string.find(anim, "function AnimController.PlayAbility", 1, true) ~= nil, "AnimController.PlayAbility missing")
	end,
}

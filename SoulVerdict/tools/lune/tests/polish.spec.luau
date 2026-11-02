--!nocheck
-- Gameplay & UX polish pass: blaster skullScale (+ Fell's huge Crimson Blaster), invisible humans skipped by every
-- targeting path, the shared leap arc constant, emotes (EmoteService rules, Hud/EmoteWheel, the input context),
-- QuickCast / InvertY settings and the hold-to-aim cast modes, the predicted dash clip wiring, the lobby
-- MenuCamera drift, lobby look / music / camera for players who are not round participants, and the MapKit house
-- side windows facing out. Pure helpers run directly; runtime wiring is pinned by source scans.
-- Run: lune run tools/lune/run_tests.luau polish
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local SERVER = "ServerScriptService.Server."
local SHARED = "ReplicatedStorage.Shared."

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

-- runs fn with a fake global `workspace` (server time = t), always restoring the previous one
local function withServerTime(Loader, t, fn)
	local G = getfenv(Loader.requirePath)
	local before = G.workspace
	G.workspace = {
		GetServerTimeNow = function()
			return t
		end,
	}
	local ok, err = pcall(fn)
	G.workspace = before
	if not ok then
		error(err, 0)
	end
end

local function read(path)
	return fs.readFile(path)
end

-- source text of `function <name>` up to the next top-level `function` / `Abilities.` definition
local function body(source, header)
	local start = string.find(source, header, 1, true)
	if start == nil then
		return ""
	end
	local stop = string.find(source, "\nAbilities%.", start + #header)
		or string.find(source, "\nfunction ", start + #header)
	return string.sub(source, start, stop or #source)
end

local function xExtent(model)
	local minX, maxX = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf, s = d.CFrame, d.Size
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local x = (cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)).X
						minX = math.min(minX, x)
						maxX = math.max(maxX, x)
					end
				end
			end
		end
	end
	return if maxX > minX then maxX - minX else 0
end

local function model(attrs)
	local m = Instance.new("Model")
	for k, v in attrs do
		m:SetAttribute(k, v)
	end
	return m
end

return {
	------------------------------------------------------------------------------------------ 1. skull scale
	polish_blaster_skull_scale = function(T, Loader)
		local HV = load(Loader, CLIENT .. "Controllers.HazardVisuals")
		T.near(HV.SkullScale({ width = 5 }, 2.5), HV.BlasterScale(5, 2.5), 1e-9, "no skullScale: width-derived")
		T.near(HV.SkullScale({ width = 3.5, skullScale = 3 }, 3), 3, 1e-9, "explicit skull scale wins")
		T.near(HV.SkullScale({ width = 3.5, skullScale = 99 }, 3), 8, 1e-9, "clamped to the max")
		T.near(HV.SkullScale({ width = 5, skullScale = -1 }, 2.5), HV.BlasterScale(5, 2.5), 1e-9, "invalid = ignored")
		-- the offline snapshot honours it: a huge skull around the same narrow beam
		local origin = CFrame.new(0, 5, 0)
		local base = { origin = origin, width = 3.5, length = 40, delay = 0.45, duration = 0.35, style = "Fell" }
		local huge = table.clone(base)
		huge.skullScale = 3
		local function skullWidth(params)
			local snap = HV.Snapshot("BlasterBeam", params, 0.3)
			for _, child in snap:GetChildren() do
				if child:IsA("Model") then
					return xExtent(child)
				end
			end
			return 0
		end
		local normalW, hugeW = skullWidth(base), skullWidth(huge)
		T.ok(normalW > 2, "normal skull drawn (" .. normalW .. ")")
		T.ok(hugeW > normalW * 1.8 and hugeW > 7, ("huge skull %.2f vs %.2f studs"):format(hugeW, normalW))
		-- camera occlusion fade
		T.near(
			HV.SkullOcclusion(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 0, -1), 5, false),
			1,
			1e-9,
			"inside"
		)
		T.near(HV.SkullOcclusion(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 0, -40), 5, false), 0, 1e-9, "far")
		local ahead = Vector3.new(0, 0, -9) -- in front of the camera, outside 1.6 radii
		T.near(
			HV.SkullOcclusion(Vector3.zero, Vector3.new(0, 0, -1), ahead, 5, false),
			0,
			1e-9,
			"enemy skull in view stays"
		)
		T.ok(
			HV.SkullOcclusion(Vector3.zero, Vector3.new(0, 0, -1), ahead, 5, true) > 0.9,
			"own skull covering the view fades"
		)
	end,

	polish_fell_crimson_huge_skull = function(T, Loader)
		local server = load(Loader, SERVER .. "Kits.FellSans")
		local client = load(Loader, CLIENT .. "Kits.FellSans")
		local s = server.Constants.CrimsonSkullScale
		T.ok(type(s) == "number" and s >= 2.5, "huge skull scale")
		T.eq(client.Constants.CrimsonSkullScale, s, "client indicator ghost uses the same skull scale")
		local N = load(Loader, SHARED .. "Kits").Ability("FellSans", "CrimsonBlaster").Numbers
		local HV = load(Loader, CLIENT .. "Controllers.HazardVisuals")
		T.ok(
			HV.SkullScale({ width = N.Width, skullScale = s }, 3) > HV.BlasterScale(N.Width, 3) * 1.8,
			"far bigger than width-derived"
		)
		local fn = body(read("src/server/Kits/FellSans.luau"), "Abilities.CrimsonBlaster = function")
		T.ok(string.find(fn, "skullScale = C.CrimsonSkullScale", 1, true) ~= nil, "CrimsonBlaster passes skullScale")
		local HazardDefs = load(Loader, SHARED .. "Combat.HazardDefs")
		T.ok(
			HazardDefs.Validate("BlasterBeam", { origin = CFrame.new(), skullScale = s }),
			"skullScale is valid plain data"
		)
	end,

	------------------------------------------------------------------------------------- 2. invisible humans
	polish_invisible_humans_are_untargetable = function(T, Loader)
		local Combat = load(Loader, CLIENT .. "Controllers.CombatController")
		T.ok(Combat.IsHidden(model({ Invisible = true }), 10), "attribute")
		T.ok(Combat.IsHidden(model({ Status_Invisible = 12 }), 10), "active status")
		T.ok(not Combat.IsHidden(model({ Status_Invisible = 8 }), 10), "expired status")
		T.ok(not Combat.IsHidden(model({}), 10), "visible")
		-- monster bots (globals resolve at load time under Lune: park `workspace` first)
		withServerTime(Loader, 100, function()
			local Bots = load(Loader, SERVER .. "Services.BotService")
			T.ok(Bots.IsInvisible(model({ Invisible = true })), "bot: attribute")
			T.ok(Bots.IsInvisible(model({ Status_Invisible = 101 })), "bot: status")
			T.ok(not Bots.IsInvisible(model({ Status_Invisible = 99 })), "bot: expired")
		end)
		local bots = read("src/server/Services/BotService.luau")
		local think = body(bots, "local function thinkMonster")
		T.ok(select(2, string.gsub(think, "not isInvisible%(m%)", "")) >= 2, "monster brain filters both target picks")
		-- Verdict Box: pure rule + the service and AbilityService pre-check
		local VBS = load(Loader, SERVER .. "Services.VerdictBoxService")
		local m = { team = "Monster", up = true, pos = Vector3.zero, look = Vector3.new(0, 0, -1) }
		local v = { team = "Humans", up = true, pos = Vector3.new(0, 0, -10) }
		T.ok(VBS.Rules.CheckPair(m, v, true), "visible victim can be boxed")
		v.invisible = true
		local ok, reason = VBS.Rules.CheckPair(m, v, true)
		T.ok(not ok and reason == "invisible", "invisible victim refused")
		T.ok(
			string.find(read("src/server/Services/VerdictBoxService.luau"), "invisible = victim:GetAttribute", 1, true)
				~= nil,
			"Open passes it"
		)
		local ability = read("src/server/Services/AbilityService.luau")
		T.ok(
			string.find(body(ability, "local function castVerdictBox"), "isInvisible(m)", 1, true) ~= nil,
			"Verdict pre-check"
		)
		T.ok(
			string.find(body(ability, "local function autoTarget"), "not isInvisible(m)", 1, true) ~= nil,
			"auto target"
		)
		T.ok(
			string.find(body(ability, "local function validTarget"), "isInvisible(target)", 1, true) ~= nil,
			"explicit target"
		)
		-- nameplates
		local Plates = load(Loader, CLIENT .. "UI.Hud.Nameplates")
		local enemy = { Team = "Humans", Invisible = true }
		T.eq(Plates.Visibility(enemy, "Monster", 0), "Hidden", "the monster sees nothing")
		T.eq(Plates.Visibility(enemy, "Humans", 0), "Ghost", "allies see a faded plate")
		T.eq(
			Plates.Visibility({ Team = "Humans", Statuses = { Invisible = 5 } }, "Monster", 4),
			"Hidden",
			"status-based"
		)
		T.eq(Plates.Visibility({ Team = "Humans", Statuses = { Invisible = 5 } }, "Monster", 6), "Plate", "expired")
		T.eq(Plates.Visibility({ Team = "Humans" }, "Monster", 0), "Plate", "visible enemy")
		local Themes = Loader.requirePath("src/client/UI/Themes")
		local Style = Loader.requirePath("src/client/UI/Hud/Style")
		for _, hud in { "Battle", "Modern" } do
			local ghost = Plates.BuildGhost(Style.Resolve(Themes.Get("Classic"), hud))
			ghost.Set({ Name = "Frisk" })
			T.ok(#ghost.Root:GetDescendants() >= 2, "ghost plate builds " .. hud)
		end
	end,

	----------------------------------------------------------------------------------------- 3. leap constant
	polish_leap_arc_constant_shared = function(T, Loader)
		local Config = load(Loader, SHARED .. "Config")
		local k = Config.Human.LeapArcFactor
		T.ok(type(k) == "number" and k > 0, "Config.Human.LeapArcFactor")
		local Movement = load(Loader, CLIENT .. "Controllers.MovementController")
		T.eq(Movement.Tuning.ImpulseDecay, k, "client mover reads it")
		local bravery = read("src/server/Kits/Bravery.luau")
		T.ok(
			string.find(bravery, "IMPULSE_DECAY: number = Config.Human.LeapArcFactor", 1, true) ~= nil,
			"server leap reads it"
		)
		T.ok(string.find(bravery, "IMPULSE_DECAY = 1.6", 1, true) == nil, "no duplicated literal left")
	end,

	---------------------------------------------------------------------------------------------- 4. emotes
	polish_emote_service_rules = function(T, Loader)
		local E = load(Loader, SERVER .. "Services.EmoteService")
		local Config = load(Loader, SHARED .. "Config")
		local skeleton, human = E.Allowed("Skeleton"), E.Allowed("Human")
		T.ok(table.find(skeleton, "Wink") ~= nil and table.find(human, "Wink") == nil, "Wink is a skeleton extra")
		for _, clip in { "Emote_Wave", "Emote_Shrug", "Emote_Sit", "Emote_Laugh" } do
			T.ok(table.find(human, clip) ~= nil and table.find(skeleton, clip) ~= nil, "common " .. clip)
		end
		-- every allowed clip exists in that family's clip library (AnimController plays it by name)
		for family, list in { Human = human, Skeleton = skeleton } do
			local lib = Loader.require(SHARED .. "Anim.Clips." .. family)
			for _, clip in list do
				T.ok(type(lib[clip]) == "table", family .. " clip " .. clip)
			end
		end
		T.eq(E.ParseClip("Emote_Wave"), "Emote_Wave")
		T.eq(E.ParseClip({ clip = "Emote_Sit" }), "Emote_Sit")
		T.eq(E.ParseClip({ Clip = "" }), "", "stop")
		T.eq(E.ParseClip(5), nil, "malformed")
		T.eq(E.ParseClip(string.rep("x", 40)), nil, "too long")
		local cd = Config.Emote.Cooldown
		local base = { Family = "Human", Team = "Humans", Up = true, Locked = false }
		T.ok(E.Validate(base, "Emote_Wave", 10), "free human in a match")
		T.eq(select(2, E.Validate(base, "Wink", 10)), "badClip", "family extra only for its family")
		T.eq(select(2, E.Validate(base, "Hack", 10)), "badClip", "unknown clip")
		local locked = table.clone(base)
		locked.Locked = true
		T.eq(select(2, E.Validate(locked, "Emote_Wave", 10)), "busy", "combat-locked in a match")
		locked.Team = "Lobby"
		T.ok(E.Validate(locked, "Emote_Wave", 10), "the lobby always allows it")
		local down = table.clone(base)
		down.Up = false
		T.eq(select(2, E.Validate(down, "Emote_Wave", 10)), "down", "downed / dead")
		local recent = table.clone(base)
		recent.LastAt = 10 - cd / 2
		T.eq(select(2, E.Validate(recent, "Emote_Wave", 10)), "cooldown", "cooldown")
		recent.LastAt = 10 - cd - 0.01
		T.ok(E.Validate(recent, "Emote_Wave", 10), "after the cooldown")
		T.ok(E.Validate(down, "", 10), "stopping is always fine")
		-- ending
		local still = { Up = true, Locked = false, Speed = 0, Airborne = false }
		T.eq(E.EndReason(still, 20, 10), nil, "keeps playing")
		T.eq(E.EndReason(still, 20, 21), "finished", "clip over")
		T.eq(E.EndReason({ Up = true, Speed = Config.Emote.MoveSpeed + 1 }, 20, 10), "moved", "walking cancels")
		T.eq(E.EndReason({ Up = true, Speed = 0, Airborne = true }, 20, 10), "jumped", "jumping cancels")
		T.eq(E.EndReason({ Up = true, Locked = true }, 20, 10), "locked", "attacks / blocks / stuns cancel")
		T.eq(E.EndReason({ Up = false }, 20, 10), "down", "downed")
		-- durations: loops last MaxLoopTime, one-shots their clip length
		T.eq(E.Duration("Human", "Emote_Wave"), Config.Emote.MaxLoopTime, "looping wave")
		local shrug = Loader.require(SHARED .. "Anim.Clips.Human").Emote_Shrug
		T.near(E.Duration("Human", "Emote_Shrug"), shrug.Length + 0.1, 1e-6, "one-shot shrug")
		T.ok(E.Duration("Skeleton", "Wink") < 1.5, "wink is short")
		-- registered with RequestService + rate gap
		T.ok(
			string.find(read("src/server/Services/EmoteService.luau"), 'RequestService.Register, "Emote"', 1, true)
				~= nil,
			"Request action"
		)
		T.ok(string.find(read("src/server/Services/RequestService.luau"), "Emote = 0.25", 1, true) ~= nil, "rate gap")
	end,

	polish_emote_wheel = function(T, Loader)
		local Strings = Loader.require(SHARED .. "Strings")
		Strings.SetLanguage("en")
		local Wheel = Loader.requirePath("src/client/UI/Hud/EmoteWheel")
		local E = load(Loader, SERVER .. "Services.EmoteService")
		for _, family in { "Human", "Skeleton" } do
			local options = Wheel.Options(family)
			local allowed = E.Allowed(family)
			T.eq(#options, #allowed, family .. ": wheel = server list")
			for i, o in options do
				T.eq(o.Clip, allowed[i], family .. " slot " .. i)
				T.ok(Strings.Has("hud.emote." .. o.Clip), "label " .. o.Clip)
			end
		end
		-- radial maths: every slot direction maps back to its slot, centre = none
		for n = 3, 9 do
			for i = 1, n do
				local p = Wheel.SlotPosition(i, n, 1)
				T.eq(Wheel.SlotAt(p, n), i, ("slot %d/%d"):format(i, n))
			end
		end
		T.eq(Wheel.SlotAt(Vector2.new(0, -1), 6), 1, "stick up = slot 1 (top)")
		T.eq(Wheel.SlotAt(Vector2.new(1, 0), 4), 2, "right = clockwise")
		T.eq(Wheel.SlotAt(Vector2.new(0.1, 0.1), 6), nil, "dead zone")
		-- builds in every theme / HUD style / layout, opens, picks
		local Themes = Loader.requirePath("src/client/UI/Themes")
		local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
		local Mock = Loader.requirePath("src/client/UI/Hud/Mock")
		local desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080))
		local phone = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390))
		for _, theme in Themes.List() do
			for _, hud in { "Battle", "Modern" } do
				for _, layout in { desktop, phone } do
					local label = ("%s %s %s"):format(theme.Id, hud, if layout.Phone then "phone" else "desktop")
					local ok, h =
						pcall(Wheel.Create, theme, { Hud = hud, Layout = layout, Open = true, Family = "Skeleton" })
					if T.ok(ok and h and h.Root, "wheel builds " .. label .. ": " .. tostring(h)) then
						T.ok(h.IsOpen(), "opened " .. label)
						local wheel = h.Root:FindFirstChild("Wheel")
						local slots = 0
						for _, c in wheel:GetChildren() do
							if string.sub(c.Name, 1, 4) == "Slot" then
								slots += 1
							end
						end
						T.eq(slots, #Wheel.Options("Skeleton"), "slots " .. label)
						h.Pick(1)
						T.ok(not h.IsOpen() and not wheel.Visible, "picking closes " .. label)
						h.Destroy()
					end
				end
			end
		end
		local h = Wheel.Create(Themes.Get("Classic"), { Hud = "Battle", Layout = desktop })
		for _, scenario in Mock.Names do
			T.noerror(function()
				h.Update(Mock.Scenario(scenario))
			end, "update " .. scenario)
		end
		h.Destroy()
		-- HUD integration
		local Hud = Loader.requirePath("src/client/UI/Hud")
		local found = false
		for _, entry in Hud.PIECES do
			found = found or entry.Name == "EmoteWheel"
		end
		T.ok(found, "mounted as a HUD piece")
		T.ok(Hud.Visible("EmoteWheel", Mock.Scenario("HumanRound")), "available in a round")
		T.ok(not Hud.Visible("EmoteWheel", Mock.Scenario("Dead")), "not while dead")
		local intro = Mock.Scenario("HumanRound")
		intro.Phase = "Intro"
		T.ok(not Hud.Visible("EmoteWheel", intro), "not during the intro")
	end,

	polish_emote_input_context = function(T, Loader)
		local Input = load(Loader, CLIENT .. "Controllers.InputController")
		T.ok(Input.SuppressingContexts.EmoteWheel == true, "wheel suppresses combat")
		T.ok(not Input.IsSuppressedBy("Emote", { EmoteWheel = 1 }), "its own key stays live")
		T.ok(Input.IsSuppressedBy("M1", { EmoteWheel = 1 }), "M1 suppressed while open")
		T.ok(Input.IsSuppressedBy("Emote", { EmoteWheel = 1, Menu = 1 }), "a menu on top suppresses it")
		T.ok(Input.IsSuppressedBy("Emote", { Menu = 1 }), "menus suppress the emote key")
		T.ok(type(Input.Cancelled) == "table" and type(Input.Cancelled.Connect) == "function", "Cancelled signal")
		T.ok(Input.CancelKeys.Escape and Input.CancelKeys.MouseButton2, "Esc / right-click cancel")
		local source = read("src/client/Controllers/InputController.luau")
		local release = body(source, "function InputController.ReleaseAll")
		local cancelAt = string.find(release, 'Cancelled:Fire("Release")', 1, true)
		local endAt = string.find(release, "forceEnd(action)", 1, true)
		T.ok(cancelAt ~= nil and endAt ~= nil and cancelAt < endAt, "forced releases cancel before the End events")
	end,

	-------------------------------------------------------------------------------------- 5. QuickCast / InvertY
	polish_quickcast_modes = function(T, Loader)
		local Combat = load(Loader, CLIENT .. "Controllers.CombatController")
		local mode = Combat.CastMode
		T.eq(mode({ Hold = { MaxTime = 1 }, Aim = "Direction" }, true), "Charge", "charges ignore QuickCast")
		T.eq(mode({ Hold = { MaxTime = 1 }, Aim = "Direction" }, false), "Charge")
		for _, aim in { "Direction", "Ground", "Target", "Ally" } do
			T.eq(mode({ Aim = aim, Slot = "Q" }, true), "Press", "quick cast " .. aim)
			T.eq(mode({ Aim = aim, Slot = "Q" }, false), "Aim", "hold to aim " .. aim)
		end
		T.eq(mode({ Aim = "Direction", Slot = "M1" }, false), "Press", "M1 always presses (combos)")
		T.eq(mode({ Aim = "Self", Slot = "R" }, false, false), "Press", "Self without an indicator")
		T.eq(mode({ Aim = "Self", Slot = "G" }, false, true), "Aim", "Self with a kit indicator previews")
		T.eq(Combat.QuickCast, true, "QuickCast defaults on")
		local Config = load(Loader, SHARED .. "Config")
		T.eq(Config.Defaults.QuickCast, true, "Config default QuickCast")
		T.eq(Config.Defaults.InvertY, false, "Config default InvertY")
		local Schema = load(Loader, SHARED .. "Progression.ProfileSchema")
		local specs = Schema.Settings()
		for key, default in { QuickCast = true, InvertY = false } do
			T.ok(
				specs[key] ~= nil and specs[key].Type == "boolean" and specs[key].Default == default,
				key .. " whitelisted"
			)
			T.ok(Schema.ValidateSetting(key, not default), key .. " accepts a boolean")
			T.ok(not Schema.ValidateSetting(key, "yes"), key .. " rejects a string")
		end
		local screen = read("src/client/UI/Screens/Settings.luau")
		T.ok(string.find(screen, 'toggle(content, "QuickCast"', 1, true) ~= nil, "QuickCast toggle")
		T.ok(string.find(screen, 'toggle(content, "InvertY"', 1, true) ~= nil, "InvertY toggle")
		local text = Loader.require(SHARED .. "Strings.Settings")
		for _, key in { "set.QuickCast", "set.InvertY", "set.desc.QuickCast", "set.desc.InvertY" } do
			T.ok(text[key] and text[key].en ~= "" and text[key].ru ~= "", key)
		end
		local combat = read("src/client/Controllers/CombatController.luau")
		T.ok(string.find(combat, 'Setting, "QuickCast", true', 1, true) ~= nil, "reads QuickCast (default on)")
		T.ok(string.find(combat, "input.Cancelled:Connect", 1, true) ~= nil, "Esc / right-click cancel an aim")
		T.ok(
			string.find(read("src/client/Controllers/CameraController.luau"), 'setting("InvertY"', 1, true) ~= nil,
			"camera reads InvertY"
		)
	end,

	------------------------------------------------------------------------------------------ 6. dash clip
	polish_predicted_dash_clip = function(T, Loader)
		local movement = read("src/client/Controllers/MovementController.luau")
		local predict = body(movement, "function MovementController.PredictDash")
		T.ok(string.find(predict, "Anim.MarkPredicted, r.Model, castId", 1, true) ~= nil, "marks the castId predicted")
		T.ok(
			string.find(predict, 'Anim.PlayAbility, r.Model, r.Model:GetAttribute("KitId"), "Dash"', 1, true) ~= nil,
			"plays Dash now"
		)
		local combat = read("src/client/Controllers/CombatController.luau")
		T.ok(
			string.find(combat, 'call("MovementController", "PredictDash", dir, castId)', 1, true) ~= nil,
			"castId passed"
		)
		T.ok(string.find(combat, 'Net.Client.Fire("Dash", dir, castId)', 1, true) ~= nil, "castId sent")
		local ability = read("src/server/Services/AbilityService.luau")
		T.ok(
			string.find(ability, "AbilityService.DashAs(model, direction, true, id)", 1, true) ~= nil,
			"server forwards it"
		)
		T.ok(
			string.find(body(ability, "function AbilityService.DashAs"), "castId = castId or 0", 1, true) ~= nil,
			"echoed"
		)
	end,

	---------------------------------------------------------------------------- 7. menu camera / 8. lobby view
	polish_menu_camera_and_lobby_viewers = function(T, Loader)
		local Camera = load(Loader, CLIENT .. "Controllers.CameraController")
		local M = Camera.Math
		local base = CFrame.lookAt(Vector3.new(8, 12, 46), Vector3.new(-2, 7.5, -8))
		for _, t in { 0, 3.3, 17, 120, 999 } do
			local cf = M.MenuDrift(base, t)
			T.ok((cf.Position - base.Position).Magnitude < 2.2, "drift stays near the marker @" .. t)
			T.ok(cf.LookVector:Dot(base.LookVector) > math.cos(math.rad(6)), "keeps the framing @" .. t)
			T.ok(math.abs(cf.RightVector.Y) < 0.05, "no roll @" .. t)
		end
		T.ok(not M.IsParticipant("Lobby", "Lobby"), "lobby waiter")
		T.ok(not M.IsParticipant("Lobby", nil), "role decides")
		T.ok(M.IsParticipant("Human", "Humans") and M.IsParticipant("Monster", nil), "fighters")
		T.ok(M.IsParticipant("Spectator", nil), "fallen participants keep watching the arena")
		T.ok(M.IsParticipant("Lobby", "Lobby", true), "listed in the intro lineup")
		T.ok(not M.IsParticipant(nil, "Lobby") and M.IsParticipant(nil, nil), "team fallback / unknown")
		local camera = read("src/client/Controllers/CameraController.luau")
		T.ok(string.find(camera, "Lobby.MenuCamera", 1, true) ~= nil, "menu mode reads the lobby marker")
		T.ok(string.find(camera, "if not participant(listed) then", 1, true) ~= nil, "intro skipped for the lobby")
		-- graphics
		local Graphics = load(Loader, CLIENT .. "Controllers.GraphicsController")
		local round = {
			GraphicsPreset = "SnowNight",
			FinalPreset = "SnowNightFinal",
			MapId = "SnowdinCrossroads",
			FinalPhase = true,
			LobbyPreset = "GoldenHall",
		}
		local lobby = Graphics.MapState(round, false)
		T.eq(lobby.MapPreset, "GoldenHall", "lobby look")
		T.ok(lobby.FinalPhase == false and lobby.MapId == nil, "no final variant / map fallback in the lobby")
		local arena = Graphics.MapState(round, true)
		T.ok(arena.MapPreset == "SnowNight" and arena.FinalPhase == true, "participants see the arena")
		T.eq(Graphics.MapState({}, false).MapPreset, "Lobby", "default lobby preset")
		T.ok(
			not Graphics.IsParticipant("Lobby", nil) and Graphics.IsParticipant("Monster", nil),
			"graphics participant rule"
		)
		-- music
		local Sound = load(Loader, CLIENT .. "Controllers.SoundController")
		local fight = { Phase = "Round", MapId = "SnowdinCrossroads" }
		T.eq(Sound.MusicFor(fight, { Participant = false }), "Lobby", "lobby music while a round runs")
		T.ok(Sound.MusicFor(fight, { Participant = true }) ~= "Lobby", "arena music for fighters")
		T.eq(
			Sound.MusicFor({ Phase = "Ending" }, { Participant = false, Stinger = "Victory" }),
			"Lobby",
			"no stinger in the lobby"
		)
		T.eq(Sound.MusicFor({ Phase = "Ending" }, { Participant = true, Stinger = "Defeat" }), "Defeat", "stinger")
		T.eq(Sound.MusicFor(fight, { Override = "Title", Participant = false }), "Title", "override wins")
	end,

	---------------------------------------------------------------------------------------- 9. house windows
	polish_house_side_windows_face_out = function(T, Loader)
		local MapKit = Loader.requirePath("src/shared/Maps/MapKit")
		local B = MapKit.new("PolishHouse", { Seed = 7 })
		local origin = CFrame.new(0, 0, 0)
		B:House("H", origin, { Width = 18, Depth = 14 })
		local glows = {}
		for _, d in B.Model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "H_WinGlow" then
				table.insert(glows, d)
			end
		end
		T.ok(#glows >= 3, "front + side windows built")
		local sides = 0
		for _, g in glows do
			local x = g.CFrame.Position.X
			if math.abs(x) > 8.5 then
				sides += 1
				-- the glow pane sits OUTSIDE the wall plane (|x| > w/2), on the side it faces
				T.ok(math.abs(x) > 9, ("side window glow outside the wall (x = %.2f)"):format(x))
			end
		end
		T.eq(sides, 2, "one window per side wall")
	end,
}

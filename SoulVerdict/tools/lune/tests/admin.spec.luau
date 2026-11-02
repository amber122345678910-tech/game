--!nocheck
-- Admin tools: AdminService.Validate (every action has a valid sample; missing / wrong-typed / out-of-range values,
-- unknown keys and unknown actions are rejected; kit <-> side cross rules), IsAdmin rules (StyleLabService mock,
-- Config.Admins), Handle (non-admins are denied with no side effects; handlers against service mocks: gold, levels,
-- unlock-all, reset with confirm, god / speed statuses, solo toggle), the RequestService "Admin" route, the bots
-- clamp, Strings coverage of every admin.* key the server / panel / HUD button use (en + ru), and the client modules
-- build offline (Screens/Admin: every theme x tab x layout x language; Hud/AdminButton visibility + footprint).
local fs = require("@lune/fs")

local SERVICE = "ServerScriptService.Server.Services.AdminService"

local function fakePlayer(userId, admin)
	local attrs = {}
	return {
		Name = "Tester" .. tostring(userId),
		DisplayName = "Tester",
		UserId = userId,
		Parent = {},
		Admin = admin,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
	}
end

-- StyleLab mock: players built with fakePlayer(id, true) are allowed
local LAB = {
	IsAllowed = function(p)
		return p.Admin == true
	end,
}

local VALID = {
	StartNow = { action = "StartNow", side = "Monster", kitId = "FellSans", mapId = "HallOfVerdicts", bots = 4 },
	SetMinPlayers = { action = "SetMinPlayers", n = 1 },
	SkipPhase = { action = "SkipPhase" },
	FinalPhase = { action = "FinalPhase" },
	Phase3 = { action = "Phase3" },
	Collapse = { action = "Collapse" },
	EndRound = { action = "EndRound", winner = "Monster" },
	SetMap = { action = "SetMap", mapId = "VoidRift" },
	AddBot = { action = "AddBot", team = "Humans", kitId = "Patience" },
	ClearBots = { action = "ClearBots" },
	SpawnDummy = { action = "SpawnDummy", count = 3 },
	BecomeKit = { action = "BecomeKit", kitId = "EclipseSans" },
	God = { action = "God", on = true },
	Heal = { action = "Heal" },
	FullUlt = { action = "FullUlt" },
	ResetCooldowns = { action = "ResetCooldowns" },
	NoCooldowns = { action = "NoCooldowns", on = false },
	Speed = { action = "Speed", mult = 2 },
	TeleportLobby = { action = "TeleportLobby" },
	TeleportArena = { action = "TeleportArena" },
	AddGold = { action = "AddGold", n = 1000 },
	AddLevels = { action = "AddLevels", n = 5 },
	UnlockAll = { action = "UnlockAll" },
	ResetProfile = { action = "ResetProfile", confirm = true },
	BoxNearest = { action = "BoxNearest" },
	DamageMe = { action = "DamageMe", n = 50 },
	AddKR = { action = "AddKR", n = 20 },
	GiveDodges0 = { action = "GiveDodges0" },
}

-- per-action invalid field sets (merged over { action = <name> })
local INVALID = {
	StartNow = {
		{},
		{ side = "Both" },
		{ side = "human" },
		{ side = "Monster", kitId = "Patience" }, -- human kit on the monster side
		{ side = "Human", kitId = "ClassicSans" },
		{ side = "Human", kitId = "NoSuchKit" },
		{ side = "Human", kitId = "../Kits" },
		{ side = "Human", bots = 9 },
		{ side = "Human", bots = -1 },
		{ side = "Human", bots = 1.5 },
		{ side = "Human", bots = "3" },
		{ side = "Human", mapId = "Lobby" },
		{ side = "Human", mapId = "NoSuchMap" },
		{ side = "Human", mapId = 7 },
	},
	SetMinPlayers = { {}, { n = 0 }, { n = 3 }, { n = "1" }, { n = 1.5 } },
	EndRound = { { winner = "Humanz" }, { winner = 1 } },
	SetMap = { {}, { mapId = "Lobby" }, { mapId = "No Such Map" }, { mapId = "" } },
	AddBot = {
		{},
		{ team = "Lobby" },
		{ team = "Human" },
		{ team = "Monster", kitId = "Determination" },
		{ team = "Humans", kitId = 3 },
	},
	SpawnDummy = { { count = 0 }, { count = 6 }, { count = 2.5 }, { count = true } },
	BecomeKit = { {}, { kitId = "Dummy" }, { kitId = 5 }, { kitId = "" } },
	God = { {}, { on = "yes" }, { on = 1 } },
	NoCooldowns = { {}, { on = "true" } },
	Speed = { {}, { mult = 0.5 }, { mult = 3.5 }, { mult = 0 / 0 }, { mult = math.huge }, { mult = "2" } },
	AddGold = { {}, { n = 0 }, { n = -5 }, { n = 1e7 }, { n = 10.5 }, { n = 0 / 0 } },
	AddLevels = { {}, { n = 0 }, { n = 101 } },
	ResetProfile = { {}, { confirm = false }, { confirm = "true" }, { confirm = 1 } },
	DamageMe = { {}, { n = 0 }, { n = 5000 }, { n = 1 / 0 } },
	AddKR = { {}, { n = 0 }, { n = 101 } },
}

local function merged(action, fields)
	local t = { action = action }
	for k, v in fields do
		t[k] = v
	end
	return t
end

local function load(Loader, services)
	local Admin = Loader.require(SERVICE)
	Admin._SetServices(services or { StyleLabService = LAB })
	return Admin
end

-- DataService mock around one live profile table
local function dataMock(profile)
	local calls = 0
	return {
		Update = function(_, fn)
			calls += 1
			fn(profile)
			return true
		end,
		Calls = function()
			return calls
		end,
	}
end

local function statusMock()
	local log = {}
	return {
		Apply = function(model, name, duration, data)
			table.insert(log, { "Apply", name, duration, data })
			return true
		end,
		Remove = function(model, name)
			table.insert(log, { "Remove", name })
		end,
		Log = log,
	}
end

local function fakeCharacter(Loader)
	local roblox = Loader.roblox
	local model = roblox.Instance.new("Model")
	model.Name = "Char"
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Parent = model
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	return model
end

local function has(log, kind, name)
	for _, entry in log do
		if entry[1] == kind and entry[2] == name then
			return entry
		end
	end
	return nil
end

-- client-side helpers (the loader is flipped to client mode and restored)
local function clientMode(Loader, fn)
	local isServer, quiet = Loader.isServer, Loader.quietWarnings
	Loader.isServer = false
	Loader.quietWarnings = true
	local ok, err = pcall(fn)
	Loader.isServer, Loader.quietWarnings = isServer, quiet
	if not ok then
		error(err, 0)
	end
end

local function fakeSignal()
	local handlers = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(handlers, fn)
		return { Connected = true, Disconnect = function() end }
	end
	function sig:Fire(...)
		for _, fn in handlers do
			fn(...)
		end
	end
	return sig
end

return {
	validate_every_action = function(T, Loader)
		local Admin = load(Loader)
		local actions = Admin.Actions()
		T.ok(#actions >= 27, "action count " .. #actions)
		for _, action in actions do
			local sample = VALID[action]
			if T.ok(sample ~= nil, "VALID sample for " .. action) then
				local cmd, err = Admin.Validate(sample)
				T.ok(cmd ~= nil and err == nil, action .. " valid sample accepted: " .. tostring(err))
				if cmd then
					T.eq(cmd.action, action, action .. " normalised action")
				end
				-- any unknown extra key is rejected
				local extra = table.clone(sample)
				extra.sneaky = 1
				T.eq(select(2, Admin.Validate(extra)), "admin.err.bad", action .. " unknown key rejected")
			end
			for i, fields in INVALID[action] or {} do
				local cmd, err = Admin.Validate(merged(action, fields))
				T.ok(cmd == nil and err == "admin.err.bad", ("%s invalid #%d rejected"):format(action, i))
			end
		end
		for name in VALID do
			T.ok(table.find(actions, name) ~= nil, "VALID entry is a real action: " .. name)
		end
	end,

	validate_shapes_and_normalising = function(T, Loader)
		local Admin = load(Loader)
		for _, bad in
			{ nil, 5, true, {}, { action = 5 }, { action = "Nope" }, { action = "" }, "Nope", { action = "IsAdmin" } }
		do
			local cmd, err = Admin.Validate(bad)
			T.ok(cmd == nil and err == "admin.err.bad", "rejected: " .. tostring(bad))
		end
		local cmd = Admin.Validate("Heal")
		T.ok(cmd and cmd.action == "Heal", "bare action string accepted")
		T.eq(Admin.Validate({ action = "Speed", mult = 1.49 }).mult, 1.5, "speed rounded to 0.05")
		T.eq(Admin.Validate({ action = "StartNow", side = "Human" }).bots, nil, "optional fields stay nil")
		T.ok(Admin.Validate({ action = "StartNow", side = "Human", kitId = "Justice", bots = 0 }) ~= nil, "0 allies ok")
		T.ok(Admin.Validate({ action = "SetMap", mapId = "TestArena" }) ~= nil, "test arena is a valid map")
		T.ok(Admin.Validate({ action = "AddBot", team = "Monster", kitId = "ClassicSans" }) ~= nil, "monster bot kit")
		-- bots clamp
		T.eq(Admin.BotsFor("Monster", 0), 1, "monster side needs >= 1 human bot")
		T.eq(Admin.BotsFor("Monster", 8), 8, "8 human bots")
		T.eq(Admin.BotsFor("Human", 8), 5, "allies capped at 5")
		T.eq(Admin.BotsFor("Human", nil), nil, "nil keeps the default")
		T.eq(Admin.BotsFor("Human", 0 / 0), nil, "NaN keeps the default")
	end,

	isadmin_rules = function(T, Loader)
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		T.ok(type(Config.Admins) == "table", "Config.Admins exists")
		local Admin = load(Loader)
		T.ok(Admin.IsAdmin(fakePlayer(1, true)), "StyleLab-allowed player (owner / Studio / private server) is admin")
		T.ok(not Admin.IsAdmin(fakePlayer(2)), "a random player is not")
		T.ok(not Admin.IsAdmin(nil), "nil is not")
		table.insert(Config.Admins, 2)
		T.ok(Admin.IsAdmin(fakePlayer(2)), "listed in Config.Admins")
		Config.Admins[#Config.Admins] = "3"
		T.ok(Admin.IsAdmin(fakePlayer(3)), "a UserId written as a string still works")
		T.ok(not Admin.IsAdmin(fakePlayer(2)), "removed again")
		table.remove(Config.Admins)
		Admin._SetServices({
			StyleLabService = {
				IsAllowed = function()
					error("boom (expected in this test)")
				end,
			},
		})
		T.ok(not Admin.IsAdmin(fakePlayer(1, true)), "a failing StyleLab check denies")
		-- Style Lab open to everyone must not make everyone an admin (admin actions write saved data): then
		-- IsAllowed (true for everyone) is not consulted and the ownership rules decide (Studio under Lune)
		local consulted = 0
		Admin._SetServices({
			StyleLabService = {
				IsAllowed = function()
					consulted += 1
					return true
				end,
			},
		})
		T.ok(Admin.IsAdmin(fakePlayer(5)), "normal build: StyleLab's owner check decides")
		T.eq(consulted, 1, "IsAllowed consulted")
		local before = Config.StyleLab.AllowEveryone
		Config.StyleLab.AllowEveryone = true
		local ok = pcall(Admin.IsAdmin, fakePlayer(5))
		Config.StyleLab.AllowEveryone = before
		T.ok(ok, "IsAdmin with AllowEveryone")
		T.eq(consulted, 1, "AllowEveryone: IsAllowed is not trusted for admin rights")
	end,

	nonadmin_rejected_without_side_effects = function(T, Loader)
		local profile = { Gold = 10, Level = 1, Exp = 0, Unlocked = {}, Equipped = {} }
		local data = dataMock(profile)
		local touched = 0
		local function count()
			touched += 1
			return true
		end
		local Admin = load(Loader, {
			StyleLabService = LAB,
			DataService = data,
			DamageService = { Apply = count, AddKR = count, SetHealth = count, DrainDodges = count },
			RoundService = {
				Phase = function()
					return "Round"
				end,
				SkipPhase = count,
				EndRound = count,
				Abort = count,
				TriggerFinalPhase = count,
			},
			BotService = { SpawnPracticeBots = count, Clear = count, SpawnDummies = count },
			CharacterService = { GetModel = count, SpawnLobby = count },
			StatusService = { Apply = count, Remove = count },
		})
		local stranger = fakePlayer(77)
		for _, action in Admin.Actions() do
			local ok, err = Admin.Handle(stranger, VALID[action])
			T.ok(ok == false and err == "admin.err.denied", action .. " denied for non-admins")
		end
		T.eq(touched, 0, "no service was touched")
		T.eq(data.Calls(), 0, "no profile update")
		T.eq(profile.Gold, 10, "gold unchanged")
		T.eq(stranger:GetAttribute("AdminGod"), nil, "no admin attribute written")
		-- admins: bad payloads / unknown actions are rejected before any handler
		local admin = fakePlayer(1, true)
		T.eq(select(2, Admin.Handle(admin, { action = "Nope" })), "admin.err.bad", "unknown action")
		T.eq(select(2, Admin.Handle(admin, { action = "AddGold", n = -1 })), "admin.err.bad", "bad payload")
		T.eq(select(2, Admin.Handle(admin, { action = "ResetProfile" })), "admin.err.bad", "reset needs confirm")
		T.eq(touched, 0, "still untouched")
	end,

	handlers_progress = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local Levels = Loader.require("ReplicatedStorage.Shared.Progression.Levels")
		local profile = {
			Gold = 25,
			Level = 1,
			Exp = 40,
			Unlocked = {},
			Equipped = {},
			Settings = { Language = "ru" },
			Created = 123,
		}
		local Admin = load(Loader, { StyleLabService = LAB, DataService = dataMock(profile) })
		local admin = fakePlayer(1, true)
		T.ok(Admin.Handle(admin, { action = "AddGold", n = 1000 }), "add gold")
		T.eq(profile.Gold, 1025, "gold added")
		T.ok(Admin.Handle(admin, { action = "AddLevels", n = 5 }), "add levels")
		T.eq(profile.Level, 6, "level +5")
		T.eq(profile.Exp, 0, "exp reset")
		for _ = 1, math.ceil(Levels.MaxLevel / 100) + 1 do
			Admin.Handle(admin, { action = "AddLevels", n = 100 })
		end
		T.eq(profile.Level, Levels.MaxLevel, "capped at MaxLevel")
		T.ok(Admin.Handle(admin, { action = "UnlockAll" }), "unlock all")
		for _, kit in Kits.All() do
			T.ok(profile.Unlocked[kit.Id] == true, "kit unlocked " .. kit.Id)
			for _, skin in kit.Skins do
				T.ok(profile.Unlocked[kit.Id .. ":" .. skin.Id] == true, "skin unlocked " .. kit.Id .. ":" .. skin.Id)
			end
		end
		T.ok(Admin.Handle(admin, { action = "ResetProfile", confirm = true }), "reset")
		T.eq(profile.Gold, 0, "gold reset")
		T.eq(profile.Level, 1, "level reset")
		T.ok(profile.Unlocked.FellSans ~= true, "paid kit locked again")
		T.eq(profile.Settings.Language, "ru", "settings kept")
		T.eq(profile.Created, 123, "created kept")
		T.ok(type(profile.Equipped) == "table" and profile.Equipped.Human == Kits.DefaultHuman, "default equips")
		-- StartNow equips the chosen kit into its role slot (alone: the practice start itself runs async)
		local okStart = Admin.Handle(admin, { action = "StartNow", side = "Monster", kitId = "EclipseSans" })
		T.ok(okStart, "start now accepted")
		T.eq(profile.Equipped.Monster, "EclipseSans", "kit equipped for the round")
	end,

	handlers_cheats = function(T, Loader)
		local status = statusMock()
		local model = fakeCharacter(Loader)
		local damage = {}
		local Admin = load(Loader, {
			StyleLabService = LAB,
			StatusService = status,
			CharacterService = {
				GetModel = function()
					return model
				end,
			},
			DamageService = {
				Apply = function(info)
					table.insert(damage, info)
					return { Applied = info.Amount }
				end,
			},
		})
		local admin = fakePlayer(1, true)
		T.ok(Admin.Handle(admin, { action = "God", on = true }), "god on")
		T.eq(admin:GetAttribute("AdminGod"), true, "AdminGod attribute")
		T.ok(has(status.Log, "Apply", "Invulnerable") ~= nil, "Invulnerable applied")
		T.ok(has(status.Log, "Apply", "Determined") ~= nil, "Determined applied")
		table.clear(status.Log)
		T.ok(Admin.Handle(admin, { action = "DamageMe", n = 30 }), "damage me")
		T.eq(#damage, 1, "one hit")
		T.eq(damage[1].Amount, 30, "amount")
		T.eq(damage[1].Kind, "True", "true damage")
		T.ok(has(status.Log, "Remove", "Invulnerable") ~= nil, "god suspended for the test hit")
		T.ok(has(status.Log, "Apply", "Invulnerable") ~= nil, "god restored after the hit")
		table.clear(status.Log)
		T.ok(Admin.Handle(admin, { action = "God", on = false }), "god off")
		T.ok(has(status.Log, "Remove", "Invulnerable") ~= nil, "Invulnerable removed")
		T.eq(admin:GetAttribute("AdminGod"), false, "attribute off")
		T.ok(Admin.Handle(admin, { action = "Speed", mult = 2 }), "speed x2")
		local haste = has(status.Log, "Apply", "Hasted")
		T.ok(haste ~= nil and haste[4] and haste[4].mult == 2, "Hasted x2")
		T.eq(admin:GetAttribute("AdminSpeed"), 2, "AdminSpeed attribute")
		T.ok(Admin.Handle(admin, { action = "Speed", mult = 1 }), "speed x1")
		T.ok(has(status.Log, "Remove", "Hasted") ~= nil, "Hasted removed at x1")
		T.ok(Admin.Handle(admin, { action = "FullUlt" }), "full ult")
		T.eq(model:GetAttribute("Ult"), 100, "ult = 100")
		model:SetAttribute("Dead", true)
		T.eq(select(2, Admin.Handle(admin, { action = "Heal" })), "admin.err.noCharacter", "dead: no character")
		T.ok(Admin.Handle(admin, { action = "SetMinPlayers", n = 1 }), "solo on")
		T.ok(Admin.Handle(admin, { action = "SetMinPlayers", n = 2 }), "solo off")
		T.eq(select(2, Admin.Handle(admin, { action = "BoxNearest" })), "admin.err.noCharacter", "box needs a body")
	end,

	request_route = function(T, Loader)
		local RS = Loader.require("ServerScriptService.Server.Services.RequestService")
		T.noerror(RS.Init, "RequestService.Init")
		local Admin = Loader.require(SERVICE)
		local services = { StyleLabService = LAB, RequestService = RS }
		for _, name in
			{
				"RoundService",
				"BotService",
				"CharacterService",
				"StatusService",
				"AbilityService",
				"DamageService",
				"DataService",
				"MapService",
				"MovementService",
				"VerdictBoxService",
				"QueueService",
			}
		do
			services[name] = {} -- inert stand-ins: Init must not require the real services here
		end
		Admin._SetServices(services)
		T.noerror(Admin.Init, "AdminService.Init")
		T.ok(RS.Has("Admin"), "Admin action registered")
		local ok, err = RS.Dispatch(fakePlayer(9), "Admin", { action = "Heal" })
		T.ok(not ok and err == "admin.err.denied", "non-admin denied through the remote path")
		local ok2, err2 = RS.Dispatch(fakePlayer(10, true), "Admin", { action = "Nope" })
		T.ok(not ok2 and err2 == "admin.err.bad", "unknown action through the remote path")
	end,

	strings_cover_every_key = function(T, Loader)
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		local tbl = Loader.require("ReplicatedStorage.Shared.Strings.Admin")
		for key, entry in tbl do
			T.ok(type(entry.en) == "string" and entry.en ~= "", key .. " en")
			T.ok(type(entry.ru) == "string" and entry.ru ~= "", key .. " ru")
			local function holes(s)
				local set = {}
				for n in string.gmatch(s, "{(%d+)}") do
					set[n] = true
				end
				local list = {}
				for n in set do
					table.insert(list, n)
				end
				table.sort(list)
				return table.concat(list, ",")
			end
			T.eq(holes(entry.en), holes(entry.ru), key .. " placeholders match")
		end
		for _, path in
			{
				"src/server/Services/AdminService.luau",
				"src/client/UI/Screens/Admin.luau",
				"src/client/UI/Hud/AdminButton.luau",
			}
		do
			local source = fs.readFile(path)
			for key in string.gmatch(source, '"(admin%.[%w%.]+)"') do
				if not string.match(key, "%.$") then
					T.ok(Strings.Has(key), path .. " uses existing key " .. key)
				end
			end
		end
		for _, side in { "Human", "Monster" } do
			T.ok(Strings.Has("admin.side." .. side), "side key " .. side)
		end
		for _, role in { "Lobby", "Human", "Monster", "Spectator" } do
			T.ok(Strings.Has("admin.role." .. role), "role key " .. role)
		end
	end,

	client_panel_builds = function(T, Loader)
		clientMode(Loader, function()
			local Themes = Loader.requirePath("src/client/UI/Themes")
			local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
			local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
			local Screen = Loader.requirePath("src/client/UI/Screens/Admin")
			local roblox = Loader.roblox
			local layouts = {
				phone = UIRoot.ComputeLayout(roblox.Vector2.new(860, 400)),
				desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080)),
			}
			for _, lang in { "en", "ru" } do
				Strings.SetLanguage(lang)
				for _, theme in Themes.List() do
					for lname, layout in layouts do
						for _, tab in Screen.Tabs do
							local label = ("Admin %s %s %s %s"):format(theme.Id, lname, lang, tab)
							local ok, handle = pcall(Screen.Create, theme, { Layout = layout, Tab = tab })
							if T.ok(ok and type(handle) == "table", label .. ": " .. tostring(handle)) then
								T.ok(handle.Root:IsA("GuiObject"), label .. " root")
								T.ok(#handle.Root:GetDescendants() > 40, label .. " content")
								T.ok(
									type(handle.OnAction) == "function" and handle.OnAction("NextTab") == true,
									label .. " next tab"
								)
								T.noerror(handle.Destroy, label .. " destroy")
							end
						end
					end
				end
			end
			Strings.SetLanguage("en")
			-- touch targets: every button in the phone panel is >= 44 pt tall
			local layout = layouts.phone
			local handle = Screen.Create(Themes.Get("Classic"), { Layout = layout, Tab = "Match" })
			local minPx = math.ceil(44 / layout.Scale)
			local small = {}
			for _, inst in handle.Root:GetDescendants() do
				if
					inst:IsA("TextButton")
					and inst.Size.Y.Scale == 0
					and inst.Size.Y.Offset > 0
					and inst.Size.Y.Offset < minPx
				then
					local parent = inst.Parent
					local inGrid = parent and parent:FindFirstChildOfClass("UIGridLayout") ~= nil
					if not inGrid then
						table.insert(small, inst.Name .. "=" .. inst.Size.Y.Offset)
					end
				end
			end
			T.eq(#small, 0, "phone buttons >= 44 pt: " .. table.concat(small, ", "))
			handle.Destroy()
		end)
	end,

	client_panel_requests = function(T, Loader)
		clientMode(Loader, function()
			local Themes = Loader.requirePath("src/client/UI/Themes")
			local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
			local Screen = Loader.requirePath("src/client/UI/Screens/Admin")
			local requests = {}
			local notify = fakeSignal()
			local state = {
				Notify = notify,
				ProfileChanged = fakeSignal(),
				CharacterChanged = fakeSignal(),
				Request = function(action, data)
					table.insert(requests, { action, data })
				end,
				Profile = function()
					return nil
				end,
				Round = function()
					return { Phase = "Waiting" }
				end,
			}
			local layout = UIRoot.ComputeLayout(Loader.roblox.Vector2.new(860, 400))
			local handle = Screen.Create(Themes.Get("Void"), { Layout = layout, State = state, Tab = "Match" })
			T.ok(handle ~= nil, "runtime-path build")
			notify:Fire("admin.ok.heal", nil, "Success")
			local fb = Screen.State().Feedback
			T.ok(
				fb ~= nil and fb.Kind == "Success" and fb.Text ~= "admin.ok.heal",
				"server toast mirrored in the panel"
			)
			notify:Fire("admin.err.denied", {}, "Warning")
			T.eq(Screen.State().Feedback.Kind, "Warning", "warning style")
			handle.Select("Progress")
			T.eq(Screen.State().Tab, "Progress", "tab switch")
			handle.Destroy()
		end)
	end,

	hud_button = function(T, Loader)
		clientMode(Loader, function()
			local Themes = Loader.requirePath("src/client/UI/Themes")
			local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
			local Button = Loader.requirePath("src/client/UI/Hud/AdminButton")
			local roblox = Loader.roblox
			local phone = UIRoot.ComputeLayout(roblox.Vector2.new(860, 400))
			local desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080))
			for _, hud in { "Battle", "Modern" } do
				for lname, layout in { phone = phone, desktop = desktop } do
					local label = hud .. " " .. lname
					local shown =
						Button.Create(Themes.Get("Classic"), { Layout = layout, Hud = hud, Attrs = { Admin = true } })
					local pill = shown.Root:FindFirstChild("Pill")
					T.ok(pill ~= nil and pill.Visible, label .. ": visible for admins")
					local pos, size = Button.Footprint(layout)
					T.ok(size.Y * layout.Scale >= 43.9, label .. ": >= 44 pt tall")
					T.ok(pos.Y * layout.Scale >= 58, label .. ": below the Roblox top bar")
					T.eq(pill.Position.Y.Offset, pos.Y, label .. ": default position")
					shown.SetPosition(roblox.UDim2.fromOffset(300, 10))
					T.eq(pill.Position.X.Offset, 300, label .. ": SetPosition")
					shown.Destroy()
					local hidden =
						Button.Create(Themes.Get("Classic"), { Layout = layout, Hud = hud, Attrs = { Admin = false } })
					T.ok(not hidden.Root:FindFirstChild("Pill").Visible, label .. ": hidden for players")
					hidden.Destroy()
				end
			end
			local fixed = Button.Create(
				Themes.Get("Void"),
				{ Layout = phone, Attrs = { Admin = true }, AdminButtonPosition = roblox.UDim2.fromOffset(500, 12) }
			)
			T.eq(fixed.Root:FindFirstChild("Pill").Position.X.Offset, 500, "deps.AdminButtonPosition")
			fixed.Destroy()
		end)
	end,
}

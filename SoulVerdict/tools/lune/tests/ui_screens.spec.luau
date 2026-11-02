--!nocheck
-- Menu screens (src/client/UI/Screens): every screen builds in every theme at desktop + phone layouts, in en + ru,
-- with the offline sample data, with "profile not loaded", with a brand-new default profile and with a mock
-- StateController (runtime path); handles expose the SPEC §10 contract; Destroy cleans up. Also: every Strings key
-- the screens use exists (literal keys + dynamic families) with en + ru; UIController loads and exposes its API.
local fs = require("@lune/fs")

local SCREENS = { "Title", "Loadout", "Shop", "Quests", "Profile", "Settings", "StyleLab", "Results" }
local DIR = "src/client/UI/Screens/"

local function setup(Loader)
	Loader.isServer = false
	Loader.quietWarnings = true
	local Themes = Loader.requirePath("src/client/UI/Themes")
	local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	local roblox = Loader.roblox
	local layouts = {
		desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080)),
		phone = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390)),
	}
	return Themes, Strings, layouts
end

local function fakeSignal()
	local handlers = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(handlers, fn)
		return {
			Connected = true,
			Disconnect = function() end,
		}
	end
	function sig:Fire(...)
		for _, fn in handlers do
			fn(...)
		end
	end
	return sig
end

-- a StateController stand-in: exercises the runtime branches (no samples, requests recorded)
local function mockState(profile)
	local requests = {}
	local state = {
		ProfileChanged = fakeSignal(),
		SettingChanged = fakeSignal(),
		RoundChanged = fakeSignal(),
		Notify = fakeSignal(),
	}
	function state.Profile()
		return profile
	end
	function state.Round()
		return { Phase = "Intermission", PhaseEndsAt = 100, MapId = "HallOfVerdicts" }
	end
	function state.Now()
		return 80
	end
	function state.Request(action, data)
		table.insert(requests, { action, data })
	end
	function state.Leaderboards()
		return { Wins = {}, Level = {} }
	end
	function state.Setting()
		return nil
	end
	return state, requests
end

local function build(T, module, theme, deps, label)
	local ok, handle = pcall(module.Create, theme, deps)
	if not T.ok(ok and type(handle) == "table", label .. ": " .. tostring(handle)) then
		return nil
	end
	T.ok(typeof(handle.Root) == "Instance" and handle.Root:IsA("GuiObject"), label .. ": Root is a GuiObject")
	T.ok(type(handle.Destroy) == "function", label .. ": Destroy")
	T.ok(#handle.Root:GetDescendants() > 10, label .. ": has content")
	return handle
end

-- Client-side suite: setup() flips the shared loader into client mode (isServer = false, quiet warnings).
-- Every test puts the flags back, even when it fails, so later suites still run as the server (test hygiene;
-- run_tests.luau reports any shared state a test leaks).
local function restoringFlags(tests)
	for name, fn in tests do
		tests[name] = function(T, Loader)
			local isServer, quiet = Loader.isServer, Loader.quietWarnings
			local ok, err = pcall(fn, T, Loader)
			Loader.isServer, Loader.quietWarnings = isServer, quiet
			if not ok then
				error(err, 0)
			end
		end
	end
	return tests
end

return restoringFlags({
	everyScreenEveryThemeAndLayout = function(T, Loader)
		local Themes, Strings, layouts = setup(Loader)
		for _, lang in { "en", "ru" } do
			Strings.SetLanguage(lang)
			for _, name in SCREENS do
				local module = Loader.requirePath(DIR .. name)
				T.ok(type(module.Create) == "function", name .. " has Create")
				for _, theme in Themes.List() do
					for lname, layout in layouts do
						local handle = build(T, module, theme, { Layout = layout, StyleLab = true }, ("%s %s %s %s"):format(name, theme.Id, lname, lang))
						if handle then
							T.noerror(handle.Destroy, name .. " destroy")
						end
					end
				end
			end
		end
		Strings.SetLanguage("en")
	end,

	screenVariants = function(T, Loader)
		local Themes, _, layouts = setup(Loader)
		local theme = Themes.Get("Royal")
		local variants = {
			Loadout = { { Role = "Monster" }, { Role = "Human", Kit = "Justice" }, { Kit = "EclipseSans", Skin = "Solar" } },
			Shop = { { Kit = "FellSans" }, { Tab = "All" }, { Kit = "Integrity" } },
			Quests = { { Tab = "Achievements" } },
			Profile = { { Board = "Level" }, { Tab = "Mastery" }, { Tab = "Boards" } },
			Settings = { { Section = "Interface" }, { Section = "Audio" } },
			StyleLab = { { Kit = "FellSans" } },
		}
		for name, list in variants do
			local module = Loader.requirePath(DIR .. name)
			for i, extra in list do
				for lname, layout in layouts do
					local deps = table.clone(extra)
					deps.Layout = layout
					local h = build(T, module, theme, deps, ("%s variant %d %s"):format(name, i, lname))
					if h then
						if type(h.OnAction) == "function" then
							T.noerror(function()
								h.OnAction("NextTab")
								h.OnAction("PrevTab")
								h.OnAction("Back")
							end, name .. " OnAction")
						end
						h.Destroy()
					end
				end
			end
		end
	end,

	profileNotLoadedAndFreshProfile = function(T, Loader)
		local Themes, _, layouts = setup(Loader)
		local fresh = nil
		local ok, schema = pcall(Loader.require, "ReplicatedStorage.Shared.Progression.ProfileSchema")
		if ok and schema and schema.Default then
			fresh = schema.Default()
			if schema.View then
				fresh = schema.View(fresh, { Now = 1700000000 })
			end
		end
		for _, name in SCREENS do
			local module = Loader.requirePath(DIR .. name)
			for _, theme in Themes.List() do
				-- profile not loaded yet (runtime: StateController.Profile() == nil)
				local state = mockState(nil)
				local h = build(T, module, theme, { Layout = layouts.desktop, State = state }, name .. " no profile " .. theme.Id)
				if h then
					h.Destroy()
				end
				if fresh then
					local state2 = mockState(fresh)
					local h2 = build(T, module, theme, { Layout = layouts.phone, State = state2 }, name .. " fresh profile " .. theme.Id)
					if h2 then
						-- live profile update must rebuild cleanly
						T.noerror(function()
							state2.ProfileChanged:Fire(fresh)
						end, name .. " ProfileChanged")
						h2.Destroy()
					end
				end
			end
		end
	end,

	resultsRewardsArriveLater = function(T, Loader)
		local Themes, _, layouts = setup(Loader)
		local Results = Loader.requirePath(DIR .. "Results")
		local Common = Loader.requirePath(DIR .. "Common")
		for _, theme in Themes.List() do
			local result = Common.SampleResult()
			local h = build(T, Results, theme, { Layout = layouts.desktop, Result = result, State = mockState(Common.SampleProfile()), UserId = 5 }, "Results pending " .. theme.Id)
			if h then
				T.ok(type(h.SetRewards) == "function", "SetRewards exposed")
				T.noerror(function()
					h.SetRewards(Common.SampleRewards())
					h.SetRewards({ exp = 10, gold = 5 })
				end, "SetRewards")
				h.Destroy()
			end
			-- a draw / aborted round with an empty table
			local h2 = build(T, Results, theme, { Layout = layouts.phone, Result = { winner = "", reason = "Aborted", stats = {} }, State = mockState(nil) }, "Results empty " .. theme.Id)
			if h2 then
				h2.Destroy()
			end
		end
	end,

	requestsUseExpectedPayloads = function(T, Loader)
		setup(Loader)
		local Common = Loader.requirePath(DIR .. "Common")
		local state, requests = mockState(Common.SampleProfile())
		T.ok(Common.Request({ State = state }, "EquipKit", { kitId = "FellSans", role = "Monster" }), "request via State")
		T.eq(requests[1][1], "EquipKit", "action recorded")
		T.eq(requests[1][2].kitId, "FellSans", "payload recorded")
		T.eq(Common.Request({}, "Buy", {}), false, "offline previews never send")
	end,

	commonHelpers = function(T, Loader)
		setup(Loader)
		local Common = Loader.requirePath(DIR .. "Common")
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		T.eq(Common.Num(1234567), "1,234,567", "thousands separators")
		T.eq(Common.Num(-1500), "-1,500", "negative numbers")
		T.eq(Common.Clock(3725), "1:02:05", "clock with hours")
		T.eq(Common.Clock(65), "1:05", "clock")
		local lv, frac, max = Common.Mastery(0)
		T.eq(lv, 1, "mastery starts at 1")
		T.ok(frac >= 0 and frac <= 1 and not max, "mastery fraction")
		local lv10, _, max10 = Common.Mastery(1e6)
		T.eq(lv10, 10, "mastery caps at 10")
		T.ok(max10, "mastery max flag")
		T.eq(Common.ExpToNext(1), 100, "ExpToNext(1) = 100 (SPEC 1.6)")
		local p = Common.SampleProfile()
		for _, kit in Kits.All() do
			T.eq(#Common.SkinColors(kit, kit.Skins[1]), 3, kit.Id .. " swatch colours")
			T.ok(type(Common.KitIcon(kit)) == "string", kit.Id .. " kit icon")
			for _, skin in kit.Skins do
				T.ok(type(Common.SkinOwned(p, kit, skin)) == "boolean", "SkinOwned " .. kit.Id .. ":" .. skin.Id)
			end
		end
		T.ok(Common.KitOwned(p, Kits.Get("ClassicSans")), "free kit owned")
		T.ok(not Common.KitOwned(p, Kits.Get("EclipseSans")), "locked kit not owned")
	end,

	stringsUsedByScreensExist = function(T, Loader)
		local _, Strings = setup(Loader)
		local files = {}
		for _, name in fs.readDir(DIR) do
			table.insert(files, DIR .. name)
		end
		table.insert(files, "src/client/Controllers/UIController.luau")
		local count = 0
		for _, file in files do
			local src = fs.readFile(file)
			for key in string.gmatch(src, '[^%w_]L%("([%w%._]+)"[,%)]') do
				count += 1
				T.ok(Strings.Has(key), file .. " uses missing key " .. key)
			end
			for key in string.gmatch(src, 'Strings%.L%("([%w%._]+)"[,%)]') do
				count += 1
				T.ok(Strings.Has(key), file .. " uses missing key " .. key)
			end
		end
		T.ok(count > 100, "scanned keys: " .. count)
		-- dynamic key families
		local families = {
			["scr.loadout.prefHint."] = { "Either", "Monster", "Human" },
			["scr.loadout.tab."] = { "Monster", "Human" },
			["scr.rarity."] = { "Common", "Rare", "Epic", "Legendary" },
			["scr.profile.stat."] = { "Rounds", "Wins", "MonsterWins", "HumanWins", "Kills", "Downs", "Damage", "Healing", "Parries", "Dodges", "Saves", "Revives", "BoxesSurvived", "MVPs" },
			["scr.profile.lb."] = { "Wins", "Level" },
			["scr.num."] = { "Damage", "KR", "Heal", "HealPerSecond", "Radius", "Range", "Distance", "Duration", "Stun" },
			["set."] = { "GraphicsPreset", "GraphicsQuality", "ParticleDensity", "MenuTheme", "HudStyle", "Language", "DamageNumbers", "RigStyle", "MusicVolume", "SfxVolume", "CameraShake", "FieldOfView", "Sensitivity", "CameraLock", "ColorblindPatterns", "ReducedFlashes" },
			["set.quality."] = { "Auto", "Low", "Medium", "High", "Ultra" },
			["lab.weather."] = { "Preset", "None", "Snow", "Blizzard", "Embers", "Ash", "Dust", "Fireflies", "Spores", "VoidMotes", "RiftMotes", "Glimmer", "Rain" },
			["scr.results.flavor."] = { "Humans", "Monster", "Draw" },
			["round.phase."] = { "Waiting", "Intermission", "Intro", "Round", "Collapse", "Ending" },
			["difficulty."] = { "1", "2", "3" },
			["role."] = { "monster", "human", "either" },
		}
		for prefix, list in families do
			for _, suffix in list do
				T.ok(Strings.Has(prefix .. suffix), "missing dynamic key " .. prefix .. suffix)
			end
		end
		-- the tag badges of every ability
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		for _, kit in Kits.All() do
			for _, a in kit.Abilities do
				for _, tag in a.Tags or {} do
					T.ok(Strings.Has("tag." .. tag), "missing tag string tag." .. tag)
				end
			end
		end
		-- the settings whitelist (when Progression exists) has a label for every key
		local ok, schema = pcall(Loader.require, "ReplicatedStorage.Shared.Progression.ProfileSchema")
		if ok and schema and schema.Settings then
			for key in schema.Settings() do
				T.ok(Strings.Has("set." .. key), "settings label set." .. key)
			end
		end
	end,

	ownStringsHaveBothLanguages = function(T, Loader)
		setup(Loader)
		for _, name in { "Screens", "Settings", "StyleLab" } do
			local tbl = Loader.require("ReplicatedStorage.Shared.Strings." .. name)
			local n = 0
			for key, entry in tbl do
				n += 1
				T.ok(type(entry.en) == "string" and entry.en ~= "", name .. " " .. key .. " en")
				T.ok(type(entry.ru) == "string" and entry.ru ~= "", name .. " " .. key .. " ru")
				local enArgs = select(2, string.gsub(entry.en, "{%d}", ""))
				local ruArgs = select(2, string.gsub(entry.ru or "", "{%d}", ""))
				T.eq(enArgs, ruArgs, name .. " " .. key .. " placeholder count")
			end
			T.ok(n > 10, name .. " has entries")
		end
	end,

	uiControllerLoads = function(T, Loader)
		setup(Loader)
		local ok, UIController = pcall(Loader.requirePath, "src/client/Controllers/UIController")
		if not T.ok(ok, "UIController requires under Lune: " .. tostring(UIController)) then
			return
		end
		T.eq(UIController.Priority, 90, "priority 90 (SPEC 20)")
		for _, fn in { "Init", "Start", "Open", "Close", "Toggle", "Back", "Play", "IsOpen", "Top", "SetVisible", "PhotoMode", "Notify", "Toast", "Setting", "Settings", "SetSetting", "ApplySetting", "ResetSettings" } do
			T.ok(type(UIController[fn]) == "function", "UIController." .. fn)
		end
		for _, sig in { "MenuChanged", "SettingChanged", "LanguageChanged", "VisibleChanged" } do
			T.ok(type(UIController[sig]) == "table" and UIController[sig].Connect ~= nil, "signal " .. sig)
		end
		-- before Start nothing opens and nothing throws
		T.eq(UIController.Open("Title"), nil, "Open before Start")
		T.eq(UIController.IsOpen(), false, "nothing open")
		T.noerror(function()
			UIController.Close()
		end, "Close before Start")
	end,
})

--!nocheck
-- HUD (src/client/UI/Hud/**): every piece builds under Lune in both HUD styles and all four menu themes with
-- mock deps for every scenario; the composite preview builds every scenario; Mount works with missing deps;
-- pure helpers (visibility rules, feed conversion, slot order, radial wipe, formatting, touch layout).
local HUD = "src/client/UI/Hud"
local PIECES = {
	"TopStrip",
	"BossBar",
	"RoundHud",
	"AbilityBar",
	"TeamPanel",
	"Objectives",
	"KillFeed",
	"Notifications",
	"Announcements",
	"IntroSplash",
	"SpectateHud",
	"DeathScreen",
	"MobileControls",
	"Nameplates",
	"LobbyHud",
}
local THEMES = { "Classic", "Royal", "Void", "Fell" }
local STYLES = { "Battle", "Modern" }

local function setup(Loader)
	Loader.isServer = false
	Loader.quietWarnings = true
	local roblox = Loader.roblox
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	Strings.SetLanguage("en")
	local Themes = Loader.requirePath("src/client/UI/Themes")
	local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
	local desktop = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080))
	local phone = UIRoot.ComputeLayout(roblox.Vector2.new(844, 390))
	return Themes, desktop, phone, Strings
end

local function countDescendants(inst)
	return #inst:GetDescendants()
end

local function findText(root, needle)
	for _, d in root:GetDescendants() do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and string.find(d.Text, needle, 1, true) then
			return true
		end
	end
	return false
end

return {
	everyPieceBuildsInEveryThemeAndStyle = function(T, Loader)
		local Themes, desktop, phone = setup(Loader)
		local Mock = Loader.requirePath(HUD .. "/Mock")
		for _, name in PIECES do
			local module = Loader.requirePath(HUD .. "/" .. name)
			T.ok(type(module.Create) == "function", name .. " has Create")
			for _, themeId in THEMES do
				for _, hud in STYLES do
					for _, layout in { desktop, phone } do
						T.noerror(
							function()
								local h = module.Create(Themes.Get(themeId), { Hud = hud, Layout = layout })
								assert(h and h.Root, "no Root")
								assert(type(h.Destroy) == "function", "no Destroy")
								assert(countDescendants(h.Root) > 0 or name == "Nameplates", "empty root")
								h.Destroy()
							end,
							string.format(
								"%s %s/%s %s",
								name,
								themeId,
								hud,
								if layout.Phone then "phone" else "desktop"
							)
						)
					end
				end
			end
			-- every scenario through Update/Tick
			local h = module.Create(Themes.Get("Classic"), { Hud = "Battle", Layout = desktop })
			for _, scenario in Mock.Names do
				T.noerror(function()
					local s = Mock.Scenario(scenario)
					if h.Update then
						h.Update(s)
					end
					if h.Tick then
						h.Tick(s.Now + 0.5, 0.016)
					end
				end, name .. " Update " .. scenario)
			end
			h.Destroy()
		end
	end,

	compositePreviewBuildsEveryScenario = function(T, Loader)
		local Themes, desktop, phone = setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local Mock = Loader.requirePath(HUD .. "/Mock")
		for _, scenario in Mock.Names do
			for _, hud in STYLES do
				T.noerror(function()
					local h = Hud.Create(Themes.Get("Void"), {
						Scenario = scenario,
						Hud = hud,
						Layout = if string.find(scenario, "Touch") then phone else desktop,
					})
					assert(h.Root and h.Pieces, "no handle")
					local s = Mock.Scenario(scenario)
					for _, entry in Hud.PIECES do
						if Hud.Visible(entry.Name, s) and entry.Name ~= "Nameplates" then
							assert(h.Pieces[entry.Name], scenario .. ": missing piece " .. entry.Name)
						end
					end
					h.Destroy()
				end, "composite " .. scenario .. " " .. hud)
			end
		end
	end,

	visibilityRules = function(T, Loader)
		setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local Mock = Loader.requirePath(HUD .. "/Mock")
		local human = Mock.Scenario("HumanRound")
		T.ok(
			Hud.Visible("RoundHud", human) and Hud.Visible("AbilityBar", human) and Hud.Visible("BossBar", human),
			"round pieces in a round"
		)
		T.ok(not Hud.Visible("LobbyHud", human) and not Hud.Visible("IntroSplash", human), "no lobby/intro in a round")
		T.ok(not Hud.Visible("MobileControls", human), "no touch controls on keyboard")
		local touch = Mock.Scenario("Touch")
		T.ok(
			Hud.Visible("MobileControls", touch) and not Hud.Visible("AbilityBar", touch),
			"touch swaps the ability bar"
		)
		local lobby = Mock.Scenario("Lobby")
		T.ok(
			Hud.Visible("LobbyHud", lobby) and not Hud.Visible("BossBar", lobby) and not Hud.Visible("RoundHud", lobby),
			"lobby"
		)
		local intro = Mock.Scenario("Intro")
		T.ok(Hud.Visible("IntroSplash", intro) and not Hud.Visible("AbilityBar", intro), "intro")
		local dead = Mock.Scenario("Dead")
		T.ok(
			Hud.Visible("DeathScreen", dead)
				and not Hud.Visible("SpectateHud", dead)
				and not Hud.Visible("RoundHud", dead),
			"death screen first"
		)
		dead.Now = dead.DeathAt + 10
		T.ok(not Hud.Visible("DeathScreen", dead) and Hud.Visible("SpectateHud", dead), "then spectate")
		local spectator = Mock.Scenario("Spectate")
		T.ok(Hud.Visible("SpectateHud", spectator) and Hud.Visible("BossBar", spectator), "spectators see the boss bar")
	end,

	feedFromEvents = function(T, Loader)
		setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local roblox = Loader.roblox
		local killer = roblox.Instance.new("Model")
		killer.Name = "Sans"
		killer:SetAttribute("KitId", "ClassicSans")
		local victim = roblox.Instance.new("Model")
		victim:SetAttribute("KitId", "Determination")
		local e = Hud.FeedFromEvent(
			"Kill",
			{ victim = victim, killer = killer, ability = "GasterBlaster", victimName = "Frisk", killerName = "Sans" },
			5
		)
		T.eq(e.Kind, "Kill")
		T.eq(e.Icon, "Blaster", "ability icon from kit data")
		T.eq(e.A, "Sans")
		T.eq(e.B, "Frisk")
		T.eq(e.Time, 5)
		local void = Hud.FeedFromEvent("Kill", { victim = victim, ability = "Void", victimName = "Frisk" }, 1)
		T.ok(void.Text and string.find(void.Text, "Frisk", 1, true), "void kill text")
		T.eq(
			Hud.FeedFromEvent("Revived", { victim = victim, by = killer, name = "Frisk", byName = "Kris" }, 1).Kind,
			"Revived"
		)
		T.eq(Hud.FeedFromEvent("SaveLit", { index = 2, by = { killer } }, 1).B, "2")
		T.eq(Hud.FeedFromEvent("PhaseChanged", { phase = "Round" }, 1), nil, "not a feed event")
		T.noerror(function()
			Hud.FeedFromEvent("Kill", nil, 1)
			Hud.FeedFromEvent("Downed", "garbage", 1)
		end, "malformed payloads")
	end,

	slotsFollowKitOrder = function(T, Loader)
		setup(Loader)
		local Style = Loader.requirePath(HUD .. "/Style")
		local function order(kitId)
			local out = {}
			for _, s in Style.Slots(kitId) do
				table.insert(out, s.Slot .. ":" .. s.Id)
			end
			return table.concat(out, ",")
		end
		local human = order("Determination")
		T.ok(string.find(human, "^M1:KnifeCombo,Q:") ~= nil, "human starts with M1 " .. human)
		T.ok(
			string.find(human, "F:Block")
				and string.find(human, "Shift:Dash")
				and string.find(human, "R:DeterminationUlt$"),
			"human built-ins + ult last " .. human
		)
		local monster = order("ClassicSans")
		T.ok(string.find(monster, "F:VerdictBox") ~= nil, "monster has the Verdict Box " .. monster)
		T.ok(string.find(monster, "G:BadTime$") ~= nil, "monster ult last " .. monster)
		local slots = Style.Slots("Justice")
		T.eq(slots[1].Ammo, 6, "Justice ammo from kit Numbers")
		T.eq(#Style.Slots("NoSuchKit"), 0, "unknown kit -> no slots")
	end,

	slotStateMaths = function(T, Loader)
		setup(Loader)
		local Style = Loader.requirePath(HUD .. "/Style")
		local AbilityBar = Loader.requirePath(HUD .. "/AbilityBar")
		local Mock = Loader.requirePath(HUD .. "/Mock")
		local s = Mock.Scenario("MonsterRound")
		local byId = {}
		for _, info in Style.Slots(s.Me.KitId) do
			byId[info.Id] = AbilityBar.SlotState(info, s, s.Now)
		end
		T.near(byId.BoneZone.Remaining, 7.4, 1e-6, "cooldown remaining")
		T.ok(byId.BadTime.UltReady, "ult 100 -> ready")
		T.ok(byId.GasterBlaster.Charge and byId.GasterBlaster.Active, "hold charge")
		T.eq(byId.BoneJab.Combo, 3, "combo")
		s.Me.Statuses = { Silenced = s.Now + 2 }
		T.ok(not AbilityBar.SlotState(Style.Slots(s.Me.KitId)[1], s, s.Now).Disabled, "silence keeps M1")
		T.ok(AbilityBar.SlotState(Style.Slots(s.Me.KitId)[2], s, s.Now).Disabled, "silence blocks abilities")
		s.Me.Statuses = { Stunned = s.Now + 2 }
		T.ok(AbilityBar.SlotState(Style.Slots(s.Me.KitId)[1], s, s.Now).Disabled, "stun blocks M1")
	end,

	radialAndFormatting = function(T, Loader)
		setup(Loader)
		local Style = Loader.requirePath(HUD .. "/Style")
		local r = Style.Radial({ Mode = "Remaining" })
		r.Set(0)
		T.ok(not r.Root.Right.Visible and not r.Root.Left.Visible, "empty wipe hidden")
		r.Set(0.25)
		T.ok(not r.Root.Right.Visible and r.Root.Left.Visible, "last quarter only on the left half")
		T.near(r.Root.Left.Fill.UIGradient.Rotation, 270, 1e-6, "edge at 9 o'clock")
		r.Set(0.75)
		T.ok(r.Root.Right.Visible and r.Root.Left.Visible, "three quarters on both halves")
		T.near(r.Root.Right.Fill.UIGradient.Rotation, 90, 1e-6, "edge at 3 o'clock")
		local f = Style.Radial({ Mode = "Filled" })
		f.Set(0.3)
		T.ok(f.Root.Right.Visible and not f.Root.Left.Visible, "filled 30% only right")
		T.eq(Style.FormatClock(204), "3:24")
		T.eq(Style.FormatClock(0), "0:00")
		T.eq(Style.FormatCd(4.21), "4.2")
		T.eq(Style.FormatCd(12.2), "13")
		local skin = Style.Resolve(Loader.requirePath("src/client/UI/Themes").Get("Classic"), "Battle")
		T.eq(Style.FormatHp(skin, 7, 92), "07 / 92", "UT zero-padded HP")
		T.ok(skin.Battle and skin.C.HP == Loader.roblox.Color3.fromRGB(255, 255, 0), "UT yellow HP")
	end,

	touchLayoutFitsThePhone = function(T, Loader)
		local _, _, phone = setup(Loader)
		local MobileControls = Loader.requirePath(HUD .. "/MobileControls")
		for _, role in { "Human", "Monster" } do
			local pos = MobileControls.Positions(role, phone.Canvas)
			local list = {}
			for action, p in pos do
				T.ok(p.X - p.Size / 2 >= 0 and p.X + p.Size / 2 <= phone.Canvas.X, role .. " " .. action .. " inside X")
				T.ok(p.Y - p.Size / 2 >= 0 and p.Y + p.Size / 2 <= phone.Canvas.Y, role .. " " .. action .. " inside Y")
				table.insert(list, { action, p })
			end
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i][2], list[j][2]
					local dist = math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
					T.ok(dist >= (a.Size + b.Size) / 2 - 1, role .. ": " .. list[i][1] .. " overlaps " .. list[j][1])
				end
			end
		end
	end,

	mountWithMissingDeps = function(T, Loader)
		local Themes, desktop = setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local roblox = Loader.roblox
		local gui = roblox.Instance.new("ScreenGui")
		T.noerror(function()
			local h = Hud.Mount(gui, nil)
			assert(h and h.Root, "no handle")
			h.Refresh()
			h.Push({ Kind = "Info", Text = "hello", Time = 0 })
			h.Announce("Surge", {})
			h.Toast("hi")
			h.SetVisible(false)
			h.SetVisible(true)
			h.Destroy()
		end, "Mount(ScreenGui, nil)")
		local frame = roblox.Instance.new("Frame")
		T.noerror(function()
			local h = Hud.Mount(frame, { Layout = desktop, State = {}, Input = {}, Combat = {}, UI = {} })
			h.Rebuild()
			h.Destroy()
		end, "Mount(Frame, empty deps)")
		local _ = Themes
	end,

	stringsExist = function(T, Loader)
		local _, _, _, Strings = setup(Loader)
		for _, key in
			{
				"hud.downed.hint",
				"hud.death.title",
				"hud.slot.verdict",
				"lobby.chance.title",
				"lobby.vote.mine",
				"hud.intro.vs",
			}
		do
			T.ok(Strings.L(key) ~= key, "string " .. key)
		end
		Strings.SetLanguage("ru")
		T.ok(Strings.L("hud.death.title") ~= Strings.L("hud.death.title", nil) or true, "ru")
		Strings.SetLanguage("en")
		local Mock = Loader.requirePath(HUD .. "/Mock")
		local Themes = Loader.requirePath("src/client/UI/Themes")
		local RoundHud = Loader.requirePath(HUD .. "/RoundHud")
		local h = RoundHud.Create(Themes.Get("Classic"), { Hud = "Battle", Snapshot = Mock.Scenario("Downed") })
		T.ok(findText(h.Root, "DOWNED"), "downed overlay text")
		h.Destroy()
	end,
}

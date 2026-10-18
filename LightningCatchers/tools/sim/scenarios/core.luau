--!nocheck
-- Core scenario: two deterministic players play the core loop for 12+ simulated minutes.
--  join -> DataSync -> catch rings on island 1 (perfect/good/miss mix, some ignored) -> sell at the SellPad ->
--  buy upgrades via ClientState.request -> (cheat Volts) unlock island 2 and move there -> hatch a cocoon
--  (cheat shards), equip pets -> daily reward, codes (request + UI), quests -> open/close every window ->
--  settings -> hub + kiosks (ProximityPrompt) -> UI button fuzz -> rebirth (cheat) -> Supercell (4:00) and
--  Ball lightning (10:00) events -> player leaves (save) and rejoins (load) -> server shutdown (BindToClose).
local roblox = require("@lune/roblox")
local Bot = require("../lib/bot")
local Services = require("../lib/services")

local Vector2, Vector3, CFrame, Enum = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Enum

local Core = {}

function Core.run(S, cfg)
	cfg = cfg or {}
	local Runtime, Sched, World, Engine, Realm, Report = S.Runtime, S.Sched, S.World, S.Engine, S.Realm, S.Report
	local DATA = Engine.DATA
	local readProp = Engine.readProp
	local T = cfg.times or {}
	local function at(name, default)
		return T[name] or default
	end
	local totalMinutes = S.opts.minutes or cfg.minutes or 12.5
	local checks = {}
	local function check(name, ok, detail)
		table.insert(checks, { name = name, ok = ok, detail = detail })
		if not ok then
			Report.add("check", "scenario", "CHECK FAILED: " .. name .. (if detail then " — " .. detail else ""), {})
		end
	end

	-- optional Config patch (fast scenario): pre-require Config in a realm and patch the table
	local function patchConfig(realm)
		if cfg.patchConfig then
			local inst = Runtime.find("ReplicatedStorage.Shared.Config", nil)
			local Config = Runtime.requireIn(realm, inst)
			cfg.patchConfig(Config)
		end
	end
	patchConfig(World.server)

	Runtime.startServer()
	Sched.runUntil(1)

	local function serverModule(name)
		local inst = Runtime.find("ServerScriptService.Server.Services." .. name, nil)
		return inst and Realm.module(World.server, inst)
	end
	local function inServer(fn)
		local ok, res
		local co = Sched.spawn(World.server, function()
			ok, res = pcall(fn)
		end)
		Sched.flush()
		return ok, res
	end

	-- spy on remote traffic for metrics and shard positions
	local bots = {}
	local botByRealm = {}
	World.spy.onClientEvent = function(realm, name, args)
		local b = botByRealm[realm]
		if not b then
			return
		end
		if name == "ShardSpawn" and type(args[1]) == "table" then
			b.metrics.shardsSeen += 1
			table.insert(b.shards, { pos = args[1].Pos, expires = args[1].Expires })
		elseif name == "Banner" then
			b.metrics.banners += 1
		elseif name == "DataSync" then
			if not b.metrics.firstDataSync then
				b.metrics.firstDataSync = Sched.now
			end
		end
	end

	local function join(userId, name, viewport, touch, skill)
		local realm = Runtime.addPlayer({ userId = userId, name = name, viewport = viewport, touch = touch })
		patchConfig(realm)
		local b = Bot.new(realm, skill)
		botByRealm[realm] = b
		return b
	end

	-- per-frame bot driver (registered before anyone joins)
	table.insert(Sched.frameHooks, function()
		for _, b in bots do
			if not b.realm.dead then
				if not b.attached then
					b:attach()
				end
				local ok, err = pcall(b.step, b)
				if not ok then
					Report.add("runtime", "harness", "[harness] bot step failed: " .. tostring(err), {})
				end
			end
		end
	end)

	World.friends[1001] = { [1002] = true }
	World.friends[1002] = { [1001] = true }

	local skill1 = { perfect = 0.55, good = 0.30, ignore = 0.06, seed = 11, overcharge = 1.25 }
	local skill2 = { perfect = 0.30, good = 0.42, ignore = 0.12, seed = 23, overcharge = 1.1 }
	local b1 = join(1001, "BotOne", Vector2.new(1366, 768), false, skill1)
	table.insert(bots, b1)
	Sched.runUntil(2.5)
	local b2 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2)
	table.insert(bots, b2)

	-- wait for DataSync and characters
	Sched.runUntil(at("ready", 12))
	for _, b in bots do
		check(b.name .. " received DataSync within 10 s of joining", b.metrics.firstDataSync ~= nil and b.metrics.firstDataSync - b.metrics.joinedAt < 10, "first DataSync at " .. tostring(b.metrics.firstDataSync))
		check(b.name .. " has a character", b:root() ~= nil)
		check(b.name .. " is on island 1", b:zone() == 1, "Zone attribute = " .. tostring(b:zone()))
		b.active = true
		b.allowBuy = true
		local home = b:homePos(1)
		if home then
			b:teleport(home)
		end
	end

	local requestLog = {}
	local function req(b, action, payload, label)
		b:request(action, payload, function(ok, res)
			table.insert(requestLog, string.format("%s %s(%s) -> %s %s", b.name, action, label or tostring(payload), if ok then "ok" else "FAIL", tostring(res)))
		end)
	end

	local function serverData(b)
		local DataService = serverModule("DataService")
		return DataService and DataService.get(b.pd.proxy)
	end

	local function grant(b, volts, shards)
		local Economy = serverModule("EconomyService")
		inServer(function()
			if volts and volts > 0 then
				Economy.grantVolts(b.pd.proxy, volts, "sim-cheat")
			end
			if shards and shards > 0 then
				Economy.grantShards(b.pd.proxy, shards)
			end
		end)
	end

	local function setZoneCheat(b, zone)
		local DataService = serverModule("DataService")
		inServer(function()
			DataService.update(b.pd.proxy, function(d)
				if d.Zone < zone then
					d.Zone = zone
				end
			end)
		end)
	end

	-- event observation
	local eventsSeen = {}
	local gs = Runtime.find("ReplicatedStorage.GameState", nil)
	table.insert(Sched.frameHooks, function()
		if not gs then
			gs = Runtime.find("ReplicatedStorage.GameState", nil)
			return
		end
		local ev = DATA[gs].attrs.Event
		if type(ev) == "string" and ev ~= "" and not eventsSeen[ev] then
			eventsSeen[ev] = Sched.now
			Report.logLine(string.format("[%s] event started: %s", Report.fmtTime(Sched.now), ev))
		end
		local lit = DATA[gs].attrs.CityLit
		if type(lit) == "number" and lit > (eventsSeen.cityLitMax or 0) then
			eventsSeen.cityLitMax = lit
		end
	end)

	local function runTo(t)
		Sched.runUntil(t)
	end

	----------------------------------------------------------------
	-- Island 1: play
	----------------------------------------------------------------
	runTo(at("cheatIsland2", 150))
	local Economy = b1:sharedModule("Economy")
	for _, b in bots do
		local sd = serverData(b)
		check(b.name .. " caught something on island 1", sd ~= nil and sd.Stats.Catches > 0, sd and ("catches=" .. sd.Stats.Catches) or "no data")
		check(b.name .. " sold at the SellPad", sd ~= nil and sd.Stats.Sells > 0, sd and ("sells=" .. sd.Stats.Sells) or "no data")
		-- cheat: enough Volts for island 2
		local cost = Economy.zoneCost(2)
		grant(b, cost + 200)
		b.allowUnlock = true
		b.followUnlock = true
	end
	runTo(at("checkIsland2", 165))
	for _, b in bots do
		local sd = serverData(b)
		check(b.name .. " unlocked island 2", sd ~= nil and sd.Zone >= 2, sd and ("Zone=" .. sd.Zone) or "no data")
		if b:zone() ~= 2 then
			req(b, "Teleport", 2)
		end
	end
	runTo(at("hatch", 180))
	for _, b in bots do
		check(b.name .. " teleported to island 2", b:zone() == 2, "Zone attribute = " .. tostring(b:zone()))
		b.allowUnlock = false
		local home = b:homePos(2)
		if home then
			b:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Pets: hatch (cheat shards), equip
	----------------------------------------------------------------
	local Pets = b1:sharedModule("Pets")
	local cocoonCost = Pets and Pets.Cocoons and Pets.Cocoons.meadow and Pets.Cocoons.meadow.Cost or 25
	for _, b in bots do
		grant(b, nil, cocoonCost * 3 + 10)
	end
	runTo(at("hatch", 180) + 1)
	local hatched = {}
	req(b1, "Hatch", "meadow")
	b1:request("Hatch", "meadow", function(ok, res)
		table.insert(requestLog, "BotOne Hatch(meadow) -> " .. tostring(ok) .. " " .. (if type(res) == "table" then tostring(res.Kind) .. "#" .. tostring(res.Id) else tostring(res)))
		if ok and type(res) == "table" then
			hatched[b1] = res
			req(b1, "EquipPet", res.Id)
		end
	end)
	-- BotTwo hatches through the Pets UI (window "Pets:cocoons", button "Hatch" of the meadow cocoon)
	b2:run(function()
		local cs = b2:state()
		cs.OpenWindow:Fire("Pets:cocoons")
	end)
	runTo(at("hatch", 180) + 2)
	do
		local win = b2:findGui("Window_Pets")
		local meadow = win and b2:findDesc(win, "meadow")
		local btn = meadow and b2:findDesc(meadow, "Hatch", "GuiButton")
		check("BotTwo: Pets window has a meadow cocoon Hatch button", btn ~= nil)
		if btn then
			b2:click(btn)
		end
	end
	runTo(at("hatch", 180) + 8)
	do
		local ui = b2:clientModule("Client.UI.UIKit")
		b2:run(function()
			ui.closeWindows()
		end)
		req(b2, "EquipBest", nil)
	end
	runTo(at("hatch", 180) + 10)
	for _, b in bots do
		local sd = serverData(b)
		check(b.name .. " has a pet after hatching", sd ~= nil and #sd.Pets > 0, sd and ("pets=" .. #sd.Pets .. " shards=" .. sd.Shards) or "no data")
		check(b.name .. " has an equipped pet", sd ~= nil and #sd.Equipped > 0, sd and ("equipped=" .. #sd.Equipped) or "no data")
	end

	----------------------------------------------------------------
	-- Daily, codes, quests
	----------------------------------------------------------------
	runTo(at("daily", 195))
	req(b1, "ClaimDaily", nil)
	req(b1, "RedeemCode", "МОЛНИЯ")
	req(b1, "RedeemCode", "молния", "молния (again, lowercase)")
	req(b1, "RedeemCode", "НЕТТАКОГО")
	for q = 1, 3 do
		req(b1, "ClaimQuest", q)
	end
	-- BotTwo: daily + code through the Daily window
	b2:run(function()
		b2:state().OpenWindow:Fire("Daily")
	end)
	runTo(at("daily", 195) + 1.5)
	do
		local win = b2:findGui("Window_Daily")
		local claim = win and b2:findDesc(win, "Calendar") and b2:findDesc(b2:findDesc(win, "Calendar"), "Claim", "GuiButton") or (win and b2:findDesc(win, "Claim", "GuiButton"))
		if claim then
			b2:click(claim)
		end
		-- the window ignores clicks while a request is in flight
		Sched.runUntil(Sched.now + 1)
		local input = win and b2:findDesc(win, "Input", "TextBox")
		local redeem = win and b2:findDesc(win, "Redeem", "GuiButton")
		check("BotTwo: Daily window has a code box and an OK button", input ~= nil and redeem ~= nil)
		if input and redeem then
			b2:run(function()
				input.proxy.Text = "ГРОЗА"
			end)
			Sched.flush()
			b2:click(redeem)
		end
	end
	runTo(at("daily", 195) + 4)
	b2:run(function()
		b2:clientModule("Client.UI.UIKit").closeWindows()
	end)
	do
		local sd = serverData(b1)
		check("BotOne redeemed МОЛНИЯ", sd ~= nil and sd.Codes and (sd.Codes["МОЛНИЯ"] == true), sd and ("codes=" .. table.concat((function()
			local t = {}
			for k in sd.Codes or {} do
				table.insert(t, k)
			end
			return t
		end)(), ",")) or "")
		local sd2 = serverData(b2)
		check("BotTwo redeemed ГРОЗА through the UI", sd2 ~= nil and sd2.Codes and sd2.Codes["ГРОЗА"] == true)
	end

	----------------------------------------------------------------
	-- Every window: open and close
	----------------------------------------------------------------
	runTo(at("windows", 205))
	local windows = { "Shop", "Shop:upgrades", "Shop:islands", "Shop:drone", "Upgrades", "Islands", "Drone", "Pets", "Pets:mine", "Pets:cocoons", "Hatchery", "Collection", "Collection:fulgs", "Collection:index", "Gallery", "Index", "Teleport", "Rebirth", "Daily", "Quests", "Settings" }
	for i, w in windows do
		for _, b in bots do
			b:run(function()
				b:state().OpenWindow:Fire(w)
			end)
		end
		runTo(at("windows", 205) + i * 0.7)
		for _, b in bots do
			local open = 0
			local g = b:playerGui()
			for _, c in Engine.childrenOf(g, b.realm) do
				local cd = DATA[c]
				if string.sub(cd.props.Name, 1, 7) == "Window_" and readProp(cd, "Enabled", b.realm) ~= false then
					open += 1
				end
			end
			if open == 0 then
				Report.add("check", b.realm.name, "OpenWindow(\"" .. w .. "\") did not enable any Window_* ScreenGui", {})
			end
			b:run(function()
				b:clientModule("Client.UI.UIKit").closeWindows()
			end)
		end
		runTo(at("windows", 205) + i * 0.7 + 0.35)
	end

	----------------------------------------------------------------
	-- Settings
	----------------------------------------------------------------
	runTo(at("settings", 222))
	do
		local d = b1:data()
		if d then
			local s = table.clone(d.Settings)
			s.Music = false
			s.Sfx = false
			s.SoftFlash = not s.SoftFlash
			s.Shake = not s.Shake
			s.Offset = 40
			req(b1, "SetSettings", s, "toggled")
		end
		-- BotTwo: click every toggle in the Settings window
		b2:run(function()
			b2:state().OpenWindow:Fire("Settings")
		end)
	end
	runTo(at("settings", 222) + 1)
	do
		local win = b2:findGui("Window_Settings")
		if win then
			for _, btn in b2:visibleButtons(win) do
				if btn.props.Name ~= "Close" then
					b2:click(btn)
				end
			end
		end
	end
	runTo(at("settings", 222) + 4)
	b2:run(function()
		b2:clientModule("Client.UI.UIKit").closeWindows()
	end)
	do
		local sd = serverData(b1)
		check("BotOne settings saved (Music off, Offset 40)", sd ~= nil and sd.Settings.Music == false and sd.Settings.Offset == 40, sd and string.format("Music=%s Offset=%s", tostring(sd.Settings.Music), tostring(sd.Settings.Offset)) or "")
		local d = b1:data()
		if d then
			local s = table.clone(d.Settings)
			s.Music = true
			s.Sfx = true
			s.Offset = 0
			req(b1, "SetSettings", s, "restored")
		end
	end

	----------------------------------------------------------------
	-- Hub, kiosks (ProximityPrompts), back to island 2
	----------------------------------------------------------------
	runTo(at("hub", 232))
	for _, b in bots do
		b.active = false
		req(b, "Teleport", 0)
	end
	runTo(at("hub", 232) + 2)
	for _, b in bots do
		check(b.name .. " teleported to the hub", b:zone() == 0, "Zone attribute = " .. tostring(b:zone()))
	end
	local kiosks = { "Kiosk_Shop", "Kiosk_Hatchery", "Kiosk_Gallery", "Kiosk_Rebirth", "Kiosk_Daily" }
	for i, k in kiosks do
		local pos = b1:markerPos(k)
		if pos then
			b1:teleport(pos - Vector3.new(0, 1, 0))
		else
			Report.add("check", "scenario", "map marker missing: " .. k, {})
		end
		runTo(at("hub", 232) + 2 + i * 1.2)
		local marker = Runtime.find("Workspace.Map.Markers." .. k, nil)
		local prompt = marker and Engine.findChild(DATA[marker], "KioskPrompt", nil)
		if prompt then
			local shown = b1.realm.shownPrompts and b1.realm.shownPrompts[DATA[prompt]]
			check("BotOne sees the " .. k .. " prompt when standing at it", shown == true)
			Runtime.triggerPrompt(b1.realm, DATA[prompt])
		else
			check("ProximityPrompt exists on " .. k, false)
		end
		runTo(at("hub", 232) + 2 + i * 1.2 + 0.6)
		local open = 0
		for _, c in Engine.childrenOf(b1:playerGui(), b1.realm) do
			local cd = DATA[c]
			if string.sub(cd.props.Name, 1, 7) == "Window_" and readProp(cd, "Enabled", b1.realm) ~= false then
				open += 1
			end
		end
		check("triggering " .. k .. " opened a window on the client", open > 0)
		b1:run(function()
			b1:clientModule("Client.UI.UIKit").closeWindows()
		end)
	end
	-- the hub SellPad (ring around the Tesla tower)
	b2:teleport(b2:markerPos("SellPad_0") or Vector3.new(0, 0, 0))
	runTo(at("hub", 232) + 12)
	for _, b in bots do
		req(b, "Teleport", 2)
	end
	runTo(at("hub", 232) + 14)
	for _, b in bots do
		local home = b:homePos(2)
		if home then
			b:teleport(home)
		end
		b.active = true
	end

	----------------------------------------------------------------
	-- UI fuzz: click every visible button of every window (BotTwo, phone)
	----------------------------------------------------------------
	runTo(at("fuzz", 255))
	local fuzzWindows = { "Shop", "Pets", "Collection", "Teleport", "Rebirth", "Daily", "Settings" }
	local clicked = 0
	for i, w in fuzzWindows do
		b2:run(function()
			b2:state().OpenWindow:Fire(w)
		end)
		runTo(at("fuzz", 255) + i * 3)
		local win = nil
		for _, c in Engine.childrenOf(b2:playerGui(), b2.realm) do
			local cd = DATA[c]
			if string.sub(cd.props.Name, 1, 7) == "Window_" and readProp(cd, "Enabled", b2.realm) ~= false then
				win = cd
			end
		end
		if win then
			for _, btn in b2:visibleButtons(win) do
				local n = btn.props.Name
				if n ~= "Close" and n ~= "Backdrop" then
					b2:click(btn)
					clicked += 1
					Sched.step()
				end
			end
		end
		runTo(at("fuzz", 255) + i * 3 + 2)
		b2:run(function()
			b2:clientModule("Client.UI.UIKit").closeWindows()
		end)
	end
	-- HUD menu buttons too
	do
		local hud = b2:findGui("HUD")
		if hud then
			for _, btn in b2:visibleButtons(hud) do
				if btn.props.Name ~= "CatchButton" then
					b2:click(btn)
					clicked += 1
					Sched.step()
					b2:run(function()
						b2:clientModule("Client.UI.UIKit").closeWindows()
					end)
				end
			end
		end
	end
	check("UI fuzz clicked buttons", clicked > 10, "clicked " .. clicked)

	----------------------------------------------------------------
	-- Rebirth (cheat: island 4 + enough Volts)
	----------------------------------------------------------------
	runTo(at("rebirth", 300))
	do
		local sd = serverData(b1)
		local cost = Economy.rebirthCost(sd and sd.Rebirths or 0)
		setZoneCheat(b1, 4)
		grant(b1, cost + 1000)
	end
	runTo(at("rebirth", 300) + 1)
	b1:run(function()
		b1:state().OpenWindow:Fire("Rebirth")
	end)
	runTo(at("rebirth", 300) + 2)
	b1:run(function()
		b1:clientModule("Client.UI.UIKit").closeWindows()
	end)
	req(b1, "Rebirth", nil)
	runTo(at("rebirth", 300) + 5)
	do
		local sd = serverData(b1)
		check("BotOne rebirthed (Rebirths=1, Zone=1, Volts reset)", sd ~= nil and sd.Rebirths == 1 and sd.Zone == 1, sd and string.format("Rebirths=%d Zone=%d Volts=%d", sd.Rebirths, sd.Zone, sd.Volts) or "")
		check("BotOne is back on island 1 after rebirth", b1:zone() == 1, "Zone attribute = " .. tostring(b1:zone()))
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Tesla drone (cheat: island 3 + Volts), play on island 3
	----------------------------------------------------------------
	local Config = b1:sharedModule("Config")
	runTo(at("drone", 312))
	setZoneCheat(b2, 3)
	grant(b2, Config.Drone.Cost + 500)
	runTo(at("drone", 312) + 1)
	req(b2, "BuyDrone", nil)
	runTo(at("drone", 312) + 2)
	req(b2, "ToggleDrone", false)
	runTo(at("drone", 312) + 3)
	req(b2, "ToggleDrone", true)
	req(b2, "Teleport", 3)
	runTo(at("drone", 312) + 5)
	do
		local sd = serverData(b2)
		check("BotTwo bought the drone", sd ~= nil and sd.Drone == true and sd.DroneOn == true, sd and string.format("Drone=%s DroneOn=%s", tostring(sd.Drone), tostring(sd.DroneOn)) or "")
		check("BotTwo teleported to island 3", b2:zone() == 3, "Zone attribute = " .. tostring(b2:zone()))
		b2.skill.overcharge = 1.0
		local home = b2:homePos(3)
		if home then
			b2:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Closed island barrier (BotOne only has island 1 after the rebirth)
	----------------------------------------------------------------
	runTo(at("barrier", 325))
	do
		local Zones = b1:sharedModule("Zones")
		local gate = b1:markerPos("Gate_2")
		local c2 = Zones.Geo[2].Center
		if gate then
			b1.active = false
			local dir = Vector3.new(c2.X - gate.X, 0, c2.Z - gate.Z).Unit
			b1:teleport(Vector3.new(gate.X, Zones.groundY(0), gate.Z) + dir * 6 - Vector3.new(0, 0, 0))
			runTo(at("barrier", 325) + 1.5)
			local p = b1:pos()
			local gateDist = (Vector3.new(gate.X, 0, gate.Z) - Vector3.new(c2.X, 0, c2.Z)).Magnitude
			local myDist = p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(c2.X, 0, c2.Z)).Magnitude or 0
			check("closed island 2: the server pushes BotOne back from behind the barrier", p ~= nil and myDist > gateDist, string.format("dist to island 2 centre %.1f, gate at %.1f", myDist, gateDist))
			check("closed island 2: Zone attribute did not become 2", b1:zone() ~= 2, "Zone=" .. tostring(b1:zone()))
		else
			check("map marker Gate_2 exists", false)
		end
		req(b1, "Teleport", 1)
		runTo(at("barrier", 325) + 3)
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
		b1.active = true
	end

	----------------------------------------------------------------
	-- Falling into the void (BotTwo on island 3)
	----------------------------------------------------------------
	runTo(at("void", 335))
	do
		b2.active = false
		local p = b2:pos()
		if p then
			b2:run(function()
				local r = b2:root()
				r.proxy.CFrame = CFrame.new(p.X + 40, Config.VoidY - 30, p.Z)
			end)
		end
		runTo(at("void", 335) + 1.5)
		local q = b2:pos()
		check("fell into the void: the server returned BotTwo onto the island", q ~= nil and q.Y > Config.VoidY + 10, "Y=" .. tostring(q and q.Y))
		check("fell into the void: still on island 3", b2:zone() == 3, "Zone=" .. tostring(b2:zone()))
		b2.active = true
	end

	----------------------------------------------------------------
	-- Death and respawn (BotOne)
	----------------------------------------------------------------
	runTo(at("death", 345))
	do
		local oldChar = b1.pd.props.Character
		inServer(function()
			local hum = oldChar and oldChar:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
		end)
		runTo(at("death", 345) + 9)
		local char = b1.pd.props.Character
		check("BotOne respawned after dying", char ~= nil and char ~= oldChar)
		if char then
			local cd = DATA[char]
			local rod = nil
			for _, c in Engine.childrenOf(cd, nil) do
				if DATA[c].cls.isA.Tool then
					rod = c
				end
			end
			check("respawned character holds the lightning rod", rod ~= nil)
			check("respawned character has the jar", Engine.findChild(cd, "Jar", nil) ~= nil)
			check("respawned on island 1", b1:zone() == 1, "Zone=" .. tostring(b1:zone()))
		end
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Island 5 (runner rings, Perun possible) for a minute, then back to island 3
	----------------------------------------------------------------
	runTo(at("island5", 380))
	setZoneCheat(b2, 5)
	runTo(at("island5", 380) + 0.5)
	req(b2, "Teleport", 5)
	runTo(at("island5", 380) + 2)
	check("BotTwo teleported to island 5", b2:zone() == 5, "Zone=" .. tostring(b2:zone()))
	do
		local home = b2:homePos(5)
		if home then
			b2:teleport(home)
		end
	end
	runTo(at("island5", 380) + 70)
	req(b2, "Teleport", 3)
	runTo(at("island5", 380) + 72)
	do
		local home = b2:homePos(3)
		if home then
			b2:teleport(home)
		end
	end

	local census1 = Runtime.census()

	----------------------------------------------------------------
	-- Long play: events (Supercell at 4:00, Ball lightning at 10:00)
	----------------------------------------------------------------
	local leaveAt = math.max(at("leave", totalMinutes * 60 - 80), at("island5", 380) + 90)
	runTo(leaveAt)
	if cfg.expectEvents ~= false then
		if Sched.now >= (cfg.supercellAt or Config.Events.Supercell.Offset) + 5 then
			check("Supercell event happened", eventsSeen.supercell ~= nil, "events seen: " .. (function()
				local t = {}
				for k, v in eventsSeen do
					table.insert(t, k .. "@" .. tostring(v))
				end
				return table.concat(t, " ")
			end)())
		end
		if Sched.now >= (cfg.ballAt or Config.Events.BallLightning.Offset) + 5 then
			check("Ball lightning event happened", eventsSeen.ball ~= nil)
		end
		if cfg.rainbowAt and Sched.now >= cfg.rainbowAt + 15 then
			check("Rainbow event happened", eventsSeen.rainbow ~= nil)
		end
	end

	----------------------------------------------------------------
	-- Leave (save) and rejoin (load)
	----------------------------------------------------------------
	local before = Services.deepCopy(serverData(b2))
	b2.active = false
	Runtime.removePlayer(b2.pd, "leave")
	runTo(leaveAt + 4)
	local store = nil
	for k, s in Services.stores do
		if s.kind == "global" and string.find(k, "PlayerData", 1, true) then
			store = s
		end
	end
	local rec = store and store.data["u_1002"]
	check("DataStore has a record for BotTwo after leaving", rec ~= nil and type(rec.Data) == "table")
	if rec and type(rec.Data) == "table" and before then
		local d = rec.Data
		check("saved Volts match the session", d.Volts == before.Volts, string.format("saved %s vs session %s", tostring(d.Volts), tostring(before.Volts)))
		check("saved TotalVolts match", d.TotalVolts == before.TotalVolts)
		check("saved Zone/Upgrades match", d.Zone == before.Zone and d.Upgrades and d.Upgrades.Rod == before.Upgrades.Rod and d.Upgrades.Jar == before.Upgrades.Jar)
		check("saved pets match", type(d.Pets) == "table" and #d.Pets == #before.Pets, string.format("saved %s vs %d", tostring(type(d.Pets) == "table" and #d.Pets), #before.Pets))
		check("session lock released on leave", rec.Lock == nil, "Lock=" .. tostring(rec.Lock and rec.Lock.Id))
	end
	runTo(leaveAt + 6)
	local b3 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2)
	table.insert(bots, b3)
	runTo(leaveAt + 18)
	do
		local d = b3:data()
		check("rejoined BotTwo received DataSync", d ~= nil)
		if d and before then
			check("loaded Volts match the saved session", math.abs(d.Volts - before.Volts) < 1e-6, string.format("loaded %s vs before %s", tostring(d.Volts), tostring(before.Volts)))
			check("loaded Zone matches", d.Zone == before.Zone, string.format("loaded %s vs %s", tostring(d.Zone), tostring(before.Zone)))
			check("loaded pets match", #d.Pets == #before.Pets)
			check("loaded Shards match", d.Shards == before.Shards, string.format("loaded %s vs %s", tostring(d.Shards), tostring(before.Shards)))
			check("loaded codes kept", (d.Codes or {})["ГРОЗА"] == (before.Codes or {})["ГРОЗА"])
		end
		check("rejoined BotTwo spawned on its last island", b3:zone() == (before and math.min(before.LastZone, before.Zone) or 2), "Zone attribute = " .. tostring(b3:zone()))
		b3.active = true
		b3.allowBuy = true
		local home = b3:homePos()
		if home then
			b3:teleport(home)
		end
	end
	runTo(leaveAt + 30)

	----------------------------------------------------------------
	-- Next day (os.time() +24 h): daily reward day 2, new quests; offline income on rejoin
	----------------------------------------------------------------
	for _, b in bots do
		b.active = false
	end
	runTo(leaveAt + 34)
	local questDayBefore = serverData(b1) and serverData(b1).Quests.Day
	Sched.osTimeOffset = 86400
	b1:request("ClaimDaily", nil, function(ok, res)
		table.insert(requestLog, "BotOne ClaimDaily (next day) -> " .. tostring(ok) .. " " .. tostring(res))
		check("next day: daily reward can be claimed again", ok == true, tostring(res))
	end)
	runTo(leaveAt + 36)
	do
		local sd = serverData(b1)
		check("next day: daily streak advanced to 2", sd ~= nil and sd.Daily.Streak == 2, sd and ("Streak=" .. tostring(sd.Daily.Streak)) or "")
	end
	-- BotTwo leaves and comes back "a day later": offline income (Welcome)
	local b3d = serverData(b3)
	local incomeRate = b3d and b3d.IncomeRate or 0
	b3.active = false
	Runtime.removePlayer(b3.pd, "leave")
	runTo(leaveAt + 40)
	Sched.osTimeOffset = 86400 * 2
	local b4 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2)
	table.insert(bots, b4)
	runTo(leaveAt + 52)
	do
		local sd = serverData(b4)
		check("offline income accrued after a day away (IncomeRate " .. string.format("%.0f", incomeRate) .. "/min)", sd ~= nil and (incomeRate <= 0 or sd.Welcome > 0), sd and ("Welcome=" .. tostring(sd.Welcome)) or "")
		local win = b4:findGui("Window_Welcome")
		local shown = win and Engine.readProp(win, "Enabled", b4.realm) ~= false
		check("WelcomeUI is shown on rejoin with offline income", (sd and sd.Welcome or 0) <= 0 or shown == true)
		if win and shown then
			local buttons = b4:visibleButtons(win)
			for _, btn in buttons do
				if btn.props.Name ~= "Close" then
					b4:click(btn)
					break
				end
			end
		end
		local welcome = sd and sd.Welcome or 0
		local voltsBefore = sd and sd.Volts or 0
		runTo(leaveAt + 56)
		local sd2 = serverData(b4)
		if welcome > 0 then
			check("ClaimWelcome through the Welcome window added the Volts", sd2 ~= nil and sd2.Welcome == 0 and sd2.Volts >= voltsBefore + welcome - 1, sd2 and string.format("Welcome=%s Volts %s -> %s", tostring(sd2.Welcome), tostring(voltsBefore), tostring(sd2.Volts)) or "")
		end
		b4.active = true
		b4.allowBuy = true
		local home = b4:homePos()
		if home then
			b4:teleport(home)
		end
	end
	for _, b in bots do
		if not b.realm.dead then
			b.active = true
		end
	end
	runTo(math.max(leaveAt + 70, totalMinutes * 60))
	local census2 = Runtime.census()

	----------------------------------------------------------------
	-- Server shutdown: BindToClose saves everyone
	----------------------------------------------------------------
	local beforeClose = Services.deepCopy(serverData(b1))
	local t0 = Sched.now
	Runtime.shutdown()
	do
		local rec1 = store and store.data["u_1001"]
		check("BindToClose saved BotOne", rec1 ~= nil and type(rec1.Data) == "table" and beforeClose ~= nil and rec1.Data.Volts == beforeClose.Volts, rec1 and rec1.Data and string.format("saved %s vs %s", tostring(rec1.Data.Volts), tostring(beforeClose and beforeClose.Volts)) or "no record")
		check("BindToClose finished within 30 s", Sched.now - t0 < 30, string.format("%.1f s", Sched.now - t0))
	end

	----------------------------------------------------------------
	-- Metrics
	----------------------------------------------------------------
	local lines = {}
	local function w(s)
		table.insert(lines, s)
	end
	w("--- Metrics ---")
	w(string.format("simulated time: %s; players: BotOne (PC 1366x768, skilled), BotTwo (phone 844x390, average; left at %s and rejoined)", Report.fmtTime(Sched.now), Report.fmtTime(leaveAt)))
	for _, b in bots do
		local m = b.metrics
		local mins = math.max(1e-6, m.zoneSeconds / 60)
		local res = {}
		for _, g in { "perfect", "good", "miss", "zap", "ground", "burst" } do
			table.insert(res, g .. "=" .. tostring(m.results[g] or 0))
		end
		local kinds = {}
		for k, v in m.strikeKinds do
			table.insert(kinds, k .. "=" .. v)
		end
		table.sort(kinds)
		local sd = serverData(b)
		w(string.format("%s (%s):", b.name, b.realm.name))
		w(string.format("  strikes received: %d (%.1f per minute on islands; %d ignored/skipped) kinds: %s", m.strikes, m.strikes / mins, m.ignored, table.concat(kinds, " ")))
		w(string.format("  presses: %d; results: %s", m.presses, table.concat(res, " ")))
		w(string.format("  sells: %d, Volts from sells: %d; purchases: %d; shards spawned: %d; toasts: %d; banners: %d", m.sells, math.floor(m.soldVolts), m.purchases, m.shardsSeen, m.toasts, m.banners))
		if sd then
			w(string.format("  server data: Volts=%d TotalVolts=%d Shards=%d Zone=%d Rebirths=%d Upgrades=Rod%d/Jar%d/Boots%d/Magnet%d/Ins%d Pets=%d Catches=%d Perfects=%d BestCombo=%d Sells=%d",
				sd.Volts, sd.TotalVolts, sd.Shards, sd.Zone, sd.Rebirths, sd.Upgrades.Rod, sd.Upgrades.Jar, sd.Upgrades.Boots, sd.Upgrades.Magnet, sd.Upgrades.Insulation, #sd.Pets, sd.Stats.Catches, sd.Stats.Perfects, sd.Stats.BestCombo, sd.Stats.Sells))
		end
		local reqs = {}
		for k, v in m.requests do
			table.insert(reqs, k .. "=" .. v)
		end
		table.sort(reqs)
		w("  requests: " .. table.concat(reqs, " "))
		local fails = {}
		for k, v in m.requestFails do
			table.insert(fails, string.format("%s (x%d)", k, v))
		end
		table.sort(fails)
		if #fails > 0 then
			w("  request refusals: " .. table.concat(fails, "; "))
		end
		local effs = {}
		for k, v in m.effects do
			table.insert(effs, k .. "=" .. v)
		end
		table.sort(effs)
		w("  effects received: " .. table.concat(effs, " "))
	end
	local evs = {}
	for k, v in eventsSeen do
		if type(v) == "number" and k ~= "cityLitMax" then
			table.insert(evs, k .. " at " .. Report.fmtTime(v))
		end
	end
	table.sort(evs)
	w("server events seen: " .. (if #evs > 0 then table.concat(evs, ", ") else "none") .. string.format("; max CityLit = %s", tostring(eventsSeen.cityLitMax or 0)))
	local rem = {}
	for k, v in World.stats.remote do
		table.insert(rem, string.format("%s=%d (~%dKB)", k, v, math.floor((World.stats.remoteBytes[k] or 0) / 1024)))
	end
	table.sort(rem)
	w("remote traffic: " .. table.concat(rem, " "))
	do
		local growth = {}
		for k, v in census2 do
			local before = census1[k] or 0
			if string.sub(k, 1, 6) == "client" and v - before > 50 then
				table.insert(growth, { k = k, a = before, b = v })
			end
		end
		table.sort(growth, function(x, y)
			return (x.b - x.a) > (y.b - y.a)
		end)
		local parts = {}
		for i, g in growth do
			if i <= 12 then
				table.insert(parts, string.format("%s %d->%d", g.k, g.a, g.b))
			end
		end
		w("client instance growth (alive in DataModel between ~7:30 and the end, >50 only): " .. (if #parts > 0 then table.concat(parts, ", ") else "none"))
	end
	w("scripted requests:")
	for _, l in requestLog do
		w("  " .. l)
	end
	local passed, failed = 0, 0
	for _, c in checks do
		if c.ok then
			passed += 1
		else
			failed += 1
		end
	end
	w(string.format("checks: %d passed, %d failed", passed, failed))
	for _, c in checks do
		w(string.format("  [%s] %s%s", if c.ok then "ok" else "FAIL", c.name, if c.detail and not c.ok then " — " .. c.detail else ""))
	end
	return table.concat(lines, "\n")
end

Core.run = Core.run
return {
	run = function(S)
		return Core.run(S, {})
	end,
	Core = Core,
}

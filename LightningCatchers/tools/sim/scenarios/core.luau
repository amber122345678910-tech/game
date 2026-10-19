--!nocheck
-- Core scenario: two deterministic players play the core loop for 12+ simulated minutes.
--  join -> DataSync -> catch rings on island 1 (perfect/good/miss mix, some ignored) -> sell at the SellPad ->
--  buy upgrades via ClientState.request -> (cheat Volts) unlock island 2 and move there -> hatch a cocoon
--  (cheat shards), equip pets -> daily reward, codes (request + UI), quests -> open/close every window ->
--  settings -> hub + kiosks (ProximityPrompt) -> UI button fuzz -> rebirth (cheat) -> Supercell (4:00) and
--  Ball lightning (10:00) events -> player leaves (save) and rejoins (load) -> server shutdown (BindToClose).
-- Languages (src/shared/Loc.luau): BotTwo's Roblox locale is "ru-ru" (Russian UI), everyone else "en-us" (English).
--  English bots must never get a Cyrillic GUI text (except the "Русский" language option and the bilingual
--  "language changes after rejoin" notice); BotTwo must see the Russian HUD and Russian world text (map signs,
--  prompts, nametags, leaderstats via Controllers/WorldText); BotTwo picks English in Settings before its
--  last rejoin and must then come back in English although its locale is Russian.
local roblox = require("@lune/roblox")
local Bot = require("../lib/bot")
local Services = require("../lib/services")
local Classes = require("../lib/classes")

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

	-- locale: Roblox account locale ("en-us" by default); lang: the UI language the bot must end up with
	-- (Loc.pick: Settings.Lang wins over the locale)
	local function join(userId, name, viewport, touch, skill, locale, lang)
		locale = locale or "en-us"
		local realm = Runtime.addPlayer({ userId = userId, name = name, viewport = viewport, touch = touch, locale = locale })
		patchConfig(realm)
		local b = Bot.new(realm, skill)
		b.locale = locale
		b.lang = lang or (if string.sub(locale, 1, 2) == "ru" then "ru" else "en")
		botByRealm[realm] = b
		return b
	end

	----------------------------------------------------------------
	-- Localization helpers
	----------------------------------------------------------------
	local CYR = "[\208\209][\128-\191]"
	local function hasCyr(t)
		return type(t) == "string" and string.find(t, CYR) ~= nil
	end
	-- Russian on purpose on every client: the language option, the bilingual notice, the font warm-up probe
	local function allowedRu(t)
		return t == "Русский"
			or string.find(t, "Language changes after rejoin", 1, true) ~= nil
			or string.find(t, "LIGHTNING CATCHERS", 1, true) ~= nil
	end
	local function short(t)
		t = string.gsub(t, "\n", " / ")
		return if #t > 90 then string.sub(t, 1, 90) .. "…" else t
	end
	-- every Cyrillic text an English bot's client writes into a TextLabel/TextButton/TextBox placeholder
	local enLeaks, enLeakList = {}, {}
	local enTextWrites = 0 -- GUI text writes seen on English clients (the check below must not be vacuous)
	table.insert(Engine.propHooks, function(d, key, value, R)
		if (key ~= "Text" and key ~= "PlaceholderText") or not R or R.kind ~= "client" or type(value) ~= "string" then
			return
		end
		local b = botByRealm[R]
		if not b or b.lang ~= "en" then
			return
		end
		enTextWrites += 1
		if not hasCyr(value) then
			return
		end
		local isA = d.cls.isA
		if not (isA.TextLabel or isA.TextButton or isA.TextBox) or (isA.TextBox and key == "Text") or allowedRu(value) then
			return
		end
		local k = b.name .. "|" .. value
		if not enLeaks[k] then
			enLeaks[k] = true
			table.insert(enLeakList, { bot = b.name, text = value, d = d, at = Sched.now })
			Report.logLine(string.format("[%s] %s (English): Cyrillic GUI text \"%s\" on %s", Report.fmtTime(Sched.now), b.name, short(value), Engine.fullName(d)))
		end
	end)
	-- texts of a bot's PlayerGui (TextLabel/TextButton .Text, TextBox placeholder)
	local function guiTexts(b, rootD, visibleOnly)
		local out = {}
		rootD = rootD or b:playerGui()
		if not rootD then
			return out
		end
		Engine.forSubtree(rootD, function(x)
			if x.destroyed or not Engine.visibleTo(x, b.realm) then
				return
			end
			local isA = x.cls.isA
			if not (isA.TextLabel or isA.TextButton or isA.TextBox) then
				return
			end
			if visibleOnly and not Bot.effectivelyVisible(x, b.realm) then
				return
			end
			local t = readProp(x, if isA.TextBox then "PlaceholderText" else "Text", b.realm)
			if type(t) == "string" and t ~= "" then
				table.insert(out, { d = x, text = t })
			end
		end)
		return out
	end
	-- English bot: no visible Cyrillic text in its GUI
	local function checkEnglishGui(b, label)
		local bad, n = {}, 0
		for _, it in guiTexts(b, nil, true) do
			n += 1
			if hasCyr(it.text) and not allowedRu(it.text) then
				table.insert(bad, "\"" .. short(it.text) .. "\" @ " .. Engine.fullName(it.d))
			end
		end
		check(string.format("%s (English) sees no Cyrillic GUI text: %s (%d visible texts)", b.name, label, n), #bad == 0 and n > 0, table.concat(bad, " | ", 1, math.min(#bad, 8)))
	end
	-- Russian bot: English dictionary values (Latin words) that show up as whole GUI texts = untranslated back
	local enValues = nil
	local function checkRussianGui(b, label)
		local Loc = b:sharedModule("Loc")
		if not enValues then
			enValues = {}
			for k, v in Loc.EN do
				if hasCyr(k) and string.find(v, "%a%a%a%a") then
					enValues[v] = k
					enValues[Loc.upper(v)] = k
				end
			end
		end
		local bad, n, ru = {}, 0, 0
		for _, it in guiTexts(b, nil, true) do
			n += 1
			if hasCyr(it.text) then
				ru += 1
			elseif enValues[it.text] then
				table.insert(bad, "\"" .. short(it.text) .. "\" (" .. enValues[it.text] .. ") @ " .. Engine.fullName(it.d))
			end
		end
		check(string.format("%s (Russian) sees Russian GUI texts, no English ones: %s (%d of %d visible texts in Russian)", b.name, label, ru, n), #bad == 0 and ru > 0, table.concat(bad, " | ", 1, math.min(#bad, 8)))
	end
	-- the catch button's tag: "ЛОВИ!" / "CATCH!"
	local function catchText(b)
		local hud = b:findGui("HUD")
		local btn = hud and b:findDesc(hud, "CatchButton")
		local found = {}
		if btn then
			for _, it in guiTexts(b, btn, false) do
				table.insert(found, it.text)
			end
		end
		return found
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
	local b2 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2, "ru-ru")
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
	-- language: picked from the Roblox locale (no Settings.Lang yet)
	for _, b in bots do
		local lang = nil
		b:run(function()
			lang = b:sharedModule("Loc").lang()
		end)
		Sched.flush()
		check(string.format("%s (locale %s) plays in %s", b.name, b.locale, b.lang), lang == b.lang, "Loc.lang() = " .. tostring(lang))
		local texts = catchText(b)
		local want = if b.lang == "ru" then "ЛОВИ!" else "CATCH!"
		check(string.format("%s: catch button says %s", b.name, want), table.find(texts, want) ~= nil, "texts: " .. table.concat(texts, ", "))
		if b.lang == "en" then
			checkEnglishGui(b, "HUD after joining")
		else
			checkRussianGui(b, "HUD after joining")
		end
	end

	local requestLog = {}
	local function req(b, action, payload, label)
		b:request(action, payload, function(ok, res)
			-- texts for the player come as a source string or a Loc.Msg: log them in the bot's language
			local shown = tostring(res)
			if type(res) == "table" and type(res[1]) == "string" then
				shown = "\"" .. b:sharedModule("Loc").renderIn(b.lang, res) .. "\""
			end
			table.insert(requestLog, string.format("%s %s(%s) -> %s %s", b.name, action, label or tostring(payload), if ok then "ok" else "FAIL", shown))
		end)
	end

	local function serverData(b)
		local DataService = serverModule("DataService")
		return DataService and DataService.get(b.pd.proxy)
	end

	-- data invariants that must always hold on the server
	local function invariants(b, label)
		local d = serverData(b)
		if not d then
			return
		end
		local Config = b:sharedModule("Config")
		local Economy = b:sharedModule("Economy")
		local problems = {}
		local function num(name, v, lo, hi)
			if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
				table.insert(problems, name .. " is not a finite number (" .. tostring(v) .. ")")
			elseif lo and v < lo then
				table.insert(problems, string.format("%s = %s < %s", name, tostring(v), tostring(lo)))
			elseif hi and v > hi then
				table.insert(problems, string.format("%s = %s > %s", name, tostring(v), tostring(hi)))
			end
		end
		num("Volts", d.Volts, 0)
		num("Shards", d.Shards, 0)
		num("TotalVolts", d.TotalVolts, 0)
		num("Charge", d.Charge, 0, Economy.jarCapacity(d.Upgrades.Jar) * Config.Overcharge.MaxFill + 1e-6)
		num("Zone", d.Zone, 1, #Config.Zones)
		num("LastZone", d.LastZone, 0, d.Zone)
		num("Rebirths", d.Rebirths, 0)
		for id, def in Config.Upgrades do
			num("Upgrades." .. id, d.Upgrades[id], 0, def.MaxLevel)
		end
		local petIds = {}
		for _, p in d.Pets do
			petIds[p.Id] = true
		end
		for _, id in d.Equipped do
			if not petIds[id] then
				table.insert(problems, "Equipped pet " .. tostring(id) .. " is not owned")
			end
		end
		if #d.Equipped > Economy.petSlots(d.Rebirths) then
			table.insert(problems, string.format("%d pets equipped > %d slots", #d.Equipped, Economy.petSlots(d.Rebirths)))
		end
		local fIds = {}
		for _, f in d.Fulgs do
			fIds[f.Id] = true
		end
		for _, id in d.EquippedFulgs do
			if not fIds[id] then
				table.insert(problems, "Equipped fulgurite " .. tostring(id) .. " is not owned")
			end
		end
		local seen = {}
		for _, id in d.Equipped do
			if seen[id] then
				table.insert(problems, "pet " .. tostring(id) .. " equipped twice")
			end
			seen[id] = true
		end
		check(string.format("%s data invariants hold (%s)", b.name, label), #problems == 0, table.concat(problems, "; "))
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
		if t < Sched.now - 0.05 then
			Report.add("note", "scenario", string.format("timeline overlap: a step wanted %s but the clock is already at %s", Report.fmtTime(t), Report.fmtTime(Sched.now)), {})
		end
		Sched.runUntil(t)
	end

	----------------------------------------------------------------
	-- Island 1: play
	----------------------------------------------------------------
	runTo(at("social", 40))
	-- world text (map signs, kiosk prompts, nametags, boards): the property is English for everyone, the Russian
	-- client swaps it locally from the Loc_<prop> attribute (Controllers/WorldText)
	do
		local Loc = b1:sharedModule("Loc")
		local ws = Runtime.find("Workspace", nil)
		local total, signs, badEn, badRu = 0, 0, {}, {}
		local shopEn, shopRu = nil, nil
		Engine.forSubtree(DATA[ws], function(x)
			if x.destroyed then
				return
			end
			for _, prop in { "Text", "ActionText", "ObjectText" } do
				local raw = Engine.getAttribute(x, "Loc_" .. prop, World.server)
				if type(raw) == "string" then
					total += 1
					local ru = Loc.renderIn("ru", Loc.decode(raw))
					if Engine.getAttribute(x, "LocUpper", World.server) then
						ru = Loc.upper(ru)
					end
					local serverText = readProp(x, prop, World.server)
					local isSign = string.find(Engine.fullName(x), "Map", 1, true) ~= nil and x.cls.isA.TextLabel
					if isSign then
						signs += 1
					end
					for _, b in { b1, b2 } do
						local seen = readProp(x, prop, b.realm)
						if b.lang == "en" then
							if seen ~= serverText or hasCyr(seen) then
								table.insert(badEn, string.format("%s.%s = \"%s\" (source \"%s\")", Engine.fullName(x), prop, short(tostring(seen)), short(raw)))
							end
						elseif seen ~= ru then
							table.insert(badRu, string.format("%s.%s = \"%s\", want \"%s\"", Engine.fullName(x), prop, short(tostring(seen)), short(ru)))
						end
					end
					if raw == "Магазин" and isSign then
						shopEn, shopRu = readProp(x, prop, b1.realm), readProp(x, prop, b2.realm)
					end
				end
			end
		end)
		Report.logLine(string.format("world text: %d localized properties (%d map signs)", total, signs))
		check("world text: map signs carry their source (Loc_Text)", signs > 10, string.format("%d signs of %d world texts", signs, total))
		check("world text: BotOne (English) sees English signs, prompts and labels", #badEn == 0, table.concat(badEn, " | ", 1, math.min(#badEn, 6)))
		check("world text: BotTwo (Russian) sees Russian signs, prompts and labels", #badRu == 0, table.concat(badRu, " | ", 1, math.min(#badRu, 6)))
		check("world text: the hub SHOP sign is \"SHOP\" in English and \"МАГАЗИН\" in Russian", shopEn == "SHOP" and shopRu == "МАГАЗИН", string.format("en=%s ru=%s", tostring(shopEn), tostring(shopRu)))
	end
	for _, b in bots do
		local fc = Engine.getAttribute(b.pd, "FriendCount", nil)
		check(b.name .. " FriendCount attribute = 1 (the other bot is a friend)", fc == 1, "FriendCount=" .. tostring(fc))
		local ls = Engine.findChild(b.pd, "leaderstats", nil)
		check(b.name .. " has leaderstats", ls ~= nil)
		if ls then
			local sd = serverData(b)
			for _, c in Engine.childrenOf(DATA[ls], nil) do
				local cd = DATA[c]
				Report.logLine(string.format("leaderstats %s.%s = %s (data Volts %s)", b.name, cd.props.Name, tostring(cd.props.Value), tostring(sd and sd.Volts)))
			end
			-- column names as each client sees them: English, Russian on the Russian client
			for _, viewer in { b1, b2 } do
				local names = {}
				for _, c in Engine.childrenOf(DATA[ls], viewer.realm) do
					table.insert(names, tostring(readProp(DATA[c], "Name", viewer.realm)))
				end
				table.sort(names)
				local want = if viewer.lang == "ru" then "Вольты,Перезапуски" else "Rebirths,Volts"
				check(string.format("%s sees %s's leaderstats columns as %s", viewer.name, b.name, want), table.concat(names, ",") == want, table.concat(names, ","))
			end
		end
	end
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
		invariants(b, "after island 2 unlock")
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
	req(b1, "RedeemCode", "lightning", "lightning (English alias of МОЛНИЯ, must be refused)")
	for q = 1, 3 do
		req(b1, "ClaimQuest", q)
	end
	req(b2, "RedeemCode", "перун", "перун (lowercase Cyrillic, first use)")
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
	checkEnglishGui(b1, "toasts after daily reward, codes and quests")
	checkRussianGui(b2, "Daily window and toasts after codes")
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
		check("lowercase Cyrillic code \"перун\" is accepted", sd2 ~= nil and sd2.Codes and sd2.Codes["ПЕРУН"] == true)
		check("English alias LIGHTNING shares the МОЛНИЯ mark (no second reward)", sd ~= nil and sd.Codes and sd.Codes.LIGHTNING == nil)
	end

	----------------------------------------------------------------
	-- Hub, kiosks (ProximityPrompts), back to island 2
	----------------------------------------------------------------
	runTo(at("hub", 202))
	for _, b in bots do
		b.active = false
		req(b, "Teleport", 0)
	end
	runTo(at("hub", 202) + 2)
	local hubStrikes = {}
	for _, b in bots do
		check(b.name .. " teleported to the hub", b:zone() == 0, "Zone attribute = " .. tostring(b:zone()))
		hubStrikes[b] = b.metrics.strikes
	end
	local kiosks = { "Kiosk_Shop", "Kiosk_Hatchery", "Kiosk_Gallery", "Kiosk_Rebirth", "Kiosk_Daily" }
	for i, k in kiosks do
		local pos = b1:markerPos(k)
		if pos then
			b1:teleport(pos - Vector3.new(0, 1, 0))
		else
			Report.add("check", "scenario", "map marker missing: " .. k, {})
		end
		runTo(at("hub", 202) + 2 + i * 1.2)
		local marker = Runtime.find("Workspace.Map.Markers." .. k, nil)
		local prompt = marker and Engine.findChild(DATA[marker], "KioskPrompt", nil)
		if prompt then
			local shown = b1.realm.shownPrompts and b1.realm.shownPrompts[DATA[prompt]]
			check("BotOne sees the " .. k .. " prompt when standing at it", shown == true)
			Runtime.triggerPrompt(b1.realm, DATA[prompt])
		else
			check("ProximityPrompt exists on " .. k, false)
		end
		runTo(at("hub", 202) + 2 + i * 1.2 + 0.6)
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
	runTo(at("hub", 202) + 12)
	for _, b in bots do
		check(b.name .. " gets no rings while in the hub", b.metrics.strikes == hubStrikes[b], string.format("%d rings arrived in the hub", b.metrics.strikes - hubStrikes[b]))
		req(b, "Teleport", 2)
	end
	runTo(at("hub", 202) + 14)
	for _, b in bots do
		local home = b:homePos(2)
		if home then
			b:teleport(home)
		end
		b.active = true
	end

	----------------------------------------------------------------
	-- Every window: open and close
	----------------------------------------------------------------
	runTo(at("windows", 218))
	local windows = { "Shop", "Shop:upgrades", "Shop:islands", "Shop:drone", "Upgrades", "Islands", "Drone", "Pets", "Pets:mine", "Pets:cocoons", "Hatchery", "Collection", "Collection:fulgs", "Collection:index", "Gallery", "Index", "Teleport", "Rebirth", "Daily", "Quests", "Settings" }
	for i, w in windows do
		for _, b in bots do
			b:run(function()
				b:state().OpenWindow:Fire(w)
			end)
		end
		runTo(at("windows", 218) + i * 0.7)
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
			if b.lang == "en" then
				checkEnglishGui(b, "window " .. w)
			else
				checkRussianGui(b, "window " .. w)
			end
			b:run(function()
				b:clientModule("Client.UI.UIKit").closeWindows()
			end)
		end
		runTo(at("windows", 218) + i * 0.7 + 0.35)
	end

	----------------------------------------------------------------
	-- Device changes: rotate BotTwo's phone, switch BotOne to touch and back, resize BotOne's window
	----------------------------------------------------------------
	runTo(at("devices", 234))
	Runtime.setViewport(b2.realm, Vector2.new(390, 844))
	Runtime.setPreferredInput(b1.realm, true)
	runTo(at("devices", 234) + 0.5)
	b2:run(function()
		b2:state().OpenWindow:Fire("Shop")
	end)
	runTo(at("devices", 234) + 1)
	Runtime.setViewport(b2.realm, Vector2.new(844, 390))
	Runtime.setPreferredInput(b1.realm, false)
	Runtime.setViewport(b1.realm, Vector2.new(1920, 1080))
	runTo(at("devices", 234) + 1.5)
	Runtime.setViewport(b1.realm, Vector2.new(1366, 768))
	b2:run(function()
		b2:clientModule("Client.UI.UIKit").closeWindows()
	end)
	-- phone HUD (BotTwo, back to 844x390): the menu stays in the top third — the lower left is the thumbstick zone
	runTo(at("devices", 234) + 1.8)
	do
		local HUD = b2:clientModule("Client.UI.HUD")
		local shop = HUD and HUD.menuButton("ShopButton")
		local shopD = shop and DATA[shop]
		local menuD = shopD and shopD.parent and DATA[shopD.parent]
		if menuD then
			local pos, size = Classes.absPos(menuD, b2.realm), Classes.absSize(menuD, b2.realm)
			local limit = b2.realm.viewport.Y / 3
			check("phone HUD menu stays in the top third (thumbstick zone free)", pos.Y + size.Y <= limit + 1, string.format("menu bottom %.0f px, limit %.0f px", pos.Y + size.Y, limit))
		else
			check("phone HUD menu found", false, "no ShopButton parent")
		end
	end

	----------------------------------------------------------------
	-- Settings
	----------------------------------------------------------------
	runTo(at("settings", 237))
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
	runTo(at("settings", 237) + 1)
	do
		local win = b2:findGui("Window_Settings")
		if win then
			for _, btn in b2:visibleButtons(win) do
				-- the language is switched on purpose later (before BotTwo's last rejoin)
				if btn.props.Name ~= "Close" and string.sub(btn.props.Name, 1, 5) ~= "Lang_" then
					b2:click(btn)
				end
			end
		end
	end
	runTo(at("settings", 237) + 4)
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
	-- UI fuzz: click every visible button of every window (BotTwo, phone)
	----------------------------------------------------------------
	runTo(at("fuzz", 305))
	local fuzzWindows = { "Shop", "Pets", "Collection", "Teleport", "Rebirth", "Daily", "Settings" }
	local clicked = 0
	for i, w in fuzzWindows do
		b2:run(function()
			b2:state().OpenWindow:Fire(w)
		end)
		runTo(at("fuzz", 305) + i * 3)
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
				if n ~= "Close" and n ~= "Backdrop" and string.sub(n, 1, 5) ~= "Lang_" then
					b2:click(btn)
					clicked += 1
					Sched.step()
				end
			end
		end
		runTo(at("fuzz", 305) + i * 3 + 2)
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
	req(b2, "Teleport", 2)
	runTo(Sched.now + 1)
	do
		local home = b2:homePos(2)
		if home then
			b2:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Rebirth (cheat: island 4 + enough Volts)
	----------------------------------------------------------------
	runTo(at("rebirth", 335))
	b1.allowBuy = false
	do
		local sd = serverData(b1)
		local cost = Economy.rebirthCost(sd and sd.Rebirths or 0)
		setZoneCheat(b1, 4)
		grant(b1, cost + 1000)
	end
	runTo(at("rebirth", 335) + 1)
	b1:run(function()
		b1:state().OpenWindow:Fire("Rebirth")
	end)
	runTo(at("rebirth", 335) + 2)
	b1:run(function()
		b1:clientModule("Client.UI.UIKit").closeWindows()
	end)
	req(b1, "Rebirth", nil)
	runTo(at("rebirth", 335) + 5)
	do
		local sd = serverData(b1)
		check("BotOne rebirthed (Rebirths=1, Zone=1, Volts reset)", sd ~= nil and sd.Rebirths == 1 and sd.Zone == 1, sd and string.format("Rebirths=%d Zone=%d Volts=%d", sd.Rebirths, sd.Zone, sd.Volts) or "")
		check("BotOne is back on island 1 after rebirth", b1:zone() == 1, "Zone attribute = " .. tostring(b1:zone()))
		b1.allowBuy = true
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Tesla drone (cheat: island 3 + Volts), play on island 3
	----------------------------------------------------------------
	local Config = b1:sharedModule("Config")
	runTo(at("drone", 345))
	b2.allowBuy = false
	setZoneCheat(b2, 3)
	grant(b2, Config.Drone.Cost + 500)
	runTo(at("drone", 345) + 1)
	req(b2, "BuyDrone", nil)
	runTo(at("drone", 345) + 2)
	req(b2, "ToggleDrone", false)
	runTo(at("drone", 345) + 3)
	req(b2, "ToggleDrone", true)
	req(b2, "Teleport", 3)
	runTo(at("drone", 345) + 5)
	do
		local sd = serverData(b2)
		check("BotTwo bought the drone", sd ~= nil and sd.Drone == true and sd.DroneOn == true, sd and string.format("Drone=%s DroneOn=%s", tostring(sd.Drone), tostring(sd.DroneOn)) or "")
		check("BotTwo teleported to island 3", b2:zone() == 3, "Zone attribute = " .. tostring(b2:zone()))
		-- the drone takes a full jar away at once (the jar is empty during the trip) and sells it after TripTime;
		-- the bot does not walk to the pad meanwhile (it would only go at 200%, which a drone jar never reaches)
		local EconomyS = serverModule("EconomyService")
		local DataS = serverModule("DataService")
		b2.skill.overcharge = 2
		local droneBefore = b2.metrics.effects.drone or 0
		local voltsBefore = sd and sd.Volts or 0
		local cap = 0
		inServer(function()
			cap = EconomyS.capacity(b2.pd.proxy)
			DataS.update(b2.pd.proxy, function(d)
				d.Charge = cap
			end)
		end)
		runTo(Sched.now + 0.6)
		local sd2 = serverData(b2)
		check("Tesla drone takes a full jar away at once", sd2 ~= nil and sd2.Charge < cap, sd2 and string.format("Charge=%s cap=%s", tostring(sd2.Charge), tostring(cap)) or "")
		runTo(Sched.now + Config.Drone.TripTime + 0.6)
		local sd3 = serverData(b2)
		local drones = (b2.metrics.effects.drone or 0) - droneBefore
		check("Tesla drone sold the jar after its trip", drones >= 2 and sd3 ~= nil and sd3.Volts > voltsBefore, string.format("drone effects=%d Volts %s -> %s", drones, tostring(voltsBefore), tostring(sd3 and sd3.Volts)))
		b2.skill.overcharge = 1.0
		b2.allowBuy = true
		local home = b2:homePos(3)
		if home then
			b2:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Closed island barrier (BotOne only has island 1 after the rebirth)
	----------------------------------------------------------------
	runTo(at("barrier", 358))
	do
		local Zones = b1:sharedModule("Zones")
		local gate = b1:markerPos("Gate_2")
		local c2 = Zones.Geo[2].Center
		if gate then
			b1.active = false
			local dir = Vector3.new(c2.X - gate.X, 0, c2.Z - gate.Z).Unit
			b1:teleport(Vector3.new(gate.X, Zones.groundY(0), gate.Z) + dir * 6 - Vector3.new(0, 0, 0))
			runTo(at("barrier", 358) + 1.5)
			local p = b1:pos()
			local gateDist = (Vector3.new(gate.X, 0, gate.Z) - Vector3.new(c2.X, 0, c2.Z)).Magnitude
			local myDist = p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(c2.X, 0, c2.Z)).Magnitude or 0
			check("closed island 2: the server pushes BotOne back from behind the barrier", p ~= nil and myDist > gateDist, string.format("dist to island 2 centre %.1f, gate at %.1f", myDist, gateDist))
			check("closed island 2: Zone attribute did not become 2", b1:zone() ~= 2, "Zone=" .. tostring(b1:zone()))
		else
			check("map marker Gate_2 exists", false)
		end
		req(b1, "Teleport", 1)
		runTo(at("barrier", 358) + 3)
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
		b1.active = true
	end

	----------------------------------------------------------------
	-- Falling into the void (BotTwo on island 3)
	----------------------------------------------------------------
	runTo(at("void", 366))
	do
		b2.active = false
		local p = b2:pos()
		if p then
			b2:run(function()
				local r = b2:root()
				r.proxy.CFrame = CFrame.new(p.X + 40, Config.VoidY - 30, p.Z)
			end)
		end
		runTo(at("void", 366) + 1.5)
		local q = b2:pos()
		check("fell into the void: the server returned BotTwo onto the island", q ~= nil and q.Y > Config.VoidY + 10, "Y=" .. tostring(q and q.Y))
		check("fell into the void: still on island 3", b2:zone() == 3, "Zone=" .. tostring(b2:zone()))
		b2.active = true
	end

	----------------------------------------------------------------
	-- Death and respawn (BotOne)
	----------------------------------------------------------------
	runTo(at("death", 372))
	do
		local oldChar = b1.pd.props.Character
		inServer(function()
			local hum = oldChar and oldChar:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
		end)
		runTo(at("death", 372) + 9)
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
	runTo(at("island5", 390))
	setZoneCheat(b2, 5)
	runTo(at("island5", 390) + 0.5)
	req(b2, "Teleport", 5)
	runTo(at("island5", 390) + 2)
	check("BotTwo teleported to island 5", b2:zone() == 5, "Zone=" .. tostring(b2:zone()))
	do
		local home = b2:homePos(5)
		if home then
			b2:teleport(home)
		end
	end
	runTo(at("island5", 390) + 70)
	req(b2, "Teleport", 3)
	runTo(at("island5", 390) + 72)
	do
		local home = b2:homePos(3)
		if home then
			b2:teleport(home)
		end
	end

	----------------------------------------------------------------
	-- Collections: fulgurites (equip/unequip/delete), delete a pet, Collection window with previews
	----------------------------------------------------------------
	for _, b in { b1, b2 } do
		local sd = serverData(b)
		if sd and #sd.Fulgs > 0 then
			local f = sd.Fulgs[1]
			local equipped = table.find(sd.EquippedFulgs, f.Id) ~= nil
			if equipped then
				req(b, "UnequipFulg", f.Id)
				runTo(Sched.now + 0.5)
			end
			req(b, "EquipFulg", f.Id)
			runTo(Sched.now + 1)
			local sd2 = serverData(b)
			check(b.name .. " equipped a fulgurite", sd2 ~= nil and table.find(sd2.EquippedFulgs, f.Id) ~= nil)
			if #sd.Fulgs > 1 then
				local last = sd.Fulgs[#sd.Fulgs]
				req(b, "DeleteFulg", last.Id)
			end
		else
			Report.logLine(b.name .. ": no fulgurites to equip (" .. (sd and #sd.Fulgs or -1) .. ")")
		end
		b:run(function()
			b:state().OpenWindow:Fire("Collection:fulgs")
		end)
		runTo(Sched.now + 1.5)
		b:run(function()
			b:state().OpenWindow:Fire("Collection:index")
		end)
		runTo(Sched.now + 1)
		b:run(function()
			b:clientModule("Client.UI.UIKit").closeWindows()
		end)
	end
	do
		local sd = serverData(b2)
		if sd and #sd.Pets > 1 then
			local victim = nil
			for _, p in sd.Pets do
				if not table.find(sd.Equipped, p.Id) then
					victim = p
				end
			end
			if victim then
				local n = #sd.Pets
				req(b2, "DeletePet", victim.Id)
				runTo(Sched.now + 1)
				local sd2 = serverData(b2)
				check("BotTwo deleted an unequipped pet", sd2 ~= nil and #sd2.Pets == n - 1)
			end
		end
	end

	----------------------------------------------------------------
	-- Malicious client: fuzz every remote with malformed payloads (BotOne)
	----------------------------------------------------------------
	do
		b1.active = false
		local Net = b1:sharedModule("Net")
		local before = Services.deepCopy(serverData(b1))
		local inst = Runtime.find("Workspace", nil)
		local payloads = {
			{ nil, "nil" }, { true, "true" }, { -1, "-1" }, { 0, "0" }, { 1e12, "1e12" }, { 0 / 0, "NaN" }, { math.huge, "inf" },
			{ "", "empty" }, { "Rod", "\"Rod\"" }, { string.rep("Ж", 3000), "long string" }, { {}, "{}" }, { { 1, 2 }, "{1,2}" },
			{ { Id = 1, Kind = "gromik" }, "table" }, { Vector3.new(1, 2, 3), "Vector3" }, { inst, "Instance" }, { 2.5, "2.5" },
		}
		local actions = {}
		for name in Net.Actions do
			table.insert(actions, name)
		end
		table.sort(actions)
		local sent = 0
		b1:run(function()
			local fn = Runtime.find("ReplicatedStorage.Remotes.Request", b1.realm)
			for _, a in actions do
				for _, p in payloads do
					sent += 1
					-- stay under the rate limit so every request reaches its handler
					Sched.wait(0.13)
					local ok, x, y = pcall(function()
						return fn:InvokeServer(a, p[1])
					end)
					if ok and x == true and a ~= "SetSettings" and a ~= "Teleport" and a ~= "TutorialStep" and a ~= "ToggleDrone" and a ~= "EquipBest" then
						Report.logLine(string.format("fuzz: %s(%s) was ACCEPTED -> %s", a, p[2], tostring(y)))
					end
				end
				-- unknown action / wrong types for the action itself
			end
			fn:InvokeServer(nil, nil)
			fn:InvokeServer(123, "x")
			fn:InvokeServer({}, {})
			fn:InvokeServer("NoSuchAction", 1)
		end)
		local catchEv = Runtime.find("ReplicatedStorage.Remotes.Catch", b1.realm)
		local shardEv = Runtime.find("ReplicatedStorage.Remotes.ShardCollect", b1.realm)
		b1:run(function()
			local now = Sched.EPOCH + Sched.now
			local args = {
				{}, { "1", 1, now }, { 1e9, 1, now }, { 0 / 0, 1, now }, { 1, 0 / 0, now }, { 1, 1, 0 / 0 }, { 1, 1, math.huge },
				{ 1, -5, now }, { 1, 99, now }, { 1, 1, "x" }, { 1, 1, now - 1e6 }, { {}, {}, {} }, { inst, inst, inst },
			}
			for _, a in args do
				Sched.wait(0.05)
				catchEv:FireServer(table.unpack(a, 1, 3))
			end
			for _, a in { nil, "x", -1, 1e12, 0 / 0, {}, inst } do
				Sched.wait(0.05)
				shardEv:FireServer(a)
			end
		end)
		runTo(Sched.now + #actions * #payloads * 0.13 + 6)
		invariants(b1, "after remote fuzz")
		local after = serverData(b1)
		if before and after then
			check("remote fuzz did not create Volts out of nothing", after.Volts <= before.Volts + 50000, string.format("Volts %s -> %s", tostring(before.Volts), tostring(after.Volts)))
			check("remote fuzz did not create shards out of nothing", after.Shards <= before.Shards + 500, string.format("Shards %s -> %s", tostring(before.Shards), tostring(after.Shards)))
		end
		req(b1, "Teleport", 1)
		runTo(Sched.now + 1)
		local home = b1:homePos(1)
		if home then
			b1:teleport(home)
		end
		b1.active = true
	end

	local census1 = Runtime.census()
	local conns1 = Engine.connectionCensus()
	local threads1 = Sched.threadCensus()

	----------------------------------------------------------------
	-- Long play: events (Supercell at 4:00, Ball lightning at 10:00)
	----------------------------------------------------------------
	local leaveAt = math.max(at("leave", totalMinutes * 60 - 80), at("island5", 390) + 180)
	----------------------------------------------------------------
	-- Edge players: late joiner during an event (tablet), instant leave, quick rejoin under the session lock
	----------------------------------------------------------------
	do
		local lateAt = math.max(Sched.now + 1, leaveAt - 110)
		runTo(lateAt)
		local skill3 = { perfect = 0.45, good = 0.35, ignore = 0.05, seed = 37, overcharge = 1.0 }
		local b5 = join(1003, "BotThree", Vector2.new(1024, 768), true, skill3)
		table.insert(bots, b5)
		-- a player that leaves before its data has loaded
		local ghost = Runtime.addPlayer({ userId = 1004, name = "Ghost", viewport = Vector2.new(1366, 768) })
		Sched.step()
		Runtime.removePlayer(ghost.playerD, "instant leave")
		runTo(lateAt + 12)
		local d5 = b5:data()
		check("late joiner BotThree received DataSync", d5 ~= nil)
		local gs2 = Runtime.find("ReplicatedStorage.GameState", b5.realm)
		check("late joiner sees GameState", gs2 ~= nil)
		if gs2 then
			local ev = Engine.getAttribute(DATA[gs2], "Event", b5.realm)
			Report.logLine("late joiner sees Event=" .. tostring(ev))
		end
		b5.active = true
		b5.allowBuy = true
		local home = b5:homePos(1)
		if home then
			b5:teleport(home)
		end
		runTo(lateAt + 30)
		local sd5 = serverData(b5)
		check("late joiner BotThree caught rings", sd5 ~= nil and sd5.Stats.Catches > 0, sd5 and ("catches=" .. sd5.Stats.Catches) or "")
		local volts5 = sd5 and sd5.Volts
		-- quick rejoin: leave and come back 0.3 s later, while the leave-save still holds the session lock
		b5.active = false
		Runtime.removePlayer(b5.pd, "quick leave")
		Sched.runUntil(Sched.now + 0.3)
		local b6 = join(1003, "BotThree", Vector2.new(1024, 768), true, skill3)
		table.insert(bots, b6)
		local t0 = Sched.now
		while Sched.now < t0 + 40 and not b6:data() do
			Sched.step()
		end
		local d6 = b6:data()
		check("quick rejoin loads data (session lock waited out)", d6 ~= nil, string.format("waited %.1f s", Sched.now - t0))
		if d6 and volts5 then
			check("quick rejoin keeps progress", d6.Volts >= volts5 - 1e-6, string.format("Volts %s vs %s before", tostring(d6.Volts), tostring(volts5)))
		end
		Report.logLine(string.format("quick rejoin: data after %.1f s", Sched.now - t0))
		b6.active = true
		local home6 = b6:homePos(1)
		if home6 then
			b6:teleport(home6)
		end
		-- a lock held by "another server": fresh (must wait, then take over) and stale (take over at once)
		do
			local store = Services.storeFor("PlayerData_v1", nil, "global")
			local nowT = math.floor(Sched.EPOCH + Sched.now + Sched.osTimeOffset)
			store.data["u_1005"] = { Data = { Volts = 777, Shards = 5, Zone = 1, LastZone = 1 }, Lock = { Id = "other-server", Time = nowT } }
			store.data["u_1006"] = { Data = { Volts = 888, Shards = 6, Zone = 1, LastZone = 1 }, Lock = { Id = "dead-server", Time = nowT - 3600 } }
			local bf = join(1005, "BotFive", Vector2.new(1366, 768), false, skill3)
			local bs = join(1006, "BotSix", Vector2.new(1366, 768), false, skill3)
			table.insert(bots, bf)
			table.insert(bots, bs)
			local t0 = Sched.now
			local tStale = nil
			while Sched.now < t0 + 45 and not bf:data() do
				Sched.step()
				if not tStale and bs:data() then
					tStale = Sched.now - t0
				end
			end
			local tFresh = Sched.now - t0
			local df, ds = bf:data(), bs:data()
			check("stale foreign lock is taken over at once", ds ~= nil and (tStale or 99) < 3, string.format("loaded after %s s", tostring(tStale)))
			check("stale-lock player keeps stored data", ds ~= nil and ds.Volts == 888, ds and ("Volts=" .. tostring(ds.Volts)) or "")
			check("fresh foreign lock: data loads after waiting (not stuck)", df ~= nil, string.format("waited %.1f s", tFresh))
			check("fresh-lock player keeps stored data", df ~= nil and df.Volts == 777, df and ("Volts=" .. tostring(df.Volts)) or "")
			Report.logLine(string.format("foreign lock: fresh loaded after %.1f s, stale after %s s", tFresh, tostring(tStale)))
			Runtime.removePlayer(bf.pd, "done")
			Runtime.removePlayer(bs.pd, "done")
		end
		do
			local ghostRec = nil
			for k, st in Services.stores do
				if st.kind == "global" and string.find(k, "PlayerData", 1, true) then
					ghostRec = st.data["u_1004"]
				end
			end
			check("instant leave left no session lock behind", ghostRec == nil or ghostRec.Lock == nil, ghostRec and ("Lock=" .. tostring(ghostRec.Lock and ghostRec.Lock.Id)) or "")
		end
	end

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
		-- Supercell: personal ring rate should go up (SupercellRate) — compare BotTwo on its island
		local sc = eventsSeen.supercell
		if sc and cfg.checkSupercellRate ~= false then
			local dur = Config.Events.Supercell.Duration
			local function rate(t0, t1)
				local n, zones = 0, {}
				for _, st in b2.metrics.strikeTimes or {} do
					if st.t >= t0 and st.t < t1 then
						n += 1
						zones[st.zone] = true
					end
				end
				return n / math.max(1e-6, t1 - t0) * 60
			end
			local during = rate(sc + math.min(20, dur * 0.3), sc + dur - 2)
			local beforeRate = rate(at("checkIsland2", 165), at("hub", 202) - 2)
			Report.logLine(string.format("supercell ring rate BotTwo: %.1f/min during vs %.1f/min before", during, beforeRate))
			check("Supercell increases the ring rate (BotTwo)", during > beforeRate * 1.3, string.format("%.1f/min during vs %.1f/min before", during, beforeRate))
		end
		if cfg.rainbowAt and Sched.now >= cfg.rainbowAt + 15 then
			check("Rainbow event happened", eventsSeen.rainbow ~= nil)
		end
	end

	----------------------------------------------------------------
	-- Leave (save) and rejoin (load)
	----------------------------------------------------------------
	local before = Services.deepCopy(serverData(b2))
	b2.lastData = before
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
	local b3 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2, "ru-ru")
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
	-- BotTwo (Russian locale) picks English in Settings: it applies after the rejoin below
	do
		checkRussianGui(b3, "HUD after rejoining")
		b3:run(function()
			b3:state().OpenWindow:Fire("Settings")
		end)
		runTo(Sched.now + 1)
		local win = b3:findGui("Window_Settings")
		local en = win and b3:findDesc(win, "Lang_en", "GuiButton")
		check("BotTwo: Settings has a Lang_en button", en ~= nil)
		if en then
			b3:click(en)
		end
		runTo(Sched.now + 2.5)
		local sd = serverData(b3)
		check("BotTwo saved Settings.Lang = \"en\"", sd ~= nil and sd.Settings.Lang == "en", sd and ("Lang=" .. tostring(sd.Settings.Lang)) or "")
		check("BotTwo still plays in Russian until it rejoins", table.find(catchText(b3), "ЛОВИ!") ~= nil, table.concat(catchText(b3), ","))
		b3:run(function()
			b3:clientModule("Client.UI.UIKit").closeWindows()
		end)
	end
	-- BotTwo leaves and comes back "a day later": offline income (Welcome)
	local b3d = serverData(b3)
	b3.lastData = Services.deepCopy(b3d)
	local incomeRate = b3d and b3d.IncomeRate or 0
	b3.active = false
	Runtime.removePlayer(b3.pd, "leave")
	runTo(leaveAt + 40)
	Sched.osTimeOffset = 86400 * 2
	local b4 = join(1002, "BotTwo", Vector2.new(844, 390), true, skill2, "ru-ru", "en")
	table.insert(bots, b4)
	runTo(leaveAt + 52)
	do
		local lang = nil
		b4:run(function()
			lang = b4:sharedModule("Loc").lang()
		end)
		Sched.flush()
		check("BotTwo rejoined in English (Settings.Lang = \"en\" beats the ru-ru locale)", lang == "en", "Loc.lang() = " .. tostring(lang))
		check("BotTwo (now English): catch button says CATCH!", table.find(catchText(b4), "CATCH!") ~= nil, table.concat(catchText(b4), ","))
		checkEnglishGui(b4, "Welcome window after switching to English")
	end
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
	local conns2 = Engine.connectionCensus()
	local threads2 = Sched.threadCensus()

	for _, b in bots do
		if not b.realm.dead then
			invariants(b, "end of play")
			if b.lang == "en" then
				checkEnglishGui(b, "end of play")
			end
		end
	end
	do
		local lines = {}
		for i, l in enLeakList do
			if i <= 10 then
				table.insert(lines, string.format("%s@%s: \"%s\" on %s", l.bot, Report.fmtTime(l.at), short(l.text), Engine.fullName(l.d)))
			end
		end
		Report.logLine(string.format("GUI text writes on English clients: %d, Cyrillic: %d", enTextWrites, #enLeakList))
		check(string.format("English bots never got a Cyrillic GUI text during the whole run (%d text writes watched)", enTextWrites), #enLeakList == 0 and enTextWrites > 500, string.format("%d texts: %s", #enLeakList, table.concat(lines, " | ")))
	end
	----------------------------------------------------------------
	-- Server shutdown: BindToClose saves everyone
	----------------------------------------------------------------
	do
		local board = Runtime.find("Workspace.Map.Markers.Board_Leaders", nil)
		local texts = {}
		if board then
			Engine.forSubtree(DATA[board], function(x)
				if x.cls.isA.TextLabel then
					local t = x.props.Text
					if type(t) == "string" and t ~= "" then
						table.insert(texts, t)
					end
				end
			end)
		end
		local joined = table.concat(texts, " | ")
		Report.logLine("Board_Leaders: " .. joined)
		check("leaderboard board lists the bots", string.find(joined, "BotOne", 1, true) ~= nil or string.find(joined, "BotTwo", 1, true) ~= nil, string.sub(joined, 1, 200))
	end
	local finalData = {}
	for _, b in bots do
		local sd = serverData(b)
		if sd then
			finalData[b] = Services.deepCopy(sd)
		end
	end
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
		local sd = finalData[b] or b.lastData
		w(string.format("%s (%s%s):", b.name, b.realm.name, if b.realm.dead then ", left" else ""))
		w(string.format("  strikes received: %d (%.1f per minute on islands; %d ignored/skipped) kinds: %s", m.strikes, m.strikes / mins, m.ignored, table.concat(kinds, " ")))
		w(string.format("  presses: %d; results: %s", m.presses, table.concat(res, " ")))
		w(string.format("  sells: %d, Volts from sells: %d; purchases: %d; shards spawned: %d; toasts: %d; banners: %d", m.sells, math.floor(m.soldVolts), m.purchases, m.shardsSeen, m.toasts, m.banners))
		if sd then
			local idx = 0
			for _ in sd.Index do
				idx += 1
			end
			w(string.format("  server data: Volts=%d TotalVolts=%d Shards=%d Zone=%d Rebirths=%d Upgrades=Rod%d/Jar%d/Boots%d/Magnet%d/Ins%d Pets=%d Fulgurites=%d Index=%d Catches=%d Perfects=%d BestCombo=%d Sells=%d IncomeRate=%.0f",
				sd.Volts, sd.TotalVolts, sd.Shards, sd.Zone, sd.Rebirths, sd.Upgrades.Rod, sd.Upgrades.Jar, sd.Upgrades.Boots, sd.Upgrades.Magnet, sd.Upgrades.Insulation, #sd.Pets, #sd.Fulgs, idx, sd.Stats.Catches, sd.Stats.Perfects, sd.Stats.BestCombo, sd.Stats.Sells, sd.IncomeRate or 0))
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
	do
		local tot = { strikes = 0, presses = 0, sells = 0, volts = 0, purchases = 0, minutes = 0 }
		local grades = {}
		for _, b in bots do
			local m = b.metrics
			tot.strikes += m.strikes
			tot.presses += m.presses
			tot.sells += m.sells
			tot.volts += m.soldVolts
			tot.purchases += m.purchases
			tot.minutes += m.zoneSeconds / 60
			for g, n in m.results do
				grades[g] = (grades[g] or 0) + n
			end
		end
		local gl = {}
		for _, g in { "perfect", "good", "miss", "zap", "ground", "burst" } do
			table.insert(gl, g .. "=" .. tostring(grades[g] or 0))
		end
		w(string.format("TOTAL: %d rings in %.1f player-minutes on islands (%.1f rings/player/min); %d presses; results %s; %d sells for %d Volts; %d purchases",
			tot.strikes, tot.minutes, tot.strikes / math.max(1e-6, tot.minutes), tot.presses, table.concat(gl, " "), tot.sells, math.floor(tot.volts), tot.purchases))
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
			if string.sub(k, 1, 6) == "client" and census1[k] ~= nil and v - before > 50 then
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
		w("client instance growth (same client, alive in DataModel at ~7:30 vs the end, >50 only): " .. (if #parts > 0 then table.concat(parts, ", ") else "none"))
	end
	do
		local function growthOf(a, b, minGrowth, label)
			local list = {}
			for k, v in b do
				local before = a[k]
				if before ~= nil and v - before >= minGrowth then
					table.insert(list, { k = k, a = before, b = v })
				end
			end
			table.sort(list, function(x, y)
				return (x.b - x.a) > (y.b - y.a)
			end)
			local parts = {}
			for i, g in list do
				if i <= 10 then
					table.insert(parts, string.format("%s %d->%d", g.k, g.a, g.b))
				end
			end
			w(label .. (if #parts > 0 then table.concat(parts, "; ") else "none"))
			return list
		end
		local cg = growthOf(conns1, conns2, 25, "connection growth (same realm, ~7:50 vs end, >=25): ")
		local tg = growthOf(threads1, threads2, 10, "suspended-thread growth (same realm, ~7:50 vs end, >=10): ")
		for _, g in cg do
			if g.b - g.a >= 100 then
				Report.add("check", "scenario", string.format("possible connection leak: %s grew %d -> %d", g.k, g.a, g.b), {})
			end
		end
		for _, g in tg do
			if g.b - g.a >= 40 then
				Report.add("check", "scenario", string.format("possible thread leak: %s grew %d -> %d", g.k, g.a, g.b), {})
			end
		end
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

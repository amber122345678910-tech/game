--!nocheck
-- Deterministic bot that plays through a client realm using the game's own client paths:
--  * listens to ClientState.StrikeSpawned (real StrikeSpawn delivery), moves the character root into the ring
--    (sets HumanoidRootPart.CFrame — no physics) and presses ⚡ at hit time ± error via one of the real input
--    paths: the HUD button (InputBegan), ClientState.CatchPressed, or the E key through ContextActionService;
--  * sells at the island's SellPad marker when the jar is full, buys upgrades / unlocks islands through
--    ClientState.request, collects shards it walks past, clicks UI buttons.
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Sched = require("./sched")
local Report = require("./report")
local World = require("./world")
local Services = require("./services")
local Realm = require("./realm")
local Runtime = require("./runtime")
local DT = require("./datatypes")

local Vector3, Vector2, CFrame, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Enum
local DATA = Engine.DATA
local readProp = Engine.readProp

local Bot = {}
Bot.__index = Bot

local function serverNow()
	return Sched.EPOCH + Sched.now
end

function Bot.new(realm, skill)
	local self = setmetatable({}, Bot)
	self.realm = realm
	self.pd = realm.playerD
	self.name = self.pd.props.Name
	self.skill = skill
	self.rng = DT.Random.new(skill.seed or 1)
	self.plans = {} -- { id, hit, pressAt (sim time), msg }
	self.active = false
	self.selling = nil
	self.pressMode = 0
	self.metrics = {
		strikes = 0,
		strikesInZone = 0,
		strikeKinds = {},
		results = {},
		presses = 0,
		ignored = 0,
		sells = 0,
		soldVolts = 0,
		purchases = 0,
		requests = {},
		requestFails = {},
		shardsSeen = 0,
		zoneSeconds = 0,
		dataSyncs = 0,
		firstDataSync = nil,
		joinedAt = Sched.now,
		effects = {},
		toasts = 0,
		banners = 0,
	}
	self.shards = {}
	return self
end

-- Run fn inside the bot's client realm (new thread). Returns the thread.
function Bot:run(fn, ...)
	return Sched.spawn(self.realm, fn, ...)
end

-- Module loaded by the client (same table the game uses)
function Bot:clientModule(path)
	local ps = Engine.findChild(self.pd, "PlayerScripts", self.realm)
	if not ps then
		return nil
	end
	local cur = DATA[ps]
	for part in string.gmatch(path, "[^%.]+") do
		local c = Engine.findChild(cur, part, self.realm)
		if not c then
			return nil
		end
		cur = DATA[c]
	end
	return Realm.module(self.realm, cur.proxy)
end

function Bot:sharedModule(name)
	local inst = Runtime.find("ReplicatedStorage.Shared." .. name, nil)
	return inst and Realm.module(self.realm, inst)
end

function Bot:state()
	return self:clientModule("Client.ClientState")
end

function Bot:data()
	local cs = self:state()
	return cs and cs.data
end

function Bot:root()
	local char = self.pd.props.Character
	if not char then
		return nil
	end
	local r = Engine.findChild(DATA[char], "HumanoidRootPart", self.realm)
	return r and DATA[r]
end

function Bot:pos()
	local r = self:root()
	return r and readProp(r, "CFrame", self.realm).Position
end

function Bot:zone()
	local z = Engine.getAttribute(self.pd, "Zone", self.realm)
	return if type(z) == "number" then z else 0
end

-- Move the character (client-owned physics) to a ground point
function Bot:teleport(groundPos, look)
	local r = self:root()
	if not r then
		return
	end
	local p = groundPos + Vector3.new(0, 3, 0)
	local cf = if look then CFrame.lookAt(p, p + look) else CFrame.new(p)
	self:run(function()
		r.proxy.CFrame = cf
	end)
end

----------------------------------------------------------------------
-- Hooks into the client
----------------------------------------------------------------------
function Bot:attach()
	local cs = self:state()
	if not cs then
		return false
	end
	if self.attached then
		return true
	end
	self.attached = true
	self:run(function()
		cs.StrikeSpawned:Connect(function(msg)
			self:onStrike(msg)
		end)
		cs.StrikeResolved:Connect(function(msg)
			local g = msg.Grade
			self.metrics.results[g] = (self.metrics.results[g] or 0) + 1
		end)
		cs.Changed:Connect(function()
			self.metrics.dataSyncs += 1
			if not self.metrics.firstDataSync then
				self.metrics.firstDataSync = Sched.now
			end
		end)
		cs.Effect:Connect(function(msg)
			local k = tostring(msg.Kind)
			self.metrics.effects[k] = (self.metrics.effects[k] or 0) + 1
			if (k == "sell" or k == "drone") and type(msg.Value) == "number" and msg.UserId == self.pd.props.UserId then
				if k == "sell" or msg.Text == "sold" then
					self.metrics.sells += 1
					self.metrics.soldVolts += msg.Value
				end
			end
		end)
		cs.Toast:Connect(function()
			self.metrics.toasts += 1
		end)
	end)
	return true
end

function Bot:onStrike(msg)
	local m = self.metrics
	m.strikes += 1
	m.strikeKinds[msg.Kind] = (m.strikeKinds[msg.Kind] or 0) + 1
	if msg.Tag then
		m.strikeKinds["tag:" .. tostring(msg.Tag)] = (m.strikeKinds["tag:" .. tostring(msg.Tag)] or 0) + 1
	end
	if not self.active or self.selling or msg.Zone ~= self:zone() then
		m.ignored += 1
		return
	end
	if self.rng:NextNumber() < self.skill.ignore then
		m.ignored += 1
		return
	end
	for i, hitT in msg.Hits do
		local roll = self.rng:NextNumber()
		local err
		if roll < self.skill.perfect then
			err = (self.rng:NextNumber() - 0.5) * 0.12
		elseif roll < self.skill.perfect + self.skill.good then
			local s = if self.rng:NextNumber() < 0.5 then -1 else 1
			err = s * (0.15 + self.rng:NextNumber() * 0.07)
		else
			local s = if self.rng:NextNumber() < 0.3 then -1 else 1
			err = s * (0.34 + self.rng:NextNumber() * 0.25)
		end
		table.insert(self.plans, {
			id = msg.Id,
			hit = i,
			hitAt = hitT - Sched.EPOCH,
			pressAt = hitT - Sched.EPOCH + err,
			msg = msg,
		})
	end
	table.sort(self.plans, function(a, b)
		return a.pressAt < b.pressAt
	end)
end

-- Ring centre at sim time t (runner rings move from Pos to To until the first hit)
local function centerAt(msg, t)
	if msg.To and msg.Hits[1] then
		local spawn = msg.Spawn - Sched.EPOCH
		local first = msg.Hits[1] - Sched.EPOCH
		local share = math.clamp((t - spawn) / math.max(0.01, first - spawn), 0, 1)
		return msg.Pos:Lerp(msg.To, share)
	end
	return msg.Pos
end

----------------------------------------------------------------------
-- Pressing ⚡ through the real input paths
----------------------------------------------------------------------
function Bot:press()
	self.metrics.presses += 1
	self.pressMode += 1
	local realm = self.realm
	local mode = self.pressMode % 3
	if mode == 0 then
		-- HUD button: InputBegan (what the HUD listens to)
		local hud = self:clientModule("Client.UI.HUD")
		local btn = hud and hud.catchButton and hud.catchButton()
		if btn then
			local u, d = World.new("InputObject", { Name = "InputObject" }, nil, realm.id)
			d.props.UserInputType = if realm.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
			d.props.UserInputState = Enum.UserInputState.Begin
			d.props.KeyCode = Enum.KeyCode.Unknown
			d.props.Position = Vector3.new(0, 0, 0)
			Engine.fire(Engine.getSignal(DATA[btn], "InputBegan"), realm, u)
			return
		end
	elseif mode == 1 and not realm.touch then
		-- keyboard E through ContextActionService / UserInputService
		Services.dispatchInput(realm, Enum.KeyCode.E, Enum.UserInputType.Keyboard, Enum.UserInputState.Begin)
		Services.dispatchInput(realm, Enum.KeyCode.E, Enum.UserInputType.Keyboard, Enum.UserInputState.End)
		return
	end
	local cs = self:state()
	if cs then
		self:run(function()
			cs.CatchPressed:Fire()
		end)
	end
end

----------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------
-- ClientState.request in the client realm; cb(ok, result) when it returns
function Bot:request(action, payload, cb)
	local cs = self:state()
	if not cs then
		return
	end
	local m = self.metrics
	self:run(function()
		local ok, res = cs.request(action, payload)
		m.requests[action] = (m.requests[action] or 0) + 1
		if not ok then
			local key = action .. ": " .. tostring(res)
			m.requestFails[key] = (m.requestFails[key] or 0) + 1
		end
		if ok and (action == "BuyUpgrade" or action == "UnlockZone" or action == "BuyDrone") then
			m.purchases += 1
		end
		Report.logLine(string.format("[%s %s] request %s(%s) -> %s %s", Report.fmtTime(Sched.now), self.name, action, tostring(payload), tostring(ok), tostring(res)))
		if cb then
			cb(ok, res)
		end
	end)
end

function Bot:buyStep()
	local d = self:data()
	local Economy = self:sharedModule("Economy")
	local Config = self:sharedModule("Config")
	if not d or not Economy or not Config then
		return
	end
	if self.pendingBuy then
		return
	end
	-- island first if affordable and allowed
	if self.allowUnlock and d.Zone < #Config.Zones then
		local cost = Economy.zoneCost(d.Zone + 1)
		if cost and d.Volts >= cost then
			self.pendingBuy = true
			self:request("UnlockZone", d.Zone + 1, function(ok)
				self.pendingBuy = false
				if ok and self.followUnlock then
					self:request("Teleport", d.Zone + 1)
				end
			end)
			return
		end
	end
	local best, bestCost = nil, math.huge
	for _, id in Config.UpgradeOrder do
		local lvl = d.Upgrades[id] or 0
		local cost = Economy.upgradeCost(id, lvl)
		if cost and cost <= d.Volts and cost < bestCost then
			best, bestCost = id, cost
		end
	end
	if best then
		self.pendingBuy = true
		self:request("BuyUpgrade", best, function()
			self.pendingBuy = false
		end)
	end
end

----------------------------------------------------------------------
-- Per-frame behaviour
----------------------------------------------------------------------
function Bot:markerPos(name)
	local m = Runtime.find("Workspace.Map.Markers." .. name, self.realm)
	if m then
		return readProp(DATA[m], "CFrame", self.realm).Position
	end
	return nil
end

function Bot:homePos(zone)
	local Zones = self:sharedModule("Zones")
	if not Zones then
		return nil
	end
	local z = zone or self:zone()
	if z >= 1 and Zones.Geo[z] then
		local g = Zones.Geo[z]
		return Vector3.new(g.Center.X, g.Center.Y, g.Center.Z) + g.ToHub * 20
	end
	return nil
end

function Bot:step()
	local now = Sched.now
	local zone = self:zone()
	if zone >= 1 then
		self.metrics.zoneSeconds += Sched.FRAME
	end
	if zone ~= self.lastZone then
		-- rings of the previous island are gone (the client clears them too)
		self.lastZone = zone
		self.plans = {}
		self.shards = {}
	end
	if not self.active then
		return
	end
	if self.allowBuy and (not self.lastBuy or now - self.lastBuy > 3) then
		self.lastBuy = now
		self:buyStep()
	end
	-- selling trip
	if self.selling then
		local s = self.selling
		local fill = Engine.getAttribute(self.pd, "JarFill", self.realm) or 0
		if fill <= 0.001 or now - s.started > 4 then
			self.selling = nil
			local home = self:homePos()
			if home then
				self:teleport(home)
			end
		end
		return
	end
	-- jar full -> go to the SellPad of this island
	local fill = Engine.getAttribute(self.pd, "JarFill", self.realm) or 0
	local limit = 1
	if zone >= 2 and self.skill.overcharge then
		limit = self.skill.overcharge
	end
	if zone >= 1 and fill >= limit - 1e-6 then
		local pad = self:markerPos("SellPad_" .. zone)
		if pad then
			self.selling = { started = now }
			self.plans = {}
			self:teleport(pad)
			return
		end
	end
	-- catching
	local plan = self.plans[1]
	while plan and plan.pressAt < now - 0.3 do
		table.remove(self.plans, 1)
		plan = self.plans[1]
	end
	if plan then
		local moveAt = plan.hitAt - 0.9
		if now >= moveAt then
			local c = centerAt(plan.msg, math.min(now, plan.hitAt))
			local p = self:pos()
			if p and (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude > 0.5 then
				self:teleport(c)
			end
		end
		if now >= plan.pressAt - Sched.FRAME / 2 then
			table.remove(self.plans, 1)
			self:press()
		end
		return
	end
	-- idle: collect nearby shards, buy things
	local p = self:pos()
	if p and #self.shards > 0 then
		local s = table.remove(self.shards, 1)
		if s.expires > serverNow() and (s.pos - p).Magnitude < 60 then
			self:teleport(s.pos)
		end
	end
end

----------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------
function Bot:playerGui()
	local g = Engine.findChild(self.pd, "PlayerGui", self.realm)
	return g and DATA[g]
end

local function effectivelyVisible(d, realm)
	local cur = d
	while cur do
		if cur.cls.isA.GuiObject then
			if readProp(cur, "Visible", realm) == false then
				return false
			end
		elseif cur.cls.isA.LayerCollector then
			return readProp(cur, "Enabled", realm) ~= false
		end
		cur = cur.parent and DATA[cur.parent]
	end
	return false
end
Bot.effectivelyVisible = effectivelyVisible

function Bot:click(btnD)
	local realm = self.realm
	local u, d = World.new("InputObject", { Name = "InputObject" }, nil, realm.id)
	d.props.UserInputType = if realm.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
	d.props.UserInputState = Enum.UserInputState.Begin
	d.props.KeyCode = Enum.KeyCode.Unknown
	d.props.Position = Vector3.zero
	local function fire(name, ...)
		local s = btnD.sigs and btnD.sigs[name]
		if s then
			Engine.fire(s, realm, ...)
		end
	end
	fire("InputBegan", u)
	fire("MouseButton1Down", 0, 0)
	fire("MouseButton1Up", 0, 0)
	fire("MouseButton1Click")
	fire("Activated", u, 1)
	fire("InputEnded", u)
end

-- All visible buttons under a GUI root
function Bot:visibleButtons(rootD)
	local out = {}
	Engine.forSubtree(rootD, function(x)
		if x.cls.isA.GuiButton and Engine.visibleTo(x, self.realm) and not x.destroyed and effectivelyVisible(x, self.realm) then
			table.insert(out, x)
		end
	end)
	return out
end

function Bot:findGui(name)
	local g = self:playerGui()
	if not g then
		return nil
	end
	local c = Engine.findChild(g, name, self.realm)
	return c and DATA[c]
end

function Bot:findDesc(rootD, name, className)
	local found = nil
	Engine.forSubtree(rootD, function(x)
		if not found and x.props.Name == name and (not className or x.cls.isA[className]) then
			found = x
		end
	end)
	return found
end

return Bot

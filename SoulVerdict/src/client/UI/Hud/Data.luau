--!strict
-- Hud/Data: builds the HUD Snapshot (contract in Hud/Mock.luau) from the live game. Runtime only: services
-- are fetched lazily inside functions, so requiring this module under Lune is harmless.
--
--   Data.new(deps) -> Source
--   source:Build() -> Snapshot          cheap enough for ~10 Hz (one GetAttributes() per character)
--   source:Now() -> number              server time (deps.State.Now() or workspace:GetServerTimeNow())
--   source:SetMyVote(mapId?) / source:SetVotes(votes) / source:SetSpectate(model?)
--   source:UnitOf(model) -> Unit?       one-off unit read (kill feed colours, intro cards)
--   source:Destroy()
-- Sources: ReplicatedStorage.RoundState attributes (SPEC §4.1, + MonsterName/Harmony extras), Players
-- (LocalPlayer; Level/Title/MonsterChance/RolePreference/Role/RoundsSinceMonster attributes), characters
-- (player.Character + workspace.Bots/*) attributes + Humanoid health, SAVE stars (CollectionService tag
-- "SaveStar": Index/Progress/Lit/Contested/Channelers/Radius), deps.Combat (Cooldowns/Charge/ComboIndex/Ammo;
-- fallback: the local character's Cooldown_<abilityId> attributes written by AbilityService), deps.Input.Device(),
-- deps.Spectate (optional SpectateController: Target() -> Model?).
local Style = require(script.Parent.Style)

local Data = {}
Data.__index = Data

type Unit = { [string]: any }

local function svc(name: string): any
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return if ok then s else nil
end

-- Players helpers that never throw (offline mocks lack LocalPlayer / GetPlayers)
local function localPlayerOf(players: any): Player?
	if not players then
		return nil
	end
	local ok, p = pcall(function()
		return players.LocalPlayer
	end)
	return if ok then p else nil
end

local function playersOf(players: any): { Player }
	if not players then
		return {}
	end
	local ok, list = pcall(function()
		return players:GetPlayers()
	end)
	return if ok and type(list) == "table" then list else {}
end

Data.LocalPlayer = localPlayerOf
Data.PlayerList = playersOf

local function call(obj: any, method: string, ...: any): (boolean, ...any)
	if type(obj) ~= "table" then
		return false
	end
	local fn = obj[method]
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

function Data.new(deps: any): any
	local self = setmetatable({}, Data) :: any
	self.deps = deps or {}
	self.myVote = nil
	self.votes = {}
	self.spectate = nil
	self.dashTrack = setmetatable({}, { __mode = "k" }) -- model -> { charges, changedAt }
	self.deadAt = nil
	self.killer = nil
	self.Players = svc("Players")
	self.ReplicatedStorage = svc("ReplicatedStorage")
	self.CollectionService = svc("CollectionService")
	self.UserInputService = svc("UserInputService")
	return self
end

function Data:Now(): number
	local ok, t = call(self.deps.State, "Now")
	if ok and type(t) == "number" then
		return t
	end
	local ok2, t2 = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok2 then t2 else os.clock()
end

function Data:SetMyVote(mapId: string?)
	self.myVote = mapId
end

function Data:SetVotes(votes: any)
	if type(votes) == "table" then
		self.votes = votes
	end
end

function Data:SetSpectate(model: Model?)
	self.spectate = model
end

function Data:SetKiller(name: string?)
	self.killer = name
end

function Data:Round(): { [string]: any }
	local ok, round = call(self.deps.State, "Round")
	if ok and type(round) == "table" then
		return round
	end
	local ok2, attrs = pcall(function()
		local rs = self.ReplicatedStorage:FindFirstChild("RoundState")
		return if rs then rs:GetAttributes() else {}
	end)
	return if ok2 and type(attrs) == "table" then attrs else {}
end

function Data:LocalCharacter(): Model?
	local ok, model = call(self.deps.State, "LocalCharacter")
	if ok and typeof(model) == "Instance" then
		return model :: Model
	end
	local player = localPlayerOf(self.Players)
	return if player then player.Character else nil
end

function Data:Device(): string
	local ok, device = call(self.deps.Input, "Device")
	if ok and type(device) == "string" then
		return device
	end
	local uis = self.UserInputService
	local okT, touch = pcall(function()
		return uis.TouchEnabled and not uis.KeyboardEnabled
	end)
	return if okT and touch then "Touch" else "KeyboardMouse"
end

local function playerOf(players: any, model: Model): Player?
	if not players then
		return nil
	end
	local ok, p = pcall(function()
		return players:GetPlayerFromCharacter(model)
	end)
	return if ok then p else nil
end

function Data:UnitOf(model: Model?, now: number?): Unit?
	if model == nil or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local t = now or self:Now()
	local a = model:GetAttributes()
	if type(a.KitId) ~= "string" or a.KitId == "" then
		return nil
	end
	local player = playerOf(self.Players, model)
	local localPlayer = localPlayerOf(self.Players)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local statuses: { [string]: number } = {}
	local cooldowns: { [string]: number } = {}
	for key, value in a do
		if type(value) == "number" then
			if string.sub(key, 1, 7) == "Status_" then
				if value > t then
					statuses[string.sub(key, 8)] = value
				end
			elseif string.sub(key, 1, 9) == "Cooldown_" then
				cooldowns[string.sub(key, 10)] = value
			end
		end
	end
	local dash = a.DashCharges or 0
	local kit = Style.Kit(a.KitId)
	local config = Style.Config()
	local dashMax = (kit and kit.Stats.DashCharges) or (if config then config.Human.DashCharges else 2)
	-- local dash recharge estimate (the server only replicates the charge count)
	local track = self.dashTrack[model]
	if track == nil or track.charges ~= dash then
		track = { charges = dash, changedAt = t }
		self.dashTrack[model] = track
	end
	local recharge = if config then config.Human.DashRecharge else 2.8
	local dashNext = if dash < dashMax then math.clamp((t - track.changedAt) / recharge, 0, 0.99) else 0
	local name = a.DisplayName
	if type(name) ~= "string" or name == "" then
		name = if player then player.DisplayName else model.Name
	end
	return {
		Model = model,
		Name = name,
		UserId = if player then player.UserId else (a.OwnerUserId or 0),
		KitId = a.KitId,
		SkinId = a.SkinId,
		Team = a.Team or "Lobby",
		Level = if player then (player:GetAttribute("Level") or 1) else (a.Level or 1),
		Title = if player then (player:GetAttribute("Title") or "") else "",
		IsLocal = player ~= nil and player == localPlayer,
		IsBot = a.IsBot == true,
		HP = if humanoid then humanoid.Health else 0,
		MaxHP = if humanoid then humanoid.MaxHealth else 100,
		KR = a.KR or 0,
		Shield = a.Shield or 0,
		Guard = a.Guard or 0,
		MaxGuard = a.MaxGuard or 100,
		Dash = dash,
		DashMax = dashMax,
		DashNext = dashNext,
		Dodges = a.Dodges or 0,
		MaxDodges = a.MaxDodges or 0,
		ExhaustedUntil = a.Exhausted or 0,
		Ult = a.Ult or 0,
		Downed = a.Downed == true,
		DownedEndsAt = a.DownedEndsAt or 0,
		Dead = a.Dead == true or (humanoid ~= nil and humanoid.Health <= 0 and a.Downed ~= true),
		Blocking = a.Blocking == true,
		Invisible = a.Invisible == true,
		FinalForm = a.FinalForm == true,
		SoulMode = a.SoulMode or "Red",
		Statuses = statuses,
		Cooldowns = cooldowns,
	}
end

function Data:Characters(): { Model }
	local out: { Model } = {}
	local seen: { [Model]: boolean } = {}
	if self.Players then
		for _, p in playersOf(self.Players) do
			local c = p.Character
			if c and not seen[c] then
				seen[c] = true
				table.insert(out, c)
			end
		end
	end
	local okW, bots = pcall(function()
		return workspace:FindFirstChild("Bots")
	end)
	if okW and bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") and not seen[m] then
				seen[m] = true
				table.insert(out, m)
			end
		end
	end
	return out
end

local function split(text: any): { string }
	if type(text) == "table" then
		return text
	end
	local out = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "[^,%s]+") do
			table.insert(out, id)
		end
	end
	return out
end

function Data:Build(): { [string]: any }
	local now = self:Now()
	local round = self:Round()
	local players = self.Players
	local localPlayer = localPlayerOf(players)
	local role = if localPlayer then (localPlayer:GetAttribute("Role") or "Lobby") else "Lobby"
	local config = Style.Config()

	local me: Unit? = nil
	local monster: Unit? = nil
	local humans: { Unit } = {}
	local others: { Unit } = {}
	local localChar = self:LocalCharacter()
	for _, model in self:Characters() do
		local unit = self:UnitOf(model, now)
		if unit then
			if model == localChar then
				unit.IsLocal = true
				me = unit
			end
			if unit.Team == "Monster" then
				if monster == nil or (round.MonsterUserId or 0) == unit.UserId then
					monster = unit
				end
			elseif unit.Team == "Humans" then
				table.insert(humans, unit)
			elseif model ~= localChar then
				table.insert(others, unit)
			end
		end
	end
	table.sort(humans, function(a, b)
		if a.IsLocal ~= b.IsLocal then
			return a.IsLocal
		end
		return tostring(a.Name) < tostring(b.Name)
	end)

	-- SAVE stars
	local saves = {}
	local root: BasePart? = if localChar then localChar:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local okTag, tagged = pcall(function()
		return self.CollectionService:GetTagged("SaveStar")
	end)
	if okTag and type(tagged) == "table" then
		for _, star in tagged do
			if star:IsA("Model") then
				local pos = star:GetPivot().Position
				table.insert(saves, {
					Index = star:GetAttribute("Index") or (#saves + 1),
					Progress = star:GetAttribute("Progress") or 0,
					Lit = star:GetAttribute("Lit") == true,
					Contested = star:GetAttribute("Contested") == true,
					Channelers = star:GetAttribute("Channelers") or 0,
					Radius = star:GetAttribute("Radius") or 7,
					Position = pos,
					Distance = if root then (root.Position - pos).Magnitude else nil,
					Model = star,
				})
			end
		end
		table.sort(saves, function(a, b)
			return a.Index < b.Index
		end)
	end

	-- collapse ring
	local collapse = nil
	local radius = round.CollapseRadius or 0
	if type(radius) == "number" and radius > 0 then
		local center = round.CollapseCenter
		local dist = 0
		if root and typeof(center) == "Vector3" then
			local d = root.Position - center
			dist = Vector3.new(d.X, 0, d.Z).Magnitude
		end
		collapse = { Radius = radius, Center = center, Distance = dist, Outside = dist > radius }
	end

	-- combat (local cooldowns / charge / combo / ammo)
	local cooldowns: { [string]: number } = {}
	if me and me.Cooldowns then
		for id, endsAt in me.Cooldowns do
			cooldowns[id] = endsAt
		end
	end
	local ok, cds = call(self.deps.Combat, "Cooldowns")
	if ok and type(cds) == "table" then
		for id, endsAt in cds do
			if type(endsAt) == "number" then
				cooldowns[id] = math.max(endsAt, cooldowns[id] or 0)
			end
		end
	end
	local charge = nil
	local okC, chargeId, chargeValue = call(self.deps.Combat, "Charge")
	if okC and type(chargeId) == "string" then
		charge = { Id = chargeId, Value = if type(chargeValue) == "number" then chargeValue else 0 }
	end
	local combo = 0
	local okK, comboIndex = call(self.deps.Combat, "ComboIndex")
	if okK and type(comboIndex) == "number" then
		combo = comboIndex
	end
	local ammo = nil
	local okA, a1, a2, a3 = call(self.deps.Combat, "Ammo")
	if okA then
		if type(a1) == "table" then
			ammo = {
				Count = a1.Count or a1.Current or a1[1] or 0,
				Max = a1.Max or a1[2] or 0,
				ReloadEndsAt = a1.ReloadEndsAt or a1.Reload or 0,
			}
		elseif type(a1) == "number" then
			ammo = {
				Count = a1,
				Max = if type(a2) == "number" then a2 else a1,
				ReloadEndsAt = if type(a3) == "number" then a3 else 0,
			}
		end
	end

	-- lobby: monster chances
	local chances = {}
	if players then
		for _, p in playersOf(players) do
			table.insert(chances, {
				Name = p.DisplayName,
				UserId = p.UserId,
				Chance = p:GetAttribute("MonsterChance") or 0,
				Pref = p:GetAttribute("RolePreference") or "Either",
				IsLocal = p == localPlayer,
				Pity = config ~= nil and (p:GetAttribute("RoundsSinceMonster") or 0) >= config.Queue.PityRounds,
			})
		end
		table.sort(chances, function(a, b)
			if a.Chance ~= b.Chance then
				return a.Chance > b.Chance
			end
			return a.Name < b.Name
		end)
	end

	-- spectating / death
	local spectating = nil
	local okS, target = call(self.deps.Spectate, "Target")
	local targetModel = if okS and typeof(target) == "Instance" then target else self.spectate
	if targetModel then
		spectating = self:UnitOf(targetModel, now)
	end
	-- the local SOUL shattered this round: stays "dead" until the round ends or a living body returns
	local phase = round.Phase or "Waiting"
	local fight = phase == "Round" or phase == "Collapse"
	local dead = me ~= nil and me.Dead == true
	if dead and self.deadAt == nil then
		self.deadAt = now
	elseif me == nil and self.deadAt ~= nil and fight then
		dead = true
	elseif not dead then
		self.deadAt = nil
	end

	local kit = if me then Style.Kit(me.KitId) else nil
	local studious = false
	if kit then
		for _, passive in kit.Passives do
			if passive.Id == "Studious" then
				studious = true
			end
		end
	end

	return {
		Now = now,
		Phase = phase,
		EndsAt = round.PhaseEndsAt or 0,
		Practice = round.Practice == true,
		Role = role,
		Device = self:Device(),
		MapId = round.MapId or "",
		VoteOptions = split(round.VoteOptions),
		Votes = self.votes,
		MyVote = self.myVote,
		Chances = chances,
		PlayerCount = math.max(1, #playersOf(players)),
		MinPlayers = if config then config.Round.MinPlayers else 2,
		Me = me,
		Monster = monster,
		MonsterName = round.MonsterName,
		Humans = humans,
		Others = others,
		Saves = saves,
		SavesLit = round.SavesLit or 0,
		SavesTotal = round.SavesTotal or #saves,
		HumansAlive = round.HumansAlive or 0,
		HumansTotal = round.HumansTotal or #humans,
		TeamRevives = round.TeamRevives or 0,
		Harmony = round.Harmony or 1,
		FinalPhase = round.FinalPhase == true,
		Collapse = collapse,
		Cooldowns = cooldowns,
		Charge = charge,
		Combo = combo,
		Ammo = ammo,
		Studious = studious,
		Spectating = spectating,
		Dead = dead,
		DeathAt = self.deadAt,
		Killer = self.killer,
	}
end

function Data:Destroy()
	table.clear(self.dashTrack)
end

return Data

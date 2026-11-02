--!strict
-- VerdictBoxService (P35): the server side of the Verdict Box (SPEC §1.2, §4, §11, §17).
-- AbilityService routes the monster's pseudo-cast "VerdictBox" (slot F; it already checked cooldown, range, cone and
-- line of sight with the cast's aim) to Start(monster, victim). This service re-validates defensively (teams, both up,
-- victim not Downed/Boxed/Invisible, one box per monster and per victim, range + slack, line of sight, not in the
-- Ending phase), then:
--   * victim: Status Boxed + Invulnerable for the duration (+0.25 s): StatusService zeroes WalkSpeed/JumpPower,
--     sets SoulMode = "Boxed" and blocks every damage kind except "Box";
--   * spawns Props.VerdictBox3D anchored Config.VerdictBox.Height above the victim (screen facing the monster) in
--     workspace.VerdictBoxes, attributes BoxId / VictimName / Verdict ("" until the end);
--   * picks a seed and the kit's pattern set (KitDef.VerdictBox -> VerdictBox/Patterns, fallback "Classic") and
--     fires BoxStart {boxId, victim, monster, seed, patternSet, duration, t0, damagePerHit, krPerHit, box, bot} to all.
-- Net "BoxReport" (victim client, incremental hits, finished): accepted hits are capped by Rules.AcceptHits (no hit
--   before the first attack, at most one per Config.VerdictBox.MinHitInterval + latency slack); each accepted hit is
--   DamageService.Apply{Kind = "Box", Amount = DamagePerHit, KR = KRPerHit} (Box damage never drops HP below 1) and
--   gives the monster MonsterUltPerHit ult.
-- Net "BoxSoul" (victim client, unreliable, x, y in box px): validated, <= 15 Hz, relayed to every other player as
--   (boxId, x, y, hits) so watchers mirror the duel on the 3D box (and flash when `hits` grows).
-- Bot victims auto-resolve: 1-4 hits at random times during the attacks (Rules.BotHits); each hit is relayed with
--   the deterministic Sim.AutoSoul position, which watchers also use between relays.
-- End: at the duration, or early when the victim dies / is downed / leaves ("VictimGone") or the monster dies /
--   leaves ("MonsterGone"); CancelAll() (round end) ends everything as "Cancelled". Removes the statuses (unless
--   something else extended them), BoxEnd(boxId, {hits, survived, reason}) to all, Ended:Fire(boxId, victim, hits,
--   survived). survived = finished (Duration / MonsterGone) and still up with hits <= SurviveMaxHits ->
--   DamageUp {mult = SurviveDamageMult} for SurviveBuffTime and +SurviveUlt ult. StatsService counts
--   BoxesSurvived / BoxHits from the Ended signal (so this service does not add them itself).
--   The 3D box stays VERDICT_HOLD s after the end (attribute Verdict = "Innocent"/"Guilty"/"Dismissed") so
--   watchers can read the verdict, then it is destroyed.
--
-- API (SPEC §17)
--   VerdictBoxService.Start(monster, victim) -> boolean   (Start() without arguments = the lifecycle hook)
--   VerdictBoxService.IsBoxed(model) -> boolean
--   VerdictBoxService.CancelAll()
--   VerdictBoxService.Ended: Signal(boxId, victim, hits, survived)
-- Extras
--   VerdictBoxService.Started: Signal(boxId, monster, victim)
--   VerdictBoxService.BoxOf(model) -> number?        active box id of a victim (or of a monster's box)
--   VerdictBoxService.Get(boxId) -> BoxInfo?         { id, monster, victim, seed, set, t0, duration, hits, bot, model }
--   VerdictBoxService.Active() -> {BoxInfo}
--   VerdictBoxService.SetSeedSource(fn?)             tests: deterministic seeds (nil restores the default)
--   VerdictBoxService.Rules                          pure helpers (Lune-tested): CheckPair, AcceptHits, Verdict,
--                                                    VerdictName, ValidSoul, BotHits

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Net = require(Shared.Net) :: any
local Signal = require(Shared.Util.Signal) :: any
local Rng = require(Shared.Util.Rng) :: any
local Kits = require(Shared.Kits) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any
local Patterns = require(Shared.VerdictBox.Patterns) :: any
local Sim = require(Shared.VerdictBox.Sim) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any

local VerdictBoxService = {}
VerdictBoxService.Priority = 35
VerdictBoxService.Ended = Signal.new()
VerdictBoxService.Started = Signal.new()

local TICK = 0.1 -- per-box housekeeping interval (end checks, bot hits)
local RANGE_SLACK = 8 -- studs beyond Config range (AbilityService already checked with +2)
local LATENCY_SLACK = 0.35 -- s of client latency tolerated by the hit cap
local MAX_REPORT_HITS = 8 -- per BoxReport packet
local SOUL_INTERVAL = 1 / 15 - 0.008 -- BoxSoul relay rate cap
local SOUL_LIMIT = 220 -- |x|, |y| in box px (the widest box is 375 px)
local VERDICT_HOLD = 0.9 -- the 3D box shows the verdict this long after the end
local STATUS_PAD = 0.25
local FOLDER = "VerdictBoxes"

local StatusService: any = nil
local DamageService: any = nil

type Box = {
	id: number,
	monster: Model,
	victim: Model,
	player: Player?,
	bot: boolean,
	seed: number,
	set: string,
	t0: number,
	duration: number,
	introEnd: number,
	timeline: any,
	hits: number,
	model: Model?,
	active: boolean,
	statusEnd: number,
	lastSoul: number,
	botHits: { number },
	clientDone: boolean,
}

local boxes: { [number]: Box } = {}
local byVictim: { [Model]: Box } = {}
local byMonster: { [Model]: Box } = {}
local nextId = 0

local function cfg(): any
	return Config.VerdictBox
end

local function now(): number
	return Validation.Now()
end

---------------------------------------------------------------------------------------------------
-- Pure rules (no services; tested offline)

local Rules = {}
VerdictBoxService.Rules = Rules

export type PairInfo = {
	team: string,
	up: boolean,
	boxed: boolean?,
	invisible: boolean?, -- victim only: Invisible humans (Patience stealth) cannot be boxed
	pos: Vector3?,
	look: Vector3?, -- monster only: when given, the cone is checked too
}

-- Can `m` (monster) box `v` (victim)? `los` = line of sight result. Returns (ok, reason?).
function Rules.CheckPair(m: PairInfo, v: PairInfo, los: boolean, c: any?): (boolean, string?)
	local conf = c or cfg()
	if m.team ~= "Monster" then
		return false, "role"
	end
	if v.team ~= "Humans" then
		return false, "target"
	end
	if not m.up then
		return false, "caster"
	end
	if not v.up then
		return false, "down"
	end
	if v.boxed then
		return false, "boxed"
	end
	if v.invisible then
		return false, "invisible"
	end
	if m.pos == nil or v.pos == nil then
		return false, "nopos"
	end
	local offset = (v.pos :: Vector3) - (m.pos :: Vector3)
	if offset.Magnitude > conf.Range + RANGE_SLACK then
		return false, "range"
	end
	if m.look then
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 1 then
			local look = m.look :: Vector3
			local lookFlat = Vector3.new(look.X, 0, look.Z)
			if lookFlat.Magnitude > 1e-3 and flat.Unit:Dot(lookFlat.Unit) < conf.ConeDot - 0.25 then
				return false, "cone"
			end
		end
	end
	if not los then
		return false, "los"
	end
	return true, nil
end

-- How many of `reported` new hits to accept. `accepted` = hits accepted so far, `elapsed` = server time since the
-- box opened. An honest client cannot be hit before the first attack (introEnd) nor more often than MinHitInterval.
function Rules.AcceptHits(accepted: number, reported: any, elapsed: number, introEnd: number, c: any?): number
	local conf = c or cfg()
	if type(reported) ~= "number" or reported ~= reported or reported < 1 then
		return 0
	end
	local want = math.min(math.floor(reported), MAX_REPORT_HITS)
	local fightTime = math.min(elapsed, conf.Duration) + LATENCY_SLACK - introEnd
	if fightTime < 0 then
		return 0
	end
	local interval = math.max(conf.MinHitInterval, 0.05)
	local cap = math.floor(fightTime / interval) + 1
	cap = math.min(cap, math.floor(math.max(conf.Duration - introEnd, 0) / interval) + 1)
	return math.clamp(want, 0, math.max(cap - accepted, 0))
end

-- Survived = the box ran its course (or the monster vanished), the victim is still up and took few enough hits.
function Rules.Verdict(hits: number, reason: string, victimUp: boolean, c: any?): boolean
	local conf = c or cfg()
	return (reason == "Duration" or reason == "MonsterGone") and victimUp and hits <= conf.SurviveMaxHits
end

function Rules.VerdictName(_hits: number, reason: string, survived: boolean): string
	if reason == "Cancelled" or reason == "VictimGone" then
		return "Dismissed"
	end
	return if survived then "Innocent" else "Guilty"
end

function Rules.ValidSoul(x: any, y: any): boolean
	return type(x) == "number"
		and type(y) == "number"
		and x == x
		and y == y
		and math.abs(x) <= SOUL_LIMIT
		and math.abs(y) <= SOUL_LIMIT
end

-- Bot victims: 1-4 hit times (sorted, >= MinHitInterval apart) inside the attack window.
function Rules.BotHits(rng: any, introEnd: number, c: any?): { number }
	local conf = c or cfg()
	local count = rng:Integer(1, 4)
	local lo, hi = introEnd + 0.3, conf.Duration - 0.25
	local out: { number } = {}
	if hi <= lo then
		return out
	end
	local slot = (hi - lo) / count
	for i = 0, count - 1 do
		local a = lo + i * slot
		table.insert(out, a + rng:Number(0, math.max(slot - conf.MinHitInterval, 0)))
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Helpers

local seedRng = Rng.new(os.clock() * 7919 + os.time())
local seedSource: (() -> number)? = nil

function VerdictBoxService.SetSeedSource(fn: (() -> number)?)
	seedSource = fn
end

local function newSeed(): number
	if seedSource then
		return seedSource()
	end
	return seedRng:Integer(1, 2147483646)
end

local function addUlt(model: Model?, amount: number)
	if model == nil or model.Parent == nil or amount <= 0 then
		return
	end
	local cur = model:GetAttribute("Ult")
	if type(cur) == "number" then
		model:SetAttribute("Ult", DamageMath.AddUlt(cur, amount))
	end
end

local function displayName(model: Model): string
	local player = Validation.GetPlayer(model)
	if player then
		return player.DisplayName
	end
	return model.Name
end

local function boxFolder(): Instance?
	local ok, ws = pcall(function()
		return workspace
	end)
	if not ok or typeof(ws) ~= "Instance" then
		return nil
	end
	local folder = (ws :: Instance):FindFirstChild(FOLDER)
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = ws
		folder = f
	end
	return folder
end

local function place(model: Model, cf: CFrame)
	local ok = pcall(function()
		model:PivotTo(cf)
	end)
	if not ok then
		-- offline fallback (the prop is built at the origin)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = cf * d.CFrame
			end
		end
	end
end

local function spawnModel(box: Box, monsterPos: Vector3, victimPos: Vector3): Model?
	local okProps, Props = pcall(require, Shared.Rigs.Props)
	if not okProps or type(Props) ~= "table" then
		return nil
	end
	local ok, model = pcall(Props.Build, "VerdictBox3D")
	if not ok or typeof(model) ~= "Instance" then
		warn("[VerdictBoxService] VerdictBox3D build failed: " .. tostring(model))
		return nil
	end
	local m = model :: Model
	m.Name = "VerdictBox_" .. box.id
	m:SetAttribute("BoxId", box.id)
	m:SetAttribute("VictimName", displayName(box.victim))
	m:SetAttribute("Verdict", "")
	local toMonster = Vector3.new(monsterPos.X - victimPos.X, 0, monsterPos.Z - victimPos.Z)
	local dir = if toMonster.Magnitude > 0.1 then toMonster.Unit else Vector3.new(0, 0, -1)
	place(m, HazardDefs.LookAlong(victimPos + Vector3.new(0, cfg().Height, 0), dir))
	local folder = boxFolder()
	if folder then
		m.Parent = folder
	end
	return m
end

local function removeOwnStatus(model: Model, name: string, ourEnd: number)
	local endsAt = StatusService.Get(model, name)
	if endsAt ~= nil and endsAt <= ourEnd + 0.05 then
		StatusService.Remove(model, name)
	end
end

local function info(box: Box): { [string]: any }
	return {
		id = box.id,
		monster = box.monster,
		victim = box.victim,
		seed = box.seed,
		set = box.set,
		t0 = box.t0,
		duration = box.duration,
		hits = box.hits,
		bot = box.bot,
		model = box.model,
	}
end

local function relaySoul(box: Box, except: Player?, x: number, y: number)
	local qx, qy = math.round(x * 10) / 10, math.round(y * 10) / 10
	for _, p in Players:GetPlayers() do
		if p ~= except then
			Net.Server.Fire("BoxSoul", p, box.id, qx, qy, box.hits)
		end
	end
end

local function applyHits(box: Box, n: number)
	local c = cfg()
	for _ = 1, n do
		if not box.active then
			return
		end
		box.hits += 1
		local ok, err = pcall(DamageService.Apply, {
			Attacker = box.monster,
			Target = box.victim,
			Amount = c.DamagePerHit,
			Kind = "Box",
			KR = c.KRPerHit,
			Ability = "VerdictBox",
			Dodgeable = false,
			Blockable = false,
		})
		if not ok then
			warn("[VerdictBoxService] box damage failed: " .. tostring(err))
		end
		addUlt(box.monster, c.MonsterUltPerHit)
	end
end

local function gone(model: Model): boolean
	return model.Parent == nil or model:GetAttribute("Dead") == true or not Validation.IsAlive(model)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function finish(box: Box, reason: string)
	if not box.active then
		return
	end
	box.active = false
	boxes[box.id] = nil
	if byVictim[box.victim] == box then
		byVictim[box.victim] = nil
	end
	if byMonster[box.monster] == box then
		byMonster[box.monster] = nil
	end
	local victim = box.victim
	if victim.Parent ~= nil then
		pcall(removeOwnStatus, victim, "Boxed", box.statusEnd)
		pcall(removeOwnStatus, victim, "Invulnerable", box.statusEnd)
	end
	local up = Validation.IsUp(victim)
	local survived = Rules.Verdict(box.hits, reason, up)
	if survived then
		local c = cfg()
		pcall(StatusService.Apply, victim, "DamageUp", c.SurviveBuffTime, { mult = c.SurviveDamageMult })
		addUlt(victim, c.SurviveUlt)
	end
	local model = box.model
	if model then
		model:SetAttribute("Verdict", Rules.VerdictName(box.hits, reason, survived))
		if reason == "Cancelled" then
			model:Destroy()
		else
			Validation.Delay(VERDICT_HOLD, function()
				model:Destroy()
			end)
		end
	end
	Net.Server.FireAll("BoxEnd", box.id, { hits = box.hits, survived = survived, reason = reason })
	VerdictBoxService.Ended:Fire(box.id, victim, box.hits, survived)
end

local function tickBox(box: Box)
	if not box.active then
		return
	end
	local elapsed = now() - box.t0
	if gone(box.victim) or box.victim:GetAttribute("Downed") == true or (box.player and box.player.Parent == nil) then
		finish(box, "VictimGone")
		return
	end
	if gone(box.monster) then
		finish(box, "MonsterGone")
		return
	end
	-- bot victims: scheduled hits
	while box.bot and #box.botHits > 0 and elapsed >= box.botHits[1] do
		table.remove(box.botHits, 1)
		applyHits(box, 1)
		if box.active then
			local x, y = Sim.AutoSoul(box.timeline, elapsed)
			relaySoul(box, nil, x, y)
		end
	end
	if not box.active then
		return
	end
	if elapsed >= box.duration then
		finish(box, "Duration")
		return
	end
	Validation.Delay(math.min(TICK, math.max(box.duration - elapsed, 0.02)), function()
		tickBox(box)
	end)
end

local startService: () -> ()

-- Dual use: Main.server calls Start() with no arguments as the service lifecycle hook (connect remotes);
-- AbilityService calls Start(monster, victim) to open a box.
function VerdictBoxService.Start(monster: Model?, victim: Model?): boolean
	if monster == nil and victim == nil then
		startService()
		return false
	end
	if StatusService == nil or DamageService == nil then
		return false
	end
	if typeof(monster) ~= "Instance" or typeof(victim) ~= "Instance" then
		return false
	end
	if not (monster :: Model):IsA("Model") or not (victim :: Model):IsA("Model") or monster == victim then
		return false
	end
	return VerdictBoxService.Open(monster :: Model, victim :: Model)
end

-- Opens a box (after the argument checks of Start).
function VerdictBoxService.Open(monster: Model, victim: Model): boolean
	if StatusService == nil or DamageService == nil then
		return false
	end
	if byMonster[monster] ~= nil or byVictim[victim] ~= nil then
		return false
	end
	if Validation.RoundAttr("Phase") == "Ending" then
		return false
	end
	local mPos, vPos = Validation.RootPosition(monster), Validation.RootPosition(victim)
	local ok = Rules.CheckPair({
		team = Validation.Team(monster),
		up = Validation.IsUp(monster),
		pos = mPos,
	}, {
		team = Validation.Team(victim),
		up = Validation.IsUp(victim),
		boxed = StatusService.Has(victim, "Boxed"),
		invisible = victim:GetAttribute("Invisible") == true or StatusService.Has(victim, "Invisible"),
		pos = vPos,
	}, mPos ~= nil and vPos ~= nil and Validation.LineOfSight(mPos, vPos))
	if not ok then
		return false
	end
	local c = cfg()
	local kit = Kits.Get(monster:GetAttribute("KitId"))
	local set = Patterns.Resolve(kit and kit.VerdictBox)
	local seed = newSeed()
	local duration = c.Duration
	local timeline = Patterns.Build(set, seed, duration)
	local player = Validation.GetPlayer(victim)
	local t0 = now()
	nextId += 1
	local box: Box = {
		id = nextId,
		monster = monster,
		victim = victim,
		player = player,
		bot = player == nil or victim:GetAttribute("IsBot") == true,
		seed = seed,
		set = set,
		t0 = t0,
		duration = duration,
		introEnd = timeline.introEnd,
		timeline = timeline,
		hits = 0,
		model = nil,
		active = true,
		statusEnd = t0 + duration + STATUS_PAD,
		lastSoul = 0,
		botHits = {},
		clientDone = false,
	}
	if box.bot then
		box.botHits = Rules.BotHits(Rng.new(seed), timeline.introEnd)
	end
	StatusService.Apply(victim, "Boxed", duration + STATUS_PAD)
	StatusService.Apply(victim, "Invulnerable", duration + STATUS_PAD)
	box.model = spawnModel(box, mPos :: Vector3, vPos :: Vector3)
	boxes[box.id] = box
	byVictim[victim] = box
	byMonster[monster] = box
	Net.Server.FireAll("BoxStart", {
		boxId = box.id,
		victim = victim,
		monster = monster,
		seed = seed,
		patternSet = set,
		duration = duration,
		t0 = t0,
		damagePerHit = c.DamagePerHit,
		krPerHit = c.KRPerHit,
		box = box.model,
		bot = box.bot,
	})
	VerdictBoxService.Started:Fire(box.id, monster, victim)
	Validation.Delay(TICK, function()
		tickBox(box)
	end)
	return true
end

function VerdictBoxService.IsBoxed(model: Model?): boolean
	return model ~= nil and byVictim[model :: Model] ~= nil
end

function VerdictBoxService.BoxOf(model: Model?): number?
	if model == nil then
		return nil
	end
	local box = byVictim[model :: Model] or byMonster[model :: Model]
	return if box then box.id else nil
end

function VerdictBoxService.Get(boxId: number): { [string]: any }?
	local box = boxes[boxId]
	return if box then info(box) else nil
end

function VerdictBoxService.Active(): { { [string]: any } }
	local out = {}
	for _, box in boxes do
		table.insert(out, info(box))
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function VerdictBoxService.CancelAll()
	local list = {}
	for _, box in boxes do
		table.insert(list, box)
	end
	for _, box in list do
		finish(box, "Cancelled")
	end
end

---------------------------------------------------------------------------------------------------
-- Remotes

local function boxFor(player: Player, boxId: any): Box?
	if type(boxId) ~= "number" then
		return nil
	end
	local box = boxes[boxId]
	if box == nil or not box.active or box.player ~= player then
		return nil
	end
	return box
end

local function onReport(player: Player, boxId: any, hits: any, finished: any)
	local box = boxFor(player, boxId)
	if box == nil then
		return
	end
	local n = Rules.AcceptHits(box.hits, hits, now() - box.t0, box.introEnd)
	if n > 0 then
		applyHits(box, n)
	end
	if finished == true then
		box.clientDone = true
	end
end

local function onSoul(player: Player, boxId: any, x: any, y: any)
	local box = boxFor(player, boxId)
	if box == nil or not Rules.ValidSoul(x, y) then
		return
	end
	local t = now()
	if t - box.lastSoul < SOUL_INTERVAL then
		return
	end
	box.lastSoul = t
	relaySoul(box, player, x, y)
end

function VerdictBoxService.Init()
	StatusService = require(script.Parent.StatusService) :: any
	DamageService = require(script.Parent.DamageService) :: any
end

local connected = false
startService = function()
	if connected then
		return
	end
	connected = true
	Net.Server.On("BoxReport", onReport)
	Net.Server.On("BoxSoul", onSoul)
	local cs = Validation.Service("CharacterService")
	if cs and cs.Despawning then
		cs.Despawning:Connect(function(model: Model)
			local box = byVictim[model]
			if box then
				finish(box, "VictimGone")
			end
			local mbox = byMonster[model]
			if mbox then
				finish(mbox, "MonsterGone")
			end
		end)
	end
end

return VerdictBoxService

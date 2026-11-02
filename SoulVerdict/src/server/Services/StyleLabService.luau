--!strict
-- StyleLabService (P80): server side of the owner-only Style Lab (SPEC §10). Handles RequestService
-- action "StyleLab" with data = { action = string, ... } (a bare action string is accepted too).
-- Allowed for: Studio, the place owner (user-owned place), the group owner (rank 255, group-owned place),
-- the private server owner, or everyone when Config.StyleLab.AllowEveryone. Allowed players get the
-- Player attribute "StyleLab" = true so the client can show the Style Lab entry.
-- (Graphics preset, menu theme, HUD style, rig style... are switched client side; only server-authoritative
-- things live here.)
--
-- Actions
--   SetMap {mapId, now?, side?}   force the next map; now = true: start it right away (skip the
--                                 intermission, or a solo practice while Waiting, or abort the running match)
--   StartRound {side?}            skip the current timed phase; while Waiting alone -> practice
--   StartPractice {side?, allies?}
--   SpawnDummy {count?}           1..5 temporary training dummies in front of you (cleared with the match)
--   GiveUlt                       your character's Ult = 100
--   SetPhase {phase}              "FinalPhase" | "Collapse" | "Skip" | "End" (= EndRound)
--   EndRound {winner?}            finish the match now (reason "Aborted"; winner "Humans"|"Monster")
--   Abort                         stop the match without results
--   Heal                          full health for your character
--   ResetCooldowns                clear your ability cooldowns
--   SetSkin {kitId, skinId}       lobby only: respawn your lobby body in place with that skin (preview, not saved)
-- Handler returns (ok, errKey?) as RequestService expects; successes answer Notify "round.lab.done".
-- Chat commands (TextChatService, same permission check) so the owner can test solo even without menus:
--   /practice [human|monster] [allies]   /skip   /final   /collapse   /end [monster]   /abort
--   /map <mapId> [now]   /dummy [n]   /ult   /heal   /cooldowns

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any

local StyleLabService = {}
StyleLabService.Priority = 80

local RoundService: any = nil
local CharacterService: any = nil
local BotService: any = nil
local AbilityService: any = nil
local DamageService: any = nil
local RequestService: any = nil

local groupOwners: { [Player]: boolean } = {}

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function call(service: any, method: string, ...: any): (boolean, any)
	if service == nil then
		return false, nil
	end
	local fn = service[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[StyleLabService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

function StyleLabService.IsAllowed(player: Player): boolean
	if Config.StyleLab.Enabled == false then
		return false
	end
	if RunService:IsStudio() or Config.StyleLab.AllowEveryone == true then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 and game.PrivateServerOwnerId == player.UserId then
		return true
	end
	return groupOwners[player] == true
end

local function ownModel(player: Player): Model?
	if CharacterService and type(CharacterService.GetModel) == "function" then
		local ok, model = pcall(CharacterService.GetModel, player)
		if ok and model then
			return model
		end
	end
	return player.Character
end

local function str(v: any, maxLen: number): string?
	if type(v) == "string" and #v <= maxLen then
		return v
	end
	return nil
end

local function side(v: any): string
	return if v == "Monster" then "Monster" else "Human"
end

local function phase(): string
	local ok, p = call(RoundService, "Phase")
	return if ok and type(p) == "string" then p else "Waiting"
end

local function startRound(player: Player, data: any): (boolean, string?)
	local current = phase()
	if current == "Waiting" then
		if #Players:GetPlayers() >= Config.Round.MinPlayers then
			return true, nil -- the loop moves to Intermission by itself
		end
		local _, ok, err = pcall(RoundService.StartPractice, player, side(data.side), nil)
		return ok == true, err
	end
	call(RoundService, "SkipPhase")
	return true, nil
end

local ACTIONS: { [string]: (Player, any) -> (boolean, string?) } = {
	SetMap = function(player: Player, data: any): (boolean, string?)
		local mapId = str(data.mapId, 64)
		if mapId == nil then
			return false, "round.lab.noMap"
		end
		local ok, forced = call(RoundService, "ForceNextMap", mapId)
		if not ok or forced ~= true then
			return false, "round.lab.noMap"
		end
		if data.now == true then
			local current = phase()
			if current == "Intermission" then
				call(RoundService, "SkipPhase")
			elseif current == "Waiting" then
				return startRound(player, data)
			else
				call(RoundService, "Abort")
			end
		end
		return true, nil
	end,

	StartRound = function(player: Player, data: any): (boolean, string?)
		return startRound(player, data)
	end,

	StartPractice = function(player: Player, data: any): (boolean, string?)
		local allies = if type(data.allies) == "number" and data.allies == data.allies then data.allies else nil
		local okCall, ok, err = pcall(RoundService.StartPractice, player, side(data.side), allies)
		if not okCall then
			return false, "round.practice.unavailable"
		end
		return ok == true, err
	end,

	SpawnDummy = function(player: Player, data: any): (boolean, string?)
		local model = ownModel(player)
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return false, "round.lab.noCharacter"
		end
		local count = if type(data.count) == "number" and data.count == data.count
			then math.clamp(math.floor(data.count), 1, 5)
			else 1
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
		local right = Vector3.new(-look.Z, 0, look.X)
		local humanoid = (model :: Model):FindFirstChildOfClass("Humanoid")
		local lift = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
		local ground = root.Position - Vector3.new(0, lift, 0)
		local frames: { CFrame } = {}
		for i = 1, count do
			local offset = (i - (count + 1) / 2) * 5
			local pos = ground + look * 12 + right * offset
			table.insert(frames, CFrame.lookAt(pos, Vector3.new(ground.X, pos.Y, ground.Z)))
		end
		local ok, spawned = call(BotService, "SpawnDummies", frames, { Temporary = true })
		return ok and type(spawned) == "table" and #spawned > 0, if ok then nil else "round.practice.unavailable"
	end,

	GiveUlt = function(player: Player, _data: any): (boolean, string?)
		local model = ownModel(player)
		if model == nil then
			return false, "round.lab.noCharacter"
		end
		model:SetAttribute("Ult", 100)
		return true, nil
	end,

	Heal = function(player: Player, _data: any): (boolean, string?)
		local model = ownModel(player)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if model == nil or humanoid == nil or model:GetAttribute("Dead") == true then
			return false, "round.lab.noCharacter"
		end
		local ok = call(DamageService, "SetHealth", model, humanoid.MaxHealth)
		if not ok then
			humanoid.Health = humanoid.MaxHealth
		end
		model:SetAttribute("KR", 0)
		return true, nil
	end,

	-- Preview any skin of a kit on your lobby body without owning / equipping it (the Style Lab skin cycler sends
	-- this for skins you do not own; integration fix: the action did not exist). The next lobby respawn or
	-- equipment change restores the equipped look.
	SetSkin = function(player: Player, data: any): (boolean, string?)
		local Kits = require(Shared:WaitForChild("Kits")) :: any
		local kitId = str(data.kitId, 40)
		local skinId = str(data.skinId, 40)
		if kitId == nil or skinId == nil or Kits.Get(kitId) == nil or Kits.Skin(kitId, skinId) == nil then
			return false, "round.lab.unknown"
		end
		local model = ownModel(player)
		local root = model and model:FindFirstChild("HumanoidRootPart")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if model == nil or root == nil or humanoid == nil or not root:IsA("BasePart") or model:GetAttribute("Dead") == true then
			return false, "round.lab.noCharacter"
		end
		if model:GetAttribute("Team") ~= "Lobby" then
			return false, "round.trykit.notLobby"
		end
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
		local ok = call(CharacterService, "SpawnPlayer", player, kitId, CFrame.new(feet) * root.CFrame.Rotation, {
			Team = "Lobby",
			SkinId = skinId,
		})
		if ok then
			player:SetAttribute("Role", "Lobby")
		end
		return ok, if ok then nil else "round.lab.unknown"
	end,

	ResetCooldowns = function(player: Player, _data: any): (boolean, string?)
		local model = ownModel(player)
		if model == nil then
			return false, "round.lab.noCharacter"
		end
		call(AbilityService, "ResetCooldowns", model)
		return true, nil
	end,

	SetPhase = function(_player: Player, data: any): (boolean, string?)
		local which = str(data.phase, 32)
		if which == "FinalPhase" then
			local _, ok = call(RoundService, "TriggerFinalPhase")
			return ok == true, if ok then nil else "round.lab.noRound"
		elseif which == "Collapse" then
			local _, ok = call(RoundService, "ForceCollapse")
			return ok == true, if ok then nil else "round.lab.noRound"
		elseif which == "Skip" then
			call(RoundService, "SkipPhase")
			return true, nil
		elseif which == "End" or which == "Ending" then
			local _, ok =
				call(RoundService, "EndRound", if data.winner == "Monster" then "Monster" else "Humans", "Aborted")
			return ok == true, if ok then nil else "round.lab.noRound"
		end
		return false, "round.lab.unknown"
	end,

	EndRound = function(_player: Player, data: any): (boolean, string?)
		local _, ok =
			call(RoundService, "EndRound", if data.winner == "Monster" then "Monster" else "Humans", "Aborted")
		return ok == true, if ok then nil else "round.lab.noRound"
	end,

	Abort = function(_player: Player, _data: any): (boolean, string?)
		local _, ok = call(RoundService, "Abort")
		return ok == true, if ok then nil else "round.lab.noRound"
	end,
}

local function onStyleLab(player: Player, payload: any): (boolean, string?)
	if not StyleLabService.IsAllowed(player) then
		return false, "round.lab.denied"
	end
	local data: any = payload
	if type(payload) == "string" then
		data = { action = payload }
	end
	if type(data) ~= "table" then
		return false, "round.lab.unknown"
	end
	local action = str(data.action, 32)
	local handler = if action then ACTIONS[action] else nil
	if handler == nil or RoundService == nil then
		return false, "round.lab.unknown"
	end
	local okCall, ok, err = pcall(handler, player, data)
	if not okCall then
		warn("[StyleLabService] " .. tostring(action) .. " failed: " .. tostring(ok))
		return false, "round.lab.unknown"
	end
	if ok then
		pcall(Net.Server.Fire, "Notify", player, "round.lab.done", { action }, "Info")
	end
	return ok == true, err
end

local function refreshAttribute(player: Player)
	player:SetAttribute("StyleLab", StyleLabService.IsAllowed(player))
end

local function onPlayerAdded(player: Player)
	refreshAttribute(player)
	if game.CreatorType == Enum.CreatorType.Group then
		task.spawn(function()
			local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
			if ok and type(groups) == "table" then
				for _, g in groups do
					if type(g) == "table" and g.Id == game.CreatorId and type(g.Rank) == "number" and g.Rank >= 255 then
						groupOwners[player] = true
					end
				end
			end
			if player.Parent then
				refreshAttribute(player)
			end
		end)
	end
end

function StyleLabService.Init()
	RoundService = tryService("RoundService")
	CharacterService = tryService("CharacterService")
	BotService = tryService("BotService")
	AbilityService = tryService("AbilityService")
	DamageService = tryService("DamageService")
	RequestService = tryService("RequestService")
	if RequestService and type(RequestService.Register) == "function" then
		local ok, err = pcall(RequestService.Register, "StyleLab", onStyleLab)
		if not ok then
			warn("[StyleLabService] registration failed: " .. tostring(err))
		end
	end
end

-- Chat command -> Style Lab action payload.
local COMMANDS: { [string]: (args: { string }) -> any } = {
	practice = function(args)
		return {
			action = "StartPractice",
			side = if args[1] == "monster" then "Monster" else "Human",
			allies = tonumber(args[2]),
		}
	end,
	skip = function()
		return { action = "StartRound" }
	end,
	final = function()
		return { action = "SetPhase", phase = "FinalPhase" }
	end,
	collapse = function()
		return { action = "SetPhase", phase = "Collapse" }
	end,
	["end"] = function(args)
		return { action = "EndRound", winner = if args[1] == "monster" then "Monster" else "Humans" }
	end,
	abort = function()
		return { action = "Abort" }
	end,
	map = function(args)
		return { action = "SetMap", mapId = args[1], now = args[2] == "now" }
	end,
	dummy = function(args)
		return { action = "SpawnDummy", count = tonumber(args[1]) }
	end,
	ult = function()
		return { action = "GiveUlt" }
	end,
	heal = function()
		return { action = "Heal" }
	end,
	cooldowns = function()
		return { action = "ResetCooldowns" }
	end,
}

local function setupChatCommands()
	local TextChatService = game:GetService("TextChatService")
	local folder = Instance.new("Folder")
	folder.Name = "StyleLabCommands"
	for name, toPayload in COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = "SV_" .. name
		command.PrimaryAlias = "/" .. name
		command.AutocompleteVisible = false
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player == nil or not StyleLabService.IsAllowed(player) then
				return
			end
			local args: { string } = {}
			for word in string.gmatch(string.lower(text), "%S+") do
				table.insert(args, word)
			end
			table.remove(args, 1) -- the alias itself
			if name == "map" and args[1] then
				-- map ids are case sensitive: take the original spelling
				local original = string.match(text, "^%S+%s+(%S+)")
				args[1] = original or args[1]
			end
			local ok, err = onStyleLab(player, toPayload(args))
			if not ok and err then
				pcall(Net.Server.Fire, "Notify", player, err, nil, "Warning")
			end
		end)
		command.Parent = folder
	end
	folder.Parent = TextChatService
end

function StyleLabService.Start()
	local okChat, chatErr = pcall(setupChatCommands)
	if not okChat then
		warn("[StyleLabService] chat commands unavailable: " .. tostring(chatErr))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		groupOwners[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Exposed for tests / other services (e.g. a chat command) — same validation as the request.
StyleLabService.Handle = onStyleLab

return StyleLabService

--!strict
-- HintController (client, Priority 60): Easy-difficulty tips for newcomers (owner: "a newbie won't understand what
-- is going on"). Only while the local player's "Difficulty" attribute (DifficultyService) has Config.Difficulty.Hints:
--   * a BLUE / ORANGE monster attack telegraphed near the local human -> "stand still" / "keep moving" toast
--   * the local player pulled into the Verdict Box (VerdictBoxController.Started, victim) -> how the box works
--   * the first fight phase of each round as a human -> one general tip (dash, block, SAVE stars)
-- Every tip is rate-limited (Cooldown s between repeats, at most MaxPerSession times) so it never nags.
--
-- API
--   HintController.ShouldHint(kind, state) -> boolean   pure: state = { Level, Shown, LastAt, Now }
--   HintController.Show(kind)                           toast now (respects the limits)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any

local HintController = {}
HintController.Priority = 60
HintController.Cooldown = 25 -- s between two tips of the same kind
HintController.MaxPerSession = 4 -- each kind at most this often per session
HintController.NearDistance = 45 -- studs: only attacks around the local player

local shown: { [string]: number } = {}
local lastAt: { [string]: number } = {}
local cache: { [string]: any } = {}

local function controller(name: string): any?
	if cache[name] ~= nil then
		return if cache[name] == false then nil else cache[name]
	end
	local module = script.Parent and script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			cache[name] = result
			return result
		end
	end
	cache[name] = false
	return nil
end

local function level(): string
	local player = Players.LocalPlayer
	local attr = player and player:GetAttribute("Difficulty")
	if type(attr) == "string" then
		return attr
	end
	return (Config.Defaults and Config.Defaults.Difficulty) or "Normal"
end

function HintController.ShouldHint(kind: string, state: { [string]: any }): boolean
	local hints = Config.Difficulty and Config.Difficulty.Hints
	if not (hints and hints[state.Level] == true) then
		return false
	end
	local count = (state.Shown or {})[kind] or 0
	if count >= HintController.MaxPerSession then
		return false
	end
	local last = (state.LastAt or {})[kind]
	return last == nil or state.Now - last >= HintController.Cooldown
end

function HintController.Show(kind: string)
	local t = os.clock()
	if not HintController.ShouldHint(kind, { Level = level(), Shown = shown, LastAt = lastAt, Now = t }) then
		return
	end
	shown[kind] = (shown[kind] or 0) + 1
	lastAt[kind] = t
	local UI = controller("UIController")
	if UI and type(UI.Notify) == "function" then
		pcall(UI.Notify, "diff.hint." .. kind, nil, "Info")
	end
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isLocalHuman(): boolean
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character ~= nil and character:GetAttribute("Team") == "Humans"
end

local function onHazard(packet: any)
	if type(packet) ~= "table" or packet.team ~= "Monster" or not isLocalHuman() then
		return
	end
	local params = if type(packet.params) == "table" then packet.params else {}
	local rule = params.color
	if rule ~= "Blue" and rule ~= "Orange" then
		return
	end
	local root = localRoot()
	local origin = params.origin
	local pos = if typeof(origin) == "CFrame" then origin.Position elseif typeof(origin) == "Vector3" then origin else nil
	if root and pos and (pos - root.Position).Magnitude > HintController.NearDistance then
		return
	end
	HintController.Show(rule)
end

function HintController.Init() end

function HintController.Start()
	pcall(function()
		local Net = require(Shared:WaitForChild("Net")) :: any
		Net.Client.On("Hazard", onHazard)
	end)
	local Box = controller("VerdictBoxController")
	if Box and Box.Started and Box.Started.Connect then
		Box.Started:Connect(function(_boxId: any, isVictim: boolean)
			if isVictim then
				HintController.Show("Box")
			end
		end)
	end
	local roundState = ReplicatedStorage:FindFirstChild("RoundState") or ReplicatedStorage:WaitForChild("RoundState", 30)
	if roundState then
		roundState:GetAttributeChangedSignal("Phase"):Connect(function()
			if roundState:GetAttribute("Phase") == "Round" and isLocalHuman() then
				task.delay(2, HintController.Show, "Round")
			end
		end)
	end
end

return HintController

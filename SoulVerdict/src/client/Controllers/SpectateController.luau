--!strict
-- SpectateController (client, SPEC §20, Priority 45): spectating living fighters while the local player is a
-- Spectator (late join) or dead during Intro / Round / Collapse / Ending.
--   * On the local character's death: CameraController.KillCam(own position, 2.2 s), then spectate.
--   * Targets: living (not Dead; Downed still counts) characters of team "Monster" / "Humans", monster first then
--     by name; cycled with InputController actions "Prev"/"Next" (Q/E, D-pad, X/Y, LB/RB) or Next()/Prev() from the
--     SpectateHud buttons. A target that dies is left on screen for 1.2 s, then the next one is picked.
--   * While active it pushes InputController context "Dead" (combat actions suppressed) and drives
--     CameraController.Spectate(model); when the player gets a living character back (or the phase returns to the
--     lobby) it pops the context and returns the camera to Follow.
--
-- API
--   SpectateController.IsSpectating() -> boolean ; Changed: Signal(active)
--   SpectateController.Target() -> Model? ; TargetChanged: Signal(model?)
--   SpectateController.Targets() -> {Model}
--   SpectateController.Next() / Prev()
--   SpectateController.SetEnabled(on)          false = never auto-spectate (Style Lab, tutorials)
--   SpectateController.TargetName() -> string  display name for the HUD ("" when none)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams"))

local SpectateController = {}
SpectateController.Priority = 45

SpectateController.Changed = Signal.new()
SpectateController.TargetChanged = Signal.new()

local TUNING = {
	PollInterval = 0.25,
	DeadTargetHold = 1.2,
	OwnDeathKillCam = 2.2,
}
SpectateController.Tuning = TUNING

local ACTIVE_PHASES = { Intro = true, Round = true, Collapse = true, Ending = true }

local enabled = true
local active = false
local target: Model? = nil
local targetDeadSince: number? = nil
local holdUntil = 0
local contextPushed = false
local started = false

-------------------------------------------------------------------------------------------- lazy deps

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = script.Parent
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			controllerCache[name] = result
			return result
		end
	end
	controllerCache[name] = false
	return nil
end

local function call(name: string, fn: string, ...: any): any
	local module = controller(name)
	if module and type(module[fn]) == "function" then
		local ok, result = pcall(module[fn], ...)
		if ok then
			return result
		end
	end
	return nil
end

local function localCharacter(): Model?
	local model = call("StateController", "LocalCharacter")
	if model ~= nil then
		return model
	end
	local player = Players.LocalPlayer
	return if player then player.Character else nil
end

local function rootOf(model: Model?): BasePart?
	if model == nil or model.Parent == nil then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

------------------------------------------------------------------------------------------------ targets

local function isFighter(model: Instance?): boolean
	if model == nil or not model:IsA("Model") or model.Parent == nil then
		return false
	end
	local team = Teams.TeamOf(model)
	if team ~= Teams.Humans and team ~= Teams.Monster then
		return false
	end
	if model:GetAttribute("Dead") == true then
		return false
	end
	return rootOf(model :: Model) ~= nil
end

function SpectateController.Targets(): { Model }
	local me = localCharacter()
	local list: { Model } = {}
	local seen: { [Instance]: boolean } = {}
	local function consider(model: Instance?)
		if model and model ~= me and not seen[model] and isFighter(model) then
			seen[model] = true
			table.insert(list, model :: Model)
		end
	end
	for _, player in Players:GetPlayers() do
		consider(player.Character)
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, child in bots:GetChildren() do
			consider(child)
		end
	end
	table.sort(list, function(a, b)
		local am = Teams.TeamOf(a) == Teams.Monster
		local bm = Teams.TeamOf(b) == Teams.Monster
		if am ~= bm then
			return am
		end
		return a.Name < b.Name
	end)
	return list
end

local function setTarget(model: Model?)
	targetDeadSince = nil
	if target == model then
		return
	end
	target = model
	if active then
		call("CameraController", "Spectate", model)
	end
	SpectateController.TargetChanged:Fire(model)
end

local function step(delta: number)
	local list = SpectateController.Targets()
	if #list == 0 then
		setTarget(nil)
		return
	end
	local index = if target then table.find(list, target :: Model) else nil
	if index == nil then
		-- the current target is gone: keep the order stable by name position
		setTarget(list[if delta < 0 then #list else 1])
		return
	end
	local nextIndex = ((index - 1 + delta) % #list) + 1
	setTarget(list[nextIndex])
end

function SpectateController.Next()
	if active then
		step(1)
	end
end

function SpectateController.Prev()
	if active then
		step(-1)
	end
end

function SpectateController.Target(): Model?
	return target
end

function SpectateController.TargetName(): string
	local model = target
	if model == nil then
		return ""
	end
	local userId = model:GetAttribute("OwnerUserId")
	if type(userId) == "number" and userId > 0 then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			return player.DisplayName
		end
	end
	return model.Name
end

function SpectateController.IsSpectating(): boolean
	return active
end

---------------------------------------------------------------------------------------------- state machine

local function shouldSpectate(): boolean
	if not enabled then
		return false
	end
	local role = call("StateController", "Role")
	if role == "Spectator" then
		return true
	end
	local phase = call("StateController", "Phase")
	if not ACTIVE_PHASES[phase] then
		return false
	end
	local me = localCharacter()
	if me == nil then
		return role == "Human" or role == "Monster"
	end
	return me:GetAttribute("Dead") == true
end

local function pushContext(on: boolean)
	if on == contextPushed then
		return
	end
	local Input = controller("InputController")
	if Input == nil then
		return
	end
	contextPushed = on
	if on then
		Input.PushContext("Dead")
	else
		Input.PopContext("Dead")
	end
end

local function begin()
	active = true
	pushContext(true)
	SpectateController.Changed:Fire(true)
	local list = SpectateController.Targets()
	target = nil
	setTarget(list[1]) -- drives CameraController.Spectate (active is already true)
end

local function finish()
	active = false
	pushContext(false)
	target = nil
	targetDeadSince = nil
	call("CameraController", "Spectate", nil)
	SpectateController.Changed:Fire(false)
	SpectateController.TargetChanged:Fire(nil)
end

local function evaluate()
	local want = shouldSpectate()
	if want and not active and os.clock() >= holdUntil then
		begin()
	elseif not want and active then
		finish()
	end
	if not active then
		return
	end
	local current = target
	if current == nil then
		step(1)
		return
	end
	if current.Parent == nil then
		setTarget(nil)
		step(1)
		return
	end
	if current:GetAttribute("Dead") == true then
		local since = targetDeadSince
		if since == nil then
			targetDeadSince = os.clock()
		elseif os.clock() - since >= TUNING.DeadTargetHold then
			step(1)
		end
	end
end

function SpectateController.SetEnabled(on: boolean)
	enabled = on == true
	evaluate()
end

local function onOwnDeath(model: Model)
	local root = rootOf(model)
	if root then
		holdUntil = os.clock() + 0.2
		call("CameraController", "KillCam", root.Position, TUNING.OwnDeathKillCam)
	end
	task.delay(0.25, evaluate)
end

local function watchCharacter(model: Model?)
	if model == nil then
		evaluate()
		return
	end
	local connection: RBXScriptConnection? = nil
	connection = model:GetAttributeChangedSignal("Dead"):Connect(function()
		if model:GetAttribute("Dead") == true then
			onOwnDeath(model)
		else
			evaluate()
		end
	end)
	model.AncestryChanged:Connect(function()
		if model.Parent == nil and connection then
			connection:Disconnect()
			connection = nil
		end
	end)
	evaluate()
end

----------------------------------------------------------------------------------------------- lifecycle

function SpectateController.Init() end

function SpectateController.Start()
	if started then
		return
	end
	started = true
	local State = controller("StateController")
	if State then
		if State.CharacterChanged then
			State.CharacterChanged:Connect(watchCharacter)
		end
		if State.RoleChanged then
			State.RoleChanged:Connect(evaluate)
		end
		if State.RoundChanged then
			State.RoundChanged:Connect(function(attr: string)
				if attr == "Phase" then
					evaluate()
				end
			end)
		end
	end
	watchCharacter(localCharacter())
	local Input = controller("InputController")
	if Input and Input.Action then
		Input.Action:Connect(function(action: string, state: string)
			if state ~= "Begin" or not active then
				return
			end
			if action == "Next" then
				SpectateController.Next()
			elseif action == "Prev" then
				SpectateController.Prev()
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(TUNING.PollInterval)
			local ok, err = pcall(evaluate)
			if not ok then
				warn("[SpectateController] " .. tostring(err))
			end
		end
	end)
end

return SpectateController

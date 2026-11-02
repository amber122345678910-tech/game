--!strict
-- PromptController (client, Priority 55): per-viewer rules for the server-made revive ProximityPrompts
-- (integration fix; CharacterService.createPrompt documents the contract but nothing consumed it).
--   * A "RevivePrompt" (under a downed human's HumanoidRootPart; attributes HumansOnly, VictimUserId, ActionKey,
--     ObjectKey) is shown only when the local character is alive, up, on team "Humans" (HumansOnly) and is not
--     the victim. Before this, the monster saw "Revive" over every downed human and the prompt's key (G = the
--     monster's ultimate) was captured by the prompt, so the ultimate could not be cast next to a downed human.
--     Hidden locally with MaxActivationDistance = 0: the server re-writes Enabled whenever TeamRevives changes,
--     but never the distance, so the local value sticks.
--   * Texts are re-localised for this client (Strings: ActionKey, ObjectKey + the victim's DisplayName) and again
--     on UIController.LanguageChanged.
-- Polls the few characters at 5 Hz (no workspace-wide DescendantAdded listener, no per-character connections).
--
-- API
--   PromptController.Refresh()            re-evaluate every revive prompt now
--   PromptController.Eligible(prompt, character?, userId?) -> boolean   pure-ish visibility rule (tests)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any

local PromptController = {}
PromptController.Priority = 55

local PROMPT_NAME = "RevivePrompt"
local POLL = 0.2

-- prompt -> the server's MaxActivationDistance (captured before we ever touch it; weak keys: destroyed prompts go)
local serverDistance: { [ProximityPrompt]: number } = setmetatable({}, { __mode = "k" }) :: any
local started = false

function PromptController.Eligible(prompt: Instance, character: Model?, userId: number?): boolean
	if character == nil or character.Parent == nil then
		return false
	end
	if character:GetAttribute("Dead") == true or character:GetAttribute("Downed") == true then
		return false
	end
	if prompt:GetAttribute("HumansOnly") == true and character:GetAttribute("Team") ~= "Humans" then
		return false
	end
	local victim = prompt:GetAttribute("VictimUserId")
	if type(victim) == "number" and victim ~= 0 and victim == userId then
		return false
	end
	return not prompt:IsDescendantOf(character)
end

local function localize(prompt: ProximityPrompt)
	local actionKey = prompt:GetAttribute("ActionKey")
	if type(actionKey) == "string" and Strings.Has(actionKey) then
		prompt.ActionText = Strings.L(actionKey)
	end
	local objectKey = prompt:GetAttribute("ObjectKey")
	if type(objectKey) == "string" and Strings.Has(objectKey) then
		local model = prompt:FindFirstAncestorOfClass("Model")
		local name = if model then model:GetAttribute("DisplayName") else nil
		prompt.ObjectText = Strings.L(objectKey, if type(name) == "string" then name elseif model then model.Name else "")
	end
end

local function characters(): { Model }
	local out: { Model } = {}
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c then
			table.insert(out, c)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function apply(prompt: ProximityPrompt, me: Model?, userId: number?)
	local distance = serverDistance[prompt]
	if distance == nil then
		distance = prompt.MaxActivationDistance
		serverDistance[prompt] = distance
		localize(prompt)
	end
	local want = if PromptController.Eligible(prompt, me, userId) then distance :: number else 0
	if prompt.MaxActivationDistance ~= want then
		prompt.MaxActivationDistance = want
	end
end

function PromptController.Refresh()
	local player = Players.LocalPlayer
	local me = if player then player.Character else nil
	local userId = if player then player.UserId else nil
	for _, model in characters() do
		local root = model:FindFirstChild("HumanoidRootPart")
		local prompt = if root then root:FindFirstChild(PROMPT_NAME) else nil
		if prompt and prompt:IsA("ProximityPrompt") then
			apply(prompt, me, userId)
		end
	end
end

function PromptController.Init() end

function PromptController.Start()
	if started then
		return
	end
	started = true
	local controllers = script.Parent
	local uiModule = controllers and controllers:FindFirstChild("UIController")
	if uiModule and uiModule:IsA("ModuleScript") then
		local ok, UI = pcall(require, uiModule)
		if ok and type(UI) == "table" and (UI :: any).LanguageChanged then
			(UI :: any).LanguageChanged:Connect(function()
				for prompt in serverDistance do
					if prompt.Parent ~= nil then
						localize(prompt)
					end
				end
			end)
		end
	end
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(PromptController.Refresh)
			if not ok then
				warn("[PromptController] " .. tostring(err))
			end
		end
	end)
end

return PromptController

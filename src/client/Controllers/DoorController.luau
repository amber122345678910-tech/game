--!strict
-- Двери бункера открываются только для владельца участка (локально у него на клиенте):
-- дверь отъезжает в сторону и перестаёт быть твёрдой. Во время шторма (кроме подготовки) дверь заперта.
-- Для сервера и других игроков дверь всегда закрыта — чужой бункер не открыть.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local DoorController = {}

local OPEN_DISTANCE = 7
local CLOSE_DISTANCE = 9.5
local SLIDE = 3.7

type DoorState = {
	open: boolean,
	closedCFrame: CFrame,
	handles: { [BasePart]: CFrame },
}

local doors: { [BasePart]: DoorState } = {}

local function canOpen(plot: Model): boolean
	local phase = plot:GetAttribute("Phase")
	return phase == nil or phase == "" or phase == "Prep"
end

local function setOpen(door: BasePart, state: DoorState, open: boolean)
	if state.open == open then
		return
	end
	state.open = open
	local offset = if open then CFrame.new(SLIDE, 0, 0) else CFrame.new()
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(door, info, { CFrame = state.closedCFrame * offset }):Play()
	for handle, relative in state.handles do
		TweenService:Create(handle, info, { CFrame = state.closedCFrame * offset * relative }):Play()
	end
	door.CanCollide = not open
	Sounds.playAt(if open then "DoorOpen" else "DoorClose", door.Position, 0.6)
end

local function track(door: BasePart): DoorState
	local state = doors[door]
	if state then
		return state
	end
	local handles: { [BasePart]: CFrame } = {}
	for _, child in door:GetChildren() do
		if child:IsA("BasePart") then
			handles[child] = door.CFrame:ToObjectSpace(child.CFrame)
		end
	end
	local newState: DoorState = { open = false, closedCFrame = door.CFrame, handles = handles }
	doors[door] = newState
	door.Destroying:Connect(function()
		doors[door] = nil
	end)
	return newState
end

local function step()
	local plot = ClientState.getPlotModel()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- забываем двери, которых больше нет
	for door in doors do
		if not door.Parent then
			doors[door] = nil
		end
	end
	if not plot or not root or not root:IsA("BasePart") then
		return
	end
	local blocks = plot:FindFirstChild("Blocks")
	if not blocks then
		return
	end
	local allowed = canOpen(plot)
	for _, child in blocks:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("IsDoor") then
			local state = track(child)
			local distance = (state.closedCFrame.Position - root.Position).Magnitude
			if not allowed then
				setOpen(child, state, false)
			elseif distance < OPEN_DISTANCE then
				setOpen(child, state, true)
			elseif distance > CLOSE_DISTANCE then
				setOpen(child, state, false)
			end
		end
	end
end

function DoorController.init()
	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(step)
			if not ok then
				warn("[DoorController] " .. tostring(err))
			end
		end
	end)
end

return DoorController

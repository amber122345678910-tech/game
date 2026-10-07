--!strict
-- Стрелка к бункеру: 3D-стрелка у ног игрока, маркер над бункером и указатель у края экрана.
-- Включается после обучения (и после каждого появления), выключается, когда игрок пришёл на участок.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local player = Players.LocalPlayer

local Waypoint = {}

local active = false
local arrowParts: { BasePart } = {}
local arrowCFrames: { CFrame } = {}
local markerPart: Part
local markerLabel: TextLabel
local edgeGui: ScreenGui
local edgeArrow: TextLabel
local fxFolder: Folder

local function getFxFolder(): Folder
	local f = workspace:FindFirstChild("ClientFX")
	if f and f:IsA("Folder") then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace
	return folder
end

local function fxPart(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Точка назначения: дверь моего бункера или центр участка.
local function targetPosition(): Vector3?
	local plot = ClientState.getPlotModel()
	if not plot then
		return nil
	end
	local blocks = plot:FindFirstChild("Blocks")
	if blocks then
		for _, child in blocks:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("IsDoor") then
				return child.Position
			end
		end
	end
	local origin = ClientState.getOrigin(plot)
	if origin then
		return origin.Position + Vector3.new(0, 3, 0)
	end
	return nil
end

local function setVisible(visible: boolean)
	for _, p in arrowParts do
		p.Transparency = if visible then 0.15 else 1
	end
	local billboard = markerPart:FindFirstChildOfClass("BillboardGui")
	if billboard then
		billboard.Enabled = visible
	end
	if not visible then
		edgeArrow.Visible = false
	end
end

function Waypoint.activate()
	if player:GetAttribute("InPlotZone") == true then
		ClientState.notify("Ты уже на своём участке! Зайди в бункер и нажми «Начать шторм».", "info")
		return
	end
	active = true
	setVisible(true)
end

function Waypoint.deactivate()
	active = false
	setVisible(false)
end

local cachedTarget: Vector3? = nil
local targetAge = math.huge

local function update(dt: number)
	if not active then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- дверь ищем не каждый кадр, а раз в полсекунды
	targetAge += dt
	if targetAge >= 0.5 or cachedTarget == nil then
		targetAge = 0
		cachedTarget = targetPosition()
	end
	local target = cachedTarget
	local camera = workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not target or not camera then
		setVisible(false)
		return
	end
	setVisible(true)
	local rootPos = root.Position
	local flat = Vector3.new(target.X - rootPos.X, 0, target.Z - rootPos.Z)
	local distance = flat.Magnitude
	if distance < 0.5 then
		return
	end
	local dir = flat.Unit
	local bob = math.sin(os.clock() * 5) * 0.25
	-- высота земли под персонажем: корень минус (HipHeight + половина корня)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local groundOffset = 3
	if hum then
		-- у R6 HipHeight = 0, а ноги длиной 2 стада
		groundOffset = if hum.RigType == Enum.HumanoidRigType.R6
			then root.Size.Y / 2 + 2
			else hum.HipHeight + root.Size.Y / 2
	end
	local base = rootPos + dir * 5 + Vector3.new(0, -groundOffset + 0.6 + bob, 0)
	local cf = CFrame.lookAt(base, base + dir)
	-- стрелка: древко + два "пера" наконечника
	arrowCFrames[1] = cf * CFrame.new(0, 0, 0.7)
	arrowCFrames[2] = cf * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, 0.75)
	arrowCFrames[3] = cf * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, 0.75)
	workspace:BulkMoveTo(arrowParts, arrowCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	markerPart.CFrame = CFrame.new(target + Vector3.new(0, 10, 0))
	markerLabel.Text = string.format("⬇ ТВОЙ БУНКЕР\n%d м", math.floor((target - rootPos).Magnitude / 3))

	-- указатель у края экрана, если маркер не виден
	local screen, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 10, 0))
	local vp = camera.ViewportSize
	if onScreen and screen.Z > 0 then
		edgeArrow.Visible = false
	else
		edgeArrow.Visible = true
		local center = vp / 2
		local v = Vector2.new(screen.X, screen.Y) - center
		if screen.Z < 0 then
			v = -v
		end
		if v.Magnitude < 1 then
			v = Vector2.new(0, 1)
		end
		local angle = math.atan2(v.Y, v.X)
		local rx, ry = vp.X / 2 - 70, vp.Y / 2 - 70
		local pos = center + Vector2.new(math.cos(angle) * rx, math.sin(angle) * ry)
		edgeArrow.Position = UDim2.fromOffset(pos.X, pos.Y)
		edgeArrow.Rotation = math.deg(angle)
	end
end

function Waypoint.init()
	fxFolder = getFxFolder()
	local color = Theme.Yellow
	table.insert(arrowParts, fxPart(Vector3.new(0.5, 0.25, 2.6), color))
	table.insert(arrowParts, fxPart(Vector3.new(0.5, 0.25, 1.7), color))
	table.insert(arrowParts, fxPart(Vector3.new(0.5, 0.25, 1.7), color))
	for i, p in arrowParts do
		p.Name = "WaypointArrow" .. i
		p.Transparency = 1
		p.Parent = fxFolder
		arrowCFrames[i] = CFrame.new()
	end

	markerPart = fxPart(Vector3.new(1, 1, 1), color)
	markerPart.Name = "WaypointMarker"
	markerPart.Transparency = 1
	markerPart.Parent = fxFolder
	local billboard = UIKit.new("BillboardGui", {
		Size = UDim2.fromOffset(230, 84),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 2000,
		Enabled = false,
		Adornee = markerPart,
		Parent = markerPart,
	}) :: BillboardGui
	markerLabel = UIKit.label({
		Text = "⬇ ТВОЙ БУНКЕР",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Theme.Yellow,
		MaxTextSize = 30,
		Parent = billboard,
	})

	edgeGui = UIKit.new("ScreenGui", {
		Name = "BunkerWaypoint",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ClipToDeviceSafeArea = false,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		DisplayOrder = 2,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	edgeArrow = UIKit.label({
		Text = "➤",
		Size = UDim2.fromOffset(72, 72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = Theme.Yellow,
		MaxTextSize = 64,
		Visible = false,
		Parent = edgeGui,
	})

	RunService.PreRender:Connect(update)

	player:GetAttributeChangedSignal("InPlotZone"):Connect(function()
		if active and player:GetAttribute("InPlotZone") == true then
			Waypoint.deactivate()
			ClientState.notify("Ты у своего бункера! Зайди внутрь и нажми «Начать шторм».", "success")
		end
	end)
	ClientState.WaypointRequested:Connect(Waypoint.activate)
	ClientState.TutorialChanged:Connect(function(running)
		if not running then
			task.delay(0.5, Waypoint.activate)
		end
	end)

	local function onSpawn()
		task.delay(1.5, function()
			local data = ClientState.Data
			if data and data.TutorialDone and not ClientState.TutorialActive then
				Waypoint.activate()
			end
		end)
	end
	player.CharacterAdded:Connect(onSpawn)
	-- первый вход: ждём данные (или они уже пришли)
	if ClientState.Data then
		if ClientState.Data.TutorialDone then
			onSpawn()
		end
	else
		ClientState.DataChanged:Once(function(data)
			if data.TutorialDone then
				onSpawn()
			end
		end)
	end
end

return Waypoint

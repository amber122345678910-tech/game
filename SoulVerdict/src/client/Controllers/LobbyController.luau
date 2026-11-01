--!strict
-- LobbyController (client, Priority 60): brings the lobby map (Shared/Maps/Lobby, workspace.Lobby) to life.
--   * builds a posed statue of every kit on its podium (marker "Podium_<kitId>"): RigBuilder.Build + ApplyPose,
--     anchored, client-local, no Humanoid/joints; falls back to the Dummy rig (or a SOUL heart for humans)
--     while a kit's blueprint is not available yet. Each podium gets a local "Try on" prompt (Request TryKit).
--   * fills the leaderboard SurfaceGuis (Board_Wins / Board_Level) from StateController.Leaderboards() and
--     refreshes them on LeaderboardsChanged (+ a slow poll).
--   * wires the lobby ProximityPrompts by their "Action" attribute: Shop / Quests -> UIController.Open(name),
--     Practice -> UIController.Open("Practice") or Request("StartPractice", {side = "Human"}).
--   * localises map text: TextLabels with attribute TextKey (Strings.L) or KitId+KitField (kit data), prompts
--     with ActionTextKey/ObjectTextKey — for the lobby AND every arena map (re-run on language changes).
--   * ambient touches: the floating SAVE star spins and bobs, the practice portal swirls, sky lanterns drift
--     (30 Hz, only while the camera is near the lobby; slower with Reduced Motion).
--
-- API
--   LobbyController.Lobby() -> Model?                  the lobby map model (nil until it exists)
--   LobbyController.Marker(name) -> BasePart?          a lobby marker by name (e.g. "MenuCamera", "PracticePortal")
--   LobbyController.MenuCamera() -> CFrame?            title-screen camera framing (marker "MenuCamera")
--   LobbyController.Statue(kitId) -> Model?            the statue built for a kit
--   LobbyController.Refresh()                          rebuild statues + boards + texts
--   LobbyController.Ready: Signal(model)               fired once the lobby has been set up

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any

local LobbyController = {}
LobbyController.Priority = 60
LobbyController.Ready = Signal.new()

local LOBBY_NAME = "Lobby"
local NEAR_DISTANCE = 420 -- camera distance from the lobby centre below which ambient animation runs
local BOARD_POLL = 20
local MONSTER_POSES = { "Pockets", "Shrug", "Ready" }
local HUMAN_POSES = { "Ready", "Wave", "Action", "Pockets", "Shrug", "Ready", "Wave" }

-- lazily resolved dependencies (controllers must not be required at module top level)
local State: any = nil
local UI: any = nil
local Graphics: any = nil
local Kits: any = nil
local RigBuilder: any = nil
local SoulProp: any = nil

local lobby: Model? = nil
local statues: { [string]: Model } = {}
local statueFolder: Folder? = nil
local connections: { RBXScriptConnection } = {} -- per-lobby (cleared when the lobby goes away)
local signalConnections: { any } = {}
local globalConnections: { RBXScriptConnection } = {} -- workspace watcher (lives for the session)
local ambient: { [string]: any } = {}
local boardsDirty = true
local setupToken = 0

local function controller(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
	end
	return nil
end

local function sharedModule(...: string): any
	local node: Instance? = Shared
	for _, name in { ... } do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node and node:IsA("ModuleScript") then
		local ok, result = pcall(require, node)
		if ok then
			return result
		end
		warn("[LobbyController] failed to load " .. node:GetFullName() .. ": " .. tostring(result))
	end
	return nil
end

local function L(key: string, ...: any): string
	local ok, text = pcall(Strings.L, key, ...)
	return if ok and type(text) == "string" then text else key
end

local function kitById(id: string): any
	if Kits and type(Kits.Get) == "function" then
		local ok, kit = pcall(Kits.Get, id)
		if ok then
			return kit
		end
	end
	return nil
end

-- Localisation -------------------------------------------------------------------------------------------------

local function localize(root: Instance)
	for _, inst in root:GetDescendants() do
		if inst:IsA("TextLabel") then
			local key = inst:GetAttribute("TextKey")
			if type(key) == "string" and key ~= "" then
				inst.Text = L(key)
			else
				local kitId = inst:GetAttribute("KitId")
				local field = inst:GetAttribute("KitField")
				if type(kitId) == "string" and type(field) == "string" then
					local kit = kitById(kitId)
					if kit and type(kit[field]) == "table" then
						inst.Text = Strings.Pick(kit[field])
					end
				end
			end
		elseif inst:IsA("ProximityPrompt") then
			local action = inst:GetAttribute("ActionTextKey")
			local object = inst:GetAttribute("ObjectTextKey")
			if type(action) == "string" then
				inst.ActionText = L(action)
			end
			if type(object) == "string" then
				inst.ObjectText = L(object)
			end
		end
	end
end

-- Markers ------------------------------------------------------------------------------------------------------

function LobbyController.Lobby(): Model?
	return if lobby and lobby.Parent then lobby else nil
end

function LobbyController.Marker(name: string): BasePart?
	local model = LobbyController.Lobby()
	local markers = model and model:FindFirstChild("Markers")
	local found = markers and markers:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

function LobbyController.MenuCamera(): CFrame?
	local marker = LobbyController.Marker("MenuCamera")
	return if marker then marker.CFrame else nil
end

function LobbyController.Statue(kitId: string): Model?
	return statues[kitId]
end

-- Statues ------------------------------------------------------------------------------------------------------

local function freeze(model: Model)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		elseif inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("Humanoid") then
			inst:Destroy()
		end
	end
end

local function rootHeight(model: Model): number
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position.Y
	end
	local _, size = model:GetBoundingBox()
	return size.Y / 2
end

local function buildRig(kit: any, index: number): Model?
	if RigBuilder == nil then
		return nil
	end
	local rigId = if type(kit.Rig) == "string" then kit.Rig else "Dummy"
	local ok, model = pcall(RigBuilder.Build, rigId, { Name = "Statue_" .. tostring(kit.Id) })
	if not ok or typeof(model) ~= "Instance" then
		if kit.Role == "Human" and SoulProp and type(SoulProp.Build) == "function" then
			local okSoul, soul = pcall(SoulProp.Build, kit.Color, 2.4)
			if okSoul and typeof(soul) == "Instance" and soul:IsA("Model") then
				soul.Name = "Statue_" .. tostring(kit.Id)
				soul:SetAttribute("Floating", true)
				return soul
			end
		end
		ok, model = pcall(RigBuilder.Build, "Dummy", { Name = "Statue_" .. tostring(kit.Id) })
		if not ok or typeof(model) ~= "Instance" then
			return nil
		end
	end
	local rig = model :: Model
	local family = rig:GetAttribute("RigFamily") or kit.Family or "Human"
	local poses = if kit.Role == "Monster" then MONSTER_POSES else HUMAN_POSES
	local poseName = poses[((index - 1) % #poses) + 1]
	local pose = nil
	if type(RigBuilder.GetPose) == "function" then
		pose = RigBuilder.GetPose(family, poseName) or RigBuilder.GetPose(family, "Ready")
	end
	if pose and type(RigBuilder.ApplyPose) == "function" then
		pcall(RigBuilder.ApplyPose, rig, pose)
	end
	return rig
end

local function addTryPrompt(marker: BasePart, kit: any)
	if marker:FindFirstChild("TryPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TryPrompt"
	prompt.ActionText = L("maps.lobby.podium.try")
	prompt.ObjectText = Strings.Pick(kit.Name)
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 40)
	prompt:SetAttribute("ActionTextKey", "maps.lobby.podium.try")
	prompt.Parent = marker
	table.insert(
		connections,
		prompt.Triggered:Connect(function()
			if State and type(State.Request) == "function" then
				pcall(State.Request, "TryKit", kit.Id)
			end
		end)
	)
end

local function buildStatues(model: Model, token: number)
	local markers = model:FindFirstChild("Markers")
	if markers == nil or RigBuilder == nil then
		return
	end
	local folder = statueFolder
	if folder == nil or folder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "ClientStatues"
		f.Parent = model
		statueFolder = f
		folder = f
	end
	local list: { { Kit: any, Marker: BasePart } } = {}
	for _, inst in markers:GetDescendants() do
		if inst:IsA("BasePart") and string.sub(inst.Name, 1, 7) == "Podium_" then
			local kit = kitById(string.sub(inst.Name, 8))
			if kit then
				table.insert(list, { Kit = kit, Marker = inst })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Marker.Name < b.Marker.Name
	end)
	for i, entry in list do
		if token ~= setupToken then
			return -- the lobby was rebuilt meanwhile
		end
		local kitId = tostring(entry.Kit.Id)
		local old = statues[kitId]
		if old then
			old:Destroy()
			statues[kitId] = nil
		end
		local rig = buildRig(entry.Kit, i)
		if rig then
			local lift = rootHeight(rig)
			freeze(rig)
			local target = entry.Marker.CFrame * CFrame.new(0, lift, 0)
			if rig:GetAttribute("Floating") then
				target = entry.Marker.CFrame * CFrame.new(0, 3.2, 0)
			end
			rig:PivotTo(target)
			rig:SetAttribute("KitId", kitId)
			rig:SetAttribute("Statue", true)
			rig.Parent = folder
			statues[kitId] = rig
			if rig:GetAttribute("Floating") then
				ambient.floating = ambient.floating or {}
				table.insert(ambient.floating, { Model = rig, Base = target, Phase = i })
			end
		end
		addTryPrompt(entry.Marker, entry.Kit)
		task.wait() -- one statue per frame: no hitch while the title screen is up
	end
end

-- Leaderboards -------------------------------------------------------------------------------------------------

local function rowValue(entry: any): (string?, number?)
	if type(entry) ~= "table" then
		return nil, nil
	end
	local name = entry.name or entry.Name or entry[1]
	local value = entry.value or entry.Value or entry[2]
	return if name ~= nil then tostring(name) else nil, tonumber(value)
end

local function fillBoard(boardName: string, data: { any }?, valueKey: string)
	local screen = LobbyController.Marker(boardName)
	local gui = screen and screen:FindFirstChild("Leaderboard")
	local rows = gui and gui:FindFirstChild("Rows")
	if rows == nil then
		return
	end
	for i = 1, 10 do
		local row = rows:FindFirstChild("Row" .. i)
		if row then
			local nameLabel = row:FindFirstChild("Name") :: TextLabel?
			local valueLabel = row:FindFirstChild("Value") :: TextLabel?
			local name, value = rowValue(if data then data[i] else nil)
			if nameLabel then
				if name then
					nameLabel.Text = name
				elseif data == nil and i == 1 then
					nameLabel.Text = L("maps.lobby.board.loading")
				else
					nameLabel.Text = L("maps.lobby.board.empty")
				end
			end
			if valueLabel then
				valueLabel.Text = if value then L(valueKey, math.floor(value)) else ""
			end
		end
	end
end

local function refreshBoards()
	boardsDirty = false
	local boards: any = nil
	if State and type(State.Leaderboards) == "function" then
		local ok, result = pcall(State.Leaderboards)
		if ok and type(result) == "table" then
			boards = result
		end
	end
	fillBoard("Board_Wins", if boards then boards.Wins else nil, "maps.lobby.board.value.wins")
	fillBoard("Board_Level", if boards then boards.Level else nil, "maps.lobby.board.value.level")
end

-- Prompts ------------------------------------------------------------------------------------------------------

local function openScreen(name: string, opts: { [string]: any }?): boolean
	if UI and type(UI.Open) == "function" then
		local ok, handle = pcall(UI.Open, name, opts)
		return ok and handle ~= nil
	end
	return false
end

local function onAction(action: string)
	if action == "Shop" or action == "Quests" or action == "Loadout" then
		openScreen(action)
	elseif action == "Practice" then
		if not openScreen("Practice") and State and type(State.Request) == "function" then
			pcall(State.Request, "StartPractice", { side = "Human" })
		end
	end
end

local function wirePrompts(model: Model)
	for _, inst in model:GetDescendants() do
		if inst:IsA("ProximityPrompt") and inst:GetAttribute("Wired") ~= true then
			local action = inst:GetAttribute("Action")
			if type(action) == "string" and action ~= "" then
				inst:SetAttribute("Wired", true)
				table.insert(
					connections,
					inst.Triggered:Connect(function()
						onAction(action)
					end)
				)
			end
		end
	end
end

-- Ambient ------------------------------------------------------------------------------------------------------

local function collectAmbient(model: Model)
	ambient = { floating = ambient.floating }
	local decor = model:FindFirstChild("Decor")
	if decor == nil then
		return
	end
	local star = decor:FindFirstChild("CenterStar", true)
	if star and star:IsA("Model") then
		ambient.star = star
		ambient.starBase = star:GetPivot()
	end
	local swirl = decor:FindFirstChild("PortalSwirl", true)
	if swirl and swirl:IsA("Model") then
		ambient.swirl = swirl
		ambient.swirlBase = swirl:GetPivot()
	end
	local lanterns = {}
	for _, inst in decor:GetDescendants() do
		if inst:IsA("BasePart") and string.sub(inst.Name, 1, 10) == "SkyLantern" and string.sub(inst.Name, 1, 13) ~= "SkyLanternCap" then
			local cap = inst.Parent and inst.Parent:FindFirstChild("SkyLanternCap" .. string.sub(inst.Name, 11))
			table.insert(lanterns, {
				Part = inst,
				Base = inst.CFrame,
				Cap = if cap and cap:IsA("BasePart") then cap else nil,
				CapBase = if cap and cap:IsA("BasePart") then cap.CFrame else nil,
				Phase = tonumber(inst:GetAttribute("Bob")) or 0,
			})
		end
	end
	ambient.lanterns = lanterns
	local center = LobbyController.Marker("Center")
	ambient.center = if center then center.Position else model:GetPivot().Position
end

local accumulator = 0
local function step(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	local frameDt = accumulator
	accumulator = 0
	local model = LobbyController.Lobby()
	if model == nil then
		return
	end
	local camera = workspace.CurrentCamera
	local center: Vector3? = ambient.center
	if camera == nil or center == nil or (camera.CFrame.Position - center).Magnitude > NEAR_DISTANCE then
		return
	end
	local _ = frameDt
	local reduced = false
	if Graphics and type(Graphics.ReducedMotion) == "function" then
		local ok, value = pcall(Graphics.ReducedMotion)
		reduced = ok and value == true
	end
	local speed = if reduced then 0.35 else 1
	local t = os.clock() * speed
	if ambient.star and ambient.starBase then
		local base: CFrame = ambient.starBase
		ambient.star:PivotTo(CFrame.new(base.Position + Vector3.new(0, math.sin(t * 1.3) * 0.45, 0)) * CFrame.Angles(0, t * 0.7, 0) * base.Rotation)
	end
	if ambient.swirl and ambient.swirlBase then
		ambient.swirl:PivotTo(ambient.swirlBase * CFrame.Angles(t * 0.9, 0, 0))
	end
	if ambient.lanterns then
		for _, lantern in ambient.lanterns do
			local offset = Vector3.new(0, math.sin(t * 0.6 + lantern.Phase) * 0.9, 0)
			lantern.Part.CFrame = lantern.Base + offset
			if lantern.Cap and lantern.CapBase then
				lantern.Cap.CFrame = lantern.CapBase + offset
			end
		end
	end
	if ambient.floating then
		for _, f in ambient.floating do
			if f.Model.Parent then
				f.Model:PivotTo(f.Base * CFrame.new(0, math.sin(t * 1.6 + f.Phase) * 0.3, 0) * CFrame.Angles(0, t * 1.2, 0))
			end
		end
	end
end

-- Setup ------------------------------------------------------------------------------------------------------

local function cleanup()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for _, c in signalConnections do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(signalConnections)
	for _, statue in statues do
		statue:Destroy()
	end
	table.clear(statues)
	ambient = {}
	statueFolder = nil
	lobby = nil
end

local function setup(model: Model)
	if lobby == model then
		return
	end
	cleanup()
	lobby = model
	setupToken += 1
	local token = setupToken
	localize(model)
	wirePrompts(model)
	collectAmbient(model)
	refreshBoards()
	table.insert(
		connections,
		model.DescendantAdded:Connect(function(inst)
			if inst:IsA("ProximityPrompt") then
				task.defer(wirePrompts, model)
			end
		end)
	)
	table.insert(
		connections,
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil and lobby == model then
				cleanup()
			end
		end)
	)
	if State and State.LeaderboardsChanged then
		table.insert(
			signalConnections,
			State.LeaderboardsChanged:Connect(function()
				boardsDirty = true
			end)
		)
	end
	task.spawn(buildStatues, model, token)
	LobbyController.Ready:Fire(model)
end

function LobbyController.Refresh()
	local model = LobbyController.Lobby()
	if model == nil then
		return
	end
	localize(model)
	refreshBoards()
	setupToken += 1
	task.spawn(buildStatues, model, setupToken)
end

local function watchMaps()
	local function consider(child: Instance)
		if not child:IsA("Model") then
			return
		end
		if child.Name == LOBBY_NAME then
			-- markers only exist on the real lobby map (a TestArena fallback just gets its texts localised)
			if child:FindFirstChild("Markers") then
				setup(child)
			else
				localize(child)
			end
		elseif child:GetAttribute("MapId") ~= nil then
			localize(child) -- round maps (signs, plates)
		end
	end
	for _, child in workspace:GetChildren() do
		task.spawn(consider, child)
	end
	table.insert(
		globalConnections,
		workspace.ChildAdded:Connect(function(child)
			-- MapService parents a fully built model; give replication a moment to deliver descendants
			task.delay(0.5, consider, child)
		end)
	)
end

function LobbyController.Init()
	State = controller("StateController")
	UI = controller("UIController")
	Graphics = controller("GraphicsController")
	Kits = sharedModule("Kits")
	RigBuilder = sharedModule("Rigs", "RigBuilder")
	SoulProp = sharedModule("Rigs", "Props", "Soul")
end

function LobbyController.Start()
	watchMaps()
	if UI and UI.LanguageChanged then
		UI.LanguageChanged:Connect(function()
			for _, child in workspace:GetChildren() do
				if child:IsA("Model") and (child.Name == LOBBY_NAME or child:GetAttribute("MapId") ~= nil) then
					localize(child)
				end
			end
			if LobbyController.Lobby() then
				refreshBoards()
			end
		end)
	end
	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		while true do
			task.wait(BOARD_POLL)
			if LobbyController.Lobby() then
				refreshBoards()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if boardsDirty and LobbyController.Lobby() then
				refreshBoards()
			end
		end
	end)
	local _ = Players
end

return LobbyController

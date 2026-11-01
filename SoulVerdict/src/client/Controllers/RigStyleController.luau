--!strict
-- RigStyleController (client, SPEC §5.4 / §20, Priority 50): applies Shared/Rigs/RigStyles to every character model
-- on this client (player characters in workspace, workspace.Bots: practice bots and lobby dummies).
--   * style = Style Lab override (SetOverride) > profile setting "RigStyle" > Config.Defaults.RigStyle > RigStyles.Default;
--     changing it re-styles every tracked model (RigStyles.Apply is reversible and idempotent);
--   * models are styled one frame after they appear and again (debounced) when late visual parts arrive or the
--     SkinId changes;
--   * the Toon outline Highlight is hidden while the model has Invisible = true (RigStyles.SetOutlineVisible) and
--     distance-culled to the nearest Tuning.MaxOutlines models within Tuning.OutlineRange (Highlight budget);
--   * HD meshes: VFX/HDMesh.ApplyToModel(model) (pcall, own thread) when HDMesh.Available().
--
-- API
--   RigStyleController.Style() -> string ; StyleChanged: Signal(styleId)
--   RigStyleController.SetOverride(styleId?)    Style Lab live switch (nil = back to the player's setting)
--   RigStyleController.ApplyTo(model)           style any model now (e.g. a ViewportFrame preview rig)
--   RigStyleController.Refresh()                re-resolve the style and re-apply everything

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigStyles = require(Shared:WaitForChild("Rigs"):WaitForChild("RigStyles"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local RigStyleController = {}
RigStyleController.Priority = 50
RigStyleController.StyleChanged = Signal.new()

local TUNING = {
	MaxOutlines = 24,
	OutlineRange = 180,
	CullInterval = 0.5,
	ReapplyDelay = 0.15,
}
RigStyleController.Tuning = TUNING

local override: string? = nil
local current: string = RigStyles.Default
local tracked: { [Model]: any } = {}
local culled: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local hdDone: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local hdModule: any = nil
local hdLoaded = false
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

local function hd(): any?
	if hdLoaded then
		return hdModule
	end
	hdLoaded = true
	local clientRoot = (script.Parent :: Instance).Parent
	local vfx = clientRoot and clientRoot:FindFirstChild("VFX")
	local module = vfx and vfx:FindFirstChild("HDMesh")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			hdModule = result
		else
			warn("[RigStyleController] VFX/HDMesh failed to load: " .. tostring(result))
		end
	end
	return hdModule
end

---------------------------------------------------------------------------------------------------- style

local function resolveStyle(): string
	if override and RigStyles.Get(override) then
		return override
	end
	local State = controller("StateController")
	if State and type(State.Setting) == "function" then
		local ok, value = pcall(State.Setting, "RigStyle")
		if ok and type(value) == "string" and RigStyles.Get(value) then
			return value
		end
	end
	local default = Config.Defaults.RigStyle
	if type(default) == "string" and RigStyles.Get(default) then
		return default
	end
	return RigStyles.Default
end

local function updateOutline(model: Model)
	local visible = model:GetAttribute("Invisible") ~= true and not culled[model]
	pcall(RigStyles.SetOutlineVisible, model, visible)
end

local function applyHD(model: Model)
	if hdDone[model] then
		return
	end
	local module = hd()
	if module == nil or type(module.ApplyToModel) ~= "function" then
		return
	end
	hdDone[model] = true
	task.spawn(function()
		local okAvailable, available = pcall(module.Available)
		if not okAvailable or not available or model.Parent == nil then
			return
		end
		local ok, err = pcall(module.ApplyToModel, model)
		if not ok then
			warn("[RigStyleController] HDMesh.ApplyToModel: " .. tostring(err))
		end
	end)
end

function RigStyleController.ApplyTo(model: Model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local ok, err = pcall(RigStyles.Apply, model, current)
	if not ok then
		warn("[RigStyleController] RigStyles.Apply: " .. tostring(err))
	end
	updateOutline(model)
	applyHD(model)
end

function RigStyleController.Style(): string
	return current
end

function RigStyleController.Refresh()
	local style = resolveStyle()
	local changed = style ~= current
	current = style
	for model in tracked do
		if model.Parent ~= nil then
			RigStyleController.ApplyTo(model)
		end
	end
	if changed then
		RigStyleController.StyleChanged:Fire(style)
	end
end

function RigStyleController.SetOverride(styleId: string?)
	override = if type(styleId) == "string" and styleId ~= "" then styleId else nil
	RigStyleController.Refresh()
end

------------------------------------------------------------------------------------------------- tracking

local function isCharacter(inst: Instance): boolean
	if not inst:IsA("Model") then
		return false
	end
	return inst:FindFirstChildOfClass("Humanoid") ~= nil
		or inst:GetAttribute("RigFamily") ~= nil
		or inst:GetAttribute("BlueprintId") ~= nil
end

local function untrack(model: Model)
	local trove = tracked[model]
	if trove then
		tracked[model] = nil
		trove:Destroy()
	end
	culled[model] = nil
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local trove = Trove.new()
	tracked[model] = trove
	local scheduled = false
	local function schedule(delay: number)
		if scheduled then
			return
		end
		scheduled = true
		task.delay(delay, function()
			scheduled = false
			if tracked[model] and model.Parent ~= nil then
				RigStyleController.ApplyTo(model)
			end
		end)
	end
	trove:Connect(model.AttributeChanged, function(attr: string)
		if attr == "Invisible" then
			updateOutline(model)
		elseif attr == "SkinId" or attr == "KitId" then
			schedule(TUNING.ReapplyDelay)
		end
	end)
	trove:Connect(model.DescendantAdded, function(inst: Instance)
		if inst:IsA("BasePart") and inst:GetAttribute("Role") ~= nil then
			schedule(TUNING.ReapplyDelay)
		end
	end)
	trove:Connect(model.AncestryChanged, function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end)
	-- one frame later: the whole rig has replicated
	task.defer(function()
		if tracked[model] and model.Parent ~= nil then
			RigStyleController.ApplyTo(model)
		end
	end)
end

local function consider(inst: Instance)
	if isCharacter(inst) then
		track(inst :: Model)
	end
end

local function watchFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		consider(child)
	end
	folder.ChildAdded:Connect(function(child: Instance)
		task.defer(consider, child)
	end)
end

local function cullOutlines()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local entries: { { model: Model, distance: number } } = {}
	for model in tracked do
		local root = model.PrimaryPart
		if root then
			table.insert(entries, { model = model, distance = (root.Position - eye).Magnitude })
		end
	end
	table.sort(entries, function(a, b)
		return a.distance < b.distance
	end)
	for index, entry in entries do
		local hide = index > TUNING.MaxOutlines or entry.distance > TUNING.OutlineRange
		if (culled[entry.model] == true) ~= hide then
			culled[entry.model] = if hide then true else nil
			updateOutline(entry.model)
		end
	end
end

------------------------------------------------------------------------------------------------ lifecycle

function RigStyleController.Init()
	current = resolveStyle()
end

function RigStyleController.Start()
	if started then
		return
	end
	started = true
	current = resolveStyle()
	local State = controller("StateController")
	if State then
		if State.SettingChanged then
			State.SettingChanged:Connect(function(key: string)
				if key == "RigStyle" then
					RigStyleController.Refresh()
				end
			end)
		end
		if State.ProfileChanged then
			State.ProfileChanged:Connect(function()
				if resolveStyle() ~= current then
					RigStyleController.Refresh()
				end
			end)
		end
	end
	for _, child in workspace:GetChildren() do
		consider(child)
		if child.Name == "Bots" then
			watchFolder(child)
		end
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Bots" then
			watchFolder(child)
		else
			task.defer(consider, child)
		end
	end)
	-- player characters can also be re-parented into workspace after CharacterAdded
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(model: Model)
			task.defer(function()
				if model:IsDescendantOf(workspace) then
					track(model)
				end
			end)
		end)
		if player.Character and player.Character:IsDescendantOf(workspace) then
			track(player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	task.spawn(function()
		while true do
			task.wait(TUNING.CullInterval)
			pcall(cullOutlines)
		end
	end)
end

return RigStyleController

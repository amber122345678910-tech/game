--!strict
-- Fixture for tools/checks/selftest.py: every line ending in `-- expect: <rule>` must produce exactly
-- that finding from apicheck.py; every other line must produce none. Not shipped (outside src/).
local Lighting = game:GetService("Lighting")
local _rs = game:GetService("RunServic") -- expect: service
local p = Instance.new("Part")
p.Anchored = true
p.Anchord = true -- expect: member
p.Size = 5 -- expect: value-type
p.Material = Enum.Material.Neon
p.Material = Enum.Font.Arial -- expect: value-type
p.Material = "Neon"
p.Material = "Neonn" -- expect: value-type
p.Transparency = "half" -- expect: value-type
p.CanCollide = 1 -- expect: value-type
p.Color = Color3.new(255, 0, 0) -- expect: mistake
p:Destroyy() -- expect: member
p:Touched(function() end) -- expect: member
p.Velocity = Vector3.zero -- expect: deprecated
local _a = Instance.new("BasePart") -- expect: instance-new
local _b = Instance.new("Workspace") -- expect: instance-new
local _c = Instance.new("Partt") -- expect: instance-new
local _e = Enum.KeyCod.A -- expect: enum
local _e2 = Enum.KeyCode.Foo -- expect: enum
local _ok = Enum.KeyCode.A
Lighting.Technology = Enum.Technology.Future -- expect: readonly
Lighting.LightingStyle = Enum.LightingStyle.Realistic -- expect: readonly
Lighting.Brightness = 2
local m = Instance.new("Model")
m.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled -- expect: readonly
local cam = workspace.CurrentCamera
cam.FieldOfView = 70
cam.FieldOfVieww = 70 -- expect: member
local f = Instance.new("Folder")
f:GetPropertyChangedSignal("Nme"):Connect(function() end) -- expect: member
if p:IsA("BasPart") then -- expect: class-name
	p.Anchored = false
end
local _cf = CFrame.Angles(0, 90, 0) -- expect: mistake
local _v = Vector3.new(1, 2, 3, 4) -- expect: mistake
local q = Instance.new("Part")
if p.Anchored then
	q = Instance.new("WedgePart")
end
q.Shape = Enum.PartType.Ball
for _, p in {} :: { any } do
	p.Whatever = 1
end
local function _typed(gui: GuiObject, inst: Instance, lbl: TextLabel?)
	gui.Trasparency = 1 -- expect: member
	gui.BackgroundTransparency = 1
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 0.5
	else
		gui.Visible = false
	end
	inst.Name = "x"
	if lbl then
		lbl.Txt = "x" -- expect: member
	end
	local folder = inst :: Folder
	folder.Nmae = "z" -- expect: member
	local alpha = if gui.Visible then 1 else 0
	gui.BackgroundTransparency = alpha
end
local label = Instance.new("TextLabel")
label.TextColor = BrickColor.new("Bright red") -- expect: deprecated
label.Colour = Color3.new() -- expect: member, mistake
local _vis = label.Visibility -- expect: mistake
local Plates = { Visibility = function(_x: any): string return "Plate" end }
local _shown = Plates.Visibility(label)
label.Text = "a" .. tostring(1)
local bf = Instance.new("BindableFunction")
bf.OnInvoke = function() end
p.Parent = workspace

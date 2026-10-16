--!nocheck
-- Сборка места: берёт place от Rojo (скрипты), добавляет модели персонажей, окружение, свет, небо.
-- lune run tools/assemble.luau build/base.rbxl ../RyuVsYuta.rbxl
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")

local src = process.args[1] or "build/base.rbxl"
local dst = process.args[2] or "../RyuVsYuta.rbxl"

local Instance = roblox.Instance

local game = roblox.deserializePlace(fs.readFile(src))
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Sequence = Loader.load("src/shared/Sequence/Sequence")
local Look = Loader.load("src/shared/Sequence/Look")

local stage = Instance.new("Folder")
stage.Name = "Cutscene"
stage.Parent = Workspace

local chars = Instance.new("Folder")
chars.Name = "Characters"
chars.Parent = stage
for _, name in { "Rika", "Yuta", "Ryu" } do
	local B = Loader.load("src/shared/Builders/" .. name)
	local model = B.build(Sequence.buildOrigin(name))
	model.Name = name
	model.Parent = chars
end

local Environment = Loader.load("src/shared/Builders/Environment")
local env = Environment.build()
env.Name = "Environment"
env.Parent = stage

-- Свет и атмосфера (база; по ходу сцены их меняет клиент)
for k, v in Look.lighting do
	Lighting[k] = v
end
for _, child in Lighting:GetChildren() do
	child.Parent = nil
end
local function add(className, props)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = Lighting
	return inst
end
add("Atmosphere", Look.atmosphere)
add("Sky", Look.sky)
add("ColorCorrectionEffect", Look.colorCorrection)
add("BloomEffect", Look.bloom)
add("DepthOfFieldEffect", Look.depthOfField)
add("SunRaysEffect", Look.sunRays)
add("BlurEffect", Look.blur)

-- камера редактора: вид на сцену при открытии файла
local cam = Workspace:FindFirstChildOfClass("Camera")
if not cam then
	cam = Instance.new("Camera")
	cam.Name = "Camera"
	cam.Parent = Workspace
end
cam.CFrame = Look.editorCamera
cam.FieldOfView = 60
Workspace.CurrentCamera = cam

fs.writeFile(dst, roblox.serializePlace(game))
local n = 0
for _, d in game:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
print(string.format("Assembled %s (%d parts)", dst, n))

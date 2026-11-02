--!nocheck
-- Builds MortysRoom.rbxlx from the sources in ../src.
-- Run from the MortysRoom folder:   lune run build/build
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")
local U = require("./Util")
local Room = require("./Room")
local House = require("./House")
local Characters = require("./Characters")
local Garage = require("./Garage")
local Planet = require("./Planet")
local Titan = require("./Titan")
local Worlds = require("./Worlds")
local Character = require("./Character")

local Instance, Enum, rgb, CFrame = U.Instance, U.Enum, U.rgb, U.CFrame

local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
local SRC = ROOT .. "src/"

local function read(path)
	return fs.readFile(SRC .. path)
end

local function script(class, name, source, parent)
	local s = Instance.new(class)
	s.Name = name
	s.Source = source
	s.Parent = parent
	return s
end

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")
local players = game:GetService("Players")
local starterPlayer = game:GetService("StarterPlayer")
local replicated = game:GetService("ReplicatedStorage")
local serverScripts = game:GetService("ServerScriptService")
local soundService = game:GetService("SoundService")
game:GetService("StarterGui")
game:GetService("ServerStorage")
game:GetService("Teams")
game:GetService("Chat")

-- World ------------------------------------------------------------------------
workspace.Gravity = 196.2
pcall(function()
	workspace.StreamingEnabled = false
end)
local house = Room.build(workspace)
House.build(house)
local cast = Characters.buildAll(workspace, house:FindFirstChild("Seats"))
Garage.build(workspace)
local planet = Planet.build(workspace)
Titan.build(planet, workspace)
Worlds.build(workspace, planet, Planet.VILLAGE + U.v(-70, 0, 40))
-- Evil Morty and Rick Prime wait far below until their scenes
Characters.build(cast, Characters.Specs.EvilMorty, CFrame.new(-6000, -600, -6000))
Characters.build(cast, Characters.Specs.RickPrime, CFrame.new(-6020, -600, -6000))

-- Lighting (Future = real shadows from every lamp) -------------------------------
lighting.Technology = Enum.Technology.Future
lighting.ClockTime = 0.4
lighting.GeographicLatitude = 41.7
lighting.Brightness = 1.6
lighting.Ambient = rgb(24, 27, 40)
lighting.OutdoorAmbient = rgb(60, 70, 100)
lighting.EnvironmentDiffuseScale = 0.35
lighting.EnvironmentSpecularScale = 0.5
lighting.GlobalShadows = true
lighting.ShadowSoftness = 0.25
lighting.ExposureCompensation = 0.15

local sky = Instance.new("Sky")
sky.Name = "Sky"
sky.StarCount = 3000
sky.Parent = lighting
local atmosphere = Instance.new("Atmosphere")
atmosphere.Name = "Atmosphere"
atmosphere.Density = 0.3
atmosphere.Offset = 0.1
atmosphere.Color = rgb(100, 120, 170)
atmosphere.Decay = rgb(40, 50, 80)
atmosphere.Glare = 0
atmosphere.Haze = 1
atmosphere.Parent = lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "Grade"
grade.Saturation = -0.05
grade.Contrast = 0.08
grade.TintColor = rgb(225, 232, 255)
grade.Parent = lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "Bloom"
bloom.Intensity = 0.6
bloom.Size = 24
bloom.Threshold = 1.3
bloom.Parent = lighting
local rays = Instance.new("SunRaysEffect")
rays.Name = "SunRays"
rays.Intensity = 0.02
rays.Spread = 0.6
rays.Enabled = false
rays.Parent = lighting
local dof = Instance.new("DepthOfFieldEffect")
dof.Name = "Focus"
dof.Enabled = false
dof.FarIntensity = 0.35
dof.NearIntensity = 0.5
dof.FocusDistance = 8
dof.InFocusRadius = 4
dof.Parent = lighting
local blur = Instance.new("BlurEffect")
blur.Name = "Blur"
blur.Size = 0
blur.Enabled = false
blur.Parent = lighting

-- Sound groups -----------------------------------------------------------------
for _, name in { "Music", "SFX", "Ambience" } do
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 0.5
	g.Parent = soundService
end
soundService.RespectFilteringEnabled = true

-- Players / camera -------------------------------------------------------------
players.CharacterAutoLoads = false
starterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
starterPlayer.CharacterWalkSpeed = 9
pcall(function()
	starterPlayer.CharacterUseJumpPower = false
	starterPlayer.CharacterJumpHeight = 3.5
end)
starterPlayer.AutoJumpEnabled = false
starterPlayer.CameraMaxZoomDistance = 0.5
starterPlayer.CameraMinZoomDistance = 0.5
starterPlayer.EnableMouseLockOption = false

local sps = Instance.new("StarterPlayerScripts")
sps.Parent = starterPlayer
local scs = Instance.new("StarterCharacterScripts")
scs.Parent = starterPlayer

Character.build(starterPlayer, read("StarterCharacter/Animate.client.luau"))

-- Scripts ----------------------------------------------------------------------
local gameFolder = Instance.new("Folder")
gameFolder.Name = "Game"
gameFolder.Parent = replicated
for _, name in { "Config", "UI", "Widgets", "Settings", "Audio", "Graphics", "MenuController", "Lang", "Dialogue", "Director", "Fx", "Puppet", "Scenes", "Story", "StoryCurve" } do
	script("ModuleScript", name, read("ReplicatedStorage/" .. name .. ".luau"), gameFolder)
end
-- crowds the client clones: Cameramen, Speakermen, TV Men, Skibidi toilets
local templates = Instance.new("Folder")
templates.Name = "Templates"
templates.Parent = gameFolder
Characters.buildTemplates(templates)
local stylesFolder = Instance.new("Folder")
stylesFolder.Name = "MenuStyles"
stylesFolder.Parent = gameFolder
for _, name in { "Cinematic", "Cartoon", "Monitor", "VHS", "Notebook" } do
	script("ModuleScript", name, read("ReplicatedStorage/MenuStyles/" .. name .. ".luau"), stylesFolder)
end
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = gameFolder
local spawnFn = Instance.new("RemoteFunction")
spawnFn.Name = "RequestSpawn"
spawnFn.Parent = remotes
local release = Instance.new("RemoteEvent")
release.Name = "ReleaseCharacter"
release.Parent = remotes
local toMenu = Instance.new("RemoteEvent")
toMenu.Name = "ReturnToMenu"
toMenu.Parent = remotes

script("Script", "GameServer", read("ServerScriptService/GameServer.server.luau"), serverScripts)
script("Script", "WorldGen", read("ServerScriptService/WorldGen.server.luau"), serverScripts)
script("LocalScript", "Client", read("StarterPlayerScripts/Client.client.luau"), sps)

-- Write ------------------------------------------------------------------------
local out = ROOT .. "MortysRoom.rbxlx"
fs.writeFile(out, roblox.serializePlace(game, true))
print(("Built %s  (%d parts)"):format(out, U.partCount))

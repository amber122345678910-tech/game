--!strict
-- STRETCH-POP · Точка входа клиента.
-- Ждём полной начальной репликации, затем: эффекты → камера → рогатка → клиент уровня → HUD → звук.
-- HUD и аудио получают те же инстансы slingshot и camera и подписываются на slingshot.Signals.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Client = script.Parent
local KineticVFX = require(Client.Effects.KineticVFX)
local ShoulderCameraController = require(Client.Controllers.ShoulderCameraController)
local ElasticSlingshotController = require(Client.Controllers.ElasticSlingshotController)
local KineticLevelClient = require(Client.Controllers.KineticLevelClient)
local StretchHUDController = require(Client.Controllers.StretchHUDController)
local StretchAudioController = require(Client.Controllers.StretchAudioController)

KineticVFX.Init()

local camera = ShoulderCameraController.new()
camera:Start()

local slingshot = ElasticSlingshotController.new(camera)
slingshot:Start()

KineticLevelClient.Start()

local hud = StretchHUDController.new(slingshot, camera)
hud:Start()

local audio = StretchAudioController.new(slingshot, camera, hud)
audio:Start()

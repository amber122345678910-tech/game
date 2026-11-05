--!strict
-- STRETCH-POP · Точка входа клиента.
-- Ждём полной начальной репликации, затем: эффекты → камера → рогатка → клиент уровня.
-- HUD и процедурный аудио-движок (следующий шаг) подключатся к сигналам slingshot.Signals.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Client = script.Parent
local KineticVFX = require(Client.Effects.KineticVFX)
local ShoulderCameraController = require(Client.Controllers.ShoulderCameraController)
local ElasticSlingshotController = require(Client.Controllers.ElasticSlingshotController)
local KineticLevelClient = require(Client.Controllers.KineticLevelClient)

KineticVFX.Init()

local camera = ShoulderCameraController.new()
camera:Start()

local slingshot = ElasticSlingshotController.new(camera)
slingshot:Start()

KineticLevelClient.Start()

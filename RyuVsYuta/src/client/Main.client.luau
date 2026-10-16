--!strict
-- Точка входа катсцены «Рю Ишигори vs Юта Оккоцу — Этап 1».
-- Игрок не превращается в персонажа: персонажа у игрока нет вовсе (CharacterAutoLoads = false),
-- камера управляется катсценой. Кнопка «Запустить анимацию» — на стартовом экране.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local Sequence = require(Shared:WaitForChild("Sequence"):WaitForChild("Sequence"))

local Director = require(script.Parent:WaitForChild("Director"))
local UI = require(script.Parent:WaitForChild("UI"))
local Audio = require(script.Parent:WaitForChild("Audio"))

-- спрятать стандартный интерфейс Roblox (чат, список игроков) — мешает смотреть
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local _player = Players.LocalPlayer

Director.init()

local function start()
	UI.hideStart()
	UI.hideEnd()
	UI.setSpeed(Director.state().speed)
	Director.play(0)
end

UI.init({
	onStart = start,
	onTogglePause = function()
		Director.togglePause()
	end,
	onRestart = start,
	onSpeed = function(s: number)
		Director.setSpeed(s)
		UI.setSpeed(s)
	end,
	onSeek = function(t: number)
		UI.hideEnd()
		Director.seek(t)
	end,
}, Sequence.shotMarks(), Sequence.duration())
UI.seekKeys(function()
	return Director.state().t
end)
UI.setSpeed(1)

Director.onFrame(function(frame, t)
	local st = Director.state()
	UI.applyFrame(frame, t, st.paused)
end)
Director.onEnded(function()
	UI.showEnd()
end)

Director.startIdle()

task.spawn(function()
	Audio.init(function(done: number, total: number)
		UI.setLoading(done, total)
	end)
end)

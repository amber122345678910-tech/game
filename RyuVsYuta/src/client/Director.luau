--!strict
-- Режиссёр: часы катсцены (пуск, пауза, скорость, перемотка) и применение кадра к сцене каждый кадр рендера.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local Types = require(Shared:WaitForChild("Sequence"):WaitForChild("Types"))
local Sequence = require(Shared:WaitForChild("Sequence"):WaitForChild("Sequence"))
local Skeletons = require(Shared:WaitForChild("Skeletons"))

local CharacterDriver = require(script.Parent:WaitForChild("CharacterDriver"))
local Env = require(script.Parent:WaitForChild("FX"):WaitForChild("Env"))
local Effects = require(script.Parent:WaitForChild("FX"):WaitForChild("Effects"))
local Audio = require(script.Parent:WaitForChild("Audio"))

local Director = {}

local RENDER_NAME = "RyuYutaCutscene"

type State = {
	playing: boolean,
	paused: boolean,
	t: number,
	speed: number,
	ended: boolean,
}

local state: State = {
	playing = false,
	paused = false,
	t = 0,
	speed = 1,
	ended = false,
}

-- Роли сцены и модели, которые могут их играть: модель персонажа или обычный манекен Roblox
local ROLES: { [string]: { models: string, dummies: string } } = {
	Rika = { models = "Rika", dummies = "Rika" },
	Yuta = { models = "Yuta", dummies = "YutaDummy" },
	Ryu = { models = "Ryu", dummies = "RyuDummy" },
}
local allDrivers: { [string]: CharacterDriver.Driver } = {} -- по имени модели
local drivers: { [string]: CharacterDriver.Driver } = {} -- активные, по роли
local style = "models"
local HIDDEN_STATE: Types.CharState = {
	visible = false,
	origin = CFrame.new(),
	pose = {},
	outline = 0,
	flutter = 0,
}
local events: { Types.Event } = Sequence.events()
local nextEvent = 1
local lastFrame: Types.Frame? = nil
local audioNeedsResync = false -- перемотали на паузе: разовые звуки подхватим при снятии паузы

-- Внешние подписчики (интерфейс)
local onFrame: { (Types.Frame, number) -> () } = {}
local onEnded: { () -> () } = {}

function Director.duration(): number
	return Sequence.duration()
end

function Director.state(): State
	return state
end

function Director.onFrame(fn: (Types.Frame, number) -> ())
	table.insert(onFrame, fn)
end

function Director.onEnded(fn: () -> ())
	table.insert(onEnded, fn)
end

function Director.init()
	local stage = Workspace:WaitForChild("Cutscene")
	local chars = stage:WaitForChild("Characters")
	local hidden = Instance.new("Folder")
	hidden.Name = "HiddenCharacters"
	hidden.Parent = ReplicatedStorage
	for _, name in { "Rika", "Yuta", "Ryu", "YutaDummy", "RyuDummy" } do
		local model = chars:WaitForChild(name, 30) :: Model?
		if model then
			local rigName = model:GetAttribute("Rig")
			local def = (Skeletons :: any)[if type(rigName) == "string" then rigName else name]
			allDrivers[name] = CharacterDriver.new(model, def, hidden)
		else
			warn("[Cutscene] model not found: " .. name)
		end
	end
	Env.init()
	Effects.init()
	Director.setStyle(style)
end

-- "models" — модели Рю и Юты; "dummies" — обычные манекены Roblox на их месте (Рика всегда модель)
function Director.setStyle(newStyle: string)
	style = newStyle
	for role, opts in ROLES do
		local want = if newStyle == "dummies" then opts.dummies else opts.models
		for _, modelName in { opts.models, opts.dummies } do
			local d = allDrivers[modelName]
			if d and modelName ~= want then
				d:update(HIDDEN_STATE, 0)
			end
		end
		drivers[role] = allDrivers[want]
	end
	Effects.setActiveRyu(if newStyle == "dummies" then ROLES.Ryu.dummies else ROLES.Ryu.models)
	local f = lastFrame
	if f then
		for role, d in drivers do
			local cs = f.chars[role]
			if cs then
				d:update(cs, f.t)
			end
		end
	end
end

function Director.style(): string
	return style
end

local function fireEvents(fromT: number, toT: number)
	while nextEvent <= #events and events[nextEvent].t <= toT do
		local e = events[nextEvent]
		if e.t > fromT - 1e-6 then
			if e.kind == "sound" then
				Audio.play(e.name, e.args, 0, state.speed)
			elseif e.kind == "fx" then
				Effects.trigger(e.name, e.args)
			end
		end
		nextEvent += 1
	end
end

local function resetEventCursor(t: number)
	nextEvent = 1
	while nextEvent <= #events and events[nextEvent].t < t do
		nextEvent += 1
	end
end

local IDLE_NAME = "RyuYutaCutsceneIdle"

-- Применяет готовый кадр к сцене
local function applyFrame(frame: Types.Frame, t: number)
	lastFrame = frame
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = frame.camera.cf
		cam.FieldOfView = frame.camera.fov
		cam.Focus = frame.camera.cf * CFrame.new(0, 0, -frame.camera.focusDist)
	end
	for name, d in drivers do
		local cs = frame.chars[name]
		if cs then
			d:update(cs, t)
		end
	end
	Env.apply(frame)
	Effects.update(frame, t)
	Audio.update(frame, t, state.speed, state.playing and not state.paused)
	-- в меню (state.playing = false) подложки не играют: звук начинается с кнопки
	for _, fn in onFrame do
		fn(frame, t)
	end
end

function Director.applyAt(t: number)
	applyFrame(Sequence.evaluate(t), t)
end

-- Фон под стартовым меню: живая сцена (туман, дыхание Рики, медленный облёт камеры)
function Director.startIdle()
	local t0 = os.clock()
	RunService:BindToRenderStep(IDLE_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local clock = os.clock() - t0
		applyFrame(Sequence.menuFrame(clock), clock)
	end)
end

function Director.stopIdle()
	RunService:UnbindFromRenderStep(IDLE_NAME)
end

local function step(dt: number)
	if not state.playing or state.paused then
		return
	end
	local prev = state.t
	local dur = Sequence.duration()
	state.t = math.min(dur, state.t + dt * state.speed)
	fireEvents(prev, state.t)
	Director.applyAt(state.t)
	if state.t >= dur and not state.ended then
		state.ended = true
		state.playing = false
		Audio.stopAll(1.5)
		for _, fn in onEnded do
			fn()
		end
	end
end

function Director.play(fromT: number?)
	Director.stopIdle()
	local t = fromT or 0
	state.t = t
	state.playing = true
	state.paused = false
	state.ended = false
	audioNeedsResync = false
	Audio.stopAll(0)
	Effects.reset(t)
	resetEventCursor(t)
	Audio.seek(t, events, state.speed)
	Director.applyAt(t)
	RunService:UnbindFromRenderStep(RENDER_NAME)
	-- после камеры по умолчанию, чтобы наш CFrame камеры был последним словом
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

function Director.setPaused(p: boolean)
	if not state.playing then
		return
	end
	state.paused = p
	Audio.setPaused(p)
	Effects.setPaused(p)
	if not p and audioNeedsResync then
		audioNeedsResync = false
		Audio.seek(state.t, events, state.speed)
	end
end

function Director.togglePause()
	Director.setPaused(not state.paused)
end

function Director.setSpeed(s: number)
	state.speed = s
	Audio.setSpeed(s)
	Effects.setSpeed(s)
end

function Director.seek(t: number)
	local dur = Sequence.duration()
	t = math.clamp(t, 0, dur)
	if not state.playing then
		Director.play(t)
		Director.setPaused(true)
		return
	end
	state.t = t
	state.ended = false
	Audio.stopAll(0)
	Effects.reset(t)
	resetEventCursor(t)
	if not state.paused then
		Audio.seek(t, events, state.speed)
	else
		audioNeedsResync = true
	end
	Director.applyAt(t)
end

function Director.stop()
	state.playing = false
	state.paused = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
	Audio.stopAll(0.5)
end

function Director.lastFrame(): Types.Frame?
	return lastFrame
end

return Director

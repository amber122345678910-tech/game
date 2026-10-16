--!strict
-- Звук катсцены: предзагрузка, группы с эффектами (реверберация, компрессор), фоновые "подложки"
-- с огибающей громкости (зависят только от времени — перемотка работает сама), разовые звуки
-- по событиям таймлайна (при перемотке подхватываются с нужного места), пауза и скорость.

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Cutscene")
local SoundBank = require(Shared:WaitForChild("Audio"):WaitForChild("SoundBank"))
local Sequence = require(Shared:WaitForChild("Sequence"):WaitForChild("Sequence"))
local Types = require(Shared:WaitForChild("Sequence"):WaitForChild("Types"))
local Track = require(Shared:WaitForChild("Track"))

local Audio = {}

type Playing = { sound: Sound, baseSpeed: number, started: number }

local folder: Folder
local groups: { [string]: SoundGroup } = {}
local templates: { [string]: { Sound } } = {} -- варианты звука (для чередования)
local roundRobin: { [string]: number } = {}
local oneShots: { Playing } = {}
local bedSounds: { [number]: Sound } = {}
local paused = false
local globalSpeed = 1

local function makeGroups()
	local master = Instance.new("SoundGroup")
	master.Name = "CutsceneMaster"
	master.Volume = SoundBank.masterVolume
	master.Parent = SoundService
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold = -14
	comp.Ratio = 3
	comp.Attack = 0.01
	comp.Release = 0.25
	comp.GainMakeup = 2
	comp.Parent = master
	groups.Master = master
	for name, g in SoundBank.groups do
		local sg = Instance.new("SoundGroup")
		sg.Name = name
		sg.Volume = g.volume
		sg.Parent = master
		if g.reverb then
			local rv = Instance.new("ReverbSoundEffect")
			rv.DecayTime = g.reverb.decay
			rv.Density = 1
			rv.Diffusion = 1
			rv.DryLevel = g.reverb.dry
			rv.WetLevel = g.reverb.wet
			rv.Priority = 1
			rv.Parent = sg
		end
		if g.lowShelf then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = g.lowShelf
			eq.MidGain = 0
			eq.HighGain = g.highShelf or 0
			eq.Priority = 2
			eq.Parent = sg
		end
		groups[name] = sg
	end
end

local function makeSound(cueName: string, cue: SoundBank.Cue, id: string, index: number): Sound
	local s = Instance.new("Sound")
	s.Name = cueName .. "_" .. index
	s.SoundId = id
	s.Volume = cue.volume
	s.PlaybackSpeed = cue.speed
	s.Looped = cue.loop == true
	s.SoundGroup = groups[cue.group] or groups.Master
	s.Parent = folder
	return s
end

-- Создаёт шаблоны и предзагружает. progress(done, total) вызывается по мере загрузки.
function Audio.init(progress: (number, number) -> ())
	folder = Instance.new("Folder")
	folder.Name = "CutsceneSounds"
	folder.Parent = SoundService
	makeGroups()
	local all: { Sound } = {}
	for name, cue in SoundBank.cues do
		local list = {}
		for i, id in cue.ids do
			local s = makeSound(name, cue, id, i)
			table.insert(list, s)
			table.insert(all, s)
		end
		templates[name] = list
		roundRobin[name] = 0
	end
	local total = #all
	local done = 0
	progress(0, total)
	local failed: { [string]: boolean } = {}
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(all, function(contentId: string, status: Enum.AssetFetchStatus)
			done += 1
			if status ~= Enum.AssetFetchStatus.Success then
				failed[contentId] = true
			end
			progress(math.min(done, total), total)
		end)
	end)
	if not ok then
		warn("[Cutscene] sound preload error: " .. tostring(err))
	end
	-- недоступный звук: пробуем запасные ID из банка, затем встроенный звук клиента (rbxasset://)
	for name, list in templates do
		local cue = SoundBank.cues[name]
		for _, s in list do
			if failed[s.SoundId] then
				local replaced = false
				for _, alt in cue.backups or {} do
					local okAlt = false
					pcall(function()
						ContentProvider:PreloadAsync({ alt }, function(_id: string, st: Enum.AssetFetchStatus)
							okAlt = st == Enum.AssetFetchStatus.Success
						end)
					end)
					if okAlt then
						warn("[Cutscene] sound " .. name .. ": " .. s.SoundId .. " failed, using backup " .. alt)
						s.SoundId = alt
						replaced = true
						break
					end
				end
				if not replaced then
					warn("[Cutscene] sound " .. name .. " unavailable, using built-in fallback")
					s.SoundId = cue.fallback or SoundBank.defaultFallback
				end
			end
		end
	end
	progress(total, total)
end

local function pick(name: string): Sound?
	local list = templates[name]
	if not list or #list == 0 then
		return nil
	end
	local i = roundRobin[name] % #list + 1
	roundRobin[name] = i
	return list[i]
end

-- Разовый звук. offsetIntoSound — сколько секунд звука уже "прошло" (для перемотки).
function Audio.play(name: string, args: { [string]: any }?, offsetIntoSound: number, speed: number)
	local cue = SoundBank.cues[name]
	local tpl = pick(name)
	if not cue or not tpl then
		warn("[Cutscene] unknown sound cue: " .. name)
		return
	end
	local a: { [string]: any } = args or {}
	local s = tpl:Clone()
	local vol = cue.volume * (if type(a.volume) == "number" then a.volume else 1)
	local base = cue.speed * (if type(a.speed) == "number" then a.speed else 1)
	s.Volume = vol
	s.PlaybackSpeed = base * speed
	s.Looped = false
	s.TimePosition = (cue.offset or 0) + offsetIntoSound * base
	s.Parent = folder
	s:Play()
	if paused then
		s:Pause()
	end
	table.insert(oneShots, { sound = s, baseSpeed = base, started = os.clock() })
	-- cut: через столько секунд (по времени сцены) звук плавно гаснет
	if type(a.cut) == "number" then
		local remain = (a.cut - offsetIntoSound) / math.max(0.05, speed)
		if remain <= 0 then
			s:Destroy()
			return
		end
		task.delay(remain, function()
			local v0 = s.Volume
			local t0 = os.clock()
			while s.Parent and os.clock() - t0 < 0.4 do
				if not s.IsPaused then
					s.Volume = v0 * (1 - (os.clock() - t0) / 0.4)
				end
				task.wait()
			end
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	local life = (if s.TimeLength > 0 then s.TimeLength else (cue.duration or 8)) / math.max(0.05, base * speed) + 1
	task.delay(life, function()
		if s.Parent and not s.IsPaused then
			s:Destroy()
		end
	end)
end

-- После перемотки: подхватить разовые звуки, которые должны ещё звучать в момент t
function Audio.seek(t: number, events: { Types.Event }, speed: number)
	for _, e in events do
		if e.kind == "sound" and e.t < t then
			local cue = SoundBank.cues[e.name]
			if cue then
				local a: { [string]: any } = e.args or {}
				local base = cue.speed * (if type(a.speed) == "number" then a.speed else 1)
				local len = (cue.duration or 3) / base
				local into = t - e.t
				if into < len - 0.05 then
					Audio.play(e.name, e.args, into, speed)
				end
			end
		end
	end
end

-- Каждый кадр: подложки (ветер, гул, треск энергии, музыка) по огибающим из Sequence
function Audio.update(frame: Types.Frame, t: number, speed: number, running: boolean)
	for i, bed in Sequence.beds() do
		local v = Track.number(bed.keys, t)
		local s = bedSounds[i]
		if v > 0.001 and running then
			if not s then
				local tpl = pick(bed.cue)
				if tpl then
					local ns = tpl:Clone()
					ns.Looped = true
					ns.Parent = folder
					local cue = SoundBank.cues[bed.cue]
					local len = if ns.TimeLength > 0 then ns.TimeLength else (cue.duration or 10)
					-- стартуем с позиции, соответствующей времени (чтобы перемотка не начинала петлю заново)
					local startPos = (cue.offset or 0) + ((t - bed.keys[1].t) * cue.speed) % math.max(1, len - (cue.offset or 0))
					ns.TimePosition = startPos
					ns:Play()
					bedSounds[i] = ns
					s = ns
				end
			end
			if s then
				local cue = SoundBank.cues[bed.cue]
				s.Volume = cue.volume * v
				local sp = if bed.speedKeys then Track.number(bed.speedKeys, t) else 1
				s.PlaybackSpeed = cue.speed * sp * speed
				if s.IsPaused and not paused then
					s:Resume()
				end
			end
		elseif s then
			s:Destroy()
			bedSounds[i] = nil
		end
	end
	local _ = frame
end

function Audio.stopAll(fade: number)
	for _, p in oneShots do
		local s = p.sound
		if s.Parent then
			if fade > 0 then
				local v0 = s.Volume
				task.spawn(function()
					local t0 = os.clock()
					while s.Parent and os.clock() - t0 < fade do
						s.Volume = v0 * (1 - (os.clock() - t0) / fade)
						task.wait()
					end
					s:Destroy()
				end)
			else
				s:Destroy()
			end
		end
	end
	table.clear(oneShots)
	for i, s in bedSounds do
		if fade > 0 then
			local v0 = s.Volume
			task.spawn(function()
				local t0 = os.clock()
				while s.Parent and os.clock() - t0 < fade do
					s.Volume = v0 * (1 - (os.clock() - t0) / fade)
					task.wait()
				end
				s:Destroy()
			end)
		else
			s:Destroy()
		end
		bedSounds[i] = nil
	end
end

function Audio.setPaused(p: boolean)
	paused = p
	for _, o in oneShots do
		if o.sound.Parent then
			if p then
				o.sound:Pause()
			else
				o.sound:Resume()
			end
		end
	end
	for _, s in bedSounds do
		if p then
			s:Pause()
		else
			s:Resume()
		end
	end
end

function Audio.setSpeed(s: number)
	globalSpeed = s
	for _, o in oneShots do
		if o.sound.Parent then
			o.sound.PlaybackSpeed = o.baseSpeed * s
		end
	end
end

function Audio.speed(): number
	return globalSpeed
end

return Audio

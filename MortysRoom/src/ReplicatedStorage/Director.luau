-- Cutscene camera: cuts, smooth moves, tracking, free look (player can look around), shake.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Settings = require(script.Parent.Settings)

local Director = {}

local active = false
local base: CFrame = CFrame.new()
local trackFn: ((number) -> CFrame)? = nil
local moveFrom: CFrame? = nil
local moveTo: CFrame? = nil
local moveStart = 0
local moveDur = 1
local moveEase = "smooth"
local fovFrom, fovTo, fovStart, fovDur = 70, 70, 0, 0

local freeOn = false
local yaw, pitch = 0, 0
local limits = { yaw = 1.2, pitchUp = 0.9, pitchDown = 0.9 }
local touchDelta = Vector2.zero

local shakes: { { amp: number, t0: number, dur: number, freq: number, seed: number } } = {}
local roll = 0

local function ease(x: number, kind: string?): number
	x = math.clamp(x, 0, 1)
	if kind == "linear" then
		return x
	elseif kind == "in" then
		return x * x * x
	elseif kind == "out" then
		return 1 - (1 - x) ^ 3
	end
	return x * x * (3 - 2 * x)
end
Director.ease = ease

local function camera(): Camera
	return workspace.CurrentCamera
end

local function step(dt: number)
	if not active then
		return
	end
	local now = os.clock()
	local cf = base
	if moveFrom and moveTo then
		local a = ease((now - moveStart) / moveDur, moveEase)
		cf = (moveFrom :: CFrame):Lerp(moveTo :: CFrame, a)
		if a >= 1 then
			base = moveTo :: CFrame
			moveFrom, moveTo = nil, nil
		end
	elseif trackFn then
		cf = (trackFn :: (number) -> CFrame)(dt)
		base = cf
	end

	if freeOn then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local d = UserInputService:GetMouseDelta() + touchDelta
		touchDelta = Vector2.zero
		local k = 0.0045 * (Settings.Get("Sensitivity") or 1)
		yaw = math.clamp(yaw - d.X * k, -limits.yaw, limits.yaw)
		pitch = math.clamp(pitch - d.Y * k, -limits.pitchDown, limits.pitchUp)
	else
		yaw *= math.exp(-dt * 3)
		pitch *= math.exp(-dt * 3)
	end
	cf = cf * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

	-- shake (sum of active shakes, smooth noise)
	local sx, sy, sr = 0, 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local t = now - s.t0
		if t > s.dur then
			table.remove(shakes, i)
		else
			local fade = 1 - t / s.dur
			local a = s.amp * fade * fade
			sx += math.noise(t * s.freq, s.seed, 0) * a
			sy += math.noise(s.seed, t * s.freq, 0) * a
			sr += math.noise(0, s.seed, t * s.freq) * a
		end
	end
	cf = cf * CFrame.new(sx * 0.6, sy * 0.6, 0) * CFrame.Angles(sy * 0.05, sx * 0.05, sr * 0.08 + roll)

	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	if fovDur > 0 then
		local a = ease((now - fovStart) / fovDur)
		cam.FieldOfView = fovFrom + (fovTo - fovFrom) * a
		if a >= 1 then
			fovDur = 0
		end
	end
end

UserInputService.InputChanged:Connect(function(input, processed)
	if active and freeOn and input.UserInputType == Enum.UserInputType.Touch and not processed then
		touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
	end
end)

function Director.start(fromCurrent: boolean?)
	if not active then
		active = true
		if fromCurrent ~= false then
			base = camera().CFrame
		end
		RunService:BindToRenderStep("Director", Enum.RenderPriority.Camera.Value + 10, step)
	end
end

function Director.stop()
	if active then
		active = false
		RunService:UnbindFromRenderStep("Director")
	end
	freeOn = false
	trackFn = nil
	moveFrom, moveTo = nil, nil
	table.clear(shakes)
	roll = 0
	yaw, pitch = 0, 0
end

function Director.isActive(): boolean
	return active
end

function Director.cut(cf: CFrame, fov: number?)
	Director.start(false)
	trackFn = nil
	moveFrom, moveTo = nil, nil
	base = cf
	yaw, pitch = 0, 0
	if fov then
		camera().FieldOfView = fov
		fovDur = 0
	end
	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
end

-- smooth move from the current base to `cf` (yields unless async)
function Director.move(cf: CFrame, duration: number, easeKind: string?, fov: number?, async: boolean?)
	Director.start()
	trackFn = nil
	moveFrom = base
	moveTo = cf
	moveStart = os.clock()
	moveDur = math.max(duration, 0.001)
	moveEase = easeKind or "smooth"
	if fov then
		Director.fov(fov, duration)
	end
	if not async then
		task.wait(duration)
	end
end

-- follow a function every frame: fn(dt) -> CFrame
function Director.track(fn: (number) -> CFrame)
	Director.start()
	moveFrom, moveTo = nil, nil
	trackFn = fn
end

function Director.fov(value: number, duration: number?)
	local cam = camera()
	if not duration or duration <= 0 then
		cam.FieldOfView = value
		fovDur = 0
		return
	end
	fovFrom = cam.FieldOfView
	fovTo = value
	fovStart = os.clock()
	fovDur = duration
end

function Director.freeLook(on: boolean, newLimits: { yaw: number?, pitchUp: number?, pitchDown: number? }?)
	freeOn = on
	if newLimits then
		limits.yaw = newLimits.yaw or limits.yaw
		limits.pitchUp = newLimits.pitchUp or limits.pitchUp
		limits.pitchDown = newLimits.pitchDown or limits.pitchDown
	end
	if on then
		UserInputService.MouseIconEnabled = false
	end
end

function Director.resetLook()
	yaw, pitch = 0, 0
end

function Director.lookAngles(): (number, number)
	return yaw, pitch
end

function Director.shake(amplitude: number, duration: number, frequency: number?)
	table.insert(shakes, { amp = amplitude, t0 = os.clock(), dur = duration, freq = frequency or 12, seed = math.random() * 100 })
end

function Director.roll(angle: number)
	roll = angle
end

function Director.base(): CFrame
	return base
end

return Director

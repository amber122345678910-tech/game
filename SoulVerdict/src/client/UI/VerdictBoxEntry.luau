--!strict
-- VerdictBoxEntry: the Verdict Box VICTIM's entry transition (SPEC §11). The world is sucked in toward the victim's
-- SOUL (camera push + narrowing FOV + a slight roll, a dark iris closing from the screen edges onto the chest, pale
-- streaks rushing inward, the red SOUL heart appearing at the chest), a short full black, then a SHARP white flash
-- that reveals the battle box. Lune-safe at require time (pure timing + GUI building); VerdictBoxController applies
-- the camera pose at runtime (render step after CameraController) and draws this layer over the box overlay.
--
-- Timeline (absolute times on the synced server clock, see Stages):
--   start ...... BoxStart arrived: the pull-in starts, and with it the box music (InputController "Box" context)
--   pullEnd .... the iris is shut: full black (the camera is put back here, unseen; the SOUL heart stays visible)
--   flashAt .... white at full opacity for FlashHold (~2 frames), the battle box is already open underneath
--   flashEnd ... the white has faded (FlashFade): only the box is left
-- flashAt lands on the box timeline's t0 (= server open + Config.VerdictBox.IntroTime) whenever the packet came in
-- time: the pull-in takes what is left (at most Pull, at least MinPull) and the black fills the rest. A late packet
-- runs the shortest full transition, and a very late one is compressed so the flash has always faded Gap s before
-- the first attack (box time introEnd) - the SOUL is never hit by anything the player could not see.
-- Reduced Motion: no camera zoom / roll, no iris motion, no streaks: the screen just darkens, then the flash.
--
-- API
--   VerdictBoxEntry.Tuning
--   VerdictBoxEntry.Stages(start, t0, introEnd?, reduced?) -> Stages { start, pull, pullEnd, flashAt, flashEnd,
--                                                                       reduced }
--   VerdictBoxEntry.At(stages, now, out?) -> Frame { stage = "Pull"|"Black"|"Flash"|"Done", pull, iris, dark, heart,
--                                                    flash, open, camera, roll, swirl, streaks }   (all 0..1 except
--                                                    roll / swirl in degrees; open = the box shows under the flash)
--   VerdictBoxEntry.CameraPose(base: CFrame, fov, chest: Vector3, k, rollDeg?) -> (CFrame, fov)   k = 0: unchanged
--   VerdictBoxEntry.CameraFx() -> Fx    fx:Apply(camera, chest, k, rollDeg) post-processes a camera that its own
--                                       controller rewrites every frame (never accumulates when nothing rewrites it);
--                                       fx:Restore(camera) puts back the last un-pulled frame if it is still ours
--   VerdictBoxEntry.Runner(stages, layer?, hooks) -> Runner   one victim's transition, stepped once per frame right
--       after the camera controller: runner:Step(now) -> Frame (camera pull, post effects, layer centred on the chest
--       as seen through the pulled camera; stops itself when Done) ; runner:Stop() (camera back, effects off, layer
--       destroyed; idempotent) ; runner.done
--       hooks { camera: () -> Camera?, chest: () -> Vector3?, project: (camera, Vector3) -> Vector2? (screen px,
--               nil = behind the camera), size: () -> Vector2 (screen px), postFx: ((amount 0..1) -> ())? }
--   VerdictBoxEntry.new(parent?, opts?) -> Entry      opts { ZIndex: number? (default 60) }
--   entry:Render(frame, center: Vector2, size: Vector2)   center = the chest on screen (px), size = the screen (px)
--   entry:Destroy() ; entry.Root: Frame
--   VerdictBoxEntry.Create(theme, deps) -> { Root, Destroy }   dump_gui preview: deps { Time, Reduced, Canvas }

local VerdictBoxView = require(script.Parent:WaitForChild("VerdictBoxView")) :: any

local VerdictBoxEntry = {}
VerdictBoxEntry.__index = VerdictBoxEntry

local Tuning = {
	Pull = 0.65, -- s: preferred pull-in (camera push + iris)
	MinPull = 0.3, -- s: a late BoxStart shortens the pull-in down to this
	Black = 0.1, -- s: full black (with the SOUL heart) before the flash
	FlashHold = 0.035, -- s: white at full opacity (~2 frames at 60 fps)
	FlashFade = 0.25, -- s: white -> the battle box
	Gap = 0.2, -- s: the flash has faded at least this long before the first attack can reach the SOUL
	HeartFrom = 0.45, -- pull progress where the SOUL heart starts to show at the chest
	DarkMax = 0.5, -- uniform darkening of the world at the end of the pull-in (1 in the black)
	StreakAlpha = 0.5, -- peak opacity of the inward streaks
	Swirl = 32, -- degrees the streaks turn during the pull-in
	-- camera (runtime only; none with Reduced Motion)
	FovScale = 0.5, -- FOV at the end of the pull-in (x the camera's own)
	Push = 0.45, -- the camera travels this fraction of the way to the chest...
	MinDistance = 2.4, -- ...but stays at least this many studs away from it
	Roll = 10, -- degrees of camera roll ("swirl") at the end of the pull-in
	Blur = 16, -- BlurEffect.Size at the end of the pull-in
	Desaturate = 0.55, -- ColorCorrectionEffect saturation drop at the end of the pull-in
}
VerdictBoxEntry.Tuning = Tuning

export type Stages = {
	start: number,
	pull: number,
	pullEnd: number,
	flashAt: number,
	flashEnd: number,
	reduced: boolean,
}

export type Frame = {
	stage: string,
	pull: number,
	iris: number,
	dark: number,
	heart: number,
	flash: number,
	open: number,
	camera: number,
	roll: number,
	swirl: number,
	streaks: number,
}

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

---------------------------------------------------------------------------------------------------
-- timing (pure)

-- start: when the client got BoxStart; t0: the box timeline's start (server open + IntroTime); introEnd: box time of
-- the first attack (Sim timeline.introEnd).
function VerdictBoxEntry.Stages(start: number, t0: number, introEnd: number?, reduced: boolean?): Stages
	local T = Tuning
	local full = T.MinPull + T.Black
	local latest = t0 + math.max(introEnd or 1, 0) - T.Gap - T.FlashHold - T.FlashFade
	local flashAt = if t0 - start >= full then t0 else start + full
	flashAt = math.max(math.min(flashAt, latest), start)
	local total = flashAt - start
	local pull = if total >= full then math.min(total - T.Black, T.Pull) else total * T.MinPull / full
	return {
		start = start,
		pull = pull,
		pullEnd = start + pull,
		flashAt = flashAt,
		flashEnd = flashAt + T.FlashHold + T.FlashFade,
		reduced = reduced == true,
	}
end

function VerdictBoxEntry.At(st: Stages, now: number, out: Frame?): Frame
	local T = Tuning
	local f: Frame = out
		or {
			stage = "Pull",
			pull = 0,
			iris = 0,
			dark = 0,
			heart = 0,
			flash = 0,
			open = 0,
			camera = 0,
			roll = 0,
			swirl = 0,
			streaks = 0,
		}
	local p = if st.pull > 1e-4 then clamp01((now - st.start) / st.pull) elseif now >= st.start then 1 else 0
	local reduced = st.reduced
	f.pull = p
	f.roll, f.swirl, f.streaks, f.camera, f.flash, f.open = 0, 0, 0, 0, 0, 0
	if now < st.pullEnd then
		-- slow start, accelerating: it reads as being sucked in
		f.stage = "Pull"
		local e2 = p * p
		f.heart = clamp01((p - T.HeartFrom) / (1 - T.HeartFrom))
		if reduced then
			f.iris = 0
			f.dark = e2 * (3 - 2 * p) -- smoothstep: a plain fade to black
		else
			f.iris = p ^ 1.5
			f.dark = T.DarkMax * e2
			f.camera = p ^ 2.2
			f.roll = T.Roll * f.camera
			f.swirl = T.Swirl * e2
			f.streaks = clamp01(p / 0.25) * (1 - clamp01((p - 0.85) / 0.15))
		end
	elseif now < st.flashAt then
		f.stage = "Black"
		f.iris = if reduced then 0 else 1
		f.dark = 1
		f.heart = 1
	elseif now < st.flashEnd then
		-- sharp: full white for FlashHold, then a fast-then-slow fade revealing the box
		f.stage = "Flash"
		f.iris, f.dark, f.heart, f.open = 0, 0, 0, 1
		local u = clamp01((now - st.flashAt - T.FlashHold) / T.FlashFade)
		f.flash = (1 - u) ^ 1.6
	else
		f.stage = "Done"
		f.iris, f.dark, f.heart, f.open = 0, 0, 0, 1
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- camera (pure pose + a tiny post-processor)

-- The camera pulled toward the chest by k (0..1): turned toward it (keeping its own up / roll), pushed along the line
-- to it (never closer than MinDistance), FOV narrowed to FovScale, rolled by rollDeg. k <= 0 returns base unchanged.
function VerdictBoxEntry.CameraPose(base: CFrame, fov: number, chest: Vector3, k: number, rollDeg: number?): (CFrame, number)
	if not (k > 0) then
		return base, fov
	end
	local T = Tuning
	k = math.min(k, 1)
	local outFov = fov * (1 - (1 - T.FovScale) * k)
	local pos = base.Position
	local to = chest - pos
	local dist = to.Magnitude
	if dist < 1e-3 then
		return base, outFov
	end
	local want = to * (1 / dist)
	local look = base.LookVector
	local axis = look:Cross(want)
	local s = axis.Magnitude
	local turn = CFrame.new()
	if s > 1e-6 then
		turn = CFrame.fromAxisAngle(axis * (1 / s), math.atan2(s, math.clamp(look:Dot(want), -1, 1)) * k)
	end
	local push = math.min(dist * T.Push * k, math.max(dist - T.MinDistance, 0))
	local cf = CFrame.new(pos + want * push) * (turn * base.Rotation) * CFrame.Angles(0, 0, math.rad(rollDeg or 0))
	return cf, outFov
end

export type Fx = {
	baseCF: CFrame?,
	baseFov: number?,
	wroteCF: CFrame?,
	wroteFov: number?,
	Apply: (self: Fx, camera: any, chest: Vector3, k: number, rollDeg: number) -> (),
	Restore: (self: Fx, camera: any) -> (),
}

local FxMethods = {}

function FxMethods.Apply(self: Fx, camera: any, chest: Vector3, k: number, rollDeg: number)
	local cf, fov = camera.CFrame, camera.FieldOfView
	if self.wroteCF ~= nil and cf == self.wroteCF and fov == self.wroteFov then
		-- nothing rewrote the camera since our last frame: start from the saved frame (never accumulate)
		cf, fov = self.baseCF :: CFrame, self.baseFov :: number
	end
	self.baseCF, self.baseFov = cf, fov
	local outCF, outFov = VerdictBoxEntry.CameraPose(cf, fov, chest, k, rollDeg)
	camera.CFrame = outCF
	camera.FieldOfView = outFov
	self.wroteCF, self.wroteFov = camera.CFrame, camera.FieldOfView
end

function FxMethods.Restore(self: Fx, camera: any)
	if camera ~= nil and self.wroteCF ~= nil and camera.CFrame == self.wroteCF and camera.FieldOfView == self.wroteFov then
		camera.CFrame = self.baseCF
		camera.FieldOfView = self.baseFov
	end
	self.baseCF, self.baseFov, self.wroteCF, self.wroteFov = nil, nil, nil, nil
end

function VerdictBoxEntry.CameraFx(): Fx
	return {
		baseCF = nil,
		baseFov = nil,
		wroteCF = nil,
		wroteFov = nil,
		Apply = FxMethods.Apply,
		Restore = FxMethods.Restore,
	}
end

---------------------------------------------------------------------------------------------------
-- the screen layer

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SOUL_RED = Color3.fromRGB(255, 0, 0)
local STREAK = Color3.fromRGB(236, 228, 255)
local RING_ALPHA = { 0.82, 0.6, 0.34 } -- soft inner edge of the iris (3 steps), then the hard black
local STREAKS = 14

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function hash01(a: number, b: number): number
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

type Ring = { frame: Frame, stroke: UIStroke }
type Streak = { frame: Frame, angle: number, phase: number, size: number }

export type Entry = {
	Root: Frame,
	dim: Frame,
	rings: { Ring },
	streaks: { Streak },
	heart: Frame,
	heartPixels: { Frame },
	glows: { Frame },
	glowAlpha: { number },
	flash: Frame,
	heartAlpha: number,
	Render: (self: Entry, frame: Frame, center: Vector2, size: Vector2) -> (),
	Destroy: (self: Entry) -> (),
}

local function ring(parent: Instance, z: number, alpha: number): Ring
	local frame = new("Frame", {
		Name = "Iris",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = z,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	local stroke = new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = BLACK,
		Transparency = alpha,
		Thickness = 1,
	}, frame)
	return { frame = frame, stroke = stroke }
end

function VerdictBoxEntry.new(parent: Instance?, opts: { [string]: any }?): Entry
	local o = opts or {}
	local root = new("Frame", {
		Name = "VerdictBoxEntry",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = o.ZIndex or 60,
	}, nil)
	local dim = new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
	}, root)
	local rings: { Ring } = {}
	for _, alpha in RING_ALPHA do
		table.insert(rings, ring(root, 2, alpha))
	end
	table.insert(rings, ring(root, 2, 0)) -- the hard black beyond the soft edge
	local streaks: { Streak } = {}
	for i = 1, STREAKS do
		local frame = new("Frame", {
			Name = "Streak",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = STREAK,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		}, root)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
		table.insert(streaks, {
			frame = frame,
			angle = (i - 1) * 360 / STREAKS + (hash01(i, 3) - 0.5) * 16,
			phase = hash01(i, 7),
			size = 0.7 + hash01(i, 11) * 0.6,
		})
	end
	local glows: { Frame } = {}
	local glowAlpha = { 0.86, 0.72 } -- outer, inner (transparency at full heart)
	for i in glowAlpha do
		local g = new("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = SOUL_RED,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
		}, root)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, g)
		table.insert(glows, g)
	end
	local heart = new("Frame", {
		Name = "Soul",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, root)
	local heartPixels: { Frame } = {}
	for _, run in VerdictBoxView.SOUL_ROWS do
		local row, x0, x1, rows = run[1], run[2], run[3], run[4]
		table.insert(
			heartPixels,
			new("Frame", {
				Name = "Px",
				Position = UDim2.fromScale(x0 / 16, row / 16),
				Size = UDim2.new((x1 - x0 + 1) / 16, 0, rows / 16 + 0.004, 0),
				BackgroundColor3 = SOUL_RED,
				BorderSizePixel = 0,
				ZIndex = 5,
			}, heart)
		)
	end
	local flash = new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 6,
	}, root)
	local self = setmetatable({
		Root = root,
		dim = dim,
		rings = rings,
		streaks = streaks,
		heart = heart,
		heartPixels = heartPixels,
		glows = glows,
		glowAlpha = glowAlpha,
		flash = flash,
		heartAlpha = -1,
	}, VerdictBoxEntry) :: any
	if parent then
		root.Parent = parent
	end
	return self
end

function VerdictBoxEntry.Render(self: Entry, f: Frame, center: Vector2, size: Vector2)
	local W, H = math.max(size.X, 1), math.max(size.Y, 1)
	local cx, cy = center.X, center.Y
	local unit = math.min(W, H) -- 400 on a landscape phone
	local farX = math.max(cx, W - cx)
	local farY = math.max(cy, H - cy)
	local far = math.sqrt(farX * farX + farY * farY) -- the farthest screen corner from the centre

	-- uniform darkening (the whole world goes dark; full black from the end of the pull-in)
	self.dim.Visible = f.dark > 0.001
	self.dim.BackgroundTransparency = 1 - f.dark

	-- iris: a hole around the chest that shrinks to nothing; soft inner edge (3 rings) + hard black beyond
	local feather = math.clamp(unit * 0.24, 24, 180)
	local radius = (1 - f.iris) * (far + feather)
	local soft = math.min(feather, radius * 0.8 + 3)
	local showIris = f.iris > 0.001 and (f.stage == "Pull" or f.stage == "Black")
	local n = #self.rings
	for i, r in self.rings do
		local inner = if i < n then radius + (i - 1) * soft / 3 else radius + soft
		local frame = r.frame
		frame.Visible = showIris and inner < far
		if frame.Visible then
			frame.Position = UDim2.fromOffset(cx, cy)
			frame.Size = UDim2.fromOffset(inner * 2, inner * 2)
			r.stroke.Thickness = if i < n then soft / 3 + 1 else far + 8
		end
	end

	-- streaks rushing inward from the edges toward the hole, turning slightly (the swirl)
	local showStreaks = f.streaks > 0.001 and f.stage == "Pull"
	local edge = math.max(radius * 0.92, unit * 0.04)
	local span = math.max(far - edge, 1)
	local thick = math.max(1.5, unit / 220)
	for _, s in self.streaks do
		local frame = s.frame
		frame.Visible = showStreaks
		if showStreaks then
			local u = (f.pull * 1.6 + s.phase) % 1 -- travel phase: 0 = at the edge, 1 = at the hole
			local dist = edge + (1 - u) * span
			local len = unit * (0.07 + 0.11 * (1 - u)) * s.size
			local a = math.rad(s.angle + f.swirl)
			local dx, dy = math.cos(a), math.sin(a)
			local mid = dist + len / 2
			frame.Position = UDim2.fromOffset(cx + dx * mid, cy + dy * mid)
			frame.Size = UDim2.fromOffset(len, thick)
			frame.Rotation = s.angle + f.swirl
			frame.BackgroundTransparency = 1 - Tuning.StreakAlpha * f.streaks * math.sin(u * math.pi)
		end
	end

	-- the SOUL heart at the chest (pixel heart, 16 x 16 sprite at an integer scale) + a soft red glow
	local heartOn = f.heart > 0.001 and (f.stage == "Pull" or f.stage == "Black")
	self.heart.Visible = heartOn
	for _, g in self.glows do
		g.Visible = heartOn
	end
	if heartOn then
		local px = math.clamp(math.floor(unit * 0.1 / 16 + 0.5), 2, 6)
		local hs = 16 * px
		self.heart.Position = UDim2.fromOffset(cx, cy)
		self.heart.Size = UDim2.fromOffset(hs, hs)
		local alpha = math.floor(f.heart * 20 + 0.5) / 20
		if alpha ~= self.heartAlpha then
			self.heartAlpha = alpha
			for _, p in self.heartPixels do
				p.BackgroundTransparency = 1 - alpha
			end
		end
		for i, g in self.glows do
			local d = hs * (if i == 1 then 3.4 else 2.1)
			g.Position = UDim2.fromOffset(cx, cy)
			g.Size = UDim2.fromOffset(d, d)
			g.BackgroundTransparency = 1 - (1 - self.glowAlpha[i]) * f.heart
		end
	end

	-- the sharp white flash
	self.flash.Visible = f.flash > 0.001
	self.flash.BackgroundTransparency = 1 - f.flash
end

function VerdictBoxEntry.Destroy(self: Entry)
	self.Root:Destroy()
end

---------------------------------------------------------------------------------------------------
-- runner (the per-frame glue; VerdictBoxController binds Step to a render step after the camera controller)

export type Hooks = {
	camera: () -> any?,
	chest: () -> Vector3?,
	project: (camera: any, point: Vector3) -> Vector2?,
	size: () -> Vector2,
	postFx: ((amount: number) -> ())?,
}

export type Runner = {
	stages: Stages,
	layer: Entry?,
	hooks: Hooks,
	fx: Fx,
	frame: Frame?,
	center: Vector2?,
	done: boolean,
	Step: (self: Runner, now: number) -> Frame,
	Stop: (self: Runner) -> (),
}

local RunnerMethods = {}

function RunnerMethods.Step(self: Runner, now: number): Frame
	local f = VerdictBoxEntry.At(self.stages, now, self.frame)
	self.frame = f
	if self.done then
		return f
	end
	local hooks = self.hooks
	local camera = hooks.camera()
	local chest = hooks.chest()
	if camera ~= nil then
		if f.camera > 0 and chest ~= nil then
			self.fx:Apply(camera, chest, f.camera, f.roll)
		else
			self.fx:Restore(camera) -- from the black on the camera is its own again (unseen)
		end
	end
	if hooks.postFx and not self.stages.reduced then
		hooks.postFx(f.camera)
	end
	local size = hooks.size()
	if f.stage == "Pull" or self.center == nil then
		-- the chest through the pulled camera; kept through the black (the camera is already back there)
		local c = if camera ~= nil and chest ~= nil then hooks.project(camera, chest :: Vector3) else nil
		self.center = c or size * 0.5
	end
	if self.layer then
		self.layer:Render(f, self.center :: Vector2, size)
	end
	if f.stage == "Done" then
		self:Stop()
	end
	return f
end

function RunnerMethods.Stop(self: Runner)
	if self.done then
		return
	end
	self.done = true
	self.fx:Restore(self.hooks.camera())
	if self.hooks.postFx then
		self.hooks.postFx(0)
	end
	local layer = self.layer
	self.layer = nil
	if layer then
		layer:Destroy()
	end
end

function VerdictBoxEntry.Runner(stages: Stages, layer: Entry?, hooks: Hooks): Runner
	return {
		stages = stages,
		layer = layer,
		hooks = hooks,
		fx = VerdictBoxEntry.CameraFx(),
		frame = nil,
		center = nil,
		done = false,
		Step = RunnerMethods.Step,
		Stop = RunnerMethods.Stop,
	}
end

---------------------------------------------------------------------------------------------------
-- dump_gui preview: the layer alone over a plain painted backdrop at deps.Time s after BoxStart

function VerdictBoxEntry.Create(_theme: any, deps: { [string]: any }?): { Root: GuiObject, Destroy: () -> () }
	local d = deps or {}
	local canvas: Vector2 = if d.Layout and d.Layout.Canvas then d.Layout.Canvas else Vector2.new(860, 400)
	local root = new("Frame", {
		Name = "VerdictBoxEntryPreview",
		Size = UDim2.fromOffset(canvas.X, canvas.Y),
		BackgroundColor3 = Color3.fromRGB(120, 150, 190),
	}, nil)
	local stages = VerdictBoxEntry.Stages(0, 0.75, 1, d.Reduced == true)
	local entry = VerdictBoxEntry.new(root, {})
	entry:Render(VerdictBoxEntry.At(stages, d.Time or 0.45), canvas * 0.5, canvas)
	return {
		Root = root,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return VerdictBoxEntry

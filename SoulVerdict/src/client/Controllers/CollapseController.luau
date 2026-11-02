--!strict
-- CollapseController (client, Priority 56): the in-world wall of the Collapse (SPEC §1.1 overtime "closing ring of
-- void"). The server drives ReplicatedStorage.RoundState CollapseCenter / CollapseRadius (10 Hz, 0 outside the
-- Collapse) and deals True damage outside; the HUD only showed a warning when you were already outside, so nothing
-- drew the boundary in the world (integration fix).
--   * While Phase == "Collapse" and CollapseRadius > 0: a ring of translucent void-purple wall segments + a bright
--     ground band at the safe radius, eased toward the replicated radius every frame (no 10 Hz stepping).
--   * Parts are anchored, non-colliding, CanQuery/CanTouch off (camera collision, aim rays and hit tests ignore
--     them) and live in workspace.SV_CollapseRing; everything is removed when the phase ends.
--
-- API
--   CollapseController.SegmentFrames(center, radius, count, height) -> {CFrame}   pure (segment centres, each
--       facing the ring centre), Lune-tested
--   CollapseController.Radius() -> number   radius currently drawn (0 = hidden)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollapseController = {}
CollapseController.Priority = 56

local SEGMENTS = 48
local WALL_HEIGHT = 70
local WALL_THICKNESS = 0.6
local BAND_HEIGHT = 0.5
local WALL_COLOR = Color3.fromRGB(140, 60, 255)
local BAND_COLOR = Color3.fromRGB(205, 150, 255)
local EASE_RATE = 6 -- 1/s exponential approach to the replicated radius

local folder: Folder? = nil
local walls: { BasePart } = {}
local bands: { BasePart } = {}
local shownRadius = 0
local targetRadius = 0
local center = Vector3.zero
local drawnRadius = -1
local started = false

-- Pure: centres of `count` segments on a circle (y = centre height + height / 2), each looking at the centre.
function CollapseController.SegmentFrames(c: Vector3, radius: number, count: number, height: number): { CFrame }
	local out: { CFrame } = {}
	for i = 1, count do
		local a = (i - 0.5) / count * 2 * math.pi
		local offset = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = c + offset * radius + Vector3.new(0, height / 2, 0)
		-- right vector along the tangent, up = Y, back (Z) outward => look (-Z) toward the centre (right-handed)
		local right = Vector3.new(math.sin(a), 0, -math.cos(a))
		table.insert(out, CFrame.fromMatrix(pos, right, Vector3.yAxis, offset))
	end
	return out
end

function CollapseController.Radius(): number
	return if folder then shownRadius else 0
end

local function makePart(name: string, color: Color3, material: Enum.Material, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("CameraIgnore", true)
	return p
end

local function ensureParts()
	if folder and folder.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "SV_CollapseRing"
	table.clear(walls)
	table.clear(bands)
	for i = 1, SEGMENTS do
		local wall = makePart("Wall" .. i, WALL_COLOR, Enum.Material.ForceField, 0.35)
		wall.Parent = f
		table.insert(walls, wall)
		local band = makePart("Band" .. i, BAND_COLOR, Enum.Material.Neon, 0.15)
		band.Parent = f
		table.insert(bands, band)
	end
	f.Parent = workspace
	folder = f
	drawnRadius = -1
end

local function clear()
	if folder then
		folder:Destroy()
	end
	folder = nil
	table.clear(walls)
	table.clear(bands)
	shownRadius = 0
	drawnRadius = -1
end

local function draw(radius: number)
	if math.abs(radius - drawnRadius) < 0.02 then
		return
	end
	drawnRadius = radius
	local width = 2 * math.pi * radius / SEGMENTS * 1.04
	local wallFrames = CollapseController.SegmentFrames(center, radius, SEGMENTS, WALL_HEIGHT)
	local bandFrames = CollapseController.SegmentFrames(center + Vector3.new(0, 0.05, 0), radius, SEGMENTS, BAND_HEIGHT)
	local wallSize = Vector3.new(width, WALL_HEIGHT, WALL_THICKNESS)
	local bandSize = Vector3.new(width, BAND_HEIGHT, 1.2)
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for i = 1, SEGMENTS do
		walls[i].Size = wallSize
		bands[i].Size = bandSize
		table.insert(parts, walls[i])
		table.insert(frames, wallFrames[i])
		table.insert(parts, bands[i])
		table.insert(frames, bandFrames[i])
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function readState()
	local rs = ReplicatedStorage:FindFirstChild("RoundState")
	if rs == nil then
		targetRadius = 0
		return
	end
	local phase = rs:GetAttribute("Phase")
	local radius = rs:GetAttribute("CollapseRadius")
	local c = rs:GetAttribute("CollapseCenter")
	if phase == "Collapse" and type(radius) == "number" and radius > 0 and typeof(c) == "Vector3" then
		targetRadius = radius
		center = c
	else
		targetRadius = 0
	end
end

local function step(dt: number)
	readState()
	if targetRadius <= 0 then
		if folder then
			clear()
		end
		return
	end
	if folder == nil then
		ensureParts()
		shownRadius = targetRadius
	else
		shownRadius += (targetRadius - shownRadius) * (1 - math.exp(-EASE_RATE * dt))
	end
	draw(shownRadius)
end

function CollapseController.Init() end

function CollapseController.Start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[CollapseController] " .. tostring(err))
		end
	end)
end

return CollapseController

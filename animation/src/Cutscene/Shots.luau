--!strict
-- Timeline of "Part 1, first 3 seconds" (style test).
--   0.000 - 0.867  wide shot: Ryu points at Rika and Yuta across the mist
--   0.867 - 3.000  split screen: Yuta's eyes (top) and Ryu's eyes (bottom)
--                  slide in from opposite sides and keep drifting
-- All timings and slide curves were measured frame by frame on the
-- reference video (30 fps).
local Builder = require(script.Parent.Builder)
local Layout = require(script.Parent.Layout)
local Rig = require(script.Parent.Rig)
local Track = require(script.Parent.Track)

local Shots = {}

Shots.DURATION = 3.0
Shots.CUT = 26 / 30

export type FrameState = {
	t: number,
	shot: string,
	camera: CFrame,
	fov: number,
	focus: number, -- depth of field focus distance
	dof: number, -- depth of field strength multiplier (0 = off for this shot)
	rigs: { [string]: { [string]: CFrame } }, -- bone world CFrames
	channels: { [string]: CFrame },
	overlay: { [string]: boolean },
}

-- Horizontal offsets of the face plates in reference pixels, relative to
-- their resting place at t = 2.0 s (measured, lightly smoothed).
local yutaSlide = Track.new({
	{ 0.8667, 569 },
	{ 0.9, 380 },
	{ 0.9333, 305 },
	{ 0.9667, 245 },
	{ 1.0, 190 },
	{ 1.0333, 160 },
	{ 1.0667, 133 },
	{ 1.1, 110 },
	{ 1.1333, 93 },
	{ 1.1667, 78 },
	{ 1.2, 66 },
	{ 1.2667, 47 },
	{ 1.3333, 34 },
	{ 1.4, 25 },
	{ 1.5, 16 },
	{ 1.6, 11.5 },
	{ 1.7, 8 },
	{ 1.8, 5 },
	{ 1.9, 2.5 },
	{ 2.0, 0 },
	{ 2.25, -4.5 },
	{ 2.5, -7.5 },
	{ 2.75, -9.8 },
	{ 3.0, -11.3 },
	{ 3.3, -13 },
})
local ryuSlide = Track.new({
	{ 0.8667, -567 },
	{ 0.9, -390 },
	{ 0.9333, -330 },
	{ 0.9667, -270 },
	{ 1.0, -208 },
	{ 1.0333, -180 },
	{ 1.0667, -152 },
	{ 1.1, -122 },
	{ 1.1333, -104 },
	{ 1.1667, -86 },
	{ 1.2, -68 },
	{ 1.2667, -45 },
	{ 1.3333, -28 },
	{ 1.4, -16 },
	{ 1.5, -9.5 },
	{ 1.6, -7 },
	{ 1.7, -5 },
	{ 1.8, -3.2 },
	{ 1.9, -1.6 },
	{ 2.0, 0 },
	{ 2.25, 3 },
	{ 2.5, 7 },
	{ 2.75, 10 },
	{ 3.0, 12.5 },
	{ 3.3, 15 },
})

Shots.tracks = { yutaSlide = yutaSlide, ryuSlide = ryuSlide }

local function slideCF(px: number): CFrame
	local spp = Layout.studsPerPx(Layout.CLOSE_FOV, Layout.FACE_DEPTH)
	return CFrame.new(Layout.CLOSE_CAM.RightVector * (px * spp))
end

-- Rig poses with small living motion on top of the held key pose
local function widePoses(scene: Builder.Scene, t: number): { [string]: { [string]: CFrame } }
	local wide = scene.data.wide
	local out = {}
	for name, root in wide.roots do
		local pose: Rig.Pose = table.clone(wide.poses[name])
		if name == "Rika" then
			local b = math.sin(t * math.pi * 2 * 0.55)
			pose.UpperTorso = (pose.UpperTorso or CFrame.new()) * Rig.R(b * 1.4, 0, 0)
			pose.Head = (pose.Head or CFrame.new()) * Rig.R(-b * 1.0, b * 0.6, 0)
			pose.RightLowerArm = (pose.RightLowerArm or CFrame.new()) * Rig.R(b * 2, 0, 0)
		elseif name == "Ryu" then
			local b = math.sin(t * math.pi * 2 * 0.4 + 1)
			pose.UpperTorso = (pose.UpperTorso or CFrame.new()) * Rig.R(b * 0.5, 0, 0)
		end
		local rig = scene.rigs[name]
		out[name] = Rig.solve(rig.def, root, pose)
	end
	return out
end

function Shots.evaluate(scene: Builder.Scene, t: number): FrameState
	local channels: { [string]: CFrame } = {
		plateYuta = slideCF(Track.sample(yutaSlide, t)),
		plateRyu = slideCF(Track.sample(ryuSlide, t)),
		fogMid = CFrame.new(0.6 * t, 0, 0),
		fogNear = CFrame.new(0.5 * t, 0, 0),
	}
	if t < Shots.CUT then
		return {
			t = t,
			shot = "wide",
			camera = Layout.WIDE_CAM,
			fov = Layout.WIDE_FOV,
			focus = 118,
			dof = 1,
			rigs = widePoses(scene, t),
			channels = channels,
			overlay = { divider = false },
		}
	end
	return {
		t = t,
		shot = "eyes",
		camera = Layout.CLOSE_CAM,
		fov = Layout.CLOSE_FOV,
		focus = Layout.FACE_DEPTH,
		-- the painted plates are transparent parts, which depth of field
		-- cannot see: keep the close-up sharp
		dof = 0,
		rigs = widePoses(scene, t),
		channels = channels,
		overlay = { divider = true },
	}
end

return Shots

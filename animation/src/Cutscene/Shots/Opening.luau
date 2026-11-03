--!strict
-- Shots 1-2 (0.000 - 5.733):
--   1  0.000-0.867  wide: Ryu points at Rika and Yuta across the misty field
--   2  0.867-5.733  split screen: Yuta's eyes (top), Ryu's eyes (bottom)
--                   slide in, drift; their energies light the panels up
-- Timings and slide curves measured frame by frame on the reference (30 fps).
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Layout = require(script.Parent.Parent.Layout)
local Track = require(script.Parent.Parent.Track)
local Rig = require(script.Parent.Parent.Rig)
local Cast = require(script.Parent.Cast)
local Field = require(script.Parent.Field)
local WideSet = require(script.Parent.Parent.Art.Sets.WideSet)
local CloseupSet = require(script.Parent.Parent.Art.Sets.CloseupSet)

local Opening = {}

function Opening.build(scene: Builder.Scene)
	WideSet.build(scene)
	CloseupSet.build(scene)
end

-- face plate offsets in reference px relative to their place at t = 2.0 s
local yutaSlide = Track.new({
	{ 0.8667, 569 }, { 0.9, 380 }, { 0.9333, 305 }, { 0.9667, 245 }, { 1.0, 190 }, { 1.0333, 160 },
	{ 1.0667, 133 }, { 1.1, 110 }, { 1.1333, 93 }, { 1.1667, 78 }, { 1.2, 66 }, { 1.2667, 47 },
	{ 1.3333, 34 }, { 1.4, 25 }, { 1.5, 16 }, { 1.6, 11.5 }, { 1.7, 8 }, { 1.8, 5 }, { 1.9, 2.5 },
	{ 2.0, 0 }, { 2.25, -4.5 }, { 2.5, -7.5 }, { 2.75, -9.8 }, { 3.0, -11.3 }, { 3.3, -13 }, { 5.733, -40 },
})
local ryuSlide = Track.new({
	{ 0.8667, -567 }, { 0.9, -390 }, { 0.9333, -330 }, { 0.9667, -270 }, { 1.0, -208 }, { 1.0333, -180 },
	{ 1.0667, -152 }, { 1.1, -122 }, { 1.1333, -104 }, { 1.1667, -86 }, { 1.2, -68 }, { 1.2667, -45 },
	{ 1.3333, -28 }, { 1.4, -16 }, { 1.5, -9.5 }, { 1.6, -7 }, { 1.7, -5 }, { 1.8, -3.2 }, { 1.9, -1.6 },
	{ 2.0, 0 }, { 2.25, 3 }, { 2.5, 7 }, { 2.75, 10 }, { 3.0, 12.5 }, { 3.3, 15 }, { 5.733, 44 },
})

local function slideCF(px: number): CFrame
	local spp = Layout.studsPerPx(Layout.CLOSE_FOV, Layout.FACE_DEPTH)
	return CFrame.new(Layout.CLOSE_CAM.RightVector * (px * spp))
end

local function wide(ctx: Timeline.Ctx)
	ctx:camera(Layout.WIDE_CAM, Layout.WIDE_FOV)
	ctx:focus(118, 1)
	-- only fog behind them in the establishing shot (reference): the ruined
	-- blocks around the field are lowered out of sight for these frames
	ctx:channel("cityBlocks", CFrame.new(0, -600, 0))
	ctx:fog(1.15)
	local t = ctx.t
	ctx:rig("Ryu", CFrame.new(Field.RYU) * CFrame.Angles(0, math.rad(-90), 0), Cast.alive(Cast.ryu.point, t))
	local rp = Cast.add(Cast.rika.crouch, "UpperTorso", Rig.R(math.sin(t * math.pi * 1.1) * 1.4, 0, 0))
	ctx:rig("Rika", CFrame.new(Field.RIKA) * CFrame.Angles(0, math.rad(128), 0), rp)
	ctx:rig("Yuta", CFrame.new(Field.YUTA) * CFrame.Angles(0, math.rad(96), 0), Cast.alive(Cast.yuta.stand, t))
	-- the glint at Ryu's raised finger
	ctx:light("RyuHand", 2.5, nil, 12)
	local plates = ctx.scene.data.wide
	ctx:place(plates.back.part, plates.back.base)
	ctx:place(plates.mid.part, CFrame.new(0.6 * t, 0, 0) * plates.mid.base)
	ctx:place(plates.near.part, CFrame.new(0.5 * t, 0, 0) * plates.near.base)
	Field.snow(ctx, 140)
end

local function eyes(ctx: Timeline.Ctx)
	ctx:camera(Layout.CLOSE_CAM, Layout.CLOSE_FOV)
	ctx:focus(Layout.FACE_DEPTH, 0)
	ctx:channel("plateYuta", slideCF(Track.sample(yutaSlide, ctx.t)))
	ctx:channel("plateRyu", slideCF(Track.sample(ryuSlide, ctx.t)))
	ctx:show("divider")
	ctx:emit("SnowClose", 20)
	-- 5.2 s on: both narrow their eyes into a glare (reference)
	if ctx.t >= 5.2 then
		ctx:show("split:yutaGlare")
		ctx:show("split:ryuGlare")
	end
	-- 5.10 s on: their energies flare up, the panels wash out to white
	local g = math.clamp((ctx.t - 5.1) / 0.55, 0, 1)
	if g > 0 then
		ctx:alpha("glowTop", g ^ 1.5)
		ctx:alpha("glowBot", g ^ 1.5)
		ctx:bloom(1 + g * 2)
	end
	local w = math.clamp((ctx.t - 5.55) / 0.18, 0, 1)
	if w > 0 then
		ctx:flash(Color3.new(1, 1, 1), w * 0.85)
	end
end

Opening.shots = {
	{ id = "01 wide", t0 = 0, t1 = 26 / 30, run = wide },
	{ id = "02 eyes", t0 = 26 / 30, t1 = 5.733, run = eyes },
} :: { Timeline.Shot }

return Opening

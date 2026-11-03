--!strict
-- Entry point shared by Roblox (Realizer) and the offline preview (Lune):
--   Scene.build(styleId)      -> scene description (plain data)
--   Scene.evaluate(scene, t)  -> everything that changes at time t
local Builder = require(script.Parent.Builder)
local Styles = require(script.Parent.Styles)
local Timeline = require(script.Parent.Timeline)

local Shots = script.Parent.Shots
local Cast = require(Shots.Cast)
local Field = require(Shots.Field)
local Opening = require(Shots.Opening)
local Clash = require(Shots.Clash)
local RyuShots = require(Shots.RyuShots)
local YutaShots = require(Shots.YutaShots)
local Part2 = require(Shots.Part2)
local Part3 = require(Shots.Part3)

local Scene = {}

-- far away and high up (never below Workspace.FallenPartsDestroyHeight)
Scene.PARK = CFrame.new(0, 9000, 40000)
Scene.DURATION = 58.533

-- English subtitles as in the reference edit (start, end, text)
export type Subtitle = { t0: number, t1: number, text: string }

Scene.SUBTITLES = {
	{ t0 = 16.067, t1 = 19.9, text = "That was seriously sweet, Okkotsu!" },
	{ t0 = 29.933, t1 = 31.4, text = "That's right!" },
	{ t0 = 31.4, t1 = 33.7, text = "Let's keep going!" },
	{ t0 = 37.3, t1 = 39.9, text = "That big thing can fire it on its own?!" },
	{ t0 = 40.133, t1 = 41.167, text = "But..." },
	{ t0 = 42.167, t1 = 44.067, text = "its force is weak!" },
	{ t0 = 45.6, t1 = 49.167, text = "After Domain Expansion and a meal with me," },
	{ t0 = 49.167, t1 = 53.667, text = "even you couldn't have recovered that much." },
	{ t0 = 53.933, t1 = 55.567, text = "I'll settle this." },
	{ t0 = 55.8, t1 = 58.533, text = "Granite Blast!" },
} :: { Subtitle }

-- Part 2 ("end fight scene pt. 2"): the first 5.27 s repeat the end of
-- part 1 (from 53.3 s on), then the new shots follow.
Scene.SUBTITLES2 = {
	{ t0 = 0, t1 = 0.333, text = "even you couldn't have recovered that much." },
	{ t0 = 0.633, t1 = 2.1, text = "I'll settle this." },
	{ t0 = 2.5, t1 = 4.9, text = "Granite Blast!" },
	{ t0 = 9.5, t1 = 12.733, text = "Okkotsu's technique" },
	{ t0 = 12.767, t1 = 15.6, text = "had already recovered." },
	{ t0 = 17.6, t1 = 20.233, text = "Uro's technique?!" },
	{ t0 = 20.333, t1 = 23.0, text = "I thought he was more than just a cursed speech user!" },
	{ t0 = 23.0, t1 = 27.6, text = "I figured that big thing probably had a different technique from Okkotsu's," },
	{ t0 = 27.667, t1 = 28.633, text = "but I was wrong!" },
	{ t0 = 28.7, t1 = 31.133, text = "Okkotsu's technique is Copy!" },
	{ t0 = 31.3, t1 = 33.2, text = "But there should be strenuous conditions on it!" },
	{ t0 = 33.2, t1 = 34.933, text = "When?! When did he satisfy those conditions?!" },
	{ t0 = 34.933, t1 = 36.1, text = "While I wasn't looking?!" },
	{ t0 = 36.2, t1 = 39.4, text = "Don't tell me there are no conditions?!" },
	{ t0 = 42.9, t1 = 44.667, text = "That was when he did it!" },
	{ t0 = 45.0, t1 = 46.2, text = "Thin Ice Breaker!" },
	{ t0 = 57.6, t1 = 58.7, text = "Five minutes." },
} :: { Subtitle }
Scene.DURATION2 = 59.167

-- Part 3: opens on the end of part 2 (t3 = t2 - 56.2)
Scene.SUBTITLES3 = {
	{ t0 = 1.4, t1 = 2.5, text = "Five minutes." },
	{ t0 = 2.933, t1 = 6.033, text = "Okkotsu's connection to \"Rika\" was severed." },
	{ t0 = 12.467, t1 = 14.667, text = "Yuta!" },
	{ t0 = 17.833, t1 = 19.5, text = "I had no idea" },
	{ t0 = 23.267, t1 = 26.4, text = "there was more after wringing everything out!" },
	{ t0 = 29.267, t1 = 33.033, text = "This is what dessert is like!" },
	{ t0 = 55.067, t1 = 56.533, text = "Now we're done." },
} :: { Subtitle }
Scene.DURATION3 = 56.867
Scene.RECAP3_FROM = 56.2
Scene.RECAP3_LEN = 2.633
Scene.RECAP_FROM = 53.3 -- part 1 time shown at part 2's t = 0
Scene.RECAP_LEN = 5.267

local part1Modules = { Opening, Clash, RyuShots, YutaShots }

-- A part 1 shot replayed at another time: the shot runs exactly as in part 1
-- (same progress, same local time) but writes into the part 2 frame.
local function shifted(s: Timeline.Shot, offset: number, lo: number, hi: number): Timeline.Shot
	return {
		id = "R" .. s.id,
		t0 = math.max(lo, s.t0 - offset),
		t1 = math.min(hi, s.t1 - offset),
		run = function(ctx: Timeline.Ctx)
			local inner = Timeline.context(ctx.scene, ctx.t + offset, s)
			inner.frame = ctx.frame
			s.run(inner)
		end,
	}
end

function Scene.build(styleId: string, part: number?): Builder.Scene
	local partId = part or 1
	local scene = Builder.new(Styles.get(styleId))
	scene.data.part = partId
	Cast.build(scene)
	Field.build(scene)
	local shots: { Timeline.Shot } = {}
	if partId == 1 then
		for _, m in part1Modules do
			m.build(scene)
		end
		for _, m in part1Modules do
			for _, s in m.shots do
				table.insert(shots, s)
			end
		end
		scene.data.duration = Scene.DURATION
		scene.data.subtitles = Scene.SUBTITLES
	elseif partId == 3 then
		for _, m in { Clash, RyuShots, YutaShots } do
			m.build(scene)
		end
		Part2.build(scene)
		Part3.build(scene)
		local a, b = Scene.RECAP3_FROM, Scene.RECAP3_FROM + Scene.RECAP3_LEN
		for _, s in Part2.shots do
			if s.t1 > a and s.t0 < b then
				table.insert(shots, shifted(s, a, 0, Scene.RECAP3_LEN))
			end
		end
		for _, s in Part3.shots do
			table.insert(shots, s)
		end
		scene.data.duration = Scene.DURATION3
		scene.data.subtitles = Scene.SUBTITLES3
	else
		for _, m in { Clash, RyuShots, YutaShots } do
			m.build(scene)
		end
		Part2.build(scene)
		-- recap: the end of part 1
		local a, b = Scene.RECAP_FROM, Scene.RECAP_FROM + Scene.RECAP_LEN
		for _, m in { Clash, RyuShots, YutaShots } do
			for _, s in m.shots do
				if s.t1 > a and s.t0 < b then
					table.insert(shots, shifted(s, a, 0, Scene.RECAP_LEN))
				end
			end
		end
		for _, s in Part2.shots do
			table.insert(shots, s)
		end
		scene.data.duration = Scene.DURATION2
		scene.data.subtitles = Scene.SUBTITLES2
	end
	table.sort(shots, function(x: Timeline.Shot, y: Timeline.Shot): boolean
		return x.t0 < y.t0
	end)
	scene.data.shots = shots
	return scene
end

function Scene.shots(scene: Builder.Scene): { Timeline.Shot }
	return scene.data.shots
end

function Scene.duration(scene: Builder.Scene): number
	return scene.data.duration or Scene.DURATION
end

function Scene.subtitle(scene: Builder.Scene, t: number): string?
	local list: { Subtitle } = scene.data.subtitles or Scene.SUBTITLES
	for _, s in list do
		if t >= s.t0 and t < s.t1 then
			return s.text
		end
	end
	return nil
end

function Scene.evaluate(scene: Builder.Scene, t: number): Timeline.FrameState
	local shots: { Timeline.Shot } = scene.data.shots
	local shot = Timeline.find(shots, t)
	local ctx = Timeline.context(scene, t, shot)
	shot.run(ctx)
	Field.aftermath(ctx)
	ctx.frame.sub = Scene.subtitle(scene, t)
	return ctx.frame
end

-- Sway of a flexing part (hair, fur, cloth): a slow wind wave shared by
-- everything plus a quicker flutter of its own, about its attachment point
local TAU = math.pi * 2
local function flexRot(part: Builder.PartSpec, frame: Timeline.FrameState): CFrame
	local amp = (part.flex or 0) * (frame.wind + frame.gust)
	if amp < 0.01 then
		return CFrame.new()
	end
	local t = frame.t
	local ph = part.id * 1.37
	local ax = 0.65 * math.sin(TAU * 0.9 * t + ph * 0.3) + 0.35 * math.sin(TAU * 3.1 * t + ph)
	local az = 0.5 * math.cos(TAU * 0.7 * t + ph * 0.2) + 0.3 * math.sin(TAU * 2.6 * t + ph * 1.7)
	-- a gust shakes things quickly
	local g = frame.gust * 0.6 * math.sin(TAU * 7 * t + ph)
	local rot = CFrame.Angles(math.rad((ax + g) * amp), 0, math.rad((az - g) * amp))
	local piv = part.pivot
	if piv then
		return CFrame.new(piv) * rot * CFrame.new(-piv)
	end
	return rot
end

-- World CFrame of a part for a frame (parked when not used by the shot)
function Scene.partCFrame(part: Builder.PartSpec, frame: Timeline.FrameState): CFrame
	if part.rig and part.bone then
		local bones = frame.rigs[part.rig]
		if bones then
			local b = bones[part.bone]
			if b then
				if part.flex then
					return b * part.cf * flexRot(part, frame)
				end
				return b * part.cf
			end
		end
		return Scene.PARK
	elseif part.fx then
		return frame.parts[part.id] or Scene.PARK
	elseif part.channel then
		local ch = frame.channels[part.channel]
		if ch then
			return ch * part.cf
		end
	end
	return part.cf
end

return Scene

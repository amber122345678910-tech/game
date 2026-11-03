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

local Scene = {}

Scene.PARK = CFrame.new(0, -5000, 0)
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

local shotModules = { Opening, Clash, RyuShots, YutaShots }

function Scene.build(styleId: string): Builder.Scene
	local scene = Builder.new(Styles.get(styleId))
	Cast.build(scene)
	Field.build(scene)
	for _, m in shotModules do
		m.build(scene)
	end
	local shots: { Timeline.Shot } = {}
	for _, m in shotModules do
		for _, s in m.shots do
			table.insert(shots, s)
		end
	end
	table.sort(shots, function(a: Timeline.Shot, b: Timeline.Shot): boolean
		return a.t0 < b.t0
	end)
	scene.data.shots = shots
	return scene
end

function Scene.shots(scene: Builder.Scene): { Timeline.Shot }
	return scene.data.shots
end

function Scene.subtitle(t: number): string?
	for _, s in Scene.SUBTITLES do
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
	ctx.frame.sub = Scene.subtitle(t)
	return ctx.frame
end

-- World CFrame of a part for a frame (parked when not used by the shot)
function Scene.partCFrame(part: Builder.PartSpec, frame: Timeline.FrameState): CFrame
	if part.rig and part.bone then
		local bones = frame.rigs[part.rig]
		if bones then
			local b = bones[part.bone]
			if b then
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

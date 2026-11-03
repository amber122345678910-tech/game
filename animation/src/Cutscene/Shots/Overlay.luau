--!strict
-- 2D overlay layers drawn over the 16:9 picture (design px 1113 x 626):
-- coloured glows for the split screen, radial speed lines, the black/white
-- impact frame, wind streaks, purple spark streaks and a blue starburst.
-- Each layer is a group whose opacity the timeline animates.
local Builder = require(script.Parent.Parent.Builder)
local Paint = require(script.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Util)

local Overlay = {}

local W, H = 1113, 626

local function add(scene: Builder.Scene, c: Paint.Canvas, group: string)
	for _, e in c.elems do
		e.group = group
		table.insert(scene.overlay, e)
	end
end

local function fade(a0: number, a1: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(1, a1) })
end

function Overlay.build(scene: Builder.Scene)
	local pal = scene.style.color

	-- split-screen energy glows (lavender from the left on top, cyan from the right below)
	local g = Paint.canvas(1, 0, 0)
	g:grad(0, 0, W, 296, { transparency = fade(0.05, 1), rotation = 0 }, Util.mix(pal.ePink, Color3.new(1, 1, 1), 0.55))
	add(scene, g, "glowTop")
	g = Paint.canvas(1, 0, 0)
	g:grad(0, 306, W, H, { transparency = fade(1, 0.05), rotation = 0 }, Util.mix(pal.eCyan, Color3.new(1, 1, 1), 0.45))
	add(scene, g, "glowBot")

	-- radial speed lines (blue/white), centre slightly right
	g = Paint.canvas(1, 0, 0)
	g:box(0, 0, W, H, pal.eBlue, 0.15)
	local r = Util.rng(77)
	for i = 1, 70 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d0 = Util.randRange(r, 90, 260)
		local len = Util.randRange(r, 260, 700)
		local cx, cy = W * 0.62 + math.cos(a) * (d0 + len / 2), H * 0.45 + math.sin(a) * (d0 + len / 2)
		g:pill(cx, cy, len, Util.randRange(r, 3, 14), math.deg(a), if i % 3 == 0 then pal.eWhite else pal.eIce, Util.randRange(r, 0.05, 0.35))
	end
	add(scene, g, "speed")

	-- impact frame: black with a ragged white splash and a yellow cross
	g = Paint.canvas(1, 0, 0)
	g:box(-10, -10, W + 10, H + 10, Color3.new(0, 0, 0))
	r = Util.rng(91)
	for _ = 1, 26 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = Util.randRange(r, 0, 120)
		g:pill(W * 0.6 + math.cos(a) * d, H * 0.36 + math.sin(a) * d * 0.8, Util.randRange(r, 80, 190), Util.randRange(r, 60, 140), math.deg(a), Color3.new(1, 1, 1))
	end
	g:pill(W * 0.62, H * 0.33, 300, 4, -20, pal.eYellow)
	g:pill(W * 0.62, H * 0.33, 240, 4, 62, pal.eYellow)
	add(scene, g, "impact")

	-- wind streaks blowing across the frame
	g = Paint.canvas(1, 0, 0)
	r = Util.rng(55)
	for _ = 1, 26 do
		local x, y = Util.randRange(r, -100, W + 100), Util.randRange(r, -40, H + 40)
		g:pill(x, y, Util.randRange(r, 160, 420), Util.randRange(r, 3, 10), -28 + Util.randRange(r, -4, 4), Color3.fromRGB(225, 232, 245), Util.randRange(r, 0.25, 0.6))
	end
	add(scene, g, "wind")

	-- purple spark streaks (Yuta dashing through Ryu's fire)
	g = Paint.canvas(1, 0, 0)
	r = Util.rng(66)
	for _ = 1, 34 do
		local x, y = Util.randRange(r, -60, W + 60), Util.randRange(r, 0, H)
		g:pill(x, y, Util.randRange(r, 60, 180), Util.randRange(r, 3, 7), -12 + Util.randRange(r, -6, 6), if Util.rand(r) > 0.3 then pal.ePink else pal.ePurple, Util.randRange(r, 0.0, 0.3))
	end
	add(scene, g, "streaks")

	-- white starburst on blue (impact flash)
	g = Paint.canvas(1, 0, 0)
	g:box(-10, -10, W + 10, H + 10, pal.eBlue)
	r = Util.rng(33)
	for _ = 1, 30 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local len = Util.randRange(r, 200, 640)
		g:pill(W * 0.6 + math.cos(a) * len / 2, H * 0.3 + math.sin(a) * len / 2, len, Util.randRange(r, 6, 30), math.deg(a), Color3.new(1, 1, 1), Util.randRange(r, 0, 0.3))
	end
	g:circle(W * 0.6, H * 0.3, 70, Color3.new(1, 1, 1))
	add(scene, g, "starburst")
end

return Overlay

--!strict
-- Painted skies (matte paintings on camera-facing plates).
--  * storm   : the overcast blue-grey sky of the reference
--  * cinema  : same mood, softer and darker (blurred by depth of field)
--  * clear   : bright "classic Roblox" day sky
-- Coordinates are reference pixels of the frame; blobs are soft clouds made
-- of stacked translucent pills.
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)

local hex = Util.hex
local SkyPaint = {}

local function vgrad(c: Paint.Canvas, x0: number, y0: number, x1: number, y1: number, stops: { { any } })
	local kps = {}
	for _, s in stops do
		table.insert(kps, ColorSequenceKeypoint.new(s[1], s[2]))
	end
	c:grad(x0, y0, x1, y1, { color = ColorSequence.new(kps), rotation = 90 })
end

local function hgrad(c: Paint.Canvas, x0: number, y0: number, x1: number, y1: number, col: Color3, t0: number, t1: number)
	c:grad(x0, y0, x1, y1, {
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t0), NumberSequenceKeypoint.new(1, t1) }),
		rotation = 0,
	}, col)
end

-- Clouds: deterministic soft blobs
local function clouds(c: Paint.Canvas, seed: number, n: number, x0: number, y0: number, x1: number, y1: number, col: Color3, alpha: number, wMin: number, wMax: number)
	local r = Util.rng(seed)
	for _ = 1, n do
		local x = Util.randRange(r, x0, x1)
		local y = Util.randRange(r, y0, y1)
		local w = Util.randRange(r, wMin, wMax)
		local h = w * Util.randRange(r, 0.28, 0.5)
		c:blob(x, y, w, h, col, alpha * Util.randRange(r, 0.6, 1))
	end
end

-- Full-frame sky for the wide shot (covers reference y -40 .. 700)
function SkyPaint.wide(c: Paint.Canvas, kind: string)
	local X0, X1 = -200, 1300
	if kind == "clear" then
		vgrad(c, X0, -40, X1, 460, {
			{ 0, hex("#3D8EF0") },
			{ 0.6, hex("#7DB8F7") },
			{ 1, hex("#CFE6FF") },
		})
		clouds(c, 11, 22, X0, 40, X1, 300, hex("#FFFFFF"), 0.8, 140, 340)
		clouds(c, 12, 12, X0, 300, X1, 410, hex("#F4F8FF"), 0.75, 180, 400)
		return
	end
	local dark = kind == "cinema"
	-- measured vertical profile of the reference sky
	vgrad(c, X0, -40, X1, 700, {
		{ 0, if dark then hex("#6F7FA6") else hex("#7F90BC") },
		{ 0.22, if dark then hex("#6B80AE") else hex("#7C92BF") },
		{ 0.33, if dark then hex("#5A6F9E") else hex("#6680B3") },
		{ 0.42, if dark then hex("#3F5384") else hex("#4A669E") },
		{ 0.5, if dark then hex("#36497A") else hex("#3E5487") },
		{ 0.57, if dark then hex("#3D507F") else hex("#4A6097") },
		{ 0.63, if dark then hex("#61759F") else hex("#6E86BC") },
		{ 0.7, if dark then hex("#7488B4") else hex("#7D93C6") },
		{ 1, if dark then hex("#5A6E9F") else hex("#6A82BA") },
	})
	-- light puffs on top
	clouds(c, 21, 16, X0, -20, X1, 150, hex("#A8B8DD"), 0.5, 260, 520)
	clouds(c, 22, 10, X0, 70, X1, 200, hex("#91A5D2"), 0.45, 300, 560)
	-- dark band with lighter wisps
	clouds(c, 23, 12, X0, 230, X1, 330, hex("#2E4070"), 0.5, 320, 620)
	clouds(c, 27, 8, X0, 250, X1, 320, hex("#8296C6"), 0.3, 180, 360)
	-- bright mist around the figures and over the horizon
	clouds(c, 24, 8, 250, 230, 650, 380, hex("#A9BBE2"), 0.55, 200, 380)
	clouds(c, 25, 8, 650, 260, 1150, 380, hex("#A9BBE2"), 0.5, 220, 400)
	clouds(c, 26, 10, X0, 360, X1, 430, hex("#B6C5E8"), 0.6, 320, 600)
end

-- Sky behind a split-screen panel. y0..y1 is the panel band.
function SkyPaint.panel(c: Paint.Canvas, kind: string, which: string, y0: number, y1: number)
	local X0, X1 = -60, 1180
	if kind == "clear" then
		vgrad(c, X0, y0, X1, y1, { { 0, hex("#4E9BF2") }, { 1, hex("#9CCBFA") } })
		clouds(c, if which == "top" then 31 else 32, 10, X0, y0 + 30, X1, y1 - 20, hex("#FFFFFF"), 0.7, 140, 300)
		return
	end
	local dark = kind == "cinema"
	if which == "top" then
		vgrad(c, X0, y0, X1, y1, {
			{ 0, if dark then hex("#6C80B4") else hex("#7A92CE") },
			{ 0.45, if dark then hex("#5A6FA4") else hex("#6A82BF") },
			{ 1, if dark then hex("#43578D") else hex("#4C629D") },
		})
		hgrad(c, X0, y0, X1, y1, if dark then hex("#2E3F6E") else hex("#3A4F8A"), 0.35, 1)
		clouds(c, 41, 12, X0, y0, 700, y1, hex("#8DA2D6"), 0.45, 120, 300)
		clouds(c, 42, 6, X0, y0 + 120, 500, y1, hex("#3C5089"), 0.4, 160, 320)
	else
		vgrad(c, X0, y0, X1, y1, {
			{ 0, if dark then hex("#3F5181") else hex("#4A5D93") },
			{ 1, if dark then hex("#33436F") else hex("#3C4E82") },
		})
		clouds(c, 43, 12, 500, y0, X1, y1, hex("#5A6EA6"), 0.45, 140, 320)
		clouds(c, 44, 8, 600, y0, X1, y1, hex("#2E3D6A"), 0.35, 160, 340)
	end
end

return SkyPaint

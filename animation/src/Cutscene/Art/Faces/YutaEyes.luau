--!strict
-- Yuta, extreme close-up of the eyes (upper half of the split screen).
-- Coordinates are reference pixels of the frame (see Layout); the face is
-- turned 3/4 to the left, looking up-left at Ryu.
local Paint = require(script.Parent.Parent.Parent.Paint)

local YutaEyes = {}

-- Horizontal extent of the painted area (the plate is wider than the frame
-- because it slides in from the right).
YutaEyes.X0 = 150
YutaEyes.X1 = 1170
YutaEyes.Y0 = -14
YutaEyes.Y1 = 301

-- A hair strand painted three times, in groups `prefix`1..3: the root
-- (first point) stays, the tip swings sideways by -amp, 0, +amp (the shot
-- cycles through the groups so the hair sways in the wind)
function YutaEyes.strand(c: Paint.Canvas, prefix: string, pts: { { number } }, w: { number } | number, col: Color3, amp: number, rootLast: boolean?)
	local n = #pts
	for k = 1, 3 do
		local off = (k - 2) * amp
		local q: { { number } } = {}
		for i, pt in pts do
			local f = (i - 1) / math.max(1, n - 1)
			if rootLast then
				f = 1 - f
			end
			local sw = off * f ^ 1.4
			table.insert(q, { pt[1] + sw, pt[2] + math.abs(sw) * 0.15 })
		end
		c:setGroup(prefix .. k)
		c:stroke(q, w, col)
	end
	c:setGroup(nil)
end

function YutaEyes.paint(c: Paint.Canvas, pal: { [string]: Color3 }, lw: number, soft: boolean?)
	local skin, shade, deep = pal.skin, pal.skinShade, pal.skinDeep
	local line, hair, hairHi = pal.line, pal.yHair, pal.yHairHi
	local function L(w: number): number
		return w * lw
	end
	local function strand(pts: { { number } }, w: { number } | number, col: Color3, amp: number)
		YutaEyes.strand(c, "split:yHair", pts, w, col, amp)
	end

	-- 1. skin -------------------------------------------------------------------
	c:box(372, -14, 1170, 301, skin)
	-- eye socket shadow around the near eye
	c:poly({ { 537, 125 }, { 580, 62 }, { 778, 52 }, { 786, 110 }, { 618, 242 } }, shade, skin)
	-- lit fold between the crease and the lid
	c:stroke({ { 648, 90 }, { 700, 92 }, { 748, 106 }, { 775, 130 } }, { 26, 34, 32, 14 }, skin)
	-- temple (right side) in shadow, under the hair
	c:box(874, -14, 1170, 301, shade)

	-- soft skin marks (forehead / cheek hatching)
	for _, s in { { 498, 36, 512, 30 }, { 503, 47, 520, 40 }, { 511, 58, 528, 50 }, { 517, 72, 530, 66 } } do
		c:stroke({ { s[1], s[2] }, { s[3], s[4] } }, { L(1.6), L(0.8) }, deep)
	end
	for _, s in { { 389, 230, 400, 218 }, { 393, 240, 406, 226 }, { 399, 249, 412, 236 } } do
		c:stroke({ { s[1], s[2] }, { s[3], s[4] } }, { L(1.6), L(0.8) }, deep)
	end

	-- 2. near eye (screen right) ---------------------------------------------------
	-- sclera
	c:stroke({ { 690, 186 }, { 740, 195 }, { 790, 203 }, { 830, 210 }, { 855, 216 } }, { 108, 110, 92, 58, 20 }, pal.sclera)
	c:stroke({ { 650, 134 }, { 646, 200 } }, { 18, 18 }, pal.sclera)
	c:stroke({ { 668, 128 }, { 700, 132 } }, { 22, 22 }, pal.sclera)
	-- lid shadow on the sclera + shaded outer part
	c:stroke({ { 652, 137 }, { 700, 143 }, { 750, 152 }, { 792, 168 }, { 826, 190 }, { 850, 212 } }, { 14, 18, 18, 18, 14, 6 }, pal.scleraShade)
	c:stroke({ { 775, 182 }, { 812, 200 }, { 842, 214 } }, { 34, 28, 10 }, pal.scleraShade)
	-- iris
	c:ellipse(725, 168, 27, 41, -6, pal.yIrisDark)
	c:ellipse(726, 170, 22, 35, -6, pal.yIris)
	c:ellipse(728, 186, 15, 17, -6, pal.yIrisLight)
	c:ellipse(726, 177, 12, 9, -6, pal.yIris)
	c:ellipse(724, 158, 11, 18, -6, pal.yIrisDark)
	-- iris light streaks (radial)
	for _, a in { -40, -15, 10, 35 } do
		local r = math.rad(a + 90)
		c:stroke({ { 727 + math.cos(r) * 8, 186 + math.sin(r) * 6 }, { 727 + math.cos(r) * 18, 186 + math.sin(r) * 15 } }, { 2.4, 1.2 }, pal.yIrisLight)
	end
	-- highlights
	c:ellipse(738, 181, 8, 2.6, -28, pal.sclera)
	c:circle(713, 150, 3.2, pal.sclera)
	-- upper lid (thick tapered line) + lashes
	c:stroke(
		{ { 641, 112 }, { 699, 121 }, { 749, 132 }, { 791, 151 }, { 824, 173 }, { 849, 202 }, { 863, 230 } },
		{ L(22), L(23), L(19), L(15), L(12), L(10), L(2) },
		line
	)
	c:stroke({ { 652, 108 }, { 638, 116 }, { 626, 124 } }, { L(6), L(3), L(1) }, line)
	c:stroke({ { 652, 117 }, { 640, 127 }, { 631, 136 } }, { L(5), L(2.5), L(0.8) }, line)
	c:stroke({ { 796, 150 }, { 812, 138 }, { 823, 133 } }, { L(5), L(2), L(0.8) }, line)
	-- inner corner and lower lid
	c:stroke({ { 645, 118 }, { 639, 160 }, { 641, 200 }, { 648, 216 } }, { L(3), L(2.4), L(2.2), L(1.6) }, line)
	c:stroke({ { 646, 214 }, { 668, 234 }, { 720, 250 }, { 772, 253 }, { 830, 240 }, { 858, 226 } }, { L(1.2), L(2.4), L(2.8), L(2.8), L(2.4), L(1) }, line)
	-- eye bags
	c:stroke({ { 657, 251 }, { 702, 265 }, { 756, 271 }, { 810, 262 }, { 850, 246 } }, { L(0.8), L(2), L(2.2), L(2), L(0.8) }, line)
	c:stroke({ { 676, 263 }, { 722, 277 }, { 776, 281 }, { 826, 271 } }, { L(0.6), L(1.6), L(1.6), L(0.6) }, deep)
	-- double-lid crease
	c:stroke({ { 616, 104 }, { 642, 78 }, { 695, 74 }, { 745, 89 }, { 775, 122 } }, { L(0.6), L(2), L(2.2), L(2), L(0.6) }, deep)

	-- 2b. glare (shown from 5.2 s, when the energies flare): the upper lid
	-- drops over the top of the iris and the eye narrows
	c:setGroup("split:yutaGlare")
	c:stroke({ { 641, 119 }, { 699, 131 }, { 749, 142 }, { 791, 158 }, { 824, 178 }, { 849, 204 }, { 863, 230 } }, { 24, 32, 32, 27, 21, 11, 3 }, skin)
	c:stroke(
		{ { 641, 126 }, { 699, 141 }, { 749, 152 }, { 791, 166 }, { 824, 184 }, { 849, 207 }, { 863, 230 } },
		{ L(22), L(23), L(19), L(15), L(12), L(10), L(2) },
		line
	)
	c:setGroup(nil)

	-- 3. far eye (screen left, foreshortened) --------------------------------------
	c:stroke({ { 420, 82 }, { 423, 104 }, { 428, 136 } }, { 76, 80, 46 }, pal.sclera)
	c:stroke({ { 392, 58 }, { 446, 66 } }, { 22, 16 }, pal.scleraShade)
	c:ellipse(420, 90, 19, 33, 4, pal.yIrisDark)
	c:ellipse(421, 92, 15, 28, 4, pal.yIris)
	c:ellipse(422, 105, 11, 13, 4, pal.yIrisLight)
	c:ellipse(420, 84, 8, 15, 4, pal.yIrisDark)
	c:ellipse(414, 78, 9, 3, -14, pal.sclera)
	c:circle(427, 112, 2.4, pal.sclera)
	-- lids and lines
	c:stroke({ { 378, 46 }, { 410, 42 }, { 446, 52 }, { 458, 70 } }, { L(13), L(12), L(8), L(3) }, line)
	c:stroke({ { 451, 58 }, { 463, 90 }, { 466, 124 }, { 456, 156 } }, { L(1.4), L(2.2), L(2.2), L(1.2) }, line)
	for i, s in { { 392, 146, 410, 152 }, { 400, 158, 428, 163 }, { 418, 168, 448, 170 }, { 396, 136, 420, 146 } } do
		c:stroke({ { s[1], s[2] }, { s[3], s[4] } }, { L(i == 4 and 1.2 or 2), L(1) }, line)
	end
	c:setGroup("split:yutaGlare")
	c:stroke({ { 380, 52 }, { 412, 50 }, { 446, 58 } }, { 14, 14, 10 }, skin)
	c:stroke({ { 378, 56 }, { 410, 54 }, { 446, 62 }, { 458, 74 } }, { L(13), L(12), L(8), L(3) }, line)
	c:setGroup(nil)
	-- far brow
	c:stroke({ { 372, 34 }, { 410, 28 }, { 448, 38 } }, { L(12), L(10), L(5) }, hair)

	-- nose / cheek line
	c:stroke({ { 467, 128 }, { 452, 180 }, { 418, 240 }, { 386, 284 } }, { L(1.2), L(2), L(2), L(1.2) }, line)

	-- 4. near brow (mostly under the hair) -----------------------------------------
	c:stroke({ { 575, 68 }, { 615, 42 }, { 700, 34 }, { 790, 38 } }, { L(3), L(24), L(30), L(30) }, hair)

	-- 5. hair ---------------------------------------------------------------------
	-- side lock along the left contour
	strand({ { 368, -14 }, { 370, 90 }, { 375, 190 }, { 381, 262 }, { 384, 292 } }, { 30, 28, 20, 8, 1 }, hair, 9)
	strand({ { 366, 20 }, { 368, 140 } }, { 3, 1 }, hairHi, 9)
	-- loose strands over the sky
	strand({ { 302, -14 }, { 264, 48 }, { 232, 104 }, { 201, 152 } }, { 11, 9, 6, 1 }, hair, 9)
	strand({ { 326, -14 }, { 304, 80 }, { 288, 170 }, { 272, 256 } }, { 13, 10, 7, 1 }, hair, 9)
	strand({ { 348, -14 }, { 352, 58 }, { 356, 110 }, { 352, 142 } }, { 26, 24, 16, 2 }, hair, 9)
	strand({ { 303, 4 }, { 268, 56 } }, { 2, 1 }, hairHi, 9)
	strand({ { 347, 6 }, { 350, 70 } }, { 3, 1 }, hairHi, 9)
	-- strands crossing the near eye
	strand({ { 791, -14 }, { 789, 80 }, { 785, 170 }, { 777, 222 } }, { 26, 22, 12, 1 }, hair, 9)
	strand({ { 813, -14 }, { 816, 80 }, { 821, 150 } }, { 14, 10, 1 }, hair, 9)
	strand({ { 790, 0 }, { 787, 110 } }, { 3, 1 }, hairHi, 9)
	-- right hair mass
	strand({ { 900, -14 }, { 905, 140 }, { 899, 262 } }, { 24, 18, 2 }, hair, 9)
	strand({ { 958, -14 }, { 972, 150 }, { 984, 292 } }, { 40, 30, 2 }, hair, 9)
	strand({ { 1030, -14 }, { 1046, 160 }, { 1052, 296 } }, { 52, 40, 4 }, hair, 9)
	strand({ { 1100, -14 }, { 1118, 200 }, { 1124, 296 } }, { 62, 50, 8 }, hair, 9)
	c:box(1140, -14, 1170, 296, hair)
	strand({ { 962, 0 }, { 975, 160 } }, { 3, 1 }, hairHi, 9)
	strand({ { 1040, 0 }, { 1054, 180 } }, { 4, 1 }, hairHi, 9)
	strand({ { 1108, 10 }, { 1124, 210 } }, { 4, 1 }, hairHi, 9)

	-- soft (cinematic) light: hair shadow from the top, falloff to the right
	if soft then
		local fade = function(a0: number, a1: number): NumberSequence
			return NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(1, a1) })
		end
		c:grad(384, -14, 1170, 120, { transparency = fade(0.45, 1), rotation = 90 }, deep)
		c:grad(700, -14, 1170, 301, { transparency = fade(1, 0.55), rotation = 0 }, deep)
		c:grad(384, 180, 700, 301, { transparency = fade(1, 0.75), rotation = 90 }, pal.skin)
	end
end

return YutaEyes

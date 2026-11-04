--!strict
-- Anime faces painted on the front of the 3D heads, with expression groups
-- the timeline switches on and off (eyes / brows / mouth variants).
-- Coordinates are "face units": x 0..100 across the face (viewer's left to
-- right), y down from the top edge of the head block.
local Paint = require(script.Parent.Parent.Parent.Paint)

local FaceRig = {}

-- expression presets: group lists per character
FaceRig.expr = {
	ryu = {
		neutral = { "ryu:eyes:normal", "ryu:brows:angry", "ryu:mouth:closed" },
		smirk = { "ryu:eyes:narrow", "ryu:brows:angry", "ryu:mouth:smirk" },
		grin = { "ryu:eyes:narrow", "ryu:brows:angry", "ryu:mouth:grin" },
		laugh = { "ryu:eyes:wide", "ryu:brows:raised", "ryu:mouth:laugh" },
		talk = { "ryu:eyes:normal", "ryu:brows:angry", "ryu:mouth:talk" },
		shout = { "ryu:eyes:wide", "ryu:brows:angry", "ryu:mouth:laugh" },
		glare = { "ryu:eyes:narrow", "ryu:brows:angry", "ryu:mouth:closed" },
		shock = { "ryu:eyes:wide", "ryu:brows:raised", "ryu:mouth:closed" },
		gasp = { "ryu:eyes:wide", "ryu:brows:raised", "ryu:mouth:talk" },
		grit = { "ryu:eyes:wide", "ryu:brows:angry", "ryu:mouth:grin" },
		strain = { "ryu:eyes:narrow", "ryu:brows:angry", "ryu:mouth:talk" },
		berserk = { "ryu:eyes:blank", "ryu:brows:angry", "ryu:mouth:grin" },
		growl = { "ryu:eyes:blank", "ryu:brows:angry", "ryu:mouth:talk" },
		hit = { "ryu:eyes:narrow", "ryu:brows:raised", "ryu:mouth:talk" },
		roar = { "ryu:eyes:blank", "ryu:brows:angry", "ryu:mouth:laugh" },
		heh = { "ryu:eyes:wide", "ryu:brows:angry", "ryu:mouth:laugh" },
	},
	yuta = {
		neutral = { "yuta:eyes:normal", "yuta:brows:calm", "yuta:mouth:closed" },
		focus = { "yuta:eyes:normal", "yuta:brows:tense", "yuta:mouth:closed" },
		talk = { "yuta:eyes:normal", "yuta:brows:tense", "yuta:mouth:talk" },
		shout = { "yuta:eyes:wide", "yuta:brows:tense", "yuta:mouth:open" },
		glare = { "yuta:eyes:normal", "yuta:brows:tense", "yuta:mouth:closed" },
		smirk = { "yuta:eyes:normal", "yuta:brows:calm", "yuta:mouth:smirk" },
		startle = { "yuta:eyes:wide", "yuta:brows:tense", "yuta:mouth:closed" },
		gasp = { "yuta:eyes:wide", "yuta:brows:tense", "yuta:mouth:talk" },
		-- part 3: doubled over, the eyes lost in the shadow of the fringe,
		-- teeth clenched; then the eyes fly open
		shadow = { "yuta:eyes:shadow", "yuta:mouth:grit" },
		grit = { "yuta:eyes:wide", "yuta:brows:tense", "yuta:mouth:grit" },
		cold = { "yuta:eyes:normal", "yuta:brows:tense", "yuta:mouth:closed" },
	},
}

-- Ryu: sharp narrow eyes, heavy angled brows, wide grin / laugh
function FaceRig.ryu(c: Paint.Canvas, pal: { [string]: Color3 })
	local line, deep = pal.line, pal.rSkinDeep
	local white, teeth = pal.sclera, Color3.fromRGB(240, 238, 232)
	local mouthIn, tongue = Color3.fromRGB(58, 22, 30), Color3.fromRGB(150, 60, 70)

	-- base: cheekbone shading, laugh lines, nose (always visible)
	c:setGroup(nil)
	c:stroke({ { 52, 52 }, { 53, 62 }, { 55, 68 } }, { 0.6, 1.3, 1.1 }, line)
	c:stroke({ { 46, 70 }, { 50, 71.5 }, { 57, 70 } }, { 0.8, 1.4, 0.8 }, line)
	c:stroke({ { 38, 64 }, { 33, 74 }, { 30, 84 } }, { 0.5, 1.2, 0.5 }, deep)
	c:stroke({ { 64, 64 }, { 69, 74 }, { 72, 84 } }, { 0.5, 1.2, 0.5 }, deep)
	c:stroke({ { 40, 98 }, { 50, 100 }, { 60, 98 } }, { 0.5, 1.1, 0.5 }, deep)

	local function eye(cx: number, dir: number, h: number, g: string)
		c:setGroup(g)
		-- dir = -1 for the viewer's left eye (character's right), +1 for the other
		local inner, outer = cx + dir * -10, cx + dir * 11
		c:stroke({ { inner, 50 }, { cx, 50 + h * 0.1 }, { outer, 48 } }, { h * 0.6, h, h * 0.4 }, white)
		c:ellipse(cx - dir * 1.5, 50.5, 4.2, math.min(4.6, h * 0.55), 0, pal.rIrisDark)
		c:ellipse(cx - dir * 1.5, 51.2, 3.0, math.min(3.4, h * 0.42), 0, pal.rIris)
		c:circle(cx - dir * 1.5, 50.5, 1.4, pal.rIrisDark)
		c:circle(cx - dir * 0.3, 49.4, 0.8, white)
		-- heavy upper lid with an upturned outer flick, thin lower lid
		local top = 50 - h * 0.5
		c:stroke({ { inner + dir * -1, top + 1.5 }, { cx, top - 0.5 }, { outer + dir * 1.5, top - 1.8 } }, { 1.6, 2.6, 1.2 }, line)
		c:stroke({ { inner, 50.5 }, { cx, 50 + h * 0.5 }, { outer, 49 } }, { 0.4, 0.9, 0.4 }, line)
	end
	for _, v in { { name = "normal", h = 7.5 }, { name = "narrow", h = 5 }, { name = "wide", h = 10 } } do
		local g = "ryu:eyes:" .. v.name
		eye(30, -1, v.h, g)
		eye(70, 1, v.h, g)
	end
	-- berserk: wide white eyes with no irises (part 3)
	c:setGroup("ryu:eyes:blank")
	for _, e in { { cx = 30, dir = -1 }, { cx = 70, dir = 1 } } do
		local inner, outer = e.cx + e.dir * -10, e.cx + e.dir * 11
		c:stroke({ { inner, 50 }, { e.cx, 51 }, { outer, 48 } }, { 6, 10, 4 }, white)
		c:stroke({ { inner + e.dir * -1, 46.5 }, { e.cx, 44.5 }, { outer + e.dir * 1.5, 43.2 } }, { 1.6, 2.6, 1.2 }, line)
		c:stroke({ { inner, 50.5 }, { e.cx, 55 }, { outer, 49 } }, { 0.4, 0.9, 0.4 }, line)
	end

	-- brows
	c:setGroup("ryu:brows:angry")
	c:stroke({ { 45, 43 }, { 32, 37 }, { 15, 33 } }, { 4.5, 4, 2 }, pal.rHair)
	c:stroke({ { 55, 43 }, { 68, 37 }, { 85, 33 } }, { 4.5, 4, 2 }, pal.rHair)
	c:stroke({ { 47, 42 }, { 49, 47 } }, { 1, 0.6 }, deep)
	c:stroke({ { 53, 42 }, { 51, 47 } }, { 1, 0.6 }, deep)
	c:setGroup("ryu:brows:raised")
	c:stroke({ { 45, 38 }, { 32, 33 }, { 15, 34 } }, { 4, 4, 2 }, pal.rHair)
	c:stroke({ { 55, 38 }, { 68, 33 }, { 85, 34 } }, { 4, 4, 2 }, pal.rHair)

	-- mouths
	c:setGroup("ryu:mouth:closed")
	c:stroke({ { 38, 84 }, { 50, 85 }, { 62, 83.5 } }, { 0.8, 1.5, 0.8 }, line)
	c:setGroup("ryu:mouth:smirk")
	c:stroke({ { 38, 85 }, { 50, 85 }, { 63, 81 } }, { 0.8, 1.5, 0.6 }, line)
	c:stroke({ { 63, 81 }, { 65, 79 } }, { 0.8, 0.4 }, line)
	c:setGroup("ryu:mouth:grin")
	-- wide grin of clenched teeth
	c:stroke({ { 31, 80 }, { 40, 85 }, { 50, 86.5 }, { 60, 85 }, { 69, 80 } }, { 2, 6, 7, 6, 2 }, teeth)
	c:stroke({ { 31, 80 }, { 40, 82.4 }, { 50, 83.4 }, { 60, 82.4 }, { 69, 80 } }, { 0.8, 1.2, 1.2, 1.2, 0.8 }, line)
	c:stroke({ { 31, 80 }, { 40, 88.2 }, { 50, 89.8 }, { 60, 88.2 }, { 69, 80 } }, { 0.8, 1.4, 1.6, 1.4, 0.8 }, line)
	c:stroke({ { 34, 83 }, { 50, 86.4 }, { 66, 83 } }, { 0.3, 0.7, 0.3 }, deep)
	for i = -3, 3 do
		local x = 50 + i * 4.6
		local y = 83.6 + (1 - (i / 4) ^ 2) * 2.2
		c:stroke({ { x, y - 2.4 }, { x, y + 2.6 } }, { 0.5, 0.5 }, deep)
	end
	c:stroke({ { 29, 78 }, { 31, 80 } }, { 0.5, 1 }, line)
	c:stroke({ { 71, 78 }, { 69, 80 } }, { 0.5, 1 }, line)
	c:setGroup("ryu:mouth:laugh")
	-- big open laugh: dark mouth, upper and lower teeth, tongue
	c:stroke({ { 33, 80 }, { 42, 88 }, { 50, 91 }, { 58, 88 }, { 67, 80 } }, { 3, 12, 15, 12, 3 }, mouthIn)
	c:ellipse(50, 92, 8, 3.4, 0, tongue)
	c:stroke({ { 35, 79.5 }, { 42, 81.6 }, { 50, 82.2 }, { 58, 81.6 }, { 65, 79.5 } }, { 1.5, 3.2, 3.6, 3.2, 1.5 }, teeth)
	c:stroke({ { 41, 95.2 }, { 50, 96.2 }, { 59, 95.2 } }, { 1.2, 2.4, 1.2 }, teeth)
	c:stroke({ { 33, 80 }, { 42, 80.2 }, { 50, 80.3 }, { 58, 80.2 }, { 67, 80 } }, { 1, 1.3, 1.3, 1.3, 1 }, line)
	c:stroke({ { 33, 80 }, { 40, 92 }, { 50, 98 }, { 60, 92 }, { 67, 80 } }, { 1, 1.6, 1.8, 1.6, 1 }, line)
	c:stroke({ { 31, 77 }, { 33, 80 } }, { 0.5, 1 }, line)
	c:stroke({ { 69, 77 }, { 67, 80 } }, { 0.5, 1 }, line)
	c:setGroup("ryu:mouth:talk")
	c:stroke({ { 39, 83 }, { 45, 87 }, { 50, 88 }, { 55, 87 }, { 61, 83 } }, { 2, 6, 7, 6, 2 }, mouthIn)
	c:stroke({ { 40, 82.4 }, { 50, 83.6 }, { 60, 82.4 } }, { 1.2, 2.4, 1.2 }, teeth)
	c:stroke({ { 39, 83 }, { 50, 82.6 }, { 61, 83 } }, { 0.9, 1.2, 0.9 }, line)
	c:stroke({ { 39, 83 }, { 50, 91.5 }, { 61, 83 } }, { 0.9, 1.4, 0.9 }, line)

	-- part 3: his face running with blood: a patch on the forehead, a smear
	-- across the eyes, streams down over the nose to the mouth, drips
	c:setGroup("ryu:blood")
	local blood, bloodDark = Color3.fromRGB(150, 18, 26), Color3.fromRGB(96, 8, 16)
	c:stroke({ { 36, 20 }, { 46, 26 }, { 52, 34 } }, { 5, 8, 5 }, blood)
	c:stroke({ { 20, 47 }, { 34, 45 }, { 48, 48 }, { 58, 46 } }, { 2, 4.5, 4, 1.5 }, blood)
	c:stroke({ { 50, 30 }, { 48, 44 }, { 47, 58 }, { 45, 70 }, { 42, 80 } }, { 3, 3.6, 3, 2.4, 1.6 }, blood)
	c:stroke({ { 53, 36 }, { 55, 52 }, { 57, 66 }, { 58, 78 } }, { 2, 2.4, 2, 1.2 }, blood)
	c:stroke({ { 40, 46 }, { 38, 58 }, { 37, 66 } }, { 1.6, 1.4, 0.6 }, blood)
	c:stroke({ { 47, 34 }, { 47.5, 48 }, { 46, 62 } }, { 0.6, 0.9, 0.5 }, bloodDark)
	c:stroke({ { 36, 84 }, { 34, 92 }, { 35, 99 } }, { 1.6, 1.2, 0.5 }, blood)
	c:stroke({ { 64, 84 }, { 65, 91 } }, { 1.4, 0.6 }, blood)
	c:circle(60, 74, 1.1, blood)
	c:circle(26, 58, 0.9, blood)
	c:setGroup(nil)
end

-- Yuta: big tired eyes (bags), thin brows, small mouth
function FaceRig.yuta(c: Paint.Canvas, pal: { [string]: Color3 })
	local line, deep = pal.line, pal.skinDeep
	local white = pal.sclera
	c:setGroup(nil)
	c:stroke({ { 50, 54 }, { 51, 64 }, { 53, 69 } }, { 0.5, 1.0, 0.8 }, line)
	c:stroke({ { 47, 71 }, { 52, 71.6 } }, { 0.6, 0.9 }, line)

	local function eye(cx: number, dir: number, h: number, g: string)
		c:setGroup(g)
		local inner, outer = cx + dir * -10, cx + dir * 11
		c:stroke({ { inner, 51 }, { cx, 50.5 }, { outer, 49.5 } }, { h * 0.7, h, h * 0.55 }, white)
		c:stroke({ { inner + dir * -1, 47 }, { cx, 45.5 }, { outer, 47 } }, { h * 0.3, h * 0.35, h * 0.2 }, pal.scleraShade)
		c:ellipse(cx - dir * 1, 51, 5.4, math.min(6.6, h * 0.62), 0, pal.yIrisDark)
		c:ellipse(cx - dir * 1, 51.8, 4.3, math.min(5.4, h * 0.5), 0, pal.yIris)
		c:ellipse(cx - dir * 1, 53.6, 3, math.min(2.8, h * 0.28), 0, pal.yIrisLight)
		c:circle(cx - dir * 1, 50.6, 1.8, pal.yIrisDark)
		c:circle(cx + dir * 0.6, 49, 1.3, white)
		c:circle(cx - dir * 2.6, 54, 0.6, white)
		local top = 51 - h * 0.55
		c:stroke({ { inner + dir * -1, top + 2 }, { cx, top }, { outer + dir * 1, top + 1.2 } }, { 1.8, 2.6, 1.4 }, line)
		c:stroke({ { outer, top + 1.2 }, { outer + dir * 2.5, top + 0.5 } }, { 1, 0.4 }, line)
		c:stroke({ { inner, 51.5 }, { cx, 51 + h * 0.5 }, { outer, 50 } }, { 0.3, 0.8, 0.3 }, line)
		-- tired bags under the eyes
		c:stroke({ { inner + dir * 1, 55 + h * 0.3 }, { cx, 56 + h * 0.45 }, { outer - dir * 1, 54 + h * 0.3 } }, { 0.3, 0.7, 0.3 }, deep)
		c:stroke({ { inner + dir * 2, 57.5 + h * 0.35 }, { cx, 58.5 + h * 0.5 }, { outer - dir * 2, 56.5 + h * 0.35 } }, { 0.2, 0.5, 0.2 }, deep)
	end
	for _, v in { { name = "normal", h = 10.5 }, { name = "wide", h = 13 } } do
		local g = "yuta:eyes:" .. v.name
		eye(30, -1, v.h, g)
		eye(70, 1, v.h, g)
	end
	c:setGroup("yuta:brows:calm")
	c:stroke({ { 42, 39 }, { 31, 36.5 }, { 19, 38 } }, { 2.2, 2.4, 1 }, pal.yHair)
	c:stroke({ { 58, 39 }, { 69, 36.5 }, { 81, 38 } }, { 2.2, 2.4, 1 }, pal.yHair)
	c:setGroup("yuta:brows:tense")
	c:stroke({ { 43, 41 }, { 31, 37 }, { 18, 36.5 } }, { 2.6, 2.6, 1 }, pal.yHair)
	c:stroke({ { 57, 41 }, { 69, 37 }, { 82, 36.5 } }, { 2.6, 2.6, 1 }, pal.yHair)
	c:setGroup("yuta:mouth:closed")
	c:stroke({ { 43, 82 }, { 50, 82.6 }, { 57, 81.8 } }, { 0.6, 1.1, 0.6 }, line)
	c:setGroup("yuta:mouth:talk")
	c:stroke({ { 44, 81.5 }, { 50, 84.5 }, { 56, 81.5 } }, { 1.5, 3.5, 1.5 }, Color3.fromRGB(70, 30, 38))
	c:stroke({ { 44, 81.5 }, { 50, 81.8 }, { 56, 81.5 } }, { 0.6, 0.9, 0.6 }, line)
	c:setGroup("yuta:mouth:open")
	c:stroke({ { 42, 81 }, { 50, 86 }, { 58, 81 } }, { 2.5, 6, 2.5 }, Color3.fromRGB(70, 30, 38))
	c:stroke({ { 43, 80.6 }, { 50, 81.3 }, { 57, 80.6 } }, { 1, 1.6, 1 }, Color3.fromRGB(240, 238, 232))
	c:stroke({ { 42, 81 }, { 50, 80.8 }, { 58, 81 } }, { 0.6, 0.9, 0.6 }, line)
	-- a cool half-smile: the left corner (screen right) lifts
	c:setGroup("yuta:mouth:smirk")
	c:stroke({ { 43, 82.4 }, { 50, 82.6 }, { 56, 81.2 }, { 59, 79.6 } }, { 0.6, 1.1, 1.0, 0.4 }, line)
	c:stroke({ { 57.5, 80.4 }, { 59.4, 81.6 } }, { 0.5, 0.3 }, deep)

	-- part 3 -----------------------------------------------------------------
	-- the eyes lost in the black shadow of the fringe (head bowed)
	c:setGroup("yuta:eyes:shadow")
	local shade = Color3.fromRGB(26, 24, 34)
	c:stroke({ { 10, 44 }, { 30, 47 }, { 50, 50 }, { 70, 47 }, { 90, 44 } }, { 10, 15, 13, 15, 10 }, shade)
	c:stroke({ { 14, 56 }, { 30, 58 }, { 46, 57 } }, { 1, 2.4, 1 }, shade)
	c:stroke({ { 54, 57 }, { 70, 58 }, { 86, 56 } }, { 1, 2.4, 1 }, shade)
	-- clenched teeth, bared
	c:setGroup("yuta:mouth:grit")
	local teeth = Color3.fromRGB(240, 238, 232)
	c:stroke({ { 38, 80 }, { 44, 82.4 }, { 50, 83 }, { 56, 82.4 }, { 62, 80 } }, { 1.5, 4, 4.6, 4, 1.5 }, teeth)
	c:stroke({ { 38, 80 }, { 44, 80.4 }, { 50, 80.6 }, { 56, 80.4 }, { 62, 80 } }, { 0.7, 1, 1, 1, 0.7 }, line)
	c:stroke({ { 38, 80 }, { 44, 84.6 }, { 50, 85.4 }, { 56, 84.6 }, { 62, 80 } }, { 0.7, 1, 1.1, 1, 0.7 }, line)
	c:stroke({ { 40, 82 }, { 50, 82.9 }, { 60, 82 } }, { 0.3, 0.5, 0.3 }, deep)
	for i = -2, 2 do
		local x = 50 + i * 4.2
		c:stroke({ { x, 81 }, { x, 84.6 } }, { 0.4, 0.4 }, deep)
	end
	-- blood running from the corners of the mouth down the chin
	c:setGroup("yuta:blood")
	local blood = Color3.fromRGB(156, 20, 28)
	c:stroke({ { 40, 82 }, { 39, 89 }, { 40, 96 }, { 39, 100 } }, { 2, 2.2, 1.4, 0.5 }, blood)
	c:stroke({ { 46, 84 }, { 46, 90 }, { 47, 95 } }, { 1.4, 1.2, 0.4 }, blood)
	c:stroke({ { 58, 82 }, { 59, 90 }, { 58, 97 } }, { 1.8, 1.6, 0.5 }, blood)
	c:circle(52, 92, 0.9, blood)
	c:circle(35, 88, 0.7, blood)
	c:setGroup(nil)
end

return FaceRig

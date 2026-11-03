--!strict
-- Ryu, extreme close-up of the eyes (lower half of the split screen).
-- Face turned 3/4 to the right, glaring at Yuta: heavy brows, veins and
-- wrinkles on the nose bridge, narrow eyes.
local Paint = require(script.Parent.Parent.Parent.Paint)

local RyuEyes = {}

RyuEyes.X0 = -70
RyuEyes.X1 = 820
RyuEyes.Y0 = 301
RyuEyes.Y1 = 642

function RyuEyes.paint(c: Paint.Canvas, pal: { [string]: Color3 }, lw: number, soft: boolean?)
	local skin, shade, deep = pal.rSkin, pal.rSkinShade, pal.rSkinDeep
	local line, hair = pal.line, pal.rHair
	local function L(w: number): number
		return w * lw
	end
	local top = 302

	-- 1. skin base + right contour (against the sky) ------------------------------
	c:box(-70, top, 640, 642, skin)
	local contour = { { 700, 398 }, { 703, 443 }, { 694, 483 }, { 680, 523 }, { 663, 561 }, { 652, 600 }, { 645, 645 } }
	c:edge(contour, 72, -1, skin)
	-- forehead above the far eye: stair-stepped boxes hidden under the brow band
	local function bandX(y: number): number
		return 785 - (y - 309) * (152 / 117)
	end
	local y = top
	while y < 426 do
		c:box(600, y, bandX(y + 12) + 10, y + 12.5, skin)
		y += 12
	end

	-- 2. shading -------------------------------------------------------------------
	-- upper-left of the face is in shadow (under the brow and hair)
	c:box(-70, top, 452, 492, shade)
	c:box(-70, 492, 92, 642, shade)
	-- lit forehead patches between the hair strands
	c:poly({ { 230, 336 }, { 256, 306 }, { 304, 306 }, { 286, 338 } }, skin, shade)
	c:poly({ { 316, 352 }, { 346, 306 }, { 392, 306 }, { 372, 352 } }, skin, shade)
	-- lit cheek below the eye
	c:poly({ { 138, 420 }, { 250, 452 }, { 452, 466 }, { 452, 642 }, { 150, 642 }, { 92, 566 }, { 92, 512 } }, skin, shade)
	-- lit nose bridge (also cleans the cut spill of the cheek)
	c:box(452, top, 600, 642, skin)
	-- shadow at the inner corner of the near eye / side of the nose
	c:poly({ { 405, 500 }, { 452, 470 }, { 478, 520 }, { 470, 586 }, { 430, 560 } }, shade, skin)
	-- veins and wrinkle shadows on the nose bridge
	for _, s in
		{
			{ { 548, 320 }, { 560, 352 }, { 566, 392 }, { 560, 420 } },
			{ { 588, 312 }, { 592, 340 }, { 600, 360 } },
			{ { 520, 440 }, { 548, 452 }, { 580, 448 } },
			{ { 506, 474 }, { 540, 480 }, { 572, 470 } },
			{ { 512, 506 }, { 540, 510 } },
			{ { 470, 520 }, { 492, 548 }, { 498, 580 } },
		}
	do
		local ws = {}
		for i = 1, #s do
			ws[i] = if i == 1 or i == #s then 2 else 7
		end
		c:stroke(s, ws, shade)
	end

	-- 3. near eye (screen left) ----------------------------------------------------
	c:stroke({ { 215, 505 }, { 258, 516 }, { 320, 512 }, { 382, 500 }, { 425, 489 }, { 446, 480 } }, { 16, 62, 80, 80, 50, 14 }, pal.sclera)
	c:stroke({ { 250, 488 }, { 320, 476 }, { 390, 466 }, { 436, 470 } }, { 14, 16, 16, 10 }, pal.scleraShade)
	c:stroke({ { 380, 488 }, { 420, 486 }, { 440, 482 } }, { 40, 30, 10 }, pal.scleraShade)
	-- iris (top part hidden under the lid)
	c:ellipse(341, 486, 33, 30, 0, pal.rIrisDark)
	c:ellipse(342, 488, 27, 25, 0, pal.rIris)
	c:ellipse(344, 500, 18, 12, 0, pal.rIrisLight)
	c:ellipse(342, 494, 15, 8, 0, pal.rIris)
	c:ellipse(343, 480, 12, 12, 0, pal.rIrisDark)
	c:ellipse(322, 497, 9, 4, -12, pal.sclera)
	c:circle(357, 507, 2.5, pal.sclera)
	-- upper lid: carve the iris top with shadow, then the thick lid line
	c:stroke({ { 200, 482 }, { 280, 462 }, { 340, 452 }, { 410, 440 }, { 452, 448 } }, { 18, 24, 26, 24, 14 }, shade)
	c:stroke(
		{ { 160, 494 }, { 205, 486 }, { 243, 478 }, { 321, 466 }, { 380, 457 }, { 420, 452 }, { 452, 461 } },
		{ L(1), L(6), L(11), L(13), L(14), L(13), L(6) },
		line
	)
	-- lashes at the inner end and the outer flick
	for _, s in { { 432, 452, 446, 440 }, { 440, 455, 458, 448 }, { 446, 460, 466, 460 } } do
		c:stroke({ { s[1], s[2] }, { s[3], s[4] } }, { L(4), L(1) }, line)
	end
	c:stroke({ { 168, 494 }, { 150, 498 }, { 138, 499 } }, { L(4), L(2), L(0.6) }, line)
	-- crease above the lid
	c:stroke({ { 166, 470 }, { 277, 448 }, { 421, 430 }, { 452, 439 } }, { L(0.8), L(2), L(2), L(0.8) }, deep)
	-- lower lid, lashes and bags
	c:stroke({ { 199, 507 }, { 230, 532 }, { 258, 548 }, { 321, 553 }, { 390, 538 }, { 430, 514 } }, { L(1), L(2.4), L(2.6), L(2.8), L(2.4), L(1) }, line)
	for i = 0, 7 do
		local x = 222 + i * 26
		local yy = 545 + math.sin(i / 7 * math.pi) * 9
		c:stroke({ { x, yy }, { x - 3, yy + 11 } }, { L(1.8), L(0.8) }, line)
	end
	c:stroke({ { 212, 548 }, { 260, 568 }, { 330, 572 }, { 400, 558 }, { 440, 540 } }, { L(0.6), L(1.8), L(2), L(1.8), L(0.6) }, deep)
	c:stroke({ { 190, 528 }, { 206, 548 } }, { L(1.4), L(0.6) }, line)

	-- 4. far eye (screen right, under the brow band) --------------------------------
	c:stroke({ { 626, 446 }, { 655, 450 }, { 684, 446 } }, { 30, 44, 34 }, pal.sclera)
	c:stroke({ { 622, 432 }, { 660, 428 }, { 690, 430 } }, { 12, 14, 10 }, pal.scleraShade)
	c:ellipse(655, 437, 15, 13, 0, pal.rIrisDark)
	c:ellipse(656, 438, 11, 10, 0, pal.rIris)
	c:ellipse(657, 444, 7, 4, 0, pal.rIrisLight)
	c:ellipse(670, 428, 7, 3, -20, pal.sclera)
	c:stroke({ { 616, 470 }, { 640, 474 }, { 672, 470 }, { 698, 452 } }, { L(1), L(2.4), L(2.4), L(1) }, line)
	for _, s in { { 626, 478, 640, 482 }, { 650, 480, 668, 478 } } do
		c:stroke({ { s[1], s[2] }, { s[3], s[4] } }, { L(1.6), L(0.6) }, line)
	end

	-- 5. brows ------------------------------------------------------------------------
	-- far brow + upper lid of the far eye: one heavy band along the face edge
	c:stroke({ { 612, 440 }, { 633, 424 }, { 700, 372 }, { 790, 306 } }, { L(10), L(20), L(26), L(28) }, line)
	-- near brow: thick, angled down to the nose, hooked end
	c:stroke({ { 118, 370 }, { 230, 352 }, { 364, 374 }, { 478, 410 }, { 540, 424 }, { 560, 436 } }, { L(2), L(22), L(36), L(38), L(30), L(10) }, hair)
	c:stroke({ { 520, 430 }, { 548, 440 }, { 566, 452 } }, { L(14), L(10), L(3) }, hair)
	c:stroke({ { 250, 345 }, { 364, 356 }, { 450, 386 } }, { L(1), L(3), L(1) }, hair)

	-- 6. hair strands crossing the forehead -------------------------------------------
	c:stroke({ { 303, 307 }, { 284, 334 }, { 252, 380 }, { 203, 440 } }, { 12, 12, 9, 1 }, hair)
	c:stroke({ { 84, 372 }, { 190, 343 }, { 262, 318 }, { 300, 307 } }, { 1, 6, 9, 10 }, hair)
	c:stroke({ { 410, 307 }, { 396, 330 }, { 366, 356 } }, { 10, 7, 1 }, hair)
	c:stroke({ { 470, 307 }, { 456, 322 } }, { 6, 1 }, hair)
	c:stroke({ { 722, 307 }, { 736, 340 }, { 742, 372 } }, { 10, 8, 1 }, hair)

	-- 7. wrinkles, nose, contour lines ---------------------------------------------------
	for _, s in
		{
			{ { 546, 330 }, { 556, 360 }, { 563, 404 } },
			{ { 568, 309 }, { 581, 352 } },
			{ { 612, 330 }, { 604, 360 }, { 606, 384 } },
			{ { 518, 446 }, { 550, 456 }, { 584, 452 } },
			{ { 500, 480 }, { 536, 486 }, { 572, 476 } },
			{ { 508, 512 }, { 536, 515 } },
			{ { 486, 400 }, { 500, 430 } },
		}
	do
		local ws = {}
		for i = 1, #s do
			ws[i] = if i == 1 or i == #s then L(0.8) else L(2.2)
		end
		c:stroke(s, ws, line)
	end
	-- deep frown creases (shadow shapes + lines) between the brows
	for _, s2 in
		{
			{ { 566, 410 }, { 584, 430 }, { 590, 462 } },
			{ { 596, 404 }, { 610, 428 }, { 612, 452 } },
			{ { 548, 470 }, { 566, 492 }, { 572, 520 } },
		}
	do
		c:stroke(s2, { L(3), L(7), L(2) }, shade)
		c:stroke(s2, { L(0.6), L(2), L(0.6) }, line)
	end
	-- nose line
	c:stroke({ { 529, 530 }, { 563, 561 }, { 586, 600 } }, { L(1), L(2.4), L(1) }, line)
	-- contour line
	c:stroke({ { 698, 404 }, { 702, 443 }, { 693, 483 }, { 679, 523 }, { 662, 561 }, { 651, 600 }, { 645, 642 } }, { L(1), L(2.2), L(2.4), L(2.4), L(2.2), L(2), L(2) }, line)
	-- cheek hatching
	for i = 0, 5 do
		local x = 610 + i * 9
		c:stroke({ { x, 500 + i * 6 }, { x + 10, 492 + i * 6 } }, { L(1.4), L(0.6) }, deep)
	end
	for i = 0, 3 do
		local x = 150 + i * 12
		c:stroke({ { x, 600 + i * 4 }, { x + 14, 590 + i * 4 } }, { L(1.4), L(0.6) }, deep)
	end

	-- soft (cinematic) light: brow shadow from the top, falloff to the left
	if soft then
		local fade = function(a0: number, a1: number): NumberSequence
			return NumberSequence.new({ NumberSequenceKeypoint.new(0, a0), NumberSequenceKeypoint.new(1, a1) })
		end
		c:grad(-70, top, 640, 440, { transparency = fade(0.4, 1), rotation = 90 }, deep)
		c:grad(-70, top, 300, 642, { transparency = fade(0.5, 1), rotation = 0 }, deep)
		-- same top shadow over the forehead steps right of x = 640 (ends under the brow band)
		local yy = top
		while yy < 426 do
			local a0 = 0.4 + 0.6 * math.clamp((yy - top) / (440 - top), 0, 1)
			local a1 = 0.4 + 0.6 * math.clamp((yy + 12 - top) / (440 - top), 0, 1)
			c:grad(640, yy, bandX(yy + 12) + 10, yy + 12, { transparency = fade(a0, a1), rotation = 90 }, deep)
			yy += 12
		end
	end
end

return RyuEyes

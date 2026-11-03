--!strict
-- Part 2 ("Yuta vs. Ryu end fight scene pt. 2", 59.17 s). The first 5.27 s
-- replay the end of part 1 (see Scene.build); the new shots start at 5.267:
--   5.27-20.30  P2/Blast      the Granite Blast swallows Yuta, he folds space
--  20.30-31.30  P2/Realize    Ryu works out Yuta's technique (Copy)
--  31.30-38.70  P2/Flashback  the fight with Uro on the rooftops, Ryu's eye
--  38.70-42.90  P2/Realize    the blast flies off, red light on Ryu
--  42.90-45.80  P2/Flashback  Rika ate Uro's arm; "Thin Ice Breaker!"
--  45.80-59.17  P2/Grapple    grapple, Rika's bite, the palm, the countdown
-- Cut times were read off the reference frame by frame (30 fps).
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local CloseupSet = require(script.Parent.Parent.Art.Sets.CloseupSet)
local Common = require(script.Parent.P2.Common)
local Overlay2 = require(script.Parent.P2.Overlay2)
local Blast = require(script.Parent.P2.Blast)
local Realize = require(script.Parent.P2.Realize)
local Flashback = require(script.Parent.P2.Flashback)
local Grapple = require(script.Parent.P2.Grapple)

local Part2 = {}

function Part2.build(scene: Builder.Scene)
	Overlay2.build(scene)
	CloseupSet.build(scene) -- Ryu's eyes in close-up reuse the painted panel
	Common.build(scene)
end

local shots: { Timeline.Shot } = {}
for _, m in { Blast.shots, Realize.shots, Flashback.shots, Grapple.shots } do
	for _, s in m do
		table.insert(shots, s)
	end
end
Part2.shots = shots

return Part2

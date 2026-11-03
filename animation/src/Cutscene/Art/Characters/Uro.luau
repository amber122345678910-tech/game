--!strict
-- Uro Takako (part 2 flashback only, never seen closer than a medium shot):
-- slim, very long straight pink hair, white top with a dark collar ribbon,
-- black shorts, long legs, white boots. R15 skeleton, face painted on.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Paint = require(script.Parent.Parent.Parent.Paint)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Uro = {}

Uro.dims = {
	hip = 2.4,
	hipX = 0.36,
	waist = 0.45,
	neck = 1.26,
	shoulderY = 1.1,
	shoulderX = 0.78,
	upperArm = 0.96,
	lowerArm = 0.88,
	upperLeg = 1.16,
	lowerLeg = 1.12,
}

local PINK = Color3.fromRGB(246, 150, 196)
local PINK_DARK = Color3.fromRGB(205, 104, 158)
local WHITE = Color3.fromRGB(236, 238, 244)
local BLACK = Color3.fromRGB(26, 26, 32)

function Uro.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Uro.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)
	local pal = scene.style.color

	-- hips: black shorts
	k.addColor("LowerTorso", "Block", V(1.26, 0.62, 0.78), C(0, 0.1, 0), BLACK, "cloth", "Shorts")
	-- torso: white top, dark collar ribbon
	k.addColor("UpperTorso", "Block", V(1.3, 1.26, 0.78), C(0, 0.62, 0), WHITE, "cloth", "Top")
	k.addColor("UpperTorso", "Block", V(1.34, 0.2, 0.82), C(0, 1.2, 0), BLACK, "cloth", "Collar")
	k.addColor("UpperTorso", "Block", V(0.18, 0.34, 0.06), C(0, 1.0, -0.42) * R(0, 0, 10), BLACK, "cloth", "Ribbon")
	k.addColor("UpperTorso", "Block", V(0.32, 0.34, 0.3), C(0, 1.34, 0), pal.skin, "skin", "Neck")

	-- head with a simple painted face
	local face = Paint.canvas(4.0, 0, 0)
	for _, sx in { -1, 1 } do
		local cx = 50 + sx * 18
		face:ellipse(cx, 52, 6.5, 7.5, 0, Color3.fromRGB(250, 250, 252))
		face:ellipse(cx - sx * 0.8, 53, 4.6, 6.2, 0, Color3.fromRGB(176, 70, 120))
		face:circle(cx - sx * 0.8, 53, 2.2, Color3.fromRGB(60, 20, 40))
		face:circle(cx + sx * 1.6, 50, 1.3, Color3.fromRGB(255, 255, 255))
		face:stroke({ { cx - 8, 46 }, { cx, 44.2 }, { cx + 8, 46 } }, { 1.6, 2.4, 1.2 }, pal.line)
		face:stroke({ { cx - 7, 38 }, { cx, 37 }, { cx + 7, 38.5 } }, { 0.8, 1.2, 0.6 }, PINK_DARK)
	end
	face:stroke({ { 46, 78 }, { 50, 79 }, { 54, 78 } }, { 0.6, 1, 0.6 }, Color3.fromRGB(150, 60, 80))
	Builder.part(scene, rigName, V(0.92, 1.0, 0.92), C(0, 0.6, 0), pal.skin, {
		shape = "Block",
		material = scene.style.material.skin,
		rig = rigName,
		bone = "Head",
		name = "Head",
		gui = { face = "Front", canvas = Vector2.new(400, 432), lightInfluence = scene.style.face.lightInfluence, elems = face.elems },
	})
	-- hair: a rounded cap, a straight fringe and very long hair down the back
	k.addColor("Head", "Ellipsoid", V(1.08, 0.66, 1.1), C(0, 1.08, 0.04), PINK, "hair", "HairTop")
	k.addColor("Head", "Block", V(0.96, 0.22, 0.12), C(0, 0.94, -0.48), PINK, "hair", "Fringe")
	for _, sx in { -1, 1 } do
		k.addColor("Head", "Block", V(0.16, 1.2, 0.5), C(sx * 0.5, 0.44, -0.18), PINK, "hair", "SideHair")
	end
	-- the long hair falls in three tapering sections that trail behind her
	local cf = C(0, 0.9, 0.42)
	for i, seg in { { 1.0, 1.0, 0.36 }, { 1.4, 0.9, 0.3 }, { 1.4, 0.7, 0.22 } } do
		local len, w, d = seg[1], seg[2], seg[3]
		Builder.flex(k.addColor("Head", "Ellipsoid", V(w, len * 1.15, d), cf * C(0, -len / 2, 0), if i == 2 then PINK_DARK else PINK, "hair", "LongHair"), 3 + i * 3, V(0, len / 2, 0))
		cf = cf * C(0, -len, 0) * R(-10, 0, 0)
	end

	-- arms
	for _, side in { "Left", "Right" } do
		k.addColor(side .. "UpperArm", "Block", V(0.4, 0.96, 0.42), C(0, -0.42, 0), WHITE, "cloth")
		k.addColor(side .. "LowerArm", "Block", V(0.34, 0.86, 0.36), C(0, -0.4, 0), pal.skin, "skin")
		k.addColor(side .. "Hand", "Block", V(0.3, 0.42, 0.18), C(0, -0.22, 0), pal.skin, "skin", "Hand")
	end
	-- legs: long, white boots up to the knee
	for _, side in { "Left", "Right" } do
		k.addColor(side .. "UpperLeg", "Block", V(0.46, 1.16, 0.5), C(0, -0.56, 0), pal.skin, "skin")
		k.addColor(side .. "LowerLeg", "Block", V(0.44, 1.12, 0.48), C(0, -0.55, 0), WHITE, "cloth", "Boot")
		k.addColor(side .. "Foot", "Block", V(0.44, 0.24, 0.84), C(0, -0.04, -0.14), WHITE, "cloth", "BootFoot")
	end
	return def
end

Uro.poses = {
	-- flying kick: one leg out, arms back, hair streaming
	kick = {
		LowerTorso = R(-20, 0, 0),
		UpperTorso = R(10, 0, 0),
		Head = R(10, 0, 0),
		LeftUpperArm = R(-40, 0, -30),
		LeftLowerArm = R(30, 0, 0),
		RightUpperArm = R(-30, 0, 40),
		RightLowerArm = R(40, 0, 0),
		RightUpperLeg = R(80, 0, 0),
		RightLowerLeg = R(-10, 0, 0),
		LeftUpperLeg = R(-30, 0, 0),
		LeftLowerLeg = R(-80, 0, 0),
	} :: Rig.Pose,
	-- leaping, knees tucked, one arm reaching up
	leap = {
		LowerTorso = R(10, 0, 0),
		UpperTorso = R(-10, 0, 0),
		Head = R(-15, 0, 0),
		LeftUpperArm = R(150, 0, -20),
		LeftLowerArm = R(10, 0, 0),
		RightUpperArm = R(40, 0, 50),
		RightLowerArm = R(50, 0, 0),
		LeftUpperLeg = R(70, 0, -10),
		LeftLowerLeg = R(-110, 0, 0),
		RightUpperLeg = R(30, 0, 10),
		RightLowerLeg = R(-90, 0, 0),
	} :: Rig.Pose,
	-- caught: arms flung, body arched back
	caught = {
		LowerTorso = R(20, 0, 0),
		UpperTorso = R(-25, 0, 0),
		Head = R(-30, 0, 0),
		LeftUpperArm = R(120, 0, -60),
		RightUpperArm = R(110, 0, 70),
		LeftUpperLeg = R(30, 0, -15),
		LeftLowerLeg = R(-60, 0, 0),
		RightUpperLeg = R(10, 0, 15),
		RightLowerLeg = R(-30, 0, 0),
	} :: Rig.Pose,
}

return Uro

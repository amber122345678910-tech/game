--!strict
-- Blueprint "Perseverance" ("The Scholar"): purple SOUL class on the Human skeleton. [Lune-safe]
-- Purple sweater with lavender stripes, charcoal trousers, penny loafers; messy auburn hair with a cowlick, a
-- pencil tucked behind the right ear, freckles; big round CLOUDY GLASSES (thin dark frames, milky glass lenses,
-- bridge and temple arms); the Torn Notebook held in the right fist. Body: HumanCommon.
-- Palette keys: Sweater, Stripe, Book (skins override these three), Skin, Hair, Pants, Shoe, Sole, Frame, Lens,
--               Freckle, Pencil.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local function build(rig: RigContext)
	local P = rig.Palette
	local info = HumanCommon.Body(rig, {
		Hair = "Messy",
		Eyes = "Open",
		Brows = "Worried",
		Mouth = "Smile",
		Stripes = { { 0.2, 0.3 }, { 0.42, 0.52 }, { 0.64, 0.74 } },
		Legs = "Pants",
		Shoes = "Loafers",
		Weapon = "Notebook",
		WeaponTilt = 0,
	})
	local face, R = info.FaceCF, info.FaceRadii

	-- freckles across the nose and cheeks
	for i, f in { { -30, -12 }, { -36, -17 }, { -25, -18 }, { 30, -12 }, { 36, -17 }, { 25, -18 } } do
		rig.Ball("Head", "Freckle" .. i, 0.035, rig.OnEllipsoid(face, R, f[1], f[2], 0.005), P.Freckle, {
			Role = "Detail",
			CastShadow = false,
		})
	end

	-- CLOUDY GLASSES: two round frames (arc rings), milky lenses, bridge, temple arms back to the ears
	local frameP = { Role = "Metal", Material = Enum.Material.SmoothPlastic, CastShadow = false }
	local lensP = { Role = "Detail", Material = Enum.Material.Glass, Transparency = 0.38, Reflectance = 0.15, CastShadow = false }
	local radius = 0.155
	local lensCentres: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local eye = rig.OnEllipsoid(face, R, 23 * s, -3, 0)
		local centre = eye.Position + V(0, 0.01, -0.07)
		table.insert(lensCentres, centre)
		local frame = rig.LookFrame(centre, V(math.sin(rad(12 * s)), 0, -1).Unit)
		rig.Arc("Head", side .. "Rim", frame, radius, 0, 360, 10, 0.038, 0.035, P.Frame, frameP)
		rig.Disc("Head", side .. "Lens", radius * 2 - 0.02, 0.02, frame, P.Lens, lensP)
		-- lens glare
		rig.Box("Head", side .. "Glare", V(0.035, 0.12, 0.012), frame * CF(-0.05, 0.03, -0.014) * CFrame.Angles(0, 0, rad(-35)), Color3.new(1, 1, 1), {
			Role = "Detail",
			Transparency = 0.25,
			CastShadow = false,
		})
		-- temple arm to the ear
		local hinge = (frame * CF(radius * s, 0.02, 0.0)).Position
		local ear = face.Position + V(0.66 * s, 0.03, 0.12)
		rig.CylBetween("Head", side .. "Temple", hinge, ear, 0.035, P.Frame, frameP)
	end
	local a, b = lensCentres[1], lensCentres[2]
	rig.CylBetween("Head", "Bridge", a + V(radius - 0.01, 0.03, 0.01), b + V(-radius + 0.01, 0.03, 0.01), 0.035, P.Frame, frameP)

	-- pencil tucked behind the right ear
	local hc = rig.CFrameOf("Head").Position
	local tip = hc + V(0.58, 0.02, -0.34)
	local tail = hc + V(0.86, 0.28, 0.32)
	local pencilP = { Role = "Detail", Material = Enum.Material.SmoothPlastic }
	rig.CylBetween("Head", "Pencil", tip:Lerp(tail, 0.12), tail, 0.07, P.Pencil, pencilP)
	rig.CylBetween("Head", "PencilWood", tip, tip:Lerp(tail, 0.12), 0.05, rgb(232, 196, 150), pencilP)
	rig.Ball("Head", "PencilLead", 0.03, CF(tip), rgb(50, 50, 56), { Role = "Detail", CastShadow = false })
	rig.CylBetween("Head", "PencilFerrule", tail:Lerp(tip, 0.06), tail, 0.075, rgb(196, 200, 206), { Role = "Metal", Material = Enum.Material.Metal })
	rig.Ball("Head", "PencilEraser", 0.075, CF(tail), rgb(240, 140, 150), pencilP)
end

local blueprint: Blueprints.Blueprint = {
	Id = "Perseverance",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Sweater = rgb(140, 64, 168),
		Stripe = rgb(214, 176, 238),
		Book = rgb(170, 52, 66),
		Skin = rgb(240, 200, 166),
		Hair = rgb(124, 60, 42),
		Pants = rgb(70, 70, 82),
		Shoe = rgb(110, 62, 40),
		Sole = rgb(46, 34, 30),
		Frame = rgb(46, 38, 50),
		Lens = rgb(226, 232, 244),
		Freckle = rgb(196, 120, 92),
		Pencil = rgb(250, 200, 50),
	},
	Build = build,
}

return blueprint

--!strict
-- Shot 1: wide establishing shot. Snowfield in thick mist; Ryu on the left
-- pointing his finger, Rika crouched on the right with Yuta behind her.
-- Character positions are solved from the measured screen positions.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)
local SkyPaint = require(script.Parent.SkyPaint)
local Ryu = require(script.Parent.Parent.Characters.Ryu)
local Yuta = require(script.Parent.Parent.Characters.Yuta)
local Rika = require(script.Parent.Parent.Characters.Rika)

local WideSet = {}

WideSet.SKY_DEPTH = 280

local function groundPoint(depth: number, rx: number): Vector3
	local p = Layout.worldAt(Layout.WIDE_CAM, Layout.WIDE_FOV, depth, rx, 0)
	return Vector3.new(p.X, 0, p.Z)
end

-- camera-facing plate covering the full frame (plus margins) at a depth
local function framePlate(scene: Builder.Scene, name: string, depth: number, scale: number, paint: (Paint.Canvas) -> (), channel: string?)
	local x0, y0, x1, y1 = -220, -60, 1320, 720
	local cf, size = Layout.plate(Layout.WIDE_CAM, Layout.WIDE_FOV, depth, x0, y0, x1, y1)
	local c = Paint.canvas(scale, x0, y0)
	paint(c)
	Builder.part(scene, "WideSet", size, cf, Color3.new(1, 1, 1), {
		name = name,
		transparency = 1,
		castShadow = false,
		channel = channel,
		gui = {
			face = "Front",
			canvas = Vector2.new((x1 - x0) * scale, (y1 - y0) * scale),
			lightInfluence = 0,
			elems = c.elems,
		},
	})
end

local function fogBlobs(c: Paint.Canvas, seed: number, n: number, x0: number, y0: number, x1: number, y1: number, col: Color3, alpha: number, wMin: number, wMax: number)
	local r = Util.rng(seed)
	for _ = 1, n do
		local w = Util.randRange(r, wMin, wMax)
		c:blob(Util.randRange(r, x0, x1), Util.randRange(r, y0, y1), w, w * Util.randRange(r, 0.16, 0.3), col, alpha * Util.randRange(r, 0.6, 1))
	end
end

function WideSet.build(scene: Builder.Scene)
	local st = scene.style
	local pal = st.color
	Builder.model(scene, "WideSet", false)

	-- ground: ends just behind the characters (the painted sky and mist
	-- cover the distance); the cinematic style uses a long real snowfield
	-- that the atmosphere fades out.
	local cinema = st.sky == "cinema"
	local far = if cinema then 2400 else 150
	Builder.part(scene, "WideSet", Vector3.new(if cinema then 4000 else 900, 4, far + 50), CFrame.new(0, -2, 50 - (far + 50) / 2), pal.snow, {
		name = "Ground",
		material = st.material.ground,
		studs = st.studs,
		castShadow = false,
	})
	-- painted sky (the cinematic style uses Roblox clouds instead)
	if not cinema then
		framePlate(scene, "SkyPlate", WideSet.SKY_DEPTH, 0.5, function(c)
			SkyPaint.wide(c, st.sky)
		end)
	end

	-- mist layers (back to front). The ground ends at depth 150, so a plate
	-- at depth d is hidden below the row where it meets the ground; every
	-- plate keeps its blobs above that row (220 -> y 377, 140 -> 413, 70 -> 513).
	local clear = st.sky == "clear"
	local fogA = if clear then 0.35 else 0.55
	if not cinema then
		framePlate(scene, "FogFar", 220, 0.5, function(c)
			fogBlobs(c, 101, 10, -150, 210, 1250, 330, pal.fogLight, if clear then 0.25 else 0.35, 220, 460)
			if not clear then
				fogBlobs(c, 102, 6, 300, 240, 640, 340, pal.fogLight, 0.45, 160, 300)
				fogBlobs(c, 103, 6, 660, 260, 1100, 340, pal.fogLight, 0.4, 180, 320)
			end
		end)
	end
	framePlate(scene, "FogBack", 140, 0.5, function(c)
		fogBlobs(c, 106, 14, -150, 338, 1250, 372, pal.fogLight, fogA, 200, 380)
		if not clear then
			fogBlobs(c, 107, 5, 650, 330, 950, 390, pal.fogLight, 0.5, 120, 220)
		end
	end)
	framePlate(scene, "FogMid", 70, 0.5, function(c)
		-- soft band over the end of the ground (horizon line) and the feet
		fogBlobs(c, 113, 12, -150, 398, 1250, 414, pal.fogLight, fogA * 0.6, 260, 480)
		fogBlobs(c, 111, 14, -150, 436, 1250, 462, pal.fogLight, fogA * 0.85, 180, 340)
		fogBlobs(c, 112, 5, 700, 420, 900, 452, pal.fogLight, 0.4, 100, 180)
	end, "fogMid")
	framePlate(scene, "FogNear", 40, 0.5, function(c)
		fogBlobs(c, 121, 14, -200, 480, 1300, 700, pal.fogLight, fogA * 0.7, 320, 620)
		if not clear then
			fogBlobs(c, 122, 8, -200, 540, 1300, 700, pal.fogDark, 0.25, 320, 600)
		end
	end, "fogNear")

	-- falling snow (cinematic style)
	if st.snow then
		table.insert(scene.emitters, {
			name = "SnowWide",
			kind = "snow",
			cf = CFrame.new(0, 34, -70),
			size = Vector3.new(130, 2, 130),
			rate = 110,
			color = Color3.fromRGB(235, 240, 250),
			sizeRange = { 0.14, 0.32 },
			speed = { 3, 5 },
			lifetime = { 8, 10 },
			transparency = 0.15,
		})
	end

	-- characters (roots solved from measured screen positions)
	Ryu.build(scene, "Ryu")
	Rika.build(scene, "Rika")
	Yuta.build(scene, "Yuta")
	local ryuAt = groundPoint(117, 228)
	local rikaAt = groundPoint(119, 792)
	local yutaAt = groundPoint(134, 866)
	scene.data.wide = {
		roots = {
			Ryu = CFrame.new(ryuAt) * CFrame.Angles(0, math.rad(-90), 0),
			Rika = CFrame.new(rikaAt) * CFrame.Angles(0, math.rad(84), 0),
			Yuta = CFrame.new(yutaAt) * CFrame.Angles(0, math.rad(96), 0),
		},
		poses = {
			Ryu = Ryu.poses.point,
			Rika = Rika.poses.crouch,
			Yuta = Yuta.poses.stand,
		},
	}
end

return WideSet

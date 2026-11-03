--!strict
-- Shot 2: split screen with the eyes. Two painted face plates slide in front
-- of two painted sky plates; the black divider is drawn in the overlay.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Paint = require(script.Parent.Parent.Parent.Paint)
local SkyPaint = require(script.Parent.SkyPaint)
local YutaEyes = require(script.Parent.Parent.Faces.YutaEyes)
local RyuEyes = require(script.Parent.Parent.Faces.RyuEyes)

local CloseupSet = {}

local FACE_SCALE = 2 -- canvas px per reference px (crisp at 1080p+)

local function plate(scene: Builder.Scene, name: string, depth: number, x0: number, y0: number, x1: number, y1: number, scale: number, lightInfluence: number, channel: string?, paint: (Paint.Canvas) -> ())
	local cf, size = Layout.plate(Layout.CLOSE_CAM, Layout.CLOSE_FOV, depth, x0, y0, x1, y1)
	local c = Paint.canvas(scale, x0, y0)
	paint(c)
	Builder.part(scene, "CloseupSet", size, cf, Color3.new(1, 1, 1), {
		name = name,
		transparency = 1,
		castShadow = false,
		channel = channel,
		gui = {
			face = "Front",
			canvas = Vector2.new((x1 - x0) * scale, (y1 - y0) * scale),
			lightInfluence = lightInfluence,
			elems = c.elems,
		},
	})
end

function CloseupSet.build(scene: Builder.Scene)
	local st = scene.style
	Builder.model(scene, "CloseupSet", false)
	local split = Layout.SPLIT_Y
	-- skies (static)
	plate(scene, "SkyTop", Layout.SKY_DEPTH, -60, -20, 1180, split, 0.5, 0, nil, function(c)
		SkyPaint.panel(c, st.sky, "top", -20, split)
	end)
	plate(scene, "SkyBottom", Layout.SKY_DEPTH, -60, split, 1180, 646, 0.5, 0, nil, function(c)
		SkyPaint.panel(c, st.sky, "bottom", split, 646)
	end)
	-- faces (slide on channels)
	local li = st.face.lightInfluence
	plate(scene, "FaceYuta", Layout.FACE_DEPTH, YutaEyes.X0, YutaEyes.Y0, YutaEyes.X1, YutaEyes.Y1, FACE_SCALE, li, "plateYuta", function(c)
		YutaEyes.paint(c, st.color, st.face.line, st.face.soft)
	end)
	plate(scene, "FaceRyu", Layout.FACE_DEPTH, RyuEyes.X0, RyuEyes.Y0, RyuEyes.X1, RyuEyes.Y1, FACE_SCALE, li, "plateRyu", function(c)
		RyuEyes.paint(c, st.color, st.face.line, st.face.soft)
	end)

	-- snow drifting between the camera and the faces (cinematic style)
	if st.snow then
		local cam = Layout.CLOSE_CAM
		local box = Builder.part(scene, "CloseupSet", Vector3.new(9, 0.2, 7), cam * CFrame.new(0, 3.2, -6), Color3.new(1, 1, 1), { transparency = 1, castShadow = false, name = "SnowCloseBox" })
		Builder.emitter(scene, "SnowClose", "snow", box, Color3.fromRGB(235, 240, 250), 0.18, 0.18)
	end

	-- overlay: hand-inked divider (frame design px 1113 x 626)
	local o = Paint.canvas(1, 0, 0)
	local y = split
	local pts, ws = {}, {}
	for i = 0, 24 do
		local x = -12 + i * (1137 / 24)
		table.insert(pts, { x, y + math.sin(i * 1.7) * 0.6 })
		table.insert(ws, 10.5 + math.sin(i * 2.3 + 1) * 1.1 + math.sin(i * 0.7) * 0.6)
	end
	o:stroke(pts, ws, Color3.fromRGB(3, 1, 6))
	-- dry-brush nubs
	for _, n in { { 180, -5.5, 14, 2.4 }, { 470, 5.6, 20, 2 }, { 760, -5.4, 11, 2.2 }, { 990, 5.2, 16, 2 } } do
		o:pill(n[1], y + n[2], n[3], n[4], 0, Color3.fromRGB(3, 1, 6))
	end
	for _, e in o.elems do
		e.group = "divider"
		table.insert(scene.overlay, e)
	end
end

return CloseupSet

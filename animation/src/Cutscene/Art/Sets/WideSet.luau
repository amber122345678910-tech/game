--!strict
-- Shot 1 helpers: mist plates fitted to the wide establishing camera (they
-- only exist while the wide shot is on screen).
local Builder = require(script.Parent.Parent.Parent.Builder)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Paint = require(script.Parent.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Parent.Util)

local WideSet = {}

export type Plate = { part: Builder.PartSpec, base: CFrame }

local function framePlate(scene: Builder.Scene, name: string, depth: number, paint: (Paint.Canvas) -> ()): Plate
	local x0, y0, x1, y1 = -220, -60, 1320, 720
	local cf, size = Layout.plate(Layout.WIDE_CAM, Layout.WIDE_FOV, depth, x0, y0, x1, y1)
	local c = Paint.canvas(0.5, x0, y0)
	paint(c)
	local p = Builder.part(scene, "WideSet", size, CFrame.new(), Color3.new(1, 1, 1), {
		name = name,
		transparency = 1,
		castShadow = false,
		fx = true,
		gui = {
			face = "Front",
			canvas = Vector2.new((x1 - x0) * 0.5, (y1 - y0) * 0.5),
			lightInfluence = 0,
			elems = c.elems,
		},
	})
	return { part = p, base = cf }
end

local function fogBlobs(c: Paint.Canvas, seed: number, n: number, x0: number, y0: number, x1: number, y1: number, col: Color3, alpha: number, wMin: number, wMax: number)
	local r = Util.rng(seed)
	for _ = 1, n do
		local w = Util.randRange(r, wMin, wMax)
		c:blob(Util.randRange(r, x0, x1), Util.randRange(r, y0, y1), w, w * Util.randRange(r, 0.16, 0.3), col, alpha * Util.randRange(r, 0.6, 1))
	end
end

function WideSet.build(scene: Builder.Scene)
	local pal = scene.style.color
	Builder.model(scene, "WideSet", false)
	local fogA = 0.55
	local plates = {
		back = framePlate(scene, "FogBack", 140, function(c)
			fogBlobs(c, 106, 14, -150, 338, 1250, 372, pal.fogLight, fogA, 200, 380)
			fogBlobs(c, 107, 5, 650, 330, 950, 390, pal.fogLight, 0.5, 120, 220)
		end),
		mid = framePlate(scene, "FogMid", 70, function(c)
			fogBlobs(c, 113, 12, -150, 398, 1250, 414, pal.fogLight, fogA * 0.6, 260, 480)
			fogBlobs(c, 111, 14, -150, 436, 1250, 462, pal.fogLight, fogA * 0.85, 180, 340)
			fogBlobs(c, 112, 5, 700, 420, 900, 452, pal.fogLight, 0.4, 100, 180)
		end),
		near = framePlate(scene, "FogNear", 40, function(c)
			fogBlobs(c, 121, 14, -200, 480, 1300, 700, pal.fogLight, fogA * 0.7, 320, 620)
			fogBlobs(c, 122, 8, -200, 540, 1300, 700, pal.fogDark, 0.25, 320, 600)
		end),
	}
	scene.data.wide = plates
end

return WideSet

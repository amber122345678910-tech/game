--!strict
-- Shared geometry of the shots: camera placements and helpers that map
-- coordinates of the reference frame onto the 3D world.
--
-- "Reference px" are pixels of the analysed reference frame (1080 x 626 crop
-- of a 16:9 picture). The full 16:9 frame is 1113 x 626 reference px, so
-- frame x = (refX + 16.5) / 1113, frame y = refY / 626.
local Util = require(script.Parent.Util)

local Layout = {}

Layout.REF_W = 1080
Layout.REF_H = 626
Layout.FRAME_W = 1113
Layout.FRAME_H = 626
Layout.REF_X0 = 16.5
Layout.ASPECT = 16 / 9

-- Wide establishing shot (set built around the world origin, ground at Y = 0)
Layout.WIDE_CAM = CFrame.new(0, 12, 0)
Layout.WIDE_FOV = 30

-- Close-up "stage" for the split-screen eyes (far away from the wide set)
Layout.CLOSE_CAM = CFrame.new(4000, 100, 0)
Layout.CLOSE_FOV = 30
Layout.FACE_DEPTH = 10
Layout.SKY_DEPTH = 36

-- Split-screen divider (measured): center at y = 301 px, thickness 11 px
Layout.SPLIT_Y = 301
Layout.SPLIT_THICK = 11

-- frame-normalized coordinates of a reference pixel
function Layout.frameXY(rx: number, ry: number): (number, number)
	return (rx + Layout.REF_X0) / Layout.FRAME_W, ry / Layout.FRAME_H
end

-- Size (studs) of the full 16:9 frame at a given depth in front of a camera
function Layout.frameSize(fov: number, depth: number): (number, number)
	local h = 2 * depth * math.tan(math.rad(fov) / 2)
	return h * Layout.ASPECT, h
end

-- Studs per reference pixel at a depth
function Layout.studsPerPx(fov: number, depth: number): number
	local w = Layout.frameSize(fov, depth)
	return w / Layout.FRAME_W
end

-- World point that appears at reference pixel (rx, ry) at a given depth
function Layout.worldAt(cam: CFrame, fov: number, depth: number, rx: number, ry: number): Vector3
	local fx, fy = Layout.frameXY(rx, ry)
	local w, h = Layout.frameSize(fov, depth)
	return cam.Position + cam.LookVector * depth + cam.RightVector * ((fx - 0.5) * w) - cam.UpVector * ((fy - 0.5) * h)
end

-- A camera-facing plate covering the reference rectangle [x0,x1] x [y0,y1].
-- Returns the plate CFrame (Front face towards the camera) and its size.
function Layout.plate(cam: CFrame, fov: number, depth: number, x0: number, y0: number, x1: number, y1: number): (CFrame, Vector3)
	local spp = Layout.studsPerPx(fov, depth)
	local c = Layout.worldAt(cam, fov, depth, (x0 + x1) / 2, (y0 + y1) / 2)
	local cf = Util.lookAt(c, c - cam.LookVector, cam.UpVector)
	return cf, Vector3.new((x1 - x0) * spp, (y1 - y0) * spp, 0.05)
end

return Layout

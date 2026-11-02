-- Generates the desert of planet B137 with smooth terrain when the server starts.
-- (Terrain can't be stored in the source files, so it is made here. Takes a few seconds.)
local Terrain = workspace.Terrain

local ORIGIN = Vector3.new(6000, 0, 0)
local VILLAGE = Vector3.new(6150, 0, -60)
local SIZE = 1700

local rng = Random.new(137)

Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(214, 146, 88))
Terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(186, 110, 72))
Terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 82, 62))
Terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(170, 104, 66))

-- flat sand floor, top at Y = 0
local half = SIZE / 2
local step = 425
for x = -half, half - step, step do
	for z = -half, half - step, step do
		Terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new(x + step / 2, -12, z + step / 2)), Vector3.new(step, 24, step), Enum.Material.Sand)
	end
	task.wait()
end

-- places that must stay flat (landing site, path, village, where the titan lands)
local flat = {
	{ ORIGIN, 60 },
	{ ORIGIN:Lerp(VILLAGE, 0.35), 50 },
	{ ORIGIN:Lerp(VILLAGE, 0.7), 50 },
	{ VILLAGE, 95 },
	{ VILLAGE + Vector3.new(120, 0, -120), 70 },
	{ VILLAGE + Vector3.new(60, 0, -60), 50 },
	-- the corridor north of the bunker hatch (chase + the Alliance army)
	{ Vector3.new(6080, 0, 20), 50 },
	{ Vector3.new(6080, 0, 90), 58 },
	{ Vector3.new(6080, 0, 170), 60 },
	{ Vector3.new(6080, 0, 250), 55 },
}
local function isFlat(p: Vector3, r: number): boolean
	for _, z in flat do
		local d = Vector3.new(p.X - z[1].X, 0, p.Z - z[1].Z).Magnitude
		if d < z[2] + r then
			return true
		end
	end
	return false
end

-- dunes
for i = 1, 190 do
	local r = rng:NextNumber(24, 100)
	local p = ORIGIN + Vector3.new(rng:NextNumber(-half + r, half - r), 0, rng:NextNumber(-half + r, half - r))
	if not isFlat(p, r * 0.9) then
		local h = r * rng:NextNumber(0.18, 0.42)
		Terrain:FillBall(p - Vector3.new(0, r - h, 0), r, Enum.Material.Sand)
	end
	if i % 15 == 0 then
		task.wait()
	end
end

-- gentle ripples in the flat areas (very low)
for _ = 1, 60 do
	local r = rng:NextNumber(12, 30)
	local p = ORIGIN + Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
	local nearPath = false
	for _, z in flat do
		if Vector3.new(p.X - z[1].X, 0, p.Z - z[1].Z).Magnitude < z[2] * 0.6 then
			nearPath = true
		end
	end
	if not nearPath then
		Terrain:FillBall(p - Vector3.new(0, r - 1.5, 0), r, Enum.Material.Sand)
	end
end
task.wait()

-- mesas on the horizon
for i = 1, 16 do
	local a = (i / 16) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
	local dist = rng:NextNumber(520, 760)
	local p = ORIGIN + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
	local radius = rng:NextNumber(36, 100)
	local height = rng:NextNumber(50, 150)
	Terrain:FillCylinder(CFrame.new(p + Vector3.new(0, height / 2 - 8, 0)), height, radius, Enum.Material.Sandstone)
	Terrain:FillCylinder(CFrame.new(p + Vector3.new(0, height - 5, 0)), 10, radius * 1.05, Enum.Material.Rock)
	Terrain:FillBall(p - Vector3.new(0, radius * 0.45, 0), radius * 1.35, Enum.Material.Sand)
	task.wait()
end

-- rocks
for i = 1, 70 do
	local r = rng:NextNumber(2, 9)
	local p = ORIGIN + Vector3.new(rng:NextNumber(-half * 0.8, half * 0.8), 0, rng:NextNumber(-half * 0.8, half * 0.8))
	if not isFlat(p, 4) then
		Terrain:FillBall(p + Vector3.new(0, r * 0.2, 0), r, if i % 3 == 0 then Enum.Material.Sandstone else Enum.Material.Rock)
	end
end

workspace:SetAttribute("DesertReady", true)

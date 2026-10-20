--!nocheck
-- Реквизит коня: гантель «500 KG» (сустав Dumbbell на правой кисти).
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Props = {}

local function label(part, face, text, rotation)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId[face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 0.6
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = roblox.UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(240, 240, 240)
	t.FontFace = roblox.Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	t.Rotation = rotation or 0
	t.Parent = gui
	return gui
end

-- Гантель: рукоять вдоль оси Z кисти (поперёк ладони), центр — в кулаке.
function Props.dumbbell(g, grip)
	local rig = g.rig
	rig:joint("Dumbbell", "RightHand", grip, grip, V(0.2, 0.2, 0.2))
	local B = "Dumbbell"
	local hl = 0.5 -- полудлина грифа между дисками
	local plateD, plateT = 1.32, 0.44
	-- гриф (хром) с насечкой посередине
	g:cylSeg(B, grip + V(0, 0, -hl - 0.05), grip + V(0, 0, hl + 0.05), 0.15, P.chrome, "Metal", { reflectance = 0.2 })
	g:cylSeg(B, grip + V(0, 0, -0.3), grip + V(0, 0, 0.3), 0.158, P.chrome:Lerp(P.plate, 0.25), "DiamondPlate")
	for _, s in { 1, -1 } do
		local zc = s * (hl + plateT / 2)
		-- втулка
		g:cylSeg(B, grip + V(0, 0, s * (hl - 0.06)), grip + V(0, 0, s * (hl + 0.01)), 0.27, P.chrome, "Metal", { reflectance = 0.25 })
		-- диск: основной цилиндр + скругление кромок
		g:cylSeg(B, grip + V(0, 0, zc - plateT / 2), grip + V(0, 0, zc + plateT / 2), plateD - 0.08, P.plate, "Rubber")
		g:cylSeg(B, grip + V(0, 0, zc - plateT / 2 + 0.05), grip + V(0, 0, zc + plateT / 2 - 0.05), plateD, P.plateRim, "Rubber")
		-- центральная ступица
		g:cylSeg(B, grip + V(0, 0, zc + s * (plateT / 2 - 0.01)), grip + V(0, 0, zc + s * (plateT / 2 + 0.03)), 0.2, P.chrome:Lerp(P.plate, 0.35), "Metal", { reflectance = 0.15 })
		-- торец (чуть утоплен внутрь обода) и надпись «500 / KG» белым — две тонкие таблички цвета диска
		local face = g:cylSeg(B, grip + V(0, 0, zc + s * (plateT / 2 - 0.02)), grip + V(0, 0, zc + s * (plateT / 2 + 0.006)), plateD - 0.2, P.plate, "Rubber")
		face.Name = "PlateFace"
		local zf = zc + s * (plateT / 2 + 0.014)
		local rot = if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
		for _, t in { { "500", 0.27, 0.6, 0.3 }, { "KG", -0.27, 0.44, 0.3 } } do
			local tag = g:box(B, CFrame.new(grip + V(0, t[2], zf)) * rot, V(t[3], t[4], 0.012), P.plate, "Rubber", nil, { castShadow = false, name = "PlateText" })
			label(tag, "Front", t[1], 0)
		end
	end
end

return Props

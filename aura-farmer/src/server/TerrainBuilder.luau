--!strict
-- Строит Terrain из невидимых деталей Sets/*/TerrainVolumes (атрибуты TerrainShape, TerrainMaterial).
-- Можно запустить и в редакторе из Command Bar, чтобы увидеть песок/воду/траву без Play:
--   require(game.ServerScriptService.AuraFarmerServer.TerrainBuilder).build(workspace.AuraFarmer, true)

local TerrainBuilder = {}

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("AuraFarmer"):WaitForChild("Config"))

function TerrainBuilder.build(world: Instance, force: boolean?)
	local terrain = workspace.Terrain
	for k, v in (Config.Terrain :: any) do
		pcall(function()
			(terrain :: any)[k] = v
		end)
	end
	if terrain:GetAttribute("AuraBuilt") and not force then
		return
	end
	local volumes: { BasePart } = {}
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("TerrainMaterial") then
			table.insert(volumes, d)
		end
	end
	table.sort(volumes, function(a: BasePart, b: BasePart)
		local sa, sb = a:FindFirstAncestorOfClass("Model"), b:FindFirstAncestorOfClass("Model")
		local na, nb = sa and sa.Name or "", sb and sb.Name or ""
		if na ~= nb then
			return na < nb
		end
		return ((a:GetAttribute("Order") :: number?) or 0) < ((b:GetAttribute("Order") :: number?) or 0)
	end)
	for i, p in volumes do
		local material = (Enum.Material :: any)[p:GetAttribute("TerrainMaterial")]
		local shape = p:GetAttribute("TerrainShape")
		if shape == "Ball" then
			terrain:FillBall(p.Position, p.Size.X / 2, material)
		elseif shape == "Cylinder" then
			terrain:FillCylinder(p.CFrame, p.Size.Y, p.Size.X / 2, material)
		elseif shape == "Wedge" then
			terrain:FillWedge(p.CFrame, p.Size, material)
		else
			terrain:FillBlock(p.CFrame, p.Size, material)
		end
		if i % 8 == 0 then
			task.wait()
		end
	end
	terrain:SetAttribute("AuraBuilt", true)
end

return TerrainBuilder

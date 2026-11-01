--!strict
-- BoneSword prop: Fell Sans' bone sword as a free-standing prop (thrown swords, galleries). [Lune-safe]
-- The sword itself is authored by Rigs/Props/Weapons ("BoneSword"); this module only delegates to it
-- and converts the hand-held weapon (unanchored, welded to its Grip) into the prop-library convention
-- (Anchored, no welds needed). Returns nil-safe errors: it fails loudly if Weapons is missing.
--
-- API
--   BoneSword.Build(palette: {[string]: Color3}?, anchored: boolean?) -> Model
--        Weapons.Build("BoneSword", palette); anchored defaults to true (welds are removed so every
--        part can be moved by CFrame). PrimaryPart "Grip" (handle at the origin, blade towards -Z per
--        the Weapons grip space). Attributes: PropId "BoneSword", WeaponId, PartCount.

local Props = require(script.Parent)

local BoneSword = {}

function BoneSword.Build(palette: { [string]: Color3 }?, anchored: boolean?): Model
	local Weapons = require(script.Parent.Weapons) :: any
	local model: Model = Weapons.Build("BoneSword", palette)
	model:SetAttribute("PropId", "BoneSword")
	if anchored == false then
		return model
	end
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	local grip = model.PrimaryPart or model:FindFirstChild("Grip")
	assert(grip and grip:IsA("BasePart"), "BoneSword: Weapons.Build returned no Grip")
	return Props.Finish(model, grip)
end

return BoneSword

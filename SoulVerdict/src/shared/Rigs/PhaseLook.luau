--!strict
-- PhaseLook: monster phase looks (owner's Last Breath Sans: phase 1 clean, phase 2 scarred eye + blood + bone,
-- phase 3 cracked skull + bloody hand). Parts named "Phase2_*" / "Phase3_*" are visible only from that phase on.
-- Server: RoundService applies it when the phase changes (replicates). Lune-safe.
--
-- API
--   PhaseLook.MinOf(name) -> number?          2 for "Phase2_Scar" ...
--   PhaseLook.Apply(model, phase)              shows / hides the phase parts, sets attribute "SansPhase"
local PhaseLook = {}

function PhaseLook.MinOf(name: string): number?
	local n = string.match(name, "^Phase(%d)_")
	return if n then tonumber(n) else nil
end

function PhaseLook.Apply(model: Instance, phase: number)
	if typeof(model) ~= "Instance" then
		return
	end
	pcall(function()
		model:SetAttribute("SansPhase", phase)
	end)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local min = PhaseLook.MinOf(d.Name)
			if min then
				d.Transparency = if phase >= min then 0 else 1
			end
		end
	end
end

return PhaseLook

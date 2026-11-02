--!nocheck
-- Core data sanity: Config, Strings, Kits.
return {
	config_loads = function(T, Loader)
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		T.ok(type(Config.Round.RoundTime) == "number", "RoundTime")
	end,
	strings_work = function(T, Loader)
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		T.eq(Strings.L("common.gold", 5), "5 G")
		Strings.SetLanguage("ru")
		T.eq(Strings.L("common.back"), "НАЗАД")
		T.eq(Strings.L("missing.key"), "missing.key")
		Strings.SetLanguage("en")
	end,
	kits_valid = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local all = Kits.All()
		T.eq(#all, 11, "kit count (+ Last Breath Sans)")
		local icons = {}
		for _, n in Kits.IconNames do
			icons[n] = true
		end
		for _, kit in all do
			T.ok(kit.Name.en ~= "" and kit.Name.ru ~= "", kit.Id .. " name")
			local slots = {}
			for _, a in kit.Abilities do
				T.ok(not slots[a.Slot], kit.Id .. " duplicate slot " .. a.Slot)
				slots[a.Slot] = true
				T.ok(icons[a.Icon] ~= nil, kit.Id .. "." .. a.Id .. " unknown icon " .. tostring(a.Icon))
				T.ok(a.Name.ru ~= nil and a.Desc.ru ~= nil, kit.Id .. "." .. a.Id .. " ru text")
				T.ok(type(a.Numbers) == "table", kit.Id .. "." .. a.Id .. " numbers")
			end
			T.ok(slots.M1, kit.Id .. " needs M1")
			if kit.Role == "Monster" then
				for _, s in { "Q", "E", "R", "T", "G", "Shift" } do
					T.ok(slots[s], kit.Id .. " missing slot " .. s)
				end
				T.ok(kit.Stats.MaxDodges ~= nil and kit.Stats.HPPerHuman ~= nil, kit.Id .. " monster stats")
				T.ok(kit.VerdictBox ~= nil, kit.Id .. " verdict box set")
			else
				for _, s in { "Q", "E", "R" } do
					T.ok(slots[s], kit.Id .. " missing slot " .. s)
				end
				local ult = Kits.AbilityBySlot(kit.Id, "R")
				T.ok(ult and ult.Ult == true, kit.Id .. " R must be ult")
			end
			T.ok(#kit.Skins >= 1 and kit.Skins[1].Id == "Default", kit.Id .. " default skin first")
		end
	end,
}

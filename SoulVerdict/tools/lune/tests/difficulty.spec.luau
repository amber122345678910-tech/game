--!nocheck
-- Difficulty: the profile setting, the server damage hook and the client tip limits.
local function restore(Loader, saved)
	Loader.isServer = saved
end

return {
	difficulty_setting_is_an_enum_defaulting_to_easy = function(T, Loader)
		local ProfileSchema = Loader.require("ReplicatedStorage.Shared.Progression.ProfileSchema")
		local spec = ProfileSchema.Settings().Difficulty
		T.ok(spec ~= nil, "Difficulty is a whitelisted setting")
		T.eq(spec.Type, "enum")
		T.eq(spec.Default, "Easy", "newcomers start on Easy")
		local ok = ProfileSchema.ValidateSetting("Difficulty", "Hard")
		T.eq(ok, true, "Hard is accepted")
		local bad = ProfileSchema.ValidateSetting("Difficulty", "Nightmare")
		T.eq(bad, false, "unknown levels are refused")
		local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
		for _, key in { "set.Difficulty", "set.desc.Difficulty", "set.difficulty.Easy", "set.difficulty.Normal",
			"set.difficulty.Hard", "diff.hint.Blue", "diff.hint.Orange", "diff.hint.Box", "diff.hint.Round" } do
			T.ok(Strings.Has(key), key .. " exists")
		end
	end,

	difficulty_hook_scales_monster_damage_to_players_only = function(T, Loader)
		local saved = Loader.isServer
		Loader.isServer = true
		local D = Loader.requirePath("src/server/Services/DifficultyService")
		local Config = Loader.require("ReplicatedStorage.Shared.Config")
		T.near(D.DamageFactor("Easy"), Config.Difficulty.DamageTaken.Easy, 1e-9)
		T.near(D.KRFactor("Hard"), Config.Difficulty.KR.Hard, 1e-9)
		T.eq(D.DamageFactor("Normal"), 1)
		-- a bot / dummy target (no Player) is never scaled
		local state = { TargetTeam = "Humans", AttackerTeam = "Monster", Kind = "Melee", Amount = 10, KRMult = 1 }
		D.Hook({ Target = Loader.roblox.Instance.new("Model") }, {}, state)
		T.eq(state.Amount, 10, "no player behind the target: untouched")
		-- monster hitting the monster / human hitting the monster: untouched
		local s2 = { TargetTeam = "Monster", AttackerTeam = "Humans", Kind = "Melee", Amount = 10, KRMult = 1 }
		D.Hook({ Target = Loader.roblox.Instance.new("Model") }, {}, s2)
		T.eq(s2.Amount, 10, "damage dealt to the monster is never scaled")
		restore(Loader, saved)
	end,

	hint_limits = function(T, Loader)
		local saved = Loader.isServer
		Loader.isServer = false
		local H = Loader.requirePath("src/client/Controllers/HintController")
		local base = { Level = "Easy", Shown = {}, LastAt = {}, Now = 100 }
		T.eq(H.ShouldHint("Blue", base), true, "Easy shows tips")
		T.eq(H.ShouldHint("Blue", { Level = "Normal", Shown = {}, LastAt = {}, Now = 100 }), false, "Normal: none")
		T.eq(H.ShouldHint("Blue", { Level = "Easy", Shown = {}, LastAt = { Blue = 90 }, Now = 100 }), false, "cooldown")
		T.eq(H.ShouldHint("Blue", { Level = "Easy", Shown = { Blue = H.MaxPerSession }, LastAt = {}, Now = 100 }), false, "cap")
		restore(Loader, saved)
	end,
}

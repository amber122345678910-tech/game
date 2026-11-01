--!strict
-- Teams: who may hurt / help whom. Pure (reads Model attributes only). Lune-safe.
--
-- Team strings (Model attribute "Team"): "Humans" | "Monster" | "Lobby" | "Dummy".
-- Rules (SPEC §17):
--   * same team            -> never enemies (no friendly fire, Config.Combat.FriendlyFire is ignored on purpose)
--   * "Dummy"              -> enemy of every other non-empty team (training targets)
--   * "Lobby"              -> may only hit Dummies (and Dummies "hit back" nobody: they never attack)
--   * "Humans" x "Monster" -> enemies
--   * empty / unknown team -> enemy of nobody (spectators, props, half-spawned models)
-- A model whose KitId attribute is "Dummy" counts as team "Dummy" even without a Team attribute.
--
-- API
--   Teams.TeamOf(model: Instance?) -> string                 "" when unknown
--   Teams.AreEnemyTeams(a: string, b: string) -> boolean     string form (hazards keep a team string)
--   Teams.AreEnemies(a: Instance?, b: Instance?) -> boolean
--   Teams.AreAllyTeams(a: string, b: string) -> boolean      same non-empty team, not "Dummy"
--   Teams.AreAllies(a: Instance?, b: Instance?) -> boolean   (a model is its own ally)
--   Teams.IsCombatTeam(team: string) -> boolean              "Humans" | "Monster"

local Teams = {}

Teams.Humans = "Humans"
Teams.Monster = "Monster"
Teams.Lobby = "Lobby"
Teams.Dummy = "Dummy"

function Teams.TeamOf(model: Instance?): string
	if model == nil then
		return ""
	end
	local team = model:GetAttribute("Team")
	if type(team) == "string" and team ~= "" then
		return team
	end
	if model:GetAttribute("KitId") == "Dummy" then
		return Teams.Dummy
	end
	return ""
end

function Teams.AreEnemyTeams(a: string, b: string): boolean
	if a == "" or b == "" or a == b then
		return false
	end
	if a == Teams.Dummy or b == Teams.Dummy then
		return true
	end
	if a == Teams.Lobby or b == Teams.Lobby then
		return false -- lobby players only fight dummies
	end
	return (a == Teams.Humans and b == Teams.Monster) or (a == Teams.Monster and b == Teams.Humans)
end

function Teams.AreEnemies(a: Instance?, b: Instance?): boolean
	if a == nil or b == nil or a == b then
		return false
	end
	return Teams.AreEnemyTeams(Teams.TeamOf(a), Teams.TeamOf(b))
end

function Teams.AreAllyTeams(a: string, b: string): boolean
	return a ~= "" and a == b and a ~= Teams.Dummy
end

function Teams.AreAllies(a: Instance?, b: Instance?): boolean
	if a == nil or b == nil then
		return false
	end
	if a == b then
		return true
	end
	return Teams.AreAllyTeams(Teams.TeamOf(a), Teams.TeamOf(b))
end

function Teams.IsCombatTeam(team: string): boolean
	return team == Teams.Humans or team == Teams.Monster
end

return Teams

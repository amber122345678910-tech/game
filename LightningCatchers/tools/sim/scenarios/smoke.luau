--!nocheck
-- Smoke scenario: boot server, join two players (PC + phone), idle; prints engine state.
local roblox = require("@lune/roblox")

return {
	run = function(S)
		local Runtime, Sched, World, Engine = S.Runtime, S.Sched, S.World, S.Engine
		local DATA = Engine.DATA
		Runtime.startServer()
		Sched.runUntil(1)
		Runtime.addPlayer({ userId = 1001, name = "BotOne", viewport = roblox.Vector2.new(1366, 768) })
		Sched.runUntil(2)
		Runtime.addPlayer({ userId = 1002, name = "BotTwo", viewport = roblox.Vector2.new(844, 390), touch = true })
		Sched.runUntil((S.opts.minutes or 1) * 60)
		local lines = { "smoke state:" }
		local remotes = {}
		for k, v in World.stats.remote do
			table.insert(remotes, k .. "=" .. v)
		end
		table.sort(remotes)
		table.insert(lines, "  remotes: " .. table.concat(remotes, " "))
		for _, pd in World.players do
			local realm = World.playerRealm[pd]
			local char = pd.props.Character
			local root = char and Engine.findChild(DATA[char], "HumanoidRootPart", nil)
			local pos = root and Engine.readProp(DATA[root], "CFrame", nil).Position
			local gui = Engine.findChild(pd, "PlayerGui", nil)
			local guis = {}
			for _, c in Engine.childrenOf(DATA[gui], realm) do
				table.insert(guis, DATA[c].props.Name)
			end
			local attrs = {}
			for k, v in pd.attrs do
				table.insert(attrs, k .. "=" .. tostring(v))
			end
			table.sort(attrs)
			table.insert(lines, string.format("  %s char=%s pos=%s attrs=%s", pd.props.Name, tostring(char ~= nil), tostring(pos), table.concat(attrs, ",")))
			table.insert(lines, "    guis: " .. table.concat(guis, ", "))
			local mods = 0
			for _ in realm.modules do
				mods += 1
			end
			table.insert(lines, "    modules loaded: " .. mods)
		end
		local smods = 0
		for _ in World.server.modules do
			smods += 1
		end
		table.insert(lines, "  server modules loaded: " .. smods)
		return table.concat(lines, "\n")
	end,
}

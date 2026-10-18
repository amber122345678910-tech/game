--!nocheck
-- Self-test of the harness: injects one fault of every kind into a server/client realm and checks that the
-- report catches it (with a stack trace pointing at the injected line). Exit code 0 = every detector works.
local roblox = require("@lune/roblox")
local Engine = require("../lib/engine")
local Report = require("../lib/report")
local World = require("../lib/world")

local CASES = {
	-- name, realm ("server"/"client"), expected category, source
	{ "unknown property read", "server", "member", 'local p = Instance.new("Part") local x = p.Sizee return 1' },
	{ "unknown property write", "server", "member", 'local p = Instance.new("Part") p.Transparancy = 1 return 1' },
	{ "wrong property type", "server", "proptype", 'local p = Instance.new("Part") p.Size = 5 return 1' },
	{ "read-only property", "server", "proptype", 'local p = Instance.new("Part") p.ClassName = "X" return 1' },
	{ "wrong enum type", "client", "proptype", 'local l = Instance.new("TextLabel") l.Font = Enum.Material.Neon return 1' },
	{ "nil index in Heartbeat", "client", "runtime", 'game:GetService("RunService").Heartbeat:Once(function() local t = nil; print(t.x) end) return 1' },
	{ "error in task.delay", "server", "runtime", 'task.delay(0.1, function() error("boom in delay") end) return 1' },
	{ "error in Changed handler", "server", "runtime", 'local v = Instance.new("NumberValue") v.Changed:Connect(function(x) local y = x .. {} end) v.Value = 3 return 1' },
	{ "infinite yield", "client", "yield", 'task.spawn(function() workspace:WaitForChild("DoesNotExist") end) return 1' },
	{ "mixed table over a remote", "server", "remote", 'local r = Instance.new("RemoteEvent") r.Parent = game.ReplicatedStorage r:FireAllClients({ 1, 2, x = 3 }) return 1' },
	{ "function over a remote", "server", "remote", 'local r = Instance.new("RemoteEvent") r.Parent = game.ReplicatedStorage r:FireAllClients(function() end) return 1' },
	{ "Vector3 into a DataStore", "server", "remote", 'pcall(function() game:GetService("DataStoreService"):GetDataStore("t"):SetAsync("k", { p = Vector3.new() }) end) return 1' },
	{ "mixed table into a DataStore", "server", "remote", 'pcall(function() game:GetService("DataStoreService"):GetDataStore("t"):SetAsync("k", { [1] = 1, [5] = 2 }) end) return 1' },
	{ "tween of unknown property", "client", "member", 'local p = Instance.new("Part") game:GetService("TweenService"):Create(p, TweenInfo.new(1), { Sizee = 1 }) return 1' },
	{ "tween type mismatch", "client", "proptype", 'local p = Instance.new("Part") game:GetService("TweenService"):Create(p, TweenInfo.new(1), { Transparency = Vector3.zero }) return 1' },
	{ "API not emulated", "server", "emu", 'game:GetService("TeleportService"):Teleport(1) return 1' },
	{ "unknown global", "client", "member", 'local x = Vectr3 return 1' },
	{ "table attribute", "server", "proptype", 'local p = Instance.new("Part") p:SetAttribute("x", {}) return 1' },
	{ "NaN position", "client", "nan", 'local p = Instance.new("Part") p.Position = Vector3.new(0/0, 0, 0) return 1' },
	{ "error printed with warn", "client", "caught", 'local ok, e = pcall(function() local t; return t.x end) warn("failed: " .. tostring(e)) return 1' },
	{ "RenderStepped on the server", "server", "runtime", 'game:GetService("RunService").RenderStepped:Connect(function() end) return 1' },
	{ "FireClient from a client", "client", "runtime", 'Instance.new("RemoteEvent"):FireClient(game.Players.LocalPlayer) return 1' },
	{ "member probe inside pcall", "client", "member_probe", 'local p = Instance.new("Part") pcall(function() return p.NotAThing end) return 1' },
	{ "dot call of a method", "server", "runtime", 'local p = Instance.new("Part") p.FindFirstChild("x") return 1' },
	{ "bad Instance.new class", "server", "runtime", 'Instance.new("Partt") return 1' },
	{ "circular parent", "server", "runtime", 'local a = Instance.new("Folder") local b = Instance.new("Folder") b.Parent = a a.Parent = b return 1' },
}

return {
	run = function(S)
		local Runtime, Sched = S.Runtime, S.Sched
		local DATA = Engine.DATA
		Runtime.startServer()
		Sched.runUntil(1)
		local client = Runtime.addPlayer({ userId = 9001, name = "SelfTest" })
		Sched.runUntil(4)
		-- forget everything the game itself produced so far
		local before = {}
		for k in Report.entries do
			before[k] = true
		end
		local results = {}
		for i, case in CASES do
			local name, realmName, cat, src = case[1], case[2], case[3], case[4]
			local mark = {}
			for k in Report.entries do
				mark[k] = true
			end
			local u, d = World.new("ModuleScript", { Name = "SelfTest" .. i }, nil, 0)
			d.source = src
			d.srcFile = "selftest/case" .. i .. ".luau"
			local realm = if realmName == "server" then World.server else client
			local co = Sched.spawn(realm, function()
				local ok = pcall(function()
					S.Realm.require(realm, u)
				end)
			end)
			Sched.runUntil(Sched.now + 6)
			local hit = false
			local where = nil
			for k, e in Report.entries do
				if not mark[k] and e.category == cat then
					hit = true
					where = e.frames[1] and (e.frames[1].src .. ":" .. e.frames[1].line) or "(no frame)"
				end
			end
			table.insert(results, { name = name, ok = hit, cat = cat, where = where })
		end
		-- the injected infinite yield belongs to this client: let it leave
		Runtime.removePlayer(client.playerD, "selftest")
		Sched.runUntil(Sched.now + 1)
		-- drop the injected entries from the report; keep only real failures of the self-test
		for k in table.clone(Report.entries) do
			if not before[k] then
				Report.entries[k] = nil
			end
		end
		local order = {}
		for _, e in Report.entries do
			table.insert(order, e)
		end
		local lines = { "--- Harness self-test ---" }
		local failed = 0
		for _, r in results do
			table.insert(lines, string.format("  [%s] %-32s -> %-12s %s", if r.ok then "ok" else "MISSED", r.name, r.cat, r.where or ""))
			if not r.ok then
				failed += 1
			end
		end
		table.insert(lines, string.format("self-test: %d/%d detectors work", #results - failed, #results))
		if failed > 0 then
			Report.add("check", "selftest", failed .. " fault detector(s) did not fire", {})
		end
		Report.rebuildOrder()
		return table.concat(lines, "\n")
	end,
}

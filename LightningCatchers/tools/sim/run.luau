--!nocheck
-- Headless runtime harness for «Ловцы Молний»: boots the REAL server and client code from the built place
-- against an emulated Roblox engine, drives simulated players through the game and reports every runtime
-- error with a stack trace (file:line in src/).
--
--   cd LightningCatchers
--   .tools/rojo build default.project.json -o <dir>/place.rbxl
--   .tools/lune run tools/sim/run.luau <dir>/place.rbxl [scenario] [--minutes N] [--log path]
--
-- Scenarios (tools/sim/scenarios):
--   core (default)  2 bots (PC + phone) play ~12.5 simulated minutes: catching, selling, upgrades, islands 1-5,
--                   pets, fulgurites, daily/codes/quests, every window, settings, kiosks, UI fuzz, rebirth, drone,
--                   barrier/void/death, remote fuzzing, Supercell + Ball lightning, late joiner, session locks,
--                   leave/rejoin save-load, next-day reward + offline income, BindToClose. ~100 s wall time.
--                   Languages: BotTwo has the Roblox locale "ru-ru" (Russian UI and world text), the others "en-us";
--                   English bots must never show Cyrillic GUI text; BotTwo switches to English in Settings and rejoins.
--   fast            core with event timers patched in Config before boot (Supercell, Ball, Rainbow, Perun, city).
--   selftest        injects one fault of every kind and checks the harness reports it (detector self-check).
--   smoke           boot + 2 players idle (quick sanity check).
-- --minutes N stretches the final free-play part of core/fast (the scripted timeline needs ~11 minutes).
-- Exit code: 0 = no errors, 1 = errors found, 2 = bad usage. Full event log: <dir>/sim.log (or --log).
--
-- Layout: lib/classdb (class/member/type tables from .tools/globalTypes.d.luau + Lune reflection defaults),
-- lib/sched (simulated clock, task scheduler, threads per realm), lib/engine (Instance core: validation,
-- realms/replication, signals), lib/classes (parts/joints/models/GUI/sounds/...), lib/world (realms, remotes,
-- raycasts), lib/services (DataModel, Players, RunService, TweenService, DataStore, input, ...), lib/realm
-- (place conversion, script environments, require), lib/runtime (boot, joins, per-frame engine work),
-- lib/bot (bot players), lib/report (report and log).
local process = require("@lune/process")
local fs = require("@lune/fs")

local Sched = require("./lib/sched")
local Report = require("./lib/report")
local Engine = require("./lib/engine")
require("./lib/classes")
local World = require("./lib/world")
require("./lib/services")
local Realm = require("./lib/realm")
local Runtime = require("./lib/runtime")

local args = process.args
local placePath = args[1]
if not placePath or not fs.isFile(placePath) then
	print("usage: lune run tools/sim/run.luau <place.rbxl> [core|fast|smoke] [--minutes N] [--log path]")
	process.exit(2)
end
local scenarioName = "core"
local opts = { minutes = nil, log = nil, quiet = false }
local i = 2
while i <= #args do
	local a = args[i]
	if a == "--minutes" then
		opts.minutes = tonumber(args[i + 1])
		i += 1
	elseif a == "--log" then
		opts.log = args[i + 1]
		i += 1
	elseif a == "--quiet" then
		opts.quiet = true
	elseif string.sub(a, 1, 2) ~= "--" then
		scenarioName = a
	end
	i += 1
end

local okScenario, scenario = pcall(require, "./scenarios/" .. scenarioName)
if not okScenario then
	print("unknown scenario '" .. scenarioName .. "': " .. tostring(scenario))
	process.exit(2)
end

local wallStart = os.clock()
Runtime.boot(placePath)

local ok, metricsText = xpcall(function()
	return scenario.run({
		Sched = Sched,
		Report = Report,
		Engine = Engine,
		World = World,
		Realm = Realm,
		Runtime = Runtime,
		opts = opts,
	})
end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)
if not ok then
	Report.add("runtime", "harness", "[harness] scenario crashed: " .. tostring(metricsText), {})
	metricsText = nil
end

-- threads still blocked at the end
for _, b in Sched.blockedThreads() do
	local what = b.info.what or "?"
	if string.find(what, "WaitForChild", 1, true) and Sched.now - b.info.since > 5 then
		Report.add("yield", Sched.realmName(b.realm), string.format("thread still blocked in %s since %s", what, Report.fmtTime(b.info.since)), Report.frames(b.co, 0))
	end
end

local text = Report.render(metricsText)
print(text)
print(string.format("(simulated %s in %.1f s wall time, %d frames)", Report.fmtTime(Sched.now), os.clock() - wallStart, Sched.frame))
local logPath = opts.log or ((string.match(placePath, "^(.*)/[^/]*$") or ".") .. "/sim.log")
Report.writeLog(logPath)
print("full log: " .. logPath)
process.exit(if Report.errorCount() > 0 then 1 else 0)

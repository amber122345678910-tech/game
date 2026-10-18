--!nocheck
-- Headless runtime harness for «Ловцы Молний»: boots the REAL server and client code from the built place
-- against an emulated Roblox engine, drives simulated players through the core loop and reports every
-- runtime error with a stack trace.
--
--   cd LightningCatchers
--   .tools/rojo build default.project.json -o <out>/place.rbxl
--   .tools/lune run tools/sim/run.luau <out>/place.rbxl [scenario] [--minutes N] [--log path] [--quiet]
--
-- Scenarios: core (default), fast (event timers shortened), smoke (boot + 60 s idle).
-- Exit code 1 if any error was found.
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
local logPath = opts.log or "/tmp/claude-0/-home-user-game/e7d2c87b-d4de-50fd-bcfb-6a61f94cb9f2/scratchpad/sim/sim.log"
Report.writeLog(logPath)
print("full log: " .. logPath)
process.exit(if Report.errorCount() > 0 then 1 else 0)

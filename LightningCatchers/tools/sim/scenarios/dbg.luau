--!nocheck
local roblox = require("@lune/roblox")
local Bot = require("../lib/bot")
return { run = function(S)
	local Runtime, Sched, World, Engine = S.Runtime, S.Sched, S.World, S.Engine
	local DATA = Engine.DATA
	Runtime.startServer()
	Sched.runUntil(1)
	local realm = Runtime.addPlayer({ userId = 1002, name = "BotTwo", viewport = roblox.Vector2.new(844, 390), touch = true })
	local b = Bot.new(realm, { perfect = 0.3, good = 0.4, ignore = 0.1, seed = 1 })
	Sched.runUntil(8)
	b:attach()
	b:run(function() b:state().OpenWindow:Fire("Daily") end)
	Sched.runUntil(10)
	local win = b:findGui("Window_Daily")
	local input = b:findDesc(win, "Input", "TextBox")
	local redeem = b:findDesc(win, "Redeem", "GuiButton")
	print("win", win and Engine.fullName(win), "input", input and Engine.fullName(input), "redeem", redeem and Engine.fullName(redeem))
	local s = redeem.sigs and redeem.sigs.Activated
	print("activated conns", s and #s.conns, s and s.conns[1] and s.conns[1].realm.name)
	b:run(function() input.proxy.Text = "ГРОЗА" end)
	Sched.flush()
	print("text now", Engine.readProp(input, "Text", realm))
	b:click(redeem)
	Sched.runUntil(12)
	return "dbg done"
end }

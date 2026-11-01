-- expect: strict
-- Fixture for tools/checks/selftest.py (checked as a Lune-safe module by conventions.py).
local x = Instance.new("Part", nil) -- expect: instance-parent
wait(1) -- expect: banned-api
task.wait(1)
local s = "wait(1) RenderStepped"
-- wait(2) in a comment is fine
local bv = Instance.new("BodyVelocity") -- expect: banned-api
local rs = game:GetService("RunService") -- expect: lune-safe
spawn(function() end) -- check:ignore(banned-api)
local r = Random.new(1) -- expect: determinism
local y = require(game.ReplicatedStorage.X) -- expect: lune-require, lune-safe
local function delay(n: number) return n end
delay(2)
local cfg = { Delay = 0.75, Wait = 1 }
print(x, s, bv, rs, r, y, cfg, workspace) -- expect: lune-safe
local anim = nil :: any
anim:LoadAnimation(nil) -- expect: banned-api

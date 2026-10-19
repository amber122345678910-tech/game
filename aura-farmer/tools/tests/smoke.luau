--!nocheck
local Loader = require("../lib/loader")
local World = require("../lib/World")
local Pose = require("../lib/Pose")
local roblox = require("@lune/roblox")
local KFS = Loader.load("src/shared/Anim/KFS")
local FK = Loader.load("src/shared/Anim/FK")
local w = World.build({ shots = { "S03", "S04" } })
for _, s in w.stats do print(s) end
-- IK test on horse
local Skel = require("../chars/HorseSkeleton")
local rig = Skel.new("T")
local solver = Pose.solver(rig)
local keys = {
  { t = 0, rArm = { ik = { 0.5, 3.0, 0.8 }, space = "body" }, lArm = { ik = { -0.5, 3.0, 0.8 } }, waist = { bend = 10, turn = 20 } },
}
local tracks = Pose.tracks(keys, solver)
local tr = Pose.evaluate(tracks, solver, 0)
local cfs = solver:fk(tr)
local wrist = (cfs.RightLowerArm * rig.motors.RightHand.C0).Position
print("right wrist", wrist, "target", roblox.Vector3.new(0.5, 3.0, -0.8))
local wristL = (cfs.LeftLowerArm * rig.motors.LeftHand.C0).Position
print("left wrist", wristL)
-- KFS round trip on S03 man
local e = w.shots.S03.actors.Man
print("kfs", e.kfs, e.kfs and #e.kfs:GetChildren())
local clip = KFS.compile(e.kfs)
local out = {}
KFS.sample(clip, 0.5, out)
local frig = FK.build(e.model)
local cf = {}
FK.solve(frig, frig.root.CFrame, out, cf)
print("fk parts", #frig.parts, cf[#cf])

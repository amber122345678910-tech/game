-- Procedural animation for NPC rigs (R6 family + Rick) and big rigs (Titan, entity).
-- Poses are tables of jointName -> CFrame (joint Transform). Layers: walking, talking, breathing,
-- look-at, glitch. Applied every frame in PreSimulation.
local RunService = game:GetService("RunService")

local Puppet = {}
Puppet.__index = Puppet

local active: { any } = {}

----------------------------------------------------------------------------
-- R6 joint helpers (R6 joints have rotated frames)
----------------------------------------------------------------------------
local R6 = {}
-- forward > 0 swings the limb forward; out > 0 lifts the arm sideways away from the body
function R6.arm(side: number, forward: number, out: number?): CFrame
	return CFrame.Angles(0, 0, side * forward) * CFrame.Angles(-(out or 0), 0, 0)
end
function R6.leg(side: number, forward: number): CFrame
	return CFrame.Angles(0, 0, side * forward)
end
-- yaw > 0 turns the head left, pitch > 0 nods down
function R6.neck(yaw: number, pitch: number): CFrame
	return CFrame.Angles(pitch, 0, yaw)
end
-- lean > 0 leans forward, yaw > 0 twists left
function R6.root(lean: number, yaw: number?): CFrame
	return CFrame.Angles(lean, 0, yaw or 0)
end
Puppet.R6 = R6

-- ready-made R6 poses
local poses = {}
poses.stand = {}
poses.sit = {
	["Right Hip"] = R6.leg(1, 1.57),
	["Left Hip"] = R6.leg(-1, 1.57),
	["Right Shoulder"] = R6.arm(1, 0.45, 0.05),
	["Left Shoulder"] = R6.arm(-1, 0.45, 0.05),
}
poses.sitEat = {
	["Right Hip"] = R6.leg(1, 1.57),
	["Left Hip"] = R6.leg(-1, 1.57),
	["Right Shoulder"] = R6.arm(1, 0.9, 0.1),
	["Left Shoulder"] = R6.arm(-1, 0.55, 0.05),
	Neck = R6.neck(0, 0.25),
}
poses.sitRead = {
	["Right Hip"] = R6.leg(1, 1.57),
	["Left Hip"] = R6.leg(-1, 1.57),
	["Right Shoulder"] = R6.arm(1, 1.25, -0.25),
	["Left Shoulder"] = R6.arm(-1, 1.25, -0.25),
	Neck = R6.neck(0, 0.3),
}
poses.sitPhone = {
	["Right Hip"] = R6.leg(1, 1.57),
	["Left Hip"] = R6.leg(-1, 1.57),
	["Right Shoulder"] = R6.arm(1, 1.1, -0.35),
	["Left Shoulder"] = R6.arm(-1, 1.1, -0.35),
	Neck = R6.neck(0, 0.45),
}
poses.sitPoint = {
	["Right Hip"] = R6.leg(1, 1.57),
	["Left Hip"] = R6.leg(-1, 1.57),
	["Right Shoulder"] = R6.arm(1, 1.55, 0.15),
	["Left Shoulder"] = R6.arm(-1, 0.4, 0.05),
	RootJoint = R6.root(0.12),
}
poses.standPoint = {
	["Right Shoulder"] = R6.arm(1, 1.5, 0.1),
	["Left Shoulder"] = R6.arm(-1, 0.1, 0.25),
	RootJoint = R6.root(0.08),
}
poses.shocked = {
	["Right Shoulder"] = R6.arm(1, 2.6, 0.3),
	["Left Shoulder"] = R6.arm(-1, 2.6, 0.3),
	RootJoint = R6.root(-0.15),
	Neck = R6.neck(0, -0.2),
}
poses.sitShocked = {
	["Right Hip"] = R6.leg(1, 1.2),
	["Left Hip"] = R6.leg(-1, 1.2),
	["Right Shoulder"] = R6.arm(1, 2.4, 0.4),
	["Left Shoulder"] = R6.arm(-1, 2.4, 0.4),
	RootJoint = R6.root(-0.3),
	Neck = R6.neck(0, -0.25),
}
poses.lean = {
	RootJoint = R6.root(0.55),
	Neck = R6.neck(0, 0.35),
	["Right Shoulder"] = R6.arm(1, 0.5, 0.1),
	["Left Shoulder"] = R6.arm(-1, 0.5, 0.1),
}
poses.handsOnHips = {
	["Right Shoulder"] = R6.arm(1, -0.2, 0.55),
	["Left Shoulder"] = R6.arm(-1, -0.2, 0.55),
}
poses.holdRadar = {
	["Right Shoulder"] = R6.arm(1, 1.25, -0.15),
	["Left Shoulder"] = R6.arm(-1, 1.15, -0.2),
	Neck = R6.neck(0, 0.45),
}
poses.drag = {
	RootJoint = R6.root(0.35),
	["Right Shoulder"] = R6.arm(1, -1.2, 0.1),
	["Left Shoulder"] = R6.arm(-1, 0.6, 0),
}
poses.crawl = {
	RootJoint = R6.root(1.2),
	["Right Shoulder"] = R6.arm(1, 1.5, 0.2),
	["Left Shoulder"] = R6.arm(-1, 1.5, 0.2),
	["Right Hip"] = R6.leg(1, 0.6),
	["Left Hip"] = R6.leg(-1, 0.6),
	Neck = R6.neck(0, -0.6),
}
poses.cough = {
	RootJoint = R6.root(0.35),
	["Right Shoulder"] = R6.arm(1, 2.2, -0.3),
	Neck = R6.neck(0, 0.4),
}
poses.pilot = {
	["Right Hip"] = R6.leg(1, 1.4),
	["Left Hip"] = R6.leg(-1, 1.4),
	["Right Shoulder"] = R6.arm(1, 1.15, 0),
	["Left Shoulder"] = R6.arm(-1, 1.15, 0),
}
poses.wave = {
	["Right Shoulder"] = R6.arm(1, 0.3, 2.6),
}
Puppet.Poses = poses

----------------------------------------------------------------------------
function Puppet.new(model: Model, kind: string?)
	local self = setmetatable({}, Puppet)
	self.model = model
	self.kind = kind or "R6"
	self.root = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Root")) :: BasePart
	self.joints = {} :: { [string]: Motor6D }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			self.joints[d.Name] = d
		end
	end
	self.target = {} :: { [string]: CFrame }
	self.current = {} :: { [string]: CFrame }
	self.smooth = 8
	self.t = math.random() * 10
	self.walk = 0
	self.walkPhase = 0
	self.walkSpeed = 0
	self.talking = false
	self.gesture = 1
	self.glitch = 0
	self.lookTarget = nil :: Vector3?
	self.follow = nil :: ((number) -> CFrame)?
	self.extra = nil :: ((number, number) -> { [string]: CFrame })?
	self.blinkAt = os.clock() + 2 + math.random() * 3
	self.parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(self.parts, d)
			if d.Name == "EyeL" or d.Name == "EyeR" or d.Name == "Mouth" then
				d:SetAttribute("BaseSize", d.Size)
			end
		end
	end
	table.insert(active, self)
	return self
end

function Puppet:destroy()
	local i = table.find(active, self)
	if i then
		table.remove(active, i)
	end
end

function Puppet:pose(nameOrTable: any, smooth: number?)
	local p = if type(nameOrTable) == "string" then poses[nameOrTable] else nameOrTable
	table.clear(self.target)
	for k, cf in p or {} do
		self.target[k] = cf
	end
	if smooth then
		self.smooth = smooth
	end
end

function Puppet:set(joint: string, cf: CFrame?)
	self.target[joint] = cf
end

function Puppet:snap()
	for name, joint in self.joints do
		local cf = self.target[name] or CFrame.new()
		self.current[name] = cf
		joint.Transform = cf
	end
end

function Puppet:place(cf: CFrame)
	self.follow = nil
	self.root.CFrame = cf
end

function Puppet:visible(on: boolean)
	for _, p in self.parts do
		p.LocalTransparencyModifier = if on then 0 else 1
	end
	self.hidden = not on
end

-- walk (anchored root slides on a flat plane). Yields until arrived.
function Puppet:walkTo(pos: Vector3, speed: number?, faceAtEnd: Vector3?)
	local sp = speed or 9
	self.follow = nil
	self.walk = 1
	self.walkSpeed = sp
	local y = self.root.Position.Y
	local goal = Vector3.new(pos.X, y, pos.Z)
	while true do
		local dt = RunService.Heartbeat:Wait()
		local cur = self.root.Position
		local delta = goal - cur
		local dist = delta.Magnitude
		if dist < 0.25 then
			break
		end
		local stepLen = math.min(dist, sp * dt)
		local dir = delta.Unit
		local newPos = cur + dir * stepLen
		local look = self.root.CFrame.LookVector
		local wantLook = Vector3.new(dir.X, 0, dir.Z).Unit
		local lerped = look:Lerp(wantLook, math.min(1, dt * 8))
		if lerped.Magnitude < 0.01 then
			lerped = wantLook
		end
		self.root.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(lerped.X, 0, lerped.Z))
	end
	self.walk = 0
	if faceAtEnd then
		self:face(faceAtEnd)
	end
end

function Puppet:face(pos: Vector3, instant: boolean?)
	local p = self.root.Position
	local target = Vector3.new(pos.X, p.Y, pos.Z)
	if (target - p).Magnitude < 0.01 then
		return
	end
	if instant then
		self.root.CFrame = CFrame.lookAt(p, target)
		return
	end
	local from = self.root.CFrame
	local to = CFrame.lookAt(p, target)
	task.spawn(function()
		local t = 0
		while t < 1 do
			t += RunService.Heartbeat:Wait() * 4
			self.root.CFrame = from:Lerp(to, math.min(t, 1))
		end
	end)
end

function Puppet:lookAt(pos: Vector3?)
	self.lookTarget = pos
end

----------------------------------------------------------------------------
local function headAngles(self, neckJoint: Motor6D): (number, number)
	local target = self.lookTarget
	if not target then
		return 0, 0
	end
	local part0 = neckJoint.Part0
	if not part0 then
		return 0, 0
	end
	local origin = part0.CFrame * neckJoint.C0
	local rel = part0.CFrame:VectorToObjectSpace(target - origin.Position)
	local yaw = math.atan2(-rel.X, -rel.Z)
	local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
	local pitch = math.atan2(-rel.Y, flat)
	return math.clamp(yaw, -1.1, 1.1), math.clamp(pitch, -0.7, 0.7)
end

function Puppet:_step(dt: number)
	self.t += dt
	local t = self.t
	if self.follow then
		self.root.CFrame = self.follow(dt)
	end
	local out: { [string]: CFrame } = {}
	for k, cf in self.target do
		out[k] = cf
	end
	local function mul(name: string, cf: CFrame)
		out[name] = (out[name] or CFrame.new()) * cf
	end

	if self.kind == "R6" then
		-- walking
		if self.walk > 0 then
			self.walkPhase += dt * (self.walkSpeed or 9) * 0.9
			local a = math.sin(self.walkPhase) * 0.75 * self.walk
			mul("Right Hip", R6.leg(1, a))
			mul("Left Hip", R6.leg(-1, -a))
			mul("Right Shoulder", R6.arm(1, -a * 0.8))
			mul("Left Shoulder", R6.arm(-1, a * 0.8))
			mul("RootJoint", R6.root(0.05, math.sin(self.walkPhase) * 0.05))
		else
			-- breathing / idle sway
			mul("RootJoint", R6.root(math.sin(t * 1.4) * 0.012, math.sin(t * 0.45) * 0.02))
		end
		-- talking gestures + head
		local yaw, pitch = 0, 0
		if self.joints.Neck then
			yaw, pitch = headAngles(self, self.joints.Neck)
		end
		if self.talking then
			pitch += math.sin(t * 7.3) * 0.05 + math.sin(t * 3.1) * 0.04
			yaw += math.sin(t * 2.2) * 0.08
			if self.walk == 0 and self.gesture > 0 then
				mul("Right Shoulder", R6.arm(1, (0.25 + 0.2 * math.sin(t * 2.6)) * self.gesture, 0.15 * self.gesture))
				mul("Left Shoulder", R6.arm(-1, (0.12 + 0.12 * math.sin(t * 2.1 + 1)) * self.gesture, 0.1 * self.gesture))
			end
		end
		mul("Neck", R6.neck(yaw, pitch))
	else
		-- big rigs: gentle idle on the root
		local yaw, pitch = 0, 0
		if self.joints.Neck then
			yaw, pitch = headAngles(self, self.joints.Neck)
		end
		mul("Neck", CFrame.Angles(-pitch, yaw, 0))
	end
	if self.extra then
		for k, cf in self.extra(t, dt) do
			mul(k, cf)
		end
	end

	-- glitch: random twitches + flicker
	if self.glitch > 0 and not self.hidden then
		if math.random() < self.glitch * 0.18 then
			for name in self.joints do
				if math.random() < 0.4 then
					mul(name, CFrame.Angles((math.random() - 0.5) * self.glitch, (math.random() - 0.5) * self.glitch, (math.random() - 0.5) * self.glitch))
				end
			end
		end
		if math.random() < self.glitch * 0.08 then
			local victims = {}
			for i = 1, math.random(2, 8) do
				local p = self.parts[math.random(1, #self.parts)]
				if p and p.Transparency < 1 then
					table.insert(victims, p)
					p.LocalTransparencyModifier = if math.random() < 0.5 then 1 else 0.6
				end
				local _ = i
			end
			task.delay(0.05 + math.random() * 0.08, function()
				if not self.hidden then
					for _, p in victims do
						p.LocalTransparencyModifier = 0
					end
				end
			end)
		end
	end

	-- blink + mouth
	local now = os.clock()
	if now > self.blinkAt then
		self.blinkAt = now + 2.5 + math.random() * 4
		for _, p in self.parts do
			if p.Name == "EyeL" or p.Name == "EyeR" then
				local base = p:GetAttribute("BaseSize")
				if base then
					p.Size = Vector3.new(base.X, base.Y * 0.12, base.Z)
					task.delay(0.12, function()
						p.Size = base
					end)
				end
			end
		end
	end
	for _, p in self.parts do
		if p.Name == "Mouth" then
			local base = p:GetAttribute("BaseSize")
			if base then
				local open = if self.talking then math.max(0, math.sin(t * 16) * 0.5 + math.sin(t * 9.7) * 0.5) else 0
				p.Size = Vector3.new(base.X, base.Y + open * 0.32, base.Z)
			end
		end
	end

	-- smooth + apply
	local k = 1 - math.exp(-self.smooth * dt)
	for name, joint in self.joints do
		local goal = out[name] or CFrame.new()
		local cur = self.current[name] or CFrame.new()
		cur = cur:Lerp(goal, k)
		self.current[name] = cur
		joint.Transform = cur
	end
end

RunService.PreSimulation:Connect(function(dt)
	for _, p in active do
		local ok, err = pcall(p._step, p, dt)
		if not ok then
			warn("Puppet error:", err)
		end
	end
end)

return Puppet

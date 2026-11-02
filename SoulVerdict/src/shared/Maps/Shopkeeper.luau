--!strict
-- Maps/Shopkeeper: "sleepy Sans", the shopkeeper NPC behind the lobby ShopBooth counter. [Lune-safe]
-- Maps/Lobby (buildShop) builds him INTO the lobby map, perched on a tall stool behind the counter: a ClassicSans
-- rig (Rigs/RigBuilder) posed asleep (SleepPose: slumped over the counter, forearms crossed on the counter top,
-- skull tipped sideways onto them, eyes shut), then frozen like the lobby statues: every part Anchored,
-- CanCollide / CanQuery / CanTouch false, no Humanoid, no joints, no lights. Players walk through him, raycasts /
-- bots / targeting never see him and he is not a round character (no Humanoid, not in workspace.Bots).
-- Controllers/ShopkeeperController animates him locally on each client (breathing, waking up, looking at the
-- local player, Zzz, speech bubble) with the pure forward kinematics below: every physics limb keeps its joint as
-- attributes, so any pose can be solved without Motor6Ds, and each limb's visual parts follow their limb.
--
-- API
--   Shopkeeper.NAME                 "ShopkeeperSans" (the Model's name, under Decor/ShopBooth)
--   Shopkeeper.BLUEPRINT, SCALE     "ClassicSans" at 1.1 (the size of the Classic Sans kit)
--   Shopkeeper.SEAT_TO_ROOT         studs (at scale 1) from the stool's seat top to the HumanoidRootPart
--   Shopkeeper.SleepPose : Pose     RigBuilder pose (degrees, see Rigs/Skeletons header): asleep on the counter
--   Shopkeeper.AwakePose : Pose     the same seat and arms, torso propped up a little, skull upright facing the
--                                   customers (ShopkeeperController turns the head towards the player on top)
--   Shopkeeper.EYES                 { "LeftPupil", "RightPupil" }: Head descendants, hidden while asleep
--   Shopkeeper.LIDS                 closed-eye lids + lash lines over the sockets: Head descendants, shown asleep
--   Shopkeeper.Build(seat: CFrame, opts?) -> Model
--       seat = top centre of the stool seat; LookVector = the way he faces (towards the customers).
--       opts = { Scale: number?, Pose: Pose? (default SleepPose), Awake: boolean? (eyes open; previews/tests) }
--   Shopkeeper.Joints(model) -> { JointInfo }   { Name, Limb, Parent, C0, C1, C1Inv } read from the limb
--       attributes, parents first (empty when the attributes are missing)
--   Shopkeeper.Transforms(pose, scale?) -> { [jointName]: CFrame }   (RigBuilder.PoseToCFrame per joint)
--   Shopkeeper.Solve(rootCF, joints, transforms) -> { [limbName]: CFrame }
--       limb = parent * C0 * Transform * C1^-1 (Motor6D maths); HumanoidRootPart = rootCF; a joint missing from
--       transforms = identity. Solving SleepPose reproduces the built model exactly.
-- Model attributes: Shopkeeper = true, BlueprintId, RigScale, RigFamily, PartCount, ZzzOffset / BubbleOffset
--   (Vector3 in HumanoidRootPart space: where the Zzz rise from above the sleeping skull / where the speech bubble
--   sits above the awake skull). Limb attributes (physics parts): Joint, JointParent, JointC0, JointC1 (CFrame).

local RigBuilder = require(script.Parent.Parent.Rigs.RigBuilder)

export type Pose = { [string]: { number } }
export type JointInfo = { Name: string, Limb: string, Parent: string, C0: CFrame, C1: CFrame, C1Inv: CFrame }

local Shopkeeper = {}

Shopkeeper.NAME = "ShopkeeperSans"
Shopkeeper.BLUEPRINT = "ClassicSans"
Shopkeeper.SCALE = 1.1 -- same size as the Classic Sans kit
Shopkeeper.SEAT_TO_ROOT = 0.55

Shopkeeper.EYES = { "LeftPupil", "RightPupil" }
Shopkeeper.LIDS = { "LeftLid", "RightLid", "LeftLidLine", "RightLidLine" }

-- Asleep on the counter: sitting on the stool (thighs level, shins and slippers dangling), the torso slumped 62 deg
-- forward over the counter, the forearms crossed flat on the counter top (palms down, the left one in front), the
-- skull rolled ~30 deg onto them and turned a little towards the customers so the shut eyes and the grin stay
-- readable from the plaza. Solved from target elbow/wrist positions (seat space) and rounded.
Shopkeeper.SleepPose = {
	Root = { 0, 0, 0 },
	Waist = { -62, 0, 0 },
	Neck = { 51.8, 11.8, 30.1 },
	LeftShoulder = { 120, -35.9, 30.6 },
	LeftElbow = { 45.9, 9.2, 21.4 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = { 122.6, 45.2, -39.5 },
	RightElbow = { 51.5, -9.5, -19.6 },
	RightWrist = { 0, 0, 0 },
	LeftHip = { 88, 0, -6 },
	LeftKnee = { -88, 0, 0 },
	LeftAnkle = { -18, 0, 0 },
	RightHip = { 88, 0, 6 },
	RightKnee = { -88, 0, 0 },
	RightAnkle = { -18, 0, 0 },
} :: Pose

-- Awake: the torso props itself up by 5 deg (the shoulders re-solved so the crossed forearms stay on the
-- counter), the skull upright and tilted up a touch, facing the customers.
Shopkeeper.AwakePose = {
	Root = { 0, 0, 0 },
	Waist = { -57, 0, 0 },
	Neck = { 63, 0, 0 },
	LeftShoulder = { 108.2, -42.3, 28.8 },
	LeftElbow = { 54.3, 9, 17.5 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = { 112.1, 52.2, -38.6 },
	RightElbow = { 59.5, -8.6, -15.1 },
	RightWrist = { 0, 0, 0 },
	LeftHip = { 88, 0, -6 },
	LeftKnee = { -88, 0, 0 },
	LeftAnkle = { -18, 0, 0 },
	RightHip = { 88, 0, 6 },
	RightKnee = { -88, 0, 0 },
	RightAnkle = { -18, 0, 0 },
} :: Pose

-- Parts the sleepy shopkeeper does without: the attack-eye glow ring (a dozing shopkeeper has no glowing eye)
-- and the open-jacket hem flaps, which stick out of his back once the torso leans over the counter.
local DROP: { [string]: boolean } = { LeftIris = true, LeftHem = true, RightHem = true }
local IDENTITY = CFrame.new()

-- Closed eyes: a bone-coloured lid over each (black) socket and a dark lash line across it. Built in the rest
-- pose (before forward kinematics) and welded to the Head so they follow it like every other Head part.
local function addLids(rig: Model)
	local head = rig:FindFirstChild("Head")
	local cranium = head and head:FindFirstChild("Cranium")
	if head == nil or cranium == nil or not cranium:IsA("BasePart") then
		return
	end
	for _, side in { "Left", "Right" } do
		local socket = head:FindFirstChild(side .. "Socket")
		if socket and socket:IsA("BasePart") then
			local size = socket.Size
			local lid = socket:Clone()
			lid:ClearAllChildren()
			local mesh = socket:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh:Clone().Parent = lid
			end
			lid.Name = side .. "Lid"
			lid.Size = Vector3.new(size.X * 1.08, size.Y * 1.1, size.Z)
			lid.CFrame = socket.CFrame * CFrame.new(0, 0, -0.035)
			lid.Color = cranium.Color
			lid.Material = cranium.Material
			lid:SetAttribute("Role", "Bone")
			lid:SetAttribute("HDGroup", nil)
			lid.Parent = head
			local line = lid:Clone()
			line.Name = side .. "LidLine"
			line.Size = Vector3.new(size.X * 0.92, size.Y * 0.16, size.Z * 1.04)
			line.CFrame = lid.CFrame * CFrame.new(0, -size.Y * 0.08, -0.004)
			line.Color = Color3.fromRGB(34, 30, 34)
			line.Material = Enum.Material.SmoothPlastic
			line:SetAttribute("Role", "Line")
			line.Parent = head
			for _, part in { lid, line } do -- welded like every visual part, so forward kinematics carries them
				local weld = Instance.new("WeldConstraint")
				weld.Name = "Weld"
				weld.Part0 = head :: BasePart
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
end

function Shopkeeper.Transforms(pose: Pose, scale: number?): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	for name, value in pose do
		out[name] = RigBuilder.PoseToCFrame(value, scale)
	end
	return out
end

function Shopkeeper.Joints(model: Model): { JointInfo }
	local list: { JointInfo } = {}
	for _, limb in model:GetChildren() do
		if limb:IsA("BasePart") then
			local name, parent = limb:GetAttribute("Joint"), limb:GetAttribute("JointParent")
			local c0, c1 = limb:GetAttribute("JointC0"), limb:GetAttribute("JointC1")
			if type(name) == "string" and type(parent) == "string" and typeof(c0) == "CFrame" and typeof(c1) == "CFrame" then
				table.insert(list, { Name = name, Limb = limb.Name, Parent = parent, C0 = c0, C1 = c1, C1Inv = c1:Inverse() })
			end
		end
	end
	-- parents first (the HumanoidRootPart is the root of the tree); limbs whose chain is broken are dropped
	local ordered: { JointInfo } = {}
	local placed: { [string]: boolean } = { HumanoidRootPart = true }
	local progress = true
	while progress do
		progress = false
		for _, joint in list do
			if not placed[joint.Limb] and placed[joint.Parent] then
				placed[joint.Limb] = true
				table.insert(ordered, joint)
				progress = true
			end
		end
	end
	return ordered
end

function Shopkeeper.Solve(rootCF: CFrame, joints: { JointInfo }, transforms: { [string]: CFrame }): { [string]: CFrame }
	local out: { [string]: CFrame } = { HumanoidRootPart = rootCF }
	for _, joint in joints do
		local parentCF = out[joint.Parent]
		if parentCF then
			out[joint.Limb] = parentCF * joint.C0 * (transforms[joint.Name] or IDENTITY) * joint.C1Inv
		end
	end
	return out
end

function Shopkeeper.Build(seat: CFrame, opts: { [string]: any }?): Model
	local options = opts or {}
	local scale = if type(options.Scale) == "number" and options.Scale > 0 then options.Scale else Shopkeeper.SCALE
	local pose: Pose = if type(options.Pose) == "table" then options.Pose else Shopkeeper.SleepPose
	local awake = options.Awake == true
	local rig = RigBuilder.Build(Shopkeeper.BLUEPRINT, { Name = Shopkeeper.NAME, Scale = scale })
	local rigScale = rig:GetAttribute("RigScale")
	local s = if type(rigScale) == "number" then rigScale else scale
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = rig:FindFirstChild("Head") :: BasePart
	local rootCF = seat * CFrame.new(0, Shopkeeper.SEAT_TO_ROOT * s, 0)
	addLids(rig)

	-- remember every joint on its child limb (C0/C1 after RigBuilder's rescale): the client solves poses from these
	for _, inst in rig:GetDescendants() do
		if inst:IsA("Motor6D") then
			local part0, part1 = inst.Part0, inst.Part1
			if part0 and part1 then
				part1:SetAttribute("Joint", inst.Name)
				part1:SetAttribute("JointParent", part0.Name)
				part1:SetAttribute("JointC0", inst.C0)
				part1:SetAttribute("JointC1", inst.C1)
			end
		end
	end

	-- forward kinematics straight into world space
	for _, entry in RigBuilder.ComputeWorldCFrameList(rig, pose, { RootCFrame = rootCF }) do
		entry.Part.CFrame = entry.CFrame
	end

	-- where the Zzz rise (above the sleeping skull) and where the speech bubble sits (above the awake skull)
	local joints = Shopkeeper.Joints(rig)
	local rootInv = rootCF:Inverse()
	local function headTop(p: Pose): Vector3
		local limbs = Shopkeeper.Solve(rootCF, joints, Shopkeeper.Transforms(p, s))
		local headCF = limbs.Head or head.CFrame
		return rootInv * (headCF.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
	end
	rig:SetAttribute("ZzzOffset", headTop(Shopkeeper.SleepPose) + Vector3.new(0, 0.3 * s, 0))
	rig:SetAttribute("BubbleOffset", headTop(Shopkeeper.AwakePose) + Vector3.new(0, 0.75 * s, 0))

	-- freeze: anchored, ghost-like (no collisions / queries / touches), no Humanoid, joints or lights
	local doomed: { Instance } = {}
	local parts = 0
	for _, inst in rig:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			if DROP[inst.Name] then
				table.insert(doomed, inst)
			else
				parts += 1
				if table.find(Shopkeeper.EYES, inst.Name) then
					inst.Transparency = if awake then 0 else 1 -- eyes shut (ShopkeeperController opens them)
				elseif table.find(Shopkeeper.LIDS, inst.Name) then
					inst.Transparency = if awake then 1 else 0
				end
			end
		elseif inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("Humanoid") or inst:IsA("Light") then
			table.insert(doomed, inst)
		end
	end
	for _, inst in doomed do
		inst:Destroy()
	end
	rig.PrimaryPart = root
	rig:SetAttribute("Shopkeeper", true)
	rig:SetAttribute("PartCount", parts)
	return rig
end

return Shopkeeper

--!strict
-- Maps/Shopkeeper: "sleepy Sans", the shopkeeper NPC behind the lobby ShopBooth counter. [Lune-safe]
-- Maps/Lobby (buildShop) builds him INTO the lobby map: a ClassicSans rig (Rigs/RigBuilder) posed asleep
-- (Shopkeeper.SleepPose: perched on a tall stool, slumped forward over the counter, skull resting on his
-- folded arms), then frozen like the lobby statues (LobbyController.freeze): every part Anchored,
-- CanCollide / CanQuery / CanTouch false, no Humanoid, no joints, no lights. So players walk through him,
-- raycasts / bots / targeting never see him and he is not a round character (no Humanoid, not in
-- workspace.Bots). His eyes are shut: the pupils are transparent and the attack-eye iris is removed.
-- Controllers/ShopkeeperController animates him locally on each client (breathing, waking up, looking at
-- the local player, Zzz, speech bubble) by moving whole limb groups around the stored pivots.
--
-- API
--   Shopkeeper.NAME                    "ShopkeeperSans" (the Model's name, under Decor/ShopBooth)
--   Shopkeeper.BLUEPRINT, Shopkeeper.SCALE
--   Shopkeeper.SEAT_TO_ROOT            studs (at scale 1) from the stool's seat top to the HumanoidRootPart
--   Shopkeeper.SleepPose : Pose        RigBuilder pose (degrees, see Rigs/Skeletons header)
--   Shopkeeper.HEAD_LIMBS / UPPER_LIMBS   physics limbs whose sub-trees the client turns (head) / breathes
--                                      (upper body); every visual part is parented under its limb part
--   Shopkeeper.EYES                    { "LeftPupil", "RightPupil" } (Head descendants; shown while awake)
--   Shopkeeper.Build(seat: CFrame, opts?) -> Model
--       seat = top centre of the stool seat; LookVector = the way he faces (towards the customers).
--       opts = { Scale: number? }
--   Shopkeeper.Pivots(model) -> ({ Waist: CFrame, Neck: CFrame, Root: CFrame }?)   rest-pose joint pivots in
--       WORLD space (from the WaistPivot / NeckPivot attributes, stored relative to the HumanoidRootPart, so
--       they survive MapService moving the map). Rotation = the child limb's orientation in the sleep pose.
-- Model attributes: Shopkeeper = true, BlueprintId, RigScale, RigFamily, WaistPivot / NeckPivot (CFrame,
--   HumanoidRootPart space), PartCount.

local RigBuilder = require(script.Parent.Parent.Rigs.RigBuilder)

export type Pivots = { Root: CFrame, Waist: CFrame, Neck: CFrame }

local Shopkeeper = {}

Shopkeeper.NAME = "ShopkeeperSans"
Shopkeeper.BLUEPRINT = "ClassicSans"
Shopkeeper.SCALE = 1.1 -- same size as the Classic Sans kit
Shopkeeper.SEAT_TO_ROOT = 0.55

Shopkeeper.HEAD_LIMBS = { "Head" }
Shopkeeper.UPPER_LIMBS = { "UpperTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" }
Shopkeeper.EYES = { "LeftPupil", "RightPupil" }

-- Asleep on the counter. Sitting (hips 90, knees -90), the upper body slumped forward over the counter,
-- upper arms reaching down onto the counter top, forearms folded inwards under the chin, skull tipped
-- forward onto them and rolled a little to one side (cosy, and it shows a bit of the face).
Shopkeeper.SleepPose = {
	Root = { 0, 0, 0 },
	Waist = { -55, 0, 0 },
	Neck = { -22, 14, 10 },
	LeftShoulder = { 75, 0, -12 },
	LeftElbow = { 10, 0, 92 },
	LeftWrist = { 0, 0, 8 },
	RightShoulder = { 75, 0, 12 },
	RightElbow = { 14, 0, -92 },
	RightWrist = { 0, 0, -8 },
	LeftHip = { 88, 0, -8 },
	LeftKnee = { -84, 0, 0 },
	LeftAnkle = { 10, 0, 0 },
	RightHip = { 88, 0, 8 },
	RightKnee = { -84, 0, 0 },
	RightAnkle = { 10, 0, 0 },
}

local function motorPivot(motor: Motor6D): CFrame?
	local part1 = motor.Part1
	if part1 == nil then
		return nil
	end
	-- part1 = part0 * C0 * Transform * C1:Inverse()  =>  part1 * C1 = the joint pivot (child orientation)
	return part1.CFrame * motor.C1
end

function Shopkeeper.Build(seat: CFrame, opts: { [string]: any }?): Model
	local options = opts or {}
	local scale = if type(options.Scale) == "number" and options.Scale > 0 then options.Scale else Shopkeeper.SCALE
	local rig = RigBuilder.Build(Shopkeeper.BLUEPRINT, { Name = Shopkeeper.NAME, Scale = scale })
	local rigScale = rig:GetAttribute("RigScale")
	local s = if type(rigScale) == "number" then rigScale else scale
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local rootCF = seat * CFrame.new(0, Shopkeeper.SEAT_TO_ROOT * s, 0)

	-- forward kinematics straight into world space
	for _, entry in RigBuilder.ComputeWorldCFrameList(rig, Shopkeeper.SleepPose, { RootCFrame = rootCF }) do
		entry.Part.CFrame = entry.CFrame
	end

	-- remember the joint pivots the client animates around (relative to the root: the map may be moved)
	for _, inst in rig:GetDescendants() do
		if inst:IsA("Motor6D") and (inst.Name == "Waist" or inst.Name == "Neck") then
			local pivot = motorPivot(inst)
			if pivot then
				rig:SetAttribute(inst.Name .. "Pivot", root.CFrame:ToObjectSpace(pivot))
			end
		end
	end

	-- freeze: anchored, ghost-like (no collisions / queries / touches), no Humanoid, joints or lights
	local doomed: { Instance } = {}
	local parts = 0
	for _, inst in rig:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			if inst.Name == "LeftIris" then
				table.insert(doomed, inst) -- the attack-eye glow ring: a sleepy shopkeeper has no glowing eye
			elseif table.find(Shopkeeper.EYES, inst.Name) then
				inst.Transparency = 1 -- eyes shut (ShopkeeperController opens them)
				parts += 1
			else
				parts += 1
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

function Shopkeeper.Pivots(model: Model): Pivots?
	local root = model:FindFirstChild("HumanoidRootPart")
	local waist = model:GetAttribute("WaistPivot")
	local neck = model:GetAttribute("NeckPivot")
	if root == nil or not root:IsA("BasePart") or typeof(waist) ~= "CFrame" or typeof(neck) ~= "CFrame" then
		return nil
	end
	local rootCF = (root :: BasePart).CFrame
	return { Root = rootCF, Waist = rootCF * waist, Neck = rootCF * neck }
end

return Shopkeeper

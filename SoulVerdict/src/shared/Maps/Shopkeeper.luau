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
--   Shopkeeper.LIDS                    closed-eye lids + lash lines over the sockets (Head descendants; shown
--                                      while asleep, hidden while awake)
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
Shopkeeper.LIDS = { "LeftLid", "RightLid", "LeftLidLine", "RightLidLine" }

-- Asleep on the counter. Sitting (hips 90, knees -90), the upper body slumped forward over the counter,
-- upper arms reaching down onto the counter top, forearms folded inwards under the chin, skull tipped
-- forward onto them and rolled a little to one side (cosy, and it shows a bit of the face).
Shopkeeper.SleepPose = {
	Root = { 0, 0, 0 },
	Waist = { -55, 0, 0 },
	Neck = { 15, 10, 18 },
	LeftShoulder = { 65, 0, -8 },
	LeftElbow = { 0, 40, 90 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = { 65, 0, 8 },
	RightElbow = { 0, -40, -90 },
	RightWrist = { 0, 0, 0 },
	LeftHip = { 80, 0, -6 },
	LeftKnee = { -115, 0, 0 },
	LeftAnkle = { 15, 0, 0 },
	RightHip = { 80, 0, 6 },
	RightKnee = { -115, 0, 0 },
	RightAnkle = { 15, 0, 0 },
}

-- Parts the sleeping shopkeeper does without: the attack-eye glow ring (a dozing shopkeeper has no glowing
-- eye) and the open-jacket hem flaps, which stick out of his back once the torso leans over the counter.
local DROP: { [string]: boolean } = { LeftIris = true, LeftHem = true, RightHem = true }

local function motorPivot(motor: Motor6D): CFrame?
	local part1 = motor.Part1
	if part1 == nil then
		return nil
	end
	-- part1 = part0 * C0 * Transform * C1:Inverse()  =>  part1 * C1 = the joint pivot (child orientation)
	return part1.CFrame * motor.C1
end

-- Closed eyes: a bone-coloured lid over each (black) socket and a dark lash line across it. Built in the
-- rest pose (before forward kinematics) so they follow the head like every other Head part.
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

function Shopkeeper.Build(seat: CFrame, opts: { [string]: any }?): Model
	local options = opts or {}
	local scale = if type(options.Scale) == "number" and options.Scale > 0 then options.Scale else Shopkeeper.SCALE
	local rig = RigBuilder.Build(Shopkeeper.BLUEPRINT, { Name = Shopkeeper.NAME, Scale = scale })
	local rigScale = rig:GetAttribute("RigScale")
	local s = if type(rigScale) == "number" then rigScale else scale
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local rootCF = seat * CFrame.new(0, Shopkeeper.SEAT_TO_ROOT * s, 0)
	addLids(rig)

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
			if DROP[inst.Name] then
				table.insert(doomed, inst)
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

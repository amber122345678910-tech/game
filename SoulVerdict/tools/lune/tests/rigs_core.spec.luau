--!nocheck
-- Rig core: PartKit, Skeletons, RigBuilder, Blueprints registry, Dummy blueprint.
-- NOTE (Lune): Instance userdata are not identity-stable (a == b works, t[a] does not), so these
-- tests compare instances with == and never key tables by Instance.
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum, Instance =
	roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum, roblox.Instance

local SPEC_JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso" },
	Waist = { "LowerTorso", "UpperTorso" },
	Neck = { "UpperTorso", "Head" },
	LeftShoulder = { "UpperTorso", "LeftUpperArm" },
	RightShoulder = { "UpperTorso", "RightUpperArm" },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm" },
	RightElbow = { "RightUpperArm", "RightLowerArm" },
	LeftWrist = { "LeftLowerArm", "LeftHand" },
	RightWrist = { "RightLowerArm", "RightHand" },
	LeftHip = { "LowerTorso", "LeftUpperLeg" },
	RightHip = { "LowerTorso", "RightUpperLeg" },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg" },
	RightKnee = { "RightUpperLeg", "RightLowerLeg" },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot" },
	RightAnkle = { "RightLowerLeg", "RightFoot" },
}

local LIMBS = {
	"HumanoidRootPart",
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local ATTACHMENTS = {
	RootAttachment = "HumanoidRootPart",
	LeftEye = "Head",
	RightEye = "Head",
	Mouth = "Head",
	HeadTop = "Head",
	Chest = "UpperTorso",
	Back = "UpperTorso",
	LeftGrip = "LeftHand",
	RightGrip = "RightHand",
	LeftFootAttachment = "LeftFoot",
	RightFootAttachment = "RightFoot",
}

local ROLES = {
	Skin = true,
	Bone = true,
	Cloth = true,
	ClothAlt = true,
	Trim = true,
	Accent = true,
	Eye = true,
	Glow = true,
	Hair = true,
	Metal = true,
	Weapon = true,
	Detail = true,
	Dark = true,
}

local function isLimbName(name)
	return table.find(LIMBS, name) ~= nil
end

local function isIdentityRotation(cf)
	local c = { cf:GetComponents() }
	local id = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	for i = 1, 9 do
		if math.abs(c[i + 3] - id[i]) > 1e-5 then
			return false
		end
	end
	return true
end

local function finite(cf)
	for _, v in { cf:GetComponents() } do
		if v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	return true
end

local function lookup(list, part)
	for _, e in list do
		if e.Part == part then
			return e.CFrame
		end
	end
	return nil
end

local function rig(Loader, opts)
	local RigBuilder = Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder")
	return RigBuilder, RigBuilder.Build("Dummy", opts)
end

return {
	dummy_physics_parts = function(T, Loader)
		local _, model = rig(Loader)
		T.ok(model:IsA("Model"), "Build returns a Model")
		T.eq(model.Name, "Dummy", "model name")
		T.ok(model.Parent == nil, "parent is nil")
		local hrp = model:FindFirstChild("HumanoidRootPart")
		T.ok(model.PrimaryPart ~= nil and model.PrimaryPart == hrp, "PrimaryPart = HumanoidRootPart")
		for _, name in LIMBS do
			local p = model:FindFirstChild(name)
			if T.ok(p ~= nil and p:IsA("BasePart"), "physics part " .. name) then
				T.eq(p.Transparency, 1, name .. " transparent")
				T.eq(p.Massless, false, name .. " not massless")
				T.eq(p.CanQuery, true, name .. " CanQuery")
				T.eq(p.CanTouch, true, name .. " CanTouch")
				T.eq(p.Anchored, false, name .. " unanchored")
				T.eq(p.CastShadow, false, name .. " no shadow")
				local collide = name == "LowerTorso" or name == "UpperTorso" or name == "Head"
				T.eq(p.CanCollide, collide, name .. " CanCollide")
				T.ok(isIdentityRotation(p.CFrame), name .. " axis-aligned at rest")
			end
		end
		T.ok(hrp.Size == Vector3.new(2, 2, 1), "HRP size 2x2x1")
	end,

	dummy_motors_follow_spec = function(T, Loader)
		local RigBuilder, model = rig(Loader)
		local motors = {}
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				table.insert(motors, d)
			end
		end
		T.eq(#motors, 15, "15 Motor6Ds")
		local names = RigBuilder.GetJointNames()
		T.eq(#names, 15, "GetJointNames")
		for _, m in motors do
			local spec = SPEC_JOINTS[m.Name]
			if T.ok(spec ~= nil, "unexpected motor " .. m.Name) then
				T.eq(m.Part0 and m.Part0.Name, spec[1], m.Name .. ".Part0")
				T.eq(m.Part1 and m.Part1.Name, spec[2], m.Name .. ".Part1")
				T.ok(m.Parent == m.Part1, m.Name .. " parented to Part1")
				T.ok(isIdentityRotation(m.C0) and isIdentityRotation(m.C1), m.Name .. " identity C0/C1 rotation")
				-- pivot consistency: Part0 * C0 == Part1 * C1 at rest
				local a = (m.Part0.CFrame * m.C0).Position
				local b = (m.Part1.CFrame * m.C1).Position
				T.ok((a - b).Magnitude < 1e-4, m.Name .. " C0/C1 agree on the pivot")
			end
		end
		for name in SPEC_JOINTS do
			T.ok(model:FindFirstChild(name, true) ~= nil, "motor " .. name .. " exists")
		end
	end,

	dummy_humanoid_and_attributes = function(T, Loader)
		local _, model = rig(Loader)
		local h = model:FindFirstChildOfClass("Humanoid")
		if T.ok(h ~= nil, "Humanoid") then
			T.ok(h.HipHeight > 0, "HipHeight > 0")
			T.ok(h.RigType == Enum.HumanoidRigType.R15, "R15")
			T.eq(h.AutomaticScalingEnabled, false, "AutomaticScalingEnabled")
			T.eq(h.BreakJointsOnDeath, false, "BreakJointsOnDeath")
			T.eq(h.RequiresNeck, false, "RequiresNeck")
			T.ok(h.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None, "DisplayDistanceType")
			T.ok(h.HealthDisplayType == Enum.HumanoidHealthDisplayType.AlwaysOff, "HealthDisplayType")
			T.eq(h.UseJumpPower, true, "UseJumpPower")
			local hrp = model.HumanoidRootPart
			T.near(hrp.CFrame.Position.Y - hrp.Size.Y / 2, h.HipHeight, 1e-4, "HipHeight = HRP bottom height")
			T.near(hrp.CFrame.Position.X, 0, 1e-6, "HRP x")
			T.near(hrp.CFrame.Position.Z, 0, 1e-6, "HRP z")
			T.ok(hrp.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999, "faces -Z")
		end
		T.ok(model:FindFirstChildOfClass("Animator", true) == nil, "no Animator")
		T.eq(model:GetAttribute("RigFamily"), "Human", "RigFamily")
		T.eq(model:GetAttribute("BlueprintId"), "Dummy", "BlueprintId")
		T.eq(model:GetAttribute("RigScale"), 1, "RigScale")
		T.eq(model:GetAttribute("SkinId"), "Default", "SkinId")
		-- feet stand on the dummy's own base (GroundOffset); the lowest visual touches y = 0
		local lift = Loader.require("ReplicatedStorage.Shared.Rigs.Blueprints").Get("Dummy").GroundOffset or 0
		local lf, rf = model.LeftFoot, model.RightFoot
		T.near(lf.CFrame.Position.Y - lf.Size.Y / 2, lift, 1e-4, "left foot on the stand")
		T.near(rf.CFrame.Position.Y - rf.Size.Y / 2, lift, 1e-4, "right foot on the stand")
		local minY = math.huge
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local cf, sz = d.CFrame, d.Size
				for _, sx in { -0.5, 0.5 } do
					for _, sy in { -0.5, 0.5 } do
						for _, sz2 in { -0.5, 0.5 } do
							minY = math.min(minY, (cf * Vector3.new(sx * sz.X, sy * sz.Y, sz2 * sz.Z)).Y)
						end
					end
				end
			end
		end
		T.near(minY, 0, 0.02, "lowest visual point on y=0 (no floating, no sinking)")
	end,

	dummy_attachments = function(T, Loader)
		local _, model = rig(Loader)
		for name, limb in ATTACHMENTS do
			local a = model[limb]:FindFirstChild(name)
			T.ok(a ~= nil and a:IsA("Attachment"), "attachment " .. name .. " on " .. limb)
			local count = 0
			for _, d in model:GetDescendants() do
				if d.Name == name then
					count += 1
				end
			end
			T.eq(count, 1, "attachment name " .. name .. " is unique in the rig")
		end
		-- eyes in front of the head, left eye on -X
		local head = model.Head
		local le = (head.CFrame * head.LeftEye.CFrame).Position
		local re = (head.CFrame * head.RightEye.CFrame).Position
		T.ok(le.X < 0 and re.X > 0, "LeftEye on -X, RightEye on +X")
		T.ok(le.Z < head.CFrame.Position.Z and re.Z < head.CFrame.Position.Z, "eyes on the front (-Z) side")
	end,

	dummy_visual_parts_contract = function(T, Loader)
		local _, model = rig(Loader)
		local total, visuals = 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				total += 1
				local physics = d.Parent == model and isLimbName(d.Name)
				if not physics then
					visuals += 1
					local role = d:GetAttribute("Role")
					T.ok(ROLES[role] == true, d:GetFullName() .. " Role " .. tostring(role))
					T.ok(
						d.CanCollide == false and d.CanQuery == false and d.CanTouch == false,
						d:GetFullName() .. " collision flags"
					)
					T.ok(d.Massless == true and d.Anchored == false, d:GetFullName() .. " massless/unanchored")
					T.ok(
						d.Parent:IsA("BasePart") and d.Parent.Parent == model and isLimbName(d.Parent.Name),
						d:GetFullName() .. " child of a limb"
					)
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					T.ok(
						weld ~= nil and weld.Part0 == d.Parent and weld.Part1 == d,
						d:GetFullName() .. " WeldConstraint limb->part"
					)
				end
			end
		end
		T.ok(total <= 220, ("part budget: %d <= 220"):format(total))
		T.ok(visuals >= 100, ("showcase detail: %d visual parts"):format(visuals))
		-- the chest target exists and faces the front
		local target = model.UpperTorso:FindFirstChild("Target1")
		T.ok(
			target ~= nil and target:IsA("Part") and target.Shape == Enum.PartType.Cylinder,
			"target ring is a cylinder"
		)
		if target then
			T.ok(target.CFrame.XVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "target disc faces -Z")
		end
	end,

	dummy_fk_pose = function(T, Loader)
		local RigBuilder, model = rig(Loader)
		local rest = RigBuilder.ComputeWorldCFrameList(model, nil)
		local count = 0
		for _, e in rest do
			count += 1
			T.ok((e.CFrame.Position - e.Part.CFrame.Position).Magnitude < 1e-4, "rest FK reproduces " .. e.Part.Name)
		end
		T.ok(count >= 150, "FK covers every part")
		local hand = model.RightHand
		local restHand = lookup(rest, hand)
		local pose = {
			RightShoulder = { 90, 0, 0 },
			LeftShoulder = { 0, 0, -90 },
			Waist = { 10, 25, 0 },
			LeftKnee = { -40, 0, 0 },
			Root = { 0, 0, 0, 0, -0.3, 0 },
		}
		local posed = RigBuilder.ComputeWorldCFrameList(model, pose)
		for _, e in posed do
			T.ok(finite(e.CFrame), "finite " .. e.Part.Name)
		end
		local posedHand = lookup(posed, hand)
		T.ok((posedHand.Position - restHand.Position).Magnitude > 0.8, "hand moves when the shoulder rotates")
		-- pose maths conventions (SPEC §3): single-joint checks
		local function handAfter(p, which)
			return lookup(RigBuilder.ComputeWorldCFrameList(model, p), model[which]).Position
		end
		local r0 = handAfter({}, "RightHand")
		local fwd = handAfter({ RightShoulder = { 60, 0, 0 } }, "RightHand")
		T.ok(fwd.Z < r0.Z - 0.5 and fwd.Y > r0.Y, "+rx swings the arm forward (-Z) and up")
		local side = handAfter({ RightShoulder = { 0, 0, 60 } }, "RightHand")
		T.ok(side.X > r0.X + 0.5 and side.Y > r0.Y, "+rz raises the right arm sideways (+X)")
		local l0 = handAfter({}, "LeftHand")
		local lside = handAfter({ LeftShoulder = { 0, 0, -60 } }, "LeftHand")
		T.ok(lside.X < l0.X - 0.5 and lside.Y > l0.Y, "-rz raises the left arm sideways (-X)")
		local turned = lookup(RigBuilder.ComputeWorldCFrameList(model, { Root = { 0, 90, 0 } }), model.Head)
		T.ok(turned.LookVector:Dot(Vector3.new(-1, 0, 0)) > 0.99, "+ry turns left (face towards -X)")
		-- welded visual follows its limb rigidly
		local button = model.Head:FindFirstChild("RightEyeButton")
		local nod = RigBuilder.ComputeWorldCFrameList(model, { Neck = { 30, 0, 0 } })
		local h0, h1 = lookup(rest, model.Head), lookup(nod, model.Head)
		local b0, b1 = lookup(rest, button), lookup(nod, button)
		local rel0, rel1 = h0:ToObjectSpace(b0), h1:ToObjectSpace(b1)
		T.ok((rel0.Position - rel1.Position).Magnitude < 1e-4, "visual keeps its offset to the limb")
		T.ok(b1.Position.Y > b0.Position.Y, "+rx on Neck tilts the face up")
		-- the map form works by iteration (Lune) and holds every part
		local n = 0
		for part, cf in RigBuilder.ComputeWorldCFrames(model, pose) do
			n += 1
			T.ok(part:IsA("BasePart") and finite(cf), "map entry")
		end
		T.eq(n, count, "map size")
	end,

	dummy_pose_and_apply = function(T, Loader)
		local RigBuilder, model = rig(Loader)
		RigBuilder.Pose(model, { RightElbow = { 45, 0, 0 } })
		local elbow = model.RightLowerArm.RightElbow
		local t = elbow.Transform
		T.ok(not isIdentityRotation(t), "Pose writes Motor6D.Transform")
		T.ok(isIdentityRotation(model.RightUpperArm.RightShoulder.Transform), "reset joints are identity")
		local before = model.RightHand.CFrame.Position
		RigBuilder.ApplyPose(model, nil) -- uses the Transforms just written
		local after = model.RightHand.CFrame.Position
		T.ok((after - before).Magnitude > 0.2 and after.Z < before.Z, "ApplyPose moves the forearm forward")
	end,

	dummy_scale_and_palette = function(T, Loader)
		local RigBuilder, model =
			rig(Loader, { Scale = 1.5, Palette = { Target = Color3.new(0, 1, 0) }, Skin = "Test", Name = "Big" })
		T.eq(model.Name, "Big", "opts.Name")
		T.eq(model:GetAttribute("RigScale"), 1.5, "RigScale")
		T.eq(model:GetAttribute("SkinId"), "Test", "SkinId")
		local hrp = model.HumanoidRootPart
		T.ok((hrp.Size - Vector3.new(3, 3, 1.5)).Magnitude < 1e-4, "HRP scaled")
		T.near(hrp.CFrame.Position.Y - 1.5, model.Humanoid.HipHeight, 1e-4, "HipHeight scaled")
		local lift = Loader.require("ReplicatedStorage.Shared.Rigs.Blueprints").Get("Dummy").GroundOffset or 0
		T.near(
			model.LeftFoot.CFrame.Position.Y - model.LeftFoot.Size.Y / 2,
			lift * 1.5,
			1e-4,
			"scaled feet keep their (scaled) stand height"
		)
		local target = model.UpperTorso:FindFirstChild("Target1")
		T.ok(target and target.Color == Color3.new(0, 1, 0), "opts.Palette overrides blueprint colours")
		T.noerror(function()
			RigBuilder.ComputeWorldCFrameList(model, { RightShoulder = { 0, 0, 90 } })
		end, "FK on a scaled rig")
		local _, small = rig(Loader)
		local ratio = model.Head.CFrame.Position.Y / small.Head.CFrame.Position.Y
		T.near(ratio, 1.5, 1e-3, "positions scale about the ground origin")
	end,

	registry_and_skeletons = function(T, Loader)
		local RigBuilder = Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder")
		local Blueprints = Loader.require("ReplicatedStorage.Shared.Rigs.Blueprints")
		local Skeletons = Loader.require("ReplicatedStorage.Shared.Rigs.Skeletons")
		T.ok(table.find(RigBuilder.Blueprints(), "Dummy") ~= nil, "Dummy listed")
		T.ok(Blueprints.Get("DoesNotExist") == nil, "missing blueprint -> nil")
		T.fails(function()
			RigBuilder.Build("DoesNotExist")
		end, "Build of a missing blueprint errors")
		local human = Skeletons.Resolve("Human")
		T.ok(human.Height > 4.6 and human.Height < 5.05, "Human height ~4.8 (" .. human.Height .. ")")
		T.near(human.Limbs.Head.Size.Y, 1.5, 0.05, "Human head ~1.5")
		local sk = Skeletons.Resolve("Skeleton")
		T.near(sk.Limbs.Head.Size.X, 2.1, 1e-6, "Skeleton skull 2.1 wide")
		T.ok(sk.HipHeight > 0 and human.HipHeight > 0, "positive HipHeight")
		T.ok(sk.Limbs.UpperTorso.Size.X > human.Limbs.UpperTorso.Size.X, "Sans torso is broader")
		-- overrides: Joint delta moves the sub-chain
		local moved = Skeletons.Resolve("Human", { RightUpperArm = { Joint = Vector3.new(0.2, 0, 0) } })
		T.near(
			moved.Limbs.RightHand.CFrame.Position.X - human.Limbs.RightHand.CFrame.Position.X,
			0.2,
			1e-6,
			"Joint delta propagates to children"
		)
		local longer = Skeletons.Resolve("Human", { LeftLowerLeg = { Size = Vector3.new(0.42, 1.0, 0.42) } })
		T.ok(longer.HipHeight > human.HipHeight, "longer legs raise HipHeight")
		local lifted = Skeletons.Resolve("Human", nil, 0.3)
		T.near(lifted.HipHeight - human.HipHeight, 0.3, 1e-6, "groundOffset raises HipHeight")
		T.near(
			lifted.Limbs.LeftFoot.CFrame.Position.Y - lifted.Limbs.LeftFoot.Size.Y / 2,
			0.3,
			1e-6,
			"groundOffset lifts the feet"
		)
		T.fails(function()
			Skeletons.Resolve("Human", { Tail = { Size = Vector3.one } })
		end, "unknown limb override errors")
		for _, id in Skeletons.List() do
			for poseName, pose in Skeletons.Get(id).Poses do
				for joint in pose do
					T.ok(SPEC_JOINTS[joint] ~= nil, id .. "." .. poseName .. " uses unknown joint " .. joint)
				end
			end
		end
	end,

	partkit_builders = function(T, Loader)
		local PartKit = Loader.require("ReplicatedStorage.Shared.Rigs.PartKit")
		local folder = Instance.new("Model")
		local cyl = PartKit.Cyl(folder, "C", 2, 0.5, CFrame.new(1, 2, 3), Color3.new(1, 0, 0))
		T.ok(cyl.Shape == Enum.PartType.Cylinder and cyl.Size == Vector3.new(2, 0.5, 0.5), "Cyl size/shape (axis X)")
		T.eq(cyl.CanCollide, false, "visual default CanCollide")
		T.eq(cyl.CanQuery, false, "visual default CanQuery")
		T.eq(cyl.Massless, true, "visual default Massless")
		T.eq(cyl:GetAttribute("Role"), "Detail", "default Role")
		T.ok(cyl.Material == Enum.Material.SmoothPlastic, "default material")
		T.eq(cyl.CastShadow, true, "big parts cast shadows")
		local tiny = PartKit.Ball(folder, "T", 0.1, CFrame.new(), Color3.new(1, 1, 1))
		T.eq(tiny.CastShadow, false, "tiny parts do not cast shadows")
		local between =
			PartKit.CylBetween(folder, "B", Vector3.new(0, 0, 0), Vector3.new(0, 4, 0), 0.3, Color3.new(1, 1, 1))
		T.near(between.Size.X, 4, 1e-5, "CylBetween length")
		T.ok(
			math.abs(between.CFrame.XVector:Dot(Vector3.new(0, 1, 0))) > 0.9999,
			"CylBetween axis along the segment (vertical ok)"
		)
		T.ok((between.CFrame.Position - Vector3.new(0, 2, 0)).Magnitude < 1e-5, "CylBetween centre")
		local disc =
			PartKit.Disc(folder, "D", 1, 0.1, CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0)), Color3.new(1, 1, 1))
		T.ok(disc.CFrame.XVector:Dot(Vector3.new(1, 0, 0)) > 0.9999, "Disc faces its LookVector")
		local ell = PartKit.Ellipsoid(
			folder,
			"E",
			Vector3.new(2, 1, 1),
			CFrame.new(),
			Color3.new(1, 1, 1),
			{ Role = "Skin", Material = Enum.Material.Fabric }
		)
		local mesh = ell:FindFirstChildOfClass("SpecialMesh")
		T.ok(mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere, "Ellipsoid uses a Sphere SpecialMesh")
		T.eq(ell:GetAttribute("Role"), "Skin", "props.Role")
		T.ok(ell.Material == Enum.Material.Fabric, "props.Material")
		T.eq(
			#PartKit.RoundedBox(folder, "R", Vector3.new(2, 2, 2), CFrame.new(), Color3.new(1, 1, 1), 0.3),
			23,
			"RoundedBox All = 23 parts"
		)
		T.eq(
			#PartKit.RoundedBox(
				folder,
				"R2",
				Vector3.new(2, 2, 2),
				CFrame.new(),
				Color3.new(1, 1, 1),
				0.3,
				{ Round = "Y" }
			),
			6,
			"RoundedBox Y = 6 parts"
		)
		local bone = PartKit.Bone(folder, "Bone", Vector3.new(0, 0, 0), Vector3.new(0, 3, 0), 0.4, Color3.new(1, 1, 1))
		T.eq(#bone, 5, "Bone = shaft + 4 knobs")
		T.eq(#PartKit.Ring(folder, "Ring", CFrame.new(), 1, 10, 0.2, Color3.new(1, 1, 1)), 10, "Ring count")
		local arc = PartKit.Arc(folder, "Arc", CFrame.new(), 1, 200, 340, 6, 0.05, 0.05, Color3.new(1, 1, 1))
		T.eq(#arc, 6, "Arc segments")
		for _, p in arc do
			T.ok(p.CFrame.Position.Y < 0, "smile arc below the centre")
		end
		T.eq(
			#PartKit.Tube(
				folder,
				"Tube",
				{ Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(1, 1, 0) },
				0.2,
				Color3.new(1, 1, 1)
			),
			3,
			"Tube = 2 segments + 1 joint"
		)
		T.ok(
			#PartKit.Dashes(
					folder,
					"Dash",
					{ Vector3.zero, Vector3.new(2, 0, 0) },
					0.1,
					0.1,
					0.03,
					Color3.new(1, 1, 1)
				) >= 9,
			"Dashes count"
		)
		T.ok(
			#PartKit.Cone(
					folder,
					"Cone",
					Vector3.zero,
					Vector3.new(0, 1, 0),
					0.4,
					0.05,
					Color3.new(1, 1, 1),
					{ Segments = 4 }
				) == 4,
			"Cone segments"
		)
		-- OnEllipsoid: on the surface, facing out
		local radii = Vector3.new(1, 0.5, 0.8)
		local front = PartKit.OnEllipsoid(CFrame.new(0, 10, 0), radii, 0, 0, 0)
		T.ok((front.Position - Vector3.new(0, 10, -0.8)).Magnitude < 1e-5, "yaw 0 = front surface point")
		T.ok(front.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999, "front frame looks outward")
		local right = PartKit.OnEllipsoid(CFrame.new(), radii, 90, 0, 0)
		T.ok(right.Position.X > 0.99, "+yaw goes to +X (character right)")
		local up = PartKit.OnEllipsoid(CFrame.new(), radii, 0, 90, 0.1)
		T.ok(math.abs(up.Position.Y - 0.4) < 1e-4 and up.LookVector.Y > 0.999, "pitch 90 = top, inset pushes inside")
		-- WithScale + ScaleModel
		local K = PartKit.WithScale(2)
		local big = K.Box(folder, "Big", Vector3.new(1, 1, 1), CFrame.new(1, 0, 0), Color3.new(1, 1, 1))
		T.ok(
			big.Size == Vector3.new(2, 2, 2) and (big.CFrame.Position - Vector3.new(2, 0, 0)).Magnitude < 1e-6,
			"WithScale scales sizes and positions"
		)
		local m = Instance.new("Model")
		local p = PartKit.Box(m, "P", Vector3.new(1, 2, 3), CFrame.new(0, 1, 0), Color3.new(1, 1, 1))
		local att = PartKit.Attach(p, "A", CFrame.new(0, 0.5, 0))
		PartKit.ScaleModel(m, 3)
		T.ok(p.Size == Vector3.new(3, 6, 9), "ScaleModel sizes")
		T.near(p.CFrame.Position.Y, 3, 1e-6, "ScaleModel positions")
		T.near(att.CFrame.Position.Y, 1.5, 1e-6, "ScaleModel attachments")
		local w = PartKit.Weld(p, big)
		T.ok(w.Parent == big and w.Part0 == p and w.Part1 == big, "Weld parented to part1")
		local light = PartKit.Light(p, "Spot", { Brightness = 3, Range = 10, Angle = 40 })
		T.ok(
			light:IsA("SpotLight") and light.Range == 10 and light.Angle == 40 and light.Brightness == 3,
			"Light props"
		)
	end,
}

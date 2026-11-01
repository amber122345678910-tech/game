--!nocheck
-- Sans family rigs (ClassicSans, FellSans, EclipseSans) + Rigs/Skins.
-- NOTE (Lune): Instance userdata are not identity-stable (a == b works, t[a] does not), so these
-- tests compare instances with == and never key tables by Instance.
local roblox = require("@lune/roblox")
local Vector3, Color3, Enum, CFrame = roblox.Vector3, roblox.Color3, roblox.Enum, roblox.CFrame

local SANS = { "ClassicSans", "FellSans", "EclipseSans" }
local VARIANT = { ClassicSans = "Classic", FellSans = "Fell", EclipseSans = "Eclipse" }
local SIGNATURE = {
	ClassicSans = { "LeftIris", "Drawstring", "Aglet", "Fur", "ZipperPull", "Slipper", "GrinTooth", "LeftPocket" },
	FellSans = { "GoldTooth", "Scar", "RightBrow", "LeftBrow", "Spike", "SpikeCollar", "Turtleneck", "Sneaker", "GrinFangs" },
	EclipseSans = { "HaloDisc", "Corona", "Fissure", "ChipHole", "Star", "LeftPupilCore", "HoodTatter", "HandVein" },
}

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

local POSES = { "Rest", "APose", "TPose", "Wave", "Walk", "Action", "Pockets", "Shrug" }

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

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 1.5 / 255 and math.abs(a.G - b.G) < 1.5 / 255 and math.abs(a.B - b.B) < 1.5 / 255
end

local function modules(Loader)
	return Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder"),
		Loader.require("ReplicatedStorage.Shared.Rigs.Skins"),
		Loader.require("ReplicatedStorage.Shared.Rigs.Blueprints.SansCommon")
end

local function visualParts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not (d.Parent == model and isLimbName(d.Name)) then
			table.insert(out, d)
		end
	end
	return out
end

local function countParts(model)
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function skinIds(Skins, id)
	local out = {}
	for _, s in Skins.List(id) do
		table.insert(out, s.Id)
	end
	return out
end

return {
	sans_blueprints_registered = function(T, Loader)
		local RigBuilder = modules(Loader)
		local list = RigBuilder.Blueprints()
		for _, id in SANS do
			T.ok(table.find(list, id) ~= nil, id .. " listed by RigBuilder.Blueprints()")
		end
		T.ok(table.find(list, "SansCommon") == nil, "the shared helper module is not listed as a blueprint")
	end,

	sans_build_every_skin_within_budget = function(T, Loader)
		local RigBuilder, Skins = modules(Loader)
		for _, id in SANS do
			local ids = skinIds(Skins, id)
			T.ok(#ids >= 3, id .. " has kit skins")
			for _, skinId in ids do
				local ok, model = pcall(RigBuilder.Build, id, { Skin = skinId })
				if T.ok(ok, ("%s builds with skin %s: %s"):format(id, skinId, tostring(model))) then
					local n = countParts(model)
					T.ok(n <= 220, ("%s/%s part budget %d <= 220"):format(id, skinId, n))
					T.ok(n >= 140, ("%s/%s detail %d >= 140 parts"):format(id, skinId, n))
					T.eq(model:GetAttribute("BlueprintId"), id, id .. " BlueprintId")
					T.eq(model:GetAttribute("SkinId"), skinId, id .. " SkinId")
					T.eq(model:GetAttribute("RigFamily"), "Skeleton", id .. " RigFamily")
				end
			end
		end
	end,

	sans_visual_parts_contract = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			for _, p in visualParts(model) do
				local name = p:GetFullName()
				T.ok(ROLES[p:GetAttribute("Role")] == true, name .. " Role " .. tostring(p:GetAttribute("Role")))
				T.ok(p.CanCollide == false and p.CanQuery == false and p.CanTouch == false, name .. " collision flags")
				T.ok(p.Massless == true and p.Anchored == false, name .. " massless/unanchored")
				T.ok(
					p.Parent:IsA("BasePart") and p.Parent.Parent == model and isLimbName(p.Parent.Name),
					name .. " is a child of a limb"
				)
				local weld = p:FindFirstChildOfClass("WeldConstraint")
				T.ok(weld ~= nil and weld.Part0 == p.Parent and weld.Part1 == p, name .. " welded limb -> part")
			end
			for _, limbName in LIMBS do
				local limb = model:FindFirstChild(limbName)
				if T.ok(limb ~= nil and limb:IsA("BasePart"), id .. " physics part " .. limbName) then
					T.eq(limb.Transparency, 1, id .. "." .. limbName .. " invisible")
					T.eq(limb.Massless, false, id .. "." .. limbName .. " has mass")
					local collide = limbName == "LowerTorso" or limbName == "UpperTorso" or limbName == "Head"
					T.eq(limb.CanCollide, collide, id .. "." .. limbName .. " CanCollide")
				end
			end
			-- feet on the ground: nothing sinks below y = 0 and the slippers/sneakers touch it
			local minY = math.huge
			for _, p in visualParts(model) do
				if p.Transparency < 1 then
					local cf, sz = p.CFrame, p.Size
					for _, sx in { -0.5, 0.5 } do
						for _, sy in { -0.5, 0.5 } do
							for _, sz2 in { -0.5, 0.5 } do
								minY = math.min(minY, (cf * Vector3.new(sx * sz.X, sy * sz.Y, sz2 * sz.Z)).Y)
							end
						end
					end
				end
			end
			T.near(minY, 0, 0.03, id .. " lowest visual point on the ground")
		end
	end,

	sans_motors_and_attachments = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			local motors = {}
			for _, d in model:GetDescendants() do
				if d:IsA("Motor6D") then
					table.insert(motors, d)
				end
			end
			T.eq(#motors, 15, id .. " has 15 Motor6Ds")
			for _, m in motors do
				local spec = SPEC_JOINTS[m.Name]
				if T.ok(spec ~= nil, id .. " unexpected motor " .. m.Name) then
					T.eq(m.Part0 and m.Part0.Name, spec[1], id .. " " .. m.Name .. ".Part0")
					T.eq(m.Part1 and m.Part1.Name, spec[2], id .. " " .. m.Name .. ".Part1")
					T.ok(m.Parent == m.Part1, id .. " " .. m.Name .. " parented to Part1")
					T.ok(isIdentityRotation(m.C0) and isIdentityRotation(m.C1), id .. " " .. m.Name .. " identity C0/C1")
				end
			end
			for name, limb in ATTACHMENTS do
				local a = model[limb]:FindFirstChild(name)
				T.ok(a ~= nil and a:IsA("Attachment"), id .. " attachment " .. name .. " on " .. limb)
				local count = 0
				for _, d in model:GetDescendants() do
					if d.Name == name then
						count += 1
					end
				end
				T.eq(count, 1, id .. " name " .. name .. " is unique")
			end
			for _, d in model:GetDescendants() do
				if d:IsA("Attachment") then
					T.ok(
						string.match(d.Name, "RigAttachment$") == nil,
						id .. " attachment is not an R15 rig attachment: " .. d.Name
					)
				end
			end
			-- grips/feet attachments live on the right limbs and below the wrists/ankles
			local head = model.Head
			local le = (head.CFrame * head.LeftEye.CFrame).Position
			local re = (head.CFrame * head.RightEye.CFrame).Position
			T.ok(le.X < 0 and re.X > 0, id .. " LeftEye on -X, RightEye on +X")
			T.ok(le.Z < head.CFrame.Position.Z - 0.5, id .. " eyes on the face")
		end
	end,

	sans_pupils_and_eyes = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			local head = model.Head
			for _, name in { "LeftPupil", "RightPupil" } do
				local p = head:FindFirstChild(name)
				if T.ok(p ~= nil and p:IsA("BasePart"), id .. " " .. name .. " under Head") then
					T.eq(p:GetAttribute("Role"), "Eye", id .. " " .. name .. " Role Eye")
					T.ok(p.Material == Enum.Material.Neon, id .. " " .. name .. " is Neon")
					T.ok(p:GetAttribute("HDGroup") == nil, id .. " " .. name .. " stays visible over the HD skull")
				end
			end
			local lp, rp = head:FindFirstChild("LeftPupil"), head:FindFirstChild("RightPupil")
			if lp and rp then
				T.ok(lp.CFrame.Position.X < 0 and rp.CFrame.Position.X > 0, id .. " LeftPupil is his left (-X)")
			end
		end
		-- Classic: tiny white pupils set low and toward the nose inside the sockets
		local model = RigBuilder.Build("ClassicSans")
		local head = model.Head
		for _, side in { "Left", "Right" } do
			local pupil, socket = head[side .. "Pupil"], head[side .. "Socket"]
			T.ok(sameColor(pupil.Color, Color3.new(1, 1, 1)), "Classic pupils are white")
			T.ok(pupil.Size.X < socket.Size.X * 0.25, "Classic pupil is tiny vs the socket")
			T.ok(pupil.CFrame.Position.Y < socket.CFrame.Position.Y, side .. " pupil sits low")
			T.ok(math.abs(pupil.CFrame.Position.X) < math.abs(socket.CFrame.Position.X), side .. " pupil sits toward the nose")
			T.ok(socket.Material == Enum.Material.Neon and socket.Color == Color3.new(0, 0, 0), side .. " socket is a void")
		end
	end,

	sans_skull_proportions_and_hd_anchor = function(T, Loader)
		local RigBuilder, _, SansCommon = modules(Loader)
		local Meshes = Loader.require("ReplicatedStorage.Shared.Meshes")
		local K = SansCommon.SKULL_K
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			local head = model.Head
			local variant = VARIANT[id]
			local anchor = head:FindFirstChild("HD_Skull")
			if T.ok(anchor ~= nil and anchor:IsA("Attachment"), id .. " HD_Skull attachment on Head") then
				local meshName = anchor:GetAttribute("HDMesh")
				T.eq(meshName, "SansSkull" .. variant, id .. " HDMesh")
				T.ok(Meshes.Has(meshName), id .. " HDMesh is a generated mesh")
				local hdSize = anchor:GetAttribute("HDSize")
				local data = Meshes.Get(meshName)
				if T.ok(typeof(hdSize) == "Vector3" and data ~= nil, id .. " HDSize Vector3 + mesh data") then
					-- SansCommon.HD stays in sync with the generated meshes; same proportions, scale K
					T.ok((SansCommon.HD[variant].Size - data.Size).Magnitude < 1e-3, id .. " SansCommon.HD in sync")
					T.ok((hdSize - data.Size * K).Magnitude < 1e-3, id .. " HDSize = mesh size x SKULL_K")
				end
				T.ok(isIdentityRotation(anchor.CFrame), id .. " anchor faces -Z like the Head")
			end
			-- the part-built skull: squircle bounding box with the HD proportions (Classic box)
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			local skullParts = 0
			for _, p in head:GetChildren() do
				if p:IsA("BasePart") and (p.Name == "Cranium" or string.sub(p.Name, 1, 9) == "SkullFace") then
					skullParts += 1
					local half = p.Size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local c = (p.CFrame * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)).Position
								lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
								hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
							end
						end
					end
				end
			end
			T.ok(skullParts >= 20, id .. " skull = cranium + rounded face block")
			local size = hi - lo
			local classic = SansCommon.HD.Classic.Size * K
			T.near(size.X, classic.X, 0.03, id .. " skull width matches the HD box")
			T.near(size.Y, classic.Y, 0.03, id .. " skull height matches the HD box")
			T.near(size.Z, classic.Z, 0.03, id .. " skull depth matches the HD box")
			local ratio = size.X / size.Y
			T.ok(ratio > 1.05 and ratio < 1.2, ("%s width:height %.3f"):format(id, ratio))
			-- head ~40% of the height (1 skull per ~2.6 total)
			local top = hi.Y
			T.ok(size.Y / top > 0.33 and size.Y / top < 0.46, ("%s head fraction %.2f"):format(id, size.Y / top))
			local grouped = 0
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") and p:GetAttribute("HDGroup") == "Skull" then
					grouped += 1
					T.ok(p.Parent == head, id .. " HDGroup parts live on Head: " .. p.Name)
				end
			end
			T.ok(grouped >= 40, ("%s %d parts tagged HDGroup=Skull"):format(id, grouped))
		end
	end,

	sans_poses_give_finite_cframes = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id, { Scale = 1.1 })
			for _, poseName in POSES do
				local pose = RigBuilder.GetPose("Skeleton", poseName)
				if T.ok(pose ~= nil, "pose " .. poseName) then
					local list = RigBuilder.ComputeWorldCFrameList(model, pose)
					local allFinite = #list > 0
					for _, e in list do
						if not finite(e.CFrame) then
							allFinite = false
						end
					end
					T.ok(allFinite, id .. " finite FK in pose " .. poseName)
				end
			end
		end
	end,

	sans_pockets_pose_hides_hands = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			local list = RigBuilder.ComputeWorldCFrameList(model, RigBuilder.GetPose("Skeleton", "Pockets"))
			local function cfOf(part)
				for _, e in list do
					if e.Part == part then
						return e.CFrame
					end
				end
				return nil
			end
			for _, side in { "Left", "Right" } do
				local pocket = model.UpperTorso[side .. "Pocket"]
				local pcf = cfOf(pocket)
				local half = pocket.Size / 2
				local inside, total = 0, 0
				for _, p in model[side .. "Hand"]:GetChildren() do
					if p:IsA("BasePart") then
						total += 1
						local l = pcf:PointToObjectSpace(cfOf(p).Position)
						local v = (l.X / half.X) ^ 2 + (l.Y / half.Y) ^ 2 + (l.Z / half.Z) ^ 2
						if v < 1 then
							inside += 1
						end
					end
				end
				T.ok(total > 0 and inside == total, ("%s %s hand tucked in the pocket (%d/%d)"):format(id, side, inside, total))
			end
		end
	end,

	sans_skin_palettes_are_honoured = function(T, Loader)
		local RigBuilder, Skins = modules(Loader)
		for _, id in SANS do
			local bp = RigBuilder.GetBlueprint(id)
			for _, skin in Skins.List(id) do
				local model = RigBuilder.Build(id, { Skin = skin.Id })
				local parts = visualParts(model)
				for key, color in skin.Palette do
					T.ok(bp.Palette[key] ~= nil, ("%s palette defines skin key %s"):format(id, key))
					local used = false
					for _, p in parts do
						if sameColor(p.Color, color) then
							used = true
							break
						end
					end
					T.ok(used, ("%s skin %s: key %s visibly used"):format(id, skin.Id, key))
				end
			end
		end
	end,

	sans_signature_details = function(T, Loader)
		local RigBuilder = modules(Loader)
		for _, id in SANS do
			local model = RigBuilder.Build(id)
			for _, name in SIGNATURE[id] do
				T.ok(model:FindFirstChild(name, true) ~= nil, id .. " has " .. name)
			end
		end
		-- Classic: the attack eye glint is his LEFT eye (the viewer's right)
		local classic = RigBuilder.Build("ClassicSans")
		T.ok(classic.Head.LeftIris.CFrame.Position.X < 0, "Classic EyeGlow iris on his left eye")
		-- Fell: gold tooth on his left (-X), scar through his right (+X) socket
		local fell = RigBuilder.Build("FellSans")
		T.ok(fell.Head.GoldTooth.CFrame.Position.X < 0, "Fell gold tooth on his left")
		T.ok(fell.Head.Scar.CFrame.Position.X > 0, "Fell scar on his right")
		-- Eclipse: ring eye left, fissures on his right crown, halo behind the head
		local eclipse = RigBuilder.Build("EclipseSans")
		local head = eclipse.Head
		T.ok(head.LeftPupil.Size.Y > head.RightPupil.Size.Y * 2, "Eclipse: one bright ring eye, one ember")
		T.ok(head.Fissure.CFrame.Position.X > 0, "Eclipse fissures on his right crown")
		T.ok(head.HaloDisc.CFrame.Position.Z > head.Cranium.CFrame.Position.Z + 1, "Eclipse halo floats behind the head")
	end,

	sans_scale_keeps_hd_size = function(T, Loader)
		local RigBuilder = modules(Loader)
		local a = RigBuilder.Build("ClassicSans")
		local b = RigBuilder.Build("ClassicSans", { Scale = 1.1 })
		T.near(b:GetAttribute("RigScale"), 1.1, 1e-6, "RigScale attribute")
		local sa, sb = a.Head.HD_Skull:GetAttribute("HDSize"), b.Head.HD_Skull:GetAttribute("HDSize")
		T.ok((sa - sb).Magnitude < 1e-6, "HDSize stays the scale-1 size (HDMesh multiplies by RigScale)")
		T.near(b.Head.Cranium.Size.X, a.Head.Cranium.Size.X * 1.1, 1e-3, "visual parts scale with the rig")
	end,

	skins_module = function(T, Loader)
		local _, Skins = modules(Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		local list = Skins.List("ClassicSans")
		local kit = Kits.Get("ClassicSans")
		T.eq(#list, #kit.Skins, "List mirrors the kit skins")
		T.eq(list[1].Id, kit.Skins[1].Id, "kit order")
		local def = Skins.Get("ClassicSans")
		T.ok(def ~= nil and def.Id == "Default" and next(def.Palette) == nil, "nil skin -> Default (empty palette)")
		local mid = Skins.Get("ClassicSans", "Midnight")
		T.ok(mid ~= nil and mid.Palette.Hoodie ~= nil and mid.Name.en ~= nil, "Get returns palette + name")
		mid.Palette.Hoodie = Color3.new(1, 0, 0)
		T.ok(not sameColor(Skins.Get("ClassicSans", "Midnight").Palette.Hoodie, Color3.new(1, 0, 0)), "Get copies")
		T.ok(Skins.Get("ClassicSans", "Nope") == nil, "unknown skin -> nil")
		T.ok(Skins.Get("NoSuchKit", "Default") == nil, "unknown kit -> nil")
		T.ok(next(Skins.Palette("NoSuchKit", "x")) == nil, "Palette falls back to {}")
		T.ok(Skins.Has("FellSans", "Royal") and not Skins.Has("FellSans", "Midnight"), "Has")
		T.eq(#Skins.List("NoSuchKit"), 0, "List of an unknown kit is empty")
	end,
}

--!nocheck
-- Human SOUL-class rigs (Rigs/Blueprints/{HumanCommon, Determination ... Justice}) + held weapons (Rigs/Props/Weapons).
-- Every class builds with every kit skin, stays within the part budget, honours every palette key its skins use,
-- follows the rig contract (roles, collision flags, welds, attachments, SPEC 5.1/19) and poses with finite FK.
-- NOTE (Lune): Instance userdata are not identity-stable (a == b works, t[a] does not): compare with ==.
local roblox = require("@lune/roblox")
local Vector3, Color3 = roblox.Vector3, roblox.Color3

local CLASSES = { "Determination", "Patience", "Bravery", "Integrity", "Perseverance", "Kindness", "Justice" }
local WEAPON_OF = {
	Determination = "RealKnife",
	Patience = "ToyKnife",
	Perseverance = "Notebook",
	Kindness = "BurntPan",
	Justice = "EmptyGun",
}
local WEAPON_IDS = { "RealKnife", "ToyKnife", "Notebook", "NotebookOpen", "BurntPan", "EmptyGun", "BoneSword" }

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

local function isLimb(name)
	return table.find(LIMBS, name) ~= nil
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

local function parts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function isPhysics(model, part)
	return part.Parent == model and isLimb(part.Name)
end

-- The limb a visual part follows (first limb ancestor).
local function limbOf(model, part)
	local node = part.Parent
	while node ~= nil and node ~= model do
		if node:IsA("BasePart") and node.Parent == model and isLimb(node.Name) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 1 / 512 and math.abs(a.G - b.G) < 1 / 512 and math.abs(a.B - b.B) < 1 / 512
end

local function build(Loader, id, opts)
	local RigBuilder = Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder")
	return RigBuilder, RigBuilder.Build(id, opts)
end

return {
	humans_registered = function(T, Loader)
		local Blueprints = Loader.require("ReplicatedStorage.Shared.Rigs.Blueprints")
		local list = Blueprints.List()
		for _, id in CLASSES do
			T.ok(table.find(list, id) ~= nil, id .. " is a registered blueprint")
			local bp = Blueprints.Get(id)
			T.ok(bp ~= nil and bp.Family == "Human" and (bp.Skeleton or bp.Family) == "Human", id .. " uses the Human skeleton")
		end
		T.ok(table.find(list, "HumanCommon") == nil, "HumanCommon is a helper, not a blueprint")
	end,

	humans_build_every_skin = function(T, Loader)
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		for _, id in CLASSES do
			local kit = Kits.Get(id)
			if T.ok(kit ~= nil and kit.Rig == id, id .. " kit exists and points at the rig") then
				for _, skin in kit.Skins do
					local ok, model = pcall(function()
						local _, m = build(Loader, id, { Skin = skin.Id })
						return m
					end)
					if T.ok(ok, ("%s/%s builds: %s"):format(id, skin.Id, if ok then "" else tostring(model))) then
						local n = #parts(model)
						T.ok(n <= 220, ("%s/%s part budget %d <= 220"):format(id, skin.Id, n))
						T.ok(n >= 120, ("%s/%s detail %d >= 120 parts"):format(id, skin.Id, n))
						T.eq(model:GetAttribute("BlueprintId"), id, id .. " BlueprintId")
						T.eq(model:GetAttribute("SkinId"), skin.Id, id .. " SkinId")
						T.eq(model:GetAttribute("RigFamily"), "Human", id .. " RigFamily")
					end
				end
			end
		end
	end,

	humans_palette_keys_honoured = function(T, Loader)
		-- every palette key any skin of the kit overrides must drive at least one part colour exactly
		local Kits = Loader.require("ReplicatedStorage.Shared.Kits")
		for _, id in CLASSES do
			local keys, seen = {}, {}
			for _, skin in Kits.Get(id).Skins do
				for key in skin.Palette do
					if not seen[key] then
						seen[key] = true
						table.insert(keys, key)
					end
				end
			end
			table.sort(keys)
			T.ok(#keys > 0, id .. " skins override palette keys")
			local palette = {}
			for i, key in keys do
				palette[key] = Color3.fromRGB(11 + i * 7, 203 - i * 5, 61 + i * 11) -- sentinel colours
			end
			local _, model = build(Loader, id, { Palette = palette })
			local all = parts(model)
			for _, key in keys do
				local used = false
				for _, p in all do
					if sameColor(p.Color, palette[key]) then
						used = true
						break
					end
				end
				T.ok(used, ("%s honours palette key %s"):format(id, key))
			end
			-- and the skins visibly change the rig
			for _, skin in Kits.Get(id).Skins do
				if skin.Id ~= "Default" then
					local _, a = build(Loader, id)
					local _, b = build(Loader, id, { Skin = skin.Id })
					local pa, pb = parts(a), parts(b)
					local diff = 0
					for i = 1, math.min(#pa, #pb) do
						if not sameColor(pa[i].Color, pb[i].Color) then
							diff += 1
						end
					end
					-- human skins are accessory-only (owner rule, see human_accessories.spec): a few parts, but visible
					T.ok(diff >= 3, ("%s skin %s recolours %d parts"):format(id, skin.Id, diff))
				end
			end
		end
	end,

	humans_rig_contract = function(T, Loader)
		for _, id in CLASSES do
			local _, model = build(Loader, id)
			local hrp = model:FindFirstChild("HumanoidRootPart")
			T.ok(model.PrimaryPart ~= nil and model.PrimaryPart == hrp, id .. " PrimaryPart = HumanoidRootPart")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			T.ok(humanoid ~= nil and humanoid.HipHeight > 0, id .. " Humanoid with HipHeight")
			for _, name in LIMBS do
				local p = model:FindFirstChild(name)
				if T.ok(p ~= nil, id .. " physics part " .. name) then
					local collide = name == "LowerTorso" or name == "UpperTorso" or name == "Head"
					T.ok(
						p.Transparency == 1 and p.CanCollide == collide and p.CanQuery and p.CanTouch and not p.Massless,
						id .. " physics flags " .. name
					)
				end
			end
			local bad = 0
			for _, d in parts(model) do
				if not isPhysics(model, d) then
					local role = d:GetAttribute("Role")
					local okRole = ROLES[role] == true
					local okFlags = d.CanCollide == false
						and d.CanQuery == false
						and d.CanTouch == false
						and d.Massless == true
						and d.Anchored == false
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					local okWeld = weld ~= nil and weld.Part1 == d and weld.Part0 ~= nil
					local okLimb = limbOf(model, d) ~= nil
					if not (okRole and okFlags and okWeld and okLimb) then
						bad += 1
						T.ok(false, ("%s visual part %s: role=%s flags=%s weld=%s limb=%s"):format(
							id,
							d:GetFullName(),
							tostring(role),
							tostring(okFlags),
							tostring(okWeld),
							tostring(okLimb)
						))
					end
					-- no visual part may reuse a limb / attachment name (RigBuilder reserves them)
					T.ok(not isLimb(d.Name) and ATTACHMENTS[d.Name] == nil, id .. " part name not reserved: " .. d.Name)
				end
			end
			T.eq(bad, 0, id .. " every visual part follows the contract")
		end
	end,

	humans_attachments = function(T, Loader)
		for _, id in CLASSES do
			local _, model = build(Loader, id)
			for name, limb in ATTACHMENTS do
				local a = model[limb]:FindFirstChild(name)
				T.ok(a ~= nil and a:IsA("Attachment"), ("%s attachment %s on %s"):format(id, name, limb))
				local count = 0
				for _, d in model:GetDescendants() do
					if d.Name == name then
						count += 1
					end
				end
				T.eq(count, 1, id .. " attachment name unique: " .. name)
			end
			for _, d in model:GetDescendants() do
				if d:IsA("Attachment") then
					-- SPEC 19: R15 BuildRigFromAttachments keys on "*RigAttachment" names
					T.ok(string.find(d.Name, "RigAttachment") == nil, id .. " attachment not named *RigAttachment: " .. d.Name)
				end
			end
			local head = model.Head
			local le = (head.CFrame * head.LeftEye.CFrame).Position
			local re = (head.CFrame * head.RightEye.CFrame).Position
			T.ok(le.X < 0 and re.X > 0, id .. " LeftEye on -X, RightEye on +X")
			T.ok(le.Z < head.CFrame.Position.Z - 0.4 and re.Z < head.CFrame.Position.Z - 0.4, id .. " eyes on the face (front)")
			local top = (head.CFrame * head.HeadTop.CFrame).Position
			local highest = -math.huge
			for _, p in parts(model) do
				if not isPhysics(model, p) then
					highest = math.max(highest, p.CFrame.Position.Y + p.Size.Y * 0.5)
				end
			end
			T.ok(top.Y > highest - 0.45, ("%s HeadTop (%.2f) sits above the hair/hat (%.2f)"):format(id, top.Y, highest))
			local torso = model.UpperTorso
			local chest = (torso.CFrame * torso.Chest.CFrame).Position
			T.ok(chest.Z < torso.CFrame.Position.Z - 0.38, id .. " Chest attachment in front of the sweater")
			local grip = (model.RightHand.CFrame * model.RightHand.RightGrip.CFrame).Position
			T.ok((grip - model.RightHand.CFrame.Position).Magnitude < 0.6, id .. " RightGrip inside/near the right hand")
			for _, side in { "Left", "Right" } do
				local foot = model[side .. "Foot"]
				local fa = (foot.CFrame * foot[side .. "FootAttachment"].CFrame).Position
				T.ok(math.abs(fa.Y) < 0.05, id .. " foot attachment on the ground: " .. side)
			end
		end
	end,

	humans_weapons_welded = function(T, Loader)
		for _, id in CLASSES do
			local _, model = build(Loader, id)
			local hand = model.RightHand
			local weapon = hand:FindFirstChild("Weapon")
			local expected = WEAPON_OF[id]
			if expected == nil then
				T.ok(weapon == nil, id .. " holds no weapon prop")
			elseif T.ok(weapon ~= nil and weapon:IsA("Model"), id .. " has a Weapon model under RightHand") then
				T.eq(weapon:GetAttribute("WeaponId"), expected, id .. " weapon id")
				local grip = weapon.PrimaryPart
				if T.ok(grip ~= nil, id .. " weapon PrimaryPart") then
					local weld = grip:FindFirstChildOfClass("WeldConstraint")
					T.ok(weld ~= nil and weld.Part0 == hand and weld.Part1 == grip, id .. " weapon Grip welded to RightHand")
					local gripAtt = (hand.CFrame * hand.RightGrip.CFrame).Position
					T.ok((grip.CFrame.Position - gripAtt).Magnitude < 0.45, id .. " weapon held at RightGrip")
				end
				for _, p in parts(weapon) do
					T.eq(p:GetAttribute("Role"), "Weapon", id .. " weapon part role " .. p.Name)
					if p ~= grip then
						local w = p:FindFirstChildOfClass("WeldConstraint")
						T.ok(w ~= nil and w.Part0 == grip and w.Part1 == p, id .. " weapon part welded to Grip: " .. p.Name)
					end
				end
			end
		end
		-- Bravery wears its Tough Glove (outfit, not a prop)
		local _, brave = build(Loader, "Bravery")
		T.ok(brave.RightHand:FindFirstChild("GloveMitt") ~= nil, "Bravery wears the Tough Glove on the right hand")
	end,

	humans_fk_finite = function(T, Loader)
		local RigBuilder = Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder")
		local poses = {}
		for _, name in { "Ready", "Walk", "Action", "APose", "TPose", "Wave" } do
			local p = RigBuilder.GetPose("Human", name)
			if p then
				table.insert(poses, p)
			end
		end
		table.insert(poses, {
			Root = { 0, 30, 0, 0, -0.2, 0 },
			Waist = { 15, -20, 5 },
			Neck = { -20, 35, 0 },
			RightShoulder = { 120, 0, 30 },
			RightElbow = { 90, 0, 0 },
			RightWrist = { -30, 20, 0 },
			LeftHip = { 60, 0, -10 },
			LeftKnee = { -80, 0, 0 },
		})
		for _, id in CLASSES do
			local _, model = build(Loader, id)
			local rest = RigBuilder.ComputeWorldCFrameList(model, nil)
			T.ok(#rest == #parts(model), id .. " rest FK covers every part")
			for _, e in rest do
				if (e.CFrame.Position - e.Part.CFrame.Position).Magnitude > 1e-3 then
					T.ok(false, id .. " rest FK reproduces " .. e.Part:GetFullName())
				end
			end
			local hand = model.RightHand
			local weapon = hand:FindFirstChild("Weapon")
			for pi, pose in poses do
				local list = RigBuilder.ComputeWorldCFrameList(model, pose)
				local bad = 0
				for _, e in list do
					if not finite(e.CFrame) then
						bad += 1
					end
				end
				T.eq(bad, 0, ("%s pose %d finite"):format(id, pi))
				if weapon then
					local h0, h1 = lookup(rest, hand), lookup(list, hand)
					local g0, g1 = lookup(rest, weapon.PrimaryPart), lookup(list, weapon.PrimaryPart)
					local rel0, rel1 = h0:ToObjectSpace(g0), h1:ToObjectSpace(g1)
					T.ok((rel0.Position - rel1.Position).Magnitude < 1e-3, ("%s weapon follows the hand (pose %d)"):format(id, pi))
				end
			end
		end
	end,

	weapons_props = function(T, Loader)
		local Weapons = Loader.require("ReplicatedStorage.Shared.Rigs.Props.Weapons")
		local list = Weapons.List()
		for _, id in WEAPON_IDS do
			T.ok(table.find(list, id) ~= nil and Weapons.Has(id), "Weapons.List has " .. id)
			local model = Weapons.Build(id)
			T.ok(model:IsA("Model") and model.Name == "Weapon" and model.Parent == nil, id .. " is a parentless Model named Weapon")
			T.eq(model:GetAttribute("WeaponId"), id, id .. " WeaponId attribute")
			local grip = model.PrimaryPart
			if T.ok(grip ~= nil and grip.Name == "Grip", id .. " PrimaryPart Grip") then
				T.ok(grip.CFrame.Position.Magnitude < 0.35, id .. " grip near the origin (grip space)")
			end
			local all = parts(model)
			T.ok(#all >= 6 and #all <= 40, ("%s part count %d in 6..40"):format(id, #all))
			for _, p in all do
				T.ok(p:GetAttribute("Role") == "Weapon", id .. " role " .. p.Name)
				T.ok(
					not p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and p.Massless,
					id .. " visual flags " .. p.Name
				)
				if p ~= grip then
					local w = p:FindFirstChildOfClass("WeldConstraint")
					T.ok(w ~= nil and w.Part0 == grip and w.Part1 == p, id .. " welded to Grip: " .. p.Name)
				end
				T.ok(finite(p.CFrame), id .. " finite CFrame " .. p.Name)
			end
		end
		-- palette overrides reach the prop
		local book = Color3.fromRGB(12, 34, 56)
		local found = false
		for _, p in parts(Weapons.Build("Notebook", { Book = book })) do
			if sameColor(p.Color, book) then
				found = true
			end
		end
		T.ok(found, "Notebook cover follows palette.Book")
		T.fails(function()
			Weapons.Build("NoSuchWeapon")
		end, "unknown weapon id errors")
		-- the revolver points down at rest (barrel along -Y in grip space), the knife forward (-Z)
		local gun = Weapons.Build("EmptyGun")
		local muzzle = gun:FindFirstChild("Muzzle", true)
		T.ok(muzzle ~= nil and muzzle.CFrame.Position.Y < -0.6, "revolver barrel points along -Y in grip space")
		local knife = Weapons.Build("RealKnife")
		local tip = knife:FindFirstChild("Tip", true)
		T.ok(tip ~= nil and tip.CFrame.Position.Z < -0.7, "knife blade points along -Z in grip space")
	end,
}

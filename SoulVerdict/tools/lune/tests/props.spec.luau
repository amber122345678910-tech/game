--!nocheck
-- Prop library (src/shared/Rigs/Props/*): every builder with every style/kind, part budgets,
-- PrimaryPart + prop invariants, Gaster Blaster hinge/muzzle/HD anchors (checked against the
-- generated HD mesh data), jaw/glow/book/rift/chain helpers and SaveStar.SetProgress.
-- NOTE (Lune): Instance userdata are not identity-stable; compare with == and never key tables by Instance.
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local ROOT = "ReplicatedStorage.Shared.Rigs.Props"

local ROLES = {}
for _, r in { "Skin", "Bone", "Cloth", "ClothAlt", "Trim", "Accent", "Eye", "Glow", "Hair", "Metal", "Weapon", "Detail", "Dark" } do
	ROLES[r] = true
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

local function find(model, name)
	for _, d in model:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- Invariants shared by every prop model.
local function checkProp(T, model, label, maxParts)
	T.ok(model ~= nil and model:IsA("Model"), label .. ": returns a Model")
	T.ok(model.PrimaryPart ~= nil, label .. ": PrimaryPart set")
	T.ok(model.PrimaryPart:IsDescendantOf(model), label .. ": PrimaryPart inside the model")
	T.ok(model.Parent == nil, label .. ": unparented")
	local list = parts(model)
	T.ok(#list > 0, label .. ": has parts")
	if maxParts then
		T.ok(#list <= maxParts, ("%s: %d parts (max %d)"):format(label, #list, maxParts))
	end
	T.eq(model:GetAttribute("PartCount"), #list, label .. ": PartCount attribute")
	T.ok(type(model:GetAttribute("PropId")) == "string", label .. ": PropId attribute")
	local bad = {}
	for _, p in list do
		if not p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch then
			table.insert(bad, p.Name .. "(flags)")
		end
		if not ROLES[p:GetAttribute("Role")] then
			table.insert(bad, p.Name .. "(role " .. tostring(p:GetAttribute("Role")) .. ")")
		end
		if p.Size.X <= 0 or p.Size.Y <= 0 or p.Size.Z <= 0 then
			table.insert(bad, p.Name .. "(size)")
		end
	end
	T.ok(#bad == 0, label .. ": part invariants " .. table.concat(bad, ", "))
	return list
end

local function nearV(T, a, b, eps, msg)
	T.ok((a - b).Magnitude <= eps, ("%s: %s vs %s"):format(msg, tostring(a), tostring(b)))
end

return {
	registry = function(T, Loader)
		local Props = Loader.require(ROOT)
		local names = Props.Names()
		for _, n in { "Bone", "GasterBlaster", "Soul", "SaveStar", "VerdictBox3D", "Rift", "VoidOrb", "GiantBook", "Dish", "StarBone", "Chain" } do
			T.ok(table.find(names, n) ~= nil, "registry lists " .. n)
			local m = Props.Get(n)
			T.ok(type(m) == "table" and type(m.Build) == "function", n .. " has Build")
			T.ok(Props.Get(n) == m, n .. " cached")
		end
		T.eq(Props.Get("NoSuchProp"), nil, "unknown prop -> nil")
		T.eq(Props.ColorOf("Blue"), Color3.fromRGB(20, 169, 255), "Blue #14A9FF")
		T.eq(Props.ColorOf("Orange"), Color3.fromRGB(255, 160, 64), "Orange #FFA040")
		local m = Props.Build("Bone", 2, 0.3, Color3.new(1, 1, 1))
		T.ok(m and m:IsA("Model"), "Props.Build convenience")
	end,

	helpers = function(T, Loader)
		local Props = Loader.require(ROOT)
		local kit = Props.Kit(1)
		local folder = roblox.Instance.new("Model")
		-- right triangle -> one wedge; scalene -> two wedges whose vertices span the triangle
		local r = Props.Triangle(kit, folder, "R", Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(0, 3, 0), 0.1, Color3.new(1, 1, 1))
		T.eq(#r, 1, "right triangle = 1 wedge")
		local t = Props.Triangle(kit, folder, "T", Vector3.new(0, 0, 0), Vector3.new(4, 0, 0), Vector3.new(1, 2, 0), 0.1, Color3.new(1, 1, 1))
		T.eq(#t, 2, "scalene triangle = 2 wedges")
		local area = 0
		for _, w in t do
			area += w.Size.Y * w.Size.Z / 2
			T.near(math.abs(w.CFrame.XVector.Z), 1, 1e-4, "wedge extruded along the triangle normal")
		end
		T.near(area, 4, 1e-3, "two halves cover the triangle area")
		local star = Props.StarOutline(5, 1, 0.4)
		T.eq(#star, 10, "star outline has 10 vertices")
		local poly = Props.Polygon(kit, folder, "P", star, CFrame.new(), 0.1, Color3.new(1, 1, 1))
		T.ok(#poly >= 8 and #poly <= 16, "star polygon triangulated (" .. #poly .. " wedges)")
	end,

	bone = function(T, Loader)
		local Bone = Loader.require(ROOT .. ".Bone")
		T.eq(Bone.Colors.Blue, Color3.fromRGB(20, 169, 255), "Bone.Colors.Blue")
		T.eq(Bone.Colors.Orange, Color3.fromRGB(255, 160, 64), "Bone.Colors.Orange")
		for _, key in { "White", "Red", "Purple", "Cyan" } do
			T.ok(typeof(Bone.Colors[key]) == "Color3", "Bone.Colors." .. key)
		end
		for _, len in { 0.5, 1, 4, 12, 40 } do
			for _, th in { 0.3, 0.8 } do
				local m = Bone.Build(len, th, Bone.Colors.White)
				local list = checkProp(T, m, ("Bone %g x %g"):format(len, th), 5)
				T.eq(m.PrimaryPart.Name, "Shaft", "PrimaryPart Shaft")
				-- pivot frame: UpVector = bone axis
				local pivot = m.PrimaryPart.CFrame * m.PrimaryPart.PivotOffset
				nearV(T, pivot.UpVector, Vector3.new(0, 1, 0), 1e-4, "pivot UpVector is the bone axis")
				nearV(T, pivot.Position, Vector3.new(0, 0, 0), 1e-4, "centred on the origin")
				-- tip to tip length along Y
				local top, bottom = -math.huge, math.huge
				for _, p in list do
					local ext = if p.Shape == Enum.PartType.Ball then p.Size.Y / 2 else p.Size.Y / 2
					if p.Name == "Shaft" then
						ext = p.Size.X / 2
					end
					top = math.max(top, p.Position.Y + ext)
					bottom = math.min(bottom, p.Position.Y - ext)
				end
				T.near(top - bottom, len, math.max(0.02, len * 0.02), ("Bone %g: tip-to-tip length"):format(len))
			end
		end
		local neon = Bone.Build(3, 0.4, Bone.Colors.Orange, Enum.Material.Neon)
		T.eq(neon.Shaft.Material, Enum.Material.Neon, "material parameter")
		Bone.SetLength(neon, 8)
		T.near(neon:GetAttribute("Length"), 8, 1e-6, "SetLength attribute")
		T.ok(neon.KnobTopL.Position.Y > 3.5, "SetLength moves the knobs")
		Bone.SetColor(neon, Bone.Colors.Blue)
		T.eq(neon.KnobBottomR.Color, Bone.Colors.Blue, "SetColor")
	end,

	blaster = function(T, Loader)
		local GB = Loader.require(ROOT .. ".GasterBlaster")
		local Meshes = Loader.require("ReplicatedStorage.Shared.Meshes")
		T.eq(#GB.Styles(), 3, "three styles")
		for _, style in GB.Styles() do
			for _, scale in { 1, 2.5 } do
				local label = ("Blaster %s x%g"):format(style, scale)
				local m = GB.Build(style, scale)
				checkProp(T, m, label, 90)
				local core = m.PrimaryPart
				T.eq(core.Name, "Core", label .. ": PrimaryPart Core")
				T.eq(m:GetAttribute("Style"), style, label .. ": Style attribute")
				T.eq(m:GetAttribute("RigScale"), scale, label .. ": RigScale for HDMesh")
				local jaw = m:FindFirstChild("Jaw")
				T.ok(jaw and jaw:IsA("Model") and jaw.PrimaryPart and jaw.PrimaryPart.Name == "Mandible", label .. ": Jaw model")
				local hinge = core:FindFirstChild("JawHinge")
				local muzzle = core:FindFirstChild("Muzzle")
				T.ok(hinge and hinge:IsA("Attachment"), label .. ": JawHinge attachment")
				T.ok(muzzle and muzzle:IsA("Attachment"), label .. ": Muzzle attachment")
				nearV(T, muzzle.CFrame.LookVector, Vector3.new(0, 0, -1), 1e-4, label .. ": muzzle looks forward")
				T.ok(core:FindFirstChild("LeftEye") and core:FindFirstChild("RightEye"), label .. ": eye anchors")
				-- HD contract (SPEC 18) checked against the generated mesh data
				local skullData = Meshes.Get("BlasterSkull" .. style)
				local jawData = Meshes.Get("BlasterJaw" .. style)
				local hdSkull = core:FindFirstChild("HD_BlasterSkull")
				T.ok(hdSkull ~= nil, label .. ": HD_BlasterSkull on Core")
				T.eq(hdSkull:GetAttribute("HDMesh"), "BlasterSkull" .. style, label .. ": HDMesh skull name")
				nearV(T, hdSkull:GetAttribute("HDSize"), skullData.Size, 1e-3, label .. ": HDSize = mesh size")
				nearV(T, hdSkull.CFrame.Position, Vector3.new(0, 0, 0), 1e-4, label .. ": skull anchor at Core")
				local anchors = skullData.Anchors
				nearV(T, hinge.CFrame.Position, anchors.JawHinge * scale, 0.01 * scale, label .. ": hinge = HD hinge")
				nearV(T, muzzle.CFrame.Position, anchors.Muzzle * scale, 0.01 * scale, label .. ": muzzle = HD muzzle")
				nearV(T, core.RightEye.CFrame.Position, anchors.RightEye * scale, 0.01 * scale, label .. ": right eye = HD anchor")
				local mandible = jaw.PrimaryPart
				local hdJaw = mandible:FindFirstChild("HD_BlasterJaw")
				T.ok(hdJaw ~= nil, label .. ": HD_BlasterJaw on Mandible")
				T.eq(hdJaw:GetAttribute("HDMesh"), "BlasterJaw" .. style, label .. ": HDMesh jaw name")
				nearV(T, hdJaw:GetAttribute("HDSize"), jawData.Size, 1e-3, label .. ": jaw HDSize")
				local jawHinge = mandible:FindFirstChild("JawHinge")
				-- both hinge attachments coincide in world space, and the HD jaw sits where the mesh says
				local wA = (core.CFrame * hinge.CFrame).Position
				local wB = (mandible.CFrame * jawHinge.CFrame).Position
				nearV(T, wA, wB, 1e-3, label .. ": skull/jaw hinges coincide")
				local hdJawWorld = (mandible.CFrame * hdJaw.CFrame).Position
				nearV(T, wB - hdJawWorld, jawData.Hinge * scale, 0.01 * scale, label .. ": HD jaw hinge offset")
				-- HDGroup tags; eyes and glow stay outside the HD groups
				local skullN, jawN, eyes = 0, 0, 0
				for _, p in parts(m) do
					local g = p:GetAttribute("HDGroup")
					if g == "BlasterSkull" then
						skullN += 1
						T.ok(not p:IsDescendantOf(jaw), label .. ": skull part outside the jaw " .. p.Name)
					elseif g == "BlasterJaw" then
						jawN += 1
						T.ok(p:IsDescendantOf(jaw), label .. ": jaw part inside the jaw " .. p.Name)
					end
					if p:GetAttribute("Role") == "Eye" then
						eyes += 1
						T.eq(g, nil, label .. ": eye parts are not hidden by HD meshes")
					end
				end
				T.ok(skullN >= 20 and jawN >= 6, label .. ": HDGroup tags present")
				T.eq(eyes, 2, label .. ": two Eye parts")
				-- bounding box close to the HD skull + jaw union (fallback matches the HD proportions)
				local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
				for _, p in parts(m) do
					if p.Transparency < 0.99 then
						minV = minV:Min(p.Position)
						maxV = maxV:Max(p.Position)
					end
				end
				local span = (maxV - minV) / scale
				T.ok(math.abs(span.X - skullData.Size.X) < 0.9, label .. ": width close to HD skull (" .. span.X .. ")")
				T.ok(math.abs(span.Z - skullData.Size.Z) < 0.9, label .. ": length close to HD skull (" .. span.Z .. ")")
			end
		end
	end,

	blasterJawAndGlow = function(T, Loader)
		local GB = Loader.require(ROOT .. ".GasterBlaster")
		for _, style in GB.Styles() do
			local m = GB.Build(style, 2)
			local core = m.PrimaryPart
			local mandible = m.Jaw.Mandible
			local chin = m.Jaw:FindFirstChild("Chin")
			local rest = mandible.CFrame
			local chinRest = chin.Position
			-- move the whole blaster first: SetJaw must use the current Core frame
			local shift = CFrame.new(10, 5, -3) * CFrame.Angles(0, math.rad(40), 0)
			for _, p in parts(m) do
				p.CFrame = shift * p.CFrame
			end
			local hingeW = (core.CFrame * core.JawHinge.CFrame).Position
			GB.SetJaw(m, 1)
			T.near(m:GetAttribute("JawOpen"), 1, 1e-6, style .. ": JawOpen attribute")
			local hingeAfter = (mandible.CFrame * mandible.JawHinge.CFrame).Position
			nearV(T, hingeAfter, hingeW, 1e-3, style .. ": jaw rotates about the hinge")
			local chinOpen = chin.Position
			local chinClosedW = (shift * CFrame.new(chinRest)).Position
			T.ok(chinOpen.Y < chinClosedW.Y - 0.5, style .. ": open jaw drops the chin")
			local angle = math.acos(math.clamp((shift.Rotation * rest.Rotation).LookVector:Dot(mandible.CFrame.LookVector), -1, 1))
			T.near(angle, m:GetAttribute("JawMaxOpen"), 0.02, style .. ": opening angle = JawMaxOpen")
			GB.SetJaw(m, 0)
			nearV(T, chin.Position, chinClosedW, 1e-3, style .. ": SetJaw(0) restores the rest pose")
			-- glow
			local light = find(m, "Glow")
			T.ok(light and light:IsA("PointLight") and not light.Enabled, style .. ": light off at rest")
			local c = Color3.fromRGB(20, 169, 255)
			GB.SetGlow(m, c, 1)
			T.ok(light.Enabled and light.Brightness > 0, style .. ": SetGlow enables the light")
			T.eq(m:GetAttribute("GlowIntensity"), 1, style .. ": GlowIntensity")
			local mouth = find(m, "MouthGlow")
			T.ok(mouth.Transparency < 0.5, style .. ": mouth glow visible")
			for _, p in parts(m) do
				if p:GetAttribute("Role") == "Eye" then
					T.eq(p.Material, Enum.Material.Neon, style .. ": glowing eyes are Neon")
				end
			end
			GB.SetGlow(m, c, 0)
			T.ok(not light.Enabled and mouth.Transparency > 0.99, style .. ": SetGlow(0) back to idle")
		end
		T.noerror(function()
			GB.Preview("Fell", 1, 0.6, 0.8)
		end, "Preview helper")
		T.eq(GB.Build("Unknown"):GetAttribute("Style"), "Classic", "unknown style falls back to Classic")
	end,

	soul = function(T, Loader)
		local Soul = Loader.require(ROOT .. ".Soul")
		for _, color in { Color3.fromRGB(255, 0, 0), Color3.fromRGB(66, 252, 255), Color3.fromRGB(0, 60, 255) } do
			for _, size in { 0.5, 1, 3 } do
				local m = Soul.Build(color, size)
				checkProp(T, m, "Soul " .. size, 8)
				T.eq(m.PrimaryPart.Name, "Core", "Soul PrimaryPart Core")
				for _, n in { "LobeL", "LobeR", "TipL", "TipR" } do
					T.ok(m:FindFirstChild(n) ~= nil, "Soul has " .. n)
				end
				for _, p in parts(m) do
					T.eq(p.Material, Enum.Material.Neon, "Soul parts are Neon")
					T.eq(p.Color, color, "Soul colour")
				end
				-- width = size, height ~1.05 size (front silhouette)
				local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
				for _, p in parts(m) do
					local half = p.Size / 2
					local r = p.CFrame.Rotation
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local w = p.Position + r * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
								minX, maxX = math.min(minX, w.X), math.max(maxX, w.X)
								minY, maxY = math.min(minY, w.Y), math.max(maxY, w.Y)
							end
						end
					end
				end
				T.near(maxX - minX, size, size * 0.03, "Soul width = size")
				T.near(maxY - minY, size * 1.05, size * 0.06, "Soul height")
			end
		end
		local broken = Soul.BuildBroken(Color3.fromRGB(255, 0, 0), 1)
		checkProp(T, broken, "SoulBroken", 40)
		local l, r = broken:FindFirstChild("LeftHalf"), broken:FindFirstChild("RightHalf")
		T.ok(l and r and l:IsA("Model") and r:IsA("Model"), "LeftHalf/RightHalf models")
		T.ok(l.PrimaryPart and r.PrimaryPart, "halves have PrimaryParts")
		local pivot = l.PrimaryPart.CFrame * l.PrimaryPart.PivotOffset
		nearV(T, pivot.Position, Vector3.new(0, 0, 0), 1e-4, "half pivot at the heart centre")
		local leftX, rightX = 0, 0
		for _, p in parts(l) do
			leftX += p.Position.X
		end
		for _, p in parts(r) do
			rightX += p.Position.X
		end
		T.ok(leftX < 0 and rightX > 0, "halves on their sides")
		T.noerror(function()
			Soul.BuildBroken(Color3.fromRGB(255, 0, 0), 1, 0.4)
		end, "pre-split broken heart")
		local shards = Soul.Shards(Color3.fromRGB(255, 0, 0), 1, 9, 3)
		T.eq(#shards, 9, "Shards count")
		for i, s in shards do
			T.ok(s:IsA("WedgePart") and s.Parent == nil and s.Anchored, "shard " .. i .. " is an unparented anchored wedge")
			T.ok(s.Position.Magnitude < 0.8, "shard inside the heart area")
		end
		local again = Soul.Shards(Color3.fromRGB(255, 0, 0), 1, 9, 3)
		nearV(T, again[4].Position, shards[4].Position, 1e-9, "Shards deterministic per seed")
		T.ok(#Soul.Outline(1) > 10, "Outline polygon")
	end,

	saveStar = function(T, Loader)
		local SaveStar = Loader.require(ROOT .. ".SaveStar")
		local m = SaveStar.Build()
		checkProp(T, m, "SaveStar", 80)
		T.eq(m.PrimaryPart.Name, "Star", "PrimaryPart Star")
		local lights = 0
		for _, d in m:GetDescendants() do
			if d:IsA("PointLight") then
				lights += 1
			end
		end
		T.eq(lights, 1, "exactly one PointLight (ObjectiveService drives it)")
		local ring = m:FindFirstChild("ProgressRing")
		T.ok(ring ~= nil, "ProgressRing")
		local segs = {}
		for _, p in ring:GetChildren() do
			segs[p:GetAttribute("Index")] = p
		end
		T.eq(m:GetAttribute("RingSegments"), 24, "RingSegments")
		for i = 1, 24 do
			T.ok(segs[i] ~= nil, "segment " .. i)
		end
		local C = SaveStar.Colors
		SaveStar.SetProgress(m, 0.5, false, false)
		T.eq(segs[1].Color, C.Gold, "filled segment gold")
		T.eq(segs[12].Color, C.Gold, "segment 12 filled at 50%")
		T.eq(segs[13].Color, C.Empty, "segment 13 empty at 50%")
		T.eq(segs[12].Material, Enum.Material.Neon, "filled segments glow")
		SaveStar.SetProgress(m, 0.51, false, false)
		T.eq(segs[13].Color, C.Partial, "partial segment")
		SaveStar.SetProgress(m, 0.5, true, false)
		T.eq(segs[5].Color, C.Contested, "contested -> red")
		SaveStar.SetProgress(m, 1, false, true)
		for i = 1, 24 do
			T.eq(segs[i].Color, C.Lit, "lit segment " .. i)
		end
		SaveStar.SetProgress(m, 0, false, false)
		T.eq(segs[1].Color, C.Empty, "reset to empty")
		T.eq(m:GetAttribute("VisualProgress"), 0, "VisualProgress attribute")
		T.noerror(function()
			SaveStar.Preview(0.3, true, false)
		end, "Preview helper")
	end,

	others = function(T, Loader)
		local Props = Loader.require(ROOT)
		local VB = Props.Get("VerdictBox3D")
		local box = VB.Build()
		checkProp(T, box, "VerdictBox3D", 40)
		local screen = box:FindFirstChild("Screen")
		T.ok(screen and screen:IsA("BasePart"), "Screen part")
		T.eq(screen:GetAttribute("SurfaceFace"), "Front", "Screen face")
		T.ok(screen.Position.Z < 0, "Screen on the front (-Z)")

		local Rift = Props.Get("Rift")
		local rift = Rift.Build(Color3.fromRGB(139, 61, 255), 2)
		checkProp(T, rift, "Rift", 60)
		T.noerror(function()
			Rift.SetOpen(rift, 0.2)
			Rift.SetOpen(rift, 1)
		end, "Rift.SetOpen")
		T.near(rift.Void.Size.X, Rift.Build(nil, 2).Void.Size.X, 1e-4, "SetOpen(1) restores the void size")

		local VoidOrb = Props.Get("VoidOrb")
		local orb = VoidOrb.Build()
		checkProp(T, orb, "VoidOrb", 70)
		T.noerror(function()
			VoidOrb.SetPulse(orb, 1)
		end, "VoidOrb.SetPulse")

		local Book = Props.Get("GiantBook")
		local book = Book.Build()
		checkProp(T, book, "GiantBook", 80)
		local left, right = book:FindFirstChild("LeftCover"), book:FindFirstChild("RightCover")
		T.ok(left and right and left.PrimaryPart and right.PrimaryPart, "LeftCover/RightCover models")
		local openUp = left.PrimaryPart.CFrame.UpVector
		Book.SetOpen(book, 0)
		T.near(math.abs(left.PrimaryPart.CFrame.UpVector.Y), 0, 1e-3, "closed: covers vertical")
		T.ok(left.PrimaryPart.Position.Y < 0 and right.PrimaryPart.Position.Y < 0, "closed: covers swing down")
		T.ok(left.PrimaryPart.Position.X < 0 and right.PrimaryPart.Position.X > 0, "closed: covers on their sides")
		Book.SetOpen(book, 1)
		nearV(T, left.PrimaryPart.CFrame.UpVector, openUp, 1e-4, "SetOpen(1) restores")

		local Dish = Props.Get("Dish")
		for _, kind in Dish.Kinds() do
			local d = Dish.Build(kind)
			checkProp(T, d, "Dish " .. kind, 40)
			T.eq(d.PrimaryPart.Name, "Plate", "Dish PrimaryPart Plate")
			T.eq(d:GetAttribute("Kind"), kind, "Dish Kind")
		end

		local StarBone = Props.Get("StarBone")
		local sb = StarBone.Build()
		checkProp(T, sb, "StarBone", 20)
		T.eq(sb.PrimaryPart.Name, "Star", "StarBone PrimaryPart")

		local Chain = Props.Get("Chain")
		for _, n in { 1, 6, 16 } do
			local c = Chain.Build(n)
			checkProp(T, c, "Chain " .. n, 6 * n + 10)
			T.eq(c:GetAttribute("Links"), n, "Links attribute")
		end
		local c = Chain.Build(6)
		local from, to = Vector3.new(0, 1, 0), Vector3.new(12, 3, 4)
		Chain.Fit(c, from, to, 0)
		nearV(T, c.Anchor.Position, from, 1e-4, "Fit: anchor at from")
		local tipZ = math.huge
		local far = 0
		for _, p in parts(c) do
			far = math.max(far, (p.Position - from).Magnitude)
		end
		T.near(far, (to - from).Magnitude, 0.6, "Fit: hook reaches the target")
		local _ = tipZ

		if Props.Get("Weapons") and Props.Get("Weapons").Has and Props.Get("Weapons").Has("BoneSword") then
			local sword = Props.Get("BoneSword").Build()
			checkProp(T, sword, "BoneSword")
		end
	end,
}

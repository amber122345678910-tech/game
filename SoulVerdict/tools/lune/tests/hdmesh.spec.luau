--!nocheck
-- HD mesh tier: generated data modules (src/shared/Meshes) + the decoder in src/client/VFX/HDMesh.luau.
-- Regenerate the data with: python3 tools/meshgen/build.py   (docs/HD_MESHES.md)
local fs = require("@lune/fs")

local EXPECTED = {
	"SansSkullClassic",
	"SansSkullFell",
	"SansSkullEclipse",
	"BlasterSkullClassic",
	"BlasterJawClassic",
	"BlasterSkullFell",
	"BlasterJawFell",
	"BlasterSkullEclipse",
	"BlasterJawEclipse",
}

local function budgetFor(name)
	if string.find(name, "^SansSkull") then
		return 6000
	elseif string.find(name, "^BlasterSkull") then
		return 8000
	elseif string.find(name, "^BlasterJaw") then
		return 3000
	end
	return 0
end

local function modules(Loader)
	local Meshes = Loader.require("ReplicatedStorage.Shared.Meshes")
	local HDMesh = Loader.require("StarterPlayer.StarterPlayerScripts.Client.VFX.HDMesh")
	return Meshes, HDMesh
end

local decodedCache = {}
local function decoded(HDMesh, data)
	if decodedCache[data.Name] == nil then
		decodedCache[data.Name] = HDMesh.Decode(data)
	end
	return decodedCache[data.Name]
end

return {
	index_lists_every_mesh = function(T, Loader)
		local Meshes = modules(Loader)
		local names = Meshes.Names()
		T.eq(#names, #EXPECTED, "mesh count")
		for i, name in EXPECTED do
			T.eq(names[i], name, "name order")
			T.ok(Meshes.Has(name), name .. " Has")
			local data = Meshes.Get(name)
			T.ok(data ~= nil, name .. " module loads")
			if data then
				T.eq(data.Name, name, "Name field")
				T.eq(data.Format, 1, name .. " format")
				T.ok(typeof(data.Size) == "Vector3", name .. " Size is a Vector3")
			end
		end
		T.eq(Meshes.Get("NoSuchMesh"), nil, "unknown mesh -> nil")
		T.ok(not Meshes.Has("NoSuchMesh"), "unknown mesh Has")
	end,

	every_mesh_decodes_and_is_consistent = function(T, Loader)
		local Meshes, HDMesh = modules(Loader)
		for _, name in EXPECTED do
			local data = Meshes.Get(name)
			local ok, m = pcall(decoded, HDMesh, data)
			if not T.ok(ok, name .. " decodes: " .. tostring(m)) then
				continue
			end
			T.eq(m.vertexCount, data.VertexCount, name .. " vertex count")
			T.eq(m.triangleCount, data.TriangleCount, name .. " triangle count")
			T.eq(#m.positions, data.VertexCount, name .. " positions")
			T.eq(#m.normals, data.VertexCount, name .. " normals")
			T.eq(#m.colors, data.VertexCount, name .. " colors")
			T.eq(#m.indices, data.TriangleCount * 3, name .. " indices")
			T.ok(data.TriangleCount <= budgetFor(name), name .. " within triangle budget")
			T.ok(data.TriangleCount >= budgetFor(name) * 0.6, name .. " uses its budget")
			T.ok(data.VertexCount <= 60000 and data.TriangleCount <= 20000, name .. " within EditableMesh limits")
			-- indices in range, no degenerate triangles, every vertex referenced
			local used = table.create(m.vertexCount, false)
			local badIndex, degenerate = 0, 0
			for t = 0, m.triangleCount - 1 do
				local a, b, c = m.indices[t * 3 + 1], m.indices[t * 3 + 2], m.indices[t * 3 + 3]
				for _, i in { a, b, c } do
					if type(i) ~= "number" or i < 1 or i > m.vertexCount or i % 1 ~= 0 then
						badIndex += 1
					else
						used[i] = true
					end
				end
				if a == b or b == c or a == c then
					degenerate += 1
				end
			end
			T.eq(badIndex, 0, name .. " indices in range")
			T.eq(degenerate, 0, name .. " degenerate triangles")
			local unused = 0
			for i = 1, m.vertexCount do
				if not used[i] then
					unused += 1
				end
			end
			T.eq(unused, 0, name .. " unreferenced vertices")
			-- unit normals
			local worst = 0
			for _, n in m.normals do
				worst = math.max(worst, math.abs(n.Magnitude - 1))
			end
			T.ok(worst < 1e-3, name .. " normals unit length (worst " .. worst .. ")")
			-- size: matches the decoded bounds, sane magnitude, centred on the bounding box
			local ext = m.boundsMax - m.boundsMin
			T.near(ext.X, data.Size.X, 0.01, name .. " size X")
			T.near(ext.Y, data.Size.Y, 0.01, name .. " size Y")
			T.near(ext.Z, data.Size.Z, 0.01, name .. " size Z")
			for _, axis in { "X", "Y", "Z" } do
				T.ok(data.Size[axis] > 0.4 and data.Size[axis] < 8, name .. " size " .. axis .. " sane")
			end
			local mid = (m.boundsMax + m.boundsMin) / 2
			T.ok(mid.Magnitude < 0.01, name .. " centred at the bounding-box centre")
			-- positions inside the bounds
			local outside = 0
			for _, p in m.positions do
				local d = p - m.boundsMin
				local e = m.boundsMax - p
				if d.X < -1e-3 or d.Y < -1e-3 or d.Z < -1e-3 or e.X < -1e-3 or e.Y < -1e-3 or e.Z < -1e-3 then
					outside += 1
				end
			end
			T.eq(outside, 0, name .. " positions inside bounds")
			-- palette
			T.ok(#m.palette >= 2 and #m.palette <= 256, name .. " palette size")
			-- winding: signed volume must be positive (counter-clockwise = outward, Roblox front faces)
			local vol = 0
			for t = 0, m.triangleCount - 1 do
				local a = m.positions[m.indices[t * 3 + 1]]
				local b = m.positions[m.indices[t * 3 + 2]]
				local c = m.positions[m.indices[t * 3 + 3]]
				vol += a:Dot(b:Cross(c)) / 6
			end
			T.ok(vol > 0, name .. " outward winding (signed volume " .. vol .. ")")
			-- decoded vertex normals agree with the triangle winding (catches normal-decoding bugs)
			local agree = 0
			for t = 0, m.triangleCount - 1 do
				local ia, ib, ic = m.indices[t * 3 + 1], m.indices[t * 3 + 2], m.indices[t * 3 + 3]
				local a, b, c = m.positions[ia], m.positions[ib], m.positions[ic]
				local fn = (b - a):Cross(c - a)
				if fn:Dot(m.normals[ia] + m.normals[ib] + m.normals[ic]) > 0 then
					agree += 1
				end
			end
			T.ok(agree / m.triangleCount > 0.97, name .. " normals match winding (" .. agree .. "/" .. m.triangleCount .. ")")
		end
	end,

	classic_skull_reads_as_sans = function(T, Loader)
		local Meshes = modules(Loader)
		local s = Meshes.Get("SansSkullClassic").Size
		T.ok(s.X > s.Y, "Classic skull is wider than tall")
		T.ok(
			math.abs(s.X - 2.1) < 0.25 and math.abs(s.Y - 1.85) < 0.25 and math.abs(s.Z - 1.95) < 0.25,
			"nominal size ~2.1 x 1.85 x 1.95"
		)
		for _, name in { "SansSkullClassic", "SansSkullFell", "SansSkullEclipse" } do
			local a = Meshes.Get(name).Anchors
			T.ok(a and a.LeftEye and a.RightEye and a.Mouth, name .. " eye/mouth anchors")
			if a and a.LeftEye and a.RightEye then
				T.ok(a.RightEye.X > 0 and a.LeftEye.X < 0, name .. " RightEye on +X (character's right)")
				T.ok(a.LeftEye.Z < 0, name .. " eyes on the front (-Z) half")
			end
		end
	end,

	blasters_have_hinges = function(T, Loader)
		local Meshes = modules(Loader)
		for _, style in { "Classic", "Fell", "Eclipse" } do
			local jaw = Meshes.Get("BlasterJaw" .. style)
			local skull = Meshes.Get("BlasterSkull" .. style)
			T.ok(typeof(jaw.Hinge) == "Vector3", style .. " jaw Hinge")
			if typeof(jaw.Hinge) == "Vector3" then
				-- hinge sits at the back of the jaw (front is -Z) and inside its bounds (with slack)
				T.ok(jaw.Hinge.Z > 0, style .. " jaw hinge at the back")
				local h, half = jaw.Hinge, jaw.Size / 2
				T.ok(
					math.abs(h.X) <= half.X + 0.2 and math.abs(h.Y) <= half.Y + 0.2 and math.abs(h.Z) <= half.Z + 0.2,
					style .. " jaw hinge near the jaw"
				)
			end
			local a = skull.Anchors
			T.ok(a and typeof(a.JawHinge) == "Vector3", style .. " skull JawHinge anchor")
			T.ok(a and typeof(a.Muzzle) == "Vector3" and a.Muzzle.Z < 0, style .. " muzzle at the front")
			T.ok(a and a.LeftEye and a.RightEye, style .. " blaster eye anchors")
			T.ok(skull.Size.Z > skull.Size.Y, style .. " skull is elongated along Z")
		end
	end,

	decoder_rejects_garbage = function(T, Loader)
		local _, HDMesh = modules(Loader)
		T.fails(function()
			HDMesh.Decode("aGVsbG8gd29ybGQ=")
		end, "non-SVM1 payload errors")
		local data = Loader.require("ReplicatedStorage.Shared.Meshes").Get("BlasterJawClassic")
		T.fails(function()
			HDMesh.Decode(string.sub(data.Data, 1, #data.Data - 400))
		end, "truncated payload errors")
	end,

	offline_fails_soft = function(T, Loader)
		local _, HDMesh = modules(Loader)
		local Instance, Vector3 = Loader.roblox.Instance, Loader.roblox.Vector3
		Loader.quietWarnings = true
		T.eq(HDMesh.Available(), false, "no HD tier under Lune")
		T.eq(HDMesh.Tier("SansSkullClassic"), "None", "tier None")
		T.eq(HDMesh.Create("SansSkullClassic"), nil, "Create -> nil without a tier")
		T.eq(HDMesh.CreateBlaster("Classic"), nil, "CreateBlaster -> nil without a tier")
		local model = Instance.new("Model")
		local head = Instance.new("Part")
		head.Name = "Head"
		head:SetAttribute("HDGroup", "Skull")
		local anchor = Instance.new("Attachment")
		anchor.Name = "HD_Skull"
		anchor:SetAttribute("HDMesh", "SansSkullClassic")
		anchor:SetAttribute("HDSize", Vector3.new(2.1, 1.85, 1.95))
		anchor.Parent = head
		head.Parent = model
		T.eq(HDMesh.ApplyToModel(model), false, "ApplyToModel -> false without a tier")
		T.eq(head:FindFirstChild("HDMesh_Skull"), nil, "no HD part added; the part-built skull stays")
		T.noerror(function()
			HDMesh.RemoveFromModel(model)
			HDMesh.Preload()
		end, "RemoveFromModel / Preload are safe offline")
		Loader.quietWarnings = false
	end,

	data_modules_stay_small = function(T)
		for _, name in EXPECTED do
			local path = "src/shared/Meshes/" .. name .. ".luau"
			local ok, src = pcall(fs.readFile, path)
			if T.ok(ok, path .. " exists") then
				T.ok(#src < 200 * 1024, name .. " module under 200 KB (" .. math.floor(#src / 1024) .. " KB)")
				T.eq(string.sub(src, 1, 9), "--!strict", name .. " starts with --!strict")
			end
		end
	end,
}

--!nocheck
-- dump_model.luau: builds a model with the project's Lune-safe builders and dumps a render-ready
-- scene description (JSON) for tools/preview/render.mjs.
--
-- Usage (from the project root):
--   lune run tools/lune/dump_model.luau rig <BlueprintId> [--pose <name|json>] [--skin <id>] [--style <id>]
--                                                        [--scale <n>] [--out file.json]
--   lune run tools/lune/dump_model.luau prop <PropModule> [jsonArgs] [--pose ...] [--out ...]
--        -> require(Rigs/Props/<PropModule>).Build(table.unpack(args))
--   lune run tools/lune/dump_model.luau map <MapId> [jsonArgs] [--out ...]
--        -> require(Maps/<MapId>).Build(...)   (a Model, or a table with .Model)
--   lune run tools/lune/dump_model.luau module <src/path/To/Module> <Function> [jsonArgs] [--out ...]
--        -> any module function returning a Model / Instance / table with .Model
--   lune run tools/lune/dump_model.luau skeleton Human|Skeleton [--pose p]   bare skeleton (physics boxes + pivots)
--   lune run tools/lune/dump_model.luau board shapes|materials|neon   renderer test boards built with PartKit
--   extra rig flags: --physics (show physics parts + joint pivots), --palette '{"Key":[r,g,b]}' (0..1)
--   lune run tools/lune/dump_model.luau list            (blueprints, props, maps, poses)
--
-- jsonArgs is a JSON array. Typed values: {"$Color3":[r,g,b]} (0..1), {"$rgb":[255,128,0]},
-- {"$Vector3":[x,y,z]}, {"$CFrame":[x,y,z]} or 12 numbers, {"$Enum":"Material.Neon"}.
-- --pose: a reference pose of the rig family (Rigs/Skeletons Poses: Rest, APose, TPose, Wave, Walk,
--   Action, Pockets, Shrug, Ready), an Anim clip name "Clip" or "Clip@0.35" (seconds) when
--   Shared/Anim/Clips/<Family>.luau exists, or an inline JSON pose {"RightShoulder":[0,0,90]}.
--
-- Output JSON:
--   { kind, id, name, pose, skin,
--     parts: [{ name, path, role, shape: "Block"|"Ball"|"Cylinder"|"Wedge"|"CornerWedge",
--               mesh: null | { type: "Sphere"|"Cylinder"|"CylinderY"|"Head"|"Wedge"|"Brick"|"FileMesh",
--                              scale: [x,y,z], offset: [x,y,z] },
--               size: [x,y,z], cf: [x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22],
--               color: [r,g,b] (0..1 sRGB), material, transparency, reflectance, castShadow }],
--     lights: [{ type: "Point"|"Spot"|"Surface", pos, dir, color, brightness, range, angle, shadows }],
--     highlights: [{ fill, outline, fillT, outlineT, depthMode, parts: [part indices, 0-based] }],
--     anchors: { [name]: { pos: [x,y,z], size: [x,y,z]? } },     -- Head/UpperTorso/attachments
--     bounds: { min: [x,y,z], max: [x,y,z] },
--     stats: { partCount, visibleParts, motors, lights, highlights } }
-- Parts with Transparency >= 1 are skipped (rig physics parts). CFrames are after forward kinematics.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("./loader")
local roblox = Loader.roblox

local CFrame, Vector3, Color3, Enum = roblox.CFrame, roblox.Vector3, roblox.Color3, roblox.Enum

local function fail(msg)
	io.stderr:write("dump_model: " .. msg .. "\n")
	process.exit(1)
end

-- CLI ------------------------------------------------------------------------------------------
local positional, flags = {}, {}
do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if string.sub(a, 1, 2) == "--" then
			local key = string.sub(a, 3)
			local value = args[i + 1]
			if value == nil or string.sub(value, 1, 2) == "--" then
				flags[key] = true
				i += 1
			else
				flags[key] = value
				i += 2
			end
		else
			table.insert(positional, a)
			i += 1
		end
	end
end

local kind = positional[1]
if kind == nil then
	fail("usage: dump_model.luau <rig|prop|map|module|list> <id> [...] [--pose p] [--skin s] [--out f]")
end

-- JSON args -> Roblox values --------------------------------------------------------------------
local function toRoblox(v)
	if type(v) ~= "table" then
		return v
	end
	if v["$Color3"] then
		local c = v["$Color3"]
		return Color3.new(c[1], c[2], c[3])
	elseif v["$rgb"] then
		local c = v["$rgb"]
		return Color3.fromRGB(c[1], c[2], c[3])
	elseif v["$Vector3"] then
		local c = v["$Vector3"]
		return Vector3.new(c[1], c[2], c[3])
	elseif v["$CFrame"] then
		local c = v["$CFrame"]
		if #c >= 12 then
			return CFrame.new(table.unpack(c, 1, 12))
		end
		return CFrame.new(c[1] or 0, c[2] or 0, c[3] or 0)
	elseif v["$Enum"] then
		local enumName, item = string.match(v["$Enum"], "^([^%.]+)%.(.+)$")
		return Enum[enumName][item]
	end
	local out = {}
	for k, x in v do
		out[k] = toRoblox(x)
	end
	return out
end

local function decodeArgs(s)
	if s == nil then
		return {}
	end
	local ok, decoded = pcall(serde.decode, "json", s)
	if not ok or type(decoded) ~= "table" then
		fail("jsonArgs must be a JSON array, got: " .. tostring(s))
	end
	return toRoblox(decoded)
end

local function listModules(dir)
	local out = {}
	if fs.isDir(dir) then
		for _, f in fs.readDir(dir) do
			local name = string.match(f, "^(.-)%.luau$")
			if name and name ~= "init" then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

-- Build ------------------------------------------------------------------------------------------
local RigBuilder = Loader.require("ReplicatedStorage.Shared.Rigs.RigBuilder")

if kind == "list" then
	print("blueprints: " .. table.concat(RigBuilder.Blueprints(), ", "))
	print("props:      " .. table.concat(listModules("src/shared/Rigs/Props"), ", "))
	print("maps:       " .. table.concat(listModules("src/shared/Maps"), ", "))
	local Skeletons = Loader.require("ReplicatedStorage.Shared.Rigs.Skeletons")
	for _, id in Skeletons.List() do
		local names = {}
		for n in Skeletons.Get(id).Poses do
			table.insert(names, n)
		end
		table.sort(names)
		print(("poses[%s]: %s"):format(id, table.concat(names, ", ")))
	end
	process.exit(0)
end

-- Renderer test boards (PartKit only) -------------------------------------------------------------
local function buildBoard(which)
	local PartKit = Loader.require("ReplicatedStorage.Shared.Rigs.PartKit")
	local K = PartKit.new({ Anchored = true })
	local m = roblox.Instance.new("Model")
	m.Name = "Board_" .. which
	local white = Color3.fromRGB(235, 235, 235)
	local base = K.Box(
		m,
		"Base",
		Vector3.new(26, 0.4, 14),
		CFrame.new(0, 0.2, 0),
		Color3.fromRGB(90, 92, 98),
		{ Material = Enum.Material.Slate }
	)
	local _ = base
	if which == "shapes" then
		-- row 1 (z = -3): primitives, every one in its DEFAULT orientation (front = -Z)
		local y = 1.4
		K.Box(m, "Block", Vector3.new(2, 2, 2), CFrame.new(-10, y, -3), Color3.fromRGB(220, 70, 60))
		K.Ball(m, "Ball", 2, CFrame.new(-7, y, -3), Color3.fromRGB(240, 170, 50))
		K.Cyl(m, "CylinderX", 2.4, 1.6, CFrame.new(-4, y, -3), Color3.fromRGB(90, 190, 90))
		K.Wedge(m, "Wedge", Vector3.new(2, 2, 2), CFrame.new(-1, y, -3), Color3.fromRGB(70, 140, 230))
		K.CornerWedge(m, "CornerWedge", Vector3.new(2, 2, 2), CFrame.new(2, y, -3), Color3.fromRGB(160, 90, 220))
		K.Ellipsoid(m, "Ellipsoid", Vector3.new(2.6, 1.6, 1.2), CFrame.new(5.5, y, -3), Color3.fromRGB(240, 240, 240))
		local head = K.Box(m, "HeadMesh", Vector3.new(2, 1, 1), CFrame.new(9, y, -3), Color3.fromRGB(245, 205, 160))
		local hm = roblox.Instance.new("SpecialMesh")
		hm.MeshType = Enum.MeshType.Head
		hm.Scale = Vector3.new(1.25, 1.25, 1.25)
		hm.Parent = head
		-- direction markers: a red nub on each part's FRONT (-Z) face, green on +X (right)
		for _, x in { -10, -7, -4, -1, 2, 5.5, 9 } do
			K.Ball(
				m,
				"FrontMarker",
				0.3,
				CFrame.new(x, y, -4.25),
				Color3.fromRGB(255, 0, 0),
				{ Material = Enum.Material.Neon }
			)
			K.Ball(
				m,
				"RightMarker",
				0.3,
				CFrame.new(x + 1.35, y, -3),
				Color3.fromRGB(0, 220, 0),
				{ Material = Enum.Material.Neon }
			)
		end
		-- row 2 (z = 3): composite builders
		K.RoundedBox(
			m,
			"RoundedAll",
			Vector3.new(2.2, 1.6, 1.6),
			CFrame.new(-10, 1.2, 3),
			Color3.fromRGB(200, 200, 210),
			0.35
		)
		K.RoundedBox(
			m,
			"RoundedY",
			Vector3.new(2.2, 1.6, 1.6),
			CFrame.new(-7, 1.2, 3),
			Color3.fromRGB(200, 200, 210),
			0.35,
			{ Round = "Y" }
		)
		K.Bone(
			m,
			"Bone",
			Vector3.new(-4.8, 0.8, 3),
			Vector3.new(-3.2, 2.6, 3),
			0.35,
			Color3.fromRGB(250, 250, 245),
			{ Role = "Bone" }
		)
		K.Ring(m, "Ring", CFrame.new(-1, 1.2, 3), 0.9, 14, 0.32, Color3.fromRGB(245, 245, 245), { Role = "Trim" })
		K.Arc(
			m,
			"Smile",
			CFrame.new(2, 1.6, 2.2),
			0.8,
			200,
			340,
			8,
			0.12,
			0.12,
			Color3.fromRGB(30, 30, 30),
			{ Joints = true }
		)
		K.Cone(
			m,
			"Cone",
			Vector3.new(4.5, 0.4, 3),
			Vector3.new(4.5, 2.8, 3),
			1.4,
			0.05,
			Color3.fromRGB(230, 120, 50),
			{ Segments = 6 }
		)
		K.Taper(m, "Horn", Vector3.new(7, 0.6, 3), Vector3.new(7.8, 2.6, 2.6), 0.9, 0.12, Color3.fromRGB(240, 230, 210))
		K.Tube(
			m,
			"Tube",
			{ Vector3.new(9, 0.6, 3), Vector3.new(9.6, 1.8, 3.4), Vector3.new(10.4, 2.2, 2.6), Vector3.new(11, 1.2, 3) },
			0.3,
			Color3.fromRGB(60, 200, 200),
			{ Caps = true }
		)
	elseif which == "materials" then
		local names = {
			"SmoothPlastic",
			"Plastic",
			"Neon",
			"Glass",
			"ForceField",
			"Metal",
			"DiamondPlate",
			"Foil",
			"CorrodedMetal",
			"Fabric",
			"Carpet",
			"Leather",
			"Wood",
			"WoodPlanks",
			"Marble",
			"Granite",
			"Slate",
			"Concrete",
			"Brick",
			"Cobblestone",
			"Pebble",
			"Rock",
			"Basalt",
			"CrackedLava",
			"Sand",
			"Snow",
			"Ice",
			"Grass",
			"LeafyGrass",
			"CeramicTiles",
		}
		for i, name in names do
			local col, row = (i - 1) % 10, math.floor((i - 1) / 10)
			local x, z = -11.25 + col * 2.5, -4 + row * 4
			local color = if name == "Neon"
				then Color3.fromRGB(80, 200, 255)
				elseif name == "ForceField" then Color3.fromRGB(255, 120, 240)
				elseif name == "Glass" then Color3.fromRGB(150, 210, 255)
				elseif name == "Grass" or name == "LeafyGrass" then Color3.fromRGB(90, 160, 70)
				elseif name == "Brick" then Color3.fromRGB(170, 85, 60)
				elseif name == "Wood" or name == "WoodPlanks" then Color3.fromRGB(150, 105, 65)
				elseif name == "CrackedLava" then Color3.fromRGB(70, 50, 45)
				else Color3.fromRGB(205, 205, 210)
			K.Box(
				m,
				name .. "_Block",
				Vector3.new(2, 1.6, 2),
				CFrame.new(x, 1.2, z),
				color,
				{ Material = Enum.Material[name] }
			)
			K.Ball(m, name .. "_Ball", 1.4, CFrame.new(x, 2.75, z), color, { Material = Enum.Material[name] })
		end
	elseif which == "neon" then
		m:FindFirstChild("Base").Color = Color3.fromRGB(28, 28, 34)
		K.Ball(
			m,
			"NeonBall",
			1.6,
			CFrame.new(-6, 1.6, 0),
			Color3.fromRGB(80, 200, 255),
			{ Material = Enum.Material.Neon }
		)
		K.Ellipsoid(
			m,
			"NeonShell",
			Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(-6, 1.6, 0),
			Color3.fromRGB(80, 200, 255),
			{ Material = Enum.Material.Neon, Transparency = 0.7 }
		)
		K.Bone(
			m,
			"NeonBone",
			Vector3.new(-2, 0.6, 0),
			Vector3.new(0, 2.6, 0),
			0.35,
			Color3.fromRGB(255, 255, 255),
			{ Material = Enum.Material.Neon }
		)
		K.Cyl(
			m,
			"OrangeBar",
			3,
			0.3,
			CFrame.new(3, 1.2, 0),
			Color3.fromRGB(255, 150, 40),
			{ Material = Enum.Material.Neon }
		)
		local lamp = K.Ball(
			m,
			"Lamp",
			0.4,
			CFrame.new(6, 2.5, -1),
			Color3.fromRGB(255, 220, 160),
			{ Material = Enum.Material.Neon }
		)
		K.Light(lamp, "Point", { Brightness = 3, Range = 12, Color = Color3.fromRGB(255, 200, 140) })
		local spot = K.Box(
			m,
			"Spot",
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(-2, 6, -2) * CFrame.Angles(math.rad(-60), 0, 0),
			Color3.fromRGB(40, 40, 40)
		)
		K.Light(
			spot,
			"Spot",
			{ Brightness = 5, Range = 16, Angle = 50, Color = Color3.fromRGB(120, 160, 255), Face = Enum.NormalId.Front }
		)
		local hlModel = roblox.Instance.new("Model")
		hlModel.Name = "Highlighted"
		K.Box(hlModel, "HLBlock", Vector3.new(1.6, 1.6, 1.6), CFrame.new(8, 1.2, 1.5), Color3.fromRGB(230, 230, 230))
		K.Ball(hlModel, "HLBall", 1.2, CFrame.new(8, 2.6, 1.5), Color3.fromRGB(230, 230, 230))
		local hl = roblox.Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 60, 60)
		hl.FillTransparency = 0.75
		hl.OutlineColor = Color3.fromRGB(0, 0, 0)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = hlModel
		hlModel.Parent = m
	else
		fail("unknown board " .. tostring(which) .. " (shapes|materials|neon)")
	end
	return m
end

local function asModel(result, label)
	if type(result) == "table" then
		result = result.Model or result.model or result[1]
	end
	if typeof(result) ~= "Instance" then
		fail(label .. " did not return a Model/Instance (or a table with .Model)")
	end
	if result:IsA("Model") then
		return result
	end
	local holder = roblox.Instance.new("Model")
	holder.Name = result.Name
	result.Parent = holder
	return holder
end

local id = positional[2]
local model
if kind == "rig" then
	if id == nil then
		fail("rig needs a blueprint id (available: " .. table.concat(RigBuilder.Blueprints(), ", ") .. ")")
	end
	local palette = nil
	if type(flags.palette) == "string" then
		palette = {}
		for key, c in serde.decode("json", flags.palette) do
			palette[key] = Color3.new(c[1], c[2], c[3])
		end
	end
	model = RigBuilder.Build(id, {
		Skin = flags.skin,
		Style = flags.style,
		Name = flags.name,
		Scale = flags.scale and tonumber(flags.scale) or nil,
		Palette = palette,
	})
	-- RigBuilder only records the style id; apply the actual RigStyles look so previews show it.
	if type(flags.style) == "string" then
		local RigStyles = Loader.requirePath("src/shared/Rigs/RigStyles")
		if not RigStyles.Apply(model, flags.style) then
			fail("unknown rig style '" .. flags.style .. "' (available: " .. table.concat(RigStyles.List(), ", ") .. ")")
		end
	end
elseif kind == "skeleton" then
	local family = id or "Human"
	model = RigBuilder.BuildFromBlueprint({
		Id = "Skeleton_" .. family,
		Family = family,
		Skeleton = family,
		Palette = {},
		Build = function() end,
	}, { Name = family .. " skeleton" })
	flags.physics = true
elseif kind == "prop" or kind == "map" then
	local dir = if kind == "prop" then "src/shared/Rigs/Props" else "src/shared/Maps"
	if id == nil or not fs.isFile(dir .. "/" .. id .. ".luau") then
		fail(
			("%s '%s' not found in %s (available: %s)"):format(
				kind,
				tostring(id),
				dir,
				table.concat(listModules(dir), ", ")
			)
		)
	end
	local mod = Loader.requirePath(dir .. "/" .. id)
	local fn = if type(mod) == "table" then (mod.Build or mod.build) else nil
	if type(fn) ~= "function" then
		fail(id .. " has no Build function")
	end
	model = asModel(fn(table.unpack(decodeArgs(positional[3]))), id .. ".Build")
elseif kind == "board" then
	model = buildBoard(id or "shapes")
elseif kind == "module" then
	local path, fnName = id, positional[3]
	if path == nil or fnName == nil then
		fail("module needs <path> <function> [jsonArgs]")
	end
	local mod = Loader.requirePath(path)
	local fn = mod[fnName]
	if type(fn) ~= "function" then
		fail(path .. " has no function " .. fnName)
	end
	model = asModel(fn(table.unpack(decodeArgs(positional[4]))), path .. "." .. fnName)
	id = path .. ":" .. fnName
else
	fail("unknown kind " .. tostring(kind))
end

-- Pose ---------------------------------------------------------------------------------------------
local function lerpPose(a, b, t)
	local out = {}
	for joint, va in a do
		local vb = b[joint] or {}
		local v = {}
		for i = 1, math.max(#va, #vb) do
			local x, y = va[i] or 0, vb[i] or 0
			v[i] = x + (y - x) * t
		end
		out[joint] = v
	end
	for joint, vb in b do
		if out[joint] == nil then
			local v = {}
			for i, y in vb do
				v[i] = y * t
			end
			out[joint] = v
		end
	end
	return out
end

local function samplePose(clip, time)
	local keys = clip.Keys or {}
	if #keys == 0 then
		return {}
	end
	if time == nil or #keys == 1 or time <= keys[1].t then
		return keys[1].Pose
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if time >= a.t and time <= b.t then
			local span = b.t - a.t
			return lerpPose(a.Pose, b.Pose, if span > 0 then (time - a.t) / span else 0)
		end
	end
	return keys[#keys].Pose
end

local poseName = flags.pose
local pose = nil
if type(poseName) == "string" then
	if string.sub(poseName, 1, 1) == "{" then
		pose = serde.decode("json", poseName)
	else
		local family = model:GetAttribute("RigFamily") or "Human"
		pose = RigBuilder.GetPose(family, poseName)
		if pose == nil then
			local clipName, at = string.match(poseName, "^([^@]+)@?([%d%.]*)$")
			local clipFile = "src/shared/Anim/Clips/" .. family
			if fs.isFile(clipFile .. ".luau") or fs.isDir(clipFile) then
				local clips = Loader.requirePath(clipFile)
				local clip = clips[clipName] or (clips.Clips and clips.Clips[clipName])
				if clip then
					pose = samplePose(clip, tonumber(at))
				end
			end
		end
		if pose == nil then
			fail(("unknown pose '%s' for family %s (see `dump_model.luau list`)"):format(poseName, family))
		end
	end
end

local list = RigBuilder.ComputeWorldCFrameList(model, pose, { Strict = kind == "rig" })

-- Serialise -------------------------------------------------------------------------------------
local function r(x)
	return math.round(x * 100000) / 100000
end
local function v3(v)
	return { r(v.X), r(v.Y), r(v.Z) }
end
local function col(c)
	return { r(c.R), r(c.G), r(c.B) }
end

local function cfOf(part)
	for _, e in list do
		if e.Part == part then
			return e.CFrame
		end
	end
	return part.CFrame
end

local SHAPES = { WedgePart = "Wedge", CornerWedgePart = "CornerWedge" }
local FACE_DIRS = {
	Front = Vector3.new(0, 0, -1),
	Back = Vector3.new(0, 0, 1),
	Top = Vector3.new(0, 1, 0),
	Bottom = Vector3.new(0, -1, 0),
	Right = Vector3.new(1, 0, 0),
	Left = Vector3.new(-1, 0, 0),
}

local parts, partIndex = {}, {}
local bmin = Vector3.new(math.huge, math.huge, math.huge)
local bmax = Vector3.new(-math.huge, -math.huge, -math.huge)
local stats = { partCount = 0, visibleParts = 0, motors = 0, lights = 0, highlights = 0 }

-- --physics: show the invisible physics parts (translucent, coloured per limb) and joint pivots.
local PHYSICS_COLORS = {
	HumanoidRootPart = { 0.9, 0.9, 0.9 },
	LowerTorso = { 0.95, 0.75, 0.2 },
	UpperTorso = { 0.95, 0.55, 0.15 },
	Head = { 0.95, 0.85, 0.3 },
	LeftUpperArm = { 0.3, 0.55, 0.95 },
	LeftLowerArm = { 0.35, 0.65, 1 },
	LeftHand = { 0.45, 0.75, 1 },
	RightUpperArm = { 0.9, 0.3, 0.35 },
	RightLowerArm = { 1, 0.4, 0.45 },
	RightHand = { 1, 0.5, 0.55 },
	LeftUpperLeg = { 0.25, 0.7, 0.45 },
	LeftLowerLeg = { 0.3, 0.8, 0.5 },
	LeftFoot = { 0.4, 0.9, 0.6 },
	RightUpperLeg = { 0.7, 0.35, 0.85 },
	RightLowerLeg = { 0.78, 0.45, 0.9 },
	RightFoot = { 0.85, 0.55, 0.95 },
}
local physicsParts = {}
local function isPhysics(part)
	return part.Parent == model and PHYSICS_COLORS[part.Name] ~= nil
end

for i, e in list do
	local part, cf = e.Part, e.CFrame
	stats.partCount += 1
	if flags.physics and isPhysics(part) and part.Name ~= "HumanoidRootPart" then
		table.insert(physicsParts, { part = part, cf = cf })
	end
	if part.Transparency < 1 then
		local shape = SHAPES[part.ClassName]
		if shape == nil then
			local ok, s = pcall(function()
				return part.Shape.Name
			end)
			shape = if ok then s else "Block"
		end
		local mesh = nil
		local meshScale = Vector3.new(1, 1, 1)
		local meshOffset = Vector3.new(0, 0, 0)
		for _, child in part:GetChildren() do
			if child:IsA("SpecialMesh") then
				mesh = { type = child.MeshType.Name, scale = v3(child.Scale), offset = v3(child.Offset) }
				meshScale, meshOffset = child.Scale, child.Offset
				break
			elseif child:IsA("BlockMesh") or child:IsA("CylinderMesh") then
				mesh = {
					type = if child:IsA("BlockMesh") then "Brick" else "CylinderY",
					scale = v3(child.Scale),
					offset = v3(child.Offset),
				}
				meshScale, meshOffset = child.Scale, child.Offset
				break
			end
		end
		local size = part.Size
		local role = part:GetAttribute("Role")
		table.insert(parts, {
			name = part.Name,
			path = part:GetFullName(),
			role = role,
			shape = shape,
			mesh = mesh,
			size = v3(size),
			cf = (function()
				local c = { cf:GetComponents() }
				for k, x in c do
					c[k] = r(x)
				end
				return c
			end)(),
			color = col(part.Color),
			material = part.Material.Name,
			transparency = r(part.Transparency),
			reflectance = r(part.Reflectance),
			castShadow = part.CastShadow,
		})
		partIndex[i] = #parts - 1
		stats.visibleParts += 1
		-- bounds from the (mesh-scaled) box corners
		local half = (size * meshScale) / 2
		local centre = cf * meshOffset
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = centre + cf:VectorToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					bmin = bmin:Min(p)
					bmax = bmax:Max(p)
				end
			end
		end
	end
end

if flags.physics then
	for _, entry in physicsParts do
		local part, cf = entry.part, entry.cf
		local c = { cf:GetComponents() }
		for k, x in c do
			c[k] = r(x)
		end
		table.insert(parts, {
			name = part.Name,
			path = part:GetFullName(),
			role = "Physics",
			shape = "Block",
			size = v3(part.Size),
			cf = c,
			color = PHYSICS_COLORS[part.Name],
			material = "SmoothPlastic",
			transparency = 0.35,
			reflectance = 0,
			castShadow = true,
		})
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					bmin = bmin:Min(p)
					bmax = bmax:Max(p)
				end
			end
		end
	end
	-- joint pivots (Part0 * C0 after FK) as small white neon balls
	for _, inst in model:GetDescendants() do
		if inst:IsA("Motor6D") and inst.Part0 then
			local pivot = cfOf(inst.Part0) * inst.C0
			table.insert(parts, {
				name = inst.Name .. "Pivot",
				path = model.Name .. "." .. inst.Name .. "Pivot",
				role = "Physics",
				shape = "Ball",
				size = { 0.16, 0.16, 0.16 },
				cf = (function()
					local c = { CFrame.new(pivot.Position):GetComponents() }
					for k, x in c do
						c[k] = r(x)
					end
					return c
				end)(),
				color = { 1, 1, 1 },
				material = "Neon",
				transparency = 0,
				reflectance = 0,
				castShadow = false,
			})
		end
	end
	stats.visibleParts = #parts
end

local lights, highlights, anchors = {}, {}, {}
for _, inst in model:GetDescendants() do
	if inst:IsA("Motor6D") then
		stats.motors += 1
	elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
		local host = inst.Parent
		if host and host:IsA("BasePart") and inst.Enabled then
			local cf = cfOf(host)
			local kindName = string.gsub(inst.ClassName, "Light$", "")
			local dir, pos = Vector3.new(0, -1, 0), cf.Position
			local angle = 180
			if not inst:IsA("PointLight") then
				local localDir = FACE_DIRS[inst.Face.Name]
				dir = cf:VectorToWorldSpace(localDir)
				angle = inst.Angle
				if inst:IsA("SurfaceLight") then
					local half = host.Size / 2
					pos = cf * Vector3.new(localDir.X * half.X, localDir.Y * half.Y, localDir.Z * half.Z)
				end
			end
			table.insert(lights, {
				type = kindName,
				pos = v3(pos),
				dir = v3(dir),
				color = col(inst.Color),
				brightness = r(inst.Brightness),
				range = r(inst.Range),
				angle = r(angle),
				shadows = inst.Shadows,
			})
			stats.lights += 1
		end
	elseif inst:IsA("Highlight") then
		local ok, enabled = pcall(function()
			return inst.Enabled
		end)
		if not ok or enabled then
			local target = inst.Adornee or inst.Parent
			local idx = {}
			for i, e in list do
				if partIndex[i] ~= nil and (e.Part == target or e.Part:IsDescendantOf(target)) then
					table.insert(idx, partIndex[i])
				end
			end
			table.insert(highlights, {
				fill = col(inst.FillColor),
				outline = col(inst.OutlineColor),
				fillT = r(inst.FillTransparency),
				outlineT = r(inst.OutlineTransparency),
				depthMode = inst.DepthMode.Name,
				parts = idx,
			})
			stats.highlights += 1
		end
	elseif inst:IsA("Attachment") then
		local host = inst.Parent
		if host and host:IsA("BasePart") then
			anchors[inst.Name] = { pos = v3((cfOf(host) * inst.CFrame).Position) }
		end
	end
end
for _, name in { "Head", "UpperTorso", "HumanoidRootPart" } do
	local p = model:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		anchors[name] = { pos = v3(cfOf(p).Position), size = v3(p.Size) }
	end
end

if stats.visibleParts == 0 then
	bmin, bmax = Vector3.new(-1, 0, -1), Vector3.new(1, 2, 1)
end

local out = {
	kind = kind,
	id = id,
	name = model.Name,
	pose = if type(poseName) == "string" then poseName else nil,
	skin = flags.skin,
	parts = parts,
	lights = lights,
	highlights = highlights,
	anchors = anchors,
	bounds = { min = v3(bmin), max = v3(bmax) },
	stats = stats,
}

local json = serde.encode("json", out, false)
if type(flags.out) == "string" then
	local dir = string.match(flags.out, "^(.*)/[^/]+$")
	if dir and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	fs.writeFile(flags.out, json)
	print(
		("dump_model: %s %s -> %s (%d visible parts, %d lights, %d highlights)"):format(
			kind,
			tostring(id),
			flags.out,
			stats.visibleParts,
			stats.lights,
			stats.highlights
		)
	)
else
	print(json)
end

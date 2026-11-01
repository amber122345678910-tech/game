--!strict
-- RigBuilder: builds a character Model from a blueprint (SPEC §5.1/§5.2) + pose maths. [Lune-safe]
--
-- BUILD
--   RigBuilder.Build(blueprintId, opts?) -> Model
--     opts = { Skin: string?, Name: string?, Style: string?, Palette: {[string]: Color3}?, Scale: number? }
--     * physics parts (R15 names, Transparency 1, CastShadow false, Massless false, CanQuery/CanTouch true,
--       CanCollide only on LowerTorso/UpperTorso/Head), Motor6Ds (parented to Part1, identity-rotation
--       C0/C1), Humanoid (R15, HipHeight so the feet touch y = 0, no Animator), standard attachments
--       (RootAttachment, LeftEye, RightEye, Mouth, HeadTop, Chest, Back, LeftGrip, RightGrip,
--       LeftFootAttachment, RightFootAttachment), PrimaryPart = HumanoidRootPart.
--     * the blueprint's Build(rig) adds visual parts through the RigContext (see Blueprints/init.luau);
--       afterwards every unwelded visual part is welded to its limb and the visual flags are enforced.
--     * final scale = blueprint.Scale * opts.Scale; the model is authored at scale 1 and rescaled at the
--       end (sizes, positions, joints, attachments, light ranges, HipHeight).
--     * palette = blueprint.Palette <- skin palette (Rigs/Skins.Get if present, else Kits skin data)
--       <- opts.Palette.
--     * attributes: RigFamily, BlueprintId, RigScale, SkinId (+ RigStyle when opts.Style is given).
--     * result: rest pose, HumanoidRootPart at CFrame.new(0, HipHeight + 1*scale, 0) facing -Z, Parent nil;
--       the lowest point is y = 0 (feet, or the blueprint's own base when it sets GroundOffset).
--   RigBuilder.BuildFromBlueprint(blueprint, opts?) -> Model   same, from a blueprint table (WIP
--                                               blueprints, tests, previews of bare skeletons)
--   RigBuilder.Blueprints() -> {string}         available blueprint ids
--   RigBuilder.GetJointNames() -> {string}      the 15 Motor6D names (SPEC order)
--   RigBuilder.GetLimbNames() -> {string}       the 16 physics part names
--   RigBuilder.GetPose(family, name) -> Pose?   reference poses from Skeletons ("APose", "Pockets", ...)
--
-- POSES (format shared with Anim clips): { [jointName] = { rxDeg, ryDeg, rzDeg, px?, py?, pz? } }
--   Transform = CFrame.new(px, py, pz) * RigScale * CFrame.Angles(rx, ry, rz)   (Angles = Rx*Ry*Rz)
--   +rx swings a hanging limb forward, +ry turns left, +rz raises the right arm (left arm: -rz).
--   Translations are authored at scale 1 and multiplied by the model's RigScale attribute.
--   RigBuilder.PoseToCFrame(value, scale?) -> CFrame
--   RigBuilder.Pose(model, pose, reset?)        writes Motor6D.Transform (reset defaults to true:
--                                               joints missing from the pose return to identity)
--   RigBuilder.ComputeWorldCFrames(model, pose?, opts?) -> {[BasePart]: CFrame}
--       pure-maths forward kinematics (no physics needed): part1 = part0 * C0 * Transform * C1:Inverse();
--       welded parts keep their current relative offset. pose = nil -> uses each Motor6D.Transform.
--       opts = { Strict: boolean? (default true when the model has a Humanoid: every part must be
--                reachable from the root), RootCFrame: CFrame? (default: root part's current CFrame) }
--       Errors on unresolved chains or non-finite results.
--   RigBuilder.ComputeWorldCFrameList(model, pose?, opts?) -> { {Part: BasePart, CFrame: CFrame} }
--       same, as an ordered list (descendant order). Prefer it under Lune: Lune hands out a NEW
--       userdata for every Instance access, so Instance-keyed tables only work by iteration there.
--   RigBuilder.ApplyPose(model, pose?) -> {[BasePart]: CFrame}
--       FK + writes every part's CFrame. For ViewportFrames / offline previews ONLY (never on a
--       simulated character in workspace: the physics solver owns those CFrames).
--   RigBuilder.GetMotors(model) -> {[string]: Motor6D}

local PartKit = require(script.Parent.PartKit)
local Skeletons = require(script.Parent.Skeletons)
local Blueprints = require(script.Parent.Blueprints)

export type RigContext = Blueprints.RigContext
export type Blueprint = Blueprints.Blueprint
export type Pose = Skeletons.Pose
export type PoseValue = Skeletons.PoseValue

export type BuildOptions = {
	Skin: string?,
	Name: string?,
	Style: string?,
	Palette: { [string]: Color3 }?,
	Scale: number?,
}

export type FKOptions = {
	Strict: boolean?,
	RootCFrame: CFrame?,
}

type LimbRef = string | BasePart

local RigBuilder = {}

RigBuilder.MAX_PARTS = 220
RigBuilder.ROLES = PartKit.ROLES

local COLLIDING_LIMBS: { [string]: boolean } = { LowerTorso = true, UpperTorso = true, Head = true }
local PHYSICS_COLOR = Color3.fromRGB(163, 162, 165)
local IDENTITY = CFrame.new()

function RigBuilder.GetJointNames(): { string }
	return table.clone(Skeletons.JOINTS)
end

function RigBuilder.GetLimbNames(): { string }
	return table.clone(Skeletons.LIMBS)
end

function RigBuilder.Blueprints(): { string }
	return Blueprints.List()
end

function RigBuilder.GetBlueprint(id: string): Blueprint?
	return Blueprints.Get(id)
end

function RigBuilder.GetPose(family: string, name: string): Pose?
	return Skeletons.Pose(family, name)
end

-- Palette ---------------------------------------------------------------------------------------

local function isPaletteTable(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	for _, v in t do
		if typeof(v) ~= "Color3" then
			return false
		end
	end
	return true
end

-- Looks up a skin palette: Rigs/Skins.luau (if present) first, then the kit's skin data.
local function skinPalette(blueprintId: string, skinId: string?): { [string]: Color3 }?
	if skinId == nil or skinId == "" or skinId == "Default" then
		return nil
	end
	local rigsFolder: any = script.Parent
	local skinsModule = rigsFolder:FindFirstChild("Skins")
	if skinsModule then
		local ok, Skins = pcall(require, skinsModule)
		if ok and type(Skins) == "table" and type((Skins :: any).Get) == "function" then
			local ok2, skin = pcall((Skins :: any).Get, blueprintId, skinId)
			if ok2 and type(skin) == "table" then
				local pal = (skin :: any).Palette or (skin :: any).palette
				if isPaletteTable(pal) then
					return pal
				elseif isPaletteTable(skin) then
					return skin :: any
				end
			end
		end
	end
	local kitsModule = rigsFolder.Parent:FindFirstChild("Kits")
	if kitsModule then
		local ok, Kits = pcall(require, kitsModule)
		if ok and type(Kits) == "table" and type((Kits :: any).Skin) == "function" then
			local skin = (Kits :: any).Skin(blueprintId, skinId)
			if skin and isPaletteTable(skin.Palette) then
				return skin.Palette
			end
		end
	end
	return nil
end

local function mergePalette(bp: Blueprint, opts: BuildOptions): { [string]: Color3 }
	local out: { [string]: Color3 } = table.clone(bp.Palette)
	local skin = skinPalette(bp.Id, opts.Skin)
	if skin then
		for k, v in skin do
			out[k] = v
		end
	end
	if opts.Palette then
		for k, v in opts.Palette do
			out[k] = v
		end
	end
	return out
end

-- Build -----------------------------------------------------------------------------------------

local function makePhysicsPart(name: string, size: Vector3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = PHYSICS_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1
	part.Anchored = false
	part.Massless = false
	part.CanCollide = COLLIDING_LIMBS[name] == true
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = false -- fully transparent parts would still cast shadows
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Lune note: Instance userdata are not identity-stable there (a == b works, t[a] does not), so the
-- builder never keys tables by Instance; it uses names, parents and == comparisons instead.
local LIMB_SET: { [string]: boolean } = {}
for _, limbName in Skeletons.LIMBS do
	LIMB_SET[limbName] = true
end

local function isPhysicsPart(model: Model, inst: Instance): boolean
	return inst.Parent == model and LIMB_SET[inst.Name] == true and inst:IsA("BasePart")
end

-- Every part referenced by a weld/joint inside the model.
local function jointEndpoints(model: Model): { BasePart }
	local out: { BasePart } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("WeldConstraint") or inst:IsA("JointInstance") then
			local j = inst :: any
			if j.Part0 then
				table.insert(out, j.Part0)
			end
			if j.Part1 then
				table.insert(out, j.Part1)
			end
		end
	end
	return out
end

local function contains(list: { BasePart }, part: BasePart): boolean
	for _, p in list do
		if p == part then
			return true
		end
	end
	return false
end

local function countParts(model: Model): number
	local n = 0
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function RigBuilder.Build(blueprintId: string, options: BuildOptions?): Model
	local bp = Blueprints.Get(blueprintId)
	if bp == nil then
		error(
			("RigBuilder.Build: unknown blueprint '%s' (available: %s)"):format(
				blueprintId,
				table.concat(Blueprints.List(), ", ")
			),
			2
		)
	end
	return RigBuilder.BuildFromBlueprint(bp :: Blueprint, options)
end

function RigBuilder.BuildFromBlueprint(blueprint: Blueprint, options: BuildOptions?): Model
	Blueprints.Validate(blueprint.Id, blueprint)
	local opts: BuildOptions = options or {}
	local skeletonId = blueprint.Skeleton or blueprint.Family
	local sk = Skeletons.Resolve(skeletonId, blueprint.Overrides, blueprint.GroundOffset)
	local scale = (blueprint.Scale or 1) * (opts.Scale or 1)
	assert(scale > 0, "RigBuilder.Build: scale must be positive")
	local skinId = opts.Skin or "Default"
	local palette = mergePalette(blueprint, opts)

	local model = Instance.new("Model")
	model.Name = opts.Name or blueprint.Id

	-- Physics parts ----------------------------------------------------------------------------
	local limbs: { [string]: BasePart } = {}
	for _, limbName in sk.Order do
		local L = sk.Limbs[limbName]
		local part = makePhysicsPart(limbName, L.Size, L.CFrame)
		part.Parent = model
		limbs[limbName] = part
	end

	-- Motor6Ds ----------------------------------------------------------------------------------
	for _, jointName in Skeletons.JOINTS do
		local J = sk.Joints[jointName]
		local p0, p1 = limbs[J.Part0], limbs[J.Part1]
		local motor = Instance.new("Motor6D")
		motor.Name = jointName
		motor.Part0 = p0
		motor.Part1 = p1
		motor.C0 = CFrame.new(p0.CFrame:PointToObjectSpace(J.Pivot))
		motor.C1 = CFrame.new(p1.CFrame:PointToObjectSpace(J.Pivot))
		motor.Transform = IDENTITY
		motor.Parent = p1
	end

	-- Standard attachments ----------------------------------------------------------------------
	local anchors: { [string]: { Limb: string, CFrame: CFrame } } = table.clone(sk.Anchors)
	if blueprint.Anchors then
		for name, a in blueprint.Anchors do
			anchors[name] = a
		end
	end
	for name, a in anchors do
		local limb = limbs[a.Limb]
		assert(limb ~= nil, ("anchor %s on unknown limb %s"):format(name, a.Limb))
		local att = Instance.new("Attachment")
		att.Name = name
		att.CFrame = a.CFrame
		att.Parent = limb
	end

	-- Humanoid ----------------------------------------------------------------------------------
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = true
	humanoid.HipHeight = sk.HipHeight
	humanoid.Parent = model

	-- RigContext --------------------------------------------------------------------------------
	local visualCount = 0
	local currentTarget: BasePart? = nil

	local function weldTo(limb: BasePart, part: BasePart)
		if part:FindFirstChild("Weld") ~= nil then
			return -- already welded by us
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Weld"
		weld.Part0 = limb
		weld.Part1 = part
		weld.Parent = part
	end

	local kit = PartKit.new({
		Sink = function(part: BasePart)
			visualCount += 1
			local target = currentTarget
			if target then
				weldTo(target, part)
			end
		end,
	})

	-- A limb reference is a limb name or any BasePart of this rig (resolved to the limb it follows).
	local function resolveLimb(ref: LimbRef, level: number?): BasePart
		if type(ref) == "string" then
			local part = limbs[ref]
			if part == nil then
				error(("RigContext: unknown limb '%s'"):format(ref), (level or 2) + 1)
			end
			return part
		end
		local part = ref :: BasePart
		local node: Instance? = part
		while node ~= nil and node ~= model do
			if isPhysicsPart(model, node) then
				return node :: BasePart
			end
			node = node.Parent
		end
		error(("RigContext: part '%s' does not belong to a limb of this rig"):format(part.Name), (level or 2) + 1)
	end

	local rig: any = {
		Model = model,
		Id = blueprint.Id,
		Family = blueprint.Family,
		SkinId = skinId,
		Style = opts.Style,
		Scale = scale,
		Palette = palette,
		Skeleton = sk,
		Kit = kit,
		OnEllipsoid = PartKit.OnEllipsoid,
		Basis = PartKit.Basis,
		LookFrame = PartKit.LookFrame,
	}

	function rig.Limb(name: string): BasePart
		return resolveLimb(name, 2)
	end

	function rig.CFrameOf(name: string): CFrame
		return resolveLimb(name, 2).CFrame
	end

	function rig.Size(name: string): Vector3
		return resolveLimb(name, 2).Size
	end

	function rig.Joint(motorName: string): Vector3
		local J = sk.Joints[motorName]
		if J == nil then
			error(("RigContext: unknown joint '%s'"):format(motorName), 2)
		end
		return J.Pivot
	end

	function rig.Color(key: string, fallback: Color3?): Color3
		local c = palette[key]
		if c ~= nil then
			return c
		end
		if fallback ~= nil then
			return fallback
		end
		error(("RigContext: palette key '%s' missing in blueprint %s"):format(key, blueprint.Id), 2)
	end

	function rig.Add(limb: LimbRef, part: BasePart): BasePart
		local target = resolveLimb(limb, 2)
		if not part:IsDescendantOf(target) then
			part.Parent = target
		end
		weldTo(target, part)
		visualCount += 1
		return part
	end

	function rig.Attachment(limb: LimbRef, name: string, worldCF: CFrame): Attachment
		local target = resolveLimb(limb, 2)
		return kit.Attach(target, name, target.CFrame:ToObjectSpace(worldCF))
	end

	function rig.Light(limb: LimbRef, kind: string, props: PartKit.Props?): Light
		return kit.Light(resolveLimb(limb, 2), kind, props)
	end

	function rig.Count(): number
		return visualCount
	end

	for _, fnName in
		{
			"Box",
			"Ellipsoid",
			"Ball",
			"Cyl",
			"Disc",
			"CylBetween",
			"Wedge",
			"CornerWedge",
			"RoundedBox",
			"Cone",
			"Taper",
			"Bone",
			"Ring",
			"Arc",
			"Tube",
			"Dashes",
		}
	do
		local builder = (kit :: any)[fnName]
		rig[fnName] = function(limb: LimbRef, ...: any): any
			local target = resolveLimb(limb, 2)
			local previous = currentTarget
			currentTarget = target
			local result = builder(target, ...)
			currentTarget = previous
			return result
		end
	end

	blueprint.Build(rig :: RigContext)

	-- Post pass: weld leftovers, enforce visual flags ------------------------------------------
	local endpoints = jointEndpoints(model)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and not isPhysicsPart(model, inst) then
			local part = inst :: BasePart
			if anchors[part.Name] ~= nil or LIMB_SET[part.Name] or part.Name == "Humanoid" then
				error(
					("RigBuilder: blueprint %s names a visual part '%s', which is reserved (limb/attachment name)"):format(
						blueprint.Id,
						part:GetFullName()
					),
					2
				)
			end
			if not contains(endpoints, part) then
				weldTo(resolveLimb(part, 1), part)
			end
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local role = part:GetAttribute("Role")
			if type(role) ~= "string" or table.find(PartKit.ROLES, role) == nil then
				if role ~= nil then
					warn(
						("RigBuilder: %s.%s has invalid Role %s -> Detail"):format(
							blueprint.Id,
							part.Name,
							tostring(role)
						)
					)
				end
				part:SetAttribute("Role", "Detail")
			end
		end
	end

	local total = countParts(model)
	if total > RigBuilder.MAX_PARTS then
		warn(("RigBuilder: %s uses %d parts (budget %d)"):format(blueprint.Id, total, RigBuilder.MAX_PARTS))
	end

	-- Final scale + metadata --------------------------------------------------------------------
	PartKit.ScaleModel(model, scale, Vector3.new(0, 0, 0))
	model.PrimaryPart = limbs.HumanoidRootPart
	model:SetAttribute("RigFamily", blueprint.Family)
	model:SetAttribute("BlueprintId", blueprint.Id)
	model:SetAttribute("RigScale", scale)
	model:SetAttribute("SkinId", skinId)
	if opts.Style then
		model:SetAttribute("RigStyle", opts.Style)
	end

	-- Every chain must resolve (throws with the offending part names otherwise).
	RigBuilder.ComputeWorldCFrameList(model, nil, { Strict = true })
	return model
end

-- Poses & forward kinematics ---------------------------------------------------------------------

function RigBuilder.PoseToCFrame(value: PoseValue, scale: number?): CFrame
	local s = scale or 1
	local rx, ry, rz = math.rad(value[1] or 0), math.rad(value[2] or 0), math.rad(value[3] or 0)
	local px, py, pz = (value[4] or 0) * s, (value[5] or 0) * s, (value[6] or 0) * s
	return CFrame.new(px, py, pz) * CFrame.Angles(rx, ry, rz)
end

function RigBuilder.GetMotors(model: Model): { [string]: Motor6D }
	local out: { [string]: Motor6D } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("Motor6D") then
			out[inst.Name] = inst
		end
	end
	return out
end

local function rigScale(model: Model): number
	local s = model:GetAttribute("RigScale")
	return if type(s) == "number" and s > 0 then s else 1
end

function RigBuilder.Pose(model: Model, pose: Pose, reset: boolean?)
	local scale = rigScale(model)
	local doReset = reset ~= false
	for name, motor in RigBuilder.GetMotors(model) do
		local value = pose[name]
		if value ~= nil then
			motor.Transform = RigBuilder.PoseToCFrame(value, scale)
		elseif doReset then
			motor.Transform = IDENTITY
		end
	end
end

local function readTransform(motor: Motor6D): CFrame
	local ok, t = pcall(function()
		return motor.Transform
	end)
	if ok and typeof(t) == "CFrame" then
		return t
	end
	return IDENTITY
end

local function isFinite(cf: CFrame): boolean
	for _, v in { cf:GetComponents() } do
		if v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	return true
end

type Edge = { To: number, Rel: CFrame }

local function findRoot(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

export type PartCFrame = { Part: BasePart, CFrame: CFrame }

function RigBuilder.ComputeWorldCFrameList(model: Model, pose: Pose?, options: FKOptions?): { PartCFrame }
	local opts: FKOptions = options or {}
	local scale = rigScale(model)

	-- Index parts. `fast` gives O(1) lookups in Roblox; under Lune it misses and we fall back to ==.
	local parts: { BasePart } = {}
	local fast: { [any]: number } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
			fast[inst] = #parts
		end
	end
	local function indexOf(part: BasePart?): number?
		if part == nil then
			return nil
		end
		local i = fast[part]
		if i then
			return i
		end
		for k, p in parts do
			if p == part then
				return k
			end
		end
		return nil
	end

	local edges: { [number]: { Edge } } = {}
	local function addEdge(a: number, b: number, rel: CFrame)
		local list = edges[a]
		if list == nil then
			list = {}
			edges[a] = list
		end
		table.insert(list, { To = b, Rel = rel })
	end

	for _, inst in model:GetDescendants() do
		if inst:IsA("JointInstance") then
			local joint = inst :: any
			local i0, i1 = indexOf(joint.Part0), indexOf(joint.Part1)
			if i0 and i1 then
				local okC, c0, c1 = pcall(function()
					return joint.C0, joint.C1
				end)
				if not okC then
					c0, c1 = IDENTITY, IDENTITY
				end
				local t = IDENTITY
				if inst:IsA("Motor6D") then
					if pose ~= nil then
						local value = pose[inst.Name]
						t = if value ~= nil then RigBuilder.PoseToCFrame(value, scale) else IDENTITY
					else
						t = readTransform(inst)
					end
				end
				local forward = c0 * t * c1:Inverse()
				addEdge(i0, i1, forward)
				addEdge(i1, i0, forward:Inverse())
			end
		elseif inst:IsA("WeldConstraint") then
			local i0, i1 = indexOf(inst.Part0), indexOf(inst.Part1)
			local okE, enabled = pcall(function()
				return inst.Enabled
			end)
			if i0 and i1 and (not okE or enabled ~= false) then
				local rel = parts[i0].CFrame:ToObjectSpace(parts[i1].CFrame)
				addEdge(i0, i1, rel)
				addEdge(i1, i0, rel:Inverse())
			end
		end
	end

	local result: { [number]: CFrame } = {}
	local function flood(start: number, startCF: CFrame)
		result[start] = startCF
		local queue = { start }
		local head = 1
		while head <= #queue do
			local current = queue[head]
			head += 1
			local list = edges[current]
			if list then
				for _, edge in list do
					if result[edge.To] == nil then
						result[edge.To] = result[current] * edge.Rel
						table.insert(queue, edge.To)
					end
				end
			end
		end
	end

	local root = findRoot(model)
	local strict = if opts.Strict ~= nil then opts.Strict else model:FindFirstChildOfClass("Humanoid") ~= nil
	local rootIndex = indexOf(root)
	if rootIndex then
		flood(rootIndex, opts.RootCFrame or parts[rootIndex].CFrame)
	elseif strict then
		error(("ComputeWorldCFrames: %s has no PrimaryPart/HumanoidRootPart"):format(model.Name), 2)
	end

	local missing: { string } = {}
	for i, part in parts do
		if result[i] == nil then
			if strict then
				table.insert(missing, part:GetFullName())
			else
				-- Unjointed geometry (props, maps): keep it where it is, carry its welded parts along.
				flood(i, part.CFrame)
			end
		end
	end
	if #missing > 0 then
		error(
			("ComputeWorldCFrames: %d part(s) not connected to the root: %s"):format(
				#missing,
				table.concat(missing, ", ", 1, math.min(#missing, 8))
			),
			2
		)
	end
	local out: { PartCFrame } = {}
	for i, part in parts do
		local cf = result[i]
		if not isFinite(cf) then
			error(("ComputeWorldCFrames: non-finite CFrame for %s"):format(part:GetFullName()), 2)
		end
		out[i] = { Part = part, CFrame = cf }
	end
	return out
end

function RigBuilder.ComputeWorldCFrames(model: Model, pose: Pose?, options: FKOptions?): { [BasePart]: CFrame }
	local map: { [BasePart]: CFrame } = {}
	for _, entry in RigBuilder.ComputeWorldCFrameList(model, pose, options) do
		map[entry.Part] = entry.CFrame
	end
	return map
end

function RigBuilder.ApplyPose(model: Model, pose: Pose?): { [BasePart]: CFrame }
	local list = RigBuilder.ComputeWorldCFrameList(model, pose)
	local map: { [BasePart]: CFrame } = {}
	for _, entry in list do
		entry.Part.CFrame = entry.CFrame
		map[entry.Part] = entry.CFrame
	end
	return map
end

return RigBuilder

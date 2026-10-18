--!nocheck
-- Class-specific behaviour of emulated instances: Instance methods, parts and joints (rigid assemblies),
-- models and pivots, attachments, GUI geometry (AbsoluteSize/TextBounds approximations), values, sounds,
-- particles, animation, tools, scripts.
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Sched = require("./sched")
local Report = require("./report")
local DT = require("./datatypes")

local Vector3, Vector2, CFrame, UDim2, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.UDim2, roblox.Enum
local DATA = Engine.DATA
local define = Engine.define
local setProp = Engine.setProp
local readProp = Engine.readProp
local throw = Engine.throw
local typeof = Engine.typeof

local Classes = {}

local function self(u, name)
	return Engine.self(u, name)
end

local function R()
	return Sched.CUR
end

local function checkString(v, argn, fn)
	if type(v) ~= "string" then
		throw("runtime", string.format("invalid argument #%d to '%s' (string expected, got %s)", argn, fn, typeof(v)))
	end
end

----------------------------------------------------------------------
-- Instance
----------------------------------------------------------------------
local function className(cd)
	return cd.class
end

define("Instance", {
	getters = {
		Parent = function(d)
			return d.parent
		end,
		ClassName = function(d)
			return d.class
		end,
		Archivable = function(d)
			return true
		end,
	},
	setters = {
		Parent = function(d, v, realm)
			Engine.setParent(d, v, realm)
		end,
		ClassName = "readonly",
		Name = function(d, v, realm)
			local old = d.props.Name
			setProp(d, "Name", v, realm)
			if old ~= v and d.parent then
				Engine.resolveWaiters(DATA[d.parent], d)
			end
		end,
	},
	methods = {
		FindFirstChild = function(u, name, recursive)
			local d = self(u, "FindFirstChild")
			if type(name) ~= "string" then
				if type(name) == "number" then
					name = tostring(name)
				else
					throw("runtime", "Argument 1 missing or nil (FindFirstChild expects a string, got " .. typeof(name) .. ")")
				end
			end
			local realm = R()
			if recursive then
				for _, c in Engine.descendantsOf(d, realm) do
					if DATA[c].props.Name == name then
						return c
					end
				end
				return nil
			end
			return Engine.findChild(d, name, realm)
		end,
		FindFirstChildOfClass = function(u, cls)
			local d = self(u, "FindFirstChildOfClass")
			checkString(cls, 1, "FindFirstChildOfClass")
			for _, c in Engine.childrenOf(d, R()) do
				if DATA[c].class == cls then
					return c
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(u, cls, recursive)
			local d = self(u, "FindFirstChildWhichIsA")
			checkString(cls, 1, "FindFirstChildWhichIsA")
			local list = if recursive then Engine.descendantsOf(d, R()) else Engine.childrenOf(d, R())
			for _, c in list do
				if DATA[c].cls.isA[cls] then
					return c
				end
			end
			return nil
		end,
		FindFirstDescendant = function(u, name)
			local d = self(u, "FindFirstDescendant")
			for _, c in Engine.descendantsOf(d, R()) do
				if DATA[c].props.Name == name then
					return c
				end
			end
			return nil
		end,
		FindFirstAncestor = function(u, name)
			local d = self(u, "FindFirstAncestor")
			local cur = d.parent and DATA[d.parent]
			while cur do
				if cur.props.Name == name then
					return cur.proxy
				end
				cur = cur.parent and DATA[cur.parent]
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(u, cls)
			local d = self(u, "FindFirstAncestorOfClass")
			local cur = d.parent and DATA[d.parent]
			while cur do
				if cur.class == cls then
					return cur.proxy
				end
				cur = cur.parent and DATA[cur.parent]
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(u, cls)
			local d = self(u, "FindFirstAncestorWhichIsA")
			local cur = d.parent and DATA[d.parent]
			while cur do
				if cur.cls.isA[cls] then
					return cur.proxy
				end
				cur = cur.parent and DATA[cur.parent]
			end
			return nil
		end,
		GetChildren = function(u)
			return Engine.childrenOf(self(u, "GetChildren"), R())
		end,
		GetDescendants = function(u)
			return Engine.descendantsOf(self(u, "GetDescendants"), R())
		end,
		IsA = function(u, cls)
			local d = self(u, "IsA")
			checkString(cls, 1, "IsA")
			return d.cls.isA[cls] == true
		end,
		IsDescendantOf = function(u, other)
			local d = self(u, "IsDescendantOf")
			if other == nil then
				return false
			end
			local od = Engine.argInstance(other, 1, "IsDescendantOf")
			return Engine.isDescendantOf(d, od)
		end,
		IsAncestorOf = function(u, other)
			local d = self(u, "IsAncestorOf")
			if other == nil then
				return false
			end
			local od = Engine.argInstance(other, 1, "IsAncestorOf")
			return Engine.isDescendantOf(od, d)
		end,
		GetFullName = function(u)
			return Engine.fullName(self(u, "GetFullName"))
		end,
		Destroy = function(u)
			Engine.destroy(self(u, "Destroy"), R())
		end,
		Remove = function(u)
			Engine.setParent(self(u, "Remove"), nil, R())
		end,
		ClearAllChildren = function(u)
			local d = self(u, "ClearAllChildren")
			for _, c in Engine.childrenOf(d, R()) do
				local cd = DATA[c]
				if cd.props.Archivable ~= nil or true then
					Engine.destroy(cd, R())
				end
			end
		end,
		Clone = function(u)
			return Engine.clone(self(u, "Clone"), R())
		end,
		WaitForChild = function(u, name, timeout)
			local d = self(u, "WaitForChild")
			if type(name) ~= "string" then
				throw("runtime", "Argument 1 missing or nil (WaitForChild expects a string)")
			end
			local realm = R()
			local c = Engine.findChild(d, name, realm)
			if c then
				return c
			end
			if timeout ~= nil and type(timeout) ~= "number" then
				throw("runtime", "invalid argument #2 to 'WaitForChild' (number expected, got " .. typeof(timeout) .. ")")
			end
			local co = coroutine.running()
			if not coroutine.isyieldable() then
				throw("runtime", "WaitForChild called from a non-yieldable context")
			end
			local w = { name = name, co = co, realm = realm, token = Sched.waitToken(co), done = false }
			d.waitList = d.waitList or {}
			table.insert(d.waitList, w)
			local frames = Report.frames(nil, 1)
			local started = Sched.now
			if timeout then
				Sched.wakeAt(Sched.now + timeout, co, w.token, nil)
			else
				Sched.at(Sched.now + 5, function()
					if not w.done and coroutine.status(co) == "suspended" and not (realm and realm.dead) then
						w.warned = true
						Report.add(
							"yield",
							Sched.realmName(realm),
							string.format('Infinite yield possible on \'%s:WaitForChild("%s")\'', Engine.fullName(d), name),
							frames
						)
					end
				end)
			end
			local result = Sched.suspend('WaitForChild("' .. name .. '")')
			w.done = true
			if w.warned and result then
				Report.add("note", Sched.realmName(realm), string.format("WaitForChild(%q) on %s resolved after %.1f s", name, Engine.fullName(d), Sched.now - started))
			end
			return result
		end,
		GetAttribute = function(u, name)
			local d = self(u, "GetAttribute")
			checkString(name, 1, "GetAttribute")
			return Engine.getAttribute(d, name, R())
		end,
		SetAttribute = function(u, name, value)
			Engine.setAttribute(self(u, "SetAttribute"), name, value, R())
		end,
		GetAttributes = function(u)
			return Engine.getAttributes(self(u, "GetAttributes"), R())
		end,
		GetAttributeChangedSignal = function(u, name)
			local d = self(u, "GetAttributeChangedSignal")
			checkString(name, 1, "GetAttributeChangedSignal")
			return Engine.getSignal(d, "attr:" .. name)
		end,
		GetPropertyChangedSignal = function(u, prop)
			local d = self(u, "GetPropertyChangedSignal")
			checkString(prop, 1, "GetPropertyChangedSignal")
			local m = d.cls.members[prop]
			if not m or m.Kind ~= "prop" then
				throw("member", string.format("%s is not a valid property name. (GetPropertyChangedSignal on %s)", prop, d.class))
			end
			return Engine.getSignal(d, "prop:" .. prop)
		end,
		AddTag = function(u, tag)
			local d = self(u, "AddTag")
			checkString(tag, 1, "AddTag")
			Classes.addTag(d, tag)
		end,
		RemoveTag = function(u, tag)
			Classes.removeTag(self(u, "RemoveTag"), tag)
		end,
		HasTag = function(u, tag)
			local d = self(u, "HasTag")
			return d.tags ~= nil and d.tags[tag] == true
		end,
		GetTags = function(u)
			local d = self(u, "GetTags")
			local out = {}
			for t in d.tags or {} do
				table.insert(out, t)
			end
			table.sort(out)
			return out
		end,
		GetActor = function()
			return nil
		end,
		GetDebugId = function(u)
			return tostring(self(u, "GetDebugId").id)
		end,
		IsPropertyModified = function(u, prop)
			local d = self(u, "IsPropertyModified")
			return d.props[prop] ~= nil
		end,
		ResetPropertyToDefault = function(u, prop)
			local d = self(u, "ResetPropertyToDefault")
			setProp(d, prop, d.cls.defaults[prop], R())
		end,
	},
})

-- CollectionService bookkeeping (signals live in services.luau)
Classes.tagSignals = {} -- tag -> { added = Signal, removed = Signal }
function Classes.tagSignal(tag, which)
	local t = Classes.tagSignals[tag]
	if not t then
		t = { added = Engine.newSignal("InstanceAdded:" .. tag), removed = Engine.newSignal("InstanceRemoved:" .. tag) }
		Classes.tagSignals[tag] = t
	end
	return t[which]
end
function Classes.addTag(d, tag)
	d.tags = d.tags or {}
	if d.tags[tag] then
		return
	end
	d.tags[tag] = true
	if Engine.inGame(d) then
		Engine.fire(Classes.tagSignal(tag, "added"), Engine.eventFilter(d), d.proxy)
	end
end
function Classes.removeTag(d, tag)
	if not d.tags or not d.tags[tag] then
		return
	end
	d.tags[tag] = nil
	if Engine.inGame(d) then
		Engine.fire(Classes.tagSignal(tag, "removed"), Engine.eventFilter(d), d.proxy)
	end
end
table.insert(Engine.onParentChanged, function(d, od, nd, wasIn, nowIn)
	if wasIn == nowIn then
		return
	end
	Engine.forSubtree(d, function(x)
		if x.tags then
			for tag in x.tags do
				Engine.fire(Classes.tagSignal(tag, if nowIn then "added" else "removed"), Engine.eventFilter(x), x.proxy)
			end
		end
	end)
end)

----------------------------------------------------------------------
-- Parts, joints and rigid assemblies
----------------------------------------------------------------------
Classes.onPartMoved = nil -- hook(d) for the raycast grid

local function partCF(d)
	return d.props.CFrame or CFrame.identity
end

local propagate -- forward

-- Set CFrame of a part and move everything rigidly connected to it through joints
local function setPartCFrame(d, cf, realm, noPropagate)
	setProp(d, "CFrame", cf, realm)
	local sigs = d.sigs
	if sigs then
		if sigs["prop:Position"] then
			Engine.fire(sigs["prop:Position"], Engine.eventFilter(d))
		end
		if sigs["prop:Orientation"] then
			Engine.fire(sigs["prop:Orientation"], Engine.eventFilter(d))
		end
	end
	if d.inGrid and Classes.onPartMoved then
		Classes.onPartMoved(d)
	end
	if not noPropagate and d.joints and next(d.joints) then
		propagate(d, realm)
	end
end
Classes.setPartCFrame = setPartCFrame

local function readCF(d, realm)
	return readProp(d, "CFrame", realm) or CFrame.identity
end

local function jointOther(jd, pd)
	local p0, p1 = jd.props.Part0, jd.props.Part1
	if p0 and DATA[p0] == pd then
		return p1 and DATA[p1], true
	elseif p1 and DATA[p1] == pd then
		return p0 and DATA[p0], false
	end
	return nil
end

local function jointEnabled(jd)
	local e = jd.props.Enabled
	return e ~= false
end

-- CFrame of the "other" part implied by the joint, given this part's CFrame
local function impliedCF(jd, fromIsPart0, fromCF)
	if jd.class == "WeldConstraint" or jd.class == "RigidConstraint" then
		local off = jd.offset or CFrame.identity
		if fromIsPart0 then
			return fromCF * off
		end
		return fromCF * off:Inverse()
	end
	local c0 = jd.props.C0 or CFrame.identity
	local c1 = jd.props.C1 or CFrame.identity
	if fromIsPart0 then
		return fromCF * c0 * c1:Inverse()
	end
	return fromCF * c1 * c0:Inverse()
end

propagate = function(start, realm)
	local visited = { [start] = true }
	local queue = { start }
	local qi = 1
	while qi <= #queue do
		local pd = queue[qi]
		qi += 1
		if pd.joints then
			local cf = readCF(pd, realm)
			for jd in pd.joints do
				if not jd.destroyed and jointEnabled(jd) then
					local other, fromIs0 = jointOther(jd, pd)
					if other and not visited[other] then
						visited[other] = true
						setPartCFrame(other, impliedCF(jd, fromIs0, cf), realm, true)
						table.insert(queue, other)
					end
				end
			end
		end
	end
end

local function registerJoint(jd)
	-- unregister from previous parts
	if jd.attached then
		for pd in jd.attached do
			if pd.joints then
				pd.joints[jd] = nil
			end
		end
	end
	jd.attached = {}
	for _, key in { "Part0", "Part1" } do
		local p = jd.props[key]
		if p then
			local pd = DATA[p]
			pd.joints = pd.joints or {}
			pd.joints[jd] = true
			jd.attached[pd] = true
		end
	end
end

-- Snap Part1 to satisfy the joint (what the engine does when a weld becomes active)
local function snapJoint(jd, realm)
	local p0, p1 = jd.props.Part0, jd.props.Part1
	if not p0 or not p1 or not jointEnabled(jd) then
		return
	end
	local d0, d1 = DATA[p0], DATA[p1]
	if jd.class == "WeldConstraint" or jd.class == "RigidConstraint" then
		jd.offset = readCF(d0, realm):Inverse() * readCF(d1, realm)
		return
	end
	-- move Part1's side of the assembly (not Part0's)
	local target = impliedCF(jd, true, readCF(d0, realm))
	local visited = { [d0] = true }
	setProp(d1, "CFrame", target, realm)
	-- propagate from d1 but never back into d0
	local queue = { d1 }
	visited[d1] = true
	local qi = 1
	while qi <= #queue do
		local pd = queue[qi]
		qi += 1
		local cf = readCF(pd, realm)
		for j in pd.joints or {} do
			if j ~= jd and not j.destroyed and jointEnabled(j) then
				local other, fromIs0 = jointOther(j, pd)
				if other and not visited[other] then
					visited[other] = true
					setProp(other, "CFrame", impliedCF(j, fromIs0, cf), realm)
					table.insert(queue, other)
				end
			end
		end
	end
end
Classes.snapJoint = snapJoint

local function jointSetter(key)
	return function(d, v, realm)
		setProp(d, key, v, realm)
		registerJoint(d)
		snapJoint(d, realm)
	end
end

local jointBehaviour = {
	setters = {
		Part0 = jointSetter("Part0"),
		Part1 = jointSetter("Part1"),
		C0 = jointSetter("C0"),
		C1 = jointSetter("C1"),
		Enabled = jointSetter("Enabled"),
	},
	init = function(d)
		d.onDestroy = function(x)
			if x.attached then
				for pd in x.attached do
					if pd.joints then
						pd.joints[x] = nil
					end
				end
			end
		end
		d.afterClone = function(x)
			registerJoint(x)
		end
	end,
}
define("JointInstance", jointBehaviour)
define("WeldConstraint", jointBehaviour)
define("RigidConstraint", {
	setters = { Attachment0 = jointSetter("Attachment0"), Attachment1 = jointSetter("Attachment1") },
})

local function orientationOf(cf)
	local x, y, z = cf:ToOrientation()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end
local function fromOrientation(v)
	return CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

define("BasePart", {
	getters = {
		Position = function(d, realm)
			return readCF(d, realm).Position
		end,
		Orientation = function(d, realm)
			return orientationOf(readCF(d, realm))
		end,
		Rotation = function(d, realm)
			local x, y, z = readCF(d, realm):ToEulerAnglesXYZ()
			return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
		end,
		AssemblyRootPart = function(d)
			return d.proxy
		end,
		AssemblyMass = function(d, realm)
			local s = readProp(d, "Size", realm) or Vector3.one
			return s.X * s.Y * s.Z * 0.7
		end,
		Mass = function(d, realm)
			local s = readProp(d, "Size", realm) or Vector3.one
			return s.X * s.Y * s.Z * 0.7
		end,
		ExtentsCFrame = function(d, realm)
			return readCF(d, realm)
		end,
		ExtentsSize = function(d, realm)
			return readProp(d, "Size", realm)
		end,
		ResizeableFaces = function()
			return roblox.Faces.new(Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back)
		end,
		ReceiveAge = function()
			return 0
		end,
		CurrentPhysicalProperties = function()
			return roblox.PhysicalProperties.new(0.7, 0.3, 0.5)
		end,
	},
	setters = {
		CFrame = function(d, v, realm)
			setPartCFrame(d, v, realm)
		end,
		Position = function(d, v, realm)
			local cf = readCF(d, realm)
			setPartCFrame(d, CFrame.new(v) * cf.Rotation, realm)
		end,
		Orientation = function(d, v, realm)
			local cf = readCF(d, realm)
			setPartCFrame(d, CFrame.new(cf.Position) * fromOrientation(v), realm)
		end,
		Rotation = function(d, v, realm)
			local cf = readCF(d, realm)
			setPartCFrame(d, CFrame.new(cf.Position) * CFrame.fromEulerAnglesXYZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)), realm)
		end,
		Size = function(d, v, realm)
			setProp(d, "Size", v, realm)
			if d.inGrid and Classes.onPartMoved then
				Classes.onPartMoved(d)
			end
		end,
		BrickColor = function(d, v, realm)
			setProp(d, "BrickColor", v, realm)
			setProp(d, "Color", v.Color, realm)
		end,
		Color = function(d, v, realm)
			setProp(d, "Color", v, realm)
		end,
	},
	methods = {
		GetPivot = function(u)
			local d = self(u, "GetPivot")
			return readCF(d, R()) * (d.props.PivotOffset or CFrame.identity)
		end,
		PivotTo = function(u, cf)
			local d = self(u, "PivotTo")
			if typeof(cf) ~= "CFrame" then
				throw("runtime", "invalid argument #1 to 'PivotTo' (CFrame expected, got " .. typeof(cf) .. ")")
			end
			setPartCFrame(d, cf * (d.props.PivotOffset or CFrame.identity):Inverse(), R())
		end,
		GetMass = function(u)
			local d = self(u, "GetMass")
			local s = readProp(d, "Size", R()) or Vector3.one
			return s.X * s.Y * s.Z * 0.7
		end,
		GetTouchingParts = function()
			return {}
		end,
		GetConnectedParts = function(u)
			local d = self(u, "GetConnectedParts")
			local out = {}
			for jd in d.joints or {} do
				local o = jointOther(jd, d)
				if o then
					table.insert(out, o.proxy)
				end
			end
			return out
		end,
		GetJoints = function(u)
			local d = self(u, "GetJoints")
			local out = {}
			for jd in d.joints or {} do
				table.insert(out, jd.proxy)
			end
			return out
		end,
		GetRootPart = function(u)
			return u
		end,
		CanCollideWith = function()
			return true
		end,
		ApplyImpulse = function(u, v)
			self(u, "ApplyImpulse")
		end,
		ApplyAngularImpulse = function(u)
			self(u, "ApplyAngularImpulse")
		end,
		SetNetworkOwner = function(u, player)
			local d = self(u, "SetNetworkOwner")
			if Sched.CUR and Sched.CUR.kind ~= "server" then
				throw("runtime", "SetNetworkOwner can only be called from the server")
			end
			if readProp(d, "Anchored", R()) then
				throw("runtime", "Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts")
			end
			d.networkOwner = player
		end,
		SetNetworkOwnershipAuto = function(u)
			self(u, "SetNetworkOwnershipAuto")
		end,
		GetNetworkOwner = function(u)
			return self(u, "GetNetworkOwner").networkOwner
		end,
		GetNetworkOwnershipAuto = function()
			return true
		end,
		BreakJoints = function(u)
			local d = self(u, "BreakJoints")
			for jd in table.clone(d.joints or {}) do
				Engine.destroy(jd, R())
			end
		end,
		GetVelocityAtPosition = function()
			return Vector3.zero
		end,
		GetClosestPointOnSurface = function(u, p)
			return p
		end,
	},
})

-- Bounding box of a set of parts in the orientation of `basis`
local function boundsOf(parts, basis, realm)
	local minV, maxV
	local inv = basis:Inverse()
	for _, pd in parts do
		local cf = readCF(pd, realm)
		local s = (readProp(pd, "Size", realm) or Vector3.one) / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = inv * (cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					if minV then
						minV = Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z))
						maxV = Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z))
					else
						minV, maxV = w, w
					end
				end
			end
		end
	end
	if not minV then
		return basis, Vector3.zero
	end
	return basis * CFrame.new((minV + maxV) / 2), maxV - minV
end

local function modelParts(d, realm)
	local list = {}
	for _, c in Engine.descendantsOf(d, realm) do
		local cd = DATA[c]
		if cd.cls.isA.BasePart then
			table.insert(list, cd)
		end
	end
	return list
end
Classes.modelParts = modelParts

local function modelPivot(d, realm)
	local pp = readProp(d, "PrimaryPart", realm)
	if pp then
		local pd = DATA[pp]
		return readCF(pd, realm) * (pd.props.PivotOffset or CFrame.identity)
	end
	local wp = d.props.WorldPivot
	if wp then
		return wp
	end
	local parts = modelParts(d, realm)
	if #parts == 0 then
		return CFrame.identity
	end
	local cf = boundsOf(parts, CFrame.identity, realm)
	return cf
end
Classes.modelPivot = modelPivot

local function pivotModelTo(d, cf, realm)
	local pivot = modelPivot(d, realm)
	local delta = cf * pivot:Inverse()
	for _, pd in modelParts(d, realm) do
		setPartCFrame(pd, delta * readCF(pd, realm), realm, true)
	end
	if not readProp(d, "PrimaryPart", realm) then
		setProp(d, "WorldPivot", cf, realm)
	end
end
Classes.pivotModelTo = pivotModelTo

define("Model", {
	getters = {
		WorldPivot = function(d, realm)
			return modelPivot(d, realm)
		end,
	},
	setters = {
		PrimaryPart = function(d, v, realm)
			if v ~= nil then
				local pd = DATA[v]
				if not Engine.isDescendantOf(pd, d) then
					Engine.record("proptype", string.format("Model.PrimaryPart set to %s which is not a descendant of %s (Roblox ignores it)", Engine.fullName(pd), Engine.fullName(d)))
					return
				end
			end
			setProp(d, "PrimaryPart", v, realm)
		end,
	},
	methods = {
		GetPivot = function(u)
			return modelPivot(self(u, "GetPivot"), R())
		end,
		PivotTo = function(u, cf)
			local d = self(u, "PivotTo")
			if typeof(cf) ~= "CFrame" then
				throw("runtime", "invalid argument #1 to 'PivotTo' (CFrame expected, got " .. typeof(cf) .. ")")
			end
			pivotModelTo(d, cf, R())
		end,
		GetBoundingBox = function(u)
			local d = self(u, "GetBoundingBox")
			local realm = R()
			local pivot = modelPivot(d, realm)
			return boundsOf(modelParts(d, realm), pivot.Rotation + Vector3.zero, realm)
		end,
		GetExtentsSize = function(u)
			local d = self(u, "GetExtentsSize")
			local realm = R()
			local _, size = boundsOf(modelParts(d, realm), modelPivot(d, realm).Rotation, realm)
			return size
		end,
		MoveTo = function(u, pos)
			local d = self(u, "MoveTo")
			local realm = R()
			local pivot = modelPivot(d, realm)
			pivotModelTo(d, CFrame.new(pos) * pivot.Rotation, realm)
		end,
		TranslateBy = function(u, delta)
			local d = self(u, "TranslateBy")
			local realm = R()
			pivotModelTo(d, modelPivot(d, realm) + delta, realm)
		end,
		SetPrimaryPartCFrame = function(u, cf)
			local d = self(u, "SetPrimaryPartCFrame")
			local realm = R()
			local pp = readProp(d, "PrimaryPart", realm)
			if not pp then
				throw("runtime", "Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists.")
			end
			pivotModelTo(d, cf * (DATA[pp].props.PivotOffset or CFrame.identity), realm)
		end,
		GetPrimaryPartCFrame = function(u)
			local d = self(u, "GetPrimaryPartCFrame")
			local pp = readProp(d, "PrimaryPart", R())
			if not pp then
				throw("runtime", "Model:GetPrimaryPartCFrame() failed because no PrimaryPart has been set")
			end
			return readCF(DATA[pp], R())
		end,
		GetScale = function(u)
			return self(u, "GetScale").scale or 1
		end,
		ScaleTo = function(u, s)
			local d = self(u, "ScaleTo")
			if type(s) ~= "number" or s <= 0 then
				throw("runtime", "Model:ScaleTo() scale must be a positive number")
			end
			local realm = R()
			local old = d.scale or 1
			local k = s / old
			local pivot = modelPivot(d, realm)
			for _, pd in modelParts(d, realm) do
				local cf = readCF(pd, realm)
				local rel = pivot:ToObjectSpace(cf)
				setProp(pd, "Size", (readProp(pd, "Size", realm) or Vector3.one) * k, realm)
				setPartCFrame(pd, pivot * (rel.Rotation + rel.Position * k), realm, true)
			end
			d.scale = s
		end,
		BreakJoints = function(u)
			local d = self(u, "BreakJoints")
			for _, c in Engine.descendantsOf(d, R()) do
				local cd = DATA[c]
				if cd.cls.isA.JointInstance or cd.class == "WeldConstraint" then
					Engine.destroy(cd, R())
				end
			end
		end,
		MakeJoints = function(u)
			self(u, "MakeJoints")
		end,
		AddPersistentPlayer = function() end,
		RemovePersistentPlayer = function() end,
	},
})

----------------------------------------------------------------------
-- Attachments
----------------------------------------------------------------------
local function attachParentCF(d, realm)
	local p = d.parent and DATA[d.parent]
	if p and p.cls.isA.BasePart then
		return readCF(p, realm)
	end
	return CFrame.identity
end

define("Attachment", {
	getters = {
		Position = function(d, realm)
			return (readProp(d, "CFrame", realm) or CFrame.identity).Position
		end,
		WorldCFrame = function(d, realm)
			return attachParentCF(d, realm) * (readProp(d, "CFrame", realm) or CFrame.identity)
		end,
		WorldPosition = function(d, realm)
			return (attachParentCF(d, realm) * (readProp(d, "CFrame", realm) or CFrame.identity)).Position
		end,
		Orientation = function(d, realm)
			return orientationOf(readProp(d, "CFrame", realm) or CFrame.identity)
		end,
		WorldOrientation = function(d, realm)
			return orientationOf(attachParentCF(d, realm) * (readProp(d, "CFrame", realm) or CFrame.identity))
		end,
		Axis = function(d, realm)
			return (readProp(d, "CFrame", realm) or CFrame.identity).RightVector
		end,
		SecondaryAxis = function(d, realm)
			return (readProp(d, "CFrame", realm) or CFrame.identity).UpVector
		end,
		WorldAxis = function(d, realm)
			return (attachParentCF(d, realm) * (readProp(d, "CFrame", realm) or CFrame.identity)).RightVector
		end,
		WorldSecondaryAxis = function(d, realm)
			return (attachParentCF(d, realm) * (readProp(d, "CFrame", realm) or CFrame.identity)).UpVector
		end,
	},
	setters = {
		Position = function(d, v, realm)
			local cf = readProp(d, "CFrame", realm) or CFrame.identity
			setProp(d, "CFrame", CFrame.new(v) * cf.Rotation, realm)
		end,
		Orientation = function(d, v, realm)
			local cf = readProp(d, "CFrame", realm) or CFrame.identity
			setProp(d, "CFrame", CFrame.new(cf.Position) * fromOrientation(v), realm)
		end,
		WorldCFrame = function(d, v, realm)
			setProp(d, "CFrame", attachParentCF(d, realm):Inverse() * v, realm)
		end,
		WorldPosition = function(d, v, realm)
			local local_ = attachParentCF(d, realm):PointToObjectSpace(v)
			local cf = readProp(d, "CFrame", realm) or CFrame.identity
			setProp(d, "CFrame", CFrame.new(local_) * cf.Rotation, realm)
		end,
	},
	methods = {
		GetConstraints = function()
			return {}
		end,
	},
})

----------------------------------------------------------------------
-- Values
----------------------------------------------------------------------
define("ValueBase", {})

----------------------------------------------------------------------
-- Sounds, particles, beams
----------------------------------------------------------------------
define("Sound", {
	getters = {
		IsPlaying = function(d)
			return d.playing == true
		end,
		IsPaused = function(d)
			return d.paused == true
		end,
		IsLoaded = function(d, realm)
			local id = readProp(d, "SoundId", realm)
			return type(id) == "string" and id ~= ""
		end,
		TimeLength = function(d, realm)
			local id = readProp(d, "SoundId", realm)
			if type(id) == "string" and id ~= "" then
				return 2.5
			end
			return 0
		end,
		PlaybackLoudness = function(d)
			return if d.playing then 100 else 0
		end,
		Playing = function(d)
			return d.playing == true
		end,
	},
	setters = {
		Playing = function(d, v, realm)
			if v then
				Classes.soundPlay(d, realm)
			else
				Classes.soundStop(d, realm)
			end
		end,
	},
	methods = {
		Play = function(u)
			Classes.soundPlay(self(u, "Play"), R())
		end,
		Stop = function(u)
			Classes.soundStop(self(u, "Stop"), R())
		end,
		Pause = function(u)
			local d = self(u, "Pause")
			d.playing = false
			d.paused = true
			Engine.fireEvent(d, "Paused", Engine.eventFilter(d), readProp(d, "SoundId", R()))
		end,
		Resume = function(u)
			local d = self(u, "Resume")
			if d.paused then
				d.paused = false
				Classes.soundPlay(d, R(), true)
			end
		end,
	},
})

function Classes.soundPlay(d, realm, resume)
	d.playing = true
	d.paused = false
	d.playToken = (d.playToken or 0) + 1
	local token = d.playToken
	Engine.fireEvent(d, if resume then "Resumed" else "Played", Engine.eventFilter(d), readProp(d, "SoundId", realm))
	if not readProp(d, "Looped", realm) then
		local speed = readProp(d, "PlaybackSpeed", realm) or 1
		local len = 2.5 / math.max(0.05, speed)
		Sched.at(Sched.now + len, function()
			if d.playToken == token and d.playing then
				d.playing = false
				Engine.fireEvent(d, "Ended", Engine.eventFilter(d), readProp(d, "SoundId", realm))
				if d.playOnRemoveDestroy then
					Engine.destroy(d, realm)
				end
			end
		end)
	end
end
function Classes.soundStop(d, realm)
	if d.playing or d.paused then
		d.playing = false
		d.paused = false
		d.playToken = (d.playToken or 0) + 1
		Engine.fireEvent(d, "Stopped", Engine.eventFilter(d), readProp(d, "SoundId", realm))
	end
end

define("ParticleEmitter", {
	methods = {
		Emit = function(u, n)
			local d = self(u, "Emit")
			if n ~= nil and type(n) ~= "number" then
				throw("runtime", "invalid argument #1 to 'Emit' (number expected, got " .. typeof(n) .. ")")
			end
			d.emitted = (d.emitted or 0) + (n or 16)
		end,
		Clear = function(u)
			self(u, "Clear")
		end,
		FastForward = function(u)
			self(u, "FastForward")
		end,
	},
})
define("Beam", { methods = { SetTextureOffset = function(u)
	self(u, "SetTextureOffset")
end } })
define("Trail", { methods = { Clear = function(u)
	self(u, "Clear")
end } })

----------------------------------------------------------------------
-- Animation
----------------------------------------------------------------------
local function newTrack(animatorD, anim)
	local u, d = Engine.makeInstance("AnimationTrack", animatorD.owner)
	d.props.Animation = anim
	d.props.Name = if anim then DATA[anim].props.Name else "AnimationTrack"
	d.playing = false
	d.animator = animatorD
	return u
end

define("AnimationTrack", {
	getters = {
		IsPlaying = function(d)
			return d.playing == true
		end,
		Length = function()
			return 1
		end,
		Speed = function(d)
			return d.speed or 1
		end,
		WeightCurrent = function(d)
			return if d.playing then 1 else 0
		end,
		WeightTarget = function(d)
			return d.weight or 1
		end,
	},
	methods = {
		Play = function(u, fade, weight, speed)
			local d = self(u, "Play")
			d.playing = true
			d.speed = speed or d.speed or 1
			d.weight = weight or 1
			local a = d.animator
			if a then
				a.tracks = a.tracks or {}
				a.tracks[d] = true
			end
			if not readProp(d, "Looped", R()) then
				local token = (d.token or 0) + 1
				d.token = token
				Sched.at(Sched.now + 1 / math.max(0.05, d.speed), function()
					if d.token == token and d.playing then
						d.playing = false
						if a and a.tracks then
							a.tracks[d] = nil
						end
						Engine.fireEvent(d, "Stopped", Engine.eventFilter(d))
						Engine.fireEvent(d, "Ended", Engine.eventFilter(d))
					end
				end)
			end
		end,
		Stop = function(u)
			local d = self(u, "Stop")
			if d.playing then
				d.playing = false
				d.token = (d.token or 0) + 1
				if d.animator and d.animator.tracks then
					d.animator.tracks[d] = nil
				end
				Engine.fireEvent(d, "Stopped", Engine.eventFilter(d))
				Engine.fireEvent(d, "Ended", Engine.eventFilter(d))
			end
		end,
		AdjustSpeed = function(u, s)
			self(u, "AdjustSpeed").speed = s or 1
		end,
		AdjustWeight = function(u, w)
			self(u, "AdjustWeight").weight = w or 1
		end,
		GetMarkerReachedSignal = function(u, name)
			return Engine.getSignal(self(u, "GetMarkerReachedSignal"), "marker:" .. tostring(name))
		end,
		GetTimeOfKeyframe = function()
			return 0
		end,
	},
})

local function loadAnimation(u, anim, fnName)
	local d = self(u, fnName)
	if anim == nil or not DATA[anim] or DATA[anim].class ~= "Animation" then
		throw("runtime", "Unable to cast value to Object (LoadAnimation requires an Animation instance)")
	end
	local track = newTrack(d, anim)
	return track
end

define("Animator", {
	methods = {
		LoadAnimation = function(u, anim)
			return loadAnimation(u, anim, "LoadAnimation")
		end,
		GetPlayingAnimationTracks = function(u)
			local d = self(u, "GetPlayingAnimationTracks")
			local out = {}
			for t in d.tracks or {} do
				table.insert(out, t.proxy)
			end
			return out
		end,
		StepAnimations = function() end,
		ApplyJointVelocities = function() end,
	},
})
Classes.loadAnimation = loadAnimation

----------------------------------------------------------------------
-- Tools
----------------------------------------------------------------------
define("Tool", {
	methods = {
		Activate = function(u)
			local d = self(u, "Activate")
			Engine.fireEvent(d, "Activated", nil)
		end,
		Deactivate = function(u)
			local d = self(u, "Deactivate")
			Engine.fireEvent(d, "Deactivated", nil)
		end,
	},
})

----------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------
define("LuaSourceContainer", {
	getters = {
		Source = function(d)
			return d.source or ""
		end,
	},
	setters = {
		Source = function(d, v)
			d.source = v
			d.bytecode = nil
		end,
	},
})

----------------------------------------------------------------------
-- GUI geometry (approximate: no layout engine, but UDim2 math, UIScale and text size estimates)
----------------------------------------------------------------------
Classes.viewportFor = function(realm)
	return Vector2.new(1366, 768)
end
Classes.GUI_INSET = 58

local absSize, absPos

local function uiScaleOf(d, realm)
	for _, c in d.children do
		local cd = DATA[c]
		if cd.class == "UIScale" and Engine.visibleTo(cd, realm) then
			return readProp(cd, "Scale", realm) or 1
		end
	end
	return 1
end

-- Parent container size/position for GUI math
local function containerOf(d, realm)
	local p = d.parent and DATA[d.parent]
	if not p then
		return Vector2.zero, Vector2.zero
	end
	if p.cls.isA.GuiObject then
		return absSize(p, realm), absPos(p, realm)
	end
	if p.cls.isA.LayerCollector then
		return absSize(p, realm), absPos(p, realm)
	end
	return Vector2.zero, Vector2.zero
end

absSize = function(d, realm)
	local cls = d.cls
	if cls.isA.ScreenGui then
		local vp = Classes.viewportFor(realm)
		if readProp(d, "IgnoreGuiInset", realm) then
			return vp
		end
		return Vector2.new(vp.X, vp.Y - Classes.GUI_INSET)
	elseif cls.isA.SurfaceGui then
		return readProp(d, "CanvasSize", realm) or Vector2.new(800, 600)
	elseif cls.isA.BillboardGui then
		local s = readProp(d, "Size", realm) or UDim2.new()
		return Vector2.new(s.X.Offset, s.Y.Offset)
	elseif cls.isA.LayerCollector then
		return Classes.viewportFor(realm)
	end
	local s = readProp(d, "Size", realm) or UDim2.new()
	local psize = containerOf(d, realm)
	local k = uiScaleOf(d, realm)
	return Vector2.new((psize.X * s.X.Scale + s.X.Offset) * k, (psize.Y * s.Y.Scale + s.Y.Offset) * k)
end
absPos = function(d, realm)
	local cls = d.cls
	if cls.isA.ScreenGui then
		if readProp(d, "IgnoreGuiInset", realm) then
			return Vector2.zero
		end
		return Vector2.new(0, Classes.GUI_INSET)
	elseif cls.isA.LayerCollector then
		return Vector2.zero
	end
	local p = readProp(d, "Position", realm) or UDim2.new()
	local psize, ppos = containerOf(d, realm)
	local size = absSize(d, realm)
	local ap = readProp(d, "AnchorPoint", realm) or Vector2.zero
	return Vector2.new(ppos.X + psize.X * p.X.Scale + p.X.Offset - ap.X * size.X, ppos.Y + psize.Y * p.Y.Scale + p.Y.Offset - ap.Y * size.Y)
end
Classes.absSize = absSize
Classes.absPos = absPos

local function textBounds(d, realm)
	local text = readProp(d, "ContentText", realm) or readProp(d, "Text", realm) or ""
	text = string.gsub(text, "<[^>]+>", "")
	local size = readProp(d, "TextSize", realm) or 14
	if readProp(d, "TextScaled", realm) then
		local a = absSize(d, realm)
		return Vector2.new(math.min(a.X, utf8.len(text) or #text) * 1, a.Y)
	end
	local lineH = size * (readProp(d, "LineHeight", realm) or 1)
	local maxW = math.huge
	if readProp(d, "TextWrapped", realm) then
		maxW = math.max(1, absSize(d, realm).X)
	end
	local widest, lines = 0, 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local w = (utf8.len(line) or #line) * size * 0.52
		if w > maxW then
			lines += math.ceil(w / maxW)
			widest = maxW
		else
			lines += 1
			widest = math.max(widest, w)
		end
	end
	return Vector2.new(math.floor(widest + 0.5), lines * lineH)
end
Classes.textBounds = textBounds

define("GuiBase2d", {
	getters = {
		AbsoluteSize = function(d, realm)
			return absSize(d, realm)
		end,
		AbsolutePosition = function(d, realm)
			return absPos(d, realm)
		end,
		AbsoluteRotation = function(d, realm)
			return readProp(d, "Rotation", realm) or 0
		end,
	},
})
define("GuiObject", {
	getters = {
		GuiState = function()
			return Enum.GuiState.Idle
		end,
	},
	methods = {
		TweenPosition = function(u, pos, dir, style, t, override, cb)
			local d = self(u, "TweenPosition")
			return Classes.legacyTween(d, { Position = pos }, t, cb)
		end,
		TweenSize = function(u, size, dir, style, t, override, cb)
			local d = self(u, "TweenSize")
			return Classes.legacyTween(d, { Size = size }, t, cb)
		end,
		TweenSizeAndPosition = function(u, size, pos, dir, style, t, override, cb)
			local d = self(u, "TweenSizeAndPosition")
			return Classes.legacyTween(d, { Size = size, Position = pos }, t, cb)
		end,
	},
})
function Classes.legacyTween(d, props, t, cb)
	local realm = Sched.CUR
	Sched.at(Sched.now + (t or 1), function()
		for k, v in props do
			setProp(d, k, v, realm)
		end
		if cb then
			Sched.deferCall(realm, cb, Enum.TweenStatus.Completed)
		end
	end)
	return true
end

local textGetters = {
	TextBounds = function(d, realm)
		return textBounds(d, realm)
	end,
	TextFits = function(d, realm)
		local b = textBounds(d, realm)
		local a = absSize(d, realm)
		return b.X <= a.X + 0.5 and b.Y <= a.Y + 0.5
	end,
	ContentText = function(d, realm)
		local t = readProp(d, "Text", realm) or ""
		if readProp(d, "RichText", realm) then
			t = string.gsub(t, "<[^>]+>", "")
		end
		return t
	end,
	LocalizedText = function(d, realm)
		return readProp(d, "Text", realm) or ""
	end,
}
define("TextLabel", { getters = textGetters })
define("TextButton", { getters = textGetters })
define("TextBox", {
	getters = textGetters,
	methods = {
		CaptureFocus = function(u)
			local d = self(u, "CaptureFocus")
			d.focused = true
			Classes.focusedBox = { d = d, realm = R() }
			Engine.fireEvent(d, "Focused", R())
		end,
		ReleaseFocus = function(u, submitted)
			local d = self(u, "ReleaseFocus")
			if d.focused then
				d.focused = false
				if Classes.focusedBox and Classes.focusedBox.d == d then
					Classes.focusedBox = nil
				end
				Engine.fireEvent(d, "FocusLost", R(), submitted == true, nil)
			end
		end,
		IsFocused = function(u)
			return self(u, "IsFocused").focused == true
		end,
	},
})
define("ImageLabel", { getters = { IsLoaded = function()
	return true
end } })
define("ImageButton", { getters = { IsLoaded = function()
	return true
end } })

define("ScrollingFrame", {
	getters = {
		AbsoluteWindowSize = function(d, realm)
			return absSize(d, realm)
		end,
		AbsoluteCanvasSize = function(d, realm)
			local cs = readProp(d, "CanvasSize", realm) or UDim2.new()
			local w = absSize(d, realm)
			local base = Vector2.new(w.X * cs.X.Scale + cs.X.Offset, w.Y * cs.Y.Scale + cs.Y.Offset)
			local auto = readProp(d, "AutomaticCanvasSize", realm)
			if auto and auto ~= Enum.AutomaticSize.None then
				local content = Classes.contentSize(d, realm)
				return Vector2.new(math.max(base.X, content.X), math.max(base.Y, content.Y))
			end
			return base
		end,
	},
})

-- Content size of a container: union of child extents, or the layout's content size
function Classes.contentSize(d, realm)
	for _, c in Engine.childrenOf(d, realm) do
		local cd = DATA[c]
		if cd.cls.isA.UIGridStyleLayout then
			return Classes.layoutContentSize(cd, realm)
		end
	end
	local maxX, maxY = 0, 0
	local base = absPos(d, realm)
	for _, c in Engine.childrenOf(d, realm) do
		local cd = DATA[c]
		if cd.cls.isA.GuiObject and readProp(cd, "Visible", realm) ~= false then
			local p = absPos(cd, realm) - base
			local s = absSize(cd, realm)
			maxX = math.max(maxX, p.X + s.X)
			maxY = math.max(maxY, p.Y + s.Y)
		end
	end
	return Vector2.new(maxX, maxY)
end

function Classes.layoutContentSize(ld, realm)
	local p = ld.parent and DATA[ld.parent]
	if not p then
		return Vector2.zero
	end
	local items = {}
	for _, c in Engine.childrenOf(p, realm) do
		local cd = DATA[c]
		if cd.cls.isA.GuiObject and readProp(cd, "Visible", realm) ~= false then
			table.insert(items, cd)
		end
	end
	if ld.class == "UIGridLayout" then
		local cell = readProp(ld, "CellSize", realm) or UDim2.fromOffset(100, 100)
		local pad = readProp(ld, "CellPadding", realm) or UDim2.fromOffset(5, 5)
		local ps = absSize(p, realm)
		local cw = ps.X * cell.X.Scale + cell.X.Offset
		local ch = ps.Y * cell.Y.Scale + cell.Y.Offset
		local px = ps.X * pad.X.Scale + pad.X.Offset
		local py = ps.Y * pad.Y.Scale + pad.Y.Offset
		local perRow = math.max(1, math.floor((ps.X + px) / math.max(1, cw + px)))
		local rows = math.ceil(#items / perRow)
		return Vector2.new(math.min(#items, perRow) * (cw + px) - px, math.max(0, rows * (ch + py) - py))
	end
	local horizontal = readProp(ld, "FillDirection", realm) == Enum.FillDirection.Horizontal
	local pad = readProp(ld, "Padding", realm) or roblox.UDim.new()
	local ps = absSize(p, realm)
	local padPx = (if horizontal then ps.X else ps.Y) * pad.Scale + pad.Offset
	local along, across = 0, 0
	for i, cd in items do
		local s = absSize(cd, realm)
		if horizontal then
			along += s.X
			across = math.max(across, s.Y)
		else
			along += s.Y
			across = math.max(across, s.X)
		end
		if i > 1 then
			along += padPx
		end
	end
	if horizontal then
		return Vector2.new(along, across)
	end
	return Vector2.new(across, along)
end

define("UIGridStyleLayout", {
	getters = {
		AbsoluteContentSize = function(d, realm)
			return Classes.layoutContentSize(d, realm)
		end,
	},
	methods = {
		ApplyLayout = function(u)
			self(u, "ApplyLayout")
		end,
	},
})
define("UIGridLayout", {
	getters = {
		AbsoluteCellSize = function(d, realm)
			local p = d.parent and DATA[d.parent]
			local cell = readProp(d, "CellSize", realm) or UDim2.fromOffset(100, 100)
			local ps = if p then absSize(p, realm) else Vector2.zero
			return Vector2.new(ps.X * cell.X.Scale + cell.X.Offset, ps.Y * cell.Y.Scale + cell.Y.Offset)
		end,
		AbsoluteCellCount = function()
			return Vector2.new(1, 1)
		end,
	},
})
define("UIPageLayout", {
	methods = {
		JumpTo = function(u, page)
			self(u, "JumpTo")
		end,
		JumpToIndex = function(u)
			self(u, "JumpToIndex")
		end,
		Next = function(u)
			self(u, "Next")
		end,
		Previous = function(u)
			self(u, "Previous")
		end,
	},
})

define("LayerCollector", {
	methods = {
		GetLayoutNodeTree = function()
			Engine.notEmulated("LayerCollector:GetLayoutNodeTree()")
		end,
	},
})
define("BasePlayerGui", {
	methods = {
		GetGuiObjectsAtPosition = function()
			return {}
		end,
	},
})
define("PlayerGui", {
	methods = {
		SetTopbarTransparency = function() end,
		GetTopbarTransparency = function()
			return 0
		end,
	},
})

----------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------
local function camViewport(d, realm)
	return d.viewport or Classes.viewportFor(realm)
end

local function worldToViewport(d, realm, p)
	local cf = readProp(d, "CFrame", realm) or CFrame.identity
	local vp = camViewport(d, realm)
	local fov = math.rad(readProp(d, "FieldOfView", realm) or 70)
	local lp = cf:PointToObjectSpace(p)
	local depth = -lp.Z
	local f = (vp.Y / 2) / math.tan(fov / 2)
	local x, y
	if math.abs(depth) < 1e-6 then
		x, y = vp.X / 2, vp.Y / 2
	else
		x = vp.X / 2 + lp.X * f / depth
		y = vp.Y / 2 - lp.Y * f / depth
	end
	local onScreen = depth > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
	return Vector3.new(x, y, depth), onScreen
end

local function viewportRay(d, realm, x, y, depth)
	local cf = readProp(d, "CFrame", realm) or CFrame.identity
	local vp = camViewport(d, realm)
	local fov = math.rad(readProp(d, "FieldOfView", realm) or 70)
	local f = (vp.Y / 2) / math.tan(fov / 2)
	local dirLocal = Vector3.new((x - vp.X / 2) / f, -(y - vp.Y / 2) / f, -1).Unit
	local origin = cf.Position + cf:VectorToWorldSpace(dirLocal) * (depth or 0)
	return roblox.Ray.new(origin, cf:VectorToWorldSpace(dirLocal))
end

define("Camera", {
	getters = {
		ViewportSize = function(d, realm)
			return camViewport(d, realm)
		end,
		NearPlaneZ = function()
			return -0.1
		end,
	},
	methods = {
		WorldToViewportPoint = function(u, p)
			local d = self(u, "WorldToViewportPoint")
			if typeof(p) ~= "Vector3" then
				throw("runtime", "invalid argument #1 to 'WorldToViewportPoint' (Vector3 expected, got " .. typeof(p) .. ")")
			end
			return worldToViewport(d, R(), p)
		end,
		WorldToScreenPoint = function(u, p)
			local d = self(u, "WorldToScreenPoint")
			local v, on = worldToViewport(d, R(), p)
			return Vector3.new(v.X, v.Y - Classes.GUI_INSET, v.Z), on
		end,
		ViewportPointToRay = function(u, x, y, depth)
			return viewportRay(self(u, "ViewportPointToRay"), R(), x, y, depth)
		end,
		ScreenPointToRay = function(u, x, y, depth)
			return viewportRay(self(u, "ScreenPointToRay"), R(), x, y + Classes.GUI_INSET, depth)
		end,
		GetPartsObscuringTarget = function()
			return {}
		end,
		GetRenderCFrame = function(u)
			return readProp(self(u, "GetRenderCFrame"), "CFrame", R())
		end,
		GetRoll = function()
			return 0
		end,
		SetRoll = function() end,
		ZoomToExtents = function() end,
		Interpolate = function(u, cf, focus, t)
			local d = self(u, "Interpolate")
			local realm = R()
			Sched.at(Sched.now + (t or 0), function()
				setProp(d, "CFrame", cf, realm)
				setProp(d, "Focus", focus, realm)
				Engine.fireEvent(d, "InterpolationFinished", realm)
			end)
		end,
	},
})

return Classes

--!strict
-- Прямая кинематика рига: обход суставов от HumanoidRootPart, расчёт CFrame каждой детали
-- по Transform моторов. В игре детали затем двигаются через workspace:BulkMoveTo (все заякорены),
-- поэтому результат не зависит от физики и Animator, и в превью (Lune) считается точно так же.

local FK = {}

local IDENTITY = CFrame.new()

-- В Roblox экземпляры уникальны и годятся как ключи таблиц; в Lune (превью/сборка) — нет, там ключ = DebugId.
local IN_ROBLOX = (game :: any) ~= nil
local function key(i: Instance): any
	if IN_ROBLOX then
		return i
	end
	return (i :: any):GetDebugId()
end

export type Entry = {
	part: BasePart,
	parent: number,
	key: string?,
	inverse: boolean,
	a: CFrame,
	b: CFrame,
}

export type Rig = {
	model: Instance,
	root: BasePart,
	entries: { Entry },
	parts: { BasePart },
}

local function isJoint(d: Instance): boolean
	return d:IsA("JointInstance") or d:IsA("WeldConstraint")
end

function FK.build(model: Instance): Rig
	local root: Instance? = (model :: any).PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "FK.build: no HumanoidRootPart in " .. model:GetFullName())

	local inModel: { [any]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			inModel[key(d)] = true
		end
	end

	local adj: { [any]: { any } } = {}
	local function link(p: Instance, rec: any)
		local list = adj[key(p)]
		if not list then
			list = {}
			adj[key(p)] = list
		end
		table.insert(list, rec)
	end
	for _, d in model:GetDescendants() do
		if isJoint(d) then
			local j = d :: any
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 and inModel[key(p0)] and inModel[key(p1)] and p0 ~= p1 then
				link(p0, { joint = j, other = p1, forward = true })
				link(p1, { joint = j, other = p0, forward = false })
			end
		end
	end

	local entries: { Entry } = {
		{ part = root :: any, parent = 0, key = nil, inverse = false, a = IDENTITY, b = IDENTITY },
	}
	local index: { [any]: number } = { [key(root :: any)] = 1 }
	local head = 1
	while head <= #entries do
		local cur = entries[head]
		for _, rec in adj[key(cur.part)] or {} do
			local other = rec.other
			if index[key(other)] == nil then
				local j = rec.joint
				local e: Entry
				if j:IsA("Motor6D") then
					if rec.forward then
						e = { part = other, parent = head, key = j.Part1.Name, inverse = false, a = j.C0, b = j.C1:Inverse() }
					else
						e = { part = other, parent = head, key = j.Part1.Name, inverse = true, a = j.C1, b = j.C0:Inverse() }
					end
				elseif j:IsA("WeldConstraint") then
					local offset = j.Part0.CFrame:ToObjectSpace(j.Part1.CFrame)
					e = { part = other, parent = head, key = nil, inverse = false, a = if rec.forward then offset else offset:Inverse(), b = IDENTITY }
				else
					if rec.forward then
						e = { part = other, parent = head, key = nil, inverse = false, a = j.C0 * j.C1:Inverse(), b = IDENTITY }
					else
						e = { part = other, parent = head, key = nil, inverse = false, a = j.C1 * j.C0:Inverse(), b = IDENTITY }
					end
				end
				table.insert(entries, e)
				index[key(other)] = #entries
			end
		end
		head += 1
	end

	local parts: { BasePart } = {}
	for i, e in entries do
		parts[i] = e.part
	end
	return { model = model, root = root :: any, entries = entries, parts = parts }
end

-- out[i] = мировой CFrame детали rig.parts[i].
function FK.solve(rig: Rig, rootCf: CFrame, transforms: { [string]: CFrame }, out: { CFrame })
	local entries = rig.entries
	out[1] = rootCf
	for i = 2, #entries do
		local e = entries[i]
		local pcf = out[e.parent]
		local key = e.key
		if key then
			local t = transforms[key] or IDENTITY
			if e.inverse then
				t = t:Inverse()
			end
			out[i] = pcf * e.a * t * e.b
		else
			out[i] = pcf * e.a
		end
	end
end

-- Имена всех моторов (по Part1), для проверки клипов.
function FK.motorKeys(rig: Rig): { [string]: boolean }
	local keys = {}
	for _, e in rig.entries do
		if e.key then
			keys[e.key] = true
		end
	end
	return keys
end

return FK

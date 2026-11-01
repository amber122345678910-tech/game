--!strict
-- HDMesh: optional HD mesh tier (docs/SPEC.md section 18, docs/HD_MESHES.md).
-- Smooth sculpted meshes (Sans skulls, Gaster Blaster skulls + jaws) generated offline by
-- tools/meshgen and shipped as data modules in ReplicatedStorage.Shared.Meshes. Gameplay never
-- depends on them: when no tier is available every function fails soft (returns nil / false) and
-- the part-built models stay as they are.
--
-- Tiers (checked per mesh name, in this order):
--   A "Imported": the owner imported assets/meshes/<Name>.obj|.glb in Studio as MeshParts named
--      <Name> inside ReplicatedStorage.SV_Meshes. Works without any verification.
--   B "Editable": AssetService:CreateEditableMesh() works (owner enabled Game Settings -> Security ->
--      "Allow Mesh / Image APIs"). One EditableMesh is built per mesh name and shared by all clones.
--
-- Public API (client; functions marked (yields) may yield - call them from task.spawn):
--   HDMesh.Decode(data: string | MeshData) -> Decoded        pure, Lune-safe ("SVM1" payload)
--   HDMesh.GetData(name: string) -> MeshData?                the generated data module
--   HDMesh.Names() -> {string}
--   HDMesh.Available() -> boolean                            any tier usable (probe cached)
--   HDMesh.Tier(name: string?) -> "Imported" | "Editable" | "None"
--   HDMesh.Create(meshName: string) -> MeshPart?             (yields) new unparented MeshPart
--   HDMesh.Preload(names: {string}?)                          builds meshes in background threads
--   HDMesh.ApplyToModel(model: Model) -> boolean             (yields) SPEC 18 anchors -> HD parts
--   HDMesh.RemoveFromModel(model: Model)                     undo ApplyToModel (local only)
--   HDMesh.CreateBlaster(style: string, scale: number?) -> Model?   (yields) Skull + Jaw rig
--   HDMesh.PoseBlasterJaw(model: Model, angle: number)       open the jaw by `angle` radians
--
-- CreateBlaster model layout: PrimaryPart "Skull" (MeshPart, Anchored) with Attachments
-- "JawHinge", "Muzzle", "LeftEye", "RightEye"; MeshPart "Jaw" (Anchored) with Attachment "JawHinge".
-- Faces -Z like every rig/prop (SPEC section 3). Move it with Model:PivotTo, then PoseBlasterJaw.
-- Never require this module from server code (EditableMesh is client-only).

local HDMesh = {}

-- ---------------------------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------------------------
export type MeshData = {
	Name: string,
	Size: Vector3,
	Hinge: Vector3?,
	Anchors: { [string]: Vector3 }?,
	VertexCount: number,
	TriangleCount: number,
	Format: number,
	Data: string,
}

export type Decoded = {
	vertexCount: number,
	triangleCount: number,
	positions: { Vector3 },
	normals: { Vector3 },
	colors: { Color3 }, -- per vertex (shared palette entries)
	alphas: { number }?, -- per vertex, only when the payload carries alpha
	colorIndex: { number }, -- per vertex, 1-based palette index
	palette: { Color3 },
	paletteAlpha: { number },
	indices: { number }, -- 1-based vertex indices, 3 per triangle, counter-clockwise = front
	boundsMin: Vector3,
	boundsMax: Vector3,
}

-- ---------------------------------------------------------------------------------------------
-- Decoder (pure)
-- ---------------------------------------------------------------------------------------------
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE: { [number]: number } = {}
for i = 1, 64 do
	B64_VALUE[string.byte(B64_ALPHABET, i)] = i - 1
end

local HEADER_SIZE = 44
local FLAG_ALPHA = 1
local FLAG_WIDE_INDICES = 2

local function base64ToBuffer(text: string): buffer
	local s = string.gsub(text, "[^%w%+/]", "")
	local n = #s
	local full = n // 4
	local rem = n - full * 4
	local outLen = full * 3 + (if rem == 2 then 1 elseif rem == 3 then 2 else 0)
	local out = buffer.create(outLen)
	local o = 0
	local i = 1
	for _ = 1, full do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = (B64_VALUE[a] or 0) * 262144
			+ (B64_VALUE[b] or 0) * 4096
			+ (B64_VALUE[c] or 0) * 64
			+ (B64_VALUE[d] or 0)
		buffer.writeu8(out, o, bit32.rshift(v, 16))
		buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(v, 8), 255))
		buffer.writeu8(out, o + 2, bit32.band(v, 255))
		o += 3
		i += 4
	end
	if rem >= 2 then
		local a, b = string.byte(s, i, i + 1)
		local c = if rem == 3 then string.byte(s, i + 2) else nil
		local v = (B64_VALUE[a] or 0) * 262144
			+ (B64_VALUE[b] or 0) * 4096
			+ (if c then (B64_VALUE[c] or 0) * 64 else 0)
		buffer.writeu8(out, o, bit32.rshift(v, 16))
		if rem == 3 then
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(v, 8), 255))
		end
	end
	return out
end

local function octDecode(u: number, v: number): Vector3
	local x = u / 255 * 2 - 1
	local y = v / 255 * 2 - 1
	local z = 1 - math.abs(x) - math.abs(y)
	if z < 0 then
		local ox = (1 - math.abs(y)) * (if x >= 0 then 1 else -1)
		local oy = (1 - math.abs(x)) * (if y >= 0 then 1 else -1)
		x, y = ox, oy
	end
	local len = math.sqrt(x * x + y * y + z * z)
	return Vector3.new(x / len, y / len, z / len)
end

-- Decodes a generated mesh payload. Errors on malformed data (callers that must not fail use pcall).
function HDMesh.Decode(data: string | MeshData): Decoded
	local text: string = if type(data) == "table" then (data :: MeshData).Data else data :: string
	local buf = base64ToBuffer(text)
	local len = buffer.len(buf)
	assert(len >= HEADER_SIZE and buffer.readstring(buf, 0, 4) == "SVM1", "HDMesh.Decode: not an SVM1 payload")
	local flags = buffer.readu16(buf, 6)
	local vertexCount = buffer.readu32(buf, 8)
	local triangleCount = buffer.readu32(buf, 12)
	local paletteCount = buffer.readu16(buf, 16)
	local minX, minY, minZ = buffer.readf32(buf, 20), buffer.readf32(buf, 24), buffer.readf32(buf, 28)
	local maxX, maxY, maxZ = buffer.readf32(buf, 32), buffer.readf32(buf, 36), buffer.readf32(buf, 40)
	local wide = bit32.band(flags, FLAG_WIDE_INDICES) ~= 0
	local hasAlpha = bit32.band(flags, FLAG_ALPHA) ~= 0
	local expected = HEADER_SIZE + paletteCount * 4 + vertexCount * 9 + triangleCount * 3 * (if wide then 4 else 2)
	assert(len == expected, ("HDMesh.Decode: payload size %d, expected %d"):format(len, expected))

	local o = HEADER_SIZE
	local palette: { Color3 } = table.create(paletteCount)
	local paletteAlpha: { number } = table.create(paletteCount)
	for p = 1, paletteCount do
		palette[p] = Color3.fromRGB(buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2))
		paletteAlpha[p] = buffer.readu8(buf, o + 3) / 255
		o += 4
	end

	local sx, sy, sz = (maxX - minX) / 65535, (maxY - minY) / 65535, (maxZ - minZ) / 65535
	local positions: { Vector3 } = table.create(vertexCount)
	for v = 1, vertexCount do
		positions[v] = Vector3.new(
			minX + buffer.readu16(buf, o) * sx,
			minY + buffer.readu16(buf, o + 2) * sy,
			minZ + buffer.readu16(buf, o + 4) * sz
		)
		o += 6
	end

	local normals: { Vector3 } = table.create(vertexCount)
	for v = 1, vertexCount do
		normals[v] = octDecode(buffer.readu8(buf, o), buffer.readu8(buf, o + 1))
		o += 2
	end

	local colorIndex: { number } = table.create(vertexCount)
	local colors: { Color3 } = table.create(vertexCount)
	local alphas: { number }? = if hasAlpha then table.create(vertexCount) else nil
	for v = 1, vertexCount do
		local ci = buffer.readu8(buf, o) + 1
		assert(ci <= paletteCount, "HDMesh.Decode: palette index out of range")
		colorIndex[v] = ci
		colors[v] = palette[ci]
		if alphas then
			alphas[v] = paletteAlpha[ci]
		end
		o += 1
	end

	local count = triangleCount * 3
	local indices: { number } = table.create(count)
	if wide then
		for k = 1, count do
			indices[k] = buffer.readu32(buf, o) + 1
			o += 4
		end
	else
		for k = 1, count do
			indices[k] = buffer.readu16(buf, o) + 1
			o += 2
		end
	end

	return {
		vertexCount = vertexCount,
		triangleCount = triangleCount,
		positions = positions,
		normals = normals,
		colors = colors,
		alphas = alphas,
		colorIndex = colorIndex,
		palette = palette,
		paletteAlpha = paletteAlpha,
		indices = indices,
		boundsMin = Vector3.new(minX, minY, minZ),
		boundsMax = Vector3.new(maxX, maxY, maxZ),
	}
end

-- ---------------------------------------------------------------------------------------------
-- Data access (lazy; nothing touches engine services at require time)
-- ---------------------------------------------------------------------------------------------
type MeshIndex = {
	Names: () -> { string },
	Get: (name: string) -> MeshData?,
}

local meshIndex: MeshIndex? = nil

local function getIndex(): MeshIndex?
	if meshIndex then
		return meshIndex
	end
	local ok, result = pcall(function()
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("Meshes")
		if module == nil then
			return nil
		end
		return require(module :: ModuleScript) :: any
	end)
	if ok and type(result) == "table" then
		meshIndex = result :: MeshIndex
	end
	return meshIndex
end

function HDMesh.GetData(name: string): MeshData?
	local index = getIndex()
	return if index then index.Get(name) else nil
end

function HDMesh.Names(): { string }
	local index = getIndex()
	return if index then index.Names() else {}
end

-- ---------------------------------------------------------------------------------------------
-- Tier detection
-- ---------------------------------------------------------------------------------------------
local MAX_EDITABLE_MESHES = 8 -- community-measured safe count per client (docs/research/engine.md 4)
local IMPORTED_FOLDER = "SV_Meshes"

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[HDMesh] " .. message)
end

local editableProbe: boolean? = nil

local function editableSupported(): boolean
	if editableProbe ~= nil then
		return editableProbe
	end
	local ok, mesh = pcall(function()
		return (game:GetService("AssetService") :: any):CreateEditableMesh()
	end)
	editableProbe = ok and mesh ~= nil
	if ok and mesh ~= nil then
		pcall(function()
			mesh:Destroy()
		end)
	end
	return editableProbe :: boolean
end

local function importedFolder(): Instance?
	local ok, folder = pcall(function()
		return game:GetService("ReplicatedStorage"):FindFirstChild(IMPORTED_FOLDER)
	end)
	return if ok then folder else nil
end

local function importedPart(name: string): MeshPart?
	local folder = importedFolder()
	local part = folder and folder:FindFirstChild(name)
	if part and part:IsA("MeshPart") then
		return part :: MeshPart
	end
	return nil
end

function HDMesh.Available(): boolean
	local folder = importedFolder()
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("MeshPart") then
				return true
			end
		end
	end
	return editableSupported()
end

function HDMesh.Tier(name: string?): string
	if name then
		if importedPart(name) then
			return "Imported"
		end
	elseif importedFolder() and HDMesh.Available() and not editableSupported() then
		return "Imported"
	end
	return if editableSupported() then "Editable" else "None"
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------
local templates: { [string]: MeshPart } = {}
local building: { [string]: boolean } = {}
local failed: { [string]: boolean } = {}
local editableCount = 0
local YIELD_EVERY = 1500 -- faces per frame on the simple path

local function configure(part: MeshPart, keepLook: boolean)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	if not keepLook then
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.new(1, 1, 1) -- vertex colours carry the look
	end
end

-- Fills an EditableMesh with the batch APIs; returns false if anything looks off.
local function fillBatch(em: any, mesh: Decoded): boolean
	local vids = em:BatchAdd(Enum.MeshAttribute.Vertex, mesh.positions)
	local nids = em:BatchAdd(Enum.MeshAttribute.Normal, mesh.normals)
	local cids = em:BatchAdd(Enum.MeshAttribute.Color, mesh.palette, mesh.paletteAlpha)
	if #vids ~= mesh.vertexCount or #nids ~= mesh.vertexCount or #cids ~= #mesh.palette then
		return false
	end
	local alpha = em:GetColorAlpha(cids[1])
	if type(alpha) ~= "number" or math.abs(alpha - mesh.paletteAlpha[1]) > 0.02 then
		return false
	end
	local idx = mesh.indices
	local ci = mesh.colorIndex
	local faces = table.create(mesh.triangleCount)
	local faceNormals = table.create(mesh.triangleCount)
	local faceColors = table.create(mesh.triangleCount)
	for t = 1, mesh.triangleCount do
		local k = (t - 1) * 3
		local a, b, c = idx[k + 1], idx[k + 2], idx[k + 3]
		faces[t] = { vids[a], vids[b], vids[c] }
		faceNormals[t] = { nids[a], nids[b], nids[c] }
		faceColors[t] = { cids[ci[a]], cids[ci[b]], cids[ci[c]] }
	end
	local fids = em:BatchAdd(Enum.MeshAttribute.Face, faces)
	if #fids ~= mesh.triangleCount then
		return false
	end
	em:BatchSetFaceAttributes(fids, faceNormals)
	em:BatchSetFaceAttributes(fids, faceColors)
	return true
end

-- Fills an EditableMesh one element at a time (documented singular APIs), yielding periodically.
local function fillSimple(em: EditableMesh, mesh: Decoded)
	local vids = table.create(mesh.vertexCount)
	local nids = table.create(mesh.vertexCount)
	for v = 1, mesh.vertexCount do
		vids[v] = em:AddVertex(mesh.positions[v])
		nids[v] = em:AddNormal(mesh.normals[v])
	end
	local cids = table.create(#mesh.palette)
	for p = 1, #mesh.palette do
		cids[p] = em:AddColor(mesh.palette[p], mesh.paletteAlpha[p])
	end
	local idx = mesh.indices
	local ci = mesh.colorIndex
	for t = 1, mesh.triangleCount do
		local k = (t - 1) * 3
		local a, b, c = idx[k + 1], idx[k + 2], idx[k + 3]
		local fid = em:AddTriangle(vids[a], vids[b], vids[c])
		em:SetFaceNormals(fid, { nids[a], nids[b], nids[c] })
		em:SetFaceColors(fid, { cids[ci[a]], cids[ci[b]], cids[ci[c]] })
		if t % YIELD_EVERY == 0 then
			task.wait()
		end
	end
end

local function buildEditable(name: string): MeshPart?
	local data = HDMesh.GetData(name)
	if data == nil then
		warnOnce("nodata:" .. name, ("no mesh data named %q"):format(name))
		return nil
	end
	if editableCount >= MAX_EDITABLE_MESHES then
		warnOnce("budget", ("EditableMesh budget (%d) reached; %q stays part-built"):format(MAX_EDITABLE_MESHES, name))
		return nil
	end
	local okDecode, mesh = pcall(HDMesh.Decode, data)
	if not okDecode then
		warnOnce("decode:" .. name, ("could not decode %q: %s"):format(name, tostring(mesh)))
		return nil
	end
	local AssetService = game:GetService("AssetService")
	local function newMesh(): EditableMesh?
		local ok, em = pcall(function()
			return AssetService:CreateEditableMesh()
		end)
		return if ok then em else nil
	end
	local em = newMesh()
	if em == nil then
		warnOnce("create", "AssetService:CreateEditableMesh() is unavailable (memory budget or API toggle)")
		return nil
	end
	local okBatch, batchResult = pcall(fillBatch, em, mesh)
	if not (okBatch and batchResult == true) then
		em:Destroy()
		em = newMesh()
		if em == nil then
			return nil
		end
		local simpleMesh = em :: EditableMesh
		local okSimple, err = pcall(fillSimple, simpleMesh, mesh)
		if not okSimple then
			warnOnce("fill:" .. name, ("could not fill %q: %s"):format(name, tostring(err)))
			simpleMesh:Destroy()
			return nil
		end
	end
	local editable = em :: EditableMesh
	local okPart, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if not okPart or part == nil then
		warnOnce("meshpart:" .. name, ("CreateMeshPartAsync failed for %q: %s"):format(name, tostring(part)))
		editable:Destroy()
		return nil
	end
	editableCount += 1
	local meshPart = part :: MeshPart
	meshPart.Name = name
	meshPart.Size = data.Size
	configure(meshPart, false)
	return meshPart
end

-- Returns a new, unparented MeshPart for `meshName` (clone of a cached template), or nil.
function HDMesh.Create(meshName: string): MeshPart?
	local imported = importedPart(meshName)
	if imported then
		local part = imported:Clone()
		part.Name = meshName
		configure(part, imported:GetAttribute("HDKeepLook") == true)
		local yaw = imported:GetAttribute("HDYaw")
		part:SetAttribute("HDYaw", if type(yaw) == "number" then yaw else 0)
		return part
	end
	while building[meshName] do
		task.wait()
	end
	local template = templates[meshName]
	if template == nil then
		if failed[meshName] or not editableSupported() then
			return nil
		end
		building[meshName] = true
		local ok, result = pcall(buildEditable, meshName)
		building[meshName] = nil
		if ok and result then
			templates[meshName] = result
			template = result
		else
			failed[meshName] = true
			if not ok then
				warnOnce("build:" .. meshName, ("building %q errored: %s"):format(meshName, tostring(result)))
			end
			return nil
		end
	end
	local clone = (template :: MeshPart):Clone()
	clone:SetAttribute("HDYaw", 0)
	return clone
end

function HDMesh.Preload(names: { string }?)
	if not HDMesh.Available() then
		return
	end
	for _, name in names or HDMesh.Names() do
		if templates[name] == nil and not building[name] and not failed[name] and importedPart(name) == nil then
			task.spawn(function()
				local part = HDMesh.Create(name)
				if part then
					part:Destroy()
				end
			end)
		end
	end
end

local function yawFix(part: BasePart): CFrame
	local yaw = part:GetAttribute("HDYaw")
	return if type(yaw) == "number" and yaw ~= 0 then CFrame.Angles(0, math.rad(yaw), 0) else CFrame.identity
end

-- ---------------------------------------------------------------------------------------------
-- Rig integration (SPEC 18 anchors)
-- ---------------------------------------------------------------------------------------------
type Applied = { hidden: { BasePart }, connections: { RBXScriptConnection } }
local appliedModels: { [Model]: Applied } = setmetatable({} :: any, { __mode = "k" })
local guardRunning = false

local function hide(entry: Applied, part: BasePart)
	part.LocalTransparencyModifier = 1
	table.insert(entry.hidden, part)
	-- default camera scripts reset LocalTransparencyModifier on characters; put it back
	table.insert(
		entry.connections,
		part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			if part.LocalTransparencyModifier ~= 1 then
				part.LocalTransparencyModifier = 1
			end
		end)
	)
end

local function startGuard()
	if guardRunning then
		return
	end
	guardRunning = true
	task.spawn(function()
		while next(appliedModels) ~= nil do
			task.wait(1)
			for model, entry in appliedModels do
				if model.Parent == nil then
					for _, c in entry.connections do
						c:Disconnect()
					end
					appliedModels[model] = nil
				else
					for _, part in entry.hidden do
						if part.LocalTransparencyModifier ~= 1 then
							part.LocalTransparencyModifier = 1
						end
					end
				end
			end
		end
		guardRunning = false
	end)
end

-- For every Attachment "HD_<Group>" (attributes HDMesh: string, HDSize: Vector3) in `model`, welds an
-- HD MeshPart "HDMesh_<Group>" at the attachment and hides the parts whose HDGroup attribute equals
-- <Group> (locally, LocalTransparencyModifier = 1; they keep colliding / serving as fallback).
-- Idempotent. Returns true when at least one HD group is applied. (yields)
function HDMesh.ApplyToModel(model: Model): boolean
	if not HDMesh.Available() then
		return false
	end
	local scaleAttr = model:GetAttribute("RigScale")
	local rigScale = if type(scaleAttr) == "number" and scaleAttr > 0 then scaleAttr else 1
	local appliedGroups: { [string]: boolean } = {}
	for _, inst in model:GetDescendants() do
		if not inst:IsA("Attachment") or string.sub(inst.Name, 1, 3) ~= "HD_" then
			continue
		end
		local attachment = inst :: Attachment
		local group = string.sub(attachment.Name, 4)
		local meshName = attachment:GetAttribute("HDMesh")
		local hdSize = attachment:GetAttribute("HDSize")
		local host = attachment.Parent
		if type(meshName) ~= "string" or typeof(hdSize) ~= "Vector3" or host == nil or not host:IsA("BasePart") then
			warnOnce("anchor:" .. attachment:GetFullName(), "malformed HD anchor " .. attachment:GetFullName())
			continue
		end
		local hostPart = host :: BasePart
		if hostPart:FindFirstChild("HDMesh_" .. group) then
			appliedGroups[group] = true
			continue
		end
		local part = HDMesh.Create(meshName) -- may yield
		if part == nil then
			continue
		end
		if hostPart.Parent == nil or hostPart:FindFirstChild("HDMesh_" .. group) then
			-- the rig was removed (or another call applied this group) while the mesh was building
			part:Destroy()
			if hostPart.Parent ~= nil then
				appliedGroups[group] = true
			end
			continue
		end
		part.Name = "HDMesh_" .. group
		part.Size = (hdSize :: Vector3) * rigScale
		part.CFrame = attachment.WorldCFrame * yawFix(part)
		part:SetAttribute("HDPart", group)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hostPart
		weld.Part1 = part
		weld.Parent = part
		part.Parent = hostPart
		appliedGroups[group] = true
	end
	if next(appliedGroups) == nil then
		return false
	end
	local e: Applied = appliedModels[model] or { hidden = {}, connections = {} }
	appliedModels[model] = e
	local already: { [BasePart]: boolean } = {}
	for _, p in e.hidden do
		already[p] = true
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst:GetAttribute("HDPart") == nil then
			local basePart = inst :: BasePart
			local g = basePart:GetAttribute("HDGroup")
			if type(g) == "string" and appliedGroups[g] and not already[basePart] then
				hide(e, basePart)
			end
		end
	end
	startGuard()
	return true
end

-- Removes HD parts added by ApplyToModel and shows the part-built groups again.
function HDMesh.RemoveFromModel(model: Model)
	local entry = appliedModels[model]
	appliedModels[model] = nil
	if entry then
		for _, c in entry.connections do
			c:Disconnect()
		end
		for _, p in entry.hidden do
			p.LocalTransparencyModifier = 0
		end
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("MeshPart") and inst:GetAttribute("HDPart") ~= nil then
			inst:Destroy()
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Gaster Blaster
-- ---------------------------------------------------------------------------------------------
-- `fix` is the part's import-orientation correction (identity for generated meshes): attachments
-- are expressed in the mesh's intended frame, so they get the inverse rotation.
local function addAttachment(parent: BasePart, name: string, position: Vector3, fix: CFrame)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = fix:Inverse() * CFrame.new(position)
	a.Parent = parent
end

-- Builds an anchored HD blaster ("Classic" | "Fell" | "Eclipse") at the origin facing -Z. (yields)
function HDMesh.CreateBlaster(style: string, scale: number?): Model?
	local s = if scale and scale > 0 then scale else 1
	local skullName, jawName = "BlasterSkull" .. style, "BlasterJaw" .. style
	local skullData, jawData = HDMesh.GetData(skullName), HDMesh.GetData(jawName)
	if skullData == nil or jawData == nil or jawData.Hinge == nil or skullData.Anchors == nil then
		return nil
	end
	local anchors = skullData.Anchors :: { [string]: Vector3 }
	local skullHinge = anchors.JawHinge
	if skullHinge == nil then
		return nil
	end
	local skull = HDMesh.Create(skullName)
	if skull == nil then
		return nil
	end
	local jaw = HDMesh.Create(jawName)
	if jaw == nil then
		skull:Destroy()
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "HDBlaster" .. style
	skull.Name = "Skull"
	jaw.Name = "Jaw"
	skull.Anchored = true
	jaw.Anchored = true
	skull.Size = skullData.Size * s
	jaw.Size = jawData.Size * s
	local skullFix, jawFix = yawFix(skull), yawFix(jaw)
	skull.CFrame = skullFix
	addAttachment(skull, "JawHinge", skullHinge * s, skullFix)
	addAttachment(jaw, "JawHinge", (jawData.Hinge :: Vector3) * s, jawFix)
	for anchorName, position in anchors do
		if anchorName ~= "JawHinge" then
			addAttachment(skull, anchorName, position * s, skullFix)
		end
	end
	skull.Parent = model
	jaw.Parent = model
	model.PrimaryPart = skull
	model:SetAttribute("HDBlaster", style)
	model:SetAttribute("Scale", s)
	HDMesh.PoseBlasterJaw(model, 0)
	return model
end

-- Places the jaw relative to the skull, opened by `angle` radians (0 = closed). Cheap; call per frame.
function HDMesh.PoseBlasterJaw(model: Model, angle: number)
	local skullInst = model:FindFirstChild("Skull")
	local jawInst = model:FindFirstChild("Jaw")
	if skullInst == nil or jawInst == nil or not skullInst:IsA("BasePart") or not jawInst:IsA("BasePart") then
		return
	end
	local skull, jaw = skullInst :: BasePart, jawInst :: BasePart
	local hingeA = skull:FindFirstChild("JawHinge")
	local hingeB = jaw:FindFirstChild("JawHinge")
	if hingeA == nil or hingeB == nil or not hingeA:IsA("Attachment") or not hingeB:IsA("Attachment") then
		return
	end
	local a, b = hingeA :: Attachment, hingeB :: Attachment
	jaw.CFrame = skull.CFrame * a.CFrame * CFrame.Angles(-angle, 0, 0) * b.CFrame:Inverse()
	model:SetAttribute("JawAngle", angle)
end

return HDMesh

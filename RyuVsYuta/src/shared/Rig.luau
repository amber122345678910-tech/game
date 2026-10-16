--!strict
-- Скелет персонажа без Humanoid и без загруженных анимаций.
-- Кости задаются смещениями от родителя; в позе покоя все кости ориентированы как модель
-- (X — вправо от персонажа, Y — вверх, -Z — вперёд, куда смотрит персонаж).
-- Детали модели привязаны к костям атрибутом "Bone"; каждый кадр мы считаем мировые CFrame
-- костей (прямая кинематика + двухзвенная IK) и двигаем детали одним вызовом BulkMoveTo.
--
-- Соглашение по углам позы (MathX.angles, градусы, порядок YXZ):
--   x > 0 — "перед кости поднимается": висящая рука/нога уходит вперёд, голова смотрит вверх, торс отклоняется назад;
--   y > 0 — поворот влево (от лица персонажа);
--   z > 0 — висящая конечность уходит вправо (+X), торс/голова наклоняются влево.

local MathX = require(script.Parent.Math)

local Rig = {}

export type BoneDef = {
	name: string,
	parent: string?,
	offset: CFrame, -- положение кости относительно родителя в позе покоя (для корня — относительно начала модели)
}

export type RigDef = {
	name: string,
	bones: { BoneDef },
	index: { [string]: number },
	parentIndex: { number }, -- 0 = нет родителя
	rest: { CFrame }, -- мировые CFrame костей в покое относительно начала модели
	lengths: { [string]: number }, -- длины (до первого ребёнка) — нужны для IK
}

-- Цель двухзвенной IK (рука или нога)
export type IKTarget = {
	upper: string, -- например "UpperArmL"
	lower: string, -- "LowerArmL"
	tip: string, -- "HandL"
	target: Vector3, -- куда поставить кончик (запястье/лодыжку), мировые координаты
	pole: Vector3, -- куда должен смотреть локоть/колено (мировая точка)
	tipRotation: CFrame?, -- мировая ориентация кисти/стопы (только поворот); nil — оставить позу
	hingeSign: number?, -- +1 для ног (колено вперёд), -1 для рук (локоть назад); по умолчанию по имени кости
}

export type Pose = { [string]: CFrame }

function Rig.define(name: string, bones: { BoneDef }): RigDef
	local index: { [string]: number } = {}
	local parentIndex: { number } = {}
	local rest: { CFrame } = {}
	for i, b in bones do
		assert(index[b.name] == nil, "Duplicate bone " .. b.name)
		index[b.name] = i
		local p = 0
		if b.parent then
			p = index[b.parent]
			assert(p ~= nil, "Bone " .. b.name .. ": parent " .. b.parent .. " must be defined earlier")
		end
		parentIndex[i] = p
		rest[i] = if p == 0 then b.offset else rest[p] * b.offset
	end
	local lengths: { [string]: number } = {}
	for i, b in bones do
		local p = parentIndex[i]
		if p ~= 0 then
			local parentName = bones[p].name
			if lengths[parentName] == nil then
				lengths[parentName] = b.offset.Position.Magnitude
			end
		end
	end
	return {
		name = name,
		bones = bones,
		index = index,
		parentIndex = parentIndex,
		rest = rest,
		lengths = lengths,
	}
end

function Rig.restOf(def: RigDef, bone: string): CFrame
	local i = def.index[bone]
	assert(i, "No bone " .. bone .. " in rig " .. def.name)
	return def.rest[i]
end

-- Поворот, переводящий единичный вектор a в единичный вектор b (кратчайший)
local function rotationBetween(a: Vector3, b: Vector3): CFrame
	local d = a:Dot(b)
	if d > 0.99999 then
		return CFrame.new()
	elseif d < -0.99999 then
		local axis = a:Cross(Vector3.new(1, 0, 0))
		if axis.Magnitude < 1e-3 then
			axis = a:Cross(Vector3.new(0, 0, 1))
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	local axis = a:Cross(b)
	return CFrame.fromAxisAngle(axis.Unit, math.acos(MathX.clamp(d, -1, 1)))
end
Rig.rotationBetween = rotationBetween

local function rotOnly(cf: CFrame): CFrame
	return cf - cf.Position
end

-- Решение двухзвенной IK. parentWorld — мировой CFrame родителя upper-кости (уже посчитан).
-- Возвращает локальные позы upper и lower (только поворот) так, чтобы кончик попал в target.
local function solveIK(def: RigDef, parentWorld: CFrame, ik: IKTarget): (CFrame, CFrame)
	local iu = def.index[ik.upper]
	local il = def.index[ik.lower]
	local it = def.index[ik.tip]
	local offU = def.bones[iu].offset
	local offL = def.bones[il].offset
	local offT = def.bones[it].offset
	local l1 = offL.Position.Magnitude
	local l2 = offT.Position.Magnitude
	-- мировая позиция плеча/бедра при нулевой позе (смещение покоя не зависит от позы этой кости)
	local upperBase = parentWorld * offU
	local s = upperBase.Position
	local toT = ik.target - s
	local dist = math.clamp(toT.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local dirT = if toT.Magnitude > 1e-6 then toT.Unit else Vector3.new(0, -1, 0)
	-- угол у плеча по теореме косинусов
	local cosA = MathX.clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
	local a = math.acos(cosA)
	-- плоскость сгиба: через полюс
	local toPole = ik.pole - s
	local planeN = dirT:Cross(toPole)
	if planeN.Magnitude < 1e-5 then
		planeN = dirT:Cross(Vector3.new(0, 0, -1))
		if planeN.Magnitude < 1e-5 then
			planeN = dirT:Cross(Vector3.new(1, 0, 0))
		end
	end
	planeN = planeN.Unit
	-- направление на локоть: dirT, повернутый на угол a к полюсу
	local perp = planeN:Cross(dirT).Unit -- в плоскости, в сторону полюса
	local elbowDir = (dirT * math.cos(a) + perp * math.sin(a)).Unit
	local elbow = s + elbowDir * l1
	local wristDir = (s + dirT * dist - elbow).Unit

	-- Upper: в покое кость (от сустава к ребёнку) направлена по offL.Position (в осях upperBase).
	local restDirU = offL.Position.Unit
	local baseRot = rotOnly(upperBase)
	local localDesiredU = baseRot:VectorToObjectSpace(elbowDir)
	-- ориентируем так, чтобы плоскость сгиба совпадала: используем "кручение" через полюс
	local swingU = rotationBetween(restDirU, localDesiredU)
	-- поправка кручения: локальная ось сгиба (X в покое) должна смотреть вдоль planeN
	local bendAxisWorld = (baseRot * swingU):VectorToWorldSpace(Vector3.new(1, 0, 0))
	local hingeSign = ik.hingeSign or (if string.find(ik.upper, "Leg") then 1 else -1)
	local desiredAxis = planeN * hingeSign
	-- проецируем на плоскость, перпендикулярную кости
	local boneW = elbowDir
	local function proj(v: Vector3): Vector3
		return v - boneW * v:Dot(boneW)
	end
	local pa, pb = proj(bendAxisWorld), proj(desiredAxis)
	local twist = CFrame.new()
	if pa.Magnitude > 1e-4 and pb.Magnitude > 1e-4 then
		pa, pb = pa.Unit, pb.Unit
		local ang = math.acos(MathX.clamp(pa:Dot(pb), -1, 1))
		if pa:Cross(pb):Dot(boneW) < 0 then
			ang = -ang
		end
		-- кручение вокруг оси кости, выраженное в локальных осях после swing
		local boneLocal = swingU:VectorToObjectSpace(localDesiredU)
		twist = CFrame.fromAxisAngle(boneLocal.Unit, ang)
	end
	local poseU = swingU * twist
	-- Lower
	local upperWorld = baseRot * poseU
	local lowerBase = upperWorld * rotOnly(offL)
	local restDirL = offT.Position.Unit
	local localDesiredL = lowerBase:VectorToObjectSpace(wristDir)
	local poseL = rotationBetween(restDirL, localDesiredL)
	return poseU, poseL
end

-- Прямая кинематика. origin — мировой CFrame начала модели (точка между стоп на земле).
-- pose[bone] — локальный CFrame (поворот и при желании сдвиг), применяемый после смещения покоя.
-- ikTargets — необязательные цели IK (переопределяют позы upper/lower и, если задан tipRotation, кончика).
-- Возвращает массив мировых CFrame в порядке def.bones.
function Rig.solve(def: RigDef, origin: CFrame, pose: Pose, ikTargets: { IKTarget }?): { CFrame }
	local world: { CFrame } = {}
	local override: { [string]: CFrame } = {}
	local ikByUpper: { [string]: IKTarget } = {}
	local tipRot: { [string]: CFrame } = {}
	if ikTargets then
		for _, ik in ikTargets do
			ikByUpper[ik.upper] = ik
			if ik.tipRotation then
				tipRot[ik.tip] = ik.tipRotation
			end
		end
	end
	for i, b in def.bones do
		local p = def.parentIndex[i]
		local parentWorld = if p == 0 then origin else world[p]
		local ik = ikByUpper[b.name]
		if ik then
			local pu, pl = solveIK(def, parentWorld, ik)
			override[ik.upper] = pu
			override[ik.lower] = pl
		end
		local tr = tipRot[b.name]
		if tr then
			local base = parentWorld * b.offset
			local extra = pose[b.name]
			local shift = if extra then extra.Position else Vector3.zero
			world[i] = CFrame.new(base.Position + rotOnly(parentWorld):VectorToWorldSpace(shift)) * rotOnly(tr)
		else
			local local_ = override[b.name] or pose[b.name]
			if local_ then
				world[i] = parentWorld * b.offset * local_
			else
				world[i] = parentWorld * b.offset
			end
		end
	end
	return world
end

function Rig.boneWorld(def: RigDef, world: { CFrame }, bone: string): CFrame
	local i = def.index[bone]
	assert(i, "No bone " .. bone)
	return world[i]
end

------------------------------------------------------------------------------------------
-- Привязка деталей к костям (одинаково в Roblox и в Lune-превизе)
------------------------------------------------------------------------------------------

export type Binding = {
	def: RigDef,
	parts: { BasePart },
	boneOf: { number }, -- индекс кости для каждой детали
	offsets: { CFrame }, -- CFrame детали относительно кости в покое
	flutter: { FlutterSpec? },
	attachments: { Attachment }, -- точки прядей волос и т. п. (двигаем локально)
	attachRest: { CFrame },
	attachWeight: { number },
	attachSeed: { number },
}

export type FlutterSpec = {
	amp: number, -- амплитуда, градусы
	freq: number, -- Гц
	hinge: Vector3, -- точка шарнира в осях детали
	axis: Vector3, -- ось колебания в осях детали
	seed: number,
}

-- origin — CFrame начала модели при сборке (совпадает с деталью "Root" модели).
function Rig.bind(def: RigDef, model: Instance, origin: CFrame): Binding
	local parts: { BasePart } = {}
	local boneOf: { number } = {}
	local offsets: { CFrame } = {}
	local flutter: { FlutterSpec? } = {}
	local attachments: { Attachment } = {}
	local attachRest: { CFrame } = {}
	local attachWeight: { number } = {}
	local attachSeed: { number } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local boneName = d:GetAttribute("Bone")
			if type(boneName) == "string" then
				local bi = def.index[boneName]
				assert(bi, "Part " .. d:GetFullName() .. " bound to unknown bone " .. boneName)
				table.insert(parts, d)
				table.insert(boneOf, bi)
				table.insert(offsets, (origin * def.rest[bi]):Inverse() * d.CFrame)
				local amp = d:GetAttribute("FlutterAmp")
				if type(amp) == "number" and amp ~= 0 then
					local freq = d:GetAttribute("FlutterFreq")
					local hinge = d:GetAttribute("FlutterHinge")
					local axis = d:GetAttribute("FlutterAxis")
					flutter[#parts] = {
						amp = amp,
						freq = if type(freq) == "number" then freq else 1.5,
						hinge = if typeof(hinge) == "Vector3" then hinge else Vector3.new(0, d.Size.Y / 2, 0),
						axis = if typeof(axis) == "Vector3" then axis else Vector3.new(1, 0, 0),
						seed = #parts * 0.731,
					}
				end
			end
		elseif d:IsA("Attachment") then
			local w = d:GetAttribute("Weight")
			if type(w) == "number" then
				table.insert(attachments, d)
				table.insert(attachRest, d.CFrame)
				table.insert(attachWeight, w)
				local seed = d:GetAttribute("Seed")
				table.insert(attachSeed, if type(seed) == "number" then seed else #attachments * 0.37)
			end
		end
	end
	return {
		def = def,
		parts = parts,
		boneOf = boneOf,
		offsets = offsets,
		flutter = flutter,
		attachments = attachments,
		attachRest = attachRest,
		attachWeight = attachWeight,
		attachSeed = attachSeed,
	}
end

-- Порыв/трепет ткани и меха: поворот детали вокруг шарнира по шуму (без состояния — зависит только от t)
function Rig.flutterOffset(spec: FlutterSpec, t: number, strength: number): CFrame
	local n = MathX.fbm(t * spec.freq, spec.seed, 2)
	local ang = math.rad(spec.amp * strength * n)
	local hinge = CFrame.new(spec.hinge)
	return hinge * CFrame.fromAxisAngle(spec.axis.Unit, ang) * hinge:Inverse()
end

-- Мировые CFrame всех деталей для данного решения скелета.
function Rig.partCFrames(binding: Binding, world: { CFrame }, t: number, flutterStrength: number): { CFrame }
	local out: { CFrame } = {}
	for i = 1, #binding.parts do
		local cf = world[binding.boneOf[i]] * binding.offsets[i]
		local fl = binding.flutter[i]
		if fl and flutterStrength > 0 then
			cf = cf * Rig.flutterOffset(fl, t, flutterStrength)
		end
		out[i] = cf
	end
	return out
end

return Rig

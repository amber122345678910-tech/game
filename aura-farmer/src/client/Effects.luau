--!strict
-- Эффекты планов (клиент). shot.effects = список событий; все «твины» считаются от времени ролика,
-- поэтому перемотка/пауза дают ту же картинку.
--
--   { t = 1.9, kind = "emit", name = "BuckleSparkle", count = 30 }           -- ParticleEmitter:Emit (при проходе t)
--   { t = 5.0, stop = 5.8, kind = "enable", name = "ChainSparkles", on = true } -- Enabled у эмиттера/света/луча (stop необязателен)
--   { t = 1.8, dur = 0.4, kind = "tween", name = "Glint", prop = "Transparency", from = 1, to = 0, ease = "out" }
--   { t = 9.53, dur = 0.25, kind = "flash", color = Color3.new(1,1,1), from = 0.3, to = 1 }  -- вспышка экрана (прозрачность)
-- name ищется среди потомков папки плана (риги) и декорации плана (первое совпадение).

local Easing = require(game:GetService("ReplicatedStorage"):WaitForChild("AuraFarmer"):WaitForChild("Anim"):WaitForChild("Easing"))

local Effects = {}

type Ctx = {
	shotFolder: Instance?,
	setModel: Instance?,
	flash: Frame,
}

local cache: { [string]: Instance } = {}
local baseValues: { [Instance]: { [string]: any } } = {}

local function find(ctx: Ctx, name: string): Instance?
	local key = (ctx.shotFolder and ctx.shotFolder.Name or "") .. "|" .. name
	local hit = cache[key]
	if hit and hit.Parent then
		return hit
	end
	for _, root in { ctx.shotFolder, ctx.setModel } do
		if root then
			local found = root:FindFirstChild(name, true)
			if found then
				cache[key] = found
				return found
			end
		end
	end
	return nil
end

local function lerpValue(a: any, b: any, e: number): any
	local ta = typeof(a)
	if ta == "number" then
		return a + (b - a) * e
	elseif ta == "Color3" or ta == "Vector3" or ta == "CFrame" or ta == "UDim2" then
		return a:Lerp(b, e)
	end
	return if e >= 1 then b else a
end

-- Вход в план: вернуть свойства, которые меняли твины, и выключить «enable»-эффекты плана.
function Effects.enter(shot: any, ctx: Ctx)
	for inst, props in baseValues do
		for prop, value in props do
			pcall(function()
				(inst :: any)[prop] = value
			end)
		end
	end
	table.clear(baseValues)
	for _, ev in shot.effects or {} do
		if ev.kind == "enable" or ev.kind == "tween" then
			local inst = find(ctx, ev.name)
			if inst then
				baseValues[inst] = baseValues[inst] or {}
				local prop = if ev.kind == "enable" then "Enabled" else ev.prop
				if baseValues[inst][prop] == nil then
					local ok, value = pcall(function()
						return (inst :: any)[prop]
					end)
					if ok then
						baseValues[inst][prop] = value
					end
				end
			end
		end
	end
end

-- Кадр: prevT — время прошлого кадра (для одноразовых событий), t — текущее.
function Effects.update(shot: any, t: number, prevT: number, ctx: Ctx)
	local flashA = 1
	for _, ev in shot.effects or {} do
		local kind = ev.kind
		if kind == "emit" then
			if prevT < ev.t and t >= ev.t and t - ev.t < 0.25 then
				local inst = find(ctx, ev.name)
				if inst and inst:IsA("ParticleEmitter") then
					inst:Emit(ev.count or 10)
				end
			end
		elseif kind == "enable" then
			local inst = find(ctx, ev.name)
			if inst then
				local on = t >= ev.t and (ev.stop == nil or t < ev.stop)
				local want = if on then (ev.on ~= false) else not (ev.on ~= false)
				if (inst :: any).Enabled ~= want then
					(inst :: any).Enabled = want
				end
			end
		elseif kind == "tween" then
			if t >= ev.t then
				local inst = find(ctx, ev.name)
				if inst then
					local dur = math.max(ev.dur or 0.001, 0.001)
					local e = Easing.named(ev.ease or "linear", math.clamp((t - ev.t) / dur, 0, 1))
					local from = ev.from
					if from == nil then
						from = (baseValues[inst] or {})[ev.prop]
					end
					if from ~= nil then
						pcall(function()
							(inst :: any)[ev.prop] = lerpValue(from, ev.to, e)
						end)
					end
				end
			end
		elseif kind == "flash" then
			if t >= ev.t and t <= ev.t + (ev.dur or 0.2) then
				local e = Easing.named(ev.ease or "out", (t - ev.t) / (ev.dur or 0.2))
				flashA = math.min(flashA, (ev.from or 0) + ((ev.to or 1) - (ev.from or 0)) * e)
				ctx.flash.BackgroundColor3 = ev.color or Color3.new(1, 1, 1)
			end
		end
	end
	ctx.flash.BackgroundTransparency = flashA
	ctx.flash.Visible = flashA < 1
end

return Effects
